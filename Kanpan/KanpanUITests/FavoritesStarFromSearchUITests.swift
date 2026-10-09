import XCTest

/// 停在哪一类，从搜索加星的品种就进哪一类（用户 2026-09-20 定的），收起搜索页仍停在那一类。
///
/// 深度审查 G 线走查：「自选页停在哪一类」的读法（`SymbolPickerModel.selectedGroupSource`）
/// 原来接在账号桥的 init 里，桥没建起来时（测试档案这条岔路、正式包里存储目录不可写落进
/// catch）一直是 nil——停在「美股」搜 ADA 加星，ADA 落进第一类「加密」，自选页还跟着
/// 跳到「加密」。这条用例走的正是没有账号桥的那条路。
@MainActor
final class FavoritesStarFromSearchUITests: KanpanUICase {
  override var extraLaunchEnvironment: [String: String] {
    ["KANPAN_PERSISTENCE_PROFILE": UUID().uuidString,
     "KANPAN_TEST_FAVORITES": "BTCUSDT,ETHUSDT,NVDAUSDT,XAUUSDT"]
  }

  func testStarFromSearchLandsInTheGroupYouAreOn() throws {
    XCTAssertTrue(app.openFavorites(), "进不了自选页")
    let btc = app.buttons["favorites.open." + testInstrumentKey("BTCUSDT")]
    XCTAssertTrue(btc.staticTexts["BTCUSDT"].waitForExistence(timeout: Self.short), "自选应连写品种与计价币")
    XCTAssertFalse(btc.staticTexts["币安"].exists, "自选不再展示交易所缩写")
    let attachment = XCTAttachment(screenshot: app.screenshot())
    attachment.name = "自选-品种计价币连写"
    attachment.lifetime = .keepAlways
    add(attachment)
    let chips = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "favorites.group."))
    func selectedChip() -> String { chips.allElementsBoundByIndex.filter(\.isSelected).map(\.identifier).joined(separator: ",") }
    let us = app.buttons["favorites.group.美股"]
    XCTAssertTrue(us.waitForExistence(timeout: Self.long), "分类条上没有「美股」：\(chips.allElementsBoundByIndex.map(\.identifier))")
    // 「美股」不是第一类——落进第一类的老毛病才看得出来。
    XCTAssertNotEqual(chips.firstMatch.identifier, "favorites.group.美股")
    us.tap()
    XCTAssertTrue(waitUntil(timeout: Self.short) { selectedChip() == "favorites.group.美股" })

    app.buttons["favorites.add"].tap()
    let query = app.textFields[Ids.searchQuery]
    XCTAssertTrue(query.waitForExistence(timeout: Self.short))
    query.tap(); query.typeText("ADA")
    let star = app.descendants(matching: .any)
      .matching(NSPredicate(format: "identifier == %@", "symbols.star." + testInstrumentKey("ADAUSDT"))).firstMatch
    XCTAssertTrue(star.waitForExistence(timeout: Self.long), "搜索结果里没有 ADA 的星")
    XCTAssertTrue(app.staticTexts["ADAUSDT"].exists, "搜索行应连写品种与计价币")
    XCTAssertFalse(app.staticTexts["ADAUSDT 永续"].exists, "搜索行不再重复永续信息")
    star.tap()
    app.buttons["search.cancel"].tap()

    let ada = app.buttons["favorites.open." + testInstrumentKey("ADAUSDT")]
    XCTAssertTrue(ada.waitForExistence(timeout: Self.short), "收起搜索页后眼前这一类里没有刚加的 ADA")
    XCTAssertEqual(selectedChip(), "favorites.group.美股", "加星之后自选页不该跳去别的分类")
    // 别的类里没有它：切到第一类看一眼。
    chips.firstMatch.tap()
    XCTAssertTrue(waitUntil(timeout: Self.short) { !ada.exists }, "ADA 同时出现在第一类里")
  }
}
