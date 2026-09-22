import XCTest

// P2.11：画布上双击 = 回到最新 + 自动纵向贴合；价格轴上的双击仍归翻轴，不在这条里。
@MainActor
final class ChartDoubleTapUITests: KanpanUICase {
  func testDoubleTapOnCanvasReturnsToLatestAndAutoFits() throws {
    XCTAssertTrue(waitUntil(timeout: Self.long) { (self.chartInfo()["bars"] as? Int ?? 0) >= 200 },
                  "K 线没加载出来")
    // 先把 Y 拖成手动：在价格轴上竖着拖一把。
    let plotW = try XCTUnwrap(chartInfo()["plotW"] as? Double)
    let mainH = try XCTUnwrap(chartInfo()["mainH"] as? Double)
    let canvas = app.otherElements["chart.canvas"]
    let origin = canvas.coordinate(withNormalizedOffset: .zero)
    let axis = origin.withOffset(CGVector(dx: plotW + 20, dy: min(140, mainH / 2)))
    axis.press(forDuration: 0.05, thenDragTo: axis.withOffset(CGVector(dx: 0, dy: -85)))
    XCTAssertTrue(waitUntil(timeout: Self.short) {
      abs((self.chartInfo()["zoomY"] as? Double ?? 1) - 1) > 0.03
    }, "价格轴拖了一把，Y 还是自动的")
    // 再推到历史里。
    var pushes = 0
    while (chartInfo()["latestRightGap"] as? Double ?? 0) > -20, pushes < 8 {
      dragChartRight(); pushes += 1
    }
    XCTAssertLessThan(try XCTUnwrap(chartInfo()["latestRightGap"] as? Double), -20, "图还贴在最新那根上")
    shot("双击前-历史里且Y手动")

    origin.withOffset(CGVector(dx: plotW * 0.45, dy: min(160, mainH * 0.45))).doubleTap()
    XCTAssertTrue(waitUntil(timeout: Self.short) {
      let info = self.chartInfo()
      return (info["latestRightGap"] as? Double ?? -999) > -2
        && abs((info["zoomY"] as? Double ?? 0) - 1) < 0.001
        && info["crosshair"] as? Bool == false
    }, "双击画布没回到最新 / 没恢复自动纵向：\(chartInfo())")
    shot("双击后-回到最新且自动贴合")

    // 单击照旧当场开十字线。
    origin.withOffset(CGVector(dx: plotW * 0.45, dy: min(160, mainH * 0.45))).tap()
    XCTAssertTrue(waitUntil(timeout: Self.short) { self.chartInfo()["crosshair"] as? Bool == true },
                  "单击没出十字线")
  }

  private func shot(_ name: String) {
    let a = XCTAttachment(screenshot: app.screenshot())
    a.name = name
    a.lifetime = .keepAlways
    add(a)
  }
}
