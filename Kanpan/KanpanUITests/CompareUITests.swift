import Foundation
import XCTest
import UIKit

@MainActor final class CompareUITests: XCTestCase {
  var app: XCUIApplication!
  let keys = ["binance/usd_m/ETHUSDT", "binance/usd_m/SOLUSDT", "binance/usd_m/DOGEUSDT"]
  var canvas: XCUIElement { app.otherElements["chart.canvas"] }

  override func setUp() {
    continueAfterFailure = false
    XCUIDevice.shared.orientation = .portrait
    app = XCUIApplication()
    app.launchEnvironment["KANPAN_TEST_PROFILE"] = "1"
    app.launchEnvironment["KANPAN_PERSISTENCE_PROFILE"] = UUID().uuidString
    app.launchEnvironment["KANPAN_CHART_DIAGNOSTICS"] = "1"
    app.launchEnvironment["KANPAN_TEST_DEEPLINK"] = "hkline://symbol/BTCUSDT?interval=1m"
  }
  override func tearDown() async throws {
    guard let app else { return }
    if app.state == .runningForeground {
      if (testRun?.failureCount ?? 0) > 0 {
        let a = XCTAttachment(string: app.debugDescription + "\n" + String(describing: info()))
        a.lifetime = .keepAlways; add(a); shot("失败现场")
      }
      app.terminate()
    }
    XCUIDevice.shared.orientation = .portrait
  }
  func info() -> [String: Any] {
    guard canvas.exists, let text = canvas.value as? String, let bytes = text.data(using: .utf8),
          let value = try? JSONSerialization.jsonObject(with: bytes) as? [String: Any] else { return [:] }
    return value
  }
  func wait(_ seconds: Double = 60, _ condition: @escaping () -> Bool) -> Bool {
    XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in condition() }, object: nil)], timeout: seconds) == .completed
  }
  func ready(_ count: Int, interval: String = "1m") {
    XCTAssertTrue(wait(90) {
      let d = self.info()
      return d["interval"] as? String == interval && (d["bars"] as? Int ?? 0) >= 100
        && (d["compareReady"] as? Int ?? 0) == count
    }, "对比未到齐：\(info())")
  }
  func shot(_ name: String) {
    let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
    attachment.name = name; attachment.lifetime = .keepAlways; add(attachment)
    let state = XCTAttachment(string: String(describing: info()))
    state.name = name + "-读数"; state.lifetime = .keepAlways; add(state)
  }
  func panel() {
    let button = app.buttons["interval.chart"]
    XCTAssertTrue(button.waitForExistence(timeout: 10)); button.tap()
    XCTAssertTrue(app.descendants(matching: .any)["compare.add"].firstMatch.waitForExistence(timeout: 10))
  }
  func closePanel() {
    let done = app.buttons["panel.done"]
    XCTAssertTrue(done.waitForExistence(timeout: 5)); done.tap()
    XCTAssertTrue(wait(10) { !done.exists })
  }
  func addCompare(_ symbol: String) {
    panel()
    app.descendants(matching: .any)["compare.add"].firstMatch.tap()
    let query = app.textFields["symbols.query"]
    XCTAssertTrue(query.waitForExistence(timeout: 10)); query.tap(); query.typeText(symbol)
    let row = app.buttons["symbols.row." + testInstrumentKey(symbol)]
    XCTAssertTrue(row.waitForExistence(timeout: 20)); row.tap()
    XCTAssertTrue(wait(10) { !query.exists })
  }

  func testPanelCollectionPersistsAndClears() {
    app.launch(); ready(0)
    addCompare("ETHUSDT"); ready(1)
    addCompare("ETHUSDT"); ready(1)
    addCompare("BTCUSDT"); ready(1)
    addCompare("SOLUSDT"); ready(2)
    addCompare("DOGEUSDT"); ready(3)
    XCTAssertEqual(info()["compareKeys"] as? [String], keys)
    panel()
    XCTAssertFalse(app.descendants(matching: .any)["compare.add"].firstMatch.isEnabled)
    shot("对比-三项面板"); closePanel()
    app.terminate(); app.launch(); ready(3)
    XCTAssertEqual(info()["compareKeys"] as? [String], keys)
    panel(); app.buttons["compare.remove." + keys[2]].tap(); ready(2)
    panel(); app.descendants(matching: .any)["compare.clear"].firstMatch.tap(); ready(0)
    XCTAssertEqual(info()["percentAxis"] as? Bool, false)
    app.terminate(); app.launch(); ready(0)
  }
  func assertPercentReadout() throws {
    let d = info()
    let base = try XCTUnwrap(d["compareBaseOpen"] as? Double)
    let close = try XCTUnwrap(d["compareMainClose"] as? Double)
    let expected = (close / base - 1) * 100
    let label = abs(expected) < 0.005 ? "0%" : String(format: "%+.2f%%", expected)
    let legend = try XCTUnwrap(d["compareLegend"] as? [[String: String]])
    XCTAssertEqual(legend.first?["label"], label)
    if d["crosshair"] as? Bool == true {
      XCTAssertEqual(d["crossAxisLabel"] as? String, label)
    }
    let ticks = try XCTUnwrap(d["compareTicks"] as? [Double])
    XCTAssertTrue(ticks.contains(0))
  }

  func testIntervalsCrosshairPanLandscapeAndReview() throws {
    app.launchEnvironment["KANPAN_TEST_COMPARE_SYMBOLS"] = keys.joined(separator: ",")
    app.launch(); ready(3)
    XCTAssertFalse(app.buttons["bottom.draw"].isEnabled)
    XCTAssertEqual(info()["overlays"] as? [String], [])
    XCTAssertEqual(info()["drawingsVisible"] as? Bool, false)
    shot("BTC-ETH-SOL-DOGE-1m")
    try assertPercentReadout()

    // 用产品已有的「收盘价」档验证十字线、图例与右轴同口径。
    panel()
    // 面板上有两个「收盘价」（K 线画法、十字线读数），这里要的是十字线那一档。
    // 只滚面板自己的列表：页面上还有别的滚动区，`scrollViews.firstMatch` 可能落在
    // 别处，划了也滚不到面板里。用手指拖而不是 swipe，免得面板被撑满屏。
    let closeMode = app.buttons["chart.crossPrice.收盘价"]
    let content = app.scrollViews["panel.content"]
    XCTAssertTrue(content.waitForExistence(timeout: 5))
    for _ in 0..<12 {
      if closeMode.exists && closeMode.isHittable && content.frame.contains(closeMode.frame) { break }
      let up = !closeMode.exists || closeMode.frame.midY > content.frame.midY
      content.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: up ? 0.7 : 0.3))
        .press(forDuration: 0.1, thenDragTo: content.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: up ? 0.3 : 0.7)))
    }
    XCTAssertTrue(closeMode.isHittable); closeMode.tap(); closePanel()
    let h = try XCTUnwrap(info()["mainH"] as? Double)
    let point = canvas.coordinate(withNormalizedOffset: .zero).withOffset(CGVector(dx: 170, dy: h * 0.55))
    point.press(forDuration: 0.8)
    XCTAssertTrue(wait(10) { self.info()["crosshair"] as? Bool == true })
    try assertPercentReadout(); shot("对比-十字线")
    point.tap()
    XCTAssertTrue(wait(10) { self.info()["crosshair"] as? Bool == false })
    let before = try XCTUnwrap(info()["compareBaseTime"] as? Double)
    let start = canvas.coordinate(withNormalizedOffset: .zero).withOffset(CGVector(dx: 110, dy: h * 0.55))
    let end = canvas.coordinate(withNormalizedOffset: .zero).withOffset(CGVector(dx: 280, dy: h * 0.55))
    start.press(forDuration: 0.05, thenDragTo: end, withVelocity: .slow, thenHoldForDuration: 0.1)
    XCTAssertTrue(wait(10) { (self.info()["compareBaseTime"] as? Double) != before })
    try assertPercentReadout(); shot("对比-平移重定基点")

    app.buttons["interval.chip.1h"].tap(); ready(3, interval: "1h")
    try assertPercentReadout(); shot("BTC-ETH-SOL-DOGE-1h")
    app.buttons["interval.more"].tap()
    let day = app.buttons["period.row.1d"]
    XCTAssertTrue(day.waitForExistence(timeout: 10)); day.tap()
    ready(3, interval: "1d"); try assertPercentReadout(); shot("BTC-ETH-SOL-DOGE-1d")

    XCUIDevice.shared.orientation = .landscapeLeft
    XCTAssertTrue(wait(15) { self.info()["percentAxis"] as? Bool == false })
    shot("对比-横屏暂退")
    XCUIDevice.shared.orientation = .portrait
    ready(3, interval: "1d")
    shot("对比-竖屏恢复")
    panel(); app.buttons["chart.record"].tap()
    let dismiss = app.buttons["收起"]
    XCTAssertTrue(dismiss.waitForExistence(timeout: 10))
    XCTAssertEqual(info()["percentAxis"] as? Bool, false)
    XCTAssertEqual(info()["compareKeys"] as? [String], [])
    shot("复盘-不含对比")
    dismiss.tap(); ready(3, interval: "1d")
  }

  func testSyncRestoresCollectionIntoFreshInstallationProfile() {
    let name = "compare_" + UUID().uuidString.replacingOccurrences(of: "-", with: "").prefix(12).lowercased()
    let password = "Cmp_" + UUID().uuidString.prefix(8) + "9x"
    app.launchEnvironment["KANPAN_ACCOUNT_API_URL"] = "https://kanpan.107-174-172-10.sslip.io"
    app.launch(); ready(0)
    addCompare("ETHUSDT"); addCompare("SOLUSDT"); addCompare("DOGEUSDT"); ready(3)
    func openAccount() {
      app.buttons["bottom.settings"].tap()
      let row = app.buttons["settings.account"]
      XCTAssertTrue(row.waitForExistence(timeout: 15)); row.tap()
      XCTAssertTrue(app.otherElements["account.view"].waitForExistence(timeout: 15))
    }
    func credentials() {
      let user = app.textFields["account.email"]
      XCTAssertTrue(user.waitForExistence(timeout: 10)); user.tap(); user.typeText(name)
      let secure = app.secureTextFields["account.password"]
      secure.tap()
      if app.buttons["GenerateStrongPasswordButton"].waitForExistence(timeout: 2) { app.buttons["xmark"].tap() }
      // XCTest 的 typeText 活动可能记录输入；密码只经本机临时粘贴板传入并立即清空。
      UIPasteboard.general.setItems([["public.utf8-plain-text": password]], options: [.localOnly: true, .expirationDate: Date().addingTimeInterval(30)])
      defer { UIPasteboard.general.items = [] }
      secure.press(forDuration: 1.1)
      let paste = [app.menuItems["粘贴"], app.menuItems["Paste"], app.buttons["粘贴"], app.buttons["Paste"]]
      XCTAssertTrue(wait(10) { paste.contains { $0.exists && $0.isHittable } })
      paste.first { $0.exists && $0.isHittable }!.tap()
      UIPasteboard.general.items = []
      app.buttons["account.submit"].tap()
      XCTAssertTrue(wait(60) { !self.app.otherElements["account.view"].exists })
    }
    openAccount(); app.buttons["注册"].tap(); credentials()
    // 产品的立即同步入口，待同步消失后才切到全新的本地档案。
    // 注册成功后账号页收起、回到原页面，要从设置页重新进账号。
    openAccount()
    let sync = app.buttons["同步"]
    XCTAssertTrue(sync.waitForExistence(timeout: 20)); sync.tap()
    let now = app.buttons["立即同步"]
    XCTAssertTrue(now.waitForExistence(timeout: 20)); now.tap()
    XCTAssertTrue(wait(180) { self.app.staticTexts["已同步"].exists })
    app.terminate()
    app.launchEnvironment["KANPAN_PERSISTENCE_PROFILE"] = UUID().uuidString
    app.launch(); ready(0)
    openAccount(); credentials()
    app.buttons["bottom.chart"].coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
    ready(3)
    XCTAssertEqual(info()["compareKeys"] as? [String], keys)
    shot("对比-新安装档案登录恢复")
    print("COMPARE_SYNC new profile restored three comparison keys; fixture account retained")
    // 验收只新增隔离账号，不删除任何线上账号或数据。
  }

  func testScanningKeepsCollectionAndIgnoresTheMainInstrument() {
    app.launchEnvironment["KANPAN_TEST_COMPARE_SYMBOLS"] = keys.joined(separator: ",")
    app.launchEnvironment["KANPAN_TEST_FAVORITES"] = ["BTCUSDT", "ETHUSDT", "SOLUSDT"].map(testInstrumentKey).joined(separator: ",")
    app.launch(); ready(3)
    let originalColors = info()["compareColors"] as? [String]
    app.buttons["bottom.favorites"].tap()
    let row = app.buttons["favorites.open." + testInstrumentKey("BTCUSDT")]
    XCTAssertTrue(row.waitForExistence(timeout: 15)); row.tap(); ready(3)
    let quote = app.descendants(matching: .any).matching(identifier: "market.quote").firstMatch
    XCTAssertTrue(quote.waitForExistence(timeout: 10))
    func swipe(_ next: Bool) {
      quote.coordinate(withNormalizedOffset: CGVector(dx: next ? 0.85 : 0.15, dy: 0.5))
        .press(forDuration: 0.05, thenDragTo: quote.coordinate(withNormalizedOffset: CGVector(dx: next ? 0.1 : 0.9, dy: 0.5)))
    }
    swipe(true)
    XCTAssertTrue(wait(30) { self.info()["symbol"] as? String == self.keys[0] })
    ready(2)
    XCTAssertEqual(info()["compareKeys"] as? [String], Array(keys.dropFirst()))
    XCTAssertEqual(info()["compareColors"] as? [String], originalColors.map { Array($0.dropFirst()) })
    panel()
    // ETH 只是这张图临时忽略；持久集合仍有它，移除入口仍在。
    XCTAssertTrue(app.buttons["compare.remove." + keys[0]].exists); closePanel()
    shot("对比-扫到ETH忽略自身")
    swipe(false)
    XCTAssertTrue(wait(30) { self.info()["symbol"] as? String == testInstrumentKey("BTCUSDT") })
    ready(3)
    XCTAssertEqual(info()["compareKeys"] as? [String], keys)
    shot("对比-扫回BTC集合保留")
  }

}
