-- Regression tests for UPDATE/DELETE single row operations.

--
-- Test that single-row UPDATE/DELETEs bypass scan.
--
CREATE TABLE single_row (k int primary key, v1 int, v2 int);

-- Below statements should all USE single-row.
EXPLAIN (COSTS FALSE) DELETE FROM single_row WHERE k = 1;
EXPLAIN (COSTS FALSE) DELETE FROM single_row WHERE k = 1 RETURNING k;
EXPLAIN (COSTS FALSE) DELETE FROM single_row WHERE k IN (1);
-- Below statements should all NOT USE single-row.
EXPLAIN (COSTS FALSE) DELETE FROM single_row;
EXPLAIN (COSTS FALSE) DELETE FROM single_row WHERE k = 1 and v1 = 1;
EXPLAIN (COSTS FALSE) DELETE FROM single_row WHERE v1 = 1 and v2 = 1;
EXPLAIN (COSTS FALSE) DELETE FROM single_row WHERE k = 1 RETURNING v1;
EXPLAIN (COSTS FALSE) DELETE FROM single_row WHERE k > 1;
EXPLAIN (COSTS FALSE) DELETE FROM single_row WHERE k != 1;
EXPLAIN (COSTS FALSE) DELETE FROM single_row WHERE k IN (1, 2);

-- Below statements should all USE single-row.
EXPLAIN (COSTS FALSE) UPDATE single_row SET v1 = 1 WHERE k = 1;
EXPLAIN (COSTS FALSE) UPDATE single_row SET v1 = 1 WHERE k = 1 RETURNING k, v1;
EXPLAIN (COSTS FALSE) UPDATE single_row SET v1 = 1, v2 = 1 + 2 WHERE k = 1;
EXPLAIN (COSTS FALSE) UPDATE single_row SET v1 = 1, v2 = 2 WHERE k = 1 RETURNING k, v1, v2;
EXPLAIN (COSTS FALSE) UPDATE single_row SET v1 = 1, v2 = 2 WHERE k = 1 RETURNING *;
EXPLAIN (COSTS FALSE) UPDATE single_row SET v1 = 1 WHERE k IN (1);
EXPLAIN (COSTS FALSE) UPDATE single_row SET v1 = 3 + 2 WHERE k = 1;
EXPLAIN (COSTS FALSE) UPDATE single_row SET v1 = power(2, 3 - 1) WHERE k = 1;
EXPLAIN (COSTS FALSE) UPDATE single_row SET v1 = v1 + 3 WHERE k = 1;
EXPLAIN (COSTS FALSE) UPDATE single_row SET v1 = v1 * 2 WHERE k = 1;

-- Below statements should all NOT USE single-row.
EXPLAIN (COSTS FALSE) UPDATE single_row SET v1 = 1;
EXPLAIN (COSTS FALSE) UPDATE single_row SET v1 = v1 + v2 WHERE k = 1;
EXPLAIN (COSTS FALSE) UPDATE single_row SET v1 = v2 + 1 WHERE k = 1;
EXPLAIN (COSTS FALSE) UPDATE single_row SET v1 = 1, v2 = v1 + v2 WHERE k = 1;
EXPLAIN (COSTS FALSE) UPDATE single_row SET v1 = v2 + 1, v2 = 1 WHERE k = 1;
EXPLAIN (COSTS FALSE) UPDATE single_row SET v1 = 1 WHERE k = 1 and v2 = 1;
EXPLAIN (COSTS FALSE) UPDATE single_row SET v1 = 1 WHERE k = 1 RETURNING v2;
EXPLAIN (COSTS FALSE) UPDATE single_row SET v1 = 1 WHERE k = 1 RETURNING *;
EXPLAIN (COSTS FALSE) UPDATE single_row SET v1 = 1 WHERE k > 1;
EXPLAIN (COSTS FALSE) UPDATE single_row SET v1 = 1 WHERE k != 1;
EXPLAIN (COSTS FALSE) UPDATE single_row SET v1 = 1 WHERE k IN (1, 2);
EXPLAIN (COSTS FALSE) UPDATE single_row SET v1 = power(2, 3 - k) WHERE k = 1;
EXPLAIN (COSTS FALSE) UPDATE single_row SET v1 = 1 WHERE k % 2 = 0;

--
-- Test single-row UPDATE/DELETE execution.
--
INSERT INTO single_row VALUES (1, 1, 1);

UPDATE single_row SET v1 = 2 WHERE k = 1;
SELECT * FROM single_row;

UPDATE single_row SET v1 = v1 * 2 WHERE k = 1;
SELECT * FROM single_row;

