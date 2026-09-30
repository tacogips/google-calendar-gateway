# Calendar Gateway Design

This document defines the target design for `google-calendar-gateway` as both a Swift
library and a local CLI calendar client. It uses a sibling `mail-gateway`
checkout as the behavioral reference for local AI-friendly gateway patterns,
while keeping calendar-specific models and safety rules separate from mail
assumptions.

## Status

Draft. The event-mutation dry-run extension is selected for issue-resolution
workflow issue `codex-design-and-implement-review-loop-session-600/comm-001238`.
No GitHub issue URL or repository-number reference was supplied, and no
Codex-agent reference was supplied.

## Goals

- Expose a Swift library API for calendar providers such as Google Calendar.
- Provide `google-calendar-gateway-reader` and `google-calendar-gateway-writer` CLIs with mail-gateway-quality command behavior:
  structured JSON output, explicit config/auth commands, one-shot GraphQL
  transport, clear exit codes, and safe file/token handling.
- Keep provider logic behind adapters so Google Calendar is the first provider,
  not the only domain model.
- Make read and write capability explicit at config, auth, library, and CLI
  boundaries.
- Support focused tests for core API models, provider abstraction behavior, and
  CLI parsing/result semantics.

## Non-Goals

- No server-hosted credential storage.
- No broad calendar sync database in the first milestone.
- No long-running `serve` mode until one-shot GraphQL and CLI flows are stable.
- No provider-specific Google Calendar raw payload as the primary public API.
- No event mutation against live calendars during tests.

## Product Surface

The first milestone ships one executable:

```bash
google-calendar-gateway-reader [--config <path>] [--pretty] <command>
```

Required commands:

- `graphql --query <query>` or `graphql --query-file <path>`
- `config validate`
- `auth login --credential <id>`
- `auth status --credential <id>`
- `auth revoke --credential <id>`
- `cache prune [--calendar <id>|--all]`
- `--help`, `help`, and `--version`

The CLI writes business JSON to stdout and structured error JSON to stderr. It
must not print OAuth client secret content, access tokens, refresh tokens, or
secret-bearing environment values.

## Configuration

Default configuration path:

- `$XDG_CONFIG_HOME/google-calendar-gateway/config.toml`

Overrides:

- `--config <path>`
- `GOOGLE_CALENDAR_GATEWAY_CONFIG`

Credential profiles are separate from calendars. Calendars reference a
credential profile by ID, allowing multiple calendars to share an OAuth client
while keeping token stores scoped to a principal.

Example:

```toml
[[credentials]]
id = "google-personal"
provider = "google"
access_mode = "read_write"
oauth_client_secret_path = "~/.config/google-calendar-gateway/google-client.json"
token_store_path = "~/.config/google-calendar-gateway/tokens/personal.json"

[[calendars]]
id = "primary"
provider = "google"
credential_id = "google-personal"
calendar_id = "primary"
display_name = "Primary"
```

Environment path overrides follow the mail-gateway pattern with calendar-specific
names:

- `GOOGLE_CALENDAR_GATEWAY_CREDENTIAL_<CREDENTIAL_ID>_OAUTH_CLIENT_SECRET_PATH`
- `GOOGLE_CALENDAR_GATEWAY_CREDENTIAL_<CREDENTIAL_ID>_TOKEN_STORE_PATH`
- optional JSON-bearing equivalents may exist, but must never be logged

Validation rules:

- `credentials.id` and `calendars.id` are unique.
- `credentials.id` and `calendars.id` contain only ASCII letters, digits,
  period, underscore, and hyphen. IDs must not contain path separators,
  traversal segments, whitespace, or characters that collide after environment
  variable normalization.
- `calendars.credential_id` references an existing credential with the same
  provider.
- `access_mode` is one of `read`, `read_write`, or `full`.
- token stores are local user files and should be `0600` where supported.
- missing credential paths are valid only when a matching env override exists.
- `config validate` must not report `ok: true` for a fabricated config when no
  config file exists. The response must make `configFileExists` and
  `usingDefaults` explicit, and a missing requested config path is an error.

