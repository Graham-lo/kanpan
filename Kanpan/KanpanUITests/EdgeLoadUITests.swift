import XCTest

// ============================================================ 边界规模压测（2026-10-04 深度审查 F 线）
//
// 09-28 那一轮压的是「中等规模」（200 自选、50 提醒、100 画线）。这里补几头的极端：
//
// 1. 一只自选都没有：自选页空态、顶栏横滑扫图（没有下一只可扫）、底栏四格来回，app 不挂、不卡。
// 2. 提醒顶满上限（`AlertArchive.limit` = 200 条，其中 50 条条件提醒）+ 十只品种各 50 条线
//    （`DrawArchive.perSymbolLimit`，共 500 条）：冷启动时长、BTC 1m 实时跳一分钟（提醒引擎
//    每笔报价按品种查表）、十只连切每只都恰好 50 条线、总表翻到底。
// 3. 重连风暴：同一份满载（200 提醒、500 线）+ BTC 1m + 对比 ETH / SOL + 主力订单流（三家簿）
//    全开着时断网 20 秒（DEBUG 包的 `KANPAN_TEST_NET_OUTAGE`，只断这个 app 的出口），
//    网回来以后报价、K 线、对比、订单流都要自己回来，期间主线程不许有 ≥ 1 秒的卡死。
//
// 只判数量（线数、提醒条数、根数、对比条数、阶段）与「没有 ≥ 1 秒的卡死」；毫秒数只记进附件。
@MainActor
final class EdgeLoadUITests: KanpanUICase {
  private let profile = UUID().uuidString
  static let tenSymbols = ["BTCUSDT", "ETHUSDT", "SOLUSDT", "XRPUSDT", "DOGEUSDT",
                           "BNBUSDT", "ADAUSDT", "LINKUSDT", "AVAXUSDT", "LTCUSDT"]

  override var extraLaunchEnvironment: [String: String] {
    var env = ["KANPAN_PERSISTENCE_PROFILE": profile, "KANPAN_TEST_ROUTE_POLICY": "direct"]
    if name.contains("testEmptyFavorites") { env["KANPAN_TEST_FAVORITES"] = "" }
    else { env["KANPAN_TEST_FAVORITES"] = Self.tenSymbols.joined(separator: ",") }
    if name.contains("testReconnectStorm") {
      env["KANPAN_TEST_DEEPLINK"] = "hkline://symbol/BTCUSDT?interval=1m"
      env["KANPAN_TEST_COMPARE_SYMBOLS"] = "binance/usd_m/ETHUSDT,binance/usd_m/SOLUSDT"
    }
    return env
  }

  override func tearDown() async throws {
    if let app, app.state != .notRunning, app.state != .unknown { app.terminate() }
    try await super.tearDown()
  }

  // ------------------------------------------------------------ 取证

  private var testName: String {
    name.components(separatedBy: " ").last?.trimmingCharacters(in: CharacterSet(charactersIn: "]")) ?? name
  }

  private func note(_ line: String) {
    let text = "\(testName)|\(line)"
    print("边界压测|" + text)
    let a = XCTAttachment(string: text); a.name = "边界压测"; a.lifetime = .keepAlways; add(a)
  }

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

  /// 这一段的卡顿记进附件；≥ 1 秒的卡死直接判红。
  private func checkHangs(_ label: String, since before: (count: Int, recent: [Int]),
                          file: StaticString = #filePath, line: UInt = #line) {
    let after = hangs()
    let n = max(0, after.count - before.count)
    let these = Array(after.recent.suffix(min(n, after.recent.count)))
    note("\(label) 卡顿>100ms=\(n) 最坏=\(these.max() ?? 0)ms >250ms=\(these.filter { $0 > 250 })")
    XCTAssertTrue(these.allSatisfy { $0 < 1000 }, "\(label)：主线程卡死 ≥ 1 秒：\(these)", file: file, line: line)
  }

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
  private func quoteTime() -> Double { Double(quote()["time"] ?? "") ?? 0 }
  private func dwell(_ s: TimeInterval) { RunLoop.main.run(until: Date().addingTimeInterval(s)) }
  private var canvas: XCUIElement { app.otherElements["chart.canvas"] }
  private var alertsPage: XCUIElement { app.descendants(matching: .any).matching(identifier: "alerts.page").firstMatch }

