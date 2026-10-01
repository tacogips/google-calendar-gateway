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
  dependencies: [.package(url: "https://github.com/tacogips/google-gateway-auth.git", revision: "28331014f2ab9f8f02f77d068421afac105150dc")],
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
