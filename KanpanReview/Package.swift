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
    .testTarget(name: "ReviewDomainTests", dependencies: ["ReviewDomain", "ReviewData"])])
