import Foundation

func nonBlank(_ value: String?) -> String? {
  guard let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines),
        !trimmed.isEmpty else {
    return nil
  }
  return trimmed
}

func normalizedPath(_ path: String) -> String {
  NSString(string: path).expandingTildeInPath
}

func canonicalPath(_ path: String) -> String {
  URL(fileURLWithPath: normalizedPath(path))
    .standardizedFileURL
    .resolvingSymlinksInPath()
    .path
}

func isWithinRoot(rootPath: String, candidatePath: String) -> Bool {
  let root = canonicalPath(rootPath)
  let candidate = canonicalPath(candidatePath)
  return candidate == root || candidate.hasPrefix(root.hasSuffix("/") ? root : root + "/")
}

func base64URLString(_ data: Data) -> String {
  data.base64EncodedString()
    .replacingOccurrences(of: "+", with: "-")
    .replacingOccurrences(of: "/", with: "_")
    .replacingOccurrences(of: "=", with: "")
}

func dataFromBase64URLString(_ value: String) -> Data? {
  guard isBase64URLString(value),
        value.count % 4 != 1 else {
    return nil
  }
  var base64 = value
    .replacingOccurrences(of: "-", with: "+")
    .replacingOccurrences(of: "_", with: "/")
  base64 += String(repeating: "=", count: (4 - base64.count % 4) % 4)
  return Data(base64Encoded: base64)
}

func formURLEncoded(_ fields: [(String, String)]) -> String {
  fields
    .map { key, value in
      "\(urlFormEncode(key))=\(urlFormEncode(value))"
    }
    .joined(separator: "&")
}

func jsonString(_ payload: Any, pretty: Bool) -> String {
  let options: JSONSerialization.WritingOptions = pretty ? [.prettyPrinted, .sortedKeys] : [.sortedKeys]
  guard JSONSerialization.isValidJSONObject(payload),
        let data = try? JSONSerialization.data(withJSONObject: payload, options: options),
        let string = String(data: data, encoding: .utf8) else {
    return "{\"error\":{\"message\":\"Failed to encode JSON\"}}"
  }
  return string
}

private func urlFormEncode(_ value: String) -> String {
  let allowed = CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~")
  return value.addingPercentEncoding(withAllowedCharacters: allowed) ?? value
}

private func isBase64URLString(_ value: String) -> Bool {
  var hasPadding = false
  for scalar in value.unicodeScalars {
    switch scalar.value {
    case 48...57, 65...90, 97...122, 45, 95:
      if hasPadding {
        return false
      }
    case 61:
      hasPadding = true
    default:
      return false
    }
  }
  return true
}

func intValue(_ value: Any?) -> Int? {
  if let string = value as? String {
    return Int(string.trimmingCharacters(in: .whitespacesAndNewlines))
  }
  guard let number = value as? NSNumber,
        CFGetTypeID(number) != CFBooleanGetTypeID() else {
    return nil
  }
  let double = number.doubleValue
  guard double.rounded() == double else {
    return nil
  }
  return number.intValue
}

func urlEncodedPathComponent(_ value: String) -> String {
  let allowed = CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~")
  return value.addingPercentEncoding(withAllowedCharacters: allowed) ?? value
}

func isRFC3339DateTime(_ value: String) -> Bool {
  guard nonBlank(value) == value,
        value.contains("T") else {
    return false
  }
  return iso8601DateFormatter(fractionalSeconds: false).date(from: value) != nil ||
    iso8601DateFormatter(fractionalSeconds: true).date(from: value) != nil
}

private func iso8601DateFormatter(fractionalSeconds: Bool) -> ISO8601DateFormatter {
  let formatter = ISO8601DateFormatter()
  formatter.formatOptions = fractionalSeconds
    ? [.withInternetDateTime, .withFractionalSeconds]
    : [.withInternetDateTime]
  return formatter
}

func isCalendarDate(_ value: String) -> Bool {
  let pattern = #"^\d{4}-\d{2}-\d{2}$"#
  guard value.range(of: pattern, options: .regularExpression) != nil else {
    return false
  }
  let formatter = DateFormatter()
  formatter.calendar = Calendar(identifier: .gregorian)
  formatter.locale = Locale(identifier: "en_US_POSIX")
  formatter.timeZone = TimeZone(secondsFromGMT: 0)
  formatter.dateFormat = "yyyy-MM-dd"
  formatter.isLenient = false
  return formatter.date(from: value) != nil
}
