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
  dependencies: [.package(url: "https://github.com/tacogips/google-gateway-auth.git", revision: "dda86daa5ca1b9a761977e4a9891e4e4380cf4dd")],
  targets: [
    .target(name: "GoogleCalendarGatewayCore"),
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
