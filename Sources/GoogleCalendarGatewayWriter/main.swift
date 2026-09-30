import GoogleGatewayAuth
import Foundation
import GoogleCalendarGatewayCore

let gatewayInvocation = GatewayAuthBootstrap.prepareOrExit(product: .calendar, role: "writer")

let result = GoogleCalendarGatewayCLI(mode: .writer).run(arguments: gatewayInvocation.arguments, environment: gatewayInvocation.environment)

if !result.stdout.isEmpty {
  FileHandle.standardOutput.write(Data(result.stdout.utf8))
}
if !result.stderr.isEmpty {
  FileHandle.standardError.write(Data(result.stderr.utf8))
}
exit(gatewayInvocation.complete(exitCode: result.exitCode))
