import XCTest

// ============================================================ 自动复盘 3d · 交易回放
//
// 交易所那一侧照 3c 用 DEBUG 包里的假提供者（`KANPAN_EXCHANGE_FIXTURE=1` + 只读 Key 开机自动接入），
// 成交按「上周一」起算、价格取真实 K 线开盘价；K 线是交易所真历史。不登录：回放只要回合与 K 线。
//
// 1. 主路：我的 › 复盘本 › 交易 → 已平的 BTC → 点图上那颗播放 → 切到图表页、回放条出来、
//    自己在播、有「开仓处」和进度线 → 「开仓处」跳到开仓那根、浮盈胶囊出来 → 退出回到这笔详情；
//    持仓中那一笔没有播放记号，点图也不走。
// 2. 拖进度线：暂停着拖到平仓刻度附近 → 游标到了平仓那根（成交全画出来）、松手仍是暂停、
//    游标不再动 → 播放接着走 → 拖到底变「重播」→ 重播从头播。
// 3. 三套皮肤 × 进入 / 持仓中 / 结束 截图。
//
// 画布上的三角、虚线 XCUITest 看不见，靠记号层在 `KANPAN_CHART_DIAGNOSTICS=1` 下报的一行
// （`ReviewRangeOverlay.reportTrade`）：「画了几枚/共几枚 trade last=… open=… close=… step=…」。
//
// 截图落在 docs/acceptance/自动复盘-2026-09-27/<机型>-交易回放-<进入|持仓中|结束>-<皮肤>.png。
@MainActor
final class TradeReplayUITests: KanpanUICase {
  private let profile = UUID().uuidString

  override var extraLaunchEnvironment: [String: String] {
    ["KANPAN_PERSISTENCE_PROFILE": profile, "KANPAN_EXCHANGE_FIXTURE": "1",
     "KANPAN_EXCHANGE_FIXTURE_KEY": "DEMOREADONLY7C31"]
  }

  override func setUp() async throws {
    XCUIDevice.shared.orientation = .portrait
    try await super.setUp()
  }

  private static let outDir = URL(
    fileURLWithPath: "/Users/mdd/zhk/kanpan/docs/acceptance/自动复盘-2026-09-27", isDirectory: true)

  private var deviceTag: String {
    switch Int(app.windows.firstMatch.frame.width.rounded()) {
    case 402: "iPhone16Pro"
    case 440: "iPhone17ProMax"
    case 430: "iPhone15ProMax"
    case let w: "宽\(w)"
    }
  }

  private func note(_ line: String) {
    print("取证|" + line)
    let a = XCTAttachment(string: line); a.name = "取证"; a.lifetime = .keepAlways; add(a)
  }

  private func shot(_ page: String, _ skin: String) {
    let screenshot = XCUIScreen.main.screenshot()
    let name = "\(deviceTag)-交易回放-\(page)-\(skin)"
    let a = XCTAttachment(screenshot: screenshot); a.name = name; a.lifetime = .keepAlways; add(a)
    try? FileManager.default.createDirectory(at: Self.outDir, withIntermediateDirectories: true)
    do { try screenshot.pngRepresentation.write(to: Self.outDir.appendingPathComponent(name + ".png")) }
    catch { note("落盘失败|\(name)|\(error)") }
  }

  // ------------------------------------------------------------ 元素

  private var disc: XCUIElement { app.buttons["trade.detail.replay"] }
  private var title: XCUIElement { app.descendants(matching: .any)["review.replay.title"] }
  private var progress: XCUIElement { app.descendants(matching: .any)["review.replay.progress"] }
  private var capsule: XCUIElement { app.descendants(matching: .any)["review.replay.pnl"] }
  private var detailBar: XCUIElement { app.navigationBars["交易详情"] }
  private var pauseButton: XCUIElement { app.buttons["暂停"] }
  private var playButton: XCUIElement { app.buttons["播放"] }
  private var replayButton: XCUIElement { app.buttons["重播"] }

