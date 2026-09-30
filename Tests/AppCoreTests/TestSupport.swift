import Foundation
import Darwin
import Testing
@testable import GoogleCalendarGatewayCore

struct FakeCalendarProvider: CalendarEventProvider {
  func listCalendars(credential: CalendarCredentialConfig) throws -> [ProviderCalendarInfo] {
    [
      ProviderCalendarInfo(
        id: "primary",
        summary: "Personal",
        timeZone: "UTC",
        accessRole: "owner",
        isPrimary: true,
        isSelected: true,
        providerMetadata: ["fake": ["credentialId": credential.id]]
      ),
      ProviderCalendarInfo(
        id: "team@example.com",
        summary: "Team",
        timeZone: "UTC",
        accessRole: "writer",
        isSelected: true,
        providerMetadata: ["fake": ["credentialId": credential.id]]
      )
    ]
  }

  func listEvents(
    account: CalendarAccountConfig,
    credential: CalendarCredentialConfig,
    search: CalendarEventSearch
  ) throws -> CalendarEventConnection {
    let calendarId = search.calendarId ?? account.defaultCalendarId
    if let pageToken = search.pageToken {
      #expect(pageToken == "next-page")
    }
    let fakeMetadata: [String: Any] = [
      "credentialId": credential.id,
      "updatedMin": search.updatedMin as Any? ?? NSNull(),
      "syncToken": search.syncToken as Any? ?? NSNull(),
      "showDeleted": search.showDeleted as Any? ?? NSNull(),
      "singleEvents": search.singleEvents,
      "orderBy": search.orderBy?.rawValue as Any? ?? NSNull()
    ]
    return CalendarEventConnection(
      accountId: account.id,
      calendarId: calendarId,
      events: [
        CalendarEvent(
          id: "event-1",
          accountId: account.id,
          calendarId: calendarId,
          summary: "Planning",
          start: CalendarEventDateTime(dateTime: "2026-07-01T09:00:00Z", timeZone: "UTC"),
          end: CalendarEventDateTime(dateTime: "2026-07-01T09:30:00Z", timeZone: "UTC"),
          attendees: [CalendarEventParticipant(email: "guest@example.com", responseStatus: "accepted")],
          providerMetadata: ["fake": fakeMetadata]
        )
      ],
      nextPageToken: "next-page",
      nextSyncToken: "next-sync"
    )
  }

  func getEvent(
    account: CalendarAccountConfig,
    credential: CalendarCredentialConfig,
    calendarId: String,
    eventId: String
  ) throws -> CalendarEvent {
    CalendarEvent(
      id: eventId,
      accountId: account.id,
      calendarId: calendarId,
      providerMetadata: ["fake": ["credentialId": credential.id]]
    )
  }

  func queryFreeBusy(
    account: CalendarAccountConfig,
    credential: CalendarCredentialConfig,
    query: CalendarFreeBusyQuery
  ) throws -> CalendarFreeBusyResponse {
    CalendarFreeBusyResponse(
      accountId: account.id,
      timeMin: query.timeMin,
      timeMax: query.timeMax,
      calendars: query.calendarIds.map { calendarId in
        CalendarFreeBusyCalendar(
          id: calendarId,
          busy: [
            CalendarFreeBusyInterval(start: "2026-07-01T09:00:00Z", end: "2026-07-01T09:30:00Z")
          ],
          providerMetadata: ["fake": ["credentialId": credential.id]]
        )
      },
      providerMetadata: ["fake": ["credentialId": credential.id]]
    )
  }

  func createEvent(
    account: CalendarAccountConfig,
    credential: CalendarCredentialConfig,
    input: CalendarEventInput
  ) throws -> CalendarEvent {
    CalendarEvent(
      id: "created-event",
      accountId: account.id,
      calendarId: input.calendarId ?? account.defaultCalendarId,
      summary: input.summary,
      colorId: input.colorId,
      visibility: input.visibility,
      transparency: input.transparency,
      recurrenceRules: input.recurrenceRules,
      reminders: CalendarEventReminders(
        useDefault: input.reminderUseDefault,
        overrides: input.reminderOverrides
      ),
      conferenceData: input.createConference ? CalendarConferenceData(
        conferenceId: "meet-123",
        solutionType: "hangoutsMeet",
        solutionName: "Google Meet",
        createRequestStatus: "success",
        entryPoints: [CalendarConferenceEntryPoint(entryPointType: "video", uri: "https://meet.google.com/aaa-bbbb-ccc")]
      ) : nil,
      providerMetadata: ["fake": ["credentialId": credential.id]]
    )
  }

