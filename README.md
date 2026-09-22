# Restaurant Recovery Explorer

Pair-programmed by SE Community + Cortex Code

A CoWork-only demo that investigates fictional restaurant performance, separates
lifecycle effects, compares pre-period peers, and proposes tests without claiming
to have proven a cause. No customer data is included.

![Expires](https://img.shields.io/badge/Expires-2026--10--22-orange)

## Quick Start

Deploy from a Snowsight SQL worksheet. No local Python installation, CLI, CSV
upload or web application is required. Python generation runs inside Snowflake.

1. Choose a dedicated demo account with Cortex Agents, Cortex Analyst and Python
   stored procedures available. The deploying administrator must be able to use
   ACCOUNTADMIN, SYSADMIN and SECURITYADMIN. Review the SQL before running it.
2. Run [bootstrap.sql](bootstrap.sql) once. It creates a narrowly scoped public
   Git API integration and repository clone. No GitHub token is needed.
3. In the same worksheet, set the intended account explicitly, then deploy:

```sql
SET RR_EXPECTED_ACCOUNT = 'YOUR_ORGANIZATION.YOUR_ACCOUNT';
SET RR_CONFIRM = 'DEPLOY';
EXECUTE IMMEDIATE FROM
  @SNOWFLAKE_EXAMPLE.GIT_REPOS.RESTAURANT_RECOVERY_REPO/branches/main/deploy_all.sql;
```

The account value is a safety confirmation, not a credential. Replace it with
your intended account name; do not compute it automatically from the session.
Deployment fetches `main`, resolves a full commit hash, and pins all subsequent
SQL, imports, specifications and copied skills to that revision. Run the same
command to redeploy after merging a source change.

4. Grant the reader role to your chosen user, then select
   `RESTAURANT_RECOVERY_AGENT` in CoWork:

```sql
USE ROLE SECURITYADMIN;
GRANT ROLE SFE_RESTAURANT_RECOVERY_READER TO USER YOUR_USER;
```

No user defaults or PUBLIC grants are changed. Ensure the role used by CoWork
inherits the reader role; user default-role behavior can differ from worksheet
role selection. [Plain-language overview](ELI5.md).

**Validation status:** the native Git deployment is newly packaged, not yet
cloud-executed end to end. These local changes must be committed and pushed before
Snowflake can fetch them. Prior API tests validate the analytical demo, not this
new deployment path. See [acceptance](docs/05-COWORK-ACCEPTANCE.md).

## What Deployment Does

`bootstrap.sql` creates the public Git integration and clone under
`SNOWFLAKE_EXAMPLE.GIT_REPOS`. `deploy_all.sql` orchestrates the following:

- Checks explicit account confirmation and project schema/warehouse markers.
- Creates the dedicated X-Small warehouse, schema, six tables and skill stage.
- Runs the seeded generator in a caller-rights Python procedure inside Snowflake.
- Validates observations, stages typed temporary tables, then replaces all six
  canonical tables in one transaction with row-count checks and rollback on error.
- Creates seven analytical views and three semantic views from checked-in specs.
- Copies only two runtime SKILL.md files into commit-specific stage directories.
- Creates or replaces the demo agent with COPY GRANTS and restores reader grants.
- Removes the deployment-only helper procedure after successful deployment.

The release has 36 fictional restaurants, 728 dates, four dayparts and three
channels. Its fixed as-of date is 2026-09-14, independent of today's date.

**Reruns replace synthetic data and reset the demo agent's version history.** This
is rebuildable demo infrastructure, not an in-place production release manager.
Use a quiet demo window: the complete DDL/data/agent sequence is not atomic.
Failures stop execution; inspect the error, fix the cause and rerun. No automatic
rollback covers DDL or agent replacement. Do not run deployments concurrently or
repurpose these dedicated names for real data. Same release IDs are not proof
that someone has not manually altered a table.

## Remove And Rebuild

Use a worksheet in the intended account:

```sql
SET RR_EXPECTED_ACCOUNT = 'YOUR_ORGANIZATION.YOUR_ACCOUNT';
SET RR_CONFIRM = 'TEARDOWN';
EXECUTE IMMEDIATE FROM
  @SNOWFLAKE_EXAMPLE.GIT_REPOS.RESTAURANT_RECOVERY_REPO/branches/main/teardown_all.sql;
```

Teardown removes exact named project objects, its stage contents, warehouse and
reader role (including assignments). It preserves the shared database, shared
semantic schema, Git repository and API integration so you can deploy again.
The project schema uses RESTRICT, not CASCADE. An unexpected dependent object
can stop teardown after earlier drops; investigate instead of broadening deletion.
The legacy CSV format is included in cleanup for earlier installations.

To rebuild, set `RR_CONFIRM = 'DEPLOY'` and rerun the deployment command. To fetch
updated entry-point scripts before either operation:

```sql
USE ROLE SYSADMIN;
ALTER GIT REPOSITORY SNOWFLAKE_EXAMPLE.GIT_REPOS.RESTAURANT_RECOVERY_REPO FETCH;
```

Keep bootstrap resources unless retiring the source connection too. Dropped table
storage can remain under Time Travel/Fail-safe. Warehouse auto-suspend does not
cap Cortex service spend; generation, querying, AI and file copies consume credits.

## Architecture And Files

Seeded observations -> canonical tables -> deterministic SQL evidence -> semantic
views -> skill-guided Cortex Agent -> CoWork.

- `bootstrap.sql`: one-time public Git integration and clone.
- `deploy_all.sql` / `teardown_all.sql`: worksheet lifecycle entry points.
- `sql/deploy.sql`: commit-pinned setup, generation, views, skills and access.
- `tools/native_runtime.py`: Snowflake-executed generation and spec deployment.
- `tools/generate_cowork.py`: reproducible fictional observations and validation.
- `cortex_project/`: JSON-compatible YAML semantic and agent specs.
- `skills/`: runtime investigation and prospective test-design workflows.
- `.claude/skills/`: project engineering and source-mapping workflows.
- `docs/04-COWORK-CONTRACT.md`: grains, measures, completeness and peer matching.
- `docs/05-COWORK-ACCEPTANCE.md`: measured results and remaining limitations.

## Development Tools

CoCo uses [AGENTS.md](AGENTS.md) and `.claude/skills/`. Python 3.11+ is optional for
local development tests, not required on the deployer's computer:

```bash
python3 -B -m unittest discover -s tools -p 'test_*.py'
python3 -B tools/check_public_source.py
```

The API harnesses are opt-in command-line programs; importing them during unit
test discovery does not call Snowflake. `tools/build_specs.py` uses agent-studio
to regenerate tracked specs during development only. Keep its output as
JSON-compatible YAML for the native loader. SQL parity/API checks require an
explicit demo connection and incur credits. Do not run them against production.

## Useful Questions

- What changed in Mesa Vale guest occasions over the eight weeks ending September 13, 2026?
- Exclude closures, then openings. How does the answer change?
- Compare R101 and R103 breakfast labor and guest changes. What contradicts a simple labor explanation?
- Why is R312's peer gap unavailable?
- What would a prospective staffing test need before effectiveness or ROI can be measured?

## Limits And Publication

Guest occasions are not checks or unique customers. Missing observations are not
zero. Peer gaps are descriptive, not recoverable demand or causal effects.
Loyalty, profit, real customer findings and campaign execution are unavailable.
Source mappings require approved definitions and reconciliation before activation.
Browser behavior is unverified; API invocation success is not answer acceptance.

Private plans, API traces, account configuration and customer evidence are outside
this source directory. Follow [SECURITY.md](SECURITY.md) and review the final Git
diff before publishing. The source scan is a safeguard, not a guarantee.
Licensing remains a separate publication decision; no license is implied.

## References

- [Git repository operations](https://docs.snowflake.com/en/developer-guide/git/git-operations)
- [EXECUTE IMMEDIATE FROM](https://docs.snowflake.com/en/sql-reference/sql/execute-immediate-from)
- [COPY FILES](https://docs.snowflake.com/en/sql-reference/sql/copy-files)
- [Semantic-view YAML deployment](https://docs.snowflake.com/en/sql-reference/stored-procedures/system_create_semantic_view_from_yaml)
- [CREATE AGENT and COPY GRANTS](https://docs.snowflake.com/en/sql-reference/sql/create-agent)