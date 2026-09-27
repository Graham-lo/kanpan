import XCTest

/// 条件提醒客户端（阶段 4b，`docs/条件提醒-协议-2026-09-27.md`）走一遍用户真的会走的路。
///
/// 1. 没登录：创建页的「条件」仍是原来那两段（价格达到 / 收盘穿过），不出条件提醒；
///    设置 › 通知多一行「品种上新与停牌下架」开关。
/// 2. 端到端（`KANPAN_E2E_CONDITION=1` 才跑，要等真行情，最长二十几分钟）：线上真后端注册一个 test_ 号、
///    在 BTCUSDT 上建「出现超过 1M 的挂单墙」、SOLUSDT 1 分钟上建「收盘站上 MA 5」→ 总表两行 →
///    服务端同步里两条都在 → 等真行情把它们判响（前台本机或服务端谁先判到谁响）→ 两条从服务端与总表里消失。
@MainActor final class ConditionAlertsUITests: XCTestCase {
  private let api = TestAccounts.api
  private let password = "Testpass2026"
  private var app: XCUIApplication!
  private var created: [String] = []
  private let profile = UUID().uuidString
  private var canvas: XCUIElement { app.otherElements["chart.canvas"] }
  private let shots = URL(fileURLWithPath: "/Users/mdd/zhk/kanpan/docs/acceptance/条件提醒-2026-09-27", isDirectory: true)

  override func setUp() async throws {
    continueAfterFailure = false
    XCUIDevice.shared.orientation = .portrait
    try? FileManager.default.createDirectory(at: shots, withIntermediateDirectories: true)
  }

  override func tearDown() async throws {
    if let app, app.state != .notRunning, app.state != .unknown { app.terminate() }
    for name in created { await TestAccounts.delete(name, password: password, api: api) }
  }

  // ------------------------------------------------------------ 用例

  func testSignedOutComposeKeepsOnlyPriceConditionsAndSettingsHasListingSwitch() throws {
    launch()
    XCTAssertTrue(openNewAlertFromChart(), "十字线上的「创建提醒」没开出创建页")
    XCTAssertTrue(app.buttons["alerts.new.condition.价格达到"].waitForExistence(timeout: 5),
                  "没登录时「条件」应当还是价格达到 / 收盘穿过两段")
    XCTAssertTrue(app.buttons["alerts.new.condition.收盘穿过"].exists)
    XCTAssertFalse(app.textFields["alerts.new.wall"].exists)
    shot("未登录-创建页只有价格条件")
    closeSheet()
    XCTAssertTrue(app.openSettingsFromMe(), "「我的 › 设置」没推出设置页")
    let toggle = app.switches["alerts.listing"].exists ? app.switches["alerts.listing"] : app.buttons["alerts.listing"]
    for _ in 0..<8 where !(toggle.exists && toggle.isHittable) { app.swipeUp(velocity: .slow) }
    XCTAssertTrue(toggle.exists && toggle.isHittable, "设置 › 通知里没有「品种上新与停牌下架」开关")
    XCTAssertTrue(app.staticTexts["品种上新与停牌下架"].exists)
    let before = toggle.value as? String
    toggle.tap()
    XCTAssertTrue(wait(seconds: 5) { (toggle.value as? String) != before }, "开关点了没变：\(before ?? "nil")")
    shot("设置-通知-品种上新与停牌下架")
  }

