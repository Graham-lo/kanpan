import XCTest
import UIKit
import CoreGraphics

// ============================================================ 偏好跟着人走：真账号闭环
//
// `kanpan-preferences-follow-the-person-instantly` 这条约定在**真账号的注册 / 退登 /
// 换号 / 登回**这条路上一直没有用例守着。以前的说法是「不能注册账号所以测不了」——
// 那是错的：`AccountMarketUITests.testOKXHistoryAndUsernameRegistration` 早就在用
// 自造的随机用户名 + 一个测试口令，在项目自己的后端上注册、重启验持久化、最后
// 「注销账号」把痕迹删干净。这个文件照着那条成例，把整条换号闭环走完。
//
// 为什么挑「皮肤 + 深浅」当探针：它们是**整屏都看得见**的偏好，跟着人走
// （`PersonalSyncCodec.fields`），而且冷启动第一帧就要用（`LaunchThemeMirror`）。
// 一个人的配色要是漏到另一个人身上，是用户一眼就发现的那种错。
//
// 两组配色挑得尽量不像：A = 陶土 · 深色（暗屏），B = 经典 · 浅色（白屏）。
// 这样「启动时闪了一下上一个人的皮肤」在屏幕亮度上就是一个能量出来的数
// （见 `relaunchSampling`），不用靠肉眼描述。
//
// 后端是项目自己的那台（`KANPAN_ACCOUNT_API_URL`），口令是现造的测试口令，
// 用完两个账号都按「注销账号」删掉；UI 那条路没走完（中途断言失败）时，
// `tearDown` 会直接按 HTTP 补一刀，不给后端留垃圾数据。

@MainActor final class AccountPreferenceSyncUITests: XCTestCase {
  /// 现造的测试口令。不碰用户的真账号、真口令。
  private let password = "Testpass2026"
  private let api = "https://kanpan.107-174-172-10.sslip.io"
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