  private func open(_ symbol: String, file: StaticString = #filePath, line: UInt = #line) {
    XCTAssertTrue(app.openSymbolSearch(), "顶栏放大镜没开出搜索页", file: file, line: line)
    let query = app.textFields[Ids.searchQuery]
    query.tap(); query.typeText(symbol)
    let hit = app.descendants(matching: .any).matching(identifier: "symbols.row." + testInstrumentKey(symbol)).firstMatch
    XCTAssertTrue(hit.waitForExistence(timeout: Self.long), "搜 \(symbol) 没出那一行", file: file, line: line)
    hit.tap()
    XCTAssertTrue(waitUntil(timeout: 45) { self.chartInfo()["symbol"] as? String == testInstrumentKey(symbol) },
                  "点了 \(symbol) 图上没换过去", file: file, line: line)
  }

  private func swipePrice(next: Bool) {
    let quote = app.descendants(matching: .any).matching(identifier: "market.quote").firstMatch
    guard quote.exists else { return }
    quote.coordinate(withNormalizedOffset: CGVector(dx: next ? 0.85 : 0.15, dy: 0.5))
      .press(forDuration: 0.02, thenDragTo: quote.coordinate(withNormalizedOffset: CGVector(dx: next ? 0.1 : 0.9, dy: 0.5)))
  }

  private func back() {
    let bar = app.navigationBars.buttons.firstMatch
    if bar.exists { bar.tap() }
  }

  // ------------------------------------------------------------ 造数据

  private func appDataContainer() -> URL? {
    let apps = URL(fileURLWithPath: NSHomeDirectory()).deletingLastPathComponent()
    let fm = FileManager.default
    guard let dirs = try? fm.contentsOfDirectory(at: apps, includingPropertiesForKeys: [.contentModificationDateKey]) else { return nil }
    var best: (URL, Date)?
    for d in dirs {
      let meta = d.appendingPathComponent(".com.apple.mobile_container_manager.metadata.plist")
      guard let data = try? Data(contentsOf: meta),
            let plist = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any],
            plist["MCMMetadataIdentifier"] as? String == "com.yj27y32.hkline" else { continue }
      let date = (try? d.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
      if best == nil || date > best!.1 { best = (d, date) }
    }
    return best?.0
  }

