import XCTest

/// Runs against the installed app on the authorized iPhone. Settings are isolated
/// in memory so evidence collection never replaces the user's saved alternatives.
@MainActor
final class AICoinBaseUITests: XCTestCase {
  override func setUp() async throws {
    continueAfterFailure = false
    XCUIDevice.shared.orientation = .portrait
  }

  override func tearDown() async throws {
    if let run = testRun, run.failureCount > 0 {
      let failure = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
      failure.name = "失败现场"; failure.lifetime = .keepAlways; add(failure)
      let tree = XCTAttachment(string: XCUIApplication().debugDescription)
      tree.name = "失败界面树"; tree.lifetime = .keepAlways; add(tree)
    }
    XCUIDevice.shared.orientation = .portrait
  }
  func testPinchAndUnifiedBackground() throws {
    let app = XCUIApplication()
    app.launchEnvironment["KANPAN_TEST_PROFILE"] = "1"
    app.launchEnvironment["KANPAN_CHART_DIAGNOSTICS"] = "1"
    app.launch()
    let canvas = app.otherElements["chart.canvas"]
    XCTAssertTrue(canvas.waitForExistence(timeout: 30))
    func info() -> [String: Any] {
      guard let value = canvas.value as? String, let d = value.data(using: .utf8),
            let result = try? JSONSerialization.jsonObject(with: d) as? [String: Any] else { return [:] }
      return result
    }
    let loaded = NSPredicate { _, _ in (info()["bars"] as? Int ?? 0) >= 256 }
    XCTAssertEqual(XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: loaded, object: nil)], timeout: 60), .completed)
    let before = try XCTUnwrap(info()["spacing"] as? Double)
    let cold = XCTAttachment(screenshot: app.screenshot()); cold.name = "统一靛色背景-冷启动"
    cold.lifetime = .keepAlways; add(cold)
    canvas.pinch(withScale: 2.0, velocity: 1)
    let after = info()
    XCTAssertGreaterThan(try XCTUnwrap(after["spacing"] as? Double), before + 0.1, "\(after)")
    let pinch = XCTAttachment(screenshot: app.screenshot()); pinch.name = "统一靛色背景-放大"
    pinch.lifetime = .keepAlways; add(pinch)
  }

  func testColdLaunchStylesAndChartInteractions() throws {
    let app = XCUIApplication()
    app.launchEnvironment["KANPAN_TEST_PROFILE"] = "1"
    app.launchEnvironment["KANPAN_CHART_DIAGNOSTICS"] = "1"
    app.launchEnvironment["KANPAN_LOG"] = "1"
    // 行情线路是**落盘**的（`MarketModel.sourcePreferenceURL`），而且掉到 OKX 兜底之后
    // 头一次回探要等 5 分钟（`MarketRecoverySchedule` 起手就是 now+300s）。真机上只要有
    // 一次跑到了兜底，共用的这个测试档案就一直停在 OKX——那条线路压根没有持仓量
    // （`OISource` 只连币安），后面的 `oiReady` 就永远等不到，和本次改动无关地红着。
    // 每次给一个全新的档案，线路从默认的币安起步。
    app.launchEnvironment["KANPAN_PERSISTENCE_PROFILE"] = UUID().uuidString
    app.launch()
    let canvas = app.otherElements["chart.canvas"]
    XCTAssertTrue(canvas.waitForExistence(timeout: 30))
    func info() -> [String: Any] {
      guard let value = canvas.value as? String, let data = value.data(using: .utf8),
            let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return [:] }
      return object
    }
    func wait(_ condition: @escaping () -> Bool, seconds: Double = 20) -> Bool {
      let predicate = NSPredicate { _, _ in condition() }
      return XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: predicate, object: nil)],
                           timeout: seconds) == .completed
    }
    func shot(_ name: String) {
      let a = XCTAttachment(screenshot: XCUIScreen.main.screenshot()); a.name = name
      a.lifetime = .keepAlways; add(a)
    }
    XCTAssertTrue(wait({ (info()["bars"] as? Int ?? 0) >= 256 }, seconds: 60), "BTC历史尚未加载")
    let original = info()
    XCTAssertEqual(original["style"] as? String, "aicoin")
    XCTAssertEqual(original["mode"] as? String, "log")
    XCTAssertEqual(original["ma"] as? [Int], [10, 30, 120, 256])
    XCTAssertEqual(original["macd"] as? [Int], [10, 30, 9])
    XCTAssertEqual(original["subs"] as? [String], ["VOL", "OI", "MACD"])
    XCTAssertEqual(try XCTUnwrap(original["spacing"] as? Double), 4, accuracy: 0.001)
    shot("01-冷启动-AICoin默认")
    // 这儿原来还挨个点那四张风格卡（经典 / 圆角 / 空心 / 轮廓），验「换风格不动版面尺寸」。
    // 风格表收成 AICoin 一套之后（见 `CandleStyle`）没有第二款可换，这一段跟着撤。
    // 「阳线实心 / 空心」这一档还在「图表」面板上，它同样不该动版面：造型是造型，
    // 间距、主图高度、时间轴位置不归它管——改用它来验同一件事。
    app.buttons["interval.chart"].tap()
    let hollow = app.buttons["chart.bodyChoice.空心"]
    XCTAssertTrue(hollow.waitForExistence(timeout: 8), "图表面板没开出来")
    hollow.tap()
    for key in ["span", "plotW", "mainH", "timeY", "bodyW", "spacing"] {
      XCTAssertEqual(try XCTUnwrap(info()[key] as? Double), try XCTUnwrap(original[key] as? Double),
                     accuracy: 0.001, "切成空心阳线改变了\(key)")
    }
    shot("02-空心阳线-尺寸保持")
    app.buttons["chart.bodyChoice.实心"].tap()
    // 图表面板是配置页，选完不自己收；后面全是点图的动作，先把它收掉。
    app.buttons["panel.done"].tap()
    XCTAssertTrue(wait { !hollow.exists }, "图表面板没收回去")
    let point = canvas.coordinate(withNormalizedOffset: CGVector(dx: 0.35, dy: 0.2))
    point.tap()
    XCTAssertTrue(wait { info()["crosshair"] as? Bool == true })
    shot("03-单击十字线")
    point.tap()
    XCTAssertTrue(wait { info()["crosshair"] as? Bool == false })
    // 主轴翻转现在默认关着（一次误触把整张图倒过来，代价远大于用处），
    // 所以先验「默认双击价格轴不翻」，再去图表面板打开它，验它确实还能翻。
    let axis = canvas.coordinate(withNormalizedOffset: CGVector(dx: 0.98, dy: 0.2))
    axis.doubleTap()
    XCTAssertFalse(wait({ info()["inverted"] as? Bool == true }, seconds: 3),
                   "开关关着的时候双击价格轴不该翻转")
    // 每个面板标题右边常驻一颗「完成」，那是明确的出口——比往下拽靠谱。
    let closePanel = { app.buttons["panel.done"].tap() }
    app.buttons["interval.chart"].tap()
    let allowInvert = app.buttons["chart.allowMainInversion"]
    XCTAssertTrue(allowInvert.waitForExistence(timeout: 8), "图表面板里没有「主轴允许翻转」")
    allowInvert.tap()
    XCTAssertTrue(wait { allowInvert.value as? String == "开" }, "开关没打开")
    closePanel()
    XCTAssertTrue(wait { !allowInvert.exists }, "图表面板没收回去")
    axis.doubleTap()
    XCTAssertTrue(wait { info()["inverted"] as? Bool == true }, "开了开关还是翻不了：\(info())")
    axis.doubleTap()
    XCTAssertTrue(wait { info()["inverted"] as? Bool == false })
    app.buttons["interval.chart"].tap()
    XCTAssertTrue(allowInvert.waitForExistence(timeout: 8))
    allowInvert.tap()
    XCTAssertTrue(wait { allowInvert.value as? String == "关" }, "开关没关回去")
    closePanel()
    XCTAssertTrue(wait { !allowInvert.exists })
    let axisStart = canvas.coordinate(withNormalizedOffset: CGVector(dx: 0.98, dy: 0.20))
    let axisEnd = canvas.coordinate(withNormalizedOffset: CGVector(dx: 0.98, dy: 0.32))
    axisStart.press(forDuration: 0.05, thenDragTo: axisEnd)
    XCTAssertTrue(wait { abs((info()["zoomY"] as? Double ?? 1) - 1) > 0.03 })
    let viewBeforeAuto = info()
    let mainH = try XCTUnwrap(info()["mainH"] as? Double)
    let height = try XCTUnwrap(info()["height"] as? Double)
    let plotW = try XCTUnwrap(info()["plotW"] as? Double)
    let axisW = try XCTUnwrap(info()["axisW"] as? Double)
    canvas.coordinate(withNormalizedOffset: CGVector(
      dx: (plotW + axisW / 2) / (plotW + axisW), dy: (mainH - 34) / height)).tap()
    XCTAssertTrue(wait { abs((info()["zoomY"] as? Double ?? 0) - 1) < 0.001 })
    XCTAssertEqual(try XCTUnwrap(info()["span"] as? Double), try XCTUnwrap(viewBeforeAuto["span"] as? Double), accuracy: 0.001)
    canvas.pinch(withScale: 2.0, velocity: 1)
    XCTAssertTrue(wait { (info()["spacing"] as? Double ?? 0) > 4.1 }, "缩放后状态：\(info())")
    shot("04-真机双指缩放")
    point.press(forDuration: 0.6)
    XCTAssertTrue(wait { info()["crosshair"] as? Bool == true }, "长按抬手应保留十字线")
    point.tap()
    // 跑着跑着被切到兜底线路也是可能的（币安那边抖一下就够了）。那种情况下持仓量
    // 本来就不会来，接着断言只是在验网络，不是验 app——说清楚再跳过。
    try XCTSkipIf(app.staticTexts["market.source"].label == "okx",
                  "当前跑在 OKX 兜底线路上，这条线路不提供持仓量，跳过")
    XCTAssertTrue(wait({ info()["oiReady"] as? Bool == true }, seconds: 45),
                  "OI真实数据未到达（线路：\(app.staticTexts["market.source"].label)）")
    shot("05-持仓量与三副图")
    let oiPane = try XCTUnwrap((info()["panes"] as? [[String: Any]])?.first { $0["id"] as? String == "OI" })
    let oiY = try XCTUnwrap(oiPane["y"] as? Double) + (try XCTUnwrap(oiPane["h"] as? Double)) / 2
    canvas.coordinate(withNormalizedOffset: .zero).withOffset(CGVector(dx: plotW * 0.4, dy: oiY)).tap()
    XCTAssertTrue(wait { info()["crosshair"] as? Bool == true && info()["crossPane"] as? String == "OI" })
    shot("06-副图十字线")
    point.tap()
    let portraitWidth = try XCTUnwrap(info()["plotW"] as? Double)
    let portraitSpacing = try XCTUnwrap(info()["spacing"] as? Double)
    let portraitHeight = try XCTUnwrap(info()["height"] as? Double)
    // 底栏没有单独的「横屏」了：横屏是画线的工作台，点周期行的「画线」直接横过去。
    app.buttons["interval.draw"].tap()
    if UIDevice.current.userInterfaceIdiom == .pad {
      // iPad windows can keep their orientation. Full chart mode must still open.
      XCTAssertTrue(wait { app.buttons["land.exit"].exists &&
        (info()["height"] as? Double ?? 0) > portraitHeight + 80 })
    } else {
      XCTAssertTrue(wait { (info()["plotW"] as? Double ?? 0) > portraitWidth + 80 })
    }
    XCTAssertEqual(try XCTUnwrap(info()["spacing"] as? Double), portraitSpacing, accuracy: 0.001)
    shot("07-横屏共用底座")
    if UIDevice.current.userInterfaceIdiom == .pad {
      XCUIDevice.shared.orientation = .landscapeLeft
      XCTAssertTrue(wait { app.buttons["land.exit"].isHittable && canvas.frame.height > 100 &&
        app.windows.firstMatch.frame.width > app.windows.firstMatch.frame.height })
      shot("08-iPad横向窗口")
    }
    app.buttons["land.exit"].tap()
    // 「竖屏」只退横屏、不退画线——用户横屏画一半转回来还得接着画。
    XCTAssertTrue(app.buttons["draw.finish"].waitForExistence(timeout: 10), "退回竖屏后画线栏没了")
    app.buttons["draw.finish"].tap()
    XCTAssertTrue(app.buttons["bottom.settings"].waitForExistence(timeout: 10))
  }
}