  /// 偏好跟着人走，不跟着这台机器走。
  ///
  /// 1. 干净档案起 app；
  /// 2. 注册 A，把配色改成陶土 · 深色，**当场**生效；
  /// 3. 退登、注册 B，改成经典 · 浅色；
  /// 4. 杀掉 app 重启，回来仍是 B 那组（B 的档案兑现的是 B 的，不是本机上一个人留下的）；
  /// 5. 退 B、登回 A，皮肤**当场**变回陶土 · 深色（整条用例的重点）；
  /// 6. 再重启一次，量「启动 → A 的档案到货」中间有多久、有没有闪过别人的皮肤；
  /// 7. 两个账号都注销掉。
  func testPreferencesFollowTheAccountAcrossRegisterLogoutSwitchAndRelogin() throws {
    continueAfterFailure = false
    let profile = UUID().uuidString
    app = makeApp(profile: profile)
    app.launch()
    defer {
      let last = XCTAttachment(screenshot: app.screenshot())
      last.name = "收尾"; last.lifetime = .keepAlways; add(last)
    }
    XCTAssertTrue(app.buttons["bottom.settings"].waitForExistence(timeout: 90),
                  "第 1 步：干净档案（profile=\(profile)）起 app 之后 90s 还没见到底栏设置格\n\(app.debugDescription)")

    // ---- 第 2 步：注册 A
    let userA = Self.randomName()
    created.append(userA)
    register(userA, step: "第 2 步（注册 A=\(userA)）")
    shot("2-注册A")

    // ---- 第 3 步：A 的配色 = 陶土 · 深色，改完当场生效
    setTheme(skin: "terra", mode: "深色", step: "第 3 步（A 改配色）")
    XCTAssertTrue(themeIs(skin: "terra", mode: "深色"),
                  "第 3 步：A 点完陶土 + 深色没有当场生效，当前 \(themeReport())\n\(app.debugDescription)")
    shot("3-A陶土深色")

    // ---- 第 4 步：退 A、注册 B，B 的配色 = 经典 · 浅色
    logout(step: "第 4 步（退出 A）")
    let userB = Self.randomName()
    created.append(userB)
    register(userB, step: "第 4 步（注册 B=\(userB)）")
    setTheme(skin: "classic", mode: "浅色", step: "第 4 步（B 改配色）")
    XCTAssertTrue(themeIs(skin: "classic", mode: "浅色"),
                  "第 4 步：B 点完经典 + 浅色没有当场生效，当前 \(themeReport())\n\(app.debugDescription)")
    shot("4-换到B-经典浅色")

    // ---- 第 5 步：杀掉重启，回来还是 B 的那一组
    let bSamples = relaunchSampling("5-B重启")
    let bSettle = expectTheme(skin: "classic", mode: "浅色",
                              step: "第 5 步（B 重启后）")
    shot("5-B重启后")

    // ---- 第 6 步：退 B、登回 A，皮肤当场变回 A 的
    logout(step: "第 6 步（退出 B）")
    openAccount(step: "第 6 步（打开登录页）")
    fill(username: userA, step: "第 6 步（填 A 的用户名口令）")
    app.buttons["account.submit"].tap()
    // 「当场变回来」先用整屏亮度量，因为它和人停在哪一页无关：登录一成功，
    // `onProfileReady()` 会重新决定落地页，设置页会被顶掉（自选不空就去自选、
    // 否则回行情页），此时再去盯 `display.theme.*` 只会等到它们从无障碍树上消失。
    // B 是经典 · 浅色（白屏 ≈0.97），A 是陶土 · 深色（暗屏），一翻就是个能看出来的数。
    let flip = sampleScreen(30, label: "6-登回A-整屏亮度") { $0 < 0.45 }
    let switchLatency = flip.elapsed
    XCTAssertTrue(flip.met,
                  """
                  第 6 步（整条用例的重点）：登回 A 之后整屏应当场变暗（陶土 · 深色），\
                  说明偏好跟着人走、不跟着这台机器走；实际等了 \(String(format: "%.2f", switchLatency))s \
                  屏幕亮度始终是 \(flip.summary)，账号页报错=\(errorText())
                  \(app.debugDescription)
                  """)
    XCTAssertTrue(waitUntil(60) { !self.app.otherElements["account.view"].exists },
                  "第 6 步：登回 A 没有闭合账号页，页面报错=\(errorText())\n\(app.debugDescription)")
    shot("6-登回A")
    // 亮度只证明「换了一套暗的」。到底是不是 A 那一套，回设置页按控件逐个核对。
    let aRestore = expectTheme(skin: "terra", mode: "深色", step: "第 6 步（回设置页核对是 A 的陶土 · 深色）")
    shot("6-登回A-设置页")

    // ---- 第 6 步补：再重启一次，量「启动 → A 的档案到货」
    let aSamples = relaunchSampling("6-A重启")
    let aSettle = expectTheme(skin: "terra", mode: "深色", step: "第 6 步补（A 重启后）")

    report(profile: profile, userA: userA, userB: userB,
           switchLatency: switchLatency, aRestore: aRestore, bSettle: bSettle, aSettle: aSettle,
           bSamples: bSamples, aSamples: aSamples)

    // ---- 第 7 步：两个账号都删掉
    closeAccount(userA, step: "第 7 步（注销 A）")
    login(userB, step: "第 7 步（登回 B 以便注销）")
    closeAccount(userB, step: "第 7 步（注销 B）")
    XCTAssertTrue(created.isEmpty, "第 7 步：还有账号没删掉 \(created)")
  }

  // ------------------------------------------------------------ P4.5 两台设备并发改同一份