## Swift Library Boundary

The public library should expose calendar-domain types and protocols, not CLI
parsing types. Initial boundary:

- `GoogleCalendarGatewayClient`: type alias for the current application service,
  supporting account/calendar lookup, event search, event fetch,
  create/update/delete operations when authorized, auth status, login, revoke,
  cache pruning, and raw Google Calendar v3 API execution for less common
  resources.
- `CalendarEventProvider`: provider adapter protocol for Google Calendar and
  future event providers.
- `GoogleCalendarGatewayConfig`: parsed and validated configuration.
- canonical models currently implemented: `CalendarInfo`,
  `CalendarCapabilities`, `ProviderCalendarInfo`, `CalendarEvent`,
  `CalendarEventParticipant`, `CalendarEventDateTime`, and
  `CalendarEventReminders`, `CalendarEventReminder`,
  `CalendarConferenceData`, `CalendarConferenceEntryPoint`, and
  `CalendarEventConnection`.

Provider adapters must return canonical models plus small namespaced metadata
when provider details are unavoidable, for example `ProviderMetadata.google`.

For v1, `CalendarInfo` intentionally represents the configured local calendar
handle, including display name, provider, credential-backed principal email,
configured calendar IDs, default provider calendar ID, time zone, and
capabilities. A separate principal/account model is deferred until the product
needs to model shared calendars, delegated calendars, or multiple principals
pointing at the same provider calendar as first-class objects.

## GraphQL Design

One-shot GraphQL is the required business transport:

```bash
google-calendar-gateway-reader graphql --query-file ./query.graphql --variables-file ./vars.json
```

Initial schema:

```graphql
type Query {
  calendars: [CalendarInfo!]!
  calendar(id: ID!): CalendarInfo
  providerCalendars(credentialId: ID!): [ProviderCalendarInfo!]!
  freeBusy(input: FreeBusyInput!): FreeBusyResponse!
  events(input: EventSearchInput!): EventConnection!
  event(calendarId: ID!, eventId: ID!): CalendarEvent
}

type Mutation {
  createEvent(input: EventInput!, dryRun: Boolean = false): EventMutationPayload!
  updateEvent(input: EventUpdateInput!, dryRun: Boolean = false): EventMutationPayload!
  deleteEvent(calendarId: ID!, eventId: ID!, sendUpdates: SendUpdates, dryRun: Boolean = false): DeleteEventPayload!
}
```

The current lightweight parser supports flat argument forms for these fields
while the schema matures, for example:

```graphql
mutation {
  createEvent(
    calendarId: "personal",
    summary: "Planning",
    start: "2026-07-01T09:00:00Z",
    end: "2026-07-01T09:30:00Z"
  ) { id }
}
```

`--variables` and `--variables-file` accept JSON objects for transport
compatibility with mail-gateway. Variable substitution is reserved for a later
schema-complete GraphQL engine; v1 queries should continue to use flat literal
arguments. A query that references variables with `$name` must fail explicitly
while substitution is unsupported.

The lightweight parser must be string-literal aware when locating root fields,
matching argument names, and balancing parentheses or braces. Argument names or
delimiter characters inside quoted strings are user data and must not affect
field dispatch or argument extraction.

Only one root field may execute per GraphQL operation until a full multi-field
executor exists. Queries with multiple root fields must fail rather than return
a partial response.

Response objects are projected through the requested selection set for
dictionaries, arrays, nested canonical event values, and free/busy values. This
keeps provider metadata out of normal CLI responses unless callers explicitly
select it.

`Mutation` availability depends on configured access mode and granted token
scope. Read-only credentials must fail before provider mutation with a
machine-readable error such as `WRITE_DISABLED`.

Search input rules:

- `calendarId` is required.
- `timeMin` and `timeMax` use RFC 3339 date-time strings and are rejected
  before provider calls when malformed. Fractional seconds are allowed.
