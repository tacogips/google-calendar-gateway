import Foundation

public struct CalendarCapabilities: Equatable {
  public let canRead: Bool
  public let canWriteEvents: Bool
  public let configuredAccessMode: CalendarAccessMode
  public let authState: CalendarAuthState

  public init(
    canRead: Bool,
    canWriteEvents: Bool,
    configuredAccessMode: CalendarAccessMode,
    authState: CalendarAuthState
  ) {
    self.canRead = canRead
    self.canWriteEvents = canWriteEvents
    self.configuredAccessMode = configuredAccessMode
    self.authState = authState
  }

  public var graphQLObject: [String: Any] {
    [
      "canRead": canRead,
      "canWriteEvents": canWriteEvents,
      "configuredAccessMode": configuredAccessMode.graphQLValue,
      "authState": authState.rawValue
    ]
  }
}

public struct CalendarInfo: Equatable {
  public let id: String
  public let displayName: String?
  public let provider: CalendarProvider
  public let emailAddress: String
  public let calendarIds: [String]
  public let defaultCalendarId: String
  public let defaultTimeZone: String?
  public let capabilities: CalendarCapabilities

  public init(
    id: String,
    displayName: String? = nil,
    provider: CalendarProvider,
    emailAddress: String,
    calendarIds: [String],
    defaultCalendarId: String,
    defaultTimeZone: String?,
    capabilities: CalendarCapabilities
  ) {
    self.id = id
    self.displayName = displayName
    self.provider = provider
    self.emailAddress = emailAddress
    self.calendarIds = calendarIds
    self.defaultCalendarId = defaultCalendarId
    self.defaultTimeZone = defaultTimeZone
    self.capabilities = capabilities
  }

  public var graphQLObject: [String: Any] {
    [
      "id": id,
      "displayName": displayName as Any? ?? NSNull(),
      "provider": provider.graphQLValue,
      "emailAddress": emailAddress,
      "calendarIds": calendarIds,
      "defaultCalendarId": defaultCalendarId,
      "defaultTimeZone": defaultTimeZone as Any? ?? NSNull(),
      "capabilities": capabilities.graphQLObject
    ]
  }
}

public struct ProviderCalendarInfo {
  public let id: String
  public let summary: String?
  public let description: String?
  public let timeZone: String?
  public let accessRole: String?
  public let isPrimary: Bool
  public let isSelected: Bool
  public let backgroundColor: String?
  public let foregroundColor: String?
  public let providerMetadata: [String: Any]

  public init(
    id: String,
    summary: String? = nil,
    description: String? = nil,
    timeZone: String? = nil,
    accessRole: String? = nil,
    isPrimary: Bool = false,
    isSelected: Bool = false,
    backgroundColor: String? = nil,
    foregroundColor: String? = nil,
    providerMetadata: [String: Any] = [:]
  ) {
    self.id = id
    self.summary = summary
    self.description = description
    self.timeZone = timeZone
    self.accessRole = accessRole
    self.isPrimary = isPrimary
    self.isSelected = isSelected
    self.backgroundColor = backgroundColor
    self.foregroundColor = foregroundColor
    self.providerMetadata = providerMetadata
  }

  public var graphQLObject: [String: Any] {
    [
      "id": id,
      "summary": summary as Any? ?? NSNull(),
      "description": description as Any? ?? NSNull(),
      "timeZone": timeZone as Any? ?? NSNull(),
      "accessRole": accessRole as Any? ?? NSNull(),
      "isPrimary": isPrimary,
      "isSelected": isSelected,
      "backgroundColor": backgroundColor as Any? ?? NSNull(),
      "foregroundColor": foregroundColor as Any? ?? NSNull(),
      "provider": providerMetadata
    ]
  }

