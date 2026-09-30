# Dry-Run Event Mutations

## Status And Rationale

Selected design for issue-resolution workflow issue
`codex-design-and-implement-review-loop-session-600/comm-001238`.
No GitHub issue URL or repository-number reference was supplied. No Codex-agent
reference was supplied, so this design is based on the authoritative workflow
intake and the local repository only.

Dry-run event mutations are selected over GraphQL variable substitution and
typed watch channels. Dry-run directly reduces the risk of accidental calendar
writes for AI-agent and CLI callers, builds on the existing guarded mutation
path, and can be verified completely with fake providers. Variable
substitution improves transport ergonomics but not mutation safety. Watch
channels require live push-notification infrastructure and have a larger
operational boundary.

## Scope

The feature covers `createEvent`, `updateEvent`, and `deleteEvent` through all
three public entry points:

- the `GoogleCalendarGatewayService` library boundary, with `dryRun` defaulting to
  `false`
- the lightweight GraphQL executor, with an optional `dryRun: Boolean`
  argument defaulting to `false`
- direct CLI commands `event create`, `event update`, and `event delete`, with
  an optional `--dry-run` Boolean flag defaulting to `false`

The direct `event` CLI command family is a new thin adapter. It must construct
the same canonical mutation input and call the shared mutation-result methods
that also back GraphQL; it must not implement separate preview, validation,
access-control, or provider logic.

Raw `calendarAPI` requests are outside this feature. A dry-run option for
arbitrary provider API writes would require method-specific request semantics
and is not implied by this design.

## Library Method And Result Contract

All dry-run behavior is owned by `GoogleCalendarGatewayService`. The implementation
adds one shared public result type and three result-producing methods:

- `createEventMutation(input:dryRun:) throws -> CalendarEventMutationResult`
- `updateEventMutation(input:dryRun:) throws -> CalendarEventMutationResult`
- `deleteEventMutation(accountId:calendarId:eventId:sendUpdates:dryRun:) throws
  -> CalendarEventMutationResult`

`dryRun` defaults to `false` on these methods. The exact public result and
preview API is:

```swift
public enum CalendarEventMutationOperation: String, Sendable {
  case createEvent
  case updateEvent
  case deleteEvent
}

public struct CalendarEventDeletionPreview: Sendable {
  public let eventId: String
  public let sendUpdates: String?
  public var wouldDelete: Bool { true }
  public var deleted: Bool { false }

  // Module-internal: only validated service code constructs this value.
  init(eventId: String, sendUpdates: String?)
}

public enum CalendarEventMutationPreviewPayload: Sendable {
  case create(validatedInput: CalendarEventInput)
  case update(validatedInput: CalendarEventInput)
  case delete(target: CalendarEventDeletionPreview)
}

public struct CalendarEventMutationPreview: Sendable {
  public let accountId: String
  public let resolvedCalendarId: String
  public let payload: CalendarEventMutationPreviewPayload
  public var operation: CalendarEventMutationOperation { get }
  public var jsonObject: [String: Any] { get }

  // Module-internal: only the service combines target data and payload.
  init(
    accountId: String,
    resolvedCalendarId: String,
    payload: CalendarEventMutationPreviewPayload
  )
}

public enum CalendarEventMutationResult {
  case event(CalendarEvent)
  case deletion([String: Any])
  case preview(CalendarEventMutationPreview)
  public var jsonObject: [String: Any] { get }
}
```

All declarations, cases, stored properties, computed properties, and
`jsonObject` projections shown as public are visible to library clients. The
two initializers shown without `public` are module-internal. Callers can inspect
and switch over previews, but only the validated service path can construct a
complete preview.

`CalendarEventMutationPreview` stores exactly one payload enum case. Its
`operation` is computed from that case (`create` maps to `createEvent`,
`update` to `updateEvent`, and `delete` to `deleteEvent`) and is never stored
independently. Create and update carry only their provider-bound
`CalendarEventInput`; delete carries only `CalendarEventDeletionPreview`.
Thus a create operation with an update/delete payload, an update operation with
a create/delete payload, or a delete operation with event input is not
representable. Before storage, the internal preview initializer requires
`accountId == validatedInput.accountId` for create/update; all associated
values have already passed service validation.

