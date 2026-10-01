import Darwin
import Foundation

private let calendarTokenRefreshLeeway: TimeInterval = 60

struct GoogleOAuthClient: Decodable {
  let clientId: String
  let clientSecret: String?
  let authURI: String?
  let tokenURI: String?

  enum CodingKeys: String, CodingKey {
    case clientId = "client_id"
    case clientSecret = "client_secret"
    case authURI = "auth_uri"
    case tokenURI = "token_uri"
  }
}

enum GoogleOAuthClientUse {
  case desktopLogin
  case tokenRefresh
}

enum CalendarAccessTokenUse {
  case read
  case write

  var missingAuthMessage: String {
    switch self {
    case .read:
      return "Calendar authentication is required"
    case .write:
      return "Calendar write authentication is required"
    }
  }

  var requiredAccessMode: CalendarAccessMode {
    switch self {
    case .read:
      return .read
    case .write:
      return .readWrite
    }
  }
}

private enum GoogleOAuthClientSource {
  case installed
  case web
}

private struct GoogleOAuthClientFile: Decodable {
  let installed: GoogleOAuthClient?
  let web: GoogleOAuthClient?
}

func loadGoogleOAuthClient(
  credential: CalendarCredentialConfig,
  use: GoogleOAuthClientUse
) throws -> GoogleOAuthClient {
  do {
    let data: Data
    if let oauthClientSecretJSON = credential.oauthClientSecretJSON {
      data = Data(oauthClientSecretJSON.utf8)
    } else {
      data = try Data(contentsOf: URL(fileURLWithPath: credential.oauthClientSecretPath))
    }
    let decoded = try JSONDecoder().decode(GoogleOAuthClientFile.self, from: data)
    let selected = try selectGoogleOAuthClient(decoded, credential: credential, use: use)
    let client = normalizedGoogleOAuthClient(selected.client)
    try validateGoogleOAuthClient(client, source: selected.source, credential: credential, use: use)
    return client
  } catch let error as GoogleCalendarGatewayError {
    throw error
  } catch {
    throw GoogleCalendarGatewayError(
      "Failed to read Google Calendar OAuth client JSON",
      code: .configInvalid,
      exitCode: oauthClientLoadExitCode(use),
      details: ["credentialId": credential.id, "path": credential.oauthClientSecretPath, "cause": error.localizedDescription]
    )
  }
}

func validGoogleCalendarAccessToken(
  credential: CalendarCredentialConfig,
  use: CalendarAccessTokenUse
) throws -> String {
  do {
    if credential.tokenStoreJSON != nil {
      return try validGoogleCalendarAccessTokenWithoutLock(credential: credential, use: use)
    }
    return try withGoogleCalendarTokenStoreLock(path: credential.tokenStorePath) {
      try validGoogleCalendarAccessTokenWithoutLock(credential: credential, use: use)
    }
  } catch let error as GoogleCalendarGatewayError {
    throw calendarTokenSourceError(error, credential: credential)
  }
}

func writeGoogleCalendarOAuthTokenStore(
  _ tokenStore: CalendarOAuthTokenStore,
  to path: String,
  errorMessage: String,
  exitCode: GoogleCalendarGatewayExitCode
) throws {
  do {
    let data = try JSONEncoder().encode(tokenStore)
    try writeCalendarSecureTokenFile(data, to: path)
  } catch {
    throw GoogleCalendarGatewayError(
      errorMessage,
      code: .authRequired,
      exitCode: exitCode,
      details: ["path": path, "cause": error.localizedDescription]
    )
  }
}

func loadGoogleCalendarOAuthTokenStore(
  credential: CalendarCredentialConfig,
  missingAuthMessage: String
) throws -> CalendarOAuthTokenStore {
  do {
    let data: Data
    if let tokenStoreJSON = credential.tokenStoreJSON {
      data = Data(tokenStoreJSON.utf8)
    } else {
      guard calendarTokenFileExists(at: credential.tokenStorePath) else {
        throw GoogleCalendarGatewayError(
          missingAuthMessage,
          code: .authRequired,
          exitCode: .providerApiError,
          details: ["credentialId": credential.id, "tokenStorePath": credential.tokenStorePath]
        )
      }
      data = try calendarSecureTokenFileData(at: credential.tokenStorePath)
    }
    return try JSONDecoder().decode(CalendarOAuthTokenStore.self, from: data)
  } catch let error as GoogleCalendarGatewayError {
    throw error
  } catch {
    throw GoogleCalendarGatewayError(
      "Failed to read Google Calendar token store",
      code: .authRequired,
      exitCode: .providerApiError,
      details: ["credentialId": credential.id, "cause": error.localizedDescription]
    )
  }
}

