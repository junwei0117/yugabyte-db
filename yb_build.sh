#!/usr/bin/env bash
set -euo pipefail

script_name=${0##*/}
script_name=${script_name%.*}

. "${BASH_SOURCE%/*}"/build-support/common-test-env.sh

show_help() {
  cat >&2 <<-EOT
Usage: ${0##*/} [<options>] [<build_type>]
Options:
  -h, --help
    Show help.
  --verbose
    Show debug output from CMake.
  --force-run-cmake, --frcm
    Ensure that we explicitly invoke CMake from this script. CMake may still run as a result of
    changes made to CMakeLists.txt files if we just invoke make on the CMake-generated Makefile.
  --force-no-run-cmake, --fnrcm
    The opposite of --force-run-cmake. Makes sure we do not run CMake.
  --clean
    Remove the build directory before building.
  --clean-thirdparty
    Remove previously built third-party dependencies and rebuild them. Does not imply --clean.
  --rocksdb-only
    Only build RocksDB code (all targets).
  --no-ccache
    Do not use ccache. Useful when debugging build scripts or compiler/linker options.
  --clang
    Use the clang C/C++ compiler.
  --skip-java-build, --skip-java, --sjb, --sj
    Do not package and install java source code.
  --run-java-tests
    Run the java unit tests when build is enabled.
  --static
    Force a static build.
  --target, --targets
    Pass the given target or set of targets to make.
  --cxx-test <test_name>
    Build and run the given C++ test. We run the test using ctest.
  --no-tcmalloc
    Do not use tcmalloc.
  --no-rebuild-thirdparty, --nbtp, --nb3p, --nrtp, --nr3p
    Skip building third-party libraries, even if the thirdparty directory has changed in git.
  --no-prebuilt-thirdparty
    Don't download prebuilt third-party libraries, build them locally instead.
  --show-compiler-cmd-line, --sccl
    Show compiler command line.
  --{no,skip}-{test-existence-check,check-test-existence}
    Don't check that all test binaries referenced by CMakeLists.txt files exist.
  --gtest_filter
    Use the given filter to select Google Test tests to run. Uses with --cxx-test.
  --test-args
    Extra arguments to pass to the test. Used with --cxx-test.
  --rebuild-file <source_file_to_rebuild>
    The .o file corresponding to the given source file will be deleted from the build directory
    before the build.
  --rebuild-file <target_name>
    Combines --target and --rebuild-file. Currently only works if target name matches the object
    file name to be deleted (e.g. this won't work for RocksDB tests, whose target names start with
    rocksdb_).
  --generate-build-debug-scripts, --gen-build-debug-scripts, --gbds
    Specify this to generate one-off shell scripts that could be used to re-run and understand
    failed compilation commands.
  --ctest
    Runs ctest in the build directory after the build. This is mutually exclusive with --cxx-test.
    This will also skip building Java code, unless --run-java-tests is specified.
  --ctest-args
    Specifies additional arguments to ctest. Implies --ctest.
  --skip-cxx-build, --scb
    Skip C++ build. This is useful when repeatedly debugging tests using this tool and not making
    any changes to the code.
  --num-repetitions, --num-reps, -n
    Repeat a C++ test this number of times. This delegates to the repeat_unit_test.sh script.
  --write-build-descriptor <build_descriptor_path>
    Write a "build descriptor" file. A "build descriptor" is a YAML file that provides information
    about the build root, compiler used, etc.
  --force, -f, -y
    Run a clean build without asking for confirmation even if a clean build was recently done.
  --with-assembly
    Build the java code with assembly (basically builds the yb-sample-apps.jar as well)
  --
    Pass all arguments after -- to repeat_unit_test.

Build types:
  debug (default), fastdebug, release, profile_gen, profile_build, asan, tsan
EOT
}

setup_vars_for_cxx_test() {
  expect_num_args 1 "$@"
  if [[ $cxx_test_name == $1 ]]; then
    # Duplicate test name specified, ignore.
    return
  fi
  if [[ -n $cxx_test_name ]]; then
    fatal "Only one C++ test name can be specified (found '$cxx_test_name' and '$1')."
  fi
  cxx_test_name=$1
  test_binary_name=${cxx_test_name#*_}
  make_targets+=( $test_binary_name )
  build_java=false

  # This is necessary to avoid failures if we are just building one test.
  test_existence_check=false
}

# -------------------------------------------------------------------------------------------------
# Command line parsing

build_type="debug"
build_type_specified=false
verbose=false
force_run_cmake=false
force_no_run_cmake=false
clean_before_build=false
clean_thirdparty=false
rocksdb_only=false
rocksdb_targets=""
no_ccache=false
make_opts=()
force=false
build_cxx=true
build_java=true
run_java_tests=false
save_log=false
make_targets=()
no_tcmalloc=false
cxx_test_name=""
test_existence_check=true
object_files_to_delete=()
run_ctest=false
ctest_args=""
num_test_repetitions=1
build_descriptor_path=""
export YB_GTEST_FILTER=""
repeat_unit_test_inherited_args=()
forward_args_to_repeat_unit_test=false
original_args=( "$@" )
java_with_assembly=false

export YB_EXTRA_GTEST_FLAGS=""

while [ $# -gt 0 ]; do
  if is_valid_build_type "$1"; then
    build_type="$1"
    build_type_specified=true
    shift
    continue
  fi
  if "$forward_args_to_repeat_unit_test"; then
    repeat_unit_test_inherited_args+=( "$1" )
    shift
    continue
  fi

  case "$1" in
    -h|--help)
      show_help >&2
      exit 1
    ;;
    --verbose)
      verbose=true
    ;;
    --force-run-cmake|--frcm)
      force_run_cmake=true
    ;;
    --force-no-run-cmake|--fnrcm)
      force_no_run_cmake=true
    ;;
    --clean)
      clean_before_build=true
    ;;
    --clean-thirdparty)
      clean_thirdparty=true
    ;;
    -f|--force|-y)
      force=true
    ;;
    --rocksdb-only)
      rocksdb_only=true
    ;;
    --no-ccache)
      no_ccache=true
    ;;
    --gcc)
      YB_COMPILER_TYPE="gcc"
    ;;
    --clang)
      YB_COMPILER_TYPE="clang"
    ;;
    --skip-java-build|--skip-java|--sjb|--sj)
      build_java=false
    ;;
    --run-java-tests)
      run_java_tests=true
    ;;
    --with-assembly)
      java_with_assembly=true
    ;;
    --static)
      YB_LINK=static
    ;;
    --save-log)
      save_log=true
    ;;
    --target)
      make_targets+=( "$2" )
      shift
    ;;
    --targets)
      make_targets+=( $2 )
      shift
    ;;
    --no-tcmalloc)
      no_tcmalloc=true
    ;;
    --cxx-test|--ct)
      setup_vars_for_cxx_test "$2"
      shift
    ;;
    --ctest)
      run_ctest=true
    ;;
    --ctest-args)
      run_ctest=true
      ctest_args+="$2"
      shift
    ;;
    --no-rebuild-thirdparty|--nrtp|--nr3p|--nbtp|--nb3p)
      export NO_REBUILD_THIRDPARTY=1
    ;;
    --no-prebuilt-thirdparty)
      export YB_NO_DOWNLOAD_PREBUILT_THIRDPARTY=1
    ;;
    --show-compiler-cmd-line|--sccl)
      export YB_SHOW_COMPILER_COMMAND_LINE=1
    ;;
    --skip-test-existence-check|--no-test-existence-check) test_existence_check=false ;;
    --skip-check-test-existence|--no-check-test-existence) test_existence_check=false ;;
    --gtest_filter)
      export YB_GTEST_FILTER=$2
      shift
    ;;
    --rebuild-file)
      object_files_to_delete+=( "$2.o" "$2.cc.o" )
      shift
    ;;
    --test-args)
      export YB_EXTRA_GTEST_FLAGS+=" $2"
      shift
    ;;
    --rebuild-target)
      object_files_to_delete+=( "$2.o" "$2.cc.o" )
      make_targets=( "$2" )
      shift
    ;;
    --generate-build-debug-scripts|--gen-build-debug-scripts|--gbds)
      export YB_GENERATE_BUILD_DEBUG_SCRIPTS=1
    ;;
    --skip-cxx-build|--scb)
      build_cxx=false
    ;;
    --num-repetitions|--num-reps|-n)
      num_test_repetitions=$2
      shift
      if [[ ! $num_test_repetitions =~ ^[0-9]+$ ]]; then
        fatal "Invalid number of test repetitions: $num_test_repetitions"
      fi
    ;;
    --write-build-descriptor)
      build_descriptor_path=$2
      shift
    ;;
    --)
      if [[ $num_test_repetitions -lt 2 ]]; then
        fatal "Forward to arguments to repeat_unit_test.sh without multiple repetitions"
      fi
      forward_args_to_repeat_unit_test=true
    ;;
    [a-z]*test)
      log "'$1' looks like a C++ test name, assuming --cxx-test"
      setup_vars_for_cxx_test "$1"
    ;;
    yb-master)
      make_targets+=( "yb-master" )
    ;;
    yb-tserver)
      make_targets+=( "yb-tserver" )
    ;;
    daemons)
      make_targets+=( "yb-master" "yb-tserver" )
    ;;
    *)
      echo "Invalid option: '$1'" >&2
      exit 1
  esac
  shift
