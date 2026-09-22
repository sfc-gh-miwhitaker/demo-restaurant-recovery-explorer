-- =====================================================================
-- deploy_all.sql -- the one entry point an operator runs
--
-- Purpose  Connect the account to the public Git repository, then hand off
--          to sql/deploy.sql at a pinned commit. This file is the only part
--          of the deployment that is pasted in by hand; everything after it
--          runs from source inside Snowflake.
-- Run in   A Snowsight worksheet, as a role that can reach ACCOUNTADMIN.
-- Inputs   Set both before running, as SQL variables:
--            RR_EXPECTED_ACCOUNT = 'MYORG.MYACCOUNT'   -- the intended target
--            RR_CONFIRM          = 'DEPLOY'            -- explicit consent
-- Creates  An API integration and Git repository (kept on teardown), the
--          warehouse, then everything in sql/deploy.sql.
-- Note     It deploys whatever is on the repository's main branch right now.
--          Local edits that have not been pushed will not appear in the
--          account, and redeploying replaces the agent, which resets its
--          version history.
-- =====================================================================

-- ACCOUNTADMIN is needed only for the API integration; the file drops back to
-- SYSADMIN as soon as that is done, and every object the demo owns is created
-- as SYSADMIN.
USE ROLE ACCOUNTADMIN;

-- Two independent confirmations, both supplied by the operator. Neither is
-- inferred from the session: a deployment should be something a person chose,
-- not something that followed from whichever connection happened to be open.
EXECUTE IMMEDIATE $$
DECLARE
  invalid_confirmation EXCEPTION (-20001, 'Set RR_CONFIRM to DEPLOY before deployment.');
  invalid_target EXCEPTION (-20003, 'Set RR_EXPECTED_ACCOUNT to the intended ORGANIZATION.ACCOUNT.');
BEGIN
  -- The named target must match this session exactly, and Snowhouse is
  -- refused outright -- it is Snowflake's internal telemetry account, never
  -- a demo target. sql/00_guard.sql repeats this check on the far side of
  -- the Git handoff, where it also looks for object collisions.
  IF ($RR_EXPECTED_ACCOUNT IS NULL OR UPPER($RR_EXPECTED_ACCOUNT) <> (CURRENT_ORGANIZATION_NAME() || '.' || CURRENT_ACCOUNT_NAME())
      OR CURRENT_ACCOUNT_NAME() ILIKE '%SNOWHOUSE%') THEN
    RAISE invalid_target;
  END IF;
  IF ($RR_CONFIRM IS NULL OR $RR_CONFIRM <> 'DEPLOY') THEN
    RAISE invalid_confirmation;
  END IF;
END;
$$;

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
CREATE WAREHOUSE IF NOT EXISTS SFE_RESTAURANT_RECOVERY_WH
  WAREHOUSE_SIZE = 'XSMALL' AUTO_SUSPEND = 60 AUTO_RESUME = TRUE
  INITIALLY_SUSPENDED = TRUE STATEMENT_TIMEOUT_IN_SECONDS = 120
  COMMENT = 'DEMO: Restaurant recovery compute (Expires: 2026-10-22)';
USE WAREHOUSE SFE_RESTAURANT_RECOVERY_WH;

-- Pull the current state of the remote into the clone.
ALTER GIT REPOSITORY SNOWFLAKE_EXAMPLE.GIT_REPOS.RESTAURANT_RECOVERY_REPO FETCH;

-- Resolve main to a commit hash, then run the deployment from that commit.
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

-- Demo objects should not outlive their review date. This final select makes
-- the expiry visible in the deployment output rather than leaving it buried
-- in object comments, so a stale demo announces itself when redeployed.
SELECT '2026-10-22'::DATE AS expiration_date,
       DATEDIFF(day, CURRENT_DATE(), '2026-10-22'::DATE) AS days_remaining,
       IFF(CURRENT_DATE() > '2026-10-22'::DATE, 'REVIEW DUE', 'DEMO') AS demo_status;
