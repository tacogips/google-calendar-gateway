import Foundation
import Testing
@testable import GoogleCalendarGatewayCore

@Test func helpUsesExecutableName() {
  let result = GoogleCalendarGatewayCLI().run(arguments: ["--help"], environment: [:])
  #expect(result.exitCode == GoogleCalendarGatewayExitCode.success.rawValue)
  #expect(result.stdout.contains("google-calendar-gateway"))
}

@Test func commandReportsVersion() {
  let result = GoogleCalendarGatewayCLI().run(arguments: ["--version"], environment: [:])
  #expect(result.exitCode == GoogleCalendarGatewayExitCode.success.rawValue)
  #expect(result.stdout.trimmingCharacters(in: .whitespacesAndNewlines) == Version.current)
}

@Test func commandRejectsUnknownFlags() {
  let root = GoogleCalendarGatewayCLI().run(arguments: ["--unknown"], environment: [:])
  let config = GoogleCalendarGatewayCLI().run(arguments: ["config", "validate", "--unknown"], environment: [:])
  let graphql = GoogleCalendarGatewayCLI().run(
    arguments: ["graphql", "--query", "{ calendars { id } }", "--unknown"],
    environment: [:]
  )

  #expect(root.exitCode == GoogleCalendarGatewayExitCode.invalidCliUsage.rawValue)
  #expect(config.exitCode == GoogleCalendarGatewayExitCode.invalidCliUsage.rawValue)
  #expect(graphql.exitCode == GoogleCalendarGatewayExitCode.invalidCliUsage.rawValue)
  #expect(root.stderr.contains("Unknown flag: --unknown"))
  #expect(config.stderr.contains("Unknown flag: --unknown"))
  #expect(graphql.stderr.contains("Unknown flag: --unknown"))
}

@Test func commandRejectsUnexpectedPositionalArguments() {
  let config = GoogleCalendarGatewayCLI().run(arguments: ["config", "validate", "extra"], environment: [:])
  let graphql = GoogleCalendarGatewayCLI().run(
    arguments: ["graphql", "extra", "--query", "{ calendars { id } }"],
    environment: [:]
  )
  let cache = GoogleCalendarGatewayCLI().run(arguments: ["cache", "prune", "extra", "--all"], environment: [:])

  #expect(config.exitCode == GoogleCalendarGatewayExitCode.invalidCliUsage.rawValue)
  #expect(graphql.exitCode == GoogleCalendarGatewayExitCode.invalidCliUsage.rawValue)
  #expect(cache.exitCode == GoogleCalendarGatewayExitCode.invalidCliUsage.rawValue)
  #expect(config.stderr.contains("Unexpected argument: extra"))
  #expect(graphql.stderr.contains("Unexpected argument: extra"))
  #expect(cache.stderr.contains("Unexpected argument: extra"))
}

@Test func serviceExposesTypedCalendarInfo() {
  let calendars = GoogleCalendarGatewayClient(config: testConfig()).calendars()

  #expect(calendars.count == 1)
  #expect(calendars[0].id == "personal")
  #expect(calendars[0].displayName == "Personal")
  #expect(calendars[0].provider == .google)
  #expect(calendars[0].capabilities.canRead)
}

@Test func serviceUsesInjectedProviderForCalendarDiscovery() throws {
  let calendars = try GoogleCalendarGatewayClient(
    config: testConfig(),
    provider: FakeCalendarProvider()
  ).listProviderCalendars(credentialId: "google-personal")

  #expect(calendars.count == 2)
  #expect(calendars[0].id == "primary")
  #expect(calendars[0].summary == "Personal")
  #expect(calendars[0].isPrimary)
  #expect(calendars[1].id == "team@example.com")
}

@Test func graphQLReturnsProviderCalendars() throws {
  let result = try executeCalendarGraphQL(
    service: GoogleCalendarGatewayService(config: testConfig(), provider: FakeCalendarProvider()),
    query: "{ providerCalendars(credentialId: \"google-personal\") { id summary isPrimary provider { fake { credentialId } } } }"
  )

  #expect(result.exitCode == .success)
  let data = try #require(result.body["data"] as? [String: Any])
  let calendars = try #require(data["providerCalendars"] as? [[String: Any]])
  let primary = try #require(calendars.first)
  let provider = try #require(primary["provider"] as? [String: Any])
  let fake = try #require(provider["fake"] as? [String: Any])
  #expect(primary["id"] as? String == "primary")
  #expect(primary["summary"] as? String == "Personal")
  #expect(primary["isPrimary"] as? Bool == true)
  #expect(fake["credentialId"] as? String == "google-personal")
}

@Test func authStatusDefaultsToTheLoginCredential() throws {
  let paths = temporaryConfigPaths()
  defer { try? FileManager.default.removeItem(atPath: paths.root) }
  try writeConfig(paths: paths)
  let cli = GoogleCalendarGatewayCLI()
  let explicit = cli.run(arguments: ["--config", paths.config, "auth", "status", "--credential", "google-personal"], environment: env(paths: paths))
  let implicit = cli.run(arguments: ["--config", paths.config, "auth", "status"], environment: env(paths: paths))
  #expect(implicit.exitCode == 0)
  #expect(implicit.stdout == explicit.stdout)
  let revoke = cli.run(arguments: ["--config", paths.config, "auth", "revoke"], environment: env(paths: paths))
  #expect(revoke.exitCode == 2)
  #expect(revoke.stderr.contains("auth commands require --credential"))
}

@Test func authStatusDetectsScopeMismatch() throws {
  let paths = temporaryConfigPaths()
  defer {
    try? FileManager.default.removeItem(atPath: paths.root)
  }
  try writeConfig(paths: paths, accessMode: "read_write")

  let result = GoogleCalendarGatewayCLI().run(
    arguments: ["--config", paths.config, "auth", "status", "--credential", "google-personal"],
    environment: env(paths: paths)
  )

  #expect(result.exitCode == GoogleCalendarGatewayExitCode.success.rawValue)
  #expect(result.stdout.contains("\"state\":\"SCOPE_MISMATCH\""))
}

