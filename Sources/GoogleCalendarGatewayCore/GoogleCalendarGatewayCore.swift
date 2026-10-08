import Foundation

public enum GoogleCalendarGatewayExitCode: Int32, Sendable {
  case success = 0
  case generalError = 1
  case invalidCliUsage = 2
  case configurationError = 3
  case authenticationBootstrapError = 4
  case graphqlExecutionError = 5
  case providerApiError = 6
}

public enum GoogleCalendarGatewayErrorCode: String, Sendable {
  case accountNotFound = "ACCOUNT_NOT_FOUND"
  case authRequired = "AUTH_REQUIRED"
  case configInvalid = "CONFIG_INVALID"
  case credentialNotFound = "CREDENTIAL_NOT_FOUND"
  case eventNotFound = "EVENT_NOT_FOUND"
  case invalidArgument = "INVALID_ARGUMENT"
  case providerApiError = "PROVIDER_API_ERROR"
  case providerRateLimited = "PROVIDER_RATE_LIMITED"
  case syncTokenExpired = "SYNC_TOKEN_EXPIRED"
  case writeDisabled = "WRITE_DISABLED"
}

public struct GoogleCalendarGatewayCommandResult: Sendable {
  public let exitCode: Int32
  public let stdout: String
  public let stderr: String
}

public struct GoogleCalendarGatewayError: Error, Sendable {
  public let message: String
  public let code: GoogleCalendarGatewayErrorCode
  public let exitCode: GoogleCalendarGatewayExitCode
  public let details: [String: String]

  public init(
    _ message: String,
    code: GoogleCalendarGatewayErrorCode,
    exitCode: GoogleCalendarGatewayExitCode,
    details: [String: String] = [:]
  ) {
    self.message = message
    self.code = code
    self.exitCode = exitCode
    self.details = details
  }
}

public enum CalendarProvider: String, Codable, Equatable, Sendable {
  case google

  var graphQLValue: String {
    switch self {
    case .google:
      return "GOOGLE"
    }
  }
}

public enum CalendarAccessMode: String, Codable, Equatable, Sendable {
  case full
  case read
  case readWrite = "read_write"

  var graphQLValue: String {
    switch self {
    case .full:
      return "FULL"
    case .read:
      return "READ"
    case .readWrite:
      return "READ_WRITE"
    }
  }
}

public enum CalendarAuthState: String, Codable, Equatable, Sendable {
  case missing = "MISSING"
  case ready = "READY"
  case expired = "EXPIRED"
  case scopeMismatch = "SCOPE_MISMATCH"
  case invalid = "INVALID"
  case unknown = "UNKNOWN"
}

public enum CalendarEventOrderBy: String, Codable, Equatable, Sendable {
  case startTime
  case updated
}

public enum CalendarEventReminderMethod: String, Codable, Equatable, Sendable {
  case email
  case popup
}

public enum CalendarEventVisibility: String, Codable, Equatable, Sendable {
  case `default`
  case `public`
  case `private`
  case confidential
}

public enum CalendarEventTransparency: String, Codable, Equatable, Sendable {
  case opaque
  case transparent
}

public struct CalendarStorageConfig: Sendable {
  public let cacheDir: String
}

public struct CalendarCredentialConfig: Sendable {
  public let id: String
  public let provider: CalendarProvider
  public let accessMode: CalendarAccessMode
  public let oauthClientSecretPath: String
  public let oauthClientSecretJSON: String?
  public let tokenStorePath: String
  public let tokenStoreJSON: String?
  public let tokenStorePathFromEnvironment: Bool

  public init(
    id: String, provider: CalendarProvider, accessMode: CalendarAccessMode,
    oauthClientSecretPath: String, oauthClientSecretJSON: String?,
    tokenStorePath: String, tokenStoreJSON: String?, tokenStorePathFromEnvironment: Bool = false
  ) {
    self.id = id
    self.provider = provider
    self.accessMode = accessMode
    self.oauthClientSecretPath = oauthClientSecretPath
    self.oauthClientSecretJSON = oauthClientSecretJSON
    self.tokenStorePath = tokenStorePath
    self.tokenStoreJSON = tokenStoreJSON
    self.tokenStorePathFromEnvironment = tokenStorePathFromEnvironment
  }
}