DELETE FROM single_row WHERE k = 1;
SELECT * FROM single_row;

--
-- Test UPDATE/DELETEs of non-existent data return no rows.
--
UPDATE single_row SET v1 = 1 WHERE k = 100 RETURNING k;
DELETE FROM single_row WHERE k = 100 RETURNING k;
SELECT * FROM single_row;

--
-- Test prepared statements.
--
INSERT INTO single_row VALUES (1, 1, 1);

PREPARE single_row_update (int, int, int) AS
  UPDATE single_row SET v1 = $2, v2 = $3 WHERE k = $1;

PREPARE single_row_delete (int) AS
  DELETE FROM single_row WHERE k = $1;

EXPLAIN (COSTS FALSE) EXECUTE single_row_update (1, 2, 2);
EXECUTE single_row_update (1, 2, 2);
SELECT * FROM single_row;

EXPLAIN (COSTS FALSE) EXECUTE single_row_delete (1);
EXECUTE single_row_delete (1);
SELECT * FROM single_row;

--
-- Test returning clauses.
--
INSERT INTO single_row VALUES (1, 1, 1);

UPDATE single_row SET v1 = 2, v2 = 2 WHERE k = 1 RETURNING v1, v2, k;
SELECT * FROM single_row;

UPDATE single_row SET v1 = 3, v2 = 3 WHERE k = 1 RETURNING *;
SELECT * FROM single_row;

DELETE FROM single_row WHERE k = 1 RETURNING k;
SELECT * FROM single_row;

---
--- Test in transaction block.
---
INSERT INTO single_row VALUES (1, 1, 1);

BEGIN;
EXPLAIN (COSTS FALSE) DELETE FROM single_row WHERE k = 1;
DELETE FROM single_row WHERE k = 1;
END;

SELECT * FROM single_row;

-- Test UPDATE/DELETE of non-existing rows.
BEGIN;
DELETE FROM single_row WHERE k = 1;
UPDATE single_row SET v1 = 2 WHERE k = 1;
END;

SELECT * FROM single_row;

---
--- Test WITH clause.
---
INSERT INTO single_row VALUES (1, 1, 1);

EXPLAIN (COSTS FALSE) WITH temp AS (UPDATE single_row SET v1 = 2 WHERE k = 1)
  UPDATE single_row SET v1 = 2 WHERE k = 1;

WITH temp AS (UPDATE single_row SET v1 = 2 WHERE k = 1)
  UPDATE single_row SET v1 = 2 WHERE k = 1;

SELECT * FROM single_row;

-- Update row that doesn't exist.
WITH temp AS (UPDATE single_row SET v1 = 2 WHERE k = 2)
  UPDATE single_row SET v1 = 2 WHERE k = 2;

SELECT * FROM single_row;

-- Adding secondary index should force re-planning, which would
-- then not choose single-row plan due to the secondary index.
EXPLAIN (COSTS FALSE) EXECUTE single_row_delete (1);
CREATE INDEX single_row_index ON single_row (v1);
EXPLAIN (COSTS FALSE) EXECUTE single_row_delete (1);
DROP INDEX single_row_index;

-- Same as above but for UPDATE.
EXPLAIN (COSTS FALSE) EXECUTE single_row_update (1, 1, 1);
CREATE INDEX single_row_index ON single_row (v1);
EXPLAIN (COSTS FALSE) EXECUTE single_row_update (1, 1, 1);
DROP INDEX single_row_index;

-- Adding BEFORE DELETE row triggers should do the same as secondary index.
EXPLAIN (COSTS FALSE) EXECUTE single_row_delete (1);
CREATE TRIGGER single_row_delete_trigger BEFORE DELETE ON single_row
  FOR EACH ROW EXECUTE PROCEDURE suppress_redundant_updates_trigger();
EXPLAIN (COSTS FALSE) EXECUTE single_row_delete (1);
-- UPDATE should still use single-row since trigger does not apply to it.
EXPLAIN (COSTS FALSE) EXECUTE single_row_update (1, 1, 1);
DROP TRIGGER single_row_delete_trigger ON single_row;

-- Adding BEFORE UPDATE row triggers should do the same as secondary index.
EXPLAIN (COSTS FALSE) EXECUTE single_row_update (1, 1, 1);
CREATE TRIGGER single_row_update_trigger BEFORE UPDATE ON single_row
  FOR EACH ROW EXECUTE PROCEDURE suppress_redundant_updates_trigger();
EXPLAIN (COSTS FALSE) EXECUTE single_row_update (1, 1, 1);
-- DELETE should still use single-row since trigger does not apply to it.
EXPLAIN (COSTS FALSE) EXECUTE single_row_delete (1);
DROP TRIGGER single_row_update_trigger ON single_row;

