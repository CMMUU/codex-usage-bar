// swift-tools-version: 6.3

import PackageDescription

let package = Package(
  name: "CodexUsageBar",
  platforms: [
    .macOS(.v13)
  ],
  products: [
    .executable(name: "CodexUsageBar", targets: ["CodexUsageBar"]),
    .executable(name: "CodexUsageWidget", targets: ["CodexUsageWidget"]),
  ],
  dependencies: [
    .package(
      url: "https://github.com/sparkle-project/Sparkle",
      exact: "2.9.4"
    )
  ],
  targets: [
    .target(
      name: "CodexUsageCore",
      path: "Sources/CodexUsageCore"
    ),
    .target(
      name: "CodexUsageShared",
      path: "Sources/CodexUsageShared"
    ),
    .executableTarget(
      name: "CodexUsageBar",
      dependencies: [
        "CodexUsageCore",
        "CodexUsageShared",
        .product(name: "Sparkle", package: "Sparkle"),
      ],
      path: "Sources/CodexUsageBar"
    ),
    .executableTarget(
      name: "CodexUsageWidget",
      dependencies: ["CodexUsageShared"],
      path: "Sources/CodexUsageWidget"
    ),
    .executableTarget(
      name: "CodexUsageVerifier",
      dependencies: ["CodexUsageCore", "CodexUsageShared"],
      path: "Tests/CodexUsageVerifier"
    ),
  ],
  swiftLanguageModes: [.v5]
)