  /// 200 条提醒（150 条价格提醒散在 50 只品种上、50 条条件提醒）+ 十只品种各 50 条线。
  /// 价格提醒的价位都远离现价（0.0001 起），一分钟里不会真触发，留在表里一直被评估。
  private func seedFullHouse() throws {
    let container = try XCTUnwrap(appDataContainer(), "找不到 app 的数据容器")
    // 这套不给 `KANPAN_ACCOUNT_API_URL`（不碰线上账号服务），app 走「没有账号桥」那条岔路
    // （`MainScreen.wireAccount`）：提醒与画线各落在自己的测试沙盒
    // `kanpan-alert-tests/<profile>`、`kanpan-drawing-tests/<profile>`，不在 `accounts/tests` 下。
    let support = container.appendingPathComponent("Library/Application Support", isDirectory: true)
    let alertDir = support.appendingPathComponent("kanpan-alert-tests/\(profile)", isDirectory: true)
    let drawDir = support.appendingPathComponent("kanpan-drawing-tests/\(profile)", isDirectory: true)
    try FileManager.default.createDirectory(at: alertDir, withIntermediateDirectories: true)
    try FileManager.default.createDirectory(at: drawDir, withIntermediateDirectories: true)
    let now = Date().timeIntervalSince1970 * 1000
    let fifty = Array(StressRegression0928UITests.top200.prefix(50))
    var alerts: [[String: Any]] = []
    for i in 0..<150 {
      let s = fifty[i % fifty.count]
      let p = 0.0001 * Double(i + 1)
      alerts.append(["id": "a" + UUID().uuidString, "kind": "price", "symbol": s, "market": "binance/usd_m",
                     "lines": [["extendLeft": true, "extendRight": true, "points": [["p": p, "t": now]]]],
                     "condition": "touch", "status": "active", "armedAt": now, "once": true,
                     "title": "\(s) 跌到 \(p)", "created": now - Double(i) * 60_000,
                     "webhook": NSNull(), "webhookText": NSNull(), "note": NSNull(), "rule": NSNull(),
                     "drawingID": NSNull(), "dueAt": NSNull(), "firedAt": NSNull(), "firedPrice": NSNull(), "reviewID": NSNull()])
    }
    let rules: [[String: Any]] = [
      ["type": "funding", "side": "above", "rate": "0.5"],
      ["type": "openInterestChange", "threshold": "0.9"],
      ["type": "orderflowWall", "threshold": "1000000000000"],
      ["type": "funding", "side": "below", "rate": "-0.5"],
    ]
    for i in 0..<50 {
      let s = fifty[i]
      alerts.append(["id": "a" + UUID().uuidString, "kind": "condition", "symbol": s, "market": "binance/usd_m",
                     "lines": [], "condition": "touch", "status": "active", "armedAt": now, "once": true,
                     "title": "\(s) 条件 \(i)", "created": now - Double(i) * 30_000, "rule": rules[i % rules.count],
                     "webhook": NSNull(), "webhookText": NSNull(), "note": NSNull(), "drawingID": NSNull(), "dueAt": NSNull(),
                     "firedAt": NSNull(), "firedPrice": NSNull(), "reviewID": NSNull()])
    }
    try JSONSerialization.data(withJSONObject: ["a": alerts, "v": 1]).write(to: alertDir.appendingPathComponent("alerts.json"))

    // 每只 50 条：趋势线、水平线、矩形轮着来，落在最近 200 小时里（1h 上看得见，1m 上大多在视野外——
    // 视野外的线照样要过一遍可见性裁剪，这正是要压的）。
    let kinds = ["trend", "hline", "rectangle"]
    var perSymbol: [String: Any] = [:]
    for (j, s) in Self.tenSymbols.enumerated() {
      perSymbol["binance/usd_m/\(s)"] = (0..<50).map { k -> [String: Any] in
        let kind = kinds[(k + j) % kinds.count]
        let t0 = now - Double(200 - k * 3) * 3_600_000
        let base = 1.0 + Double(k) * 0.01
        let pts: [[String: Any]] = kind == "hline" ? [["t": t0, "p": base]]
          : [["t": t0, "p": base], ["t": t0 + 20 * 3_600_000, "p": base * 1.5]]
        return ["id": "d" + UUID().uuidString, "kind": kind, "points": pts, "dash": "solid", "locked": false,
                "hidden": false, "lineWidth": 1.3, "filled": true, "levels": [0, 0.236, 0.382, 0.5, 0.618, 0.786, 1]]
      }
    }
    let draws: [String: Any] = [
      "v": 3,
      "preferences": ["magnet": true, "favorites": ["trend", "hline"], "continuous": false, "variants": [:], "styles": [:]],
      "d": perSymbol,
    ]
    try JSONSerialization.data(withJSONObject: draws).write(to: drawDir.appendingPathComponent("draws.json"))
  }

  private func relaunchMeasured(_ label: String, env extra: [String: String] = [:]) -> TimeInterval {
    app.terminate()
    for (k, v) in extra { app.launchEnvironment[k] = v }
    let t0 = Date()
    app.launch()
    let chartTab = app.buttons[Ids.bottomChart]
    if chartTab.waitForExistence(timeout: 5), !app.symbolLabel.exists { chartTab.tap() }
    XCTAssertTrue(app.symbolLabel.waitForExistence(timeout: Self.long), "\(label)：顶栏没出来")
    XCTAssertTrue(waitUntil(timeout: 60, poll: 0.1) { (self.chartInfo()["bars"] as? Int ?? 0) > 0 }, "\(label)：K 线没来")
    let live = Date().timeIntervalSince(t0)
    note("\(label) 启动→K线 \(String(format: "%.2f", live))s")
    return live
  }

