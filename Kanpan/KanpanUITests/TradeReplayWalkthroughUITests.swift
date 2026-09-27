import XCTest

// ============================================================ 自动复盘 3d · 交易回放 · 交易员走查
//
// `TradeReplayUITests` 按功能点断言；这一份是以交易员的身份把回放从头到尾真的看一遍，
// 量「看得舒不舒服」和「被打断时会不会留下半截」：
//
// 1. 节奏：点进来不用再点就在播；整趟（开仓前 20 根 → 平仓后 5 根）落在 20–40 秒里
//    （倍速按根数自动挑，1–4×）；走到开仓那根停一下；持仓那段浮盈胶囊一根一变；
//    平仓后第 5 根自己停、按钮变「重播」；退出回到这笔详情，没写过「当时怎么想」就滚到那一节。
// 2. 打断：暂停着等 6 秒游标不动（行情推送不许拨它）；退后台再回来、横过来再竖回去，
//    回放还是那一趟、游标没被重置；横屏时左侧周期栏不出现（回放是这一笔的周期，不许半截换）。
// 3. 取不到 K 线（币安 REST 按死）：一句吐司、自己退回这笔详情，不留在空图上。
// 4. 最大动态字号：标题和浮盈胶囊各自一行。
@MainActor
final class TradeReplayWalkthroughUITests: KanpanUICase {
  private let profile = UUID().uuidString

  override var extraLaunchEnvironment: [String: String] {
    var env = ["KANPAN_PERSISTENCE_PROFILE": profile, "KANPAN_EXCHANGE_FIXTURE": "1",
               "KANPAN_EXCHANGE_FIXTURE_KEY": "DEMOREADONLY7C31"]
    if name.contains("HistoryUnavailable") { env["KANPAN_TEST_BINANCE_REST_DOWN"] = "1" }
    return env
  }

  override var extraLaunchArguments: [String] {
    name.contains("LargestType")
      ? ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"] : []
  }

  override func setUp() async throws {
    XCUIDevice.shared.orientation = .portrait
    try await super.setUp()
  }

  override func tearDown() async throws {
    XCUIDevice.shared.orientation = .portrait
    try await super.tearDown()
  }

  private static let outDir = URL(
    fileURLWithPath: "/Users/mdd/zhk/kanpan/docs/acceptance/自动复盘-2026-09-27", isDirectory: true)

  private var deviceTag: String {
    switch Int(min(app.windows.firstMatch.frame.width, app.windows.firstMatch.frame.height).rounded()) {
    case 402: "iPhone16Pro"
    case 440: "iPhone17ProMax"
    case let w: "宽\(w)"
    }
  }

  private func note(_ line: String) {
    print("走查|" + line)
    let a = XCTAttachment(string: line); a.name = "走查"; a.lifetime = .keepAlways; add(a)
  }

  private func shot(_ page: String) {
    let screenshot = XCUIScreen.main.screenshot()
    let name = "\(deviceTag)-交易回放-\(page)"
    let a = XCTAttachment(screenshot: screenshot); a.name = name; a.lifetime = .keepAlways; add(a)
    try? FileManager.default.createDirectory(at: Self.outDir, withIntermediateDirectories: true)
    try? screenshot.pngRepresentation.write(to: Self.outDir.appendingPathComponent(name + ".png"))
  }

  // ------------------------------------------------------------ 元素

  private var disc: XCUIElement { app.buttons["trade.detail.replay"] }
  private var title: XCUIElement { app.descendants(matching: .any)["review.replay.title"] }
  private var capsule: XCUIElement { app.descendants(matching: .any)["review.replay.pnl"] }
  private var detailBar: XCUIElement { app.navigationBars["交易详情"] }
  private var pauseButton: XCUIElement { app.buttons["暂停"] }
  private var playButton: XCUIElement { app.buttons["播放"] }
  private var replayButton: XCUIElement { app.buttons["重播"] }
  private var speedButton: XCUIElement { app.buttons.matching(NSPredicate(format: "label BEGINSWITH '倍速'")).firstMatch }

  private func report() -> [String: Int64]? {
    guard let snap = try? app.otherElements["review.range"].snapshot(),
          let text = snap.value as? String, text.contains(" trade ") else { return nil }
    var out: [String: Int64] = [:]
    let head = text.prefix(while: { $0 != " " }).split(separator: "/")
    if head.count == 2 { out["shown"] = Int64(head[0]); out["total"] = Int64(head[1]) }
    for token in text.split(separator: " ") {
      guard let eq = token.firstIndex(of: "=") else { continue }
      out[String(token[..<eq])] = Int64(token[token.index(after: eq)...])
    }
    return out
  }

