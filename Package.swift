// swift-tools-version: 6.0

import PackageDescription

let package = Package(
  name: "google-calendar-gateway",
  platforms: [
    .macOS(.v14)
  ],
  products: [
    .library(name: "GoogleCalendarGatewayCore", targets: ["GoogleCalendarGatewayCore"]),
    .executable(name: "google-calendar-gateway-reader", targets: ["GoogleCalendarGatewayReader"]),
    .executable(name: "google-calendar-gateway-writer", targets: ["GoogleCalendarGatewayWriter"])
  ],
  dependencies: [.package(url: "https://github.com/tacogips/google-gateway-auth.git", revision: "258c3b74c58fa8df8fdcea617d419c4d0cab7628")],
  targets: [
    .target(name: "GoogleCalendarGatewayCore", dependencies: [.product(name: "GoogleGatewayAuth", package: "google-gateway-auth")]),
    .executableTarget(
      name: "GoogleCalendarGatewayReader",
      dependencies: [.product(name: "GoogleGatewayAuth", package: "google-gateway-auth"), "GoogleCalendarGatewayCore"],
      path: "Sources/GoogleCalendarGatewayReader"
    ),
    .executableTarget(
      name: "GoogleCalendarGatewayWriter",
      dependencies: [.product(name: "GoogleGatewayAuth", package: "google-gateway-auth"), "GoogleCalendarGatewayCore"]
    ),
    .testTarget(
      name: "GoogleCalendarGatewayCoreTests",
      dependencies: ["GoogleCalendarGatewayCore"],
      path: "Tests/AppCoreTests"
    )
  ],
  swiftLanguageModes: [.v6]
)
