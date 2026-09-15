import XCTest

/// 临时用例：把「注册 → 退出 → 错密码 → 正确密码」整条账号链路在真机上走一遍。验完即删。
///
/// 不继承 `KanpanUICase`：那个底座不给 `KANPAN_ACCOUNT_API_URL`，而 `wireAccount()` 在
/// 「测试档案 + 没配端点」时会整个跳过（`MainScreen.swift`），账号功能只装了一半。
/// 账号用例必须自己把端点配上，这也是那行注释里写的做法。
@MainActor
final class ZAccountLoginUITests: XCTestCase {
  private var app: XCUIApplication!
  private static let short: TimeInterval = 8
  private static let long: TimeInterval = 30

  override func setUp() async throws {
    continueAfterFailure = false
    app = XCUIApplication()
    app.launchEnvironment["KANPAN_TEST_PROFILE"] = "1"
    app.launchEnvironment["KANPAN_PERSISTENCE_PROFILE"] = UUID().uuidString
    app.launchEnvironment["KANPAN_ACCOUNT_API_URL"] = "https://kanpan.107-174-172-10.sslip.io"
    app.launch()
    XCTAssertTrue(app.buttons["top.symbol"].waitForExistence(timeout: Self.long), "启动后没见到顶栏")
  }

  override func tearDown() async throws { app = nil }

  private func wait(_ timeout: TimeInterval = long, _ cond: () -> Bool) -> Bool {
    let deadline = Date().addingTimeInterval(timeout)
    while Date() < deadline {
      if cond() { return true }
      _ = XCTWaiter.wait(for: [XCTestExpectation(description: "poll")], timeout: 0.25)
    }
    return cond()
  }

  private var errorText: String {
    app.staticTexts["account.error"].exists ? app.staticTexts["account.error"].label : "（无提示）"
  }