public struct CalendarAccountConfig: Sendable {
  public let id: String
  public let displayName: String?
  public let provider: CalendarProvider
  public let emailAddress: String
  public let credentialId: String
  public let calendarIds: [String]
  public let defaultCalendarId: String
  public let defaultTimeZone: String?
}

public struct GoogleCalendarGatewayConfig: Sendable {
  public let configPath: String
  public let storage: CalendarStorageConfig
  public let credentials: [CalendarCredentialConfig]
  public let accounts: [CalendarAccountConfig]
}

public struct CalendarEventSearch: Sendable {
  public let accountId: String
  public let calendarId: String?
  public let query: String?
  public let timeMin: String?
  public let timeMax: String?
  public let updatedMin: String?
  public let maxResults: Int?
  public let pageToken: String?
  public let syncToken: String?
  public let showDeleted: Bool?
  public let singleEvents: Bool
  public let orderBy: CalendarEventOrderBy?

  public init(
    accountId: String,
    calendarId: String? = nil,
    query: String? = nil,
    timeMin: String? = nil,
    timeMax: String? = nil,
    updatedMin: String? = nil,
    maxResults: Int? = nil,
    pageToken: String? = nil,
    syncToken: String? = nil,
    showDeleted: Bool? = nil,
    singleEvents: Bool = true,
    orderBy: CalendarEventOrderBy? = nil
  ) {
    self.accountId = accountId
    self.calendarId = calendarId
    self.query = query
    self.timeMin = timeMin
    self.timeMax = timeMax
    self.updatedMin = updatedMin
    self.maxResults = maxResults
    self.pageToken = pageToken
    self.syncToken = syncToken
    self.showDeleted = showDeleted
    self.singleEvents = singleEvents
    self.orderBy = orderBy
  }
}

public struct CalendarFreeBusyQuery: Sendable {
  public let accountId: String
  public let calendarIds: [String]
  public let timeMin: String
  public let timeMax: String
  public let timeZone: String?
  public let groupExpansionMax: Int?
  public let calendarExpansionMax: Int?

  public init(
    accountId: String,
    calendarIds: [String] = [],
    timeMin: String,
    timeMax: String,
    timeZone: String? = nil,
    groupExpansionMax: Int? = nil,
    calendarExpansionMax: Int? = nil
  ) {
    self.accountId = accountId
    self.calendarIds = calendarIds
    self.timeMin = timeMin
    self.timeMax = timeMax
    self.timeZone = timeZone
    self.groupExpansionMax = groupExpansionMax
    self.calendarExpansionMax = calendarExpansionMax
  }
}

public struct CalendarEventInput: Sendable {
  public let accountId: String
  public let calendarId: String?
  public let eventId: String?
  public let summary: String?
  public let description: String?
  public let location: String?
  public let colorId: String?
  public let visibility: CalendarEventVisibility?
  public let transparency: CalendarEventTransparency?
  public let start: String?
  public let end: String?
  public let timeZone: String?
  public let attendeeEmails: [String]
  public let recurrenceRules: [String]
  public let reminderUseDefault: Bool?
  public let reminderOverrides: [CalendarEventReminder]
  public let createConference: Bool
  public let conferenceRequestId: String?
  public let sendUpdates: String?