  /// 两台设备、同一个账号，**互相没看见对方的时候**各改同一份设置与自选，
  /// 验证收敛到「谁新用谁」（按改动时刻，不按谁后推上去），而且两边的队列都不堵。
  ///
  /// **两台设备怎么来的**：同一个模拟器上两个不同的 `KANPAN_PERSISTENCE_PROFILE`（各自一棵
  /// 档案子树、各自一份 keychain、各自一个设备 id），和 `FavoritesGroupSyncUITests`
  /// 是同一套手法。B 那台启动时带 `KANPAN_TEST_DEVICE_KIND=tablet`（只有 DEBUG 包认），
  /// 自报「平板」——账号规则是每类设备只许一台在线，两台都报「手机」的话，后登的会把
  /// 先登的踢下线，那测的就是踢人而不是并发。规则本身一行没动。
  ///
  /// **「同时」怎么造**：两台都关掉「自动同步」再改，改动只进各自的待发队列；
  /// 然后按一个刻意的顺序推上去——**手里拿着较旧改动的那台最后推**。这样「后推的赢」和
  /// 「新改的赢」给出的答案不一样，用例才分得出服务端到底按哪条规矩合并：
  ///
  /// | 时刻 | 设备 | 改动 |
  /// | --- | --- | --- |
  /// | T1 | A | 皮肤 → 陶土；加自选 SOL（暂停中，没推） |
  /// | T2 | B | 皮肤 → 经典、深浅 → 浅色；加自选 DOGE、删自选 ETH（暂停中，没推） |
  /// | T3 | A | 深浅 → 深色；推（连同 T1 的） |
  /// | 之后 | B | 推 T2 那一批——**最后推的是它** |
  ///
  /// 期望：皮肤 = 经典（B 的 T2 比 A 的 T1 新），深浅 = 深色（A 的 T3 比 B 的 T2 新，
  /// 虽然 B 后推）；自选 = SOL、DOGE 都在，ETH 没了。任何一台都不该停在自己本地那一份上。
  /// 最后再从 A 改一次皮肤，B 拉到它，证明合并完之后两边的队列都还通。
  func testConcurrentEditsOnTwoDevicesConvergeToTheNewest() throws {
    continueAfterFailure = false
    let user = "p45_" + UUID().uuidString.replacingOccurrences(of: "-", with: "").prefix(12).lowercased()
    // 档案 id 必须是一个裸 UUID：app 只在它能解析成 UUID 时才给这台「设备」单开偏好、
    // 账号存档与同步队列的目录，否则两台共用一份队列——B 一启动就会把 A 没推的改动推上去。
    let profileA = UUID().uuidString
    let profileB = UUID().uuidString

    // ---- 基线：A 注册，加 ETH，推上去；B 登录拉到同一份
    app = makeApp(profile: profileA)
    app.launch()
    XCTAssertTrue(app.buttons["bottom.settings"].waitForExistence(timeout: 90), "A 起了 90s 还没见到底栏")
    created.append(user)
    register(user, step: "A 注册 \(user)")
    setFavorite("ETHUSDT", on: true, step: "A 加基线自选 ETH")
    syncNow(step: "A 把基线推上去")
    expectTheme(skin: "sage", mode: "跟随系统", step: "A 基线配色")
    app.terminate()

    app = makeApp(profile: profileB, kind: "tablet")
    app.launch()
    XCTAssertTrue(app.buttons["bottom.settings"].waitForExistence(timeout: 90), "B 起了 90s 还没见到底栏")
    login(user, step: "B（平板）登录 \(user)")
    syncNow(step: "B 拉基线")
    expectFavorites(present: ["ETHUSDT"], absent: [], step: "B 拉到的基线自选")
    app.terminate()

    // ---- T1：A 暂停同步后改
    app = makeApp(profile: profileA)
    app.launch()
    XCTAssertTrue(app.buttons["bottom.settings"].waitForExistence(timeout: 90), "A 重启后没见到底栏")
    setAutoSync(false, step: "A 暂停自动同步")
    setTheme(skin: "terra", mode: "跟随系统", step: "T1 A 皮肤改陶土")
    setFavorite("SOLUSDT", on: true, step: "T1 A 加 SOL")
    settle()
    app.terminate()

    // ---- T2：B 暂停同步后改（它看不见 A 的 T1——A 还没推）
    app = makeApp(profile: profileB, kind: "tablet")
    app.launch()
    XCTAssertTrue(app.buttons["bottom.settings"].waitForExistence(timeout: 90), "B 重启后没见到底栏")
    setAutoSync(false, step: "B 暂停自动同步")
    expectTheme(skin: "sage", mode: "跟随系统", step: "B 改之前应当还是基线（A 的 T1 没推）")
    setTheme(skin: "classic", mode: "浅色", step: "T2 B 皮肤经典、深浅浅色")
    setFavorite("DOGEUSDT", on: true, step: "T2 B 加 DOGE")
    setFavorite("ETHUSDT", on: false, step: "T2 B 删 ETH")
    settle()
    shot("P45-B-本地改完没推")
    app.terminate()

    // ---- T3：A 改深浅并推（连同 T1 那批）。B 的 T2 还压在 B 的队列里
    app = makeApp(profile: profileA)
    app.launch()
    XCTAssertTrue(app.buttons["bottom.settings"].waitForExistence(timeout: 90), "A 第三次起没见到底栏")
    setTheme(skin: "terra", mode: "深色", step: "T3 A 深浅改深色")
    setAutoSync(true, step: "A 恢复自动同步")
    syncNow(step: "A 推 T1 + T3")
    expectTheme(skin: "terra", mode: "深色", step: "A 推完（B 还没推）应当是自己那份")
    app.terminate()

    // ---- B 最后推：拿着较旧的深浅改动
    app = makeApp(profile: profileB, kind: "tablet")
    app.launch()
    XCTAssertTrue(app.buttons["bottom.settings"].waitForExistence(timeout: 90), "B 第三次起没见到底栏")
    setAutoSync(true, step: "B 恢复自动同步")
    syncNow(step: "B 推 T2 并拉合并结果")
    expectTheme(skin: "classic", mode: "深色",
                step: "B 收敛：皮肤取 B 的 T2（比 A 的 T1 新），深浅取 A 的 T3（比 B 的 T2 新，虽然 B 后推）",
                timeout: 60)
    expectFavorites(present: ["SOLUSDT", "DOGEUSDT"], absent: ["ETHUSDT"], step: "B 收敛后的自选")
    shot("P45-B-收敛后")
    app.terminate()

    // ---- A 再拉一次，应当和 B 一模一样
    app = makeApp(profile: profileA)
    app.launch()
    XCTAssertTrue(app.buttons["bottom.settings"].waitForExistence(timeout: 90), "A 第四次起没见到底栏")
    syncNow(step: "A 拉合并结果")
    expectTheme(skin: "classic", mode: "深色", step: "A 收敛到同一份", timeout: 60)
    expectFavorites(present: ["SOLUSDT", "DOGEUSDT"], absent: ["ETHUSDT"], step: "A 收敛后的自选")
    shot("P45-A-收敛后")

    // ---- 队列不堵：合并之后 A 再改一次，B 照样拿得到
    setTheme(skin: "sage", mode: "深色", step: "A 合并后再改皮肤")
    syncNow(step: "A 推合并后的新改动")
    app.terminate()
    app = makeApp(profile: profileB, kind: "tablet")
    app.launch()
    XCTAssertTrue(app.buttons["bottom.settings"].waitForExistence(timeout: 90), "B 第四次起没见到底栏")
    syncNow(step: "B 拉合并后的新改动")
    expectTheme(skin: "sage", mode: "深色", step: "合并之后队列仍通：B 拿到 A 的新皮肤", timeout: 60)
    shot("P45-B-队列仍通")

    closeAccount(user, step: "注销 \(user)")
    XCTAssertTrue(created.isEmpty, "测试账号没删掉：\(created)")
  }

