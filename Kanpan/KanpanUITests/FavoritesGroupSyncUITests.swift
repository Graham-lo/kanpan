import XCTest

// ============================================================ 停在哪一类跟着人走
//
// 用户 2026-09-19 报的现象：「在 A 手机上把自选页停在第二个分类上，换到 B 手机（同一个
// 账号）打开自选页，停的还是第一个分类，不是他上次看的那一类。」
//
// 根因是「停在哪一类」当年住在 `SymbolPrefs.selectedGroupID` 里，而那个字段按
// `SymbolFieldPlan` 是 `localOnly`——它压根不上云。换台设备读不到，`SymbolPrefs.group(_:)`
// 就退回 `groups.first`，于是永远停在第一类。提交 `8f6f883` 把它搬成了
// `Prefs.favoritesGroup`（`PrefsFieldPlan` 里归 `.synced`，服务端白名单也已经放行），
// 这条用例钉的就是「搬完之后那个现象没了」。
//
// **两台「设备」怎么模拟**：同一个模拟器、同一个 app，靠两个不同的
// `KANPAN_PERSISTENCE_PROFILE`（各自一棵档案子树、各自一份 keychain）当 A 和 B——
// 和 `AccountPreferenceSyncUITests` 用一个档案走「换号」是同一套手法的另一半：
// 那条用例是一台机器两个人，这条是两台机器一个人。
//
// 断言一律读界面：分类胶囊的选中态（`FavoritesView.chip` 给选中那格加了 `.isSelected`
// trait）加上列表里露出来的那一行。**不许去翻 prefs.json 绕过 UI**——用户看见的是
// 界面停在哪一类，不是文件里写着什么。
//
// 后端是项目自己那台（`KANPAN_ACCOUNT_API_URL`），账号是现造的 `test_` 随机名加测试口令。
// 正常路径由 B 设备走完 UI 上的「注销账号」把它删掉；中途断言失败没走到那一步时，
// `tearDown` 按 HTTP 再补一刀，不给线上留垃圾账号。
@MainActor final class FavoritesGroupSyncUITests: XCTestCase {
  private let password = "Testpass2026"
  private let api = "https://kanpan.107-174-172-10.sslip.io"
  /// A 设备与 B 设备各自的档案。两棵子树互不相通，只有账号把它们连起来。
  private let profileA = UUID().uuidString
  private let profileB = UUID().uuidString
  private let account = "test_" + UUID().uuidString.replacingOccurrences(of: "-", with: "").prefix(12).lowercased()
  /// 两个分类怎么来的：**第一个自动，第二个手建**。
  ///
  /// 一条自选都还没有的时候加一个币，`SymbolPickerModel.addFavorite` 按品种类型
  /// （`FavoriteCategory`）建出「加密」并选中它。此后再加的品种就**留在当下这一类**里，
  /// 不再按类型另起一类——这是用户 2026-09-20 定的规矩（`addFavorite` 里那句
  /// `guard prefs.groupForSymbol[key] == nil`：「从某一类里点搜索加进来的品种要留在那一类」）。
  /// 这条用例 2026-09-19 写的时候还没有那条规矩，于是原来那句「再加一支美股，分类条上
  /// 就自己多一格『美股』」从此不成立：AAPLUSDT 会乖乖落进「加密」，分类条上只有一格。
  ///
  /// 所以第二类改成照用户自己的路建：「…」→「新建分类」→ 打「美股」→「保存」，
  /// 建完这一格自己就选中了，站在它里面加 AAPLUSDT，那支股就落在它里面。
  /// 这条用例要验的东西没变——它验的是「停在哪一类」跟不跟着账号走，
  /// 不是「分类是怎么冒出来的」。
  /// 用户说的「第一个分类」就是「加密」，「上次看的那一类」是「美股」。
  private let first = "加密"
  private let second = "美股"
  /// 后端上还没确认删掉的账号。断言中途失败时兜底用。
  private var created: [String] = []

