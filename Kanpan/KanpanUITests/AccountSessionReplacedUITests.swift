import XCTest
import UIKit

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
//   3. 登回来这一下**自己也是同一类设备**，会把中途那台顶掉——规则是对称的，
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
//
// ------------------------------------------------------------ 2026-09-22 三处返工
//
// 这条用例在 09-21 的 M8 兼容性矩阵上同时犯了三个毛病，根因各不相同：
//
// A. **写死了「第二部手机」。** 规则是**按类**算的：服务端只撤 `device_kind` 相同
//    （或同一个 `device_id`）的活会话。在 iPad 上跑这条用例时本机报的是 `tablet`，
//    拿一台 `phone` 去登录根本碰不到它——设备列表照常 200，那句话永远不出现。
//    四台 iPad 全红就是这么来的。现在「第二台」跟着本机的类别走，期望的那句话
//    （手机 / 平板 / 电脑）和设备列表里的前缀也跟着走。
//
// B. **`continueAfterFailure = false` 用在了 `async` 用例上。** 那条路是靠
//    Objective-C 异常就地终止用例的，而异常穿不过 Swift 的 async 帧：断言一红，
//    之后第一个 `await` 就再也没有回来。iPad (A16) / iPad mini / iPhone 16 Plus
//    三条流水线全是这么挂死的——一条用例分别吃掉 7.1 / 4.5 / 5.4 小时，
//    后面八十多条用例一条都没跑上。现在失败一律走 `check(...)` **抛 Swift 错误**：
//    unwind 是正常路径，`defer` 和 `tearDown` 都照常跑完，红也是几分钟内红。
//
// C. **自己那几趟 HTTP 用了 `URLSession.shared`。** 它的资源超时是**七天**，
//    一趟卡住就没有尽头。现在统一走 `Self.http`（15s 请求 / 20s 资源），
//    并且只对「这一趟没发出去」做有限次重试——判据一个字都没松。

@MainActor final class AccountSessionReplacedUITests: XCTestCase {
  /// 现造的测试口令。不碰用户的真账号、真口令。
  private let password = "Testpass2026"
  private let api = "https://kanpan.107-174-172-10.sslip.io"
  /// 本机在服务端眼里算哪一类设备。和 app 壳层 `DeviceKind.current` 同一套判断
  /// （`AccountFeature.swift` 末尾）：模拟器上 `isiOSAppOnMac` 永远是 false，
  /// 所以只看 idiom。测试进程和被测 app 跑在同一台模拟器上，判出来是同一类。
  private let kind: (wire: String, label: String) = {
    switch UIDevice.current.userInterfaceIdiom {
    case .pad: ("tablet", "平板")
    case .mac: ("desktop", "电脑")
    default: ("phone", "手机")
    }
  }()
  /// 被同类设备顶下去时界面上该出现的那一句（`AccountError.sessionReplaced(_:)`
  /// 的 `errorDescription`）。在 iPhone 上是「手机」那一支，在 iPad 上是「平板」。
  private var notice: String { "这个账号在另一台\(kind.label)上登录了" }
  private var app: XCUIApplication!
  /// 这一轮在后端建过、还没确认删掉的账号。断言中途失败时兜底用。
  private var created: [String] = []

  /// 用例自己那几趟 HTTP 一律走这把会话，**不许用 `URLSession.shared`**：
  /// 后者的 `timeoutIntervalForResource` 默认是七天，一趟卡住就等于把整条流水线
  /// 挂在这儿（09-21 矩阵上三台机器就是这么被吃掉几个小时的）。
  /// 15s / 20s 和 app 里 `AccountClient` 那把（15s / 30s）同一个量级。
  private static let http: URLSession = {
    let configuration = URLSessionConfiguration.ephemeral
    configuration.timeoutIntervalForRequest = 15
    configuration.timeoutIntervalForResource = 20
    configuration.waitsForConnectivity = false
    return URLSession(configuration: configuration)
  }()