  public init(
    accountId: String,
    calendarId: String? = nil,
    eventId: String? = nil,
    summary: String? = nil,
    description: String? = nil,
    location: String? = nil,
    colorId: String? = nil,
    visibility: CalendarEventVisibility? = nil,
    transparency: CalendarEventTransparency? = nil,
    start: String? = nil,
    end: String? = nil,
    timeZone: String? = nil,
    attendeeEmails: [String] = [],
    recurrenceRules: [String] = [],
    reminderUseDefault: Bool? = nil,
    reminderOverrides: [CalendarEventReminder] = [],
    createConference: Bool = false,
    conferenceRequestId: String? = nil,
    sendUpdates: String? = nil
  ) {
    self.accountId = accountId
    self.calendarId = calendarId
    self.eventId = eventId
    self.summary = summary
    self.description = description
    self.location = location
    self.colorId = colorId
    self.visibility = visibility
    self.transparency = transparency
    self.start = start
    self.end = end
    self.timeZone = timeZone
    self.attendeeEmails = attendeeEmails
    self.recurrenceRules = recurrenceRules
    self.reminderUseDefault = reminderUseDefault
    self.reminderOverrides = reminderOverrides
    self.createConference = createConference
    self.conferenceRequestId = conferenceRequestId
    self.sendUpdates = sendUpdates
  }
}

public protocol CalendarEventProvider {
  func listCalendars(credential: CalendarCredentialConfig) throws -> [ProviderCalendarInfo]

  func listEvents(
    account: CalendarAccountConfig,
    credential: CalendarCredentialConfig,
    search: CalendarEventSearch
  ) throws -> CalendarEventConnection

  func getEvent(
    account: CalendarAccountConfig,
    credential: CalendarCredentialConfig,
    calendarId: String,
    eventId: String
  ) throws -> CalendarEvent

  func queryFreeBusy(
    account: CalendarAccountConfig,
    credential: CalendarCredentialConfig,
    query: CalendarFreeBusyQuery
  ) throws -> CalendarFreeBusyResponse

  func createEvent(
    account: CalendarAccountConfig,
    credential: CalendarCredentialConfig,
    input: CalendarEventInput
  ) throws -> CalendarEvent

  func updateEvent(
    account: CalendarAccountConfig,
    credential: CalendarCredentialConfig,
    input: CalendarEventInput
  ) throws -> CalendarEvent

  func deleteEvent(
    account: CalendarAccountConfig,
    credential: CalendarCredentialConfig,
    calendarId: String,
    eventId: String,
    sendUpdates: String?
  ) throws -> [String: Any]

  func executeCalendarAPI(
    credential: CalendarCredentialConfig,
    request: CalendarRawAPIRequest
  ) throws -> [String: Any]
}

public struct GoogleCalendarGatewayService {
  public let config: GoogleCalendarGatewayConfig
  let provider: any CalendarEventProvider

  public init(config: GoogleCalendarGatewayConfig) {
    self.init(config: config, provider: GoogleCalendarLiveClient())
  }

  public init(config: GoogleCalendarGatewayConfig, provider: any CalendarEventProvider) {
    self.config = config
    self.provider = provider
  }

  public func calendars() -> [CalendarInfo] {
    config.accounts.sorted { $0.id < $1.id }.map(calendarInfo)
  }

  public func calendar(id: String) -> CalendarInfo? {
    guard let account = config.accounts.first(where: { $0.id == id }) else {
      return nil
    }
    return calendarInfo(account)
  }

  public func listAccounts() -> [[String: Any]] {
    calendars().map { info in
      var object = info.graphQLObject
      object["provider"] = info.provider.rawValue
      if var capabilities = object["capabilities"] as? [String: Any] {
        capabilities["configuredAccessMode"] = info.capabilities.configuredAccessMode.rawValue
        object["capabilities"] = capabilities
      }
      return object
    }
  }

  public func graphQLAccounts() -> [[String: Any]] {
    calendars().map(\.graphQLObject)
  }

  public func graphQLAccount(id: String) -> [String: Any]? {
    calendar(id: id)?.graphQLObject
  }

  public func listProviderCalendars(credentialId: String) throws -> [ProviderCalendarInfo] {
    let credential = try requireCredential(credentialId)
    return try provider.listCalendars(credential: credential)
  }

  public func graphQLProviderCalendars(credentialId: String) throws -> [[String: Any]] {
    try listProviderCalendars(credentialId: credentialId).map(\.graphQLObject)
  }

