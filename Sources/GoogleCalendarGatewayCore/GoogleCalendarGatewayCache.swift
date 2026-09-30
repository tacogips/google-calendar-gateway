import Foundation

public extension GoogleCalendarGatewayService {
  func pruneCache(calendarId: String?, all: Bool) throws -> [String: Any] {
    let cacheRoot = canonicalPath(config.storage.cacheDir)
    let targets: [String]
    switch (all, calendarId) {
    case (true, nil):
      targets = [cacheRoot]
    case (false, .some(let calendarId)):
      let account = try requireAccount(calendarId)
      targets = [URL(fileURLWithPath: cacheRoot).appendingPathComponent(account.id, isDirectory: true).path]
    case (false, nil):
      throw GoogleCalendarGatewayError(
        "cache prune requires --all or --calendar",
        code: .invalidArgument,
        exitCode: .invalidCliUsage
      )
    case (true, .some):
      throw GoogleCalendarGatewayError(
        "cache prune accepts either --all or --calendar, but not both",
        code: .invalidArgument,
        exitCode: .invalidCliUsage
      )
    }

    var prunedPaths: [String] = []
    for target in targets {
      let normalizedTarget = try assertWithinCacheRoot(target)
      guard FileManager.default.fileExists(atPath: normalizedTarget) else {
        continue
      }
      do {
        try FileManager.default.removeItem(atPath: normalizedTarget)
      } catch {
        throw GoogleCalendarGatewayError(
          "Failed to prune cache path",
          code: .configInvalid,
          exitCode: .configurationError,
          details: ["path": normalizedTarget, "cause": error.localizedDescription]
        )
      }
      prunedPaths.append(normalizedTarget)
    }
    if all {
      try createCacheRoot(cacheRoot)
    }
    return ["prunedPaths": prunedPaths, "cacheRoot": cacheRoot, "empty": prunedPaths.isEmpty]
  }

  private func assertWithinCacheRoot(_ target: String) throws -> String {
    let cacheRoot = canonicalPath(config.storage.cacheDir)
    let normalizedTarget = canonicalPath(target)
    if !isWithinRoot(rootPath: cacheRoot, candidatePath: normalizedTarget) {
      throw GoogleCalendarGatewayError(
        "Refusing to prune outside the configured cache root",
        code: .configInvalid,
        exitCode: .configurationError,
        details: ["target": normalizedTarget, "cacheRoot": cacheRoot]
      )
    }
    return normalizedTarget
  }

  private func createCacheRoot(_ cacheRoot: String) throws {
    try FileManager.default.createDirectory(
      atPath: cacheRoot,
      withIntermediateDirectories: true,
      attributes: [.posixPermissions: 0o700]
    )
  }
}
