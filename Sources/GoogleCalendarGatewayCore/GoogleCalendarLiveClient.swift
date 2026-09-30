import Foundation

struct GoogleCalendarLiveClient: CalendarEventProvider {
  func listCalendars(credential: CalendarCredentialConfig) throws -> [ProviderCalendarInfo] {
    let token = try validGoogleCalendarAccessToken(credential: credential, use: .read)
    var calendars: [ProviderCalendarInfo] = []
    var pageToken: String?
    repeat {
      var components = URLComponents(string: "https://www.googleapis.com/calendar/v3/users/me/calendarList")
      components?.queryItems = [
        URLQueryItem(name: "maxResults", value: "250")
      ]
      if let pageToken {
        components?.queryItems?.append(URLQueryItem(name: "pageToken", value: pageToken))
      }
      let object = try performGoogleCalendarJSONRequest(
        url: try requireURL(components?.url),
        accessToken: token,
        context: "Google Calendar calendarList.list failed"
      )
      let items = object["items"] as? [[String: Any]] ?? []
      calendars.append(contentsOf: items.compactMap(ProviderCalendarInfo.fromGoogle))
      pageToken = nonBlank(object["nextPageToken"] as? String)
    } while pageToken != nil
    return calendars
  }

  func listEvents(
    account: CalendarAccountConfig,
    credential: CalendarCredentialConfig,
    search: CalendarEventSearch
  ) throws -> CalendarEventConnection {
    let token = try validGoogleCalendarAccessToken(credential: credential, use: .read)
    let calendarId = search.calendarId ?? account.defaultCalendarId
    var components = URLComponents(
      string: "https://www.googleapis.com/calendar/v3/calendars/\(urlEncodedPathComponent(calendarId))/events"
    )
    components?.queryItems = queryItems(search: search, account: account)
    let object = try performGoogleCalendarJSONRequest(
      url: try requireURL(components?.url),
      accessToken: token,
      context: "Google Calendar events.list failed"
    )
    let items = object["items"] as? [[String: Any]] ?? []
    return CalendarEventConnection(
      accountId: account.id,
      calendarId: calendarId,
      events: items.map { CalendarEvent.fromGoogle($0, accountId: account.id, calendarId: calendarId) },
      nextPageToken: nonBlank(object["nextPageToken"] as? String),
      nextSyncToken: nonBlank(object["nextSyncToken"] as? String)
    )
  }

  func getEvent(
    account: CalendarAccountConfig,
    credential: CalendarCredentialConfig,
    calendarId: String,
    eventId: String
  ) throws -> CalendarEvent {
    let token = try validGoogleCalendarAccessToken(credential: credential, use: .read)
    let url = try requireURL(URL(string: "https://www.googleapis.com/calendar/v3/calendars/\(urlEncodedPathComponent(calendarId))/events/\(urlEncodedPathComponent(eventId))"))
    let object = try performGoogleCalendarJSONRequest(
      url: url,
      accessToken: token,
      context: "Google Calendar events.get failed",
      failureKind: .event
    )
    return CalendarEvent.fromGoogle(object, accountId: account.id, calendarId: calendarId)
  }

  func queryFreeBusy(
    account: CalendarAccountConfig,
    credential: CalendarCredentialConfig,
    query: CalendarFreeBusyQuery
  ) throws -> CalendarFreeBusyResponse {
    let token = try validGoogleCalendarAccessToken(credential: credential, use: .read)
    var request = URLRequest(url: try requireURL(URL(string: "https://www.googleapis.com/calendar/v3/freeBusy")))
    request.httpMethod = "POST"
    request.timeoutInterval = 30
    request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
    request.httpBody = try freeBusyBodyData(query)
    let object = try performGoogleCalendarJSONRequest(request: request, context: "Google Calendar freebusy.query failed")
    return CalendarFreeBusyResponse.fromGoogle(object, accountId: account.id)
  }

