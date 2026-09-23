import XCTest

/// 第五轮收尾时挂在 `PROJECT.md` 上的两条观察，从用户的手指这一侧钉住。
///
/// **甲：竖屏点中已有的画线会被拽进横屏工作台。** 病根在 `DrawingController.sync()`
/// 那句「选中了就 `active = true`」——`MainScreen` 对 `active` 的 onChange 当场转屏。
/// 现在「选中」永远不开工作台，而且不在画线态时图根本不收画线的手
/// （`ChartView.drawingEditable`），点中一条旧线连选中都不会发生。
///
/// **乙：单锚点工具一次点击可能落两条。** 病根在 `finishUnclaimed` 里那条
/// 「抬手时若手上有工具就补一个点」的陈旧分支：手上有工具的那根手指在
/// `touchesBegan` 就被画线层整根收走了，还能走到那儿的手指全都是**不该落笔**的。
/// 时序相关的两条复现（点完马上捏合、按住了才拿起工具）在
/// `KanpanChartTests/ChartDrawingTapDisciplineTests` 里按毫秒钉；这儿钉的是
/// 用户真实的那一下：**点一下，图上只许多出一条**。
@MainActor final class DrawingTapDisciplineUITests: XCTestCase {
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

  private func count() -> Int { (info()["drawingCount"] as? Int) ?? -1 }

  private func wait(seconds: Double = 20, _ condition: @escaping () -> Bool) -> Bool {
    XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in condition() }, object: nil)],
                   timeout: seconds) == .completed
  }

  /// 在主图那一段里取一个点（副图区画不了线，y 按 `mainH` 折算）。
  private func point(x: Double, y: Double) throws -> XCUICoordinate {
    let frame = canvas.frame
    let height = try XCTUnwrap(info()["height"] as? Double)
    let mainH = try XCTUnwrap(info()["mainH"] as? Double)
    let scale = frame.height / height
    return canvas.coordinate(withNormalizedOffset: .zero)
      .withOffset(CGVector(dx: frame.width * x, dy: mainH * scale * y))
  }

  /// 乙：单锚点工具，点一下只许多出一条；再点一下也只多一条。
  ///
  /// 「连续」先打开——不然画完一笔工具自己退回选择态，第二下就不是同一件事了，
  /// 而手上一直举着工具正是那条陈旧分支最容易多落一条的场面。
  func testSingleAnchorTapPlacesExactlyOneLine() throws {
    XCTAssertTrue(app.enterDrawingInPortrait(), "没能进入竖屏画线态")
    // 「连续画同一种线」2026-09-23 起收在画线栏的「更多」弹层里。
    XCTAssertTrue(app.openDrawMore(), "画线栏上开不出「更多」")
    let repeatToggle = app.buttons["draw.continuous.quick"]
    if repeatToggle.value as? String == "关" { repeatToggle.tap() }
    app.closeDrawMore()

    let chip = app.buttons["draw.hline"]
    XCTAssertTrue(chip.waitForExistence(timeout: 8), "画线栏上没有水平线")
    chip.tap()

    try point(x: 0.45, y: 0.35).tap()
    XCTAssertTrue(wait(seconds: 8) { self.count() == 1 }, "第一下没画上：\(info())")
    // 多等一会儿再数一次：多出来的那一条是抬手之后补落的，立刻数会漏掉它。
    XCTAssertFalse(wait(seconds: 3) { self.count() != 1 }, "一次点击落了 \(count()) 条")

    try point(x: 0.60, y: 0.55).tap()
    XCTAssertTrue(wait(seconds: 8) { self.count() == 2 }, "第二下没画上：\(info())")
    XCTAssertFalse(wait(seconds: 3) { self.count() != 2 }, "第二次点击落了不止一条：\(info())")
  }

  /// 甲：收了工具之后点中那条线，屏幕不许自己转过去。
  func testTappingAnExistingLineInPortraitStaysPortrait() throws {
    XCTAssertTrue(app.enterDrawingInPortrait(), "没能进入竖屏画线态")
    let chip = app.buttons["draw.hline"]
    XCTAssertTrue(chip.waitForExistence(timeout: 8), "画线栏上没有水平线")
    chip.tap()
    let spot = try point(x: 0.45, y: 0.4)
    spot.tap()
    XCTAssertTrue(wait(seconds: 8) { self.count() == 1 }, "线没画上：\(info())")

    // 先证明这个坐标真的压在线身上：画线态下点它会选中，选中栏就出来了。
    // 没有这一步，下面「点了没转屏」可能只是因为根本没点中，用例就成了空转。
    spot.tap()
    // 「删除」只在选中栏里，它在场就等于真的选中了。
    XCTAssertTrue(app.buttons["draw.delete"].waitForExistence(timeout: 8),
                  "这个坐标没压在线上，后面那一下等于没点：\(info())")

    let finish = app.buttons["draw.finish"]
    XCTAssertTrue(finish.waitForExistence(timeout: 8), "画线栏上没有完成")
    finish.tap()
    XCTAssertTrue(wait(seconds: 8) { !finish.exists }, "「完成」点了没退出画线态")

    // 就点在那条线身上。
    spot.tap()
    XCTAssertFalse(wait(seconds: 4) { self.app.buttons["land.exit"].exists },
                   "点中一条旧线把屏幕转成了横屏画线工作台")
    XCTAssertFalse(app.buttons["draw.finish"].exists, "点中一条旧线把画线工作台打开了")
    XCTAssertEqual(count(), 1, "点一下把线弄丢了或者多画了一条：\(info())")
  }
}
