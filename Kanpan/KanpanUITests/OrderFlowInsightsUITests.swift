import UIKit
import XCTest

@MainActor
final class OrderFlowInsightsUITests: KanpanUICase {
  override var extraLaunchEnvironment: [String: String] {
    ["KANPAN_TEST_INTERVAL": "1m", "KANPAN_PERSISTENCE_PROFILE": UUID().uuidString,
     "KANPAN_TEST_DEEPLINK": "hkline://symbol/BTCUSDT?interval=1m"]
  }
  private func el(_ id: String) -> XCUIElement { app.descendants(matching: .any)[id].firstMatch }
  private func waitEntry() {
    expectExists(el("insights.entry"), Self.long)
  }
  private func close() {
    app.buttons["bigtrade.back"].tap()
    expectGone(el("bigtrade.sheet"), Self.short)
  }
  func testEntryFullScreenScrollThresholdAndBack() {
    waitEntry()
    el("insights.entry").tap()
    expectExists(el("bigtrade.sheet"), Self.short)
    XCTAssertGreaterThan(el("bigtrade.sheet").frame.height, windowFrame.height * 0.88)
    expectExists(el("insights.walls"), Self.short)
    XCTAssertTrue(app.staticTexts["盘口洞察"].exists)
    shot("native-open")
    app.buttons["bigtrade.threshold"].tap()
    expectExists(app.buttons["orderflow.cancel"], Self.short)
    app.buttons["orderflow.cancel"].tap()
    expectExists(el("bigtrade.sheet"), Self.short)
    let scroll = el("insights.scroll")
    for _ in 0..<3 { scroll.swipeUp(velocity: .slow) }
    expectExists(el("insights.events"), Self.short)
    shot("native-scroll")
    close()
  }
  func testUpwardEntryOpensAndHorizontalEntryDoesNot() {
    waitEntry()
    let entry = el("insights.entry")
    let start = entry.coordinate(withNormalizedOffset: CGVector(dx: 0.3, dy: 0.5))
    start.press(forDuration: 0.05, thenDragTo: start.withOffset(CGVector(dx: 120, dy: -10)))
    XCTAssertFalse(el("bigtrade.sheet").exists)
    let up = entry.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.7))
    up.press(forDuration: 0.05, thenDragTo: up.withOffset(CGVector(dx: 0, dy: -90)))
    expectExists(el("bigtrade.sheet"), Self.short)
    close()
  }
  func testWallReturnsToActualPriceWithoutOrderCard() throws {
    waitEntry()
    el("insights.entry").tap()
    let wall = app.buttons["insights.wall.ask"]
    expectExists(wall, Self.long, "主图同所挂单未就绪，无法验证真实价位回图")
    let price = app.staticTexts["insights.wall.ask.price"].label
    let expected = try XCTUnwrap(Double(price.replacingOccurrences(of: ",", with: "")))
    wall.tap()
    expectGone(el("bigtrade.sheet"), Self.short)
    XCTAssertTrue(waitUntil(timeout: Self.short) { self.chartInfo()["crosshair"] as? Bool == true })
    XCTAssertTrue(waitUntil(timeout: Self.short) {
      let label = self.chartInfo()["crossAxisLabel"] as? String ?? ""
      return Double(label.replacingOccurrences(of: ",", with: "")).map { abs($0 - expected) <= 0.11 } ?? false
    }, "回图十字线没有落到实际挂单价")
    XCTAssertFalse(el("chart.orderFlowCard").exists)
    XCTAssertEqual(chartInfo()["orderFlowSelected"] as? String, "")
    shot("native-wall-location")
  }

  private func shot(_ name: String) {
    let image = app.screenshot()
    let a = XCTAttachment(screenshot: image); a.name = name; a.lifetime = .keepAlways; add(a)
    let url = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
      .appendingPathComponent("docs/acceptance/盘口洞察-2026-10-09", isDirectory: true)
    try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    try? image.pngRepresentation.write(to: url.appendingPathComponent("iOS-16Pro-\(name).png"))
  }
}
