import Foundation
import XCTest

/// 同一台模拟器、全新测试缓存：启动到首批主图数据以及三条对比数据可画。
@MainActor final class ComparePerformanceUITests: XCTestCase {
  func testColdStartOneMinute() throws {
    continueAfterFailure = false
    let app = XCUIApplication()
    app.launchEnvironment["KANPAN_TEST_PROFILE"] = "1"
    app.launchEnvironment["KANPAN_PERSISTENCE_PROFILE"] = UUID().uuidString
    app.launchEnvironment["KANPAN_TEST_DEEPLINK"] = "hkline://symbol/BTCUSDT?interval=1m"
    app.launchEnvironment["KANPAN_CHART_DIAGNOSTICS"] = "1"
    app.launchEnvironment["KANPAN_TEST_COMPARE_SYMBOLS"] = "binance/usd_m/ETHUSDT,binance/usd_m/SOLUSDT,binance/usd_m/DOGEUSDT"
    let started = Date()
    app.launch()
    let canvas = app.otherElements["chart.canvas"]
    var data: [String: Any] = [:]
    func read() -> [String: Any] {
      guard canvas.exists, let raw = canvas.value as? String, let bytes = raw.data(using: .utf8),
            let value = try? JSONSerialization.jsonObject(with: bytes) as? [String: Any] else { return [:] }
      return value
    }
    let mainReady = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
      data = read()
      return data["interval"] as? String == "1m" && (data["bars"] as? Int ?? 0) >= 100
    }, object: nil)
    XCTAssertEqual(XCTWaiter.wait(for: [mainReady], timeout: 90), .completed)
    let first = Date().timeIntervalSince(started)
    var all: Double?
    // 第一阶段没有接数据，此时记录无对比的基线；接线后同一入口必须等到三条都可画。
    if data["percentAxis"] as? Bool == true {
      let comparisons = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
        data = read(); return data["compareReady"] as? Int == 3
      }, object: nil)
      XCTAssertEqual(XCTWaiter.wait(for: [comparisons], timeout: 90), .completed)
      all = Date().timeIntervalSince(started)
    }
    let report = "COMPARE_COLD main=\(first) all=\(all.map(String.init(describing:)) ?? "baseline") interval=\(data["interval"] ?? "") bars=\(data["bars"] ?? 0)"
    print(report)
    let text = XCTAttachment(string: report); text.lifetime = .keepAlways; add(text)
    let shot = XCTAttachment(screenshot: XCUIScreen.main.screenshot()); shot.name = "对比-冷启动"; shot.lifetime = .keepAlways; add(shot)
    app.terminate()
  }
}