  // ------------------------------------------------------------ 启动与环境

  private func makeApp(profile: String, kind: String? = nil) -> XCUIApplication {
    let value = XCUIApplication()
    if let kind { value.launchEnvironment["KANPAN_TEST_DEVICE_KIND"] = kind }
    value.launchEnvironment["KANPAN_TEST_PROFILE"] = "1"
    value.launchEnvironment["KANPAN_PERSISTENCE_PROFILE"] = profile
    value.launchEnvironment["KANPAN_ACCOUNT_API_URL"] = api
    value.launchEnvironment["KANPAN_LOG"] = "1"
    return value
  }

  private static func randomName() -> String {
    "pref_" + UUID().uuidString.replacingOccurrences(of: "-", with: "").prefix(12).lowercased()
  }

  // ------------------------------------------------------------ 账号页

  /// 账号页没开就从底栏「设置」那一格进去开。已经开着就原样返回。
  private func openAccount(step: String) {
    if !app.otherElements["account.view"].exists {
      goToSettings(step: step)
      let row = app.buttons["settings.account"]
      XCTAssertTrue(row.waitForExistence(timeout: 20),
                    "\(step)：设置页上没有账号行 settings.account\n\(app.debugDescription)")
      row.tap()
    }
    XCTAssertTrue(app.otherElements["account.view"].waitForExistence(timeout: 20),
                  "\(step)：点了账号行但账号页没打开\n\(app.debugDescription)")
  }

