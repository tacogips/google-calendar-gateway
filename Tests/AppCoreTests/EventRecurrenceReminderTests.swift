import Testing
@testable import GoogleCalendarGatewayCore

@Test func createEventGraphQLSupportsRecurrenceAndReminderOverrides() throws {
  let result = try executeCalendarGraphQL(
    service: GoogleCalendarGatewayService(config: testConfig(accessMode: .readWrite), provider: FakeCalendarProvider()),
    query: """
    mutation {
      createEvent(
        calendarId: "personal",
        summary: "Planning",
        start: "2026-07-01T09:00:00Z",
        end: "2026-07-01T09:30:00Z",
        timeZone: "UTC",
        recurrenceRules: ["RRULE:FREQ=WEEKLY;COUNT=4"],
        reminderUseDefault: false,
        reminderOverrides: ["popup:30", "email:1440"]
      ) { id recurrenceRules reminders { useDefault overrides { method minutes } } }
    }
    """
  )

  #expect(result.exitCode == .success)
  let data = try #require(result.body["data"] as? [String: Any])
  let event = try #require(data["createEvent"] as? [String: Any])
  let reminders = try #require(event["reminders"] as? [String: Any])
  let overrides = try #require(reminders["overrides"] as? [[String: Any]])
  #expect(event["recurrenceRules"] as? [String] == ["RRULE:FREQ=WEEKLY;COUNT=4"])
  #expect(reminders["useDefault"] as? Bool == false)
  #expect(overrides.count == 2)
  #expect(overrides[0]["method"] as? String == "popup")
  #expect(overrides[0]["minutes"] as? Int == 30)
  #expect(overrides[1]["method"] as? String == "email")
  #expect(overrides[1]["minutes"] as? Int == 1440)
}

@Test func serviceSupportsTypedRecurrenceAndReminders() throws {
  let event = try GoogleCalendarGatewayService(
    config: testConfig(accessMode: .readWrite),
    provider: FakeCalendarProvider()
  ).createCalendarEvent(input: CalendarEventInput(
    accountId: "personal",
    summary: "Planning",
    start: "2026-07-01T09:00:00Z",
    end: "2026-07-01T09:30:00Z",
    timeZone: "UTC",
    recurrenceRules: ["RRULE:FREQ=DAILY;COUNT=2"],
    reminderUseDefault: false,
    reminderOverrides: [CalendarEventReminder(method: .popup, minutes: 10)]
  ))

  #expect(event.recurrenceRules == ["RRULE:FREQ=DAILY;COUNT=2"])
  #expect(event.reminders?.useDefault == false)
  #expect(event.reminders?.overrides == [CalendarEventReminder(method: .popup, minutes: 10)])
}

@Test func googleEventMappingExposesRecurrenceAndReminders() throws {
  let event = CalendarEvent.fromGoogle(
    [
      "id": "event-1",
      "recurrence": ["RRULE:FREQ=WEEKLY;COUNT=4"],
      "reminders": [
        "useDefault": false,
        "overrides": [
          ["method": "popup", "minutes": 30],
          ["method": "email", "minutes": 1440]
        ]
      ]
    ],
    accountId: "personal",
    calendarId: "primary"
  )

  #expect(event.recurrenceRules == ["RRULE:FREQ=WEEKLY;COUNT=4"])
  #expect(event.reminders?.useDefault == false)
  #expect(event.reminders?.overrides.count == 2)
  #expect(event.reminders?.overrides.first == CalendarEventReminder(method: .popup, minutes: 30))
}

@Test func recurrenceAndReminderValidationRunsBeforeProviderCall() throws {
  let missingTimeZone = try requireGoogleCalendarGatewayError {
    _ = try GoogleCalendarGatewayService(
      config: testConfig(accessMode: .readWrite),
      provider: FailingWriteProvider()
    ).createEvent(input: CalendarEventInput(
      accountId: "personal",
      summary: "Planning",
      start: "2026-07-01T09:00:00Z",
      end: "2026-07-01T09:30:00Z",
      recurrenceRules: ["RRULE:FREQ=DAILY;COUNT=2"]
    ))
  }
  let invalidReminder = try requireGoogleCalendarGatewayError {
    _ = try GoogleCalendarGatewayService(
      config: testConfig(accessMode: .readWrite),
      provider: FailingWriteProvider()
    ).createEvent(input: CalendarEventInput(
      accountId: "personal",
      summary: "Planning",
      start: "2026-07-01T09:00:00Z",
      end: "2026-07-01T09:30:00Z",
      reminderOverrides: [CalendarEventReminder(method: .popup, minutes: 40321)]
    ))
  }

  #expect(missingTimeZone.message == "Recurring timed events require timeZone")
  #expect(invalidReminder.message == "reminderOverrides minutes must be between 0 and 40320")
}

@Test func recurrenceRulesRejectEmbeddedStartAndEnd() throws {
  let error = try requireGoogleCalendarGatewayError {
    _ = try GoogleCalendarGatewayService(
      config: testConfig(accessMode: .readWrite),
      provider: FailingWriteProvider()
    ).createEvent(input: CalendarEventInput(
      accountId: "personal",
      summary: "Planning",
      start: "2026-07-01",
      end: "2026-07-02",
      recurrenceRules: ["DTSTART:20260701T090000Z"]
    ))
  }

  #expect(error.message == "recurrenceRules must not contain DTSTART or DTEND")
}

@Test func graphQLRejectsInvalidReminderOverrideLiteral() throws {
  let result = try executeCalendarGraphQL(
    service: GoogleCalendarGatewayService(config: testConfig(accessMode: .readWrite), provider: FailingWriteProvider()),
    query: """
    mutation {
      createEvent(
        calendarId: "personal",
        summary: "Planning",
        start: "2026-07-01T09:00:00Z",
        end: "2026-07-01T09:30:00Z",
        reminderOverrides: ["sms:10"]
      ) { id }
    }
    """
  )

  #expect(result.exitCode == .graphqlExecutionError)
  let errors = try #require(result.body["errors"] as? [[String: Any]])
  #expect(errors.first?["message"] as? String == "GraphQL argument reminderOverrides must contain values like popup:30 or email:1440")
}
