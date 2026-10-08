import XCTest

// ============================================================ 顶栏铃铛 → 「提醒」表（列表 | 日志），2026-10-05
//
// 照 TradingView 手机版：顶栏第二颗是铃铛，角上一颗这只品种还没触发的提醒数；点开是一张「提醒」表，
// 顶上分段「列表 | 日志」。列表把图上这只置顶成一组、底部一颗通栏「创建提醒」（品种锁定、价格预填最新价）；
// 日志是服务端那份「响过的提醒」，没登录只有一句「登录后可查看」。
//
// 取证那条（`testEvidenceShots`）把验收截图落到
// `docs/acceptance/顶栏对比与提醒-2026-10-05/<机型>-<页>.png`，16 Pro 与 17 Pro Max 各跑一遍；
// 「暂无记录」要登录，用的是这次在线上后端现造的 qa_ 账号，做完就注销。
@MainActor
final class TopBarAlertsUITests: KanpanUICase {
  private let api = "https://kanpan.43-160-232-253.sslip.io"
  private let profile = UUID().uuidString
  private var account: (name: String, password: String)?

  override var extraLaunchEnvironment: [String: String] {
    var env = ["KANPAN_PERSISTENCE_PROFILE": profile, "KANPAN_TEST_TOAST_SECONDS": "4",
               "KANPAN_ACCOUNT_API_URL": api]
    if name.contains("Evidence") {
      env["KANPAN_TEST_COMPARE_SYMBOLS"] = ["ETHUSDT", "SOLUSDT"].map(testInstrumentKey).joined(separator: ",")
      env["KANPAN_TEST_TOAST_SECONDS"] = "1"   // 截图里不留「已加提醒」那条提示
    }
    return env
  }

  private static let outDir = URL(
    fileURLWithPath: "/Users/mdd/zhk/kanpan/docs/acceptance/顶栏对比与提醒-2026-10-05", isDirectory: true)

  override func setUp() async throws {
    XCUIDevice.shared.orientation = .portrait
    try await super.setUp()
  }

  override func tearDown() async throws {
    app?.terminate()
    if let account { await closeAccount(account.name, account.password) }
    try await super.tearDown()
  }

  // ------------------------------------------------------------ 小工具

  private var bell: XCUIElement { app.buttons[Ids.topAlerts] }
  private var hubTab: XCUIElement { app.segmentedControls["alerts.hub.tab"] }
  private var create: XCUIElement { app.buttons["alerts.hub.create"] }

  private var deviceTag: String {
    switch Int(app.windows.firstMatch.frame.width.rounded()) {
    case 402: "iPhone16Pro"
    case 440: "iPhone17ProMax"
    case 430: "iPhone15ProMax"
    case let w: "宽\(w)"
    }
  }

  private func shot(_ page: String) {
    RunLoop.main.run(until: Date().addingTimeInterval(0.6))
    let screenshot = XCUIScreen.main.screenshot()
    let name = "\(deviceTag)-\(page)"
    let a = XCTAttachment(screenshot: screenshot); a.name = name; a.lifetime = .keepAlways; add(a)
    try? FileManager.default.createDirectory(at: Self.outDir, withIntermediateDirectories: true)
    try? screenshot.pngRepresentation.write(to: Self.outDir.appendingPathComponent(name + ".png"))
  }

  private func openHub(file: StaticString = #filePath, line: UInt = #line) {
    XCTAssertTrue(bell.waitForExistence(timeout: Self.short), "顶栏没有铃铛", file: file, line: line)
    bell.tap()
    XCTAssertTrue(hubTab.waitForExistence(timeout: Self.short), "铃铛没开出「提醒」表", file: file, line: line)
  }

  private func pick(_ segment: String) {
    let button = hubTab.buttons[segment]
    XCTAssertTrue(button.waitForExistence(timeout: Self.short), "分段上没有「\(segment)」")
    button.tap()
    XCTAssertTrue(waitUntil(timeout: Self.short) { button.isSelected }, "没切到「\(segment)」")
  }