- `updatedMin` uses an RFC 3339 date-time string and is rejected before
  provider calls when malformed. Fractional seconds are allowed so clients can
  feed Google `updated` values back into incremental sync. Deleted events
  updated since that time are included by Google regardless of `showDeleted`.
- `query` is provider search text and is combined with structured filters.
- `maxResults` must be between 1 and 2500, matching Google Calendar
  `events.list` limits.
- pagination uses provider tokens wrapped in opaque cursors; `nextCursor` is
  returned from event connections and accepted as `cursor` on subsequent
  `events` queries.
- raw provider page tokens are not the preferred public contract. If exposed for
  compatibility, they must be documented as a provider escape hatch and callers
  must re-supply the same non-token query arguments across pages.
- `nextSyncToken` is exposed so clients can perform later incremental syncs.
- `syncToken` returns entries changed since a completed previous listing and
  cannot be combined with `query`, `timeMin`, `timeMax`, `updatedMin`, or
  `orderBy`. `showDeleted: false` is rejected with `syncToken` because Google
  always includes deletions during incremental sync.
- `orderBy` accepts `startTime` or `updated`; `startTime` requires
  `singleEvents: true`.
- by default, expanded event listings keep the existing start-time ordering.

Free/busy input rules:

- `calendarId` is the configured local calendar handle; `providerCalendarId` or
  `providerCalendarIds` can target one or more provider calendar IDs.
- if no provider calendar ID is supplied, the configured default provider
  calendar ID is used.
- `timeMin` and `timeMax` are required RFC 3339 date-time strings.
- `groupExpansionMax` must be between 1 and 100.
- `calendarExpansionMax` must be between 1 and 50, matching Google Calendar
  `freebusy.query` limits.
- responses include only busy intervals and provider/group errors, not event
  summaries, descriptions, attendees, or locations.

Event mutation date rules:

- `start` and `end` accept RFC 3339 date-time strings for timed events.
- `start` and `end` accept `YYYY-MM-DD` strings for all-day events.
- malformed date/time values are rejected before provider calls.
- `createEvent` requires both `start` and `end`.
- `updateEvent` requires at least one writable field in addition to `eventId`.
- attendee email values must be non-empty email-address-shaped strings.
- `recurrenceRules` accepts RRULE/RDATE/EXRULE/EXDATE strings. `DTSTART` and
  `DTEND` are rejected because start/end are represented by canonical event
  fields.
- recurring timed events require `timeZone` so the provider can expand the
  recurrence consistently.
- reminders expose `useDefault` plus up to 5 overrides. Overrides use `email` or
  `popup` with minutes between 0 and 40320.
- `reminderUseDefault: true` cannot be combined with reminder overrides.
- `colorId` is accepted as a provider color identifier and must be non-empty
  when supplied.
- `visibility` accepts `default`, `public`, `private`, or `confidential`.
- `transparency` accepts `opaque` or `transparent`.
- `createConference: true` requests Google Meet creation for Google Calendar
  writes. `conferenceRequestId` may be supplied with `createConference: true`
  as an idempotency key and must be non-empty when present.
- The existing `sendUpdates` validator treats omitted or whitespace-only input
  as absent; otherwise, the trimmed value must be one of Google Calendar's
  supported values: `all`, `externalOnly`, or `none`. Validation does not
  rewrite the live provider argument, and dry-run previews expose that same
  original provider-bound value.

Event mutation dry-run rules:

- `dryRun` is opt-in and defaults to `false` for service and GraphQL callers.
- The service resolves the configured account and enforces the existing write
  gate before validation, normalization, and any dry-run short-circuit. A
  read-only credential therefore returns `WRITE_DISABLED` even for a dry-run.
- Dry-run create/update responses include `dryRun: true`, the operation name,
  resolved target metadata, and `validatedInput` matching the exact normalized
  input that the live branch would pass to the provider. Dry-run delete
  responses include both local and resolved provider target identifiers,
  `wouldDelete: true`, and `deleted: false`.
