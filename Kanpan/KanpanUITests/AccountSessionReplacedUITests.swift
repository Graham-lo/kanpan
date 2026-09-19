import XCTest

// ============================================================ 每类设备只许一台在线
//
// `kanpan-one-device-per-class-online`：一个账号同时只准每一类设备各一台在线
// ——手机一类、平板一类、电脑一类，同类里第二台一登录，第一台那条会话就被服务端
// 撤掉（`Backend/kanpan-api/src/auth.rs` 的 `new_session`，`revoked_reason='replaced'`）。
// 之后那台机器不论是拿 access 令牌打任何接口，还是去刷新，收到的都是
// `401 {"error":{"code":"session_replaced","deviceKind":"phone"}}`。
//
// 这条规则以前只有包内单测（`KanpanAccountTests/DeviceKindTests`）拿假服务器守着。
// 那守的是「解析对不对」；这个文件守的是**用户看得见的那一半**：
//
//   1. 被顶下去的那台，界面上说得出**是什么顶的**——账号页横幅是
//      「这个账号在另一台手机上登录了」，不是笼统的「登录已失效」；
//   2. 那条横幅下面有一条**走得通的出路**（「重新登录」），点完能登回来；
//   3. 登回来这一下**自己也是一部手机**，会把中途那台顶掉——规则是对称的，
//      不是「app 有豁免」。第 6 步直接拿中途那台的令牌打 `/v1/auth/me` 验这一条。
//
// 为什么用「账号页 →『登录设备』」当探针：它是账号页上**唯一一个必然带着 access
// 令牌出门**的动作（`AccountFeature.loadDevices` → `GET /v1/auth/devices`），
// 不依赖后台同步什么时候醒、也不依赖某个偏好字段在不在白名单里。人一点进去就撞墙，
// 撞完 `AccountFeature.lost(_:)` 把 `replacedNotice` 立起来，界面上那一句就有了。
//
// 后端是项目自己那台（`KANPAN_ACCOUNT_API_URL`），账号是现造的随机用户名 + 测试口令，
// 走完按「注销账号」删干净；UI 那条路中途断了的话 `tearDown` 再按 HTTP 补一刀
// （login + DELETE），不给后端留垃圾。写法一概照抄 `AccountPreferenceSyncUITests`。

@MainActor final class AccountSessionReplacedUITests: XCTestCase {
  /// 现造的测试口令。不碰用户的真账号、真口令。
  private let password = "Testpass2026"
  private let api = "https://kanpan.107-174-172-10.sslip.io"
  /// 被同类设备顶下去时界面上该出现的那一句（`AccountError.sessionReplaced(.phone)`
  /// 的 `errorDescription`）。模拟器是 iPhone，所以是「手机」那一支。
  private let notice = "这个账号在另一台手机上登录了"
  private var app: XCUIApplication!
  /// 这一轮在后端建过、还没确认删掉的账号。断言中途失败时兜底用。
  private var created: [String] = []

  override func tearDown() async throws {
    let leftovers = created
    created = []
    for name in leftovers { await forceDelete(name) }
    app = nil
  }

  // ------------------------------------------------------------ 正题