  public func listEvents(search: CalendarEventSearch) throws -> [String: Any] {
    try searchEvents(search: search).graphQLObject
  }

  public func searchEvents(search: CalendarEventSearch) throws -> CalendarEventConnection {
    try validateMaxResults(search.maxResults)
    try validateEventSearch(search)
    let account = try requireAccount(search.accountId)
    let credential = try requireCredential(account.credentialId)
    return try provider.listEvents(
      account: account,
      credential: credential,
      search: try normalizedEventSearch(search)
    )
  }

  public func getEvent(accountId: String, calendarId: String? = nil, eventId: String) throws -> Any {
    try calendarEvent(accountId: accountId, calendarId: calendarId, eventId: eventId).graphQLObject
  }

  public func calendarEvent(accountId: String, calendarId: String? = nil, eventId: String) throws -> CalendarEvent {
    let account = try requireAccount(accountId)
    let credential = try requireCredential(account.credentialId)
    guard let eventId = nonBlank(eventId) else {
      throw GoogleCalendarGatewayError(
        "eventId must be a non-empty string",
        code: .invalidArgument,
        exitCode: .graphqlExecutionError
      )
    }
    return try provider.getEvent(
      account: account,
      credential: credential,
      calendarId: try normalizedProviderCalendarId(calendarId, defaultCalendarId: account.defaultCalendarId),
      eventId: eventId
    )
  }

  public func freeBusy(query: CalendarFreeBusyQuery) throws -> [String: Any] {
    try queryFreeBusy(query: query).graphQLObject
  }

  public func queryFreeBusy(query: CalendarFreeBusyQuery) throws -> CalendarFreeBusyResponse {
    let account = try requireAccount(query.accountId)
    let credential = try requireCredential(account.credentialId)
    let normalizedQuery = try validateFreeBusyQuery(query, account: account)
    return try provider.queryFreeBusy(account: account, credential: credential, query: normalizedQuery)
  }

  public func getAuthStatus(credentialId: String) throws -> [String: Any] {
    let credential = try requireCredential(credentialId)
    let tokenState = inspectCalendarTokenStore(credential: credential)
    return [
      "credentialId": credential.id,
      "provider": credential.provider.rawValue,
      "configuredAccessMode": credential.accessMode.rawValue,
      "state": tokenState.state.rawValue,
      "tokenStorePath": credential.tokenStorePath,
      "tokenStoreExists": tokenState.exists,
      "grantedAccessMode": tokenState.grantedAccessMode?.rawValue as Any? ?? NSNull(),
      "expiresAt": tokenState.expiresAt as Any? ?? NSNull(),
      "hasRefreshToken": tokenState.hasRefreshToken
    ].merging(calendarTokenSourceDetails(credential)) { current, _ in current }
  }

  public func revokeAuth(credentialId: String) throws -> [String: Any] {
    try revokeAuth(credentialId: credentialId, revokeProviderToken: revokeGoogleOAuthToken)
  }

  func revokeAuth(
    credentialId: String,
    revokeProviderToken: (String) throws -> Void
  ) throws -> [String: Any] {
    let credential = try requireCredential(credentialId)
    let tokenStore = try? loadGoogleCalendarOAuthTokenStore(
      credential: credential,
      missingAuthMessage: "Google Calendar token store does not exist"
    )

    var providerRevocationAttempted = false
    var providerRevoked = false
    var providerRevocationError: String?
    if let token = nonBlank(tokenStore?.refreshToken) ?? nonBlank(tokenStore?.accessToken) {
      providerRevocationAttempted = true
      do {
        try revokeProviderToken(token)
        providerRevoked = true
      } catch let error as GoogleCalendarGatewayError {
        providerRevocationError = error.message
      } catch {
        providerRevocationError = error.localizedDescription
      }
    }

    var localTokenDeleted = false
    var localDeletionSkipped = false
    var localDeletionReason: String?
    if credential.tokenStoreJSON != nil {
      localDeletionSkipped = true
      localDeletionReason = "token store is supplied by environment"
    } else if calendarTokenFileExists(at: credential.tokenStorePath) {
      do {
        localTokenDeleted = try removeCalendarSecureTokenFile(at: credential.tokenStorePath)
      } catch {
        throw GoogleCalendarGatewayError(
          "Failed to delete token store for credential \(credential.id)",
          code: .authRequired,
          exitCode: .authenticationBootstrapError,
          details: ["cause": error.localizedDescription]
        )
      }
    }

    return [
      "credentialId": credentialId,
      "revoked": providerRevoked || localTokenDeleted,
      "providerRevocationAttempted": providerRevocationAttempted,
      "providerRevoked": providerRevoked,
      "providerRevocationError": providerRevocationError as Any? ?? NSNull(),
      "localTokenDeleted": localTokenDeleted,
      "localDeletionSkipped": localDeletionSkipped,
      "localDeletionReason": localDeletionReason as Any? ?? NSNull()
    ]
  }

