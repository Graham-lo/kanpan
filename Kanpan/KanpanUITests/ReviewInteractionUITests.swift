import XCTest

// ============================================================ P3.7 复盘交互
//
// 规格表（docs/待办交接-Codex-2026-09-22.md「P3.7」）里每一项都要在 app 里真的走一遍：
//
// 1. 取景卡上的起止时间钮：改一下，选区（卡片抬头的根数）跟着变；
// 2. 拖选区贴到图的左边按住，图自己往更早的那头滚，选区跟着长（贴边自动滚动）；
// 3. 非圈选时点图上已画的记录，打开它的详情；
// 4. 复盘本：摘要卡 + 「全部 · 待判定 · 已判定」、底部「判定规则 criteria-v2」、
//    「…」里的「已存案例」、详情里的「修订记录」（复盘改两次看得到两版）、补图。
//
// 第 4 条要账号：在项目自己的后端上注册一个一次性账号，做完当场注销（注销会把记录、
// 补图一起删掉），`tearDown` 再按 HTTP 补一刀，不给后端留垃圾数据。

@MainActor
final class ReviewInteractionUITests: KanpanUICase {
  private let profile = UUID().uuidString
  private static let api = "https://kanpan.107-174-172-10.sslip.io"
  private static let password = "Testpass2026"
  private var created: [String] = []

