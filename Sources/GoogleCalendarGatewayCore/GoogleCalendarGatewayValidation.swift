func normalizedEventInput(_ input: CalendarEventInput) throws -> CalendarEventInput {
  CalendarEventInput(
    accountId: input.accountId,
    calendarId: try normalizedOptionalProviderCalendarId(input.calendarId),
    eventId: nonBlank(input.eventId),
    summary: input.summary,
    description: input.description,
    location: input.location,
    colorId: input.colorId,
    visibility: input.visibility,
    transparency: input.transparency,
    start: input.start,
    end: input.end,
    timeZone: input.timeZone,
    attendeeEmails: input.attendeeEmails,
    recurrenceRules: input.recurrenceRules,
    reminderUseDefault: input.reminderUseDefault,
    reminderOverrides: input.reminderOverrides,
    createConference: input.createConference,
    conferenceRequestId: input.conferenceRequestId,
    sendUpdates: input.sendUpdates
  )
}