  // ------------------------------------------------------------ 1. 空自选

  func testEmptyFavoritesEverywhere() throws {
    executionTimeAllowance = 600
    XCTAssertTrue(waitForLiveChart(), "空自选下行情页没起来")
    let h0 = hangs()
    let before = chartInfo()["symbol"] as? String ?? ""
    // 没有自选可扫：左右各滑三下，图要还在、不闪退。
    for _ in 0..<3 { swipePrice(next: true); dwell(0.4) }
    for _ in 0..<3 { swipePrice(next: false); dwell(0.4) }
    XCTAssertEqual(app.state, .runningForeground, "空自选下横滑扫图后 app 不在前台")
    XCTAssertTrue(waitUntil(timeout: Self.long) { (self.chartInfo()["bars"] as? Int ?? 0) > 0 }, "扫图后图没了")
    note("空自选横滑前 \(before) 后 \(chartInfo()["symbol"] as? String ?? "?")")

    XCTAssertTrue(app.openFavorites(), "空自选下自选页没开出来")
    XCTAssertTrue(app.staticTexts["还没有自选"].waitForExistence(timeout: Self.short), "自选页没有空态")
    for _ in 0..<3 {
      app.openSectors(); dwell(0.5)
      app.buttons[Ids.bottomMe].tap(); dwell(0.5)
      app.buttons[Ids.bottomFavorites].tap(); dwell(0.5)
      app.buttons[Ids.bottomChart].tap(); dwell(0.5)
    }
    XCTAssertTrue(waitUntil(timeout: Self.long) { (self.chartInfo()["bars"] as? Int ?? 0) > 0 }, "底栏来回后图没了")
    // 冷启动也走一遍：空自选不能让启动落到一张空页上回不来。
    _ = relaunchMeasured("空自选冷启动")
    checkHangs("空自选全程", since: h0)
  }

  // ------------------------------------------------------------ 2. 提醒顶满 + 500 条线

  func testAlertsAtCapAndFiveHundredDrawings() throws {
    executionTimeAllowance = 1500
    XCTAssertTrue(waitForLiveChart())
    let bare = relaunchMeasured("对照-空档")
    app.terminate()
    try seedFullHouse()
    var runs: [TimeInterval] = []
    for i in 0..<3 { runs.append(relaunchMeasured("满载启动 \(i + 1)")) }
    note("满载启动→K线 \(runs.map { String(format: "%.2f", $0) }) 对照 \(String(format: "%.2f", bare))")

    // BTC 1m 实时跳一分钟：提醒引擎每笔报价按品种查表，200 条里只有 BTC 那几条参与。
    open("BTCUSDT")
    app.tapIntervalChip("1m")
    XCTAssertTrue(waitUntil(timeout: Self.long) { (self.chartInfo()["interval"] as? String) == "1m" })
    let h0 = hangs()
    let mark = Date().timeIntervalSince1970 * 1000
    dwell(60)
    XCTAssertGreaterThan(quoteTime(), mark, "一分钟里没来新报价")
    checkHangs("满载 BTC 1m 实时一分钟", since: h0)

    // 十只连切：每只恰好 50 条线。
    let h1 = hangs()
    let t1 = Date()
    for s in Self.tenSymbols {
      open(s)
      XCTAssertTrue(waitUntil(timeout: Self.short) { (self.chartInfo()["drawingCount"] as? Int ?? 0) == 50 },
                    "\(s) 上不是 50 条线：\(chartInfo()["drawingCount"] ?? "?")")
      canvas.swipeRight(); canvas.swipeLeft()
    }
    note("十只各 50 线连切 \(Int(Date().timeIntervalSince(t1)))s")
    checkHangs("十只 × 50 线连切", since: h1)

    // 总表 200 条：价格段、条件段都在，翻到底再翻回来。
    XCTAssertTrue(app.tapMeRow(Ids.meAlerts), "我的 › 全部预警 没点开")
    XCTAssertTrue(alertsPage.waitForExistence(timeout: Self.short), "总表没开出来")
    XCTAssertTrue(app.descendants(matching: .any)["alerts.section.price"].waitForExistence(timeout: 5), "总表没有价格段")
    let h2 = hangs()
    for _ in 0..<40 { app.swipeUp(velocity: .fast) }
    for _ in 0..<40 { app.swipeDown(velocity: .fast) }
    checkHangs("总表 200 条来回翻", since: h2)
    back()
    XCTAssertEqual(app.state, .runningForeground)
  }

