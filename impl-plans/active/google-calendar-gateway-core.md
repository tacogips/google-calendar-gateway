# Calendar Gateway Core Implementation Plan

## Status

Active

## Scope

Implement the first production-shaped slice of `google-calendar-gateway` as a Swift
library and local CLI client, using the mail-gateway command/config patterns but
calendar-native public concepts.

Reference files from a sibling `mail-gateway` checkout:

- `Sources/MailGatewayCore/MailGatewayCLI.swift`
- `Sources/MailGatewayCore/ConfigLoading.swift`
- `Sources/MailGatewayCore/MailGatewayGraphQL.swift`
- `Sources/MailGatewayCore/GmailOAuthSupport.swift`

## Completed In Current Slice

- Renamed the library target to `GoogleCalendarGatewayCore`.
- Added config loading for `[storage]`, `[[credentials]]`, and
  `[[calendars]]`.
- Added calendar credential environment overrides for OAuth client and token
  store paths or JSON.
- Added auth status and revoke handling with token inspection.
- Added one-shot GraphQL-style query handling for `calendars`, `calendar`,
  `providerCalendars`, `freeBusy`, `events`, and `event`.
- Added a provider protocol and injectable service boundary so tests and future
  providers do not depend on live Google Calendar calls.
- Added typed Swift library models: `GoogleCalendarGatewayClient`, `CalendarInfo`,
  `CalendarCapabilities`, `ProviderCalendarInfo`, `CalendarEvent`,
  `CalendarEventParticipant`, `CalendarEventDateTime`, `CalendarEventReminders`,
  `CalendarEventReminder`, `CalendarConferenceData`,
  `CalendarConferenceEntryPoint`, and `CalendarEventConnection`.
- Added configured calendar `display_name` parsing and `CalendarInfo.displayName`
  exposure.
- Added provider calendar discovery through `GoogleCalendarGatewayClient`
  and GraphQL `providerCalendars(credentialId:)`.
- Added a Google Calendar HTTP adapter for `events.list` and `events.get`.
- Added Google Calendar `calendarList.list` discovery.
- Added Google Calendar `freebusy.query` availability lookup without exposing
  event detail payloads.
- Added installed-app Google Calendar OAuth login with loopback callback, PKCE,
  token-store writing, and token refresh.
- Added CalendarList and free/busy read scope requests and token mismatch
  detection so provider calendar discovery and availability lookup work with
  newly issued tokens.
- Added actionable Google Calendar HTTP error mapping for auth failures,
  missing event item operations, expired sync tokens, rate limits, and generic
  provider failures.
- Added guarded event write operations for create, update, and delete behind
  `read_write`.
- Added `cache prune --calendar <id>` and `cache prune --all`.
- Added CLI help/version/config/auth/graphql command routing.
- Added per-command unknown flag rejection before config loading or provider
  calls.
- Added per-command unexpected positional argument rejection before config
  loading or side effects.
- Added global `--help` and `--version` validation so those modes reject
  unknown flags and attached values before returning success output.
- Added duplicate flag rejection before config loading, provider calls, or
  global success output.
- Added `graphql --variables` and `graphql --variables-file` JSON-object
  validation for mail-gateway transport parity.
- Added GraphQL-style `createEvent`, `updateEvent`, and `deleteEvent`.
- Added lightweight GraphQL selection projection for dictionaries, arrays, and
  nested event objects.
- Added GraphQL input validation for search RFC 3339 date-times and event
  all-day/date-time values before provider calls.
- Added event incremental sync controls for `updatedMin`, `syncToken`,
  `showDeleted`, `singleEvents`, and `orderBy`, including Google-documented
  `syncToken` compatibility validation.
- Added GraphQL free/busy validation for required RFC 3339 date-times, provider
  calendar ID arrays, and Google expansion limits.
- Added event search `maxResults` validation for Google Calendar's supported
  1...2500 range before provider calls.
- Added service-level `sendUpdates` validation for Google-supported values
  before create/update/delete provider mutations.
- Added service-level event mutation validation for required create start/end,
  update writable fields, and attendee email shape before provider mutations.
- Added service-level event search and mutation date validation so direct Swift
  library calls reject malformed dates before provider calls.
- Added service-level blank delete event ID validation before provider calls.
- Added recurrence and reminder support for event reads and mutations, including
  RRULE-style recurrence fields, reminder override limits, and Google reminder
  body mapping.
- Added event metadata and conference support for color IDs, visibility,
  transparency, Google Meet create requests, and conference data reads.
- Added Google Calendar `conferenceData.createRequest` write mapping with
  `conferenceDataVersion=1` for event insert and patch calls that request
  conference creation.
- Added opaque event pagination cursors with `nextCursor` output and `cursor`
  input while retaining raw `nextPageToken`/`pageToken` compatibility.
- Added live integration documentation with explicit opt-in gates.
- Added focused Swift Testing coverage for config validation, GraphQL calendar
  listing, incremental event sync, direct library input validation, CLI global
  flag, duplicate flag, and positional argument validation, recurrence/reminders,
  metadata/conference fields, free/busy lookup, GraphQL projection, provider
  error mapping, auth status, missing token behavior, and token expiry parsing.

## Remaining Work

- Resume or rerun Riela implementation-plan/review steps if codex-agent
  authentication becomes available again.

## Verification

- `swift test` passed on 2026-07-01 with 74 tests after adding direct library
  date/delete-event validation plus command and global flag/positional
  argument rejection and duplicate flag rejection.
- `swift build` passed on 2026-07-01 after adding duplicate flag rejection.
- `swift run google-calendar-gateway --help` passed on 2026-07-01 after adding
  duplicate flag rejection.
- `mise run lint` passed on 2026-07-01 through `nix develop` with Xcode
  `DEVELOPER_DIR`, `SDKROOT`, `TOOLCHAINS`, and toolchain `PATH` overrides
  after adding duplicate flag rejection.
- `mise run build` and `mise run test` passed on 2026-07-01 through `nix develop`
  with the same Xcode toolchain overrides after adding duplicate flag
  rejection. `mise run test` passed with 74 tests.

## Riela Workflow Evidence

- Selected workflow: `codex-design-and-implement-review-loop`.
- Session `codex-design-and-implement-review-loop-session-141` completed intake,
  design update, design self-review, and design review.
- Design review accepted the design and reported one low finding about citing
  concrete mail-gateway reference files.
- The finding is addressed in this plan and
  `design-docs/specs/google-calendar-gateway.md`.
- Step 4 failed after interruption and supervised reruns because codex-agent
  authentication was unavailable; local implementation continued against the
  accepted Riela design.
- Session `codex-design-and-implement-review-loop-session-143` was checked again
  on 2026-07-01 and still failed at `step4-impl-plan-create` with
  `policy_blocked: codex-agent authentication is unavailable`.