@Test func authStatusDetectsMissingCalendarListScope() throws {
  let paths = temporaryConfigPaths()
  defer {
    try? FileManager.default.removeItem(atPath: paths.root)
  }
  try writeConfig(paths: paths)
  try """
  {"accessMode":"read","accessToken":"test-token","refreshToken":"refresh","expiresAt":"2099-01-01T00:00:00Z","scope":"https://www.googleapis.com/auth/calendar.events.readonly"}
  """.write(toFile: paths.token, atomically: true, encoding: .utf8)

  let result = GoogleCalendarGatewayCLI().run(
    arguments: ["--config", paths.config, "auth", "status", "--credential", "google-personal"],
    environment: env(paths: paths)
  )

  #expect(result.exitCode == GoogleCalendarGatewayExitCode.success.rawValue)
  #expect(result.stdout.contains("\"state\":\"SCOPE_MISMATCH\""))
}

@Test func eventQueryWithoutTokenReturnsGraphQLError() throws {
  let paths = temporaryConfigPaths()
  defer {
    try? FileManager.default.removeItem(atPath: paths.root)
  }
  try writeConfig(paths: paths)
  try FileManager.default.removeItem(atPath: paths.token)

  let result = GoogleCalendarGatewayCLI().run(
    arguments: [
      "--config", paths.config,
      "graphql",
      "--query", "{ events(calendarId: \"personal\", timeMin: \"2026-07-01T00:00:00Z\") { events { id } } }"
    ],
    environment: env(paths: paths)
  )

  #expect(result.exitCode == GoogleCalendarGatewayExitCode.providerApiError.rawValue)
  #expect(result.stdout.contains("\"errors\""))
  #expect(result.stdout.contains("Calendar authentication is required"))
}

@Test func serviceUsesInjectedProviderForEventQueries() throws {
  let provider = FakeCalendarProvider()
  let result = try GoogleCalendarGatewayService(config: testConfig(), provider: provider).listEvents(
    search: CalendarEventSearch(accountId: "personal", timeMin: "2026-07-01T00:00:00Z")
  )

  #expect(result["calendarId"] as? String == "primary")
  let events = try #require(result["events"] as? [[String: Any]])
  #expect(events.count == 1)
  #expect(events.first?["id"] as? String == "event-1")
}

@Test func serviceExposesTypedCalendarEventConnection() throws {
  let connection = try GoogleCalendarGatewayService(config: testConfig(), provider: FakeCalendarProvider()).searchEvents(
    search: CalendarEventSearch(accountId: "personal")
  )

  #expect(connection.calendarId == "primary")
  #expect(connection.events.first?.id == "event-1")
  #expect(connection.events.first?.start?.dateTime == "2026-07-01T09:00:00Z")
  #expect(connection.events.first?.attendees.first?.email == "guest@example.com")
}

@Test func graphQLSupportsIncrementalEventSyncArguments() throws {
  let result = try executeCalendarGraphQL(
    service: GoogleCalendarGatewayService(config: testConfig(), provider: FakeCalendarProvider()),
    query: """
    { events(
      calendarId: "personal",
      syncToken: "sync-1",
      showDeleted: true,
      singleEvents: false,
      maxResults: 10
    ) { events { provider { fake { syncToken showDeleted singleEvents } } } nextSyncToken } }
    """
  )

  #expect(result.exitCode == .success)
  let data = try #require(result.body["data"] as? [String: Any])
  let connection = try #require(data["events"] as? [String: Any])
  let events = try #require(connection["events"] as? [[String: Any]])
  let event = try #require(events.first)
  let provider = try #require(event["provider"] as? [String: Any])
  let fake = try #require(provider["fake"] as? [String: Any])
  #expect(connection["nextSyncToken"] as? String == "next-sync")
  #expect(fake["syncToken"] as? String == "sync-1")
  #expect(fake["showDeleted"] as? Bool == true)
  #expect(fake["singleEvents"] as? Bool == false)
}

@Test func graphQLSupportsUpdatedEventSearchArguments() throws {
  let result = try executeCalendarGraphQL(
    service: GoogleCalendarGatewayService(config: testConfig(), provider: FakeCalendarProvider()),
    query: """
    { events(
      calendarId: "personal",
      updatedMin: "2026-07-01T00:00:00Z",
      showDeleted: true,
      singleEvents: true,
      orderBy: "updated"
    ) { events { provider { fake { updatedMin showDeleted singleEvents orderBy } } } } }
    """
  )

  #expect(result.exitCode == .success)
  let data = try #require(result.body["data"] as? [String: Any])
  let connection = try #require(data["events"] as? [String: Any])
  let events = try #require(connection["events"] as? [[String: Any]])
  let event = try #require(events.first)
  let provider = try #require(event["provider"] as? [String: Any])
  let fake = try #require(provider["fake"] as? [String: Any])
  #expect(fake["updatedMin"] as? String == "2026-07-01T00:00:00Z")
  #expect(fake["showDeleted"] as? Bool == true)
  #expect(fake["singleEvents"] as? Bool == true)
  #expect(fake["orderBy"] as? String == "updated")
}

@Test func graphQLAcceptsFractionalSecondDateTimes() throws {
  let result = try executeCalendarGraphQL(
    service: GoogleCalendarGatewayService(config: testConfig(), provider: FakeCalendarProvider()),
    query: """
    { events(
      calendarId: "personal",
      timeMin: "2026-07-01T00:00:00.000Z",
      timeMax: "2026-07-02T09:30:15.123+09:00",
      updatedMin: "2026-07-01T12:00:00.000Z"
    ) { events { id } } }
    """
  )

  #expect(result.exitCode == .success)
}