  /// 填用户名（传 nil 就只填口令，注销那一页用）与口令。
  ///
  /// 口令要逐字符敲：整串 `typeText` 会被 iOS 的「强密码」建议气泡吃掉，只剩最后一个字符
  /// （`AccountMarketUITests` 里踩过同一颗雷，这儿照抄它的写法）。
  private func fill(username: String?, step: String) {
    if let username {
      let field = app.textFields["account.email"]
      XCTAssertTrue(field.waitForExistence(timeout: 20),
                    "\(step)：没有用户名输入框 account.email\n\(app.debugDescription)")
      field.tap()
      field.typeText(username)
    }
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
    let entry = app.buttons["注册"]
    XCTAssertTrue(entry.waitForExistence(timeout: 20),
                  "\(step)：登录页上没有「注册」入口\n\(app.debugDescription)")
    entry.tap()
    fill(username: username, step: step)
    app.buttons["account.submit"].tap()
    XCTAssertTrue(waitUntil(60) { !self.app.otherElements["account.view"].exists },
                  "\(step)：注册没有闭合账号页，页面报错=\(errorText())\n\(app.debugDescription)")
  }

  private func login(_ username: String, step: String) {
    openAccount(step: step)
    fill(username: username, step: step)
    app.buttons["account.submit"].tap()
    XCTAssertTrue(waitUntil(60) { !self.app.otherElements["account.view"].exists },
                  "\(step)：登录没有闭合账号页，页面报错=\(errorText())\n\(app.debugDescription)")
  }

  private func logout(step: String) {
    openAccount(step: step)
    let button = app.buttons["退出登录"]
    XCTAssertTrue(button.waitForExistence(timeout: 20),
                  "\(step)：账号页上没有「退出登录」\n\(app.debugDescription)")
    button.tap()
    XCTAssertTrue(waitUntil(30) { !self.app.otherElements["account.view"].exists },
                  "\(step)：点了退出登录但账号页没关，页面报错=\(errorText())\n\(app.debugDescription)")
  }

  /// 「注销账号」要再输一次口令。删成功之后 `AccountFeature` 自己会退登并收起账号页。
  private func closeAccount(_ username: String, step: String) {
    openAccount(step: step)
    let entry = app.buttons["注销账号"]
    XCTAssertTrue(entry.waitForExistence(timeout: 20),
                  "\(step)：账号页上没有「注销账号」\n\(app.debugDescription)")
    entry.tap()
    fill(username: nil, step: step)
    app.buttons["account.submit"].tap()
    XCTAssertTrue(waitUntil(60) { !self.app.otherElements["account.view"].exists },
                  "\(step)：注销 \(username) 没完成，页面报错=\(errorText())\n\(app.debugDescription)")
    created.removeAll { $0 == username }
  }

  private func errorText() -> String {
    let label = app.staticTexts["account.error"]
    return label.exists ? label.label : "（页面上没有报错）"
  }

  // ------------------------------------------------------------ 配色

  /// 底栏「设置」那一格。已经在设置页上（皮肤卡在树上）就不再点一次。
  private func goToSettings(step: String) {
    if app.buttons["display.theme.sage"].exists { return }
    let tab = app.buttons["bottom.settings"]
    XCTAssertTrue(tab.waitForExistence(timeout: 60),
                  "\(step)：底栏上没有设置格 bottom.settings\n\(app.debugDescription)")
    tab.tap()
    XCTAssertTrue(app.buttons["display.theme.sage"].waitForExistence(timeout: 20),
                  "\(step)：进了设置页但没有配色卡\n\(app.debugDescription)")
  }

  /// 皮肤卡的 id 是 `display.theme.<skin.rawValue>`（sage / terra / classic），
  /// 选中与否挂在 `accessibilityValue` 上；深浅那一排是 `display.mode.<档位文字>`，
  /// 选中与否走 `isSelected`（`PanelSegment` 给选中那格加了 `.isSelected` trait）。
  private func setTheme(skin: String, mode: String, step: String) {
    goToSettings(step: step)
    let card = app.buttons["display.theme." + skin]
    XCTAssertTrue(card.waitForExistence(timeout: 20),
                  "\(step)：设置页上没有皮肤卡 display.theme.\(skin)\n\(app.debugDescription)")
    if (card.value as? String) != "已选" { card.tap() }
    let segment = app.buttons["display.mode." + mode]
    XCTAssertTrue(segment.waitForExistence(timeout: 20),
                  "\(step)：设置页上没有深浅档 display.mode.\(mode)\n\(app.debugDescription)")
    if !segment.isSelected { segment.tap() }
  }

  private func themeIs(skin: String, mode: String) -> Bool {
    let card = app.buttons["display.theme." + skin]
    let segment = app.buttons["display.mode." + mode]
    guard card.exists, segment.exists else { return false }
    return (card.value as? String) == "已选" && segment.isSelected
  }