  override func setUp() async throws {
    // **不设 `continueAfterFailure = false`**：见文件头 B。这条是 `async` 用例，
    // 那条路会把测试进程的并发运行时搅坏、再也不返回。就地终止靠 `check(...)` 抛错。
    continueAfterFailure = true
    // 开了 `-test-timeouts-enabled YES` 的时候（`Tools/ui-test.sh` 现在一直开着），
    // 这条用例最多占 5 分钟墙钟。正常走完约 70s，全红也就两三分钟。
    executionTimeAllowance = 300
  }

  override func tearDown() async throws {
    let leftovers = created
    created = []
    for name in leftovers { await forceDelete(name) }
    app = nil
  }

  /// 断言失败就**抛 Swift 错误**退出这条用例。
  ///
  /// `XCTFail` 先把带 file:line 的那条失败记下来（日志里读到的还是原来那句话），
  /// 再抛 `AbortTest` 把栈正常收掉。判据没有任何放松——只是换了一条 `async`
  /// 帧走得通的退出路径。
  private func check(_ condition: Bool, _ message: @autoclosure () -> String,
                     file: StaticString = #filePath, line: UInt = #line) throws {
    if condition { return }
    XCTFail(message(), file: file, line: line)
    throw AbortTest()
  }

  // ------------------------------------------------------------ 正题

