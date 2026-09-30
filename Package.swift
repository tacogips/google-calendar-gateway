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
  targets: [
    .target(name: "GoogleCalendarGatewayCore"),
    .executableTarget(
      name: "GoogleCalendarGatewayReader",
      dependencies: ["GoogleCalendarGatewayCore"],
      path: "Sources/GoogleCalendarGatewayReader"
    ),
    .executableTarget(
      name: "GoogleCalendarGatewayWriter",
      dependencies: ["GoogleCalendarGatewayCore"]
    ),
    .testTarget(
      name: "GoogleCalendarGatewayCoreTests",
      dependencies: ["GoogleCalendarGatewayCore"],
      path: "Tests/AppCoreTests"
    )
  ],
  swiftLanguageModes: [.v6]
)