  func updateEvent(
    account: CalendarAccountConfig,
    credential: CalendarCredentialConfig,
    input: CalendarEventInput
  ) throws -> CalendarEvent {
    CalendarEvent(
      id: input.eventId,
      accountId: account.id,
      calendarId: input.calendarId ?? account.defaultCalendarId,
      summary: input.summary,
      colorId: input.colorId,
      visibility: input.visibility,
      transparency: input.transparency,
      recurrenceRules: input.recurrenceRules,
      reminders: CalendarEventReminders(
        useDefault: input.reminderUseDefault,
        overrides: input.reminderOverrides
      ),
      conferenceData: input.createConference ? CalendarConferenceData(
        conferenceId: "meet-123",
        solutionType: "hangoutsMeet",
        solutionName: "Google Meet",
        createRequestStatus: "success",
        entryPoints: [CalendarConferenceEntryPoint(entryPointType: "video", uri: "https://meet.google.com/aaa-bbbb-ccc")]
      ) : nil,
      providerMetadata: ["fake": ["credentialId": credential.id]]
    )
  }

  func deleteEvent(
    account: CalendarAccountConfig,
    credential: CalendarCredentialConfig,
    calendarId: String,
    eventId: String,
    sendUpdates: String?
  ) throws -> [String: Any] {
    [
      "accountId": account.id,
      "credentialId": credential.id,
      "calendarId": calendarId,
      "eventId": eventId,
      "sendUpdates": sendUpdates as Any? ?? NSNull(),
      "deleted": true
    ]
  }

  func executeCalendarAPI(
    credential: CalendarCredentialConfig,
    request: CalendarRawAPIRequest
  ) throws -> [String: Any] {
    [
      "status": 200,
      "body": [
        "credentialId": credential.id,
        "method": request.method.rawValue,
        "path": request.path,
        "query": Dictionary(uniqueKeysWithValues: request.queryItems),
        "body": request.bodyJSON.flatMap { try? parseRawCalendarAPIJSONBody($0) } as Any? ?? NSNull(),
        "access": request.access.rawValue
      ]
    ]
  }
}

struct FailingWriteProvider: CalendarEventProvider {
  func listCalendars(credential: CalendarCredentialConfig) throws -> [ProviderCalendarInfo] {
    []
  }

  func listEvents(
    account: CalendarAccountConfig,
    credential: CalendarCredentialConfig,
    search: CalendarEventSearch
  ) throws -> CalendarEventConnection {
    CalendarEventConnection(accountId: account.id, calendarId: account.defaultCalendarId, events: [])
  }

  func getEvent(
    account: CalendarAccountConfig,
    credential: CalendarCredentialConfig,
    calendarId: String,
    eventId: String
  ) throws -> CalendarEvent {
    CalendarEvent(id: eventId, accountId: account.id, calendarId: calendarId)
  }

  func queryFreeBusy(
    account: CalendarAccountConfig,
    credential: CalendarCredentialConfig,
    query: CalendarFreeBusyQuery
  ) throws -> CalendarFreeBusyResponse {
    CalendarFreeBusyResponse(
      accountId: account.id,
      timeMin: query.timeMin,
      timeMax: query.timeMax,
      calendars: []
    )
  }

  func createEvent(
    account: CalendarAccountConfig,
    credential: CalendarCredentialConfig,
    input: CalendarEventInput
  ) throws -> CalendarEvent {
    Issue.record("Provider write should not be called")
    return CalendarEvent(accountId: account.id, calendarId: account.defaultCalendarId)
  }

  func updateEvent(
    account: CalendarAccountConfig,
    credential: CalendarCredentialConfig,
    input: CalendarEventInput
  ) throws -> CalendarEvent {
    Issue.record("Provider write should not be called")
    return CalendarEvent(accountId: account.id, calendarId: account.defaultCalendarId)
  }

