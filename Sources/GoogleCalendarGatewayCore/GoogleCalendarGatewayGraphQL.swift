import Foundation

public func executeCalendarGraphQL(
  config: GoogleCalendarGatewayConfig,
  query: String,
  mode: GoogleCalendarGatewayCLIMode = .writer
) throws -> (body: [String: Any], exitCode: GoogleCalendarGatewayExitCode) {
  try executeCalendarGraphQL(service: GoogleCalendarGatewayService(config: config), query: query, mode: mode)
}

public func executeCalendarGraphQL(
  service: GoogleCalendarGatewayService,
  query: String,
  mode: GoogleCalendarGatewayCLIMode = .writer
) throws -> (body: [String: Any], exitCode: GoogleCalendarGatewayExitCode) {
  do {
    return (["data": try executeCalendarGraphQLData(service: service, query: query, mode: mode)], .success)
  } catch let error as GoogleCalendarGatewayError {
    var extensions: [String: Any] = [
      "code": error.code.rawValue,
      "exitCode": error.exitCode.rawValue
    ]
    if !error.details.isEmpty {
      extensions["details"] = error.details
    }
    return (
      [
        "data": NSNull(),
        "errors": [
          [
            "message": error.message,
            "extensions": extensions
          ]
        ]
      ],
      error.exitCode
    )
  }
}

