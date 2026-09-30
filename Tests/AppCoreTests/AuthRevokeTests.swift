import Foundation
import Testing
@testable import GoogleCalendarGatewayCore

@Test func authRevokeReportsProviderAndLocalDeletionOutcomes() throws {
  let paths = temporaryConfigPaths()
  defer {
    try? FileManager.default.removeItem(atPath: paths.root)
  }
  try writeConfig(paths: paths)
  var revokedToken: String?
  let config = try GoogleCalendarGatewayConfigLoader.loadConfig(configPath: paths.config, environment: env(paths: paths))
  let service = GoogleCalendarGatewayService(config: config)

  let result = try service.revokeAuth(credentialId: "google-personal") { token in
    revokedToken = token
  }

  #expect(revokedToken == "refresh")
  #expect(result["providerRevocationAttempted"] as? Bool == true)
  #expect(result["providerRevoked"] as? Bool == true)
  #expect(result["localTokenDeleted"] as? Bool == true)
  #expect(result["localDeletionSkipped"] as? Bool == false)
  #expect(!FileManager.default.fileExists(atPath: paths.token))
}

@Test func authRevokeDoesNotDeleteEnvironmentSuppliedTokenStores() throws {
  let config = GoogleCalendarGatewayConfig(
    configPath: "/tmp/google-calendar-gateway-test.toml",
    storage: CalendarStorageConfig(cacheDir: "/tmp/google-calendar-gateway-cache"),
    credentials: [
      testCredential(tokenStoreJSON: """
      {"accessMode":"read","accessToken":"access","refreshToken":"refresh","expiresAt":"2099-01-01T00:00:00Z"}
      """)
    ],
    accounts: testConfig().accounts
  )
  let service = GoogleCalendarGatewayService(config: config)
  var revokedToken: String?

  let result = try service.revokeAuth(credentialId: "google-personal") { token in
    revokedToken = token
  }

  #expect(revokedToken == "refresh")
  #expect(result["providerRevoked"] as? Bool == true)
  #expect(result["localTokenDeleted"] as? Bool == false)
  #expect(result["localDeletionSkipped"] as? Bool == true)
  #expect(result["localDeletionReason"] as? String == "token store is supplied by environment")
}

@Test func authRevokeDeletesLocalTokenStoreWhenProviderRevocationFails() throws {
  let paths = temporaryConfigPaths()
  defer {
    try? FileManager.default.removeItem(atPath: paths.root)
  }
  try writeConfig(paths: paths)
  let config = try GoogleCalendarGatewayConfigLoader.loadConfig(configPath: paths.config, environment: env(paths: paths))
  let service = GoogleCalendarGatewayService(config: config)

  let result = try service.revokeAuth(credentialId: "google-personal") { _ in
    throw GoogleCalendarGatewayError("revocation unavailable", code: .providerApiError, exitCode: .providerApiError)
  }

  #expect(result["providerRevocationAttempted"] as? Bool == true)
  #expect(result["providerRevoked"] as? Bool == false)
  #expect(result["providerRevocationError"] as? String == "revocation unavailable")
  #expect(result["localTokenDeleted"] as? Bool == true)
  #expect(!FileManager.default.fileExists(atPath: paths.token))
}