  func testConditionAlertsSyncFireAndVanish() async throws {
    try XCTSkipUnless(ProcessInfo.processInfo.environment["KANPAN_E2E_CONDITION"] == "1",
                      "端到端要等真行情，给 KANPAN_E2E_CONDITION=1 才跑（未执行，不等于通过）")
    // 1 分钟 MA5 站上要等真行情，首跑实测十分钟才等到一次；默认十分钟的执行时限不够。
    executionTimeAllowance = 30 * 60
    let name = try await registerOverHTTP()
    launch()
    login(name)

    // BTCUSDT：出现超过 1M 的挂单墙。
    XCTAssertTrue(openNewAlertFromChart(), "BTC：没开出创建页")
    pick(kind: "wall")
    let wall = app.textFields["alerts.new.wall"]
    XCTAssertTrue(wall.waitForExistence(timeout: 5), "选了大单挂单墙没换出金额那一格")
    replace(wall, with: "1M")
    dismissKeyboard()
    shot("BTC-创建-大单墙1M")
    create("BTC 大单墙")

    // SOLUSDT 1 分钟：收盘站上 MA 5。重开一次 app 落到 SOL（登录与档案都留着）。
    app.terminate()
    launch(link: "hkline://symbol/binance/usd_m/SOLUSDT?interval=1m")
    XCTAssertTrue(openNewAlertFromChart(), "SOL：没开出创建页")
    let symbol = app.descendants(matching: .any).matching(identifier: "alerts.new.symbol").firstMatch
    XCTAssertTrue(symbol.waitForExistence(timeout: 5) && symbol.label.contains("SOL"),
                  "深链没落到 SOLUSDT：创建页品种是 \(symbol.label)")
    pick(kind: "ma")
    let interval = app.buttons["alerts.new.interval"]
    XCTAssertTrue(interval.waitForExistence(timeout: 5), "选了均线没换出周期那一格")
    XCTAssertTrue(interval.label.contains("1 分钟"), "周期没默认成图上那一档：\(interval.label)")
    let length = app.textFields["alerts.new.length"]
    XCTAssertTrue(length.exists)
    XCTAssertEqual(length.value as? String, "10", "均线没默认成主图第一条 MA")
    replace(length, with: "5")
    dismissKeyboard()
    app.buttons["alerts.new.side.站上"].tap()
    shot("SOL-创建-1分钟站上MA5")
    create("SOL 均线")

    XCTAssertTrue(openAlertsPage(), "总表没开出来")
    let wallRow = labelled("出现超过 1M 的挂单墙")
    let maRow = labelled("1m 收盘站上 MA 5")
    XCTAssertTrue(wallRow.waitForExistence(timeout: 8), "总表里没有「出现超过 1M 的挂单墙」")
    XCTAssertTrue(maRow.exists, "总表里没有「1m 收盘站上 MA 5」")
    XCTAssertTrue(app.descendants(matching: .any)["alerts.section.price"].exists, "条件提醒没归在「价格提醒」那一段")
    shot("总表-两条条件提醒")

    // 服务端：两条都同步上去了。
    let token = try await loginOverHTTP(name)
    var active: [[String: Any]] = []
    for _ in 0..<40 {
      active = try await conditionAlerts(token: token)
      if active.count == 2 { break }
      try await Task.sleep(for: .seconds(3))
    }
    XCTAssertEqual(active.count, 2, "服务端同步里没见到两条条件提醒：\(active)")
    let rules = active.compactMap { ($0["rule"] as? [String: Any])?["type"] as? String }.sorted()
    XCTAssertEqual(rules, ["maCross", "orderflowWall"])
    print("条件提醒端到端：服务端已收到 \(active.map { "\($0["title"] ?? "")" })")

    // 等真行情判响：两条都从服务端消失（响过就删）或状态不再是 active。
    let started = Date()
    var gone: [String: TimeInterval] = [:]
    var lastCount = 2
    while Date().timeIntervalSince(started) < 25 * 60 {
      let now = try await conditionAlerts(token: token)
      let live = Set(now.filter { ($0["status"] as? String) == "active" }
        .compactMap { ($0["rule"] as? [String: Any])?["type"] as? String })
      for type in ["maCross", "orderflowWall"] where !live.contains(type) && gone[type] == nil {
        gone[type] = Date().timeIntervalSince(started)
        print("条件提醒端到端：\(type) 已判响，用时 \(Int(gone[type]!)) 秒；那一刻服务端 = \(now)")
      }
      if live.count < lastCount { shot("触发-\(gone.count)条"); lastCount = live.count }
      if live.isEmpty { break }
      try await Task.sleep(for: .seconds(15))
    }
    XCTAssertEqual(gone.count, 2, "25 分钟内没把两条都判响：已响 \(gone)")

    // 总表：两行都消失（服务端判响的，回一次前台同步下来）。
    if !wait(seconds: 20, { !wallRow.exists && !maRow.exists }) {
      XCUIDevice.shared.press(.home)
      try await Task.sleep(for: .seconds(2))
      app.activate()
    }
    XCTAssertTrue(wait(seconds: 60) { !wallRow.exists && !maRow.exists }, "判响之后总表里还挂着")
    shot("总表-触发后两条都消失")
  }

