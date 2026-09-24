import XCTest

// ============================================================ 复盘模块收拢 · 端到端
//
// 一个一次性的 `test_` 账号把复盘整条路走一遍（线上后端，做完当场注销）：
//
// 1. 注册 → 记一笔「看多」（带当时那张图）→ 第一次记有方向的一笔时问通知权限；
// 2. 退出登录 → 再登录：记录与图都还在；
// 3. 换一份全新的本机档案（等于换了台手机）再登录：记录与图从服务端拉回来；
// 4. 到点提醒：用 DEBUG 钩子 `KANPAN_REVIEW_DUE_SHIFT` 把「现在」拨到到期前 30 秒，
//    app 退到后台，系统通知响**一次**；点开直接进这条记录；回到前台 app 自己不再补叫。
//
// 截图落在 /tmp/kanpan-lanel-shots/。

@MainActor
final class ReviewModuleE2EUITests: KanpanUICase {
  private var profile = UUID().uuidString
  private var shift: String?
  private static let api = "https://kanpan.107-174-172-10.sslip.io"
  private static let password = "Testpass2026"
  private var created: [String] = []
  private let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")

  override var extraLaunchEnvironment: [String: String] {
    var env = ["KANPAN_PERSISTENCE_PROFILE": profile, "KANPAN_ACCOUNT_API_URL": Self.api]
    if let shift { env["KANPAN_REVIEW_DUE_SHIFT"] = shift }
    return env
  }

  override func setUp() async throws {
    XCUIDevice.shared.orientation = .portrait
    try await super.setUp()
  }

  override func tearDown() async throws {
    let leftovers = created
    created = []
    for name in leftovers { await forceDelete(name) }
    try await super.tearDown()
  }

  func testLoginRecordLogoutLoginNewDeviceAndDueReminderOnce() throws {
    let user = "test_" + UUID().uuidString.replacingOccurrences(of: "-", with: "").prefix(10).lowercased()
    created.append(user)
    register(user)

    // ---- 1. 记一笔看多
    app.buttons[Ids.bottomChart].tap()
    XCTAssertTrue(waitForLiveChart(), "没等到行情")
    guard openCapture() else { return }
    let long = app.buttons["看多"]
    guard expectExists(long, Self.short, "取景卡上没有「看多」") else { return }
    long.tap()
    shot("01-取景卡-看多")
    app.buttons["记下"].tap()
    let recordedAt = Date()
    // 第一次记有方向的一笔：系统问一次通知权限（装机后第一次才有这个弹窗）。
    let allow = springboard.alerts.buttons.matching(NSPredicate(format: "label IN {'允许', 'Allow'}")).firstMatch
    if allow.waitForExistence(timeout: Self.short) {
      shot("02-通知权限")
      allow.tap()
      note("通知权限：弹了，点了允许")
    } else {
      note("通知权限：没弹（之前已经问过）")
    }
    XCTAssertTrue(waitUntil(timeout: Self.short) { !self.app.buttons["记下"].exists }, "取景卡没收回去")

    guard openRecordWithShot(step: "03-记下之后") else { return }
    closeBook()

    // ---- 2. 退出登录 → 再登录
    logout()
    shot("04-已退出登录")
    login(user)
    guard openRecordWithShot(step: "05-重新登录之后") else { return }
    closeBook()

    // ---- 3. 换一份全新的本机档案（像换了台手机），记录和图都得从服务端回来
    app.terminate()
    profile = UUID().uuidString
    relaunch()
    login(user)
    guard openRecordWithShot(step: "06-新档案登录之后") else { return }
    closeBook()

    // ---- 4. 到点提醒：拨到到期前 30 秒，退到后台等系统通知
    let due = recordedAt.addingTimeInterval(86_400)
    let lead: TimeInterval = 30
    shift = String(Int(due.timeIntervalSinceNow - lead))
    app.terminate()
    relaunch()
    // 等记录读进来、提醒排上（账号已登录，本机档案里有这条）。
    _ = XCTWaiter.wait(for: [XCTestExpectation(description: "schedule")], timeout: 5)
    XCUIDevice.shared.press(.home)
    let banner = springboard.descendants(matching: .any)
      .matching(NSPredicate(format: "label CONTAINS '到点了'")).firstMatch
    XCTAssertTrue(banner.waitForExistence(timeout: lead + 60), "后台等了 \(Int(lead + 60)) 秒没见到「到点了」系统通知")
    // 横幅只停几秒：先点，截图留到回 app 之后。同名元素是横幅的几层嵌套（一条通知），
    // 点坐标比点某一层稳——那几层里有的不可点。
    note("系统通知：label=\(banner.label)")
    let frame = banner.frame
    shotSpringboard("07-后台系统通知")
    springboard.coordinate(withNormalizedOffset: .zero)
      .withOffset(CGVector(dx: frame.midX, dy: frame.midY)).tap()
    _ = XCTWaiter.wait(for: [XCTestExpectation(description: "open")], timeout: 3)
    save(XCUIScreen.main.screenshot(), "07b-点了通知之后")
    note("点通知：frame=\(frame) app.state=\(app.state.rawValue)")
    XCTAssertTrue(app.wait(for: .runningForeground, timeout: Self.long), "点通知没回到 app")
    XCTAssertTrue(app.navigationBars["记录详情"].waitForExistence(timeout: Self.long), "点通知没打开这条记录")
    shot("08-点通知进了记录详情")
    // 回到前台之后 app 自己不再补叫一次（一条只叫一回）。
    let toast = app.staticTexts.matching(NSPredicate(format: "label CONTAINS '到点了'")).firstMatch
    XCTAssertFalse(toast.waitForExistence(timeout: 6), "系统通知响过了，前台又补叫了一次")
    shot("09-前台没有重复提醒")

    if app.navigationBars["记录详情"].exists { app.navigationBars["记录详情"].buttons.firstMatch.tap() }
    closeBook()
    closeAccount(user)
  }