  /// 逐个字段确认「点进去 → 真的敲进去了」，不然错的是用例而不是 app。
  private func fill(_ user: String?, _ password: String) {
    if let user {
      let field = app.textFields["account.email"]
      XCTAssertTrue(field.waitForExistence(timeout: Self.short), "没有用户名输入框")
      field.tap()
      // 退出登录后 app 会把用户名留在框里（省得下次重敲），所以这里先清干净再填。
      if let old = field.value as? String, old != "用户名", !old.isEmpty {
        field.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: old.count + 4))
      }
      field.typeText(user)
      XCTAssertEqual(field.value as? String, user, "用户名没敲进去")
    }
    let pw = app.secureTextFields["account.password"]
    XCTAssertTrue(pw.waitForExistence(timeout: Self.short), "没有密码输入框")
    pw.tap()
    // 逐字敲，区分「app 把字吃了」和「XCUITest 一次性灌太快」。
    for ch in password {
      pw.typeText(String(ch))
      _ = XCTWaiter.wait(for: [XCTestExpectation(description: "key")], timeout: 0.08)
    }
    // 安全输入框只回 “••••”，位数对上就说明焦点没跑偏。
    XCTAssertEqual((pw.value as? String)?.count, password.count, "密码没敲进密码框，实收：\(String(describing: pw.value))")
    if let user { XCTAssertEqual(app.textFields["account.email"].value as? String, user, "密码敲串到用户名框里了") }
  }

  func testRegisterLogoutLoginOnDevice() {
    // 现造一组凭据，源码里不留任何真实口令。
    let stamp = String(Int(Date().timeIntervalSince1970))
    let user = "dev\(stamp)", password = "Dev\(stamp)"
    print("PROBE_USER \(user)")

    app.buttons["bottom.settings"].tap()
    let row = app.buttons["settings.account"]
    XCTAssertTrue(row.waitForExistence(timeout: Self.short), "「设置」里没有账号那一行")
    row.tap()
    XCTAssertTrue(app.buttons["account.submit"].waitForExistence(timeout: Self.short), "点账号行没开出登录页")
    // 一进门就报错，说明打包时没带上后端地址（`KanpanAccountAPIURL`）。
    XCTAssertFalse(app.staticTexts["account.error"].exists, "刚进登录页就报错：\(errorText)")

    // ---- 先在「登录」页试一遍密码框：这页用的是 .password，注册页用的是 .newPassword，
    // 两页表现不同就说明是 AutoFill 把输入吃了。
    fill(user, password)
    app.buttons["account.submit"].tap()
    XCTAssertTrue(wait { self.app.staticTexts["account.error"].exists }, "查无此人却一声不吭")
    XCTAssertTrue(errorText.contains("不对"), "登录未注册账号，提示成了：\(errorText)")

    // ---- 注册（用户名跟着翻页留在框里，这里只补密码）
    app.buttons["注册"].tap()
    XCTAssertEqual(app.textFields["account.email"].value as? String, user, "翻到注册页用户名丢了")
    fill(nil, password)
    app.buttons["account.submit"].tap()
    // 注册/登录成功后整张账号页自己收起来（`accept()` 里 presented = false），
    // 所以这里等的是「弹层没了」，再从设置里重新点进去看账号状态。
    XCTAssertTrue(wait { !self.app.buttons["account.submit"].exists }, "注册没成功，提示：\(errorText)")
    XCTAssertTrue(openAccount(), "登录后再点账号行没看到账号页")

    // ---- 退出登录（`logout()` 同样会把弹层收起来）
    app.buttons["退出登录"].tap()
    XCTAssertTrue(wait { !self.app.buttons["退出登录"].exists }, "点了退出登录没反应")
    XCTAssertTrue(openLogin(), "退出后再点账号行没回到登录页")

    // ---- 错密码该挨一句「用户名或密码不对」
    fill(user, password + "zz")
    app.buttons["account.submit"].tap()
    XCTAssertTrue(wait { self.app.staticTexts["account.error"].exists }, "错密码登录一声不吭")
    XCTAssertTrue(errorText.contains("不对"), "错密码提示成了：\(errorText)")

    // ---- 正确密码（用户名还留在框里，只重填密码）
    let pw = app.secureTextFields["account.password"]
    pw.tap()
    pw.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: password.count + 6))
    pw.typeText(password)
    app.buttons["account.submit"].tap()
    XCTAssertTrue(wait { !self.app.buttons["account.submit"].exists }, "正确密码登录不进去，提示：\(errorText)")
    XCTAssertTrue(openAccount(), "重新登录后账号页打不开")
  }

  /// 从设置里重新点开账号页；`marker` 是这一页该有的那颗按钮。
  ///
  /// 注意：底栏的「设置」是个开关。弹层收起来的那一两帧里设置面板还没恢复可访问，
  /// 这时候去点「设置」反而会把本来就开着的面板关掉，所以先多等一会儿再决定要不要点。
  private func openSheet(_ marker: String) -> Bool {
    let row = app.buttons["settings.account"]
    // 登录/退出成功后 app 会自己把侧栏收掉（`AppAccountBridge.onSwitch` → `dismissPanel()`）。
    // 收的那 0.3 秒里账号行还在树上但点不着，这时候去点反而会把刚开的面板又关掉，
    // 所以先等它彻底消失、或者等它真的可点，再决定下一步。
    if !wait(4, { row.exists && row.isHittable }) {
      guard wait(Self.short, { !row.exists }) else { print("SHEET \(marker): 账号行一直卡在不可点"); return false }
      app.buttons["bottom.settings"].tap()
      guard wait(Self.short, { row.exists && row.isHittable }) else { print("SHEET \(marker): 点了设置也没见到账号行"); return false }
    }
    row.tap()
    let ok = wait(Self.short) { self.app.buttons[marker].exists }
    print("SHEET \(marker): \(ok ? "开出来了" : "没开出来")")
    return ok
  }
  private func openAccount() -> Bool { openSheet("退出登录") }
  private func openLogin() -> Bool { openSheet("account.submit") }
}
