import XCTest

/// P2.17「收盘价」画法：从「图表」面板切到第三档，主图换成收盘价折线；再切回蜡烛。
///
/// 断言读的是图的诊断（`candleKind`），截图作为验收证据留在结果包里。
@MainActor
final class CandleKindLineUITests: KanpanUICase {
  func testSwitchToCloseLineAndBack() throws {
    XCTAssertTrue(waitUntil(timeout: 60) { (self.chartInfo()["bars"] as? Int ?? 0) >= 100 },
                  "K 线没加载出来")
    XCTAssertEqual(chartInfo()["candleKind"] as? String, "candle", "出厂画法应是蜡烛")

    app.buttons[Ids.intervalChart].tap()
    let line = app.buttons["chart.candleKind.收盘价"]
    XCTAssertTrue(line.waitForExistence(timeout: Self.short), "图表面板里没有「收盘价」这一档")
    XCTAssertTrue(app.buttons["chart.candleKind.蜡烛"].exists)
    XCTAssertTrue(app.buttons["chart.candleKind.平均K线"].exists)
    line.tap()
    XCTAssertTrue(waitUntil(timeout: Self.short) { self.chartInfo()["candleKind"] as? String == "line" },
                  "点了「收盘价」图没换画法")
    shot("01-面板里选中收盘价")
    app.buttons[Ids.panelDone].tap()
    XCTAssertTrue(waitUntil(timeout: Self.short) { !line.exists }, "图表面板没收回去")
    shot("02-收盘价折线")

    app.buttons[Ids.intervalChart].tap()
    let candle = app.buttons["chart.candleKind.蜡烛"]
    XCTAssertTrue(candle.waitForExistence(timeout: Self.short))
    candle.tap()
    XCTAssertTrue(waitUntil(timeout: Self.short) { self.chartInfo()["candleKind"] as? String == "candle" },
                  "切回「蜡烛」图没换回来")
    app.buttons[Ids.panelDone].tap()
    XCTAssertTrue(waitUntil(timeout: Self.short) { !candle.exists })
    shot("03-切回蜡烛")
  }

  private func shot(_ name: String) {
    let a = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
    a.name = name
    a.lifetime = .keepAlways
    add(a)
  }
}
