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
    for id in ["stout", "indigo", "glow", "airy", "brick", "needle", "pill", "paper", "outline", "bone", "dense"] {
      app.buttons["bottom.style"].tap()
      let card = app.buttons["style.card." + id]
      let scroll = app.scrollViews["panel.content"]
      for _ in 0..<8 {
        if card.exists, card.isHittable,
           scroll.frame.insetBy(dx: 0, dy: 8).contains(card.frame) { break }
        scroll.swipeUp()
      }
      XCTAssertTrue(card.waitForExistence(timeout: 8)); card.tap()
      XCTAssertTrue(wait { info()["style"] as? String == id }, "风格未切换到\(id)，状态：\(info())")
      for key in ["span", "plotW", "mainH", "timeY", "bodyW", "spacing"] {
        XCTAssertEqual(try XCTUnwrap(info()[key] as? Double), try XCTUnwrap(original[key] as? Double),
                       accuracy: 0.001, "切风格\(id)改变了\(key)")
      }
    }
    shot("02-原有风格-尺寸保持")
    app.buttons["bottom.style"].tap()
    app.buttons["style.card.aicoin"].tap()
    XCTAssertTrue(wait { info()["style"] as? String == "aicoin" })
    let point = canvas.coordinate(withNormalizedOffset: CGVector(dx: 0.35, dy: 0.2))
    point.tap()
    XCTAssertTrue(wait { info()["crosshair"] as? Bool == true })
    shot("03-单击十字线")
    point.tap()
    XCTAssertTrue(wait { info()["crosshair"] as? Bool == false })
    let axis = canvas.coordinate(withNormalizedOffset: CGVector(dx: 0.98, dy: 0.2))
    axis.tap()
    XCTAssertTrue(wait { info()["inverted"] as? Bool == true })
    axis.tap()
    XCTAssertTrue(wait { info()["inverted"] as? Bool == false })
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
    XCTAssertTrue(wait({ info()["oiReady"] as? Bool == true }, seconds: 45), "OI真实数据未到达")
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
    app.buttons["bottom.landscape"].tap()
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
    XCTAssertTrue(app.buttons["bottom.style"].waitForExistence(timeout: 10))
  }
}
