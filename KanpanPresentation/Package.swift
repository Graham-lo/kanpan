// swift-tools-version: 6.2
import PackageDescription

// 展示层的令牌：三套皮肤的配色种子、图表用色表，以及几处设置里给人看的档位名。
//
// 这些原来都在 `KanpanCore` 里（审查 24）：Core 本该只装行情模型与算法，可皮肤、色值、
// 「上海0点」这类界面文案也住在那儿，于是改一支颜色就要重编整个 Core、连带所有依赖它的包，
// 而一个只要算指标的包也被迫认识「青苔」「陶土」。现在拆成：
// - `Hex`（颜色值本身）留在 Core——画线存档、指标默认色、小组件快照里都存颜色，它是数据；
// - 颜色**是哪一套、怎么配**（`Skin` / `PaletteSeed` / `Palette` / `ChartColors`）和档位名住这里。
//
// 只依赖 KanpanCore、只用 Foundation，所以 mac 上 `swift test` 就能跑。
// 图表层、app、小组件三方都用它；Review 包只在注释里提到种子，不依赖它。
let package = Package(
  name: "KanpanPresentation",
  platforms: [.iOS(.v26), .macOS(.v14)],
  products: [
    .library(name: "KanpanPresentation", targets: ["KanpanPresentation"]),
  ],
  dependencies: [
    .package(path: "../KanpanCore"),
  ],
  targets: [
    .target(
      name: "KanpanPresentation",
      dependencies: [.product(name: "KanpanCore", package: "KanpanCore")],
      path: "Sources/KanpanPresentation"
    ),
    .testTarget(
      name: "KanpanPresentationTests",
      dependencies: ["KanpanPresentation", .product(name: "KanpanCore", package: "KanpanCore")],
      path: "Tests/KanpanPresentationTests"
    ),
  ]
)
