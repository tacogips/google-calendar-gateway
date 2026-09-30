# Google gateway browser authentication

## Requested behavior

All Google gateway commands and Gmail should open the browser on `auth login`,
ask the user to choose a Google account and grant the command's scopes, and
persist refreshable credentials. End users should not need to download a
`google-client.json` file. Reader and writer roles must retain their scope and
capability boundaries. Service account and explicit credential overrides remain
available for automation.

## Current implementation audit

| Repository | Browser login | Application client source | Required change |
| --- | --- | --- | --- |
| gmail-gateway | `auth login` | Imported client/profile or explicit credential configuration | Shared registered application client fallback |
| google-calendar-gateway | `auth login` | Installed client JSON from file/environment | Shared client fallback; default login credential now implemented |
| google-documents-gateway | `auth login` in Docs, Sheets, Drive roles | Client ID environment variable or installed client JSON | Shared client fallback |
| google-analytics-gateway | `auth login` (`auth oauth2` alias) | OAuth client JSON path in credential profile | Shared client fallback |
| google-marketing-gateway | `auth login` | OAuth client JSON path in credential profile | Shared client fallback |
| google-document-ocr-gateway | No interactive login | Access token or service account | Browser login, token persistence, refresh, status, revoke |
| google-service-gateway | `auth login` (`oauth login` alias) in auth executable | Imported client in credential vault | Shared client fallback |

Worktree container directories are alternate checkouts, not additional command
families. Their branches should not be overwritten during the integration.

## Shared Swift implementation

`google-service-gateway` already exports `GoogleServiceGatewayCore` with OAuth
client models, PKCE authorization request construction, token exchange, refresh,
revocation, and a Keychain credential vault. The loopback browser
authorizer and its interactive protocol have now been moved into that public
library, with compatibility type aliases in the auth executable. Its 94 tests,
including callback, state, grant completeness, and callback deadline validation,
pass after extraction. A separate
repository is permitted if extracting more of the implementation reduces coupling.

The application client and user token are different credentials. Browser login
creates the user's token; a registered Google desktop application client must
already identify the app. End-user JSON setup can be removed by distributing a
client registered for these gateways. No registered distribution client is
present in the audited source, and no client registration has been supplied in
this session. Do not invent a client ID or adopt another application's client.

## Remaining evidence required

- An application client registered for these gateways, or an agreed alternative.
- Mocked browser callback tests for each role's requested scopes and persisted token.
- Refresh, status and revocation checks using the same selected credentials.
- Build/lint/tests for every changed repository and command family.
- An actual authorized browser login before claiming live authentication works.

Calendar verification: `swift test` passed all 128 tests; `swiftlint --quiet`
passed; both macOS architecture archives include the reader and writer; the
rendered Formula passes `ruby -c`. The Cask scripts pass shell syntax and dry-run
checks; signed notarized DMGs have not been built or published.

Additional verification: Analytics `swift test` passed 291 tests after adding the
`auth login` alias; SwiftLint passed. Service tests pass with the alias, including
both spellings exercising the configured consent scopes and token exchange.
Calendar `auth login` now defaults to `google-personal`; 128 tests and SwiftLint
pass after the change. No live Google authorization has been performed.

## Shared login orchestration implemented

`GoogleOAuthBrowserLogin` now owns desktop client validation, scope normalization,
browser authorization, PKCE code exchange, and refreshable grant validation.
The Service auth adapter delegates to it and persists the result only after the
requested scopes and refresh token are present. Tests prove rejected grants leave
an existing stored credential unchanged and keep token values out of diagnostics.

The public callback handler now bounds both accepting the connection and reading
HTTP headers by the login deadline. An incomplete local request cannot block
past that deadline; a regression test holds a socket open with partial headers.
Direct authorizer calls also validate finite timeout bounds before creating a
listener. The library is importable from Core without importing the auth CLI.

Verification: `swift test` passed 94 Service tests. `swiftlint --quiet` exited
successfully, with existing warnings elsewhere in the package and no warnings
in the newly extracted login and callback files. Calendar and Analytics source
has not changed since their passing 128-test and 291-test runs respectively.

Unfinished: publish/integrate the shared application client and login service
into every gateway, add OCR interactive credentials, and validate the selected
application with an authorized live browser login. No distribution OAuth client
has been selected or registered, and these local changes have not been published.

