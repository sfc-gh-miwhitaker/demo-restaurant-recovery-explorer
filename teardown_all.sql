-- =====================================================================
-- teardown_all.sql -- remove the demo, leave the shared containers
--
-- Purpose  Drop everything deploy_all.sql created for this project, in
--          reverse dependency order, so no orphaned object is left holding
--          a grant or a warehouse.
-- Run in   A Snowsight worksheet, as a role that can reach SECURITYADMIN.
-- Inputs   RR_EXPECTED_ACCOUNT = 'MYORG.MYACCOUNT'
--          RR_CONFIRM          = 'TEARDOWN'   -- a different word from
--                                             -- DEPLOY, deliberately: the
--                                             -- two scripts must never be
--                                             -- runnable from one setting.
-- Kept     SNOWFLAKE_EXAMPLE, SEMANTIC_MODELS and GIT_REPOS are shared with
--          other demos and are never dropped here. The Git clone survives
--          too, so redeployment does not need the API integration rebuilt.
--
-- Every statement is IF EXISTS, so a partial deployment tears down cleanly
-- and the script is safe to re-run. It includes a few objects from earlier
-- versions of this project (DEPLOY_ASSETS, CSV_INPUT) so that an account
-- deployed from an older revision still ends up empty.
-- =====================================================================

USE ROLE SYSADMIN;
-- Same two-part confirmation as deployment. Teardown is the more destructive
-- of the two, and the target check is what stops a copied worksheet from
-- dropping objects in the wrong account.
EXECUTE IMMEDIATE $$
DECLARE
  invalid_confirmation EXCEPTION (-20005, 'Set RR_CONFIRM to TEARDOWN before removing the demo.');
  invalid_target EXCEPTION (-20003, 'Target mismatch. Set RR_EXPECTED_ACCOUNT to the intended ORGANIZATION.ACCOUNT.');
BEGIN
  IF ($RR_EXPECTED_ACCOUNT IS NULL OR UPPER($RR_EXPECTED_ACCOUNT) <> (CURRENT_ORGANIZATION_NAME() || '.' || CURRENT_ACCOUNT_NAME())
      OR CURRENT_ACCOUNT_NAME() ILIKE '%SNOWHOUSE%') THEN RAISE invalid_target; END IF;
  IF ($RR_CONFIRM IS NULL OR $RR_CONFIRM <> 'TEARDOWN') THEN RAISE invalid_confirmation; END IF;
END;
$$;

-- Order matters from here down: dependents before their dependencies.
-- Helper procedures first -- they should already be gone, since deploy.sql
-- drops SEED_DEMO immediately after use, but an interrupted deployment can
-- leave one behind.
DROP PROCEDURE IF EXISTS SNOWFLAKE_EXAMPLE.RESTAURANT_RECOVERY.DEPLOY_ASSETS(VARCHAR, VARCHAR);
DROP PROCEDURE IF EXISTS SNOWFLAKE_EXAMPLE.RESTAURANT_RECOVERY.SEED_DEMO();
-- The agent, then the semantic views it references.
DROP AGENT IF EXISTS SNOWFLAKE_EXAMPLE.RESTAURANT_RECOVERY.RESTAURANT_RECOVERY_AGENT;
DROP SEMANTIC VIEW IF EXISTS SNOWFLAKE_EXAMPLE.SEMANTIC_MODELS.SV_RESTAURANT_RECOVERY_PERFORMANCE;
DROP SEMANTIC VIEW IF EXISTS SNOWFLAKE_EXAMPLE.SEMANTIC_MODELS.SV_RESTAURANT_RECOVERY_OPERATIONS;
DROP SEMANTIC VIEW IF EXISTS SNOWFLAKE_EXAMPLE.SEMANTIC_MODELS.SV_RESTAURANT_RECOVERY_COMPARISONS;
-- Evidence views, dropped in reverse build order: COMPARISON_EVIDENCE reads
-- WINDOW_OUTCOMES and PEER_SELECTION, which read PRE_PERIOD_FEATURES and
-- ANALYSIS_WINDOWS, and OPERATIONS_EVIDENCE reads PAIRED_PERFORMANCE.
DROP VIEW IF EXISTS SNOWFLAKE_EXAMPLE.RESTAURANT_RECOVERY.COMPARISON_EVIDENCE;
DROP VIEW IF EXISTS SNOWFLAKE_EXAMPLE.RESTAURANT_RECOVERY.WINDOW_OUTCOMES;
DROP VIEW IF EXISTS SNOWFLAKE_EXAMPLE.RESTAURANT_RECOVERY.PEER_SELECTION;
DROP VIEW IF EXISTS SNOWFLAKE_EXAMPLE.RESTAURANT_RECOVERY.PRE_PERIOD_FEATURES;
DROP VIEW IF EXISTS SNOWFLAKE_EXAMPLE.RESTAURANT_RECOVERY.ANALYSIS_WINDOWS;
DROP VIEW IF EXISTS SNOWFLAKE_EXAMPLE.RESTAURANT_RECOVERY.OPERATIONS_EVIDENCE;
DROP VIEW IF EXISTS SNOWFLAKE_EXAMPLE.RESTAURANT_RECOVERY.PAIRED_PERFORMANCE;
-- Base tables, then the stage and the schema itself.
DROP TABLE IF EXISTS SNOWFLAKE_EXAMPLE.RESTAURANT_RECOVERY.PERFORMANCE;
DROP TABLE IF EXISTS SNOWFLAKE_EXAMPLE.RESTAURANT_RECOVERY.OPERATIONS;
DROP TABLE IF EXISTS SNOWFLAKE_EXAMPLE.RESTAURANT_RECOVERY.EVENTS;
DROP TABLE IF EXISTS SNOWFLAKE_EXAMPLE.RESTAURANT_RECOVERY.CALENDAR;
DROP TABLE IF EXISTS SNOWFLAKE_EXAMPLE.RESTAURANT_RECOVERY.ROSTER;
DROP TABLE IF EXISTS SNOWFLAKE_EXAMPLE.RESTAURANT_RECOVERY.RELEASE_METADATA;
DROP FILE FORMAT IF EXISTS SNOWFLAKE_EXAMPLE.RESTAURANT_RECOVERY.CSV_INPUT;
DROP STAGE IF EXISTS SNOWFLAKE_EXAMPLE.RESTAURANT_RECOVERY.RELEASE_FILES;
-- RESTRICT, and never the recursive alternative: if anything unexpected is
-- still in the schema, the drop fails and a human looks at it rather than
-- losing someone else's work. tools/test_native_deploy.py asserts that the
-- recursive keyword appears nowhere in this file.
DROP SCHEMA IF EXISTS SNOWFLAKE_EXAMPLE.RESTAURANT_RECOVERY RESTRICT;
DROP WAREHOUSE IF EXISTS SFE_RESTAURANT_RECOVERY_WH;
-- The role is owned by SECURITYADMIN, so dropping it needs that role. Last,
-- because dropping it earlier would revoke access mid-teardown.
USE ROLE SECURITYADMIN;
DROP ROLE IF EXISTS SFE_RESTAURANT_RECOVERY_READER;