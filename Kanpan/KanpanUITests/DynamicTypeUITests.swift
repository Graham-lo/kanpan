import XCTest

// ============================================================ P2.13 动态字体
//
// 画布外的字 2026-09-23 起跟随系统「文字大小」，整个 app 封顶 `.xxxLarge`，
// 行情页头部那一行单独封顶默认档 `.large`。这条用例在辅助大字 AX3
// （`UICTContentSizeCategoryAccessibilityXL`）下走五页：
//
// - 行情页头部：六格仍在价格右边，价格、六格、周期条的位置和默认档一个 pt 都不差；
// - 自选页、板块页（气泡场 + 全部板块 + 板块品种表）、设置整页、提醒总表：各留一张图，
//   截字和重叠靠人看图判（验收报告里逐张写结论），用例只守「控件都还在窗口里」。
//
// 启动参数 `-UIPreferredContentSizeCategoryName` 是 UIKit 自己认的，不是测试后门。
@MainActor
final class DynamicTypeUITests: KanpanUICase {

  override var extraLaunchEnvironment: [String: String] {
    // 自选里放几只小数位差得远的，提醒总表里种一条「已触发」，两页都有行可看。
    ["KANPAN_TEST_FAVORITES": "BTCUSDT,ETHUSDT,SOLUSDT,1000SATSUSDT,DOGEUSDT",
     "KANPAN_TEST_ALERT_FIRED": "BTCUSDT",
     "KANPAN_TEST_DEEPLINK": "hkline://symbol/BTCUSDT"]
  }

  private struct Header: CustomStringConvertible {
    var price: CGRect, change: CGRect, stats: CGRect, intervalY: CGFloat
    var description: String { "price=\(price) change=\(change) stats=\(stats) intervalY=\(intervalY)" }
  }

  func testAX3PagesKeepHeaderAndFit() {
    continueAfterFailure = true
    relaunch(size: "UICTContentSizeCategoryL")
    guard let base = measureHeader("默认档-头部") else { return }

    relaunch(size: "UICTContentSizeCategoryAccessibilityXL")
    guard let ax3 = measureHeader("AX3-头部") else { return }
    print("HEADER default \(base)\nHEADER ax3 \(ax3)")
    XCTAssertEqual(ax3.price.height, base.price.height, accuracy: 0.5, "AX3 下价格字号变了")
    XCTAssertEqual(ax3.stats.height, base.stats.height, accuracy: 0.5, "AX3 下六格变高了")
    XCTAssertEqual(ax3.intervalY, base.intervalY, accuracy: 0.5, "AX3 下头部挤高了周期条")

    // 自选页
    XCTAssertTrue(app.openFavorites(), "AX3 下进不了自选页")
    XCTAssertTrue(waitUntil(timeout: Self.long) {
      self.app.descendants(matching: .any)["favorites.change." + testInstrumentKey("BTCUSDT")].exists
    }, "自选页上没有 BTCUSDT 那一行")
    shot("AX3-自选")
    assertInWindow(["favorites.more", Ids.bottomChart], page: "自选")

    // 板块页：气泡场 → 全部板块 → 一个板块的品种表
    app.buttons[Ids.bottomSectors].tap()
    expectExists(app.otherElements["sector.page"], Self.long, "AX3 下进不了板块页")
    _ = waitUntil(timeout: Self.long) { self.app.otherElements["sector.bubbles"].exists }
    shot("AX3-板块")
    let more = app.buttons["sector.more"]
    if expectExists(more, Self.short, "板块页上没有「…」") {
      assertInWindow(["sector.more"], page: "板块")
      more.tap()
      let row = app.buttons.matching(
        NSPredicate(format: "identifier BEGINSWITH %@", "sector.all.row.")).firstMatch
      if expectExists(row, Self.long, "「全部板块」里一行都没有") {
        shot("AX3-全部板块")
        row.tap()
        RunLoop.current.run(until: Date(timeIntervalSinceNow: 2))
        shot("AX3-板块品种表")
      }
    }

    // 设置整页
    openSettingsPage()
    shot("AX3-设置")
    assertInWindow([Ids.settingsMagnet], page: "设置")

    // 提醒总表（设置 →「提醒」）
    let entry = app.descendants(matching: .any).matching(identifier: "settings.alerts").firstMatch
    if expectExists(entry, Self.short, "设置里没有「提醒」") {
      for _ in 0..<5 where !app.descendants(matching: .any)["alerts.page"].exists {
        guard waitUntil(timeout: 5, { entry.frame.height > 1 }) else { continue }
        entry.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        _ = app.descendants(matching: .any)["alerts.page"].waitForExistence(timeout: 5)
      }
      XCTAssertTrue(app.descendants(matching: .any)["alerts.page"].exists, "AX3 下开不出提醒总表")
      RunLoop.current.run(until: Date(timeIntervalSinceNow: 1))
      shot("AX3-提醒总表")
    }
  }

  // ------------------------------------------------------------ 小工具

  private func relaunch(size: String) {
    app.terminate()
    app.launchArguments = ["-UIPreferredContentSizeCategoryName", size]
    app.launch()
    let chartTab = app.buttons[Ids.bottomChart]
    if chartTab.waitForExistence(timeout: 5), !app.symbolLabel.exists { chartTab.tap() }
    XCTAssertTrue(app.symbolLabel.waitForExistence(timeout: Self.long), "\(size) 下没回到行情页")
  }

  /// 等价格与六格的实值到齐，量位置并留图。六格必须整块在价格与涨跌行右边、在屏幕以内。
  private func measureHeader(_ name: String) -> Header? {
    let price = app.staticTexts["top.lastPrice"]
    let change = app.descendants(matching: .any)["top.changePercent"].firstMatch
    let stats = app.otherElements["top.stats"]
    guard expectExists(price, Self.long), expectExists(stats, Self.long) else { return nil }
    XCTAssertTrue(waitUntil(timeout: Self.long) {
      [price.label, self.app.staticTexts["top.turnover"].label, self.app.staticTexts["top.funding"].label]
        .allSatisfy { !["", "—", "--"].contains($0) }
    }, "\(name)：价格与六格实值没有到齐")
    let header = Header(price: price.frame, change: change.frame, stats: stats.frame,
                        intervalY: app.buttons[Ids.intervalMore].frame.minY)
    shot(name)
    XCTAssertGreaterThanOrEqual(header.stats.minX, header.price.maxX, "\(name)：六格掉到价格下面")
    XCTAssertGreaterThanOrEqual(header.stats.minX, header.change.maxX + 7.5, "\(name)：涨跌行挤进六格")
    XCTAssertLessThanOrEqual(header.stats.maxX, windowFrame.maxX - 12 + 0.5, "\(name)：六格超出屏幕右缘")
    XCTAssertTrue(header.stats.minY < header.change.maxY && header.stats.maxY > header.price.minY,
                  "\(name)：六格和价格不在同一行")
    return header
  }

  private func assertInWindow(_ ids: [String], page: String) {
    for id in ids {
      let el = app.descendants(matching: .any).matching(identifier: id).firstMatch
      guard el.exists else { XCTFail("\(page)：\(id) 不在了"); continue }
      XCTAssertTrue(windowFrame.insetBy(dx: -0.5, dy: -0.5).contains(el.frame),
                    "\(page)：\(id) 被顶出窗口（\(el.frame)）")
    }
  }

  private func shot(_ name: String) {
    let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
    attachment.name = name
    attachment.lifetime = .keepAlways
    add(attachment)
  }
}
