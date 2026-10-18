import Foundation
import XCTest
@testable import GoogleCalendarGatewayCore

final class WriteRetryTests: XCTestCase {
  override func setUp() {
    super.setUp()
    WriteRetryURLProtocol.responses = []
    WriteRetryURLProtocol.count = 0
    URLProtocol.registerClass(WriteRetryURLProtocol.self)
  }

  override func tearDown() {
    URLProtocol.unregisterClass(WriteRetryURLProtocol.self)
    super.tearDown()
  }

  private func execute(
    policy: GoogleCalendarWriteRetryPolicy = .default,
    sleep: (TimeInterval) throws -> Void = { _ in }
  ) throws -> Int {
    var request = URLRequest(url: try XCTUnwrap(URL(string: "https://retry.invalid/write")))
    request.httpMethod = "POST"
    request.httpBody = Data("fixed mutation body".utf8)
    return try performGoogleCalendarHTTPRequest(request, context: "test", writeRetry: policy, sleep: sleep).response.statusCode
  }

  func testTOMLAndSuppliedEnvironmentReachSDKConfiguration() throws {
    let paths = temporaryConfigPaths()
    defer { try? FileManager.default.removeItem(atPath: paths.root) }
    try writeConfig(paths: paths)
    let configPath = paths.config
    let original = try String(contentsOfFile: configPath, encoding: .utf8)
    let source = original + "\n[write_retry]\ninitial_wait_seconds = 9\nmax_retries = 1\n"
    try source.write(toFile: configPath, atomically: true, encoding: .utf8)
    let config = try GoogleCalendarGatewayConfigLoader.loadConfig(configPath: configPath, environment: [:])
    XCTAssertEqual(config.writeRetry, try GoogleCalendarWriteRetryPolicy(initialWaitSeconds: 9, maxRetries: 1))
    let overridden = try GoogleCalendarGatewayConfigLoader.loadConfig(configPath: configPath,
      environment: ["GOOGLE_CALENDAR_GATEWAY_WRITE_RETRY_MAX_RETRIES": "0"])
    XCTAssertEqual(overridden.writeRetry.maxRetries, 0)
    XCTAssertEqual(overridden.writeRetry.initialWaitSeconds, 9)
  }

  func testMutationRedirectDelegateDeclinesReplay() throws {
    let url = try XCTUnwrap(URL(string: "https://retry.invalid/write"))
    let task = URLSession.shared.dataTask(with: url)
    let response = try XCTUnwrap(HTTPURLResponse(url: url, statusCode: 307, httpVersion: nil, headerFields: [:]))
    let done = expectation(description: "redirect decision")
    GoogleCalendarWriteRedirectBlocker().urlSession(URLSession.shared, task: task,
      willPerformHTTPRedirection: response, newRequest: URLRequest(url: url)) { redirected in
        XCTAssertNil(redirected)
        done.fulfill()
      }
    wait(for: [done], timeout: 1)
    task.cancel()
  }

  func testRetryAfterMinimumAndBoundedStop() throws {
    for (header, delay) in [("30", 30.0), ("unknown-private-value", 2.0)] {
      WriteRetryURLProtocol.responses = [.limited(header), .status(200)]
      WriteRetryURLProtocol.count = 0
      var delays: [Double] = []
      XCTAssertEqual(try execute(sleep: { delays.append($0) }), 200)
      XCTAssertEqual(delays, [delay])
      XCTAssertEqual(WriteRetryURLProtocol.count, 2)
    }
    WriteRetryURLProtocol.responses = [.limited("61"), .status(200)]
    WriteRetryURLProtocol.count = 0
    XCTAssertThrowsError(try execute(sleep: { _ in XCTFail("provider minimum exceeds cap") }))
    XCTAssertEqual(WriteRetryURLProtocol.count, 1)
    let now = Date(timeIntervalSince1970: 0)
    let url = try XCTUnwrap(URL(string: "https://retry.invalid/write"))
    let response = try XCTUnwrap(HTTPURLResponse(url: url, statusCode: 429, httpVersion: nil,
      headerFields: ["Retry-After": "Thu, 01 Jan 1970 00:00:30 GMT"]))
    XCTAssertEqual(googleCalendarWriteRetryDelay(policy: .default, retryIndex: 0, response: response, now: now), 30)
  }