`CalendarEventMutationResult.jsonObject` is the single shared projection used
by dynamic library wrappers, GraphQL, and CLI. It delegates `.preview` to
`CalendarEventMutationPreview.jsonObject`; transports do not switch over the
payload or construct preview dictionaries. The exact JSON shape is pinned
below.

The complete compatibility mapping is:

| Existing or affected service method | Swift result type | Required behavior |
| --- | --- | --- |
| `createEvent(input:dryRun:)` | `Any` | Add `dryRun: Bool = false`; project `.event` to the existing event dictionary and `.preview` to preview JSON. |
| `updateEvent(input:dryRun:)` | `Any` | Add `dryRun: Bool = false`; project `.event` to the existing event dictionary and `.preview` to preview JSON. |
| `deleteEvent(accountId:calendarId:eventId:sendUpdates:dryRun:)` | `[String: Any]` | Add `dryRun: Bool = false`; return the existing provider dictionary for `.deletion` and preview JSON for `.preview`. |
| `createCalendarEvent(input:)` | `CalendarEvent` | Keep the signature unchanged and live-only; delegate with `dryRun: false` and unwrap `.event`. This preserves typed-call source and result compatibility. |
| `updateCalendarEvent(input:)` | `CalendarEvent` | Keep the signature unchanged and live-only; delegate with `dryRun: false` and unwrap `.event`. This preserves typed-call source and result compatibility. |
| `createEventMutation(input:dryRun:)` | `CalendarEventMutationResult` | New shared-result entry point used by the dynamic wrapper and direct CLI adapter. |
| `updateEventMutation(input:dryRun:)` | `CalendarEventMutationResult` | New shared-result entry point used by the dynamic wrapper and direct CLI adapter. |
| `deleteEventMutation(accountId:calendarId:eventId:sendUpdates:dryRun:)` | `CalendarEventMutationResult` | New shared-result entry point used by the dictionary wrapper and direct CLI adapter. |

No `dryRun` parameter is added to `createCalendarEvent(input:)` or
`updateCalendarEvent(input:)`: a method returning `CalendarEvent` cannot
honestly represent a preview without fabricating an event. Callers that need a
typed dry-run result use the new `*EventMutation` methods. Existing calls to
all five current methods compile unchanged, and their `dryRun = false` dynamic
shapes, validation behavior, provider arguments, and provider effects remain
unchanged.

`CalendarEventProvider.createEvent`, `.updateEvent`, and `.deleteEvent` retain
their existing signatures and result types. Providers never receive a dry-run
flag or construct a preview.

The shared `CalendarEventMutationResult.jsonObject` projection is
mode-dependent and compatibility-preserving:
`.event` projects the contained `CalendarEvent.graphQLObject` with no wrapper;
`.deletion` projects the contained provider dictionary unchanged; and
`.preview` projects the preview object defined below. Both the existing dynamic
service methods and the two transport adapters use this projection rather than
switching independently on mutation operation, payload, or dry-run state.

## Service Data Flow And Ordering

Each mutation follows one service-owned path:

1. Resolve the configured local calendar/account and its credential.
2. Enforce the existing write gate. Credentials configured with
   `access_mode = "read"` fail with `WRITE_DISABLED`, including when `dryRun`
   is `true`.
3. Apply all existing operation-specific identifier, event, date/time,
   recurrence, reminder, and metadata validation. Apply the existing
   `validateSendUpdates` check without rewriting the supplied value.
4. Normalize the provider-bound input using the shared normalization path and
   independently resolve the effective provider calendar ID for preview target
   metadata.
5. If `dryRun` is `true`, return the preview described below.
6. Otherwise invoke the existing provider mutation and return its existing
   response unchanged.

The preview short-circuit is after the write gate, validation, and
normalization, but before every `CalendarEventProvider` write method. Provider
protocol methods do not receive a dry-run flag and provider adapters do not
produce previews. This makes a provider call during dry-run a contract
violation and keeps preview behavior provider-independent.

For create/update, the same normalized `CalendarEventInput` value is either
stored in the preview or passed to the provider. For delete, the same resolved
provider calendar ID, normalized event ID, and original validated
`sendUpdates` value are either stored in the preview or passed to the provider.

