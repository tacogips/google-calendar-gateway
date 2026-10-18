# Bounded write retries (0.1.11)

User requested configurable initial wait and maximum retries across gateway writes. Use per-config immutable typed policy, TOML/environment overrides, default2seconds/3retries, n1...60/m0...5, exponential60second cap. Retry only confirmed429/documented quota403 rejection or preconnection errors; decline mutation redirects so a later connection failure cannot hide the original write. Never replay ambiguous5xx/timeout/lost response or a confirmed write merely because parsing/readback failed. Preserve all existing permissions/read/OAuth behavior. Honor Retry-After minimums; stop if above cap. Request-scoped deadlines and cancellation prevent later attempts.

Validate real URLSession paths with local URLProtocol fixtures, fake backoff/deadline clocks, config integration, exact attempt budget, quota vs permission, transient connection vs ambiguous dispatch, and no duplicate write after success. Full tests/build/lint and both macOS release archives are required before publication; no live provider writes are used.

Validation: 19 XCTest tests plus 139 Swift Testing tests passed, including 13 retry/config/deadline fixtures. SwiftLint has only the two existing OAuthBootstrap formatting warnings. Independent Apple gateway maintainer review found no blocker. Successful event writes missing a returned identity are reported as unknown without replay. No live provider writes were performed.

## Completed release verification

- Immutable `v0.1.11` source: `950dfd1ade965e9d92af395bc2dd6b176e324b7a`.
- `arch -arm64 swift test`: 19 XCTest and 139 Swift Testing tests passed. SwiftLint retained only two pre-existing formatting warnings.
- Both macOS archives passed SHA-256 and extracted reader/writer version/help checks; all four public asset digests match local files.
- Formula strict Homebrew audit, fetch, upgrade, and tests passed. Tap change: `1ece8122b94ec08b0f950c8c1b46f91dfcea4d55`; metadata workflow `39131449964` succeeded. Immutable metadata `8a8dd3916c1b3d41e5dce03c00ca43b3b0041f69` reports version 0.1.11 and the committed Formula SHA-256.
- GitHub gitleaks and macOS-only platform-boundary CI passed. No live provider writes or container/image operations were performed.