  func deleteEvent(
    account: CalendarAccountConfig,
    credential: CalendarCredentialConfig,
    calendarId: String,
    eventId: String,
    sendUpdates: String?
  ) throws -> [String: Any] {
    Issue.record("Provider write should not be called")
    return [:]
  }

  func executeCalendarAPI(
    credential: CalendarCredentialConfig,
    request: CalendarRawAPIRequest
  ) throws -> [String: Any] {
    Issue.record("Provider raw API write should not be called")
    return [:]
  }
}

struct ThrowingReadProvider: CalendarEventProvider {
  func listCalendars(credential: CalendarCredentialConfig) throws -> [ProviderCalendarInfo] {
    throw rateLimitedError()
  }

  func listEvents(
    account: CalendarAccountConfig,
    credential: CalendarCredentialConfig,
    search: CalendarEventSearch
  ) throws -> CalendarEventConnection {
    throw rateLimitedError()
  }

  func getEvent(
    account: CalendarAccountConfig,
    credential: CalendarCredentialConfig,
    calendarId: String,
    eventId: String
  ) throws -> CalendarEvent {
    throw rateLimitedError()
  }

  func queryFreeBusy(
    account: CalendarAccountConfig,
    credential: CalendarCredentialConfig,
    query: CalendarFreeBusyQuery
  ) throws -> CalendarFreeBusyResponse {
    throw rateLimitedError()
  }

  func createEvent(
    account: CalendarAccountConfig,
    credential: CalendarCredentialConfig,
    input: CalendarEventInput
  ) throws -> CalendarEvent {
    CalendarEvent(id: "created-event", accountId: account.id, calendarId: input.calendarId ?? account.defaultCalendarId)
  }

  func updateEvent(
    account: CalendarAccountConfig,
    credential: CalendarCredentialConfig,
    input: CalendarEventInput
  ) throws -> CalendarEvent {
    CalendarEvent(id: input.eventId, accountId: account.id, calendarId: input.calendarId ?? account.defaultCalendarId)
  }

  func deleteEvent(
    account: CalendarAccountConfig,
    credential: CalendarCredentialConfig,
    calendarId: String,
    eventId: String,
    sendUpdates: String?
  ) throws -> [String: Any] {
    ["deleted": true]
  }

  func executeCalendarAPI(
    credential: CalendarCredentialConfig,
    request: CalendarRawAPIRequest
  ) throws -> [String: Any] {
    throw rateLimitedError()
  }

  private func rateLimitedError() -> GoogleCalendarGatewayError {
    GoogleCalendarGatewayError(
      "Google Calendar rate limit exceeded",
      code: .providerRateLimited,
      exitCode: .providerApiError
    )
  }
}

struct TestConfigPaths {
  let root: String
  let config: String
  let oauthClient: String
  let token: String
  let cache: String
}

func temporaryConfigPaths() -> TestConfigPaths {
  let root = URL(fileURLWithPath: NSTemporaryDirectory())
    .appendingPathComponent("google-calendar-gateway-tests-\(UUID().uuidString)", isDirectory: true)
  return TestConfigPaths(
    root: root.path,
    config: root.appendingPathComponent("config.toml").path,
    oauthClient: root.appendingPathComponent("google-client.json").path,
    token: root.appendingPathComponent("token.json").path,
    cache: root.appendingPathComponent("cache", isDirectory: true).path
  )
}

func writeConfig(paths: TestConfigPaths, accessMode: String = "read") throws {
  try FileManager.default.createDirectory(atPath: paths.root, withIntermediateDirectories: true)
  try """
  {"installed":{"client_id":"client","auth_uri":"https://accounts.example.test/auth","token_uri":"https://tokens.example.test/token"}}
  """.write(toFile: paths.oauthClient, atomically: true, encoding: .utf8)
  try """
  {"accessMode":"read","accessToken":"test-token","refreshToken":"refresh","expiresAt":"2099-01-01T00:00:00Z","scope":"https://www.googleapis.com/auth/calendar.events.readonly https://www.googleapis.com/auth/calendar.calendarlist.readonly https://www.googleapis.com/auth/calendar.freebusy"}
  """.write(toFile: paths.token, atomically: true, encoding: .utf8)
  try """
  [storage]
  cache_dir = "\(paths.cache)"

  [[credentials]]
  id = "google-personal"
  provider = "google"
  access_mode = "\(accessMode)"
  oauth_client_secret_path = "\(paths.oauthClient)"
  token_store_path = "\(paths.token)"

  [[calendars]]
  id = "personal"
  display_name = "Personal"
  provider = "google"
  credential_id = "google-personal"
  calendar_id = "primary"
  default_time_zone = "UTC"
  """.write(toFile: paths.config, atomically: true, encoding: .utf8)
}