  // ------------------------------------------------------------ 小工具

  private func launch(link: String? = nil) {
    app = XCUIApplication()
    app.launchEnvironment["KANPAN_TEST_PROFILE"] = "1"
    app.launchEnvironment["KANPAN_PERSISTENCE_PROFILE"] = profile
    app.launchEnvironment["KANPAN_ACCOUNT_API_URL"] = api
    app.launchEnvironment["KANPAN_CHART_DIAGNOSTICS"] = "1"
    app.launchEnvironment["KANPAN_TEST_TOAST_SECONDS"] = "6"
    app.launchEnvironment["KANPAN_TEST_INTERVAL"] = "1m"
    if let link { app.launchEnvironment["KANPAN_TEST_DEEPLINK"] = link }
    app.launch()
    let chartTab = app.buttons["bottom.chart"]
    if chartTab.waitForExistence(timeout: 5), !canvas.exists { chartTab.tap() }
    XCTAssertTrue(canvas.waitForExistence(timeout: 30), "K 线画布没出来")
    XCTAssertTrue(wait(seconds: 60) { (self.info()["bars"] as? Int ?? 0) >= 64 }, "K 线没拿到数据：\(info())")
  }

  private func login(_ name: String) {
    XCTAssertTrue(app.openAccountFromMe(), "「我的 › 账号」没推出账号页")
    let username = app.textFields["account.email"]
    XCTAssertTrue(username.waitForExistence(timeout: 10)); username.tap(); username.typeText(name)
    let secure = app.secureTextFields["account.password"]
    XCTAssertTrue(secure.waitForExistence(timeout: 5)); secure.tap()
    if app.buttons["GenerateStrongPasswordButton"].waitForExistence(timeout: 2) { app.buttons["xmark"].tap() }
    for character in password { secure.typeText(String(character)) }
    app.buttons["account.submit"].tap()
    XCTAssertTrue(wait(seconds: 45) { !self.app.accountView.exists }, "登录 \(name) 没闭合账号页")
    let chartTab = app.buttons["bottom.chart"]
    XCTAssertTrue(chartTab.waitForExistence(timeout: 10)); chartTab.tap()
    XCTAssertTrue(canvas.waitForExistence(timeout: 15), "登录后回不到行情页")
  }

