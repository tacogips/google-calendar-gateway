# Calendar Gateway Review Findings Implementation Plan

**Status**: Completed
**Workflow Mode**: issue-resolution
**Created**: 2026-07-02
**Issue Reference**: No GitHub issue URL or repository-plus-number was provided; this plan is tied to workflow intake and local design/review documents.

## Purpose

Implement the accepted Step 3 design updates for the google-calendar-gateway
implementation review findings. The work repairs red CI first, then fixes High
severity correctness issues, then same-boundary Medium issues that are already
specified in `design-docs/specs/`.

This plan is the implementation handoff artifact. It does not introduce new
product scope beyond the accepted design.

## Source Of Truth

- `design-docs/reviews/2026-07-02-implementation-review.md`
- `design-docs/specs/architecture.md`
- `design-docs/specs/google-calendar-gateway.md`
- `design-docs/specs/command.md`
- `design-docs/user-qa/pending-google-calendar-gateway-decisions.md`

No Codex-agent reference inputs were present for this workflow transition.
Cursor- or Codex-agent-specific behavior remains outside provider adapters, as
accepted in the design.

## Deliverables

- [x] CI no longer runs an impossible Linux product build while v1 is macOS-only.
- [x] Gitleaks workflow no longer fails before scanning on first-push ranges.
- [x] Scope coverage semantics are shared by auth status, capability reporting,
      and request-time token validation.
- [x] RFC 3339 validation accepts fractional seconds and numeric offsets for
      all existing datetime entry points.
- [x] GraphQL execution rejects multi-root-field documents instead of returning
      silent partial results.
- [x] GraphQL field and argument scanning ignores string literal contents.
- [x] Config validation, ID validation, cache pruning, and local file deletion
      behavior match the accepted cache and config safety design.
- [x] Auth refresh, revoke, and loopback callback behavior match the accepted
      auth design.
- [x] Raw calendar API mutating methods are write-gated regardless of
      `access: "read"`.
- [x] GraphQL variable references fail explicitly while substitution is
      unsupported.
- [x] Tests cover every fixed High issue and each implemented Medium issue.
- [x] Progress updates are appended to this plan as implementation tasks land.

## Dependencies

- TASK-001 must land before CI status can be trusted for later tasks.
- TASK-002, TASK-003, and TASK-004 are High correctness work and should land
  before Medium behavior changes.
- TASK-005 depends on or must coordinate closely with TASK-004 because both
  touch `Sources/GoogleCalendarGatewayCore/GoogleCalendarGatewayGraphQL.swift`.
- TASK-006 config ID validation is a prerequisite for the cache prune
  containment hardening in TASK-007.
- TASK-008 auth refresh and revoke changes share token-store code paths and
  should be coordinated in one branch of work.
- TASK-010 final verification depends on all implementation tasks.

## Tasks

### TASK-001: Repair CI Platform And Secret Scan Jobs

**Write Scope**:

- `.github/workflows/linux-amd64-build.yml`
- `.github/workflows/gitleaks.yml`
- optional CI notes in `design-docs/specs/architecture.md` only if behavior
  diverges from the accepted design

**Work**:

- Disable, remove, or retarget the Linux product build so CI honors the
  accepted macOS-only v1 boundary.
- Keep macOS build/test verification as the required product signal.
- Adjust gitleaks configuration so first-push and ordinary pull request scans
  use an existing revision range, full history, or checked-out tree scan.
- Preserve pinned GitHub Action SHAs and least-privilege permissions.

**Completion Criteria**:

- Linux CI no longer attempts to build the macOS-only `google-calendar-gateway`
  product.
- Gitleaks cannot fail solely because `<first-commit>^` is not a valid
  revision.
- CI workflow changes pass YAML/syntax review and repository security rules.
- The Linux platform-boundary workflow shell step passes locally against the
  current multiline `Package.swift` platform declaration.

### TASK-002: Unify OAuth Scope Coverage Semantics

**Write Scope**:

- `Sources/GoogleCalendarGatewayCore/AuthTokenInspection.swift`
- `Sources/GoogleCalendarGatewayCore/GoogleCalendarOAuthSupport.swift`
- `Tests/AppCoreTests/*`

**Work**:

- Keep one source of truth for `calendarAccessMode(_:covers:)`.
- Use the same coverage rule for `auth status`, calendar capabilities, and
  request-time token validation.
- Ensure broader granted scopes can satisfy compatible narrower configured
  modes, and incompatible partial scopes still fail.

**Completion Criteria**:

- A `full` token with configured `read` credentials reports ready and can pass
  request-time validation.
- Event-only or calendar-list-only tokens remain mismatches.
- Regression tests cover status and live validation paths.

