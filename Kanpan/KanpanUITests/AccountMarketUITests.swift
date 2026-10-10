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

  func testGatewayHistoryAndUsernameRegistration() throws {
    continueAfterFailure = false
    let app = XCUIApplication()
    app.launchEnvironment["KANPAN_TEST_PROFILE"] = "1"
    app.launchEnvironment["KANPAN_PERSISTENCE_PROFILE"] = UUID().uuidString
    app.launchEnvironment["KANPAN_CHART_DIAGNOSTICS"] = "1"
    app.launchEnvironment["KANPAN_LOG"] = "1"
    // 线路是用户定的，没有自动切换，也没有替身（OKX 替身 2026-10-08 起删了）：这条用例验的是「网关」线路，
    // 币安品种照样是币安自家的数——REST 经 kanpan-api `/v1/market/raw/...?source=binance` 原样透传，
    // 推送走 Python 网关 `/market/stream`。证明走的是网关看链路日志：K 线请求记成「网关 <主机> /fapi/v1/klines」，
    // 且没有一笔「直连 fapi.binance.com」。（`KANPAN_TEST_BINANCE_REST_DOWN=1` 会连网关透传一起掐断，不能再开。）
    app.launchEnvironment["KANPAN_TEST_ROUTE_POLICY"] = "gateway"
    app.launchEnvironment["KANPAN_TEST_BINANCE_REST_DOWN"] = "0"
    app.launchEnvironment["KANPAN_ACCOUNT_API_URL"] = "https://kanpan.43-160-232-253.sslip.io"
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
    let network = app.staticTexts["market.network"]
    XCTAssertTrue(wait {
      app.staticTexts["market.source"].label == "binance" && (info()["bars"] as? Int ?? 0) >= 300
        && network.label.contains("/fapi/v1/klines HTTP 200") && network.label.contains("网关 ")
    }, "网关线路没出币安的图：source=\(app.staticTexts["market.source"].label) \(info()) network=\(network.label)")
    XCTAssertFalse(network.label.contains("直连 fapi.binance.com"), "网关线路不该直连币安：\(network.label)")
    if (info()["bars"] as? Int ?? 0) <= 300 {
      for _ in 0..<8 {
        let from = canvas.coordinate(withNormalizedOffset: .zero).withOffset(CGVector(dx: 40, dy: 120))
        let to = canvas.coordinate(withNormalizedOffset: .zero).withOffset(CGVector(dx: 310, dy: 120))
        from.press(forDuration: 0.05, thenDragTo: to)
      }
    }
    XCTAssertTrue(wait { (info()["bars"] as? Int ?? 0) > 300 }, "网关透传的币安历史必须能往前接：\(info()) network=\(app.staticTexts["market.network"].label)")
    let shot = XCTAttachment(screenshot: app.screenshot()); shot.name = "网关线路-币安历史"; shot.lifetime = .keepAlways; add(shot)
    // 账号卡 2026-09-27 起在「我的」页最上面（原来是「设置 › 账号」）。
    XCTAssertTrue(app.openAccountFromMe(), "「我的 › 账号」没推出账号页")
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
    XCTAssertTrue(app.openAccountFromMe(), "重启后「我的 › 账号」没推出账号页")
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
