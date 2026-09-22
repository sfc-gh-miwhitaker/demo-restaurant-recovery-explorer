EXECUTE IMMEDIATE $$
DECLARE
  invalid_target EXCEPTION (-20003, 'Target mismatch. Set RR_EXPECTED_ACCOUNT to the intended ORGANIZATION.ACCOUNT; do not derive it automatically.');
  collision EXCEPTION (-20004, 'Existing project schema or warehouse is not marked as this demo. Review ownership before continuing.');
  matches INTEGER;
BEGIN
  IF ($RR_EXPECTED_ACCOUNT IS NULL OR UPPER($RR_EXPECTED_ACCOUNT) <> (CURRENT_ORGANIZATION_NAME() || '.' || CURRENT_ACCOUNT_NAME())
      OR CURRENT_ACCOUNT_NAME() ILIKE '%SNOWHOUSE%') THEN
    RAISE invalid_target;
  END IF;
  SHOW SCHEMAS LIKE 'RESTAURANT_RECOVERY' IN DATABASE SNOWFLAKE_EXAMPLE;
  SELECT COUNT(*) INTO :matches FROM TABLE(RESULT_SCAN(LAST_QUERY_ID()))
    WHERE "name" = 'RESTAURANT_RECOVERY'
      AND (COALESCE("comment", '') NOT LIKE 'DEMO: Synthetic restaurant recovery%' OR "owner" <> 'SYSADMIN');
  IF (matches > 0) THEN RAISE collision; END IF;
  SHOW WAREHOUSES LIKE 'SFE_RESTAURANT_RECOVERY_WH';
  SELECT COUNT(*) INTO :matches FROM TABLE(RESULT_SCAN(LAST_QUERY_ID()))
    WHERE "name" = 'SFE_RESTAURANT_RECOVERY_WH'
      AND (COALESCE("comment", '') NOT LIKE 'DEMO: Restaurant recovery compute%' OR "owner" <> 'SYSADMIN');
  IF (matches > 0) THEN RAISE collision; END IF;
END;
$$;