`sendUpdates` behavior is deliberately unchanged for live calls. The existing
`validateSendUpdates` implementation applies `nonBlank` only to decide whether
the supplied value is absent or one of `all`, `externalOnly`, or `none`; it does
not replace the value stored in `CalendarEventInput` or passed to
`CalendarEventProvider`. Therefore `nil` remains `nil`, whitespace-only input
passes validation and remains the original whitespace string, and a padded
allowed value such as `" externalOnly "` passes validation and remains padded.
Dry-run stores and projects that same original provider-bound value. This
preserves the accepted additive scope and makes preview/live equivalence exact
without changing existing caller behavior.

## Preview Contract

`CalendarEventMutationPreview.jsonObject` emits business JSON. Every preview
includes:

- `dryRun: true`
- `operation`, equal to `createEvent`, `updateEvent`, or `deleteEvent`

Every preview also includes `accountId` and `resolvedCalendarId`, identifying
the configured local account and effective provider calendar target. Create and
update previews additionally include `validatedInput`, the JSON projection of
the exact normalized `CalendarEventInput` that the live branch would pass to
`CalendarEventProvider`. The object has the same complete field set for both
operations; keys are never omitted. This fixed shape lets callers distinguish
an absent optional value (`null`) from an empty validated collection (`[]`) and
from an explicit Boolean default (`false`). No provider-assigned event ID,
link, timestamp, conference result, or generated conference request ID is
fabricated.

### Canonical `validatedInput` Schema

| Field | JSON type and allowed value | Create | Update |
| --- | --- | --- | --- |
| `accountId` | string; the input's local account handle, unchanged | required | required |
| `calendarId` | string or null; explicitly supplied provider calendar ID normalized by `normalizedOptionalProviderCalendarId`, or null when the provider will use the account default | optional | optional |
| `eventId` | string or null; normalized with the existing `nonBlank` helper | optional and normally null | required string |
| `summary` | string or null | optional | optional |
| `description` | string or null | optional | optional |
| `location` | string or null | optional | optional |
| `colorId` | string or null | optional | optional |
| `visibility` | string or null; enum raw value `default`, `public`, `private`, or `confidential` | optional | optional |
| `transparency` | string or null; enum raw value `opaque` or `transparent` | optional | optional |
| `start` | string or null; validated RFC 3339 date-time or `YYYY-MM-DD` date | required string | optional |
| `end` | string or null; validated RFC 3339 date-time or `YYYY-MM-DD` date | required string | optional |
| `timeZone` | string or null | optional | optional |
| `attendeeEmails` | array of strings | present, possibly empty | present, possibly empty |
| `recurrenceRules` | array of strings | present, possibly empty | present, possibly empty |
| `reminderUseDefault` | Boolean or null | optional | optional |
| `reminderOverrides` | array of reminder objects | present, possibly empty | present, possibly empty |
| `createConference` | Boolean | present; defaults to false | present; defaults to false |
| `conferenceRequestId` | string or null | optional | optional |
| `sendUpdates` | string or null; exact provider-bound value after existing validation; null only when omitted | optional | optional |

Each reminder override is encoded as exactly
`{"method":"email|popup","minutes":<integer>}`. `method` uses the enum raw
value, `minutes` is a JSON integer in the validated range 0 through 40320, and
the array preserves caller order. `attendeeEmails` and `recurrenceRules` also
preserve caller order. Collections are not sorted or deduplicated.

All optional scalar keys are emitted with JSON `null` when absent; optional
keys are never omitted. Empty collections are emitted as `[]` and never as
`null`. `reminderUseDefault` remains `null` when omitted and preserves an
explicit `false`; it is not defaulted. `createConference` is always a JSON
Boolean and is `false` when omitted. Enum values use the lowercase/camel-case
raw strings listed above, never enum case names or numeric encodings.

The preview value is based on `normalizedEventInput(_:)`, not on a new
preview-only normalizer. That function preserves `accountId`; applies
`normalizedOptionalProviderCalendarId` to `calendarId`; applies `nonBlank` to
`eventId`; and passes `sendUpdates` and every other scalar, enum, Boolean,
array, and reminder value through unchanged.
Consequently, optional strings such as `summary`, `description`, `location`,
`colorId`, `start`, `end`, `timeZone`, and `conferenceRequestId` are not newly
trimmed, rewritten, or collapsed to null for previews. Date/time strings are
not reformatted, time zones are not converted, and arrays are not reordered.
The same normalized input feeds preview and provider branches, and the feature
does not change the live path.

