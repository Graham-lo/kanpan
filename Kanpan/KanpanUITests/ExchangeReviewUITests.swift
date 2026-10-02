import XCTest

// ============================================================ 自动复盘 3c · 界面与端到端
//
// 没有真账户：交易所那一侧用 DEBUG 包里的假提供者（`ExchangeDemoProvider`，`KANPAN_EXCHANGE_FIXTURE=1`），
// 成交按「上周一」起算、价格取真实 K 线开盘价，所以服务端算出来的浮盈浮亏与离开后都是真算的。
// Key 里带 `TRADE` 当成开着交易权限，必须被拒收。
//
// 1. 接入页三态：未接入 → 带交易权限的 Key 拒收（「只收只读 Key」）→ 只读 Key 接入成功，
//    「我的」两行跟着变。
// 2. 端到端：假 Key 开机自动接入 → 未登录只在本机拼回合 → 注册 `test_` 账号后上传 →
//    复盘本「交易」段（上周卡、持仓中、按天分组）→ 交易详情（带记号的图、成交、服务端回写的
//    持仓期间与离开后、写「当时怎么想」）→ 战绩切到交易那一面。账号做完当场注销。
//
// 截图落在 docs/acceptance/自动复盘-2026-09-27/<机型>-<页>-<皮肤>.png。
@MainActor
final class ExchangeReviewUITests: KanpanUICase {
  private let profile = UUID().uuidString
  private var autoKey: String?
  private static let api = "https://kanpan.43-160-232-253.sslip.io"
  private static let password = "Testpass2026"
  private var created: [String] = []

  override var extraLaunchEnvironment: [String: String] {
    var env = ["KANPAN_PERSISTENCE_PROFILE": profile, "KANPAN_EXCHANGE_FIXTURE": "1",
               "KANPAN_ACCOUNT_API_URL": Self.api]
    if let autoKey { env["KANPAN_EXCHANGE_FIXTURE_KEY"] = autoKey }
    return env
  }

  override func setUp() async throws {
    XCUIDevice.shared.orientation = .portrait
    // 端到端那条开机就带着只读 Key 自动接入。
    if name.contains("EndToEnd") { autoKey = "DEMOREADONLY7C31" }
    try await super.setUp()
  }

  override func tearDown() async throws {
    let leftovers = created
    created = []
    for name in leftovers { await forceDelete(name) }
    try await super.tearDown()
  }

  private static let outDir = URL(
    fileURLWithPath: "/Users/mdd/zhk/kanpan/docs/acceptance/自动复盘-2026-09-27", isDirectory: true)

  private var deviceTag: String {
    switch Int(app.windows.firstMatch.frame.width.rounded()) {
    case 402: "iPhone16Pro"
    case 440: "iPhone17ProMax"
    case 430: "iPhone15ProMax"
    case let w: "宽\(w)"
    }
  }

  private func note(_ line: String) {
    print("取证|" + line)
    let a = XCTAttachment(string: line); a.name = "取证"; a.lifetime = .keepAlways; add(a)
  }

  private func shot(_ page: String, _ skin: String = "青苔") {
    let screenshot = XCUIScreen.main.screenshot()
    let name = "\(deviceTag)-\(page)-\(skin)"
    let a = XCTAttachment(screenshot: screenshot); a.name = name; a.lifetime = .keepAlways; add(a)
    try? FileManager.default.createDirectory(at: Self.outDir, withIntermediateDirectories: true)
    do { try screenshot.pngRepresentation.write(to: Self.outDir.appendingPathComponent(name + ".png")) }
    catch { note("落盘失败|\(name)|\(error)") }
  }

  // ------------------------------------------------------------ 1. 接入页三态

