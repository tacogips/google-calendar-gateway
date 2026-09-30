import Foundation

func calendarTokenSourceDetails(_ credential: CalendarCredentialConfig) -> [String: String] {
  let jsonVariable = GoogleCalendarGatewayConfigLoader.getCredentialJSONEnvVarName(credentialId: credential.id, valueKey: "token_store_json")
  let pathVariable = GoogleCalendarGatewayConfigLoader.getCredentialPathEnvVarName(credentialId: credential.id, pathKey: "token_store_path")
  var details = ["credentialId": credential.id]
  if credential.tokenStoreJSON != nil {
    details["tokenSource"] = "ENVIRONMENT_JSON"
    details["tokenEnvironmentVariable"] = jsonVariable
    details["tokenSourceHint"] = "Unset \(jsonVariable) before login; inline JSON overrides token files."
    if credential.tokenStorePathFromEnvironment { details["tokenPathEnvironmentVariable"] = pathVariable }
  } else {
    details["tokenSource"] = credential.tokenStorePathFromEnvironment ? "ENVIRONMENT_PATH" : "FILE"
    details["tokenStorePath"] = credential.tokenStorePath
    details["tokenSourceHint"] = "Keep \(jsonVariable) unset and select this path with \(pathVariable); environment paths override config paths."
    if credential.tokenStorePathFromEnvironment { details["tokenEnvironmentVariable"] = pathVariable }
  }
  return details
}

func calendarTokenSourceError(_ error: GoogleCalendarGatewayError, credential: CalendarCredentialConfig) -> GoogleCalendarGatewayError {
  let metadata = calendarTokenSourceDetails(credential)
  let summary = metadata.keys.sorted().compactMap { key in metadata[key].map { "\(key)=\($0)" } }.joined(separator: "; ")
  return GoogleCalendarGatewayError(
    "\(error.message) (\(summary))", code: error.code, exitCode: error.exitCode,
    details: error.details.merging(metadata) { _, selected in selected }
  )
}
