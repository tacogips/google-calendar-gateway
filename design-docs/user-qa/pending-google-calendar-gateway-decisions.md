# Pending Calendar Gateway Decisions

Track user decisions that should not block the first design pass but may affect
implementation scope.

## Provider Scope

Should v1 include only Google Calendar, or should the public API include named
placeholders for additional providers?

Default design decision: implement Google Calendar first behind a generic
provider protocol.

## Long-Running Transport

Is `google-calendar-gateway serve` required for v1, or is one-shot GraphQL sufficient?

Default design decision: one-shot GraphQL only for v1.

## CLI Shape

Should v1 remain a single `google-calendar-gateway` executable, or split into separate
reader/writer binaries like the mail-gateway reference?

Default design decision: use one executable with access-mode gating unless
review finds separate binaries are necessary for write safety.

## Platform Scope

Should the project preserve Linux CI for the executable now, or explicitly scope
v1 to macOS while Google Calendar OAuth bootstrap remains Apple-platform
specific?

Default design decision: v1 is macOS-only because `Package.swift` declares
macOS 14 and the current OAuth bootstrap depends on Apple platform APIs. Linux
support can be reconsidered after the OAuth bootstrap, browser launch, random
bytes, and socket receiver are behind portable adapters.

## Resolved Decisions

Write safety is resolved by issue
`codex-design-and-implement-review-loop-session-600/comm-001238`: event
create/update/delete expose an optional dry-run mode that defaults to `false`.
Dry-run still requires `read_write` or `full` access, runs normal validation,
and returns a preview before any provider write. Tests use fake providers. The
authoritative behavior is recorded in
`design-docs/specs/design-dry-run-event-mutations.md`.

No `sendUpdates` compatibility change is authorized by this issue. Create,
update, and delete retain their existing validation and live provider argument
behavior. Dry-run previews expose the exact same provider-bound value.
