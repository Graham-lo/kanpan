import XCTest

// ============================================================ iPad 版面体检
//
// 2026-09-18 用户给 iPad 定的口径是「不破」：每一页在 iPad 全部宽度下不错位、
// 不拉伸、可用——不做宽屏分栏布局。整套界面是照 iPhone 宽度画的，所以真正会「破」
// 的是那几张**铺满整屏**的页：搜索页、品种整页、复盘本。它们都是「左边一个名目、
// 右边一个数」的行，13" iPad 横屏铺满就是 1300pt，品种名钉在最左、价格钉在最右，
// 中间一片空白，对不上号。
//
// `readableColumn(560)` 给这几页封了顶，这个类就是那道封顶的看门人：每台 iPad 上
// 把这几页走一遍，量关键控件的宽度，顺手留一张截图。
//
// ------------------------------------------------------------ 审查 C-04 / C.9
//
// 第五轮审查把这一组用例点了名：复盘那条把宽度断言放在 `if segment.exists` 里，
// 于是**分段控件不存在时整块断言不执行、用例照样绿**——「测试说复盘页在 iPad 上
// 没破，但它其实只看到了未登录页」。搜索那条的 `if all.waitForExistence` 是同一种
// 写法。这一轮把它们全部改成硬断言：
//
//   * 「查看全部」必须出现，必须真的过到品种整页，再量宽度；
//   * 复盘本拆成两条——**未登录**那条钉「登录门本身也得是封顶的一列」，
//     **已登录**那条先注册一个一次性账号真的进到复盘本里，确认登录门已经不在了，
//     才去量分段控件的宽度。两条都不许因为「控件不在」而略过核心断言。
//
// 唯一保留的前置是窗口宽度（`skipUnlessWide`）：它是**设备适用范围声明**，不是
// 假绿——这几条量的是「宽屏下别拉开」，iPhone 上无从谈起。按审查的要求，跳过时
// 明确把「未执行」记成附件，不许被读成通过；真正的执行证据来自 iPad 模拟器那一轮。
@MainActor
final class IPadLayoutUITests: KanpanUICase {
  /// 内容列的上限（`readableColumn` 的 560）再加一点余量：控件自己还有内边距，
  /// 量出来只会比 560 小；留 600 是为了不被 1pt 的舍入判红。
  static let columnCap: CGFloat = 600

  private func skipUnlessWide() throws {
    try IPadWide.skipUnlessWide(self, width: windowFrame.width)
  }

  private func shot(_ name: String) {
    let a = XCTAttachment(screenshot: app.screenshot())
    a.name = name; a.lifetime = .keepAlways; add(a)
  }