--
-- Test table with composite primary key.
--
CREATE TABLE single_row_comp_key (v int, k1 int, k2 int, PRIMARY KEY (k1 HASH, k2 ASC));

-- Below statements should all USE single-row.
EXPLAIN (COSTS FALSE) DELETE FROM single_row_comp_key WHERE k1 = 1 and k2 = 1;
EXPLAIN (COSTS FALSE) DELETE FROM single_row_comp_key WHERE k1 = 1 and k2 = 1 RETURNING k1, k2;

-- Below statements should all NOT USE single-row.
EXPLAIN (COSTS FALSE) DELETE FROM single_row_comp_key;
EXPLAIN (COSTS FALSE) DELETE FROM single_row_comp_key WHERE k1 = 1;
EXPLAIN (COSTS FALSE) DELETE FROM single_row_comp_key WHERE k2 = 1;
EXPLAIN (COSTS FALSE) DELETE FROM single_row_comp_key WHERE v = 1 and k1 = 1 and k2 = 1;
EXPLAIN (COSTS FALSE) DELETE FROM single_row_comp_key WHERE k1 = 1 and k2 = 1 RETURNING v;
EXPLAIN (COSTS FALSE) DELETE FROM single_row_comp_key WHERE k1 = 1 AND k2 < 1;
EXPLAIN (COSTS FALSE) DELETE FROM single_row_comp_key WHERE k1 = 1 AND k2 != 1;

-- Below statements should all USE single-row.
EXPLAIN (COSTS FALSE) UPDATE single_row_comp_key SET v = 1 WHERE k1 = 1 and k2 = 1;
EXPLAIN (COSTS FALSE) UPDATE single_row_comp_key SET v = 1 WHERE k1 = 1 and k2 = 1 RETURNING k1, k2, v;
EXPLAIN (COSTS FALSE) UPDATE single_row_comp_key SET v = 1 + 2 WHERE k1 = 1 and k2 = 1;
EXPLAIN (COSTS FALSE) UPDATE single_row_comp_key SET v = v + 1 WHERE k1 = 1 and k2 = 1;
EXPLAIN (COSTS FALSE) UPDATE single_row SET v1 = 3 - 2 WHERE k = 1;
EXPLAIN (COSTS FALSE) UPDATE single_row SET v1 = ceil(3 - 2.5) WHERE k = 1;
EXPLAIN (COSTS FALSE) UPDATE single_row SET v1 = 3 - v1 WHERE k = 1;

-- Below statements should all NOT USE single-row.
EXPLAIN (COSTS FALSE) UPDATE single_row_comp_key SET v = 1;
EXPLAIN (COSTS FALSE) UPDATE single_row_comp_key SET v = k1 + 1 WHERE k1 = 1 and k2 = 1;
EXPLAIN (COSTS FALSE) UPDATE single_row_comp_key SET v = 1 WHERE k1 = 1 and k2 = 1 and v = 1;
EXPLAIN (COSTS FALSE) UPDATE single_row SET v1 = 3 - k WHERE k = 1;
EXPLAIN (COSTS FALSE) UPDATE single_row SET v1 = v1 - k WHERE k = 1;

-- Random is not a stable function so it should NOT USE single-row.
-- TODO However it technically does not read/write data so later on it could be allowed.
EXPLAIN (COSTS FALSE) UPDATE single_row SET v1 = ceil(random()) WHERE k = 1;

-- Test execution.
INSERT INTO single_row_comp_key VALUES (1, 2, 3);

UPDATE single_row_comp_key SET v = 2 WHERE k1 = 2 and k2 = 3;
SELECT * FROM single_row_comp_key;

-- try switching around the order, reversing value/key
DELETE FROM single_row_comp_key WHERE 2 = k2 and 3 = k1;
SELECT * FROM single_row_comp_key;
DELETE FROM single_row_comp_key WHERE 3 = k2 and 2 = k1;
SELECT * FROM single_row_comp_key;

--
-- Test table with non-standard const type.
--
CREATE TABLE single_row_complex (k bigint PRIMARY KEY, v float);

-- Below statements should all USE single-row.
EXPLAIN (COSTS FALSE) DELETE FROM single_row_complex WHERE k = 1;
EXPLAIN (COSTS FALSE) DELETE FROM single_row_complex WHERE k = 1 RETURNING k;
-- Below statements should all NOT USE single-row.
EXPLAIN (COSTS FALSE) DELETE FROM single_row_complex;
EXPLAIN (COSTS FALSE) DELETE FROM single_row_complex WHERE k = 1 and v = 1;
EXPLAIN (COSTS FALSE) DELETE FROM single_row_complex WHERE v = 1;
EXPLAIN (COSTS FALSE) DELETE FROM single_row_complex WHERE k = 1 RETURNING v;

