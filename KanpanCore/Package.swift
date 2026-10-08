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
      path: "Sources/KanpanCore",
      // 指标名与出厂参数的唯一一份（iOS / 手机网页 / 电脑网页三端共读），见 `IndicatorID.catalog`。
      resources: [.process("Indicator/indicators.json")]
    ),
    .testTarget(
      name: "KanpanCoreTests",
      dependencies: ["KanpanCore"],
      path: "Tests/KanpanCoreTests",
      resources: [.copy("Fixtures")]
    ),
  ]
)
