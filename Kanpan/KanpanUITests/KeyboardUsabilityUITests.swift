import XCTest

// ============================================================ 审查 C.10 第 8 条
//
// 「键盘实际可用」。报告点的不是「键盘弹不弹得出来」——那件事早有用例——而是
// 键盘**起来之后**那半块屏：输入框和这一步的主动作有没有被它压在底下、
// 搜索页一进来就自己弹不弹、锁没锁 ASCII、收起之后图表高度回不回得来、
// 键盘那层挡板上的点会不会穿透到底下的控件去。
//
// 这几件事都只有把键盘真的叫起来、量它的上沿才说得清，
// 所以这一条从头到尾都在跟 `app.keyboards` 的 `frame` 打交道。
//
// 复盘那条长备注不在这儿：它在 `KanpanReview`，本轮不归这一摊改。
@MainActor
final class KeyboardUsabilityUITests: KanpanUICase {

  /// 键盘本体。存在性各处自己断言，这儿只管取。
  private var keyboard: XCUIElement { app.keyboards.element(boundBy: 0) }

  /// 键盘上沿。人能看见、能点到的东西都必须在这条线以上。
  private func keyboardTop() -> CGFloat { keyboard.frame.minY }

  // ------------------------------------------------------------ 搜索

  /// 搜索页：进来键盘自己上来、焦点就在框里；打的是 ASCII；
  /// 键盘不压输入框也不压第一条结果；退出去图表高度原样回来。
  ///
  /// **这一页自动聚焦是对的。** 用户 2026-09-18 把两种搜品种的口子分开定了：
  /// 画线工作台里点品种名弹的那层浮层，主体是底下那格「常看」，键盘一上来就把它盖了，
  /// 所以那儿不许自动弹（那一条由 `ChartFoundationUITests
  /// .testDrawingSymbolSwitcherKeepsKeyboardDown` 守着）；而整页搜索页是用户自己点
  /// 「搜索」进来的，进来就是为了打字，「那儿自动聚焦是对的」。
  /// 报告 C.10 第 8 行里那句「搜索初始无键盘」说的是前者，别套到这一页上。
  func testSearchKeyboardIsAutomaticAsciiAndGivesTheChartBack() {
    let heightBefore = chartBottom - chartTop
    XCTAssertTrue(app.openSymbolSearch(), "顶栏放大镜没开出搜索页")

    // 一、键盘自己上来。
    XCTAssertTrue(app.keyboards.element.waitForExistence(timeout: Self.short),
                  "从「搜索」进来，键盘没有自己上来（这一页该自动聚焦）")

    // 二、ASCII，而且焦点真的落在那个框上：**不点它**，直接打字，字必须进框里。
    // 品种代号全是英文，键盘锁了 `.asciiCapable`：三个字母要**原样**落进去
    // （中文输入法那一档得先过候选区，落不成这样），键盘上也摆着英文字母键。
    let field = app.textFields[Ids.searchQuery]
    expectExists(field, Self.short, "搜索页上没有输入框")
    field.typeText("BTC")
    XCTAssertTrue(waitUntil(timeout: Self.short) { (field.value as? String) == "BTC" },
                  "打了 BTC，框里是「\(field.value as? String ?? "?")」")
    XCTAssertTrue(app.keyboards.keys["B"].exists || app.keyboards.keys["b"].exists,
                  "键盘上找不到英文字母键，八成没锁 ASCII")

    // 四、键盘不压输入框，也不压第一条结果。
    let top = keyboardTop()
    XCTAssertLessThan(field.frame.maxY, top, "搜索框被键盘盖住了（框底 \(field.frame.maxY)，键盘顶 \(top)）")
    let row = app.buttons["symbols.row.binance/usd_m/BTCUSDT"]
    expectExists(row, Self.long, "搜 BTC 没出 BTCUSDT 这一行")
    XCTAssertLessThan(row.frame.maxY, top,
                      "第一条结果压在键盘底下（行底 \(row.frame.maxY)，键盘顶 \(top)）")

    // 五、收起来：图表高度要原样回来，不许被键盘那一下留下的内边距吃掉一截。
    app.buttons["search.cancel"].tap()
    expectGone(app.textFields[Ids.searchQuery], Self.short, "搜索页取消没关掉")
    XCTAssertTrue(waitUntil(timeout: Self.short) { self.app.keyboards.element.exists == false },
                  "退出搜索页，键盘还杵在屏幕上")
    XCTAssertTrue(waitUntil(timeout: Self.short) { self.app.buttons[Ids.intervalMore].exists },
                  "退出搜索页没回到行情页")
    let heightAfter = app.buttons[Ids.bottomFavorites].frame.minY - app.buttons[Ids.intervalMore].frame.maxY
    XCTAssertEqual(heightAfter, heightBefore, accuracy: 1,
                   "键盘走了图区没长回去：\(heightBefore) → \(heightAfter)")
  }

  // ------------------------------------------------------------ 指标参数

