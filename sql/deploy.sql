-- =====================================================================
-- deploy.sql -- deployment orchestrator, run inside Snowflake
--
-- Purpose  Execute the whole deployment in dependency order from one
--          Git commit, so every object in the account comes from the same
--          revision of the source.
-- Called   By bootstrap.sql, which resolves main's commit hash and passes it
--          as :revision. Not intended to be run by hand: outside that
--          wrapper {{ revision }} is unbound and the stage paths will not
--          resolve. Deploying from Git rather than from a laptop is what
--          makes a deployment reproducible and attributable to a commit.
-- Order    guard -> containers -> data -> views -> semantics -> skills ->
--          agent -> grants. Each step depends on the one before it, and the
--          grants come last because GRANT fails on an object that does not
--          yet exist.
-- =====================================================================

-- Prove the target and check for collisions before anything is created.
EXECUTE IMMEDIATE FROM './00_guard.sql';
-- Containers and canonical tables, all CREATE IF NOT EXISTS.
EXECUTE IMMEDIATE FROM './01_setup.sql';

-- Generate and load the fixture. The generator is Python, so it runs as a
-- stored procedure with the two source files imported straight from the
-- pinned commit -- the same code the local unit tests exercise, with no
-- separate copy in the account to drift out of sync.
--
-- EXECUTE AS CALLER is the important clause: the procedure holds no
-- privileges of its own, so it can only touch what the deploying role could
-- already touch. An owner's-rights procedure would be a standing privilege-
-- escalation path that outlived the deployment.
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
-- Dropped immediately after use. A procedure that can DELETE and INSERT the
-- fixture has no business remaining callable once the data is loaded, and it
-- is never granted to the reader role.
DROP PROCEDURE SNOWFLAKE_EXAMPLE.RESTAURANT_RECOVERY.SEED_DEMO();

-- Evidence views, then the semantic views that sit on top of them. Views
-- follow the load so CREATE OR REPLACE never briefly points at empty tables.
EXECUTE IMMEDIATE FROM './02_analytics.sql';
EXECUTE IMMEDIATE FROM './04_semantics.sql';

-- Stage the runtime skills under the commit hash. Copying per revision means
-- the agent created below reads the instructions from this exact commit, and
-- a redeployment cannot leave it pointing at older text.
COPY FILES INTO @SNOWFLAKE_EXAMPLE.RESTAURANT_RECOVERY.RELEASE_FILES/skills/{{ revision }}/restaurant-investigation/
  FROM @SNOWFLAKE_EXAMPLE.GIT_REPOS.RESTAURANT_RECOVERY_REPO/commits/{{ revision }}/skills/restaurant-investigation/
  FILES = ('SKILL.md');
COPY FILES INTO @SNOWFLAKE_EXAMPLE.RESTAURANT_RECOVERY.RELEASE_FILES/skills/{{ revision }}/restaurant-test-design/
  FROM @SNOWFLAKE_EXAMPLE.GIT_REPOS.RESTAURANT_RECOVERY_REPO/commits/{{ revision }}/skills/restaurant-test-design/
  FILES = ('SKILL.md');

-- The agent, which needs the revision at run time to build its skill paths.
-- USING passes it as a bind variable rather than as text substitution.
EXECUTE IMMEDIATE FROM './05_agent.sql' USING (revision => '{{ revision }}');

-- Grants last, once every object exists to be granted.
EXECUTE IMMEDIATE FROM './03_reader.sql';
