import Foundation

private enum TomlSection {
  case none
  case storage
  case credential(Int)
  case calendar(Int)
}

private struct CredentialPathRequest {
  let configPath: String
  let credentialId: String
  let pathKey: String
  let configValue: String?
  let environment: [String: String]
  let context: String
}

public enum GoogleCalendarGatewayConfigLoader {
  private static let defaultCredentialId = "google-personal"
  private static let defaultAccountId = "personal"

  public static func getCredentialPathEnvVarName(credentialId: String, pathKey: String) -> String {
    let safeSuffix = credentialEnvSuffix(credentialId)
    if pathKey == "oauth_client_secret_path" {
      return "GOOGLE_CALENDAR_GATEWAY_CREDENTIAL_\(safeSuffix)_OAUTH_CLIENT_SECRET_PATH"
    }
    return "GOOGLE_CALENDAR_GATEWAY_CREDENTIAL_\(safeSuffix)_TOKEN_STORE_PATH"
  }

  public static func getCredentialJSONEnvVarName(credentialId: String, valueKey: String) -> String {
    let safeSuffix = credentialEnvSuffix(credentialId)
    if valueKey == "oauth_client_secret_json" {
      return "GOOGLE_CALENDAR_GATEWAY_CREDENTIAL_\(safeSuffix)_OAUTH_CLIENT_SECRET_JSON"
    }
    return "GOOGLE_CALENDAR_GATEWAY_CREDENTIAL_\(safeSuffix)_TOKEN_STORE_JSON"
  }

  /// Default directory for persisted OAuth token stores. Tokens are auth
  /// state, not configuration, so the default lives under XDG_STATE_HOME
  /// (~/.local/state), never ~/.config. GOOGLE_CALENDAR_GATEWAY_CREDENTIAL_DIR
  /// relocates the directory; a per-credential *_TOKEN_STORE_PATH still wins
  /// for one file.
  public static func resolveDefaultCredentialDirectory(
    environment: [String: String] = ProcessInfo.processInfo.environment
  ) -> String {
    if let credentialDir = nonBlank(environment["GOOGLE_CALENDAR_GATEWAY_CREDENTIAL_DIR"]) {
      return normalizedPath(credentialDir)
    }
    let stateRoot = nonBlank(environment["XDG_STATE_HOME"]).flatMap { $0.hasPrefix("/") ? $0 : nil }
      ?? FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent(".local")
        .appendingPathComponent("state")
        .path
    return normalizedPath(URL(fileURLWithPath: stateRoot)
      .appendingPathComponent("google-calendar-gateway")
      .appendingPathComponent("credentials")
      .path)
  }

  public static func resolveDefaultConfigPath(
    environment: [String: String] = ProcessInfo.processInfo.environment
  ) -> String {
    if let xdgConfigHome = nonBlank(environment["XDG_CONFIG_HOME"]), xdgConfigHome.hasPrefix("/") {
      return normalizedPath(URL(fileURLWithPath: xdgConfigHome)
        .appendingPathComponent("google-calendar-gateway")
        .appendingPathComponent("config.toml")
        .path)
    }
    return normalizedPath(FileManager.default.homeDirectoryForCurrentUser
      .appendingPathComponent(".config")
      .appendingPathComponent("google-calendar-gateway")
      .appendingPathComponent("config.toml")
      .path)
  }

