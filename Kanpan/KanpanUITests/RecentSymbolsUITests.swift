import XCTest

// M5 A5.9：「最近看过」按时间倒序、最多 10 个。
//
// 走用户那条路：顶栏放大镜 → 打代号 → 点那一行，连开 12 只；再打开搜索页，
// 「最近看过」里应当正好是后开的 10 只、最后开的在最上面，最早开的两只（连同启动时的
// BTCUSDT）被挤掉。上限在 `SymbolPrefs.recentLimit`；搜索页原来另截到 8 个，已改成按上限摆。
@MainActor
final class RecentSymbolsUITests: KanpanUICase {

  private let opened = ["ETHUSDT", "SOLUSDT", "XRPUSDT", "DOGEUSDT", "ADAUSDT", "LINKUSDT",
                        "AVAXUSDT", "LTCUSDT", "DOTUSDT", "BNBUSDT", "SUIUSDT", "TRXUSDT"]

  private func row(_ symbol: String) -> XCUIElement {
    app.descendants(matching: .any).matching(identifier: "symbols.row." + testInstrumentKey(symbol)).firstMatch
  }

  func testRecentsAreNewestFirstAndKeepTen() throws {
    for symbol in opened {
      XCTAssertTrue(app.openSymbolSearch(), "顶栏放大镜没开出搜索页")
      let query = app.textFields[Ids.searchQuery]
      query.tap()
      query.typeText(symbol)
      let hit = row(symbol)
      XCTAssertTrue(hit.waitForExistence(timeout: Self.long), "搜 \(symbol) 没出那一行")
      hit.tap()
      XCTAssertTrue(waitUntil(timeout: 45) { self.chartInfo()["symbol"] as? String == testInstrumentKey(symbol) },
                    "点了 \(symbol) 图上没换过去：\(chartInfo())")
    }

    XCTAssertTrue(app.openSymbolSearch(), "顶栏放大镜没开出搜索页")
    let expected = Array(opened.reversed().prefix(10))
    XCTAssertTrue(row(expected[0]).waitForExistence(timeout: Self.long), "搜索页上没有「最近看过」")
    shot("最近看过-上半")
    for i in 1..<expected.count {
      let next = row(expected[i])
      var drags = 0
      while !(next.exists && next.isHittable) && drags < 6 {
        app.windows.firstMatch.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.75))
          .press(forDuration: 0.05, thenDragTo: app.windows.firstMatch.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.55)))
        drags += 1
      }
      XCTAssertTrue(next.exists, "「最近看过」里第 \(i + 1) 个应当是 \(expected[i])，没找到")
      let previous = row(expected[i - 1])
      XCTAssertTrue(previous.exists && previous.frame.minY < next.frame.minY,
                    "\(expected[i - 1]) 应当排在 \(expected[i]) 上面（时间倒序）")
    }
    shot("最近看过-下半")
    for gone in Array(opened.prefix(2)) + ["BTCUSDT"] {
      XCTAssertFalse(row(gone).exists, "\(gone) 是第 11 个以后开的，应当已被挤出「最近看过」")
    }
  }

  private func shot(_ name: String) {
    let attachment = XCTAttachment(screenshot: app.screenshot())
    attachment.name = name
    attachment.lifetime = .keepAlways
    add(attachment)
  }
}
