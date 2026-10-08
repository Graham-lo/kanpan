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
    // 每次给一个全新的档案：行情线路记在 Prefs 里（测试沙盒起步直连=币安），全新档案保证
    // 这条用例从币安起步，不会被别的用例留下的「网关」设置带到 OKX——那条线路
    // 压根没有持仓量（`OISource` 只连币安），后面的 `oiReady` 就永远等不到。
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
    XCTAssertEqual(original["mode"] as? String, "log")
    XCTAssertEqual(original["ma"] as? [Int], [10, 30, 120, 256])
    XCTAssertEqual(original["macd"] as? [Int], [10, 30, 9])
    XCTAssertEqual(original["subs"] as? [String], ["VOL", "OI", "MACD"])
    XCTAssertEqual(try XCTUnwrap(original["spacing"] as? Double), 4, accuracy: 0.001)
    shot("01-冷启动-AICoin默认")
    // 这儿原来还挨个点那四张风格卡（经典 / 圆角 / 空心 / 轮廓），验「换风格不动版面尺寸」。
    // 风格表收成 AICoin 一套之后（见 `CandleStyle`）没有第二款可换，这一段跟着撤。
    // 「阳线实心 / 空心」2026-09-28 收掉（收设置项 B 组，阳线一律实心），改用同一张面板上
    // 「K 线 · 画法」的「平均K线」来验同一件事：造型是造型，间距、主图高度、时间轴位置不归它管。
    app.buttons["interval.chart"].tap()
    let heikin = app.buttons["chart.candleKind.平均K线"]
    XCTAssertTrue(heikin.waitForExistence(timeout: 8), "图表面板没开出来")
    heikin.tap()
    for key in ["span", "plotW", "mainH", "timeY", "bodyW", "spacing"] {
      XCTAssertEqual(try XCTUnwrap(info()[key] as? Double), try XCTUnwrap(original[key] as? Double),
                     accuracy: 0.001, "换成平均K线改变了\(key)")
    }
    shot("02-平均K线-尺寸保持")
    app.buttons["chart.candleKind.蜡烛"].tap()
    // 图表面板是配置页，选完不自己收；后面全是点图的动作，先把它收掉。
    app.closeChartPanel()
    XCTAssertTrue(wait { !heikin.exists }, "图表面板没收回去")
    let point = canvas.coordinate(withNormalizedOffset: CGVector(dx: 0.35, dy: 0.2))
    point.tap()
    XCTAssertTrue(wait { info()["crosshair"] as? Bool == true })
    shot("03-单击十字线")
    point.tap()
    XCTAssertTrue(wait { info()["crosshair"] as? Bool == false })
    // 「主轴允许翻转」开关 2026-09-28 收掉（收设置项 B 组）：双击价格轴直接翻，再双击翻回来。
    let axis = canvas.coordinate(withNormalizedOffset: CGVector(dx: 0.98, dy: 0.2))
    axis.doubleTap()
    XCTAssertTrue(wait { info()["inverted"] as? Bool == true }, "双击价格轴没翻：\(info())")
    axis.doubleTap()
    XCTAssertTrue(wait { info()["inverted"] as? Bool == false }, "再双击没翻回来")
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
    // 持仓量那一段搬去了 `testOpenInterestPaneCarriesRealDataAndTakesTheCrosshair`（审查 C.9）：
    // 它原来就长在这儿，前面还挂着一句「线路是 OKX 就跳过」。中途 skip 吞的不是那三行，
    // 是**整条用例的后半段**——底下横屏共用底座、iPad 横向窗口、退横屏不退画线，
    // 全都跟持仓量无关，却一条都跑不到，而汇总上只显示「已跳过」。
    point.tap()
    XCTAssertTrue(wait { info()["crosshair"] as? Bool == false }, "再点一下十字线该收走")
    let portraitWidth = try XCTUnwrap(info()["plotW"] as? Double)
    let portraitSpacing = try XCTUnwrap(info()["spacing"] as? Double)
    let portraitHeight = try XCTUnwrap(info()["height"] as? Double)
    // 底栏没有单独的「横屏」了：横屏是画线的工作台，点「分析」面板第一节的「画线」直接横过去（2026-09-28）。
    XCTAssertTrue(app.tapDrawEntry(), "分析面板里没有「画线」")
    if UIDevice.current.userInterfaceIdiom == .pad {
      // iPad windows can keep their orientation. Full chart mode must still open.
      XCTAssertTrue(wait { app.buttons["draw.finish"].exists &&
        (info()["height"] as? Double ?? 0) > portraitHeight + 80 })
    } else {
      XCTAssertTrue(wait { (info()["plotW"] as? Double ?? 0) > portraitWidth + 80 })
    }
    // 2026-10-05 起横屏有自己那份 K 线宽度（`landscapeBarSpacing`）：竖屏刚捏宽的那一下不带进横屏，
    // 横屏用的是它自己记着的那份（全新档案 = 出厂 4）。底座仍是同一张，只是宽度各记各的。
    let layoutProbe = app.descendants(matching: .any).matching(identifier: "layout.diagnostics").firstMatch
    func landStored() -> Double? {
      guard layoutProbe.exists, let text = layoutProbe.value as? String else { return nil }
      for pair in text.split(separator: ";") {
        let kv = pair.split(separator: "=", maxSplits: 1)
        if kv.count == 2, kv[0] == "landStored" { return Double(kv[1]) }
      }
      return nil
    }
    let landSpacing = landStored() ?? 4
    XCTAssertTrue(wait { abs((info()["spacing"] as? Double ?? 0) - landSpacing) < 0.001 },
                  "横屏没用自己那份 K 线宽度 \(landSpacing)：\(info())（竖屏 \(portraitSpacing)）")
    XCTAssertNotEqual(portraitSpacing, landSpacing, accuracy: 0.001, "竖屏捏宽之后横屏不该跟着变")
    shot("05-横屏共用底座")
    if UIDevice.current.userInterfaceIdiom == .pad {
      XCUIDevice.shared.orientation = .landscapeLeft
      XCTAssertTrue(wait { app.buttons["draw.finish"].isHittable && canvas.frame.height > 100 &&
        app.windows.firstMatch.frame.width > app.windows.firstMatch.frame.height })
      shot("06-iPad横向窗口")
    }
    // 画线进行中横屏侧栏整条收起（「画线 / 竖屏」和「完成」重复），出口是「完成」：
    // 点「画线」横过来的，完成后自动转回竖屏。
    XCTAssertFalse(app.buttons["land.exit"].exists, "画线进行中横屏侧栏还在")
    app.buttons["draw.finish"].tap()
    XCTAssertTrue(app.buttons["bottom.me"].waitForExistence(timeout: 10))
  }

  /// 持仓量副图：真数据到得了，点它出十字线且落在 OI 那一格。
  ///
  /// 审查 C.9：这一段原来嵌在 `testColdLaunchStylesAndChartInteractions` 中间，
  /// 拆出来单过，中途跳过就再也遮不住别的断言。
  ///
  /// 顺带把那句 `XCTSkipIf(market.source == "okx")` 也去掉了。行情线路只认设置里的
  /// 那一档、出厂是直连币安、全程没有任何自动切换（见设置里的「行情线路」），
  /// 而这条用例每次都给一个全新档案，所以线路必然是币安。不是币安就不是「这条用例
  /// 不适用」，是路由那一层出事了，该红。
  func testOpenInterestPaneCarriesRealDataAndTakesTheCrosshair() throws {
    let app = XCUIApplication()
    app.launchEnvironment["KANPAN_TEST_PROFILE"] = "1"
    app.launchEnvironment["KANPAN_CHART_DIAGNOSTICS"] = "1"
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
    XCTAssertEqual(app.staticTexts["market.source"].label, "binance",
                   "全新档案起步就不在直连币安上，持仓量本来就取不到——先修路由")
    XCTAssertEqual(info()["subs"] as? [String], ["VOL", "OI", "MACD"], "出厂三副图里没有持仓量")
    XCTAssertTrue(wait({ info()["oiReady"] as? Bool == true }, seconds: 45), "OI真实数据未到达")
    shot("01-持仓量与三副图")
    let plotW = try XCTUnwrap(info()["plotW"] as? Double)
    let oiPane = try XCTUnwrap((info()["panes"] as? [[String: Any]])?.first { $0["id"] as? String == "OI" })
    let oiY = try XCTUnwrap(oiPane["y"] as? Double) + (try XCTUnwrap(oiPane["h"] as? Double)) / 2
    canvas.coordinate(withNormalizedOffset: .zero).withOffset(CGVector(dx: plotW * 0.4, dy: oiY)).tap()
    XCTAssertTrue(wait { info()["crosshair"] as? Bool == true && info()["crossPane"] as? String == "OI" },
                  "点在持仓量那一格上没出十字线：\(info())")
    shot("02-副图十字线")
  }
}
