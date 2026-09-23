# Restaurant Recovery Explorer

Pair-programmed by SE Community + Cortex Code

A CoWork-only demo that investigates fictional restaurant performance, separates
lifecycle effects, compares pre-period peers, and proposes tests without claiming
to have proven a cause. No customer data is included.

![Expires](https://img.shields.io/badge/Expires-2026--10--22-orange)
![License](https://img.shields.io/badge/License-Apache%202.0-blue)

## Demo Recording

A 2m 40s screen recording of the agent investigating fictional restaurant
performance in CoWork: [docs/media/cowork-demo.mp4](docs/media/cowork-demo.mp4)
(1.1 MB, H.264 640x316, no audio). The recording shows one session and is not a
validation result. See [acceptance](docs/05-COWORK-ACCEPTANCE.md).

## Quick Start

Everything runs inside Snowflake. No local Python, CLI, CSV upload or web app.

1. Open a Snowsight SQL worksheet in a demo account with Cortex Agents and Cortex
   Analyst enabled, using a role that can reach ACCOUNTADMIN and SECURITYADMIN.
2. Copy the full contents of [deploy_all.sql](deploy_all.sql) into the worksheet
   and click **Run All**. It creates the Git integration, fetches this repository,
   pins a commit, and builds the whole demo from that revision. No GitHub token is
   needed. Takes a few minutes; review the SQL before running it.
3. Grant the reader role to whoever will use CoWork, then select
   `RESTAURANT_RECOVERY_AGENT` there:

```sql
USE ROLE SECURITYADMIN;
GRANT ROLE SFE_RESTAURANT_RECOVERY_READER TO USER YOUR_USER;
```

Ensure the role CoWork runs under inherits the reader role; a user's default role
can differ from the role selected in a worksheet. No user defaults or PUBLIC
grants are changed. [Plain-language overview](ELI5.md).

To rebuild, run `deploy_all.sql` again. To remove the demo, run
[teardown_all.sql](teardown_all.sql) the same way.

## What Deployment Does

`deploy_all.sql` creates the public Git integration and clone under
`SNOWFLAKE_EXAMPLE.GIT_REPOS`, then hands off to `sql/deploy.sql` at a pinned
commit, which orchestrates the following:

- Checks the project schema and warehouse for markers so an object someone else
  owns is never quietly adopted.
- Creates the dedicated X-Small warehouse, schema, six tables and skill stage.
- Runs the seeded generator in a caller-rights Python procedure inside Snowflake.
- Validates observations, stages typed temporary tables, then replaces all six
  canonical tables in one transaction with row-count checks and rollback on error.
- Creates seven analytical views and three semantic views from checked-in specs.
- Copies only two runtime SKILL.md files into commit-specific stage directories.
- Creates or replaces the demo agent with COPY GRANTS and restores reader grants.
- Removes the deployment-only helper procedure after successful deployment.

Deployment resolves `main` to a full commit hash and pins all subsequent SQL,
imports, specifications and copied skills to that revision, so every object in
the account traces to one commit. Unpushed local edits will not appear in the
account.

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

Copy [teardown_all.sql](teardown_all.sql) into a worksheet and click **Run All**.

Teardown removes exact named project objects, its stage contents, warehouse and
reader role (including assignments). It preserves the shared database, shared
semantic schema, Git repository and API integration so you can deploy again.
The project schema uses RESTRICT, not CASCADE. An unexpected dependent object
can stop teardown after earlier drops; investigate instead of broadening deletion.
The legacy CSV format is included in cleanup for earlier installations.

To rebuild, run `deploy_all.sql` again. To fetch updated entry-point scripts
without a full redeployment:

```sql
USE ROLE SYSADMIN;
ALTER GIT REPOSITORY SNOWFLAKE_EXAMPLE.GIT_REPOS.RESTAURANT_RECOVERY_REPO FETCH;
```

Keep the Git integration and clone unless retiring the source connection too.
Dropped table storage can remain under Time Travel/Fail-safe. Warehouse
auto-suspend does not cap Cortex service spend; generation, querying, AI and file
copies consume credits.

## Architecture And Files

Seeded observations -> canonical tables -> deterministic SQL evidence -> semantic
views -> skill-guided Cortex Agent -> CoWork.

- `deploy_all.sql` / `teardown_all.sql`: worksheet lifecycle entry points, each
  self-contained and run with Snowsight's Run All.
- `sql/deploy.sql`: commit-pinned setup, generation, views, skills and access.
- `sql/04_semantics.sql` / `sql/05_agent.sql`: the only source of the semantic
  view and agent specifications, inline as JSON-compatible payloads.
- `tools/native_runtime.py`: Snowflake-executed generation and spec deployment.
- `tools/generate_cowork.py`: reproducible fictional observations and validation.
- `skills/`: runtime investigation and prospective test-design workflows.
- `.claude/skills/`: project engineering and source-mapping workflows.
- `docs/04-COWORK-CONTRACT.md`: grains, measures, completeness and peer matching.
- `docs/05-COWORK-ACCEPTANCE.md`: measured results and remaining limitations.
- `docs/06-DATA-MODEL-DIAGRAMS.md`: grain, lineage, withholding and mapping diagrams.
- `docs/media/cowork-demo.mp4`: screen recording of one CoWork investigation session.

## Development Tools

CoCo uses [AGENTS.md](AGENTS.md) and `.claude/skills/`. Python 3.11+ is optional for
local development tests, not required on the deployer's computer:

```bash
python3 -B -m unittest discover -s tools -p 'test_*.py'
python3 -B tools/check_public_source.py
```

The API harnesses are opt-in command-line programs; importing them during unit
test discovery does not call Snowflake. Semantic view and agent specifications are
edited directly in `sql/04_semantics.sql` and `sql/05_agent.sql`; there is no
separate spec-generation step. SQL parity/API checks require an explicit demo
connection and incur credits. Do not run them against production.

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
Browser behavior and API invocation success are not answer acceptance: review the
evidence and SQL behind any conclusion before repeating it.

Private plans, API traces, account configuration and customer evidence are outside
this source directory. Follow [SECURITY.md](SECURITY.md) and review the final Git
diff before publishing. The source scan is a safeguard, not a guarantee.

## License

Licensed under the Apache License 2.0. See [LICENSE](LICENSE).

## References

- [Git repository operations](https://docs.snowflake.com/en/developer-guide/git/git-operations)
- [EXECUTE IMMEDIATE FROM](https://docs.snowflake.com/en/sql-reference/sql/execute-immediate-from)
- [COPY FILES](https://docs.snowflake.com/en/sql-reference/sql/copy-files)
- [Semantic-view YAML deployment](https://docs.snowflake.com/en/sql-reference/stored-procedures/system_create_semantic_view_from_yaml)
- [CREATE AGENT and COPY GRANTS](https://docs.snowflake.com/en/sql-reference/sql/create-agent)
