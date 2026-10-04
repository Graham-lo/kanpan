import XCTest

/// 深度审查 G 线走查：从搜索点进 1000PEPE / 1000SHIB，顶栏涨跌一行和「额」刚点进来有数，
/// 几秒后变回「—」，要等二十来秒才再补上。搜索列表露出那一眼刚为这只发过一次 REST；收起搜索页时它被裁出报价范围，
/// 可「什么时候收到的 / 问过」没跟着裁，点进图里重新挂上后补价请求被当成「刚问过」拦掉，
/// 头一笔逐笔成交拼出的是一格没有 24h 统计的价，顶栏又只认这一格、把图表行情流手里
/// 现成的 24h 统计挡在后面。这条用例按走查原样走：先换周期，再从搜索连换三只，每只停在
/// 结果页上等列表那次 REST 发出去再点。
@MainActor
final class HeaderChangeAfterSearchUITests: KanpanUICase {
  // 要有一份档案和自选：没有自选表时报价簿「还不知道自选」，一只都不裁，毛病露不出来。
  override var extraLaunchEnvironment: [String: String] {
    ["KANPAN_PERSISTENCE_PROFILE": UUID().uuidString,
     "KANPAN_TEST_FAVORITES": "BTCUSDT,ETHUSDT,SOLUSDT,NVDAUSDT,XAUUSDT"]
  }

  func testChangeLineAndTurnoverFillRightAfterSearch() throws {
    XCTAssertTrue(waitForLiveChart(), "图没起来")
    app.tapIntervalChip("1h")
    for code in ["1000SHIBUSDT", "BTCUSDT", "1000PEPEUSDT"] {
      XCTAssertTrue(app.openSymbolSearch(), "打不开搜索")
      let query = app.textFields[Ids.searchQuery]
      XCTAssertTrue(query.waitForExistence(timeout: Self.short))
      query.typeText(code)
      let row = app.descendants(matching: .any)["symbols.row." + testInstrumentKey(code)]
      XCTAssertTrue(row.waitForExistence(timeout: Self.long), "搜索结果里没有 \(code)")
      // 停在结果页上，让列表为这一行把 REST 发出去、收回来——毛病要的正是这一步。
      _ = waitUntil(timeout: 2.5) { false }
      row.tap()
      XCTAssertTrue(waitUntil(timeout: Self.long) {
        (self.chartInfo()["symbol"] as? String ?? "").hasSuffix(code)
      }, "没换到 \(code)")

      let change = app.descendants(matching: .any)["top.changePercent"]
      let turnover = app.descendants(matching: .any)["top.turnover"]
      func complete() -> Bool {
        !change.label.isEmpty && !change.label.contains("—") && !turnover.label.isEmpty && !turnover.label.contains("—")
      }
      XCTAssertTrue(waitUntil(timeout: 6) { complete() },
                    "\(code) 点进来 6 秒顶栏还缺统计：涨跌「\(change.label)」额「\(turnover.label)」")
      // 毛病的样子是「先有、后丢」：刚点进来顶栏读的是图表行情流那份（有统计），头一笔逐笔成交
      // 一到就换成只有价的那格，涨跌和「额」变回「—」，直到 20 秒后补价请求放行。
      // 所以有了之后还得盯一阵，中途丢一次就算红。
      var lost: String?
      let watchUntil = Date().addingTimeInterval(12)
      while Date() < watchUntil, lost == nil {
        if !complete() { lost = "涨跌「\(change.label)」额「\(turnover.label)」" }
        _ = waitUntil(timeout: 0.4) { false }
      }
      let shot = XCTAttachment(screenshot: app.screenshot())
      shot.name = "顶栏-\(code)"; shot.lifetime = .keepAlways; add(shot)
      XCTAssertNil(lost, "\(code) 顶栏的统计有了又丢：\(lost ?? "")")
    }
  }
}