  func testExpiredDeadlinePreventsInitialAttemptAndFurtherRetries() throws {
    WriteRetryURLProtocol.responses = [.status(200)]
    XCTAssertThrowsError(try GoogleCalendarWriteExecutionContext.withDeadline(Date.distantPast) { try execute() }) { error in
      XCTAssertEqual((error as? GoogleCalendarGatewayError)?.code, .cancelled)
    }
    XCTAssertEqual(WriteRetryURLProtocol.count, 0)
    WriteRetryURLProtocol.responses = [.status(429), .status(200)]
    let clock = WriteRetryClock()
    XCTAssertThrowsError(try GoogleCalendarWriteExecutionContext.$currentDate.withValue({ clock.read() }, operation: {
      try GoogleCalendarWriteExecutionContext.withDeadline(Date(timeIntervalSince1970: 1)) {
        try execute(sleep: { _ in clock.advance() })
      }
    }))
    XCTAssertEqual(WriteRetryURLProtocol.count, 1)
    XCTAssertThrowsError(try GoogleCalendarWriteExecutionContext.withDeadline(Date.distantPast) {
      try GoogleCalendarWriteExecutionContext.withDeadline(Date.distantFuture) { try execute() }
    })
    XCTAssertEqual(WriteRetryURLProtocol.count, 1)
  }

  func testDefaultAndBoundedPolicy() throws {
    XCTAssertEqual(GoogleCalendarWriteRetryPolicy.default.initialWaitSeconds, 2)
    XCTAssertEqual(GoogleCalendarWriteRetryPolicy.default.maxRetries, 3)
    let policy = try GoogleCalendarWriteRetryPolicy(initialWaitSeconds: 20, maxRetries: 5)
    XCTAssertEqual((0..<5).map { policy.delay(retryIndex: $0) }, [20, 40, 60, 60, 60])
    for wait in [-1, 0, 61, Int.max] { XCTAssertThrowsError(try GoogleCalendarWriteRetryPolicy(initialWaitSeconds: wait)) }
    for count in [-1, 6, Int.max] { XCTAssertThrowsError(try GoogleCalendarWriteRetryPolicy(maxRetries: count)) }
  }

  func testSuppliedEnvironmentOverridesTOMLWithoutAmbientValues() throws {
    let policy = try GoogleCalendarWriteRetryPolicy.load(record: ["initial_wait_seconds": 7, "max_retries": 1],
      environment: ["GOOGLE_CALENDAR_GATEWAY_WRITE_RETRY_INITIAL_WAIT_SECONDS": "3", "GOOGLE_CALENDAR_GATEWAY_WRITE_RETRY_MAX_RETRIES": "0"])
    XCTAssertEqual(policy, try GoogleCalendarWriteRetryPolicy(initialWaitSeconds: 3, maxRetries: 0))
    XCTAssertEqual(try GoogleCalendarWriteRetryPolicy.load(environment: [:]), .default)
    for value in ["-1", " 2", "2.5", "true", "999999999999", "secret"] {
      XCTAssertThrowsError(try GoogleCalendarWriteRetryPolicy.load(environment: ["GOOGLE_CALENDAR_GATEWAY_WRITE_RETRY_MAX_RETRIES": value]))
    }
    XCTAssertThrowsError(try GoogleCalendarWriteRetryPolicy.load(record: ["max_retries": true], environment: [:]))
    XCTAssertThrowsError(try GoogleCalendarWriteRetryPolicy.load(record: ["typo": 1], environment: [:]))
  }

