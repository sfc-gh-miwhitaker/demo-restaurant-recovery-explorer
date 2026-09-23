-- =====================================================================
-- 01_setup.sql -- containers and canonical tables
--
-- Purpose  Create the objects the rest of the deployment writes into. Idem-
--          potent: every statement is CREATE IF NOT EXISTS, so re-running a
--          deployment never destroys loaded data.
-- Runs     First in the deployment sequence, before anything writes data.
--          Re-running adopts the objects a previous run of this same demo
--          created, which is what makes redeployment cheap.
-- Contract Column names and types are the canonical contract in
--          docs/04-COWORK-CONTRACT.md. tools/native_runtime.py compares the
--          live table schema against tools/generate_cowork.py's FIELDS and
--          refuses to load if they diverge, so renaming a column here
--          breaks the load loudly instead of shifting data quietly.
--
-- Two conventions run through every object:
--   * Every comment starts 'DEMO:' and carries an expiry date. The runtime
--     and teardown both key off that prefix to tell demo objects apart from
--     real ones.
--   * Every table carries RELEASE_ID. Fixtures are regenerated, and the
--     release column is what keeps two generations from blending into one
--     accidental result set.
-- =====================================================================

USE ROLE SYSADMIN;

-- Shared containers. Deliberately generic and NOT demo-scoped: several SE
-- demos live in SNOWFLAKE_EXAMPLE, and SEMANTIC_MODELS is a shared home for
-- semantic views. Neither is dropped on teardown of this project.
CREATE DATABASE IF NOT EXISTS SNOWFLAKE_EXAMPLE
  COMMENT = 'Shared SE demonstration database';
CREATE SCHEMA IF NOT EXISTS SNOWFLAKE_EXAMPLE.SEMANTIC_MODELS
  COMMENT = 'Shared semantic views for SE demonstrations';

-- This project's own schema. Everything below is disposable with it.
CREATE SCHEMA IF NOT EXISTS SNOWFLAKE_EXAMPLE.RESTAURANT_RECOVERY
  COMMENT = 'DEMO: Synthetic restaurant recovery (Expires: 2026-10-22)';

-- Dedicated warehouse, sized for a demo rather than for scale:
--   XSMALL                        the fixture is ~130k rows; nothing here
--                                 benefits from more compute.
--   AUTO_SUSPEND 60               a demo is idle between questions, and
--                                 idle compute is pure waste.
--   INITIALLY_SUSPENDED           creating the warehouse does not start it.
--   STATEMENT_TIMEOUT 120         a runaway agent-generated query fails fast
--                                 instead of burning credits unattended.
--                                 This is the backstop for text-to-SQL, and
--                                 the reason to give an agent its own
--                                 warehouse rather than share a general one.
CREATE WAREHOUSE IF NOT EXISTS SFE_RESTAURANT_RECOVERY_WH
  WAREHOUSE_SIZE = 'XSMALL' AUTO_SUSPEND = 60 AUTO_RESUME = TRUE
  INITIALLY_SUSPENDED = TRUE STATEMENT_TIMEOUT_IN_SECONDS = 120
  COMMENT = 'DEMO: Restaurant recovery compute (Expires: 2026-10-22)';
USE WAREHOUSE SFE_RESTAURANT_RECOVERY_WH;

-- Holds the runtime skill files, copied per Git commit so the skills the
-- agent loads are pinned to the same revision as the SQL that created it.
CREATE STAGE IF NOT EXISTS SNOWFLAKE_EXAMPLE.RESTAURANT_RECOVERY.RELEASE_FILES
  COMMENT = 'DEMO: Commit-pinned runtime skills (Expires: 2026-10-22)';

-- ROSTER -- grain: one row per restaurant.
-- OPEN_DATE and CLOSE_DATE are what make like-for-like comparison possible
-- at all; CLOSE_DATE NULL means still trading. Treating these as data rather
-- than as a hardcoded list of exceptions is why the analytics views can
-- classify lifecycle without naming a single restaurant ID.
CREATE TABLE IF NOT EXISTS SNOWFLAKE_EXAMPLE.RESTAURANT_RECOVERY.ROSTER (
  RELEASE_ID VARCHAR, RESTAURANT_ID VARCHAR, RESTAURANT_NAME VARCHAR, MARKET VARCHAR,
  FORMAT VARCHAR, OPEN_DATE DATE, CLOSE_DATE DATE
) COMMENT = 'DEMO: Fictional restaurant roster (Expires: 2026-10-22)';

