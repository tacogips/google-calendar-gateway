# Live Integration

## Status

Draft

## Purpose

Live Google Calendar checks are optional and must never run as part of the
default test suite. Unit tests use fake providers and local token-store fixtures.

## Opt-In Gate

Live checks require all of the following:

- `GOOGLE_CALENDAR_GATEWAY_LIVE_TESTS=1`
- a config file selected by `--config` or `GOOGLE_CALENDAR_GATEWAY_CONFIG`
- credential material supplied by local files or environment variables
- a non-production test calendar where event writes are acceptable

Recommended credential environment names:

- `GOOGLE_CALENDAR_GATEWAY_CREDENTIAL_<ID>_OAUTH_CLIENT_SECRET_PATH`
- `GOOGLE_CALENDAR_GATEWAY_CREDENTIAL_<ID>_TOKEN_STORE_PATH`
- `GOOGLE_CALENDAR_GATEWAY_CREDENTIAL_<ID>_OAUTH_CLIENT_SECRET_JSON`
- `GOOGLE_CALENDAR_GATEWAY_CREDENTIAL_<ID>_TOKEN_STORE_JSON`

These values may be supplied through kinko. If kinko values are needed, use the
corresponding `mail-gateway` credential naming pattern from a sibling checkout
as the local reference, but never print secret values.

## Read Smoke Commands

```bash
google-calendar-gateway-reader --config /path/to/config.toml config validate
google-calendar-gateway-reader --config /path/to/config.toml auth status --credential google-personal
google-calendar-gateway-reader --config /path/to/config.toml graphql --query \
  '{ events(calendarId: "personal", maxResults: 5) { events { id summary start end } } }'
```

## Write Smoke Commands

Run writes only against a disposable calendar.

```bash
google-calendar-gateway-writer --config /path/to/config.toml graphql --query \
  'mutation { createEvent(calendarId: "personal", summary: "google-calendar-gateway smoke", start: "2026-07-01T09:00:00Z", end: "2026-07-01T09:15:00Z") { id summary } }'
```

Delete the created event by ID after inspection:

```bash
google-calendar-gateway-writer --config /path/to/config.toml graphql --query \
  'mutation { deleteEvent(calendarId: "personal", eventId: "<created-event-id>") { deleted eventId } }'
```

## Safety Rules

- Do not run live write checks without explicit opt-in.
- Do not include token values, OAuth client JSON, or event payloads containing
  private data in logs or documentation.
- Prefer a dedicated test calendar over a primary personal calendar.
- If a live write fails after creating an event, use the returned event ID to
  clean it up manually.