private func executeCalendarGraphQLData(service: GoogleCalendarGatewayService, query: String, mode: GoogleCalendarGatewayCLIMode) throws -> [String: Any] {
  try rejectUnsupportedGraphQLVariables(in: query)
  let rootFields = topLevelRootFields(in: query)
  if rootFields.count > 1 {
    throw GoogleCalendarGatewayError(
      "GraphQL operations may contain exactly one root field",
      code: .invalidArgument,
      exitCode: .graphqlExecutionError
    )
  }
  if let source = rootFieldSource("calendarAPI", in: query) {
    let request = try rawCalendarAPIRequest(from: source)
    if rawCalendarAPITokenUse(for: request) == .write {
      try mode.requireWrites()
    }
    return [
      "calendarAPI": projectGraphQLValue(
        try service.executeCalendarAPI(request: request),
        selection: selectionBodyFromFieldSource(source)
      )
    ]
  }
  if let source = rootFieldSource("createEvent", in: query) {
    try mode.requireWrites()
    return [
      "createEvent": projectGraphQLValue(
        try service.createEvent(
          input: eventInput(from: source, requireEventId: false),
          dryRun: try extractOptionalBooleanArgument("dryRun", from: source) ?? false
        ),
        selection: selectionBodyFromFieldSource(source)
      )
    ]
  }
  if let source = rootFieldSource("updateEvent", in: query) {
    try mode.requireWrites()
    return [
      "updateEvent": projectGraphQLValue(
        try service.updateEvent(
          input: eventInput(from: source, requireEventId: true),
          dryRun: try extractOptionalBooleanArgument("dryRun", from: source) ?? false
        ),
        selection: selectionBodyFromFieldSource(source)
      )
    ]
  }
  if let source = rootFieldSource("deleteEvent", in: query) {
    try mode.requireWrites()
    let gatewayCalendarId = try extractOptionalStringArgument("accountId", from: source)
      ?? extractStringArgument("calendarId", from: source)
    return [
      "deleteEvent": projectGraphQLValue(
        try service.deleteEvent(
          accountId: gatewayCalendarId,
          calendarId: try extractOptionalStringArgument("providerCalendarId", from: source),
          eventId: try extractStringArgument("eventId", from: source),
          sendUpdates: try extractOptionalStringArgument("sendUpdates", from: source),
          dryRun: try extractOptionalBooleanArgument("dryRun", from: source) ?? false
        ),
        selection: selectionBodyFromFieldSource(source)
      )
    ]
  }
  if let source = rootFieldSource("calendars", in: query) {
    return ["calendars": projectGraphQLValue(service.graphQLAccounts(), selection: selectionBodyFromFieldSource(source))]
  }
  if let source = rootFieldSource("accounts", in: query) {
    return ["accounts": projectGraphQLValue(service.graphQLAccounts(), selection: selectionBodyFromFieldSource(source))]
  }
  if let source = rootFieldSource("calendar", in: query) {
    return [
      "calendar": projectGraphQLValue(
        service.graphQLAccount(id: try extractStringArgument("id", from: source)) as Any? ?? NSNull(),
        selection: selectionBodyFromFieldSource(source)
      )
    ]
  }
  if let source = rootFieldSource("account", in: query) {
    return [
      "account": projectGraphQLValue(
        service.graphQLAccount(id: try extractStringArgument("id", from: source)) as Any? ?? NSNull(),
        selection: selectionBodyFromFieldSource(source)
      )
    ]
  }
  if let source = rootFieldSource("providerCalendars", in: query) {
    return [
      "providerCalendars": projectGraphQLValue(
        try service.graphQLProviderCalendars(credentialId: try extractStringArgument("credentialId", from: source)),
        selection: selectionBodyFromFieldSource(source)
      )
    ]
  }
  if let source = rootFieldSource("freeBusy", in: query) {
    return [
      "freeBusy": projectGraphQLValue(
        try service.freeBusy(query: freeBusyQuery(from: source)),
        selection: selectionBodyFromFieldSource(source)
      )
    ]
  }
  if let source = rootFieldSource("events", in: query) {
    let gatewayCalendarId = try extractOptionalStringArgument("accountId", from: source)
      ?? extractStringArgument("calendarId", from: source)
    return [
      "events": projectGraphQLValue(
        try service.listEvents(search: CalendarEventSearch(
          accountId: gatewayCalendarId,
          calendarId: try extractOptionalStringArgument("providerCalendarId", from: source),
          query: try extractOptionalStringArgument("query", from: source),
          timeMin: try extractOptionalRFC3339DateTimeArgument("timeMin", from: source),
          timeMax: try extractOptionalRFC3339DateTimeArgument("timeMax", from: source),
          updatedMin: try extractOptionalRFC3339DateTimeArgument("updatedMin", from: source),
          maxResults: try extractOptionalMaxResultsArgument(from: source),
          pageToken: try eventPageToken(from: source),
          syncToken: try extractOptionalStringArgument("syncToken", from: source),
          showDeleted: try extractOptionalBooleanArgument("showDeleted", from: source),
          singleEvents: try extractOptionalBooleanArgument("singleEvents", from: source) ?? true,
          orderBy: try extractOptionalEventOrderByArgument(from: source)
        )),
        selection: selectionBodyFromFieldSource(source)
      )
    ]
  }
  if let source = rootFieldSource("event", in: query) {
    let gatewayCalendarId = try extractOptionalStringArgument("accountId", from: source)
      ?? extractStringArgument("calendarId", from: source)
    return [
      "event": projectGraphQLValue(
        try service.getEvent(
          accountId: gatewayCalendarId,
          calendarId: try extractOptionalStringArgument("providerCalendarId", from: source),
          eventId: try extractStringArgument("eventId", from: source)
        ),
        selection: selectionBodyFromFieldSource(source)
      )
    ]
  }
  throw GoogleCalendarGatewayError(
    "Unsupported GraphQL query",
    code: .invalidArgument,
    exitCode: .graphqlExecutionError
  )
}

func rejectUnsupportedGraphQLVariables(in query: String) throws {
  guard graphQLReferencesVariables(query) else {
    return
  }
  throw GoogleCalendarGatewayError(
    "GraphQL variables are not supported yet; use literal arguments",
    code: .invalidArgument,
    exitCode: .graphqlExecutionError
  )
}