  /// 断言失败时报的不是「false」，而是三张皮肤卡、三个深浅档现在各是什么状态。
  private func themeReport() -> String {
    let skins = ["sage", "terra", "classic"].map { raw -> String in
      let card = app.buttons["display.theme." + raw]
      guard card.exists else { return "\(raw)=缺失" }
      return "\(raw)=\((card.value as? String) ?? "无值")"
    }
    let modes = ["跟随系统", "浅色", "深色"].map { title -> String in
      let segment = app.buttons["display.mode." + title]
      guard segment.exists else { return "\(title)=缺失" }
      return "\(title)=\(segment.isSelected ? "选中" : "未选")"
    }
    return (skins + modes).joined(separator: " ")
  }

  /// 等到设置页上的配色确实是这一组，并把等了多久交出来。
  @discardableResult
  private func expectTheme(skin: String, mode: String, step: String,
                           timeout: TimeInterval = 30) -> TimeInterval {
    let start = Date()
    goToSettings(step: step)
    let ok = waitUntil(timeout) { self.themeIs(skin: skin, mode: mode) }
    let elapsed = Date().timeIntervalSince(start)
    XCTAssertTrue(ok,
                  """
                  \(step)：配色应当是 \(skin) + \(mode)，等了 \(String(format: "%.2f", elapsed))s \
                  仍是 \(themeReport())
                  \(app.debugDescription)
                  """)
    return elapsed
  }

  // ------------------------------------------------------------ 重启与「闪一下」的量法

  /// 杀掉 app 重启，并在重启后**尽可能快地**连拍，量整屏平均亮度。
  ///
  /// A 是陶土 · 深色（暗屏），B 是经典 · 浅色（白屏），出厂默认（青苔 · 跟随系统，
  /// 模拟器是浅色）也是亮屏。所以：
  ///
  /// - 登录 A 时重启，只要有一帧是亮的，就是「闪了一下别人（或出厂）的皮肤」；
  /// - 登录 B 时重启，只要有一帧是暗的，同理。
  ///
  /// 采样的起点是 `launch()` 返回之后——XCTest 没有办法在 `launch()` 阻塞期间插进去拍，
  /// 所以这一串数覆盖的是「app 已经起来之后」的那一段，覆盖不到更早的几帧。
  /// 更早那一段由 `LaunchThemeMirror` 顶着（它把皮肤与深浅镜像到本机，
  /// 第一帧直接拿镜像开张），单测在 `LaunchThemeMirrorTests` 里。
  private func relaunchSampling(_ label: String, budget: TimeInterval = 2.5) -> [(TimeInterval, Double)] {
    app.terminate()
    let start = Date()
    app.launch()
    let launched = Date().timeIntervalSince(start)
    var samples: [(TimeInterval, Double)] = []
    while Date().timeIntervalSince(start) < launched + budget {
      let moment = Date().timeIntervalSince(start)
      samples.append((moment, Self.meanLuminance(app.screenshot())))
    }
    attachSamples(label: label + "-启动亮度", launched: launched, samples: samples)
    return samples
  }

  /// 一边尽可能快地连拍整屏亮度，一边等它满足条件；采样串照例挂成附件。
  ///
  /// 亮度是**跟页面无关**的探针：不管 app 这会儿停在设置页、行情页还是账号弹层上，
  /// 「这一屏是 A 的暗色还是 B 的白色」都答得出来。控件级的核对交给 `expectTheme`。
  private func sampleScreen(_ timeout: TimeInterval, label: String,
                            until: (Double) -> Bool) -> (met: Bool, elapsed: TimeInterval, summary: String) {
    let start = Date()
    var samples: [(TimeInterval, Double)] = []
    var met = false
    while Date().timeIntervalSince(start) < timeout {
      let value = Self.meanLuminance(app.screenshot())
      samples.append((Date().timeIntervalSince(start), value))
      if until(value) { met = true; break }
    }
    let elapsed = Date().timeIntervalSince(start)
    attachSamples(label: label, launched: nil, samples: samples)
    let low = samples.map(\.1).min() ?? -1
    let high = samples.map(\.1).max() ?? -1
    return (met, elapsed, String(format: "%.3f–%.3f（%d 帧）", low, high, samples.count))
  }