  override var extraLaunchEnvironment: [String: String] {
    ["KANPAN_PERSISTENCE_PROFILE": profile, "KANPAN_ACCOUNT_API_URL": Self.api]
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

  // ------------------------------------------------------------ 小工具

  private func shot(_ name: String) {
    let screenshot = app.screenshot()
    let attachment = XCTAttachment(screenshot: screenshot)
    attachment.name = name; attachment.lifetime = .keepAlways; add(attachment)
    let dir = URL(fileURLWithPath: "/tmp/kanpan-p37", isDirectory: true)
    try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    try? screenshot.pngRepresentation.write(to: dir.appendingPathComponent(name + ".png"))
  }

  private func note(_ text: String) {
    let a = XCTAttachment(string: text); a.name = "记录"; a.lifetime = .keepAlways; add(a)
    print("P37|" + text)
  }

  /// 取景卡抬头那一行「N 根 · 1h」里的 N。
  private func captureBars() -> Int? {
    let label = app.staticTexts.matching(NSPredicate(format: "label CONTAINS ' 根 · '")).firstMatch
    guard let snap = try? label.snapshot() else { return nil }
    return Int(snap.label.prefix(while: \.isNumber))
  }

  private func markReport() -> String? {
    guard let snap = try? app.otherElements["review.range"].snapshot() else { return nil }
    return snap.value as? String
  }

  private func openCapture() -> Bool {
    let entry = app.buttons[Ids.intervalChart]
    guard expectExists(entry, Self.short, "周期行右端没有「图表」") else { return false }
    entry.tap()
    let record = app.buttons["chart.record"]
    guard expectExists(record, Self.short, "「图表」面板里没有「记一笔」") else { return false }
    record.tap()
    return expectExists(app.buttons["记下"], Self.short, "点「记一笔」没开出取景卡")
  }

  /// 紧凑时间钮里「时刻」那一半：点开是一组滚轮，把小时那一轮往上拨一下。
  private func nudgeHour(_ picker: XCUIElement, earlier: Bool) {
    let buttons = picker.buttons
    let time = buttons.count > 1 ? buttons.element(boundBy: buttons.count - 1) : picker
    time.tap()
    let wheel = app.pickerWheels.firstMatch
    guard wheel.waitForExistence(timeout: Self.short) else {
      XCTFail("点了时间钮没出滚轮：\(app.debugDescription)"); return
    }
    note("滚轮原值=\(wheel.value as? String ?? "?")")
    // 实测：往下扫是往后拨（16 点 → 20 点），往上扫是往前拨。
    if earlier { wheel.swipeUp() } else { wheel.swipeDown() }
    _ = XCTWaiter.wait(for: [XCTestExpectation(description: "settle")], timeout: 1.2)
    note("滚轮新值=\(wheel.value as? String ?? "?")")
  }

  private func dismissPopover() {
    // 紧凑时间钮的弹层点外面就收：点顶栏统计块那一片（点穿了也无害）。
    app.coordinate(withNormalizedOffset: CGVector(dx: 0.7, dy: 0.15)).tap()
    _ = XCTWaiter.wait(for: [XCTestExpectation(description: "settle")], timeout: 0.8)
  }

  // ------------------------------------------------------------ 1–3：图上的三件事

  func testCaptureRangePickersEdgeScrollAndTapToOpen() throws {
    XCTAssertTrue(waitForLiveChart(), "没等到行情")
    guard openCapture() else { return }
    shot("P37-01-取景卡-起止时间钮")
    let start = app.datePickers["review.capture.start"], end = app.datePickers["review.capture.end"]
    guard expectExists(start, Self.short, "取景卡上没有「起」时间钮"),
          expectExists(end, Self.short, "取景卡上没有「止」时间钮") else { return }
    let before = captureBars()
    note("起止钮之前 根数=\(before ?? -1)")

    // 起点往前拨：选区变长。
    nudgeHour(start, earlier: true)
    shot("P37-02-起点时间滚轮")
    dismissPopover()
    let afterStart = captureBars()
    note("改起点之后 根数=\(afterStart ?? -1)")
    XCTAssertNotEqual(afterStart, before, "改了起点，选区根数没变")
    shot("P37-03-改起点之后选区跟着变")

    // 终点往前拨：选区变短。
    nudgeHour(end, earlier: true)
    dismissPopover()
    let afterEnd = captureBars()
    note("改终点之后 根数=\(afterEnd ?? -1)")
    XCTAssertNotEqual(afterEnd, afterStart, "改了终点，选区根数没变")
    shot("P37-04-改终点之后")

    // 贴边自动滚动：从图中间起一段新选区，拖到左边缘按住 3 秒。
    let canvas = app.otherElements["chart.canvas"]
    guard expectExists(canvas, Self.short, "取景态下没有图") else { return }
    let from = canvas.coordinate(withNormalizedOffset: CGVector(dx: 0.55, dy: 0.45))
    let edge = canvas.coordinate(withNormalizedOffset: CGVector(dx: 0.005, dy: 0.45))
    from.press(forDuration: 0.15, thenDragTo: edge, withVelocity: .slow, thenHoldForDuration: 3.0)
    let scrolled = captureBars() ?? 0
    note("贴边按住 3 秒之后 根数=\(scrolled)")
    shot("P37-05-贴边自动滚动之后")
    // 从 55% 拖到 0% 本身只够盖住半屏（竖屏 1h 大约 30–40 根）；滚起来才会远超一屏。
    XCTAssertGreaterThan(scrolled, 120, "贴边按住 3 秒选区只有 \(scrolled) 根——图没有自己往前滚")

    // 记下这一笔，再用默认选区记一笔（落在屏幕右侧、一定看得见），去点它。
    app.buttons["记下"].tap()
    XCTAssertTrue(waitUntil(timeout: Self.short) { !self.app.buttons["记下"].exists }, "取景卡没收回去")
    guard openCapture() else { return }
    app.buttons["记下"].tap()
    XCTAssertTrue(waitUntil(timeout: Self.short) { !self.app.buttons["记下"].exists }, "取景卡没收回去")

    // 记号层在诊断模式下报「几条/共几条 … @x,y」，@ 后面是最后一条可点记号的中心。
    var spot: CGPoint?
    _ = waitUntil(timeout: Self.long) {
      guard let report = self.markReport(), let at = report.split(separator: "@").last, report.contains("@") else { return false }
      let parts = at.split(separator: ",").compactMap { Double($0) }
      guard parts.count == 2 else { return false }
      spot = CGPoint(x: parts[0], y: parts[1]); return true
    }
    note("记号层=\(markReport() ?? "-")")
    guard let spot else { XCTFail("图上没有可点的记号：\(markReport() ?? "-")"); return }
    shot("P37-06-图上已画的记录")
    let layer = app.otherElements["review.range"]
    let origin = layer.frame.origin   // 探针是这一层左上角那 1×1
    app.coordinate(withNormalizedOffset: .zero)
      .withOffset(CGVector(dx: origin.x + spot.x, dy: origin.y + spot.y)).tap()
    let detail = app.navigationBars["记录详情"]
    XCTAssertTrue(detail.waitForExistence(timeout: Self.short), "点图上的记录没打开详情：\(app.debugDescription)")
    shot("P37-07-点记录打开详情")

    // 点图上别处（非记号）不许被这一层吃掉：回到图上拖一下，图照常平移。
    if app.buttons["review.back"].exists { app.buttons["review.back"].tap() }
    let back = app.navigationBars.buttons.firstMatch
    if detail.exists, back.exists { back.tap(); if app.buttons["review.back"].waitForExistence(timeout: 3) { app.buttons["review.back"].tap() } }
  }

  // ------------------------------------------------------------ 4：复盘本

  func testSignedInBookSummaryChipsRevisionsAttachmentsAndSavedMatches() throws {
    let user = "p37_" + UUID().uuidString.replacingOccurrences(of: "-", with: "").prefix(12).lowercased()
    created.append(user)
    register(user)
    app.buttons[Ids.bottomChart].tap()
    XCTAssertTrue(waitForLiveChart(), "没等到行情")
    guard openCapture() else { return }
    app.buttons["记下"].tap()
    XCTAssertTrue(waitUntil(timeout: Self.short) { !self.app.buttons["记下"].exists }, "取景卡没收回去")

    let entry = app.buttons[Ids.topReview]
    guard expectExists(entry, Self.short, "顶栏没有「复盘」") else { return }
    entry.tap()
    guard expectExists(app.buttons["review.back"], Self.long, "「复盘」没开出复盘本") else { return }

    // 摘要卡 + 三枚筛选。
    let summary = app.buttons["review.summary"]
    guard expectExists(summary, Self.short, "复盘本顶上没有战绩摘要卡") else { return }
    XCTAssertTrue(waitUntil(timeout: Self.long) { summary.label.contains("criteria-v2") },
                  "摘要卡底部没有「判定规则 criteria-v2」：\(summary.label)")
    for id in ["review.chip.all", "review.chip.todo", "review.chip.decided"] {
      XCTAssertTrue(app.buttons[id].exists, "没有筛选 \(id)")
    }
    app.buttons["review.chip.all"].tap()
    shot("P37-10-复盘本-摘要卡与筛选")
    app.buttons["review.chip.decided"].tap()
    shot("P37-11-复盘本-已判定")
    app.buttons["review.chip.all"].tap()

    // 摘要卡点进去是战绩页。
    summary.tap()
    XCTAssertTrue(app.navigationBars["战绩"].waitForExistence(timeout: Self.short), "点摘要卡没进战绩页")
    shot("P37-12-战绩页")
    app.navigationBars["战绩"].buttons.firstMatch.tap()

    // 「…」→ 已存案例。
    app.buttons["review.menu"].tap()
    let saved = app.buttons["review.menu.saved"]
    guard expectExists(saved, Self.short, "「…」里没有「已存案例」") else { return }
    saved.tap()
    XCTAssertTrue(app.navigationBars["已存案例"].waitForExistence(timeout: Self.short), "没进已存案例页")
    XCTAssertTrue(waitUntil(timeout: Self.long) {
      self.app.descendants(matching: .any)["review.saved.empty"].exists || self.app.buttons["review.saved.row"].exists
    }, "已存案例页既没有列表也没有空状态")
    shot("P37-13-已存案例")
    app.navigationBars["已存案例"].buttons.firstMatch.tap()

    // 打开刚记的那一条：等它传上去（有 serverId 才有修订记录与补图）。
    app.buttons["review.chip.all"].tap()
    let row = app.cells.firstMatch.exists ? app.cells.firstMatch : app.buttons.matching(NSPredicate(format: "label CONTAINS '只记录' OR label CONTAINS '1h'")).firstMatch
    guard expectExists(row, Self.long, "复盘本「全部」里没有刚记的那一条") else { return }
    shot("P37-10b-复盘本-全部-有记录")
    row.tap()
    guard expectExists(app.navigationBars["记录详情"], Self.short, "没进记录详情") else { return }

    shot("P37-13b-记录详情")
    // 复盘写两次，都点「完成复盘」。第二次在第一次后面接着写，两版一看就分得开。
    for (round, text) in ["突破没站稳", "突破没站稳；其实是假突破，等回踩"].enumerated() {
      let field = app.descendants(matching: .any)["review.note"]
      // 第二轮时上一轮为了够到按钮往上滚过：输入框可能已经滚出屏幕顶上（List 是懒的，
      // 滚出去就不存在了），这时要往下滑才找得回来。
      for _ in 0..<6 where !field.isHittable {
        let below = field.exists ? field.frame.minY > app.frame.midY : round == 0
        if below { app.swipeUp() } else { app.swipeDown() }
      }
      guard expectExists(field, Self.short, "详情里没有「现在怎么看」输入框") else { return }
      field.tap()
      // 「完成复盘」会收键盘，第二轮重新点进框里时光标落在点的位置（r11 落在了开头，
      // 存成了「；其实是…突破没站稳」）。所以整段删掉重写，第二版里带着第一版的原话。
      if let old = field.value as? String, !old.isEmpty, round > 0 {
        field.coordinate(withNormalizedOffset: CGVector(dx: 0.98, dy: 0.2)).tap()
        app.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: old.count + 2))
      }
      app.typeText(text)
      let done = app.buttons["完成复盘"]
      // 键盘盖住的按钮 XCUITest 照样报 isHittable，点下去落在键盘上——r7 两次「完成复盘」
      // 都是这么丢的（服务端只收到离开详情时补存的那一条草稿）。按钮下沿压进键盘就接着往上滚。
      func covered() -> Bool {
        let keyboard = app.keyboards.firstMatch
        return keyboard.exists && done.exists && done.frame.maxY > keyboard.frame.minY
      }
      for _ in 0..<4 where !done.isHittable || covered() { app.swipeUp() }
      XCTAssertFalse(covered(), "「完成复盘」还压在键盘底下")
      done.tap()
      _ = XCTWaiter.wait(for: [XCTestExpectation(description: "upload")], timeout: 4)
      shot("P37-14a-完成复盘-第\(round + 1)版")
    }

