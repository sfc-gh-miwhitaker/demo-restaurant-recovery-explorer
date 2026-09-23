/*==============================================================================
DEPLOY ALL - Restaurant Recovery Explorer
Pair-programmed by SE Community + Cortex Code | Expires: 2026-10-22
INSTRUCTIONS: Open in Snowsight -> Click "Run All"

Creates   SNOWFLAKE_EXAMPLE.RESTAURANT_RECOVERY (six tables, seven views), the
          SFE_RESTAURANT_RECOVERY_WH warehouse, three SV_RESTAURANT_RECOVERY_*
          semantic views, RESTAURANT_RECOVERY_AGENT, and the
          SFE_RESTAURANT_RECOVERY_READER role. Also creates a single-repository
          Git API integration and clone, both kept on teardown.
Requires  A demo account with Cortex Agents and Cortex Analyst enabled, run by a
          role that can reach ACCOUNTADMIN (API integration only) and
          SECURITYADMIN (reader role). Everything the demo owns is SYSADMIN's.
Remove    Run teardown_all.sql the same way.

This file is the only part pasted in by hand; everything after the Git handoff
runs from pinned source inside Snowflake. It deploys whatever is on the
repository's main branch right now, so unpushed local edits will not appear in
the account, and redeploying replaces the agent, which resets its version
history. Nothing here is atomic across the whole sequence: on failure, read the
error, fix the cause and run it again.
==============================================================================*/

-- 1. Expiration check. Informational only: a stale demo announces itself in the
--    Run All output rather than refusing to deploy.
SELECT
    '2026-10-22'::DATE AS expiration_date,
    CURRENT_DATE() AS current_date,
    DATEDIFF('day', CURRENT_DATE(), '2026-10-22'::DATE) AS days_remaining,
    CASE
        WHEN DATEDIFF('day', CURRENT_DATE(), '2026-10-22'::DATE) < 0
        THEN 'EXPIRED - Code may use outdated syntax. Remove expiration banner to continue.'
        WHEN DATEDIFF('day', CURRENT_DATE(), '2026-10-22'::DATE) <= 7
        THEN 'EXPIRING SOON - ' || DATEDIFF('day', CURRENT_DATE(), '2026-10-22'::DATE) || ' days remaining'
        ELSE 'ACTIVE - ' || DATEDIFF('day', CURRENT_DATE(), '2026-10-22'::DATE) || ' days remaining'
    END AS demo_status;

-- 2. Shared infrastructure, idempotent and safe to re-run. ACCOUNTADMIN is
--    needed only for the API integration; the file drops back to SYSADMIN as
--    soon as that is done.
USE ROLE ACCOUNTADMIN;

-- Outbound access to exactly one repository. The prefix allowlist is the
-- security boundary: this integration cannot be reused to fetch code from
-- anywhere else. ALLOWED_AUTHENTICATION_SECRETS = NONE states that the
-- source is public and no credential is involved, so nothing here can leak
-- one.
CREATE API INTEGRATION IF NOT EXISTS SFE_RESTAURANT_RECOVERY_GIT_API
  API_PROVIDER = git_https_api
  API_ALLOWED_PREFIXES = ('https://github.com/sfc-gh-miwhitaker/demo-restaurant-recovery-explorer.git')
  ALLOWED_AUTHENTICATION_SECRETS = NONE
  ENABLED = TRUE
  COMMENT = 'DEMO: Public restaurant recovery source (Expires: 2026-10-22)';
GRANT USAGE ON INTEGRATION SFE_RESTAURANT_RECOVERY_GIT_API TO ROLE SYSADMIN;

-- Everything from here owns no privilege it does not need.
USE ROLE SYSADMIN;
CREATE DATABASE IF NOT EXISTS SNOWFLAKE_EXAMPLE;
CREATE SCHEMA IF NOT EXISTS SNOWFLAKE_EXAMPLE.GIT_REPOS;
-- The repository clone lives outside the project schema on purpose, so
-- teardown can remove the demo without removing the source it came from --
-- and a redeployment does not have to re-fetch from GitHub.
CREATE GIT REPOSITORY IF NOT EXISTS SNOWFLAKE_EXAMPLE.GIT_REPOS.RESTAURANT_RECOVERY_REPO
  API_INTEGRATION = SFE_RESTAURANT_RECOVERY_GIT_API
  ORIGIN = 'https://github.com/sfc-gh-miwhitaker/demo-restaurant-recovery-explorer.git'
  COMMENT = 'DEMO: Restaurant recovery source; preserved on teardown (Expires: 2026-10-22)';

