# google-calendar-gateway

Credential token selection prefers `GOOGLE_CALENDAR_GATEWAY_CREDENTIAL_<ID>_TOKEN_STORE_JSON`,
then `TOKEN_STORE_PATH`, then the configured/default file. Explicit `--config`
does not override credential environment variables. Inline JSON is immutable;
unset its exact variable before login or refresh. Auth errors, status, and login
output identify the selected source and explain how subsequent commands can use
the written token file. The implicit fallback configuration works for both auth
and GraphQL commands.

Swift library and local CLI gateway for calendar clients such as Google
Calendar.

## Development

```bash
mise install
mise run build
mise run test
swift run google-calendar-gateway-reader --help
swift run google-calendar-gateway-writer --help
```

The package uses Swift Package Manager with:

- Library target: `GoogleCalendarGatewayCore`
- Executable targets: `GoogleCalendarGatewayReader`, `GoogleCalendarGatewayWriter`
- Installed executables: `google-calendar-gateway-reader`, `google-calendar-gateway-writer`

Swift target names and type names must be valid Swift identifiers. If the project
name contains hyphens, keep `PROJECT_NAME` and `EXECUTABLE_NAME` hyphenated as
needed, but use identifier-safe values such as `GoogleCalendarGatewayCore`,
`GoogleCalendarGatewayCLI`, and `GoogleCalendarGatewayCommandResult` for Swift module/type
variables.

## CLI

This project supports Google Calendar only. Apple Calendar is not supported.
The former `calendar-gateway` executable is replaced by two commands:

- `google-calendar-gateway-reader` supports queries, discovery, free/busy, and raw GET requests.
- `google-calendar-gateway-writer` also supports event create/update/delete and raw API writes.

Both commands support config, auth, and cache management and share credential storage.
The rename also changes the default XDG directories and environment prefix to
`google-calendar-gateway` and `GOOGLE_CALENDAR_GATEWAY_*`. Existing explicit
config paths and credential files can still be selected with the new commands.
The reader rejects mutations, including dry runs, even with a write enabled credential.
The writer still requires `access_mode = "read_write"` or `"full"` for writes.
OAuth login requests the scopes configured for the selected credential.
Use `access_mode = "read"` for a credential that needs only reads.
`GoogleCalendarGatewayCLI` defaults to reader mode; select `.writer` explicitly for writes.
Library GraphQL execution keeps write support by default and accepts `mode: .reader`
to apply the same restriction.


```bash
google-calendar-gateway-reader --help
google-calendar-gateway-reader config validate
google-calendar-gateway-reader auth status --credential google-personal
google-calendar-gateway-reader auth login --credential google-personal --redirect-uri http://127.0.0.1:8765/oauth2callback
google-calendar-gateway-reader cache prune --calendar personal
google-calendar-gateway-reader graphql --query '{ calendars { id provider } }'
google-calendar-gateway-reader graphql --query '{ freeBusy(calendarId: "personal", timeMin: "2026-07-01T00:00:00Z", timeMax: "2026-07-02T00:00:00Z") { calendars { id busy { start end } } } }'
google-calendar-gateway-reader graphql --query '{ calendarAPI(credentialId: "google-personal", method: "GET", path: "/colors") { status body } }'
```

```bash
google-calendar-gateway-writer event create --calendar personal --summary Planning --start 2026-07-01T09:00:00Z --end 2026-07-01T09:30:00Z --dry-run
```

Configuration defaults to `$XDG_CONFIG_HOME/google-calendar-gateway/config.toml` and
can be overridden with `--config` or `GOOGLE_CALENDAR_GATEWAY_CONFIG`.