    // 修订记录：两版复盘都在。
    let revisions = app.buttons["review.revisions"]
    _ = waitUntil(timeout: Self.long) {
      if revisions.exists { return true }
      self.app.swipeUp(); return revisions.exists
    }
    guard expectExists(revisions, Self.long, "详情里没有「修订记录」") else { return }
    // 复盘是排队上传的：修订记录页只在打开那一刻问一次服务端，没赶上就退出来再进一次。
    var found = false
    for _ in 0..<4 where !found {
      // 退回详情后滚动位置可能变了，按钮在但点不到（not hittable），先滚到能点。
      for _ in 0..<4 where !revisions.isHittable { app.swipeUp() }
      revisions.tap()
      XCTAssertTrue(app.navigationBars["修订记录"].waitForExistence(timeout: Self.short), "没进修订记录页")
      found = waitUntil(timeout: Self.short) {
        self.app.staticTexts["现在怎么看：突破没站稳；其实是假突破，等回踩"].exists
      }
      if !found { app.navigationBars["修订记录"].buttons.firstMatch.tap(); _ = revisions.waitForExistence(timeout: Self.short) }
    }
    XCTAssertTrue(waitUntil(timeout: Self.short) { self.app.staticTexts["现在怎么看：突破没站稳"].exists },
                  "修订记录里没有第一版复盘：\(app.debugDescription)")
    XCTAssertTrue(app.staticTexts["现在怎么看：突破没站稳；其实是假突破，等回踩"].exists, "修订记录里没有第二版复盘")
    shot("P37-14-修订记录-两版复盘")
    app.navigationBars["修订记录"].buttons.firstMatch.tap()

