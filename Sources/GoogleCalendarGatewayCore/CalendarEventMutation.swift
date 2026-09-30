import Foundation

public enum CalendarEventMutationOperation: String, Sendable {
  case createEvent
  case updateEvent
  case deleteEvent
}

public struct CalendarEventDeletionPreview: Sendable {
  public let eventId: String
  public let sendUpdates: String?
  public var wouldDelete: Bool { true }
  public var deleted: Bool { false }

  init(eventId: String, sendUpdates: String?) {
    self.eventId = eventId
    self.sendUpdates = sendUpdates
  }
}

public enum CalendarEventMutationPreviewPayload: Sendable {
  case create(validatedInput: CalendarEventInput)
  case update(validatedInput: CalendarEventInput)
  case delete(target: CalendarEventDeletionPreview)
}

public struct CalendarEventMutationPreview: Sendable {
  public let accountId: String
  public let resolvedCalendarId: String
  public let payload: CalendarEventMutationPreviewPayload

  public var operation: CalendarEventMutationOperation {
    switch payload {
    case .create:
      return .createEvent
    case .update:
      return .updateEvent
    case .delete:
      return .deleteEvent
    }
  }

  public var jsonObject: [String: Any] {
    switch payload {
    case .create(let validatedInput), .update(let validatedInput):
      return [
        "accountId": accountId,
        "dryRun": true,
        "operation": operation.rawValue,
        "resolvedCalendarId": resolvedCalendarId,
        "validatedInput": validatedInput.mutationPreviewJSONObject
      ]
    case .delete(let target):
      return [
        "accountId": accountId,
        "deleted": target.deleted,
        "dryRun": true,
        "eventId": target.eventId,
        "operation": operation.rawValue,
        "resolvedCalendarId": resolvedCalendarId,
        "sendUpdates": target.sendUpdates as Any? ?? NSNull(),
        "wouldDelete": target.wouldDelete
      ]
    }
  }

  init(
    accountId: String,
    resolvedCalendarId: String,
    payload: CalendarEventMutationPreviewPayload
  ) {
    switch payload {
    case .create(let input), .update(let input):
      precondition(accountId == input.accountId)
    case .delete:
      break
    }
    self.accountId = accountId
    self.resolvedCalendarId = resolvedCalendarId
    self.payload = payload
  }
}

public enum CalendarEventMutationResult {
  case event(CalendarEvent)
  case deletion([String: Any])
  case preview(CalendarEventMutationPreview)

  public var jsonObject: [String: Any] {
    switch self {
    case .event(let event):
      return event.graphQLObject
    case .deletion(let deletion):
      return deletion
    case .preview(let preview):
      return preview.jsonObject
    }
  }
}

private extension CalendarEventInput {
  var mutationPreviewJSONObject: [String: Any] {
    [
      "accountId": accountId,
      "attendeeEmails": attendeeEmails,
      "calendarId": calendarId as Any? ?? NSNull(),
      "colorId": colorId as Any? ?? NSNull(),
      "conferenceRequestId": conferenceRequestId as Any? ?? NSNull(),
      "createConference": createConference,
      "description": description as Any? ?? NSNull(),
      "end": end as Any? ?? NSNull(),
      "eventId": eventId as Any? ?? NSNull(),
      "location": location as Any? ?? NSNull(),
      "recurrenceRules": recurrenceRules,
      "reminderOverrides": reminderOverrides.map { reminder in
        ["method": reminder.method.rawValue, "minutes": reminder.minutes]
      },
      "reminderUseDefault": reminderUseDefault as Any? ?? NSNull(),
      "sendUpdates": sendUpdates as Any? ?? NSNull(),
      "start": start as Any? ?? NSNull(),
      "summary": summary as Any? ?? NSNull(),
      "timeZone": timeZone as Any? ?? NSNull(),
      "transparency": transparency?.rawValue as Any? ?? NSNull(),
      "visibility": visibility?.rawValue as Any? ?? NSNull()
    ]
  }
}
