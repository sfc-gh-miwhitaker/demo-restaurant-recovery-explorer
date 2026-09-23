---
name: restaurant-recovery-explorer
description: Build and extend the CoWork restaurant recovery demo, synthetic daily observations, deterministic evidence, semantic views, runtime skills, and source mapping.
---

# Restaurant Recovery Explorer

Pair-programmed by SE Community + Cortex Code

## Purpose

Investigate restaurant performance with synthetic evidence and explicit limits.
CoWork is the business interface; CoCo handles engineering and source mapping.

## Architecture

Seeded observations -> canonical tables -> SQL evidence -> semantic views ->
Cortex Agent with investigation and test-design skills -> CoWork.

## Key Files

- `docs/04-COWORK-CONTRACT.md`: daily grains, units, completeness and matching.
- `tools/generate_cowork.py`: reproducible v3 fictional observations.
- `tools/mapping.py`: small executable mapping boundary, not a production adapter.
- `sql/02_analytics.sql`: paired contributions, operations and frozen peers.
- `sql/04_semantics.sql` and `sql/05_agent.sql`: inline semantic view and agent
  specifications, the only source for both.
- `deploy_all.sql` and `teardown_all.sql`: self-contained Run All entry points;
  deployment connects Git and pins a commit before running anything.
- `tools/native_runtime.py`: caller-rights helper for generation and spec loading.
- `skills/`: instruction-only runtime workflows.
- `docs/05-COWORK-ACCEPTANCE.md`: validation evidence and limitations.

## Extension Playbook

1. Read the current contract and affected source before editing.
2. Add deterministic calculations and boundary tests before narrative guidance.
3. Preserve grains, paired exclusions and pre-period-only selection.
4. Use the source-mapping skill for customer adaptation; keep customer details confidential.
5. Use agent-studio for semantic and agent changes, with an explicit approved target.
6. Run local tests. Run paid API checks only when requested; retain evidence and failures.

## Snowflake Objects

Project schema `SNOWFLAKE_EXAMPLE.RESTAURANT_RECOVERY`; warehouse
`SFE_RESTAURANT_RECOVERY_WH`; three `SV_RESTAURANT_RECOVERY_*` semantic views in
`SNOWFLAKE_EXAMPLE.SEMANTIC_MODELS`; project agent `RESTAURANT_RECOVERY_AGENT`.
Reader role `SFE_RESTAURANT_RECOVERY_READER`. No account is an implicit target.
Git clone in `SNOWFLAKE_EXAMPLE.GIT_REPOS` survives project teardown.

## Gotchas

Skills guide behavior, not security. Guests are not checks or unique people.
Hours are all-channel denominators. Missing data is not inactivity. Similarity
peers are not automatically experiment controls. A matched gap is not a causal
effect. CoWork UI is unverified; do not restart browser or evaluation loops unless
requested. The old Next.js application and v1/v2 artifacts have been removed.
Native redeployment replaces the demo agent and resets its version history.