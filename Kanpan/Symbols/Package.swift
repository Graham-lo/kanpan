// swift-tools-version: 6.2
import PackageDescription

// 品种页的**测试壳**。
//
// app 工程（Kanpan/Kanpan.xcodeproj）用的是 file-system synchronized group，
// 品种页的真身就放在 `Kanpan/Kanpan/Symbols/`，扔进去就自动进 app target。
// 但那个工程里**没有 test target**（`make app-test` 会直接报
// 「Scheme Kanpan is not currently configured for the test action」），
// 加 test target 得改 project.pbxproj——那是接线的人的活。
//
// 所以这里开一个只管跑测试的 SwiftPM 包：`Sources/KanpanSymbols/` 下全是
// **指向真身的符号链接**，一份代码两处编，不存在抄一份再走样的问题。
// 视图那一档（SymbolPickerView.swift，吃 SwiftUI/UIKit）不在里面，
// 它的证据走 `#Preview`。
//
// 跑：cd Kanpan/Symbols && swift test

let package = Package(
  name: "KanpanSymbols",
  platforms: [.iOS(.v26), .macOS(.v14)],
  products: [
    .library(name: "KanpanSymbols", targets: ["KanpanSymbols"]),
  ],
  dependencies: [
    .package(path: "../../KanpanCore"),
  ],
  targets: [
    .target(
      name: "KanpanSymbols",
      dependencies: [.product(name: "KanpanCore", package: "KanpanCore")],
      path: "Sources/KanpanSymbols",
      // 假数据 / 帧探针 / 诊断导出在 app 里只进 DEBUG 包（审查 C5）；测试壳在 `swift test -c release`
      // 下也要编得进来，所以这里单独打开。
      swiftSettings: [.define("KANPAN_TEST_SUPPORT")]
    ),
    .testTarget(
      name: "KanpanSymbolsTests",
      dependencies: ["KanpanSymbols", .product(name: "KanpanCore", package: "KanpanCore")],
      path: "Tests/KanpanSymbolsTests"
    ),
  ]
)