## External credential compatibility requirement

The user explicitly requires ordinary commands to continue accepting credentials
obtained elsewhere, without running `auth login`. This applies to every product.
Browser login must be an optional credential acquisition path, not a prerequisite
for externally authenticated requests. Existing environment names remain supported
as compatibility aliases when common naming is introduced.

The canonical naming convention uses a product namespace and the same suffixes:

| Product | Environment prefix |
| --- | --- |
| Gmail | `GMAIL_GATEWAY_` |
| Calendar | `GOOGLE_CALENDAR_GATEWAY_` |
| Docs | `GOOGLE_DOCS_GATEWAY_` |
| Sheets | `GOOGLE_SHEETS_GATEWAY_` |
| Drive | `GOOGLE_DRIVE_GATEWAY_` |
| Analytics | `GOOGLE_ANALYTICS_GATEWAY_` |
| Marketing | `GOOGLE_MARKETING_GATEWAY_` |
| Document OCR | `GOOGLE_DOCUMENT_OCR_GATEWAY_` |
| Service | `GOOGLE_SERVICE_GATEWAY_` |

Suffixes: `ACCESS_TOKEN`, `TOKEN_STORE_JSON`, `TOKEN_STORE_PATH`,
`OAUTH_CLIENT_JSON`, `OAUTH_CLIENT_PATH`, `SERVICE_ACCOUNT_JSON`, and
`SERVICE_ACCOUNT_PATH`, where supported by the product's authentication model.
Profile-specific names use `CREDENTIAL_<NORMALIZED_ID>_<SUFFIX>` under the
same product prefix. Normalize IDs to uppercase with non-alphanumeric characters
converted to underscores; reject collisions within a configuration.

Explicit profile inputs take precedence over product defaults. Canonical variables
and legacy aliases with conflicting nonempty values must report a configuration
error, rather than silently select credentials. Reader/writer scope checks still
apply to externally supplied credentials. An access token alone must support
ordinary requests without requiring an OAuth application client or refresh token;
expiration should ask for a replacement token, not force browser login.

These are integration requirements, not a claim that all environment variables
are implemented. Verify each product's existing inputs, add aliases and conflict
checks, and test external-token execution without invoking browser authorization.

## Marketing integration progress

Marketing reader/writer/admin/deleter now all route auth login/status/logout to
the auth service. Selection requires a profile matching the executable capability;
a unique configured profile can be selected without `--profile`.

The credential resolver accepts canonical product/profile `ACCESS_TOKEN`,
`TOKEN_STORE_JSON`, `TOKEN_STORE_PATH`, and `OAUTH_CLIENT_PATH` inputs. Google Ads
reader and mutation paths accept canonical `DEVELOPER_TOKEN` with configured
variable names retained as aliases. Normalized profile ID collisions and
conflicting alias/token-source inputs are rejected. Fresh external tokens need
no client, and a token-store path can be configured independently of a client.
Status recognizes inline JSON and the selected file override.

Verification: all 113 Marketing tests pass with `swift test`. New coverage includes
ordinary mocked API execution using canonical token/developer-token inputs with
no login call, external JSON/file sources, retained legacy token input, conflict
rejection without value disclosure, profile binding, capability-specific auth
routing, and normalized-ID collision rejection. `swiftlint --quiet` exits zero;
remaining warnings are in pre-existing code, with none in the new/changed sections.
Live clean-environment checks confirm all four executables now reach the same auth
configuration error instead of rejecting auth as an unavailable mutation.

Remaining Marketing work: inline application-client JSON support, shared browser
login/application client integration, and implicit/default configuration suitable
for first-run login. A real Google authorization has not been performed.

## Docs, Sheets, and Drive integration progress

All six roles accept canonical `GOOGLE_DOCS_GATEWAY_`, `GOOGLE_SHEETS_GATEWAY_`,
and `GOOGLE_DRIVE_GATEWAY_` variables. Shared suffixes cover `ACCESS_TOKEN`,
`TOKEN_STORE_JSON`, `TOKEN_STORE_PATH`, `OAUTH_CLIENT_JSON`, `OAUTH_CLIENT_PATH`,
and `OAUTH_CLIENT_ID`. Profile-specific inputs override product defaults; previous
`GOOGLE_DOCUMENTS_GATEWAY_CREDENTIAL_*` variables remain aliases with conflict
checks. Direct access tokens reject malformed values and ambiguous token sources.

