import Testing
@testable import GoogleCalendarGatewayCore

@Test func globalHelpAndVersionRejectUnknownFlagsAndValues() {
  let versionWithUnknown = GoogleCalendarGatewayCLI().run(arguments: ["--version", "--unknown"], environment: [:])
  let helpWithUnknown = GoogleCalendarGatewayCLI().run(arguments: ["--help", "--unknown"], environment: [:])
  let versionWithValue = GoogleCalendarGatewayCLI().run(arguments: ["--version=false"], environment: [:])
  let helpWithValue = GoogleCalendarGatewayCLI().run(arguments: ["--help=false"], environment: [:])

  #expect(versionWithUnknown.exitCode == GoogleCalendarGatewayExitCode.invalidCliUsage.rawValue)
  #expect(helpWithUnknown.exitCode == GoogleCalendarGatewayExitCode.invalidCliUsage.rawValue)
  #expect(versionWithValue.exitCode == GoogleCalendarGatewayExitCode.invalidCliUsage.rawValue)
  #expect(helpWithValue.exitCode == GoogleCalendarGatewayExitCode.invalidCliUsage.rawValue)
  #expect(versionWithUnknown.stderr.contains("Unknown flag: --unknown"))
  #expect(helpWithUnknown.stderr.contains("Unknown flag: --unknown"))
  #expect(versionWithValue.stderr.contains("--version does not accept a value"))
  #expect(helpWithValue.stderr.contains("--help does not accept a value"))
}

@Test func commandRejectsDuplicateFlagsBeforeRunning() {
  let version = GoogleCalendarGatewayCLI().run(arguments: ["--version", "--version"], environment: [:])
  let graphql = GoogleCalendarGatewayCLI().run(
    arguments: [
      "graphql",
      "--query", "{ calendars { id } }",
      "--query", "{ calendars { provider } }"
    ],
    environment: [:]
  )
  let cache = GoogleCalendarGatewayCLI().run(arguments: ["cache", "prune", "--all", "--all"], environment: [:])

  #expect(version.exitCode == GoogleCalendarGatewayExitCode.invalidCliUsage.rawValue)
  #expect(graphql.exitCode == GoogleCalendarGatewayExitCode.invalidCliUsage.rawValue)
  #expect(cache.exitCode == GoogleCalendarGatewayExitCode.invalidCliUsage.rawValue)
  #expect(version.stderr.contains("Duplicate flag: --version"))
  #expect(graphql.stderr.contains("Duplicate flag: --query"))
  #expect(cache.stderr.contains("Duplicate flag: --all"))
}

@Test func openBrowserFlagParsesAsBooleanAuthOption() throws {
  let enabled = try parseArguments(["auth", "login", "--credential", "google-personal", "--open-browser"])
  let disabled = try parseArguments(["auth", "login", "--credential", "google-personal", "--open-browser", "false"])

  #expect(try getBooleanFlag(enabled.flags, "open-browser"))
  #expect(try getBooleanFlag(disabled.flags, "open-browser") == false)
}

@Test func timeoutSecondsFlagRequiresInteger() {
  let result = GoogleCalendarGatewayCLI().run(
    arguments: [
      "auth",
      "login",
      "--credential", "google-personal",
      "--timeout-seconds", "never"
    ],
    environment: [:]
  )

  #expect(result.exitCode == GoogleCalendarGatewayExitCode.invalidCliUsage.rawValue)
  #expect(result.stderr.contains("--timeout-seconds must be an integer between 1 and 3600"))
}