private func rawCalendarAPIRequest(from source: String) throws -> CalendarRawAPIRequest {
  let methodValue = try extractStringArgument("method", from: source).uppercased()
  guard let method = CalendarRawHTTPMethod(rawValue: methodValue) else {
    throw GoogleCalendarGatewayError(
      "GraphQL argument method must be one of: GET, POST, PUT, PATCH, DELETE",
      code: .invalidArgument,
      exitCode: .graphqlExecutionError
    )
  }
  let access: CalendarRawAPIAccess
  if let accessValue = try extractOptionalStringArgument("access", from: source) {
    guard let parsed = CalendarRawAPIAccess(rawValue: accessValue) else {
      throw GoogleCalendarGatewayError(
        "GraphQL argument access must be one of: auto, read, write",
        code: .invalidArgument,
        exitCode: .graphqlExecutionError
      )
    }
    access = parsed
  } else {
    access = .auto
  }
  return CalendarRawAPIRequest(
    credentialId: try extractStringArgument("credentialId", from: source),
    method: method,
    path: try extractStringArgument("path", from: source),
    queryItems: try extractOptionalQueryItemsArgument(from: source),
    bodyJSON: try extractOptionalDecodedStringArgument("body", from: source),
    access: access
  )
}

private func selectionBodyFromFieldSource(_ source: String) -> String? {
  guard let open = source.firstIndex(of: "{"),
        let closeAfter = indexAfterBalancedDelimiter(in: source, from: open, open: "{", close: "}") else {
    return nil
  }
  return String(source[source.index(after: open)..<source.index(before: closeAfter)])
}

private func projectGraphQLValue(_ value: Any, selection: String?) -> Any {
  guard let selection,
        !selection.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
    return value
  }
  if let object = value as? [String: Any] {
    return projectGraphQLObject(object, selection: selection)
  }
  if let array = value as? [Any] {
    return array.map { projectGraphQLValue($0, selection: selection) }
  }
  return value
}

private func projectGraphQLObject(_ object: [String: Any], selection: String) -> [String: Any] {
  var projected: [String: Any] = [:]
  for field in selectedGraphQLFields(selection) {
    guard let value = object[field.name] else {
      continue
    }
    if let nestedSelection = field.selection {
      projected[field.name] = projectGraphQLValue(value, selection: nestedSelection)
    } else {
      projected[field.name] = value
    }
  }
  return projected
}

private struct SelectedGraphQLField {
  let name: String
  let selection: String?
}

private func selectedGraphQLFields(_ selection: String) -> [SelectedGraphQLField] {
  var fields: [SelectedGraphQLField] = []
  var index = selection.startIndex
  while index < selection.endIndex {
    index = skipWhitespaceAndCommas(in: selection, from: index)
    guard index < selection.endIndex else {
      break
    }
    let nameStart = index
    while index < selection.endIndex, isGraphQLIdentifier(selection[index]) {
      index = selection.index(after: index)
    }
    guard nameStart < index else {
      index = selection.index(after: index)
      continue
    }
    let name = String(selection[nameStart..<index])
    index = skipWhitespace(in: selection, from: index)
    if index < selection.endIndex, selection[index] == "(",
       let afterArguments = indexAfterBalancedDelimiter(in: selection, from: index, open: "(", close: ")") {
      index = skipWhitespace(in: selection, from: afterArguments)
    }
    var nested: String?
    if index < selection.endIndex, selection[index] == "{",
       let afterSelection = indexAfterBalancedDelimiter(in: selection, from: index, open: "{", close: "}") {
      nested = String(selection[selection.index(after: index)..<selection.index(before: afterSelection)])
      index = afterSelection
    }
    fields.append(SelectedGraphQLField(name: name, selection: nested))
  }
  return fields
}

private func skipWhitespaceAndCommas(in query: String, from start: String.Index) -> String.Index {
  var index = start
  while index < query.endIndex, query[index].isWhitespace || query[index] == "," {
    index = query.index(after: index)
  }
  return index
}

