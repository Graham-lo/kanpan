// swift-tools-version: 6.0
import PackageDescription

// 「客户端替哪些字段说话」那张表的跑道。
//
// `PersonalSyncCodec` 住在 app 靶子里（`Kanpan/Kanpan/Account/`），而 app 工程用的是
// file-system synchronized group、**没有 test target**，所以照 `Kanpan/Settings` 和
// `Kanpan/Symbols` 的老规矩另起一个只管跑测试的 SwiftPM 包：
// `Sources/KanpanAccountCodec/` 下全是**指向真身的符号链接**，一份代码两处编。
//
// 为什么非要把设置模型和 `SymbolPrefs` 一起链进来：`PersonalSyncCodec` 吃的
// `Prefs` / `PrefsCodec` / `SymbolPrefs` 都是 **internal** 的，import 隔壁那两个测试壳
// 根本看不见它们。app 靶子里这三摊本来就在同一个模块里，这儿照搬那个形状——
// 同一个模块编到一起，测试看到的就是 app 看到的。
//
//     cd Kanpan/AccountCodec && swift test
let package = Package(
  name: "KanpanAccountCodec",
  platforms: [.iOS(.v18), .macOS(.v14)],
  products: [
    .library(name: "KanpanAccountCodec", targets: ["KanpanAccountCodec"]),
  ],
  dependencies: [
    .package(path: "../../KanpanCore"),
    .package(path: "../../KanpanData"),
    .package(path: "../../KanpanAccount"),
  ],
  targets: [
    .target(
      name: "KanpanAccountCodec",
      dependencies: [
        .product(name: "KanpanCore", package: "KanpanCore"),
        .product(name: "KanpanData", package: "KanpanData"),
        .product(name: "KanpanAccount", package: "KanpanAccount"),
      ],
      path: "Sources/KanpanAccountCodec"
    ),
    .testTarget(
      name: "KanpanAccountCodecTests",
      dependencies: [
        "KanpanAccountCodec",
        .product(name: "KanpanCore", package: "KanpanCore"),
        .product(name: "KanpanAccount", package: "KanpanAccount"),
      ],
      path: "Tests/KanpanAccountCodecTests"
    ),
  ]
)
