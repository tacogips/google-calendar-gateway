import Darwin
import Foundation
import Testing
@testable import GoogleCalendarGatewayCore

@Test func defaultCredentialDirectoryUsesXDGStateHome() {
  let directory = GoogleCalendarGatewayConfigLoader.resolveDefaultCredentialDirectory(
    environment: ["XDG_STATE_HOME": "/tmp/xdg-state"]
  )
  #expect(directory == "/tmp/xdg-state/google-calendar-gateway/credentials")
}

@Test func defaultCredentialDirectoryDefaultsToLocalState() {
  let directory = GoogleCalendarGatewayConfigLoader.resolveDefaultCredentialDirectory(environment: [:])
  let home = FileManager.default.homeDirectoryForCurrentUser.path
  #expect(directory == "\(home)/.local/state/google-calendar-gateway/credentials")
}

@Test func credentialDirEnvironmentVariableOverridesStateDefault() {
  let directory = GoogleCalendarGatewayConfigLoader.resolveDefaultCredentialDirectory(
    environment: [
      "GOOGLE_CALENDAR_GATEWAY_CREDENTIAL_DIR": "/tmp/riela-credentials",
      "XDG_STATE_HOME": "/tmp/xdg-state"
    ]
  )
  #expect(directory == "/tmp/riela-credentials")
}

@Test func synthesizedConfigStoresTokensUnderCredentialDirectory() throws {
  let scratch = FileManager.default.temporaryDirectory
    .appendingPathComponent("calendar-credential-dir-\(UUID().uuidString)", isDirectory: true)
  try FileManager.default.createDirectory(at: scratch, withIntermediateDirectories: true)
  defer { try? FileManager.default.removeItem(at: scratch) }
  let missingConfig = scratch.appendingPathComponent("config/google-calendar-gateway/config.toml").path
  let config = try GoogleCalendarGatewayConfigLoader.loadConfig(
    environment: [
      "XDG_CONFIG_HOME": scratch.appendingPathComponent("config").path,
      "GOOGLE_CALENDAR_GATEWAY_CREDENTIAL_DIR": "/tmp/riela-credentials"
    ]
  )
  _ = missingConfig
  #expect(config.credentials.first?.tokenStorePath == "/tmp/riela-credentials/google-personal.json")
}

@Test func implicitConfigMigratesLegacySynthesizedTokenToXDGStateOnce() throws {
  let scratch = try makeCredentialMigrationScratch()
  defer { try? FileManager.default.removeItem(at: scratch.root) }
  let legacy = scratch.config.appendingPathComponent("google-calendar-gateway/tokens/google-personal.json")
  try FileManager.default.createDirectory(at: legacy.deletingLastPathComponent(), withIntermediateDirectories: true)
  let expected = Data("{\"accessMode\":\"read\",\"accessToken\":\"legacy-token\"}".utf8)
  try expected.write(to: legacy)

  let config = try GoogleCalendarGatewayConfigLoader.loadConfig(environment: scratch.environment)
  let destination = try #require(config.credentials.first?.tokenStorePath)
  let migrated = try Data(contentsOf: URL(fileURLWithPath: destination))
  #expect(migrated == expected)
  #expect(FileManager.default.fileExists(atPath: legacy.path))
  #expect(filePermissions(destination) == 0o600)
  #expect(filePermissions(URL(fileURLWithPath: destination).deletingLastPathComponent().path) == 0o700)

  try FileManager.default.removeItem(atPath: destination)
  _ = try GoogleCalendarGatewayConfigLoader.loadConfig(environment: scratch.environment)
  #expect(!FileManager.default.fileExists(atPath: destination))
}

@Test func migrationNeverOverwritesStateTokenOrAppliesToCredentialDirectoryOverride() throws {
  let scratch = try makeCredentialMigrationScratch()
  defer { try? FileManager.default.removeItem(at: scratch.root) }
  let legacy = scratch.config.appendingPathComponent("google-calendar-gateway/tokens/google-personal.json")
  try FileManager.default.createDirectory(at: legacy.deletingLastPathComponent(), withIntermediateDirectories: true)
  try Data("{\"accessMode\":\"read\",\"accessToken\":\"legacy-token\"}".utf8).write(to: legacy)
  let destination = scratch.state.appendingPathComponent("google-calendar-gateway/credentials/google-personal.json")
  try FileManager.default.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
  try Data("new-token".utf8).write(to: destination)

  _ = try GoogleCalendarGatewayConfigLoader.loadConfig(environment: scratch.environment)
  let preserved = try Data(contentsOf: destination)
  #expect(preserved == Data("new-token".utf8))
  #expect(FileManager.default.fileExists(atPath: legacy.path))

  let override = scratch.root.appendingPathComponent("override")
  _ = try GoogleCalendarGatewayConfigLoader.loadConfig(environment: scratch.environment.merging([
    "GOOGLE_CALENDAR_GATEWAY_CREDENTIAL_DIR": override.path
  ]) { _, new in new })
  #expect(!FileManager.default.fileExists(atPath: override.appendingPathComponent("google-personal.json").path))
  #expect(FileManager.default.fileExists(atPath: legacy.path))
}

