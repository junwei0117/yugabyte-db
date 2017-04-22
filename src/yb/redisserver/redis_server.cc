// Copyright (c) YugaByte, Inc.

#include "yb/redisserver/redis_server.h"

#include "yb/util/flag_tags.h"
#include "yb/gutil/strings/substitute.h"
#include "yb/redisserver/redis_service.h"

using yb::rpc::ServiceIf;

DEFINE_int32(redis_svc_num_threads, 10,
             "Number of RPC worker threads for the redis service");
TAG_FLAG(redis_svc_num_threads, advanced);

DEFINE_int32(redis_svc_queue_length, 50,
             "RPC queue length for redis service");
TAG_FLAG(redis_svc_queue_length, advanced);

namespace yb {
namespace redisserver {

RedisServer::RedisServer(const RedisServerOptions& opts)
    : RpcAndWebServerBase("RedisServer", opts, "yb.redisserver"), opts_(opts) {}

Status RedisServer::Start() {
  RETURN_NOT_OK(server::RpcAndWebServerBase::Init());

  gscoped_ptr<ServiceIf> redis_service(new RedisServiceImpl(this, opts_.master_addresses_flag));
  RETURN_NOT_OK(RegisterService(FLAGS_redis_svc_queue_length, redis_service.Pass()));

  RETURN_NOT_OK(server::RpcAndWebServerBase::Start());

  return Status::OK();
}

}  // namespace redisserver
}  // namespace yb