  public static func loadConfig(
    configPath: String? = nil,
    environment sourceEnvironment: [String: String] = ProcessInfo.processInfo.environment
  ) throws -> GoogleCalendarGatewayConfig {
    let initialEnvironment = sourceEnvironment
    let explicitConfigPath = nonBlank(configPath) ?? nonBlank(initialEnvironment["GOOGLE_CALENDAR_GATEWAY_CONFIG"])
    let usesImplicitDefaultConfig = explicitConfigPath == nil
    let selectedConfigPath = normalizedPath(explicitConfigPath ?? resolveDefaultConfigPath(environment: initialEnvironment))
    let source: String
    do {
      source = try String(contentsOfFile: selectedConfigPath, encoding: .utf8)
    } catch {
      if usesImplicitDefaultConfig,
         !FileManager.default.fileExists(atPath: selectedConfigPath) {
        return try defaultConfig(configPath: selectedConfigPath, environment: calendarCredentialEnvironment(initialEnvironment))
      }
      throw configError(
        "Failed to read config: \(selectedConfigPath)",
        details: ["cause": error.localizedDescription]
      )
    }

    let parsed = try parseTomlSubset(source)
    guard let storageRecord = parsed.storage else {
      throw configError("storage must be a table/object")
    }
    if parsed.credentials.isEmpty {
      throw configError("credentials must be a non-empty array")
    }
    if parsed.accounts.isEmpty {
      throw configError("calendars must be a non-empty array")
    }

    let environment = try calendarCredentialEnvironment(
      sourceEnvironment,
      credentialIDs: parsed.credentials.compactMap { $0["id"] as? String }
    )
    let storage = try parseStorageConfig(storageRecord, configPath: selectedConfigPath)
    let credentials = try parsed.credentials.enumerated().map { index, record in
      try parseCredentialConfig(record, index: index, configPath: selectedConfigPath, environment: environment)
    }
    let accounts = try parsed.accounts.enumerated().map { index, record in
      try parseAccountConfig(record, index: index)
    }

    try ensureUnique(credentials.map(\.id), context: "credentials.id")
    try ensureUnique(accounts.map(\.id), context: "calendars.id")
    try ensureUnique(credentials.map { identifierEnvironmentKey($0.id) }, context: "normalized credentials.id")
    try ensureUnique(accounts.map { identifierEnvironmentKey($0.id) }, context: "normalized calendars.id")
    try ensureUnique(credentials.map(\.tokenStorePath), context: "credentials.token_store_path")
    try validateAccountCredentialLinks(credentials: credentials, accounts: accounts)
    try validateOAuthClientSecretPaths(credentials)

    return GoogleCalendarGatewayConfig(
      configPath: selectedConfigPath,
      storage: storage,
      credentials: credentials,
      accounts: accounts
    )
  }

  public static func validateConfig(
    configPath: String? = nil,
    environment: [String: String] = ProcessInfo.processInfo.environment
  ) throws -> [String: Any] {
    let explicitConfigPath = nonBlank(configPath) ?? nonBlank(environment["GOOGLE_CALENDAR_GATEWAY_CONFIG"])
    let usesImplicitDefaultConfig = explicitConfigPath == nil
    let selectedConfigPath = normalizedPath(explicitConfigPath ?? resolveDefaultConfigPath(environment: environment))
    if usesImplicitDefaultConfig, !FileManager.default.fileExists(atPath: selectedConfigPath) {
      return [
        "ok": false,
        "configPath": selectedConfigPath,
        "configFileExists": false,
        "usingDefaults": true,
        "accountIds": [],
        "credentialIds": []
      ]
    }
    let config = try loadConfig(configPath: configPath, environment: environment)
    return [
      "ok": true,
      "configPath": config.configPath,
      "configFileExists": true,
      "usingDefaults": false,
      "accountIds": config.accounts.map(\.id),
      "credentialIds": config.credentials.map(\.id)
    ]
  }

  private static func defaultConfig(
    configPath: String,
    environment: [String: String]
  ) throws -> GoogleCalendarGatewayConfig {
    let credential = CalendarCredentialConfig(
      id: defaultCredentialId,
      provider: .google,
      accessMode: .read,
      oauthClientSecretPath: try resolveCredentialPath(CredentialPathRequest(
        configPath: configPath,
        credentialId: defaultCredentialId,
        pathKey: "oauth_client_secret_path",
        configValue: "google-client.json",
        environment: environment,
        context: "credentials.\(defaultCredentialId).oauth_client_secret_path"
      )),
      oauthClientSecretJSON: credentialJSONEnvValue(
        credentialId: defaultCredentialId,
        valueKey: "oauth_client_secret_json",
        environment: environment
      ),
      tokenStorePath: try resolveCredentialPath(CredentialPathRequest(
        configPath: configPath,
        credentialId: defaultCredentialId,
        pathKey: "token_store_path",
        configValue: URL(fileURLWithPath: resolveDefaultCredentialDirectory(environment: environment))
          .appendingPathComponent("\(defaultCredentialId).json")
          .path,
        environment: environment,
        context: "credentials.\(defaultCredentialId).token_store_path"
      )),
      tokenStoreJSON: credentialJSONEnvValue(
        credentialId: defaultCredentialId,
        valueKey: "token_store_json",
        environment: environment
      ),
      tokenStorePathFromEnvironment: nonBlank(environment[getCredentialPathEnvVarName(
        credentialId: defaultCredentialId, pathKey: "token_store_path"
      )]) != nil
    )
    // Only the historical synthesized default is migrated. Configured paths,
    // per-credential environment paths, inline JSON, and credential-directory
    // overrides intentionally retain their selected source without migration.
    if credential.tokenStoreJSON == nil,
       !credential.tokenStorePathFromEnvironment,
       nonBlank(environment["GOOGLE_CALENDAR_GATEWAY_CREDENTIAL_DIR"]) == nil {
      let legacyPath = URL(fileURLWithPath: configPath)
        .deletingLastPathComponent()
        .appendingPathComponent("tokens")
        .appendingPathComponent("\(defaultCredentialId).json")
        .path
      try migrateCalendarLegacyTokenStore(from: legacyPath, to: credential.tokenStorePath)
    }

    return GoogleCalendarGatewayConfig(
      configPath: configPath,
      storage: CalendarStorageConfig(cacheDir: defaultCacheDirectory(environment: environment)),
      credentials: [credential],
      accounts: [
        CalendarAccountConfig(
          id: defaultAccountId,
          displayName: nil,
          provider: .google,
          emailAddress: "\(defaultAccountId)@example.invalid",
          credentialId: credential.id,
          calendarIds: ["primary"],
          defaultCalendarId: "primary",
          defaultTimeZone: nil
        )
      ]
    )
  }