-- Below statements should all USE single-row.
EXPLAIN (COSTS FALSE) UPDATE single_row_complex SET v = 1 WHERE k = 1;
EXPLAIN (COSTS FALSE) UPDATE single_row_complex SET v = 1 WHERE k = 1 RETURNING k, v;
EXPLAIN (COSTS FALSE) UPDATE single_row_complex SET v = 1 + 2 WHERE k = 1;
EXPLAIN (COSTS FALSE) UPDATE single_row_complex SET v = v + 1 WHERE k = 1;
EXPLAIN (COSTS FALSE) UPDATE single_row_complex SET v = 3 * (v + 3 - 2) WHERE k = 1;

-- Below statements should all NOT USE single-row.
EXPLAIN (COSTS FALSE) UPDATE single_row_complex SET v = 1;
EXPLAIN (COSTS FALSE) UPDATE single_row_complex SET v = k + 1 WHERE k = 1;
EXPLAIN (COSTS FALSE) UPDATE single_row_complex SET v = 1 WHERE k = 1 and v = 1;

-- Test execution.
INSERT INTO single_row_complex VALUES (1, 1);

UPDATE single_row_complex SET v = 2 WHERE k = 1;
SELECT * FROM single_row_complex;

UPDATE single_row_complex SET v = 3 * (v + 3 - 2) WHERE k = 1;
SELECT * FROM single_row_complex;

DELETE FROM single_row_complex WHERE k = 1;
SELECT * FROM single_row_complex;

--
-- Test table with non-const type.
--
CREATE TABLE single_row_array (k int primary key, arr int []);

-- Below statements should all USE single-row.
EXPLAIN (COSTS FALSE) DELETE FROM single_row_array WHERE k = 1;
EXPLAIN (COSTS FALSE) DELETE FROM single_row_array WHERE k = 1 RETURNING k;
-- Below statements should all NOT USE single-row.
EXPLAIN (COSTS FALSE) DELETE FROM single_row_array;
EXPLAIN (COSTS FALSE) DELETE FROM single_row_array WHERE k = 1 and arr[1] = 1;
EXPLAIN (COSTS FALSE) DELETE FROM single_row_array WHERE arr[1] = 1;
EXPLAIN (COSTS FALSE) DELETE FROM single_row_array WHERE k = 1 RETURNING arr;

-- Below statements should all NOT USE single-row.
EXPLAIN (COSTS FALSE) UPDATE single_row_array SET arr[1] = 1 WHERE k = 1;

-- Test execution.
INSERT INTO single_row_array VALUES (1, ARRAY [1, 2, 3]);

DELETE FROM single_row_array WHERE k = 1;
SELECT * FROM single_row_array;

--
-- Test table without a primary key.
--
CREATE TABLE single_row_no_primary_key (a int, b int);

-- Below statements should all NOT USE single-row.
EXPLAIN (COSTS FALSE) DELETE FROM single_row_no_primary_key;
EXPLAIN (COSTS FALSE) DELETE FROM single_row_no_primary_key WHERE a = 1;
EXPLAIN (COSTS FALSE) DELETE FROM single_row_no_primary_key WHERE a = 1 and b = 1;

-- Below statements should all NOT USE single-row.
EXPLAIN (COSTS FALSE) UPDATE single_row_no_primary_key SET a = 1;
EXPLAIN (COSTS FALSE) UPDATE single_row_no_primary_key SET b = 1 WHERE a = 1;
EXPLAIN (COSTS FALSE) UPDATE single_row_no_primary_key SET b = 1 WHERE b = 1;

--
-- Test table with range primary key (ASC).
--
CREATE TABLE single_row_range_asc_primary_key (k int, v int, primary key (k ASC));

-- Below statements should all USE single-row.
EXPLAIN (COSTS FALSE) DELETE FROM single_row_range_asc_primary_key WHERE k = 1;
EXPLAIN (COSTS FALSE) UPDATE single_row_range_asc_primary_key SET v = 1 WHERE k = 1;
EXPLAIN (COSTS FALSE) UPDATE single_row_range_asc_primary_key SET v = 1 + 2 WHERE k = 1;
EXPLAIN (COSTS FALSE) UPDATE single_row_range_asc_primary_key SET v = ceil(2.5 + power(2,2)) WHERE k = 4;
EXPLAIN (COSTS FALSE) UPDATE single_row_range_asc_primary_key SET v = v + 1 WHERE k = 1;

