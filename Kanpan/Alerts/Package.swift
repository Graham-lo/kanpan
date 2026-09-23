// swift-tools-version: 6.2
import PackageDescription

// 提醒模块的**测试壳**。
//
// 和 `Kanpan/Sector`、`Kanpan/AccountCodec` 同一个套路：app 工程用的是 file-system
// synchronized group，提醒的真身放在 `Kanpan/Kanpan/Alerts/`，扔进去就自动进 app
// target；但那个工程里没有 test target，所以这里开一个只管跑测试的 SwiftPM 包，
// `Sources/KanpanAlerts/` 下全是**指向真身的符号链接**，一份代码两处编。
//
// 只链在 mac 上也编得动、也量得到东西的那四件：存档与对账（`AlertArchive`）、
// 那份存档的管家（`AlertStore`）、前台的到价判定（`AlertEngine`——只吃 Combine 与
// `KanpanCore`，把一口一口的价折成 1 分钟桶交给 `AlertEvaluator`）、以及
// 「通知关着那一行出不出」的判据（`AlertPermission`——`UNAuthorizationStatus`
// 在 mac 上也有，它那半句 `UIApplication.openSettingsURLString` 自己用
// `#if canImport(UIKit)` 圈着）。P3.1 又添两件：复盘到点折成提醒的对账
// （`ReviewDueAlerts`）、自选五分钟波动的前台接线（`WatchMoveMonitor`）。
// 问句（`AlertPrompt`）、总表（`AlertListPage`）吃 SwiftUI，
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
      path: "Sources/KanpanAlerts",
      // `AlertEngine.bucketState` 这类只读测试口子在 app 里只进 DEBUG 包；
      // 测试壳在 `swift test -c release` 下也要编得进来，所以这里单独打开。
      swiftSettings: [.define("KANPAN_TEST_SUPPORT")]
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