  public func login(credentialId: String, options: GoogleCalendarOAuthLoginOptions = .default) throws -> [String: Any] {
    let credential = try requireCredential(credentialId)
    return try GoogleCalendarOAuthBootstrapper().login(credential: credential, options: options)
  }

  func requireCredential(_ credentialId: String) throws -> CalendarCredentialConfig {
    guard let credential = config.credentials.first(where: { $0.id == credentialId }) else {
      throw GoogleCalendarGatewayError(
        "Unknown credential: \(credentialId)",
        code: .credentialNotFound,
        exitCode: .configurationError
      )
    }
    return credential
  }

  func requireWriteCredential(_ credentialId: String) throws -> CalendarCredentialConfig {
    let credential = try requireCredential(credentialId)
    guard credential.accessMode == .readWrite || credential.accessMode == .full else {
      throw GoogleCalendarGatewayError(
        "Google Calendar write operations require access_mode = \"read_write\" or \"full\"",
        code: .writeDisabled,
        exitCode: .graphqlExecutionError,
        details: ["credentialId": credential.id]
      )
    }
    return credential
  }

  func requireAccount(_ accountId: String) throws -> CalendarAccountConfig {
    guard nonBlank(accountId) != nil else {
      throw GoogleCalendarGatewayError(
        "accountId must be a non-empty string",
        code: .invalidArgument,
        exitCode: .graphqlExecutionError
      )
    }
    guard let account = config.accounts.first(where: { $0.id == accountId }) else {
      throw GoogleCalendarGatewayError(
        "Unknown account: \(accountId)",
        code: .accountNotFound,
        exitCode: .graphqlExecutionError
      )
    }
    return account
  }

  private func calendarInfo(_ account: CalendarAccountConfig) -> CalendarInfo {
    let credential = try? requireCredential(account.credentialId)
    let tokenState = credential.map(inspectCalendarTokenStore)?.state ?? .missing
    return CalendarInfo(
      id: account.id,
      displayName: account.displayName,
      provider: account.provider,
      emailAddress: account.emailAddress,
      calendarIds: account.calendarIds,
      defaultCalendarId: account.defaultCalendarId,
      defaultTimeZone: account.defaultTimeZone,
      capabilities: CalendarCapabilities(
        canRead: true,
        canWriteEvents: credential?.accessMode == .readWrite || credential?.accessMode == .full,
        configuredAccessMode: credential?.accessMode ?? .read,
        authState: tokenState
      )
    )
  }
}

public typealias GoogleCalendarGatewayClient = GoogleCalendarGatewayService

public enum Version {
  public static let current = "0.1.10"
}

func validateSendUpdates(_ sendUpdates: String?) throws {
  guard let sendUpdates = nonBlank(sendUpdates) else {
    return
  }
  guard ["all", "externalOnly", "none"].contains(sendUpdates) else {
    throw GoogleCalendarGatewayError(
      "sendUpdates must be one of: all, externalOnly, none",
      code: .invalidArgument,
      exitCode: .graphqlExecutionError
    )
  }
}

