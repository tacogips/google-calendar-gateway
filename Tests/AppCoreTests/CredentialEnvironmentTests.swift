import Foundation
@testable import GoogleCalendarGatewayCore
import XCTest

final class CredentialEnvironmentTests: XCTestCase {
  func testProfileSourceReplacesProductSourceAcrossInputTypes() throws {
    let selected = try calendarCredentialEnvironment([
      "GOOGLE_CALENDAR_GATEWAY_TOKEN_STORE_PATH": "/unused/default-token.json",
      "GOOGLE_CALENDAR_GATEWAY_CREDENTIAL_WORK_ACCESS_TOKEN": "work-token",
      "GOOGLE_CALENDAR_GATEWAY_OAUTH_CLIENT_PATH": "/unused/default-client.json",
      "GOOGLE_CALENDAR_GATEWAY_CREDENTIAL_WORK_OAUTH_CLIENT_JSON": "inline-application"
    ], credentialIDs: ["work"])
    XCTAssertEqual(selected["GOOGLE_CALENDAR_GATEWAY_CREDENTIAL_WORK_ACCESS_TOKEN"], "work-token")
    XCTAssertNil(selected["GOOGLE_CALENDAR_GATEWAY_CREDENTIAL_WORK_TOKEN_STORE_PATH"])
    XCTAssertEqual(selected["GOOGLE_CALENDAR_GATEWAY_CREDENTIAL_WORK_OAUTH_CLIENT_SECRET_JSON"], "inline-application")
    XCTAssertNil(selected["GOOGLE_CALENDAR_GATEWAY_CREDENTIAL_WORK_OAUTH_CLIENT_SECRET_PATH"])
  }

  func testMalformedDirectTokenIsRejectedWithoutDisclosure() throws {
    XCTAssertThrowsError(try calendarCredentialEnvironment([
      "GOOGLE_CALENDAR_GATEWAY_ACCESS_TOKEN": "invalid\ntoken"
    ])) { error in
      XCTAssertFalse(String(describing: error).contains("invalid\ntoken"))
    }
  }

  func testBareAccessTokenNeedsNoClient() throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: root) }
    let config = try GoogleCalendarGatewayConfigLoader.loadConfig(environment: [
      "XDG_CONFIG_HOME": root.path, "XDG_STATE_HOME": root.path,
      "GOOGLE_CALENDAR_GATEWAY_ACCESS_TOKEN": "external-token"
    ])
    let credential = try XCTUnwrap(config.credentials.first)
    XCTAssertEqual(try validGoogleCalendarAccessToken(credential: credential, use: .read), "external-token")
    XCTAssertFalse(FileManager.default.fileExists(atPath: credential.tokenStorePath))
  }

  func testCanonicalClientAndLegacyAliasConflictDoesNotLeakValues() throws {
    XCTAssertThrowsError(try calendarCredentialEnvironment([
      "GOOGLE_CALENDAR_GATEWAY_CREDENTIAL_GOOGLE_PERSONAL_OAUTH_CLIENT_JSON": "canonical-secret",
      "GOOGLE_CALENDAR_GATEWAY_CREDENTIAL_GOOGLE_PERSONAL_OAUTH_CLIENT_SECRET_JSON": "legacy-secret"
    ])) { error in
      XCTAssertFalse(String(describing: error).contains("canonical-secret"))
      XCTAssertFalse(String(describing: error).contains("legacy-secret"))
    }
  }

  func testProfileTokenOverridesProductDefault() throws {
    let env = try calendarCredentialEnvironment([
      "GOOGLE_CALENDAR_GATEWAY_ACCESS_TOKEN": "default-token",
      "GOOGLE_CALENDAR_GATEWAY_CREDENTIAL_WORK_ACCESS_TOKEN": "work-token"
    ], credentialIDs: ["work"])
    let json = try XCTUnwrap(env["GOOGLE_CALENDAR_GATEWAY_CREDENTIAL_WORK_TOKEN_STORE_JSON"])
    let token = try JSONDecoder().decode(CalendarOAuthTokenStore.self, from: Data(json.utf8))
    XCTAssertEqual(token.accessToken, "work-token")
  }

  func testAmbiguousTokenSourcesAreRejected() throws {
    XCTAssertThrowsError(try calendarCredentialEnvironment([
      "GOOGLE_CALENDAR_GATEWAY_ACCESS_TOKEN": "token",
      "GOOGLE_CALENDAR_GATEWAY_TOKEN_STORE_PATH": "/tmp/token.json"
    ]))
  }
}
