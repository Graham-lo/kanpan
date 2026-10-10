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

  /// 横拖不开；上滑开半页；点行情头收起。
  func testUpwardEntryOpensAndHorizontalEntryDoesNot() {
    let entry = el("highlights.entry")
    expectExists(entry, Self.long)
    let start = entry.coordinate(withNormalizedOffset: CGVector(dx: 0.3, dy: 0.5))
    start.press(forDuration: 0.05, thenDragTo: start.withOffset(CGVector(dx: 120, dy: -10)))
    XCTAssertFalse(el("highlights.sheet").exists)
    let up = entry.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
    up.press(forDuration: 0.05, thenDragTo: up.withOffset(CGVector(dx: 0, dy: -90)))
    expectExists(el("highlights.sheet"), Self.short)
    // 半页顶在行情头下沿：头部还露着，点它收起。
    app.coordinate(withNormalizedOffset: CGVector(dx: 0.3, dy: 0.12)).tap()
    expectGone(el("highlights.sheet"), Self.short)
  }
}
