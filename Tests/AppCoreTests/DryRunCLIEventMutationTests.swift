import Foundation
import Testing
@testable import GoogleCalendarGatewayCore

@Suite("DryRun CLI Event Mutations")
struct DryRunCLIEventMutationTests {
  @Test("DryRun CLI uses injected service and canonical previews")
  func previewCommands() throws {
    let paths = temporaryConfigPaths()
    defer { try? FileManager.default.removeItem(atPath: paths.root) }
    try writeConfig(paths: paths, accessMode: "read_write")
    let provider = RecordingCalendarProvider()
    let cli = GoogleCalendarGatewayCLI(mode: .writer) { GoogleCalendarGatewayService(config: $0, provider: provider) }

    let create = cli.run(arguments: [
      "event", "create", "--config", paths.config, "--calendar", "personal",
      "--summary", "Planning", "--start", "2026-07-01T09:00:00Z", "--end", "2026-07-01T09:30:00Z",
      "--attendee-emails", "[\"first@example.com\",\"second@example.com\"]",
      "--reminder-overrides", "[\"popup:30\",\"email:1440\"]", "--dry-run"
    ], environment: env(paths: paths))
    #expect(create.exitCode == 0)
    let createObject = try decodedJSONObject(create.stdout)
    #expect(createObject["operation"] as? String == "createEvent")

    let update = cli.run(arguments: [
      "event", "update", "--config", paths.config, "--calendar", "personal", "--event-id", "event-1",
      "--summary", "Updated", "--reminder-use-default=false", "--create-conference", "false", "--dry-run=true"
    ], environment: env(paths: paths))
    #expect(update.exitCode == 0)
    #expect(try decodedJSONObject(update.stdout)["operation"] as? String == "updateEvent")

    let delete = cli.run(arguments: [
      "event", "delete", "--config", paths.config, "--calendar", "personal", "--event-id", "event-1",
      "--send-updates", "none", "--dry-run"
    ], environment: env(paths: paths))
    #expect(delete.exitCode == 0)
    #expect(try decodedJSONObject(delete.stdout)["operation"] as? String == "deleteEvent")
    #expect(provider.createInputs.isEmpty)
    #expect(provider.updateInputs.isEmpty)
    #expect(provider.deleteCalls.isEmpty)
  }

  @Test("DryRun CLI false and omitted values preserve live routing")
  func liveCommands() throws {
    let paths = temporaryConfigPaths()
    defer { try? FileManager.default.removeItem(atPath: paths.root) }
    try writeConfig(paths: paths, accessMode: "read_write")
    let provider = RecordingCalendarProvider()
    let cli = GoogleCalendarGatewayCLI(mode: .writer) { GoogleCalendarGatewayService(config: $0, provider: provider) }

    let create = cli.run(arguments: [
      "event", "create", "--config", paths.config, "--calendar", "personal",
      "--start", "2026-07-01T09:00:00Z", "--end", "2026-07-01T09:30:00Z", "--dry-run=false"
    ], environment: env(paths: paths))
    let delete = cli.run(arguments: [
      "event", "delete", "--config", paths.config, "--calendar", "personal", "--event-id", "event-1"
    ], environment: env(paths: paths))
    #expect(create.exitCode == 0)
    #expect(delete.exitCode == 0)
    #expect(provider.createInputs.count == 1)
    #expect(provider.deleteCalls.count == 1)
  }

  @Test("DryRun CLI rejects malformed requests before service creation")
  func parsingFailures() throws {
    let paths = temporaryConfigPaths()
    defer { try? FileManager.default.removeItem(atPath: paths.root) }
    try writeConfig(paths: paths, accessMode: "read_write")
    var factoryCalls = 0
    let cli = GoogleCalendarGatewayCLI(mode: .writer) {
      factoryCalls += 1
      return GoogleCalendarGatewayService(config: $0, provider: RecordingCalendarProvider())
    }
    let requests = [
      ["event", "create", "--config", paths.config, "--calendar", "personal", "--attendee-emails", "not-json"],
      ["event", "create", "--config", paths.config, "--calendar", "personal", "--attendee-emails", "[1]"],
      ["event", "create", "--config", paths.config, "--calendar", "personal", "--reminder-overrides", "[\"popup:-1\"]"],
      ["event", "create", "--config", paths.config, "--calendar", "personal", "--visibility", "hidden"],
      ["event", "create", "--config", paths.config, "--calendar", "personal", "--event-id", "not-allowed"],
      ["event", "create", "--config", paths.config, "--calendar", "personal", "--dry-run=TRUE"],
      ["event", "delete", "--config", paths.config, "--calendar", "personal"],
      ["event", "delete", "--config", paths.config, "--calendar", "personal", "--event-id", "one", "--event-id", "two"],
      ["event", "delete", "--config", paths.config, "--calendar", "personal", "--event-id", "one", "--unknown"],
      ["event", "delete", "extra", "--config", paths.config, "--calendar", "personal", "--event-id", "one"]
    ]
    for request in requests {
      let result = cli.run(arguments: request, environment: env(paths: paths))
      #expect(result.exitCode == GoogleCalendarGatewayExitCode.invalidCliUsage.rawValue)
      #expect(result.stdout.isEmpty)
      #expect(result.stderr.contains("INVALID_ARGUMENT"))
    }
    #expect(factoryCalls == 0)
  }

  @Test("DryRun CLI preserves WRITE_DISABLED")
  func readOnly() throws {
    let paths = temporaryConfigPaths()
    defer { try? FileManager.default.removeItem(atPath: paths.root) }
    try writeConfig(paths: paths, accessMode: "read")
    let provider = RecordingCalendarProvider()
    let cli = GoogleCalendarGatewayCLI(mode: .writer) { GoogleCalendarGatewayService(config: $0, provider: provider) }
    let result = cli.run(arguments: [
      "event", "delete", "--config", paths.config, "--calendar", "personal", "--event-id", "event-1", "--dry-run"
    ], environment: env(paths: paths))
    #expect(result.exitCode == GoogleCalendarGatewayExitCode.graphqlExecutionError.rawValue)
    #expect(result.stderr.contains("WRITE_DISABLED"))
    #expect(provider.deleteCalls.isEmpty)
  }
}
