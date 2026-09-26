import XCTest

// ============================================================ 整机压测（2026-09-26）
//
// 以交易员的手速把行情页折腾一遍，然后看它**停下来之后**是不是一张自洽的图：
//
// - 品种扫图 200 下、切周期 200 下，交替着来，每下之间随机 0–100 ms；
// - 「更多」弹层、指标页、RSI 开关各开关 30 次；
// - 停手之后：图上那只 = 顶栏报价那只 = 盘口那只；周期 = 最后点的那一档；视野在最新一根；
//   顶栏最新价和图上末根收盘对得上；画在 BTC 上的线不跟着跑到别的品种上，回到 BTC 线不多不少。
//
// 卡顿（主线程晚过 100 ms）只报数、不断言——模拟器上的墙钟抖得厉害（见 `MainThreadHangLog`）。
// 这条要真行情（直连币安公开接口，只开这一台模拟器上的几只品种），拿不到行情就是断了。

@MainActor
final class WholeAppStressUITests: KanpanUICase {
  static let list = ["BTCUSDT", "ETHUSDT", "SOLUSDT", "BNBUSDT", "XRPUSDT", "DOGEUSDT"]

  override var extraLaunchEnvironment: [String: String] {
    ["KANPAN_TEST_FAVORITES": Self.list.joined(separator: ",")]
  }

  // ------------------------------------------------------------ 取证

  private func shot(_ name: String) {
    let screenshot = app.screenshot()
    let attachment = XCTAttachment(screenshot: screenshot)
    attachment.name = name; attachment.lifetime = .keepAlways; add(attachment)
    // 宿主侧取证目录（`TEST_RUNNER_KANPAN_STRESS_SHOTS=…` 传进来）；截图同时也挂在 xcresult 里。
    let path = ProcessInfo.processInfo.environment["KANPAN_STRESS_SHOTS"] ?? "/tmp/kanpan-stress-ui-shots"
    let dir = URL(fileURLWithPath: path, isDirectory: true)
    try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    try? screenshot.pngRepresentation.write(to: dir.appendingPathComponent(name + ".png"))
  }

  private func code(_ key: String) -> String { key.split(separator: "/").last.map(String.init) ?? key }
  private func symbolOnChart() -> String { code(chartInfo()["symbol"] as? String ?? "") }

  /// 顶栏价格区挂的诊断串：`symbol=…;last=…;time=…`。
  private func quote() -> [String: String] {
    let el = app.descendants(matching: .any).matching(identifier: "market.quote").firstMatch
    guard el.exists, let text = el.value as? String else { return [:] }
    var out: [String: String] = [:]
    for part in text.split(separator: ";") {
      let kv = part.split(separator: "=", maxSplits: 1)
      if kv.count == 2 { out[String(kv[0])] = String(kv[1]) }
    }
    return out
  }

  /// 主线程卡顿账（`main.hangs`：`count=N;recent=a,b,c`）。
  private func hangs() -> (count: Int, recent: [Int]) {
    let el = app.descendants(matching: .any).matching(identifier: "main.hangs").firstMatch
    guard el.exists, let text = el.value as? String else { return (0, []) }
    var count = 0, recent: [Int] = []
    for part in text.split(separator: ";") {
      let kv = part.split(separator: "=", maxSplits: 1)
      guard kv.count == 2 else { continue }
      if kv[0] == "count" { count = Int(kv[1]) ?? 0 }
      if kv[0] == "recent" { recent = kv[1].split(separator: ",").compactMap { Int($0) } }
    }
    return (count, recent)
  }

  private func report(_ name: String, since before: (count: Int, recent: [Int])) {
    let after = hangs()
    let n = after.count - before.count
    let these = Array(after.recent.suffix(min(n, after.recent.count)))
    let line = "STRESS \(name) hangs_over_100ms=\(n) worst_ms=\(these.max() ?? 0) samples=\(these)"
    print(line)
    let note = XCTAttachment(string: line); note.name = name; note.lifetime = .keepAlways; add(note)
  }

