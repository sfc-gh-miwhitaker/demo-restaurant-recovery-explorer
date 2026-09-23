-- =====================================================================
-- 00_guard.sql -- pre-deployment collision gate
--
-- Purpose  Refuse to overwrite objects that are not this demo.
-- Runs     First, before any DDL in 01_setup.sql.
-- Fails    -20004 object name collision.
--
-- Why a collision check rather than an operator-typed account confirmation:
-- deploy_all.sql is meant to be pasted into a worksheet and run with one
-- click, so a gate that requires a hand-typed variable would fail every
-- first-time deployment by design. What actually needs protecting is not the
-- choice of account -- every object here is namespaced under SNOWFLAKE_EXAMPLE
-- with SFE_ prefixes and demo comments, and teardown_all.sql reverses it --
-- but the possibility that something else already owns one of these names.
-- 01_setup.sql uses CREATE IF NOT EXISTS, which would quietly adopt whatever
-- it found, so that is the case worth stopping.
-- =====================================================================
EXECUTE IMMEDIATE $$
DECLARE
  collision EXCEPTION (-20004, 'Existing project schema or warehouse is not marked as this demo. Review ownership before continuing.');
  matches INTEGER;
BEGIN
  -- Collision test. The schema name is generic enough that something else
  -- could already own it, and 01_setup.sql uses CREATE IF NOT EXISTS, which
  -- would quietly adopt whatever it found. So: if an object of this name
  -- exists, it must carry both this demo's comment prefix and SYSADMIN
  -- ownership. Anything else stops the deployment for a human to look at.
  --
  -- SHOW does not support a WHERE clause, so the pattern throughout is
  -- SHOW followed by RESULT_SCAN(LAST_QUERY_ID()) to filter its output.
  -- The double-quoted column names are required: SHOW returns lowercase
  -- identifiers.
  SHOW SCHEMAS LIKE 'RESTAURANT_RECOVERY' IN DATABASE SNOWFLAKE_EXAMPLE;
  SELECT COUNT(*) INTO :matches FROM TABLE(RESULT_SCAN(LAST_QUERY_ID()))
    WHERE "name" = 'RESTAURANT_RECOVERY'
      -- COALESCE because an absent comment is NULL, and NULL NOT LIKE ...
      -- is NULL, not TRUE -- the unmarked object would slip through.
      AND (COALESCE("comment", '') NOT LIKE 'DEMO: Synthetic restaurant recovery%' OR "owner" <> 'SYSADMIN');
  IF (matches > 0) THEN RAISE collision; END IF;
  -- Same test for the warehouse, which is account-level and so more likely
  -- than the schema to collide with somebody else's object.
  SHOW WAREHOUSES LIKE 'SFE_RESTAURANT_RECOVERY_WH';
  SELECT COUNT(*) INTO :matches FROM TABLE(RESULT_SCAN(LAST_QUERY_ID()))
    WHERE "name" = 'SFE_RESTAURANT_RECOVERY_WH'
      AND (COALESCE("comment", '') NOT LIKE 'DEMO: Restaurant recovery compute%' OR "owner" <> 'SYSADMIN');
  IF (matches > 0) THEN RAISE collision; END IF;
END;
$$;
