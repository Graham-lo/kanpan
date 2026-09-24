import XCTest
import UIKit

/// 审查 U14 / U15：账号页边输边校验、两页切换同一样式；朋友页没登录时说清楚并给登录，
/// 登录后能在朋友页自己加朋友。账号走线上真后端，自造的 test_ 号收尾一律注销。
@MainActor final class AccountFormUITests: XCTestCase {
  private let api = TestAccounts.api
  private let password = "Testpass2026"
  private var app: XCUIApplication!
  private var created: [String] = []

  override func setUp() async throws {
    continueAfterFailure = false
    XCUIDevice.shared.orientation = .portrait
    app = XCUIApplication()
    app.launchEnvironment = ["KANPAN_TEST_PROFILE": "1", "KANPAN_PERSISTENCE_PROFILE": UUID().uuidString,
                             "KANPAN_ACCOUNT_API_URL": api]
    app.launch()
  }
  override func tearDown() async throws {
    app?.terminate()
    for name in created { await TestAccounts.delete(name, password: password, api: api) }
  }

  /// 规则不再等服务端拒了才露面：填到不合格就置灰、框下一行规则字，合格了规则字收起。
  /// 登录、注册两页切换的是同一颗、同一个位置。
  func testRegisterFormChecksRulesWhileTyping() throws {
    openAccount()
    let submit = app.buttons["account.submit"]
    let toggle = app.buttons["account.switch"]
    XCTAssertTrue(toggle.waitForExistence(timeout: 10), "登录页上没有切换到注册的那一颗")
    XCTAssertEqual(toggle.label, "注册")
    XCTAssertFalse(submit.isEnabled, "什么都没填，登录不该亮")
    let loginToggleX = toggle.frame.midX
    toggle.tap()
    XCTAssertTrue(app.navigationBars["注册"].waitForExistence(timeout: 5))
    XCTAssertEqual(toggle.label, "登录")
    XCTAssertEqual(toggle.frame.midX, loginToggleX, accuracy: 1, "两页的切换不在同一个位置")
    XCTAssertEqual(toggle.frame.midX, app.frame.midX, accuracy: 2, "切换那一颗应当居中")

    let name = "test_" + UUID().uuidString.replacingOccurrences(of: "-", with: "").prefix(10).lowercased()
    let username = app.textFields["account.email"]
    username.tap(); username.typeText("ab")
    let nameRule = app.staticTexts["account.email.rule"]
    XCTAssertTrue(nameRule.waitForExistence(timeout: 3), "用户名两位时没有规则字")
    XCTAssertEqual(nameRule.label, "用户名需 3–32 位字母、数字或下划线")
    XCTAssertFalse(submit.isEnabled)
    username.typeText(".")
    XCTAssertTrue(nameRule.exists, "带点的用户名应当不合格")
    username.typeText(XCUIKeyboardKey.delete.rawValue + XCUIKeyboardKey.delete.rawValue + XCUIKeyboardKey.delete.rawValue)
    username.typeText(name)
    XCTAssertFalse(nameRule.exists, "合格以后规则字要收起")
    XCTAssertFalse(submit.isEnabled, "密码空着，注册不该亮")

    let secure = typePassword("abc1")
    let passRule = app.staticTexts["account.password.rule"]
    XCTAssertTrue(passRule.waitForExistence(timeout: 3), "密码四位时没有规则字")
    XCTAssertEqual(passRule.label, "密码至少 8 位，需含字母和数字")
    XCTAssertFalse(submit.isEnabled)
    attach("注册-边输边校验-不合格")
    for character in "defgh" { secure.typeText(String(character)) }
    XCTAssertFalse(passRule.exists, "合格以后密码规则字要收起")
    XCTAssertTrue(submit.isEnabled, "用户名、密码都合格，注册应当亮")
    attach("注册-边输边校验-合格")

    // 回登录页：用户名留着、密码清空 → 置灰；登录页不摆密码规则。
    toggle.tap()
    XCTAssertTrue(app.navigationBars["登录"].waitForExistence(timeout: 5))
    XCTAssertFalse(submit.isEnabled, "登录页密码空着不该亮")
    _ = typePassword("x")
    XCTAssertFalse(app.staticTexts["account.password.rule"].exists, "登录页不该摆密码规则")
    XCTAssertTrue(submit.isEnabled, "登录只要用户名合格、密码不空")
    attach("登录-切换同一样式")
  }

  /// 没登录：整页一句「登录后可收发画线」和一颗「登录」，点了进登录页；登完回到朋友页，
  /// 那里有「加朋友」。注册走线上真后端。
  func testFriendsPageSignedOutLeadsToLogin() throws {
    openFriends()
    XCTAssertTrue(app.staticTexts["friends.signedOut"].waitForExistence(timeout: 10), "没登录的朋友页没有提示")
    XCTAssertEqual(app.staticTexts["friends.signedOut"].label, "登录后可收发画线")
    XCTAssertFalse(app.staticTexts["还没有朋友"].exists, "没登录时不该说「还没有朋友」")
    XCTAssertFalse(app.staticTexts["还没有收到画线"].exists)
    attach("朋友页-未登录")
    tap("friends.login")
    XCTAssertTrue(app.accountView.waitForExistence(timeout: 10), "点了登录没进账号页")
    tap("account.switch")
    let name = register()
    XCTAssertTrue(app.friendsPage.waitForExistence(timeout: 20), "登完没有回到朋友页")
    XCTAssertTrue(app.buttons["friends.add"].waitForExistence(timeout: 10), "登录后的朋友页没有「加朋友」")
    XCTAssertFalse(app.staticTexts["friends.signedOut"].exists)
    attach("朋友页-登录后 \(name)")
  }