  func testConnectPageRejectsTradingKeyThenAcceptsReadOnly() throws {
    applySageLight()
    let row = app.buttons[Ids.meExchange]
    XCTAssertTrue(row.waitForExistence(timeout: Self.short), "「我的」上没有交易所账户")
    note("我的·交易所行|接入前|\(row.label)")
    XCTAssertTrue(row.label.contains("未接入"), "没接入时「我的」那一行不是「未接入」：\(row.label)")
    let review = app.buttons[Ids.meReview]
    XCTAssertTrue(review.label.contains("接入交易所后自动生成"), "复盘本那一行没有交易那半句：\(review.label)")

    row.tap()
    let page = app.descendants(matching: .any).matching(identifier: "me.exchange.page").firstMatch
    XCTAssertTrue(page.waitForExistence(timeout: Self.short), "交易所账户页没推出来")
    XCTAssertTrue(app.staticTexts["币安 · 合约"].exists, "页上没有「币安 · 合约」")
    let state = app.staticTexts["exchange.state"]
    XCTAssertEqual(state.label, "未接入")
    let key = app.textFields["exchange.key"], secret = app.secureTextFields["exchange.secret"]
    XCTAssertTrue(key.exists && secret.exists, "没有 Key / Secret 两个输入框")
    XCTAssertEqual(key.placeholderValue, "只读 API Key")
    XCTAssertEqual(secret.placeholderValue, "Secret")
    let connect = app.buttons["exchange.connect"]
    XCTAssertFalse(connect.isEnabled, "什么都没填「接入」就能点")
    RunLoop.main.run(until: Date().addingTimeInterval(0.4))
    shot("接入页-未接入")

    // 带交易权限的 Key：拒收，一行红字。
    key.tap(); key.typeText("DEMOTRADE00FF")
    secret.tap(); secret.typeText("fixture-secret")
    XCTAssertTrue(connect.isEnabled)
    connect.tap()
    let error = app.staticTexts["exchange.error"]
    XCTAssertTrue(error.waitForExistence(timeout: Self.long), "带交易权限的 Key 没被拒收")
    note("拒收|\(error.label)")
    XCTAssertTrue(error.label.hasPrefix("只收只读 Key"), "拒收文案不对：\(error.label)")
    XCTAssertEqual(state.label, "未接入", "拒收之后状态却变了")
    dismissKeyboard()
    shot("接入页-拒收")

    // 换一把只读 Key：接入成功，显示尾四位、上次同步、回溯范围。
    key.tap()
    key.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: 16))
    key.typeText("DEMOREADONLY9A2F")
    connect.tap()
    let suffix = app.staticTexts["exchange.suffix"]
    XCTAssertTrue(suffix.waitForExistence(timeout: Self.long), "只读 Key 没接上")
    XCTAssertEqual(suffix.label, "••••9A2F")
    XCTAssertEqual(state.label, "已接入")
    XCTAssertFalse(error.exists, "接上了还挂着红字")
    let backfill = app.staticTexts["exchange.backfill"]
    XCTAssertTrue(backfill.exists && backfill.label.hasSuffix("起"), "没有回溯范围")
    let lastSync = app.staticTexts["exchange.lastSync"]
    XCTAssertTrue(waitUntil(timeout: Self.long) { lastSync.label.contains("前") || lastSync.label == "刚刚" },
                  "接入后第一次同步没落下：\(lastSync.label)")
    XCTAssertTrue(app.buttons["exchange.sync"].exists && app.buttons["exchange.remove"].exists, "少了立即同步 / 移除")
    XCTAssertFalse(key.exists, "接上了还摆着输入框")
    note("已接入|\(suffix.label)|\(lastSync.label)|\(backfill.label)")
    shot("接入页-已接入")

    // 「我的」两行跟着变。
    back(from: page)
    XCTAssertTrue(row.waitForExistence(timeout: Self.short), "没退回「我的」")
    XCTAssertTrue(waitUntil(timeout: Self.short) { row.label.contains("币安合约") }, "「我的」交易所那一行没变：\(row.label)")
    XCTAssertTrue(waitUntil(timeout: Self.short) { review.label.contains("交易 上周") }, "复盘本那一行没有交易小结：\(review.label)")
    note("我的|\(row.label)|\(review.label)")
    shot("我的-已接入")

    // 移除：回到未接入。
    row.tap()
    XCTAssertTrue(app.buttons["exchange.remove"].waitForExistence(timeout: Self.short))
    app.buttons["exchange.remove"].tap()
    let confirm = app.buttons["exchange.remove.confirm"].firstMatch
    XCTAssertTrue(confirm.waitForExistence(timeout: Self.short), "移除没有二次确认")
    confirm.tap()
    XCTAssertTrue(waitUntil(timeout: Self.short) { state.label == "未接入" }, "移除之后没回到未接入")
    XCTAssertTrue(app.textFields["exchange.key"].exists, "移除之后没回到输入框")
  }

  // ------------------------------------------------------------ 2. 端到端

  func testEndToEndTradeSegmentDetailAndStats() throws {
    applySageLight()
    // 开机已用只读 Key 自动接入，未登录：回合只在本机。
    let row = app.buttons[Ids.meExchange]
    XCTAssertTrue(waitUntil(timeout: Self.long) { row.label.contains("币安合约") }, "开机没自动接入：\(row.label)")
    let review = app.buttons[Ids.meReview]
    XCTAssertTrue(waitUntil(timeout: Self.long) { review.label.contains("笔 · 净盈亏") }, "本机没拼出上周的回合：\(review.label)")
    note("未登录|\(review.label)")

    // 注册一个一次性账号：回合上传，服务端回写结果。
    let user = "test_" + UUID().uuidString.replacingOccurrences(of: "-", with: "").prefix(10).lowercased()
    created.append(user)
    register(user)

    XCTAssertTrue(app.openReviewBookFromMe(), "「我的 › 复盘本」没开出复盘本")
    let tradesTab = app.buttons["review.segment.交易"]
    XCTAssertTrue(tradesTab.waitForExistence(timeout: Self.short), "复盘本没有「观点 · 交易」开关")
    tradesTab.tap()
    let week = app.buttons["review.trades.week"]
    XCTAssertTrue(week.waitForExistence(timeout: Self.long), "交易段没有上周卡")
    note("上周卡|\(week.label)")
    XCTAssertTrue(app.staticTexts["review.trades.open"].waitForExistence(timeout: Self.short), "持仓中那一笔没排在前面")
    let btc = app.buttons.matching(identifier: "review.trades.row.BTC")
    XCTAssertGreaterThanOrEqual(btc.count, 2, "BTC 应有一笔持仓中、一笔已平")
    XCTAssertTrue(app.buttons["review.trades.row.ETH"].exists && app.buttons["review.trades.row.SOL"].exists, "上周的 ETH / SOL 回合不在")
    // 持仓中排在最上面。
    let openRow = btc.element(boundBy: 0)
    XCTAssertTrue(openRow.label.contains("持仓中") || openRow.descendants(matching: .staticText)["持仓中"].exists,
                  "第一行不是持仓中：\(openRow.label)")
    RunLoop.main.run(until: Date().addingTimeInterval(1.5))
    shot("复盘本-交易")

    // 交易详情：已平的 BTC 那一笔。等服务端把持仓期间与离开后算回来（异步 worker）。
    var resolved = false
    let deadline = Date().addingTimeInterval(120)
    while !resolved, Date() < deadline {
      btc.element(boundBy: 1).tap()
      XCTAssertTrue(app.navigationBars["交易详情"].waitForExistence(timeout: Self.short), "没进交易详情")
      XCTAssertTrue(app.descendants(matching: .any)["trade.detail.chart"].waitForExistence(timeout: Self.short), "详情没有图")
      RunLoop.main.run(until: Date().addingTimeInterval(3))
      app.swipeUp()
      resolved = app.staticTexts["最大浮盈"].exists && !app.staticTexts["—"].exists
      if !resolved {
        app.navigationBars["交易详情"].buttons.firstMatch.tap()
        _ = week.waitForExistence(timeout: Self.short)
        // 下拉刷新：再拉一次交易所、再和服务端同步一次。
        app.descendants(matching: .any)["review.trades.list"].swipeDown()
        RunLoop.main.run(until: Date().addingTimeInterval(4))
      }
    }
    XCTAssertTrue(resolved, "两分钟内服务端没把持仓期间 / 离开后算回来")
    note("详情|resolved=\(resolved)|\(app.staticTexts.allElementsBoundByIndex.prefix(80).map(\.label).joined(separator: " / "))")

    // 当时怎么想：写一句、保存。
    let field = app.textViews["trade.detail.note"].exists ? app.textViews["trade.detail.note"] : app.textFields["trade.detail.note"]
    for _ in 0..<3 where !field.exists { app.swipeUp() }
    XCTAssertTrue(field.waitForExistence(timeout: Self.short), "登录后详情里没有「当时怎么想」输入框")
    field.tap(); field.typeText("突破前高追多")
    app.buttons["trade.detail.note.save"].tap()
    XCTAssertTrue(waitUntil(timeout: Self.long) { !self.app.buttons["trade.detail.note.save"].isEnabled }, "「当时怎么想」没存上")
    app.swipeDown(); app.swipeDown()
    RunLoop.main.run(until: Date().addingTimeInterval(0.8))
    shot("交易详情")
    app.swipeUp()
    RunLoop.main.run(until: Date().addingTimeInterval(0.5))
    shot("交易详情-下半")
    app.navigationBars["交易详情"].buttons.firstMatch.tap()

    // 战绩：上周卡点进去，落在交易那一面；切观点再切回来。
    XCTAssertTrue(week.waitForExistence(timeout: Self.short))
    week.tap()
    let summary = app.descendants(matching: .any)["review.stats.trades.summary"]
    XCTAssertTrue(summary.waitForExistence(timeout: Self.short), "战绩没落在交易那一面")
    app.buttons["review.stats.segment.观点"].tap()
    XCTAssertTrue(waitUntil(timeout: Self.short) { !summary.exists }, "战绩切不到观点")
    app.buttons["review.stats.segment.交易"].tap()
    XCTAssertTrue(summary.waitForExistence(timeout: Self.short), "战绩切不回交易")
    RunLoop.main.run(until: Date().addingTimeInterval(0.8))
    shot("战绩-交易")
    app.navigationBars.buttons.firstMatch.tap()
    if app.buttons["review.back"].waitForExistence(timeout: Self.short) { app.buttons["review.back"].tap() }
  }

  // ------------------------------------------------------------ 小工具

  /// 按系统返回退出这一层；键盘收起、同步落下时第一下偶尔被吃掉，没退掉就再点。
  private func back(from page: XCUIElement) {
    for _ in 0..<3 {
      let button = app.navigationBars.buttons["BackButton"].exists
        ? app.navigationBars.buttons["BackButton"] : app.navigationBars.buttons.firstMatch
      if button.exists { button.tap() }
      if waitUntil(timeout: 3, { !page.exists }) { return }
    }
  }

  private func dismissKeyboard() {
    if app.keyboards.firstMatch.exists { app.staticTexts["exchange.state"].tap() }
  }

  /// 「我的 › 设置」换成青苔浅色，再退回「我的」根页。
  private func applySageLight() {
    XCTAssertTrue(app.openSettingsFromMe(), "「我的 › 设置」没开出来")
    let card = app.buttons["display.theme.sage"]
    XCTAssertTrue(card.waitForExistence(timeout: Self.short), "设置页上没有皮肤卡")
    if (card.value as? String) != "已选" {
      if waitUntil(timeout: Self.short, { card.isHittable }) { card.tap() }
      else { card.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap() }
    }
    let light = app.buttons["display.mode.浅色"]
    if light.waitForExistence(timeout: Self.short), !light.isSelected { light.tap() }
    app.navigationBars.buttons.firstMatch.tap()
    XCTAssertTrue(app.buttons[Ids.meSettings].waitForExistence(timeout: Self.short), "没退回「我的」")
  }

  private func register(_ username: String) {
    XCTAssertTrue(app.openAccountFromMe(), "「我的 › 账号」没推出账号页")
    let entry = app.buttons["注册"]
    expectExists(entry, Self.long, "登录页上没有「注册」入口")
    entry.tap()
    let field = app.textFields["account.email"]
    expectExists(field, Self.long, "没有用户名输入框 account.email")
    field.tap(); field.typeText(username)
    let secure = app.secureTextFields["account.password"]
    expectExists(secure, Self.long, "没有口令输入框 account.password")
    secure.tap()
    if app.buttons["GenerateStrongPasswordButton"].waitForExistence(timeout: 2) { app.buttons["xmark"].tap() }
    for character in Self.password { secure.typeText(String(character)) }
    app.buttons["account.submit"].tap()
    XCTAssertTrue(waitUntil(timeout: 60) { !self.app.accountView.exists }, "注册 \(username) 没有闭合账号页")
    if !app.buttons[Ids.meReview].exists, app.navigationBars.buttons.firstMatch.exists {
      app.navigationBars.buttons.firstMatch.tap()
    }
  }

  private func forceDelete(_ username: String) async {
    struct Device: Encodable { var id = UUID(); var name = "uitest"; var secret = UUID().uuidString + UUID().uuidString }
    struct Login: Encodable { var username: String; var password: String; var device: Device }
    struct Tokens: Decodable { struct Payload: Decodable { var accessToken: String }; var data: Payload }
    struct Close: Encodable { var password: String }
    guard let base = URL(string: Self.api) else { return }
    var login = URLRequest(url: base.appendingPathComponent("v1/auth/login"))
    login.httpMethod = "POST"
    login.setValue("application/json", forHTTPHeaderField: "Content-Type")
    login.httpBody = try? JSONEncoder().encode(Login(username: username, password: Self.password, device: Device()))
    guard let (data, response) = try? await URLSession.shared.data(for: login),
          let code = (response as? HTTPURLResponse)?.statusCode, (200..<300).contains(code),
          let token = try? JSONDecoder().decode(Tokens.self, from: data).data.accessToken else { return }
    var remove = URLRequest(url: base.appendingPathComponent("v1/auth/account"))
    remove.httpMethod = "DELETE"
    remove.setValue("application/json", forHTTPHeaderField: "Content-Type")
    remove.setValue("Bearer " + token, forHTTPHeaderField: "Authorization")
    remove.httpBody = try? JSONEncoder().encode(Close(password: Self.password))
    _ = try? await URLSession.shared.data(for: remove)
  }
}