-- Below statements should all NOT USE single-row.
EXPLAIN (COSTS FALSE) UPDATE single_row_range_asc_primary_key SET v = 1 WHERE k > 1;
EXPLAIN (COSTS FALSE) UPDATE single_row_range_asc_primary_key SET v = 1 WHERE k != 1;
EXPLAIN (COSTS FALSE) UPDATE single_row_range_asc_primary_key SET v = v + k WHERE k = 1;
EXPLAIN (COSTS FALSE) UPDATE single_row_range_asc_primary_key SET v = abs(5 - k) WHERE k = 1;

-- Test execution
INSERT INTO single_row_range_asc_primary_key(k,v) values (1,1), (2,2), (3,3), (4,4);

UPDATE single_row_range_asc_primary_key SET v = 10 WHERE k = 1;
SELECT * FROM single_row_range_asc_primary_key;
UPDATE single_row_range_asc_primary_key SET v = v + 1 WHERE k = 2;
SELECT * FROM single_row_range_asc_primary_key;
UPDATE single_row_range_asc_primary_key SET v = -3 WHERE k < 4 AND k >= 3;
SELECT * FROM single_row_range_asc_primary_key;
UPDATE single_row_range_asc_primary_key SET v = ceil(2.5 + power(2,2)) WHERE k = 4;
SELECT * FROM single_row_range_asc_primary_key;
DELETE FROM single_row_range_asc_primary_key WHERE k < 3;
SELECT * FROM single_row_range_asc_primary_key;
DELETE FROM single_row_range_asc_primary_key WHERE k = 4;
SELECT * FROM single_row_range_asc_primary_key;

--
-- Test table with range primary key (DESC).
--
CREATE TABLE single_row_range_desc_primary_key (k int, v int, primary key (k DESC));

-- Below statements should all USE single-row.
EXPLAIN (COSTS FALSE) DELETE FROM single_row_range_desc_primary_key WHERE k = 1;
EXPLAIN (COSTS FALSE) UPDATE single_row_range_desc_primary_key SET v = 1 WHERE k = 1;
EXPLAIN (COSTS FALSE) UPDATE single_row_range_desc_primary_key SET v = 1 + 2 WHERE k = 1;
EXPLAIN (COSTS FALSE) UPDATE single_row_range_desc_primary_key SET v = ceil(2.5 + power(2,2)) WHERE k = 4;
EXPLAIN (COSTS FALSE) UPDATE single_row_range_desc_primary_key SET v = v + 1 WHERE k = 1;

-- Below statements should all NOT USE single-row.
EXPLAIN (COSTS FALSE) UPDATE single_row_range_desc_primary_key SET v = 1 WHERE k > 1;
EXPLAIN (COSTS FALSE) UPDATE single_row_range_desc_primary_key SET v = 1 WHERE k != 1;
EXPLAIN (COSTS FALSE) UPDATE single_row_range_desc_primary_key SET v = k + 1 WHERE k = 1;
EXPLAIN (COSTS FALSE) UPDATE single_row_range_desc_primary_key SET v = abs(5 - k) WHERE k = 1;

-- Test execution
INSERT INTO single_row_range_desc_primary_key(k,v) values (1,1), (2,2), (3,3), (4,4);

UPDATE single_row_range_desc_primary_key SET v = 10 WHERE k = 1;
SELECT * FROM single_row_range_desc_primary_key;
UPDATE single_row_range_desc_primary_key SET v = v + 1 WHERE k = 2;
SELECT * FROM single_row_range_desc_primary_key;
UPDATE single_row_range_desc_primary_key SET v = -3 WHERE k < 4 AND k >= 3;
SELECT * FROM single_row_range_desc_primary_key;
UPDATE single_row_range_desc_primary_key SET v = ceil(2.5 + power(2,2)) WHERE k = 4;
SELECT * FROM single_row_range_desc_primary_key;
DELETE FROM single_row_range_desc_primary_key WHERE k < 3;
SELECT * FROM single_row_range_desc_primary_key;
DELETE FROM single_row_range_desc_primary_key WHERE k = 4;
SELECT * FROM single_row_range_desc_primary_key;

--
-- Test tables with constraints.
--
CREATE TABLE single_row_not_null_constraints (k int PRIMARY KEY, v1 int NOT NULL, v2 int NOT NULL);
CREATE TABLE single_row_check_constraints (k int PRIMARY KEY, v1 int NOT NULL, v2 int CHECK (v2 >= 0));
CREATE TABLE single_row_check_constraints2 (k int PRIMARY KEY, v1 int NOT NULL, v2 int CHECK (v1 >= v2));