  private static func defaultCacheDirectory(environment: [String: String]) -> String {
    if let xdgCacheHome = nonBlank(environment["XDG_CACHE_HOME"]) {
      return normalizedPath(URL(fileURLWithPath: xdgCacheHome)
        .appendingPathComponent("google-calendar-gateway", isDirectory: true)
        .path)
    }
    return normalizedPath(FileManager.default.homeDirectoryForCurrentUser
      .appendingPathComponent(".cache", isDirectory: true)
      .appendingPathComponent("google-calendar-gateway", isDirectory: true)
      .path)
  }

  private static func credentialJSONEnvValue(
    credentialId: String,
    valueKey: String,
    environment: [String: String]
  ) -> String? {
    nonBlank(environment[getCredentialJSONEnvVarName(credentialId: credentialId, valueKey: valueKey)])
  }

  private static func credentialEnvSuffix(_ credentialId: String) -> String {
    identifierEnvironmentKey(credentialId)
  }
}

private struct ParsedToml {
  var storage: [String: Any]?
  var credentials: [[String: Any]]
  var accounts: [[String: Any]]
}

private func parseTomlSubset(_ source: String) throws -> ParsedToml {
  var parsed = ParsedToml(storage: nil, credentials: [], accounts: [])
  var section = TomlSection.none

  for rawLine in source.split(separator: "\n", omittingEmptySubsequences: false) {
    let line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
    if line.isEmpty || line.hasPrefix("#") {
      continue
    }
    if line == "[storage]" {
      parsed.storage = parsed.storage ?? [:]
      section = .storage
      continue
    }
    if line == "[[credentials]]" {
      parsed.credentials.append([:])
      section = .credential(parsed.credentials.count - 1)
      continue
    }
    if line == "[[calendars]]" || line == "[[accounts]]" {
      parsed.accounts.append([:])
      section = .calendar(parsed.accounts.count - 1)
      continue
    }
    guard let equals = line.firstIndex(of: "=") else {
      throw configError("config contains an unsupported TOML line: \(line)")
    }
    let key = line[..<equals].trimmingCharacters(in: .whitespacesAndNewlines)
    let rawValue = line[line.index(after: equals)...].trimmingCharacters(in: .whitespacesAndNewlines)
    let value = try parseTomlValue(rawValue)
    switch section {
    case .storage:
      parsed.storage?[key] = value
    case .credential(let index):
      parsed.credentials[index][key] = value
    case .calendar(let index):
      parsed.accounts[index][key] = value
    case .none:
      throw configError("config key appears outside a supported section: \(key)")
    }
  }

  return parsed
}

private func parseTomlValue(_ rawValue: String) throws -> Any {
  if rawValue.hasPrefix("\""), rawValue.hasSuffix("\"") {
    return String(rawValue.dropFirst().dropLast())
  }
  if rawValue.hasPrefix("["), rawValue.hasSuffix("]") {
    let inner = String(rawValue.dropFirst().dropLast()).trimmingCharacters(in: .whitespacesAndNewlines)
    if inner.isEmpty {
      return [String]()
    }
    return try splitTomlArray(inner).map { item in
      let trimmed = item.trimmingCharacters(in: .whitespacesAndNewlines)
      guard trimmed.hasPrefix("\""), trimmed.hasSuffix("\"") else {
        throw configError("array values must be strings")
      }
      return String(trimmed.dropFirst().dropLast())
    }
  }
  throw configError("config contains an unsupported TOML value: \(rawValue)")
}

