import Foundation
import Testing
@testable import GoogleCalendarGatewayCore

@Test func calendarLogoutDeletesLocalTokenAndIsIdempotent() throws {
  let paths = temporaryConfigPaths()
  defer { try? FileManager.default.removeItem(atPath: paths.root) }
  try writeConfig(paths: paths)
  let config = try GoogleCalendarGatewayConfigLoader.loadConfig(configPath: paths.config, environment: [:])
  let service = GoogleCalendarGatewayService(config: config)
  let result = try service.logoutAuth(credentialId: "google-personal")
  #expect(result["state"] as? String == "LOGGED_OUT")
  #expect(result["localTokenDeleted"] as? Bool == true)
  #expect(!FileManager.default.fileExists(atPath: paths.token))
  #expect(try service.logoutAuth(credentialId: "google-personal")["localTokenDeleted"] as? Bool == false)
}

@Test func calendarLogoutPreservesInlineExternalCredential() throws {
  let config = GoogleCalendarGatewayConfig(
    configPath: "/tmp/calendar-logout.toml",
    storage: CalendarStorageConfig(cacheDir: "/tmp/calendar-logout-cache"),
    credentials: [testCredential(tokenStoreJSON: "external-fixture")],
    accounts: testConfig().accounts
  )
  let result = try GoogleCalendarGatewayService(config: config).logoutAuth(credentialId: "google-personal")
  #expect(result["externalCredentialPreserved"] as? Bool == true)
  #expect(result["localTokenDeleted"] as? Bool == false)
}

@Test func calendarLogoutPreservesExternalTokenFile() throws {
  let paths = temporaryConfigPaths()
  defer { try? FileManager.default.removeItem(atPath: paths.root) }
  try writeConfig(paths: paths)
  let original = try Data(contentsOf: URL(fileURLWithPath: paths.token))
  let config = try GoogleCalendarGatewayConfigLoader.loadConfig(configPath: paths.config, environment: env(paths: paths))
  let result = try GoogleCalendarGatewayService(config: config).logoutAuth(credentialId: "google-personal")
  #expect(result["externalCredentialPreserved"] as? Bool == true)
  #expect(try Data(contentsOf: URL(fileURLWithPath: paths.token)) == original)
}