  /// 记号层这一帧报的交易回放诊断：shown / total / last / open / close / step。
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

  /// 进度线上第 `time` 根所在的比例（线从开仓前 20 根到平仓后 5 根，一格一根）。
  private func fraction(at time: Int64, _ r: [String: Int64]) -> CGFloat {
    let step = r["step"]!, lower = r["open"]! - 20 * step, upper = r["close"]! + 5 * step
    return CGFloat(Double(time - lower) / Double(upper - lower))
  }

  /// 在进度线上按住，从 `from` 拖到 `to`（0…1），松手。
  private func drag(from: CGFloat, to: CGFloat) {
    let a = progress.coordinate(withNormalizedOffset: CGVector(dx: min(max(from, 0.01), 0.99), dy: 0.5))
    let b = progress.coordinate(withNormalizedOffset: CGVector(dx: min(max(to, 0), 1), dy: 0.5))
    a.press(forDuration: 0.15, thenDragTo: b)
  }

  // ------------------------------------------------------------ 路径

  private func applySkin(_ skin: String) {
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
  }

  /// 我的 › 复盘本 › 交易 → 第 `index` 行 BTC（0 = 持仓中那笔，1 = 已平那笔）→ 交易详情。
  private func openBTCTrade(_ index: Int, file: StaticString = #filePath, line: UInt = #line) -> Bool {
    let review = app.buttons[Ids.meReview]
    if !app.buttons["review.back"].exists {
      XCTAssertTrue(app.openMePage(), "开不出「我的」", file: file, line: line)
      XCTAssertTrue(waitUntil(timeout: Self.long) { review.label.contains("笔 · 净盈亏") },
                    "本机没拼出上周的回合：\(review.label)", file: file, line: line)
    }
    guard app.openReviewBookFromMe() else { XCTFail("「我的 › 复盘本」没开出复盘本", file: file, line: line); return false }
    let tradesTab = app.buttons["review.segment.交易"]
    if tradesTab.waitForExistence(timeout: Self.short) { tradesTab.tap() }
    let btc = app.buttons.matching(identifier: "review.trades.row.BTC")
    guard waitUntil(timeout: Self.long, { btc.count >= 2 }) else {
      XCTFail("交易段里 BTC 不是一笔持仓中、一笔已平（\(btc.count)）", file: file, line: line); return false
    }
    btc.element(boundBy: index).tap()
    guard detailBar.waitForExistence(timeout: Self.short) else { XCTFail("没进交易详情", file: file, line: line); return false }
    return true
  }

  /// 从交易详情点播放记号，等回放真的起来（有 K 线、在播）。
  private func startReplay(file: StaticString = #filePath, line: UInt = #line) -> [String: Int64]? {
    guard disc.waitForExistence(timeout: Self.short) else { XCTFail("已平那笔的图上没有播放记号", file: file, line: line); return nil }
    XCTAssertEqual(disc.label, "回放这笔交易", file: file, line: line)
    disc.tap()
    XCTAssertTrue(waitUntil(timeout: Self.short) { self.title.exists && self.title.label.hasPrefix("回放 · ") },
                  "点了播放没切到图表页的回放（标题：\(title.exists ? title.label : "无")）", file: file, line: line)
    XCTAssertFalse(detailBar.exists, "复盘本还压在图上", file: file, line: line)
    XCTAssertTrue(pauseButton.waitForExistence(timeout: Self.long), "K 线到了也没自己播起来", file: file, line: line)
    guard waitUntil(timeout: Self.short, { self.report() != nil }) else {
      XCTFail("记号层没报交易回放那一行", file: file, line: line); return nil
    }
    return report()
  }

  private func exitToDetail(file: StaticString = #filePath, line: UInt = #line) {
    app.buttons["退出"].tap()
    XCTAssertTrue(detailBar.waitForExistence(timeout: Self.short), "退出没回到这笔的交易详情", file: file, line: line)
    XCTAssertFalse(title.exists, "退出了回放标题还在", file: file, line: line)
  }