  /// 搜索页与品种整页：满屏的一列品种行，封顶之后仍该是居中的一条，不许两端拉开。
  func testSearchAndSymbolPagesKeepAReadableColumn() throws {
    try skipUnlessWide()

    app.buttons[Ids.searchButton].tap()
    let query = app.textFields[Ids.searchQuery]
    expectExists(query, Self.long, "顶栏放大镜没开搜索页")
    shot("iPad-搜索页")
    XCTAssertLessThanOrEqual(query.frame.width, Self.columnCap,
                             "搜索框被拉到 \(Int(query.frame.width))pt，内容列没封住")

    // 打一个一定超过七条的词。「BTC」在这张合约表里只命中三条（BTCUSDT、
    // BTCDOMUSDT、PUMPBTCUSDT），凑不出「查看全部」那一行——所以这儿用「USD」，
    // 每一条 U 本位合约都算命中。
    query.typeText("USD")
    // 硬断言（审查 C-04）：「查看全部 N 个品种」那一行必须出现，出不来就是搜索或
    // 目录坏了，不是「这条用例的主角不在」。原来这儿是 `if all.waitForExistence`，
    // 走 else 分支照样绿，正是审查点名的那种假绿。
    let all = app.buttons[Ids.searchAll]
    expectExists(all, Self.long, "搜「USD」之后没有「查看全部」那一行——目录没到，或者搜索断了")
    all.tap()
    let symbolsQuery = app.textFields[Ids.symbolsQuery]
    expectExists(symbolsQuery, Self.long, "「查看全部」没过到品种整页")
    shot("iPad-品种整页")
    XCTAssertLessThanOrEqual(symbolsQuery.frame.width, Self.columnCap,
                             "品种整页的搜索框被拉到 \(Int(symbolsQuery.frame.width))pt")
    // 目录那一列也要封顶：品种整页真正铺满屏幕的是这些行，不是顶上的输入框。
    let row = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "symbols.row."))
      .firstMatch
    expectExists(row, Self.long, "品种整页上一行品种都没有")
    XCTAssertLessThanOrEqual(row.frame.width, Self.columnCap,
                             "品种整页的行被拉到 \(Int(row.frame.width))pt，目录没封顶")
    app.buttons[Ids.symbolsBack].tap()
  }

  /// 复盘本 · 未登录：登录门这一页本身也归内容列管。
  ///
  /// 这条**不是**「只看到了未登录页也算过」——它钉的就是未登录这个明确 fixture：
  /// 分段控件必须在（它和登录状态无关，`ReviewBook` 一进来就画），「战绩」那一档
  /// 必须给出登录门 `review.stats.login`，而且这几件东西都得在 560 的一列里。
  func testReviewBookLoginGateKeepsAReadableColumn() throws {
    try skipUnlessWide()

    app.buttons[Ids.topReview].tap()
    expectExists(app.buttons["review.back"], Self.long, "顶栏的「复盘」没开复盘本")
    shot("iPad-复盘本-未登录")

    let tabs = app.segmentedControls.firstMatch
    expectExists(tabs, Self.short, "复盘本上没有「待办 / 记录 / 战绩」分段控件")
    XCTAssertLessThanOrEqual(tabs.frame.width, Self.columnCap,
                             "复盘本的分段控件被摊到 \(Int(tabs.frame.width))pt")

    let stats = tabs.buttons["战绩"]
    expectExists(stats, Self.short, "分段控件里没有「战绩」")
    stats.tap()
    let gate = app.buttons["review.stats.login"]
    expectExists(gate, Self.long, "未登录的「战绩」应当只给一句话加一颗「登录」，没见到登录门")
    XCTAssertLessThanOrEqual(gate.frame.width, Self.columnCap,
                             "登录门那一行被摊到 \(Int(gate.frame.width))pt")
    shot("iPad-复盘本-登录门")
    app.buttons["review.back"].tap()
  }
}

// ============================================================ 复盘本 · 已登录
//
// 审查 C-04 要的第二个 fixture：**真的进到复盘本里**再量宽度。
// 办法和 `AccountPreferenceSyncUITests` 一样——在项目自己的后端上注册一个一次性
// 账号（随机用户名 + 现造的测试口令），量完当场注销；`tearDown` 再按 HTTP 补一刀，
// 不给后端留垃圾数据，也绝不碰用户的真账号。
@MainActor
final class IPadReviewBookSignedInUITests: KanpanUICase {
  private static let api = "https://kanpan.107-174-172-10.sslip.io"
  private static let password = "Testpass2026"
  /// 这一轮建过、还没确认删掉的账号。断言中途失败时兜底用。
  private var created: [String] = []

  override var extraLaunchEnvironment: [String: String] {
    ["KANPAN_PERSISTENCE_PROFILE": UUID().uuidString,
     "KANPAN_ACCOUNT_API_URL": Self.api]
  }

  override func tearDown() async throws {
    let leftovers = created
    created = []
    for name in leftovers { await forceDelete(name) }
    try await super.tearDown()
  }

