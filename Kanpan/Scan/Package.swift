// swift-tools-version: 6.0
import PackageDescription

// 连续扫图与「看细节」的**测试壳**。
//
// 和 `Kanpan/Symbols`、`Kanpan/Sector` 同一个套路：真身住在 `Kanpan/Kanpan/Main/`
// （app 工程用的是 file-system synchronized group，扔进去就自动进 app target），
// 但那个工程里没有 test target，所以这里开一个只管跑测试的 SwiftPM 包，
// `Sources/KanpanScan/` 下全是**指向真身的符号链接**，一份代码两处编，不会各自走样。
//
// 里面只放不吃 SwiftUI 的那两件：名单与下标（`ScanList`）、更细的那一档与视野窗
// （`DetailZoom`）。手势、按钮、周期条那几块吃 SwiftUI，证据走真机 / 模拟器。
//
// 跑：cd Kanpan/Scan && swift test（或 make scan-test）

let package = Package(
  name: "KanpanScan",
  platforms: [.iOS(.v18), .macOS(.v14)],
  products: [
    .library(name: "KanpanScan", targets: ["KanpanScan"]),
  ],
  dependencies: [
    .package(path: "../../KanpanCore"),
  ],
  targets: [
    .target(
      name: "KanpanScan",
      dependencies: [
        .product(name: "KanpanCore", package: "KanpanCore"),
      ],
      path: "Sources/KanpanScan"
    ),
    .testTarget(
      name: "KanpanScanTests",
      dependencies: [
        "KanpanScan",
        .product(name: "KanpanCore", package: "KanpanCore"),
      ],
      path: "Tests/KanpanScanTests"
    ),
  ]
)