  // ------------------------------------------------------------ 动作

  private func swipePrice(next: Bool) {
    let quote = app.descendants(matching: .any).matching(identifier: "market.quote").firstMatch
    guard quote.exists else { return }
    let start = CGVector(dx: next ? 0.85 : 0.15, dy: 0.5)
    let end = CGVector(dx: next ? 0.1 : 0.9, dy: 0.5)
    quote.coordinate(withNormalizedOffset: start)
      .press(forDuration: 0.02, thenDragTo: quote.coordinate(withNormalizedOffset: end))
  }

  private func openFromFavorites(_ symbol: String) {
    XCTAssertTrue(app.openFavorites(), "进不了自选页")
    let row = app.buttons["favorites.open." + testInstrumentKey(symbol)]
    expectExists(row, Self.long, "自选页上没有 \(symbol) 这一行")
    row.tap()
    XCTAssertTrue(waitUntil(timeout: Self.long) { self.symbolOnChart() == symbol },
                  "点了 \(symbol) 没进它的图（现在是 \(symbolOnChart())）")
  }

  /// 在当前这只上画一条水平线，返回它的 id。
  private func drawOneHLine() -> String? {
    guard app.enterDrawingInPortrait() else { return nil }
    let chip = app.buttons["draw.hline"]
    guard chip.waitForExistence(timeout: Self.short) else { return nil }
    chip.tap()
    let canvas = app.otherElements["chart.canvas"]
    canvas.coordinate(withNormalizedOffset: CGVector(dx: 0.45, dy: 0.25)).tap()
    _ = waitUntil(timeout: Self.short) { (self.chartInfo()["drawingCount"] as? Int ?? 0) >= 1 }
    app.buttons[Ids.drawFinish].tap()
    _ = waitUntil(timeout: Self.short) { !self.app.buttons[Ids.drawFinish].exists }
    return (chartInfo()["drawingIDs"] as? [String])?.last
  }

  /// 每下之间随机 0–100 ms（种子固定，失败能原样重放）。
  private struct Jitter {
    var state: UInt64
    mutating func next() -> UInt64 {
      state = state &* 6364136223846793005 &+ 1442695040888963407
      return state >> 33
    }
    mutating func pause() { usleep(UInt32(next() % 101) * 1000) }
    mutating func bool() -> Bool { next() % 2 == 0 }
    mutating func pick<T>(_ a: [T]) -> T { a[Int(next() % UInt64(a.count))] }
  }

  // ------------------------------------------------------------ 用例

