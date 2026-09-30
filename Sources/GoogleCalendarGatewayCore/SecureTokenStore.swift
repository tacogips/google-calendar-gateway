import Darwin
import Foundation

final class CalendarTokenParent {
  let fd: Int32
  let leaf: String
  init(fd: Int32, leaf: String) { self.fd = fd; self.leaf = leaf }
  deinit { close(fd) }
}

func calendarTokenParent(_ path: String, create: Bool) throws -> CalendarTokenParent {
  let raw = URL(fileURLWithPath: path).standardizedFileURL.path
  let normalized = raw.hasPrefix("/var/") ? "/private\(raw)" : raw
  guard normalized.hasPrefix("/") else { throw POSIXError(.EINVAL) }
  let parts = normalized.split(separator: "/").map(String.init)
  guard let leaf = parts.last, !leaf.isEmpty else { throw POSIXError(.EINVAL) }
  var fd = Darwin.open("/", O_RDONLY | O_DIRECTORY | O_NOFOLLOW)
  guard fd >= 0 else { throw POSIXError(.EACCES) }
  for part in parts.dropLast() {
    var next = Darwin.openat(fd, part, O_RDONLY | O_DIRECTORY | O_NOFOLLOW)
    if next < 0, errno == ENOENT, create {
      guard Darwin.mkdirat(fd, part, S_IRWXU) == 0 || errno == EEXIST else { close(fd); throw POSIXError(.EACCES) }
      next = Darwin.openat(fd, part, O_RDONLY | O_DIRECTORY | O_NOFOLLOW)
    }
    guard next >= 0 else { close(fd); throw POSIXError(.ELOOP) }
    close(fd); fd = next
  }
  var info = stat()
  guard fstat(fd, &info) == 0, (info.st_mode & S_IFMT) == S_IFDIR,
        info.st_uid == geteuid() else { close(fd); throw POSIXError(.EPERM) }
  if create, fchmod(fd, S_IRWXU) != 0 { close(fd); throw POSIXError(.EPERM) }
  return CalendarTokenParent(fd: fd, leaf: leaf)
}

private func calendarReadTokenLeaf(_ parent: CalendarTokenParent, _ leaf: String) throws -> Data? {
  let fd = Darwin.openat(parent.fd, leaf, O_RDONLY | O_NOFOLLOW | O_NONBLOCK)
  if fd < 0 { if errno == ENOENT { return nil }; throw POSIXError(.EACCES) }
  defer { close(fd) }
  try validateCalendarTokenFileDescriptor(fd)
  return try FileHandle(fileDescriptor: fd, closeOnDealloc: false).readToEnd() ?? Data()
}

private func calendarPublishToken(_ data: Data, parent: CalendarTokenParent, leaf: String, exclusive: Bool) throws -> Bool {
  let temp = ".\(leaf).\(UUID().uuidString).tmp"
  let fd = Darwin.openat(parent.fd, temp, O_CREAT | O_EXCL | O_WRONLY | O_NOFOLLOW, S_IRUSR | S_IWUSR)
  guard fd >= 0 else { throw POSIXError(.EIO) }
  defer { close(fd); _ = Darwin.unlinkat(parent.fd, temp, 0) }
  try data.withUnsafeBytes { bytes in
    guard let base = bytes.baseAddress else { return }
    var offset = 0
    while offset < bytes.count {
      let count = Darwin.write(fd, base.advanced(by: offset), bytes.count - offset)
      guard count > 0 else { throw POSIXError(.EIO) }
      offset += count
    }
  }
  guard fchmod(fd, S_IRUSR | S_IWUSR) == 0, fsync(fd) == 0 else { throw POSIXError(.EIO) }
  let flags: UInt32 = exclusive ? UInt32(RENAME_EXCL) : 0
  if renameatx_np(parent.fd, temp, parent.fd, leaf, flags) != 0 {
    if errno == EEXIST { return false }
    throw POSIXError(.EIO)
  }
  guard fsync(parent.fd) == 0 else { throw POSIXError(.EIO) }
  return true
}

/// Filesystem operations for OAuth token state. Token files are secrets, so do
/// not follow a replacement symlink or accept a hard-linked file whose contents
/// could also be changed through another name.
func calendarSecureTokenFileData(at path: String) throws -> Data {
  let parent = try calendarTokenParent(path, create: false)
  guard let data = try calendarReadTokenLeaf(parent, parent.leaf) else { throw POSIXError(.ENOENT) }
  return data
}

func calendarTokenFileExists(at path: String) -> Bool {
  guard let parent = try? calendarTokenParent(path, create: false) else { return false }
  return (try? calendarReadTokenLeaf(parent, parent.leaf)) != nil
}

func writeCalendarSecureTokenFile(_ data: Data, to path: String) throws {
  let parent = try calendarTokenParent(path, create: true)
  _ = try calendarPublishToken(data, parent: parent, leaf: parent.leaf, exclusive: false)
}

