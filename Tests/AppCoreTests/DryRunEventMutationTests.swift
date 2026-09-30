import Foundation
import Testing
@testable import GoogleCalendarGatewayCore

@Suite("DryRun Event Mutations")
struct DryRunEventMutationTests {
  @Test("DryRun service previews are canonical and perform zero writes")
  func servicePreviews() throws {
    let provider = RecordingCalendarProvider()
    let service = GoogleCalendarGatewayService(config: testConfig(accessMode: .readWrite), provider: provider)
    let createInput = CalendarEventInput(
      accountId: "personal",
      calendarId: " team@example.com ",
      eventId: " optional-create-id ",
      summary: "Planning",
      description: "",
      location: "Room 1",
      colorId: "7",
      visibility: .private,
      transparency: .transparent,
      start: "2026-07-01T09:00:00Z",
      end: "2026-07-01T09:30:00Z",
      timeZone: "UTC",
      attendeeEmails: ["first@example.com", "second@example.com"],
      recurrenceRules: ["RRULE:FREQ=WEEKLY;COUNT=2"],
      reminderUseDefault: false,
      reminderOverrides: [
        CalendarEventReminder(method: .popup, minutes: 30),
        CalendarEventReminder(method: .email, minutes: 1_440)
      ],
      createConference: true,
      conferenceRequestId: "request-1",
      sendUpdates: " externalOnly "
    )

    let create = try service.createEventMutation(input: createInput, dryRun: true).jsonObject
    let validated = try #require(create["validatedInput"] as? [String: Any])
    #expect(Set(create.keys) == ["accountId", "dryRun", "operation", "resolvedCalendarId", "validatedInput"])
    #expect(Set(validated.keys) == [
      "accountId", "attendeeEmails", "calendarId", "colorId", "conferenceRequestId", "createConference",
      "description", "end", "eventId", "location", "recurrenceRules", "reminderOverrides",
      "reminderUseDefault", "sendUpdates", "start", "summary", "timeZone", "transparency", "visibility"
    ])
    #expect(create["operation"] as? String == "createEvent")
    #expect(create["resolvedCalendarId"] as? String == "team@example.com")
    #expect(validated["calendarId"] as? String == "team@example.com")
    #expect(validated["eventId"] as? String == "optional-create-id")
    #expect(validated["description"] as? String == "")
    #expect(validated["visibility"] as? String == "private")
    #expect(validated["transparency"] as? String == "transparent")
    #expect(validated["reminderUseDefault"] as? Bool == false)
    #expect(validated["createConference"] as? Bool == true)
    #expect(validated["sendUpdates"] as? String == " externalOnly ")
    #expect(validated["attendeeEmails"] as? [String] == ["first@example.com", "second@example.com"])
    let reminders = try #require(validated["reminderOverrides"] as? [[String: Any]])
    #expect(reminders.map { $0["method"] as? String } == ["popup", "email"])
    #expect(reminders.map { $0["minutes"] as? Int } == [30, 1_440])

    let update = try service.updateEventMutation(input: CalendarEventInput(
      accountId: "personal",
      eventId: " update-id ",
      summary: "Updated"
    ), dryRun: true).jsonObject
    let updateInput = try #require(update["validatedInput"] as? [String: Any])
    #expect(update["operation"] as? String == "updateEvent")
    #expect(updateInput["eventId"] as? String == "update-id")
    #expect(updateInput["calendarId"] is NSNull)
    #expect(updateInput["attendeeEmails"] as? [String] == [])
    #expect(updateInput["createConference"] as? Bool == false)

    let deletion = try service.deleteEventMutation(
      accountId: "personal",
      eventId: " delete-id ",
      dryRun: true
    ).jsonObject
    #expect(Set(deletion.keys) == [
      "accountId", "deleted", "dryRun", "eventId", "operation", "resolvedCalendarId", "sendUpdates", "wouldDelete"
    ])
    #expect(deletion["eventId"] as? String == "delete-id")
    #expect(deletion["resolvedCalendarId"] as? String == "primary")
    #expect(deletion["sendUpdates"] is NSNull)
    #expect(deletion["wouldDelete"] as? Bool == true)
    #expect(deletion["deleted"] as? Bool == false)

    let repeatedCreate = try service.createEventMutation(input: createInput, dryRun: true).jsonObject
    #expect(provider.createInputs.isEmpty)
    #expect(provider.updateInputs.isEmpty)
    #expect(provider.deleteCalls.isEmpty)
    #expect(try sortedJSONData(create) == sortedJSONData(repeatedCreate))
  }

  @Test("DryRun preserves write gate, validation, and live compatibility")
  func serviceOrderingAndLiveCompatibility() throws {
    let readOnlyProvider = RecordingCalendarProvider()
    let readOnly = GoogleCalendarGatewayService(config: testConfig(), provider: readOnlyProvider)
    let writeError = try requireGoogleCalendarGatewayError {
      _ = try readOnly.createEventMutation(input: CalendarEventInput(
        accountId: "personal",
        start: "bad",
        end: "bad"
      ), dryRun: true)
    }
    #expect(writeError.code == .writeDisabled)
    #expect(readOnlyProvider.createInputs.isEmpty)

    let provider = RecordingCalendarProvider()
    let service = GoogleCalendarGatewayService(config: testConfig(accessMode: .readWrite), provider: provider)
    let invalidError = try requireGoogleCalendarGatewayError {
      _ = try service.updateEventMutation(input: CalendarEventInput(
        accountId: "personal",
        eventId: "",
        summary: "Invalid"
      ), dryRun: true)
    }
    #expect(invalidError.code == .invalidArgument)
    #expect(provider.updateInputs.isEmpty)

    _ = try service.createEvent(input: CalendarEventInput(
      accountId: "personal",
      start: "2026-07-01T09:00:00Z",
      end: "2026-07-01T09:30:00Z",
      sendUpdates: " none "
    ))
    _ = try service.updateEvent(input: CalendarEventInput(
      accountId: "personal",
      eventId: "event-1",
      summary: "Live"
    ), dryRun: false)
    let liveDelete = try service.deleteEvent(
      accountId: "personal",
      eventId: "event-1",
      sendUpdates: "   ",
      dryRun: false
    )
    #expect(provider.createInputs.count == 1)
    #expect(provider.createInputs[0].sendUpdates == " none ")
    #expect(provider.updateInputs.count == 1)
    #expect(provider.deleteCalls.count == 1)
    #expect(provider.deleteCalls[0].sendUpdates == "   ")
    #expect(liveDelete["deleted"] as? Bool == true)
  }

  @Test("DryRun GraphQL forwards booleans, projects selections, and preserves errors")
  func graphQLTransport() throws {
    let provider = RecordingCalendarProvider()
    let service = GoogleCalendarGatewayService(config: testConfig(accessMode: .readWrite), provider: provider)
    let dryRun = try executeCalendarGraphQL(service: service, query: """
      mutation {
        createEvent(
          calendarId: "personal",
          summary: "Planning",
          start: "2026-07-01T09:00:00Z",
          end: "2026-07-01T09:30:00Z",
          dryRun: true
        ) { dryRun operation validatedInput { summary createConference attendeeEmails } }
      }
      """)
    let data = try #require(dryRun.body["data"] as? [String: Any])
    let preview = try #require(data["createEvent"] as? [String: Any])
    #expect(Set(preview.keys) == ["dryRun", "operation", "validatedInput"])
    #expect(provider.createInputs.isEmpty)

    let updateDryRun = try executeCalendarGraphQL(service: service, query: """
      mutation {
        updateEvent(calendarId: "personal", eventId: "event-1", summary: "Preview", dryRun: true) {
          operation validatedInput { eventId summary }
        }
      }
      """)
    let updateData = try #require(updateDryRun.body["data"] as? [String: Any])
    let updatePreview = try #require(updateData["updateEvent"] as? [String: Any])
    #expect(updatePreview["operation"] as? String == "updateEvent")

    let deleteDryRun = try executeCalendarGraphQL(service: service, query: """
      mutation {
        deleteEvent(calendarId: "personal", eventId: "event-1", dryRun: true) {
          operation eventId wouldDelete deleted
        }
      }
      """)
    let deleteData = try #require(deleteDryRun.body["data"] as? [String: Any])
    let deletePreview = try #require(deleteData["deleteEvent"] as? [String: Any])
    #expect(deletePreview["operation"] as? String == "deleteEvent")
    #expect(provider.updateInputs.isEmpty)
    #expect(provider.deleteCalls.isEmpty)

    _ = try executeCalendarGraphQL(service: service, query: """
      mutation {
        updateEvent(calendarId: "personal", eventId: "event-1", summary: "Live", dryRun: false) { id }
      }
      """)
    _ = try executeCalendarGraphQL(service: service, query: """
      mutation { deleteEvent(calendarId: "personal", eventId: "event-1") { deleted } }
      """)
    #expect(provider.updateInputs.count == 1)
    #expect(provider.deleteCalls.count == 1)

    let invalid = try executeCalendarGraphQL(service: service, query: """
      mutation {
        deleteEvent(calendarId: "personal", eventId: "event-1", dryRun: "true") { dryRun }
      }
      """)
    #expect(invalid.body["data"] is NSNull)
    let errors = try #require(invalid.body["errors"] as? [[String: Any]])
    let extensions = try #require(errors.first?["extensions"] as? [String: Any])
    #expect(extensions["code"] as? String == "INVALID_ARGUMENT")
    #expect(provider.deleteCalls.count == 1)
  }
}
