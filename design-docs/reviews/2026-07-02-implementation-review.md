# Implementation And Specification Review

## Status

Review completed 2026-07-02 against `main` (`1ae8d93`). This document records
problems and improvement opportunities found by reading every file under
`Sources/`, `Tests/`, `design-docs/specs/`, `.github/workflows/`, and the
packaging/automation entry points. No code was changed as part of this review.

Severity legend:

- **High**: broken behavior, correctness bug, or a contradiction that will bite
  real usage soon.
- **Medium**: works today but has a concrete failure mode, inconsistency, or
  safety gap.
- **Low**: polish, documentation, or maintainability.

## Summary

| # | Severity | Area | Finding |
|---|----------|------|---------|
| 1 | High | CI / platform | Linux CI build is red: OAuth bootstrap is macOS-only (`CryptoKit`, `Darwin`, `Security`, `/usr/bin/open`) |
| 2 | High | CI | gitleaks workflow is red: commit-range computation fails on the initial push |
| 3 | High | Auth | Scope-mismatch rules differ between `auth status` and live request paths; live path contradicts the spec |
| 4 | High | GraphQL | Queries with multiple root fields silently return only one field |
| 5 | High | Validation | `isRFC3339DateTime` rejects fractional seconds, so Google-emitted timestamps fail `timeMin`/`timeMax`/`updatedMin` validation |
| 6 | Medium | GraphQL parser | Argument names are matched inside string literal values |
| 7 | Medium | GraphQL parser | `rangeOfField` does not skip string literals when counting brace/paren depth |
| 8 | Medium | Config / FS safety | `cache prune` root-containment check is prefix-based on non-canonicalized paths; IDs have no charset validation |
| 9 | Medium | CLI surface | `cache prune` manages a cache that nothing writes; removal errors are swallowed but still reported as pruned |
| 10 | Medium | Auth | Token refresh drops a rotated `refresh_token`; concurrent refreshes can clobber the token store |
| 11 | Medium | Auth / security | `auth revoke` deletes the local file but never calls Google's revocation endpoint |
| 12 | Medium | Auth | Loopback OAuth receiver accepts exactly one connection; any stray request aborts login |
| 13 | Medium | GraphQL | Error surface is inconsistent: some errors become GraphQL `errors`, others bypass to CLI stderr |
| 14 | Medium | Config | Missing config file silently fabricates a default config; `config validate` reports `ok: true` and skips secret-path validation |
| 15 | Medium | Raw API | `calendarAPI` with `access: "read"` lets mutating methods bypass the `WRITE_DISABLED` fail-fast gate |
| 16 | Medium | CLI | `--variables` / `--variables-file` are parsed and then discarded |
| 17–31 | Low | various | See detailed findings |

---

## 1. Build, CI, And Platform Strategy

### 1.1 Linux CI build is broken (High)

`.github/workflows/linux-amd64-build.yml` builds the `google-calendar-gateway`
product with `--triple x86_64-unknown-linux-gnu`, and the run on `main`
(`28557202123`) fails:

```
Sources/GoogleCalendarGatewayCore/GoogleCalendarOAuthBootstrap.swift:1:8:
error: no such module 'CryptoKit'
```

`GoogleCalendarOAuthBootstrap.swift` is macOS-only end to end:

- `import CryptoKit` (SHA-256 for PKCE) — not available on Linux.
- `import Darwin` + raw BSD socket code using `sockaddr_in.sin_len` — Darwin-only field.
- `import Security` / `SecRandomCopyBytes` — Darwin-only.
- `openBrowser` hardcodes `/usr/bin/open` (`GoogleCalendarOAuthBootstrap.swift:261`).

Meanwhile `Package.swift` declares `platforms: [.macOS(.v14)]` only. The
project has to pick one of:

1. **macOS-only for now**: delete or gate the Linux workflow, and state the
   platform decision in `design-docs/specs/architecture.md`.
2. **Cross-platform**: replace `CryptoKit` with `swift-crypto`, replace
   `SecRandomCopyBytes` with a portable CSPRNG, wrap the socket receiver and
   browser launch in `#if os(macOS)` / portable equivalents (`xdg-open`), and
   keep the Linux job.

Either way, the current state (CI required to build a target the code cannot
support) fails every push to `main` and will mask future regressions because
red CI becomes normal.