func env(paths: TestConfigPaths) -> [String: String] {
  [
    "GOOGLE_CALENDAR_GATEWAY_CREDENTIAL_GOOGLE_PERSONAL_OAUTH_CLIENT_SECRET_PATH": paths.oauthClient,
    "GOOGLE_CALENDAR_GATEWAY_CREDENTIAL_GOOGLE_PERSONAL_TOKEN_STORE_PATH": paths.token
  ]
}

func requireGoogleCalendarGatewayError(_ operation: () throws -> Void) throws -> GoogleCalendarGatewayError {
  do {
    try operation()
  } catch let error as GoogleCalendarGatewayError {
    return error
  } catch {
    Issue.record("Unexpected error: \(error)")
  }
  Issue.record("Expected GoogleCalendarGatewayError")
  throw GoogleCalendarGatewayError("Expected test error", code: .invalidArgument, exitCode: .generalError)
}

final class OneShotHTTPServer: @unchecked Sendable {
  let url: String

  private let socketFD: Int32
  private let responseBody: String
  private let finished = DispatchSemaphore(value: 0)
  private let lock = NSLock()
  private var result: Result<String, Error>?
  private var closed = false

  init(path: String = "/token", responseBody: String) throws {
    let fd = socket(AF_INET, SOCK_STREAM, 0)
    guard fd >= 0 else {
      throw GoogleCalendarGatewayError("Failed to create test HTTP socket", code: .providerApiError, exitCode: .providerApiError)
    }

    var reuse: Int32 = 1
    guard setsockopt(fd, SOL_SOCKET, SO_REUSEADDR, &reuse, socklen_t(MemoryLayout<Int32>.size)) == 0 else {
      close(fd)
      throw GoogleCalendarGatewayError("Failed to configure test HTTP socket", code: .providerApiError, exitCode: .providerApiError)
    }

    var address = sockaddr_in()
    address.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
    address.sin_family = sa_family_t(AF_INET)
    address.sin_port = in_port_t(0).bigEndian
    address.sin_addr = in_addr(s_addr: inet_addr("127.0.0.1"))

    let bindResult = withUnsafePointer(to: &address) { pointer in
      pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { socketAddress in
        Darwin.bind(fd, socketAddress, socklen_t(MemoryLayout<sockaddr_in>.size))
      }
    }
    guard bindResult == 0 else {
      close(fd)
      throw GoogleCalendarGatewayError("Failed to bind test HTTP socket", code: .providerApiError, exitCode: .providerApiError)
    }
    guard listen(fd, 1) == 0 else {
      close(fd)
      throw GoogleCalendarGatewayError("Failed to listen on test HTTP socket", code: .providerApiError, exitCode: .providerApiError)
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
      throw GoogleCalendarGatewayError("Failed to resolve test HTTP socket port", code: .providerApiError, exitCode: .providerApiError)
    }

    socketFD = fd
    self.responseBody = responseBody
    url = "http://127.0.0.1:\(UInt16(bigEndian: boundAddress.sin_port))\(path)"

    DispatchQueue.global().async {
      self.serve()
    }
  }

  deinit {
    closeSocket()
  }

  func waitForRequest(timeout: DispatchTime = .now() + 5) throws -> String {
    #expect(finished.wait(timeout: timeout) == .success)
    switch loadResult() {
    case .success(let request):
      return request
    case .failure(let error):
      throw error
    case nil:
      throw GoogleCalendarGatewayError("Test HTTP server did not capture a request", code: .providerApiError, exitCode: .providerApiError)
    }
  }