  override func tearDown() async throws {
    let leftovers = created
    created = []
    for name in leftovers { await forceDelete(name) }
  }

  // ------------------------------------------------------------ 正题

  /// 「换台设备打开自选，停的还是第一个分类，不是他上次看的那一类。」
  func testSelectedFavoriteGroupFollowsTheAccountToAnotherDevice() throws {
    continueAfterFailure = false

    // ---- A 设备：注册、摆两个分类、停在第二个
    let a = makeApp(profile: profileA)
    a.launch()
    XCTAssertTrue(a.buttons["bottom.settings"].waitForExistence(timeout: 90),
                  "A 设备（profile=\(profileA)）起了 90s 还没见到底栏\n\(a.debugDescription)")
    created.append(account)
    register(a, step: "A 设备注册 \(account)")

    openFavorites(a, step: "A 设备进自选页")
    addFavoriteFromSearch(a, symbol: "BTCUSDT", step: "A 设备加一个币")
    // 第二类手建（理由见上面 `second` 那儿）。建完它自己就是选中的那一格，
    // 接着加的美股就落在它里面。
    createGroup(a, name: second, step: "A 设备新建第二个分类")
    addFavoriteFromSearch(a, symbol: "AAPLUSDT", step: "A 设备加一支美股")
    XCTAssertTrue(waitUntil(20) { self.chip(a, self.first).exists && self.chip(a, self.second).exists },
                  "A 设备加完两个品种，分类条上应当有「\(first)」和「\(second)」两格：\(groupReport(a))\n\(a.debugDescription)")

    // 加完自选那一下，页面自己就跟着品种切到了它落进的那一类。先退回第一个再点回去，
    // 让「停在第二类」确确实实是用手点出来的那一下，而不是加自选的副作用。
    tapGroup(a, name: first, step: "A 设备先退回第一个分类")
    XCTAssertTrue(waitUntil(10) { a.buttons["favorites.open.BTCUSDT"].exists },
                  "A 设备点了 \(first) 但列表没换成它的成员：\(groupReport(a))\n\(a.debugDescription)")
    tapGroup(a, name: second, step: "A 设备停到第二个分类")
    XCTAssertTrue(waitUntil(10) { self.chip(a, second).isSelected && a.buttons["favorites.open.AAPLUSDT"].exists },
                  "A 设备点了 \(second) 但它没选中：\(groupReport(a))\n\(a.debugDescription)")
    shot(a, "A设备-停在第二个分类")

    // 推上去。改一次偏好要过 500ms 防抖才生成推送（`AppAccountBridge` 里那条 `debounce`），
    // 之后是一次真实的线上往返，所以盯着同步页自己报「已同步」，比干等一个拍脑袋的秒数准。
    syncNow(a, step: "A 设备等这次选择推上去")
    a.terminate()

    // ---- B 设备：全新档案，登同一个账号
    let b = makeApp(profile: profileB)
    b.launch()
    XCTAssertTrue(b.buttons["bottom.settings"].waitForExistence(timeout: 90),
                  "B 设备（profile=\(profileB)）起了 90s 还没见到底栏\n\(b.debugDescription)")
    login(b, step: "B 设备登录 \(account)")
    // 登录本身就会拉一次全量，这儿再点一下「立即同步」并等它报「已同步」，为的是
    // 把「云端那份到底有没有到这台机器上」和「到了之后自选页停在哪一类」分成两件事：
    // 网络慢的那一跑该红在这儿，而不是红在下面那句断言上、让人以为现象又回来了。
    syncNow(b, step: "B 设备把云端那份拉下来")
    openFavorites(b, step: "B 设备进自选页")

    // 先等云端那份档案落地：分类条上两格都在了，才谈得上「停在哪一格」。
    XCTAssertTrue(waitUntil(120) { self.chip(b, self.first).exists && self.chip(b, self.second).exists },
                  "B 设备登录后 120s 还没拉到 A 摆的那两个分类：\(groupReport(b))\n\(b.debugDescription)")
    // 再给「停在哪一类」一点到货时间。它和分类名单来自同一次拉取，正常是同时到的；
    // 这里转圈只是不让网络抖动把用例判死——现象还在的话，转多久都是第一个分类选中。
    _ = waitUntil(30) { self.chip(b, self.second).isSelected }
    shot(b, "B设备-登录后的自选页")

    // ---- 硬断言：停的是 A 上选的那一类
    XCTAssertTrue(chip(b, second).isSelected,
                  """
                  换台设备登同一个账号，自选页应当停在他上次看的那一类（\(second)），\
                  实际停在别处：\(groupReport(b))
                  \(b.debugDescription)
                  """)
    XCTAssertFalse(chip(b, first).isSelected,
                   "B 设备停回了第一个分类（\(first)）——正是用户报的那个现象：\(groupReport(b))")
    // 胶囊的选中态之外再看一眼列表：真正摆在他眼前的是不是第二类的成员。
    XCTAssertTrue(b.buttons["favorites.open.AAPLUSDT"].waitForExistence(timeout: 20),
                  "B 设备停在 \(second) 上却没列出它的成员 AAPLUSDT\n\(b.debugDescription)")
    XCTAssertFalse(b.buttons["favorites.open.BTCUSDT"].exists,
                   "B 设备列出的是第一个分类的成员 BTCUSDT，说明停错了类：\(groupReport(b))")

    // ---- 收尾：把测试账号删掉，不在后端留垃圾
    closeAccount(b, step: "注销 \(account)")
    XCTAssertTrue(created.isEmpty, "测试账号没删掉：\(created)")
  }

