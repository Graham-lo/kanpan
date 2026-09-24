import XCTest

@MainActor
final class AlertSoundUITests: XCTestCase {
  private var app: XCUIApplication!

  override func setUp() async throws {
    continueAfterFailure = false
    executionTimeAllowance = 240
    XCUIDevice.shared.orientation = .portrait
    app = XCUIApplication()
    app.launchEnvironment["KANPAN_TEST_PROFILE"] = "1"
    app.launchEnvironment["KANPAN_PERSISTENCE_PROFILE"] = UUID().uuidString
    if name.contains("Notification") {
      app.launchEnvironment["KANPAN_CHART_DIAGNOSTICS"] = "1"
      app.launchEnvironment["KANPAN_TEST_ROUTE_POLICY"] = "gateway"
    }
    app.launch()
    XCTAssertTrue(app.buttons["bottom.settings"].waitForExistence(timeout: 30))
    app.buttons["bottom.settings"].tap()
  }

  override func tearDown() async throws { app.terminate() }

  private func openSounds() {
    let alerts = app.buttons["settings.alerts"]
    XCTAssertTrue(alerts.waitForExistence(timeout: 10))
    if !alerts.isHittable { app.swipeUp() }
    alerts.tap()
    let sounds = app.buttons["alerts.sound.open"]
    XCTAssertTrue(sounds.waitForExistence(timeout: 10))
    sounds.tap()
    XCTAssertTrue(app.buttons["alerts.sound.default"].waitForExistence(timeout: 10))
  }

  /// 铃声页是提醒总表里推进去的一层，走系统导航栏（2026-09-24 UI 整改 P1b）：
  /// 回总表按导航栏左上那颗系统返回钮，`panel.done` 现在只是总表的「关闭」。
  private func backFromSounds() {
    let back = app.navigationBars["提醒铃声"].buttons.element(boundBy: 0)
    XCTAssertTrue(back.waitForExistence(timeout: 5), "铃声页没有系统返回钮")
    back.tap()
  }

  private func shot(_ name: String) {
    let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
    attachment.name = name
    attachment.lifetime = .keepAlways
    add(attachment)
  }

  func testFourSoundsAndRestart() {
    openSounds()
    for sound in ["default", "crisp", "electronic", "glass"] {
      app.buttons["alerts.sound." + sound].tap()
      for other in ["default", "crisp", "electronic", "glass"] {
        XCTAssertEqual(app.buttons["alerts.sound." + other].value as? String, other == sound ? "已选" : "未选")
      }
      shot("铃声-" + sound)
    }
    backFromSounds()
    XCTAssertEqual(app.buttons["alerts.sound.open"].value as? String, "玻璃")
    shot("提醒总表-玻璃")
    app.terminate()
    app.launch()
    XCTAssertTrue(app.buttons["bottom.settings"].waitForExistence(timeout: 30))
    app.buttons["bottom.settings"].tap()
    openSounds()
    XCTAssertEqual(app.buttons["alerts.sound.glass"].value as? String, "已选")
    shot("重启-玻璃")
  }

  func testThreeSkins() {
    for skin in ["sage", "terra", "classic"] {
      let button = app.buttons["display.theme." + skin]
      XCTAssertTrue(button.waitForExistence(timeout: 10))
      if !button.isHittable { app.swipeDown() }
      button.tap()
      XCTAssertEqual(button.value as? String, "已选")
      openSounds()
      app.buttons["alerts.sound.glass"].tap()
      shot("铃声皮肤-" + skin)
      backFromSounds()
      XCTAssertTrue(app.buttons["alerts.sound.open"].waitForExistence(timeout: 10))
      app.buttons["panel.done"].tap()
    }
  }
  func testNotificationPermissionAndDefaultPreview() throws {
    let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
    app.buttons["bottom.chart"].tap()
    let canvas = app.otherElements["chart.canvas"]
    XCTAssertTrue(canvas.waitForExistence(timeout: 30))
    XCTAssertTrue(XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
      guard let raw = canvas.value as? String, let data = raw.data(using: .utf8),
            let info = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return false }
      return (info["bars"] as? Int ?? 0) >= 64
    }, object: nil)], timeout: 60) == .completed)
    XCTAssertTrue(app.enterDrawingInPortrait())
    let point = canvas.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.2))
    let horizontal = app.buttons["draw.hline"]
    XCTAssertTrue(horizontal.waitForExistence(timeout: 10))
    horizontal.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
    point.tap()
    // 画完线它自动选中，选中栏左边那颗「跌到 / 涨到 X 叫我」就是加提醒的唯一入口。
    let chip = app.buttons["alert.line"]
    XCTAssertTrue(chip.waitForExistence(timeout: 8))
    chip.tap()
    let allow = springboard.alerts.buttons.matching(NSPredicate(format: "label IN %@", ["允许", "Allow"])).firstMatch
    XCTAssertTrue(allow.waitForExistence(timeout: 10), "新安装后应通过正常加入提醒流程申请通知权限")
    shot("系统通知授权")
    allow.tap()
    let finish = app.buttons["draw.finish"]
    if finish.exists { finish.tap() }
    app.buttons["bottom.settings"].tap()
    openSounds()
    app.buttons["alerts.sound.default"].tap()
    XCTAssertEqual(app.buttons["alerts.sound.default"].value as? String, "已选")
    shot("通知授权后-默认试听")
    app.buttons["alerts.sound.glass"].tap()
    shot("推送验收-玻璃")
  }
}