@Test func eventSyncTokenRejectsIncompatibleSearchArguments() throws {
  let withTimeMin = try executeCalendarGraphQL(
    service: GoogleCalendarGatewayService(config: testConfig(), provider: ThrowingReadProvider()),
    query: """
    { events(calendarId: "personal", syncToken: "sync-1", timeMin: "2026-07-01T00:00:00Z") { events { id } } }
    """
  )
  let withShowDeletedFalse = try executeCalendarGraphQL(
    service: GoogleCalendarGatewayService(config: testConfig(), provider: ThrowingReadProvider()),
    query: """
    { events(calendarId: "personal", syncToken: "sync-1", showDeleted: false) { events { id } } }
    """
  )

  #expect(withTimeMin.exitCode == .graphqlExecutionError)
  #expect(withShowDeletedFalse.exitCode == .graphqlExecutionError)
  let timeMinErrors = try #require(withTimeMin.body["errors"] as? [[String: Any]])
  let showDeletedErrors = try #require(withShowDeletedFalse.body["errors"] as? [[String: Any]])
  #expect(timeMinErrors.first?["message"] as? String == "syncToken cannot be combined with: timeMin")
  #expect(showDeletedErrors.first?["message"] as? String == "syncToken cannot be combined with showDeleted = false")
}

@Test func eventSearchRejectsInvalidUpdatedMinAndOrderBy() throws {
  let invalidUpdatedMin = try executeCalendarGraphQL(
    service: GoogleCalendarGatewayService(config: testConfig(), provider: FakeCalendarProvider()),
    query: """
    { events(calendarId: "personal", updatedMin: "yesterday") { events { id } } }
    """
  )
  let invalidOrderBy = try executeCalendarGraphQL(
    service: GoogleCalendarGatewayService(config: testConfig(), provider: FakeCalendarProvider()),
    query: """
    { events(calendarId: "personal", orderBy: "summary") { events { id } } }
    """
  )

  #expect(invalidUpdatedMin.exitCode == .graphqlExecutionError)
  #expect(invalidOrderBy.exitCode == .graphqlExecutionError)
  let orderByErrors = try #require(invalidOrderBy.body["errors"] as? [[String: Any]])
  #expect(orderByErrors.first?["message"] as? String == "GraphQL argument orderBy must be one of: startTime, updated")
}

@Test func serviceExposesTypedFreeBusyResponse() throws {
  let response = try GoogleCalendarGatewayService(config: testConfig(), provider: FakeCalendarProvider()).queryFreeBusy(
    query: CalendarFreeBusyQuery(
      accountId: "personal",
      calendarIds: ["primary", "team@example.com"],
      timeMin: "2026-07-01T00:00:00Z",
      timeMax: "2026-07-02T00:00:00Z"
    )
  )

  #expect(response.accountId == "personal")
  #expect(response.calendars.count == 2)
  #expect(response.calendars[0].id == "primary")
  #expect(response.calendars[0].busy.first?.start == "2026-07-01T09:00:00Z")
}

@Test func graphQLReturnsProjectedFreeBusy() throws {
  let result = try executeCalendarGraphQL(
    service: GoogleCalendarGatewayService(config: testConfig(), provider: FakeCalendarProvider()),
    query: """
    { freeBusy(
      calendarId: "personal",
      providerCalendarIds: ["primary", "team@example.com"],
      timeMin: "2026-07-01T00:00:00Z",
      timeMax: "2026-07-02T00:00:00Z",
      calendarExpansionMax: 2
    ) { calendars { id busy { start end } } } }
    """
  )

  #expect(result.exitCode == .success)
  let data = try #require(result.body["data"] as? [String: Any])
  let freeBusy = try #require(data["freeBusy"] as? [String: Any])
  let calendars = try #require(freeBusy["calendars"] as? [[String: Any]])
  let firstCalendar = try #require(calendars.first)
  let firstBusy = try #require((firstCalendar["busy"] as? [[String: Any]])?.first)
  #expect(Set(freeBusy.keys) == ["calendars"])
  #expect(firstCalendar["id"] as? String == "primary")
  #expect(firstBusy["start"] as? String == "2026-07-01T09:00:00Z")
  #expect(firstBusy["end"] as? String == "2026-07-01T09:30:00Z")
}

@Test func freeBusyDefaultsToConfiguredProviderCalendar() throws {
  let response = try GoogleCalendarGatewayService(config: testConfig(), provider: FakeCalendarProvider()).queryFreeBusy(
    query: CalendarFreeBusyQuery(
      accountId: "personal",
      timeMin: "2026-07-01T00:00:00Z",
      timeMax: "2026-07-02T00:00:00Z"
    )
  )

  #expect(response.calendars.map(\.id) == ["primary"])
}

@Test func freeBusyRejectsInvalidDateTimeAndExpansionMax() throws {
  let invalidDate = try executeCalendarGraphQL(
    service: GoogleCalendarGatewayService(config: testConfig(), provider: FakeCalendarProvider()),
    query: """
    { freeBusy(calendarId: "personal", timeMin: "tomorrow", timeMax: "2026-07-02T00:00:00Z") { calendars { id } } }
    """
  )
  let invalidExpansion = try executeCalendarGraphQL(
    service: GoogleCalendarGatewayService(config: testConfig(), provider: FakeCalendarProvider()),
    query: """
    { freeBusy(
      calendarId: "personal",
      timeMin: "2026-07-01T00:00:00Z",
      timeMax: "2026-07-02T00:00:00Z",
      calendarExpansionMax: 51
    ) { calendars { id } } }
    """
  )

  #expect(invalidDate.exitCode == .graphqlExecutionError)
  #expect(invalidExpansion.exitCode == .graphqlExecutionError)
  let errors = try #require(invalidExpansion.body["errors"] as? [[String: Any]])
  let firstError = try #require(errors.first)
  #expect(firstError["message"] as? String == "calendarExpansionMax must be between 1 and 50")
}

