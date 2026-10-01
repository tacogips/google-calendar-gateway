import Foundation

public struct GoogleCalendarGatewayCLI {
  let mode: GoogleCalendarGatewayCLIMode
  let serviceFactory: (GoogleCalendarGatewayConfig) -> GoogleCalendarGatewayService

  public init(mode: GoogleCalendarGatewayCLIMode = .reader) {
    self.mode = mode
    serviceFactory = { GoogleCalendarGatewayService(config: $0) }
  }

  init(mode: GoogleCalendarGatewayCLIMode = .reader, serviceFactory: @escaping (GoogleCalendarGatewayConfig) -> GoogleCalendarGatewayService) {
    self.mode = mode
    self.serviceFactory = serviceFactory
  }

  public func run(
    arguments: [String],
    environment: [String: String] = ProcessInfo.processInfo.environment
  ) -> GoogleCalendarGatewayCommandResult {
    do {
      let parsed = try parseArguments(arguments)
      try validateNoRepeatedFlags(parsed.repeatedFlags)
      if parsed.flags["version"] != nil {
        try validateGlobalControlCommand(parsed, flag: "version")
        return GoogleCalendarGatewayCommandResult(exitCode: GoogleCalendarGatewayExitCode.success.rawValue, stdout: Version.current + "\n", stderr: "")
      }
      if shouldShowHelp(parsed) {
        try validateGlobalControlCommand(parsed, flag: "help")
        return GoogleCalendarGatewayCommandResult(exitCode: GoogleCalendarGatewayExitCode.success.rawValue, stdout: rootHelpText(mode: mode), stderr: "")
      }
      let configPath = try getStringFlag(parsed.flags, "config") ?? environment["GOOGLE_CALENDAR_GATEWAY_CONFIG"]
      let pretty = try getBooleanFlag(parsed.flags, "pretty")
      return try runParsedCommand(parsed, configPath: configPath, environment: environment, pretty: pretty)
    } catch let error as GoogleCalendarGatewayError {
      return GoogleCalendarGatewayCommandResult(
        exitCode: error.exitCode.rawValue,
        stdout: "",
        stderr: jsonString(errorOutput(error), pretty: true) + "\n"
      )
    } catch {
      let appError = GoogleCalendarGatewayError(String(describing: error), code: .configInvalid, exitCode: .generalError)
      return GoogleCalendarGatewayCommandResult(
        exitCode: appError.exitCode.rawValue,
        stdout: "",
        stderr: jsonString(errorOutput(appError), pretty: true) + "\n"
      )
    }
  }

  private func shouldShowHelp(_ parsed: ParsedArgs) -> Bool {
    parsed.flags["help"] != nil || parsed.positionals.first == "help" || parsed.positionals == ["auth"]
  }

  private func runParsedCommand(
    _ parsed: ParsedArgs,
    configPath: String?,
    environment: [String: String],
    pretty: Bool
  ) throws -> GoogleCalendarGatewayCommandResult {
    let command = parsed.positionals.first
    let subcommand = parsed.positionals.dropFirst().first
    switch command {
    case "graphql":
      try validateAllowedFlags(parsed.flags, commandFlags: ["query", "query-file", "variables", "variables-file"])
      try validatePositionalCount(parsed.positionals, count: 1)
      let config = try GoogleCalendarGatewayConfigLoader.loadConfig(configPath: configPath, environment: environment, synthesizedAccessMode: mode.synthesizedAccessMode)
      let query = try loadQuery(flags: parsed.flags)
      _ = try loadVariables(flags: parsed.flags)
      let result = try executeCalendarGraphQL(service: serviceFactory(config), query: query, mode: mode)
      return success(result.body, exitCode: result.exitCode, pretty: pretty)
    case "config":
      try validateAllowedFlags(parsed.flags, commandFlags: [])
      try validatePositionalCount(parsed.positionals, count: 2)
      guard subcommand == "validate" else {
        throw GoogleCalendarGatewayError(
          "config requires the validate subcommand",
          code: .invalidArgument,
          exitCode: .invalidCliUsage
        )
      }
      return success(
        try GoogleCalendarGatewayConfigLoader.validateConfig(configPath: configPath, environment: environment),
        pretty: pretty
      )
    case "auth":
      try validateAllowedFlags(
        parsed.flags,
        commandFlags: ["credential", "open-browser", "redirect-uri", "timeout-seconds"]
      )
      try validatePositionalCount(parsed.positionals, count: 2)
      return try runAuth(subcommand: subcommand, flags: parsed.flags, configPath: configPath, environment: environment, pretty: pretty)
    case "cache":
      try validateAllowedFlags(parsed.flags, commandFlags: ["calendar", "all"])
      try validatePositionalCount(parsed.positionals, count: 2)
      return try runCache(subcommand: subcommand, flags: parsed.flags, configPath: configPath, environment: environment, pretty: pretty)
    case "event":
      try mode.requireWrites(exitCode: .invalidCliUsage)
      try validateAllowedFlags(parsed.flags, commandFlags: try eventCommandFlags(subcommand: subcommand))
      try validatePositionalCount(parsed.positionals, count: 2)
      return try runEventCommand(
        subcommand: subcommand,
        flags: parsed.flags,
        configPath: configPath,
        environment: environment,
        pretty: pretty
      )
    default:
      try validateAllowedFlags(parsed.flags, commandFlags: [])
      throw GoogleCalendarGatewayError(
        "Supported commands: graphql, config validate, auth <login|logout|revoke|status>, cache prune, event <create|update|delete>",
        code: .invalidArgument,
        exitCode: .invalidCliUsage
      )
    }
  }