private func validGoogleCalendarAccessTokenWithoutLock(
  credential: CalendarCredentialConfig,
  use: CalendarAccessTokenUse
) throws -> String {
  let tokenStore = try loadGoogleCalendarOAuthTokenStore(credential: credential, missingAuthMessage: use.missingAuthMessage)
  try validateTokenStoreAccessMode(tokenStore, credential: credential, use: use)
  if let accessToken = nonBlank(tokenStore.accessToken),
     calendarAccessTokenIsFresh(expiresAt: tokenStore.expiresAt, refreshLeeway: calendarTokenRefreshLeeway) {
    return accessToken
  }
  guard credential.tokenStoreJSON == nil else {
    throw GoogleCalendarGatewayError("Inline token JSON requires refresh but is immutable; select a writable token file and log in", code: .authRequired, exitCode: .providerApiError)
  }
  return try refreshGoogleCalendarAccessToken(credential: credential, tokenStore: tokenStore)
}

func withGoogleCalendarTokenStoreLock<T>(path: String, operation: () throws -> T) throws -> T {
  let lockPath = path + ".lock"
  let lockParent = try calendarTokenParent(lockPath, create: true)
  let fd = Darwin.openat(lockParent.fd, lockParent.leaf, O_CREAT | O_RDWR | O_NOFOLLOW, S_IRUSR | S_IWUSR)
  guard fd >= 0 else {
    throw GoogleCalendarGatewayError(
      "Failed to open Google Calendar token store lock",
      code: .authRequired,
      exitCode: .providerApiError,
      details: ["path": lockPath]
    )
  }
  defer {
    close(fd)
  }
  var lockInfo = stat()
  guard Darwin.fstat(fd, &lockInfo) == 0,
        (lockInfo.st_mode & S_IFMT) == S_IFREG,
        lockInfo.st_nlink == 1 else {
    throw GoogleCalendarGatewayError(
      "Refusing unsafe Google Calendar token store lock",
      code: .authRequired,
      exitCode: .providerApiError,
      details: ["path": lockPath]
    )
  }
  _ = fchmod(fd, S_IRUSR | S_IWUSR)
  guard flock(fd, LOCK_EX) == 0 else {
    throw GoogleCalendarGatewayError(
      "Failed to lock Google Calendar token store",
      code: .authRequired,
      exitCode: .providerApiError,
      details: ["path": lockPath]
    )
  }
  defer {
    flock(fd, LOCK_UN)
  }
  return try operation()
}

func revokeGoogleOAuthToken(_ token: String) throws {
  guard let revokeURL = URL(string: "https://oauth2.googleapis.com/revoke") else {
    throw GoogleCalendarGatewayError(
      "Google OAuth revocation endpoint is invalid",
      code: .providerApiError,
      exitCode: .providerApiError
    )
  }
  var request = URLRequest(url: revokeURL)
  request.httpMethod = "POST"
  request.timeoutInterval = 30
  request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
  request.httpBody = formURLEncoded([("token", token)]).data(using: .utf8)
  _ = try performGoogleCalendarHTTPRequest(request, context: "Google OAuth token revocation failed")
}

private func validateTokenStoreAccessMode(
  _ tokenStore: CalendarOAuthTokenStore,
  credential: CalendarCredentialConfig,
  use: CalendarAccessTokenUse
) throws {
  let grantedAccessMode = tokenStore.accessMode ?? accessModeFromScopes(tokenStore.scope)
  if let grantedAccessMode, !calendarAccessMode(grantedAccessMode, covers: credential.accessMode) {
    throw GoogleCalendarGatewayError(
      "Stored Google Calendar token scope does not match configured access mode",
      code: .authRequired,
      exitCode: .providerApiError,
      details: ["credentialId": credential.id]
    )
  }
  if let scope = nonBlank(tokenStore.scope),
     !calendarScopesCover(accessMode: credential.accessMode, grantedScope: scope) {
    throw GoogleCalendarGatewayError(
      "Stored Google Calendar token scope is missing required calendar access",
      code: .authRequired,
      exitCode: .providerApiError,
      details: ["credentialId": credential.id]
    )
  }
  if use == .write, credential.accessMode != .readWrite && credential.accessMode != .full {
    throw GoogleCalendarGatewayError(
      "Google Calendar write access requires access_mode = \"read_write\" or \"full\"",
      code: .authRequired,
      exitCode: .providerApiError,
      details: ["credentialId": credential.id]
    )
  }
}