-- CALENDAR -- grain: one row per business date.
-- BASELINE_DATE is the 364-day-earlier date, stored rather than computed so
-- the year-ago pairing is auditable in one place and identical everywhere.
-- COMPLETE lets a whole trading day be marked unobserved at the source.
CREATE TABLE IF NOT EXISTS SNOWFLAKE_EXAMPLE.RESTAURANT_RECOVERY.CALENDAR (
  RELEASE_ID VARCHAR, BUSINESS_DATE DATE, BASELINE_DATE DATE, WEEK_START DATE, COMPLETE BOOLEAN
) COMMENT = 'DEMO: Explicit synthetic business calendar (Expires: 2026-10-22)';

-- PERFORMANCE -- grain: restaurant x business date x daypart x channel.
-- GUESTS are guest occasions: people served on a visit. Not checks, not
-- unique customers. Three distinct ideas that get conflated constantly, so
-- CHECKS is stored separately and unique customers are simply absent -- the
-- data cannot answer a retention question and should not appear to.
-- COMPLETE FALSE with NULL measures is an unobserved cell; a genuine zero is
-- stored as 0 with COMPLETE TRUE. The difference is load-bearing.
CREATE TABLE IF NOT EXISTS SNOWFLAKE_EXAMPLE.RESTAURANT_RECOVERY.PERFORMANCE (
  RELEASE_ID VARCHAR, RESTAURANT_ID VARCHAR, BUSINESS_DATE DATE, DAYPART VARCHAR,
  CHANNEL VARCHAR, GUESTS NUMBER(18,0), CHECKS NUMBER(18,0), NET_SALES NUMBER(18,2), COMPLETE BOOLEAN
) COMMENT = 'DEMO: Fictional daily guest occasions, checks and net USD sales (Expires: 2026-10-22)';

-- OPERATIONS -- grain: restaurant x business date x daypart. No channel,
-- and that omission is the point: a restaurant opens its doors once per
-- daypart to serve all three channels at once. There is no such thing as
-- delivery open hours, so the column does not exist to be misused.
-- SERVICE_MINUTES is a mean over SERVICE_OBSERVATIONS samples; both are kept
-- so consumers can re-weight instead of averaging averages.
CREATE TABLE IF NOT EXISTS SNOWFLAKE_EXAMPLE.RESTAURANT_RECOVERY.OPERATIONS (
  RELEASE_ID VARCHAR, RESTAURANT_ID VARCHAR, BUSINESS_DATE DATE, DAYPART VARCHAR,
  OPEN_HOURS NUMBER(10,2), LABOR_HOURS NUMBER(10,2), SERVICE_MINUTES NUMBER(10,2),
  SERVICE_OBSERVATIONS NUMBER(18,0), COMPLETE BOOLEAN
) COMMENT = 'DEMO: Daily operations; never repeat hours across channels (Expires: 2026-10-22)';

-- EVENTS -- grain: one row per dated operating event.
-- A record that something was logged on a date, with a stated SOURCE. An
-- event adjacent to a decline is a lead, not a cause: it is not exposed to
-- the agent as an explanatory label, precisely so a coincidence of dates
-- cannot be presented as a finding.
CREATE TABLE IF NOT EXISTS SNOWFLAKE_EXAMPLE.RESTAURANT_RECOVERY.EVENTS (
  RELEASE_ID VARCHAR, EVENT_ID VARCHAR, RESTAURANT_ID VARCHAR, EFFECTIVE_DATE DATE,
  DAYPART VARCHAR, EVENT_TYPE VARCHAR, SOURCE VARCHAR
) COMMENT = 'DEMO: Fictional dated events; not causal labels (Expires: 2026-10-22)';

-- RELEASE_METADATA -- grain: one row per release.
-- AS_OF_DATE is the fixture's fixed "today", which is why answers must not
-- default to CURRENT_DATE. SYNTHETIC TRUE is asserted in data and checked
-- before load, so nothing real can be loaded through this path by mistake.
-- SEED makes the whole fixture reproducible from the generator alone.
CREATE TABLE IF NOT EXISTS SNOWFLAKE_EXAMPLE.RESTAURANT_RECOVERY.RELEASE_METADATA (
  RELEASE_ID VARCHAR, AS_OF_DATE DATE, CONTRACT_VERSION VARCHAR, ANALYSIS_VERSION VARCHAR,
  SYNTHETIC BOOLEAN, SEED NUMBER(18,0)
) COMMENT = 'DEMO: Release provenance (Expires: 2026-10-22)';
