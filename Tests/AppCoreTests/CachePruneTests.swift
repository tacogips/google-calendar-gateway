import Foundation
import Testing
@testable import GoogleCalendarGatewayCore

@Test func cachePruneRequiresSelector() throws {
  let error = try requireGoogleCalendarGatewayError {
    _ = try GoogleCalendarGatewayService(config: testConfig()).pruneCache(calendarId: nil, all: false)
  }

  #expect(error.code == .invalidArgument)
  #expect(error.exitCode == .invalidCliUsage)
}

@Test func cachePruneRemovesCalendarCacheOnly() throws {
  let paths = temporaryConfigPaths()
  defer {
    try? FileManager.default.removeItem(atPath: paths.root)
  }
  try writeConfig(paths: paths)
  let target = URL(fileURLWithPath: paths.cache)
    .appendingPathComponent("personal", isDirectory: true)
    .appendingPathComponent("events.json")
    .path
  try FileManager.default.createDirectory(
    atPath: URL(fileURLWithPath: target).deletingLastPathComponent().path,
    withIntermediateDirectories: true
  )
  try "{}".write(toFile: target, atomically: true, encoding: .utf8)

  let result = GoogleCalendarGatewayCLI().run(
    arguments: ["--config", paths.config, "cache", "prune", "--calendar", "personal"],
    environment: env(paths: paths)
  )

  #expect(result.exitCode == GoogleCalendarGatewayExitCode.success.rawValue)
  #expect(!FileManager.default.fileExists(atPath: target))
  #expect(FileManager.default.fileExists(atPath: paths.cache))
}

@Test func cachePruneRejectsCalendarCacheSymlinkOutsideRoot() throws {
  let paths = temporaryConfigPaths()
  defer {
    try? FileManager.default.removeItem(atPath: paths.root)
  }
  try writeConfig(paths: paths)
  let outside = URL(fileURLWithPath: paths.root).appendingPathComponent("outside", isDirectory: true).path
  let symlink = URL(fileURLWithPath: paths.cache).appendingPathComponent("personal", isDirectory: true).path
  try FileManager.default.createDirectory(atPath: paths.cache, withIntermediateDirectories: true)
  try FileManager.default.createDirectory(atPath: outside, withIntermediateDirectories: true)
  try FileManager.default.createSymbolicLink(atPath: symlink, withDestinationPath: outside)

  let result = GoogleCalendarGatewayCLI().run(
    arguments: ["--config", paths.config, "cache", "prune", "--calendar", "personal"],
    environment: env(paths: paths)
  )

  #expect(result.exitCode == GoogleCalendarGatewayExitCode.configurationError.rawValue)
  #expect(result.stderr.contains("Refusing to prune outside the configured cache root"))
  #expect(FileManager.default.fileExists(atPath: outside))
}