  private func closeHub() {
    let done = app.buttons[Ids.panelDone].firstMatch
    XCTAssertTrue(done.waitForExistence(timeout: Self.short), "「提醒」表没有关闭")
    done.tap()
    XCTAssertTrue(waitUntil(timeout: Self.short) { !self.hubTab.exists }, "「提醒」表没收起")
  }

  private func replace(_ field: XCUIElement, with text: String) {
    field.coordinate(withNormalizedOffset: CGVector(dx: 0.97, dy: 0.5)).tap()
    let old = (field.value as? String) ?? ""
    field.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: old.count + 2) + text)
  }

  /// 「提醒」表列表页底部「创建提醒」→ 创建页（品种锁定为图上那只、价预填）→ 改价 → 建好退回列表。
  private func createFromHub(price: String, file: StaticString = #filePath, line: UInt = #line) {
    XCTAssertTrue(create.waitForExistence(timeout: Self.short), "列表页底部没有「创建提醒」", file: file, line: line)
    create.tap()
    let field = app.textFields["alerts.new.price"]
    XCTAssertTrue(field.waitForExistence(timeout: Self.short), "没推出创建页", file: file, line: line)
    replace(field, with: price)
    if app.keyboards.firstMatch.exists {
      app.buttons["完成"].firstMatch.tap()
      _ = app.keyboards.firstMatch.waitForNonExistence(timeout: 3)
    }
    let add = app.buttons["alerts.new.create"]
    XCTAssertTrue(waitUntil(timeout: Self.short) { add.isEnabled }, "创建页主按钮按不下去", file: file, line: line)
    for _ in 0..<3 where !add.isHittable { app.otherElements["alerts.new.page"].swipeUp() }
    add.tap()
    XCTAssertTrue(create.waitForExistence(timeout: Self.short), "建好没退回「提醒」表的列表页", file: file, line: line)
  }

  // ------------------------------------------------------------ 用例

  /// 铃铛 → 「提醒」表：列表页置顶这只（空的时候一行「暂无提醒」）→ 日志（没登录：登录后可查看）
  /// → 列表底部「创建提醒」：品种锁定为图上那只、价格预填 → 建两条，置顶那组出现、关表后铃角标是 2。
  func testBellOpensSheetLogAndCreate() throws {
    XCTAssertTrue(waitForLiveChart(), "图没活")
    XCTAssertEqual(bell.label, "提醒", "没有提醒时铃铛不该带数")

    openHub()
    XCTAssertTrue(app.navigationBars["提醒"].exists, "表的标题不是「提醒」")
    let pinned = app.staticTexts["alerts.pinned"]
    XCTAssertTrue(pinned.waitForExistence(timeout: Self.short), "列表页没有置顶那组")
    XCTAssertEqual(pinned.label, "BTC/USDT", "置顶的不是图上这只")
    XCTAssertTrue(app.staticTexts["alerts.pinned.empty"].exists, "这只一条没有时置顶那组该是「暂无提醒」")

    // 日志：测试档案没登录。
    pick("日志")
    XCTAssertTrue(app.descendants(matching: .any)["alerts.log.signedOut"].waitForExistence(timeout: Self.short),
                  "没登录时日志页该只有一句「登录后可查看」")
    XCTAssertFalse(app.buttons["alerts.log.clear"].exists, "没登录不该有「清空」")
    XCTAssertFalse(create.exists, "日志页不该有「创建提醒」")

    // 列表 → 创建提醒：品种锁定、价格预填。
    pick("列表")
    XCTAssertTrue(create.waitForExistence(timeout: Self.short), "列表页底部没有「创建提醒」")
    create.tap()
    let symbol = app.staticTexts["alerts.new.symbol"]
    XCTAssertTrue(symbol.waitForExistence(timeout: Self.short), "没推出创建页")
    XCTAssertEqual(symbol.label, "BTC/USDT", "创建页的品种不是图上那只")
    XCTAssertEqual(app.textFields.matching(NSPredicate(format: "identifier BEGINSWITH 'alerts.new.symbol'")).count, 0,
                   "创建页的品种该是锁定的，不该有能改的品种框")
    let price = app.textFields["alerts.new.price"]
    XCTAssertTrue(price.waitForExistence(timeout: Self.short), "创建页没有价格框")
    let prefilled = (price.value as? String) ?? ""
    XCTAssertNotNil(prefilled.rangeOfCharacter(from: .decimalDigits), "价格没预填最新价：\(prefilled)")
    // 系统返回回到列表页，再从列表页建两条（价离现价远，免得真行情碰到被「触发即删」带走）。
    app.navigationBars.buttons.firstMatch.tap()
    createFromHub(price: "9999999")
    createFromHub(price: "1")
    XCTAssertTrue(app.descendants(matching: .any)["alerts.pinned.price"].waitForExistence(timeout: Self.short),
                  "建好之后置顶那组没有「价格」小节")
    XCTAssertFalse(app.staticTexts["alerts.pinned.empty"].exists, "建好之后还写着「暂无提醒」")
    closeHub()
    XCTAssertTrue(waitUntil(timeout: Self.short) { self.bell.label == "提醒 2" }, "铃角标不是 2：\(bell.label)")
  }

  /// 验收截图：顶栏（铃角标；10-08 起对比收进「⋯」菜单，不再亮强调色）青苔浅 / 深、对比模式搜索页两只、提醒列表置顶、日志未登录与登录后空。
  func testEvidenceShots() throws {
    XCTAssertTrue(waitForLiveChart(), "图没活")
    XCTAssertTrue(app.buttons[Ids.topMore].waitForExistence(timeout: Self.short), "顶栏没有「⋯」")

    openHub()
    createFromHub(price: "9999999")
    createFromHub(price: "1")
    RunLoop.main.run(until: Date().addingTimeInterval(1.5))
    shot("提醒列表-置顶")
    pick("日志")
    XCTAssertTrue(app.descendants(matching: .any)["alerts.log.signedOut"].waitForExistence(timeout: Self.short))
    shot("日志-未登录")
    closeHub()
    XCTAssertTrue(waitUntil(timeout: Self.short) { self.bell.label == "提醒 2" }, "铃角标不是 2：\(bell.label)")
    setMode("浅色")
    shot("顶栏-青苔浅")

    // 对比模式的搜索页：启动时带着 ETH、SOL 两只。
    XCTAssertTrue(app.openTopMenuItem(Ids.topCompare, timeout: Self.short), "顶栏「⋯」菜单里没有「添加对比」")
    XCTAssertTrue(app.buttons["compare.done"].waitForExistence(timeout: Self.short), "「⋯ › 添加对比」没开出对比模式的搜索页")
    XCTAssertEqual(app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'compare.remove.'")).count, 2,
                   "「正在对比」那条不是两只")
    shot("对比搜索-两只")
    app.buttons["compare.done"].tap()
    XCTAssertTrue(waitUntil(timeout: 10) { !self.app.textFields[Ids.searchQuery].exists }, "「完成」没收起对比搜索页")
    XCTAssertTrue(bell.waitForExistence(timeout: Self.short), "收起搜索页没回到行情页")

    setMode("深色")
    shot("顶栏-青苔深")

    // 登录（现造 qa_ 账号）后日志页：服务端还没有记录 → 「暂无记录」。
    let name = "qa_alertlog_" + UUID().uuidString.replacingOccurrences(of: "-", with: "").prefix(10).lowercased()
    let password = UUID().uuidString + "a1"
    try register(name, password)
    account = (name, password)
    XCTAssertTrue(app.openAccountFromMe(), "「我的 › 账号」没推出账号页")
    let username = app.textFields["account.email"]
    XCTAssertTrue(username.waitForExistence(timeout: 10)); username.tap(); username.typeText(name)
    let secure = app.secureTextFields["account.password"]; secure.tap(); secure.typeText(password)
    app.buttons["account.submit"].tap()
    XCTAssertTrue(waitUntil(timeout: 45) { !self.app.accountView.exists }, "登录未完成")
    app.buttons[Ids.bottomChart].tap()
    XCTAssertTrue(waitForLiveChart(), "登录后图没活")
    openHub()
    pick("日志")
    XCTAssertTrue(app.descendants(matching: .any)["alerts.log.empty"].waitForExistence(timeout: 20),
                  "登录后日志页没有「暂无记录」")
    XCTAssertFalse(app.buttons["alerts.log.clear"].exists, "没有记录时不该有「清空」")
    shot("日志-空")
    closeHub()
  }

  /// 「我的 › 设置」里换深浅，再回行情页。
  private func setMode(_ mode: String) {
    XCTAssertTrue(app.openSettingsFromMe(), "「我的 › 设置」没进到设置页")
    let card = app.buttons["display.theme.sage"]
    if card.waitForExistence(timeout: Self.short), (card.value as? String) != "已选" { card.tap() }
    let button = app.buttons["display.mode." + mode]
    XCTAssertTrue(button.waitForExistence(timeout: Self.short), "设置页没有「\(mode)」")
    if !button.isSelected { button.tap() }
    XCTAssertTrue(waitUntil(timeout: Self.short) { button.isSelected }, "没切到「\(mode)」")
    app.buttons[Ids.bottomChart].tap()
    XCTAssertTrue(waitForLiveChart(), "回行情页图没活")
    XCTAssertTrue(bell.waitForExistence(timeout: Self.short))
  }

  /// 同步注册（用例本身是同步的：`continueAfterFailure = false` 只在同步用例里能当场停下）。
  private func register(_ name: String, _ password: String) throws {
    var request = URLRequest(url: URL(string: api + "/v1/auth/register")!)
    request.httpMethod = "POST"; request.timeoutInterval = 30
    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
    let device = ["id": UUID().uuidString, "name": "提醒日志验收", "secret": UUID().uuidString + UUID().uuidString,
                  "kind": "desktop"]
    request.httpBody = try JSONSerialization.data(withJSONObject: ["username": name, "password": password, "device": device])
    let done = expectation(description: "注册")
    nonisolated(unsafe) var status = 0
    URLSession.shared.dataTask(with: request) { _, response, _ in
      status = (response as? HTTPURLResponse)?.statusCode ?? 0
      done.fulfill()
    }.resume()
    wait(for: [done], timeout: 40)
    XCTAssertTrue((200..<300).contains(status), "注册失败：\(status)")
  }

  private func closeAccount(_ name: String, _ password: String) async {
    func send(_ path: String, _ method: String, _ body: [String: Any], token: String? = nil) async -> Data? {
      var request = URLRequest(url: URL(string: api + path)!)
      request.httpMethod = method; request.timeoutInterval = 30
      request.setValue("application/json", forHTTPHeaderField: "Content-Type")
      if let token { request.setValue("Bearer " + token, forHTTPHeaderField: "Authorization") }
      request.httpBody = try? JSONSerialization.data(withJSONObject: body)
      return try? await URLSession.shared.data(for: request).0
    }
    let device = ["id": UUID().uuidString, "name": "提醒日志验收", "secret": UUID().uuidString + UUID().uuidString,
                  "kind": "desktop"]
    guard let data = await send("/v1/auth/login", "POST", ["username": name, "password": password, "device": device]),
          let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
          let token = (object["data"] as? [String: Any])?["accessToken"] as? String else { return }
    _ = await send("/v1/auth/account", "DELETE", ["password": password], token: token)
  }
}