  static func fromGoogle(_ object: [String: Any]) -> ProviderCalendarInfo? {
    guard let id = nonBlank(object["id"] as? String) else {
      return nil
    }
    return ProviderCalendarInfo(
      id: id,
      summary: nonBlank(object["summary"] as? String),
      description: nonBlank(object["description"] as? String),
      timeZone: nonBlank(object["timeZone"] as? String),
      accessRole: nonBlank(object["accessRole"] as? String),
      isPrimary: object["primary"] as? Bool ?? false,
      isSelected: object["selected"] as? Bool ?? false,
      backgroundColor: nonBlank(object["backgroundColor"] as? String),
      foregroundColor: nonBlank(object["foregroundColor"] as? String),
      providerMetadata: ["google": object]
    )
  }
}

public struct CalendarEventDateTime: Equatable {
  public let date: String?
  public let dateTime: String?
  public let timeZone: String?

  public init(date: String? = nil, dateTime: String? = nil, timeZone: String? = nil) {
    self.date = date
    self.dateTime = dateTime
    self.timeZone = timeZone
  }

  public var graphQLObject: [String: Any] {
    [
      "date": date as Any? ?? NSNull(),
      "dateTime": dateTime as Any? ?? NSNull(),
      "timeZone": timeZone as Any? ?? NSNull()
    ]
  }

  static func fromGoogle(_ value: Any?) -> CalendarEventDateTime? {
    guard let object = value as? [String: Any] else {
      return nil
    }
    return CalendarEventDateTime(
      date: nonBlank(object["date"] as? String),
      dateTime: nonBlank(object["dateTime"] as? String),
      timeZone: nonBlank(object["timeZone"] as? String)
    )
  }
}

public struct CalendarEventParticipant: Equatable {
  public let email: String?
  public let displayName: String?
  public let responseStatus: String?
  public let isSelf: Bool

  public init(
    email: String? = nil,
    displayName: String? = nil,
    responseStatus: String? = nil,
    isSelf: Bool = false
  ) {
    self.email = email
    self.displayName = displayName
    self.responseStatus = responseStatus
    self.isSelf = isSelf
  }

  public var graphQLObject: [String: Any] {
    [
      "email": email as Any? ?? NSNull(),
      "displayName": displayName as Any? ?? NSNull(),
      "responseStatus": responseStatus as Any? ?? NSNull(),
      "isSelf": isSelf
    ]
  }

  static func fromGoogle(_ value: Any?) -> CalendarEventParticipant? {
    guard let object = value as? [String: Any] else {
      return nil
    }
    return CalendarEventParticipant(
      email: nonBlank(object["email"] as? String),
      displayName: nonBlank(object["displayName"] as? String),
      responseStatus: nonBlank(object["responseStatus"] as? String),
      isSelf: object["self"] as? Bool ?? false
    )
  }
}

public struct CalendarEventReminder: Equatable, Sendable {
  public let method: CalendarEventReminderMethod
  public let minutes: Int

  public init(method: CalendarEventReminderMethod, minutes: Int) {
    self.method = method
    self.minutes = minutes
  }

  public var graphQLObject: [String: Any] {
    [
      "method": method.rawValue,
      "minutes": minutes
    ]
  }

  static func fromGoogle(_ value: Any?) -> CalendarEventReminder? {
    guard let object = value as? [String: Any],
          let methodValue = nonBlank(object["method"] as? String),
          let method = CalendarEventReminderMethod(rawValue: methodValue),
          let minutes = intValue(object["minutes"]) else {
      return nil
    }
    return CalendarEventReminder(method: method, minutes: minutes)
  }
}

public struct CalendarEventReminders: Equatable, Sendable {
  public let useDefault: Bool?
  public let overrides: [CalendarEventReminder]

  public init(useDefault: Bool? = nil, overrides: [CalendarEventReminder] = []) {
    self.useDefault = useDefault
    self.overrides = overrides
  }

  public var graphQLObject: [String: Any] {
    [
      "useDefault": useDefault as Any? ?? NSNull(),
      "overrides": overrides.map(\.graphQLObject)
    ]
  }

  static func fromGoogle(_ value: Any?) -> CalendarEventReminders? {
    guard let object = value as? [String: Any] else {
      return nil
    }
    return CalendarEventReminders(
      useDefault: object["useDefault"] as? Bool,
      overrides: (object["overrides"] as? [Any] ?? []).compactMap(CalendarEventReminder.fromGoogle)
    )
  }
}