  private func openClosedBTC(file: StaticString = #filePath, line: UInt = #line) -> Bool {
    let review = app.buttons[Ids.meReview]
    if !app.buttons["review.back"].exists {
      XCTAssertTrue(app.openMePage(), "开不出「我的」", file: file, line: line)
      XCTAssertTrue(waitUntil(timeout: Self.long) { review.label.contains("笔 · 净盈亏") },
                    "本机没拼出上周的回合：\(review.label)", file: file, line: line)
    }
    guard app.openReviewBookFromMe() else { XCTFail("没开出复盘本", file: file, line: line); return false }
    let tradesTab = app.buttons["review.segment.交易"]
    if tradesTab.waitForExistence(timeout: Self.short) { tradesTab.tap() }
    let btc = app.buttons.matching(identifier: "review.trades.row.BTC")
    guard btc.firstMatch.waitForExistence(timeout: Self.long) else {
      XCTFail("交易段里没有 BTC", file: file, line: line); return false
    }
    // 两笔 BTC：「持仓中」那一笔在上、已平的那一笔在下面按天分的段里。
    if waitUntil(timeout: 3, { btc.count >= 2 }) {
      btc.element(boundBy: 1).tap()
      return detailBar.waitForExistence(timeout: Self.short)
    }
    // 最大字号下一屏只摆得下一两行：往下一屏屏找，打开之后有播放记号的就是已平的那一笔。
    for _ in 0..<6 {
      if btc.count > 0 {
        btc.element(boundBy: btc.count - 1).tap()
        if detailBar.waitForExistence(timeout: Self.short), disc.waitForExistence(timeout: 3) { return true }
        detailBar.buttons.firstMatch.tap()
        _ = btc.firstMatch.waitForExistence(timeout: Self.short)
      }
      app.swipeUp(velocity: .slow)
    }
    XCTFail("交易段里找不到那笔已平的 BTC", file: file, line: line); return false
  }

  private func startReplay(file: StaticString = #filePath, line: UInt = #line) -> [String: Int64]? {
    guard disc.waitForExistence(timeout: Self.short) else { XCTFail("没有播放记号", file: file, line: line); return nil }
    disc.tap()
    XCTAssertTrue(pauseButton.waitForExistence(timeout: Self.long), "点一下之后没自己播起来", file: file, line: line)
    guard waitUntil(timeout: Self.short, { self.report() != nil }) else {
      XCTFail("记号层没报交易回放那一行", file: file, line: line); return nil
    }
    return report()
  }

  // ------------------------------------------------------------ 1. 节奏与收尾