done

unset cmake_opts
set_cmake_build_type_and_compiler_type
log "YB_COMPILER_TYPE=$YB_COMPILER_TYPE"

if "$verbose"; then
  log "build_type=$build_type, cmake_build_type=$cmake_build_type"
fi

if "$force_run_cmake" && "$force_no_run_cmake"; then
  fatal "--force-run-cmake and --force-no-run-cmake are incompatible"
fi

if "$run_ctest"; then
  if [[ -n $cxx_test_name ]]; then
    fatal "--cxx-test (run one C++ test) is mutually exclusive with --ctest (run a number of tests)"
  fi
  if ! "$run_java_tests"; then
    build_java=false
  fi
fi

if [[ $num_test_repetitions -lt 1 ]]; then
  fatal "Invalid number of test repetitions: $num_test_repetitions. Must be 1 or more."
fi

if "$save_log"; then
  log_dir="$HOME/logs"
  mkdir_safe "$log_dir"
  log_name_prefix="$log_dir/${script_name}_${build_type}"
  log_path="${log_name_prefix}_$( date +%Y-%m-%d_%H_%M_%S ).log"
  latest_log_symlink_path="${log_name_prefix}_latest.log"
  rm -f "$latest_log_symlink_path"
  ln -s "$log_path" "$latest_log_symlink_path"

  echo "Logging to $log_path (also symlinked to $latest_log_symlink_path)" >&2
  filtered_args=()
  for arg in "${original_args[@]}"; do
    if [[ "$arg" != "--save-log" ]]; then
      filtered_args+=( "$arg" )
    fi
  done

  set +eu
  ( set -x; "$0" "${filtered_args[@]}" ) 2>&1 | tee "$log_path"
  exit_code=$?
  echo "Log saved to $log_path (also symlinked to $latest_log_symlink_path)" >&2
  exit "$exit_code"