-- Below statements should all USE single-row.
EXPLAIN (COSTS FALSE) DELETE FROM single_row_not_null_constraints WHERE k = 1;
EXPLAIN (COSTS FALSE) DELETE FROM single_row_check_constraints WHERE k = 1;
EXPLAIN (COSTS FALSE) DELETE FROM single_row_check_constraints2 WHERE k = 1;
EXPLAIN (COSTS FALSE) UPDATE single_row_not_null_constraints SET v1 = 2 WHERE k = 1;
EXPLAIN (COSTS FALSE) UPDATE single_row_not_null_constraints SET v2 = 2 WHERE k = 1;
EXPLAIN (COSTS FALSE) UPDATE single_row_not_null_constraints SET v2 = v2 + 3 WHERE k = 1;
EXPLAIN (COSTS FALSE) UPDATE single_row_not_null_constraints SET v1 = abs(v1), v2 = power(v2,2) WHERE k = 1;
EXPLAIN (COSTS FALSE) UPDATE single_row_not_null_constraints SET v2 = v2 + null WHERE k = 1;

-- Below statements should all NOT USE single-row.
EXPLAIN (COSTS FALSE) UPDATE single_row_check_constraints SET v1 = 2 WHERE k = 1;
EXPLAIN (COSTS FALSE) UPDATE single_row_check_constraints SET v2 = 2 WHERE k = 1;
EXPLAIN (COSTS FALSE) UPDATE single_row_check_constraints2 SET v1 = 2 WHERE k = 1;
EXPLAIN (COSTS FALSE) UPDATE single_row_check_constraints2 SET v2 = 2 WHERE k = 1;

-- Test execution.
INSERT INTO single_row_not_null_constraints(k,v1, v2) values (1,1,1), (2,2,2), (3,3,3);
UPDATE single_row_not_null_constraints SET v1 = 2 WHERE k = 1;
UPDATE single_row_not_null_constraints SET v2 = v2 + 3 WHERE k = 1;
DELETE FROM single_row_not_null_constraints where k = 3;
SELECT * FROM single_row_not_null_constraints ORDER BY k;
UPDATE single_row_not_null_constraints SET v1 = abs(v1), v2 = power(v2,2) WHERE k = 1;
SELECT * FROM single_row_not_null_constraints ORDER BY k;
-- Should fail constraint check.
UPDATE single_row_not_null_constraints SET v2 = v2 + null WHERE k = 1;
-- Should update 0 rows (non-existent key).
UPDATE single_row_not_null_constraints SET v2 = v2 + 2 WHERE k = 4;
SELECT * FROM single_row_not_null_constraints ORDER BY k;


INSERT INTO single_row_check_constraints(k,v1, v2) values (1,1,1), (2,2,2), (3,3,3);
UPDATE single_row_check_constraints SET v1 = 2 WHERE k = 1;
UPDATE single_row_check_constraints SET v2 = 3 WHERE k = 1;
UPDATE single_row_check_constraints SET v2 = -3 WHERE k = 1;
DELETE FROM single_row_check_constraints where k = 3;
SELECT * FROM single_row_check_constraints ORDER BY k;

INSERT INTO single_row_check_constraints2(k,v1, v2) values (1,1,1), (2,2,2), (3,3,3);
UPDATE single_row_check_constraints2 SET v1 = 2 WHERE k = 1;
UPDATE single_row_check_constraints2 SET v2 = 3 WHERE k = 1;
UPDATE single_row_check_constraints2 SET v2 = 1 WHERE k = 1;
DELETE FROM single_row_check_constraints2 where k = 3;
SELECT * FROM single_row_check_constraints2 ORDER BY k;

--
-- Test table with decimal.
--
CREATE TABLE single_row_decimal (k int PRIMARY KEY, v1 decimal, v2 decimal(10,2), v3 int);

