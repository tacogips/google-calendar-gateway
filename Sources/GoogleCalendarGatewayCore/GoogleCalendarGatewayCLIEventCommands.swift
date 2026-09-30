import Foundation

extension GoogleCalendarGatewayCLI {
  func runEventCommand(
    subcommand: String?,
    flags: [String: StringOrBool],
    configPath: String?,
    environment: [String: String],
    pretty: Bool
  ) throws -> GoogleCalendarGatewayCommandResult {
    let request = try eventCommandRequest(subcommand: subcommand, flags: flags)
    let config = try GoogleCalendarGatewayConfigLoader.loadConfig(configPath: configPath, environment: environment)
    let service = serviceFactory(config)
    let result: CalendarEventMutationResult
    switch request {
    case .create(let input, let dryRun):
      result = try service.createEventMutation(input: input, dryRun: dryRun)
    case .update(let input, let dryRun):
      result = try service.updateEventMutation(input: input, dryRun: dryRun)
    case .delete(let accountId, let calendarId, let eventId, let sendUpdates, let dryRun):
      result = try service.deleteEventMutation(
        accountId: accountId,
        calendarId: calendarId,
        eventId: eventId,
        sendUpdates: sendUpdates,
        dryRun: dryRun
      )
    }
    return GoogleCalendarGatewayCommandResult(
      exitCode: GoogleCalendarGatewayExitCode.success.rawValue,
      stdout: jsonString(result.jsonObject, pretty: pretty) + "\n",
      stderr: ""
    )
  }
}

private enum EventCommandRequest {
  case create(CalendarEventInput, dryRun: Bool)
  case update(CalendarEventInput, dryRun: Bool)
  case delete(accountId: String, calendarId: String?, eventId: String, sendUpdates: String?, dryRun: Bool)
}

private func eventCommandRequest(
  subcommand: String?,
  flags: [String: StringOrBool]
) throws -> EventCommandRequest {
  guard let accountId = try getStringFlag(flags, "calendar") else {
    throw invalidCLIArgument("event commands require --calendar")
  }
  let dryRun = try getBooleanFlag(flags, "dry-run")
  switch subcommand {
  case "create":
    return .create(try eventInput(accountId: accountId, flags: flags, requireEventId: false), dryRun: dryRun)
  case "update":
    return .update(try eventInput(accountId: accountId, flags: flags, requireEventId: true), dryRun: dryRun)
  case "delete":
    guard let eventId = try getStringFlag(flags, "event-id") else {
      throw invalidCLIArgument("event update and delete require --event-id")
    }
    return .delete(
      accountId: accountId,
      calendarId: try getStringFlag(flags, "provider-calendar"),
      eventId: eventId,
      sendUpdates: try getStringFlag(flags, "send-updates"),
      dryRun: dryRun
    )
  default:
    throw invalidCLIArgument("event requires one of: create, update, delete")
  }
}

private func eventInput(
  accountId: String,
  flags: [String: StringOrBool],
  requireEventId: Bool
) throws -> CalendarEventInput {
  let eventId = try getStringFlag(flags, "event-id")
  if requireEventId, eventId == nil {
    throw invalidCLIArgument("event update and delete require --event-id")
  }
  return CalendarEventInput(
    accountId: accountId,
    calendarId: try getStringFlag(flags, "provider-calendar"),
    eventId: eventId,
    summary: try getStringFlag(flags, "summary"),
    description: try getStringFlag(flags, "description"),
    location: try getStringFlag(flags, "location"),
    colorId: try getStringFlag(flags, "color-id"),
    visibility: try eventEnumFlag(flags, "visibility", as: CalendarEventVisibility.self),
    transparency: try eventEnumFlag(flags, "transparency", as: CalendarEventTransparency.self),
    start: try getStringFlag(flags, "start"),
    end: try getStringFlag(flags, "end"),
    timeZone: try getStringFlag(flags, "time-zone"),
    attendeeEmails: try stringArrayFlag(flags, "attendee-emails"),
    recurrenceRules: try stringArrayFlag(flags, "recurrence-rules"),
    reminderUseDefault: try optionalBooleanFlag(flags, "reminder-use-default"),
    reminderOverrides: try reminderArrayFlag(flags),
    createConference: try getBooleanFlag(flags, "create-conference"),
    conferenceRequestId: try getStringFlag(flags, "conference-request-id"),
    sendUpdates: try getStringFlag(flags, "send-updates")
  )
}

private func optionalBooleanFlag(_ flags: [String: StringOrBool], _ name: String) throws -> Bool? {
  guard flags[name] != nil else {
    return nil
  }
  return try getBooleanFlag(flags, name)
}

private func eventEnumFlag<T: RawRepresentable>(
  _ flags: [String: StringOrBool],
  _ name: String,
  as type: T.Type
) throws -> T? where T.RawValue == String {
  guard let value = try getStringFlag(flags, name) else {
    return nil
  }
  guard let result = type.init(rawValue: value) else {
    throw invalidCLIArgument("--\(name) is invalid")
  }
  return result
}

private func stringArrayFlag(_ flags: [String: StringOrBool], _ name: String) throws -> [String] {
  guard let source = try getStringFlag(flags, name) else {
    return []
  }
  let value: Any
  do {
    value = try JSONSerialization.jsonObject(with: Data(source.utf8))
  } catch {
    throw invalidCLIArgument("--\(name) must be a valid JSON array of strings")
  }
  guard let values = value as? [Any], values.allSatisfy({ $0 is String }) else {
    throw invalidCLIArgument("--\(name) must be a JSON array of strings")
  }
  return values.compactMap { $0 as? String }
}

private func reminderArrayFlag(_ flags: [String: StringOrBool]) throws -> [CalendarEventReminder] {
  try stringArrayFlag(flags, "reminder-overrides").map { value in
    let parts = value.split(separator: ":", maxSplits: 1, omittingEmptySubsequences: false)
    guard parts.count == 2,
          let method = CalendarEventReminderMethod(rawValue: String(parts[0])),
          !parts[1].isEmpty,
          parts[1].allSatisfy(\.isNumber),
          let minutes = Int(parts[1]) else {
      throw invalidCLIArgument("--reminder-overrides must contain values like popup:30 or email:1440")
    }
    return CalendarEventReminder(method: method, minutes: minutes)
  }
}

private func invalidCLIArgument(_ message: String) -> GoogleCalendarGatewayError {
  GoogleCalendarGatewayError(message, code: .invalidArgument, exitCode: .invalidCliUsage)
}
