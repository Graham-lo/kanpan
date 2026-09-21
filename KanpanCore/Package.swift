// swift-tools-version: 6.2
import PackageDescription

let package = Package(
  name: "KanpanCore",
  platforms: [.iOS(.v26), .macOS(.v14)],
  products: [
    .library(name: "KanpanCore", targets: ["KanpanCore"]),
  ],
  targets: [
    .target(
      name: "KanpanCore",
      path: "Sources/KanpanCore"
    ),
    .testTarget(
      name: "KanpanCoreTests",
      dependencies: ["KanpanCore"],
      path: "Tests/KanpanCoreTests",
      resources: [.copy("Fixtures")]
    ),
  ]
)