  private func serve() {
    let requestResult = Result {
      let connection = accept(socketFD, nil, nil)
      guard connection >= 0 else {
        throw GoogleCalendarGatewayError("Failed to accept test HTTP request", code: .providerApiError, exitCode: .providerApiError)
      }
      defer {
        close(connection)
        closeSocket()
      }

      let request = try readHTTPRequest(from: connection)
      try writeHTTPResponse(to: connection)
      return request
    }
    store(requestResult)
    finished.signal()
  }

  private func readHTTPRequest(from connection: Int32) throws -> String {
    var data = Data()
    var buffer = [UInt8](repeating: 0, count: 4_096)
    while true {
      let count = Darwin.read(connection, &buffer, buffer.count)
      guard count > 0 else {
        break
      }
      data.append(buffer, count: Int(count))
      if requestDataIsComplete(data) {
        break
      }
    }
    guard let request = String(data: data, encoding: .utf8), !request.isEmpty else {
      throw GoogleCalendarGatewayError("Test HTTP request was empty", code: .providerApiError, exitCode: .providerApiError)
    }
    return request
  }

  private func requestDataIsComplete(_ data: Data) -> Bool {
    guard let request = String(data: data, encoding: .utf8),
          let headerRange = request.range(of: "\r\n\r\n") else {
      return false
    }
    let header = String(request[..<headerRange.lowerBound])
    let bodyStart = request.distance(from: request.startIndex, to: headerRange.upperBound)
    let contentLength = header
      .components(separatedBy: "\r\n")
      .first { $0.lowercased().hasPrefix("content-length:") }?
      .split(separator: ":", maxSplits: 1)
      .last
      .flatMap { Int($0.trimmingCharacters(in: .whitespaces)) }
    return data.count >= bodyStart + (contentLength ?? 0)
  }

  private func writeHTTPResponse(to connection: Int32) throws {
    let response = """
    HTTP/1.1 200 OK\r
    Content-Type: application/json\r
    Connection: close\r
    Content-Length: \(responseBody.utf8.count)\r
    \r
    \(responseBody)
    """
    _ = response.withCString { pointer in
      Darwin.write(connection, pointer, strlen(pointer))
    }
  }

  private func store(_ result: Result<String, Error>) {
    lock.lock()
    self.result = result
    lock.unlock()
  }

  private func loadResult() -> Result<String, Error>? {
    lock.lock()
    defer {
      lock.unlock()
    }
    return result
  }

  private func closeSocket() {
    lock.lock()
    defer {
      lock.unlock()
    }
    guard !closed else {
      return
    }
    close(socketFD)
    closed = true
  }
}

func testCredential(
  oauthClientSecretJSON: String = "{}",
  tokenStoreJSON: String = "{}",
  accessMode: CalendarAccessMode = .read
) -> CalendarCredentialConfig {
  CalendarCredentialConfig(
    id: "google-personal",
    provider: .google,
    accessMode: accessMode,
    oauthClientSecretPath: "/tmp/google-client.json",
    oauthClientSecretJSON: oauthClientSecretJSON,
    tokenStorePath: "/tmp/token.json",
    tokenStoreJSON: tokenStoreJSON
  )
}

func testConfig(accessMode: CalendarAccessMode = .read) -> GoogleCalendarGatewayConfig {
  GoogleCalendarGatewayConfig(
    configPath: "/tmp/google-calendar-gateway-test.toml",
    storage: CalendarStorageConfig(cacheDir: "/tmp/google-calendar-gateway-cache"),
    credentials: [
      CalendarCredentialConfig(
        id: "google-personal",
        provider: .google,
        accessMode: accessMode,
        oauthClientSecretPath: "/tmp/google-client.json",
        oauthClientSecretJSON: "{}",
        tokenStorePath: "/tmp/token.json",
        tokenStoreJSON: "{}"
      )
    ],
    accounts: [
      CalendarAccountConfig(
        id: "personal",
        displayName: "Personal",
        provider: .google,
        emailAddress: "person@example.com",
        credentialId: "google-personal",
        calendarIds: ["primary"],
        defaultCalendarId: "primary",
        defaultTimeZone: "UTC"
      )
    ]
  )
}
