import Foundation
import Testing
@testable import GoogleCalendarGatewayCore

@Test func tokenRefreshPersistsRotatedRefreshToken() throws {
  let paths = temporaryConfigPaths()
  defer {
    try? FileManager.default.removeItem(atPath: paths.root)
  }
  let tokenServer = try OneShotHTTPServer(responseBody: """
  {"access_token":"new-access","refresh_token":"rotated-refresh","token_type":"Bearer","expires_in":3600,"scope":"https://www.googleapis.com/auth/calendar.events.readonly https://www.googleapis.com/auth/calendar.calendarlist.readonly https://www.googleapis.com/auth/calendar.freebusy"}
  """)
  try writeConfig(paths: paths)
  try """
  {"installed":{"client_id":"client","auth_uri":"https://accounts.example.test/auth","token_uri":"\(tokenServer.url)"}}
  """.write(toFile: paths.oauthClient, atomically: true, encoding: .utf8)
  try """
  {"accessMode":"read","accessToken":"old-access","refreshToken":"old-refresh","expiresAt":"2000-01-01T00:00:00Z","scope":"https://www.googleapis.com/auth/calendar.events.readonly https://www.googleapis.com/auth/calendar.calendarlist.readonly https://www.googleapis.com/auth/calendar.freebusy"}
  """.write(toFile: paths.token, atomically: true, encoding: .utf8)
  let config = try GoogleCalendarGatewayConfigLoader.loadConfig(configPath: paths.config, environment: env(paths: paths))
  let credential = try #require(config.credentials.first)

  let accessToken = try validGoogleCalendarAccessToken(credential: credential, use: .read)
  let request = try tokenServer.waitForRequest()
  let persisted = try JSONDecoder().decode(
    CalendarOAuthTokenStore.self,
    from: Data(contentsOf: URL(fileURLWithPath: paths.token))
  )

  #expect(accessToken == "new-access")
  #expect(request.contains("POST /token HTTP/1.1"))
  #expect(request.contains("grant_type=refresh_token"))
  #expect(request.contains("refresh_token=old-refresh"))
  #expect(persisted.accessToken == "new-access")
  #expect(persisted.refreshToken == "rotated-refresh")
}
