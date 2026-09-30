import Foundation

/// Canonical inputs and historical aliases. Never include credential values in errors.
func calendarCredentialEnvironment(
  _ source: [String: String], credentialIDs: [String] = ["google-personal"]
) throws -> [String: String] {
  var result = source
  let prefix = "GOOGLE_CALENDAR_GATEWAY_"
  let suffixes = [
    ("OAUTH_CLIENT_JSON", "OAUTH_CLIENT_SECRET_JSON"),
    ("OAUTH_CLIENT_PATH", "OAUTH_CLIENT_SECRET_PATH"),
    ("TOKEN_STORE_JSON", "TOKEN_STORE_JSON"),
    ("TOKEN_STORE_PATH", "TOKEN_STORE_PATH"),
    ("ACCESS_TOKEN", "ACCESS_TOKEN")
  ]
  for id in credentialIDs {
    let profile = "CREDENTIAL_\(identifierEnvironmentKey(id))_"
    let hasSpecific: [Bool: Bool] = Dictionary(uniqueKeysWithValues: [false, true].map { isApplication in
      let present = suffixes.filter { $0.0.hasPrefix("OAUTH_CLIENT_") == isApplication }.contains { canonical, legacy in
        let keys = [prefix + profile + canonical, prefix + profile + legacy, "CALENDAR_GATEWAY_" + profile + legacy]
        return keys.contains { nonBlank(source[$0]) != nil }
      }
      return (isApplication, present)
    })
    for (canonical, legacy) in suffixes {
      let names = [prefix + profile + canonical, prefix + profile + legacy,
                   "CALENDAR_GATEWAY_" + profile + legacy]
      let specific = try calendarEnvironmentAlias(source, names: Array(Set(names)).sorted())
      let value = try specific ?? (hasSpecific[canonical.hasPrefix("OAUTH_CLIENT_")] == true
        ? nil : calendarEnvironmentAlias(source, names: [prefix + canonical]))
      if let value { result[prefix + profile + legacy] = value }
    }
    let tokenKey = prefix + profile + "ACCESS_TOKEN"
    if let token = nonBlank(result[tokenKey]) {
      guard token.utf8.count <= 8192, !token.utf8.contains(where: { $0 < 33 || $0 == 127 }) else {
        throw configError("ACCESS_TOKEN contains unsupported characters")
      }
      let jsonKey = prefix + profile + "TOKEN_STORE_JSON"
      let pathKey = prefix + profile + "TOKEN_STORE_PATH"
      guard nonBlank(result[jsonKey]) == nil, nonBlank(result[pathKey]) == nil else {
        throw configError("ACCESS_TOKEN cannot be combined with TOKEN_STORE_JSON or TOKEN_STORE_PATH for credential \(id)")
      }
      let data = try JSONSerialization.data(withJSONObject: ["accessToken": token, "tokenType": "Bearer"])
      guard let json = String(data: data, encoding: .utf8) else {
        throw configError("Unable to encode external access token")
      }
      result[jsonKey] = json
    }
  }
  return result
}

private func calendarEnvironmentAlias(_ source: [String: String], names: [String]) throws -> String? {
  let entries = names.compactMap { name in nonBlank(source[name]).map { (name, $0) } }
  guard let first = entries.first else { return nil }
  guard entries.allSatisfy({ $0.1 == first.1 }) else {
    throw configError("Conflicting credential environment variables: \(entries.map { $0.0 }.joined(separator: ", "))")
  }
  return first.1
}