  /// 朋友页自己加朋友，输入框和「发给朋友」那一个同样规则；只记进自己的名单。
  func testAddFriendFromFriendsPage() async throws {
    let me = try await registerOverHTTP(), friend = try await registerOverHTTP()
    openAccount()
    let username = app.textFields["account.email"]
    XCTAssertTrue(username.waitForExistence(timeout: 10)); username.tap(); username.typeText(me)
    _ = typePassword(password)
    tap("account.submit")
    XCTAssertTrue(wait(45) { !self.app.accountView.exists }, "登录未完成")
    openFriends()
    tap("friends.add")
    let field = app.textFields["friends.username"]
    XCTAssertTrue(field.waitForExistence(timeout: 5)); field.tap(); field.typeText("a.b")
    XCTAssertTrue(app.staticTexts["friends.username.rule"].waitForExistence(timeout: 3), "不合格的名字没有规则字")
    XCTAssertFalse(app.buttons["friends.add.confirm"].isEnabled)
    attach("加朋友-不合格")
    field.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: 3) + friend.uppercased())
    XCTAssertTrue(app.buttons["friends.add.confirm"].isEnabled)
    tap("friends.add.confirm")
    XCTAssertTrue(app.staticTexts[friend].waitForExistence(timeout: 20),
                  "加完名单里没有 \(friend)，页面报错=\(app.staticTexts["friends.error"].exists ? app.staticTexts["friends.error"].label : "无")")
    XCTAssertTrue(app.buttons["friends.add"].exists, "加完输入框应当收起，回到「加朋友」一行")
    attach("加朋友-已加上")
    // 服务端只记进我这边：对方的名单里没有我。
    let theirs = try await friends(of: friend)
    XCTAssertFalse(theirs.contains(me), "加朋友不该替对方把我加回去")
    let mine = try await friends(of: me)
    XCTAssertTrue(mine.contains(friend), "我的名单里没有 \(friend)：\(mine)")
  }

  // MARK: - 小工具

  private func openAccount() {
    tap("bottom.settings"); tap("settings.account")
    XCTAssertTrue(app.accountView.waitForExistence(timeout: 10))
  }
  private func openFriends() {
    tap("bottom.settings")
    let friends = app.buttons["settings.friends"]
    XCTAssertTrue(friends.waitForExistence(timeout: 10))
    if !friends.isHittable { app.scrollViews.firstMatch.swipeUp() }
    friends.tap()
    XCTAssertTrue(app.friendsPage.waitForExistence(timeout: 10))
  }
  /// 口令要逐字符敲：整串 `typeText` 会被「强密码」建议气泡吃掉。
  @discardableResult private func typePassword(_ text: String) -> XCUIElement {
    let secure = app.secureTextFields["account.password"]
    XCTAssertTrue(secure.waitForExistence(timeout: 5)); secure.tap()
    if app.buttons["GenerateStrongPasswordButton"].waitForExistence(timeout: 2) { app.buttons["xmark"].tap() }
    XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 5))
    for character in text { secure.typeText(String(character)) }
    return secure
  }
  private func register() -> String {
    let name = "test_" + UUID().uuidString.replacingOccurrences(of: "-", with: "").prefix(10).lowercased()
    created.append(name)
    let username = app.textFields["account.email"]
    XCTAssertTrue(username.waitForExistence(timeout: 10)); username.tap(); username.typeText(name)
    typePassword(password)
    tap("account.submit")
    XCTAssertTrue(wait(45) { !self.app.accountView.exists },
                  "注册 \(name) 没闭合账号页，页面报错=\(app.staticTexts["account.error"].exists ? app.staticTexts["account.error"].label : "无")")
    return name
  }
  private func registerOverHTTP() async throws -> String {
    let name = "test_" + UUID().uuidString.replacingOccurrences(of: "-", with: "").prefix(10).lowercased()
    created.append(name)
    _ = try await call("v1/auth/register", method: "POST", body: ["username": name, "password": password, "device": device()])
    return name
  }
  private func friends(of name: String) async throws -> [String] {
    let login = try await call("v1/auth/login", method: "POST", body: ["username": name, "password": password, "device": device()])
    let token = try XCTUnwrap((login as? [String: Any])?["accessToken"] as? String)
    let list = try await call("v1/friends", token: token) as? [[String: Any]] ?? []
    return list.compactMap { $0["username"] as? String }
  }
  private func device() -> [String: String] {
    ["id": UUID().uuidString, "name": "账号表单验收", "secret": UUID().uuidString + UUID().uuidString, "kind": "desktop"]
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
  private func tap(_ id: String) {
    let button = app.buttons[id]; XCTAssertTrue(button.waitForExistence(timeout: 12), id)
    button.tap()
  }
  private func wait(_ seconds: Double, _ predicate: @escaping () -> Bool) -> Bool {
    XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in predicate() }, object: nil)], timeout: seconds) == .completed
  }
  private func attach(_ name: String) {
    let shot = XCTAttachment(screenshot: XCUIScreen.main.screenshot()); shot.name = name; shot.lifetime = .keepAlways; add(shot)
  }
}
