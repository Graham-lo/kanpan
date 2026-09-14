// swift-tools-version: 6.0
import PackageDescription

// 绘制层：UIKit + CoreGraphics 手绘，零第三方依赖。
// 算法一律走 KanpanCore，这里只负责把数落到像素上。
let package = Package(
  name: "KanpanChart",
  platforms: [.iOS(.v17), .macOS(.v14)],
  products: [.library(name: "KanpanChart", targets: ["KanpanChart"])],
  dependencies: [.package(path: "../KanpanCore")],
  targets: [
    .target(
      name: "KanpanChart",
      dependencies: [.product(name: "KanpanCore", package: "KanpanCore")],
      swiftSettings: [.swiftLanguageMode(.v6)]
    ),
    .testTarget(
      name: "KanpanChartTests",
      dependencies: ["KanpanChart"],
      swiftSettings: [.swiftLanguageMode(.v6)]
    ),
  ]
)
