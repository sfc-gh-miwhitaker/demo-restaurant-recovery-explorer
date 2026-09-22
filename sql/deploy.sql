EXECUTE IMMEDIATE FROM './00_guard.sql';
EXECUTE IMMEDIATE FROM './01_setup.sql';
CREATE OR REPLACE PROCEDURE SNOWFLAKE_EXAMPLE.RESTAURANT_RECOVERY.SEED_DEMO()
  RETURNS VARCHAR
  LANGUAGE PYTHON
  RUNTIME_VERSION = '3.11'
  PACKAGES = ('snowflake-snowpark-python')
  IMPORTS = (
    '@SNOWFLAKE_EXAMPLE.GIT_REPOS.RESTAURANT_RECOVERY_REPO/commits/{{ revision }}/tools/generate_cowork.py',
    '@SNOWFLAKE_EXAMPLE.GIT_REPOS.RESTAURANT_RECOVERY_REPO/commits/{{ revision }}/tools/native_runtime.py')
  HANDLER = 'native_runtime.seed'
  COMMENT = 'DEMO: Deployment-only helper; no reader grant (Expires: 2026-10-22)'
  EXECUTE AS CALLER;
CALL SNOWFLAKE_EXAMPLE.RESTAURANT_RECOVERY.SEED_DEMO();
DROP PROCEDURE SNOWFLAKE_EXAMPLE.RESTAURANT_RECOVERY.SEED_DEMO();
EXECUTE IMMEDIATE FROM './02_analytics.sql';
EXECUTE IMMEDIATE FROM './04_semantics.sql';
COPY FILES INTO @SNOWFLAKE_EXAMPLE.RESTAURANT_RECOVERY.RELEASE_FILES/skills/{{ revision }}/restaurant-investigation/
  FROM @SNOWFLAKE_EXAMPLE.GIT_REPOS.RESTAURANT_RECOVERY_REPO/commits/{{ revision }}/skills/restaurant-investigation/
  FILES = ('SKILL.md');
COPY FILES INTO @SNOWFLAKE_EXAMPLE.RESTAURANT_RECOVERY.RELEASE_FILES/skills/{{ revision }}/restaurant-test-design/
  FROM @SNOWFLAKE_EXAMPLE.GIT_REPOS.RESTAURANT_RECOVERY_REPO/commits/{{ revision }}/skills/restaurant-test-design/
  FILES = ('SKILL.md');
EXECUTE IMMEDIATE FROM './05_agent.sql' USING (revision => '{{ revision }}');
EXECUTE IMMEDIATE FROM './03_reader.sql';