func validateMaxResults(_ maxResults: Int?) throws {
  guard let maxResults else {
    return
  }
  guard (1...2500).contains(maxResults) else {
    throw GoogleCalendarGatewayError(
      "maxResults must be between 1 and 2500",
      code: .invalidArgument,
      exitCode: .graphqlExecutionError
    )
  }
}

func validateEventSearch(_ search: CalendarEventSearch) throws {
  try validateProviderCalendarId(search.calendarId)
  if let timeMin = nonBlank(search.timeMin), !isRFC3339DateTime(timeMin) {
    throw GoogleCalendarGatewayError(
      "timeMin must be an RFC 3339 date-time string",
      code: .invalidArgument,
      exitCode: .graphqlExecutionError
    )
  }
  if let timeMax = nonBlank(search.timeMax), !isRFC3339DateTime(timeMax) {
    throw GoogleCalendarGatewayError(
      "timeMax must be an RFC 3339 date-time string",
      code: .invalidArgument,
      exitCode: .graphqlExecutionError
    )
  }
  if let updatedMin = nonBlank(search.updatedMin), !isRFC3339DateTime(updatedMin) {
    throw GoogleCalendarGatewayError(
      "updatedMin must be an RFC 3339 date-time string",
      code: .invalidArgument,
      exitCode: .graphqlExecutionError
    )
  }
  if search.orderBy == .startTime, !search.singleEvents {
    throw GoogleCalendarGatewayError(
      "orderBy = startTime requires singleEvents = true",
      code: .invalidArgument,
      exitCode: .graphqlExecutionError
    )
  }
  guard nonBlank(search.syncToken) != nil else {
    return
  }
  let incompatibleArguments = [
    nonBlank(search.query).map { _ in "query" },
    nonBlank(search.timeMin).map { _ in "timeMin" },
    nonBlank(search.timeMax).map { _ in "timeMax" },
    nonBlank(search.updatedMin).map { _ in "updatedMin" },
    search.orderBy.map { _ in "orderBy" }
  ].compactMap { $0 }
  if !incompatibleArguments.isEmpty {
    throw GoogleCalendarGatewayError(
      "syncToken cannot be combined with: \(incompatibleArguments.joined(separator: ", "))",
      code: .invalidArgument,
      exitCode: .graphqlExecutionError
    )
  }
  if search.showDeleted == false {
    throw GoogleCalendarGatewayError(
      "syncToken cannot be combined with showDeleted = false",
      code: .invalidArgument,
      exitCode: .graphqlExecutionError
    )
  }
}

private func normalizedEventSearch(_ search: CalendarEventSearch) throws -> CalendarEventSearch {
  CalendarEventSearch(
    accountId: search.accountId,
    calendarId: try normalizedOptionalProviderCalendarId(search.calendarId),
    query: search.query,
    timeMin: search.timeMin,
    timeMax: search.timeMax,
    updatedMin: search.updatedMin,
    maxResults: search.maxResults,
    pageToken: search.pageToken,
    syncToken: search.syncToken,
    showDeleted: search.showDeleted,
    singleEvents: search.singleEvents,
    orderBy: search.orderBy
  )
}

private func validateProviderCalendarId(_ calendarId: String?) throws {
  _ = try normalizedOptionalProviderCalendarId(calendarId)
}

func normalizedProviderCalendarId(_ calendarId: String?, defaultCalendarId: String) throws -> String {
  try normalizedOptionalProviderCalendarId(calendarId) ?? defaultCalendarId
}

func normalizedOptionalProviderCalendarId(_ calendarId: String?) throws -> String? {
  guard let calendarId else {
    return nil
  }
  guard let normalized = nonBlank(calendarId) else {
    throw GoogleCalendarGatewayError(
      "providerCalendarId must be a non-empty string",
      code: .invalidArgument,
      exitCode: .graphqlExecutionError
    )
  }
  return normalized
}