The credential profile can now represent an externally authenticated caller
without an application client. Fresh token JSON/files and direct tokens execute
without login. Login, authorization-code exchange, and refresh reject a missing
client before browser/token-endpoint activity. External token stores still enforce
service, access mode, scope, and secure-file rules. Expired tokens without an
application fail and require replacement rather than attempting an invalid refresh.

SDK inputs support direct tokens and inline canonical JSON while retaining the
existing rule that call-scoped environment paths are not filesystem authority.
Cancellation is checked before and after normalization; already-cancelled loading
returns the cancellation transport failure and never falls back to secret-file reads.

Verification: `swift test` passes 177 tests. New tests cover all six roles, product
namespace isolation, canonical/legacy client aliases, external token JSON/file
without clients, wrong-role rejection, missing-client refresh rejection, a mocked
ordinary request without login, and SDK file boundaries. `swiftlint --quiet` exits
zero with no warnings in the changed credential files or new tests.

Remaining: shared browser application registration/integration. Analytics, Gmail,
OCR, and Service still need complete canonical environment input coverage.

## Analytics canonical credentials implemented

Analytics accepts product/profile `ACCESS_TOKEN`, `TOKEN_STORE_JSON`,
`TOKEN_STORE_PATH`, and `OAUTH_CLIENT_PATH`. Configured token variable references
remain aliases. Normalized IDs are collision checked, alias conflicts/ambiguous
sources are rejected without values, and profile-specific inputs override product
defaults even when the configured variable references the product default itself.
The same precedence correction was applied to Marketing.

Fresh token stores can be configured without a client. Inline JSON is validated
against profile/product/exact scopes and is immutable; expired JSON asks for a
replacement. Direct token providers report no inspectable granted scopes rather
than inventing them. Status recognizes JSON/file overrides. Profile selection
applies path overrides with config/client/token collision checks, so auth login
and logout select the same file path as ordinary requests. Canonical application
and token paths can configure login for a synthesized profile; no bundled client
has been selected.

Verification: `swift test` passes all 296 Analytics tests; `swiftlint --quiet`
passes without warnings. New coverage exercises legacy/canonical direct tokens,
provider scope metadata, synthesized-profile precedence, JSON profile binding,
fresh files without clients, status paths, alias value non-disclosure, and ID
collisions. Existing executable link/capability boundaries are included in the
full suite. Marketing's 113 tests still pass after the precedence correction.

Pending canonical input coverage: Gmail and Service; OCR also needs its interactive
OAuth lifecycle. Inline OAuth application JSON is not yet consistently integrated
outside Calendar and Docs/Sheets/Drive. Shared first-run application registration
and authorized live browser login remain required before overall completion.

## Gmail canonical credential integration

Gmail now resolves canonical product/profile `ACCESS_TOKEN`, `TOKEN_STORE_JSON`,
`TOKEN_STORE_PATH`, `OAUTH_CLIENT_JSON`, and `OAUTH_CLIENT_PATH` inputs. Historical
`OAUTH_CLIENT_SECRET_JSON` and `OAUTH_CLIENT_SECRET_PATH` variables remain aliases.
Profile variables override product defaults. Conflicting aliases and direct tokens
combined with token-store overrides are rejected without printing values.

Direct tokens are stored only in the call's credential configuration. Ordinary
execution returns that token without reading client files, token files, or vault
tokens. Persistent hydration retains executable/access-mode validation before
using the direct input. Raw inputs have no inspectable granted scopes or principal
metadata; Google remains authoritative. Existing persisted-token client fingerprint,
account, scopes, metadata, and lifecycle checks were preserved. Login/revoke reject
management of stored credentials while a direct-token override is active, and status
reports the external source without migration or credential disclosure.

Verification: the full `swift test` run passes 146 XCTest tests and 178 Swift Testing
tests. The new four-test suite also passes separately after extending it to check
status in all five executable modes. It covers direct input in all access modes,
persistent hydration/status, canonical/legacy aliases and conflict non-disclosure,
profile precedence, malformed input, and a mocked ordinary GraphQL request without
login or application setup. `swiftlint` exits zero with one existing unrelated
request-test type-length warning and no warnings in the new credential/test files.