func removeCalendarSecureTokenFile(at path: String) throws -> Bool {
  let parent = try calendarTokenParent(path, create: false)
  let fd = Darwin.openat(parent.fd, parent.leaf, O_RDONLY | O_NOFOLLOW | O_NONBLOCK)
  if fd < 0 { if errno == ENOENT { return false }; throw POSIXError(.EACCES) }
  defer { close(fd) }
  let expected = try validateCalendarTokenFileDescriptor(fd)
  let quarantine = ".\(parent.leaf).revoke.\(UUID().uuidString)"
  guard renameatx_np(parent.fd, parent.leaf, parent.fd, quarantine, UInt32(RENAME_EXCL)) == 0 else { throw POSIXError(.EIO) }
  let moved = Darwin.openat(parent.fd, quarantine, O_RDONLY | O_NOFOLLOW | O_NONBLOCK)
  guard moved >= 0 else { throw POSIXError(.EIO) }
  defer { close(moved) }
  let actual = try validateCalendarTokenFileDescriptor(moved)
  guard actual.st_dev == expected.st_dev, actual.st_ino == expected.st_ino else {
    _ = renameatx_np(parent.fd, quarantine, parent.fd, parent.leaf, UInt32(RENAME_EXCL))
    throw POSIXError(.EPERM)
  }
  guard Darwin.unlinkat(parent.fd, quarantine, 0) == 0, fsync(parent.fd) == 0 else { throw POSIXError(.EIO) }
  return true
}

/// Copies the former implicit token only when the destination does not exist.
/// A durable completion marker is intentionally retained after revoke: the
/// legacy copy remains recoverable but can never become active again.
func migrateCalendarLegacyTokenStore(from legacyPath: String, to destinationPath: String, beforeMarker: (() throws -> Void)? = nil) throws {
  guard calendarTokenPathExists(legacyPath) || calendarTokenPathExists(destinationPath)
    || calendarTokenPathExists(destinationPath + ".migration-complete") else { return }
  try withCalendarTokenMigrationLock(path: destinationPath) {
    try migrateCalendarLegacyTokenStoreLocked(from: legacyPath, to: destinationPath, beforeMarker: beforeMarker)
  }
}

private func migrateCalendarLegacyTokenStoreLocked(from legacyPath: String, to destinationPath: String, beforeMarker: (() throws -> Void)?) throws {
  if calendarTokenPathExists(destinationPath) {
    let parent = try calendarTokenParent(destinationPath, create: true)
    let fd = Darwin.openat(parent.fd, parent.leaf, O_RDONLY | O_NOFOLLOW | O_NONBLOCK)
    guard fd >= 0 else { throw POSIXError(.EACCES) }
    defer { close(fd) }
    try validateCalendarTokenFileDescriptor(fd)
    guard fchmod(fd, S_IRUSR | S_IWUSR) == 0 else { throw POSIXError(.EPERM) }
  }
  let markerPath = destinationPath + ".migration-complete"
  let completed = Data("calendar-token-state-migration-v1\n".utf8)
  let marker: Data?
  do {
    marker = try calendarSecureTokenFileData(at: markerPath)
  } catch let error as POSIXError where error.errorCode == ENOENT {
    marker = nil
  }
  if let marker {
    guard marker == completed else { throw POSIXError(.EINVAL) }
    return
  }
  if calendarTokenPathExists(destinationPath) {
    _ = try calendarSecureTokenFileData(at: destinationPath)
    try writeCalendarSecureTokenFile(completed, to: markerPath)
    return
  }
  guard calendarTokenPathExists(legacyPath) else { return }
  let source = try calendarSecureTokenFileData(at: legacyPath)
  _ = try JSONDecoder().decode(CalendarOAuthTokenStore.self, from: source)
  let destination = try calendarTokenParent(destinationPath, create: true)
  guard try calendarPublishToken(source, parent: destination, leaf: destination.leaf, exclusive: true) else {
    _ = try calendarSecureTokenFileData(at: destinationPath)
    try writeCalendarSecureTokenFile(completed, to: markerPath)
    return
  }
  try beforeMarker?()
  let markerParent = try calendarTokenParent(markerPath, create: true)
  guard try calendarPublishToken(completed, parent: markerParent, leaf: markerParent.leaf, exclusive: true) else {
    guard try calendarSecureTokenFileData(at: markerPath) == completed else { throw POSIXError(.EINVAL) }
    return
  }
}

func withCalendarTokenMigrationLock<T>(path: String, operation: () throws -> T) throws -> T {
  let parent = try calendarTokenParent(path, create: true)
  let leaf = parent.leaf + ".migration.lock"
  let fd = Darwin.openat(parent.fd, leaf, O_CREAT | O_RDWR | O_NOFOLLOW, S_IRUSR | S_IWUSR)
  guard fd >= 0 else { throw POSIXError(.EACCES) }
  defer { close(fd) }
  try validateCalendarTokenFileDescriptor(fd)
  guard fchmod(fd, S_IRUSR | S_IWUSR) == 0, flock(fd, LOCK_EX) == 0 else { throw POSIXError(.EACCES) }
  defer { flock(fd, LOCK_UN) }
  return try operation()
}

@discardableResult
private func validateCalendarTokenFileDescriptor(_ fd: Int32) throws -> stat {
  var info = stat()
  guard Darwin.fstat(fd, &info) == 0,
        (info.st_mode & S_IFMT) == S_IFREG,
        info.st_uid == geteuid(),
        info.st_nlink == 1 else {
    throw POSIXError(.EPERM)
  }
  return info
}

private func calendarTokenPathExists(_ path: String) -> Bool {
  var info = stat()
  return Darwin.lstat(path, &info) == 0
}
