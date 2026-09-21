// swift-tools-version: 6.2
import PackageDescription

let package = Package(
  name: "KanpanData",
  platforms: [.iOS(.v26), .macOS(.v14)],
  products: [
    .library(name: "KanpanData", targets: ["KanpanData"]),
    .executable(name: "kanpan-feed", targets: ["kanpan-feed"]),
  ],
  dependencies: [
    .package(path: "../KanpanCore"),
    .package(path: "../KanpanNetwork"),
  ],
  targets: [
    .target(
      name: "KanpanData",
      dependencies: [
        .product(name: "KanpanCore", package: "KanpanCore"),
        .product(name: "KanpanNetwork", package: "KanpanNetwork"),
      ],
      path: "Sources/KanpanData"
    ),
    .executableTarget(
      name: "kanpan-feed",
      dependencies: ["KanpanData", .product(name: "KanpanCore", package: "KanpanCore")],
      path: "Sources/kanpan-feed"
    ),
    .testTarget(
      name: "KanpanDataTests",
      dependencies: [
        "KanpanData",
        .product(name: "KanpanCore", package: "KanpanCore"),
        .product(name: "KanpanNetworkTestSupport", package: "KanpanNetwork"),
      ],
      path: "Tests/KanpanDataTests",
      resources: [.copy("Fixtures")]
    ),
  ]
)
