public enum GoogleCalendarGatewayCLIMode: Sendable {
  case reader
  case writer

  var executableName: String {
    switch self {
    case .reader: return "google-calendar-gateway-reader"
    case .writer: return "google-calendar-gateway-writer"
    }
  }

  func requireWrites(exitCode: GoogleCalendarGatewayExitCode = .graphqlExecutionError) throws {
    guard self == .writer else {
      throw GoogleCalendarGatewayError(
        "google-calendar-gateway-reader cannot write calendar data; use google-calendar-gateway-writer",
        code: .writeDisabled,
        exitCode: exitCode
      )
    }
  }
}
