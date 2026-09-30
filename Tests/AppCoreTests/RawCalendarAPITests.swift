import Testing
@testable import GoogleCalendarGatewayCore

@Test func graphQLRawCalendarAPIReadsOfficialResourcePaths() throws {
  let result = try executeCalendarGraphQL(
    service: GoogleCalendarGatewayService(config: testConfig(), provider: FakeCalendarProvider()),
    query: """
    {
      calendarAPI(
        credentialId: "google-personal",
        method: "GET",
        path: "/colors",
        query: ["maxResults=10"]
      ) {
        status
        body { method path query { maxResults } access }
      }
    }
    """
  )

  #expect(result.exitCode == .success)
  let data = try #require(result.body["data"] as? [String: Any])
  let payload = try #require(data["calendarAPI"] as? [String: Any])
  let body = try #require(payload["body"] as? [String: Any])
  let query = try #require(body["query"] as? [String: Any])
  #expect(payload["status"] as? Int == 200)
  #expect(body["method"] as? String == "GET")
  #expect(body["path"] as? String == "/colors")
  #expect(query["maxResults"] as? String == "10")
  #expect(body["access"] as? String == "auto")
}

@Test func graphQLRawCalendarAPISupportsWatchNotificationBodies() throws {
  let result = try executeCalendarGraphQL(
    service: GoogleCalendarGatewayService(config: testConfig(accessMode: .readWrite), provider: FakeCalendarProvider()),
    query: """
    mutation {
      calendarAPI(
        credentialId: "google-personal",
        method: "POST",
        path: "/calendars/primary/events/watch",
        body: "{\\"id\\":\\"channel-1\\",\\"type\\":\\"web_hook\\",\\"address\\":\\"https://example.com/calendar-hook\\"}"
      ) {
        body { method path body { id type address } }
      }
    }
    """
  )

  #expect(result.exitCode == .success)
  let data = try #require(result.body["data"] as? [String: Any])
  let payload = try #require(data["calendarAPI"] as? [String: Any])
  let body = try #require(payload["body"] as? [String: Any])
  let requestBody = try #require(body["body"] as? [String: Any])
  #expect(body["method"] as? String == "POST")
  #expect(body["path"] as? String == "/calendars/primary/events/watch")
  #expect(requestBody["id"] as? String == "channel-1")
  #expect(requestBody["type"] as? String == "web_hook")
}

@Test func graphQLRawCalendarAPIRejectsUnsafePaths() throws {
  let result = try executeCalendarGraphQL(
    service: GoogleCalendarGatewayService(config: testConfig(), provider: FakeCalendarProvider()),
    query: """
    { calendarAPI(credentialId: "google-personal", method: "GET", path: "https://example.com/colors") { status } }
    """
  )

  #expect(result.exitCode == .graphqlExecutionError)
  #expect(result.body["errors"] != nil)
}

@Test func rawCalendarAPIWriteAccessFailsBeforeProviderForReadOnlyCredentials() throws {
  let result = try executeCalendarGraphQL(
    service: GoogleCalendarGatewayService(config: testConfig(), provider: FailingWriteProvider()),
    query: """
    mutation {
      calendarAPI(
        credentialId: "google-personal",
        method: "DELETE",
        path: "/channels/stop",
        access: "read",
        body: "{\\"id\\":\\"channel-1\\",\\"resourceId\\":\\"resource-1\\"}"
      ) { status }
    }
    """
  )

  #expect(result.exitCode == .graphqlExecutionError)
  let errors = try #require(result.body["errors"] as? [[String: Any]])
  #expect(errors.first?["message"] as? String == "Google Calendar write operations require access_mode = \"read_write\" or \"full\"")
}

@Test func publicGraphQLResolverCanBeUsedAsLibrary() throws {
  let resolver = GoogleCalendarGatewayGraphQLResolver(
    service: GoogleCalendarGatewayService(config: testConfig(), provider: FakeCalendarProvider())
  )

  let result = try resolver.execute(query: "{ calendars { id provider } }")

  #expect(result.exitCode == .success)
  let data = try #require(result.body["data"] as? [String: Any])
  let calendars = try #require(data["calendars"] as? [[String: Any]])
  #expect(calendars.first?["id"] as? String == "personal")
}