-- Below statements should all USE single-row.
EXPLAIN (COSTS FALSE) UPDATE single_row_decimal SET v1 = 1.555 WHERE k = 1;
EXPLAIN (COSTS FALSE) UPDATE single_row_decimal SET v1 = v1 + 1.555 WHERE k = 1;
EXPLAIN (COSTS FALSE) UPDATE single_row_decimal SET v2 = 1.555 WHERE k = 1;
EXPLAIN (COSTS FALSE) UPDATE single_row_decimal SET v2 = v2 + 1.555 WHERE k = 1;
EXPLAIN (COSTS FALSE) UPDATE single_row_decimal SET v3 = 1 WHERE k = 1;
EXPLAIN (COSTS FALSE) UPDATE single_row_decimal SET v3 = v3 + 1 WHERE k = 1;
EXPLAIN (COSTS FALSE) UPDATE single_row_decimal SET v1 = v1 + 1.555, v2 = v2 + 1.555, v3 = v3 + 1 WHERE k = 1;
EXPLAIN (COSTS FALSE) UPDATE single_row_decimal SET v1 = v1 + null WHERE k = 2;
EXPLAIN (COSTS FALSE) UPDATE single_row_decimal SET v2 = null + v2 WHERE k = 2;
EXPLAIN (COSTS FALSE) UPDATE single_row_decimal SET v3 = v3 + 4 * (null - 5) WHERE k = 2;
-- Below statements should all NOT USE single-row.
EXPLAIN (COSTS FALSE) UPDATE single_row_decimal SET v1 = v2 + 1.555 WHERE k = 1;
EXPLAIN (COSTS FALSE) UPDATE single_row_decimal SET v2 = k + 1.555 WHERE k = 1;
EXPLAIN (COSTS FALSE) UPDATE single_row_decimal SET v3 = k - v3 WHERE k = 1;

-- Test execution.
INSERT INTO single_row_decimal(k, v1, v2, v3) values (1,1.5,1.5,1), (2,2.5,2.5,2), (3,null, null,null);
SELECT * FROM single_row_decimal ORDER BY k;
UPDATE single_row_decimal SET v1 = v1 + 1.555, v2 = v2 + 1.555, v3 = v3 + 1 WHERE k = 1;
-- v2 should be rounded to 2 decimals.
SELECT * FROM single_row_decimal ORDER BY k;

-- Test null arguments, all expressions should evaluate to null.
UPDATE single_row_decimal SET v1 = v1 + null WHERE k = 2;
UPDATE single_row_decimal SET v2 = null + v2 WHERE k = 2;
UPDATE single_row_decimal SET v3 = v3 + 4 * (null - 5) WHERE k = 2;
SELECT * FROM single_row_decimal ORDER BY k;

-- Test null values, all expressions should evaluate to null.
UPDATE single_row_decimal SET v1 = v1 + 1.555 WHERE k = 3;
UPDATE single_row_decimal SET v2 = v2 + 1.555 WHERE k = 3;
UPDATE single_row_decimal SET v3 = v3 + 1 WHERE k = 3;
SELECT * FROM single_row_decimal ORDER BY k;

--
-- Test table with foreign key constraint.
-- Should still try single-row if (and only if) the FK column is not updated.
--
CREATE TABLE single_row_decimal_fk(k int PRIMARY KEY);
INSERT INTO single_row_decimal_fk(k) VALUES (1), (2), (3), (4);
ALTER TABLE single_row_decimal ADD FOREIGN KEY (v3) REFERENCES single_row_decimal_fk(k);

-- Below statements should all USE single-row.
EXPLAIN (COSTS FALSE) UPDATE single_row_decimal SET v1 = 1.555 WHERE k = 4;
EXPLAIN (COSTS FALSE) UPDATE single_row_decimal SET v1 = v1 + 1.555 WHERE k = 4;
EXPLAIN (COSTS FALSE) UPDATE single_row_decimal SET v2 = 1.555 WHERE k = 4;
EXPLAIN (COSTS FALSE) UPDATE single_row_decimal SET v2 = v2 + 1.555 WHERE k = 4;

-- Below statements should all NOT USE single-row.
EXPLAIN (COSTS FALSE) UPDATE single_row_decimal SET v3 = 1 WHERE k = 4;
EXPLAIN (COSTS FALSE) UPDATE single_row_decimal SET v3 = v3 + 1 WHERE k = 4;
EXPLAIN (COSTS FALSE) UPDATE single_row_decimal SET v1 = v2 + 1.555 WHERE k = 4;
EXPLAIN (COSTS FALSE) UPDATE single_row_decimal SET v2 = k + 1.555 WHERE k = 4;
EXPLAIN (COSTS FALSE) UPDATE single_row_decimal SET v3 = k - v3 WHERE k = 4;

-- Test execution.
INSERT INTO single_row_decimal(k, v1, v2, v3) values (4,4.5,4.5,4);

SELECT * FROM single_row_decimal ORDER BY k;
UPDATE single_row_decimal SET v1 = v1 + 4.555 WHERE k = 4;
UPDATE single_row_decimal SET v2 = v2 + 4.555 WHERE k = 4;
UPDATE single_row_decimal SET v3 = v3 + 4 WHERE k = 4;
-- v2 should be rounded to 2 decimals.
SELECT * FROM single_row_decimal ORDER BY k;

