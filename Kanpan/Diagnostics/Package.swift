// swift-tools-version: 6.0
import PackageDescription

// 诊断层（M9）的**测试壳**。
//
// app 工程（Kanpan/Kanpan.xcodeproj）用 file-system synchronized group，
// 诊断层的真身放在 `Kanpan/Kanpan/Diagnostics/`，扔进去就自动进 app target。
// 那个工程没有 test target，加一个要改 `project.pbxproj`——那是接线的人的活。
//
// 所以照 `Kanpan/Symbols` / `Kanpan/Settings` 的老规矩再开一个 SwiftPM 包：
// `Sources/KanpanDiagnostics/` 下全是**指向真身的符号链接**，一份代码两处编，
// 不存在抄一份再走样。
//
// 零依赖是故意的：诊断层不认识 K 线、不认识指标，它只认 JSON 和时间戳。
// 这样它在 mac 上 `swift test` 里全速跑，不用拉起模拟器。
//
// 两块能测、一块测不了：
//   - MetricKit 摘要（`MeasurementText` / `PayloadDigest`）：喂手写 JSON，全测。
//   - 落盘与淘汰（`DiagnosticsStore` / `FrameReportStore`）：临时目录，全测。
//   - `FrameProbe` 的 CADisplayLink + runloop 观察者：整份 `#if os(iOS)`，
//     mac 上编出来是空文件。它的证据只能在模拟器 / 真机上跑出来，见
//     docs/acceptance/M9.md。
//
// 跑：cd Kanpan/Diagnostics && swift test

let package = Package(
  name: "KanpanDiagnostics",
  platforms: [.iOS(.v17), .macOS(.v14)],
  products: [
    .library(name: "KanpanDiagnostics", targets: ["KanpanDiagnostics"]),
  ],
  targets: [
    .target(
      name: "KanpanDiagnostics",
      path: "Sources/KanpanDiagnostics"
    ),
    .testTarget(
      name: "KanpanDiagnosticsTests",
      dependencies: ["KanpanDiagnostics"],
      path: "Tests/KanpanDiagnosticsTests"
    ),
  ]
)
