// swift-tools-version: 6.0
import PackageDescription

// 深链路由的**测试壳**。
//
// 和 `Kanpan/Symbols`、`Kanpan/Sector` 同一个套路：app 工程用的是 file-system
// synchronized group，深链的真身放在 `Kanpan/Kanpan/Main/DeepLink.swift`，扔进去
// 就自动进 app target；但那个工程没有 test target，所以这里开一个只管跑测试的
// SwiftPM 包，`Sources/KanpanDeepLink/` 下是**指向真身的符号链接**，一份代码
// 两处编，不会各自走样。
//
// 零依赖是故意的：`DeepLink` 只认 URL，不认品种表、不认周期枚举（`interval`
// 原样是个字符串，翻译成 `Interval` 是 `MainScreen` 的事）。这样这条跑道在 mac 上
// `swift test` 全速跑，不用起模拟器，也就能挂进 `make app-logic-test`。
//
// 跑：cd Kanpan/DeepLink && swift test（或 make deeplink-test）

let package = Package(
  name: "KanpanDeepLink",
  platforms: [.iOS(.v18), .macOS(.v14)],
  products: [
    .library(name: "KanpanDeepLink", targets: ["KanpanDeepLink"]),
  ],
  targets: [
    .target(
      name: "KanpanDeepLink",
      path: "Sources/KanpanDeepLink"
    ),
    .testTarget(
      name: "KanpanDeepLinkTests",
      dependencies: ["KanpanDeepLink"],
      path: "Tests/KanpanDeepLinkTests"
    ),
  ]
)