  /// 同一类的第二台设备登录，把本机顶下去；本机说得出是什么顶的，并且能登回来把它顶回去。
  ///
  /// 1. 干净档案起 app，注册一个随机账号（= 第一台，就是本机）；
  /// 2. 直接对线上 API 用**另一个 device id、同一个 kind** 登录同一账号（= 第二台）；
  /// 3. 本机再碰一次服务器：账号页 →「登录设备」，带 access 令牌 `GET /v1/auth/devices`；
  /// 4. 账号页上出现「这个账号在另一台…上登录了」，并且有「重新登录」；
  /// 5. 点「重新登录」，同一账号登回来（= 第三次登录，仍是这台机器），账号页关上；
  /// 6. 拿第二台的 access 令牌打 `/v1/auth/me`，应当也被顶成 401 `session_replaced`
  ///    ——规则对称，登回来的这一下把中途那台顶掉了；
  /// 7. 设备列表里这一类只剩一行，而且是「… · 本机」；
  /// 8. 注销账号，删干净。
  func testSecondDeviceOfThisClassEvictsThisOneAndReloginEvictsIt() async throws {
    let profile = UUID().uuidString
    app = makeApp(profile: profile)
    app.launch()
    defer { shot("收尾") }
    try check(app.buttons["bottom.settings"].waitForExistence(timeout: 90),
              "第 1 步：干净档案（profile=\(profile)）起 app 之后 90s 还没见到底栏设置格\n\(app.debugDescription)")

    // ---- 第 1 步：app 内注册 = 第一台（本机）
    let user = Self.randomName()
    created.append(user)
    try register(user, step: "第 1 步（注册 \(user) = 第一台 \(kind.label)）")
    shot("1-注册")

    // ---- 第 2 步：第二台（另一个 device id、同样的 kind）直接登录同一账号
    let second = try await loginDirect(user, deviceName: "uitest-\(kind.wire)-2",
                                       step: "第 2 步（第二台\(kind.label)登录）")

    // ---- 第 3 步：让本机再碰一次服务器（带 access 令牌的 GET /v1/auth/devices）
    //
    // 进出设备列表最多三趟：`.task { loadDevices() }` 每进一次就重发一趟请求，
    // 而那一趟可能只是撞上了 15s 请求超时（矩阵上 iPhone 16 Pro 那条 -1001 就是
    // 同一段网络抖的）。**判据一个字没松**：还是要页面上真的出现那句话。
    try openAccount(step: "第 3 步（打开账号页）")
    var struck = false
    for round in 1...3 {
      try tapLabel("登录设备", step: "第 3 步（打开设备列表，第 \(round) 趟）")
      if waitUntil(20, { self.app.staticTexts[self.notice].exists }) { struck = true; break }
      if round < 3 { try back(step: "第 3 步（退回账号页准备重开设备列表）") }
    }
    try check(struck,
              """
              第 3 步：本机（\(kind.label)）带着 access 令牌去取设备列表，应当撞上 401 session_replaced \
              并在页面上说出「\(notice)」；进出设备列表三趟、共等 60s 都没有这句话（当前报错=\(errorText())）
              \(app.debugDescription)
              """)
    shot("3-设备列表撞墙")

    // ---- 第 4 步：回账号页，横幅那一句 + 一条走得通的出路
    try back(step: "第 4 步（从设备列表退回账号页）")
    try check(waitUntil(20) { self.app.staticTexts[self.notice].exists },
              """
              第 4 步：账号页失效横幅应当是「\(notice)」而不是笼统的「登录已失效」，等了 20s 没等到
              \(app.debugDescription)
              """)
    let relogin = app.buttons["account.reauthenticate"]
    try check(relogin.waitForExistence(timeout: 20),
              "第 4 步：横幅下面没有「重新登录」（account.reauthenticate），人就被困在一个点什么都没用的账号页上\n\(app.debugDescription)")
    shot("4-账号页横幅")

    // ---- 第 5 步：点「重新登录」，同一账号登回来
    relogin.tap()
    try check(app.buttons["account.submit"].waitForExistence(timeout: 20),
              "第 5 步：点了「重新登录」没有摆出登录页\n\(app.debugDescription)")
    // 登录页上那一行字也得说清楚是被顶下来的（`AccountView` 里 `account.error` 那一处）。
    try check(errorText() == notice,
              "第 5 步：被顶回登录页时，登录页上那行字应当是「\(notice)」，实际是「\(errorText())」\n\(app.debugDescription)")
    shot("5-登录页")
    try typeUsername(user, step: "第 5 步（用户名）")
    try fillPassword(step: "第 5 步（口令）")
    app.buttons["account.submit"].tap()
    try check(waitUntil(45) { !self.app.otherElements["account.view"].exists },
              "第 5 步：登回 \(user) 没有闭合账号页，页面报错=\(errorText())\n\(app.debugDescription)")
    shot("5-登回来")

    // ---- 第 6 步：规则是对称的——登回来这一下把第二台顶掉了
    let after = await probe(path: "v1/auth/me", token: second)
    try check(after.status == 401,
              "第 6 步：本机登回来之后，第二台\(kind.label)的 access 令牌打 /v1/auth/me 应当是 401，实际 \(after.status)（\(after.body)）")
    try check(after.code == "session_replaced",
              "第 6 步：第二台\(kind.label)应当被顶成 session_replaced，实际 \(after.body)")

    // ---- 第 7 步：这一类只剩一行，而且是本机
    try openAccount(step: "第 7 步（打开账号页）")
    try tapLabel("登录设备", step: "第 7 步（再看一次设备列表）")
    let prefix = kind.label + " · "
    var mine: [String] = []
    let single = waitUntil(30) {
      mine = self.app.staticTexts.allElementsBoundByIndex
        .map(\.label).filter { $0.hasPrefix(prefix) }
      return mine == [prefix + "本机"]
    }
    try check(single,
              """
              第 7 步：\(kind.label)这一类同时只准一台在线，设备列表里应当只有「\(prefix)本机」一条，实际 \(mine)
              \(app.debugDescription)
              """)
    shot("7-设备列表")

    // ---- 第 8 步：删干净
    try back(step: "第 8 步（退回账号页）")
    try closeAccount(user, step: "第 8 步（注销 \(user)）")
    try check(created.isEmpty, "第 8 步：还有账号没删掉 \(created)")
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
  private func openAccount(step: String) throws {
    if !app.otherElements["account.view"].exists {
      let tab = app.buttons["bottom.settings"]
      try check(tab.waitForExistence(timeout: 60),
                "\(step)：底栏上没有设置格 bottom.settings\n\(app.debugDescription)")
      tab.tap()
      let row = app.buttons["settings.account"]
      try check(row.waitForExistence(timeout: 20),
                "\(step)：设置页上没有账号行 settings.account\n\(app.debugDescription)")
      row.tap()
    }
    try check(app.otherElements["account.view"].waitForExistence(timeout: 20),
              "\(step)：点了账号行但账号页没打开\n\(app.debugDescription)")
  }

  /// 账号页左上角那颗「‹」：在子页上是「返回上一层」。
  private func back(step: String) throws {
    let button = app.buttons["account.back"]
    try check(button.waitForExistence(timeout: 20),
              "\(step)：账号页左上角没有 account.back\n\(app.debugDescription)")
    button.tap()
  }

  private func tapLabel(_ label: String, step: String) throws {
    let button = app.buttons[label]
    try check(button.waitForExistence(timeout: 20),
              "\(step)：页面上没有「\(label)」\n\(app.debugDescription)")
    button.tap()
  }

  private func typeUsername(_ username: String, step: String) throws {
    let field = app.textFields["account.email"]
    try check(field.waitForExistence(timeout: 20),
              "\(step)：没有用户名输入框 account.email\n\(app.debugDescription)")
    // 「重新登录」那条路上 `AccountFeature.reauthenticate()` 已经把用户名预填好了，
    // 再敲一遍就变成接在后面。填对了就别动它。
    if (field.value as? String) == username { return }
    field.tap()
    field.typeText(username)
  }

  /// 口令要逐字符敲：整串 `typeText` 会被 iOS 的「强密码」建议气泡吃掉，只剩最后一个字符
  /// （`AccountMarketUITests` / `AccountPreferenceSyncUITests` 里踩过同一颗雷）。
  private func fillPassword(step: String) throws {
    let secure = app.secureTextFields["account.password"]
    try check(secure.waitForExistence(timeout: 20),
              "\(step)：没有口令输入框 account.password\n\(app.debugDescription)")
    secure.tap()
    if app.buttons["GenerateStrongPasswordButton"].waitForExistence(timeout: 2) { app.buttons["xmark"].tap() }
    try check(app.keyboards.firstMatch.waitForExistence(timeout: 20),
              "\(step)：点了口令框但键盘没起来\n\(app.debugDescription)")
    for character in password { secure.typeText(String(character)) }
  }

  private func register(_ username: String, step: String) throws {
    try openAccount(step: step)
    try tapLabel("注册", step: step)
    try typeUsername(username, step: step)
    try fillPassword(step: step)
    app.buttons["account.submit"].tap()
    try check(waitUntil(45) { !self.app.otherElements["account.view"].exists },
              "\(step)：注册没有闭合账号页，页面报错=\(errorText())\n\(app.debugDescription)")
  }

  /// 「注销账号」要再输一次口令。删成功之后 `AccountFeature` 自己会退登并收起账号页。
  private func closeAccount(_ username: String, step: String) throws {
    try openAccount(step: step)
    try tapLabel("注销账号", step: step)
    try fillPassword(step: step)
    app.buttons["account.submit"].tap()
    try check(waitUntil(45) { !self.app.otherElements["account.view"].exists },
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

  // ------------------------------------------------------------ 另一台设备（直接走 HTTP）

  private struct Device: Encodable {
    var id = UUID()
    var name: String
    var secret = UUID().uuidString + UUID().uuidString   // 服务端要求 32..=128 位
    var kind: String
  }
  private struct Credentials: Encodable { var username: String; var password: String; var device: Device }
  private struct Tokens: Decodable { struct Payload: Decodable { var accessToken: String }; var data: Payload }

  /// 发一趟请求。**只有「这一趟压根没发出去」（超时、连不上）才重试**，
  /// 服务端答复了就原样交出去——状态码是判据的一部分，不许吞。
  /// 三趟共 45s 封顶，绝不会把流水线挂住。
  private func exchange(_ request: URLRequest) async -> (data: Data, status: Int, failure: (any Error)?) {
    var last: (any Error)?
    for attempt in 0..<3 {
      if attempt > 0 { try? await Task.sleep(for: .seconds(1)) }
      do {
        let (data, response) = try await Self.http.data(for: request)
        return (data, (response as? HTTPURLResponse)?.statusCode ?? -1, nil)
      } catch { last = error }
    }
    return (Data(), -1, last)
  }

  /// 「另一台设备」在服务端眼里只是另一个 `device.id` + 一个类别，所以这一步不用真的
  /// 再起一个模拟器：对线上 API 发一趟 `POST /v1/auth/login` 就是一台新设备登录了。
  /// 类别跟着**本机**走——规则是按类算的，拿别的类别去登根本顶不掉本机。
  /// 交出它的 access 令牌，第 6 步拿它验「它自己后来也被顶掉了」。
  private func loginDirect(_ username: String, deviceName: String, step: String) async throws -> String {
    guard let base = URL(string: api) else { XCTFail("\(step)：API 地址不对 \(api)"); throw AbortTest() }
    var request = URLRequest(url: base.appendingPathComponent("v1/auth/login"))
    request.httpMethod = "POST"
    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
    request.httpBody = try JSONEncoder().encode(
      Credentials(username: username, password: password, device: Device(name: deviceName, kind: kind.wire)))
    let result = await exchange(request)
    try check((200..<300).contains(result.status),
              "\(step)：登录应当成功，实际 \(result.status)（\(String(data: result.data, encoding: .utf8) ?? "")\(result.failure.map { "，\($0)" } ?? "")）")
    guard let token = try? JSONDecoder().decode(Tokens.self, from: result.data).data.accessToken else {
      XCTFail("\(step)：登录回来的不是一对令牌（\(String(data: result.data, encoding: .utf8) ?? "")）")
      throw AbortTest()
    }
    return token
  }

  private struct AbortTest: Error, CustomStringConvertible {
    var description = "前面已经有一条断言红了，用例就地结束（详见上一条 failure）"
  }

  /// 拿某一把 access 令牌打一个接口，把状态码、错误码和原文都带回来
  /// ——断言失败时要说得出服务端到底回了什么。
  private func probe(path: String, token: String) async -> (status: Int, code: String, body: String) {
    struct Failure: Decodable { struct Payload: Decodable { var code: String }; var error: Payload }
    guard let base = URL(string: api) else { return (-1, "", "API 地址不对") }
    var request = URLRequest(url: base.appendingPathComponent(path))
    request.setValue("Bearer " + token, forHTTPHeaderField: "Authorization")
    let result = await exchange(request)
    if let failure = result.failure { return (-1, "", "请求没发出去：\(failure)") }
    let body = String(data: result.data, encoding: .utf8) ?? ""
    let code = (try? JSONDecoder().decode(Failure.self, from: result.data).error.code) ?? ""
    return (result.status, code, body)
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
      Credentials(username: username, password: password, device: Device(name: "uitest-cleanup", kind: kind.wire)))
    let session = await exchange(login)
    guard (200..<300).contains(session.status),
          let token = try? JSONDecoder().decode(Tokens.self, from: session.data).data.accessToken else { return }
    var remove = URLRequest(url: base.appendingPathComponent("v1/auth/account"))
    remove.httpMethod = "DELETE"
    remove.setValue("application/json", forHTTPHeaderField: "Content-Type")
    remove.setValue("Bearer " + token, forHTTPHeaderField: "Authorization")
    remove.httpBody = try? JSONEncoder().encode(Close(password: password))
    _ = await exchange(remove)
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