private func eventInput(from source: String, requireEventId: Bool) throws -> CalendarEventInput {
  let gatewayCalendarId = try extractOptionalStringArgument("accountId", from: source)
    ?? extractStringArgument("calendarId", from: source)
  let eventId: String?
  if requireEventId {
    eventId = try extractStringArgument("eventId", from: source)
  } else {
    eventId = try extractOptionalStringArgument("eventId", from: source)
  }
  return CalendarEventInput(
    accountId: gatewayCalendarId,
    calendarId: try extractOptionalStringArgument("providerCalendarId", from: source),
    eventId: eventId,
    summary: try extractOptionalStringArgument("summary", from: source),
    description: try extractOptionalStringArgument("description", from: source),
    location: try extractOptionalStringArgument("location", from: source),
    colorId: try extractOptionalStringArgument("colorId", from: source),
    visibility: try extractOptionalEnumArgument("visibility", from: source, as: CalendarEventVisibility.self),
    transparency: try extractOptionalEnumArgument("transparency", from: source, as: CalendarEventTransparency.self),
    start: try extractOptionalCalendarDateOrDateTimeArgument("start", from: source),
    end: try extractOptionalCalendarDateOrDateTimeArgument("end", from: source),
    timeZone: try extractOptionalStringArgument("timeZone", from: source),
    attendeeEmails: try extractOptionalStringArrayArgument("attendeeEmails", from: source),
    recurrenceRules: try extractOptionalStringArrayArgument("recurrenceRules", from: source),
    reminderUseDefault: try extractOptionalBooleanArgument("reminderUseDefault", from: source),
    reminderOverrides: try extractOptionalReminderOverridesArgument(from: source),
    createConference: try extractOptionalBooleanArgument("createConference", from: source) ?? false,
    conferenceRequestId: try extractOptionalStringArgument("conferenceRequestId", from: source),
    sendUpdates: try extractOptionalStringArgument("sendUpdates", from: source)
  )
}

private func freeBusyQuery(from source: String) throws -> CalendarFreeBusyQuery {
  let gatewayCalendarId = try extractOptionalStringArgument("accountId", from: source)
    ?? extractStringArgument("calendarId", from: source)
  let calendarIds = try freeBusyProviderCalendarIds(from: source)
  return CalendarFreeBusyQuery(
    accountId: gatewayCalendarId,
    calendarIds: calendarIds,
    timeMin: try extractRFC3339DateTimeArgument("timeMin", from: source),
    timeMax: try extractRFC3339DateTimeArgument("timeMax", from: source),
    timeZone: try extractOptionalStringArgument("timeZone", from: source),
    groupExpansionMax: try extractOptionalIntArgument("groupExpansionMax", from: source),
    calendarExpansionMax: try extractOptionalIntArgument("calendarExpansionMax", from: source)
  )
}

private func freeBusyProviderCalendarIds(from source: String) throws -> [String] {
  let calendarIds = try extractOptionalStringArrayArgument("providerCalendarIds", from: source)
  if !calendarIds.isEmpty {
    return calendarIds
  }
  if let calendarId = try extractOptionalStringArgument("providerCalendarId", from: source) {
    return [calendarId]
  }
  return []
}

private func extractRFC3339DateTimeArgument(_ name: String, from query: String) throws -> String {
  guard let value = try extractOptionalRFC3339DateTimeArgument(name, from: query) else {
    throw GoogleCalendarGatewayError(
      "Missing GraphQL argument: \(name)",
      code: .invalidArgument,
      exitCode: .graphqlExecutionError
    )
  }
  return value
}

private func extractOptionalRFC3339DateTimeArgument(_ name: String, from query: String) throws -> String? {
  guard let value = try extractOptionalStringArgument(name, from: query) else {
    return nil
  }
  guard isRFC3339DateTime(value) else {
    throw GoogleCalendarGatewayError(
      "GraphQL argument \(name) must be an RFC 3339 date-time string",
      code: .invalidArgument,
      exitCode: .graphqlExecutionError
    )
  }
  return value
}

private func extractOptionalCalendarDateOrDateTimeArgument(_ name: String, from query: String) throws -> String? {
  guard let value = try extractOptionalStringArgument(name, from: query) else {
    return nil
  }
  guard isCalendarDate(value) || isRFC3339DateTime(value) else {
    throw GoogleCalendarGatewayError(
      "GraphQL argument \(name) must be an RFC 3339 date-time or YYYY-MM-DD date string",
      code: .invalidArgument,
      exitCode: .graphqlExecutionError
    )
  }
  return value
}

