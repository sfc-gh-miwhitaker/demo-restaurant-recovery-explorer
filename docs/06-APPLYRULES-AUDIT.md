# Applyrules Audit

Pair-programmed by SE Community + Cortex Code

Project: demo-restaurant-recovery-explorer. Type: demo. Date: 2026-09-22.

## Current Verdict

The directory is sanitized and native Git deployment is packaged. End-to-end
cloud lifecycle acceptance remains open. No commits, pushes or cloud mutations
were performed for this conversion. A real GitHub origin is configured.

## Completed

- Public Git API integration is restricted to the actual repository URL and uses
  no authentication secret. Bootstrap preserves existing objects with IF NOT EXISTS.
- Root SQL entry points use EXECUTE IMMEDIATE FROM, not client-only `!source`.
- Explicit target and action confirmations precede deployment/removal. Existing
  schema and warehouse ownership/markers are checked. Do not use production.
- Fetch resolves the full main-branch commit; nested SQL, handler imports, specs
  and skill directories use that immutable revision within each deployment.
- The unchanged seeded generator executes inside Snowflake. Typed temporary tables
  precede transactional replacement, row-count validation, commit or rollback.
- No generator or oracle files are copied into the runtime skill stage. Reader
  has no grant on the Git repository or deployment helper procedure.
- Only two exact SKILL.md files are copied. Missing skills prevent agent creation.
- Semantic definitions come from tracked JSON-compatible YAML. Agent replacement
  preserves explicit grants; reader grants are reapplied afterward.
- Shared database, semantic schema and Git bootstrap survive teardown. Project
  schema uses RESTRICT, never CASCADE. Deployment helper is explicitly removed.
- Removed local shell wrappers, lifecycle runner, CSV loader and obsolete tests.
- README, ELI5, AGENTS and engineering skill describe native deployment and risks.
- Private plans, build state, traces and caches remain outside the project.
- Removed blanket docs/tools ignore rules so required deployment imports and
  validation documentation can actually be published. Private/cache exclusions remain.

## Verification

- Local fixture and mapping tests continue to pass.
- All 32 local tests passed: 9 fixture, 5 mapping, 13 native deployment and
  5 publication-check tests. Source scan checked 37 text files with zero findings.
- Native deployment tests check bootstrap origin, confirmations, commit pinning,
  relative includes, pipeline order, skill allowlist, teardown scope, spec parsing,
  literal quoting, transaction boundaries and rollback behavior with test doubles.
- Publication hygiene scan includes hidden source. Known private artifacts and
  common credential patterns produce location-only findings, not value disclosure.
- No new agent evaluations or browser tests were performed.

Local tests do not execute or compile Snowflake DDL. Syntax was grounded in current
product documentation; server acceptance of the complete Git/import/procedure
path still needs testing after these changes reach the repository. Do not label
the native deployment production-ready or claim a successful cloud round-trip.

## Remaining Gates

- Commit/push the reviewed changes before Snowflake can fetch this implementation.
- Execute fresh deploy, repeated deploy, failure recovery and teardown/rebuild in
  a dedicated demo account. Validate Python runtime/package availability there.
- Review licensing before distributing under an open-source license. None is
  assigned by this work.
- Review the final Git diff and history for publication. The source scanner is
  not a comprehensive secret scanner and does not inspect commit history.

## Operational Limits

Agent replacement resets version history. The entire deployment is not atomic;
only six-table replacement is transactional. Use a quiet window and one deployer.
Schema/warehouse markers and release IDs are guards, not proof that resources
have not been repurposed. Teardown intentionally removes the dedicated reader
role and its assignments; do not attach unrelated grants to it. Unexpected schema
objects or dependencies can stop teardown after earlier drops.

Bootstrap's IF NOT EXISTS does not change an existing integration or clone with
the same name. Review its origin and allowed prefixes before reuse. Initial entry
point selection is from main; restrict Git write access and review merged SQL.
The subsequent fetched revision is pinned, not necessarily identical to an older
cached entry point. Fetch first when updating lifecycle scripts.

Reader inherits account-specific PUBLIC privileges and stage-wide file access.
Legacy CSVs can remain on the stage until teardown. Previous API checks retain
their narrative caveats; CoWork browser behavior remains unverified.