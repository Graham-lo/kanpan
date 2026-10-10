import UIKit
import XCTest

/// 行情页「要点」入口条 → 「盘口要点」半页（PROJECT.md §79）。
@MainActor
final class HighlightsUITests: KanpanUICase {
  override var extraLaunchEnvironment: [String: String] {
    ["KANPAN_TEST_INTERVAL": "1m", "KANPAN_PERSISTENCE_PROFILE": UUID().uuidString,
     "KANPAN_TEST_DEEPLINK": "hkline://symbol/BTCUSDT?interval=1m"]
  }
  private func el(_ id: String) -> XCUIElement { app.descendants(matching: .any)[id].firstMatch }

  /// 要点在报价下方、周期条上方；仅点击打开，横拖和上滑都不开。
  func testTopEntryOpensOnlyOnTap() {
    let entry = el("highlights.entry")
    guard expectExists(entry, Self.long) else { return }
    XCTAssertTrue(waitUntil(timeout: Self.long) { entry.isHittable && entry.frame.height >= 43 })
    let quote = el("market.quote"), intervals = app.buttons[Ids.intervalMore]
    XCTAssertGreaterThanOrEqual(entry.frame.minY, quote.frame.maxY)
    XCTAssertLessThanOrEqual(entry.frame.maxY, intervals.frame.minY + 1)
    let start = entry.coordinate(withNormalizedOffset: CGVector(dx: 0.3, dy: 0.5))
    start.press(forDuration: 0.05, thenDragTo: start.withOffset(CGVector(dx: 120, dy: -10)))
    XCTAssertFalse(el("highlights.sheet").exists)
    let up = entry.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
    up.press(forDuration: 0.05, thenDragTo: up.withOffset(CGVector(dx: 0, dy: -90)))
    XCTAssertFalse(el("highlights.sheet").exists, "上滑不应打开要点")
    entry.tap()
    expectExists(el("highlights.sheet"), Self.short)
    // 半页顶在行情头下沿：头部还露着，点它收起。
    app.staticTexts["top.lastPrice"].tap()
    expectGone(el("highlights.sheet"), Self.short)
  }
  func testHomeFocusCanBeHiddenFromAnalysis() throws {
    executionTimeAllowance = 180
    XCTAssertTrue(app.openIndicatorPage())
    let walls = app.buttons["indicator.switch.ORDERFLOW"]
    if walls.value as? String != "开" { walls.tap() }
    dismissSheet(until: app.staticTexts[Ids.panelHeader].firstMatch)
    app.buttons["bottom.home"].tap()
    let row = app.descendants(matching: .any).matching(NSPredicate(format: "identifier BEGINSWITH %@", "home.row.book.")).firstMatch
    expectExists(row, 60, "首页没有盘口异动行")
    row.tap()
    let sheet = el("highlights.sheet")
    expectExists(sheet, Self.long)
    func assertSimplifiedCopy() {
      let text = sheet.staticTexts.allElementsBoundByIndex.map(\.label).joined(separator: " ")
      XCTAssertNil(text.range(of: "测\\s*\\d+\\s*次", options: .regularExpression))
      XCTAssertFalse(text.contains("距价"))
      XCTAssertFalse(text.contains("已破"))
    }
    assertSimplifiedCopy()
    let level = app.descendants(matching: .any).matching(NSPredicate(format: "identifier BEGINSWITH %@", "highlights.level.")).firstMatch
    if level.exists { level.tap(); assertSimplifiedCopy() }
    let simplified = XCTAttachment(screenshot: app.screenshot())
    simplified.name = "盘口要点精简文案"; simplified.lifetime = .keepAlways; add(simplified)
    app.coordinate(withNormalizedOffset: CGVector(dx: 0.3, dy: 0.12)).tap()
    expectGone(sheet, Self.short)
    let band = app.staticTexts["highlights.chartBand"]
    XCTAssertTrue(waitUntil(timeout: Self.short) { band.value as? String != "none" && band.exists })
    XCTAssertTrue(app.openIndicatorPage())
    XCTAssertEqual(walls.value as? String, "开")
    walls.tap()
    let signs = app.buttons["orderflow.bigTradeSigns"]
    if signs.value as? String == "开" { signs.tap() }
    dismissSheet(until: app.staticTexts[Ids.panelHeader].firstMatch)
    XCTAssertTrue(waitUntil(timeout: Self.short) { band.value as? String == "none" })
    XCTAssertTrue(waitUntil(timeout: Self.short) { (self.chartInfo()["orderFlowPhase"] as? String ?? "").isEmpty })
    let image = XCTAttachment(screenshot: app.screenshot())
    image.name = "首页进图关闭订单流标记"; image.lifetime = .keepAlways; add(image)
  }

}
