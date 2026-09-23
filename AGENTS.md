# Restaurant Recovery Explorer

<!-- Global rules apply automatically via ~/.claude/CLAUDE.md; keep this file project-specific. -->

Pair-programmed by SE Community + Cortex Code

## Architecture

`tools/generate_cowork.py` produces fictional daily observations.
`sql/02_analytics.sql` owns deterministic evidence and matching.
`sql/04_semantics.sql` and `sql/05_agent.sql` are the only source of the semantic
view and agent specifications; edit them directly, with agent-studio guidance.
`skills/` guides the business conversation; CoWork is the sole business interface.
`deploy_all.sql` connects public Git, pins a commit and runs the whole deployment
from that revision; `teardown_all.sql` reverses it. Both are pasted into a
Snowsight worksheet and run with Run All, with no variables to set first.
`tools/native_runtime.py` runs there, not on the deployer's laptop.

## Visiting From Another Repository?

This is a synthetic reference demo, Apache 2.0 licensed. To stand it up, copy
`deploy_all.sql` into a Snowsight worksheet and click Run All -- see the README
Quick Start. Before mapping any real restaurant source onto this contract, load
the `restaurant-source-mapping` skill; do not infer customer semantics from
column names. The rules below are for anyone editing this repository.

## Project Rules

- Follow `docs/04-COWORK-CONTRACT.md`, not the removed weekly map-app contract.
- Keep guest occasions, checks and unique customers distinct.
- Exclude both sides of incomplete pairs. Never multiply operations over channels.
- Select peers from pre-period features only; withhold invalid gaps without rematching.
- Separate lifecycle contributions, descriptive comparisons, hypotheses and tests.
- Generator labels and expected answers must not enter runtime analytical tools.
- Customer-specific metadata stays outside the generic package and synthetic runtime.
- Always name the approved demo connection; the IDE's active account is not an implicit deployment target.
- No additional API evaluation, browser attempts, publication or customer deployment is implied by cleanup work.

## Local Verification

```bash
python3 -B -m unittest discover -s tools -p 'test_cowork.py'
python3 -B -m unittest discover -s tools -p 'test_mapping.py'
python3 -B -m unittest discover -s tools -p 'test_native_deploy.py'
```

Cloud checks live in `tools/verify_cowork.py`, `tools/test_agent_api.py` and
`tools/test_agent_threads.py`; run them only for requested validation against an
explicit target. Preserve API evidence under ignored `local/` and record caveats
in `docs/05-COWORK-ACCEPTANCE.md`. Do not equate successful calls with acceptance.

Run `python3 -B tools/check_public_source.py` before preparing a public commit.
Private evidence and historical plans belong outside this project directory.
Publication URL configuration is separate from source sanitization.