private func refreshGoogleCalendarAccessToken(
  credential: CalendarCredentialConfig,
  tokenStore: CalendarOAuthTokenStore
) throws -> String {
  guard let refreshToken = nonBlank(tokenStore.refreshToken) else {
    throw GoogleCalendarGatewayError(
      "Stored Google Calendar access token is expired and has no refresh token",
      code: .authRequired,
      exitCode: .providerApiError,
      details: ["credentialId": credential.id]
    )
  }
  let client = try loadGoogleOAuthClient(credential: credential, use: .tokenRefresh)
  guard let tokenURI = nonBlank(client.tokenURI),
        let tokenURL = URL(string: tokenURI) else {
    throw GoogleCalendarGatewayError(
      "OAuth client token_uri is invalid",
      code: .configInvalid,
      exitCode: .configurationError,
      details: ["credentialId": credential.id]
    )
  }

  var fields = [
    ("client_id", client.clientId),
    ("grant_type", "refresh_token"),
    ("refresh_token", refreshToken)
  ]
  if let clientSecret = nonBlank(client.clientSecret) {
    fields.append(("client_secret", clientSecret))
  }

  var request = URLRequest(url: tokenURL)
  request.httpMethod = "POST"
  request.timeoutInterval = 30
  request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
  request.httpBody = formURLEncoded(fields).data(using: .utf8)
  let response = try performGoogleCalendarHTTPRequest(request, context: "Google Calendar token refresh failed")
  guard let object = try JSONSerialization.jsonObject(with: response.data) as? [String: Any],
        let accessToken = nonBlank(object["access_token"] as? String) else {
    throw GoogleCalendarGatewayError(
      "Google Calendar token refresh response did not include an access token",
      code: .authRequired,
      exitCode: .providerApiError,
      details: ["credentialId": credential.id]
    )
  }

  let refreshed = CalendarOAuthTokenStore(
    accessMode: tokenStore.accessMode ?? credential.accessMode,
    accessToken: accessToken,
    refreshToken: nonBlank(object["refresh_token"] as? String) ?? tokenStore.refreshToken,
    tokenType: nonBlank(object["token_type"] as? String) ?? tokenStore.tokenType,
    scope: nonBlank(object["scope"] as? String) ?? tokenStore.scope,
    expiresAt: intValue(object["expires_in"]).map {
      ISO8601DateFormatter().string(from: Date().addingTimeInterval(TimeInterval($0)))
    },
    emailAddress: tokenStore.emailAddress
  )
  guard credential.tokenStoreJSON == nil else {
    return accessToken
  }
  try writeGoogleCalendarOAuthTokenStore(
    refreshed,
    to: credential.tokenStorePath,
    errorMessage: "Failed to write refreshed Google Calendar token store",
    exitCode: .providerApiError
  )
  return accessToken
}

enum GoogleCalendarHTTPFailureKind {
  case general
  case event
}

func performGoogleCalendarHTTPRequest(
  _ request: URLRequest,
  context: String,
  failureKind: GoogleCalendarHTTPFailureKind = .general
) throws -> (data: Data, response: HTTPURLResponse) {
  let semaphore = DispatchSemaphore(value: 0)
  let box = HTTPResultBox()
  URLSession.shared.dataTask(with: request) { data, response, error in
    defer {
      semaphore.signal()
    }
    if let error {
      box.store(.failure(error))
      return
    }
    guard let data,
          let httpResponse = response as? HTTPURLResponse else {
      box.store(.failure(GoogleCalendarGatewayError(
        "Google Calendar API response was empty",
        code: .providerApiError,
        exitCode: .providerApiError
      )))
      return
    }
    box.store(.success((data, httpResponse)))
  }.resume()
  semaphore.wait()

  let resolved: (data: Data, response: HTTPURLResponse)
  do {
    resolved = try box.load()?.get() ?? {
      throw GoogleCalendarGatewayError(
        "Google Calendar API request did not complete",
        code: .providerApiError,
        exitCode: .providerApiError
      )
    }()
  } catch let error as GoogleCalendarGatewayError {
    throw error
  } catch {
    throw GoogleCalendarGatewayError(
      context,
      code: .providerApiError,
      exitCode: .providerApiError,
      details: ["cause": error.localizedDescription]
    )
  }

  guard (200..<300).contains(resolved.response.statusCode) else {
    throw googleCalendarHTTPError(
      context: context,
      statusCode: resolved.response.statusCode,
      failureKind: failureKind
    )
  }
  return resolved
}

