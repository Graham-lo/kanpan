// swift-tools-version: 6.2
import PackageDescription
let package = Package(name: "KanpanReview", platforms: [.iOS(.v18), .macOS(.v14)],
  products: [.library(name: "KanpanReview", targets: ["ReviewDomain", "ReviewData", "ReviewUI"])],
  // ReviewUI 借 KanpanCore 的价格 / 时间格式化（审查 B-07 / B-08）：复盘本里的价和
  // 时刻必须和顶栏、K 线轴、选区标签同一口径，各自现造 formatter 就会写成三种样子。
  dependencies: [.package(path: "../KanpanCore")],
  targets: [.target(name: "ReviewDomain"), .target(name: "ReviewData", dependencies: ["ReviewDomain"]),
    .target(name: "ReviewUI", dependencies: ["ReviewDomain", "ReviewData",
                                             .product(name: "KanpanCore", package: "KanpanCore")]),
    // 三个测试目标分三层，和报告 B.5 的客户端那张表一一对上：
    // 领域（契约与回放算术）、存档（事务与淘汰）、模型（同步队列与列表口径）。
    // `ReviewUITests` 要 iOS 运行时：ReviewUI 里有 `.keyboardType` 这类只在 UIKit 平台
    // 存在的修饰符，macOS 上编不过，所以整包跑法是
    // `xcodebuild test -scheme KanpanReview -destination 'platform=iOS Simulator,…'`。
    .testTarget(name: "ReviewDomainTests", dependencies: ["ReviewDomain", "ReviewData"]),
    .testTarget(name: "ReviewDataTests", dependencies: ["ReviewDomain", "ReviewData"]),
    .testTarget(name: "ReviewUITests", dependencies: ["ReviewDomain", "ReviewData", "ReviewUI"])])