  // ------------------------------------------------------------ 小工具

  private func relaunch() {
    app.launchEnvironment["KANPAN_PERSISTENCE_PROFILE"] = profile
    if let shift { app.launchEnvironment["KANPAN_REVIEW_DUE_SHIFT"] = shift }
    app.launch()
    let chartTab = app.buttons[Ids.bottomChart]
    if chartTab.waitForExistence(timeout: 5), !app.symbolLabel.exists { chartTab.tap() }
    XCTAssertTrue(app.symbolLabel.waitForExistence(timeout: Self.long), "重启后没见到顶栏品种名")
  }

  private static let shotDir = URL(fileURLWithPath: "/tmp/kanpan-lanel-shots", isDirectory: true)
  private func save(_ screenshot: XCUIScreenshot, _ name: String) {
    let attachment = XCTAttachment(screenshot: screenshot)
    attachment.name = name; attachment.lifetime = .keepAlways; add(attachment)
    try? FileManager.default.createDirectory(at: Self.shotDir, withIntermediateDirectories: true)
    try? screenshot.pngRepresentation.write(to: Self.shotDir.appendingPathComponent(name + ".png"))
  }
  private func shot(_ name: String) { save(app.screenshot(), name) }
  private func shotSpringboard(_ name: String) { save(springboard.screenshot(), name) }

  private func note(_ text: String) {
    let a = XCTAttachment(string: text); a.name = "记录"; a.lifetime = .keepAlways; add(a)
    print("E2E|" + text)
  }

  private func openCapture() -> Bool {
    let entry = app.buttons[Ids.intervalChart]
    guard expectExists(entry, Self.short, "周期行右端没有图表设置那颗") else { return false }
    entry.tap()
    let record = app.buttons["chart.record"]
    guard expectExists(record, Self.short, "「图表」面板里没有「记一笔」") else { return false }
    record.tap()
    return expectExists(app.buttons["记下"], Self.short, "点「记一笔」没开出取景卡")
  }