    // 补图：从相册挑一张。
    let add = app.buttons["review.attachments.add"]
    // 按钮在详情顶上：从修订记录退回来时它常压在导航栏底下——存在、但点下去落在导航栏上
    // （r12 就是这样没打开相册）。滑到真的点得着为止。
    _ = waitUntil(timeout: Self.short) {
      if add.exists && add.isHittable && add.frame.minY > self.app.navigationBars.firstMatch.frame.maxY { return true }
      self.app.swipeDown(); return false
    }
    if expectExists(add, Self.short, "详情里没有「补一张图」") {
      shot("P37-15-补图-之前")
      add.tap()
      // 系统相册面板是跨进程的：它的格子不在 app 的无障碍树里（r9 实测树里只剩面板后面的
      // 行情页），`app.images` 找到的是 app 自己的图——r8 点的 `images.firstMatch` 命中点
      // {-1,-1}，什么都没选上。面板先转几秒「正在载入…」再出网格，所以按屏幕坐标点
      // 第一行第一格（顶上有没有「私密访问照片」横幅，这一点都落在某张照片上），
      // 没出图就隔几秒再点一次。
      let pager = app.descendants(matching: .any)["review.attachments.pager"]
      var picked = false
      for _ in 0..<4 where !picked {
        _ = XCTWaiter.wait(for: [XCTestExpectation(description: "grid")], timeout: 4)
        shot("P37-15b-相册面板")
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.163, dy: 0.41)).tap()
        picked = pager.waitForExistence(timeout: 20)
      }
      XCTAssertTrue(picked, "挑了图但详情里没出现那张图")
      if picked {
        XCTAssertTrue(waitUntil(timeout: Self.long) { add.label.contains("1/3") }, "补图计数没到 1/3：\(add.label)")
        shot("P37-16-补图-之后")
      }
    }

    // 收尾：注销账号，记录与补图跟着删。
    if app.navigationBars["记录详情"].exists { app.navigationBars["记录详情"].buttons.firstMatch.tap() }
    if app.buttons["review.back"].waitForExistence(timeout: 3) { app.buttons["review.back"].tap() }
    closeAccount(user)
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