private func eventPageToken(from source: String) throws -> String? {
  if let cursor = try extractOptionalStringArgument("cursor", from: source) {
    return try pageTokenFromCalendarEventCursor(cursor)
  }
  return try extractOptionalStringArgument("pageToken", from: source)
}

private func extractOptionalMaxResultsArgument(from source: String) throws -> Int? {
  guard let maxResults = try extractOptionalIntArgument("maxResults", from: source) else {
    return nil
  }
  guard (1...2500).contains(maxResults) else {
    throw GoogleCalendarGatewayError(
      "GraphQL argument maxResults must be between 1 and 2500",
      code: .invalidArgument,
      exitCode: .graphqlExecutionError
    )
  }
  return maxResults
}

private func extractOptionalEventOrderByArgument(from source: String) throws -> CalendarEventOrderBy? {
  guard let value = try extractOptionalStringArgument("orderBy", from: source) else {
    return nil
  }
  guard let orderBy = CalendarEventOrderBy(rawValue: value) else {
    throw GoogleCalendarGatewayError(
      "GraphQL argument orderBy must be one of: startTime, updated",
      code: .invalidArgument,
      exitCode: .graphqlExecutionError
    )
  }
  return orderBy
}

private func extractOptionalReminderOverridesArgument(from source: String) throws -> [CalendarEventReminder] {
  try extractOptionalStringArrayArgument("reminderOverrides", from: source).map(parseReminderOverride)
}

private func extractOptionalEnumArgument<T: RawRepresentable>(
  _ name: String,
  from source: String,
  as type: T.Type
) throws -> T? where T.RawValue == String {
  guard let value = try extractOptionalStringArgument(name, from: source) else {
    return nil
  }
  guard let typedValue = type.init(rawValue: value) else {
    throw GoogleCalendarGatewayError(
      "GraphQL argument \(name) is invalid",
      code: .invalidArgument,
      exitCode: .graphqlExecutionError
    )
  }
  return typedValue
}

private func parseReminderOverride(_ value: String) throws -> CalendarEventReminder {
  let parts = value.split(separator: ":", maxSplits: 1, omittingEmptySubsequences: false)
  guard parts.count == 2,
        let method = CalendarEventReminderMethod(rawValue: String(parts[0])),
        let minutes = Int(String(parts[1])) else {
    throw GoogleCalendarGatewayError(
      "GraphQL argument reminderOverrides must contain values like popup:30 or email:1440",
      code: .invalidArgument,
      exitCode: .graphqlExecutionError
    )
  }
  return CalendarEventReminder(method: method, minutes: minutes)
}

private func rootFieldSource(_ field: String, in query: String) -> String? {
  fieldSource(for: field, in: query, atBraceDepth: 1)
}

private func topLevelRootFields(in query: String) -> [String] {
  var fields: [String] = []
  var braceDepth = 0
  var parenDepth = 0
  var index = query.startIndex
  var inString = false
  var previousWasEscape = false
  while index < query.endIndex {
    let character = query[index]
    if character == "\"" && !previousWasEscape {
      inString.toggle()
      index = query.index(after: index)
      continue
    }
    if inString {
      previousWasEscape = character == "\\" && !previousWasEscape
      index = query.index(after: index)
      continue
    }
    previousWasEscape = false
    switch character {
    case "{":
      braceDepth += 1
    case "}":
      braceDepth -= 1
    case "(":
      parenDepth += 1
    case ")":
      parenDepth -= 1
    default:
      if braceDepth == 1, parenDepth == 0, isGraphQLIdentifierStart(character) {
        let start = index
        var end = query.index(after: index)
        while end < query.endIndex, isGraphQLIdentifier(query[end]) {
          end = query.index(after: end)
        }
        fields.append(String(query[start..<end]))
        index = end
        continue
      }
    }
    index = query.index(after: index)
  }
  return fields
}

