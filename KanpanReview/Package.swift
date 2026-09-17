// swift-tools-version: 6.2
import PackageDescription
let package = Package(name: "KanpanReview", platforms: [.iOS(.v18)],
  products: [.library(name: "KanpanReview", targets: ["ReviewDomain", "ReviewData", "ReviewUI"])],
  targets: [.target(name: "ReviewDomain"), .target(name: "ReviewData", dependencies: ["ReviewDomain"]),
    .target(name: "ReviewUI", dependencies: ["ReviewDomain", "ReviewData"]),
    .testTarget(name: "ReviewDomainTests", dependencies: ["ReviewDomain", "ReviewData"])])