  /// 第二部手机登录，把本机顶下去；本机说得出是什么顶的，并且能登回来把它顶回去。
  ///
  /// 1. 干净档案起 app，注册一个随机账号（= 第一部手机，就是本机）；
  /// 2. 直接对线上 API 用**另一个 device id、kind=phone** 登录同一账号（= 第二部手机）；
  /// 3. 本机再碰一次服务器：账号页 →「登录设备」，带 access 令牌 `GET /v1/auth/devices`；
  /// 4. 账号页上出现「这个账号在另一台手机上登录了」，并且有「重新登录」；
  /// 5. 点「重新登录」，同一账号登回来（= 第三次登录，仍是这部手机），账号页关上；
  /// 6. 拿第二部手机的 access 令牌打 `/v1/auth/me`，应当也被顶成 401 `session_replaced`
  ///    ——规则对称，登回来的这一下把中途那台顶掉了；
  /// 7. 设备列表里手机这一类只剩一行，而且是「手机 · 本机」；
  /// 8. 注销账号，删干净。
  func testSecondPhoneLoginEvictsThisOneAndReloginEvictsTheSecond() async throws {
    continueAfterFailure = false
    let profile = UUID().uuidString
    app = makeApp(profile: profile)
    app.launch()
    defer { shot("收尾") }
    XCTAssertTrue(app.buttons["bottom.settings"].waitForExistence(timeout: 90),
                  "第 1 步：干净档案（profile=\(profile)）起 app 之后 90s 还没见到底栏设置格\n\(app.debugDescription)")

    // ---- 第 1 步：app 内注册 = 第一部手机（本机）
    let user = Self.randomName()
    created.append(user)
    register(user, step: "第 1 步（注册 \(user) = 第一部手机）")
    shot("1-注册")

    // ---- 第 2 步：第二部手机（另一个 device id、同样 kind=phone）直接登录同一账号
    let secondPhone = try await loginDirect(user, deviceName: "uitest-phone-2", kind: "phone",
                                            step: "第 2 步（第二部手机登录）")

    // ---- 第 3 步：让本机再碰一次服务器（带 access 令牌的 GET /v1/auth/devices）
    openAccount(step: "第 3 步（打开账号页）")
    tapLabel("登录设备", step: "第 3 步（打开设备列表）")
    XCTAssertTrue(waitUntil(60) { self.app.staticTexts[self.notice].exists },
                  """
                  第 3 步：本机带着 access 令牌去取设备列表，应当撞上 401 session_replaced 并在页面上\
                  说出「\(notice)」；等了 60s 页面上没有这句话（当前报错=\(errorText())）
                  \(app.debugDescription)
                  """)
    shot("3-设备列表撞墙")

    // ---- 第 4 步：回账号页，横幅那一句 + 一条走得通的出路
    back(step: "第 4 步（从设备列表退回账号页）")
    XCTAssertTrue(waitUntil(30) { self.app.staticTexts[self.notice].exists },
                  """
                  第 4 步：账号页失效横幅应当是「\(notice)」而不是笼统的「登录已失效」，\
                  等了 30s 没等到
                  \(app.debugDescription)
                  """)
    let relogin = app.buttons["account.reauthenticate"]
    XCTAssertTrue(relogin.waitForExistence(timeout: 20),
                  "第 4 步：横幅下面没有「重新登录」（account.reauthenticate），人就被困在一个点什么都没用的账号页上\n\(app.debugDescription)")
    shot("4-账号页横幅")

    // ---- 第 5 步：点「重新登录」，同一账号登回来
    relogin.tap()
    XCTAssertTrue(app.buttons["account.submit"].waitForExistence(timeout: 20),
                  "第 5 步：点了「重新登录」没有摆出登录页\n\(app.debugDescription)")
    // 登录页上那一行字也得说清楚是被顶下来的（`AccountView` 里 `account.error` 那一处）。
    XCTAssertEqual(errorText(), notice,
                   "第 5 步：被顶回登录页时，登录页上那行字应当是「\(notice)」\n\(app.debugDescription)")
    shot("5-登录页")
    typeUsername(user, step: "第 5 步（用户名）")
    fillPassword(step: "第 5 步（口令）")
    app.buttons["account.submit"].tap()
    XCTAssertTrue(waitUntil(60) { !self.app.otherElements["account.view"].exists },
                  "第 5 步：登回 \(user) 没有闭合账号页，页面报错=\(errorText())\n\(app.debugDescription)")
    shot("5-登回来")

    // ---- 第 6 步：规则是对称的——登回来这一下把第二部手机顶掉了
    let after = await probe(path: "v1/auth/me", token: secondPhone)
    XCTAssertEqual(after.status, 401,
                   "第 6 步：本机登回来之后，第二部手机的 access 令牌打 /v1/auth/me 应当是 401，实际 \(after.status)（\(after.body)）")
    XCTAssertEqual(after.code, "session_replaced",
                   "第 6 步：第二部手机应当被顶成 session_replaced，实际 \(after.body)")

    // ---- 第 7 步：手机这一类只剩一行，而且是本机
    openAccount(step: "第 7 步（打开账号页）")
    tapLabel("登录设备", step: "第 7 步（再看一次设备列表）")
    var phones: [String] = []
    let single = waitUntil(60) {
      phones = self.app.staticTexts.allElementsBoundByIndex
        .map(\.label).filter { $0.hasPrefix("手机 · ") }
      return phones == ["手机 · 本机"]
    }
    XCTAssertTrue(single,
                  """
                  第 7 步：手机这一类同时只准一台在线，设备列表里手机行应当只有「手机 · 本机」一条，\
                  实际 \(phones)
                  \(app.debugDescription)
                  """)
    shot("7-设备列表")

    // ---- 第 8 步：删干净
    back(step: "第 8 步（退回账号页）")
    closeAccount(user, step: "第 8 步（注销 \(user)）")
    XCTAssertTrue(created.isEmpty, "第 8 步：还有账号没删掉 \(created)")
  }

  // ------------------------------------------------------------ 启动与环境