  private func closeBook() {
    for _ in 0..<3 where detailBar.exists {
      detailBar.buttons.firstMatch.tap()
      _ = waitUntil(timeout: 3) { !self.detailBar.exists }
    }
    let back = app.buttons["review.back"]
    if back.waitForExistence(timeout: Self.short) { back.tap() }
    _ = waitUntil(timeout: Self.short) { !back.exists }
  }

  // ------------------------------------------------------------ 1. 主路

  func testReplayAClosedTradeFromItsDetailAndReturn() throws {
    // 持仓中那一笔：没有播放记号，点图也不走。
    XCTAssertTrue(openBTCTrade(0))
    XCTAssertTrue(app.descendants(matching: .any)["trade.detail.chart"].waitForExistence(timeout: Self.short), "详情没有图")
    RunLoop.main.run(until: Date().addingTimeInterval(1.5))
    XCTAssertFalse(disc.exists, "持仓中那一笔不该有播放记号")
    app.descendants(matching: .any)["trade.detail.chart"].tap()
    RunLoop.main.run(until: Date().addingTimeInterval(1))
    XCTAssertTrue(detailBar.exists && !title.exists, "持仓中那一笔点图不该进回放")
    detailBar.buttons.firstMatch.tap()

    // 已平那一笔：一下就播。
    XCTAssertTrue(openBTCTrade(1))
    let r = try XCTUnwrap(startReplay())
    note("进入|\(title.label)|\(r)")
    XCTAssertTrue(title.label.contains("BTC"), "标题里没有品种：\(title.label)")
    XCTAssertTrue(app.otherElements["chart.canvas"].exists, "不在图表页")
    XCTAssertTrue(app.buttons["开仓处"].exists, "回放条上没有「开仓处」")
    XCTAssertTrue(progress.exists, "回放条上没有进度线")
    XCTAssertEqual(progress.label, "回放进度")
    XCTAssertFalse(app.buttons["前一根"].exists || app.buttons["后一根"].exists, "前一根 / 后一根该去掉了")
    XCTAssertLessThan(r["last"]!, r["open"]!, "一进来游标该在开仓之前")
    XCTAssertEqual(r["shown"], 0, "开仓之前不该画出成交")

    // 「开仓处」：跳到开仓那根，持仓浮盈胶囊出来。
    app.buttons["开仓处"].tap()
    XCTAssertTrue(waitUntil(timeout: Self.short) { (self.report()?["last"] ?? 0) >= r["open"]! },
                  "点「开仓处」游标没到开仓那根：\(String(describing: report()))")
    XCTAssertTrue(capsule.waitForExistence(timeout: Self.short), "持仓中没有浮盈胶囊")
    XCTAssertTrue(capsule.label.hasPrefix("持仓浮盈 "), "胶囊的读屏文案不对：\(capsule.label)")
    XCTAssertGreaterThan(report()?["shown"] ?? 0, 0, "到了开仓那根还没画出成交三角")
    note("开仓处|\(capsule.label)|\(String(describing: report()))")

    // 倍速按一下换档。
    let speed = app.buttons.matching(NSPredicate(format: "label BEGINSWITH '倍速'")).firstMatch
    XCTAssertTrue(speed.exists, "回放条上没有倍速")
    let before = speed.label
    speed.tap()
    XCTAssertTrue(waitUntil(timeout: Self.short) { speed.label != before }, "倍速没换档：\(before)")

    // 退出：回到这一笔的详情（不是复盘本首页、不是行情页）。
    exitToDetail()
    XCTAssertTrue(app.staticTexts["当时怎么想"].waitForExistence(timeout: Self.short), "详情里没有「当时怎么想」")
  }

  // ------------------------------------------------------------ 2. 拖进度线