  func testRejectedWriteRetriesExactlyConfiguredBudgetAndBackoff() throws {
    WriteRetryURLProtocol.responses = [.status(429), .status(429), .status(429), .status(200)]
    var delays: [Double] = []
    XCTAssertEqual(try execute(sleep: { delays.append($0) }), 200)
    XCTAssertEqual(delays, [2, 4, 8])
    XCTAssertEqual(WriteRetryURLProtocol.count, 4)
    WriteRetryURLProtocol.count = 0
    WriteRetryURLProtocol.responses = Array(repeating: .status(429), count: 5)
    delays = []
    XCTAssertThrowsError(try execute(sleep: { delays.append($0) }))
    XCTAssertEqual(delays, [2, 4, 8])
    XCTAssertEqual(WriteRetryURLProtocol.count, 4)
  }

  func testZeroDisablesRetriesAndPermanentFailuresDoNotSleep() throws {
    for status in [400, 401, 403, 404, 409, 412, 429] {
      WriteRetryURLProtocol.responses = [.status(status), .status(200)]
      WriteRetryURLProtocol.count = 0
      var delays: [Double] = []
      XCTAssertThrowsError(try execute(policy: .disabled, sleep: { delays.append($0) }))
      XCTAssertEqual(WriteRetryURLProtocol.count, 1)
      XCTAssertTrue(delays.isEmpty)
    }
    for status in [400, 401, 403, 404, 409, 412] {
      WriteRetryURLProtocol.responses = [.status(status), .status(200)]
      WriteRetryURLProtocol.count = 0
      XCTAssertThrowsError(try execute(sleep: { _ in XCTFail("permanent error slept") }))
      XCTAssertEqual(WriteRetryURLProtocol.count, 1)
    }
  }

