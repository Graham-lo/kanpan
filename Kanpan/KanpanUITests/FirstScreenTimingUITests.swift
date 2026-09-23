import Foundation
import XCTest

/// 冷启动首屏计时：全新测试档案、指定线路，从 `app.launch()` 到
/// ①主图第一批 K 线可画（`chart.canvas` 报 ≥ 100 根）②推送 live（`market.source` 的值）。
///
/// 改线路 / 取数层之前后各跑一遍对比（「网络改动不许倒退」）。线路与轮数从测试进程的环境变量取，
/// xcodebuild 前加 `TEST_RUNNER_` 前缀传入：
///
///     TEST_RUNNER_FIRST_SCREEN_ROUTE=gateway TEST_RUNNER_FIRST_SCREEN_ROUNDS=5 \
///       scripts/machine-guard.sh run xcodebuild test … -only-testing:KanpanUITests/FirstScreenTimingUITests
///
/// 每轮一行 `FIRST_SCREEN route=… round=… chart=…ms live=…ms source=…`，最后一行给中位数。
@MainActor final class FirstScreenTimingUITests: XCTestCase {
  func testColdStartFirstScreen() throws {
    continueAfterFailure = true
    let env = ProcessInfo.processInfo.environment
    let route = env["FIRST_SCREEN_ROUTE"] ?? "direct"
    let rounds = max(1, Int(env["FIRST_SCREEN_ROUNDS"] ?? "") ?? 3)
    var charts: [Double] = []
    var lives: [Double] = []
    for round in 1...rounds {
      let app = XCUIApplication()
      app.launchEnvironment["KANPAN_TEST_PROFILE"] = "1"
      app.launchEnvironment["KANPAN_PERSISTENCE_PROFILE"] = UUID().uuidString
      app.launchEnvironment["KANPAN_TEST_DEEPLINK"] = "hkline://symbol/BTCUSDT?interval=1h"
      app.launchEnvironment["KANPAN_CHART_DIAGNOSTICS"] = "1"
      app.launchEnvironment["KANPAN_TEST_ROUTE_POLICY"] = route
      let canvas = app.otherElements["chart.canvas"]
      let source = app.staticTexts["market.source"]
      func bars() -> Int {
        guard canvas.exists, let raw = canvas.value as? String, let bytes = raw.data(using: .utf8),
              let value = try? JSONSerialization.jsonObject(with: bytes) as? [String: Any],
              value["interval"] as? String == "1h" else { return 0 }
        return value["bars"] as? Int ?? 0
      }
      let started = Date()
      app.launch()
      var chartAt: Double?
      var liveAt: Double?
      let deadline = Date().addingTimeInterval(60)
      while Date() < deadline, chartAt == nil || liveAt == nil {
        if chartAt == nil, bars() >= 100 { chartAt = Date().timeIntervalSince(started) }
        if liveAt == nil, source.exists, (source.value as? String) == "live" { liveAt = Date().timeIntervalSince(started) }
        if chartAt == nil || liveAt == nil { Thread.sleep(forTimeInterval: 0.05) }
      }
      let label = source.exists ? source.label : "?"
      let ms = { (v: Double?) in v.map { String(Int(($0 * 1000).rounded())) } ?? "—" }
      print("FIRST_SCREEN route=\(route) round=\(round) chart=\(ms(chartAt))ms live=\(ms(liveAt))ms source=\(label)")
      XCTAssertNotNil(chartAt, "第 \(round) 轮 60s 内没等到主图 K 线")
      if let chartAt { charts.append(chartAt) }
      if let liveAt { lives.append(liveAt) }
      app.terminate()
    }
    func median(_ xs: [Double]) -> String {
      guard !xs.isEmpty else { return "—" }
      let s = xs.sorted()
      let m = s.count % 2 == 1 ? s[s.count / 2] : (s[s.count / 2 - 1] + s[s.count / 2]) / 2
      return String(Int((m * 1000).rounded()))
    }
    let summary = "FIRST_SCREEN_MEDIAN route=\(route) rounds=\(rounds) chart=\(median(charts))ms live=\(median(lives))ms"
    print(summary)
    let text = XCTAttachment(string: summary); text.lifetime = .keepAlways; add(text)
  }
}
