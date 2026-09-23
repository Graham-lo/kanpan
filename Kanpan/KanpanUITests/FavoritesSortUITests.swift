import XCTest

// ============================================================ 自选排序（审查 C3）
//
// 自选页排好的顺序从 2026-09-24 起按「名单 + 口径 + 升降序 + 报价版本」缓存，
// 不再每求值一次 body 就整表重排。缓存最怕的是该失效时没失效：换了口径、翻了方向，
// 表还停在上一种排法。这条用例把口径与方向各换一遍，看屏幕上的顺序真的跟着变。

@MainActor
final class FavoritesSortUITests: KanpanUICase {
  private let profile = UUID().uuidString
  /// 二十几只主流合约：一屏放不下，和真实用户的自选规模差不多。
  static let seed = ["ETHUSDT", "SOLUSDT", "BTCUSDT", "XRPUSDT", "DOGEUSDT", "ADAUSDT", "LINKUSDT", "AVAXUSDT",
                     "DOTUSDT", "LTCUSDT", "BCHUSDT", "TRXUSDT", "NEARUSDT", "APTUSDT", "ARBUSDT", "OPUSDT",
                     "SUIUSDT", "FILUSDT", "ATOMUSDT", "UNIUSDT", "AAVEUSDT", "INJUSDT", "TIAUSDT", "BNBUSDT"]
  override var extraLaunchEnvironment: [String: String] {
    ["KANPAN_PERSISTENCE_PROFILE": profile, "KANPAN_TEST_FAVORITES": Self.seed.joined(separator: ",")]
  }

  /// 屏幕上从上到下看得见的那几行（代号）。
  private func visibleOrder() -> [String] {
    let prefix = "favorites.open.binance/usd_m/"
    let rows = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", prefix)).allElementsBoundByIndex
    return rows.filter { $0.exists && $0.isHittable }
      .sorted { $0.frame.minY < $1.frame.minY }
      .map { String($0.identifier.dropFirst(prefix.count)) }
  }

  private func pick(_ title: String) {
    app.buttons["favorites.sort"].tap()
    let item = app.buttons[title].firstMatch
    XCTAssertTrue(item.waitForExistence(timeout: Self.short), "排序弹层里没有「\(title)」")
    item.tap()
    XCTAssertTrue(waitUntil(timeout: Self.short) { !item.exists || !item.isHittable }, "选完「\(title)」弹层没收")
  }

  func testSortModeAndDirectionReorderTheList() {
    XCTAssertTrue(app.openFavorites(), "自选页没开")
    let btc = app.staticTexts["favorites.price.binance/usd_m/BTCUSDT"]
    XCTAssertTrue(waitUntil(timeout: Self.long) { btc.exists && btc.label != "—" }, "自选报价没到")

    pick("品种")
    XCTAssertTrue(waitUntil(timeout: Self.short) {
      let rows = self.visibleOrder(); return rows.count >= 5 && rows == rows.sorted()
    }, "按「品种」升序后顺序不对：\(visibleOrder())")
    XCTAssertEqual(visibleOrder().first, "AAVEUSDT")

    pick("品种")   // 同一个键第二次：翻成降序
    XCTAssertTrue(waitUntil(timeout: Self.short) {
      let rows = self.visibleOrder(); return rows.count >= 5 && rows == rows.sorted(by: >)
    }, "再点一次「品种」没翻成降序：\(visibleOrder())")
    XCTAssertEqual(visibleOrder().first, "XRPUSDT")

    pick("成交额")
    XCTAssertTrue(waitUntil(timeout: Self.short) {
      let top = Array(self.visibleOrder().prefix(3)); return top.contains("BTCUSDT") && top.contains("ETHUSDT")
    }, "按「成交额」降序后 BTC / ETH 不在前三：\(visibleOrder())")
    // 报价继续在跳，顺序表在缓存命中之外照常刷新：价格还在动。
    var seen = Set<String>()
    XCTAssertTrue(waitUntil(timeout: Self.long, poll: 0.5) {
      if btc.exists { seen.insert(btc.label) }; return seen.count >= 2
    }, "排序之后报价不跳了")
    let shot = XCTAttachment(screenshot: app.screenshot()); shot.name = "自选-按成交额"; shot.lifetime = .keepAlways
    add(shot)
  }
}
