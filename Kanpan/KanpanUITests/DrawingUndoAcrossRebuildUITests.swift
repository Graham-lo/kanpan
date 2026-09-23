import XCTest

/// 任务 3 的复现用例：**画线的撤销栈要活得过图的重建**。
///
/// 用户走的那条路是「画两笔 → 切到自选页再回来 → 撤销」。竖屏切一次自选页，
/// `ChartBox.makeUIView` 就造一个全新的 `ChartView`；撤销栈从前只活在那个实例身上，
/// 于是回来之后两笔还在图上、「撤销」却是灰的，点下去什么都不发生。
///
/// 修法是把栈挪进 `DrawingController`（`MainScreen` 里唯一那个 `@StateObject`，
/// 活得过所有重建），按品种分格存放，图一接上来就接回去。这条用例量三件事：
///
/// 1. 从自选页回来之后，两笔线还在，而且「撤销」是**亮的**；
/// 2. 点「撤销」真的撤掉一笔，不是空响；
/// 3. 撤掉的是**最后画的那一笔**——`drawingIDs` 只剩第一笔的 id，顺序没乱。
@MainActor final class DrawingUndoAcrossRebuildUITests: XCTestCase {
  private var app: XCUIApplication!
  private var canvas: XCUIElement { app.otherElements["chart.canvas"] }

  override func setUp() async throws {
    continueAfterFailure = false
    XCUIDevice.shared.orientation = .portrait
    app = XCUIApplication()
    app.launchEnvironment["KANPAN_TEST_PROFILE"] = "1"
    app.launchEnvironment["KANPAN_PERSISTENCE_PROFILE"] = UUID().uuidString
    app.launchEnvironment["KANPAN_CHART_DIAGNOSTICS"] = "1"
    app.launch()
    let chartTab = app.buttons["bottom.chart"]
    if chartTab.waitForExistence(timeout: 5), !canvas.exists { chartTab.tap() }
    XCTAssertTrue(canvas.waitForExistence(timeout: 30), "K 线画布没出来")
    XCTAssertTrue(wait(seconds: 60) { (self.info()["bars"] as? Int ?? 0) >= 64 },
                  "K 线没拿到数据：\(info())")
  }

  override func tearDown() async throws {
    guard app.state != .notRunning, app.state != .unknown else { return }
    app.terminate()
  }

  private func info() -> [String: Any] {
    guard canvas.exists, let value = canvas.value as? String, let data = value.data(using: .utf8),
          let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return [:] }
    return object
  }

  private func ids() -> [String] { (info()["drawingIDs"] as? [String]) ?? [] }

  private func wait(seconds: Double = 20, _ condition: @escaping () -> Bool) -> Bool {
    XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in condition() }, object: nil)],
                   timeout: seconds) == .completed
  }

  private func shot(_ name: String) {
    let a = XCTAttachment(screenshot: XCUIScreen.main.screenshot()); a.name = name
    a.lifetime = .keepAlways; add(a)
  }

  /// 在主图那一段里取一个点。副图区画不了线，所以 y 一律按 `mainH` 折算。
  private func point(x: Double, y: Double) throws -> XCUICoordinate {
    let frame = canvas.frame
    let height = try XCTUnwrap(info()["height"] as? Double)
    let mainH = try XCTUnwrap(info()["mainH"] as? Double)
    let scale = frame.height / height   // 诊断里的高度是 point，和 frame 一致，这儿只是兜个底
    return canvas.coordinate(withNormalizedOffset: .zero)
      .withOffset(CGVector(dx: frame.width * x, dy: mainH * scale * y))
  }

  /// 画一笔趋势线。工具每画完一笔就退回选择态（「连续」默认是关的），所以每笔都重新拿。
  ///
  /// 画完的那条会自动选中，上排整排换成选中栏（`DrawingSelectionBar`，1e271ee），趋势线 chip
  /// 这时不在栏上——走下排钉死的「全部工具」，跟用户画完一笔接着换工具走的是同一条路。
  private func drawTrend(from a: (Double, Double), to b: (Double, Double), expect count: Int) throws {
    let chip = app.buttons["draw.trend"]
    if chip.waitForExistence(timeout: 3) {
      chip.tap()
    } else {
      let tools = app.buttons["draw.tools"]
      XCTAssertTrue(tools.waitForExistence(timeout: 8), "画线栏下排没有「全部工具」")
      tools.tap()
      let cell = app.buttons["draw.tool.trend"]
      XCTAssertTrue(cell.waitForExistence(timeout: 8), "全部工具面板里没有趋势线")
      cell.tap()
    }
    try point(x: a.0, y: a.1).tap()
    try point(x: b.0, y: b.1).tap()
    XCTAssertTrue(wait(seconds: 8) { self.info()["drawingCount"] as? Int == count },
                  "第 \(count) 笔没画上：\(info())")
  }

  func testUndoStackSurvivesChartRebuildAcrossTabs() throws {
    // ① 画两笔。
    XCTAssertTrue(app.enterDrawingInPortrait(), "没能进入竖屏画线态")
    try drawTrend(from: (0.22, 0.20), to: (0.62, 0.38), expect: 1)
    try drawTrend(from: (0.22, 0.60), to: (0.62, 0.80), expect: 2)
    let drawn = ids()
    XCTAssertEqual(drawn.count, 2, "两笔没都画上：\(info())")
    XCTAssertTrue(app.buttons["draw.undo"].isEnabled, "刚画完「撤销」就是灰的")
    shot("1-画两笔")

    // ② 切到自选页再回来。这一趟会把 ChartView 整个拆掉重造。
    XCTAssertTrue(app.openFavorites(), "没进到自选页")
    shot("2-自选页")
    let chartTab = app.buttons["bottom.chart"]
    XCTAssertTrue(chartTab.waitForExistence(timeout: 10), "标签栏上没有「图表」")
    chartTab.tap()
    XCTAssertTrue(wait(seconds: 20) { self.canvas.exists && self.ids().count == 2 },
                  "回到图上两笔线没了：\(info())")

    // ③ 重新进画线态（离开图表那一格时画线工作台会自己收）。
    if !app.buttons["draw.undo"].exists {
      XCTAssertTrue(app.enterDrawingInPortrait(), "回来之后没能再进画线态")
    }
    XCTAssertEqual(ids(), drawn, "重建之后线的顺序或 id 变了")
    let undo = app.buttons["draw.undo"]
    XCTAssertTrue(undo.waitForExistence(timeout: 10), "画线栏上没有「撤销」")
    XCTAssertTrue(undo.isEnabled, "图重建之后「撤销」变灰了——撤销栈没活过来")
    shot("3-切回来后撤销仍然可用")

    // ④ 撤销，撤掉的必须是最后那一笔。
    undo.tap()
    XCTAssertTrue(wait(seconds: 8) { self.ids() == [drawn[0]] },
                  "撤销撤掉的不是最后一笔：期望 \([drawn[0]])，实际 \(ids())")
    shot("4-撤销撤掉了最后一笔")

    // 顺带验一下「重做」把它放回来，顺序照旧。
    let redo = app.buttons["draw.redo"]
    if redo.exists, redo.isEnabled {
      redo.tap()
      XCTAssertTrue(wait(seconds: 8) { self.ids() == drawn }, "重做没把第二笔放回原位：\(ids())")
    }
  }
}