private func fieldSource(for field: String, in query: String, atBraceDepth braceDepth: Int) -> String? {
  guard let range = rangeOfField(field, in: query, atBraceDepth: braceDepth) else {
    return nil
  }
  var index = skipWhitespace(in: query, from: range.upperBound)
  if index < query.endIndex,
     query[index] == "(",
     let endIndex = indexAfterBalancedDelimiter(in: query, from: index, open: "(", close: ")") {
    index = skipWhitespace(in: query, from: endIndex)
  }
  if index < query.endIndex,
     query[index] == "{",
     let endIndex = indexAfterBalancedDelimiter(in: query, from: index, open: "{", close: "}") {
    return String(query[range.lowerBound..<endIndex])
  }
  return String(query[range.lowerBound..<index])
}

private func rangeOfField(_ field: String, in query: String, atBraceDepth targetBraceDepth: Int) -> Range<String.Index>? {
  var braceDepth = 0
  var parenDepth = 0
  var index = query.startIndex
  var inString = false
  var previousWasEscape = false
  while index < query.endIndex {
    let character = query[index]
    if character == "\"" && !previousWasEscape {
      inString.toggle()
      index = query.index(after: index)
      continue
    }
    if inString {
      previousWasEscape = character == "\\" && !previousWasEscape
      index = query.index(after: index)
      continue
    }
    previousWasEscape = false
    switch character {
    case "{":
      braceDepth += 1
    case "}":
      braceDepth -= 1
    case "(":
      parenDepth += 1
    case ")":
      parenDepth -= 1
    default:
      if braceDepth == targetBraceDepth,
         parenDepth == 0,
         query[index...].hasPrefix(field) {
        let end = query.index(index, offsetBy: field.count)
        let before = index > query.startIndex ? query[query.index(before: index)] : " "
        let after = end < query.endIndex ? query[end] : " "
        if !isGraphQLIdentifier(before), !isGraphQLIdentifier(after) {
          return index..<end
        }
      }
    }
    index = query.index(after: index)
  }
  return nil
}

private func isGraphQLIdentifierStart(_ character: Character) -> Bool {
  character.isLetter || character == "_"
}

private func isGraphQLIdentifier(_ character: Character) -> Bool {
  character.isLetter || character.isNumber || character == "_"
}

private func skipWhitespace(in query: String, from start: String.Index) -> String.Index {
  var index = start
  while index < query.endIndex, query[index].isWhitespace {
    index = query.index(after: index)
  }
  return index
}

private func indexAfterBalancedDelimiter(
  in query: String,
  from start: String.Index,
  open: Character,
  close: Character
) -> String.Index? {
  var depth = 0
  var index = start
  var inString = false
  var previousWasEscape = false
  while index < query.endIndex {
    let character = query[index]
    if character == "\"" && !previousWasEscape {
      inString.toggle()
      index = query.index(after: index)
      continue
    }
    if inString {
      previousWasEscape = character == "\\" && !previousWasEscape
      index = query.index(after: index)
      continue
    }
    previousWasEscape = false
    if character == open {
      depth += 1
    } else if character == close {
      depth -= 1
      if depth == 0 {
        return query.index(after: index)
      }
    }
    index = query.index(after: index)
  }
  return nil
}

private func extractStringArgument(_ name: String, from query: String) throws -> String {
  guard let value = try extractOptionalStringArgument(name, from: query) else {
    throw GoogleCalendarGatewayError(
      "Missing GraphQL argument: \(name)",
      code: .invalidArgument,
      exitCode: .graphqlExecutionError
    )
  }
  guard let normalized = nonBlank(value) else {
    throw GoogleCalendarGatewayError(
      "GraphQL argument \(name) must be a non-empty string",
      code: .invalidArgument,
      exitCode: .graphqlExecutionError
    )
  }
  return normalized
}

