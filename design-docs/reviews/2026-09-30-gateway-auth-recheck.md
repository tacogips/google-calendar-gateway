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
- Service lacked `auth status` and common lifecycle aliases. Its shared auth
  adapter now reports local external/vault credential status without network
  calls or token disclosure and accepts `auth refresh` and `auth revoke` while
  retaining explicit profile selection for those lifecycle operations.
- Calendar's fresh writer incorrectly synthesized the reader's access mode and
  token path. It now synthesizes `read_write` and uses
  `google-personal-read-write.json`; explicit configurations retain their own
  policy, and historical reader credential migration remains reader-only.
- Executable checks with an opaque fixture token confirm that local auth status
  succeeds without an application client in all 28 commands and never prints
  the token. These checks do not verify that Google accepts the fixture token.

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

## Published patch releases and installed verification

| Gateway | Version |
| --- | --- |
| Calendar | 0.1.8 |
| Gmail | 0.1.16 |
| Documents / Sheets / Drive | 0.3.5 |
| Analytics | 0.1.4 |
| Marketing | 0.1.3 |
| Document OCR | 0.1.3 |
| Service | 0.1.4 |

All seven source repositories were committed and pushed, and release archives
were published for both supported macOS architectures. Calendar's signed,
notarized DMGs were also published. All 13 Homebrew formulas passed strict
formula audit, download, installed upgrade, and package tests. Calendar's Cask
passed download and audit checks. The tap metadata workflow for commit
`7661bdd4faa41a4c3c1ee5e4fdc064c89057ece1` succeeded; all 14 public API entries
matched the published versions and committed Ruby source checksums. Both
retired Calendar metadata endpoints returned HTTP 404.

The final installed check passed 112 checks across all 28 commands: help,
version, bare auth help, and local external-token readiness without disclosure.
Calendar and Gmail status checks use their explicit default credential selector;
these checks do not imply that every auth subcommand omits that selector.
The installed Calendar writer also passed event creation dry run with an
external fixture token and without an OAuth application client.

Clean login was rechecked on every installed command. All 28 failed before
Google browser authorization: 21 reported a missing application client and the
seven Documents roles reported missing OAuth credential configuration. No real
browser consent or live Google API acceptance is claimed.

The existing mise-darwin update uses `latest` for gateway packages, so these
verified Homebrew upgrades install the new patches without another version pin
change. Its update commit is `1202e71c2abdb44453e1e217675be3a4fd6e834b`.
The retired local directory, Homebrew binary, and Cellar compatibility alias are
absent. Preexisting unrelated changes in Marketing and mise-darwin were retained.