  /// 打开复盘本里那一条，看到「当时那张图」。
  private func openRecordWithShot(step: String) -> Bool {
    let entry = app.buttons[Ids.topReview]
    if !entry.exists { app.buttons[Ids.bottomChart].tap() }
    guard expectExists(entry, Self.long, "\(step)：顶栏没有「复盘」") else { return false }
    entry.tap()
    guard expectExists(app.buttons["review.back"], Self.long, "\(step)：「复盘」没开出复盘本") else { return false }
    if app.buttons["review.chip.all"].exists { app.buttons["review.chip.all"].tap() }
    let row = app.buttons.matching(NSPredicate(format: "label CONTAINS '看多'")).firstMatch
    guard expectExists(row, Self.long, "\(step)：复盘本里没有那条看多的记录") else { shot(step + "-没有记录"); return false }
    shot(step + "-复盘本")
    row.tap()
    guard expectExists(app.navigationBars["记录详情"], Self.short, "\(step)：没进记录详情") else { return false }
    let image = app.images["review.detail.shot"]
    // 图在「当时」那一段下面（List 是懒的，滚出屏幕就不在树上）：先原地等一会儿，
    // 再往顶上翻，最后才往下找。
    var found = image.waitForExistence(timeout: Self.short)
    for _ in 0..<4 where !found { app.swipeDown(); found = image.waitForExistence(timeout: 1.5) }
    for _ in 0..<6 where !found { app.swipeUp(); found = image.waitForExistence(timeout: 1.5) }
    shot(step + "-记录详情")
    XCTAssertTrue(found, "\(step)：记录详情里没有「当时那张图」")
    app.navigationBars["记录详情"].buttons.firstMatch.tap()
    return found
  }

  private func closeBook() {
    if app.buttons["review.back"].waitForExistence(timeout: 3) { app.buttons["review.back"].tap() }
  }

  // ------------------------------------------------------------ 账号

  private func openAccountPage() {
    if app.otherElements["account.view"].exists { return }
    if !app.buttons["settings.account"].exists {
      let tab = app.buttons[Ids.bottomSettings]
      expectExists(tab, Self.long, "底栏上没有设置格")
      tab.tap()
    }
    let row = app.buttons["settings.account"]
    expectExists(row, Self.long, "设置页上没有账号行 settings.account")
    row.tap()
    expectExists(app.otherElements["account.view"], Self.long, "点了账号行但账号页没打开")
  }

  private func fill(username: String?) {
    if let username {
      let field = app.textFields["account.email"]
      expectExists(field, Self.long, "没有用户名输入框 account.email")
      field.tap()
      field.typeText(username)
    }
    let secure = app.secureTextFields["account.password"]
    expectExists(secure, Self.long, "没有口令输入框 account.password")
    secure.tap()
    if app.buttons["GenerateStrongPasswordButton"].waitForExistence(timeout: 2) { app.buttons["xmark"].tap() }
    expectExists(app.keyboards.firstMatch, Self.long, "点了口令框但键盘没起来")
    for character in Self.password { secure.typeText(String(character)) }
  }

  private func register(_ username: String) {
    openAccountPage()
    let entry = app.buttons["注册"]
    expectExists(entry, Self.long, "登录页上没有「注册」入口")
    entry.tap()
    fill(username: username)
    app.buttons["account.submit"].tap()
    XCTAssertTrue(waitUntil(timeout: 60) { !self.app.otherElements["account.view"].exists },
                  "注册 \(username) 没有闭合账号页")
  }

  /// 已经登着（钥匙串跟着档案还在）就不再登一次。
  private func login(_ username: String) {
    openAccountPage()
    if app.buttons["退出登录"].waitForExistence(timeout: 2) {
      note("登录：已经登着 \(username)")
      closeAccountPage(); return
    }
    fill(username: username)
    app.buttons["account.submit"].tap()
    XCTAssertTrue(waitUntil(timeout: 60) { !self.app.otherElements["account.view"].exists },
                  "登录 \(username) 没有闭合账号页")
  }

  private func closeAccountPage() {
    let close = app.buttons.matching(NSPredicate(format: "identifier == 'account.close' OR label IN {'关闭', '完成'}")).firstMatch
    if close.exists { close.tap() } else { app.swipeDown() }
    _ = waitUntil(timeout: Self.short) { !self.app.otherElements["account.view"].exists }
  }

  private func logout() {
    openAccountPage()
    let button = app.buttons["退出登录"]
    expectExists(button, Self.long, "账号页上没有「退出登录」")
    button.tap()
    XCTAssertTrue(waitUntil(timeout: 30) { !self.app.otherElements["account.view"].exists },
                  "点了退出登录但账号页没关")
  }

  private func closeAccount(_ username: String) {
    openAccountPage()
    let entry = app.buttons["注销账号"]
    expectExists(entry, Self.long, "账号页上没有「注销账号」")
    entry.tap()
    fill(username: nil)
    app.buttons["account.submit"].tap()
    XCTAssertTrue(waitUntil(timeout: 60) { !self.app.otherElements["account.view"].exists },
                  "注销 \(username) 没完成")
    created.removeAll { $0 == username }
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