  func createEvent(
    account: CalendarAccountConfig,
    credential: CalendarCredentialConfig,
    input: CalendarEventInput
  ) throws -> CalendarEvent {
    let token = try validGoogleCalendarAccessToken(credential: credential, use: .write)
    let calendarId = input.calendarId ?? account.defaultCalendarId
    var components = eventCollectionComponents(calendarId: calendarId)
    components.queryItems = eventMutationQueryItems(input: input)
    var request = URLRequest(url: try requireURL(components.url))
    request.httpMethod = "POST"
    request.timeoutInterval = 30
    request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
    request.httpBody = try eventBodyData(input: input, requireStartEnd: true)
    let object = try performGoogleCalendarJSONRequest(request: request, context: "Google Calendar events.insert failed")
    return CalendarEvent.fromGoogle(object, accountId: account.id, calendarId: calendarId)
  }

  func updateEvent(
    account: CalendarAccountConfig,
    credential: CalendarCredentialConfig,
    input: CalendarEventInput
  ) throws -> CalendarEvent {
    let token = try validGoogleCalendarAccessToken(credential: credential, use: .write)
    let calendarId = input.calendarId ?? account.defaultCalendarId
    let eventId = try requireNonBlank(input.eventId, name: "eventId")
    var components = eventItemComponents(calendarId: calendarId, eventId: eventId)
    components.queryItems = eventMutationQueryItems(input: input)
    var request = URLRequest(url: try requireURL(components.url))
    request.httpMethod = "PATCH"
    request.timeoutInterval = 30
    request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
    request.httpBody = try eventBodyData(input: input, requireStartEnd: false)
    let object = try performGoogleCalendarJSONRequest(
      request: request,
      context: "Google Calendar events.patch failed",
      failureKind: .event
    )
    return CalendarEvent.fromGoogle(object, accountId: account.id, calendarId: calendarId)
  }

  func deleteEvent(
    account: CalendarAccountConfig,
    credential: CalendarCredentialConfig,
    calendarId: String,
    eventId: String,
    sendUpdates: String?
  ) throws -> [String: Any] {
    let token = try validGoogleCalendarAccessToken(credential: credential, use: .write)
    let eventId = try requireNonBlank(eventId, name: "eventId")
    var components = eventItemComponents(calendarId: calendarId, eventId: eventId)
    components.queryItems = sendUpdatesQueryItems(sendUpdates)
    var request = URLRequest(url: try requireURL(components.url))
    request.httpMethod = "DELETE"
    request.timeoutInterval = 30
    request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
    _ = try performGoogleCalendarHTTPRequest(
      request,
      context: "Google Calendar events.delete failed",
      failureKind: .event
    )
    return [
      "accountId": account.id,
      "calendarId": calendarId,
      "eventId": eventId,
      "deleted": true
    ]
  }

  func executeCalendarAPI(
    credential: CalendarCredentialConfig,
    request: CalendarRawAPIRequest
  ) throws -> [String: Any] {
    let token = try validGoogleCalendarAccessToken(credential: credential, use: rawCalendarAPITokenUse(for: request))
    var components = URLComponents(string: "https://www.googleapis.com/calendar/v3\(request.path)")
    if !request.queryItems.isEmpty {
      components?.queryItems = request.queryItems.map { name, value in
        URLQueryItem(name: name, value: value)
      }
    }
    var urlRequest = URLRequest(url: try requireURL(components?.url))
    urlRequest.httpMethod = request.method.rawValue
    urlRequest.timeoutInterval = 30
    urlRequest.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
    if let bodyJSON = nonBlank(request.bodyJSON) {
      _ = try parseRawCalendarAPIJSONBody(bodyJSON)
      urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
      urlRequest.httpBody = Data(bodyJSON.utf8)
    }
    let response = try performGoogleCalendarHTTPRequest(urlRequest, context: "Google Calendar raw API request failed")
    return [
      "status": response.response.statusCode,
      "body": try rawCalendarAPIResponseBody(response.data)
    ]
  }

