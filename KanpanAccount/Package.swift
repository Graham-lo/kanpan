// swift-tools-version: 6.2
import PackageDescription
let package = Package(name: "KanpanAccount", platforms: [.iOS(.v26), .macOS(.v14)],
  products: [.library(name: "KanpanAccount", targets: ["KanpanAccount"])],
  targets: [.target(name: "KanpanAccount"), .testTarget(name: "KanpanAccountTests", dependencies: ["KanpanAccount"])])
