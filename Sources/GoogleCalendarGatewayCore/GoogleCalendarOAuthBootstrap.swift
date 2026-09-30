import CryptoKit
import Darwin
import Foundation
import Security

public struct GoogleCalendarOAuthLoginOptions: Sendable {
  public let redirectURI: String?
  public let openBrowser: Bool
  public let timeoutSeconds: Int

  public static let `default` = GoogleCalendarOAuthLoginOptions(
    redirectURI: nil,
    openBrowser: true,
    timeoutSeconds: 300
  )

  public init(redirectURI: String?, openBrowser: Bool, timeoutSeconds: Int) {
    self.redirectURI = redirectURI
    self.openBrowser = openBrowser
    self.timeoutSeconds = timeoutSeconds
  }
}

struct GoogleCalendarOAuthBootstrapper {
  func login(
    credential: CalendarCredentialConfig,
    options: GoogleCalendarOAuthLoginOptions = .default
  ) throws -> [String: Any] {
    guard credential.tokenStoreJSON == nil else {
      throw calendarTokenSourceError(
        GoogleCalendarGatewayError("Inline token JSON is immutable", code: .invalidArgument, exitCode: .invalidCliUsage),
        credential: credential
      )
    }
    let client = try loadGoogleOAuthClient(credential: credential, use: .desktopLogin)
    let receiver = try LoopbackOAuthReceiver(redirectURI: options.redirectURI)
    let state = try randomURLSafeString(byteCount: 32)
    let codeVerifier = try randomURLSafeString(byteCount: 32)
    let authorizationURL = try buildAuthorizationURL(
      client: client,
      credential: credential,
      redirectURI: receiver.redirectURI,
      state: state,
      codeVerifier: codeVerifier
    )

    if options.openBrowser {
      try openBrowser(authorizationURL)
    } else {
      FileHandle.standardError.write(Data(manualAuthorizationMessage(for: authorizationURL).utf8))
    }
    let code = try receiver.waitForCode(expectedState: state, timeoutSeconds: Int32(options.timeoutSeconds))
    let tokenResponse = try exchangeAuthorizationCode(
      client: client,
      code: code,
      codeVerifier: codeVerifier,
      redirectURI: receiver.redirectURI
    )
    let tokenStore = buildTokenStore(credential: credential, tokenResponse: tokenResponse)
    try writeGoogleCalendarOAuthTokenStore(
      tokenStore,
      to: credential.tokenStorePath,
      errorMessage: "Failed to write Google Calendar OAuth token store",
      exitCode: .authenticationBootstrapError
    )

    return [
      "credentialId": credential.id,
      "provider": credential.provider.rawValue,
      "state": CalendarAuthState.ready.rawValue,
      "tokenStorePath": credential.tokenStorePath,
      "redirectUri": receiver.redirectURI,
      "emailAddress": tokenStore.emailAddress as Any? ?? NSNull(),
      "expiresAt": tokenStore.expiresAt as Any? ?? NSNull(),
      "hasRefreshToken": tokenStore.refreshToken?.isEmpty == false
    ].merging(calendarTokenSourceDetails(credential)) { current, _ in current }
  }
}

struct GoogleCalendarLoopbackRedirectURI {
  let host: String
  let port: UInt16
  let path: String

  init(_ redirectURI: String) throws {
    guard let components = URLComponents(string: redirectURI),
          components.scheme == "http",
          let host = components.host,
          let port = components.port,
          port > 0,
          port <= Int(UInt16.max) else {
      throw authError("OAuth redirect URI must be an http:// loopback URL with an explicit port")
    }
    let normalizedHost = host.lowercased() == "localhost" ? "127.0.0.1" : host.lowercased()
    guard normalizedHost == "127.0.0.1" else {
      throw authError("OAuth redirect URI must use localhost or 127.0.0.1")
    }
    self.host = normalizedHost
    self.port = UInt16(port)
    self.path = components.path.isEmpty ? "/" : components.path
  }
}

private struct GoogleCalendarOAuthTokenResponse {
  let accessToken: String
  let refreshToken: String?
  let tokenType: String?
  let scope: String?
  let expiresIn: Int?
}

final class LoopbackOAuthReceiver: @unchecked Sendable {
  let redirectURI: String
  private let callbackPath: String
  private let socketFD: Int32

