import XCTest

/// 「点面板外面收起面板」只许有一层（审查 16.3）。
///
/// 从前有两层：宿主页最上面那块透明的 `PanelDismissShield`（`panel.outside`），
/// 和图表盒子 `ChartBox` 里自己再铺的一块 `UIControl`（`chart.dismissPanel`）。
/// 2026-09-24 在 iPhone 16 Pro 模拟器上探过：竖屏开图表设置，前者可点、后者 exists 但
/// 不可点（整屏被前者盖着）；横屏画线台开样式表，那张表占满整屏（874×402），
/// 表外没有可点的图，后者同样不可点。第二层从来接不到手指，只是摆着等哪天和前者
/// 一起触发——现在删掉，只留宿主那一层。
@MainActor final class PanelDismissLayerUITests: XCTestCase {
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
    XCUIDevice.shared.orientation = .portrait
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

  private var outside: XCUIElement { app.descendants(matching: .any).matching(identifier: "panel.outside").firstMatch }
  private var chartLayer: XCUIElement { app.descendants(matching: .any).matching(identifier: "chart.dismissPanel").firstMatch }

  private func report(_ stage: String) {
    print("DISMISS-PROBE \(stage): panel.outside exists=\(outside.exists) hittable=\(outside.exists && outside.isHittable) "
      + "chart.dismissPanel exists=\(chartLayer.exists) hittable=\(chartLayer.exists && chartLayer.isHittable)")
  }

  /// 竖屏：开图表设置，点一下图，面板收起、图上不落十字线，而且只要点一下。
  func testPortraitChartPanelClosesOnOneOutsideTap() throws {
    let entry = app.buttons["interval.chart"]
    XCTAssertTrue(entry.waitForExistence(timeout: 10), "周期条尾巴上没有图表设置入口")
    entry.tap()
    let header = app.staticTexts["panel.header"]
    XCTAssertTrue(header.waitForExistence(timeout: 8), "图表设置面板没开出来")
    report("portrait-open")
    try? XCUIScreen.main.screenshot().pngRepresentation
      .write(to: URL(fileURLWithPath: "/tmp/kanpan-laneg-shots/16.3-竖屏图表设置开着.png"))
    XCTAssertTrue(outside.exists, "面板开着时宿主那层「点外面收起」不在")
    XCTAssertFalse(chartLayer.exists, "图表盒子里还有第二层收起面板")

    app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.3)).tap()
    XCTAssertTrue(wait(seconds: 5) { !header.exists }, "点了一下外面，面板没收")
    report("portrait-closed")
    XCTAssertEqual(info()["crosshair"] as? Bool, false, "收面板那一下漏到图上落了十字线：\(info())")
    XCTAssertFalse(outside.exists, "面板收了，挡点击的那层还留着")
  }

  /// 横屏画线台：样式表是整屏的，收起走表上的「取消」；图表盒子里不再有第二层收起面板。
  func testLandscapeStyleSheetHasNoSecondDismissLayer() throws {
    XCTAssertTrue(app.tapDrawEntry(), "底栏没有画线入口")
    XCTAssertTrue(app.landscapeMarker.waitForExistence(timeout: 15), "点画线没转到横屏画线台")
    let chip = app.buttons["draw.hline"]
    XCTAssertTrue(chip.waitForExistence(timeout: 8), "横屏画线台上没有水平线")
    chip.tap()
    let spot = canvas.coordinate(withNormalizedOffset: CGVector(dx: 0.45, dy: 0.35))
    spot.tap()
    XCTAssertTrue(wait(seconds: 8) { (self.info()["drawingCount"] as? Int) == 1 }, "线没画上：\(info())")
    if !app.buttons["draw.style"].exists { spot.tap() }
    let style = app.buttons["draw.style"]
    XCTAssertTrue(style.waitForExistence(timeout: 8), "选中栏上没有样式")
    style.tap()
    let save = app.buttons["draw.save"]
    XCTAssertTrue(save.waitForExistence(timeout: 8), "样式表没开出来")
    report("landscape-style-open")
    XCTAssertFalse(chartLayer.exists, "图表盒子里还有第二层收起面板")
    app.buttons["取消"].firstMatch.tap()
    XCTAssertTrue(wait(seconds: 5) { !save.exists }, "点取消样式表没收")
    XCTAssertEqual(info()["drawingCount"] as? Int, 1, "收样式表把线弄没了：\(info())")
    XCTAssertTrue(app.landscapeMarker.exists, "收样式表把横屏画线台也退掉了")
  }
}