-- Created here as well as in 01_setup.sql because the Git fetch and the
-- deployment script itself need compute before 01_setup.sql runs. Identical
-- definition in both places, and CREATE IF NOT EXISTS makes the second a
-- no-op.
-- STATEMENT_TIMEOUT_IN_SECONDS is deliberately generous: the seeding procedure
-- builds and loads roughly 420,000 rows in one Python statement, which is a
-- single long-running statement on an XSMALL, not a runaway query.
CREATE WAREHOUSE IF NOT EXISTS SFE_RESTAURANT_RECOVERY_WH
  WAREHOUSE_SIZE = 'XSMALL' AUTO_SUSPEND = 60 AUTO_RESUME = TRUE
  INITIALLY_SUSPENDED = TRUE STATEMENT_TIMEOUT_IN_SECONDS = 3600
  COMMENT = 'DEMO: Restaurant recovery compute (Expires: 2026-10-22)';
USE WAREHOUSE SFE_RESTAURANT_RECOVERY_WH;

-- 3. Pull the current state of the remote into the clone.
ALTER GIT REPOSITORY SNOWFLAKE_EXAMPLE.GIT_REPOS.RESTAURANT_RECOVERY_REPO FETCH;

-- 4. Resolve main to a commit hash, then run the deployment from that commit.
--
-- Why pin at all: /branches/main is a moving pointer. Reading it once and
-- then deploying from /commits/<hash> means the SQL, the Python generator and
-- the runtime skill files all come from a single revision, and the revision
-- is echoed back to the operator. A deployment that took ten minutes cannot
-- straddle two versions of the source, and the account's contents can always
-- be traced to one commit.
EXECUTE IMMEDIATE $$
DECLARE
  revision VARCHAR;
  statement VARCHAR;
  invalid_revision EXCEPTION (-20002, 'Expected one main branch with a full Git commit hash.');
BEGIN
  -- SHOW has no WHERE clause, so its output is filtered through RESULT_SCAN.
  SHOW GIT BRANCHES LIKE 'main' IN GIT REPOSITORY SNOWFLAKE_EXAMPLE.GIT_REPOS.RESTAURANT_RECOVERY_REPO;
  -- LIKE is a pattern, so it can match more than one branch name; MAX plus
  -- the exact-name predicate collapses that to a single deterministic value.
  SELECT MAX("commit_hash") INTO :revision FROM TABLE(RESULT_SCAN(LAST_QUERY_ID())) WHERE "name" = 'main';
  -- Validate the shape before interpolating it. The revision is about to be
  -- concatenated into an executed statement, so requiring 40 hex characters
  -- is what keeps that concatenation from being an injection point.
  IF (revision IS NULL OR NOT REGEXP_LIKE(revision, '[0-9a-f]{40}')) THEN
    RAISE invalid_revision;
  END IF;
  -- The statement is built dynamically because a stage path cannot be
  -- parameterised. The revision is passed onward via USING as well, so the
  -- deployment scripts can build their own stage paths from it.
  statement := 'EXECUTE IMMEDIATE FROM @SNOWFLAKE_EXAMPLE.GIT_REPOS.RESTAURANT_RECOVERY_REPO/commits/'
    || revision || '/sql/deploy.sql USING (revision => ''' || revision || ''')';
  EXECUTE IMMEDIATE :statement;
  RETURN 'Deployed restaurant recovery from commit ' || revision;
END;
$$;

-- 5. Final summary. Grant the reader role to whoever will use CoWork, then
--    select RESTAURANT_RECOVERY_AGENT there.
SELECT 'Deployment complete!' AS status,
       CURRENT_TIMESTAMP() AS completed_at,
       'GRANT ROLE SFE_RESTAURANT_RECOVERY_READER TO USER <your_user>; -- as SECURITYADMIN' AS next_step;