When using the implicit configuration, mutable OAuth tokens are stored at
`${XDG_STATE_HOME:-~/.local/state}/google-calendar-gateway/credentials/<profile>.json`.
The former implicit token at
`${XDG_CONFIG_HOME:-~/.config}/google-calendar-gateway/tokens/google-personal.json`
is copied once when no replacement token exists. A private completion marker
keeps the legacy recovery copy from being selected again after revocation.
Explicit config paths,
credential path/JSON environment variables, and `GOOGLE_CALENDAR_GATEWAY_CREDENTIAL_DIR`
are never migrated. Token directories and files are restricted to `0700` and
`0600`; unsafe symlinks and hard-linked token files are rejected.

`auth login` defaults to the `google-personal` credential; use `--credential`
to select another configured credential. It starts a local loopback OAuth callback server, opens the Google
authorization page, exchanges the callback code, and writes the token store. Use
`--redirect-uri http://127.0.0.1:<port>/<path>` to bind a fixed local callback
URI, `--open-browser false` to print the authorization URL for manual browser
use, and `--timeout-seconds <seconds>` to control how long the callback server
waits.

Typed GraphQL fields cover accounts, provider calendar discovery, free/busy,
event search/fetch, and event create/update/delete. The `calendarAPI` field is a
library and CLI escape hatch for the rest of the official Google Calendar v3
surface, including ACLs, calendar metadata, colors, settings, channels, and
watch notification endpoints. Use `access_mode = "full"` when a credential must
request the broad `https://www.googleapis.com/auth/calendar` scope.

## Homebrew Formula

Build local formula archives:

```bash
mise run build:homebrew -- darwin-arm64 darwin-x64
```

Render a formula after both platform archives exist:

```bash
mise run homebrew:formula -- 0.1.1
```

Render directly into the default sibling tap checkout:

```bash
mise run homebrew:tap-formula -- 0.1.1
```

Install from the tap after the formula is published:

```bash
brew tap tacogips/tap
brew install google-calendar-gateway
```

## Homebrew Cask

The Cask workflow builds signed, notarized, and stapled macOS DMG artifacts.
Apple signing credentials must stay local and must not be committed.

Check the build plan:

```bash
mise run build:homebrew-cask -- --dry-run darwin-arm64 darwin-x64
```

Build with local signing credentials:

```bash
kinko exec --env APPLE_SIGNING_IDENTITY,APPLE_ID,APPLE_PASSWORD,APPLE_TEAM_ID -- \
  mise run build:homebrew-cask -- darwin-arm64 darwin-x64
```

Render a Cask:

```bash
mise run homebrew:cask -- 0.1.1
```

For a tagged release, build, upload, and render the tap Cask:

```bash
kinko exec --env APPLE_SIGNING_IDENTITY,APPLE_ID,APPLE_PASSWORD,APPLE_TEAM_ID -- \
  mise run release:homebrew-cask-local -- v0.1.1
```

See `packaging/homebrew/README.md` and `.agents/skills/` for release workflows.

### Externally obtained credentials

Ordinary requests can use `GOOGLE_CALENDAR_GATEWAY_ACCESS_TOKEN` without running
`auth login` or supplying an OAuth application file. The token stays in memory
and is not persisted. Its Google permissions still govern API access; writer
requests additionally require a configured write-capable credential.

Canonical alternatives are `GOOGLE_CALENDAR_GATEWAY_TOKEN_STORE_JSON` (JSON
contents) and `GOOGLE_CALENDAR_GATEWAY_TOKEN_STORE_PATH` (file path).
`GOOGLE_CALENDAR_GATEWAY_OAUTH_CLIENT_JSON` and
`GOOGLE_CALENDAR_GATEWAY_OAUTH_CLIENT_PATH` configure an application for login or
refresh when needed. Profile-specific values use
`GOOGLE_CALENDAR_GATEWAY_CREDENTIAL_<NORMALIZED_ID>_<SUFFIX>` and override product
defaults. Existing `OAUTH_CLIENT_SECRET_JSON`/`OAUTH_CLIENT_SECRET_PATH` suffixes
and old `CALENDAR_GATEWAY_CREDENTIAL_*` aliases remain accepted. Conflicting
aliases are rejected without printing values; direct access tokens cannot be
combined with token-store inputs for the same selected profile.