private func extractOptionalStringArgument(_ name: String, from query: String) throws -> String? {
  guard let range = argumentValueRange(name, in: query) else {
    return nil
  }
  let raw = query[range].trimmingCharacters(in: .whitespacesAndNewlines)
  guard raw.hasPrefix("\""), raw.hasSuffix("\"") else {
    throw GoogleCalendarGatewayError(
      "GraphQL argument \(name) must be a string literal",
      code: .invalidArgument,
      exitCode: .graphqlExecutionError
    )
  }
  return String(raw.dropFirst().dropLast())
}

private func extractOptionalIntArgument(_ name: String, from query: String) throws -> Int? {
  guard let range = argumentValueRange(name, in: query) else {
    return nil
  }
  let raw = query[range].trimmingCharacters(in: .whitespacesAndNewlines)
  guard let value = Int(raw) else {
    throw GoogleCalendarGatewayError(
      "GraphQL argument \(name) must be an integer literal",
      code: .invalidArgument,
      exitCode: .graphqlExecutionError
    )
  }
  return value
}

private func extractOptionalBooleanArgument(_ name: String, from query: String) throws -> Bool? {
  guard let range = argumentValueRange(name, in: query) else {
    return nil
  }
  let raw = query[range].trimmingCharacters(in: .whitespacesAndNewlines)
  switch raw {
  case "true":
    return true
  case "false":
    return false
  default:
    throw GoogleCalendarGatewayError(
      "GraphQL argument \(name) must be a boolean literal",
      code: .invalidArgument,
      exitCode: .graphqlExecutionError
    )
  }
}

private func extractOptionalStringArrayArgument(_ name: String, from query: String) throws -> [String] {
  guard let range = argumentValueRange(name, in: query) else {
    return []
  }
  let raw = query[range].trimmingCharacters(in: .whitespacesAndNewlines)
  guard raw.hasPrefix("["), raw.hasSuffix("]") else {
    throw GoogleCalendarGatewayError(
      "GraphQL argument \(name) must be a string array literal",
      code: .invalidArgument,
      exitCode: .graphqlExecutionError
    )
  }
  let inner = raw.dropFirst().dropLast().trimmingCharacters(in: .whitespacesAndNewlines)
  guard !inner.isEmpty else {
    return []
  }
  return try splitGraphQLArray(String(inner)).map { item in
    let trimmed = item.trimmingCharacters(in: .whitespacesAndNewlines)
    guard trimmed.hasPrefix("\""), trimmed.hasSuffix("\"") else {
      throw GoogleCalendarGatewayError(
        "GraphQL argument \(name) must contain string literals",
        code: .invalidArgument,
        exitCode: .graphqlExecutionError
      )
    }
    return String(trimmed.dropFirst().dropLast())
  }
}

private func extractOptionalQueryItemsArgument(from source: String) throws -> [(String, String)] {
  try extractOptionalStringArrayArgument("query", from: source).map { item in
    let parts = item.split(separator: "=", maxSplits: 1, omittingEmptySubsequences: false)
    guard parts.count == 2,
          nonBlank(String(parts[0])) != nil else {
      throw GoogleCalendarGatewayError(
        "GraphQL argument query must contain values like name=value",
        code: .invalidArgument,
        exitCode: .graphqlExecutionError
      )
    }
    return (String(parts[0]), String(parts[1]))
  }
}

private func extractOptionalDecodedStringArgument(_ name: String, from query: String) throws -> String? {
  guard let range = argumentValueRange(name, in: query) else {
    return nil
  }
  let raw = query[range].trimmingCharacters(in: .whitespacesAndNewlines)
  guard raw.hasPrefix("\""), raw.hasSuffix("\"") else {
    throw GoogleCalendarGatewayError(
      "GraphQL argument \(name) must be a string literal",
      code: .invalidArgument,
      exitCode: .graphqlExecutionError
    )
  }
  do {
    return try JSONDecoder().decode(String.self, from: Data(raw.utf8))
  } catch {
    throw GoogleCalendarGatewayError(
      "GraphQL argument \(name) must be a valid escaped string literal",
      code: .invalidArgument,
      exitCode: .graphqlExecutionError,
      details: ["cause": error.localizedDescription]
    )
  }
}

