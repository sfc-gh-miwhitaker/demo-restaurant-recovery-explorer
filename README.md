# Restaurant Recovery Explorer

Pair-programmed by SE Community + Cortex Code

A CoWork-only demonstration of evidence-backed restaurant performance analysis.
The agent investigates guest changes, separates lifecycle effects, compares
pre-period peers, and proposes tests without claiming to have proven a cause.
All runtime observations are fictional. No customer data is deployed.

![Expires](https://img.shields.io/badge/Expires-2026--10--22-orange)

## Quick Start

Use Python 3.11+, Snowflake CLI (`snow`) 3.24.1+ and Cortex CLI with agent-studio.
Configure a named demo connection with default role SYSADMIN and permission to
use SECURITYADMIN. Keep credentials in the CLI credential store, not this project.

Set the target once in your terminal (values are prompted, not stored in source):

```bash
read -r -p 'Demo connection name: ' DEMO_CONNECTION
read -r -p 'Expected organization: ' DEMO_ORG
read -r -p 'Expected account name: ' DEMO_ACCOUNT
read -r -p 'User to receive the reader role: ' DEMO_USER
```

Preview, then deploy:

```bash
bash deploy_all.sh --connection "$DEMO_CONNECTION" --organization "$DEMO_ORG" --account "$DEMO_ACCOUNT"
bash deploy_all.sh --connection "$DEMO_CONNECTION" --organization "$DEMO_ORG" --account "$DEMO_ACCOUNT" --reader-user "$DEMO_USER" --apply
```

Run the prompts in Bash (`bash` first if your shell is zsh). Open CoWork in that
account and select `RESTAURANT_RECOVERY_AGENT`. [Plain-language overview](ELI5.md).
The wrapper is packaged and locally tested; a live teardown/redeploy round-trip
has not been run. [Audit and remaining release gates](docs/06-APPLYRULES-AUDIT.md).

## Architecture

Seeded daily observations -> canonical tables -> deterministic SQL views ->
semantic views -> skill-guided Cortex Agent -> CoWork.

CoCo is the engineering interface. There is no local web application, map server,
Node.js dependency, or Streamlit deployment.

## Directory

- `sql/`: resource setup, staged CSV loading, analytical views, and reader grants.
- `cortex_project/`: tracked semantic-view and agent specifications.
- `skills/`: agent runtime investigation and prospective test-design instructions.
- `.claude/skills/`: project engineering and source-mapping workflows.
- `tools/`: v3 generator, mapping boundary, spec builder, and repeatable checks.
- `deploy_all.sh` / `teardown_all.sh`: complete, explicit-target lifecycle entry points.
- `deploy_all.sql` / `teardown_all.sql`: SQL orchestration and exact drop manifest.
- `docs/04-COWORK-CONTRACT.md`: current grains, units, matching rules and coverage.
- `docs/05-COWORK-ACCEPTANCE.md`: measured validation and remaining limitations.
- `local/`: optional ignored output directory, created only by local development commands.

## Local Checks

Run from this directory with Python 3.11 or later:

```bash
python3 -B -m unittest discover -s tools -p 'test_cowork.py'
python3 -B -m unittest discover -s tools -p 'test_mapping.py'
python3 -B -m unittest discover -s tools -p 'test_lifecycle.py'
```

Regenerate the current synthetic release when needed:

```bash
python3 tools/generate_cowork.py --output local/cowork-v3
```

The release contains 36 restaurants, 728 business dates, four dayparts and three
channels. Its as-of date is 2026-09-14. Informational review date: 2026-10-22.

## Cloud Boundary

The demo has been deployed and API-tested in an explicitly approved demo account.
Never deploy to the IDE's active account implicitly. Cloud scripts and API checks
require an explicitly selected connection, Snowflake CLI and Cortex CLI. API
checks consume credits; they are not part of the local unit-test commands above.

The deploy wrapper checks target identity, demo markers, existing objects and
release provenance before writes. It generates six synthetic CSVs, uploads only
those CSVs and two runtime skills, loads tables, deploys views/specs and restores
reader grants. Skills use content-hashed paths. Existing agents are saved and
committed as a new live version, not dropped. This is version activation inside
the selected account, not external publication. Omit `--reader-user` to skip a
direct user assignment; the reader role is still granted to SYSADMIN.

Rerunning deployment replaces the contents of all six dedicated synthetic tables
within one DML transaction. It does not append duplicate observations. DDL and
agent/grant changes are not a single transaction. A failed command stops later
steps; fix the cause and rerun. Existing conversations can see a mixed release
during deployment: use a quiet demo window. There is no automatic rollback.

`deploy_all.sql` alone is not a complete deployment: the wrapper stages data first
and handles skills, agent-studio and grants afterward. Do not run it directly.

## Cleanup

Preview the deletion scope, optionally run read-only checks, then apply:

```bash
bash teardown_all.sh --connection "$DEMO_CONNECTION" --organization "$DEMO_ORG" --account "$DEMO_ACCOUNT"
bash teardown_all.sh --connection "$DEMO_CONNECTION" --organization "$DEMO_ORG" --account "$DEMO_ACCOUNT" --check
bash teardown_all.sh --connection "$DEMO_CONNECTION" --organization "$DEMO_ORG" --account "$DEMO_ACCOUNT" --apply
```

Teardown removes the named agent, three semantic views, seven analytical views,
six tables, stage and its files, file format, project schema, warehouse and reader
role (including its assignments). It preserves the shared database and semantic
schema, unrelated objects and local evidence. The project schema uses RESTRICT,
not CASCADE; unexpected resources require review. Absent schemas are skipped.
Read-only checks may resume the warehouse and consume credits. Preview makes no
connections. No flag defaults to applying changes. Do not run concurrent lifecycle
commands or repurpose these dedicated resources for customer data.

Deploy again with the same command to restore the demo. Local files are required;
cloud teardown does not remove the source needed for redeployment. Snowflake Time
Travel/Fail-safe can retain dropped table storage according to account policy.

## Development Tools

CoCo uses [AGENTS.md](AGENTS.md) and `.claude/skills/` for project engineering and
mapping rules. `tools/lifecycle.py` orchestrates Snowflake CLI and agent-studio;
local generation and lifecycle tests use Python's standard library. Optional
`tools/verify_cowork.py` uses PyYAML when decoding CLI YAML output. No Node.js or
local web server is required. Credentials and account-specific evidence stay out
of the shareable source package.

## Useful Questions

- What changed in Mesa Vale guest occasions over the eight weeks ending September 13, 2026?
- Exclude closures, then openings. How does the answer change?
- Compare R101 and R103 breakfast labor and guest changes. What contradicts a simple labor explanation?
- Why is R312's peer gap unavailable?
- What would a prospective staffing test need before we could measure effectiveness or ROI?

## Limits

Guest occasions are guests served per occasion, not checks or unique customers.
Missing observations are not zero. Peer gaps are descriptive, not recoverable
demand or causal effects. Loyalty, profit, real customer findings, and campaign
execution are unavailable. Customer mappings remain proposals until definitions,
cardinalities, reconciliation and activation are approved.

API checks are recorded separately from UI checks. CoWork browser testing is not
claimed. See the acceptance checkpoint before presenting this as handoff-ready.

## Publication Preparation

Private execution traces, local account configuration, historical plans and build
state are not part of this source directory. Do not add them to a public repository.
Run the offline source scan before publishing:

```bash
python3 -B tools/check_public_source.py
```

The scan checks hidden files too and reports locations without printing matched
values. It is a safeguard, not a guarantee or a substitute for reviewing the final
Git diff. A repository URL is not required for sanitization. The Git-backed SQL
deployment replacement is still pending; the commands above describe the existing
wrapper, not the proposed replacement. Repository URL and license selection are
deferred until publication. No public repository has been created.