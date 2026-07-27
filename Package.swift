// swift-tools-version: 6.3

import PackageDescription

let package = Package(
  name: "CodexUsageBar",
  platforms: [
    .macOS(.v13)
  ],
  products: [
    .executable(name: "CodexUsageBar", targets: ["CodexUsageBar"])
  ],
  targets: [
    .target(
      name: "CodexUsageCore",
      path: "Sources/CodexUsageCore"
    ),
    .executableTarget(
      name: "CodexUsageBar",
      dependencies: ["CodexUsageCore"],
      path: "Sources/CodexUsageBar"
    ),
    .executableTarget(
      name: "CodexUsageVerifier",
      dependencies: ["CodexUsageCore"],
      path: "Tests/CodexUsageVerifier"
    ),
  ],
  swiftLanguageModes: [.v5]
)
