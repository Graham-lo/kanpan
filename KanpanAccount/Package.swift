// swift-tools-version: 6.2
import PackageDescription
let package = Package(name: "KanpanAccount", platforms: [.iOS(.v26), .macOS(.v14)],
  products: [.library(name: "KanpanAccount", targets: ["KanpanAccount"])],
  // 只借 KanpanCore 的 `ServerHosts`：放行名单和行情网关表是同一对主机，只留一份。
  dependencies: [.package(path: "../KanpanCore")],
  targets: [.target(name: "KanpanAccount", dependencies: [.product(name: "KanpanCore", package: "KanpanCore")]),
            .testTarget(name: "KanpanAccountTests", dependencies: ["KanpanAccount",
                                                                  .product(name: "KanpanCore", package: "KanpanCore")])])