@Test func graphQLRejectsMultipleRootFields() throws {
  let result = try executeCalendarGraphQL(
    service: GoogleCalendarGatewayService(config: testConfig(), provider: FakeCalendarProvider()),
    query: "{ calendars { id } providerCalendars(credentialId: \"google-personal\") { id } }"
  )

  #expect(result.exitCode == .graphqlExecutionError)
  let errors = try #require(result.body["errors"] as? [[String: Any]])
  #expect(errors.first?["message"] as? String == "GraphQL operations may contain exactly one root field")
}

@Test func graphQLArgumentLookupIgnoresArgumentNamesInsideStrings() throws {
  let result = try executeCalendarGraphQL(
    service: GoogleCalendarGatewayService(config: testConfig(accessMode: .readWrite), provider: FakeCalendarProvider()),
    query: """
    mutation {
      createEvent(
        calendarId: "personal",
        summary: "Reminder: set timeMin: tomorrow",
        start: "2026-07-01T09:00:00Z",
        end: "2026-07-01T09:30:00Z"
      ) { id summary }
    }
    """
  )

  #expect(result.exitCode == .success)
  let data = try #require(result.body["data"] as? [String: Any])
  let event = try #require(data["createEvent"] as? [String: Any])
  #expect(event["summary"] as? String == "Reminder: set timeMin: tomorrow")
}

@Test func graphQLFieldLookupIgnoresDelimitersInsideStrings() throws {
  let result = try executeCalendarGraphQL(
    service: GoogleCalendarGatewayService(config: testConfig(accessMode: .readWrite), provider: FakeCalendarProvider()),
    query: """
    mutation {
      createEvent(
        calendarId: "personal",
        summary: "1) use {braces",
        start: "2026-07-01T09:00:00Z",
        end: "2026-07-01T09:30:00Z"
      ) { id summary }
    }
    """
  )

  #expect(result.exitCode == .success)
  let data = try #require(result.body["data"] as? [String: Any])
  let event = try #require(data["createEvent"] as? [String: Any])
  #expect(event["summary"] as? String == "1) use {braces")
}

@Test func graphQLProjectsSelectedEventFields() throws {
  let result = try executeCalendarGraphQL(
    service: GoogleCalendarGatewayService(config: testConfig(), provider: FakeCalendarProvider()),
    query: "{ events(calendarId: \"personal\") { events { id start { dateTime } } nextCursor nextPageToken } }"
  )

  #expect(result.exitCode == .success)
  let data = try #require(result.body["data"] as? [String: Any])
  let connection = try #require(data["events"] as? [String: Any])
  let events = try #require(connection["events"] as? [[String: Any]])
  let event = try #require(events.first)
  let start = try #require(event["start"] as? [String: Any])
  #expect(Set(connection.keys) == ["events", "nextCursor", "nextPageToken"])
  #expect(Set(event.keys) == ["id", "start"])
  #expect(Set(start.keys) == ["dateTime"])
  #expect(event["id"] as? String == "event-1")
  #expect(start["dateTime"] as? String == "2026-07-01T09:00:00Z")
  #expect(connection["nextPageToken"] as? String == "next-page")
  #expect(try pageTokenFromCalendarEventCursor(try #require(connection["nextCursor"] as? String)) == "next-page")
}

@Test func graphQLAcceptsOpaqueEventCursor() throws {
  let cursor = calendarEventCursor(pageToken: "next-page")
  let result = try executeCalendarGraphQL(
    service: GoogleCalendarGatewayService(config: testConfig(), provider: FakeCalendarProvider()),
    query: "{ events(calendarId: \"personal\", cursor: \"\(cursor)\") { events { id } nextCursor } }"
  )

  #expect(result.exitCode == .success)
  let data = try #require(result.body["data"] as? [String: Any])
  let connection = try #require(data["events"] as? [String: Any])
  #expect(try pageTokenFromCalendarEventCursor(try #require(connection["nextCursor"] as? String)) == "next-page")
}

@Test func graphQLRejectsInvalidOpaqueEventCursor() throws {
  let result = try executeCalendarGraphQL(
    service: GoogleCalendarGatewayService(config: testConfig(), provider: FakeCalendarProvider()),
    query: "{ events(calendarId: \"personal\", cursor: \"not-a-cursor\") { events { id } } }"
  )

  #expect(result.exitCode == .graphqlExecutionError)
  let errors = try #require(result.body["errors"] as? [[String: Any]])
  let firstError = try #require(errors.first)
  #expect(firstError["message"] as? String == "GraphQL argument cursor is invalid")
}

@Test func eventCursorRoundTripRejectsMalformedValues() throws {
  let cursor = calendarEventCursor(pageToken: "provider-token")

  #expect(try pageTokenFromCalendarEventCursor(cursor) == "provider-token")
  #expect(throws: GoogleCalendarGatewayError.self) {
    _ = try pageTokenFromCalendarEventCursor("bad")
  }
}

@Test func graphQLRejectsInvalidEventSearchDateTime() throws {
  let result = try executeCalendarGraphQL(
    service: GoogleCalendarGatewayService(config: testConfig(), provider: FakeCalendarProvider()),
    query: "{ events(calendarId: \"personal\", timeMin: \"next week\") { events { id } } }"
  )

  #expect(result.exitCode == .graphqlExecutionError)
  let errors = try #require(result.body["errors"] as? [[String: Any]])
  let firstError = try #require(errors.first)
  #expect(firstError["message"] as? String == "GraphQL argument timeMin must be an RFC 3339 date-time string")
}

