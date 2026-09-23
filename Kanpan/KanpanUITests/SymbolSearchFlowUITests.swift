import XCTest

/// 搜索页 ⇄ 品种整页（审查 16.4）。行情页顶栏放大镜和自选页搜索框走同一个
/// `SymbolSearchFlow`：「查看全部」进整页，整页返回原路退回搜索页、词还在。
/// 两边各走一个来回，再走一次看换页没被吞掉。
final class SymbolSearchFlowUITests: KanpanUICase {
  override var extraLaunchEnvironment: [String: String] {
    ["KANPAN_TEST_FAVORITES": "BTCUSDT,ETHUSDT"]
  }

  func testChartSearchAllAndBackKeepsTheQuery() throws {
    XCTAssertTrue(app.openSymbolSearch(), "顶栏放大镜没开出搜索页")
    roundTrip(label: "行情页")
  }

  func testFavoritesSearchAllAndBackKeepsTheQuery() throws {
    app.buttons[Ids.bottomFavorites].tap()
    let entry = app.buttons["favorites.add"]
    XCTAssertTrue(entry.waitForExistence(timeout: 10), "自选页上没有搜索入口")
    entry.tap()
    XCTAssertTrue(app.textFields[Ids.searchQuery].waitForExistence(timeout: 8), "自选页搜索页没开")
    roundTrip(label: "自选页")
  }

  private func roundTrip(label: String) {
    let query = app.textFields[Ids.searchQuery]
    query.tap(); query.typeText("USD")
    for pass in 1...2 {
      let all = app.buttons[Ids.searchAll]
      XCTAssertTrue(all.waitForExistence(timeout: 10), "\(label)第 \(pass) 趟：搜「USD」没有「查看全部」")
      all.tap()
      XCTAssertTrue(app.textFields[Ids.symbolsQuery].waitForExistence(timeout: 10), "\(label)第 \(pass) 趟：「查看全部」没进到品种整页")
      if pass == 1 {
        try? app.screenshot().pngRepresentation
          .write(to: URL(fileURLWithPath: "/tmp/kanpan-laneg-shots/16.4-\(label)-品种整页.png"))
      }
      let back = app.buttons[Ids.symbolsBack]
      XCTAssertTrue(back.waitForExistence(timeout: 5), "品种整页没有返回")
      back.tap()
      XCTAssertTrue(query.waitForExistence(timeout: 10), "\(label)第 \(pass) 趟：整页返回没退回搜索页")
      XCTAssertEqual(query.value as? String, "USD", "\(label)第 \(pass) 趟：退回搜索页查询词没留着")
      if pass == 1 {
        try? app.screenshot().pngRepresentation
          .write(to: URL(fileURLWithPath: "/tmp/kanpan-laneg-shots/16.4-\(label)-退回搜索页.png"))
      }
    }
  }
}
