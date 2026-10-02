import XCTest

// ============================================================ P3.7 复盘交互
//
// 规格表（docs/待办交接-Codex-2026-09-22.md「P3.7」）里每一项都要在 app 里真的走一遍：
//
// 1–2. 取景（收设置项 2026-09-28 改）：圈的就是图上看得见的那一段——拖图、捏图，卡片上那行
//      「x 根 · 起 – 止」跟着变；原来的起止时间钮、贴边自动滚动一并收掉；
// 3. 非圈选时点图上已画的记录，打开它的详情；
// 4. 复盘本：摘要卡 + 「全部 · 待判定 · 已判定」（「判定规则 criteria-v2」UI 整改 P3 撤了，断言它不再上屏）、
//    「…」里的「已存案例」、详情里的「修订记录」（复盘改两次看得到两版）、补图。
//
// 第 4 条要账号：在项目自己的后端上注册一个一次性账号，做完当场注销（注销会把记录、
// 补图一起删掉），`tearDown` 再按 HTTP 补一刀，不给后端留垃圾数据。

@MainActor
final class ReviewInteractionUITests: KanpanUICase {
  private let profile = UUID().uuidString
  private static let api = "https://kanpan.43-160-232-253.sslip.io"
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

  /// 取景卡上那一行「N 根 · 起 – 止」里的 N。
  private func captureBars() -> Int? {
    guard let label = captureRange() else { return nil }
    return Int(label.prefix(while: \.isNumber))
  }

  private func markReport() -> String? {
    guard let snap = try? app.otherElements["review.range"].snapshot() else { return nil }
    return snap.value as? String
  }

  private func openCapture() -> Bool {
    // 2026-09-28 顶栏方案 B：「记一笔」是顶栏右侧那颗书本圆片，不再在图表设置里。
    let record = app.buttons[Ids.topNote]
    guard expectExists(record, Self.short, "顶栏没有「记一笔」那颗") else { return false }
    record.tap()
    return expectExists(app.buttons["记下"], Self.short, "点「记一笔」没开出取景卡")
  }

  /// 取景卡上那一行「x 根 · 起 – 止」（收设置项 2026-09-28 起只读）。
  private func captureRange() -> String? {
    (try? app.staticTexts["review.capture.range"].snapshot())?.label
  }

  // ------------------------------------------------------------ 1–3：图上的三件事