public struct CalendarConferenceEntryPoint: Equatable, Sendable {
  public let entryPointType: String?
  public let uri: String?
  public let label: String?

  public init(entryPointType: String? = nil, uri: String? = nil, label: String? = nil) {
    self.entryPointType = entryPointType
    self.uri = uri
    self.label = label
  }

  public var graphQLObject: [String: Any] {
    [
      "entryPointType": entryPointType as Any? ?? NSNull(),
      "uri": uri as Any? ?? NSNull(),
      "label": label as Any? ?? NSNull()
    ]
  }

  static func fromGoogle(_ value: Any?) -> CalendarConferenceEntryPoint? {
    guard let object = value as? [String: Any] else {
      return nil
    }
    return CalendarConferenceEntryPoint(
      entryPointType: nonBlank(object["entryPointType"] as? String),
      uri: nonBlank(object["uri"] as? String),
      label: nonBlank(object["label"] as? String)
    )
  }
}

public struct CalendarConferenceData: Equatable, Sendable {
  public let conferenceId: String?
  public let solutionType: String?
  public let solutionName: String?
  public let createRequestStatus: String?
  public let entryPoints: [CalendarConferenceEntryPoint]

  public init(
    conferenceId: String? = nil,
    solutionType: String? = nil,
    solutionName: String? = nil,
    createRequestStatus: String? = nil,
    entryPoints: [CalendarConferenceEntryPoint] = []
  ) {
    self.conferenceId = conferenceId
    self.solutionType = solutionType
    self.solutionName = solutionName
    self.createRequestStatus = createRequestStatus
    self.entryPoints = entryPoints
  }

  public var graphQLObject: [String: Any] {
    [
      "conferenceId": conferenceId as Any? ?? NSNull(),
      "solutionType": solutionType as Any? ?? NSNull(),
      "solutionName": solutionName as Any? ?? NSNull(),
      "createRequestStatus": createRequestStatus as Any? ?? NSNull(),
      "entryPoints": entryPoints.map(\.graphQLObject)
    ]
  }

  static func fromGoogle(_ value: Any?) -> CalendarConferenceData? {
    guard let object = value as? [String: Any] else {
      return nil
    }
    let solution = object["conferenceSolution"] as? [String: Any] ?? [:]
    let solutionKey = solution["key"] as? [String: Any] ?? [:]
    let createRequest = object["createRequest"] as? [String: Any] ?? [:]
    let status = createRequest["status"] as? [String: Any] ?? [:]
    return CalendarConferenceData(
      conferenceId: nonBlank(object["conferenceId"] as? String),
      solutionType: nonBlank(solutionKey["type"] as? String),
      solutionName: nonBlank(solution["name"] as? String),
      createRequestStatus: nonBlank(status["statusCode"] as? String),
      entryPoints: (object["entryPoints"] as? [Any] ?? []).compactMap(CalendarConferenceEntryPoint.fromGoogle)
    )
  }
}

public struct CalendarEvent {
  public let id: String?
  public let accountId: String
  public let calendarId: String
  public let status: String?
  public let summary: String?
  public let description: String?
  public let location: String?
  public let colorId: String?
  public let visibility: CalendarEventVisibility?
  public let transparency: CalendarEventTransparency?
  public let htmlLink: String?
  public let hangoutLink: String?
  public let created: String?
  public let updated: String?
  public let start: CalendarEventDateTime?
  public let end: CalendarEventDateTime?
  public let attendees: [CalendarEventParticipant]
  public let organizer: CalendarEventParticipant?
  public let creator: CalendarEventParticipant?
  public let recurrenceRules: [String]
  public let recurringEventId: String?
  public let reminders: CalendarEventReminders?
  public let conferenceData: CalendarConferenceData?
  public let providerMetadata: [String: Any]