func validateFreeBusyQuery(_ query: CalendarFreeBusyQuery, account: CalendarAccountConfig) throws -> CalendarFreeBusyQuery {
  guard isRFC3339DateTime(query.timeMin) else {
    throw GoogleCalendarGatewayError(
      "freeBusy timeMin must be an RFC 3339 date-time string",
      code: .invalidArgument,
      exitCode: .graphqlExecutionError
    )
  }
  guard isRFC3339DateTime(query.timeMax) else {
    throw GoogleCalendarGatewayError(
      "freeBusy timeMax must be an RFC 3339 date-time string",
      code: .invalidArgument,
      exitCode: .graphqlExecutionError
    )
  }
  let calendarIds = try normalizedFreeBusyCalendarIds(query.calendarIds, account: account)
  try validateExpansionMax(query.groupExpansionMax, name: "groupExpansionMax", range: 1...100)
  try validateExpansionMax(query.calendarExpansionMax, name: "calendarExpansionMax", range: 1...50)
  return CalendarFreeBusyQuery(
    accountId: query.accountId,
    calendarIds: calendarIds,
    timeMin: query.timeMin,
    timeMax: query.timeMax,
    timeZone: nonBlank(query.timeZone) ?? account.defaultTimeZone,
    groupExpansionMax: query.groupExpansionMax,
    calendarExpansionMax: query.calendarExpansionMax
  )
}

private func normalizedFreeBusyCalendarIds(_ calendarIds: [String], account: CalendarAccountConfig) throws -> [String] {
  if calendarIds.isEmpty {
    return [account.defaultCalendarId]
  }
  let normalized = calendarIds.compactMap(nonBlank)
  guard normalized.count == calendarIds.count else {
    throw GoogleCalendarGatewayError(
      "freeBusy calendar IDs must be non-empty strings",
      code: .invalidArgument,
      exitCode: .graphqlExecutionError
    )
  }
  guard normalized.count <= 50 else {
    throw GoogleCalendarGatewayError(
      "freeBusy accepts at most 50 calendar IDs",
      code: .invalidArgument,
      exitCode: .graphqlExecutionError
    )
  }
  return normalized
}

private func validateExpansionMax(_ value: Int?, name: String, range: ClosedRange<Int>) throws {
  guard let value else {
    return
  }
  guard range.contains(value) else {
    throw GoogleCalendarGatewayError(
      "\(name) must be between \(range.lowerBound) and \(range.upperBound)",
      code: .invalidArgument,
      exitCode: .graphqlExecutionError
    )
  }
}

func validateEventInput(_ input: CalendarEventInput, requireStartEnd: Bool) throws {
  try validateProviderCalendarId(input.calendarId)
  if requireStartEnd {
    guard nonBlank(input.start) != nil else {
      throw GoogleCalendarGatewayError("createEvent requires start", code: .invalidArgument, exitCode: .graphqlExecutionError)
    }
    guard nonBlank(input.end) != nil else {
      throw GoogleCalendarGatewayError("createEvent requires end", code: .invalidArgument, exitCode: .graphqlExecutionError)
    }
  }
  try validateEventDateValue(input.start, name: "start")
  try validateEventDateValue(input.end, name: "end")
  if !eventInputContainsWritableField(input) {
    throw GoogleCalendarGatewayError(
      "Event input must contain at least one writable field",
      code: .invalidArgument,
      exitCode: .graphqlExecutionError
    )
  }
  for attendeeEmail in input.attendeeEmails {
    guard isValidAttendeeEmail(attendeeEmail) else {
      throw GoogleCalendarGatewayError(
        "attendeeEmails must contain non-empty email addresses",
        code: .invalidArgument,
        exitCode: .graphqlExecutionError
      )
    }
  }
  try validateEventMetadataInput(input)
  try validateRecurrenceRules(input)
  try validateReminderInput(input)
}

private func validateEventDateValue(_ value: String?, name: String) throws {
  guard value != nil else {
    return
  }
  guard let value = nonBlank(value),
        isCalendarDate(value) || isRFC3339DateTime(value) else {
    throw GoogleCalendarGatewayError(
      "\(name) must be an RFC 3339 date-time or YYYY-MM-DD date string",
      code: .invalidArgument,
      exitCode: .graphqlExecutionError
    )
  }
}

