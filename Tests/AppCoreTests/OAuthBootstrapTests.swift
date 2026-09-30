import Foundation
import Testing
@testable import GoogleCalendarGatewayCore

@Test func loopbackRedirectAcceptsLocalhostAndCallbackPath() throws {
  let redirect = try GoogleCalendarLoopbackRedirectURI("http://localhost:8765/callback")

  #expect(redirect.host == "127.0.0.1")
  #expect(redirect.port == 8765)
  #expect(redirect.path == "/callback")
}

@Test func loopbackRedirectRejectsNonLocalHosts() throws {
  let error = try requireGoogleCalendarGatewayError {
    _ = try GoogleCalendarLoopbackRedirectURI("https://example.com/callback")
  }

  #expect(error.exitCode == .authenticationBootstrapError)
  #expect(error.message.contains("loopback URL"))
}

@Test func loopbackReceiverIgnoresStrayRequestsUntilExpectedCallback() throws {
  let receiver = try LoopbackOAuthReceiver(redirectURI: nil)
  let finished = DispatchSemaphore(value: 0)
  final class ResultBox: @unchecked Sendable {
    var result: Result<String, Error>?
  }
  let box = ResultBox()

  DispatchQueue.global().async {
    box.result = Result {
      try receiver.waitForCode(expectedState: "expected-state", timeoutSeconds: 5)
    }
    finished.signal()
  }

  try sendLoopbackRequest(to: receiver.redirectURI.replacingOccurrences(of: "/oauth2callback", with: "/favicon.ico"))
  try sendLoopbackRequest(to: "\(receiver.redirectURI)?code=good-code&state=expected-state")

  #expect(finished.wait(timeout: .now() + 5) == .success)
  let result = try #require(box.result)
  #expect(try result.get() == "good-code")
}

@Test func googleAuthorizationURLUsesFixedRedirectURIAndCalendarScopes() throws {
  let credential = testCredential(accessMode: .read)
  let client = GoogleOAuthClient(
    clientId: "client-id",
    clientSecret: "secret",
    authURI: "https://accounts.example.test/o/oauth2/auth",
    tokenURI: "https://tokens.example.test/token"
  )

  let url = try buildGoogleCalendarAuthorizationURLForTesting(
    client: client,
    credential: credential,
    redirectURI: "http://127.0.0.1:8765/callback",
    state: "state-value",
    codeVerifier: "verifier-value"
  )
  let components = try #require(URLComponents(url: url, resolvingAgainstBaseURL: false))
  let query = Dictionary(uniqueKeysWithValues: (components.queryItems ?? []).map { ($0.name, $0.value ?? "") })

  #expect(query["client_id"] == "client-id")
  #expect(query["redirect_uri"] == "http://127.0.0.1:8765/callback")
  #expect(query["state"] == "state-value")
  #expect(query["code_challenge_method"] == "S256")
  #expect(query["scope"]?.contains("https://www.googleapis.com/auth/calendar.events.readonly") == true)
  #expect(query["scope"]?.contains("https://www.googleapis.com/auth/calendar.calendarlist.readonly") == true)
  #expect(query["scope"]?.contains("https://www.googleapis.com/auth/calendar.freebusy") == true)
}

private func sendLoopbackRequest(to urlString: String) throws {
  let url = try #require(URL(string: urlString))
  let finished = DispatchSemaphore(value: 0)
  final class ResponseBox: @unchecked Sendable {
    var error: Error?
  }
  let box = ResponseBox()
  URLSession.shared.dataTask(with: url) { _, _, error in
    box.error = error
    finished.signal()
  }.resume()
  #expect(finished.wait(timeout: .now() + 5) == .success)
  if let error = box.error {
    throw error
  }
}