private func splitTomlArray(_ source: String) -> [String] {
  var values: [String] = []
  var current = ""
  var inString = false
  var escaping = false
  for character in source {
    if escaping {
      current.append(character)
      escaping = false
      continue
    }
    if character == "\\" {
      current.append(character)
      escaping = true
      continue
    }
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

private func parseStorageConfig(_ record: [String: Any], configPath: String) throws -> CalendarStorageConfig {
  CalendarStorageConfig(
    cacheDir: try resolveConfigRelativePath(configPath: configPath, rawPath: readString(record["cache_dir"], "storage.cache_dir"))
  )
}

private func parseCredentialConfig(
  _ record: [String: Any],
  index: Int,
  configPath: String,
  environment: [String: String]
) throws -> CalendarCredentialConfig {
  let contextBase = "credentials[\(index)]"
  let credentialId = try readString(record["id"], "\(contextBase).id")
  try validateConfigIdentifier(credentialId, context: "\(contextBase).id")
  let oauthClientSecretJSON = nonBlank(environment[
    GoogleCalendarGatewayConfigLoader.getCredentialJSONEnvVarName(
      credentialId: credentialId,
      valueKey: "oauth_client_secret_json"
    )
  ])
  let tokenStoreJSON = nonBlank(environment[
    GoogleCalendarGatewayConfigLoader.getCredentialJSONEnvVarName(
      credentialId: credentialId,
      valueKey: "token_store_json"
    )
  ])
  return CalendarCredentialConfig(
    id: credentialId,
    provider: try readProvider(record["provider"], "\(contextBase).provider"),
    accessMode: try readAccessMode(record["access_mode"], "\(contextBase).access_mode"),
    oauthClientSecretPath: try resolveCredentialPath(CredentialPathRequest(
      configPath: configPath,
      credentialId: credentialId,
      pathKey: "oauth_client_secret_path",
      configValue: readOptionalString(record["oauth_client_secret_path"], "\(contextBase).oauth_client_secret_path"),
      environment: environment,
      context: "\(contextBase).oauth_client_secret_path"
    )),
    oauthClientSecretJSON: oauthClientSecretJSON,
    tokenStorePath: try resolveCredentialPath(CredentialPathRequest(
      configPath: configPath,
      credentialId: credentialId,
      pathKey: "token_store_path",
      configValue: readOptionalString(record["token_store_path"], "\(contextBase).token_store_path"),
      environment: environment,
      context: "\(contextBase).token_store_path"
    )),
    tokenStoreJSON: tokenStoreJSON,
    tokenStorePathFromEnvironment: nonBlank(environment[GoogleCalendarGatewayConfigLoader.getCredentialPathEnvVarName(
      credentialId: credentialId, pathKey: "token_store_path"
    )]) != nil
  )
}

private func parseAccountConfig(_ record: [String: Any], index: Int) throws -> CalendarAccountConfig {
  let contextBase = "calendars[\(index)]"
  let id = try readString(record["id"], "\(contextBase).id")
  try validateConfigIdentifier(id, context: "\(contextBase).id")
  let emailAddress = try readOptionalString(record["email_address"], "\(contextBase).email_address") ?? "\(id)@example.invalid"
  if !emailAddress.contains("@") {
    throw configError("\(contextBase).email_address must contain @")
  }
  let calendarIds = try readOptionalStringArray(record["calendar_ids"], "\(contextBase).calendar_ids")
  let defaultCalendarId = try readOptionalString(record["default_calendar_id"], "\(contextBase).default_calendar_id")
    ?? readOptionalStringUnchecked(record["calendar_id"])
    ?? calendarIds.first
    ?? "primary"
  return CalendarAccountConfig(
    id: id,
    displayName: try readOptionalString(record["display_name"], "\(contextBase).display_name"),
    provider: try readProvider(record["provider"], "\(contextBase).provider"),
    emailAddress: emailAddress,
    credentialId: try readString(record["credential_id"], "\(contextBase).credential_id"),
    calendarIds: calendarIds.isEmpty ? [defaultCalendarId] : calendarIds,
    defaultCalendarId: defaultCalendarId,
    defaultTimeZone: try readOptionalString(record["default_time_zone"], "\(contextBase).default_time_zone")
  )
}

private func resolveCredentialPath(_ request: CredentialPathRequest) throws -> String {
  let envName = GoogleCalendarGatewayConfigLoader.getCredentialPathEnvVarName(
    credentialId: request.credentialId,
    pathKey: request.pathKey
  )
  let selected = nonBlank(request.environment[envName]) ?? request.configValue
  guard let selected else {
    throw configError("\(request.context) must be set in config or \(envName)")
  }
  return try resolveConfigRelativePath(configPath: request.configPath, rawPath: selected)
}

private func resolveConfigRelativePath(configPath: String, rawPath: String) throws -> String {
  // Expanding first lets config values use "~/..." as an absolute home path
  // instead of being misread as a config-directory-relative segment.
  let expanded = normalizedPath(rawPath)
  if expanded.hasPrefix("/") {
    return expanded
  }
  let configDirectory = URL(fileURLWithPath: configPath).deletingLastPathComponent()
  return normalizedPath(configDirectory.appendingPathComponent(rawPath).path)
}

private func validateOAuthClientSecretPaths(_ credentials: [CalendarCredentialConfig]) throws {
  for credential in credentials
    where credential.tokenStoreJSON == nil && credential.oauthClientSecretJSON == nil &&
    !FileManager.default.isReadableFile(atPath: credential.oauthClientSecretPath) {
    throw configError(
      "credentials.\(credential.id).oauth_client_secret_path is not readable: \(credential.oauthClientSecretPath)"
    )
  }
}

private func readProvider(_ value: Any?, _ context: String) throws -> CalendarProvider {
  let provider = try readString(value, context)
  guard let parsed = CalendarProvider(rawValue: provider) else {
    throw configError("\(context) must currently be \"google\"")
  }
  return parsed
}

private func readAccessMode(_ value: Any?, _ context: String) throws -> CalendarAccessMode {
  let raw = value == nil ? "read" : try readString(value, context)
  guard let parsed = CalendarAccessMode(rawValue: raw) else {
    throw configError("\(context) must be \"read\", \"read_write\", or \"full\"")
  }
  return parsed
}

private func readString(_ value: Any?, _ context: String) throws -> String {
  guard let string = value as? String,
        !string.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
    throw configError("\(context) must be a non-empty string")
  }
  return string
}

private func readOptionalString(_ value: Any?, _ context: String) throws -> String? {
  guard value != nil else {
    return nil
  }
  return try readString(value, context)
}

private func readOptionalStringArray(_ value: Any?, _ context: String) throws -> [String] {
  guard value != nil else {
    return []
  }
  guard let values = value as? [String] else {
    throw configError("\(context) must be an array of strings")
  }
  for (index, item) in values.enumerated() where item.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
    throw configError("\(context)[\(index)] must be a non-empty string")
  }
  return values
}