  private func queryItems(search: CalendarEventSearch, account: CalendarAccountConfig) -> [URLQueryItem] {
    var items: [URLQueryItem] = [
      URLQueryItem(name: "singleEvents", value: search.singleEvents ? "true" : "false")
    ]
    if let orderBy = search.orderBy {
      items.append(URLQueryItem(name: "orderBy", value: orderBy.rawValue))
    } else if search.singleEvents, nonBlank(search.syncToken) == nil {
      items.append(URLQueryItem(name: "orderBy", value: CalendarEventOrderBy.startTime.rawValue))
    }
    if let query = nonBlank(search.query) {
      items.append(URLQueryItem(name: "q", value: query))
    }
    if let timeMin = nonBlank(search.timeMin) {
      items.append(URLQueryItem(name: "timeMin", value: timeMin))
    }
    if let timeMax = nonBlank(search.timeMax) {
      items.append(URLQueryItem(name: "timeMax", value: timeMax))
    }
    if let updatedMin = nonBlank(search.updatedMin) {
      items.append(URLQueryItem(name: "updatedMin", value: updatedMin))
    }
    if let maxResults = search.maxResults {
      items.append(URLQueryItem(name: "maxResults", value: String(maxResults)))
    }
    if let pageToken = nonBlank(search.pageToken) {
      items.append(URLQueryItem(name: "pageToken", value: pageToken))
    }
    if let syncToken = nonBlank(search.syncToken) {
      items.append(URLQueryItem(name: "syncToken", value: syncToken))
    }
    if let showDeleted = search.showDeleted {
      items.append(URLQueryItem(name: "showDeleted", value: showDeleted ? "true" : "false"))
    }
    if let timeZone = nonBlank(account.defaultTimeZone) {
      items.append(URLQueryItem(name: "timeZone", value: timeZone))
    }
    return items
  }

}

private func rawCalendarAPIResponseBody(_ data: Data) throws -> Any {
  guard !data.isEmpty else {
    return NSNull()
  }
  return try JSONSerialization.jsonObject(with: data)
}

private func eventCollectionComponents(calendarId: String) -> URLComponents {
  URLComponents(string: "https://www.googleapis.com/calendar/v3/calendars/\(urlEncodedPathComponent(calendarId))/events")!
}

private func eventItemComponents(calendarId: String, eventId: String) -> URLComponents {
  URLComponents(string: "https://www.googleapis.com/calendar/v3/calendars/\(urlEncodedPathComponent(calendarId))/events/\(urlEncodedPathComponent(eventId))")!
}

private func sendUpdatesQueryItems(_ sendUpdates: String?) -> [URLQueryItem]? {
  guard let sendUpdates = nonBlank(sendUpdates) else {
    return nil
  }
  return [URLQueryItem(name: "sendUpdates", value: sendUpdates)]
}

private func eventBodyData(input: CalendarEventInput, requireStartEnd: Bool) throws -> Data {
  var body: [String: Any] = [:]
  if let summary = nonBlank(input.summary) {
    body["summary"] = summary
  }
  if let description = nonBlank(input.description) {
    body["description"] = description
  }
  if let location = nonBlank(input.location) {
    body["location"] = location
  }
  if let colorId = nonBlank(input.colorId) {
    body["colorId"] = colorId
  }
  if let visibility = input.visibility {
    body["visibility"] = visibility.rawValue
  }
  if let transparency = input.transparency {
    body["transparency"] = transparency.rawValue
  }
  if let start = nonBlank(input.start) {
    body["start"] = dateTimeObject(start, timeZone: input.timeZone)
  } else if requireStartEnd {
    throw invalidEventInput("createEvent requires start")
  }
  if let end = nonBlank(input.end) {
    body["end"] = dateTimeObject(end, timeZone: input.timeZone)
  } else if requireStartEnd {
    throw invalidEventInput("createEvent requires end")
  }
  if !input.attendeeEmails.isEmpty {
    body["attendees"] = input.attendeeEmails.map { ["email": $0] }
  }
  if !input.recurrenceRules.isEmpty {
    body["recurrence"] = input.recurrenceRules
  }
  if let reminders = remindersObject(input) {
    body["reminders"] = reminders
  }
  if input.createConference {
    body["conferenceData"] = conferenceDataCreateRequest(input)
  }
  guard !body.isEmpty else {
    throw invalidEventInput("Event input must contain at least one writable field")
  }
  do {
    return try JSONSerialization.data(withJSONObject: body, options: [.sortedKeys])
  } catch {
    throw GoogleCalendarGatewayError(
      "Failed to encode Google Calendar event body",
      code: .invalidArgument,
      exitCode: .graphqlExecutionError,
      details: ["cause": error.localizedDescription]
    )
  }
}