  private func attachSamples(label: String, launched: TimeInterval?, samples: [(TimeInterval, Double)]) {
    var lines = [launched.map { "\(label)：launch() 返回用了 \(String(format: "%.3f", $0))s，此后连拍" }
                 ?? "\(label)：连拍",
                 "（时刻 = 距起点的秒数；亮度 = 整屏平均 0–1，越小越暗）"]
    lines += samples.map { String(format: "  %6.3fs  %.3f", $0.0, $0.1) }
    let note = XCTAttachment(string: lines.joined(separator: "\n"))
    note.name = label + "-采样"
    note.lifetime = .keepAlways
    add(note)
  }

  /// 一张截图的整屏平均亮度。缩到 8×8 再平均，比直接缩到 1×1 稳。
  private static func meanLuminance(_ screenshot: XCUIScreenshot) -> Double {
    guard let image = screenshot.image.cgImage else { return -1 }
    let side = 8
    let count = side * side * 4
    let bytes = UnsafeMutablePointer<UInt8>.allocate(capacity: count)
    defer { bytes.deallocate() }
    bytes.initialize(repeating: 0, count: count)
    guard let context = CGContext(data: bytes, width: side, height: side, bitsPerComponent: 8,
                                  bytesPerRow: side * 4, space: CGColorSpaceCreateDeviceRGB(),
                                  bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue) else { return -1 }
    context.interpolationQuality = .medium
    context.draw(image, in: CGRect(x: 0, y: 0, width: side, height: side))
    var total = 0.0
    for index in 0..<(side * side) {
      total += 0.299 * Double(bytes[index * 4])
        + 0.587 * Double(bytes[index * 4 + 1])
        + 0.114 * Double(bytes[index * 4 + 2])
    }
    return total / Double(side * side) / 255
  }

  private func shot(_ name: String) {
    let value = XCTAttachment(screenshot: app.screenshot())
    value.name = name
    value.lifetime = .keepAlways
    add(value)
  }

  private func report(profile: String, userA: String, userB: String,
                      switchLatency: TimeInterval, aRestore: TimeInterval,
                      bSettle: TimeInterval, aSettle: TimeInterval,
                      bSamples: [(TimeInterval, Double)], aSamples: [(TimeInterval, Double)]) {
    func span(_ samples: [(TimeInterval, Double)]) -> String {
      guard let low = samples.map(\.1).min(), let high = samples.map(\.1).max() else { return "没采到样" }
      return String(format: "%d 帧，亮度 %.3f–%.3f，首帧 %.3f", samples.count, low, high, samples.first?.1 ?? -1)
    }
    let text = """
    档案 profile=\(profile)
    A=\(userA)（陶土 · 深色）  B=\(userB)（经典 · 浅色）

    退 B 登回 A：从点「登录」到整屏变成 A 的暗色 \(String(format: "%.2f", switchLatency))s（含一次登录往返）
    退 B 登回 A：再回设置页逐控件核对到陶土 · 深色又用了 \(String(format: "%.2f", aRestore))s（含点底栏、等设置页）
    B 重启后配色落定（含进设置页）：\(String(format: "%.2f", bSettle))s
    A 重启后配色落定（含进设置页）：\(String(format: "%.2f", aSettle))s

    B 重启后连拍（应当**全是亮的**，出现暗帧＝闪了 A 的陶土深色）：\(span(bSamples))
    A 重启后连拍（应当**全是暗的**，出现亮帧＝闪了 B 的经典浅色或出厂青苔）：\(span(aSamples))
    """
    let note = XCTAttachment(string: text)
    note.name = "换号闭环-实测"
    note.lifetime = .keepAlways
    add(note)
    print("=== 换号闭环-实测 ===\n" + text)
  }

  // ------------------------------------------------------------ 同步页与自选（P4.5）

  /// 「立即同步」走全量（先推再拉），等同步页自己报「已同步」——那是队列空了、没有被服务端
  /// 隔离的字段、确实成功过一次这三件事的合取（写法照 `FavoritesGroupSyncUITests.syncNow`）。
  private func syncNow(step: String) {
    openSyncPage(step: step)
    app.buttons["立即同步"].tap()
    let done = waitUntil(180) { self.app.staticTexts["已同步"].exists }
    if !done { shot(step + "-同步没完成") }
    XCTAssertTrue(done, "\(step)：180s 之后同步页还没报「已同步」\n\(app.debugDescription)")
    leaveAccount(step: step)
  }

