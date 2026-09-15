// swift-tools-version: 6.0
import PackageDescription

// 设置模型层的单测跑道。
//
// app 工程用的是 Xcode file-system synchronized group，没有测试 target，
// 加一个就得改 `project.pbxproj`——那个文件这轮不许动（同一个仓库里还有别的人在改）。
// 所以这里另起一个 SwiftPM 包，`Sources/KanpanSettings` 是一条软链，指回
// `Kanpan/Kanpan/Settings/Model/`：**同一批 .swift 文件**，app 那边由 synchronized
// group 自动收进 target，这边由 SwiftPM 编成模块给 `swift test` 跑。没有副本，
// 不会两边走样。
//
//     cd Kanpan/Settings && swift test
//
// 链上 KanpanData 是故意的：这样 `#if canImport(KanpanData)` 那支
// （`DiskMarketCache`，A6.11 的清缓存）在测试里是真编真跑的。app target 现在
// 只链 KanpanCore，走的是 `#else` 的占位实现，由 `make build` 覆盖。
let package = Package(
  name: "KanpanSettings",
  platforms: [.iOS(.v17), .macOS(.v14)],
  products: [
    .library(name: "KanpanSettings", targets: ["KanpanSettings"]),
  ],
  dependencies: [
    .package(path: "../../KanpanCore"),
    .package(path: "../../KanpanData"),
  ],
  targets: [
    .target(
      name: "KanpanSettings",
      dependencies: [
        .product(name: "KanpanCore", package: "KanpanCore"),
        .product(name: "KanpanData", package: "KanpanData"),
      ],
      path: "Sources/KanpanSettings"
    ),
    .testTarget(
      name: "KanpanSettingsTests",
      dependencies: [
        "KanpanSettings",
        .product(name: "KanpanCore", package: "KanpanCore"),
      ],
      path: "Tests/KanpanSettingsTests"
    ),
    // 这儿原来还有 `KanpanStyleArt` / `KanpanStyleArtTests`：把十一款风格的缩略图
    // 用 `ImageRenderer` 真画出来存 PNG 的取证跑道（A6.2）。风格收成 AICoin 一套之后
    // 缩略图和风格卡都撤了，跑道跟着撤。
  ]
)
