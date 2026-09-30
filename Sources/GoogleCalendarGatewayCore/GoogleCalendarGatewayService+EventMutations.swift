public extension GoogleCalendarGatewayService {
  func createEvent(input: CalendarEventInput, dryRun: Bool = false) throws -> Any {
    try createEventMutation(input: input, dryRun: dryRun).jsonObject
  }

  func createCalendarEvent(input: CalendarEventInput) throws -> CalendarEvent {
    switch try createEventMutation(input: input, dryRun: false) {
    case .event(let event):
      return event
    case .deletion, .preview:
      preconditionFailure("Live create mutation returned an invalid result")
    }
  }

  func createEventMutation(
    input: CalendarEventInput,
    dryRun: Bool = false
  ) throws -> CalendarEventMutationResult {
    let account = try requireAccount(input.accountId)
    let credential = try requireWriteCredential(account.credentialId)
    try validateEventInput(input, requireStartEnd: true)
    try validateSendUpdates(input.sendUpdates)
    let normalizedInput = try normalizedEventInput(input)
    let resolvedCalendarId = try normalizedProviderCalendarId(
      normalizedInput.calendarId,
      defaultCalendarId: account.defaultCalendarId
    )
    if dryRun {
      return .preview(CalendarEventMutationPreview(
        accountId: account.id,
        resolvedCalendarId: resolvedCalendarId,
        payload: .create(validatedInput: normalizedInput)
      ))
    }
    return .event(try provider.createEvent(account: account, credential: credential, input: normalizedInput))
  }

  func updateEvent(input: CalendarEventInput, dryRun: Bool = false) throws -> Any {
    try updateEventMutation(input: input, dryRun: dryRun).jsonObject
  }

  func updateCalendarEvent(input: CalendarEventInput) throws -> CalendarEvent {
    switch try updateEventMutation(input: input, dryRun: false) {
    case .event(let event):
      return event
    case .deletion, .preview:
      preconditionFailure("Live update mutation returned an invalid result")
    }
  }

  func updateEventMutation(
    input: CalendarEventInput,
    dryRun: Bool = false
  ) throws -> CalendarEventMutationResult {
    let account = try requireAccount(input.accountId)
    let credential = try requireWriteCredential(account.credentialId)
    guard nonBlank(input.eventId) != nil else {
      throw GoogleCalendarGatewayError(
        "updateEvent requires eventId",
        code: .invalidArgument,
        exitCode: .graphqlExecutionError
      )
    }
    try validateEventInput(input, requireStartEnd: false)
    try validateSendUpdates(input.sendUpdates)
    let normalizedInput = try normalizedEventInput(input)
    let resolvedCalendarId = try normalizedProviderCalendarId(
      normalizedInput.calendarId,
      defaultCalendarId: account.defaultCalendarId
    )
    if dryRun {
      return .preview(CalendarEventMutationPreview(
        accountId: account.id,
        resolvedCalendarId: resolvedCalendarId,
        payload: .update(validatedInput: normalizedInput)
      ))
    }
    return .event(try provider.updateEvent(account: account, credential: credential, input: normalizedInput))
  }

  func deleteEvent(
    accountId: String,
    calendarId: String? = nil,
    eventId: String,
    sendUpdates: String? = nil,
    dryRun: Bool = false
  ) throws -> [String: Any] {
    try deleteEventMutation(
      accountId: accountId,
      calendarId: calendarId,
      eventId: eventId,
      sendUpdates: sendUpdates,
      dryRun: dryRun
    ).jsonObject
  }

  func deleteEventMutation(
    accountId: String,
    calendarId: String? = nil,
    eventId: String,
    sendUpdates: String? = nil,
    dryRun: Bool = false
  ) throws -> CalendarEventMutationResult {
    let account = try requireAccount(accountId)
    let credential = try requireWriteCredential(account.credentialId)
    guard let normalizedEventId = nonBlank(eventId) else {
      throw GoogleCalendarGatewayError(
        "deleteEvent requires eventId",
        code: .invalidArgument,
        exitCode: .graphqlExecutionError
      )
    }
    try validateSendUpdates(sendUpdates)
    let resolvedCalendarId = try normalizedProviderCalendarId(
      calendarId,
      defaultCalendarId: account.defaultCalendarId
    )
    if dryRun {
      return .preview(CalendarEventMutationPreview(
        accountId: account.id,
        resolvedCalendarId: resolvedCalendarId,
        payload: .delete(target: CalendarEventDeletionPreview(
          eventId: normalizedEventId,
          sendUpdates: sendUpdates
        ))
      ))
    }
    return .deletion(try provider.deleteEvent(
      account: account,
      credential: credential,
      calendarId: resolvedCalendarId,
      eventId: normalizedEventId,
      sendUpdates: sendUpdates
    ))
  }
}