@Test func graphQLRejectsOutOfRangeMaxResults() throws {
  let tooLow = try executeCalendarGraphQL(
    service: GoogleCalendarGatewayService(config: testConfig(), provider: FakeCalendarProvider()),
    query: "{ events(calendarId: \"personal\", maxResults: 0) { events { id } } }"
  )
  let tooHigh = try executeCalendarGraphQL(
    service: GoogleCalendarGatewayService(config: testConfig(), provider: FakeCalendarProvider()),
    query: "{ events(calendarId: \"personal\", maxResults: 2501) { events { id } } }"
  )

  #expect(tooLow.exitCode == .graphqlExecutionError)
  #expect(tooHigh.exitCode == .graphqlExecutionError)
  let errors = try #require(tooHigh.body["errors"] as? [[String: Any]])
  let firstError = try #require(errors.first)
  #expect(firstError["message"] as? String == "GraphQL argument maxResults must be between 1 and 2500")
}

@Test func graphQLAcceptsMaxResultsUpperBound() throws {
  let result = try executeCalendarGraphQL(
    service: GoogleCalendarGatewayService(config: testConfig(), provider: FakeCalendarProvider()),
    query: "{ events(calendarId: \"personal\", maxResults: 2500) { events { id } } }"
  )

  #expect(result.exitCode == .success)
}

@Test func graphQLMapsProviderErrorsFromInjectedProvider() throws {
  let result = try executeCalendarGraphQL(
    service: GoogleCalendarGatewayService(config: testConfig(), provider: ThrowingReadProvider()),
    query: "{ events(calendarId: \"personal\") { events { id } } }"
  )

  #expect(result.exitCode == .providerApiError)
  #expect(result.body["data"] is NSNull)
  let errors = try #require(result.body["errors"] as? [[String: Any]])
  let firstError = try #require(errors.first)
  let extensions = try #require(firstError["extensions"] as? [String: Any])
  #expect(firstError["message"] as? String == "Google Calendar rate limit exceeded")
  #expect(extensions["code"] as? String == GoogleCalendarGatewayErrorCode.providerRateLimited.rawValue)
  #expect(extensions["exitCode"] as? Int32 == GoogleCalendarGatewayExitCode.providerApiError.rawValue)
}

@Test func graphQLMapsConfigurationErrorsIntoErrorEnvelope() throws {
  let result = try executeCalendarGraphQL(
    service: GoogleCalendarGatewayService(config: testConfig(), provider: FakeCalendarProvider()),
    query: "{ providerCalendars(credentialId: \"missing\") { id } }"
  )

  #expect(result.exitCode == .configurationError)
  #expect(result.body["data"] is NSNull)
  let errors = try #require(result.body["errors"] as? [[String: Any]])
  let extensions = try #require(errors.first?["extensions"] as? [String: Any])
  #expect(errors.first?["message"] as? String == "Unknown credential: missing")
  #expect(extensions["code"] as? String == GoogleCalendarGatewayErrorCode.credentialNotFound.rawValue)
}

@Test func googleHTTPErrorMappingUsesActionableCodes() {
  let unauthorized = googleCalendarHTTPError(context: "request failed", statusCode: 401)
  let forbidden = googleCalendarHTTPError(context: "request failed", statusCode: 403)
  let missingEvent = googleCalendarHTTPError(context: "request failed", statusCode: 404, failureKind: .event)
  let missingCalendar = googleCalendarHTTPError(context: "request failed", statusCode: 404)
  let rateLimited = googleCalendarHTTPError(context: "request failed", statusCode: 429)
  let expiredSyncToken = googleCalendarHTTPError(context: "request failed", statusCode: 410)
  let serverError = googleCalendarHTTPError(context: "request failed", statusCode: 500)

  #expect(unauthorized.code == .authRequired)
  #expect(forbidden.code == .authRequired)
  #expect(missingEvent.code == .eventNotFound)
  #expect(missingCalendar.code == .providerApiError)
  #expect(expiredSyncToken.code == .syncTokenExpired)
  #expect(rateLimited.code == .providerRateLimited)
  #expect(serverError.code == .providerApiError)
  #expect(missingEvent.exitCode == .providerApiError)
  #expect(missingEvent.details["httpStatus"] == "404")
}

@Test func createEventGraphQLRejectsInvalidDateTime() throws {
  let result = try executeCalendarGraphQL(
    service: GoogleCalendarGatewayService(config: testConfig(accessMode: .readWrite), provider: FakeCalendarProvider()),
    query: """
    mutation { createEvent(calendarId: "personal", summary: "Planning", start: "July 1", end: "2026-07-01T09:30:00Z") { id } }
    """
  )

  #expect(result.exitCode == .graphqlExecutionError)
  let errors = try #require(result.body["errors"] as? [[String: Any]])
  let firstError = try #require(errors.first)
  #expect(firstError["message"] as? String == "GraphQL argument start must be an RFC 3339 date-time or YYYY-MM-DD date string")
}

@Test func createEventGraphQLAcceptsAllDayDates() throws {
  let result = try executeCalendarGraphQL(
    service: GoogleCalendarGatewayService(config: testConfig(accessMode: .readWrite), provider: FakeCalendarProvider()),
    query: """
    mutation { createEvent(calendarId: "personal", summary: "Holiday", start: "2026-07-01", end: "2026-07-02") { id summary } }
    """
  )

  #expect(result.exitCode == .success)
  let data = try #require(result.body["data"] as? [String: Any])
  let event = try #require(data["createEvent"] as? [String: Any])
  #expect(event["id"] as? String == "created-event")
  #expect(event["summary"] as? String == "Holiday")
}

