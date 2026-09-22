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
    app.buttons["panel.done"].tap()
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
      app.buttons["panel.done"].tap()
      XCTAssertTrue(app.buttons["alerts.sound.open"].waitForExistence(timeout: 10))
      app.buttons["panel.done"].tap()
    }
  }
}