  func testPaceOpenPauseCapsuleAutoStopAndReturn() throws {
    XCTAssertTrue(openClosedBTC())
    let began = Date()
    let r = try XCTUnwrap(startReplay())
    let step = r["step"]!, open = r["open"]!, close = r["close"]!
    let bars = Int((close + 5 * step - (open - 20 * step)) / step)
    note("进入|\(title.label)|\(speedButton.label)|整趟 \(bars) 根|\(r)")
    // 这笔 1 小时 48 根：按 1× 整趟 50 多秒，倍速该自己挑到 2×（`ReplayPace`）。
    XCTAssertTrue(speedButton.label.contains("2"), "倍速没按这一趟的根数自己挑：\(speedButton.label)")

    // 一路记游标（每拍只问记号层那一行，便宜）；胶囊、「重播」每五拍问一次——它们要翻整棵树，
    // 每拍都问会把采样拖到一秒一拍，量不出开仓那一停。
    var trace: [(t: Double, last: Int64, pnl: String?)] = []
    var capsules = Set<String>()
    var openSeen: Double?, openLeft: Double?, lastOpenSample: Double?
    var sawOpenShot = false, sawHoldShot = false
    var tick = 0
    let deadline = Date().addingTimeInterval(90)
    while Date() < deadline {
      guard let now = report()?["last"] else { continue }
      let t = Date().timeIntervalSince(began)
      tick += 1
      let pnl = tick % 5 == 0 ? (try? capsule.snapshot())?.label : nil
      if let pnl { capsules.insert(pnl) }
      trace.append((t, now, pnl))
      if now == open {
        if openSeen == nil { openSeen = t }
        lastOpenSample = t
        if !sawOpenShot { sawOpenShot = true; shot("走查-开仓那一停") }
      } else if now > open, openSeen != nil, openLeft == nil {
        openLeft = t
      }
      if !sawHoldShot, now > open + (close - open) / 2 { sawHoldShot = true; shot("走查-持仓中") }
      if now >= close + 5 * step, tick % 5 == 0, replayButton.exists { break }
    }
    let total = Date().timeIntervalSince(began)
    let firstMove = trace.first(where: { $0.last > trace.first!.last })?.t ?? -1
    let gaps = zip(trace.dropFirst(), trace).map { $0.t - $1.t }
    let sample = gaps.isEmpty ? 0 : gaps.reduce(0, +) / Double(gaps.count)
    // 开仓那一停：看到的最早 → 最晚是下限，最早 → 第一次离开是上限，取中间。
    let hold: Double? = openSeen.flatMap { seen in
      openLeft.map { ((lastOpenSample ?? seen) - seen + $0 - seen) / 2 }
    }
    // 每一根停了多久（按离开仓那根几根记），给「停在哪一根」留证据。
    // 持仓段之外读数是四根一跳（2.1 秒）：那是 XCUITest 的快照缓存——探针只改 accessibilityValue、
    // 不发无障碍通知，快照要等别处（视野翻页）刷新才看得到；持仓段胶囊每根一变，所以逐根准。
    // 图与覆盖层本身每根都在重画（`ChartView` 把追加一根算作 `.input` 变化）。
    var dwell: [String] = []
    var i = 0
    while i < trace.count {
      var j = i
      while j + 1 < trace.count, trace[j + 1].last == trace[i].last { j += 1 }
      let leave = j + 1 < trace.count ? trace[j + 1].t : trace[j].t
      dwell.append("\((trace[i].last - open) / step):\(String(format: "%.2f", leave - trace[i].t))")
      i = j + 1
    }
    note("逐根|" + dwell.joined(separator: " "))
    note("节奏|整趟 \(String(format: "%.1f", total)) 秒|第一步 \(String(format: "%.2f", firstMove)) 秒|开仓停约 \(hold.map { String(format: "%.2f", $0) } ?? "-") 秒|采样 \(String(format: "%.2f", sample)) 秒一拍|胶囊 \(capsules.count) 种|末根 \(trace.last?.last ?? 0)")
    shot("走查-播完")
    XCTAssertTrue(replayButton.exists, "90 秒内没播完、没变「重播」")
    XCTAssertEqual(report()?["last"], close + 5 * step, "没停在平仓后第 5 根")
    XCTAssertGreaterThanOrEqual(total, 18, "整趟 \(total) 秒，太快看不清")
    XCTAssertLessThanOrEqual(total, 45, "整趟 \(total) 秒，太拖")
    // 2× 时一根 0.5 秒；开仓那根再停 1.2 秒，前后合起来 1.7 秒。
    if let hold { XCTAssertGreaterThan(hold, 1.0, "开仓那根没停下") }
    else { XCTFail("游标没在开仓那根停过") }
    XCTAssertGreaterThan(capsules.count, 3, "持仓那段浮盈胶囊没一根一变：\(capsules)")
    RunLoop.main.run(until: Date().addingTimeInterval(2))
    XCTAssertEqual(report()?["last"], close + 5 * step, "播完之后游标又动了")

    // 退出：回到这笔详情；没登录写不了，但仍滚到「当时怎么想」那一节。
    app.buttons["退出"].tap()
    XCTAssertTrue(detailBar.waitForExistence(timeout: Self.short), "退出没回到这笔详情")
    let section = app.staticTexts["当时怎么想"]
    XCTAssertTrue(waitUntil(timeout: Self.short) { section.exists && section.isHittable }, "退出后没滚到「当时怎么想」")
    RunLoop.main.run(until: Date().addingTimeInterval(0.6))
    shot("走查-退出回详情")
  }

  // ------------------------------------------------------------ 2. 打断

