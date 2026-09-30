import Testing
@testable import GoogleCalendarGatewayCore

@Test func createEventGraphQLSupportsMetadataAndConferenceCreation() throws {
  let result = try executeCalendarGraphQL(
    service: GoogleCalendarGatewayService(config: testConfig(accessMode: .readWrite), provider: FakeCalendarProvider()),
    query: """
    mutation {
      createEvent(
        calendarId: "personal",
        summary: "Planning",
        start: "2026-07-01T09:00:00Z",
        end: "2026-07-01T09:30:00Z",
        colorId: "7",
        visibility: "private",
        transparency: "transparent",
        createConference: true,
        conferenceRequestId: "request-1"
      ) {
        id
        colorId
        visibility
        transparency
        conferenceData { conferenceId solutionType createRequestStatus entryPoints { entryPointType uri } }
      }
    }
    """
  )

  #expect(result.exitCode == .success)
  let data = try #require(result.body["data"] as? [String: Any])
  let event = try #require(data["createEvent"] as? [String: Any])
  let conferenceData = try #require(event["conferenceData"] as? [String: Any])
  let entryPoints = try #require(conferenceData["entryPoints"] as? [[String: Any]])
  #expect(event["colorId"] as? String == "7")
  #expect(event["visibility"] as? String == "private")
  #expect(event["transparency"] as? String == "transparent")
  #expect(conferenceData["conferenceId"] as? String == "meet-123")
  #expect(conferenceData["solutionType"] as? String == "hangoutsMeet")
  #expect(conferenceData["createRequestStatus"] as? String == "success")
  #expect(entryPoints.first?["entryPointType"] as? String == "video")
}

@Test func serviceSupportsTypedMetadataAndConferenceCreation() throws {
  let event = try GoogleCalendarGatewayService(
    config: testConfig(accessMode: .readWrite),
    provider: FakeCalendarProvider()
  ).createCalendarEvent(input: CalendarEventInput(
    accountId: "personal",
    summary: "Planning",
    colorId: "5",
    visibility: .private,
    transparency: .transparent,
    start: "2026-07-01T09:00:00Z",
    end: "2026-07-01T09:30:00Z",
    createConference: true,
    conferenceRequestId: "request-1"
  ))

  #expect(event.colorId == "5")
  #expect(event.visibility == .private)
  #expect(event.transparency == .transparent)
  #expect(event.conferenceData?.solutionType == "hangoutsMeet")
  #expect(event.conferenceData?.entryPoints.first?.uri == "https://meet.google.com/aaa-bbbb-ccc")
}

@Test func googleEventMappingExposesMetadataAndConferenceData() {
  let event = CalendarEvent.fromGoogle(
    [
      "id": "event-1",
      "colorId": "9",
      "visibility": "public",
      "transparency": "transparent",
      "hangoutLink": "https://meet.google.com/aaa-bbbb-ccc",
      "conferenceData": [
        "conferenceId": "aaa-bbbb-ccc",
        "conferenceSolution": [
          "name": "Google Meet",
          "key": ["type": "hangoutsMeet"]
        ],
        "createRequest": [
          "status": ["statusCode": "success"]
        ],
        "entryPoints": [
          [
            "entryPointType": "video",
            "uri": "https://meet.google.com/aaa-bbbb-ccc",
            "label": "meet.google.com/aaa-bbbb-ccc"
          ]
        ]
      ]
    ],
    accountId: "personal",
    calendarId: "primary"
  )

  #expect(event.colorId == "9")
  #expect(event.visibility == .public)
  #expect(event.transparency == .transparent)
  #expect(event.hangoutLink == "https://meet.google.com/aaa-bbbb-ccc")
  #expect(event.conferenceData?.conferenceId == "aaa-bbbb-ccc")
  #expect(event.conferenceData?.solutionName == "Google Meet")
  #expect(event.conferenceData?.entryPoints.first?.label == "meet.google.com/aaa-bbbb-ccc")
}

@Test func graphQLRejectsInvalidVisibilityAndTransparency() throws {
  let invalidVisibility = try executeCalendarGraphQL(
    service: GoogleCalendarGatewayService(config: testConfig(accessMode: .readWrite), provider: FailingWriteProvider()),
    query: """
    mutation {
      createEvent(
        calendarId: "personal",
        summary: "Planning",
        start: "2026-07-01T09:00:00Z",
        end: "2026-07-01T09:30:00Z",
        visibility: "friends"
      ) { id }
    }
    """
  )
  let invalidTransparency = try executeCalendarGraphQL(
    service: GoogleCalendarGatewayService(config: testConfig(accessMode: .readWrite), provider: FailingWriteProvider()),
    query: """
    mutation {
      createEvent(
        calendarId: "personal",
        summary: "Planning",
        start: "2026-07-01T09:00:00Z",
        end: "2026-07-01T09:30:00Z",
        transparency: "busy"
      ) { id }
    }
    """
  )

  #expect(invalidVisibility.exitCode == .graphqlExecutionError)
  #expect(invalidTransparency.exitCode == .graphqlExecutionError)
  let visibilityErrors = try #require(invalidVisibility.body["errors"] as? [[String: Any]])
  let transparencyErrors = try #require(invalidTransparency.body["errors"] as? [[String: Any]])
  #expect(visibilityErrors.first?["message"] as? String == "GraphQL argument visibility is invalid")
  #expect(transparencyErrors.first?["message"] as? String == "GraphQL argument transparency is invalid")
}

@Test func eventMetadataValidationRunsBeforeProviderCall() throws {
  let blankRequestId = try requireGoogleCalendarGatewayError {
    _ = try GoogleCalendarGatewayService(
      config: testConfig(accessMode: .readWrite),
      provider: FailingWriteProvider()
    ).updateEvent(input: CalendarEventInput(
      accountId: "personal",
      eventId: "event-1",
      createConference: true,
      conferenceRequestId: " "
    ))
  }

  let missingCreateFlag = try requireGoogleCalendarGatewayError {
    _ = try GoogleCalendarGatewayService(
      config: testConfig(accessMode: .readWrite),
      provider: FailingWriteProvider()
    ).createCalendarEvent(input: CalendarEventInput(
      accountId: "personal",
      start: "2026-07-01T09:00:00Z",
      end: "2026-07-01T09:30:00Z",
      conferenceRequestId: "request-1"
    ))
  }

  #expect(blankRequestId.message == "conferenceRequestId must be a non-empty string")
  #expect(missingCreateFlag.message == "conferenceRequestId requires createConference = true")
}
