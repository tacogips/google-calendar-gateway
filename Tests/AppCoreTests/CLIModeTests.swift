import Foundation
import Testing
@testable import GoogleCalendarGatewayCore

@Suite("Reader and writer CLI boundaries")
struct CLIModeTests {
  @Test func bareAuthShowsHelpBeforeLoadingConfiguration() {
    for mode in [GoogleCalendarGatewayCLIMode.reader, .writer] {
      let result = GoogleCalendarGatewayCLI(mode: mode).run(arguments: ["auth", "--config", "/missing/config.toml"], environment: [:])
      #expect(result.exitCode == 0)
      #expect(result.stdout.contains("auth login"))
      #expect(result.stderr.isEmpty)
    }
  }

  @Test func helpMatchesMode() {
    for mode in [GoogleCalendarGatewayCLIMode.reader, .writer] {
      let result = GoogleCalendarGatewayCLI(mode: mode).run(arguments: ["--help"], environment: [:])
      #expect(result.exitCode == 0)
      #expect(result.stdout.contains(mode.executableName))
      #expect(result.stdout.contains("event create") == (mode == .writer))
    }
  }

  @Test func readerRejectsEventCommandsBeforeConfiguration() {
    for operation in ["create", "update", "delete"] {
      let result = GoogleCalendarGatewayCLI(mode: .reader).run(
        arguments: ["event", operation, "--config", "/missing/config.toml", "--dry-run"], environment: [:]
      )
      #expect(result.exitCode == GoogleCalendarGatewayExitCode.invalidCliUsage.rawValue)
      #expect(result.stderr.contains("WRITE_DISABLED"))
      #expect(result.stderr.contains("google-calendar-gateway-writer"))
    }
  }

  @Test func graphQLModeControlsTypedAndRawWrites() throws {
    let paths = temporaryConfigPaths()
    defer { try? FileManager.default.removeItem(atPath: paths.root) }
    try writeConfig(paths: paths, accessMode: "read_write")
    let writes = [
      "mutation { createEvent(calendarId: \"personal\", start: \"2026-07-01\", end: \"2026-07-02\") { id } }",
      "{ updateEvent(calendarId: \"personal\", eventId: \"event-1\", summary: \"Changed\") { id } }",
      "mutation { deleteEvent(calendarId: \"personal\", eventId: \"event-1\", dryRun: true) { operation } }",
      "{ calendarAPI(credentialId: \"google-personal\", method: \"GET\", path: \"/colors\", access: \"write\") { status } }"
    ] + ["POST", "PUT", "PATCH", "DELETE"].map {
      "{ calendarAPI(credentialId: \"google-personal\", method: \"\($0)\", path: \"/calendars/primary/events\", access: \"read\") { status } }"
    }
    for query in writes {
      for mode in [GoogleCalendarGatewayCLIMode.reader, .writer] {
        let cli = GoogleCalendarGatewayCLI(mode: mode) { GoogleCalendarGatewayService(config: $0, provider: FakeCalendarProvider()) }
        let result = cli.run(arguments: ["--config", paths.config, "graphql", "--query", query], environment: env(paths: paths))
        if mode == .reader {
          #expect(result.exitCode == GoogleCalendarGatewayExitCode.graphqlExecutionError.rawValue)
          #expect(result.stdout.contains("WRITE_DISABLED"))
        } else {
          #expect(result.exitCode == 0)
        }
      }
    }
  }

  @Test func bothModesAllowQueriesAndRawReads() throws {
    let paths = temporaryConfigPaths()
    defer { try? FileManager.default.removeItem(atPath: paths.root) }
    try writeConfig(paths: paths)
    for mode in [GoogleCalendarGatewayCLIMode.reader, .writer] {
      let cli = GoogleCalendarGatewayCLI(mode: mode) { GoogleCalendarGatewayService(config: $0, provider: FakeCalendarProvider()) }
      for query in [
        "{ calendars { id } }",
        "{ events(calendarId: \"personal\") { events { id } } }",
        "{ calendarAPI(credentialId: \"google-personal\", method: \"GET\", path: \"/colors\") { status } }"
      ] {
        let result = cli.run(arguments: ["--config", paths.config, "graphql", "--query", query], environment: env(paths: paths))
        #expect(result.exitCode == 0)
      }
    }
  }
}