### TASK-003: Accept RFC 3339 Fractional Seconds Everywhere

**Write Scope**:

- `Sources/GoogleCalendarGatewayCore/GoogleCalendarGatewayUtilities.swift`
- existing validation call sites as needed in `GoogleCalendarGatewayCore.swift` and
  `GoogleCalendarGatewayGraphQL.swift`
- `Tests/AppCoreTests/*`

**Work**:

- Update `isRFC3339DateTime` to accept RFC 3339 timestamps with and without
  fractional seconds.
- Preserve support for `Z` and explicit numeric offsets.
- Reuse the helper for GraphQL and direct library validation paths.

**Completion Criteria**:

- `.000Z`, non-zero fractional seconds, `Z`, and `+09:00` offset forms pass.
- Date-only strings still fail where RFC 3339 date-time is required.
- Tests cover `timeMin`, `timeMax`, `updatedMin`, free/busy bounds, and event
  mutation datetime validation where practical.

### TASK-004: Reject Multiple GraphQL Root Fields

**Write Scope**:

- `Sources/GoogleCalendarGatewayCore/GoogleCalendarGatewayGraphQL.swift`
- `Tests/AppCoreTests/*`

**Work**:

- Detect all top-level executable root fields in the current lightweight
  GraphQL document.
- Reject documents containing more than one root field with `INVALID_ARGUMENT`.
- Keep one-root behavior unchanged for existing fields.
- Preserve write gating for write field names even when the operation keyword
  says `query`.

**Completion Criteria**:

- `{ calendars { id } providerCalendars(credentialId: "...") { id } }` fails.
- Single-root queries and mutations continue to pass.
- The error is machine-readable and does not return partial data.

### TASK-005: Make GraphQL Scanners String-Literal Aware

**Write Scope**:

- `Sources/GoogleCalendarGatewayCore/GoogleCalendarGatewayGraphQL.swift`
- `Tests/AppCoreTests/*`

**Work**:

- Update field-range scanning so braces and parentheses inside quoted strings
  do not affect depth counters.
- Update argument-name lookup so identifiers inside quoted strings are ignored.
- Reuse existing balanced-delimiter/string scanning helpers where possible.

**Completion Criteria**:

- Argument values such as `summary: "contains timeMin: text"` do not confuse
  argument extraction.
- String values containing braces or parentheses do not corrupt root field
  dispatch.
- Regression tests cover string-literal argument names and unbalanced delimiter
  characters inside strings.

### TASK-006: Make Config Validation Honest And IDs Safe

**Write Scope**:

- `Sources/GoogleCalendarGatewayCore/ConfigLoading.swift`
- `Sources/GoogleCalendarGatewayCore/GoogleCalendarGatewayCLI.swift`
- `Tests/AppCoreTests/*`

**Work**:

- Enforce accepted ID character rules for `credentials.id` and `calendars.id`.
- Reject IDs that collide after environment variable normalization.
- Update `config validate` output so `configFileExists` and `usingDefaults` are
  explicit.
- Ensure missing explicitly requested config paths remain errors.
- Ensure missing implicit config reports `configFileExists: false` and
  `usingDefaults: true`, and does not return `ok: true` for fabricated config
  data.

**Completion Criteria**:

- `config validate` cannot report `ok: true` for a fabricated config with no
  backing config file.
- Missing implicit config returns explicit defaults metadata with
  `configFileExists: false` and `usingDefaults: true`; missing explicitly
  requested config remains an error.
- IDs containing path separators, traversal segments, whitespace, or env-name
  collisions fail during config load.
- Tests cover missing implicit config, missing requested config, valid IDs, bad
  IDs, and env-normalization collisions.

### TASK-007: Harden Cache Prune And Local File Safety

**Write Scope**:

- `Sources/GoogleCalendarGatewayCore/GoogleCalendarGatewayCore.swift`
- `Sources/GoogleCalendarGatewayCore/GoogleCalendarGatewayUtilities.swift`
- `Tests/AppCoreTests/*`

**Work**:

- Canonicalize and resolve symlinks before cache-root containment checks.
- Use validated account/calendar IDs when constructing prune targets.
- Report removal failures as errors instead of counting them as pruned paths.
- Make empty-cache behavior explicit in command output if no cache entries
  exist.

**Completion Criteria**:

- Traversal attempts cannot remove paths outside the configured cache root.
- Failed removals fail the command or are reported as failures, not successes.
- Tests cover traversal IDs, symlink/prefix containment, removal failure
  behavior where practical, and empty-cache output.

### TASK-008: Complete Auth Refresh, Revoke, And Loopback Fixes

**Write Scope**:

- `Sources/GoogleCalendarGatewayCore/GoogleCalendarOAuthSupport.swift`
- `Sources/GoogleCalendarGatewayCore/GoogleCalendarOAuthBootstrap.swift`
- `Sources/GoogleCalendarGatewayCore/GoogleCalendarGatewayCore.swift`
- `Tests/AppCoreTests/*`

**Work**:

- Persist rotated `refresh_token` values returned by token refresh.
- Add token-store read-modify-write serialization where feasible, or document
  the platform limitation if locking is deferred.
- Call Google's revocation endpoint best-effort before deleting local token
  material.
- Report provider revocation and local deletion outcomes separately.
- Treat environment-supplied token stores as non-deletable local material.
- Keep accepting loopback connections until the expected callback path and
  state arrive or the deadline expires.

**Completion Criteria**:

- Refresh-token rotation is preserved in the token store, with a regression
  test that exercises an expired file-backed token store and a mocked token
  endpoint response containing a rotated `refresh_token`.
- `auth revoke` no longer only deletes the local file when provider revocation
  is possible.
- Stray loopback requests do not abort an otherwise valid login.
- Tests cover refresh rotation, revoke result shape, env token-store handling,
  and loopback stray request handling.

### TASK-009: Close Raw API And Variables Gaps

**Write Scope**:

- `Sources/GoogleCalendarGatewayCore/CalendarRawAPI.swift`
- `Sources/GoogleCalendarGatewayCore/GoogleCalendarGatewayGraphQL.swift`
- `Sources/GoogleCalendarGatewayCore/GoogleCalendarGatewayCLIParsing.swift`
- `Tests/AppCoreTests/*`

**Work**:

- Gate mutating raw Calendar API HTTP methods before provider calls regardless
  of the `access` argument.
- Keep `access` only as a token-scope hint for non-mutating behavior.
- Ensure GraphQL variable references with `$name` fail explicitly while
  substitution is unsupported.

**Completion Criteria**:

- `calendarAPI(... method: "DELETE", access: "read")` fails locally with
  `WRITE_DISABLED` for read-only credentials.
- `--variables` and `--variables-file` continue to validate JSON objects.
- Queries containing `$name` fail with a clear `INVALID_ARGUMENT`.

### TASK-010: Verification, Documentation, And Progress Closeout

**Write Scope**:

- `impl-plans/active/google-calendar-gateway-review-findings-2026-07-02.md`
- `impl-plans/active/google-calendar-gateway-core.md` or `impl-plans/completed/`
  only if the implementation step elects to close the shipped core plan
- docs under `design-docs/specs/` only when implementation intentionally
  diverges from the accepted design

**Work**:

- Run narrow tests after each task and full verification before handoff.
- Update this plan's progress log with task completion dates, commands, and
  any deliberate deferrals.
- Move or mark the older shipped core implementation plan only if doing so is
  in scope for the implementation step.

**Completion Criteria**:

- Required verification commands have passed or failures are documented with
  exact command output summaries.
- This plan records completed tasks and any unresolved TODOs.
- No implementation behavior diverges from the accepted design without a doc
  update.

## Parallelizable Tasks

The following tasks may run in parallel only when their write scopes remain
disjoint:

- TASK-001 can run in parallel with Swift source tasks because it only changes
  `.github/workflows/`.
- TASK-003 can run in parallel with TASK-004 if tests are split by validation
  vs GraphQL root-field behavior.
- TASK-006 can run in parallel with TASK-009 if config tests and raw
  API/variables tests are kept in separate files or coordinated before merge.

Do not run TASK-004 and TASK-005 in parallel unless one implementer owns the
shared `GoogleCalendarGatewayGraphQL.swift` edits. Do not run TASK-006 and TASK-007
in parallel unless ID validation is complete first.

## Verification Plan

Run the narrowest relevant command after each task, then the full set before
handoff:

```bash
swift test --filter <focused-test-name>
swift test
swift build
swift run google-calendar-gateway --help
mise run lint
mise run build
mise run test
git diff --check
git status --short
```

CI workflow changes should also be checked with repository-available YAML or
action validation tools if present. If unavailable, inspect the workflows
manually and document that limitation in the progress log.

## Completion Criteria

- CI repair findings and all High severity review findings are implemented.
- Same-boundary Medium findings accepted in Step 3 are implemented or have an
  explicit documented deferral with rationale.
- Tests cover the fixed behavior before broader verification is run.
- Full verification commands pass, or remaining failures are unrelated and
  documented with exact commands.
- `git diff --check` reports no whitespace errors.
- No git commit or push is created unless explicitly requested by the user.

## Progress Log

- 2026-07-02: Plan created from accepted Step 3 design review
  `comm-000308` for workflow
  `codex-design-and-implement-review-loop-session-151`.