private func eventInputContainsWritableField(_ input: CalendarEventInput) -> Bool {
  nonBlank(input.summary) != nil ||
    nonBlank(input.description) != nil ||
    nonBlank(input.location) != nil ||
    nonBlank(input.colorId) != nil ||
    input.visibility != nil ||
    input.transparency != nil ||
    nonBlank(input.start) != nil ||
    nonBlank(input.end) != nil ||
    !input.attendeeEmails.isEmpty ||
    !input.recurrenceRules.isEmpty ||
    input.reminderUseDefault != nil ||
    !input.reminderOverrides.isEmpty ||
    input.createConference
}

private func isValidAttendeeEmail(_ value: String) -> Bool {
  guard let value = nonBlank(value),
        value.contains("@"),
        !value.hasPrefix("@"),
        !value.hasSuffix("@") else {
    return false
  }
  return true
}

private func validateEventMetadataInput(_ input: CalendarEventInput) throws {
  if let colorId = input.colorId, nonBlank(colorId) == nil {
    throw GoogleCalendarGatewayError(
      "colorId must be a non-empty string",
      code: .invalidArgument,
      exitCode: .graphqlExecutionError
    )
  }
  if let conferenceRequestId = input.conferenceRequestId, nonBlank(conferenceRequestId) == nil {
    throw GoogleCalendarGatewayError(
      "conferenceRequestId must be a non-empty string",
      code: .invalidArgument,
      exitCode: .graphqlExecutionError
    )
  }
  if nonBlank(input.conferenceRequestId) != nil, !input.createConference {
    throw GoogleCalendarGatewayError(
      "conferenceRequestId requires createConference = true",
      code: .invalidArgument,
      exitCode: .graphqlExecutionError
    )
  }
}

private func validateRecurrenceRules(_ input: CalendarEventInput) throws {
  guard !input.recurrenceRules.isEmpty else {
    return
  }
  for rule in input.recurrenceRules {
    guard let rule = nonBlank(rule) else {
      throw GoogleCalendarGatewayError(
        "recurrenceRules must contain non-empty strings",
        code: .invalidArgument,
        exitCode: .graphqlExecutionError
      )
    }
    let uppercasedRule = rule.uppercased()
    if uppercasedRule.hasPrefix("DTSTART") || uppercasedRule.hasPrefix("DTEND") {
      throw GoogleCalendarGatewayError(
        "recurrenceRules must not contain DTSTART or DTEND",
        code: .invalidArgument,
        exitCode: .graphqlExecutionError
      )
    }
  }
  if isTimedCalendarValue(input.start) || isTimedCalendarValue(input.end) {
    guard nonBlank(input.timeZone) != nil else {
      throw GoogleCalendarGatewayError(
        "Recurring timed events require timeZone",
        code: .invalidArgument,
        exitCode: .graphqlExecutionError
      )
    }
  }
}

private func validateReminderInput(_ input: CalendarEventInput) throws {
  if input.reminderUseDefault == true, !input.reminderOverrides.isEmpty {
    throw GoogleCalendarGatewayError(
      "reminderUseDefault cannot be true when reminderOverrides are supplied",
      code: .invalidArgument,
      exitCode: .graphqlExecutionError
    )
  }
  guard input.reminderOverrides.count <= 5 else {
    throw GoogleCalendarGatewayError(
      "reminderOverrides accepts at most 5 reminders",
      code: .invalidArgument,
      exitCode: .graphqlExecutionError
    )
  }
  for reminder in input.reminderOverrides {
    guard (0...40320).contains(reminder.minutes) else {
      throw GoogleCalendarGatewayError(
        "reminderOverrides minutes must be between 0 and 40320",
        code: .invalidArgument,
        exitCode: .graphqlExecutionError
      )
    }
  }
}

private func isTimedCalendarValue(_ value: String?) -> Bool {
  nonBlank(value)?.contains("T") == true
}