The first full run showed an intermittent existing cancellation assertion about
URLProtocol stop timing; the subsequent full run passes. No cancellation test was
weakened as part of these changes.

Remaining: Service canonical inputs, OCR interactive lifecycle, common application
JSON handling across all gateways, and a registered shared distribution application
with actual authorized browser login. Gmail write/mutation commands still require
a configuration with their appropriate access mode; the synthesized reader profile
is never upgraded implicitly by direct token input.

## Service canonical credential inputs

Reader/writer/admin/deleter now share `GoogleServiceExternalCredentials` in Core.
Canonical suffixes cover access tokens, token-store JSON/path, service-account
JSON/path, and auth application JSON/path under `GOOGLE_SERVICE_GATEWAY_`.
Profile-specific sources use `CREDENTIAL_<NORMALIZED_NAME>_<SUFFIX>`. Explicit
vault profiles retain precedence over unrelated global credentials, and explicit
service-account/token-env selectors remain supported. Ambiguous external sources
and conflicting token aliases fail without revealing values.

External files are bounded, regular, private, current-user-owned, and read-only.
Fresh externally obtained tokens need neither a client nor login; expired tokens
require replacement. Vault-style numeric and ISO-8601 dates both decode.
Token-source resolution is called by all four operational adapters. The auth
adapter accepts call-scoped application JSON/path without client import and defaults
login to `google-personal`; explicit/saved scopes are still required.

Verification: `swift test` passes 101 tests. Seven new tests cover direct/custom
variable inputs, explicit-profile precedence, both token-date formats, expired
and ambiguous credentials, value non-disclosure, private token files and symlink
rejection, a mocked ordinary reader request without vault setup, and canonical
application JSON reaching the shared authorizer using the default login profile.
`swiftlint --quiet` exits zero; there are existing warnings elsewhere in the repo
and no warnings in the new external-credential implementation or its tests.

Remaining: OCR interactive auth, complete application-JSON integration in every
product, integration/distribution of the shared browser implementation, and a
registered shared application followed by a real authorized browser login.

## Token values, JSON contents, and file paths

The environment suffix states the input type explicitly. `ACCESS_TOKEN` is a
raw token value, `*_JSON` holds JSON contents, and `*_PATH` holds a filesystem
path. They are separate alternatives; no variable guesses whether its value is
a token, JSON, or a filename. OAuth application inputs identify the application;
token-store inputs authorize the user's API requests. Old names remain aliases.
Token-store payload schemas still retain each product's existing role/profile
binding requirements; the canonical environment naming does not make those
payloads interchangeable across products.

Analytics and Marketing now accept `OAUTH_CLIENT_JSON` alongside
`OAUTH_CLIENT_PATH` for both login and refresh. Inline application JSON is kept
in memory and excluded from encoded profile configuration. Regression tests cover
mocked browser login, persisted refresh, ambiguous source rejection, and error
non-disclosure. No application file is created from the inline input.

OCR now has `auth login`, `auth status`, and confirmed `auth revoke`, backed by
the shared browser authorizer. Managed private token files support ordinary
execution and refresh. Direct access tokens, external token JSON/path, and
service-account JSON/path remain independent acquisition paths. OCR status never
falls back to a saved token when explicitly supplied inline JSON is invalid.
The shared library revision is published in draft PR
https://github.com/tacogips/google-service-gateway/pull/1; OCR resolves that exact
GitHub revision, rather than a local package path.

First-run login without application setup remains unfinished: no distribution
application has been registered/selected, and no live Google browser authorization
has been completed. Other gateways still need full integration with the shared
browser implementation.

Verification for the input-type correction: `swift test` passes 299 Analytics,
116 Marketing, and 34 OCR tests. `swiftlint --quiet` exits zero in all three;
Analytics and OCR are warning-free. Marketing retains existing warnings in
unrelated/previously existing code; the new inline-input tests and credential
selection code have no warnings. `git diff --check` passes for all three repos.

## Profile source selection and implicit profiles

Canonical profile source precedence now applies to the whole input group in
Calendar, Gmail, Docs/Sheets/Drive, Analytics, and Marketing. A profile's raw
token or inline token JSON suppresses a product default file path; a profile
application JSON input suppresses a product default application path. Same-level
alias conflicts still fail without revealing values. OCR already applies this
group selection, and Service preserves its explicit-vault-profile precedence.
Calendar direct tokens now also reject malformed header values before execution.