- 2026-07-02: Implemented TASK-001 through TASK-009 in the local worktree.
  Linux CI now verifies the documented macOS-only boundary instead of building
  the macOS-only product on Linux. Gitleaks now installs a checksum-pinned
  CLI and scans a verified PR/push revision range, falling back to full history
  when no valid base exists.
- 2026-07-02: Implemented shared OAuth scope coverage, RFC 3339 fractional
  second validation, single-root GraphQL enforcement, string-literal-aware
  GraphQL scanners, explicit variable-reference rejection, config ID safety,
  honest `config validate` output, canonical cache pruning, raw API write
  gating, refresh-token rotation persistence, file-backed refresh locking,
  best-effort provider revocation with separate local deletion reporting, and
  loopback callback tolerance for stray local requests.
- 2026-07-02: Added regression coverage in `CommandTests`,
  `RawCalendarAPITests`, `AuthRevokeTests`, `CachePruneTests`, and
  `OAuthBootstrapTests`. Split cache behavior into `GoogleCalendarGatewayCache.swift`
  to keep Swift files under the repository size limit.
- 2026-07-02: Added request-time OAuth scope coverage regression for the live
  token validation path and split CLI config/GraphQL validation coverage into
  `Tests/AppCoreTests/CLIConfigGraphQLValidationTests.swift` so all Swift
  source and test files remain under 1000 lines.
- 2026-07-02: Verification passed:
  `swift test --filter loopbackReceiverIgnoresStrayRequestsUntilExpectedCallback`,
  `swift test --filter liveTokenValidationUsesScopeCoverageSemantics`,
  `swift test`, `mise run lint`, `mise run build`, `mise run test`, `swift build`,
  `swift run google-calendar-gateway --help`, `git diff --check`, workflow YAML
  parsing via Ruby, and source/test line-count audit. Commands were run with
  the Xcode SDK environment required by the local macOS/Nix shell.
- 2026-07-02: Addressed Step 6 self-review feedback for TASK-001 by replacing
  the single-line `grep` package-platform assertion in
  `.github/workflows/linux-amd64-build.yml` with a multiline Ruby manifest
  check. Ran the exact workflow shell step locally:
  `set -euo pipefail; ruby -e '...'; grep -q 'macOS-only' design-docs/specs/architecture.md; echo ...`.
- 2026-07-02: Addressed Step 6 test-integrity feedback for TASK-008 by adding
  `tokenRefreshPersistsRotatedRefreshToken`, which drives
  `validGoogleCalendarAccessToken` through an expired file-backed token store
  and a local mocked token endpoint response containing
  `refresh_token: "rotated-refresh"`, then asserts the persisted token store
  keeps that rotated refresh token. Initial focused verification
  `swift test --filter tokenRefreshPersistsRotatedRefreshToken` failed before
  package compilation because the inherited Nix SDK was incompatible with the
  selected Xcode Swift toolchain (`no such module 'SwiftShims'`). Reran with
  the Xcode SDK/toolchain environment and the focused test passed.
- 2026-07-02: Reran broad verification after the TASK-008 test-integrity fix:
  `swift test`, `swift build`, `swift run google-calendar-gateway --help`,
  `mise run build`, `mise run test`, `mise run lint`, and `git diff --check` passed.
  `mise run lint` was run inside `nix develop` because `swiftlint` was not
  available on the direct shell `PATH`.
- 2026-07-02: Addressed Step 6 self-review feedback for the Swift file
  line-count rule by moving `tokenRefreshPersistsRotatedRefreshToken` from
  `Tests/AppCoreTests/CommandTests.swift` to
  `Tests/AppCoreTests/OAuthTokenRefreshTests.swift`. Verified the split with
  `wc -l Tests/AppCoreTests/CommandTests.swift Tests/AppCoreTests/OAuthTokenRefreshTests.swift Tests/AppCoreTests/TestSupport.swift`;
  `CommandTests.swift` is now 978 lines.
- 2026-07-02: Reran verification after the line-count split:
  `swift test --filter tokenRefreshPersistsRotatedRefreshToken`, `swift test`,
  `nix develop -c bash -lc '... mise run lint'`, `git diff --check`, and
  `rg --files -g '*.swift' | xargs wc -l | sort -n | tail -20` passed.
  Broad `swift test` passed 103 tests.
- 2026-07-02: Final continuation verification passed with the Xcode
  SDK/toolchain environment: `swift test --filter
  tokenRefreshPersistsRotatedRefreshToken`, `swift test` with 103 tests,
  `swift build`, `swift run google-calendar-gateway --help`, `mise run build`,
  `mise run test`, `nix develop -c bash -lc '... mise run lint'`, `git diff --check`,
  and the Swift file line-count audit. `mise run lint` reported 0 violations in
  28 files.
