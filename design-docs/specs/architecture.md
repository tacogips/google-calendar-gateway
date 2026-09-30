# Architecture

## Status

Draft

## Overview

`google-calendar-gateway` is a Swift Package Manager project with a calendar-domain
library target, reader and writer executable targets, tests, and release automation for
Homebrew.

## Targets

- `GoogleCalendarGatewayCore`: calendar config, auth status, provider adapters,
  event and free/busy operations, GraphQL-style command execution, and public
  library API
- `GoogleCalendarGatewayReader` and `GoogleCalendarGatewayWriter`: command line entry points for the reader and writer
  executables
- `GoogleCalendarGatewayCoreTests`: package tests

## Release Surfaces

- Homebrew formula archives under `dist/homebrew/`
- Signed and notarized Cask DMGs under `dist/homebrew-cask/`

## Supported Platform Boundary

The package currently targets macOS 14 and later. The local Google Calendar
OAuth bootstrap is a macOS desktop flow: it uses Apple platform APIs for random
bytes, local loopback sockets, key material handling, and browser launch. Until
those pieces are moved behind portable adapters and implemented for Linux, CI
must treat the product as macOS-only.

Required CI behavior:

- macOS CI builds and tests the package and executable.
- Linux CI must not build the macOS-only product target unless the OAuth
  bootstrap has been made portable.
- If Linux support is reintroduced, platform-specific code must live behind
  narrow adapters and must be covered by Linux build verification.
- Secret scanning must use a revision range that exists for first pushes and
  for ordinary pull requests; when no valid base revision exists, scan the full
  repository history or the checked-out tree instead of failing before scan
  execution.

This is an intentional near-term platform boundary, not a permanent rejection
of Linux support.
