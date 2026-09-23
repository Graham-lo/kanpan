// swift-tools-version: 6.2
import Foundation
import PackageDescription
// `make strict` 置 KANPAN_STRICT=KanpanReview 时本包自己的 target 警告即错误（为什么不走
// xcodebuild 的 SWIFT_TREAT_WARNINGS_AS_ERRORS、为什么认包名，见 KanpanChart/Package.swift 顶上）。
let strict: [SwiftSetting] = ProcessInfo.processInfo.environment["KANPAN_STRICT"] == "KanpanReview"
  ? [.treatAllWarnings(as: .error)] : []
let package = Package(name: "KanpanReview", platforms: [.iOS(.v26), .macOS(.v14)],
  products: [.library(name: "KanpanReview", targets: ["ReviewDomain", "ReviewData", "ReviewUI"])],
  // ReviewUI 借 KanpanCore 的价格 / 时间格式化（审查 B-07 / B-08）：复盘本里的价和
  // 时刻必须和顶栏、K 线轴、选区标签同一口径，各自现造 formatter 就会写成三种样子。
  // ReviewData 认 KanpanAccount 只为一件事：app 里复盘走的是账号那条带 token 的通道，
  // 失败抛的是 `AccountError`，队列要按它的状态码决定「留着重发 / 摘出来裁决」
  // （`AccountError: ReviewFailureStatus`，见 ScorebookClient.swift）。KanpanAccount 是
  // 零依赖的叶子包，不会把别的东西带进来。
  dependencies: [.package(path: "../KanpanCore"), .package(path: "../KanpanAccount")],
  targets: [.target(name: "ReviewDomain", dependencies: [.product(name: "KanpanCore", package: "KanpanCore")], swiftSettings: strict),
    .target(name: "ReviewData", dependencies: ["ReviewDomain", .product(name: "KanpanAccount", package: "KanpanAccount")], swiftSettings: strict),
    .target(name: "ReviewUI", dependencies: ["ReviewDomain", "ReviewData",
                                             .product(name: "KanpanCore", package: "KanpanCore")], swiftSettings: strict),
    // 三个测试目标分三层，和报告 B.5 的客户端那张表一一对上：
    // 领域（契约与回放算术）、存档（事务与淘汰）、模型（同步队列与列表口径）。
    // `ReviewUITests` 要 iOS 运行时：ReviewUI 里有 `.keyboardType` 这类只在 UIKit 平台
    // 存在的修饰符，macOS 上编不过，所以整包跑法是
    // `xcodebuild test -scheme KanpanReview -destination 'platform=iOS Simulator,…'`。
    .testTarget(name: "ReviewDomainTests", dependencies: ["ReviewDomain", "ReviewData"], swiftSettings: strict),
    .testTarget(name: "ReviewDataTests", dependencies: ["ReviewDomain", "ReviewData"], swiftSettings: strict),
    .testTarget(name: "ReviewUITests", dependencies: ["ReviewDomain", "ReviewData", "ReviewUI",
                                                      .product(name: "KanpanAccount", package: "KanpanAccount")], swiftSettings: strict)])