  private func runAuth(
    subcommand: String?,
    flags: [String: StringOrBool],
    configPath: String?,
    environment: [String: String],
    pretty: Bool
  ) throws -> GoogleCalendarGatewayCommandResult {
    guard let credentialId = try getStringFlag(flags, "credential")
      ?? (["login", "status", "logout"].contains(subcommand ?? "") ? "google-personal" : nil) else {
      throw GoogleCalendarGatewayError(
        "auth commands require --credential",
        code: .invalidArgument,
        exitCode: .invalidCliUsage
      )
    }
    switch subcommand {
    case "status":
      let service = GoogleCalendarGatewayService(
        config: try GoogleCalendarGatewayConfigLoader.loadConfig(configPath: configPath, environment: environment, synthesizedAccessMode: mode.synthesizedAccessMode)
      )
      return success(try service.getAuthStatus(credentialId: credentialId), pretty: pretty)
    case "logout":
      let service = GoogleCalendarGatewayService(
        config: try GoogleCalendarGatewayConfigLoader.loadConfig(configPath: configPath, environment: environment, synthesizedAccessMode: mode.synthesizedAccessMode)
      )
      return success(try service.logoutAuth(credentialId: credentialId), pretty: pretty)
    case "revoke":
      let service = GoogleCalendarGatewayService(
        config: try GoogleCalendarGatewayConfigLoader.loadConfig(configPath: configPath, environment: environment, synthesizedAccessMode: mode.synthesizedAccessMode)
      )
      return success(try service.revokeAuth(credentialId: credentialId), pretty: pretty)
    case "login":
      let options = GoogleCalendarOAuthLoginOptions(
        redirectURI: try getStringFlag(flags, "redirect-uri"),
        openBrowser: try getBooleanFlag(flags, "open-browser", defaultValue: true),
        timeoutSeconds: try getIntFlag(flags, "timeout-seconds", defaultValue: 300, range: 1...3_600)
      )
      let service = GoogleCalendarGatewayService(
        config: try GoogleCalendarGatewayConfigLoader.loadConfig(configPath: configPath, environment: environment, synthesizedAccessMode: mode.synthesizedAccessMode)
      )
      return success(try service.login(credentialId: credentialId, options: options), pretty: pretty)
    default:
      throw GoogleCalendarGatewayError(
        "auth requires one of: login, logout, revoke, status",
        code: .invalidArgument,
        exitCode: .invalidCliUsage
      )
    }
  }

  private func runCache(
    subcommand: String?,
    flags: [String: StringOrBool],
    configPath: String?,
    environment: [String: String],
    pretty: Bool
  ) throws -> GoogleCalendarGatewayCommandResult {
    guard subcommand == "prune" else {
      throw GoogleCalendarGatewayError(
        "cache requires the prune subcommand",
        code: .invalidArgument,
        exitCode: .invalidCliUsage
      )
    }
    let service = GoogleCalendarGatewayService(
      config: try GoogleCalendarGatewayConfigLoader.loadConfig(configPath: configPath, environment: environment, synthesizedAccessMode: mode.synthesizedAccessMode)
    )
    return success(
      try service.pruneCache(
        calendarId: try getStringFlag(flags, "calendar"),
        all: try getBooleanFlag(flags, "all")
      ),
      pretty: pretty
    )
  }

  private func success(
    _ payload: [String: Any],
    exitCode: GoogleCalendarGatewayExitCode = .success,
    pretty: Bool
  ) -> GoogleCalendarGatewayCommandResult {
    GoogleCalendarGatewayCommandResult(exitCode: exitCode.rawValue, stdout: jsonString(payload, pretty: pretty) + "\n", stderr: "")
  }
}