@Test func serviceUsesInjectedProviderForWriteOperations() throws {
  let provider = FakeCalendarProvider()
  let result = try GoogleCalendarGatewayService(
    config: testConfig(accessMode: .readWrite),
    provider: provider
  ).createCalendarEvent(input: CalendarEventInput(
    accountId: "personal",
    summary: "Planning",
    start: "2026-07-01T09:00:00Z",
    end: "2026-07-01T09:30:00Z"
  ))

  #expect(result.id == "created-event")
  #expect(result.summary == "Planning")
}

@Test func serviceRejectsOutOfRangeMaxResultsBeforeProviderCall() throws {
  let error = try requireGoogleCalendarGatewayError {
    _ = try GoogleCalendarGatewayService(config: testConfig(), provider: ThrowingReadProvider()).searchEvents(
      search: CalendarEventSearch(accountId: "personal", maxResults: 2501)
    )
  }

  #expect(error.code == .invalidArgument)
  #expect(error.message == "maxResults must be between 1 and 2500")
}

@Test func serviceRejectsInvalidEventSearchDateTimesBeforeProviderCall() throws {
  let invalidTimeMin = try requireGoogleCalendarGatewayError {
    _ = try GoogleCalendarGatewayService(config: testConfig(), provider: ThrowingReadProvider()).searchEvents(
      search: CalendarEventSearch(accountId: "personal", timeMin: "next week")
    )
  }
  let invalidTimeMax = try requireGoogleCalendarGatewayError {
    _ = try GoogleCalendarGatewayService(config: testConfig(), provider: ThrowingReadProvider()).searchEvents(
      search: CalendarEventSearch(accountId: "personal", timeMax: "tomorrow")
    )
  }

  #expect(invalidTimeMin.code == .invalidArgument)
  #expect(invalidTimeMin.message == "timeMin must be an RFC 3339 date-time string")
  #expect(invalidTimeMax.code == .invalidArgument)
  #expect(invalidTimeMax.message == "timeMax must be an RFC 3339 date-time string")
}

@Test func readOnlyCredentialRejectsWriteBeforeProviderCall() throws {
  let error = try requireGoogleCalendarGatewayError {
    _ = try GoogleCalendarGatewayService(
      config: testConfig(accessMode: .read),
      provider: FailingWriteProvider()
    ).createEvent(input: CalendarEventInput(
      accountId: "personal",
      summary: "Planning",
      start: "2026-07-01T09:00:00Z",
      end: "2026-07-01T09:30:00Z"
    ))
  }

  #expect(error.code == .writeDisabled)
  #expect(error.exitCode == .graphqlExecutionError)
}

@Test func createEventGraphQLRejectsReadOnlyCredential() throws {
  let paths = temporaryConfigPaths()
  defer {
    try? FileManager.default.removeItem(atPath: paths.root)
  }
  try writeConfig(paths: paths)

  let result = GoogleCalendarGatewayCLI(mode: .writer).run(
    arguments: [
      "--config", paths.config,
      "graphql",
      "--query",
      """
      mutation { createEvent(calendarId: "personal", summary: "Planning", start: "2026-07-01T09:00:00Z", end: "2026-07-01T09:30:00Z") { id } }
      """
    ],
    environment: env(paths: paths)
  )

  #expect(result.exitCode == GoogleCalendarGatewayExitCode.graphqlExecutionError.rawValue)
  #expect(result.stdout.contains("\"code\":\"WRITE_DISABLED\""))
}

@Test func serviceRejectsInvalidSendUpdatesBeforeProviderCall() throws {
  let error = try requireGoogleCalendarGatewayError {
    _ = try GoogleCalendarGatewayService(
      config: testConfig(accessMode: .readWrite),
      provider: FailingWriteProvider()
    ).createEvent(input: CalendarEventInput(
      accountId: "personal",
      summary: "Planning",
      start: "2026-07-01T09:00:00Z",
      end: "2026-07-01T09:30:00Z",
      sendUpdates: "everyone"
    ))
  }

  #expect(error.code == .invalidArgument)
  #expect(error.message == "sendUpdates must be one of: all, externalOnly, none")
}

@Test func createEventRequiresStartAndEndBeforeProviderCall() throws {
  let error = try requireGoogleCalendarGatewayError {
    _ = try GoogleCalendarGatewayService(
      config: testConfig(accessMode: .readWrite),
      provider: FailingWriteProvider()
    ).createEvent(input: CalendarEventInput(
      accountId: "personal",
      summary: "Planning",
      start: "2026-07-01T09:00:00Z"
    ))
  }

  #expect(error.code == .invalidArgument)
  #expect(error.message == "createEvent requires end")
}

@Test func eventMutationRejectsInvalidDatesBeforeProviderCall() throws {
  let invalidStart = try requireGoogleCalendarGatewayError {
    _ = try GoogleCalendarGatewayService(
      config: testConfig(accessMode: .readWrite),
      provider: FailingWriteProvider()
    ).createEvent(input: CalendarEventInput(
      accountId: "personal",
      summary: "Planning",
      start: "July 1",
      end: "2026-07-01T09:30:00Z"
    ))
  }
  let invalidEnd = try requireGoogleCalendarGatewayError {
    _ = try GoogleCalendarGatewayService(
      config: testConfig(accessMode: .readWrite),
      provider: FailingWriteProvider()
    ).updateEvent(input: CalendarEventInput(
      accountId: "personal",
      eventId: "event-1",
      end: "tomorrow"
    ))
  }

  #expect(invalidStart.code == .invalidArgument)
  #expect(invalidStart.message == "start must be an RFC 3339 date-time or YYYY-MM-DD date string")
  #expect(invalidEnd.code == .invalidArgument)
  #expect(invalidEnd.message == "end must be an RFC 3339 date-time or YYYY-MM-DD date string")
}