  init(redirectURI configuredRedirectURI: String?) throws {
    let fd = socket(AF_INET, SOCK_STREAM, 0)
    guard fd >= 0 else {
      throw authError("Failed to create OAuth callback socket")
    }

    var reuse: Int32 = 1
    guard setsockopt(fd, SOL_SOCKET, SO_REUSEADDR, &reuse, socklen_t(MemoryLayout<Int32>.size)) == 0 else {
      close(fd)
      throw authError("Failed to configure OAuth callback socket")
    }

    let configuredRedirect = try configuredRedirectURI.map { try GoogleCalendarLoopbackRedirectURI($0) }
    var address = sockaddr_in()
    address.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
    address.sin_family = sa_family_t(AF_INET)
    address.sin_port = in_port_t(configuredRedirect?.port ?? 0).bigEndian
    address.sin_addr = in_addr(s_addr: inet_addr("127.0.0.1"))

    let bindResult = withUnsafePointer(to: &address) { pointer in
      pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { socketAddress in
        Darwin.bind(fd, socketAddress, socklen_t(MemoryLayout<sockaddr_in>.size))
      }
    }
    guard bindResult == 0 else {
      close(fd)
      throw authError("Failed to bind OAuth callback socket")
    }
    guard listen(fd, 1) == 0 else {
      close(fd)
      throw authError("Failed to listen for OAuth callback")
    }

    var boundAddress = sockaddr_in()
    var length = socklen_t(MemoryLayout<sockaddr_in>.size)
    let nameResult = withUnsafeMutablePointer(to: &boundAddress) { pointer in
      pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { socketAddress in
        getsockname(fd, socketAddress, &length)
      }
    }
    guard nameResult == 0 else {
      close(fd)
      throw authError("Failed to resolve OAuth callback port")
    }
    socketFD = fd
    let path = configuredRedirect?.path ?? "/oauth2callback"
    callbackPath = path
    redirectURI = "http://127.0.0.1:\(UInt16(bigEndian: boundAddress.sin_port))\(path)"
  }

  deinit {
    close(socketFD)
  }

  func waitForCode(expectedState: String, timeoutSeconds: Int32) throws -> String {
    let deadline = Date().addingTimeInterval(TimeInterval(timeoutSeconds))
    while true {
      let remainingMilliseconds = Int(deadline.timeIntervalSinceNow * 1_000)
      guard remainingMilliseconds > 0 else {
        throw authError("Timed out waiting for Google Calendar OAuth callback")
      }

      var pollSet = [pollfd(fd: socketFD, events: Int16(POLLIN), revents: 0)]
      let pollResult = Darwin.poll(&pollSet, 1, Int32(remainingMilliseconds))
      guard pollResult > 0 else {
        throw authError("Timed out waiting for Google Calendar OAuth callback")
      }

      let connection = accept(socketFD, nil, nil)
      guard connection >= 0 else {
        throw authError("Failed to accept Google Calendar OAuth callback")
      }
      defer {
        close(connection)
      }

      var buffer = [UInt8](repeating: 0, count: 8_192)
      let count = Darwin.read(connection, &buffer, buffer.count)
      guard count > 0,
            let request = String(bytes: buffer.prefix(Int(count)), encoding: .utf8) else {
        try writeHTTPResponse(
          connection,
          status: "400 Bad Request",
          body: "Google Calendar authentication failed. Return to the terminal for details.\n"
        )
        continue
      }

      do {
        let code = try parseCallbackCode(request: request, expectedState: expectedState, expectedPath: callbackPath)
        try writeHTTPResponse(
          connection,
          status: "200 OK",
          body: "Google Calendar authentication completed. You can close this window.\n"
        )
        return code
      } catch {
        try writeHTTPResponse(
          connection,
          status: "400 Bad Request",
          body: "Google Calendar authentication failed. Return to the terminal for details.\n"
        )
      }
    }
  }
}

private func buildAuthorizationURL(
  client: GoogleOAuthClient,
  credential: CalendarCredentialConfig,
  redirectURI: String,
  state: String,
  codeVerifier: String
) throws -> URL {
  guard let authURI = nonBlank(client.authURI),
        var components = URLComponents(string: authURI) else {
    throw authError("OAuth client auth_uri is invalid")
  }
  components.queryItems = [
    URLQueryItem(name: "client_id", value: client.clientId),
    URLQueryItem(name: "redirect_uri", value: redirectURI),
    URLQueryItem(name: "response_type", value: "code"),
    URLQueryItem(name: "scope", value: calendarScopes(accessMode: credential.accessMode).joined(separator: " ")),
    URLQueryItem(name: "access_type", value: "offline"),
    URLQueryItem(name: "prompt", value: "consent"),
    URLQueryItem(name: "state", value: state),
    URLQueryItem(name: "code_challenge", value: codeChallenge(for: codeVerifier)),
    URLQueryItem(name: "code_challenge_method", value: "S256")
  ]
  guard let url = components.url else {
    throw authError("Failed to construct Google Calendar OAuth authorization URL")
  }
  return url
}

func buildGoogleCalendarAuthorizationURLForTesting(
  client: GoogleOAuthClient,
  credential: CalendarCredentialConfig,
  redirectURI: String,
  state: String,
  codeVerifier: String
) throws -> URL {
  try buildAuthorizationURL(
    client: client,
    credential: credential,
    redirectURI: redirectURI,
    state: state,
    codeVerifier: codeVerifier
  )
}

private func manualAuthorizationMessage(for url: URL) -> String {
  "Open this Google Calendar OAuth authorization URL to continue: \(url.absoluteString)\n"
}

