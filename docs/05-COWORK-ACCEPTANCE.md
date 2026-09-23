# CoWork Acceptance Checkpoint

Pair-programmed by SE Community + Cortex Code

Status on 2026-09-22: API-tested implementation. CoWork UI behavior is not claimed
as verified. This is not full release acceptance.

## Verified Evidence

- Nine fixture tests and five mapping-boundary tests pass locally.
- Independent Python totals match 72 restaurant/window SQL records.
- Eight reference SQL queries execute with nonempty results.
- Twenty-two distinct API probes completed without invocation errors. Captured
  answers and tool results were reviewed; successful calls are not blanket passes.
- Ten targeted retests exercised revised analytical guidance. A final three-case
  peer retest was not completed.
- Traces contain actual `server_skill` calls for both restaurant-investigation
  and restaurant-test-design, as well as SQL and chart tool calls.
- Two fresh server-side reader-role threads completed three turns each:
  Mesa Vale -1,621; excluding closures +8,746; also excluding openings -6,279.
  Three excluded pairs remain throughout. All six persisted checks confirm
  expected totals, thread continuity, completed status, no warnings and fresh SQL.
- Reader invocation used the documented DATA_AGENT_RUN API wrapper with secondary
  roles NONE. All three semantic views also passed direct reader SQL checks.
- Direct reader SELECT on canonical PERFORMANCE was denied. No project object
  write or ownership privileges were granted to the reader.

## Evidence Boundary

Raw execution responses, thread metadata and account-specific test artifacts are
preserved privately outside this source directory. They are not included in the
public package. The results above summarize prior engineering checks; the local
test programs allow maintainers to reproduce checks in their own demo account.
No new API calls were run for sanitization.

## Corrections And Residual Risks

Semantic instructions now distinguish full-period closure-unit losses from
closed-day losses (-236 before closure and -10,131 on closed dates for R110),
explicit opening zeros from missing data, guests from transactions, and observed
window trends from unknown earlier onset. They also limit claims from missing-cell
counts, peer-subset sensitivity and contrasting labor outcomes.

Targeted retests improved those explanations. Remaining concerns include occasional
overstrong narrative conclusions, automatic suggestions of similarity peers as
experiment controls, and substitution language for unsupported periods. Do not
report perfect answer accuracy or claim every explanation is independently verified.

Numeric token presence in the API harness is only a screening aid: "1,621 fewer"
can be correct without containing -1621. Inspect meaning, SQL and results.
Reference-query execution is not an independent oracle for every peer calculation.
EVENTS remains outside the agent's analytical tools; dated event retrieval is not
an accepted capability.

## Access Limits

The reader inherits existing PUBLIC privileges, including broader AI and artifact
privileges. This is scoped project access, not account-wide isolation. No unrelated
grants or user defaults were changed. Immediate access evidence uses fresh SHOW
results and reader-session tests; the initial recursive ACCOUNT_USAGE query ran
before the new grants appeared and was not final inherited-access proof.

READ on RELEASE_FILES is stage-wide. Earlier deployments placed fictional source
CSVs there; native deployments copy only runtime skills. Existing CSVs remain
until teardown. Generator source, scenario construction and expected answers are
not copied to the reader's stage. Reader gets no Git repository or deployment
helper access. Raw-table denial does not imply raw-file isolation.

## Outstanding Release Work

Deployment and teardown are single self-contained Snowsight scripts, covered by
structural tests over the entry points, the pinned-commit handoff, the
transactional table replacement and its rollback path. The generator
runs unchanged inside Snowflake with temporary staging. Documentation accuracy is
enforced by tests: every markdown link and backticked repository path in the
entry-point documents must resolve.

Customer mapping annex and production-source validation remain open. The source is
Apache 2.0 licensed with a configured GitHub origin. The directory contains generic
source and validation summaries, not private execution evidence.