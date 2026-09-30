# Command

## Status

Draft

## Current CLI

```bash
google-calendar-gateway-reader [--config <path>] [--pretty] <command>
```

Implemented commands:

- `google-calendar-gateway-reader --help`
- `google-calendar-gateway help`
- `google-calendar-gateway-reader --version`
- `google-calendar-gateway-reader config validate`
- `google-calendar-gateway-reader auth status --credential <id>`
- `google-calendar-gateway-reader auth revoke --credential <id>`
- `google-calendar-gateway-reader auth login [--credential <id>]`
- `google-calendar-gateway-reader cache prune --calendar <id>`
- `google-calendar-gateway-reader cache prune --all`
- `google-calendar-gateway-reader graphql --query <query> [--variables <json>|--variables-file <path>]`
- `google-calendar-gateway-reader graphql --query-file <path> [--variables <json>|--variables-file <path>]`

Selected event-mutation command addition for issue-resolution workflow issue
`codex-design-and-implement-review-loop-session-600/comm-001238`:

- `google-calendar-gateway-writer event create --calendar <id> [event input flags] [--dry-run]`
- `google-calendar-gateway-writer event update --calendar <id> --event-id <id> [event input flags] [--dry-run]`
- `google-calendar-gateway-writer event delete --calendar <id> --event-id <id> [--provider-calendar <id>] [--send-updates <value>] [--dry-run]`

These commands are thin adapters over `GoogleCalendarGatewayService`; they do not own
separate validation, preview, or provider logic. Create and update event input
flags map to the canonical GraphQL/service input using kebab-case names, with
collection values encoded as typed JSON arrays. Boolean event flags accept a
bare flag or an exact lowercase `true`/`false` value. The exact collection
element schemas, examples, defaults, and invalid-value behavior are defined in
`design-docs/specs/design-dry-run-event-mutations.md`.

The CLI writes business payloads as JSON on stdout and structured errors as
JSON on stderr. `auth login` runs Google installed-app OAuth for desktop client
JSON. Token stores can also be supplied through the config file or
`GOOGLE_CALENDAR_GATEWAY_CREDENTIAL_<ID>_TOKEN_STORE_JSON`.
Unknown flags are rejected with `INVALID_ARGUMENT` and exit code 2 before
loading config or contacting providers.
Unexpected positional arguments are rejected the same way, before config loading
or side effects.
Global `--help` and `--version` reject unknown flags and reject attached values
such as `--version=false` before returning success output.
Duplicate flags are rejected before config loading, provider calls, or global
success output; callers must supply each flag at most once.
Variable JSON is parsed and validated as an object for CLI compatibility with
the mail-gateway transport contract; the current lightweight GraphQL parser
still uses flat literal arguments. Until variable substitution is implemented,
queries that reference GraphQL variables with `$name` must fail with
`INVALID_ARGUMENT` instead of silently ignoring supplied variables.

Exit codes:

| Code | Meaning |
|------|---------|
| 0 | success |
| 1 | unexpected failure |
| 2 | invalid CLI usage or invalid argument |
| 3 | configuration or credential error |
| 4 | authentication required |
| 5 | GraphQL execution or provider API failure |
| 6 | write operation disabled by configured access mode |

Implemented GraphQL-style root fields:

- `calendars`
- `calendar(id: "...")`
- `providerCalendars(credentialId: "...")`
- `freeBusy(calendarId: "...", providerCalendarIds: ["..."], timeMin: "...", timeMax: "...")`
- `events(calendarId: "...", providerCalendarId: "...", timeMin: "...", timeMax: "...", updatedMin: "...", cursor: "...")`
- `events(calendarId: "...", syncToken: "...", showDeleted: true, singleEvents: false)`
- `event(calendarId: "...", providerCalendarId: "...", eventId: "...")`
- `createEvent(calendarId: "...", summary: "...", start: "...", end: "...", recurrenceRules: ["RRULE:..."], colorId: "7", createConference: true, dryRun: true)`
- `updateEvent(calendarId: "...", eventId: "...", summary: "...", reminderOverrides: ["popup:30"], visibility: "private", transparency: "transparent", dryRun: true)`
- `deleteEvent(calendarId: "...", eventId: "...", sendUpdates: "all|externalOnly|none", dryRun: true)`
- `calendarAPI(credentialId: "...", method: "GET|POST|PUT|PATCH|DELETE", path: "/colors", query: ["name=value"], body: "{\"json\":true}", access: "auto|read|write")`

