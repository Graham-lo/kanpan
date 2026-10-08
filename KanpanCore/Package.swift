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
      // 三端共读的唯一一份：指标名与出厂参数（`IndicatorID.catalog`）、大单与爆仓的用词（`BigTradeTerm`）。
      resources: [.process("Indicator/indicators.json"), .process("Terms/terms.json")]
    ),
    .testTarget(
      name: "KanpanCoreTests",
      dependencies: ["KanpanCore"],
      path: "Tests/KanpanCoreTests",
      resources: [.copy("Fixtures")]
    ),
  ]
)