### 1.2 gitleaks workflow is broken (High)

Run `28557202125` fails before scanning anything:

```
gitleaks detect ... --log-opts=--no-merges --first-parent cc822b2^..1ae8d93
fatal: ambiguous argument 'cc822b2...^..': unknown revision
```

`cc822b2` is the repository's first commit; `<first-commit>^` does not exist,
so the push-event range computed by `gitleaks-action` fails and the job exits
1. Note the log then prints "no leaks found in partial scan" — the job fails
on the range error, not on findings. Options: scan full history on push to
`main` instead of a range, set a base ref that exists, or pin the workflow to
run only on `pull_request` plus a scheduled full scan. Also note `on: push` +
`on: pull_request` currently double-runs every PR commit (Low, see 8.4).

---

## 2. Correctness Bugs

### 2.1 Scope-mismatch semantics differ between status and live paths (High)

Two implementations disagree:

- `AuthTokenInspection.swift:50` (`auth status`, `calendars` capabilities)
  uses a *coverage* relation: `calendarAccessMode(granted, covers: configured)`
  so a `full` token with a configured `read` credential is `READY`.
- `GoogleCalendarOAuthSupport.swift:162` (`validateTokenStoreAccessMode`,
  executed before every live request) requires **exact equality**:
  `grantedAccessMode != credential.accessMode` throws `AUTH_REQUIRED`.

Consequence: a token whose granted mode is broader than the configured mode
reports `READY` in `auth status` but every actual API call fails with
"Stored Google Calendar token scope does not match configured access mode".