private func ensureUnique(_ values: [String], context: String) throws {
  var seen: Set<String> = []
  for value in values {
    if seen.contains(value) {
      throw configError("\(context) contains a duplicate value: \(value)")
    }
    seen.insert(value)
  }
}

private func validateConfigIdentifier(_ value: String, context: String) throws {
  let pattern = #"^[A-Za-z0-9._-]+$"#
  guard value.range(of: pattern, options: .regularExpression) != nil,
        value != ".",
        value != ".." else {
    throw configError("\(context) may contain only ASCII letters, digits, period, underscore, and hyphen")
  }
}

func identifierEnvironmentKey(_ value: String) -> String {
  let suffix = value.trimmingCharacters(in: .whitespacesAndNewlines).map { character -> Character in
    character.isLetter || character.isNumber ? character : "_"
  }
  let normalized = String(suffix)
    .trimmingCharacters(in: CharacterSet(charactersIn: "_"))
    .uppercased()
  return normalized.isEmpty ? "CREDENTIAL" : normalized
}

private func validateAccountCredentialLinks(
  credentials: [CalendarCredentialConfig],
  accounts: [CalendarAccountConfig]
) throws {
  let credentialsById = Dictionary(uniqueKeysWithValues: credentials.map { ($0.id, $0) })
  for account in accounts {
    guard let credential = credentialsById[account.credentialId] else {
      throw configError("calendars.\(account.id) references unknown credential: \(account.credentialId)")
    }
    if credential.provider != account.provider {
      throw configError("calendars.\(account.id) provider does not match credential provider")
    }
  }
}

private func readOptionalStringUnchecked(_ value: Any?) -> String? {
  guard let string = value as? String else {
    return nil
  }
  return nonBlank(string)
}

func configError(_ message: String, details: [String: String] = [:]) -> GoogleCalendarGatewayError {
  GoogleCalendarGatewayError(message, code: .configInvalid, exitCode: .configurationError, details: details)
}
