// swift-tools-version: 6.2
import PackageDescription

// 板块页的**测试壳**。
//
// 和 `Kanpan/Symbols`、`Kanpan/KanpanTests` 同一个套路：app 工程
// （Kanpan/Kanpan.xcodeproj）用的是 file-system synchronized group，板块页的真身放在
// `Kanpan/Kanpan/Sector/`，扔进去就自动进 app target；但那个工程里没有 test target，
// 所以这里开一个只管跑测试的 SwiftPM 包，`Sources/KanpanSector/` 下全是**指向真身的
// 符号链接**，一份代码两处编，不会各自走样。
//
// 里面只放不吃 SwiftUI 的那几件：取数（`SectorFeed`）、列表的值与文案与排序
// （`SectorRows`）、窗口这一档（`SectorWindowChoice`）、下钻去留（`SectorDrillDecision`）、
// 板块记号表（`SectorIconTable`，只有 id / 身份色 / 路径，画法留在 `SectorIcon.swift`）。
// 页面外壳那些吃 SwiftUI/UIKit，证据走 UI 用例和真机。
//
// 跑：cd Kanpan/Sector && swift test（或 make sector-test）

let package = Package(
  name: "KanpanSector",
  platforms: [.iOS(.v26), .macOS(.v14)],
  products: [
    .library(name: "KanpanSector", targets: ["KanpanSector"]),
  ],
  dependencies: [
    .package(path: "../../KanpanCore"),
    .package(path: "../../KanpanNetwork"),
  ],
  targets: [
    .target(
      name: "KanpanSector",
      dependencies: [
        .product(name: "KanpanCore", package: "KanpanCore"),
        .product(name: "KanpanNetwork", package: "KanpanNetwork"),
      ],
      path: "Sources/KanpanSector"
    ),
    .testTarget(
      name: "KanpanSectorTests",
      dependencies: [
        "KanpanSector",
        .product(name: "KanpanCore", package: "KanpanCore"),
        .product(name: "KanpanNetwork", package: "KanpanNetwork"),
      ],
      path: "Tests/KanpanSectorTests"
    ),
  ]
)
