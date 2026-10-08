import Foundation
import Testing
@testable import GoogleCalendarGatewayCore

@Test func systemTemporaryAliasSupportsPrivateTokenLifecycle() throws {
  let root = URL(fileURLWithPath: "/tmp").appendingPathComponent(UUID().uuidString)
  defer { try? FileManager.default.removeItem(at: root) }
  let path = root.appendingPathComponent("token.json").path
  let bytes = Data("token-fixture".utf8)
  try writeCalendarSecureTokenFile(bytes, to: path)
  #expect(try calendarSecureTokenFileData(at: path) == bytes)
  #expect(try removeCalendarSecureTokenFile(at: path))
  #expect(!FileManager.default.fileExists(atPath: path))
}

@Test func systemAliasDoesNotPermitUserControlledTokenSymlinks() throws {
  let root = URL(fileURLWithPath: "/tmp").appendingPathComponent(UUID().uuidString)
  defer { try? FileManager.default.removeItem(at: root) }
  let real = root.appendingPathComponent("real")
  let path = real.appendingPathComponent("token.json").path
  try writeCalendarSecureTokenFile(Data("fixture".utf8), to: path)
  let link = root.appendingPathComponent("link")
  try FileManager.default.createSymbolicLink(at: link, withDestinationURL: real)
  #expect(throws: (any Error).self) {
    try calendarSecureTokenFileData(at: link.appendingPathComponent("token.json").path)
  }
  let leaf = real.appendingPathComponent("link.json")
  try FileManager.default.createSymbolicLink(atPath: leaf.path, withDestinationPath: path)
  #expect(throws: (any Error).self) { try calendarSecureTokenFileData(at: leaf.path) }
}