  func testRapidSwitchStormSettlesOnLastChoice() throws {
    openFromFavorites("BTCUSDT")
    XCTAssertTrue(waitForLiveChart(), "\(Self.long)s 内没等到 BTC 的 K 线")
    // 画线存档不跟着测试档案清（上一轮留下的线还在），所以按「画之前那几条 + 这一条」对账。
    let prior = chartInfo()["drawingIDs"] as? [String] ?? []
    let seed = try XCTUnwrap(drawOneHLine(), "BTC 上没画出那条水平线")
    let btcLines = prior + [seed]
    XCTAssertEqual(chartInfo()["drawingIDs"] as? [String], btcLines)

    var jitter = Jitter(state: 20260926)
    var index = 0
    var lastInterval = chartInfo()["interval"] as? String ?? "15m"
    let before = hangs()
    for step in 0..<400 {
      if step.isMultiple(of: 2) {
        let next = index == 0 ? true : (index == Self.list.count - 1 ? false : jitter.bool())
        swipePrice(next: next)
        index = max(0, min(Self.list.count - 1, index + (next ? 1 : -1)))
      } else {
        lastInterval = jitter.pick(Ids.quickIntervals)
        app.tapIntervalChip(lastInterval)
      }
      jitter.pause()
    }
    report("switch_storm_400", since: before)

    let panelsBefore = hangs()
    for _ in 0..<30 {
      app.buttons[Ids.intervalMore].tap(); jitter.pause()
      app.buttons[Ids.intervalMore].tap(); jitter.pause()
      let entry = app.buttons[Ids.intervalIndicators]
      if entry.waitForExistence(timeout: Self.short) { entry.tap() }
      let rsi = app.buttons[Ids.indicatorSwitch("RSI")]
      if rsi.waitForExistence(timeout: Self.short) { rsi.tap(); jitter.pause(); rsi.tap() }
      let done = app.buttons[Ids.panelDone]
      if done.waitForExistence(timeout: Self.short) { done.tap() }
      _ = waitUntil(timeout: Self.short) { !rsi.exists }
      jitter.pause()
    }
    report("panel_toggle_30", since: panelsBefore)

    // 停手之后：一张自洽的图。
    XCTAssertTrue(waitUntil(timeout: Self.long) {
      let info = self.chartInfo(), q = self.quote()
      let sym = self.code(info["symbol"] as? String ?? "")
      return !sym.isEmpty && (info["bars"] as? Int ?? 0) > 0 && info["interval"] as? String == lastInterval
        && self.code(q["symbol"] ?? "") == sym
    }, "停手后图、顶栏、周期对不上：chart=\(symbolOnChart()) interval=\(chartInfo()["interval"] ?? "") " +
       "want=\(lastInterval) quote=\(quote())")
    let settled = symbolOnChart()
    shot("stress-01-连切停手后-\(settled)-\(lastInterval)")

    // 盘口与报价跟着这一只；顶栏最新价与末根收盘对得上（旧品种的价没残留在顶栏）。
    XCTAssertTrue(waitUntil(timeout: Self.long) {
      let info = self.chartInfo(), q = self.quote()
      let depth = self.code(info["depthSymbol"] as? String ?? "")
      guard depth.isEmpty || depth == settled else { return false }
      guard let last = Double(q["last"] ?? ""), last.isFinite, let close = info["lastClose"] as? Double, close > 0
      else { return false }
      return abs(last - close) / close < 0.005
    }, "顶栏报价 / 盘口没跟上 \(settled)：quote=\(quote()) lastClose=\(chartInfo()["lastClose"] ?? "") " +
       "depth=\(chartInfo()["depthSymbol"] ?? "")")

    // 视野落在最新一根：切品种 / 周期的旧视野没盖到新图上。
    let gap = chartInfo()["latestRightGap"] as? Double ?? -1
    let plotW = chartInfo()["plotW"] as? Double ?? 0
    XCTAssertTrue(gap >= -1 && gap < plotW / 2, "停手后视野不在最新一根：latestRightGap=\(gap) plotW=\(plotW)")

    // 画线只属于 BTC：停在别的品种上时图上不能有那条线；回到 BTC 恰好一条。
    let ids = chartInfo()["drawingIDs"] as? [String] ?? []
    if settled != "BTCUSDT" {
      XCTAssertTrue(Set(ids).isDisjoint(with: btcLines), "BTC 的线漏到了 \(settled) 上：\(ids)")
      openFromFavorites("BTCUSDT")
    }
    XCTAssertTrue(waitUntil(timeout: Self.long) { (self.chartInfo()["drawingIDs"] as? [String]) == btcLines },
                  "回到 BTC 线不是恰好原来那几条：want=\(btcLines) got=\(chartInfo()["drawingIDs"] ?? "")")
    shot("stress-02-回到BTC-线还在")
  }

