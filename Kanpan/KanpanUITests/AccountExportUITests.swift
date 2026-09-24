import XCTest

/// P3.6：设置里「关于」一行（版本号、隐私政策、服务条款），账号页「导出我的数据」
/// 走真后端拿到一份 JSON 并弹出系统分享面板。账号是这次现造的 qa_ 账号。
@MainActor final class AccountExportUITests: XCTestCase {
  private let api = "https://kanpan.107-174-172-10.sslip.io"
  private var app: XCUIApplication!
  private var account: (name: String, password: String)?

  override func setUp() async throws {
    continueAfterFailure = false
    XCUIDevice.shared.orientation = .portrait
  }
  override func tearDown() async throws {
    app?.terminate()
    // 线上后端上现造的号，做完就注销，不留垃圾账号。
    if let account { await closeAccount(account.name, account.password) }
  }

  func testAboutRowAndExportOpensShareSheet() async throws {
    let name = "qa_export_" + UUID().uuidString.replacingOccurrences(of: "-", with: "").prefix(12).lowercased()
    let password = UUID().uuidString + "a1"
    try await register(name, password)
    account = (name, password)
    print("导出验收账号：\(name)")

    app = XCUIApplication()
    app.launchEnvironment = ["KANPAN_TEST_PROFILE": "1", "KANPAN_PERSISTENCE_PROFILE": UUID().uuidString,
                             "KANPAN_ACCOUNT_API_URL": api]
    app.launch()

    // 「关于」：版本号与构建号一行，右边两条链接。
    tap("bottom.settings")
    let about = app.descendants(matching: .any)["settings.about"]
    for _ in 0..<6 where !about.isHittable { app.swipeUp() }
    XCTAssertTrue(about.waitForExistence(timeout: 10), "设置里没有「关于」")
    let version = app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH 'Hkline '")).firstMatch
    XCTAssertTrue(version.exists, "「关于」没写版本号")
    XCTAssertTrue(app.links["隐私政策"].exists || app.buttons["settings.privacy"].exists, "没有隐私政策链接")
    XCTAssertTrue(app.links["服务条款"].exists || app.buttons["settings.terms"].exists, "没有服务条款链接")
    attach("01-设置-关于")

    // 登录 → 账号页 → 导出。
    for _ in 0..<6 where !app.buttons["settings.account"].isHittable { app.swipeDown() }
    tap("settings.account")
    let username = app.textFields["account.email"]
    XCTAssertTrue(username.waitForExistence(timeout: 10)); username.tap(); username.typeText(name)
    let secure = app.secureTextFields["account.password"]; secure.tap(); secure.typeText(password)
    tap("account.submit")
    XCTAssertTrue(wait(45) { !self.app.accountView.exists }, "登录未完成")
    // 登录成功会回到图表页，再从底栏回设置。
    if !app.buttons["settings.account"].waitForExistence(timeout: 3) { tap("bottom.settings") }
    for _ in 0..<6 where !app.buttons["settings.account"].isHittable { app.swipeDown() }
    tap("settings.account")
    tap("account.export")
    attach("02-账号页-导出")
    // 系统分享面板的标题里是文件名。
    let sheet = app.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS 'Hkline-我的数据'")).firstMatch
    XCTAssertTrue(sheet.waitForExistence(timeout: 30), "导出后没弹出分享面板：\(app.debugDescription)")
    XCTAssertFalse(app.staticTexts["account.error"].exists, "导出报错")
    attach("03-系统分享面板")
  }

  private func register(_ name: String, _ password: String) async throws {
    var request = URLRequest(url: URL(string: api + "/v1/auth/register")!)
    request.httpMethod = "POST"; request.timeoutInterval = 30
    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
    let device = ["id": UUID().uuidString, "name": "导出验收", "secret": UUID().uuidString + UUID().uuidString, "kind": "desktop"]
    request.httpBody = try JSONSerialization.data(withJSONObject: ["username": name, "password": password, "device": device])
    let (_, response) = try await URLSession.shared.data(for: request)
    XCTAssertTrue((200..<300).contains((response as! HTTPURLResponse).statusCode), "注册失败")
  }
  private func closeAccount(_ name: String, _ password: String) async {
    func post(_ path: String, _ method: String, _ body: [String: Any], token: String? = nil) async -> Data? {
      var request = URLRequest(url: URL(string: api + path)!)
      request.httpMethod = method; request.timeoutInterval = 30
      request.setValue("application/json", forHTTPHeaderField: "Content-Type")
      if let token { request.setValue("Bearer " + token, forHTTPHeaderField: "Authorization") }
      request.httpBody = try? JSONSerialization.data(withJSONObject: body)
      return try? await URLSession.shared.data(for: request).0
    }
    let device = ["id": UUID().uuidString, "name": "导出验收", "secret": UUID().uuidString + UUID().uuidString, "kind": "desktop"]
    guard let data = await post("/v1/auth/login", "POST", ["username": name, "password": password, "device": device]),
          let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
          let token = (object["data"] as? [String: Any])?["accessToken"] as? String else { return }
    _ = await post("/v1/auth/account", "DELETE", ["password": password], token: token)
  }
  private func tap(_ id: String) {
    let button = app.buttons[id]; XCTAssertTrue(button.waitForExistence(timeout: 12), id)
    button.tap()
  }
  private func wait(_ seconds: Double, _ predicate: @escaping () -> Bool) -> Bool {
    XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in predicate() }, object: nil)], timeout: seconds) == .completed
  }
  private func attach(_ name: String) {
    let shot = XCUIScreen.main.screenshot()
    let attachment = XCTAttachment(screenshot: shot)
    attachment.name = name; attachment.lifetime = .keepAlways; add(attachment)
    let dir = URL(fileURLWithPath: "/tmp/kanpan-p36", isDirectory: true)
    try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    try? shot.pngRepresentation.write(to: dir.appendingPathComponent(name + ".png"))
  }
}
