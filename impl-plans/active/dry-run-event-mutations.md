# Dry-Run Event Mutations Implementation Plan

**Status**: Complete
**Workflow Mode**: `issue-resolution`
**Issue Reference**: `codex-design-and-implement-review-loop-session-600/comm-001238`
**Design Review Decision**: `accepted-ready-for-implementation-planning`
**Design Review Communication**: `comm-001248` (review communication
`comm-001245`)
**Implementation Plan Review**: `comm-001254`
(`accepted-ready-for-implementation`; prior `comm-001251` findings addressed)
**Codex-Agent References**: None supplied; no Codex-reference or Cursor-adapter behavior applies.

## Purpose

Implement opt-in dry-run behavior for `createEvent`, `updateEvent`, and
`deleteEvent` at the shared Swift service boundary, then expose the same
canonical result through the lightweight GraphQL executor and direct singular
`event` CLI commands. Dry-run must enforce the existing write gate and all
validation, return a deterministic preview, and stop before every provider
write. Existing callers remain live by default.

## Design Source Of Truth

- `design-docs/specs/design-dry-run-event-mutations.md` is authoritative, with
  task-level traceability to these accepted sections:
  - [Library Method And Result Contract](../../design-docs/specs/design-dry-run-event-mutations.md#library-method-and-result-contract)
    and [Preview Contract](../../design-docs/specs/design-dry-run-event-mutations.md#preview-contract)
    for TASK-001's public result types and canonical projection.
  - [Service Data Flow And Ordering](../../design-docs/specs/design-dry-run-event-mutations.md#service-data-flow-and-ordering)
    for TASK-002's validation, normalization, write-gate, preview, and provider
    call sequence.
  - [GraphQL Contract](../../design-docs/specs/design-dry-run-event-mutations.md#graphql-contract),
    [CLI Contract](../../design-docs/specs/design-dry-run-event-mutations.md#cli-contract),
    and [CLI Service Injection Boundary](../../design-docs/specs/design-dry-run-event-mutations.md#cli-service-injection-boundary)
    for TASK-003, TASK-004, and TASK-006 transport behavior.
  - [Compatibility And Boundaries](../../design-docs/specs/design-dry-run-event-mutations.md#compatibility-and-boundaries)
    and [Acceptance And Verification](../../design-docs/specs/design-dry-run-event-mutations.md#acceptance-and-verification)
    for TASK-005 through TASK-008 regression, scope, and final acceptance gates.
- `design-docs/specs/google-calendar-gateway.md`: gateway security and mutation
  behavior; the deferred dry-run decision is resolved here.
- `design-docs/specs/command.md`: GraphQL argument and singular `event` CLI
  command contract.
- `design-docs/user-qa/pending-google-calendar-gateway-decisions.md`: records dry-run
  as resolved and preserves existing `sendUpdates` behavior.

Step 3 accepted the design with no findings or implementation-blocking user
decision. Implementation must not diverge from the pinned public result types,
exact preview keys, write-gating order, normalized-input rules, raw
`sendUpdates` forwarding, transport projection, or CLI service-injection
boundary without returning to design review first.

## Step 5 Revision Record

- `comm-001251` mid finding at the former TASK-008 line 320: addressed by
  requiring explicit staged stat, name, patch, whitespace, and status
  inspection commands plus a recorded `Pass` before commit.
- `comm-001251` low finding at the former design-source line 22: addressed by
  linking the accepted library/result, preview, service-ordering, GraphQL, CLI,
  compatibility, and acceptance-verification sections to their owning tasks.

## Constraints

- Reuse the existing `GoogleCalendarGatewayCore` and `GoogleCalendarGatewayCLI` SwiftPM
  targets; add no module and preserve the macOS 14 boundary.
- Keep every touched non-generated Swift file below 1000 lines. In particular,
  do not grow `GoogleCalendarGatewayCore.swift` (currently 976 lines) into a larger
  mixed-responsibility file; move event-mutation service behavior to a
  cohesive extension file. Keep `GoogleCalendarGatewayGraphQL.swift` below the same
  limit.
- Keep provider protocol signatures unchanged. Providers never receive
  `dryRun` and never create previews.
- Use fake providers only. Never use live Google credentials or issue live
  calendar mutations, and never print or commit secrets or tokens.
- Do not modify `scripts/`, `packaging/`, `dist/`, `flake.nix`, `VERSION`, or
  Homebrew formula/cask tasks. Do not push.
- Preserve GraphQL and CLI error envelopes, exit codes, `WRITE_DISABLED`
  semantics, live response shapes, and existing `sendUpdates` validation and
  forwarding.

## Deliverables

- [x] Public typed mutation operation, deletion preview, preview payload,
  preview, and result contracts with one canonical `jsonObject` projection.
- [x] Service-owned dry-run execution paths for create, update, and delete,
  plus source-compatible live wrappers and unchanged typed live-only methods.
- [x] Optional GraphQL `dryRun` Boolean argument on all three event mutations.
- [x] Singular direct CLI `event create|update|delete` commands, canonical
  input parsing, `--dry-run`, and injectable service factory.
- [x] Focused fake-provider service, GraphQL, and CLI coverage, including
  deterministic serialization and zero-write assertions.
- [x] Documentation reconciliation, full verification, adversarial review,
  and one focused local commit with no push.

## Tasks

### TASK-001: Add Canonical Mutation Result And Preview Types

**Write Scope**:

- Add `Sources/GoogleCalendarGatewayCore/CalendarEventMutation.swift`.
- Modify `Sources/GoogleCalendarGatewayCore/CalendarModels.swift` only if a small,
  existing model projection must be exposed for the canonical preview; prefer
  keeping all new projection logic in the new mutation file.

**Deliverables**:

- Implement the exact public declarations accepted in the design:
  `CalendarEventMutationOperation`, `CalendarEventDeletionPreview`,
  `CalendarEventMutationPreviewPayload`, `CalendarEventMutationPreview`, and
  `CalendarEventMutationResult`.
- Make invalid operation/payload combinations unrepresentable and keep preview
  initializers module-internal.
- Implement the single canonical `jsonObject` projection. Create/update output
  must emit the complete fixed `validatedInput` key set with explicit
  `NSNull`, empty arrays, raw enum strings, ordered reminder objects, and an
  explicit `createConference` Boolean. Delete output must emit exactly the
  accepted eight keys.
- Preserve provider live projections: `.event` is the existing unwrapped event
  object and `.deletion` is the provider dictionary unchanged.

**Dependencies**: Accepted design only.

**Completion Criteria**:

- [x] Public visibility and internal construction boundaries match the design.
- [x] Projection contains no secret/token/config credential data.
- [x] Repeated sorted-key JSON serialization is deterministic and preserves
  array order.
- [x] New and touched Swift files remain below 1000 lines.

### TASK-002: Centralize Service Mutation Execution And Short-Circuiting

**Write Scope**:

- Add `Sources/GoogleCalendarGatewayCore/GoogleCalendarGatewayService+EventMutations.swift`.
- Modify `Sources/GoogleCalendarGatewayCore/GoogleCalendarGatewayCore.swift` to remove the
  existing mutation implementations from the main service body and expose only
  the minimum module-internal helpers required by the extension.
- Modify `Sources/GoogleCalendarGatewayCore/GoogleCalendarGatewayValidation.swift` only if
  needed to reuse, not duplicate, normalized input behavior.

**Deliverables**:

- Add `createEventMutation(input:dryRun:)`,
  `updateEventMutation(input:dryRun:)`, and
  `deleteEventMutation(accountId:calendarId:eventId:sendUpdates:dryRun:)`, with
  `dryRun = false`.
- Enforce the exact order: resolve account/credential, enforce write access,
  validate operation/input/`sendUpdates`, normalize provider-bound input and
  target identifiers, return preview when requested, otherwise invoke the
  existing provider method.
- Update dynamic `createEvent`, `updateEvent`, and `deleteEvent` wrappers with
  defaulted `dryRun` and shared-result projection.
- Keep `createCalendarEvent(input:)` and `updateCalendarEvent(input:)`
  signatures unchanged and live-only by delegating with `dryRun: false` and
  unwrapping `.event` without fabricating fallback events.
- Preserve exact raw `sendUpdates` values, including whitespace-only and
  padded allowed strings, after current validation.

**Dependencies**: TASK-001.

**Completion Criteria**:

- [x] Every dry-run path reaches the existing write gate and validation before
  preview construction.
- [x] No dry-run path can invoke `CalendarEventProvider.createEvent`,
  `.updateEvent`, or `.deleteEvent`.
- [x] Live callers compile unchanged and retain response shapes, provider
  arguments, errors, and effects.
- [x] Provider protocol and adapters are unchanged.
- [x] `GoogleCalendarGatewayCore.swift` and all new/touched Swift files are below
  1000 lines.

### TASK-003: Add GraphQL Dry-Run Transport Support

**Write Scope**:

- Modify `Sources/GoogleCalendarGatewayCore/GoogleCalendarGatewayGraphQL.swift`.

**Deliverables**:

- Parse optional Boolean literal `dryRun` for `createEvent`, `updateEvent`, and
  `deleteEvent`, defaulting to `false`.
- Forward the Boolean to the corresponding dynamic service wrapper and apply
  the existing GraphQL selection projection to the canonical result object.
- Reject non-Boolean values with existing `INVALID_ARGUMENT` behavior and
  retain `data: null` plus the existing `errors` envelope for all failures.

**Dependencies**: TASK-002.

**Completion Criteria**:

- [x] Omitted and false values retain live behavior.
- [x] True values expose only the canonical service preview projection.
- [x] GraphQL does not normalize inputs or reconstruct preview dictionaries.
- [x] `GoogleCalendarGatewayGraphQL.swift` remains below 1000 lines.

### TASK-004: Add Direct Event CLI Commands And Service Injection

**Write Scope**:

- Modify `Sources/GoogleCalendarGatewayCore/GoogleCalendarGatewayCLI.swift`.
- Modify `Sources/GoogleCalendarGatewayCore/GoogleCalendarGatewayCLIParsing.swift`.
- Add `Sources/GoogleCalendarGatewayCore/GoogleCalendarGatewayCLIEventCommands.swift` if
  needed to keep parsing, command adaptation, and the main CLI dispatcher
  cohesive and below 1000 lines.
- Keep `Sources/AppCLI/main.swift` unchanged at its call site.

**Deliverables**:

- Add a stored `(GoogleCalendarGatewayConfig) -> GoogleCalendarGatewayService` factory,
  preserve public `init()`, and add the module-internal injectable initializer
  accepted by the design.
- Route singular `event create`, `event update`, and `event delete` through
  loaded configuration, the injected service, and the shared typed mutation
  methods; do not instantiate a live service inside the event handler.
- Parse required local `--calendar`, update/delete `--event-id`, optional
  `--provider-calendar`, scalar/enum/Boolean fields, JSON-array collection
  fields, `--send-updates`, and `--dry-run` exactly as documented.
- Accept bare `--dry-run` or explicit `true|false`; retain duplicate/unknown
  flag and positional validation before config loading or side effects.
- Serialize `CalendarEventMutationResult.jsonObject` through the existing
  sorted-key JSON output and preserve stderr envelopes/exit codes.
- Update root help with all three commands and the dry-run option.

**Dependencies**: TASK-002.

**Completion Criteria**:

- [x] CLI inputs map one-to-one to canonical `CalendarEventInput` values.
- [x] CLI contains no preview construction, duplicate normalization, provider
  calls, or live-service fallback in the event handler.
- [x] Existing commands and public `GoogleCalendarGatewayCLI()` callers remain
  source-compatible.
- [x] All CLI Swift files remain below 1000 lines.

### TASK-005: Add Service And GraphQL Fake-Provider Regression Coverage

**Write Scope**:

- Add `Tests/AppCoreTests/DryRunTestSupport.swift` with a reference-type
  recording fake provider and mutation call/input records.
- Add `Tests/AppCoreTests/DryRunEventMutationTests.swift`.
- Avoid growing `Tests/AppCoreTests/CommandTests.swift` (currently 978 lines).

**Deliverables**:

- Cover service dry-run create/update/delete previews and assert zero provider
  write counts.
- Pin the complete create/update key set and exact null, empty-array, enum,
  reminder, Boolean, normalized ID, resolved calendar, and raw `sendUpdates`
  encodings.
- Pin delete's exact eight-key object, `wouldDelete: true`, `deleted: false`,
  normalized event ID, resolved calendar ID, and required null
  `sendUpdates` key when omitted.
- Verify invalid input fails before writes, read-only access returns
  `WRITE_DISABLED` before preview construction, and live omitted/false paths
  still invoke the provider once with unchanged arguments/results.
- Verify compact sorted-key serialization is byte-identical across repeated
  runs and array order is unchanged.
- Cover GraphQL true/false/omitted/non-Boolean cases, selection projection,
  zero writes, and unchanged error envelopes.

**Dependencies**: TASK-002 and TASK-003.

**Completion Criteria**:

- [x] Recording fake proves all three dry-run provider write counts are zero.
- [x] Live compatibility and raw `sendUpdates` forwarding are regression
  tested.
- [x] Tests use no token store, OAuth credential value, network, or live write.
- [x] `swift test --filter DryRun` passes for service and GraphQL coverage.

### TASK-006: Add End-To-End Direct CLI Dry-Run Coverage

**Write Scope**:

- Add `Tests/AppCoreTests/DryRunCLIEventMutationTests.swift`.
- Reuse `DryRunTestSupport.swift` and existing temporary config helpers; make
  only narrowly required helper visibility changes in
  `Tests/AppCoreTests/TestSupport.swift`.

**Deliverables**:

- Invoke real `event create`, `event update`, and `event delete` arguments
  through `GoogleCalendarGatewayCLI(serviceFactory:)` with temporary local config.
- Decode stdout and assert canonical previews plus zero create/update/delete
  calls on the same recording fake instance.
- Cover bare/explicit `--dry-run`, JSON-array fields, false/omitted live
  routing, missing required flags, malformed arrays/Booleans/enums, duplicate
  flags, unknown flags, unexpected positionals, and read-only
  `WRITE_DISABLED` exit behavior.
- Assert parsing failures happen before service creation and provider effects.

**Dependencies**: TASK-004 and TASK-005.

**Completion Criteria**:

- [x] All three CLI mutation routes use the injected factory and shared result
  projection.
- [x] CLI output and error/exit contracts match the accepted design.
- [x] `swift test --filter DryRun` passes including CLI coverage.

### TASK-007: Reconcile Documentation With Implemented Public Behavior

**Write Scope**:

- `design-docs/specs/design-dry-run-event-mutations.md`
- `design-docs/specs/command.md`
- `design-docs/specs/google-calendar-gateway.md`
- `design-docs/user-qa/pending-google-calendar-gateway-decisions.md`

**Deliverables**:

- Confirm implementation matches the already accepted design and command
  examples; make only accuracy corrections that do not alter the accepted
  contract.
- Ensure the deferred dry-run note remains resolved and the direct CLI shape,
  default-false behavior, write-gating order, preview schemas, and fake-only
  testing restriction are explicit.
- If implementation reveals a contract change, stop and return to design
  review instead of silently changing these documents.

**Dependencies**: TASK-003 and TASK-004.

**Completion Criteria**:

- [x] All four references describe the same implemented behavior.
- [x] No unresolved feature-specific user decision remains.
- [x] No Codex-agent or Cursor-specific behavior is introduced.

### TASK-008: Adversarial Review, Full Verification, And Local Commit

**Write Scope**: Only fixes within the scopes above, plus this progress log.

**Deliverables**:

- Review write-gate ordering, validation parity, normalized preview/live
  equivalence, exact JSON shape, raw `sendUpdates`, GraphQL envelopes, CLI
  injection, default-false compatibility, file lengths, and secret safety.
- Fix all high and mid findings and rerun affected focused checks before the
  full gate.
- Stage only in-scope source, tests, design documents, resolved-decision file,
  and this plan.
- Before committing, inspect the exact staged target with
  `git status --short`, `git diff --cached --stat`,
  `git diff --cached --name-only`, `git diff --cached`, and
  `git diff --cached --check`. Review every staged path and patch line for real
  credentials or private-key material, credential-bearing or private URLs,
  machine-local absolute paths, and generated content containing environment
  or credential values. Do not use gitleaks as a substitute for this manual
  staged-patch review.
- Record the staged-content safety result as `Pass` before creating one focused
  local commit. If the result is `Issues`, unstage or correct the affected
  content, restage only the intended paths, rerun the full staged inspection,
  and do not commit until it records `Pass`. Do not push.

**Dependencies**: TASK-005, TASK-006, and TASK-007.

**Completion Criteria**:

- [x] No unresolved high or mid review finding remains; low findings are fixed
  or explicitly recorded with rationale.
- [x] Every required verification command passes.
- [x] Final staged/committed scope contains no release, packaging, secret, or
  unrelated file.
- [x] The progress log records the five staged-content inspection commands,
  reviewed paths, and an explicit `Pass` result before the commit command.
- [x] One focused local commit exists and no remote push occurred.

## Dependencies

```text
TASK-001 -> TASK-002 -> TASK-003 -> TASK-005 -> TASK-006 -> TASK-008
                       TASK-004 --------^          ^
                          |                         |
                          +-----> TASK-007 --------+
```

- TASK-001 pins the shared result contract before any service or transport
  code consumes it.
- TASK-002 owns all mutation behavior; both transport adapters depend on it.
- TASK-003 and TASK-004 may proceed concurrently after TASK-002 because their
  write scopes are disjoint.
- TASK-005 follows the service and GraphQL adapters. TASK-006 follows the CLI
  adapter and reuses the recording support established by TASK-005.
- TASK-007 may proceed alongside test work after both adapters stabilize.
- TASK-008 is the serial review, verification, and commit gate.

## Parallelizable Tasks

- **Group A after TASK-002**: TASK-003 and TASK-004. Source write scopes are
  disjoint (`GoogleCalendarGatewayGraphQL.swift` versus CLI files).
- **Group B after TASK-003 and TASK-004**: TASK-005 and TASK-007 may proceed in
  parallel. Test and documentation write scopes are disjoint.
- TASK-001, TASK-002, TASK-006, and TASK-008 are serial because they establish
  shared contracts/support or perform the final integrated gate.

## Verification

Run in this order and record command, result, and any corrective rerun:

```bash
swift test --filter DryRun
swiftlint
mise run lint
swift build
swift test
git diff --check
rg --files Sources Tests -g '*.swift' | xargs wc -l | sort -n
git status --short --untracked-files=all
git diff --cached --stat
git diff --cached --name-only
git diff --cached
git diff --cached --check
```

Verification assertions beyond command exit status:

- Recording fake counts are zero for dry-run create/update/delete at service,
  GraphQL, and CLI boundaries.
- Read-only dry-runs fail with `WRITE_DISABLED`; invalid requests fail before
  provider writes.
- Omitted/false dry-run paths preserve live provider calls, response shapes,
  errors, and exact `sendUpdates` values.
- Preview JSON is canonical and deterministic, create/update use the full fixed
  schema, and delete has exactly eight keys.
- Final status contains only in-scope `Sources/`, `Tests/`, accepted design
  documents, `design-docs/user-qa/pending-google-calendar-gateway-decisions.md`, and
  this plan. No release/packaging path or secret material is present.
- The staged-content safety review covers every path and patch line shown by
  the cached-diff commands and records `Pass` only when no credential, private
  URL, machine-local absolute path, or generated-secret issue remains.

If direct `swiftlint` is unavailable outside the development shell, record the
failure and run `mise run lint` through the repository's Nix/Xcode environment as
documented by `.codex/skills/swift-coding-agent/SKILL.md`; the final lint gate
must still pass.

## Completion Criteria

- [x] Library, GraphQL, and CLI expose default-false dry-run for all three event
  mutations exactly as accepted.
- [x] Write gating and validation occur before preview; no dry-run reaches a
  provider write.
- [x] Shared typed result and canonical projection are the only preview source.
- [x] Existing live APIs, provider protocols, response/error shapes, and
  `sendUpdates` behavior remain compatible.
- [x] Focused and full lint/build/test gates pass with all Swift files below
  1000 lines.
- [x] Documents match implementation and no user decision, Codex reference,
  high/mid finding, or secret-safety concern remains unresolved.
- [x] The exact staged commit target receives a recorded safety `Pass` after
  all staged-diff commands and before `git commit`.
- [x] Changes are contained to authorized paths and committed once locally
  without a push.

## Progress Log Expectations

After each task, update its checkboxes and append a dated entry containing the
task ID, status, files changed, exact verification commands and results, review
findings addressed, and any remaining risk/blocker. Record only safe metadata;
never copy OAuth client secrets, access tokens, refresh tokens, private event
contents, or live provider request bodies. Any proposed contract divergence
must be logged as blocked and routed back through design review before code or
documentation is changed.

## Progress Log

- 2026-07-18: Plan updated for independent design review. Review findings:
  premature acceptance language removed. Codex-agent references: none.
  Implementation not started.
- 2026-07-18: Independent design review communication `comm-001245` required
  exact CLI collection and Boolean contracts. The authoritative design now
  specifies typed JSON-array examples, string reminder literals, ordering and
  empty-array behavior, Boolean syntax/defaults, and CLI-versus-service
  invalid-value handling for TASK-004 and TASK-006. Implementation has not
  started.
- 2026-07-18: Step 3 acceptance communication `comm-001248` recorded decision
  `accepted-ready-for-implementation-planning`, with no findings, no required
  revision, no Codex-agent reference, and no implementation-blocking user
  decision. TASK-001 through TASK-008 remain incomplete and ready for the
  implementation step.
- 2026-07-18: TASK-001 completed. Added
  `Sources/GoogleCalendarGatewayCore/CalendarEventMutation.swift` with the accepted
  public typed result and exact canonical preview projection. Verification:
  `swift test --filter DryRun` passed; deterministic sorted-key serialization
  and ordered arrays are covered. Findings: none. Remaining risk: final staged
  safety review and commit.
- 2026-07-18: TASK-002 completed. Moved event mutations into
  `Sources/GoogleCalendarGatewayCore/GoogleCalendarGatewayService+EventMutations.swift` and
  narrowed `GoogleCalendarGatewayCore.swift`. Dry-run exits after write gating,
  validation, and normalization and before provider writes. Verification:
  focused and full tests passed. Findings: none. Remaining risk: final commit.
- 2026-07-18: TASK-003 completed. `GoogleCalendarGatewayGraphQL.swift` accepts and
  forwards default-false Boolean `dryRun` for all three mutations. Verification:
  focused GraphQL true/false/omitted/non-Boolean tests passed. Findings: none.
- 2026-07-18: TASK-004 completed. Added the injectable direct singular event
  CLI adapter in `GoogleCalendarGatewayCLIEventCommands.swift` and updated CLI parsing,
  dispatch, and help. Verification: focused CLI tests passed. Adversarial review
  fixed create's initially overbroad `--event-id` acceptance. Remaining risk:
  final staged safety review and commit.
- 2026-07-18: TASK-005 and TASK-006 completed. Added
  `DryRunTestSupport.swift`, `DryRunEventMutationTests.swift`, and
  `DryRunCLIEventMutationTests.swift`. The recording fake proves zero dry-run
  writes and live/default-false compatibility. Verification:
  `swift test --filter DryRun` passed 7 tests in 2 suites. Findings: none.
- 2026-07-18: TASK-007 completed. Confirmed the accepted dry-run design,
  command specification, gateway specification, and resolved-decision record
  match the implementation without contract changes. Codex-agent references:
  none. Findings: none.
- 2026-07-18: TASK-008 verification and adversarial review completed. Exact
  commands passed: `swift test --filter DryRun`, `swiftlint`, `mise run lint`,
  `swift build`, `swift test`, `git diff --check`, and
  `rg --files Sources Tests -g '*.swift' | xargs wc -l | sort -n`. Full suite:
  110 tests passed; lint: 0 violations; every Swift file is below 1000 lines.
  Review fixed the create CLI flag scope and strengthened all-mutation GraphQL
  dry-run coverage plus repeated serialization coverage. No high, mid, or
  residual low finding remains. Remaining action: staged-content safety review
  and one local commit; no push.
- 2026-07-18: TASK-008 staged-content review result: `Pass`. Ran and reviewed
  `git status --short --untracked-files=all`, `git diff --cached --stat`,
  `git diff --cached --name-only`, `git diff --cached`, and
  `git diff --cached --check`. Reviewed all 15 staged paths under the authorized
  `Sources/`, `Tests/`, `design-docs/`, and `impl-plans/active/` scopes and every
  staged patch line. No release or packaging file, real credential, private-key
  material, credential-bearing or private URL, machine-local absolute path,
  generated environment value, or unrelated change is present. The only
  credential-keyword matches are safety-policy prose in this plan. Commit is
  now authorized; no push is authorized.
- 2026-07-18: TASK-008 completed. Created the single focused local commit
  `Add dry-run event mutation previews`; the repository gitleaks commit hook
  passed. This progress-only amendment finalizes the same commit. No remote
  push occurred. Remaining risks or blockers: none.
