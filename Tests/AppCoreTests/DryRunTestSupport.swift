import Foundation
@testable import GoogleCalendarGatewayCore

final class RecordingCalendarProvider: CalendarEventProvider {
  struct DeleteCall {
    let calendarId: String
    let eventId: String
    let sendUpdates: String?
  }

  private let fallback = FakeCalendarProvider()

  private(set) var createInputs: [CalendarEventInput] = []
  private(set) var updateInputs: [CalendarEventInput] = []
  private(set) var deleteCalls: [DeleteCall] = []

  func listCalendars(credential: CalendarCredentialConfig) throws -> [ProviderCalendarInfo] {
    try fallback.listCalendars(credential: credential)
  }

  func listEvents(
    account: CalendarAccountConfig,
    credential: CalendarCredentialConfig,
    search: CalendarEventSearch
  ) throws -> CalendarEventConnection {
    try fallback.listEvents(account: account, credential: credential, search: search)
  }

  func getEvent(
    account: CalendarAccountConfig,
    credential: CalendarCredentialConfig,
    calendarId: String,
    eventId: String
  ) throws -> CalendarEvent {
    try fallback.getEvent(account: account, credential: credential, calendarId: calendarId, eventId: eventId)
  }

  func queryFreeBusy(
    account: CalendarAccountConfig,
    credential: CalendarCredentialConfig,
    query: CalendarFreeBusyQuery
  ) throws -> CalendarFreeBusyResponse {
    try fallback.queryFreeBusy(account: account, credential: credential, query: query)
  }

  func createEvent(
    account: CalendarAccountConfig,
    credential: CalendarCredentialConfig,
    input: CalendarEventInput
  ) throws -> CalendarEvent {
    createInputs.append(input)
    return try fallback.createEvent(account: account, credential: credential, input: input)
  }

  func updateEvent(
    account: CalendarAccountConfig,
    credential: CalendarCredentialConfig,
    input: CalendarEventInput
  ) throws -> CalendarEvent {
    updateInputs.append(input)
    return try fallback.updateEvent(account: account, credential: credential, input: input)
  }

  func deleteEvent(
    account: CalendarAccountConfig,
    credential: CalendarCredentialConfig,
    calendarId: String,
    eventId: String,
    sendUpdates: String?
  ) throws -> [String: Any] {
    deleteCalls.append(DeleteCall(calendarId: calendarId, eventId: eventId, sendUpdates: sendUpdates))
    return try fallback.deleteEvent(
      account: account,
      credential: credential,
      calendarId: calendarId,
      eventId: eventId,
      sendUpdates: sendUpdates
    )
  }

  func executeCalendarAPI(
    credential: CalendarCredentialConfig,
    request: CalendarRawAPIRequest
  ) throws -> [String: Any] {
    try fallback.executeCalendarAPI(credential: credential, request: request)
  }
}

func decodedJSONObject(_ source: String) throws -> [String: Any] {
  try JSONSerialization.jsonObject(with: Data(source.utf8)) as? [String: Any] ?? [:]
}

func sortedJSONData(_ object: [String: Any]) throws -> Data {
  try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
}
