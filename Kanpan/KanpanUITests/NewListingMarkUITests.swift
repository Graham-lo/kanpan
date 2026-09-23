import XCTest

// P2.15：上线 ≤30 天的品种，搜索结果与自选行的名字后面各有一枚「新」。
//
// 哪个品种算「新」每天都在变，所以不把代号写死：开跑前自己去币安拉一次品种表，
// 挑上线时间最近、正在交易的那一只。三十天里一只新品种都没有的话这条跳过，不算挂。
@MainActor
final class NewListingMarkUITests: KanpanUICase {

  /// 上线最晚、正在交易的那一只 USDT 永续（30 天内）。
  private static let newest: String? = {
    guard let url = URL(string: "https://fapi.binance.com/fapi/v1/exchangeInfo") else { return nil }
    var found: String?
    let done = DispatchSemaphore(value: 0)
    URLSession.shared.dataTask(with: url) { data, _, _ in
      defer { done.signal() }
      guard let data,
            let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let rows = root["symbols"] as? [[String: Any]] else { return }
      let now = Date().timeIntervalSince1970 * 1000
      let fresh = rows.compactMap { row -> (String, Double)? in
        guard row["status"] as? String == "TRADING", row["quoteAsset"] as? String == "USDT",
              row["contractType"] as? String == "PERPETUAL",
              let s = row["symbol"] as? String, let t = row["onboardDate"] as? Double,
              t <= now, now - t <= 29 * 86_400_000 else { return nil }
        return (s, t)
      }
      found = fresh.max { $0.1 < $1.1 }?.0
    }.resume()
    _ = done.wait(timeout: .now() + 20)
    return found
  }()

  override var extraLaunchEnvironment: [String: String] {
    ["KANPAN_TEST_FAVORITES": [Self.newest, "BTCUSDT"].compactMap { $0 }.joined(separator: ",")]
  }

  func testNewListingsCarryTheMarkInSearchAndFavorites() throws {
    let symbol = try XCTUnwrap(Self.newest, "近 30 天没有新上线的 USDT 永续，或者拉不到品种表")
    let base = String(symbol.dropLast(4))

    XCTAssertTrue(app.openSymbolSearch(), "顶栏放大镜没开出搜索页")
    let field = app.textFields[Ids.searchQuery]
    expectExists(field, Self.short, "搜索页上没有输入框")
    field.tap()
    field.typeText(base)
    let mark = app.descendants(matching: .any)["symbols.new." + testInstrumentKey(symbol)]
    expectExists(mark, Self.long, "搜 \(base) 的结果里 \(symbol) 后面没有「新」")
    XCTAssertEqual(mark.label, "新上线")
    field.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: base.count) + "BTC")
    expectExists(app.buttons["symbols.star." + testInstrumentKey("BTCUSDT")], Self.long, "搜 BTC 没出 BTCUSDT")
    XCTAssertFalse(app.descendants(matching: .any)["symbols.new." + testInstrumentKey("BTCUSDT")].exists,
                   "老品种 BTCUSDT 也挂上了「新」")
    field.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: 3) + base)
    expectExists(mark, Self.long, "删回去之后「新」没回来")
    shot("新-搜索结果")
    app.buttons["search.cancel"].tap()

    XCTAssertTrue(app.openFavorites(), "没进到自选页")
    expectExists(app.buttons["favorites.open." + testInstrumentKey(symbol)], Self.long, "预置的 \(symbol) 不在自选页上")
    expectExists(mark, Self.long, "自选行上 \(symbol) 后面没有「新」")
    XCTAssertFalse(app.descendants(matching: .any)["symbols.new." + testInstrumentKey("BTCUSDT")].exists)
    shot("新-自选行")
  }

  private func shot(_ name: String) {
    let attachment = XCTAttachment(screenshot: app.screenshot())
    attachment.name = name
    attachment.lifetime = .keepAlways
    add(attachment)
  }
}
