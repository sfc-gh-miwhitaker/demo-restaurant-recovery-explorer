/*==============================================================================
TEARDOWN ALL - Restaurant Recovery Explorer
Pair-programmed by SE Community + Cortex Code | Expires: 2026-10-22
INSTRUCTIONS: Open in Snowsight -> Click "Run All"

Drops     The RESTAURANT_RECOVERY schema and everything in it, the three
          SV_RESTAURANT_RECOVERY_* semantic views, RESTAURANT_RECOVERY_AGENT,
          SFE_RESTAURANT_RECOVERY_WH, and the SFE_RESTAURANT_RECOVERY_READER
          role including its assignments.
Keeps     SNOWFLAKE_EXAMPLE, SEMANTIC_MODELS and GIT_REPOS are shared with other
          demos and are never dropped here. The Git clone and API integration
          survive too, so redeploying does not have to rebuild them.
Requires  A role that can reach SYSADMIN and SECURITYADMIN.
Rebuild   Run deploy_all.sql again.

Every statement is IF EXISTS, so a partial deployment tears down cleanly and the
script is safe to re-run. It includes a few objects from earlier versions of
this project (DEPLOY_ASSETS, CSV_INPUT) so that an account deployed from an
older revision still ends up empty. Dropped table storage can remain under Time
Travel and Fail-safe.

There is no confirmation prompt: opening this file and clicking Run All is the
confirmation. What protects other people's work is the object namespace -- every
name below is specific to this demo -- and RESTRICT on the schema drop.
==============================================================================*/

USE ROLE SYSADMIN;

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

SELECT 'Teardown complete!' AS status,
       CURRENT_TIMESTAMP() AS completed_at,
       'SNOWFLAKE_EXAMPLE, SEMANTIC_MODELS, GIT_REPOS and the Git integration were preserved.' AS preserved;