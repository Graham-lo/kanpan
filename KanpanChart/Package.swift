// swift-tools-version: 6.2
import Foundation
import PackageDescription

// 绘制层：UIKit + CoreGraphics 手绘，零第三方依赖。
// 算法一律走 KanpanCore，这里只负责把数落到像素上。
//
// A2.13 的「警告即错误」不能走 xcodebuild 的 `SWIFT_TREAT_WARNINGS_AS_ERRORS=YES`：
// 命令行传的构建设置会一路盖到 SwiftPM 依赖 `KanpanCore` 头上，和 Xcode 给包依赖
// 自动加的 `-suppress-warnings` 撞车，报
// `Conflicting options '-warnings-as-errors' and '-suppress-warnings'`。
// 所以收窄成只对本包自己的两个 target 生效，由 `make strict` 置 `KANPAN_STRICT=1` 打开。
let strict = ProcessInfo.processInfo.environment["KANPAN_STRICT"] != nil
let common: [SwiftSetting] =
  [.swiftLanguageMode(.v6)] + (strict ? [.treatAllWarnings(as: .error)] : [])

let package = Package(
  name: "KanpanChart",
  platforms: [.iOS(.v18), .macOS(.v14)],
  products: [.library(name: "KanpanChart", targets: ["KanpanChart"])],
  dependencies: [.package(path: "../KanpanCore")],
  targets: [
    .target(
      name: "KanpanChart",
      dependencies: [.product(name: "KanpanCore", package: "KanpanCore")],
      swiftSettings: common
    ),
    .testTarget(
      name: "KanpanChartTests",
      dependencies: ["KanpanChart"],
      // 取证用的定版快照与原型黄金值（`Tools/export-chart-fixtures.mjs` 生成）。
      resources: [.copy("Fixtures")],
      swiftSettings: common
    ),
  ]
)