@Test func migrationRejectsSymlinkAndHardLinkedLegacyTokens() throws {
  let scratch = try makeCredentialMigrationScratch()
  defer { try? FileManager.default.removeItem(at: scratch.root) }
  let legacy = scratch.config.appendingPathComponent("google-calendar-gateway/tokens/google-personal.json")
  try FileManager.default.createDirectory(at: legacy.deletingLastPathComponent(), withIntermediateDirectories: true)
  let outside = scratch.root.appendingPathComponent("outside-token")
  try Data("token".utf8).write(to: outside)
  try FileManager.default.createSymbolicLink(at: legacy, withDestinationURL: outside)
  #expect(throws: Error.self) {
    try GoogleCalendarGatewayConfigLoader.loadConfig(environment: scratch.environment)
  }
  try FileManager.default.removeItem(at: legacy)
  try FileManager.default.linkItem(at: outside, to: legacy)
  #expect(throws: Error.self) {
    try GoogleCalendarGatewayConfigLoader.loadConfig(environment: scratch.environment)
  }
}

@Test func migrationRejectsAncestorSymlinkAndFIFOWithoutBlocking() throws {
  let fixture = try makeCredentialMigrationScratch()
  defer { try? FileManager.default.removeItem(at: fixture.root) }
  let legacy = fixture.config.appendingPathComponent("google-calendar-gateway/tokens/google-personal.json")
  try FileManager.default.createDirectory(at: legacy.deletingLastPathComponent(), withIntermediateDirectories: true)
  try Data("{\"accessMode\":\"read\"}".utf8).write(to: legacy)
  let outside = fixture.root.appendingPathComponent("outside")
  try FileManager.default.createDirectory(at: outside, withIntermediateDirectories: true)
  try FileManager.default.createDirectory(at: fixture.state, withIntermediateDirectories: true)
  try FileManager.default.createSymbolicLink(
    at: fixture.state.appendingPathComponent("google-calendar-gateway"), withDestinationURL: outside
  )
  #expect(throws: Error.self) { try GoogleCalendarGatewayConfigLoader.loadConfig(environment: fixture.environment) }
  try FileManager.default.removeItem(at: fixture.state.appendingPathComponent("google-calendar-gateway"))
  try FileManager.default.removeItem(at: legacy)
  guard mkfifo(legacy.path, S_IRUSR | S_IWUSR) == 0 else { throw POSIXError(.EIO) }
  #expect(throws: Error.self) { try GoogleCalendarGatewayConfigLoader.loadConfig(environment: fixture.environment) }
}

@Test func relativeXDGRootsFallBackToStandardLocations() {
  let home = FileManager.default.homeDirectoryForCurrentUser.path
  #expect(GoogleCalendarGatewayConfigLoader.resolveDefaultCredentialDirectory(environment: ["XDG_STATE_HOME": "relative"]) ==
    "\(home)/.local/state/google-calendar-gateway/credentials")
  #expect(GoogleCalendarGatewayConfigLoader.resolveDefaultConfigPath(environment: ["XDG_CONFIG_HOME": "relative"]) ==
    "\(home)/.config/google-calendar-gateway/config.toml")
}

private struct CredentialMigrationScratch {
  let root: URL
  let config: URL
  let state: URL
  let environment: [String: String]
}

@Test func missingImplicitCredentialsDoNotCreateStateDirectories() throws {
  let fixture = try makeCredentialMigrationScratch()
  defer { try? FileManager.default.removeItem(at: fixture.root) }
  _ = try GoogleCalendarGatewayConfigLoader.loadConfig(environment: fixture.environment)
  #expect(!FileManager.default.fileExists(atPath: fixture.state.path))
}

@Test func interruptedMigrationRecoversMarkerAndCannotResurrectRevokedToken() throws {
  let fixture = try makeCredentialMigrationScratch()
  defer { try? FileManager.default.removeItem(at: fixture.root) }
  let legacy = fixture.config.appendingPathComponent("google-calendar-gateway/tokens/google-personal.json")
  let destination = fixture.state.appendingPathComponent("google-calendar-gateway/credentials/google-personal.json")
  try FileManager.default.createDirectory(at: legacy.deletingLastPathComponent(), withIntermediateDirectories: true)
  let token = Data("{\"accessMode\":\"read\",\"accessToken\":\"test-token\"}".utf8)
  try token.write(to: legacy)
  #expect(throws: Error.self) {
    try migrateCalendarLegacyTokenStore(from: legacy.path, to: destination.path, beforeMarker: { throw POSIXError(.EIO) })
  }
  #expect(try Data(contentsOf: destination) == token)
  #expect(!FileManager.default.fileExists(atPath: destination.path + ".migration-complete"))
  _ = try GoogleCalendarGatewayConfigLoader.loadConfig(environment: fixture.environment)
  #expect(try removeCalendarSecureTokenFile(at: destination.path))
  _ = try GoogleCalendarGatewayConfigLoader.loadConfig(environment: fixture.environment)
  #expect(!FileManager.default.fileExists(atPath: destination.path))
  #expect(FileManager.default.fileExists(atPath: legacy.path))
}

private func makeCredentialMigrationScratch() throws -> CredentialMigrationScratch {
  let root = FileManager.default.temporaryDirectory
    .appendingPathComponent("calendar-token-migration-\(UUID().uuidString)", isDirectory: true)
  try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
  let config = root.appendingPathComponent("config", isDirectory: true)
  let state = root.appendingPathComponent("state", isDirectory: true)
  return CredentialMigrationScratch(
    root: root,
    config: config,
    state: state,
    environment: ["XDG_CONFIG_HOME": config.path, "XDG_STATE_HOME": state.path]
  )
}

private func filePermissions(_ path: String) -> Int? {
  let attributes = try? FileManager.default.attributesOfItem(atPath: path)
  return (attributes?[.posixPermissions] as? NSNumber)?.intValue
}