  private func makeApp(profile: String) -> XCUIApplication {
    let value = XCUIApplication()
    value.launchEnvironment["KANPAN_TEST_PROFILE"] = "1"
    value.launchEnvironment["KANPAN_PERSISTENCE_PROFILE"] = profile
    value.launchEnvironment["KANPAN_ACCOUNT_API_URL"] = api
    value.launchEnvironment["KANPAN_LOG"] = "1"
    return value
  }

  /// 用户名规则：3..=32 位 ASCII 字母数字或 `_`（服务端 `auth.rs` 的 `email(_:)`）。
  private static func randomName() -> String {
    "qa_" + UUID().uuidString.replacingOccurrences(of: "-", with: "").prefix(12).lowercased()
  }

  // ------------------------------------------------------------ 账号页

  /// 账号页没开就从底栏「设置」那一格进去开。已经开着就原样返回。
  private func openAccount(step: String) {
    if !app.otherElements["account.view"].exists {
      let tab = app.buttons["bottom.settings"]
      XCTAssertTrue(tab.waitForExistence(timeout: 60),
                    "\(step)：底栏上没有设置格 bottom.settings\n\(app.debugDescription)")
      tab.tap()
      let row = app.buttons["settings.account"]
      XCTAssertTrue(row.waitForExistence(timeout: 20),
                    "\(step)：设置页上没有账号行 settings.account\n\(app.debugDescription)")
      row.tap()
    }
    XCTAssertTrue(app.otherElements["account.view"].waitForExistence(timeout: 20),
                  "\(step)：点了账号行但账号页没打开\n\(app.debugDescription)")
  }

  /// 账号页左上角那颗「‹」：在子页上是「返回上一层」。
  private func back(step: String) {
    let button = app.buttons["account.back"]
    XCTAssertTrue(button.waitForExistence(timeout: 20),
                  "\(step)：账号页左上角没有 account.back\n\(app.debugDescription)")
    button.tap()
  }

  private func tapLabel(_ label: String, step: String) {
    let button = app.buttons[label]
    XCTAssertTrue(button.waitForExistence(timeout: 20),
                  "\(step)：页面上没有「\(label)」\n\(app.debugDescription)")
    button.tap()
  }

  private func typeUsername(_ username: String, step: String) {
    let field = app.textFields["account.email"]
    XCTAssertTrue(field.waitForExistence(timeout: 20),
                  "\(step)：没有用户名输入框 account.email\n\(app.debugDescription)")
    // 「重新登录」那条路上 `AccountFeature.reauthenticate()` 已经把用户名预填好了，
    // 再敲一遍就变成接在后面。填对了就别动它。
    if (field.value as? String) == username { return }
    field.tap()
    field.typeText(username)
  }

