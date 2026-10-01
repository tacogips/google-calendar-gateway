import Foundation
import GoogleGatewayAuth

extension GoogleCalendarGatewayService {
  public func logoutAuth(credentialId: String) throws -> [String: Any] {
    let credential = try requireCredential(credentialId)
    let external = credential.tokenStoreJSON != nil || credential.tokenStorePathFromEnvironment
    let result = try GatewayLogout.perform(externalCredential: external) {
      guard calendarTokenFileExists(at: credential.tokenStorePath) else { return false }
      return try withGoogleCalendarTokenStoreLock(path: credential.tokenStorePath) {
        try removeCalendarSecureTokenFile(at: credential.tokenStorePath)
      }
    }
    return ["credentialId": credentialId, "state": result.state,
            "localTokenDeleted": result.localTokenDeleted,
            "externalCredentialPreserved": result.externalCredentialPreserved]
  }
}