fi

if "$verbose"; then
  log "$script_name command line: ${original_args[@]}"
fi

set_build_root

validate_cmake_build_type "$cmake_build_type"

export YB_COMPILER_TYPE

if "$verbose"; then
  # http://stackoverflow.com/questions/22803607/debugging-cmakelists-txt
  cmake_opts+=( -Wdev --debug-output --trace -DYB_VERBOSE=1 )
  make_opts+=( VERBOSE=1 SH="bash -x" )
  export YB_SHOW_COMPILER_COMMAND_LINE=1
fi

# If we are running in an interactive session, check if a clean build was done less than an hour
# ago. In that case, make sure this is what the user really wants.
if tty -s && ( $clean_before_build || $clean_thirdparty ); then
  build_root_basename=${BUILD_ROOT##*/}
  last_clean_timestamp_path="$YB_SRC_ROOT/build/last_clean_timestamp__$build_root_basename"
  current_timestamp_sec=$( date +%s )
  if [ -f "$last_clean_timestamp_path" ]; then
    last_clean_timestamp_sec=$( cat "$last_clean_timestamp_path" )
    last_build_time_sec_ago=$(( $current_timestamp_sec - $last_clean_timestamp_sec ))
    if [[ "$last_build_time_sec_ago" -lt 3600 ]] && ! "$force"; then
      log "Last clean build on $build_root_basename was performed less than an hour" \
          "($last_build_time_sec_ago sec) ago."
      log "Do you still want to do a clean build? [y/N]"
      read answer
      if [[ ! "$answer" =~ ^[yY]$ ]]; then
        fatal "Operation canceled"
      fi
    fi
  fi
  mkdir -p "$YB_SRC_ROOT/build"
  echo "$current_timestamp_sec" >"$last_clean_timestamp_path"
fi

if "$clean_before_build"; then
  log "Removing '$BUILD_ROOT' (--clean specified)"
  ( set -x; rm -rf "$BUILD_ROOT" )
fi

mkdir_safe "$BUILD_ROOT"
mkdir_safe "thirdparty/installed/uninstrumented/include"
mkdir_safe "thirdparty/installed-deps/include"

cd "$BUILD_ROOT"

if "$clean_thirdparty"; then
  log "Removing and re-building third-party dependencies (--clean-thirdparty specified)"
  (
    set -x
    "$YB_THIRDPARTY_DIR"/clean_thirdparty.sh --all
  )
fi

if "$no_ccache"; then
  export YB_NO_CCACHE=1
fi

if "$no_tcmalloc"; then
  cmake_opts+=( -DYB_TCMALLOC_AVAILABLE=0 )
fi

detect_num_cpus

set_build_env_vars

if "$build_cxx"; then
  if ( "$force_run_cmake" || [[ ! -f Makefile ]] ) && \
     ! "$force_no_run_cmake"; then
    if [[ -z ${NO_REBUILD_THIRDPARTY:-} ]]; then
      build_compiler_if_necessary
    fi
    log "Using cmake binary: $( which cmake )"
    log "Running cmake in $PWD"
    ( set -x; cmake "${cmake_opts[@]}" "$YB_SRC_ROOT" )
  fi

  if "$rocksdb_only"; then
    make_opts+=( build_rocksdb_all_targets )
  fi

  if [[ "${#object_files_to_delete[@]}" -gt 0 ]]; then
    log_empty_line
    log "Deleting object files corresponding to: ${object_files_to_delete[@]}"
    # TODO: can delete multiple files using the same find command.
    for object_file_to_delete in "${object_files_to_delete[@]}"; do
      ( set -x; find "$BUILD_ROOT" -name "$object_file_to_delete" -exec rm -fv {} \; )
    done
    log_empty_line
  fi

  log "Running make in $PWD"
  set +u +e  # "set -u" may cause failures on empty lists
  time (
    set -x
    make -j"$YB_NUM_CPUS" "${make_opts[@]}" "${make_targets[@]}"
  )

  exit_code=$?
  set -u -e
  log "Non-java build finished with exit code $exit_code" \
      "(build type: $build_type, compiler: $YB_COMPILER_TYPE)." \
      "Timing information is available above."
  if [ "$exit_code" -ne 0 ]; then
    exit "$exit_code"
  fi

  if "$test_existence_check"; then
    (
      cd "$BUILD_ROOT"
      log "Checking if all test binaries referenced by CMakeLists.txt files exist."
      set +e
      YB_CHECK_TEST_EXISTENCE_ONLY=1 ctest -j8 2>&1 | grep Failed
      if [[ "${PIPESTATUS[0]}" -ne 0 ]]; then
        fatal "Some test binaries referenced in CMakeLists.txt files do not exist"
      fi
    )
  fi
fi

if [[ -n $cxx_test_name ]]; then
  if [[ $num_test_repetitions -eq 1 ]]; then
    (
      set_asan_tsan_options
      cd "$BUILD_ROOT"

      # The following makes our test framework repeat the test log in stdout in addition writing the
      # log file instead of simply redirecting it to the log file. Combined with the --verbose ctest
      # option, this gives us nice real-time test output, while still taking advantage of correct
      # test flags such (e.g. ASAN/TSAN options and suppression rules) that are set in run-test.sh.
      export YB_CTEST_VERBOSE=1

      # --verbose: enable verbose output from tests.  Test output is normally suppressed and only
      # summary information is displayed.  This option will show all test output.
      # --output-on-failure is unnecessary when --verbose is specified. In fact, adding
      # --output-on-failure will result in duplicate output in case of a failure.
      set -x
      ctest --verbose -R ^"$cxx_test_name"$
    )
  else
    (
      export YB_COMPILER_TYPE
      set +u
      repeat_unit_test_extra_args=( "${repeat_unit_test_inherited_args[@]}" )
      set -u
      if "$verbose"; then
        repeat_unit_test_extra_args+=( --verbose )
      fi
      set -x +u
      "$YB_SRC_ROOT"/bin/repeat_unit_test.sh "$build_type" "$test_binary_name" \
         --num-iter "$num_test_repetitions" "${repeat_unit_test_extra_args[@]}"
      set -u
    )
  fi
fi

if "$run_ctest"; then
  # Not setting YB_CTEST_VERBOSE here because we don't want the output of a potentially large number
  # of tests to go to stdout.
  (
    cd "$BUILD_ROOT"
    set -x
    ctest -j"$YB_NUM_CPUS" --verbose $ctest_args 2>&1 |
      egrep -v "^[0-9]+: Test timeout computed to be: "
  )
fi

# Check if the Java build is needed. And skip Java unit test runs if requested.
if "$build_java"; then
  cd "$YB_SRC_ROOT"/java
  build_opts=( install )
  if ! "$java_with_assembly"; then
    build_opts+=( -DskipAssembly )
  fi
  if ! "$run_java_tests"; then
    build_opts+=( -DskipTests )
  fi
  time ( build_yb_java_code ${build_opts[@]} )
  log "Java build finished, total time information above."
fi

if [[ -n $build_descriptor_path ]]; then
  # The format of this file is YAML.
  cat >"$build_descriptor_path" <<-EOT
build_type: "$build_type"
cmake_build_type: "$cmake_build_type"
build_root: "$BUILD_ROOT"
compiler_type: "$YB_COMPILER_TYPE"
EOT
  log "Created a build descriptor file at '$build_descriptor_path'"
fi
