import Foundation

public enum CalendarRawHTTPMethod: String, Codable, Equatable, Sendable {
  case delete = "DELETE"
  case get = "GET"
  case patch = "PATCH"
  case post = "POST"
  case put = "PUT"
}

public enum CalendarRawAPIAccess: String, Codable, Equatable, Sendable {
  case auto
  case read
  case write
}

public struct CalendarRawAPIRequest: Sendable {
  public let credentialId: String
  public let method: CalendarRawHTTPMethod
  public let path: String
  public let queryItems: [(String, String)]
  public let bodyJSON: String?
  public let access: CalendarRawAPIAccess

  public init(
    credentialId: String,
    method: CalendarRawHTTPMethod,
    path: String,
    queryItems: [(String, String)] = [],
    bodyJSON: String? = nil,
    access: CalendarRawAPIAccess = .auto
  ) {
    self.credentialId = credentialId
    self.method = method
    self.path = path
    self.queryItems = queryItems
    self.bodyJSON = bodyJSON
    self.access = access
  }
}

public struct GoogleCalendarGatewayGraphQLResolver {
  public let service: GoogleCalendarGatewayService

  public init(config: GoogleCalendarGatewayConfig) {
    self.init(service: GoogleCalendarGatewayService(config: config))
  }

  public init(service: GoogleCalendarGatewayService) {
    self.service = service
  }

  public func execute(query: String) throws -> (body: [String: Any], exitCode: GoogleCalendarGatewayExitCode) {
    try executeCalendarGraphQL(service: service, query: query)
  }
}

public extension GoogleCalendarGatewayService {
  func executeCalendarAPI(request: CalendarRawAPIRequest) throws -> [String: Any] {
    try validateRawCalendarAPIRequest(request)
    let credential: CalendarCredentialConfig
    if rawCalendarAPITokenUse(for: request) == .write {
      credential = try requireWriteCredential(request.credentialId)
    } else {
      credential = try requireCredential(request.credentialId)
    }
    return try provider.executeCalendarAPI(credential: credential, request: request)
  }
}

func validateRawCalendarAPIRequest(_ request: CalendarRawAPIRequest) throws {
  guard request.path.hasPrefix("/"),
        !request.path.hasPrefix("//"),
        !request.path.contains("://"),
        !request.path.contains("?"),
        !request.path.contains("#"),
        !request.path.contains("\n"),
        !request.path.split(separator: "/").contains("..") else {
    throw GoogleCalendarGatewayError(
      "calendarAPI path must be a relative Calendar v3 path starting with /",
      code: .invalidArgument,
      exitCode: .graphqlExecutionError
    )
  }
  if let bodyJSON = nonBlank(request.bodyJSON) {
    _ = try parseRawCalendarAPIJSONBody(bodyJSON)
  }
  for item in request.queryItems where nonBlank(item.0) == nil {
    throw GoogleCalendarGatewayError(
      "calendarAPI query item names must be non-empty",
      code: .invalidArgument,
      exitCode: .graphqlExecutionError
    )
  }
}

func rawCalendarAPITokenUse(for request: CalendarRawAPIRequest) -> CalendarAccessTokenUse {
  guard request.method == .get else {
    return .write
  }
  switch request.access {
  case .read:
    return .read
  case .write:
    return .write
  case .auto:
    if request.method == .get || request.path == "/freeBusy" || request.path.hasSuffix("/watch") {
      return .read
    }
    return .write
  }
}

func parseRawCalendarAPIJSONBody(_ bodyJSON: String) throws -> Any {
  do {
    return try JSONSerialization.jsonObject(with: Data(bodyJSON.utf8))
  } catch {
    throw GoogleCalendarGatewayError(
      "calendarAPI body must be valid JSON",
      code: .invalidArgument,
      exitCode: .graphqlExecutionError,
      details: ["cause": error.localizedDescription]
    )
  }
}
