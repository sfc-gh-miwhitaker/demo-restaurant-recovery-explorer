-- =====================================================================
-- 00_guard.sql -- pre-deployment safety gate
--
-- Purpose  Refuse to deploy anywhere the operator did not explicitly name,
--          and refuse to overwrite objects that are not this demo.
-- Runs     First, before any DDL in 01_setup.sql.
-- Inputs   RR_EXPECTED_ACCOUNT -- the intended ORGANIZATION.ACCOUNT, passed
--          in by the operator. It is compared against the session, never
--          derived from it.
-- Fails    -20003 wrong or unnamed target; -20004 object name collision.
--
-- Why an explicit target rather than "wherever I am connected": a demo
-- deployment creates a schema, a warehouse, a role and an agent under
-- well-known names. Getting that into the wrong account is the expensive
-- mistake, and the active connection is the easiest thing to be wrong
-- about. Requiring the operator to type the account turns a silent
-- accident into a deliberate act.
-- =====================================================================
EXECUTE IMMEDIATE $$
DECLARE
  invalid_target EXCEPTION (-20003, 'Target mismatch. Set RR_EXPECTED_ACCOUNT to the intended ORGANIZATION.ACCOUNT; do not derive it automatically.');
  collision EXCEPTION (-20004, 'Existing project schema or warehouse is not marked as this demo. Review ownership before continuing.');
  matches INTEGER;
BEGIN
  -- Three ways to fail the target test: the operator named nothing, the name
  -- does not match this session, or the session is Snowhouse. The Snowhouse
  -- exclusion is absolute -- it is Snowflake's internal telemetry account and
  -- is never a demo target, even if someone names it deliberately.
  IF ($RR_EXPECTED_ACCOUNT IS NULL OR UPPER($RR_EXPECTED_ACCOUNT) <> (CURRENT_ORGANIZATION_NAME() || '.' || CURRENT_ACCOUNT_NAME())
      OR CURRENT_ACCOUNT_NAME() ILIKE '%SNOWHOUSE%') THEN
    RAISE invalid_target;
  END IF;
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
