// swift-tools-version: 6.2
import PackageDescription

// 行情网络层：怎么连到交易所。
//
// 这一包只回答「请求从哪条路出去」：HTTP / WebSocket 的最小接口、币安 REST / WS 客户端
// 与限流、行情线路（直连 / 网关）、网关竞速与冷却、网关信封解析。它不认识 K 线怎么存、
// 怎么喂图——那些在 `KanpanData`。网络这块单独成包，改线路逻辑时只碰这里，
// 数据层与 app 只拿它的公开接口。
//
// `KanpanNetworkTestSupport` 是给单测用的假件（假 server、假 socket、阶梯时钟），
// `KanpanData` 的测试也用同一份，所以做成产品而不是藏在测试目录里。
let package = Package(
  name: "KanpanNetwork",
  platforms: [.iOS(.v26), .macOS(.v14)],
  products: [
    .library(name: "KanpanNetwork", targets: ["KanpanNetwork"]),
    .library(name: "KanpanNetworkTestSupport", targets: ["KanpanNetworkTestSupport"]),
  ],
  dependencies: [
    .package(path: "../KanpanCore"),
  ],
  targets: [
    .target(
      name: "KanpanNetwork",
      dependencies: [.product(name: "KanpanCore", package: "KanpanCore")],
      path: "Sources/KanpanNetwork"
    ),
    .target(
      name: "KanpanNetworkTestSupport",
      dependencies: ["KanpanNetwork"],
      path: "Sources/KanpanNetworkTestSupport"
    ),
    .testTarget(
      name: "KanpanNetworkTests",
      dependencies: ["KanpanNetwork", "KanpanNetworkTestSupport", .product(name: "KanpanCore", package: "KanpanCore")],
      path: "Tests/KanpanNetworkTests"
    ),
  ]
)
