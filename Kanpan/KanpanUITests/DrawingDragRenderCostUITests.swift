import XCTest

/// 拖一条线的时候，宿主页跟着重算了多少遍（审查 16.1）。
///
/// 这条用例本身不判数：它只负责在模拟器上把「画一条水平线 → 选中 → 来回拖几趟」这件事
/// 稳定地做一遍。DEBUG 包里图上每一段手势都会让 `FrameProbe` 采一段，采集期间
/// `MainScreen` / `DrawingBar` / `DrawingSelectionBar` 的 `body` 各被求值几次记在报告的
/// `bodies` 里，报告落在 app 沙盒的 `Diagnostics/frames/`。改 `DrawingController`
/// 的发布方式前后各跑一遍、把两份报告摆在一起比，就是那笔账。
@MainActor final class DrawingDragRenderCostUITests: XCTestCase {
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
    XCTAssertTrue(wait(seconds: 60) { (self.info()["bars"] as? Int ?? 0) >= 64 }, "K 线没拿到数据：\(info())")
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

  private func wait(seconds: Double = 20, _ condition: @escaping () -> Bool) -> Bool {
    XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in condition() }, object: nil)],
                   timeout: seconds) == .completed
  }

  private func point(x: Double, y: Double) throws -> XCUICoordinate {
    let frame = canvas.frame
    let height = try XCTUnwrap(info()["height"] as? Double)
    let mainH = try XCTUnwrap(info()["mainH"] as? Double)
    let scale = frame.height / height
    return canvas.coordinate(withNormalizedOffset: .zero)
      .withOffset(CGVector(dx: frame.width * x, dy: mainH * scale * y))
  }

  func testDraggingASelectedLine() throws {
    XCTAssertTrue(app.enterDrawingInPortrait(), "没能进入竖屏画线态")
    let chip = app.buttons["draw.hline"]
    XCTAssertTrue(chip.waitForExistence(timeout: 8), "画线栏上没有水平线")
    chip.tap()
    let spot = try point(x: 0.45, y: 0.40)
    spot.tap()
    XCTAssertTrue(wait(seconds: 8) { (self.info()["drawingCount"] as? Int) == 1 }, "线没画上：\(info())")
    spot.tap()
    XCTAssertTrue(app.buttons["draw.delete"].waitForExistence(timeout: 8), "没选中那条线：\(info())")
    // 让前面落笔、选中那两段采集先各自收尾存盘，下面的拖动单独成一份报告。
    Thread.sleep(forTimeInterval: 2)

    var from = spot
    for round in 0..<6 {
      let to = try point(x: 0.45, y: round.isMultiple(of: 2) ? 0.60 : 0.40)
      from.press(forDuration: 0.15, thenDragTo: to, withVelocity: .slow, thenHoldForDuration: 0.1)
      from = to
    }
    // 抬手后探针还要再采 1.2 秒才停、存盘。
    Thread.sleep(forTimeInterval: 2.5)
    XCTAssertEqual(info()["drawingCount"] as? Int, 1, "拖的过程中线丢了或者多出来了：\(info())")
  }
}
