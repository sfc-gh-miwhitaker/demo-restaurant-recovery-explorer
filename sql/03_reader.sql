-- =====================================================================
-- 03_reader.sql -- least-privilege serving role
--
-- Purpose  Create the one role a demo audience needs, holding read access to
--          exactly the objects the agent serves from and nothing else.
-- Runs     Last. Every object it references must already exist, because a
--          GRANT on a missing object fails rather than waiting.
-- Role     SECURITYADMIN owns role creation and granting; SYSADMIN owns the
--          objects. The file switches to SECURITYADMIN and switches back, so
--          the deployment leaves the session as it found it.
--
-- The design point: the skills in this project shape how the agent reasons,
-- but they are instructions, and instructions can be talked around. This
-- role is the enforcement boundary. Anything the reader role cannot select
-- is unreachable no matter what a prompt asks for -- which is why the base
-- tables, the intermediate peer views and the seeding procedure are all
-- absent from the list below. The audience is granted the evidence layer,
-- not the machinery that produces it.
-- =====================================================================

USE ROLE SECURITYADMIN;

CREATE ROLE IF NOT EXISTS SFE_RESTAURANT_RECOVERY_READER
  COMMENT = 'DEMO: Restaurant recovery serving access (Expires: 2026-10-22)';
-- Granted to SYSADMIN so the deployer can test as the audience sees it, and
-- so the role sits under the standard hierarchy rather than floating loose.
GRANT ROLE SFE_RESTAURANT_RECOVERY_READER TO ROLE SYSADMIN;

-- Required to call any Cortex Agent. Without this database role the agent is
-- visible but not runnable, which is a confusing failure to diagnose.
GRANT DATABASE ROLE SNOWFLAKE.CORTEX_AGENT_USER TO ROLE SFE_RESTAURANT_RECOVERY_READER;

-- Traversal only. USAGE on a database or schema grants no data access by
-- itself; each object below still has to be granted explicitly.
GRANT USAGE ON DATABASE SNOWFLAKE_EXAMPLE TO ROLE SFE_RESTAURANT_RECOVERY_READER;
GRANT USAGE ON SCHEMA SNOWFLAKE_EXAMPLE.RESTAURANT_RECOVERY TO ROLE SFE_RESTAURANT_RECOVERY_READER;
GRANT USAGE ON SCHEMA SNOWFLAKE_EXAMPLE.SEMANTIC_MODELS TO ROLE SFE_RESTAURANT_RECOVERY_READER;
-- Compute. Scoped to this demo's warehouse, so its cost is attributable and
-- its 120-second statement timeout applies to everything the audience runs.
GRANT USAGE ON WAREHOUSE SFE_RESTAURANT_RECOVERY_WH TO ROLE SFE_RESTAURANT_RECOVERY_READER;

GRANT USAGE ON AGENT SNOWFLAKE_EXAMPLE.RESTAURANT_RECOVERY.RESTAURANT_RECOVERY_AGENT TO ROLE SFE_RESTAURANT_RECOVERY_READER;

-- Semantic views need SELECT to query and REFERENCES so the agent's Cortex
-- Analyst tools can read their metadata to plan a query.
GRANT SELECT, REFERENCES ON SEMANTIC VIEW SNOWFLAKE_EXAMPLE.SEMANTIC_MODELS.SV_RESTAURANT_RECOVERY_PERFORMANCE TO ROLE SFE_RESTAURANT_RECOVERY_READER;
GRANT SELECT, REFERENCES ON SEMANTIC VIEW SNOWFLAKE_EXAMPLE.SEMANTIC_MODELS.SV_RESTAURANT_RECOVERY_OPERATIONS TO ROLE SFE_RESTAURANT_RECOVERY_READER;
GRANT SELECT, REFERENCES ON SEMANTIC VIEW SNOWFLAKE_EXAMPLE.SEMANTIC_MODELS.SV_RESTAURANT_RECOVERY_COMPARISONS TO ROLE SFE_RESTAURANT_RECOVERY_READER;

-- The three evidence views, for verifying an answer directly in SQL.
-- Note what is NOT here: PERFORMANCE, OPERATIONS and the other base tables,
-- where an unpaired query could compare mismatched dates or count an
-- unobserved cell as zero; and PRE_PERIOD_FEATURES / PEER_SELECTION /
-- WINDOW_OUTCOMES, the intermediate steps, where a peer set could be rebuilt
-- by hand with the withholding rules left out.
GRANT SELECT ON VIEW SNOWFLAKE_EXAMPLE.RESTAURANT_RECOVERY.PAIRED_PERFORMANCE TO ROLE SFE_RESTAURANT_RECOVERY_READER;
GRANT SELECT ON VIEW SNOWFLAKE_EXAMPLE.RESTAURANT_RECOVERY.OPERATIONS_EVIDENCE TO ROLE SFE_RESTAURANT_RECOVERY_READER;
GRANT SELECT ON VIEW SNOWFLAKE_EXAMPLE.RESTAURANT_RECOVERY.COMPARISON_EVIDENCE TO ROLE SFE_RESTAURANT_RECOVERY_READER;

-- READ, not WRITE: the agent loads its skill files from this stage and must
-- never be able to modify the instructions it runs under.
GRANT READ ON STAGE SNOWFLAKE_EXAMPLE.RESTAURANT_RECOVERY.RELEASE_FILES TO ROLE SFE_RESTAURANT_RECOVERY_READER;

USE ROLE SYSADMIN;