Marketing synthesizes implemented product/role profiles when no configuration
is selected. Auth defaults to Google Ads; `--product` selects another implemented
product. Ordinary command families choose the same product/role profiles.
Default private stores are under the product and role beneath the state directory.
An explicit config never falls back. Login creates missing private parents before
browser authorization; external credentials still require no login or client.

Analytics now gives its synthesized `default-env` profile a managed token store
under a role-specific state directory. Config and a custom store path are optional;
a registered application is still required. Missing managed tokens report an auth
failure. OAuth application and token destinations cannot collide.

Verification: Calendar passes 128 Swift Testing tests plus 6 XCTest tests; Gmail
passes 147 XCTest tests plus 178 Swift Testing tests; Docs/Sheets/Drive pass 178
tests; Analytics passes 302 tests; Marketing passes 123 tests. Commands were
`swift test` and `swiftlint --quiet` in each changed repository. New source-selection
and default-profile files/tests have no lint warnings. Marketing/Gmail retain
existing warnings elsewhere. Mocked default login saves credentials which ordinary
requests use without config/application input. Path collision regression tests
prove config files remain unchanged and authorization never starts on collision.

Current clean-environment probe:
`/tmp/google-gateway-current-clean-auth-results.json`. No probe opened a browser.
Calendar, Analytics, OCR, and Service auth still need a registered application.
Marketing now selects its implicit profile rather than requiring config, then
fails on the unavailable application. Docs/Sheets/Drive require role-specific
OAuth setup. Gmail draft/sender still hit a synthesized access-mode mismatch;
Service reader/writer/admin/deleter reject `auth login` and require the auth
executable. These startup gaps need implementation; the overall auth request
is not yet complete. The deprecated Docs package utility returns usage rather
than performing login. Shared-library extraction is optional; a shared default
registered application and consistent command behavior are required.

Calendar completion evidence was rechecked independently: both built executables
show their distinct roles; reader help excludes event mutation commands and
writer help includes create/update/delete. The boundary test suite checks typed
and raw GraphQL writes. GitHub currently reports repository name
`google-calendar-gateway` at https://github.com/tacogips/google-calendar-gateway.

## Remaining startup mismatches corrected

Gmail's implicit profile now follows its executable: read, read_send (draft and
sender), read_modify (threads), or full (message-box). Explicit and existing
implicit configuration files retain their declared access modes. Synthesized
non-reader token filenames and vault access-mode keys keep credentials separate;
reader migration remains intact. New tests cover all profile modes, missing-client
login in reader/draft/sender, explicit-config rejection, and mocked login followed
by resolution without application input. Reader tokens survive subsequent send
logins unchanged. Gmail now passes 151 XCTest plus 178 Swift Testing tests.

Service's reader/writer/admin/deleter route auth/oauth commands through the public
Core AuthAdapter. Compatibility aliases preserve imports from the auth executable.
Login requests explicit/saved scopes or the Cloud Platform default; it stores the
validated application and user grant together for subsequent use. Ordinary commands
can resolve the saved default profile, while missing explicit token variables
still fail. Four role cases exercise mocked authorization and storage; default
reader execution uses the saved token. All 104 Service tests pass.

The deprecated Docs package executable is now a Docs reader alias, rather than a
scaffold greeting on `auth login`. All 178 Docs/Sheets/Drive tests pass. Direct
runtime checks verify help, failed clean login, and token-value-free status with
an external access token. Marketing's missing-client diagnostic now identifies
the missing application rather than calling the valid implicit profile invalid;
all 123 tests pass.

Verification commands were `swift test`, `swiftlint --quiet`, and `git diff --check`
in the changed repositories. Newly added mode/auth adapter/tests have no lint
warnings; unrelated existing warnings remain. The latest clean probe of all 28
built commands is `/tmp/google-gateway-current-clean-auth-results.json`: Gmail
access-mode failures, Service unknown-auth failures, and the Docs alias's false
success are gone. Every clean login still stops before Google authorization
because the application/role credential source is unavailable. No browser was
opened, and no live authorization has been completed. Registration/distribution
of an application client and actual authorized browser login remain unfinished.
