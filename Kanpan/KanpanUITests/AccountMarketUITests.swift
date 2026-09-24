import XCTest

@MainActor final class AccountMarketUITests: XCTestCase {
  /// 本条用例注册的号：正常路径在界面上注销，中途失败时收尾兜底删掉，不留在线上。
  private var createdAccount: String?
  override func tearDown() async throws {
    if let name = createdAccount { await TestAccounts.delete(name, password: "Testpass2026") }
  }

  func testBinanceStartupThroughExistingNetwork() throws {
    continueAfterFailure = false
    let app = XCUIApplication()
    app.launchEnvironment["KANPAN_TEST_PROFILE"] = "1"
    app.launchEnvironment["KANPAN_CHART_DIAGNOSTICS"] = "1"
    app.launchEnvironment["KANPAN_TEST_BINANCE_REST_DOWN"] = "0"
    app.launchEnvironment["KANPAN_LOG"] = "1"
    let start = Date()
    app.launch()
    defer {
      let a = XCTAttachment(screenshot: app.screenshot()); a.lifetime = .keepAlways; add(a)
      app.terminate()
    }
    let canvas = app.otherElements["chart.canvas"]
    XCTAssertTrue(canvas.waitForExistence(timeout: 20))
    let ready = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
      guard let raw = canvas.value as? String, let data = raw.data(using: .utf8),
            let info = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return false }
      return (info["bars"] as? Int ?? 0) >= 256 && app.staticTexts["market.source"].label == "binance"
        && app.staticTexts["market.source"].value as? String == "live"
    }, object: nil)
    XCTAssertEqual(XCTWaiter.wait(for: [ready], timeout: 25), .completed, "source=\(app.staticTexts["market.source"].label) status=\(String(describing: app.staticTexts["market.source"].value)) network=\(app.staticTexts["market.network"].label)")
    let evidence = XCTAttachment(string: "Existing phone/Mac gateway; Binance chart and live stream ready in \(Date().timeIntervalSince(start)) seconds, including app launch. No simulated failure.")
    evidence.name = "正常网络首屏"; evidence.lifetime = .keepAlways; add(evidence)
    let shot = XCTAttachment(screenshot: app.screenshot()); shot.lifetime = .keepAlways; add(shot)
  }

  func testOKXHistoryAndUsernameRegistration() throws {
    continueAfterFailure = false
    let app = XCUIApplication()
    app.launchEnvironment["KANPAN_TEST_PROFILE"] = "1"
    app.launchEnvironment["KANPAN_PERSISTENCE_PROFILE"] = UUID().uuidString
    app.launchEnvironment["KANPAN_CHART_DIAGNOSTICS"] = "1"
    app.launchEnvironment["KANPAN_LOG"] = "1"
    // 线路是用户定的，不再有「币安坏了自动退 OKX」：这条用例验的是「网关」线路，
    // 从网关拿 OKX 的历史与实时。REST_DOWN 只是把币安直连彻底封死，证明没有偷偷走它。
    app.launchEnvironment["KANPAN_TEST_ROUTE_POLICY"] = "gateway"
    app.launchEnvironment["KANPAN_TEST_BINANCE_REST_DOWN"] = "1"
    app.launchEnvironment["KANPAN_ACCOUNT_API_URL"] = "https://kanpan.107-174-172-10.sslip.io"
    app.launch()
    defer {
      let a = XCTAttachment(screenshot: app.screenshot()); a.lifetime = .keepAlways; add(a)
      app.terminate()
    }
    let canvas = app.otherElements["chart.canvas"]
    func info() -> [String: Any] {
      guard let v = canvas.value as? String, let d = v.data(using: .utf8) else { return [:] }
      return (try? JSONSerialization.jsonObject(with: d) as? [String: Any]) ?? [:]
    }
    func wait(_ seconds: Double = 60, _ condition: @escaping () -> Bool) -> Bool {
      XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in condition() }, object: nil)], timeout: seconds) == .completed
    }
    XCTAssertTrue(canvas.waitForExistence(timeout: 30))
    XCTAssertTrue(wait { app.staticTexts["market.source"].label == "okx" && (info()["bars"] as? Int ?? 0) >= 300 })
    if (info()["bars"] as? Int ?? 0) <= 300 {
      for _ in 0..<8 {
        let from = canvas.coordinate(withNormalizedOffset: .zero).withOffset(CGVector(dx: 40, dy: 120))
        let to = canvas.coordinate(withNormalizedOffset: .zero).withOffset(CGVector(dx: 310, dy: 120))
        from.press(forDuration: 0.05, thenDragTo: to)
      }
    }
    XCTAssertTrue(wait { (info()["bars"] as? Int ?? 0) > 300 }, "OKX history must prepend: \(info()) network=\(app.staticTexts["market.network"].label)")
    let shot = XCTAttachment(screenshot: app.screenshot()); shot.name = "网关线路-OKX历史"; shot.lifetime = .keepAlways; add(shot)
    app.buttons["bottom.settings"].tap()
    app.buttons["settings.account"].tap()
    XCTAssertTrue(app.buttons["注册"].waitForExistence(timeout: 5)); app.buttons["注册"].tap()
    let name = "test_" + UUID().uuidString.replacingOccurrences(of: "-", with: "").prefix(12)
    createdAccount = String(name)
    app.textFields["account.email"].tap(); app.textFields["account.email"].typeText(String(name))
    app.secureTextFields["account.password"].tap()
    if app.buttons["GenerateStrongPasswordButton"].waitForExistence(timeout: 2) { app.buttons["xmark"].tap() }
    XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 5))
    for character in "Testpass2026" { app.secureTextFields["account.password"].typeText(String(character)) }
    app.buttons["account.submit"].tap()
    XCTAssertTrue(wait(25) { !app.accountView.exists }, app.debugDescription)
    app.terminate(); app.launch()
    XCTAssertTrue(canvas.waitForExistence(timeout: 30))
    app.buttons["bottom.settings"].tap(); app.buttons["settings.account"].tap()
    XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label ENDSWITH %@", String(name).lowercased())).firstMatch.waitForExistence(timeout: 10), "Account survives restart")
    let accountShot = XCTAttachment(screenshot: app.screenshot()); accountShot.name = "用户名注册持久化"; accountShot.lifetime = .keepAlways; add(accountShot)
    app.buttons["注销账号"].tap()
    app.secureTextFields["account.password"].tap()
    if app.buttons["GenerateStrongPasswordButton"].waitForExistence(timeout: 2) { app.buttons["xmark"].tap() }
    XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 5))
    for character in "Testpass2026" { app.secureTextFields["account.password"].typeText(String(character)) }
    app.buttons["account.submit"].tap()
    XCTAssertTrue(wait(20) { !app.accountView.exists })
  }
}