  public init(
    id: String? = nil,
    accountId: String,
    calendarId: String,
    status: String? = nil,
    summary: String? = nil,
    description: String? = nil,
    location: String? = nil,
    colorId: String? = nil,
    visibility: CalendarEventVisibility? = nil,
    transparency: CalendarEventTransparency? = nil,
    htmlLink: String? = nil,
    hangoutLink: String? = nil,
    created: String? = nil,
    updated: String? = nil,
    start: CalendarEventDateTime? = nil,
    end: CalendarEventDateTime? = nil,
    attendees: [CalendarEventParticipant] = [],
    organizer: CalendarEventParticipant? = nil,
    creator: CalendarEventParticipant? = nil,
    recurrenceRules: [String] = [],
    recurringEventId: String? = nil,
    reminders: CalendarEventReminders? = nil,
    conferenceData: CalendarConferenceData? = nil,
    providerMetadata: [String: Any] = [:]
  ) {
    self.id = id
    self.accountId = accountId
    self.calendarId = calendarId
    self.status = status
    self.summary = summary
    self.description = description
    self.location = location
    self.colorId = colorId
    self.visibility = visibility
    self.transparency = transparency
    self.htmlLink = htmlLink
    self.hangoutLink = hangoutLink
    self.created = created
    self.updated = updated
    self.start = start
    self.end = end
    self.attendees = attendees
    self.organizer = organizer
    self.creator = creator
    self.recurrenceRules = recurrenceRules
    self.recurringEventId = recurringEventId
    self.reminders = reminders
    self.conferenceData = conferenceData
    self.providerMetadata = providerMetadata
  }

  public var graphQLObject: [String: Any] {
    [
      "id": id as Any? ?? NSNull(),
      "accountId": accountId,
      "calendarId": calendarId,
      "status": status as Any? ?? NSNull(),
      "summary": summary as Any? ?? NSNull(),
      "description": description as Any? ?? NSNull(),
      "location": location as Any? ?? NSNull(),
      "colorId": colorId as Any? ?? NSNull(),
      "visibility": visibility?.rawValue as Any? ?? NSNull(),
      "transparency": transparency?.rawValue as Any? ?? NSNull(),
      "htmlLink": htmlLink as Any? ?? NSNull(),
      "hangoutLink": hangoutLink as Any? ?? NSNull(),
      "created": created as Any? ?? NSNull(),
      "updated": updated as Any? ?? NSNull(),
      "start": start?.graphQLObject as Any? ?? NSNull(),
      "end": end?.graphQLObject as Any? ?? NSNull(),
      "attendees": attendees.map(\.graphQLObject),
      "organizer": organizer?.graphQLObject as Any? ?? NSNull(),
      "creator": creator?.graphQLObject as Any? ?? NSNull(),
      "recurrenceRules": recurrenceRules,
      "recurringEventId": recurringEventId as Any? ?? NSNull(),
      "reminders": reminders?.graphQLObject as Any? ?? NSNull(),
      "conferenceData": conferenceData?.graphQLObject as Any? ?? NSNull(),
      "provider": providerMetadata
    ]
  }

  static func fromGoogle(_ object: [String: Any], accountId: String, calendarId: String) -> CalendarEvent {
    CalendarEvent(
      id: nonBlank(object["id"] as? String),
      accountId: accountId,
      calendarId: calendarId,
      status: nonBlank(object["status"] as? String),
      summary: nonBlank(object["summary"] as? String),
      description: nonBlank(object["description"] as? String),
      location: nonBlank(object["location"] as? String),
      colorId: nonBlank(object["colorId"] as? String),
      visibility: CalendarEventVisibility(rawValue: nonBlank(object["visibility"] as? String) ?? ""),
      transparency: CalendarEventTransparency(rawValue: nonBlank(object["transparency"] as? String) ?? ""),
      htmlLink: nonBlank(object["htmlLink"] as? String),
      hangoutLink: nonBlank(object["hangoutLink"] as? String),
      created: nonBlank(object["created"] as? String),
      updated: nonBlank(object["updated"] as? String),
      start: CalendarEventDateTime.fromGoogle(object["start"]),
      end: CalendarEventDateTime.fromGoogle(object["end"]),
      attendees: (object["attendees"] as? [Any] ?? []).compactMap(CalendarEventParticipant.fromGoogle),
      organizer: CalendarEventParticipant.fromGoogle(object["organizer"]),
      creator: CalendarEventParticipant.fromGoogle(object["creator"]),
      recurrenceRules: object["recurrence"] as? [String] ?? [],
      recurringEventId: nonBlank(object["recurringEventId"] as? String),
      reminders: CalendarEventReminders.fromGoogle(object["reminders"]),
      conferenceData: CalendarConferenceData.fromGoogle(object["conferenceData"]),
      providerMetadata: ["google": object]
    )
  }
}