  /// 取景：圈的就是图上看得见的那一段（收设置项 2026-09-28）。原来这条用例拨卡片上的
  /// 起止时间钮、再拖选区贴边自动滚；那两样都收掉了——现在拖图、捏图就是在圈，
  /// 卡片上只读一行「x 根 · 起 – 止」。把握、到期也不再在卡片上。
  func testCaptureFollowsViewportAndTapToOpen() throws {
    XCTAssertTrue(waitForLiveChart(), "没等到行情")
    guard openCapture() else { return }
    shot("P37-01-取景卡-只读区间")
    let rangeLine = app.staticTexts["review.capture.range"]
    guard expectExists(rangeLine, Self.short, "取景卡上没有「x 根 · 起 – 止」那一行") else { return }
    XCTAssertFalse(app.datePickers.firstMatch.exists, "取景卡上不该再有时间钮")
    XCTAssertFalse(app.buttons["review.capture.more"].exists, "取景卡上不该再有「更多」")
    XCTAssertFalse(app.staticTexts["把握"].exists, "取景卡上不该再有「把握」")
    XCTAssertTrue(app.staticTexts["来源"].exists, "「来源」该直接摆在卡片上")
    let before = captureBars(), beforeText = captureRange() ?? ""
    note("打开取景卡 \(beforeText)")
    XCTAssertGreaterThanOrEqual(before ?? 0, 3, "取景区间不足三根：\(beforeText)")

    // 往右拖图（看更早的）：区间跟着视野往前挪。拖的是图的上半截，下半截压着取景卡。
    let canvas = app.otherElements["chart.canvas"]
    guard expectExists(canvas, Self.short, "取景态下没有图") else { return }
    canvas.coordinate(withNormalizedOffset: CGVector(dx: 0.25, dy: 0.2))
      .press(forDuration: 0.05, thenDragTo: canvas.coordinate(withNormalizedOffset: CGVector(dx: 0.75, dy: 0.2)))
    XCTAssertTrue(waitUntil(timeout: Self.short) { (self.captureRange() ?? beforeText) != beforeText },
                  "拖了图，取景区间没跟着视野走：\(captureRange() ?? "-")")
    let panned = captureRange() ?? ""
    note("拖图之后 \(panned)")
    shot("P37-02-拖图之后区间跟着走")

    // 捏图：看得见的根数变了，卡片上的根数跟着变。合成的捏小在模拟器上有时不生效
    // （见 `ChartLayoutPersistenceUITests.pinchUntilLayoutChanges`），不动就改捏大。
    let beforePinch = captureBars()
    canvas.pinch(withScale: 0.4, velocity: -1)
    if !waitUntil(timeout: 2, { self.captureBars() != beforePinch }) { canvas.pinch(withScale: 2.6, velocity: 1) }
    XCTAssertTrue(waitUntil(timeout: Self.short) { self.captureBars() != beforePinch },
                  "捏了图，取景根数没变：\(captureRange() ?? "-")")
    note("捏图之后 \(captureRange() ?? "-")")
    shot("P37-03-捏图之后根数跟着变")

    // 记下这一笔，再开一次取景直接记一笔（区间就是当前这一屏、一定看得见），去点它。
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

  /// 取景卡三套皮肤各一张（收设置项 2026-09-28 验收）：只读区间一行、来源一行，
  /// 没有起止钮、把握、到期。切到「看多」让目标 / 失效两条线和两个价框也上屏。
  func testCaptureCardInThreeSkins() throws {
    let out = URL(fileURLWithPath: "/Users/mdd/zhk/kanpan/docs/acceptance/收设置项-2026-09-28", isDirectory: true)
    let tag: String = switch Int(app.windows.firstMatch.frame.width.rounded()) {
    case 402: "iPhone16Pro"
    case 440: "iPhone17ProMax"
    case let w: "宽\(w)"
    }
    for (skin, name) in [("sage", "青苔"), ("terra", "陶土"), ("classic", "经典")] {
      XCTAssertTrue(app.openSettingsFromMe(), "「我的 › 设置」没开出来")
      let card = app.buttons["display.theme." + skin]
      XCTAssertTrue(card.waitForExistence(timeout: Self.short), "设置页上没有皮肤卡 \(skin)")
      for _ in 0..<3 where (card.value as? String) != "已选" {
        if waitUntil(timeout: Self.short, { card.isHittable }) { card.tap() }
        else { card.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap() }
        _ = waitUntil(timeout: 3) { (card.value as? String) == "已选" }
      }
      let light = app.buttons["display.mode.浅色"]
      if light.waitForExistence(timeout: Self.short), !light.isSelected { light.tap() }
      app.navigationBars.buttons.firstMatch.tap()
      let chartTab = app.buttons[Ids.bottomChart]
      XCTAssertTrue(chartTab.waitForExistence(timeout: Self.short), "底栏没有图表那格")
      chartTab.tap()
      XCTAssertTrue(waitForLiveChart(), "没等到行情")
      guard openCapture() else { return }
      let long = app.buttons["看多"]
      if long.waitForExistence(timeout: Self.short) { long.tap() }
      XCTAssertTrue(app.staticTexts["review.capture.range"].waitForExistence(timeout: Self.short), "取景卡上没有区间那一行")
      XCTAssertFalse(app.datePickers.firstMatch.exists, "取景卡上不该再有时间钮")
      XCTAssertFalse(app.staticTexts["把握"].exists, "取景卡上不该再有「把握」")
      XCTAssertFalse(app.staticTexts["到期"].exists, "取景卡上不该再有「到期」")
      _ = waitUntil(timeout: 1.5) { false }   // 等选区与线画稳
      let screenshot = XCUIScreen.main.screenshot()
      let file = "\(tag)-取景卡-\(name)"
      let a = XCTAttachment(screenshot: screenshot); a.name = file; a.lifetime = .keepAlways; add(a)
      try? FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)
      try? screenshot.pngRepresentation.write(to: out.appendingPathComponent(file + ".png"))
      app.buttons["收起"].tap()
      XCTAssertTrue(waitUntil(timeout: Self.short) { !self.app.buttons["记下"].exists }, "取景卡没收回去")
    }
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

    // 2026-09-27 底栏四格：顶栏那颗复盘撤了，复盘本从「我的 › 复盘本」进。
    XCTAssertTrue(app.openReviewBookFromMe(), "「我的 › 复盘本」没开出复盘本")
    guard expectExists(app.buttons["review.back"], Self.long, "「复盘本」没开出复盘本") else { return }

    // 摘要卡 + 三枚筛选。
    let summary = app.buttons["review.summary"]
    guard expectExists(summary, Self.short, "复盘本顶上没有战绩摘要卡") else { return }
    // 判定算法的版本号是审计字段，不上屏（UI 整改 P3）：摘要卡与整页都不许再出现它。
    XCTAssertFalse(summary.label.contains("criteria-v2"), "摘要卡上还有判定规则版本号：\(summary.label)")
    XCTAssertFalse(app.staticTexts.containing(NSPredicate(format: "label CONTAINS 'criteria-v2'")).firstMatch.exists,
                   "复盘本上还有「判定规则 criteria-v2」")
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
      shot("P37-15c-挑完之后")
      XCTAssertTrue(picked, "挑了图但详情里没出现那张图")
      if picked {
        // 详情顶上多了「当时那张图」之后，挑完图那一刻「补一张图」常落在屏幕下沿之外——
        // List 是懒加载的，出了屏的行不在无障碍树里，直接读 `.label` 会当场抛错。先滑到它出来。
        for _ in 0..<4 where !add.exists { app.swipeUp() }
        XCTAssertTrue(waitUntil(timeout: Self.long) { add.exists && add.label.contains("1/3") },
                      "补图计数没到 1/3：\(add.exists ? add.label : "按钮不在屏上")")
        shot("P37-16-补图-之后")
      }
    }