  private func labelled(_ text: String) -> XCUIElement {
    app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", text)).firstMatch
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

  private func shot(_ name: String) {
    let screenshot = XCUIScreen.main.screenshot()
    let a = XCTAttachment(screenshot: screenshot); a.name = name
    a.lifetime = .keepAlways; add(a)
    try? screenshot.pngRepresentation.write(to: shots.appendingPathComponent("iPhone16Pro-" + name + ".png"))
  }

  private var alertsPage: XCUIElement { app.descendants(matching: .any).matching(identifier: "alerts.page").firstMatch }
  private var newAlertPage: XCUIElement { app.descendants(matching: .any).matching(identifier: "alerts.new.page").firstMatch }

  private func selectACandle() -> Bool {
    guard let mainH = info()["mainH"] as? Double, let plotW = info()["plotW"] as? Double else { return false }
    let scale = canvas.frame.height / max(1, info()["height"] as? Double ?? canvas.frame.height)
    canvas.coordinate(withNormalizedOffset: .zero)
      .withOffset(CGVector(dx: plotW * scale * 0.8, dy: mainH * scale * 0.78)).tap()
    return wait(seconds: 8) { self.info()["crosshair"] as? Bool == true }
  }

  @discardableResult private func openNewAlertFromChart() -> Bool {
    for _ in 0..<3 {
      if newAlertPage.exists { return true }
      if info()["crosshair"] as? Bool != true, !selectACandle() { continue }
      let chip = app.buttons["chart.crosshair.alert"]
      guard chip.waitForExistence(timeout: 5) else { continue }
      chip.tap()
      if newAlertPage.waitForExistence(timeout: 8) { return true }
    }
    return false
  }

  @discardableResult private func openAlertsPage() -> Bool {
    guard openNewAlertFromChart() else { return false }
    let all = app.buttons["alerts.all"]
    guard all.waitForExistence(timeout: 5) else { return false }
    all.tap()
    return alertsPage.waitForExistence(timeout: 8)
  }

  private func closeSheet() {
    for _ in 0..<4 {
      if !alertsPage.exists && !newAlertPage.exists { return }
      let close = app.buttons["panel.done"]
      if close.waitForExistence(timeout: 2), close.isHittable {
        close.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
      } else if app.navigationBars.buttons.firstMatch.exists {
        app.navigationBars.buttons.firstMatch.tap()
      }
      _ = wait(seconds: 5) { !self.alertsPage.exists && !self.newAlertPage.exists }
    }
  }

  /// 「条件」菜单里挑一样（登录后六样放不下一段，是个菜单）。
  private func pick(kind: String) {
    let menu = app.buttons["alerts.new.condition"]
    XCTAssertTrue(menu.waitForExistence(timeout: 5), "登录后「条件」没变成菜单")
    menu.tap()
    let item = app.buttons["alerts.new.kind." + kind]
    XCTAssertTrue(item.waitForExistence(timeout: 5), "条件菜单里没有 \(kind)")
    item.tap()
  }

  private func replace(_ field: XCUIElement, with text: String) {
    field.coordinate(withNormalizedOffset: CGVector(dx: 0.97, dy: 0.5)).tap()
    let old = (field.value as? String) ?? ""
    field.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: old.count + 2) + text)
  }

  private func dismissKeyboard() {
    guard app.keyboards.firstMatch.exists else { return }
    let done = app.buttons["完成"].firstMatch
    if done.exists { done.tap() } else { app.keyboards.buttons["Done"].firstMatch.tap() }
    _ = app.keyboards.firstMatch.waitForNonExistence(timeout: 3)
  }

  private func create(_ what: String) {
    let add = app.buttons["alerts.new.create"]
    XCTAssertTrue(add.waitForExistence(timeout: 5) && add.isEnabled, "\(what)：「创建提醒」按不下去")
    dismissKeyboard()
    for _ in 0..<3 where !add.isHittable { newAlertPage.swipeUp() }
    add.tap()
    XCTAssertTrue(newAlertPage.waitForNonExistence(timeout: 8), "\(what)：建完新建页没收起")
  }

  // ------------------------------------------------------------ 线上后端

  private func device() -> [String: String] {
    ["id": UUID().uuidString, "name": "条件提醒验收", "secret": UUID().uuidString + UUID().uuidString, "kind": "desktop"]
  }

  private func registerOverHTTP() async throws -> String {
    let name = "test_" + UUID().uuidString.replacingOccurrences(of: "-", with: "").prefix(10).lowercased()
    created.append(name)
    _ = try await call("v1/auth/register", method: "POST", body: ["username": name, "password": password, "device": device()])
    return name
  }

  private func loginOverHTTP(_ name: String) async throws -> String {
    let login = try await call("v1/auth/login", method: "POST", body: ["username": name, "password": password, "device": device()])
    return try XCTUnwrap((login as? [String: Any])?["accessToken"] as? String)
  }

  /// 服务端同步里这个号的条件提醒（body）。删掉的不在 bootstrap 里。
  private func conditionAlerts(token: String) async throws -> [[String: Any]] {
    let sync = try await call("v1/sync/bootstrap?collection=alerts", token: token) as? [String: Any] ?? [:]
    return (sync["objects"] as? [[String: Any]] ?? []).compactMap { $0["body"] as? [String: Any] }
      .filter { $0["kind"] as? String == "condition" }
  }

  private func call(_ path: String, method: String = "GET", body: [String: Any]? = nil, token: String? = nil) async throws -> Any? {
    var request = URLRequest(url: URL(string: api + "/" + path)!)
    request.httpMethod = method; request.timeoutInterval = 30
    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
    if let token { request.setValue("Bearer " + token, forHTTPHeaderField: "Authorization") }
    if let body { request.httpBody = try JSONSerialization.data(withJSONObject: body) }
    let (data, response) = try await URLSession.shared.data(for: request)
    let code = (response as! HTTPURLResponse).statusCode
    XCTAssertTrue((200..<300).contains(code), "接口失败 \(path)：\(code) \(String(data: data, encoding: .utf8) ?? "")")
    return (try JSONSerialization.jsonObject(with: data) as? [String: Any])?["data"]
  }
}