private func argumentValueRange(_ name: String, in query: String) -> Range<String.Index>? {
  guard let argsOpen = query.firstIndex(of: "("),
        let argsClose = indexAfterBalancedDelimiter(in: query, from: argsOpen, open: "(", close: ")") else {
    return nil
  }
  let args = query[query.index(after: argsOpen)..<query.index(before: argsClose)]
  var searchIndex = args.startIndex
  var matchRange: Range<String.Index>?
  var searchInString = false
  var searchPreviousWasEscape = false
  while searchIndex < args.endIndex {
    let character = query[searchIndex]
    if character == "\"" && !searchPreviousWasEscape {
      searchInString.toggle()
      searchIndex = query.index(after: searchIndex)
      continue
    }
    if searchInString {
      searchPreviousWasEscape = character == "\\" && !searchPreviousWasEscape
      searchIndex = query.index(after: searchIndex)
      continue
    }
    searchPreviousWasEscape = false
    if query[searchIndex...].hasPrefix(name) {
      let candidateEnd = query.index(searchIndex, offsetBy: name.count)
      let before = searchIndex > args.startIndex ? query[query.index(before: searchIndex)] : " "
      let after = candidateEnd < args.endIndex ? query[candidateEnd] : " "
      if !isGraphQLIdentifier(before), !isGraphQLIdentifier(after) {
        matchRange = searchIndex..<candidateEnd
        break
      }
    }
    searchIndex = query.index(after: searchIndex)
  }
  guard let nameRange = matchRange else {
    return nil
  }
  var colonSearch = nameRange.upperBound
  while colonSearch < args.endIndex, query[colonSearch].isWhitespace {
    colonSearch = query.index(after: colonSearch)
  }
  guard colonSearch < args.endIndex, query[colonSearch] == ":" else {
    return nil
  }
  let colon = colonSearch
  var start = query.index(after: colon)
  while start < args.endIndex, query[start].isWhitespace {
    start = query.index(after: start)
  }
  var end = start
  var inString = false
  var bracketDepth = 0
  var braceDepth = 0
  var parenDepth = 0
  var previousWasEscape = false
  while end < args.endIndex {
    let character = query[end]
    if character == "\"" && !previousWasEscape {
      inString.toggle()
    }
    if inString {
      previousWasEscape = character == "\\" && !previousWasEscape
      end = query.index(after: end)
      continue
    }
    previousWasEscape = false
    switch character {
    case "[":
      bracketDepth += 1
    case "]":
      bracketDepth -= 1
    case "{":
      braceDepth += 1
    case "}":
      braceDepth -= 1
    case "(":
      parenDepth += 1
    case ")":
      parenDepth -= 1
    case "," where bracketDepth == 0 && braceDepth == 0 && parenDepth == 0:
      return start..<end
    default:
      break
    }
    end = query.index(after: end)
  }
  return start..<end
}

private func graphQLReferencesVariables(_ query: String) -> Bool {
  var index = query.startIndex
  var inString = false
  var previousWasEscape = false
  while index < query.endIndex {
    let character = query[index]
    if character == "\"" && !previousWasEscape {
      inString.toggle()
      index = query.index(after: index)
      continue
    }
    if inString {
      previousWasEscape = character == "\\" && !previousWasEscape
      index = query.index(after: index)
      continue
    }
    previousWasEscape = false
    if character == "$" {
      return true
    }
    index = query.index(after: index)
  }
  return false
}

private func splitGraphQLArray(_ source: String) -> [String] {
  var values: [String] = []
  var current = ""
  var inString = false
  for character in source {
    if character == "\"" {
      inString.toggle()
      current.append(character)
      continue
    }
    if character == ",", !inString {
      values.append(current)
      current = ""
      continue
    }
    current.append(character)
  }
  if !current.isEmpty {
    values.append(current)
  }
  return values
}