  func testSignedInReviewBookKeepsAReadableColumn() throws {
    try IPadWide.skipUnlessWide(self, width: windowFrame.width)

    let user = "ipad_" + UUID().uuidString.replacingOccurrences(of: "-", with: "").prefix(12).lowercased()
    created.append(user)
    register(user)

    // 注册成功之后落地页由 `onProfileReady()` 决定，先回行情页——顶栏的「复盘」在那儿。
    app.buttons[Ids.bottomChart].tap()
    let entry = app.buttons[Ids.topReview]
    expectExists(entry, Self.long, "登录之后行情页顶栏上没有「复盘」")
    entry.tap()
    expectExists(app.buttons["review.back"], Self.long, "顶栏的「复盘」没开复盘本")

    let tabs = app.segmentedControls.firstMatch
    expectExists(tabs, Self.short, "复盘本上没有「待办 / 记录 / 战绩」分段控件")
    let stats = tabs.buttons["战绩"]
    expectExists(stats, Self.short, "分段控件里没有「战绩」")
    stats.tap()
    // 先证明「真的进到已登录的复盘本里了」，再量宽度（审查 C-04 的要害）。
    XCTAssertTrue(waitUntil(timeout: Self.long) { !self.app.buttons["review.stats.login"].exists },
                  "已登录却还挂着登录门 review.stats.login——这一条量的还是未登录页")
    shot("iPad-复盘本-已登录")

    XCTAssertLessThanOrEqual(tabs.frame.width, IPadLayoutUITests.columnCap,
                             "已登录的复盘本里分段控件被摊到 \(Int(tabs.frame.width))pt")
    // 内容那一列同样封顶：战绩这一页铺满屏幕的是列表，不是分段控件。
    let list = app.collectionViews.firstMatch.exists ? app.collectionViews.firstMatch
                                                     : app.tables.firstMatch
    expectExists(list, Self.short, "战绩页上没有列表")
    XCTAssertLessThanOrEqual(list.frame.width, IPadLayoutUITests.columnCap,
                             "战绩列表被摊到 \(Int(list.frame.width))pt，内容列没封住")

    app.buttons["review.back"].tap()
    closeAccount(user)
  }

  // ------------------------------------------------------------ 账号

  private func shot(_ name: String) {
    let a = XCTAttachment(screenshot: app.screenshot())
    a.name = name; a.lifetime = .keepAlways; add(a)
  }

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

  /// 口令要逐字符敲：整串 `typeText` 会被 iOS 的「强密码」建议气泡吃掉，只剩最后一个字符。
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
                  "注册 \(username) 没有闭合账号页，页面报错=\(errorText())")
  }

  /// 「注销账号」要再输一次口令。删成功之后 `AccountFeature` 自己会退登并收起账号页。
  private func closeAccount(_ username: String) {
    openAccountPage()
    let entry = app.buttons["注销账号"]
    expectExists(entry, Self.long, "账号页上没有「注销账号」")
    entry.tap()
    fill(username: nil)
    app.buttons["account.submit"].tap()
    XCTAssertTrue(waitUntil(timeout: 60) { !self.app.otherElements["account.view"].exists },
                  "注销 \(username) 没完成，页面报错=\(errorText())")
    created.removeAll { $0 == username }
  }

  private func errorText() -> String {
    let label = app.staticTexts["account.error"]
    return label.exists ? label.label : "（页面上没有报错）"
  }

  /// UI 那条注销路径没走完时，直接按 HTTP 把账号删掉。账号已经不在了就什么都不做。
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

// ============================================================ 设备适用范围
//
// 窗口不到 700pt 宽时这几条无从谈起（iPhone、iPad 的窄分屏）。
// 审查的要求是：**跳过必须被记成「未执行」，不许读成通过**——所以除了 `XCTSkip`
// 之外再挂一张附件，把当时的窗口宽度写进结果里。
enum IPadWide {
  static func skipUnlessWide(_ test: XCTestCase, width: CGFloat) throws {
    guard width <= 700 else { return }
    let note = XCTAttachment(string: "未执行：窗口只有 \(Int(width))pt 宽，内容列封顶这件事只在宽屏 iPad 上成立。")
    note.name = "iPad 版面体检-未执行"
    note.lifetime = .keepAlways
    test.add(note)
    throw XCTSkip("窗口只有 \(Int(width))pt 宽，封顶这件事无从谈起（未执行，不等于通过）")
  }
}