The lightweight GraphQL executor accepts exactly one top-level root field per
operation. A document containing multiple root fields must fail with
`INVALID_ARGUMENT`; silent partial results are not allowed. Resolver dispatch is
based on the root field name, and write resolver names remain write-gated even
if a caller labels the operation as `query`.

Write fields fail with `WRITE_DISABLED` before provider mutation when the
credential is not configured with `access_mode = "read_write"` or
`access_mode = "full"`.
`sendUpdates` is validated before provider mutation. Omitted or whitespace-only
input is accepted as absent; otherwise, the trimmed value must be `all`,
`externalOnly`, or `none`. The existing rule does not rewrite the original
provider-bound string. Dry-run previews preserve the same string, including
whitespace-only or padded allowed input, while an omitted value is `null`.

`dryRun` is an optional Boolean on `createEvent`, `updateEvent`, and
`deleteEvent`, and `--dry-run` is the corresponding direct `event` command
flag. Both default to `false`. The service enforces the write gate and all
existing validation before returning a preview, so read-only dry-runs still
fail with `WRITE_DISABLED`. A successful create/update preview contains
`dryRun: true`, the operation, resolved target metadata, and `validatedInput`
matching the normalized input the live branch would pass to the provider. A
delete preview contains the resolved target identifiers, `wouldDelete: true`,
and `deleted: false`. No dry-run reaches a provider write method. GraphQL error
envelopes and CLI stderr error envelopes remain unchanged.

`freeBusy` returns canonical busy intervals without event details. `timeMin` and
`timeMax` are required RFC 3339 date-time strings. The accepted form includes
timestamps with or without fractional seconds and with either `Z` or an explicit
numeric offset. When no
`providerCalendarId` or `providerCalendarIds` argument is supplied, the
configured default provider calendar ID is used.

`events` supports initial and incremental sync flows. `updatedMin`, `timeMin`,
and `timeMax` must be RFC 3339 date-time strings, including Google-emitted
fractional-second values such as `.000Z`. `syncToken` accepts the
`nextSyncToken` from a completed previous event listing and cannot be combined
with `query`, `timeMin`, `timeMax`, `updatedMin`, or `orderBy`; `showDeleted:
false` is also rejected with `syncToken`.

Event mutations support recurrence and reminders. `recurrenceRules` accepts
Google-compatible RRULE/RDATE/EXRULE/EXDATE strings; `DTSTART` and `DTEND` are
rejected because event start/end are supplied separately. Reminder overrides use
flat literals in the form `popup:<minutes>` or `email:<minutes>` and support up
to 5 overrides with minutes between 0 and 40320.

Event mutations also support provider event metadata and Google Meet creation.
`colorId` must be non-empty when supplied. `visibility` accepts `default`,
`public`, `private`, or `confidential`; `transparency` accepts `opaque` or
`transparent`. `createConference: true` requests a Google Meet link on Google
Calendar writes, and `conferenceRequestId` may be supplied with
`createConference: true` as a non-empty idempotency key.

`calendarAPI` is the raw official Google Calendar v3 resolver for less common
resources such as ACLs, calendar metadata, colors, settings, channels, and watch
notification endpoints. `path` must be a relative Calendar v3 path starting with
`/`; absolute URLs and embedded query strings are rejected. Broad API usage
should use `access_mode = "full"` so OAuth requests the full Calendar scope.
Mutating HTTP methods (`POST`, `PUT`, `PATCH`, and `DELETE`) are always
write-gated before provider calls. The `access` argument is only a token-scope
hint and cannot downgrade a mutating method into a read operation.

GraphQL resolver failures should be returned through the GraphQL `errors` array
with machine-readable `extensions.code` and any safe diagnostic details. CLI
usage failures that occur before GraphQL execution may still be reported as
top-level stderr errors.