  func testDraggingTheProgressLinePastTheCloseTickKeepsPlayState() throws {
    XCTAssertTrue(openBTCTrade(1))
    let r = try XCTUnwrap(startReplay())
    let step = r["step"]!, close = r["close"]!, total = r["total"]!

    // 先停下来：松手之后应该还是停着。
    pauseButton.tap()
    XCTAssertTrue(playButton.waitForExistence(timeout: Self.short), "按了暂停没停")

    // 拖到平仓刻度右边一根半的地方（「平仓刻度附近」，手指的精度差一根也不会落到平仓之前）。
    let target = fraction(at: close + step + step / 2, r)
    drag(from: 0.2, to: target)
    XCTAssertTrue(waitUntil(timeout: Self.short) { (self.report()?["last"] ?? 0) >= close },
                  "拖到平仓刻度附近，游标没到平仓那根：\(String(describing: report()))")
    let settled = try XCTUnwrap(report())
    XCTAssertEqual(settled["shown"], total, "过了平仓，成交没全画出来：\(settled)")
    XCTAssertTrue(playButton.exists, "松手之后该保持暂停")
    XCTAssertFalse(capsule.exists, "平仓之后不该再有持仓浮盈")
    RunLoop.main.run(until: Date().addingTimeInterval(2.5))
    XCTAssertEqual(report()?["last"], settled["last"], "停着的时候游标自己走了")
    note("拖到平仓|\(settled)|\(progress.value as? String ?? "")")

    // 接着播：往前走。
    playButton.tap()
    XCTAssertTrue(waitUntil(timeout: Self.short) {
      (self.report()?["last"] ?? 0) > settled["last"]! || self.replayButton.exists
    }, "按了播放游标没往前走")

    // 拖到底：到头了，按钮变「重播」。
    drag(from: 0.5, to: 1)
    XCTAssertTrue(replayButton.waitForExistence(timeout: Self.short), "拖到底按钮没变「重播」")
    XCTAssertEqual(report()?["last"], close + 5 * step, "拖到底游标没停在平仓后第 5 根：\(String(describing: report()))")

    // 重播：从头来、在播。
    replayButton.tap()
    XCTAssertTrue(pauseButton.waitForExistence(timeout: Self.short), "重播没播起来")
    XCTAssertTrue(waitUntil(timeout: Self.short) { (self.report()?["last"] ?? .max) < r["open"]! },
                  "重播没回到开仓之前：\(String(describing: report()))")

    exitToDetail()
  }

  // ------------------------------------------------------------ 3. 三套皮肤截图

  func testReplayScreensInThreeSkins() throws {
    for (skin, name) in [("sage", "青苔"), ("terra", "陶土"), ("classic", "经典")] {
      applySkin(skin)
      XCTAssertTrue(openBTCTrade(1), "\(name)：没进已平那笔")
      let r = try XCTUnwrap(startReplay(), "\(name)：回放没起来")
      RunLoop.main.run(until: Date().addingTimeInterval(0.6))
      shot("进入", name)

      // 持仓中：停下来拖到开仓与平仓两根中间。
      pauseButton.tap()
      XCTAssertTrue(playButton.waitForExistence(timeout: Self.short))
      let mid = (fraction(at: r["open"]!, r) + fraction(at: r["close"]!, r)) / 2
      drag(from: 0.1, to: mid)
      XCTAssertTrue(capsule.waitForExistence(timeout: Self.short), "\(name)：持仓中没有浮盈胶囊：\(String(describing: report()))")
      RunLoop.main.run(until: Date().addingTimeInterval(0.8))
      note("\(name)|持仓中|\(capsule.label)|\(String(describing: report()))")
      shot("持仓中", name)

      // 结束：拖到底。
      drag(from: mid, to: 1)
      XCTAssertTrue(replayButton.waitForExistence(timeout: Self.short), "\(name)：拖到底没变「重播」")
      RunLoop.main.run(until: Date().addingTimeInterval(0.8))
      shot("结束", name)

      exitToDetail()
      closeBook()
    }
  }
}