@Test func updateEventRequiresWritableFieldBeforeProviderCall() throws {
  let error = try requireGoogleCalendarGatewayError {
    _ = try GoogleCalendarGatewayService(
      config: testConfig(accessMode: .readWrite),
      provider: FailingWriteProvider()
    ).updateEvent(input: CalendarEventInput(
      accountId: "personal",
      eventId: "event-1"
    ))
  }

  #expect(error.code == .invalidArgument)
  #expect(error.message == "Event input must contain at least one writable field")
}

@Test func createEventRejectsInvalidAttendeeEmailBeforeProviderCall() throws {
  let error = try requireGoogleCalendarGatewayError {
    _ = try GoogleCalendarGatewayService(
      config: testConfig(accessMode: .readWrite),
      provider: FailingWriteProvider()
    ).createEvent(input: CalendarEventInput(
      accountId: "personal",
      summary: "Planning",
      start: "2026-07-01T09:00:00Z",
      end: "2026-07-01T09:30:00Z",
      attendeeEmails: ["not-an-email"]
    ))
  }

  #expect(error.code == .invalidArgument)
  #expect(error.message == "attendeeEmails must contain non-empty email addresses")
}

@Test func createEventGraphQLRejectsInvalidSendUpdates() throws {
  let result = try executeCalendarGraphQL(
    service: GoogleCalendarGatewayService(config: testConfig(accessMode: .readWrite), provider: FailingWriteProvider()),
    query: """
    mutation { createEvent(calendarId: "personal", summary: "Planning", start: "2026-07-01T09:00:00Z", end: "2026-07-01T09:30:00Z", sendUpdates: "everyone") { id } }
    """
  )

  #expect(result.exitCode == .graphqlExecutionError)
  let errors = try #require(result.body["errors"] as? [[String: Any]])
  let firstError = try #require(errors.first)
  #expect(firstError["message"] as? String == "sendUpdates must be one of: all, externalOnly, none")
}

@Test func deleteEventGraphQLAcceptsValidSendUpdates() throws {
  let result = try executeCalendarGraphQL(
    service: GoogleCalendarGatewayService(config: testConfig(accessMode: .readWrite), provider: FakeCalendarProvider()),
    query: """
    mutation { deleteEvent(calendarId: "personal", eventId: "event-1", sendUpdates: "externalOnly") { deleted sendUpdates } }
    """
  )

  #expect(result.exitCode == .success)
  let data = try #require(result.body["data"] as? [String: Any])
  let payload = try #require(data["deleteEvent"] as? [String: Any])
  #expect(payload["deleted"] as? Bool == true)
  #expect(payload["sendUpdates"] as? String == "externalOnly")
}

@Test func deleteEventRejectsBlankEventIdBeforeProviderCall() throws {
  let error = try requireGoogleCalendarGatewayError {
    _ = try GoogleCalendarGatewayService(
      config: testConfig(accessMode: .readWrite),
      provider: FailingWriteProvider()
    ).deleteEvent(accountId: "personal", eventId: " ")
  }

  #expect(error.code == .invalidArgument)
  #expect(error.message == "deleteEvent requires eventId")
}

@Test func tokenRefreshOAuthClientUsesInstalledClientTokenURI() throws {
  let credential = testCredential(oauthClientSecretJSON: """
  {
    "installed": {
      "client_id": " client-id ",
      "auth_uri": " https://accounts.example.test/o/oauth2/auth ",
      "token_uri": " https://tokens.example.test/token "
    }
  }
  """)

  let client = try loadGoogleOAuthClient(credential: credential, use: .tokenRefresh)

  #expect(client.clientId == "client-id")
  #expect(client.clientSecret == nil)
  #expect(client.tokenURI == "https://tokens.example.test/token")
}

@Test func desktopLoginRejectsWebOnlyOAuthClient() throws {
  let credential = testCredential(oauthClientSecretJSON: """
  {
    "web": {
      "client_id": "web-client-id",
      "client_secret": "web-secret",
      "token_uri": "https://tokens.example.test/token"
    }
  }
  """)

  let error = try requireGoogleCalendarGatewayError {
    _ = try loadGoogleOAuthClient(credential: credential, use: .desktopLogin)
  }

  #expect(error.code == .configInvalid)
  #expect(error.exitCode == .authenticationBootstrapError)
}

@Test(arguments: [true, false]) func authLoginRejectsWebOnlyClientBeforeBrowserLaunch(explicitCredential: Bool) throws {
  let paths = temporaryConfigPaths()
  defer {
    try? FileManager.default.removeItem(atPath: paths.root)
  }
  try writeConfig(paths: paths)
  try """
  {"web":{"client_id":"web-client-id","client_secret":"web-secret","token_uri":"https://tokens.example.test/token"}}
  """.write(toFile: paths.oauthClient, atomically: true, encoding: .utf8)

  let result = GoogleCalendarGatewayCLI().run(
    arguments: ["--config", paths.config, "auth", "login"]
      + (explicitCredential ? ["--credential", "google-personal"] : []),
    environment: env(paths: paths)
  )

  #expect(result.exitCode == GoogleCalendarGatewayExitCode.authenticationBootstrapError.rawValue)
  #expect(result.stderr.contains("installed desktop client"))
  #expect(!result.stderr.contains("web-secret"))
}

@Test func calendarScopesUseNarrowEventAndCalendarListScopes() {
  #expect(calendarScopes(accessMode: .full) == [
    "https://www.googleapis.com/auth/calendar"
  ])
  #expect(calendarScopes(accessMode: .read) == [
    "https://www.googleapis.com/auth/calendar.events.readonly",
    "https://www.googleapis.com/auth/calendar.calendarlist.readonly",
    "https://www.googleapis.com/auth/calendar.freebusy"
  ])
  #expect(calendarScopes(accessMode: .readWrite) == [
    "https://www.googleapis.com/auth/calendar.events",
    "https://www.googleapis.com/auth/calendar.calendarlist.readonly",
    "https://www.googleapis.com/auth/calendar.freebusy"
  ])
}