  private func openSyncPage(step: String) {
    openAccount(step: step)
    let sync = app.buttons["同步"]
    XCTAssertTrue(sync.waitForExistence(timeout: 20), "\(step)：账号页上没有「同步」\n\(app.debugDescription)")
    sync.tap()
    XCTAssertTrue(app.buttons["立即同步"].waitForExistence(timeout: 20), "\(step)：同步页没打开\n\(app.debugDescription)")
  }

  /// 同步页上的「自动同步」开关。SwiftUI 的 Toggle 在列表里整行是一个 switch，
  /// 点中心有时落在文字上不翻，所以点完看值，没翻再点右侧的开关本体。
  private func setAutoSync(_ on: Bool, step: String) {
    openSyncPage(step: step)
    let toggle = app.switches["自动同步"]
    XCTAssertTrue(toggle.waitForExistence(timeout: 20), "\(step)：同步页上没有「自动同步」\n\(app.debugDescription)")
    func isOn() -> Bool { (toggle.value as? String) == "1" }
    if isOn() != on { toggle.tap() }
    if !waitUntil(3, { isOn() == on }) { toggle.coordinate(withNormalizedOffset: CGVector(dx: 0.93, dy: 0.5)).tap() }
    XCTAssertTrue(waitUntil(5) { isOn() == on }, "\(step)：「自动同步」没切到 \(on)\n\(app.debugDescription)")
    if !on { XCTAssertTrue(waitUntil(5) { self.app.staticTexts["已暂停"].exists }, "\(step)：暂停后状态不是「已暂停」") }
    leaveAccount(step: step)
  }

  /// 从账号页退回页面本身（`account.back` 在子页是「返回」、在账号页是「收起」）。
  private func leaveAccount(step: String) {
    for _ in 0..<4 {
      guard app.otherElements["account.view"].exists else { return }
      let back = app.buttons["account.back"]
      guard back.exists, back.isHittable else { break }
      back.tap()
      _ = waitUntil(5) { !self.app.otherElements["account.view"].exists }
    }
    XCTAssertFalse(app.otherElements["account.view"].exists, "\(step)：账号页收不起来\n\(app.debugDescription)")
  }

  private func openFavoritesPage(step: String) {
    if app.buttons["favorites.more"].exists { return }
    let tab = app.buttons["bottom.favorites"]
    XCTAssertTrue(tab.waitForExistence(timeout: 60), "\(step)：底栏上没有自选格\n\(app.debugDescription)")
    tab.tap()
    XCTAssertTrue(app.buttons["favorites.more"].waitForExistence(timeout: 30), "\(step)：点了自选格但没到自选页\n\(app.debugDescription)")
  }

  /// 自选页头部搜索 → 打代号 → 按星的 label 决定点不点（星是开关）→ 取消退回。
  private func setFavorite(_ symbol: String, on: Bool, step: String) {
    openFavoritesPage(step: step)
    app.buttons["favorites.add"].tap()
    let query = app.textFields["search.query"]
    XCTAssertTrue(query.waitForExistence(timeout: 20), "\(step)：搜索页没打开\n\(app.debugDescription)")
    query.tap()
    query.typeText(symbol)
    let star = app.buttons["symbols.star." + testInstrumentKey(symbol)]
    XCTAssertTrue(star.waitForExistence(timeout: 60), "\(step)：搜索页没搜到 \(symbol)\n\(app.debugDescription)")
    if (star.label == "加入自选") == on { star.tap() }
    XCTAssertTrue(waitUntil(5) { (star.label == "加入自选") != on }, "\(step)：星的状态没变过来，label=\(star.label)")
    app.buttons["search.cancel"].tap()
  }

  private func expectFavorites(present: [String], absent: [String], step: String) {
    openFavoritesPage(step: step)
    let row = { (symbol: String) in self.app.buttons["favorites.open." + testInstrumentKey(symbol)] }
    let ok = waitUntil(60) { present.allSatisfy { row($0).exists } && absent.allSatisfy { !row($0).exists } }
    let report = (present + absent).map { "\($0)=\(row($0).exists ? "在" : "不在")" }.joined(separator: " ")
    XCTAssertTrue(ok, "\(step)：自选应当有 \(present)、没有 \(absent)，实际 \(report)\n\(app.debugDescription)")
  }

  /// 改动要过 500ms 防抖才进待发队列、再落盘；杀 app 之前给它这一拍。
  private func settle() { _ = XCTWaiter.wait(for: [XCTestExpectation(description: "settle")], timeout: 3) }

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
