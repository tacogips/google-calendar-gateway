import Foundation
import Testing
@testable import GoogleCalendarGatewayCore

@Test func configValidationAcceptsEnvBackedCredentialFiles() throws {
  let paths = temporaryConfigPaths()
  defer {
    try? FileManager.default.removeItem(atPath: paths.root)
  }
  try writeConfig(paths: paths)

  let result = GoogleCalendarGatewayCLI().run(
    arguments: ["--config", paths.config, "config", "validate"],
    environment: env(paths: paths)
  )

  #expect(result.exitCode == GoogleCalendarGatewayExitCode.success.rawValue)
  #expect(result.stdout.contains("\"ok\":true"))
}

@Test func calendarsGraphQLReturnsConfiguredCapabilities() throws {
  let paths = temporaryConfigPaths()
  defer {
    try? FileManager.default.removeItem(atPath: paths.root)
  }
  try writeConfig(paths: paths)

  let result = GoogleCalendarGatewayCLI().run(
    arguments: [
      "--config", paths.config,
      "graphql",
      "--query", "{ calendars { id displayName provider capabilities { canRead authState } } }"
    ],
    environment: env(paths: paths)
  )

  #expect(result.exitCode == GoogleCalendarGatewayExitCode.success.rawValue)
  #expect(result.stdout.contains("\"id\":\"personal\""))
  #expect(result.stdout.contains("\"displayName\":\"Personal\""))
  #expect(result.stdout.contains("\"provider\":\"GOOGLE\""))
  #expect(result.stdout.contains("\"authState\":\"READY\""))
}

@Test func graphQLAcceptsVariablesFile() throws {
  let paths = temporaryConfigPaths()
  defer {
    try? FileManager.default.removeItem(atPath: paths.root)
  }
  try writeConfig(paths: paths)
  let variablesPath = URL(fileURLWithPath: paths.root).appendingPathComponent("variables.json").path
  try "{}".write(toFile: variablesPath, atomically: true, encoding: .utf8)

  let result = GoogleCalendarGatewayCLI().run(
    arguments: [
      "--config", paths.config,
      "graphql",
      "--query", "{ calendars { id } }",
      "--variables-file", variablesPath
    ],
    environment: env(paths: paths)
  )

  #expect(result.exitCode == GoogleCalendarGatewayExitCode.success.rawValue)
  #expect(result.stdout.contains("\"id\":\"personal\""))
}

@Test func graphQLRejectsVariableReferencesWhileUnsupported() throws {
  let paths = temporaryConfigPaths()
  defer {
    try? FileManager.default.removeItem(atPath: paths.root)
  }
  try writeConfig(paths: paths)

  let result = GoogleCalendarGatewayCLI().run(
    arguments: [
      "--config", paths.config,
      "graphql",
      "--query", "query($id: String!) { calendar(id: $id) { id } }",
      "--variables", "{\"id\":\"personal\"}"
    ],
    environment: env(paths: paths)
  )

  #expect(result.exitCode == GoogleCalendarGatewayExitCode.graphqlExecutionError.rawValue)
  #expect(result.stdout.contains("\"errors\""))
  #expect(result.stdout.contains("GraphQL variables are not supported yet"))
}

@Test func graphQLRejectsInvalidVariablesJSON() throws {
  let paths = temporaryConfigPaths()
  defer {
    try? FileManager.default.removeItem(atPath: paths.root)
  }
  try writeConfig(paths: paths)

  let result = GoogleCalendarGatewayCLI().run(
    arguments: [
      "--config", paths.config,
      "graphql",
      "--query", "{ calendars { id } }",
      "--variables", "[1, 2, 3]"
    ],
    environment: env(paths: paths)
  )

  #expect(result.exitCode == GoogleCalendarGatewayExitCode.invalidCliUsage.rawValue)
  #expect(result.stderr.contains("--variables must be a JSON object"))
}

@Test func configValidateReportsMissingImplicitConfigWithoutOkTrue() throws {
  let paths = temporaryConfigPaths()
  defer {
    try? FileManager.default.removeItem(atPath: paths.root)
  }
  try FileManager.default.createDirectory(atPath: paths.root, withIntermediateDirectories: true)

  let result = GoogleCalendarGatewayCLI().run(
    arguments: ["config", "validate"],
    environment: ["XDG_CONFIG_HOME": paths.root]
  )

  #expect(result.exitCode == GoogleCalendarGatewayExitCode.success.rawValue)
  #expect(result.stdout.contains("\"ok\":false"))
  #expect(result.stdout.contains("\"configFileExists\":false"))
  #expect(result.stdout.contains("\"usingDefaults\":true"))
}

@Test func configRejectsUnsafeAndCollidingIds() throws {
  let traversalPaths = temporaryConfigPaths()
  defer {
    try? FileManager.default.removeItem(atPath: traversalPaths.root)
  }
  try writeConfig(paths: traversalPaths)
  try """
  [storage]
  cache_dir = "\(traversalPaths.cache)"

  [[credentials]]
  id = "../google"
  provider = "google"
  access_mode = "read"
  oauth_client_secret_path = "\(traversalPaths.oauthClient)"
  token_store_path = "\(traversalPaths.token)"

  [[calendars]]
  id = "personal"
  provider = "google"
  credential_id = "../google"
  calendar_id = "primary"
  """.write(toFile: traversalPaths.config, atomically: true, encoding: .utf8)

  let traversal = GoogleCalendarGatewayCLI().run(
    arguments: ["--config", traversalPaths.config, "config", "validate"],
    environment: env(paths: traversalPaths)
  )

  let collisionPaths = temporaryConfigPaths()
  defer {
    try? FileManager.default.removeItem(atPath: collisionPaths.root)
  }
  try writeConfig(paths: collisionPaths)
  let secondToken = URL(fileURLWithPath: collisionPaths.root).appendingPathComponent("token-2.json").path
  try "{}".write(toFile: secondToken, atomically: true, encoding: .utf8)
  try """
  [storage]
  cache_dir = "\(collisionPaths.cache)"

  [[credentials]]
  id = "google-personal"
  provider = "google"
  access_mode = "read"
  oauth_client_secret_path = "\(collisionPaths.oauthClient)"
  token_store_path = "\(collisionPaths.token)"

  [[credentials]]
  id = "google_personal"
  provider = "google"
  access_mode = "read"
  oauth_client_secret_path = "\(collisionPaths.oauthClient)"
  token_store_path = "\(secondToken)"

  [[calendars]]
  id = "personal"
  provider = "google"
  credential_id = "google-personal"
  calendar_id = "primary"
  """.write(toFile: collisionPaths.config, atomically: true, encoding: .utf8)

  let collision = GoogleCalendarGatewayCLI().run(
    arguments: ["--config", collisionPaths.config, "config", "validate"],
    environment: env(paths: collisionPaths)
  )

  #expect(traversal.exitCode == GoogleCalendarGatewayExitCode.configurationError.rawValue)
  #expect(traversal.stderr.contains("may contain only ASCII letters"))
  #expect(collision.exitCode == GoogleCalendarGatewayExitCode.configurationError.rawValue)
  #expect(collision.stderr.contains("normalized credentials.id contains a duplicate value"))
}