@Test func calendarScopeInferenceRequiresCalendarListAndFreeBusyRead() {
  #expect(accessModeFromScopes("https://www.googleapis.com/auth/calendar.events.readonly") == nil)
  #expect(accessModeFromScopes([
    "https://www.googleapis.com/auth/calendar.events.readonly",
    "https://www.googleapis.com/auth/calendar.calendarlist.readonly"
  ].joined(separator: " ")) == nil)
  #expect(accessModeFromScopes([
    "https://www.googleapis.com/auth/calendar.events.readonly",
    "https://www.googleapis.com/auth/calendar.calendarlist.readonly",
    "https://www.googleapis.com/auth/calendar.freebusy"
  ].joined(separator: " ")) == .read)
  #expect(accessModeFromScopes([
    "https://www.googleapis.com/auth/calendar.events",
    "https://www.googleapis.com/auth/calendar.calendarlist.readonly",
    "https://www.googleapis.com/auth/calendar.freebusy"
  ].joined(separator: " ")) == .readWrite)
  #expect(accessModeFromScopes("https://www.googleapis.com/auth/calendar.readonly") == .read)
  #expect(accessModeFromScopes("https://www.googleapis.com/auth/calendar") == .full)
  #expect(calendarScopesCover(accessMode: .read, grantedScope: "https://www.googleapis.com/auth/calendar"))
  #expect(calendarScopesCover(accessMode: .readWrite, grantedScope: "https://www.googleapis.com/auth/calendar"))
  #expect(calendarScopesCover(accessMode: .full, grantedScope: "https://www.googleapis.com/auth/calendar"))
}

@Test func liveTokenValidationUsesScopeCoverageSemantics() throws {
  let broadToken = """
  {"accessToken":"access","refreshToken":"refresh","expiresAt":"2099-01-01T00:00:00Z","scope":"https://www.googleapis.com/auth/calendar"}
  """
  let broadCredential = testCredential(tokenStoreJSON: broadToken, accessMode: .read)

  #expect(try validGoogleCalendarAccessToken(credential: broadCredential, use: .read) == "access")

  let partialToken = """
  {"accessToken":"access","refreshToken":"refresh","expiresAt":"2099-01-01T00:00:00Z","scope":"https://www.googleapis.com/auth/calendar.events.readonly"}
  """
  let partialCredential = testCredential(tokenStoreJSON: partialToken, accessMode: .read)

  let error = try requireGoogleCalendarGatewayError {
    _ = try validGoogleCalendarAccessToken(credential: partialCredential, use: .read)
  }
  #expect(error.code == .authRequired)
  #expect(error.exitCode == .providerApiError)
}

@Test func formURLEncodedEscapesReservedCharacters() {
  let encoded = formURLEncoded([
    ("redirect_uri", "http://127.0.0.1:1234/oauth2callback"),
    ("literal", "a+b c%")
  ])

  #expect(encoded == "redirect_uri=http%3A%2F%2F127.0.0.1%3A1234%2Foauth2callback&literal=a%2Bb%20c%25")
}

@Test func base64URLDecoderRejectsStandardBase64Alphabet() {
  #expect(dataFromBase64URLString("-w") == Data([251]))
  #expect(dataFromBase64URLString("-w==") == Data([251]))
  #expect(dataFromBase64URLString("+w==") == nil)
  #expect(dataFromBase64URLString("abc=d") == nil)
  #expect(dataFromBase64URLString("a") == nil)
}

@Test func pathComponentEncodingEscapesSlash() {
  #expect(urlEncodedPathComponent("calendar/with/slash") == "calendar%2Fwith%2Fslash")
}

@Test func graphQLArgumentLookupDoesNotConfuseProviderCalendarId() throws {
  let result = GoogleCalendarGatewayCLI().run(
    arguments: [
      "graphql",
      "--query",
      "{ events(providerCalendarId: \"primary\") { events { id } } }"
    ],
    environment: [
      "GOOGLE_CALENDAR_GATEWAY_CREDENTIAL_GOOGLE_PERSONAL_OAUTH_CLIENT_SECRET_JSON": "{}",
      "GOOGLE_CALENDAR_GATEWAY_CREDENTIAL_GOOGLE_PERSONAL_TOKEN_STORE_JSON": "{}"
    ]
  )

  #expect(result.exitCode == GoogleCalendarGatewayExitCode.graphqlExecutionError.rawValue)
  #expect(result.stdout.contains("Missing GraphQL argument: calendarId"))
}

@Test func calendarAccessTokenFreshnessRejectsMalformedExpiry() throws {
  let now = try #require(ISO8601DateFormatter().date(from: "2026-07-01T00:00:00Z"))

  #expect(calendarAccessTokenIsFresh(expiresAt: nil, now: now))
  #expect(!calendarAccessTokenIsFresh(expiresAt: "not-a-date", now: now))
  #expect(!calendarAccessTokenIsFresh(expiresAt: "2026-07-01T00:00:30Z", now: now, refreshLeeway: 60))
  #expect(calendarAccessTokenIsFresh(expiresAt: "2026-07-01T00:02:00Z", now: now, refreshLeeway: 60))
}

@Test func calendarDateValidationRejectsInvalidDates() {
  #expect(isCalendarDate("2026-07-01"))
  #expect(!isCalendarDate("2026-02-30"))
  #expect(!isCalendarDate("2026-7-1"))
  #expect(isRFC3339DateTime("2026-07-01T09:00:00Z"))
  #expect(!isRFC3339DateTime("2026-07-01"))
}