When no explicit provider calendar ID is supplied,
`validatedInput.calendarId` is `null`, exactly as it is in the provider-bound
input, while the top-level `resolvedCalendarId` reports the account default the
provider will target. If an explicit ID is supplied, the normalized explicit
value appears in both fields. A direct service caller's create input may carry
an `eventId`; because `normalizedEventInput(_:)` preserves its normalized
value, the preview does too rather than forcing it to null. GraphQL and CLI
create adapters do not populate `eventId`.

For byte serialization outside GraphQL projection, use UTF-8 JSON with the
existing sorted-key encoder. Compact output contains no insignificant
whitespace; a caller-selected pretty mode may add whitespace only. Object key
order is lexicographic at every object level, array order remains as supplied,
and repeated serialization of the same canonical value must produce identical
bytes. GraphQL selection order does not change the underlying value or these
field encodings.

Example create preview:

```json
{
  "accountId": "personal",
  "dryRun": true,
  "operation": "createEvent",
  "resolvedCalendarId": "primary",
  "validatedInput": {
    "accountId": "personal",
    "attendeeEmails": [],
    "calendarId": null,
    "colorId": null,
    "conferenceRequestId": null,
    "createConference": false,
    "description": null,
    "end": "2026-07-01T09:30:00Z",
    "eventId": null,
    "location": null,
    "recurrenceRules": [],
    "reminderOverrides": [],
    "reminderUseDefault": null,
    "sendUpdates": "none",
    "start": "2026-07-01T09:00:00Z",
    "summary": "Planning",
    "timeZone": null,
    "transparency": null,
    "visibility": null
  }
}
```

A delete preview has no event payload. It includes the target identifiers and
an explicit confirmation marker. Its JSON object emits exactly these eight
keys; none are omitted:

| Key | JSON type and value |
| --- | --- |
| `accountId` | string; configured local account handle |
| `deleted` | Boolean; always `false` |
| `dryRun` | Boolean; always `true` |
| `eventId` | string; normalized deletion target event ID |
| `operation` | string; always `deleteEvent` |
| `resolvedCalendarId` | string; effective provider calendar target |
| `sendUpdates` | string or null; exact provider-bound value after existing validation, or JSON `null` only when omitted |
| `wouldDelete` | Boolean; always `true` |

In particular, `sendUpdates` is always present. An omitted input is a nil Swift
`CalendarEventDeletionPreview.sendUpdates` value and projects as JSON `null`;
the key is never omitted. Whitespace-only and padded allowed inputs project as
their original strings because those are the exact values the unchanged live
branch would pass to the provider.

Example with an explicitly supplied `sendUpdates` value:

```json
{
  "accountId": "personal",
  "deleted": false,
  "dryRun": true,
  "eventId": "event-1",
  "operation": "deleteEvent",
  "resolvedCalendarId": "primary",
  "sendUpdates": "none",
  "wouldDelete": true
}
```

`wouldDelete` and `deleted` come from the constant computed properties on
`CalendarEventDeletionPreview`; callers cannot initialize them with
contradictory values. `wouldDelete: true` confirms that the normalized request
reached the preview boundary. `deleted: false` confirms that no deletion occurred.
`resolvedCalendarId` is the exact string that the live service branch would
pass to the provider; `accountId` is the configured local handle used to
resolve it. The event ID is normalized with `nonBlank`. `sendUpdates` is
checked by the existing validator and otherwise preserved, matching the live
provider argument exactly; only an omitted value is represented by the
required JSON `null` value above.

## GraphQL Contract

The lightweight executor accepts a Boolean literal `dryRun` on all three event
mutation root fields. Omission and `dryRun: false` select the existing live
path. Non-Boolean literals fail with the existing `INVALID_ARGUMENT` GraphQL
execution behavior.

The executor maps `createEvent` to `GoogleCalendarGatewayService.createEvent`,
`updateEvent` to `GoogleCalendarGatewayService.updateEvent`, and `deleteEvent` to
`GoogleCalendarGatewayService.deleteEvent`, passing the extracted Boolean to the new
defaulted parameter. Those wrappers delegate to the corresponding shared
`createEventMutation`, `updateEventMutation`, or `deleteEventMutation` method.
For live results, the GraphQL field continues to see the existing unwrapped
event or deletion dictionary. For a preview, it sees the shared preview JSON
and applies the requested GraphQL selection normally; the executor does not
reconstruct or renormalize preview fields.

Example:

```graphql
mutation {
  createEvent(
    calendarId: "personal",
    summary: "Planning",
    start: "2026-07-01T09:00:00Z",
    end: "2026-07-01T09:30:00Z",
    dryRun: true
  ) {
    dryRun
    operation
    validatedInput { accountId calendarId summary start end }
  }
}
```

Dry-run success is returned under the normal `data.<field>` location. Validation,
access, and other failures retain the existing envelope: `data: null` plus an
`errors` array containing the same message, `extensions.code`, exit code, and
safe details that the equivalent non-dry-run request would produce. No new
top-level error shape is introduced.

## CLI Contract

The canonical direct commands are singular `event` commands:

```text
google-calendar-gateway-writer event create --calendar <local-id> [event input flags] [--dry-run]
google-calendar-gateway-writer event update --calendar <local-id> --event-id <id> [event input flags] [--dry-run]
google-calendar-gateway-writer event delete --calendar <local-id> --event-id <id> [--provider-calendar <id>] [--send-updates <value>] [--dry-run]
```

Create and update input flags map one-to-one to the canonical event input
already accepted by GraphQL, using kebab-case names:

- common target flags: required `--calendar` for the local account handle and
  optional `--provider-calendar` for an explicit provider calendar ID
- update target flag: required `--event-id`
- scalar event flags: `--summary`, `--description`, `--location`, `--color-id`,
  `--visibility`, `--transparency`, `--start`, `--end`, `--time-zone`,
  `--conference-request-id`, and `--send-updates`
- Boolean event flags: `--reminder-use-default` and `--create-conference`
- collection event flags: `--attendee-emails`, `--recurrence-rules`, and
  `--reminder-overrides`, each encoded as a JSON array so values containing
  commas remain unambiguous

Collection flags use these exact JSON representations:

| Flag | Accepted JSON array | Element validation |
|------|---------------------|--------------------|
| `--attendee-emails` | `["alice@example.com","bob@example.com"]` | Every element must be a JSON string. The service then applies the existing non-empty, email-address-shaped validation to each string. |
| `--recurrence-rules` | `["RRULE:FREQ=WEEKLY;COUNT=4","EXDATE:20260715T090000Z"]` | Every element must be a JSON string. The service then applies the existing non-empty rule, rejects `DTSTART` and `DTEND`, and requires `--time-zone` for recurring timed events. |
| `--reminder-overrides` | `["popup:30","email:1440"]` | Every element must be a JSON string in the exact `<method>:<minutes>` form. `method` is exactly `popup` or `email`; `minutes` is an unsigned base-10 integer. JSON objects such as `{"method":"popup","minutes":30}` are not accepted. The service then enforces at most five elements, minutes from 0 through 40320 inclusive, and the conflict with `--reminder-use-default true`. |

An empty array is accepted for each collection flag and preserves the canonical
empty-array value. The array preserves caller order and duplicate elements;
the CLI performs no trimming, sorting, or deduplication. A missing collection
flag supplies the canonical empty array. A malformed JSON value, a non-array
top-level value, an element of the wrong JSON type, or a malformed reminder
literal fails as CLI `INVALID_ARGUMENT` with exit code 2 before configuration
loading, service creation, or provider access. After successful decoding,
domain validation remains service-owned and retains the service's existing
business error code and exit code.

The three Boolean flags `--reminder-use-default`, `--create-conference`, and
`--dry-run` accept exactly the same forms:

```text
--flag
--flag true
--flag false
--flag=true
--flag=false
```

The bare form means `true`; explicit values are case-sensitive lowercase
`true` or `false`. Omitted `--reminder-use-default` maps to `nil`, so the
preview contains `reminderUseDefault: null`; an explicit `false` is preserved.
Omitted `--create-conference` and `--dry-run` both default to `false`.
Empty values, values other than exact lowercase `true` or `false`, and duplicate
occurrences fail as CLI `INVALID_ARGUMENT` with exit code 2 before
configuration loading, service creation, or provider access. These failures
retain the existing top-level stderr error envelope. Failures returned after
service invocation retain their existing business error codes and exit codes.

When `--dry-run` succeeds, stdout contains exactly the service preview JSON. It
must include `dryRun: true`; delete additionally includes `wouldDelete: true`
and `deleted: false`. The CLI must not claim success from a provider or print a
fabricated event ID. Without `--dry-run`, command behavior is the existing live
service behavior.