  /// 指标参数：数字键盘起来时，参数框和「保存」都得在键盘上沿以内；
  /// 这时候点面板外面，那一下不许穿透到底下的 K 线上；后台转一圈回来，打的字还在。
  func testIndicatorParamKeyboardKeepsTheMainActionReachableAndDoesNotLeakTaps() {
    openIndicatorEditor()
    let field = app.textFields["indicator.param.0.field"]
    expectExists(field, Self.short, "指标编辑器里没有第一格参数")
    field.tap()
    XCTAssertTrue(app.keyboards.element.waitForExistence(timeout: Self.short), "点了参数格键盘没上来")
    field.typeText("42")

    let top = keyboardTop()
    XCTAssertLessThan(field.frame.maxY, top, "参数框被键盘盖住了（框底 \(field.frame.maxY)，键盘顶 \(top)）")
    let save = app.buttons["indicator.save"]
    expectExists(save, Self.short, "指标编辑器里没有「保存」")
    XCTAssertLessThan(save.frame.maxY, top,
                      "这一步的主动作「保存」压在键盘底下（\(save.frame.maxY) vs \(top)）")
    XCTAssertTrue(save.isHittable, "「保存」够得着的位置上却点不到")

    // 后台转一圈：回来打的字还在，编辑器也还开着。
    XCUIDevice.shared.press(.home)
    app.activate()
    XCTAssertTrue(waitUntil(timeout: Self.long) { field.exists },
                  "从后台回来，指标编辑器没了")
    XCTAssertEqual(field.value as? String, "42", "从后台回来，框里打了一半的字丢了")

    // 面板外面那一下不许穿透：图上不能因此出十字线。
    let before = chartInfo()
    chartPoint().tap()
    let after = waitUntil(timeout: 2) { self.chartInfo()["crosshair"] as? Bool == true }
    XCTAssertFalse(after, "点在面板外面，那一下穿到 K 线上去了（点前 crosshair=\(String(describing: before["crosshair"]))）")
  }

  // ------------------------------------------------------------ 账号

  /// 账号页：用户名、密码、这一步的主动作、以及失败之后那行红字，
  /// 键盘起来时都得看得见（够不着的就得能滚到）。后台转一圈，打的用户名还在。
  ///
  /// 走的是**登录**，而且用一个随机的用户名配一个错口令：服务端只会答一句不对，
  /// 不会在生产库里留下任何账号（注册才会），这条因此可以挂进常规回归。
  func testAccountFormAndItsErrorStayReachableWithTheKeyboardUp() {
    openSettingsPage()
    let entry = app.buttons["settings.account"]
    expectExists(entry, Self.short, "设置整页上没有账号入口")
    entry.tap()
    expectExists(app.descendants(matching: .any).matching(identifier: "account.view").firstMatch,
                 Self.short, "账号页没开")

    let user = app.textFields["account.email"]
    expectExists(user, Self.short, "登录页上没有用户名框")
    user.tap()
    XCTAssertTrue(app.keyboards.element.waitForExistence(timeout: Self.short), "点了用户名框键盘没上来")
    // 用户名只许字母、数字、下划线（`AccountCredentialRules`，审查 U14 起边输边校验、不合格主按钮置灰）：
    // 原来写的「kb-probe-…」带连字符，主按钮一直是灰的，点了什么都不发，自然等不到那行错。
    user.typeText("kb_probe_" + UUID().uuidString.prefix(8).lowercased())
    XCTAssertLessThan(user.frame.maxY, keyboardTop(), "用户名框被键盘盖住了")

    let password = app.secureTextFields["account.password"]
    expectExists(password, Self.short, "登录页上没有口令框")
    password.tap()
    password.typeText("definitely-not-the-password")
    XCTAssertTrue(waitUntil(timeout: Self.short) { password.frame.maxY < self.keyboardTop() },
                  "口令框被键盘盖住了（框底 \(password.frame.maxY)，键盘顶 \(keyboardTop())）")
    let submit = app.buttons["account.submit"]
    expectExists(submit, Self.short, "登录页上没有主按钮")
    XCTAssertTrue(waitUntil(timeout: Self.short) { submit.frame.maxY < self.keyboardTop() },
                  "「登录」压在键盘底下（\(submit.frame.maxY) vs \(keyboardTop())）")

    // 后台转一圈：用户名还在（这条路上最容易丢字的就是它——系统密码面板会把 app 顶到后台）。
    let typed = user.value as? String
    XCUIDevice.shared.press(.home)
    app.activate()
    XCTAssertTrue(waitUntil(timeout: Self.long) { user.exists }, "从后台回来账号页没了")
    XCTAssertEqual(user.value as? String, typed, "从后台回来，用户名被清了")

    // 打出那行错，再把键盘叫回来：红字和主按钮都还得在键盘上沿以内。
    XCTAssertFalse(app.staticTexts["account.email.rule"].exists, "测试用户名本身不合规则，主按钮是灰的")
    XCTAssertTrue(submit.isEnabled, "用户名、口令都填了，「登录」还是灰的")
    submit.tap()
    let error = app.staticTexts["account.error"]
    XCTAssertTrue(error.waitForExistence(timeout: Self.long),
                  "用错口令登录，页面上没有任何说法\n\(app.debugDescription)")
    let shot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
    shot.name = "账号-错口令红字"
    shot.lifetime = .keepAlways
    add(shot)
    password.tap()
    XCTAssertTrue(app.keyboards.element.waitForExistence(timeout: Self.short), "再点口令框键盘没回来")
    XCTAssertTrue(waitUntil(timeout: Self.short) { error.frame.maxY < self.keyboardTop() },
                  "那行错被键盘压住了（字底 \(error.frame.maxY)，键盘顶 \(keyboardTop())）")
    XCTAssertTrue(waitUntil(timeout: Self.short) { submit.frame.maxY < self.keyboardTop() },
                  "出错之后「登录」压在键盘底下了")

    app.buttons["account.back"].tap()
  }
}
