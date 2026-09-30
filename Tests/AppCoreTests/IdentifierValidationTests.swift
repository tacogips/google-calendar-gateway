import Testing
@testable import GoogleCalendarGatewayCore

@Test func graphQLRejectsBlankRequiredIdentifiersBeforeProviderCalls() throws {
  let service = GoogleCalendarGatewayService(config: testConfig(), provider: ThrowingReadProvider())
  let cases = [
    (
      "{ events(calendarId: \"\") { events { id } } }",
      "GraphQL argument calendarId must be a non-empty string"
    ),
    (
      "{ event(calendarId: \"personal\", eventId: \"\") { id } }",
      "GraphQL argument eventId must be a non-empty string"
    )
  ]

  for testCase in cases {
    let result = try executeCalendarGraphQL(service: service, query: testCase.0)
    let errors = try #require(result.body["errors"] as? [[String: Any]])
    let firstError = try #require(errors.first)

    #expect(result.exitCode == .graphqlExecutionError)
    #expect(firstError["message"] as? String == testCase.1)
  }
}

@Test func libraryRejectsBlankReadIdentifiersBeforeProviderCalls() throws {
  let service = GoogleCalendarGatewayService(config: testConfig(), provider: ThrowingReadProvider())

  let blankAccount = try requireGoogleCalendarGatewayError {
    _ = try service.searchEvents(search: CalendarEventSearch(accountId: " "))
  }
  let blankProviderCalendar = try requireGoogleCalendarGatewayError {
    _ = try service.searchEvents(search: CalendarEventSearch(accountId: "personal", calendarId: " "))
  }
  let blankEvent = try requireGoogleCalendarGatewayError {
    _ = try service.calendarEvent(accountId: "personal", eventId: " ")
  }

  #expect(blankAccount.code == .invalidArgument)
  #expect(blankAccount.message == "accountId must be a non-empty string")
  #expect(blankProviderCalendar.code == .invalidArgument)
  #expect(blankProviderCalendar.message == "providerCalendarId must be a non-empty string")
  #expect(blankEvent.code == .invalidArgument)
  #expect(blankEvent.message == "eventId must be a non-empty string")
}

@Test func libraryRejectsBlankWriteProviderCalendarIdBeforeProviderCalls() throws {
  let service = GoogleCalendarGatewayService(config: testConfig(accessMode: .readWrite), provider: FailingWriteProvider())
  let createError = try requireGoogleCalendarGatewayError {
    _ = try service.createCalendarEvent(input: CalendarEventInput(
      accountId: "personal",
      calendarId: " ",
      summary: "Planning",
      start: "2026-07-01T09:00:00Z",
      end: "2026-07-01T09:30:00Z"
    ))
  }
  let deleteError = try requireGoogleCalendarGatewayError {
    _ = try service.deleteEvent(accountId: "personal", calendarId: " ", eventId: "event-1")
  }

  #expect(createError.code == .invalidArgument)
  #expect(createError.message == "providerCalendarId must be a non-empty string")
  #expect(deleteError.code == .invalidArgument)
  #expect(deleteError.message == "providerCalendarId must be a non-empty string")
}

@Test func libraryNormalizesWriteProviderCalendarAndEventIdsBeforeProviderCalls() throws {
  let service = GoogleCalendarGatewayService(config: testConfig(accessMode: .readWrite), provider: FakeCalendarProvider())

  let created = try service.createCalendarEvent(input: CalendarEventInput(
    accountId: "personal",
    calendarId: " primary ",
    summary: "Planning",
    start: "2026-07-01T09:00:00Z",
    end: "2026-07-01T09:30:00Z"
  ))
  let updated = try service.updateCalendarEvent(input: CalendarEventInput(
    accountId: "personal",
    calendarId: " primary ",
    eventId: " event-1 ",
    summary: "Planning"
  ))

  #expect(created.calendarId == "primary")
  #expect(updated.calendarId == "primary")
  #expect(updated.id == "event-1")
}