The CLI create, update, and delete handlers call `createEventMutation`,
`updateEventMutation`, and `deleteEventMutation`, respectively, then serialize
the shared JSON projection. They do not call `CalendarEventProvider`, construct
preview dictionaries, or normalize inputs independently.

### CLI Service Injection Boundary

`GoogleCalendarGatewayCLI` gains one stored service factory with the module-internal
shape `(GoogleCalendarGatewayConfig) -> GoogleCalendarGatewayService`. Its existing public
`init()` remains source-compatible and installs the production factory
`{ GoogleCalendarGatewayService(config: $0) }`, which retains the live provider. A
second module-internal `init(serviceFactory:)` is visible to the test target
through `@testable import GoogleCalendarGatewayCore`; it does not become a public CLI
or library option.

The `event create`, `event update`, and `event delete` dispatch path first loads
and validates configuration exactly as production does, then passes that
loaded `GoogleCalendarGatewayConfig` to the stored factory. The resulting service is
passed into a shared event-command handler. The handler has no fallback that
constructs `GoogleCalendarGatewayService` or `GoogleCalendarLiveClient` internally.
Parsing failures that occur before service creation retain the current CLI
error path.

Direct CLI tests construct a reference-type recording fake provider, then
inject `{ GoogleCalendarGatewayService(config: $0, provider: recordingFake) }` into
`GoogleCalendarGatewayCLI`. Each test invokes `run(arguments:environment:)` with the
real `event create`, `event update`, or `event delete` arguments and a temporary
local config, decodes stdout, and asserts both the preview contract and zero
create/update/delete calls on the same recording fake. This seam tests the
complete CLI parser-to-service route without a token store, OAuth credential,
network call, or live provider mutation. Production `GoogleCalendarGatewayCLI()` and
`Sources/AppCLI/main.swift` remain unchanged at their call sites.

## Compatibility And Boundaries

- `dryRun` is opt-in and defaults to `false` at every boundary.
- Existing GraphQL queries, library calls, live mutation response shapes, error
  codes, exit codes, provider arguments, and provider effects remain unchanged
  when dry-run is omitted. In particular, `sendUpdates` is validated and
  forwarded with the same pre-feature behavior.
- The service is the only owner of write gating, normalization, preview
  construction, and provider short-circuiting.
- Existing SwiftPM targets and the macOS 14 platform boundary remain unchanged;
  no new module is required.
- Swift files touched during implementation remain below 1000 lines. Because
  the current core and GraphQL files are already close to that limit, mutation
  result and adapter responsibilities should be split into cohesive files
  inside the existing `GoogleCalendarGatewayCore` target as needed.
- Tests use fake providers only. No live OAuth credentials or calendar writes
  are permitted, and secret/token values must never appear in previews,
  diagnostics, fixtures, or logs.
- Release scripts, packaging, `dist/`, `flake.nix`, `VERSION`, and Homebrew tasks
  are outside scope.

## Acceptance And Verification

Focused fake-provider coverage must prove:

- dry-run create and update return normalized `validatedInput`
- create/update previews use the complete fixed `validatedInput` key set and
  exact null, empty-array, enum, reminder-object, and Boolean encodings above
- repeated compact serialization of the same preview is byte-identical and
  uses sorted object keys while preserving array order
- dry-run delete returns resolved target IDs, `wouldDelete: true`, and
  `deleted: false`, with exactly the eight-key projection above and
  `sendUpdates: null` when omitted
- create, update, and delete preserve whitespace-only and padded allowed
  `sendUpdates` strings in previews, matching unchanged provider-bound
  arguments; omitted values project as null
- provider create, update, and delete call counts remain zero for dry-runs
- invalid dry-run inputs fail before provider calls
- a read-only credential returns `WRITE_DISABLED` before preview construction
- GraphQL dry-run errors use the unchanged error envelope
- direct CLI `--dry-run` commands route through the injected service factory
  and the recording fake reports zero writes for create, update, and delete
- omitted or false dry-run values preserve non-dry-run response behavior and
  existing `sendUpdates` validation and forwarding behavior

Required implementation verification:

```bash
swift test --filter DryRun
mise run lint
swift build
swift test
git status --short
```

The final status must show only in-scope paths under `Sources/`, `Tests/`,
`design-docs/specs/`, and the resolved-decision file
`design-docs/user-qa/pending-google-calendar-gateway-decisions.md`. The implementation
workflow creates one focused local commit after review and successful
verification and must not push it.
