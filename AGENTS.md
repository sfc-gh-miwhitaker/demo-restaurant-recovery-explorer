# Restaurant Recovery Explorer

<!-- Global rules apply automatically via ~/.claude/CLAUDE.md; keep this file project-specific. -->

Pair-programmed by SE Community + Cortex Code

## Architecture

`tools/generate_cowork.py` produces fictional daily observations.
`sql/02_analytics.sql` owns deterministic evidence and matching.
`tools/build_specs.py` writes tracked semantic and agent specs through agent-studio.
`skills/` guides the business conversation; CoWork is the sole business interface.

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
python3 -B -m unittest discover -s tools -p 'test_lifecycle.py'
```

Cloud checks live in `tools/verify_cowork.py`, `tools/test_agent_api.py` and
`tools/test_agent_threads.py`; run them only for requested validation against an
explicit target. Preserve API evidence under ignored `local/` and record caveats
in `docs/05-COWORK-ACCEPTANCE.md`. Do not equate successful calls with acceptance.

Run `python3 -B tools/check_public_source.py` before preparing a public commit.
Private evidence and historical plans belong outside this project directory.
Publication URL configuration is separate from source sanitization.