This also contradicts `design-docs/specs/google-calendar-gateway.md` ("The broader
`calendar.readonly` and `calendar` scopes are accepted when already present in
token metadata for compatible configured modes"). The live path should use the
same coverage relation as `inspectCalendarTokenStore` (or both should be a
single shared function so they cannot drift again).

### 2.2 Multiple root fields are silently dropped (High)

`executeCalendarGraphQLData` (`GoogleCalendarGatewayGraphQL.swift:36-156`)
dispatches on the **first** matching root field, in a hard-coded priority
order (`calendarAPI`, `createEvent`, `updateEvent`, `deleteEvent`,
`calendars`, `accounts`, ...). A legal GraphQL document such as:

```graphql
{ calendars { id } providerCalendars(credentialId: "google-personal") { id } }
```

returns only `calendars` and silently omits `providerCalendars` — no error,
no warning. For the AI-agent audience this gateway targets, silent partial
results are worse than an error. Until multi-field execution exists, the
executor should detect a second root field and reject the query with
`INVALID_ARGUMENT`.

The priority order also means dispatch is not purely syntactic: a top-level
field named `createEvent` in a read query would run the mutation resolver.
Operation type (`query` vs `mutation`) is ignored entirely, so
`query { deleteEvent(...) }` executes a delete (Low in practice, but a spec
deviation worth an explicit note; see 8.2).

### 2.3 RFC 3339 validation rejects fractional seconds (High)

`isRFC3339DateTime` (`GoogleCalendarGatewayUtilities.swift:100`) uses a default
`ISO8601DateFormatter`, which does **not** accept fractional seconds. RFC 3339
explicitly allows them, and — critically — Google Calendar emits them:
`event.updated` is `2026-07-01T09:00:00.000Z`. The documented incremental-sync
workflow ("`updatedMin` uses an RFC 3339 date-time string") therefore breaks
on copy-paste: a client that feeds an event's own `updated` value into
`updatedMin` is rejected with `INVALID_ARGUMENT` before the provider call.

Fix by trying both formatter configurations (with and without
`.withFractionalSeconds`), and add test cases for `.000Z` and `+09:00` offset
forms. The same helper gates `timeMin`, `timeMax`, `freeBusy` bounds, and
event mutation datetimes, so the fix pays off everywhere.

### 2.4 Argument lookup matches names inside string values (Medium)

`argumentValueRange` (`GoogleCalendarGatewayGraphQL.swift:678-751`) scans the raw
argument substring for the identifier without string-literal awareness. A
mutation like:

```graphql
mutation { createEvent(calendarId: "personal",
  summary: "Reminder — set timeMin: tomorrow",
  start: "2026-07-03T09:00:00Z", end: "2026-07-03T10:00:00Z") { id } }
```

finds `timeMin` *inside the summary string* (boundary characters `"` and `:`
are both non-identifier), then fails or extracts garbage as the value. There
is already a test for identifier-boundary confusion
(`graphQLArgumentLookupDoesNotConfuseProviderCalendarId`), but the
string-content case is unhandled. The scanner needs to skip quoted regions
while searching for names, exactly as the value-scanning loop below it already
does.

### 2.5 `rangeOfField` corrupts depth counters on braces in strings (Medium)

`rangeOfField` (`GoogleCalendarGatewayGraphQL.swift:463-493`) counts `{}`/`()`
without tracking string literals, unlike its sibling
`indexAfterBalancedDelimiter` which does. Any argument value containing an
unbalanced `{`, `}`, `(`, or `)` — e.g. `summary: "1) kickoff"` or
`description: "use {braces}"` with one side missing — shifts the depth
counters, after which root-field dispatch can miss the field (→ "Unsupported
GraphQL query") or match text in the wrong region. Event summaries and
descriptions are arbitrary user text, so this is reachable in normal use.

### 2.6 `cache prune` containment check is bypassable; IDs are unvalidated (Medium)

`isWithinRoot` (`GoogleCalendarGatewayUtilities.swift:15`) is a string-prefix check
and `normalizedPath` only expands `~` — it does not resolve `..` or symlinks.
`pruneCache` (`GoogleCalendarGatewayCore.swift:517-560`) builds the target as
`cacheRoot + "/" + account.id`. An account ID like `../../precious` yields
`/cache/root/../../precious`, which passes `hasPrefix("/cache/root/")`, and
`FileManager.removeItem` then resolves `..` and deletes **outside** the cache
root.

The config file is local and user-authored, so this is not remote-attacker
material, but the containment check exists precisely to catch config mistakes
and currently does not. Two fixes reinforce each other:

- canonicalize with `URL.standardizedFileURL` / `resolvingSymlinksInPath()`
  before the prefix comparison;
- validate `credentials.id` / `calendars.id` charset at config load
  (e.g. `[A-Za-z0-9._-]+`). This also fixes the env-var mapping collision
  where `google-personal` and `google_personal` resolve to the same
  `GOOGLE_CALENDAR_GATEWAY_CREDENTIAL_GOOGLE_PERSONAL_*` variables
  (`ConfigLoading.swift:196-204`), and keeps IDs safe for URL path embedding.

### 2.7 Token refresh drops rotated refresh tokens (Medium)

`refreshGoogleCalendarAccessToken` (`GoogleCalendarOAuthSupport.swift:237-247`)
persists `refreshToken: tokenStore.refreshToken`, ignoring any
`refresh_token` present in the refresh response. Google can rotate refresh
tokens (and does under some org policies); when that happens the new token is
discarded and the stored one eventually dies, forcing a re-login that a
one-line fix would have avoided.

Related: there is no locking around read-modify-write of the token store.
Two concurrent `google-calendar-gateway` invocations that both refresh will race;
the atomic write prevents corruption but not lost updates. A simple `flock`
on the token file (or accept-and-document the risk) is worth a decision.

---

## 3. Spec ↔ Implementation Inconsistencies

### 3.1 Fabricated default config makes `config validate` misleading (Medium)

When no config file exists and none was requested explicitly,
`loadConfig` fabricates a default config (`ConfigLoading.swift:66-68,
122-174`) with credential `google-personal`, account `personal`, and email
`personal@example.invalid`. Consequences:

- `google-calendar-gateway config validate` with **no config file at all** prints
  `{"ok": true, ...}` — the command's core promise ("validate my config") is
  inverted.
- The default path skips `validateOAuthClientSecretPaths`, so the parse path
  and default path enforce different invariants.
- The synthesized `*@example.invalid` email then surfaces in `calendars`
  GraphQL responses as if it were real data.

At minimum `config validate` should report `"configFileExists": false` /
`"usingDefaults": true`; arguably it should fail. The spec
(`google-calendar-gateway.md` Configuration section) never mentions an implicit
default config, so this behavior is also undocumented.

### 3.2 `calendarAPI` read-access override defeats the write gate (Medium)

Spec (`google-calendar-gateway.md`): "Read-only credentials must fail before provider
mutation with a machine-readable error such as `WRITE_DISABLED`."

`rawCalendarAPITokenUse` (`CalendarRawAPI.swift:97-109`) honors a caller-
supplied `access: "read"`, and `executeCalendarAPI` only calls
`requireWriteCredential` when the resolved use is `.write`. So
`calendarAPI(credentialId: "read-only-cred", method: "DELETE", path: "...",
access: "read")` skips the local gate entirely and relies on Google to 403.
Failure still happens, but late, with `AUTH_REQUIRED` instead of
`WRITE_DISABLED`, contradicting the fail-fast contract. Method should trump
the `access` hint for gating (the hint can still choose the token scope).

### 3.3 Error envelope inconsistency in `graphql` (Medium)

`executeCalendarGraphQL` (`GoogleCalendarGatewayGraphQL.swift:16`) converts only
errors whose exit code is `graphqlExecutionError` or `providerApiError` into
the GraphQL `errors` array. Errors carrying other exit codes escape to CLI
stderr:

- `events(calendarId: "unknown")` → GraphQL `errors` payload, exit 5.
- `providerCalendars(credentialId: "unknown")` → `CREDENTIAL_NOT_FOUND` has
  exit code 3, so it bypasses the envelope and lands on stderr as a top-level
  CLI error.
- `calendarAPI` with a URL that fails `URLComponents` construction throws with
  `.invalidCliUsage` (`GoogleCalendarLiveClient.swift:411-416`) — a graphql
  business failure reported as a CLI-usage error, exit 2.

Agents consuming this transport have to handle two shapes for what is
semantically the same class of failure. Decide one rule (e.g. "anything
thrown during GraphQL execution becomes `errors` + mapped exit code") and
funnel all resolver errors through it.

### 3.4 `--variables` is accepted and ignored (Medium)

`GoogleCalendarGatewayCLI.swift:58` runs `_ = try loadVariables(...)`. The spec
frames this as transport compatibility, but the observable behavior is a
silent no-op: a caller passing `--variables '{"id":"x"}'` with `$id` in the
query gets an unrelated parse error ("must be a string literal") rather than
"variables are not supported yet". Either implement substitution for the flat
argument grammar (cheap: textual `$name` → literal), or reject queries
containing `$` with an explicit `INVALID_ARGUMENT` message while variables are
unsupported.

### 3.5 Cache surface with no cache (Medium)

`cache prune` and `storage.cache_dir` are fully plumbed (config key required,
directory recreated with 0700), yet nothing in the codebase ever writes cache
content — there is no caching feature. Additionally
`pruneCache` uses `try? FileManager.removeItem` and then unconditionally
appends the path to `prunedPaths`, so a permissions failure reports success.
Either document that the command exists for forward-compatibility with a
planned cache (and make `storage` optional until then), or remove the surface.
The silent `try?` should become a real error either way.

### 3.6 Cursor opacity is undermined (Low)

Spec: "pagination uses provider tokens wrapped in opaque cursors."
`CalendarEventConnection.graphQLObject` (`CalendarModels.swift:508-517`)
exposes both `nextCursor` *and* raw `nextPageToken`, and the `events` field
accepts a raw `pageToken` argument (`GoogleCalendarGatewayGraphQL.swift:370-375`).
If the raw token is a deliberate escape hatch, the spec should say so;
otherwise drop it. Also worth documenting: Google requires the non-token query
parameters to be identical across pages, and the cursor only carries the
pageToken — callers must re-supply all other arguments themselves.

### 3.7 Undocumented root fields and vocabulary split (Low)

- `accounts` and `account` root fields exist
  (`GoogleCalendarGatewayGraphQL.swift:79, 90`) but `command.md` documents only
  `calendars`/`calendar`.
- The same concept is `[[calendars]]` in TOML, `CalendarAccountConfig` in
  code, `accountId`-or-`calendarId` in GraphQL arguments, and
  `--calendar` on the CLI. The dual `accountId`/`calendarId` acceptance in
  every event field (`GoogleCalendarGatewayGraphQL.swift:62-63, 115-116, 138-139,
  274-275, 306-307`) doubles the parser surface and the documentation burden.
  Pick one public term (the spec's own "configured local calendar handle"
  suggests `calendarId` + `providerCalendarId`) and keep the alias only as a
  deprecated compatibility shim, documented as such.

---

## 4. Auth And Security Observations

What is already good: PKCE with S256, random `state` verified on callback,
loopback bound to 127.0.0.1 with explicit path matching, `offline` +
`prompt=consent` for refresh tokens, token stores written 0600 under 0700
directories with atomic writes, no token/secret values in any output path,
and `calendarAPI` path validation rejecting `..`, `?`, `#`, absolute URLs, and
newlines.

### 4.1 `auth revoke` does not revoke (Medium)

`revokeAuth` (`GoogleCalendarGatewayCore.swift:499-515`) removes the token-store
file and reports `revoked: true`. The access/refresh tokens remain valid at
Google until they expire naturally. A user who runs `auth revoke` after a
machine compromise is not protected. Call
`https://oauth2.googleapis.com/revoke` with the refresh token first (best
effort), then delete the file; report both outcomes separately. Also decide
behavior when the credential is backed by `TOKEN_STORE_JSON` env (currently
the file path is still deleted, and the env-provided token is untouched).

### 4.2 Loopback receiver is single-shot (Medium)

`waitForCode` (`GoogleCalendarOAuthBootstrap.swift:165-208`) accepts exactly
one connection. Any other client hitting the port first — a browser
prefetch/favicon probe, a local port scanner, a second tab — consumes the
accept, fails path/state parsing, and the whole login aborts even though the
real callback would have arrived moments later. Loop on accept until the
expected path+state arrives or the deadline expires; answer non-matching
requests with 404 and keep waiting.

### 4.3 Blocking HTTP transport (Low)

`performGoogleCalendarHTTPRequest` (`GoogleCalendarOAuthSupport.swift:265`)
bridges `URLSession` with a `DispatchSemaphore`. Acceptable for a one-shot
CLI, but this is also the advertised **library** surface
(`GoogleCalendarGatewayClient`): callers on Swift concurrency get a thread-blocking
sync API, no cancellation, no retry/backoff for 429/5xx (the gateway maps 429
to `PROVIDER_RATE_LIMITED` but never retries), and a hardcoded 30 s timeout.
When the library API stabilizes, add `async` variants on the provider protocol
and let the CLI wrap them; make the timeout configurable.

---

## 5. Config Loader

### 5.1 Ad-hoc TOML subset is stricter than it looks (Low)

`parseTomlSubset` (`ConfigLoading.swift:213-310`) supports only
`key = "string"` and `key = ["array", "of", "strings"]` under three known
section headers. Real-TOML constructs users will reasonably write all fail
with generic errors:

- trailing comments: `access_mode = "read" # note` → "unsupported TOML value";
- escaped quotes inside strings are passed through raw (no unescaping);
- booleans/integers, multi-line arrays, dotted keys, `[storage.sub]` → errors.

Either adopt a real TOML parser dependency, or document the exact accepted
grammar in `google-calendar-gateway.md` (currently it just says "config.toml") and
make the error message name the limitation ("trailing comments are not
supported") instead of echoing the line.

### 5.2 Duplicate-detection and default quirks (Low)

- `credentials.oauth_client_secret_path` uniqueness is not enforced (token
  store paths are). Fine, but asymmetric — intentional?
- `parseAccountConfig` accepts `calendar_id` via `readOptionalStringUnchecked`
  (`ConfigLoading.swift:372,486-491`), silently ignoring a blank value where
  every other field errors. Minor inconsistency.
- `email_address` defaults to `<id>@example.invalid` and only checks
  `contains("@")` — see 3.1 for how the placeholder leaks into output.

---

## 6. Library API Shape (Improvements)

- `GoogleCalendarGatewayService` mixes typed and untyped returns: `getEvent` returns
  `Any`, `createEvent`/`updateEvent` return `Any`, `deleteEvent` returns
  `[String: Any]`, while `searchEvents`/`calendarEvent` return typed models.
  The typed/`graphQLObject` split is good; the `Any`-returning wrappers should
  return `[String: Any]` at minimum, and the delete payload deserves a small
  struct.
- `CalendarEventProvider` is a good seam, but `deleteEvent` and
  `executeCalendarAPI` returning `[String: Any]` push presentation concerns
  into providers (each fake re-invents the payload shape). Return typed
  results and build JSON at the boundary.
- `validateMaxResults` logic exists twice with two different error messages
  (`GoogleCalendarGatewayCore.swift:663-674` and
  `GoogleCalendarGatewayGraphQL.swift:377-389`). Same for RFC 3339 checks. Single
  source per rule prevents drift.
- Update semantics gaps worth documenting (or fixing): `updateEvent` cannot
  clear a field (empty strings are filtered by `nonBlank`), `attendeeEmails`
  fully replaces the attendee list on patch, and `createConference: false`
  cannot remove existing conference data. Agents will hit all three.
- `Version.current = "0.1.0"` (`GoogleCalendarGatewayCore.swift:647`) duplicates the
  `VERSION` file; release automation reads one, `--version` prints the other.
  Generate one from the other at build/release time.
- Projection: when a root field has **no** selection set
  (`{ calendars }`), `projectGraphQLValue` returns the entire object including
  raw `provider` metadata (`GoogleCalendarGatewayGraphQL.swift:198-210`), which the
  spec says should only appear when explicitly selected. Require a selection
  set for object-valued fields, or strip `provider` when unselected.
- GraphQL error `extensions` drop `error.details`
  (`GoogleCalendarGatewayGraphQL.swift:17-20`), losing e.g. `httpStatus` that the
  stderr path preserves. Include details in extensions.

---

## 7. Tests

Current suite (88 tests) covers validation ordering, access-mode gating,
projection, cursors, scope inference, and CLI flag hygiene well, with a clean
injected-provider pattern. Gaps:

- **No request-construction tests for `GoogleCalendarLiveClient`.** Query-item
  assembly (`singleEvents`/implicit `orderBy` injection, timeZone from
  account), JSON body shapes for insert/patch/freeBusy, and
  `conferenceDataVersion=1` are all untested because the live client calls
  `URLSession.shared` directly. Inject a `URLProtocol`-backed session (or a
  request-performing closure) to make the HTTP layer testable without the
  network.
- **OAuth loopback receiver untested** (port binding, path matching, state
  mismatch, timeout). It is plain socket code — the riskiest kind to leave
  untested. It is also the code this review flags in 4.2.
- **TOML parser negative cases**: trailing comment, escaped quote, duplicate
  section, key outside section have no coverage.
- **Findings above should land as regression tests**: fractional-second
  timestamps (2.3), multi-root-field query (2.2), argument name inside a
  string value (2.4), brace inside a string argument (2.5), granted-mode
  broader than configured (2.1), `..` in account id for prune (2.6).

---

## 8. Documentation Gaps

1. **Exit codes are not enumerated anywhere.** `GoogleCalendarGatewayExitCode`
   defines 0–6 with clear meanings; `command.md` mentions only exit 2 in
   passing. Add a table (spec promises "clear exit codes").
2. **Operation-type behavior**: document that the lightweight executor ignores
   `query`/`mutation` keywords and dispatches purely on field name (or fix,
   per 2.2).
3. **Default-config fallback** (3.1) is entirely undocumented.
4. **gitleaks workflow** double-runs on PRs (`on: push` + `on: pull_request`).
5. `impl-plans/active/google-calendar-gateway-core.md` describes work that has
   shipped; per the impl-plans process it should move to
   `impl-plans/completed/` with a completion note.
6. `AGENTS.md` caps Swift files at 1000 lines; `GoogleCalendarGatewayCore.swift` is
   at 992 and will cross on the next feature. Plan the split now (service vs.
   validation functions is the natural seam).

---

## 9. Suggested Priority Order

1. Fix CI: decide the platform story (1.1) and repair gitleaks (1.2) so red
   runs mean something again.
2. Unify scope-coverage semantics (2.1) — user-visible auth failures with a
   misleading `READY` status.
3. Fix RFC 3339 fractional seconds (2.3) — breaks the documented incremental
   sync flow.
4. Reject multi-root-field queries (2.2) — silent data loss for agent callers.
5. String-literal awareness in the argument/field scanners (2.4, 2.5).
6. Harden `auth revoke` (4.1), loopback receiver (4.2), refresh-token rotation
   (2.7).
7. `config validate` honesty + ID charset validation + prune canonicalization
   (3.1, 2.6).
8. Error-envelope consistency and the remaining Medium/Low items as
   maintenance.