  func testPausedCursorHoldsThroughPushesBackgroundAndRotation() throws {
    XCTAssertTrue(openClosedBTC())
    let r = try XCTUnwrap(startReplay())
    let header = title.label
    // 走到开仓处、停下来。
    app.buttons["开仓处"].tap()
    pauseButton.tap()
    XCTAssertTrue(playButton.waitForExistence(timeout: Self.short), "暂停没停")
    let held = try XCTUnwrap(report()?["last"])
    XCTAssertGreaterThanOrEqual(held, r["open"]!)

    // 行情照常在推：停着 6 秒游标不许动。
    RunLoop.main.run(until: Date().addingTimeInterval(6))
    XCTAssertEqual(report()?["last"], held, "停着的时候游标被推送拨动了")

    // 退后台再回来：还是这一趟、还停在这根。
    XCUIDevice.shared.press(.home)
    RunLoop.main.run(until: Date().addingTimeInterval(2))
    app.activate()
    XCTAssertTrue(title.waitForExistence(timeout: Self.short), "从后台回来回放没了")
    XCTAssertEqual(title.label, header, "从后台回来标题变了")
    XCTAssertTrue(playButton.exists, "从后台回来不是暂停着")
    XCTAssertEqual(report()?["last"], held, "从后台回来游标被重置了")
    note("后台回来|\(title.label)|\(String(describing: report()))")

    // 横过来：还是这一趟；左边不许冒出能换周期的那条栏。
    XCUIDevice.shared.orientation = .landscapeLeft
    RunLoop.main.run(until: Date().addingTimeInterval(1.5))
    XCTAssertTrue(title.waitForExistence(timeout: Self.short), "横过来回放没了")
    XCTAssertEqual(report()?["last"], held, "横过来游标变了")
    shot("走查-横屏")
    // 横屏周期栏（`IntervalRail`）的钮没有 identifier，认它行尾那颗「更多周期」。
    let rail = app.buttons.matching(NSPredicate(format: "label == '更多周期' OR identifier BEGINSWITH 'interval.chip.'"))
    note("横屏|周期钮 \(rail.count) 个|\(String(describing: report()))")
    XCTAssertEqual(rail.count, 0, "回放横屏时还摆着周期栏，点了会在回放底下换掉行情的周期")
    playButton.tap()
    XCTAssertTrue(waitUntil(timeout: Self.short) { (self.report()?["last"] ?? 0) > held }, "横屏里播不动")
    pauseButton.tap()
    XCUIDevice.shared.orientation = .portrait
    RunLoop.main.run(until: Date().addingTimeInterval(1.5))
    XCTAssertTrue(title.waitForExistence(timeout: Self.short), "竖回来回放没了")
    XCTAssertEqual(title.label, header)

    // 退出之后行情页是好的：有顶栏、有周期条，图在最新。
    app.buttons["退出"].tap()
    XCTAssertTrue(detailBar.waitForExistence(timeout: Self.short), "退出没回到这笔详情")
    detailBar.buttons.firstMatch.tap()
    let back = app.buttons["review.back"]
    if back.waitForExistence(timeout: Self.short) { back.tap() }
    XCTAssertTrue(app.buttons[Ids.bottomChart].waitForExistence(timeout: Self.short))
    app.buttons[Ids.bottomChart].tap()
    XCTAssertTrue(app.symbolLabel.waitForExistence(timeout: Self.short), "退出后回不到行情页")
    XCTAssertFalse(title.exists, "行情页上还挂着回放标题")
    XCTAssertTrue(waitForLiveChart(), "退出后行情页没有活图")
  }

  // ------------------------------------------------------------ 3. 取不到 K 线

  func testHistoryUnavailableSaysOnceAndReturns() throws {
    XCTAssertTrue(openClosedBTC())
    XCTAssertTrue(disc.waitForExistence(timeout: Self.short))
    disc.tap()
    let toast = app.staticTexts.matching(NSPredicate(format: "label CONTAINS '取不到' OR label CONTAINS '无法获取' OR label CONTAINS '暂未接入' OR label CONTAINS '等待行情'"))
    XCTAssertTrue(toast.firstMatch.waitForExistence(timeout: Self.long), "取不到 K 线没说一句")
    note("吐司|\(toast.count)|\(toast.firstMatch.label)")
    XCTAssertEqual(toast.count, 1, "说了不止一句")
    XCTAssertTrue(detailBar.waitForExistence(timeout: Self.short), "没自己退回这笔详情")
    XCTAssertFalse(title.exists, "还留在回放的空图上")
    shot("走查-取不到K线")
  }

  // ------------------------------------------------------------ 4. 最大动态字号

  func testLargestTypeKeepsTitleAndCapsuleOnOneLine() throws {
    XCTAssertTrue(openClosedBTC())
    let r = try XCTUnwrap(startReplay())
    pauseButton.tap()
    app.buttons["开仓处"].tap()
    XCTAssertTrue(capsule.waitForExistence(timeout: Self.short), "持仓那段没有胶囊")
    RunLoop.main.run(until: Date().addingTimeInterval(0.8))
    let titleFrame = title.frame, capsuleFrame = capsule.frame
    note("AX|标题 \(titleFrame)|胶囊 \(capsuleFrame)|\(title.label)|\(capsule.label)|\(r)")
    shot("走查-最大字号")
    // 最大字号下标题一行约 40pt 高、胶囊一行约 36pt；折成两行会翻倍。
    XCTAssertLessThan(titleFrame.height, 60, "标题折行了：\(titleFrame)")
    XCTAssertLessThan(capsuleFrame.height, 56, "胶囊折行了：\(capsuleFrame)")
    XCTAssertLessThanOrEqual(titleFrame.maxX, app.windows.firstMatch.frame.maxX, "标题出了屏幕")
    XCTAssertLessThanOrEqual(capsuleFrame.maxX, app.windows.firstMatch.frame.maxX, "胶囊出了屏幕")
  }
}