  // ------------------------------------------------------------ 启动与环境

  private func makeApp(profile: String) -> XCUIApplication {
    let value = XCUIApplication()
    value.launchEnvironment["KANPAN_TEST_PROFILE"] = "1"
    value.launchEnvironment["KANPAN_PERSISTENCE_PROFILE"] = profile
    value.launchEnvironment["KANPAN_ACCOUNT_API_URL"] = api
    return value
  }

  // ------------------------------------------------------------ 账号页
  //
  // 这一段和 `AccountPreferenceSyncUITests` 是同一套动作，只是那边一台机器两个人、
  // 这边两台机器一个人，所以 `app` 得当参数传进来。

  private func openAccount(_ app: XCUIApplication, step: String) {
    if !app.otherElements["account.view"].exists {
      let tab = app.buttons["bottom.settings"]
      XCTAssertTrue(tab.waitForExistence(timeout: 60), "\(step)：底栏上没有设置格\n\(app.debugDescription)")
      tab.tap()
      let row = app.buttons["settings.account"]
      XCTAssertTrue(row.waitForExistence(timeout: 20), "\(step)：设置页上没有账号行\n\(app.debugDescription)")
      row.tap()
    }
    XCTAssertTrue(app.otherElements["account.view"].waitForExistence(timeout: 20),
                  "\(step)：账号页没打开\n\(app.debugDescription)")
  }