--
-- Test table with indexes.
-- Should use single-row for expressions if (and only if) the indexed columns are not updated.
--
CREATE TABLE single_row_index(k int PRIMARY KEY, v1 smallint, v2 smallint, v3 smallint);

-- Below statements should all USE single-row.
EXPLAIN (COSTS FALSE) UPDATE single_row_index SET v1 = 1 WHERE k = 1;
EXPLAIN (COSTS FALSE) UPDATE single_row_index SET v1 = v1 + 1 WHERE k = 1;
EXPLAIN (COSTS FALSE) UPDATE single_row_index SET v2 = 2 WHERE k = 1;
EXPLAIN (COSTS FALSE) UPDATE single_row_index SET v2 = v2 + 2 WHERE k = 1;
EXPLAIN (COSTS FALSE) UPDATE single_row_index SET v3 = 3 WHERE k = 1;
EXPLAIN (COSTS FALSE) UPDATE single_row_index SET v3 = v3 + 3 WHERE k = 1;

CREATE INDEX single_row_index_idx on single_row_index(v1) include (v3);

-- Below statements should all USE single-row.
EXPLAIN (COSTS FALSE) UPDATE single_row_index SET v2 = 2 WHERE k = 1;
EXPLAIN (COSTS FALSE) UPDATE single_row_index SET v2 = v2 + 2 WHERE k = 1;

-- Below statements should all NOT USE single-row.
EXPLAIN (COSTS FALSE) UPDATE single_row_index SET v1 = 1 WHERE k = 1;
EXPLAIN (COSTS FALSE) UPDATE single_row_index SET v1 = v1 + 1 WHERE k = 1;
EXPLAIN (COSTS FALSE) UPDATE single_row_index SET v3 = 3 WHERE k = 1;
EXPLAIN (COSTS FALSE) UPDATE single_row_index SET v3 = v3 + 3 WHERE k = 1;

-- Test execution.
INSERT INTO single_row_index(k, v1, v2, v3) VALUES (1,0,0,0), (2,2,32000,2);

SELECT * FROM single_row_index ORDER BY k;
UPDATE single_row_index SET v1 = 1 WHERE k = 1;
UPDATE single_row_index SET v2 = 2 WHERE k = 1;
UPDATE single_row_index SET v3 = 3 WHERE k = 1;
SELECT * FROM single_row_index ORDER BY k;
UPDATE single_row_index SET v1 = v1 + 1 WHERE k = 1;
UPDATE single_row_index SET v2 = v2 + 2 WHERE k = 1;
UPDATE single_row_index SET v3 = v3 + 3 WHERE k = 1;
SELECT * FROM single_row_index ORDER BY k;

-- Test error reporting (overflow).
EXPLAIN (COSTS FALSE) UPDATE single_row_index SET v2 = v2 + 1000 WHERE k = 2;
UPDATE single_row_index SET v2 = v2 + 1000 WHERE k = 2;

-- Test column ordering.
CREATE TABLE single_row_col_order(a int, b int, c int, d int, e int, primary key(d, b));

-- Below statements should all USE single-row.
EXPLAIN (COSTS OFF) UPDATE single_row_col_order SET c = 6, a = 2, e = 10 WHERE b = 2 and d = 4;
EXPLAIN (COSTS OFF) UPDATE single_row_col_order SET c = c * c, a = a * 2, e = power(e, 2) WHERE b = 2 and d = 4;
EXPLAIN (COSTS OFF) DELETE FROM single_row_col_order WHERE b = 2 and d = 4;

-- Below statements should all NOT USE single-row.
EXPLAIN (COSTS OFF) UPDATE single_row_col_order SET c = 6, a = c + 2, e = 10 WHERE b = 2 and d = 4;
EXPLAIN (COSTS OFF) UPDATE single_row_col_order SET c = c * b, a = a * 2, e = power(e, 2) WHERE b = 2 and d = 4;

-- Test execution.
INSERT INTO single_row_col_order(a,b,c,d,e) VALUES (1,2,3,4,5), (2,3,4,5,6);

UPDATE single_row_col_order SET c = 6, a = 2, e = 10 WHERE b = 2 and d = 4;
SELECT * FROM single_row_col_order ORDER BY d, b;

UPDATE single_row_col_order SET c = c * c, a = a * 2, e = power(e, 2) WHERE d = 4 and b = 2;
SELECT * FROM single_row_col_order ORDER BY d, b;

DELETE FROM single_row_col_order WHERE b = 2 and d = 4;
SELECT * FROM single_row_col_order ORDER BY d, b;