  func testKnownQuota403RetriesButPermissionAndDailyQuotaDoNot() throws {
    for reason in ["rateLimitExceeded", "userRateLimitExceeded", "forbidden", "dailyLimitExceeded", "arbitrary-secret"] {
      WriteRetryURLProtocol.responses = [.quota(reason), .status(200)]
      WriteRetryURLProtocol.count = 0
      if ["rateLimitExceeded", "userRateLimitExceeded"].contains(reason) {
        XCTAssertEqual(try execute(), 200)
        XCTAssertEqual(WriteRetryURLProtocol.count, 2)
      } else {
        XCTAssertThrowsError(try execute())
        XCTAssertEqual(WriteRetryURLProtocol.count, 1)
      }
    }
    XCTAssertFalse(googleCalendarWriteWasRateLimited(status: 403, data: Data(repeating: 32, count: 65_537)))
    XCTAssertFalse(googleCalendarWriteWasRateLimited(status: 403, data: Data(#"{"error":{"errors":[{"reason":"rateLimitExceeded"},{"reason":"forbidden"}]}}"#.utf8)))
  }

  func testAmbiguousWriteNeverReplays() throws {
    for response in [WriteRetryURLProtocol.Response.status(500), .status(503), .failure(.timedOut), .failure(.networkConnectionLost)] {
      WriteRetryURLProtocol.responses = [response, .status(200)]
      WriteRetryURLProtocol.count = 0
      XCTAssertThrowsError(try execute(sleep: { _ in XCTFail("ambiguous write slept") })) { error in
        XCTAssertEqual((error as? GoogleCalendarGatewayError)?.code, .mutationOutcomeUnknown)
      }
      XCTAssertEqual(WriteRetryURLProtocol.count, 1)
    }
  }

  func testPreconnectionFailureCanRetryAndCancellationStopsBackoff() throws {
    for code in [URLError.cannotFindHost, .dnsLookupFailed, .cannotConnectToHost, .notConnectedToInternet] {
      WriteRetryURLProtocol.responses = [.failure(code), .status(200)]
      WriteRetryURLProtocol.count = 0
      XCTAssertEqual(try execute(), 200)
      XCTAssertEqual(WriteRetryURLProtocol.count, 2)
    }
    WriteRetryURLProtocol.responses = [.status(429), .status(200)]
    WriteRetryURLProtocol.count = 0
    XCTAssertThrowsError(try execute(sleep: { _ in throw CancellationError() })) { error in
      XCTAssertTrue(error is CancellationError)
    }
    XCTAssertEqual(WriteRetryURLProtocol.count, 1)
  }

  func testCalendarCreateDecodeFailureNeverRepeatsConfirmedWrite() throws {
    let credential = CalendarCredentialConfig(id: "fixture", provider: .google, accessMode: .readWrite,
      oauthClientSecretPath: "/unused", oauthClientSecretJSON: nil, tokenStorePath: "/unused",
      tokenStoreJSON: #"{"accessMode":"read_write","accessToken":"fixture","expiresAt":"2999-01-01T00:00:00Z","scope":"https://www.googleapis.com/auth/calendar.events https://www.googleapis.com/auth/calendar.calendarlist.readonly https://www.googleapis.com/auth/calendar.freebusy"}"#)
    let account = CalendarAccountConfig(id: "fixture", displayName: nil, provider: .google,
      emailAddress: "fixture@example.invalid", credentialId: "fixture", calendarIds: ["retry-fixture"],
      defaultCalendarId: "retry-fixture", defaultTimeZone: "UTC")
    let input = CalendarEventInput(accountId: "fixture", summary: "fixture",
      start: "2026-01-01T00:00:00Z", end: "2026-01-01T01:00:00Z")
    for response in [WriteRetryURLProtocol.Response.status(200), .emptyObject] {
      WriteRetryURLProtocol.count = 0
      WriteRetryURLProtocol.responses = [response, .status(200)]
      XCTAssertThrowsError(try GoogleCalendarLiveClient().createEvent(account: account, credential: credential, input: input)) { error in
        XCTAssertEqual((error as? GoogleCalendarGatewayError)?.code, .mutationOutcomeUnknown)
      }
      XCTAssertEqual(WriteRetryURLProtocol.count, 1)
    }
  }

  func testConfirmedSuccessDoesNotReplayEvenWithoutResponseBody() throws {
    WriteRetryURLProtocol.responses = [.status(204), .status(200)]
    XCTAssertEqual(try execute(), 204)
    XCTAssertEqual(WriteRetryURLProtocol.count, 1)
  }
}

private final class WriteRetryURLProtocol: URLProtocol {
  enum Response { case emptyObject, status(Int), quota(String), limited(String), failure(URLError.Code) }
  nonisolated(unsafe) static var responses: [Response] = []
  nonisolated(unsafe) static var count = 0
  override static func canInit(with request: URLRequest) -> Bool {
    request.url?.host == "retry.invalid" ||
      (request.url?.host == "www.googleapis.com" && request.url?.path.contains("/retry-fixture/") == true)
  }
  override static func canonicalRequest(for request: URLRequest) -> URLRequest { request }
  override func startLoading() {
    Self.count += 1
    let next = Self.responses.isEmpty ? .status(500) : Self.responses.removeFirst()
    let status: Int
    var data = Data()
    var headers: [String: String] = [:]
    switch next {
    case .failure(let code): client?.urlProtocol(self, didFailWithError: URLError(code)); return
    case .emptyObject: status = 200; data = Data("{}".utf8)
    case .status(let value): status = value
    case .limited(let minimum): status = 429; headers["Retry-After"] = minimum
    case .quota(let reason):
      status = 403
      data = (try? JSONSerialization.data(withJSONObject: ["error": ["errors": [["reason": reason]], "message": "private-provider-text"]])) ?? Data()
    }
    guard let url = request.url, let response = HTTPURLResponse(url: url, statusCode: status, httpVersion: nil, headerFields: headers) else {
      client?.urlProtocol(self, didFailWithError: URLError(.badURL)); return
    }
    client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
    client?.urlProtocol(self, didLoad: data)
    client?.urlProtocolDidFinishLoading(self)
  }
  override func stopLoading() {}
}

private final class WriteRetryClock: @unchecked Sendable {
  private let lock = NSLock()
  private var value = Date(timeIntervalSince1970: 0)
  func read() -> Date { lock.lock(); defer { lock.unlock() }; return value }
  func advance() { lock.lock(); defer { lock.unlock() }; value = value.addingTimeInterval(2) }
}