private func rootHelpText(mode: GoogleCalendarGatewayCLIMode) -> String {
  let executable = mode.executableName
  let eventCommands = mode == .writer ? """
    event create --calendar <local-id> [event input flags] [--dry-run]
    event update --calendar <local-id> --event-id <id> [event input flags] [--dry-run]
    event delete --calendar <local-id> --event-id <id> [--provider-calendar <id>] [--send-updates <value>] [--dry-run]
  """ : ""
  return """
  \(executable)

  Usage:
    \(executable) [--config <path>] [--pretty] <command>

  Commands:
    graphql --query <query> [--variables <json>|--variables-file <path>]
    graphql --query-file <path> [--variables <json>|--variables-file <path>]
    config validate
    auth <login|status> [--credential <id>]
    auth logout [--credential <id>]
    auth revoke --credential <id>
    auth login [--credential <id>] [--redirect-uri <loopback-url>] [--open-browser false] [--timeout-seconds <seconds>]
    cache prune [--calendar <id>|--all]
  \(eventCommands)

  Examples:
    \(executable) graphql --query '{ calendars { id } }'
    \(executable) config validate
    \(executable) auth status --credential google-personal
    \(executable) cache prune --calendar personal
  """
}

private func eventCommandFlags(subcommand: String?) throws -> Set<String> {
  let targetFlags: Set<String> = ["calendar", "provider-calendar", "send-updates", "dry-run"]
  let inputFlags: Set<String> = [
    "summary", "description", "location", "color-id", "visibility", "transparency",
    "start", "end", "time-zone", "attendee-emails", "recurrence-rules",
    "reminder-use-default", "reminder-overrides", "create-conference", "conference-request-id"
  ]
  switch subcommand {
  case "create":
    return targetFlags.union(inputFlags)
  case "update":
    return targetFlags.union(inputFlags).union(["event-id"])
  case "delete":
    return targetFlags.union(["event-id"])
  default:
    throw GoogleCalendarGatewayError(
      "event requires one of: create, update, delete",
      code: .invalidArgument,
      exitCode: .invalidCliUsage
    )
  }
}

private func validateGlobalControlCommand(_ parsed: ParsedArgs, flag: String) throws {
  try validateAllowedFlags(parsed.flags, commandFlags: [flag])
  if parsed.flags[flag] != nil {
    try validateBooleanControlFlag(parsed.flags, flag)
  }
  let isAuthHelp = flag == "help" && parsed.positionals == ["auth"]
  let allowedPositionals = parsed.positionals.first == "help" || isAuthHelp ? 1 : 0
  try validatePositionalCount(parsed.positionals, count: allowedPositionals)
}

private func validateNoRepeatedFlags(_ repeatedFlags: [String: [StringOrBool]]) throws {
  for flag in repeatedFlags.keys.sorted() where (repeatedFlags[flag]?.count ?? 0) > 1 {
    throw GoogleCalendarGatewayError(
      "Duplicate flag: --\(flag)",
      code: .invalidArgument,
      exitCode: .invalidCliUsage
    )
  }
}

private func validateBooleanControlFlag(_ flags: [String: StringOrBool], _ flag: String) throws {
  switch flags[flag] {
  case .bool(true), nil:
    return
  case .bool(false), .string:
    throw GoogleCalendarGatewayError(
      "--\(flag) does not accept a value",
      code: .invalidArgument,
      exitCode: .invalidCliUsage
    )
  }
}

private func getBooleanFlag(_ flags: [String: StringOrBool], _ name: String, defaultValue: Bool) throws -> Bool {
  guard flags[name] != nil else {
    return defaultValue
  }
  return try getBooleanFlag(flags, name)
}

private func getIntFlag(
  _ flags: [String: StringOrBool],
  _ name: String,
  defaultValue: Int,
  range: ClosedRange<Int>
) throws -> Int {
  guard let value = try getStringFlag(flags, name) else {
    return defaultValue
  }
  guard let intValue = Int(value), range.contains(intValue) else {
    throw GoogleCalendarGatewayError(
      "--\(name) must be an integer between \(range.lowerBound) and \(range.upperBound)",
      code: .invalidArgument,
      exitCode: .invalidCliUsage
    )
  }
  return intValue
}

private func validatePositionalCount(_ positionals: [String], count: Int) throws {
  guard positionals.count <= count else {
    throw GoogleCalendarGatewayError(
      "Unexpected argument: \(positionals[count])",
      code: .invalidArgument,
      exitCode: .invalidCliUsage
    )
  }
}

private func validateAllowedFlags(_ flags: [String: StringOrBool], commandFlags: Set<String>) throws {
  let allowed = commandFlags.union(["config", "pretty", "help", "version"])
  for flag in flags.keys.sorted() where !allowed.contains(flag) {
    throw GoogleCalendarGatewayError(
      "Unknown flag: --\(flag)",
      code: .invalidArgument,
      exitCode: .invalidCliUsage
    )
  }
}