    // 收尾：注销账号，记录与补图跟着删。
    if app.navigationBars["记录详情"].exists { app.navigationBars["记录详情"].buttons.firstMatch.tap() }
    if app.buttons["review.back"].waitForExistence(timeout: 3) { app.buttons["review.back"].tap() }
    closeAccount(user)
  }

  // ------------------------------------------------------------ P3.8：找相似

  /// 15m 和 4h 各框一段、点「找相似」，任务要真的跑完（线上后端、全市场一年历史）：出结果或
  /// 「没有很像的区间」都算完成——有没有命中取决于当时那段行情（2026-09-24 实测 BTCUSDT 15m
  /// 精确取满 300 个候选也没有一个过 0.60，4h 有），用例不能假设某一档一定有。
  /// 哪一档先出结果就在那一页左滑存下第一条，再去复盘本「…」→「已存案例」看到它；两档都没命中才算失败。
  func testFindSimilarOn15mAnd4hAndSaveOne() throws {
    let user = "p38_" + UUID().uuidString.replacingOccurrences(of: "-", with: "").prefix(12).lowercased()
    created.append(user)
    register(user)
    app.buttons[Ids.bottomChart].tap()
    XCTAssertTrue(waitForLiveChart(), "没等到行情")
    var savedOne = false
    for tf in ["15m", "4h"] {
      app.tapIntervalChip(tf)
      // 15m 不在出厂钉住的那几档里（周期条只列钉住的，见 U12）：没有那颗胶囊时，
      // 「更多」那颗的读法会写「当前 15 分钟」。
      let spoken = ["15m": "15 分钟", "4h": "4 小时"][tf] ?? tf
      XCTAssertTrue(waitUntil(timeout: Self.long) {
        let chip = self.app.buttons[Ids.intervalChip(tf)]
        return (chip.exists && chip.isSelected)
          || self.app.buttons[Ids.intervalMore].label.hasSuffix("当前 \(spoken)")
      }, "没切到 \(tf)")
      XCTAssertTrue(waitForLiveChart(), "\(tf) 没等到行情")
      guard openCapture() else { return }
      XCTAssertTrue(waitUntil(timeout: Self.short) { (self.captureBars() ?? 0) >= 16 }, "\(tf) 取景不到 16 根")
      note("\(tf) 取景根数=\(captureBars() ?? -1)")
      app.buttons["找相似"].tap()
      XCTAssertTrue(app.navigationBars["找相似"].waitForExistence(timeout: Self.short), "\(tf) 没开出找相似")
      let row = app.buttons.matching(NSPredicate(format: "label CONTAINS '相似 0.'")).firstMatch
      let started = Date()
      let found = waitUntil(timeout: 150, poll: 1) {
        row.exists || self.app.staticTexts["没有很像的区间"].exists
      }
      note("\(tf) 找相似用时 \(Int(Date().timeIntervalSince(started))) 秒，结果行=\(row.exists)")
      XCTAssertTrue(found, "\(tf) 找相似没跑完（既没结果也没空状态）：\(app.debugDescription)")
      shot("P38-\(tf)-找相似结果")
      if !savedOne, row.exists {
        row.swipeLeft()
        let save = app.buttons["保存"]
        if expectExists(save, Self.short, "左滑没出「保存」") {
          save.tap()
          _ = XCTWaiter.wait(for: [XCTestExpectation(description: "save")], timeout: 2)
          row.swipeLeft()
          XCTAssertTrue(app.buttons["已保存"].waitForExistence(timeout: Self.short), "存了之后左滑没变成「已保存」")
          shot("P38-\(tf)-已保存")
          row.swipeRight()
          savedOne = true
        }
      }
      app.buttons["review.search.back"].tap()
      XCTAssertTrue(waitUntil(timeout: Self.short) { !self.app.navigationBars["找相似"].exists }, "找相似没关掉")
      app.buttons["记下"].tap()
      XCTAssertTrue(waitUntil(timeout: Self.short) { !self.app.buttons["记下"].exists }, "取景卡没收回去")
    }

    XCTAssertTrue(savedOne, "15m 与 4h 两档都没有命中，存不了案例")
    guard savedOne else { closeAccount(user); return }

    // 复盘本「…」→「已存案例」：刚存的那一条在。
    XCTAssertTrue(app.openReviewBookFromMe(), "「我的 › 复盘本」没开出复盘本")  // 2026-09-27 底栏四格
    guard expectExists(app.buttons["review.back"], Self.long, "「复盘本」没开出复盘本") else { return }
    app.buttons["review.menu"].tap()
    let saved = app.buttons["review.menu.saved"]
    guard expectExists(saved, Self.short, "「…」里没有「已存案例」") else { return }
    saved.tap()
    XCTAssertTrue(app.buttons["review.saved.row"].waitForExistence(timeout: Self.long), "已存案例里没有刚存的那一条")
    shot("P38-已存案例-有一条")
    app.navigationBars["已存案例"].buttons.firstMatch.tap()
    if app.buttons["review.back"].waitForExistence(timeout: 3) { app.buttons["review.back"].tap() }
    closeAccount(user)
  }

  // ------------------------------------------------------------ 账号

  private func openAccountPage() {
    if app.accountView.exists { return }
    // 2026-09-27 底栏四格：账号从「我的」顶上那张账号卡推进去（原来是「设置 › 账号」）。
    expectExists(app.buttons[Ids.bottomMe], Self.long, "底栏上没有「我的」格")
    XCTAssertTrue(app.openAccountFromMe(), "「我的 › 账号」没推出账号页")
    expectExists(app.accountView, Self.long, "点了账号卡但账号页没打开")
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
    XCTAssertTrue(waitUntil(timeout: 60) { !self.app.accountView.exists },
                  "注册 \(username) 没有闭合账号页")
  }

  private func closeAccount(_ username: String) {
    openAccountPage()
    let entry = app.buttons["注销账号"]
    expectExists(entry, Self.long, "账号页上没有「注销账号」")
    entry.tap()
    fill(username: nil)
    app.buttons["account.submit"].tap()
    XCTAssertTrue(waitUntil(timeout: 60) { !self.app.accountView.exists },
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
