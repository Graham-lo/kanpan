import XCTest

/// 搜索页第一次打开不再是一整屏空白（审查 U7）：没历史搜索、没最近看过时，
/// 列按 24h 成交额排的前 10 个；看过一只之后「最近看过」出来，「热门」让位。
@MainActor
final class SearchHotUITests: KanpanUICase {
  private let profile = UUID().uuidString
  override var extraLaunchEnvironment: [String: String] { ["KANPAN_PERSISTENCE_PROFILE": profile] }

  private func save(_ name: String) {
    try? FileManager.default.createDirectory(atPath: "/tmp/kanpan-laneg-shots", withIntermediateDirectories: true)
    try? XCUIScreen.main.screenshot().pngRepresentation
      .write(to: URL(fileURLWithPath: "/tmp/kanpan-laneg-shots/\(name).png"))
  }

  private var rows: XCUIElementQuery {
    app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "symbols.row."))
  }

  func testFirstOpenShowsTopTenByVolume() throws {
    let entry = app.buttons["top.search"]
    XCTAssertTrue(entry.waitForExistence(timeout: Self.long), "顶栏没有放大镜")
    entry.tap()
    XCTAssertTrue(app.textFields[Ids.searchQuery].waitForExistence(timeout: Self.short), "搜索页没开")
    let hot = app.descendants(matching: .any)["search.hot"]
    XCTAssertTrue(hot.waitForExistence(timeout: Self.long), "第一次打开搜索页没有「热门」")
    XCTAssertTrue(waitUntil(timeout: Self.short) { self.rows.count == 10 }, "「热门」不是 10 行：\(rows.count)")
    XCTAssertFalse(app.staticTexts["最近看过"].exists)
    // 成交额头名稳定是比特币（与搜索结果、「全部合约」同一个排序口径）。
    XCTAssertEqual(rows.element(boundBy: 0).identifier, "symbols.row.binance/usd_m/BTCUSDT",
                   "「热门」第一行不是成交额最大的那只")
    save("U7-搜索页第一次打开-热门")

    // 点一只：人去了那张图；再开搜索页，「最近看过」出来，「热门」让位。
    let pick = rows.element(boundBy: 1)
    let picked = pick.identifier
    pick.tap()
    XCTAssertTrue(waitUntil(timeout: Self.short) { !self.app.textFields[Ids.searchQuery].exists }, "点了热门里的品种搜索页没收")
    entry.tap()
    XCTAssertTrue(app.textFields[Ids.searchQuery].waitForExistence(timeout: Self.short), "搜索页没再开")
    XCTAssertTrue(app.buttons[picked].waitForExistence(timeout: Self.short), "刚看过的那只不在「最近看过」里")
    XCTAssertFalse(hot.exists, "有了最近看过，「热门」还在")
  }
}