public struct CalendarEventConnection {
  public let accountId: String
  public let calendarId: String
  public let events: [CalendarEvent]
  public let nextPageToken: String?
  public let nextSyncToken: String?

  public init(
    accountId: String,
    calendarId: String,
    events: [CalendarEvent],
    nextPageToken: String? = nil,
    nextSyncToken: String? = nil
  ) {
    self.accountId = accountId
    self.calendarId = calendarId
    self.events = events
    self.nextPageToken = nextPageToken
    self.nextSyncToken = nextSyncToken
  }

  public var graphQLObject: [String: Any] {
    [
      "accountId": accountId,
      "calendarId": calendarId,
      "events": events.map(\.graphQLObject),
      "nextCursor": nextPageToken.map(calendarEventCursor) as Any? ?? NSNull(),
      "nextPageToken": nextPageToken as Any? ?? NSNull(),
      "nextSyncToken": nextSyncToken as Any? ?? NSNull()
    ]
  }
}

public struct CalendarFreeBusyInterval: Equatable {
  public let start: String
  public let end: String

  public init(start: String, end: String) {
    self.start = start
    self.end = end
  }

  public var graphQLObject: [String: Any] {
    [
      "start": start,
      "end": end
    ]
  }

  static func fromGoogle(_ value: Any?) -> CalendarFreeBusyInterval? {
    guard let object = value as? [String: Any],
          let start = nonBlank(object["start"] as? String),
          let end = nonBlank(object["end"] as? String) else {
      return nil
    }
    return CalendarFreeBusyInterval(start: start, end: end)
  }
}

public struct CalendarProviderError: Equatable {
  public let domain: String?
  public let reason: String?

  public init(domain: String? = nil, reason: String? = nil) {
    self.domain = domain
    self.reason = reason
  }

  public var graphQLObject: [String: Any] {
    [
      "domain": domain as Any? ?? NSNull(),
      "reason": reason as Any? ?? NSNull()
    ]
  }

  static func fromGoogle(_ value: Any?) -> CalendarProviderError? {
    guard let object = value as? [String: Any] else {
      return nil
    }
    return CalendarProviderError(
      domain: nonBlank(object["domain"] as? String),
      reason: nonBlank(object["reason"] as? String)
    )
  }
}

public struct CalendarFreeBusyCalendar {
  public let id: String
  public let busy: [CalendarFreeBusyInterval]
  public let errors: [CalendarProviderError]
  public let providerMetadata: [String: Any]

  public init(
    id: String,
    busy: [CalendarFreeBusyInterval] = [],
    errors: [CalendarProviderError] = [],
    providerMetadata: [String: Any] = [:]
  ) {
    self.id = id
    self.busy = busy
    self.errors = errors
    self.providerMetadata = providerMetadata
  }

  public var graphQLObject: [String: Any] {
    [
      "id": id,
      "busy": busy.map(\.graphQLObject),
      "errors": errors.map(\.graphQLObject),
      "provider": providerMetadata
    ]
  }

  static func fromGoogle(id: String, object: [String: Any]) -> CalendarFreeBusyCalendar {
    CalendarFreeBusyCalendar(
      id: id,
      busy: (object["busy"] as? [Any] ?? []).compactMap(CalendarFreeBusyInterval.fromGoogle),
      errors: (object["errors"] as? [Any] ?? []).compactMap(CalendarProviderError.fromGoogle),
      providerMetadata: ["google": object]
    )
  }
}