func googleCalendarHTTPError(
  context: String,
  statusCode: Int,
  failureKind: GoogleCalendarHTTPFailureKind = .general
) -> GoogleCalendarGatewayError {
  let code: GoogleCalendarGatewayErrorCode
  switch statusCode {
  case 401, 403:
    code = .authRequired
  case 404 where failureKind == .event:
    code = .eventNotFound
  case 410:
    code = .syncTokenExpired
  case 429:
    code = .providerRateLimited
  default:
    code = .providerApiError
  }
  return GoogleCalendarGatewayError(
    context,
    code: code,
    exitCode: .providerApiError,
    details: ["httpStatus": String(statusCode)]
  )
}

func calendarScopes(accessMode: CalendarAccessMode) -> [String] {
  switch accessMode {
  case .full:
    return ["https://www.googleapis.com/auth/calendar"]
  case .read:
    return [
      "https://www.googleapis.com/auth/calendar.events.readonly",
      "https://www.googleapis.com/auth/calendar.calendarlist.readonly",
      "https://www.googleapis.com/auth/calendar.freebusy"
    ]
  case .readWrite:
    return [
      "https://www.googleapis.com/auth/calendar.events",
      "https://www.googleapis.com/auth/calendar.calendarlist.readonly",
      "https://www.googleapis.com/auth/calendar.freebusy"
    ]
  }
}

private final class HTTPResultBox: @unchecked Sendable {
  private let lock = NSLock()
  private var result: Result<(Data, HTTPURLResponse), Error>?

  func store(_ result: Result<(Data, HTTPURLResponse), Error>) {
    lock.lock()
    self.result = result
    lock.unlock()
  }

  func load() -> Result<(Data, HTTPURLResponse), Error>? {
    lock.lock()
    defer {
      lock.unlock()
    }
    return result
  }
}

private func selectGoogleOAuthClient(
  _ file: GoogleOAuthClientFile,
  credential: CalendarCredentialConfig,
  use: GoogleOAuthClientUse
) throws -> (client: GoogleOAuthClient, source: GoogleOAuthClientSource) {
  switch use {
  case .desktopLogin:
    if file.installed == nil, let web = file.web { return (web, .web) }
    guard let installed = file.installed else {
      throw GoogleCalendarGatewayError(
        "OAuth client JSON must contain an installed desktop client",
        code: .configInvalid,
        exitCode: .authenticationBootstrapError,
        details: ["credentialId": credential.id, "path": credential.oauthClientSecretPath]
      )
    }
    return (installed, .installed)
  case .tokenRefresh:
    if let installed = file.installed {
      return (installed, .installed)
    }
    guard let web = file.web else {
      throw GoogleCalendarGatewayError(
        "OAuth client JSON must contain installed or web credentials",
        code: .configInvalid,
        exitCode: .configurationError,
        details: ["credentialId": credential.id, "path": credential.oauthClientSecretPath]
      )
    }
    return (web, .web)
  }
}

private func normalizedGoogleOAuthClient(_ client: GoogleOAuthClient) -> GoogleOAuthClient {
  GoogleOAuthClient(
    clientId: nonBlank(client.clientId) ?? "",
    clientSecret: nonBlank(client.clientSecret),
    authURI: nonBlank(client.authURI),
    tokenURI: nonBlank(client.tokenURI)
  )
}

private func validateGoogleOAuthClient(
  _ client: GoogleOAuthClient,
  source: GoogleOAuthClientSource,
  credential: CalendarCredentialConfig,
  use: GoogleOAuthClientUse
) throws {
  guard nonBlank(client.clientId) != nil,
        nonBlank(client.tokenURI) != nil else {
    throw invalidOAuthClientError(credential: credential, use: use)
  }
  if use == .desktopLogin, nonBlank(client.authURI) == nil {
    throw invalidOAuthClientError(credential: credential, use: use)
  }
  if source == .web, nonBlank(client.clientSecret) == nil {
    throw invalidOAuthClientError(credential: credential, use: use)
  }
}

private func invalidOAuthClientError(
  credential: CalendarCredentialConfig,
  use: GoogleOAuthClientUse
) -> GoogleCalendarGatewayError {
  GoogleCalendarGatewayError(
    oauthClientInvalidMessage(use),
    code: .configInvalid,
    exitCode: oauthClientLoadExitCode(use),
    details: ["credentialId": credential.id, "path": credential.oauthClientSecretPath]
  )
}

private func oauthClientInvalidMessage(_ use: GoogleOAuthClientUse) -> String {
  switch use {
  case .desktopLogin:
    return "OAuth client JSON must contain an installed desktop client"
  case .tokenRefresh:
    return "OAuth client JSON must contain refreshable installed or web credentials"
  }
}

private func oauthClientLoadExitCode(_ use: GoogleOAuthClientUse) -> GoogleCalendarGatewayExitCode {
  switch use {
  case .desktopLogin:
    return .authenticationBootstrapError
  case .tokenRefresh:
    return .configurationError
  }
}