private func dateTimeObject(_ value: String, timeZone: String?) -> [String: Any] {
  if value.contains("T") {
    var object: [String: Any] = ["dateTime": value]
    if let timeZone = nonBlank(timeZone) {
      object["timeZone"] = timeZone
    }
    return object
  }
  return ["date": value]
}

private func eventMutationQueryItems(input: CalendarEventInput) -> [URLQueryItem]? {
  var items = sendUpdatesQueryItems(input.sendUpdates) ?? []
  if input.createConference {
    items.append(URLQueryItem(name: "conferenceDataVersion", value: "1"))
  }
  return items.isEmpty ? nil : items
}

private func conferenceDataCreateRequest(_ input: CalendarEventInput) -> [String: Any] {
  [
    "createRequest": [
      "requestId": nonBlank(input.conferenceRequestId) ?? UUID().uuidString,
      "conferenceSolutionKey": ["type": "hangoutsMeet"]
    ]
  ]
}

private func remindersObject(_ input: CalendarEventInput) -> [String: Any]? {
  guard input.reminderUseDefault != nil || !input.reminderOverrides.isEmpty else {
    return nil
  }
  var object: [String: Any] = [:]
  if let reminderUseDefault = input.reminderUseDefault {
    object["useDefault"] = reminderUseDefault
  } else {
    object["useDefault"] = false
  }
  if !input.reminderOverrides.isEmpty {
    object["overrides"] = input.reminderOverrides.map { reminder in
      [
        "method": reminder.method.rawValue,
        "minutes": reminder.minutes
      ] as [String: Any]
    }
  }
  return object
}

private func freeBusyBodyData(_ query: CalendarFreeBusyQuery) throws -> Data {
  var body: [String: Any] = [
    "timeMin": query.timeMin,
    "timeMax": query.timeMax,
    "items": query.calendarIds.map { ["id": $0] }
  ]
  if let timeZone = nonBlank(query.timeZone) {
    body["timeZone"] = timeZone
  }
  if let groupExpansionMax = query.groupExpansionMax {
    body["groupExpansionMax"] = groupExpansionMax
  }
  if let calendarExpansionMax = query.calendarExpansionMax {
    body["calendarExpansionMax"] = calendarExpansionMax
  }
  do {
    return try JSONSerialization.data(withJSONObject: body, options: [.sortedKeys])
  } catch {
    throw GoogleCalendarGatewayError(
      "Failed to encode Google Calendar free/busy body",
      code: .invalidArgument,
      exitCode: .graphqlExecutionError,
      details: ["cause": error.localizedDescription]
    )
  }
}

func performGoogleCalendarJSONRequest(
  url: URL,
  accessToken: String,
  context: String,
  failureKind: GoogleCalendarHTTPFailureKind = .general
) throws -> [String: Any] {
  var request = URLRequest(url: url)
  request.httpMethod = "GET"
  request.timeoutInterval = 30
  request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
  return try performGoogleCalendarJSONRequest(request: request, context: context, failureKind: failureKind)
}

private func performGoogleCalendarJSONRequest(
  request: URLRequest,
  context: String,
  failureKind: GoogleCalendarHTTPFailureKind = .general
) throws -> [String: Any] {
  let response = try performGoogleCalendarHTTPRequest(request, context: context, failureKind: failureKind)
  let json = try JSONSerialization.jsonObject(with: response.data)
  guard let object = json as? [String: Any] else {
    throw GoogleCalendarGatewayError(
      "Google Calendar response was not a JSON object",
      code: .providerApiError,
      exitCode: .providerApiError
    )
  }
  return object
}

private func requireURL(_ url: URL?) throws -> URL {
  guard let url else {
    throw GoogleCalendarGatewayError("Invalid Google Calendar API URL", code: .invalidArgument, exitCode: .invalidCliUsage)
  }
  return url
}

private func requireNonBlank(_ value: String?, name: String) throws -> String {
  guard let value = nonBlank(value) else {
    throw invalidEventInput("\(name) must be a non-empty string")
  }
  return value
}

private func invalidEventInput(_ message: String) -> GoogleCalendarGatewayError {
  GoogleCalendarGatewayError(message, code: .invalidArgument, exitCode: .graphqlExecutionError)
}
