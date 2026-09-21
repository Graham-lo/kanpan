// swift-tools-version: 6.2
import PackageDescription

// 提醒模块的**测试壳**。
//
// 和 `Kanpan/Sector`、`Kanpan/AccountCodec` 同一个套路：app 工程用的是 file-system
// synchronized group，提醒的真身放在 `Kanpan/Kanpan/Alerts/`，扔进去就自动进 app
// target；但那个工程里没有 test target，所以这里开一个只管跑测试的 SwiftPM 包，
// `Sources/KanpanAlerts/` 下全是**指向真身的符号链接**，一份代码两处编。
//
// 只链不吃 SwiftUI / UIKit 的那两件：存档与对账（`AlertArchive`）和那份存档的
// 管家（`AlertStore`）。问句（`AlertPrompt`）、总表（`AlertListPage`）吃 SwiftUI，
// 「响了怎么走到人眼前」（`AlertWatcher` / `AlertNotifications`）吃 UIKit 与
// UserNotifications，那几件的证据走模拟器。
//
// 纯逻辑（几何摊平、触发判定、线价插值）在 `KanpanCore/Alerts`，跑
// `swift test --package-path KanpanCore --filter Alert`。
//
// 跑：cd Kanpan/Alerts && swift test（或 make alerts-test）

let package = Package(
  name: "KanpanAlerts",
  platforms: [.iOS(.v26), .macOS(.v14)],
  products: [
    .library(name: "KanpanAlerts", targets: ["KanpanAlerts"]),
  ],
  dependencies: [
    .package(path: "../../KanpanCore"),
  ],
  targets: [
    .target(
      name: "KanpanAlerts",
      dependencies: [.product(name: "KanpanCore", package: "KanpanCore")],
      path: "Sources/KanpanAlerts"
    ),
    .testTarget(
      name: "KanpanAlertsTests",
      dependencies: [
        "KanpanAlerts",
        .product(name: "KanpanCore", package: "KanpanCore"),
      ],
      path: "Tests/KanpanAlertsTests"
    ),
  ]
)