- The short-circuit occurs before the provider adapter, so provider write
  methods are never called for dry-run requests.
- With dry-run omitted or false, existing mutation response shapes, validation,
  provider arguments, and behavior stay unchanged. GraphQL validation and
  access failures retain the existing `data: null` plus `errors` envelope.

The selected rationale, exact preview shapes, direct CLI contract, boundaries,
and verification requirements are defined in
`design-docs/specs/design-dry-run-event-mutations.md`.

## Provider Adapter Contract

Each provider implements:

- validate credential and calendar config
- interactive authorize
- auth status and revoke
- list calendars and capabilities
- search events
- get event
- query free/busy availability
- create, update, and delete event when configured for write access

Google Calendar v1 maps:

- Google calendar ID to `CalendarInfo.providerCalendarId`
- Google event ID to `CalendarEvent.id`
- recurring event IDs and instances into canonical recurrence fields
- Google event color, visibility, transparency, reminders, and conference data
  into canonical fields
- Google Meet create requests into `conferenceData.createRequest` with
  `conferenceDataVersion=1` on event insert and patch calls

Implemented Google Calendar calls:

- `calendarList.list` for provider calendar discovery
- `freebusy.query` for availability lookup
- `events.list` for event search
- `events.get` for event fetch
- `events.insert` for create
- `events.patch` for update
- `events.delete` for delete

`calendarList.list` uses the official Google Calendar API endpoint
`GET https://www.googleapis.com/calendar/v3/users/me/calendarList`.
`freebusy.query` uses the official Google Calendar API endpoint
`POST https://www.googleapis.com/calendar/v3/freeBusy`.

Provider HTTP failures map into actionable gateway codes for callers:

- HTTP 401 and 403: `AUTH_REQUIRED`
- HTTP 404 on event item operations: `EVENT_NOT_FOUND`
- HTTP 410: `SYNC_TOKEN_EXPIRED`
- HTTP 429: `PROVIDER_RATE_LIMITED`
- other non-2xx provider responses: `PROVIDER_API_ERROR`

## CLI Behavior Mapping From Mail Gateway

Adopted patterns:

- one executable command router with deterministic help text
- `--config`, `--pretty`, JSON stdout, and structured JSON stderr
- `config validate`, `auth <login|revoke|status>`, `cache prune`, and `graphql`
- explicit provider credentials and token stores
- no secrets in GraphQL, logs, or errors

Concrete `mail-gateway` reference files used for these patterns:

- `Sources/MailGatewayCore/MailGatewayCLI.swift`
- `Sources/MailGatewayCore/ConfigLoading.swift`
- `Sources/MailGatewayCore/MailGatewayGraphQL.swift`
- `Sources/MailGatewayCore/GmailOAuthSupport.swift`

Intentional calendar-specific changes:

- use `calendars` instead of mail `accounts`
- use `events`, `freeBusy`, and event mutations instead of
  threads/messages/files
- omit mail attachment download commands unless event attachment/file support is
  explicitly designed later
- use `read_write` rather than mail `read_send`
- gate all writes through access mode and granted OAuth scopes

Cursor- or Codex-agent-specific behavior must stay outside provider adapters.
If a future Cursor CLI integration is required, implement it as a thin CLI
transport adapter that calls the same library and GraphQL surface.

## Auth And Security

Google Calendar uses installed-app OAuth. Scope selection must be least
privilege:

- `read`: read-only calendar event access
- `read_write`: read plus event create/update/delete access
- `full`: broad Google Calendar API access for raw operations such as ACLs,
  calendar metadata, settings, channels, and watch notification endpoints
- provider calendar discovery requires read-only CalendarList access
- free/busy availability lookup requires Google Calendar free/busy read access

Google Calendar scope selection follows the current Google Calendar API scope
documentation:

- `read`:
  `https://www.googleapis.com/auth/calendar.events.readonly` and
  `https://www.googleapis.com/auth/calendar.calendarlist.readonly` and
  `https://www.googleapis.com/auth/calendar.freebusy`
- `read_write`:
  `https://www.googleapis.com/auth/calendar.events` and
  `https://www.googleapis.com/auth/calendar.calendarlist.readonly` and
  `https://www.googleapis.com/auth/calendar.freebusy`
- `full`: `https://www.googleapis.com/auth/calendar`

The broader `calendar.readonly` and `calendar` scopes are accepted when already
present in token metadata for compatible configured modes. This scope coverage
rule applies consistently to `auth status`, capability reporting, and every
request-time token validation path. Event-only or calendar-list-only tokens are
treated as scope mismatches because they cannot cover both `calendarList.list`
and `freebusy.query`. Secrets and token values must not be printed, committed,
or embedded in design examples.

Implemented auth behavior:

- Desktop OAuth client JSON is required for `auth login`.
- The login flow uses a loopback callback, browser launch, PKCE, `offline`
  access, and consent prompting to obtain a refresh token.
- The loopback receiver keeps accepting local connections until the expected
  callback path and state arrive or the login deadline expires. Stray requests
  receive an error response and do not abort the login flow.
- Expired access tokens are refreshed from `refresh_token` when possible. If
  the provider returns a rotated `refresh_token`, the new token replaces the
  old token in the store.
- Token refresh persistence should serialize read-modify-write access to the
  token store where the platform supports file locking. If locking is not
  available, the concurrency limitation must be documented.
- Token stores are written under user-only directories with `0600` file
  permissions where supported.
- `auth revoke` calls the provider revocation endpoint on the stored refresh or
  access token on a best-effort basis before deleting local token material. The
  response reports provider revocation and local deletion outcomes separately.
  Environment-supplied token stores cannot be deleted locally and must be
  reported as such.

Write operations are high-risk:

- tests must use fakes unless explicitly marked live/integration
- create, update, and delete expose the opt-in dry-run behavior defined in
  `design-docs/specs/design-dry-run-event-mutations.md`; dry-run is not a
  substitute for write access and never bypasses the write gate
- event deletion must require an explicit event ID and calendar ID
- provider write errors must be surfaced without dumping request bodies that may
  contain private event details

## Cache And Local File Safety

`cache prune` must only remove paths inside the configured cache root after
canonicalization and symlink resolution. Prefix-only string checks are not
sufficient. Removal failures must be reported as errors and must not be counted
as successfully pruned paths.

The command exists for the gateway cache surface. Until a feature writes cache
entries, documentation and command output should make the empty-cache case
clear rather than implying data was pruned.

## Rollout And Verification

Implementation should proceed in this order:

1. Core canonical models and provider protocol.
2. Config loader and validation.
3. Fake provider-backed library and CLI command behavior.
4. Google Calendar adapter skeleton and auth status/login/revoke flow.
5. GraphQL read operations, then guarded write operations.
6. Focused tests and adversarial review before handoff.

Riela status:

- `codex-design-and-implement-review-loop-session-141` completed intake, design
  update, design self-review, and design review.
- The one low-severity design-review finding asked for concrete mail-gateway
  reference files; those are now cited in this document and the active
  implementation plan.
- Riela Step 4 implementation-plan creation failed after interruption and
  supervised reruns because codex-agent authentication was unavailable, so
  implementation continued locally against the accepted design.

Required verification commands for full implementation handoff:

```bash
mise run lint
swift build
swift test
```

Optional live integration checks are documented in
`design-docs/specs/live-integration.md` and require explicit opt-in.

## Risks

- OAuth token and calendar data handling are security-sensitive.
- Write operations can mutate real calendars; tests must not require live
  credentials.
- Copying mail-gateway directly would import mail-specific naming and attachment
  assumptions.
- Package target changes can affect build, release, and Homebrew automation.
- Long-running transport should not be added before one-shot behavior is
  verified.