  // ------------------------------------------------------------ 3. 重连风暴

  func testReconnectStormWithEverythingOpen() throws {
    executionTimeAllowance = 1200
    XCTAssertTrue(waitForLiveChart())
    app.terminate()
    try seedFullHouse()
    // 断网窗口开在这次启动 150 秒之后、持续 20 秒：先让对比、订单流（三家簿回填可能要一两分钟）、
    // 提醒订阅全起来，再一起断。
    let start = Date().timeIntervalSince1970 + 150
    _ = relaunchMeasured("满载 + 断网窗口启动", env: ["KANPAN_TEST_NET_OUTAGE": "\(Int(start)):20"])
    XCTAssertTrue(waitUntil(timeout: Self.long) { (self.chartInfo()["compareReady"] as? Int ?? 0) == 2 }, "对比两条没齐")
    XCTAssertTrue(app.openIndicatorPage(), "分析面板没开")
    let flow = app.buttons[Ids.indicatorSwitch("ORDERFLOW")]
    for _ in 0..<6 where !flow.exists { app.swipeUp(velocity: .slow) }
    XCTAssertTrue(flow.waitForExistence(timeout: Self.short), "分析面板里没有主力订单流开关")
    if (flow.value as? String) != "开" { flow.tap() }
    XCTAssertTrue(waitUntil(timeout: Self.short) { (flow.value as? String) == "开" }, "主力订单流没打开")
    app.closeOpenPanel()
    XCTAssertTrue(waitUntil(timeout: 120, poll: 1) { (self.chartInfo()["orderFlowPhase"] as? String) == "ready" }, "订单流没就绪")
    XCTAssertEqual(chartInfo()["drawingCount"] as? Int, 50)
    XCTAssertLessThan(Date().timeIntervalSince1970, start, "准备阶段超过 150 秒，断网窗口已经开始了，这一轮不作数")

    let h0 = hangs()
    while Date().timeIntervalSince1970 < start + 2 { dwell(1) }
    // 断网中照常操作：拖、捏、切周期再切回来。
    canvas.swipeRight(); canvas.pinch(withScale: 0.6, velocity: -1)
    app.tapIntervalChip("5m"); dwell(1); app.tapIntervalChip("1m")
    XCTAssertEqual(app.state, .runningForeground, "断网中操作后 app 不在前台")
    while Date().timeIntervalSince1970 < start + 20 { dwell(1) }
    let end = start + 20
    let tBack = Date()
    XCTAssertTrue(waitUntil(timeout: 90) { self.quoteTime() > end * 1000 }, "网回来 90 秒报价没恢复：\(quote())")
    let quoteBack = Date().timeIntervalSince(tBack)
    XCTAssertTrue(waitUntil(timeout: 60) {
      let info = self.chartInfo()
      return (info["interval"] as? String) == "1m" && (info["bars"] as? Int ?? 0) > 0
        && (info["compareReady"] as? Int ?? 0) == 2 && (info["orderFlowPhase"] as? String) == "ready"
    }, "网回来后图 / 对比 / 订单流没全回来：\(chartInfo()["compareReady"] ?? "?") \(chartInfo()["orderFlowPhase"] ?? "?")")
    note("断网 20s → 报价恢复 \(String(format: "%.1f", quoteBack))s，全部就绪 \(String(format: "%.1f", Date().timeIntervalSince(tBack)))s")
    checkHangs("满载断网 20 秒再恢复", since: h0)
  }
}
