// swift-tools-version: 6.2
import Foundation
import PackageDescription

// 主界面（`Kanpan/Kanpan/Main/`）那几个生命周期件的**测试壳**。
//
// 和 `Kanpan/Symbols`、`Kanpan/Settings` 同一个套路：app 工程没有 test action，
// 所以开一个只管跑测试的 SwiftPM 包，`Sources/KanpanMain/` 下全是**指向真身的
// 符号链接**，一份代码两处编，不会各自走样。
//
// 里面这几个都吃 UIKit / CADisplayLink / `UIApplication`，mac 上编得过也量不到
// 东西，所以跑法和 `make diag-ios-test` 一样要起模拟器：
//
//   cd Kanpan/KanpanTests && xcodebuild test -scheme KanpanMain \
//     -destination 'platform=iOS Simulator,name=iPhone 16 Pro' -derivedDataPath .xcbuild

// `make strict` 置 KANPAN_STRICT=KanpanMain 时本包自己的 target 警告即错误（为什么不走
// xcodebuild 的 SWIFT_TREAT_WARNINGS_AS_ERRORS、为什么认包名，见 KanpanChart/Package.swift 顶上）。
let strict: [SwiftSetting] = ProcessInfo.processInfo.environment["KANPAN_STRICT"] == "KanpanMain"
  ? [.treatAllWarnings(as: .error)] : []

let package = Package(
  name: "KanpanMain",
  platforms: [.iOS(.v26), .macOS(.v14)],
  products: [
    .library(name: "KanpanMain", targets: ["KanpanMain"]),
  ],
  dependencies: [
    .package(path: "../../KanpanCore"),
    .package(path: "../../KanpanChart"),
    .package(path: "../../KanpanNetwork"),
    .package(path: "../../KanpanData"),
    .package(path: "../../KanpanAccount"),
  ],
  targets: [
    .target(
      name: "KanpanMain",
      dependencies: [
        .product(name: "KanpanCore", package: "KanpanCore"),
        .product(name: "KanpanChart", package: "KanpanChart"),
        .product(name: "KanpanNetwork", package: "KanpanNetwork"),
        .product(name: "KanpanData", package: "KanpanData"),
        .product(name: "KanpanAccount", package: "KanpanAccount"),
      ],
      path: "Sources/KanpanMain",
      swiftSettings: strict
    ),
    .testTarget(
      name: "KanpanMainTests",
      dependencies: [
        "KanpanMain",
        .product(name: "KanpanCore", package: "KanpanCore"),
        .product(name: "KanpanChart", package: "KanpanChart"),
        .product(name: "KanpanNetwork", package: "KanpanNetwork"),
        .product(name: "KanpanAccount", package: "KanpanAccount"),
      ],
      path: "Tests/KanpanMainTests",
      swiftSettings: strict
    ),
  ]
)
