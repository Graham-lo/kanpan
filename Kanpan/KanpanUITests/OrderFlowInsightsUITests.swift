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
}
