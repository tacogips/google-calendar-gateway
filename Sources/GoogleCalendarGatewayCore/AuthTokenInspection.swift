import Foundation

public struct CalendarTokenInspection: Sendable {
  public let state: CalendarAuthState
  public let exists: Bool
  public let grantedAccessMode: CalendarAccessMode?
  public let expiresAt: String?
  public let hasRefreshToken: Bool
}

struct CalendarOAuthTokenStore: Codable {
  let accessMode: CalendarAccessMode?
  let accessToken: String?
  let refreshToken: String?
  let tokenType: String?
  let scope: String?
  let expiresAt: String?
  let emailAddress: String?
}

public func inspectCalendarTokenStore(credential: CalendarCredentialConfig) -> CalendarTokenInspection {
  let data: Data
  if let tokenStoreJSON = credential.tokenStoreJSON {
    data = Data(tokenStoreJSON.utf8)
  } else if let fileData = try? calendarSecureTokenFileData(at: credential.tokenStorePath) {
    data = fileData
  } else {
    return CalendarTokenInspection(
      state: .missing,
      exists: false,
      grantedAccessMode: nil,
      expiresAt: nil,
      hasRefreshToken: false
    )
  }

  guard let tokenStore = try? JSONDecoder().decode(CalendarOAuthTokenStore.self, from: data) else {
    return CalendarTokenInspection(
      state: .invalid,
      exists: true,
      grantedAccessMode: nil,
      expiresAt: nil,
      hasRefreshToken: false
    )
  }

  let grantedAccessMode = tokenStore.accessMode ?? accessModeFromScopes(tokenStore.scope)
  let state: CalendarAuthState
  if let grantedAccessMode, !calendarAccessMode(grantedAccessMode, covers: credential.accessMode) {
    state = .scopeMismatch
  } else if let scope = nonBlank(tokenStore.scope),
            !calendarScopesCover(accessMode: credential.accessMode, grantedScope: scope) {
    state = .scopeMismatch
  } else if calendarAccessTokenIsFresh(expiresAt: tokenStore.expiresAt) {
    state = .ready
  } else {
    state = .expired
  }

  return CalendarTokenInspection(
    state: state,
    exists: true,
    grantedAccessMode: grantedAccessMode,
    expiresAt: tokenStore.expiresAt,
    hasRefreshToken: nonBlank(tokenStore.refreshToken) != nil
  )
}

func calendarAccessTokenIsFresh(
  expiresAt: String?,
  now: Date = Date(),
  refreshLeeway: TimeInterval = 60
) -> Bool {
  guard let expiresAt = nonBlank(expiresAt) else {
    return true
  }
  guard let expiry = ISO8601DateFormatter().date(from: expiresAt) else {
    return false
  }
  return expiry.timeIntervalSince(now) > refreshLeeway
}

func accessModeFromScopes(_ scope: String?) -> CalendarAccessMode? {
  guard let scope else {
    return nil
  }
  let scopes = calendarScopeSet(scope)
  if scopes.contains("https://www.googleapis.com/auth/calendar") {
    return .full
  }
  if scopes.contains("https://www.googleapis.com/auth/calendar.events") &&
      calendarScopesAllowCalendarListRead(scopes) &&
      calendarScopesAllowFreeBusyRead(scopes) {
    return .readWrite
  }
  if scopes.contains("https://www.googleapis.com/auth/calendar.readonly") ||
    (
      scopes.contains("https://www.googleapis.com/auth/calendar.events.readonly") &&
      calendarScopesAllowCalendarListRead(scopes) &&
      calendarScopesAllowFreeBusyRead(scopes)
    ) {
    return .read
  }
  return nil
}

func calendarScopesCover(accessMode: CalendarAccessMode, grantedScope: String?) -> Bool {
  guard let grantedScope = nonBlank(grantedScope) else {
    return true
  }
  let scopes = calendarScopeSet(grantedScope)
  switch accessMode {
  case .full:
    return scopes.contains("https://www.googleapis.com/auth/calendar")
  case .read:
    return calendarScopesAllowReadEvents(scopes) &&
      calendarScopesAllowCalendarListRead(scopes) &&
      calendarScopesAllowFreeBusyRead(scopes)
  case .readWrite:
    return calendarScopesAllowWriteEvents(scopes) &&
      calendarScopesAllowCalendarListRead(scopes) &&
      calendarScopesAllowFreeBusyRead(scopes)
  }
}

func calendarAccessMode(_ granted: CalendarAccessMode, covers configured: CalendarAccessMode) -> Bool {
  switch (granted, configured) {
  case (.full, _), (.readWrite, .read), (.readWrite, .readWrite), (.read, .read):
    return true
  case (.read, .readWrite), (.read, .full), (.readWrite, .full):
    return false
  }
}

private func calendarScopeSet(_ scope: String) -> Set<String> {
  Set(scope.split(separator: " ").map(String.init))
}

private func calendarScopesAllowReadEvents(_ scopes: Set<String>) -> Bool {
  scopes.contains("https://www.googleapis.com/auth/calendar") ||
    scopes.contains("https://www.googleapis.com/auth/calendar.readonly") ||
    scopes.contains("https://www.googleapis.com/auth/calendar.events") ||
    scopes.contains("https://www.googleapis.com/auth/calendar.events.readonly")
}

private func calendarScopesAllowWriteEvents(_ scopes: Set<String>) -> Bool {
  scopes.contains("https://www.googleapis.com/auth/calendar") ||
    scopes.contains("https://www.googleapis.com/auth/calendar.events")
}

private func calendarScopesAllowCalendarListRead(_ scopes: Set<String>) -> Bool {
  scopes.contains("https://www.googleapis.com/auth/calendar") ||
    scopes.contains("https://www.googleapis.com/auth/calendar.readonly") ||
    scopes.contains("https://www.googleapis.com/auth/calendar.calendarlist") ||
    scopes.contains("https://www.googleapis.com/auth/calendar.calendarlist.readonly")
}

private func calendarScopesAllowFreeBusyRead(_ scopes: Set<String>) -> Bool {
  scopes.contains("https://www.googleapis.com/auth/calendar") ||
    scopes.contains("https://www.googleapis.com/auth/calendar.readonly") ||
    scopes.contains("https://www.googleapis.com/auth/calendar.freebusy") ||
    scopes.contains("https://www.googleapis.com/auth/calendar.events.freebusy")
}