  /// 填用户名（传 nil 就只填口令，注销那一页用）与口令。
  ///
  /// 口令逐字符敲：整串 `typeText` 会被 iOS 的「强密码」建议气泡吃掉，只剩最后一个字符。
  private func fill(_ app: XCUIApplication, username: String?, step: String) {
    if let username {
      let field = app.textFields["account.email"]
      XCTAssertTrue(field.waitForExistence(timeout: 20), "\(step)：没有用户名输入框\n\(app.debugDescription)")
      field.tap()
      field.typeText(username)
    }
    let secure = app.secureTextFields["account.password"]
    XCTAssertTrue(secure.waitForExistence(timeout: 20), "\(step)：没有口令输入框\n\(app.debugDescription)")
    secure.tap()
    if app.buttons["GenerateStrongPasswordButton"].waitForExistence(timeout: 2) { app.buttons["xmark"].tap() }
    XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 20),
                  "\(step)：点了口令框但键盘没起来\n\(app.debugDescription)")
    for character in password { secure.typeText(String(character)) }
  }

  private func register(_ app: XCUIApplication, step: String) {
    openAccount(app, step: step)
    let entry = app.buttons["注册"]
    XCTAssertTrue(entry.waitForExistence(timeout: 20), "\(step)：登录页上没有「注册」入口\n\(app.debugDescription)")
    entry.tap()
    fill(app, username: account, step: step)
    app.buttons["account.submit"].tap()
    XCTAssertTrue(waitUntil(60) { !app.otherElements["account.view"].exists },
                  "\(step)：注册没闭合账号页，页面报错=\(errorText(app))\n\(app.debugDescription)")
  }

  private func login(_ app: XCUIApplication, step: String) {
    openAccount(app, step: step)
    fill(app, username: account, step: step)
    app.buttons["account.submit"].tap()
    XCTAssertTrue(waitUntil(60) { !app.otherElements["account.view"].exists },
                  "\(step)：登录没闭合账号页，页面报错=\(errorText(app))\n\(app.debugDescription)")
  }

  /// 「注销账号」要再输一次口令。删成功之后 `AccountFeature` 自己会退登并收起账号页。
  private func closeAccount(_ app: XCUIApplication, step: String) {
    openAccount(app, step: step)
    let entry = app.buttons["注销账号"]
    XCTAssertTrue(entry.waitForExistence(timeout: 20), "\(step)：账号页上没有「注销账号」\n\(app.debugDescription)")
    entry.tap()
    fill(app, username: nil, step: step)
    app.buttons["account.submit"].tap()
    XCTAssertTrue(waitUntil(60) { !app.otherElements["account.view"].exists },
                  "\(step)：注销没完成，页面报错=\(errorText(app))\n\(app.debugDescription)")
    created.removeAll { $0 == account }
  }

  /// 点一下同步页上的「立即同步」，等状态自己变成「已同步」。
  ///
  /// 为什么盯「已同步」而不是「待同步 N 项」归零：后者是一行 `LabeledContent`，
  /// 标签和数值粘成一个元素，按「待同步」这个名字压根找不着它——那种写法看着在等，
  /// 其实第一圈就通过了，等于没等。状态那行是 `AppAccountBridge.updateStatus()` 写的
  /// 一句纯文本，而且「已同步」是三件事的合取：队列空了、没有被服务端隔离的字段、
  /// 确实同步成功过一次。这三件事齐了，才谈得上另一台设备能读到。
  ///
  /// 「立即同步」走的是全量（`SyncPlan.full`）：先推再拉。A 设备用它把这次选择推上去，
  /// B 设备用它确认云端那份已经落到本机——干等一个拍脑袋的秒数换不来这个保证，
  /// 而慢一拍的那一跑会红在一个和根因无关的地方。
  private func syncNow(_ app: XCUIApplication, step: String) {
    openAccount(app, step: step)
    let sync = app.buttons["同步"]
    XCTAssertTrue(sync.waitForExistence(timeout: 20), "\(step)：账号页上没有「同步」\n\(app.debugDescription)")
    sync.tap()
    let now = app.buttons["立即同步"]
    XCTAssertTrue(now.waitForExistence(timeout: 20), "\(step)：同步页没打开\n\(app.debugDescription)")
    now.tap()
    let done = waitUntil(180) { app.staticTexts["已同步"].exists }
    if !done { shot(app, step + "-同步没完成") }
    XCTAssertTrue(done, "\(step)：180s 之后同步页还没报「已同步」\n\(app.debugDescription)")
    leaveAccount(app, step: step)
  }

  /// 从账号页退回页面本身。`account.back` 在子页是「返回」、在账号页是「收起」，
  /// 所以点到 `account.view` 消失为止——沿着用户自己的那条路走回去，别拿手势去猜
  /// sheet 怎么关。不收起来的话它整个盖在底栏上，后面点「自选」那一下根本落不到底栏上。
  private func leaveAccount(_ app: XCUIApplication, step: String) {
    for _ in 0..<4 {
      guard app.otherElements["account.view"].exists else { return }
      let back = app.buttons["account.back"]
      guard back.exists, back.isHittable else { break }
      back.tap()
      _ = waitUntil(5) { !app.otherElements["account.view"].exists }
    }
    XCTAssertFalse(app.otherElements["account.view"].exists,
                   "\(step)：账号页收不起来\n\(app.debugDescription)")
  }

  private func errorText(_ app: XCUIApplication) -> String {
    let label = app.staticTexts["account.error"]
    return label.exists ? label.label : "（页面上没有报错）"
  }

  // ------------------------------------------------------------ 自选页

  /// 底栏「自选」那一格。到没到用「…」那颗菜单判断——自选页上只有它，别的页都没有。
  private func openFavorites(_ app: XCUIApplication, step: String) {
    if app.buttons["favorites.more"].exists { return }
    let tab = app.buttons["bottom.favorites"]
    XCTAssertTrue(tab.waitForExistence(timeout: 60), "\(step)：底栏上没有自选格\n\(app.debugDescription)")
    tab.tap()
    XCTAssertTrue(app.buttons["favorites.more"].waitForExistence(timeout: 30),
                  "\(step)：点了自选格但没到自选页\n\(app.debugDescription)")
  }

  /// 分类胶囊。标识按**名字**拼（`FavoritesView.chip`），不是按 id。
  private func chip(_ app: XCUIApplication, _ name: String) -> XCUIElement {
    app.buttons["favorites.group." + name]
  }

  /// 新建一个分类：「…」→「新建分类」→ 打字 →「保存」。建完那一格自己就选中了
  /// （`FavoritesView` 的新建弹窗里 `createGroup` 之后紧跟着 `select(id)`）。
  ///
  /// 整步最多走两遍，理由和 `KanpanUICase.createGroup` 那儿记的一样：菜单是自绘浮层，
  /// 弹窗是模态的，任何一环被上一张浮层的收起动画吃掉，收场都是「这一格没建成」。
  /// 重试路径上不做断言，只看 `favorites.group.<名字>` 这颗胶囊出没出来。
  private func createGroup(_ app: XCUIApplication, name: String, step: String) {
    let group = chip(app, name)
    for _ in 0..<2 {
      if group.exists { return }
      // 上一遍留下的弹窗是模态的，不收掉下一遍的「…」就永远点不动。
      let stray = app.alerts.firstMatch
      if stray.exists, stray.buttons["取消"].isHittable { stray.buttons["取消"].tap() }
      let more = app.buttons["favorites.more"]
      guard more.waitForExistence(timeout: 15), more.isHittable else { continue }
      more.tap()
      let action = app.buttons["favorites.newGroup"]
      guard action.waitForExistence(timeout: 10), action.isHittable else { continue }
      action.tap()
      let field = app.alerts.textFields.firstMatch
      guard field.waitForExistence(timeout: 10), field.isHittable else { continue }
      field.typeText(name)
      let save = app.alerts.buttons["保存"]
      guard save.exists, save.isHittable else { continue }
      save.tap()
      if group.waitForExistence(timeout: 10) { return }
    }
    XCTAssertTrue(group.exists, "\(step)：走了两遍也没建出「\(name)」\n\(app.debugDescription)")
  }

  /// 从自选页加一个品种：头部那条长搜索框 → 打字 → 点那一行的星 → 取消退回。
  /// 星是开关，已经在自选里的再点一下反而会被移除，所以先看 label 再决定点不点。
  private func addFavoriteFromSearch(_ app: XCUIApplication, symbol: String, step: String) {
    app.buttons["favorites.add"].tap()
    let query = app.textFields["search.query"]
    XCTAssertTrue(query.waitForExistence(timeout: 20), "\(step)：搜索页没打开\n\(app.debugDescription)")
    query.tap()
    query.typeText(symbol)
    let star = app.buttons["symbols.star." + symbol]
    XCTAssertTrue(star.waitForExistence(timeout: 60), "\(step)：搜索页没搜到 \(symbol)\n\(app.debugDescription)")
    if star.label == "加入自选" { star.tap() }
    app.buttons["search.cancel"].tap()
    XCTAssertTrue(app.buttons["favorites.open." + symbol].waitForExistence(timeout: 20),
                  "\(step)：加完应当停在品种落进去的那一组、看得见刚加的那一行\n\(app.debugDescription)")
  }

  /// 点中某一类。只有两个分类，分类条不会滚出屏幕，但仍旧等它可点再点——
  /// 上一张浮层的收起动画偶尔会吃掉第一下。
  private func tapGroup(_ app: XCUIApplication, name: String, step: String) {
    let target = chip(app, name)
    XCTAssertTrue(target.waitForExistence(timeout: 15), "\(step)：分类条上没有 \(name)\n\(app.debugDescription)")
    XCTAssertTrue(waitUntil(10) { target.isHittable }, "\(step)：\(name) 点不着\n\(app.debugDescription)")
    target.tap()
  }

  /// 断言失败时报的不是「false」，而是两格分类现在各是什么状态、列表里露着谁。
  private func groupReport(_ app: XCUIApplication) -> String {
    let groups = [first, second].map { name -> String in
      let element = chip(app, name)
      guard element.exists else { return "\(name)=缺失" }
      return "\(name)=\(element.isSelected ? "选中" : "未选")"
    }
    let rows = ["BTCUSDT", "AAPLUSDT"].filter { app.buttons["favorites.open." + $0].exists }
    return groups.joined(separator: " ") + "；列表里露着 " + (rows.isEmpty ? "（一行都没有）" : rows.joined(separator: "、"))
  }

  private func shot(_ app: XCUIApplication, _ name: String) {
    let value = XCTAttachment(screenshot: app.screenshot())
    value.name = name
    value.lifetime = .keepAlways
    add(value)
  }

  // ------------------------------------------------------------ 兜底清理

  /// UI 那条注销路径没走完时，直接按 HTTP 把账号删掉。
  /// 账号已经不在了（登录 401）就什么都不做。
  private func forceDelete(_ username: String) async {
    struct Device: Encodable { var id = UUID(); var name = "uitest"; var secret = UUID().uuidString + UUID().uuidString }
    struct Login: Encodable { var username: String; var password: String; var device: Device }
    struct Tokens: Decodable { struct Payload: Decodable { var accessToken: String }; var data: Payload }
    struct Close: Encodable { var password: String }
    guard let base = URL(string: api) else { return }
    var login = URLRequest(url: base.appendingPathComponent("v1/auth/login"))
    login.httpMethod = "POST"
    login.setValue("application/json", forHTTPHeaderField: "Content-Type")
    login.httpBody = try? JSONEncoder().encode(Login(username: username, password: password, device: Device()))
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
  // `XCTNSPredicateExpectation` 对 `isSelected` / `value` 这种非 KVO 属性不可靠，
  // 所以和 `AccountPreferenceSyncUITests` 一样老老实实自己转圈。

  private func waitUntil(_ timeout: TimeInterval, _ condition: () -> Bool) -> Bool {
    let deadline = Date().addingTimeInterval(timeout)
    while Date() < deadline {
      if condition() { return true }
      _ = XCTWaiter.wait(for: [XCTestExpectation(description: "poll")], timeout: 0.2)
    }
    return condition()
  }
}