public struct CalendarFreeBusyGroup {
  public let id: String
  public let calendars: [String]
  public let errors: [CalendarProviderError]
  public let providerMetadata: [String: Any]

  public init(
    id: String,
    calendars: [String] = [],
    errors: [CalendarProviderError] = [],
    providerMetadata: [String: Any] = [:]
  ) {
    self.id = id
    self.calendars = calendars
    self.errors = errors
    self.providerMetadata = providerMetadata
  }

  public var graphQLObject: [String: Any] {
    [
      "id": id,
      "calendars": calendars,
      "errors": errors.map(\.graphQLObject),
      "provider": providerMetadata
    ]
  }

  static func fromGoogle(id: String, object: [String: Any]) -> CalendarFreeBusyGroup {
    CalendarFreeBusyGroup(
      id: id,
      calendars: object["calendars"] as? [String] ?? [],
      errors: (object["errors"] as? [Any] ?? []).compactMap(CalendarProviderError.fromGoogle),
      providerMetadata: ["google": object]
    )
  }
}

public struct CalendarFreeBusyResponse {
  public let accountId: String
  public let timeMin: String
  public let timeMax: String
  public let calendars: [CalendarFreeBusyCalendar]
  public let groups: [CalendarFreeBusyGroup]
  public let providerMetadata: [String: Any]

  public init(
    accountId: String,
    timeMin: String,
    timeMax: String,
    calendars: [CalendarFreeBusyCalendar],
    groups: [CalendarFreeBusyGroup] = [],
    providerMetadata: [String: Any] = [:]
  ) {
    self.accountId = accountId
    self.timeMin = timeMin
    self.timeMax = timeMax
    self.calendars = calendars
    self.groups = groups
    self.providerMetadata = providerMetadata
  }

  public var graphQLObject: [String: Any] {
    [
      "accountId": accountId,
      "timeMin": timeMin,
      "timeMax": timeMax,
      "calendars": calendars.map(\.graphQLObject),
      "groups": groups.map(\.graphQLObject),
      "provider": providerMetadata
    ]
  }

  static func fromGoogle(_ object: [String: Any], accountId: String) -> CalendarFreeBusyResponse {
    let calendarObjects = object["calendars"] as? [String: Any] ?? [:]
    let groupObjects = object["groups"] as? [String: Any] ?? [:]
    return CalendarFreeBusyResponse(
      accountId: accountId,
      timeMin: nonBlank(object["timeMin"] as? String) ?? "",
      timeMax: nonBlank(object["timeMax"] as? String) ?? "",
      calendars: calendarObjects.keys.sorted().compactMap { id in
        guard let calendar = calendarObjects[id] as? [String: Any] else {
          return nil
        }
        return CalendarFreeBusyCalendar.fromGoogle(id: id, object: calendar)
      },
      groups: groupObjects.keys.sorted().compactMap { id in
        guard let group = groupObjects[id] as? [String: Any] else {
          return nil
        }
        return CalendarFreeBusyGroup.fromGoogle(id: id, object: group)
      },
      providerMetadata: ["google": object]
    )
  }
}

func calendarEventCursor(pageToken: String) -> String {
  let object: [String: Any] = [
    "version": 1,
    "pageToken": pageToken
  ]
  guard let data = try? JSONSerialization.data(withJSONObject: object, options: [.sortedKeys]) else {
    return pageToken
  }
  return base64URLString(data)
}

func pageTokenFromCalendarEventCursor(_ cursor: String) throws -> String {
  guard let data = dataFromBase64URLString(cursor),
        let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
        intValue(object["version"]) == 1,
        let pageToken = nonBlank(object["pageToken"] as? String) else {
    throw GoogleCalendarGatewayError(
      "GraphQL argument cursor is invalid",
      code: .invalidArgument,
      exitCode: .graphqlExecutionError
    )
  }
  return pageToken
}