private func openBrowser(_ url: URL) throws {
  let process = Process()
  process.executableURL = URL(fileURLWithPath: "/usr/bin/open")
  process.arguments = [url.absoluteString]
  do {
    try process.run()
    process.waitUntilExit()
  } catch {
    throw GoogleCalendarGatewayError(
      "Failed to open browser for Google Calendar OAuth",
      code: .authRequired,
      exitCode: .authenticationBootstrapError,
      details: ["cause": error.localizedDescription]
    )
  }
  guard process.terminationStatus == 0 else {
    throw GoogleCalendarGatewayError(
      "Browser launch for Google Calendar OAuth failed",
      code: .authRequired,
      exitCode: .authenticationBootstrapError,
      details: ["status": String(process.terminationStatus)]
    )
  }
}

private func parseCallbackCode(request: String, expectedState: String, expectedPath: String) throws -> String {
  guard let firstLine = request.components(separatedBy: "\r\n").first else {
    throw authError("OAuth callback request was empty")
  }
  let parts = firstLine.split(separator: " ")
  guard parts.count >= 2,
        parts[0] == "GET",
        let components = URLComponents(string: "http://127.0.0.1\(parts[1])") else {
    throw authError("OAuth callback request was malformed")
  }
  guard components.path == expectedPath else {
    throw authError("OAuth callback path did not match the configured redirect URI")
  }
  var query: [String: String] = [:]
  for item in components.queryItems ?? [] {
    query[item.name] = item.value ?? ""
  }
  if let error = query["error"] {
    throw GoogleCalendarGatewayError(
      "Google Calendar OAuth authorization failed",
      code: .authRequired,
      exitCode: .authenticationBootstrapError,
      details: ["oauthError": error]
    )
  }
  guard query["state"] == expectedState else {
    throw authError("Google Calendar OAuth callback state did not match")
  }
  guard let code = nonBlank(query["code"]) else {
    throw authError("Google Calendar OAuth callback did not include an authorization code")
  }
  return code
}

private func exchangeAuthorizationCode(
  client: GoogleOAuthClient,
  code: String,
  codeVerifier: String,
  redirectURI: String
) throws -> GoogleCalendarOAuthTokenResponse {
  guard let tokenURI = nonBlank(client.tokenURI),
        let tokenURL = URL(string: tokenURI) else {
    throw authError("OAuth client token_uri is invalid")
  }
  var fields: [(String, String)] = [
    ("client_id", client.clientId),
    ("code", code),
    ("code_verifier", codeVerifier),
    ("grant_type", "authorization_code"),
    ("redirect_uri", redirectURI)
  ]
  if let clientSecret = nonBlank(client.clientSecret) {
    fields.append(("client_secret", clientSecret))
  }

  var request = URLRequest(url: tokenURL)
  request.httpMethod = "POST"
  request.timeoutInterval = 30
  request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
  request.httpBody = formURLEncoded(fields).data(using: .utf8)

  let response = try performGoogleCalendarHTTPRequest(request, context: "Google Calendar OAuth token exchange failed")
  guard let object = try JSONSerialization.jsonObject(with: response.data) as? [String: Any] else {
    throw authError("Google Calendar OAuth token response was not a JSON object")
  }
  guard let accessToken = nonBlank(object["access_token"] as? String) else {
    throw GoogleCalendarGatewayError(
      "Google Calendar OAuth token response did not include an access token",
      code: .authRequired,
      exitCode: .authenticationBootstrapError
    )
  }
  return GoogleCalendarOAuthTokenResponse(
    accessToken: accessToken,
    refreshToken: nonBlank(object["refresh_token"] as? String),
    tokenType: nonBlank(object["token_type"] as? String),
    scope: nonBlank(object["scope"] as? String),
    expiresIn: intValue(object["expires_in"])
  )
}

private func buildTokenStore(
  credential: CalendarCredentialConfig,
  tokenResponse: GoogleCalendarOAuthTokenResponse
) -> CalendarOAuthTokenStore {
  let expiresAt = tokenResponse.expiresIn.map {
    ISO8601DateFormatter().string(from: Date().addingTimeInterval(TimeInterval($0)))
  }
  return CalendarOAuthTokenStore(
    accessMode: credential.accessMode,
    accessToken: tokenResponse.accessToken,
    refreshToken: tokenResponse.refreshToken,
    tokenType: tokenResponse.tokenType,
    scope: tokenResponse.scope,
    expiresAt: expiresAt,
    emailAddress: nil
  )
}

private func randomURLSafeString(byteCount: Int) throws -> String {
  var bytes = [UInt8](repeating: 0, count: byteCount)
  let status = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
  guard status == errSecSuccess else {
    throw authError("Failed to generate secure OAuth random value")
  }
  return base64URLString(Data(bytes))
}

private func codeChallenge(for verifier: String) -> String {
  base64URLString(Data(SHA256.hash(data: Data(verifier.utf8))))
}

private func writeHTTPResponse(_ connection: Int32, status: String, body: String) throws {
  let response = """
  HTTP/1.1 \(status)\r
  Content-Type: text/plain; charset=utf-8\r
  Connection: close\r
  Content-Length: \(body.utf8.count)\r
  \r
  \(body)
  """
  _ = response.withCString { pointer in
    Darwin.write(connection, pointer, strlen(pointer))
  }
}

private func authError(_ message: String) -> GoogleCalendarGatewayError {
  GoogleCalendarGatewayError(message, code: .authRequired, exitCode: .authenticationBootstrapError)
}
