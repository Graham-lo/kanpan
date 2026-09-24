import XCTest

/// 周期一律中文短写、条尾图表设置只剩一颗记号（审查 U12）。
///
/// 周期档的字画在按钮里、按钮的无障碍名是整句（「5 分钟」），测试读不到画出来的那几个字，
/// 所以字面对不对靠截图看；这里钉住的是「功能一个没丢」：图表设置那颗照旧 44pt 能点、
/// 点开的照旧是图表设置面板，没钉住的档从网格选了之后「更多」替它说话，横屏周期栏也在。
@MainActor
final class IntervalLabelUITests: KanpanUICase {
  private func save(_ name: String) {
    try? FileManager.default.createDirectory(atPath: "/tmp/kanpan-laneg-shots", withIntermediateDirectories: true)
    try? XCUIScreen.main.screenshot().pngRepresentation
      .write(to: URL(fileURLWithPath: "/tmp/kanpan-laneg-shots/\(name).png"))
  }

  func testShortLabelsAndIconOnlyChartSettings() throws {
    XCTAssertTrue(waitForLiveChart(), "没等到行情")
    save("U12-周期条-出厂")

    // 条尾那颗：没有字，但读屏读得出、手指点得着、点开的是图表设置。
    let entry = app.buttons[Ids.intervalChart]
    XCTAssertTrue(entry.waitForExistence(timeout: Self.short), "周期行右端没有图表设置那颗")
    XCTAssertEqual(entry.label, "图表设置")
    XCTAssertGreaterThanOrEqual(entry.frame.width, 44, "图表设置那颗命中区不到 44pt：\(entry.frame)")
    XCTAssertTrue(entry.isHittable)
    // 行情页上不再有一个写着「图表」的字：底栏只有图标，条尾也换成了记号。
    XCTAssertFalse(app.staticTexts["图表"].exists, "行情页上还有「图表」两个字")
    entry.tap()
    XCTAssertTrue(app.buttons["chart.indicators"].waitForExistence(timeout: Self.short), "点图表设置那颗没开出图表设置面板")
    save("U12-图表设置面板")
    app.buttons[Ids.panelDone].tap()
    XCTAssertTrue(waitUntil(timeout: Self.short) { !self.app.buttons["chart.indicators"].exists }, "图表设置面板没收")

    // 「更多」网格：十四档照旧都在。
    app.buttons[Ids.intervalMore].tap()
    for raw in ["1m", "3m", "15m", "2h", "6h", "12h", "1M", "1y"] {
      XCTAssertTrue(app.buttons["period.row.\(raw)"].waitForExistence(timeout: Self.short), "网格里少了 \(raw)")
    }
    XCTAssertEqual(app.buttons["period.row.1M"].label, "1 月")
    XCTAssertEqual(app.buttons["period.row.1m"].label, "1 分钟")
    save("U12-更多网格")

    // 选一档没钉住的：「更多」改写成那一档并说出来。
    app.buttons["period.row.2h"].tap()
    let more = app.buttons[Ids.intervalMore]
    XCTAssertTrue(waitUntil(timeout: Self.short) { more.label.contains("当前 2 小时") }, "「更多」没替 2h 说话：\(more.label)")
    save("U12-周期条-更多替没钉住的档说话")

    // 横屏画线台左边那条周期栏。
    XCTAssertTrue(app.tapDrawEntry(), "标签栏上没有「画线」")
    XCTAssertTrue(app.landscapeMarker.waitForExistence(timeout: Self.long), "点「画线」没横过来")
    XCTAssertTrue(app.buttons["更多周期"].waitForExistence(timeout: Self.long), "横屏周期栏底下没有「更多周期」")
    Thread.sleep(forTimeInterval: 1)
    save("U12-横屏周期栏")
    app.rotateDrawingToPortraitByHand()
  }
}
