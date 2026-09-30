import Foundation
import Testing
@testable import GoogleCalendarGatewayCore

@Test func freshCalendarProfilesUseRoleScopesAndSeparateTokenFiles() throws {
  let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
  defer { try? FileManager.default.removeItem(at: root) }
  let environment = roleCredentialEnvironment(root)
  let reader = try GoogleCalendarGatewayConfigLoader.loadConfig(environment: environment)
  let writer = try GoogleCalendarGatewayConfigLoader.loadConfig(environment: environment, synthesizedAccessMode: .readWrite)
  let readCredential = try #require(reader.credentials.first)
  let writeCredential = try #require(writer.credentials.first)
  #expect(readCredential.accessMode == .read)
  #expect(writeCredential.accessMode == .readWrite)
  #expect(readCredential.tokenStorePath.hasSuffix("/google-personal.json"))
  #expect(writeCredential.tokenStorePath.hasSuffix("/google-personal-read-write.json"))
  #expect(readCredential.tokenStorePath != writeCredential.tokenStorePath)
  #expect(calendarScopes(accessMode: writeCredential.accessMode).contains("https://www.googleapis.com/auth/calendar.events"))
  #expect(!FileManager.default.fileExists(atPath: root.path))
}

@Test func freshCalendarWriterAcceptsExternalTokenAndDryRunsWithoutClient() throws {
  let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
  defer { try? FileManager.default.removeItem(at: root) }
  var environment = roleCredentialEnvironment(root)
  environment["GOOGLE_CALENDAR_GATEWAY_ACCESS_TOKEN"] = "external-writer-token"
  let config = try GoogleCalendarGatewayConfigLoader.loadConfig(environment: environment, synthesizedAccessMode: .readWrite)
  #expect(try validGoogleCalendarAccessToken(credential: #require(config.credentials.first), use: .write) == "external-writer-token")
  let provider = RecordingCalendarProvider()
  let cli = GoogleCalendarGatewayCLI(mode: .writer) { GoogleCalendarGatewayService(config: $0, provider: provider) }
  let result = cli.run(arguments: ["event", "create", "--calendar", "personal", "--summary", "Preview",
                                 "--start", "2026-10-01T09:00:00Z", "--end", "2026-10-01T09:30:00Z", "--dry-run"], environment: environment)
  #expect(result.exitCode == 0)
  #expect(result.stdout.contains("createEvent"))
  #expect(!result.stdout.contains("external-writer-token"))
  #expect(provider.createInputs.isEmpty)
  #expect(provider.updateInputs.isEmpty)
  #expect(provider.deleteCalls.isEmpty)
}

@Test func writerDefaultDoesNotMigrateHistoricalReaderCredentials() throws {
  let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
  defer { try? FileManager.default.removeItem(at: root) }
  let environment = roleCredentialEnvironment(root)
  let legacy = root.appendingPathComponent("config/google-calendar-gateway/tokens/google-personal.json")
  try FileManager.default.createDirectory(at: legacy.deletingLastPathComponent(), withIntermediateDirectories: true)
  let bytes = Data(#"{"accessMode":"read","accessToken":"reader-token"}"#.utf8)
  try bytes.write(to: legacy)
  let config = try GoogleCalendarGatewayConfigLoader.loadConfig(environment: environment, synthesizedAccessMode: .readWrite)
  #expect(try Data(contentsOf: legacy) == bytes)
  #expect(!FileManager.default.fileExists(atPath: try #require(config.credentials.first).tokenStorePath))
}

@Test func writerModePreservesExplicitReadOnlyConfiguration() throws {
  let paths = temporaryConfigPaths()
  defer { try? FileManager.default.removeItem(atPath: paths.root) }
  try writeConfig(paths: paths, accessMode: "read")
  let config = try GoogleCalendarGatewayConfigLoader.loadConfig(configPath: paths.config, environment: env(paths: paths), synthesizedAccessMode: .readWrite)
  #expect(config.credentials.first?.accessMode == .read)
}

private func roleCredentialEnvironment(_ root: URL) -> [String: String] {
  ["XDG_CONFIG_HOME": root.appendingPathComponent("config").path,
   "XDG_STATE_HOME": root.appendingPathComponent("state").path]
}
