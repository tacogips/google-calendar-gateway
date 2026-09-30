# Gateway authentication recheck — 2026-09-30

## Scope

All 28 installed executable products across Calendar, Gmail, Documents
(Docs, Sheets, Drive), Analytics, Marketing, Document OCR, and Service were
checked in isolated XDG configuration and state directories with gateway
credential environment variables removed.

## Findings

- Every installed executable exposes help and recognizes `auth login`.
- All 28 clean login attempts fail before browser authorization because a
  registered default application client has not been selected or integrated.
  This is a failed acceptance check; it is not evidence of working Google login.
- Bare `auth` returned an error in every installed gateway. The patch makes it
  show command help without loading configuration or credentials.
- Gmail's login diagnostic now identifies the missing OAuth application client
  and states that browser login cannot start.
- A Gmail SDK cancellation test sometimes checked before URLSession delivered
  the provider stop callback. It now waits at most one second for that callback
  and retains the assertion that the provider request was stopped.

## Verification boundaries

Full Swift build, test, and lint checks cover the changed implementations.
Existing credential tests exercise external raw tokens, JSON/file inputs,
profile/source precedence, role validation, and mocked provider dispatch.
Browser callback and OAuth grant tests use controlled test implementations.
These tests do not substitute for a real Google account authorization or
live Google API execution. No usable end-user credential or distribution
application was supplied for those checks.

## Remaining acceptance requirement

Select the owning Google Cloud project or provide an existing desktop OAuth
application registered for these gateways. Integrate that application as the
default and complete real browser consent, token persistence, refresh, status,
and authorized read checks before claiming clean browser login is complete.

The available native computer-use tool failed to initialize, so Cloud Console
registration could not be inspected through that tool during this recheck.