  /// 对照组：只做连切 / 开关面板那两段每一步都会做的查询（按钮在不在、顶栏诊断串、图表诊断串），
  /// 一下都不点。XCUITest 每查一次都要 app 在**主线程**上现造一份无障碍树，这份开销会原样记进
  /// `main.hangs`——两段的卡顿数要减掉这一份，剩下的才是 app 自己切换的成本。
  func testAccessibilityQueryBaseline() throws {
    openFromFavorites("BTCUSDT")
    XCTAssertTrue(waitForLiveChart(), "\(Self.long)s 内没等到 BTC 的 K 线")
    var jitter = Jitter(state: 20260926)
    let chart = hangs()
    for _ in 0..<100 {
      _ = app.buttons[Ids.intervalMore].exists
      _ = quote(); _ = chartInfo()
      jitter.pause()
    }
    report("ax_query_chart_100", since: chart)

    app.buttons[Ids.intervalMore].tap()
    let entry = app.buttons[Ids.intervalIndicators]
    XCTAssertTrue(entry.waitForExistence(timeout: Self.short))
    entry.tap()
    let rsi = app.buttons[Ids.indicatorSwitch("RSI")]
    XCTAssertTrue(rsi.waitForExistence(timeout: Self.short))
    let panel = hangs()
    for _ in 0..<30 {
      _ = rsi.exists; _ = app.buttons[Ids.panelDone].exists; _ = app.buttons[Ids.intervalMore].exists
      jitter.pause()
    }
    report("ax_query_panel_30", since: panel)
    app.buttons[Ids.panelDone].tap()
  }

  /// 前后台来回 100 次、通知中心下拉 20 次（`.inactive` 来回）之后，图还是活的：
  /// 同一只、同一档、顶栏那口价还在往前走，没有停在进后台之前那一口。
  /// 宿主侧在跑这一条的同时用 `simctl` 发内存警告、采 RSS（见报告），这里只看 app 自己。
  func testLifecycleChurnKeepsChartLive() throws {
    openFromFavorites("ETHUSDT")
    XCTAssertTrue(waitForLiveChart(), "\(Self.long)s 内没等到 ETH 的 K 线")
    let interval = chartInfo()["interval"] as? String ?? ""
    var jitter = Jitter(state: 926)
    let before = hangs()
    for _ in 0..<100 {
      XCUIDevice.shared.press(.home)
      jitter.pause()
      app.activate()
      _ = app.wait(for: .runningForeground, timeout: Self.short)
      jitter.pause()
    }
    report("home_activate_100", since: before)
    XCTAssertEqual(app.state, .runningForeground)
    shot("stress-03-前后台100次后")

    let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
    let inactiveBefore = hangs()
    for _ in 0..<20 {
      let top = springboard.coordinate(withNormalizedOffset: CGVector(dx: 0.3, dy: 0.002))
      top.press(forDuration: 0.05, thenDragTo: springboard.coordinate(withNormalizedOffset: CGVector(dx: 0.3, dy: 0.6)))
      jitter.pause()
      let bottom = springboard.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.995))
      bottom.press(forDuration: 0.05, thenDragTo: springboard.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.3)))
      if app.state != .runningForeground { app.activate() }
      _ = app.wait(for: .runningForeground, timeout: Self.short)
      jitter.pause()
    }
    report("notification_center_20", since: inactiveBefore)

    // 停手之后：还是 ETH、还是那一档、有 K 线，顶栏那口价的时间还在往前走。
    XCTAssertTrue(waitUntil(timeout: Self.long) {
      let info = self.chartInfo()
      return self.code(info["symbol"] as? String ?? "") == "ETHUSDT" && info["interval"] as? String == interval
        && (info["bars"] as? Int ?? 0) > 0
    }, "来回之后图变了：\(chartInfo())")
    let t0 = Int64(quote()["time"] ?? "") ?? 0
    XCTAssertTrue(waitUntil(timeout: Self.long) { (Int64(self.quote()["time"] ?? "") ?? 0) > t0 },
                  "来回之后顶栏那口价停住了：\(quote())")
    XCTAssertFalse(app.staticTexts["行情实时"].exists, "界面上冒出了工程状态字段")
    shot("stress-04-通知中心20次后-仍在跳")
  }
}