  /// 口令要逐字符敲：整串 `typeText` 会被 iOS 的「强密码」建议气泡吃掉，只剩最后一个字符
  /// （`AccountMarketUITests` / `AccountPreferenceSyncUITests` 里踩过同一颗雷）。
  private func fillPassword(step: String) {
    let secure = app.secureTextFields["account.password"]
    XCTAssertTrue(secure.waitForExistence(timeout: 20),
                  "\(step)：没有口令输入框 account.password\n\(app.debugDescription)")
    secure.tap()
    if app.buttons["GenerateStrongPasswordButton"].waitForExistence(timeout: 2) { app.buttons["xmark"].tap() }
    XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 20),
                  "\(step)：点了口令框但键盘没起来\n\(app.debugDescription)")
    for character in password { secure.typeText(String(character)) }
  }

  private func register(_ username: String, step: String) {
    openAccount(step: step)
    tapLabel("注册", step: step)
    typeUsername(username, step: step)
    fillPassword(step: step)
    app.buttons["account.submit"].tap()
    XCTAssertTrue(waitUntil(60) { !self.app.otherElements["account.view"].exists },
                  "\(step)：注册没有闭合账号页，页面报错=\(errorText())\n\(app.debugDescription)")
  }

  /// 「注销账号」要再输一次口令。删成功之后 `AccountFeature` 自己会退登并收起账号页。
  private func closeAccount(_ username: String, step: String) {
    openAccount(step: step)
    tapLabel("注销账号", step: step)
    fillPassword(step: step)
    app.buttons["account.submit"].tap()
    XCTAssertTrue(waitUntil(60) { !self.app.otherElements["account.view"].exists },
                  "\(step)：注销 \(username) 没完成，页面报错=\(errorText())\n\(app.debugDescription)")
    created.removeAll { $0 == username }
  }

  private func errorText() -> String {
    let label = app.staticTexts["account.error"]
    return label.exists ? label.label : "（页面上没有报错）"
  }

  private func shot(_ name: String) {
    let value = XCTAttachment(screenshot: app.screenshot())
    value.name = name
    value.lifetime = .keepAlways
    add(value)
  }

  // ------------------------------------------------------------ 另一部手机（直接走 HTTP）

  private struct Device: Encodable {
    var id = UUID()
    var name: String
    var secret = UUID().uuidString + UUID().uuidString   // 服务端要求 32..=128 位
    var kind: String
  }
  private struct Credentials: Encodable { var username: String; var password: String; var device: Device }
  private struct Tokens: Decodable { struct Payload: Decodable { var accessToken: String }; var data: Payload }

  /// 「另一台设备」在服务端眼里只是另一个 `device.id` + 一个类别，所以这一步不用真的
  /// 再起一个模拟器：对线上 API 发一趟 `POST /v1/auth/login` 就是一部新手机登录了。
  /// 交出它的 access 令牌，第 6 步拿它验「它自己后来也被顶掉了」。
  private func loginDirect(_ username: String, deviceName: String, kind: String, step: String) async throws -> String {
    guard let base = URL(string: api) else { XCTFail("\(step)：API 地址不对 \(api)"); throw AbortTest() }
    var request = URLRequest(url: base.appendingPathComponent("v1/auth/login"))
    request.httpMethod = "POST"
    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
    request.httpBody = try JSONEncoder().encode(
      Credentials(username: username, password: password, device: Device(name: deviceName, kind: kind)))
    let (data, response) = try await URLSession.shared.data(for: request)
    let status = (response as? HTTPURLResponse)?.statusCode ?? -1
    guard (200..<300).contains(status) else {
      XCTFail("\(step)：登录应当成功，实际 \(status)（\(String(data: data, encoding: .utf8) ?? "")）")
      throw AbortTest()
    }
    return try JSONDecoder().decode(Tokens.self, from: data).data.accessToken
  }

  private struct AbortTest: Error {}

  /// 拿某一把 access 令牌打一个接口，把状态码、错误码和原文都带回来
  /// ——断言失败时要说得出服务端到底回了什么。
  private func probe(path: String, token: String) async -> (status: Int, code: String, body: String) {
    struct Failure: Decodable { struct Payload: Decodable { var code: String }; var error: Payload }
    guard let base = URL(string: api) else { return (-1, "", "API 地址不对") }
    var request = URLRequest(url: base.appendingPathComponent(path))
    request.setValue("Bearer " + token, forHTTPHeaderField: "Authorization")
    guard let (data, response) = try? await URLSession.shared.data(for: request) else {
      return (-1, "", "请求没发出去")
    }
    let body = String(data: data, encoding: .utf8) ?? ""
    let code = (try? JSONDecoder().decode(Failure.self, from: data).error.code) ?? ""
    return ((response as? HTTPURLResponse)?.statusCode ?? -1, code, body)
  }

  // ------------------------------------------------------------ 兜底清理

  /// UI 那条注销路径没走完时，直接按 HTTP 把账号删掉。
  /// 账号已经不在了（登录 401）就什么都不做。
  private func forceDelete(_ username: String) async {
    struct Close: Encodable { var password: String }
    guard let base = URL(string: api) else { return }
    var login = URLRequest(url: base.appendingPathComponent("v1/auth/login"))
    login.httpMethod = "POST"
    login.setValue("application/json", forHTTPHeaderField: "Content-Type")
    login.httpBody = try? JSONEncoder().encode(
      Credentials(username: username, password: password, device: Device(name: "uitest-cleanup", kind: "phone")))
    guard let (data, response) = try? await URLSession.shared.data(for: login),
          let code = (response as? HTTPURLResponse)?.statusCode, (200..<300).contains(code),
          let token = try? JSONDecoder().decode(Tokens.self, from: data).data.accessToken else { return }
    var remove = URLRequest(url: base.appendingPathComponent("v1/auth/account"))
    remove.httpMethod = "DELETE"
    remove.setValue("application/json", forHTTPHeaderField: "Content-Type")
    remove.setValue("Bearer " + token, forHTTPHeaderField: "Authorization")
    remove.httpBody = try? JSONEncoder().encode(Close(password: password))
    _ = try? await URLSession.shared.data(for: remove)
  }

  // ------------------------------------------------------------ 轮询
  //
  // `XCTNSPredicateExpectation` 对 `value` 这种非 KVO 属性不可靠，
  // 所以和 `UITestSupport` 里一样老老实实自己转圈。

  private func waitUntil(_ timeout: TimeInterval, _ condition: () -> Bool) -> Bool {
    let deadline = Date().addingTimeInterval(timeout)
    while Date() < deadline {
      if condition() { return true }
      _ = XCTWaiter.wait(for: [XCTestExpectation(description: "poll")], timeout: 0.2)
    }
    return condition()
  }
}
