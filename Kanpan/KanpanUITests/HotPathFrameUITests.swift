import XCTest

/// 行情页渲染热路径的满载场景（2026-10-04 深度审查 F 线）。
///
/// 场景：BTCUSDT 1m、副图三个（VOL + MACD + RSI）、图上 30 条线（含三把计算型工具）、
/// 对比 ETH / SOL、主力订单流开着；在这上面缩小、往回翻历史直到 6000 根以上、甩、
/// 十字线按住拖、捏合放大，最后切周期、换品种再回来。
///
/// 每一段画布手势都会让 DEBUG / KANPAN_TEST_SUPPORT 包里的 `FrameProbe` 采一份报告
/// （`ChartGestureFrames`，抬手后 1.2 秒才停），报告里有主线程每帧忙时分位、超过 8 ms 的
/// 重帧数、重帧里各渲染段（`render.<段>` / `>3ms` / `>8ms`）出现的次数。用例收尾把
/// 这几份报告从 app 沙盒里读出来，汇总成一份文本（`KANPAN_HOTPATH_OUT`，缺省 /tmp），
/// 同时挂成附件。
///
/// 判「场景真的搭起来了」（线数、对比条数、根数、副图）、「全程没有一次 ≥ 1 秒的卡死」，
/// 以及手势段超 8 ms 的帧不超过 12%（只在 Release 测试包里判，见收尾那条断言的注释；Debug 包只记数）；
/// 毫秒分位不做断言（机器负载一变就飘），拿报告前后对比。
/// **量的时候别读诊断**：`chart.canvas` 的无障碍值是一大块 JSON（锚点、订单流带……），
/// XCUITest 一读就在 app 主线程上现算一遍，所以每段手势之后先等探针停了再读。
@MainActor final class HotPathFrameUITests: KanpanUICase {
  private let profile = UUID().uuidString
  private static let out = URL(fileURLWithPath: ProcessInfo.processInfo.environment["KANPAN_HOTPATH_OUT"] ?? "/tmp/kanpan-hotpath",
                               isDirectory: true)

  override var extraLaunchEnvironment: [String: String] {
    ["KANPAN_PERSISTENCE_PROFILE": profile,
     "KANPAN_TEST_DEEPLINK": "hkline://symbol/BTCUSDT?interval=1m",
     "KANPAN_TEST_COMPARE_SYMBOLS": "binance/usd_m/ETHUSDT,binance/usd_m/SOLUSDT",
     "KANPAN_TEST_ROUTE_POLICY": "direct"]
  }

  private var canvas: XCUIElement { app.otherElements["chart.canvas"] }
  private var lines: [String] = []
  private func note(_ s: String) { lines.append(s); print("HOTPATH|" + s) }
  private func settle(_ s: TimeInterval = 1.6) { RunLoop.main.run(until: Date().addingTimeInterval(s)) }

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

  private func container() -> URL? {
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

  private func framesDir(_ c: URL) -> URL {
    c.appendingPathComponent("Library/Application Support/kanpan/Diagnostics/frames", isDirectory: true)
  }

  /// 30 条线：常见几何工具 + 三把计算型（锚定均价线 / 区间成交量分布 / 锚定成交量分布）+ 回归通道，
  /// 全落在最近几百根 1m K 线里，开图就在视野内。
  private func seedDrawings(into c: URL, around price: Double) throws {
    // 不给 `KANPAN_ACCOUNT_API_URL`（不碰线上账号服务）时 app 没有账号桥，画线落在
    // `kanpan-drawing-tests/<profile>/draws.json`（`DrawStore.folder`）。
    let personal = c.appendingPathComponent("Library/Application Support/kanpan-drawing-tests/\(profile)", isDirectory: true)
    try FileManager.default.createDirectory(at: personal, withIntermediateDirectories: true)
    let kinds: [(String, Int)] = [
      ("trend", 2), ("hline", 1), ("rectangle", 2), ("fibonacci", 2), ("channel", 3), ("ray", 2),
      ("extended", 2), ("vline", 1), ("measure", 2), ("anchoredVWAP", 1), ("fixedVolumeProfile", 2),
      ("anchoredVolumeProfile", 1), ("regression", 3), ("pitchfork", 3), ("fibFan", 2),
    ]
    let minute = 60_000.0
    let now = (Date().timeIntervalSince1970 * 1000 / minute).rounded(.down) * minute
    var items: [[String: Any]] = []
    for i in 0..<30 {
      let (kind, n) = kinds[i % kinds.count]
      let t0 = now - Double(40 + i * 9) * minute
      let p0 = price * (1 + Double(i % 7 - 3) * 0.0015)
      let pts: [[String: Any]] = (0..<n).map { k in
        ["t": t0 + Double(k) * 25 * minute, "p": p0 * (1 + Double(k) * (k.isMultiple(of: 2) ? 0.002 : -0.0015))]
      }
      items.append(["id": "d" + UUID().uuidString, "kind": kind, "points": pts, "dash": "solid", "locked": false,
                    "hidden": false, "lineWidth": 1.3, "filled": true, "levels": [0, 0.236, 0.382, 0.5, 0.618, 0.786, 1]])
    }
    let draws: [String: Any] = [
      "v": 3,
      "preferences": ["magnet": false, "favorites": ["trend", "hline"], "continuous": false, "variants": [:], "styles": [:]],
      "d": ["binance/usd_m/BTCUSDT": items],
    ]
    try JSONSerialization.data(withJSONObject: draws).write(to: personal.appendingPathComponent("draws.json"))
  }

  private func setSwitch(_ id: String, on: Bool) {
    let s = app.buttons[Ids.indicatorSwitch(id)]
    for _ in 0..<6 where !s.exists { app.swipeUp(velocity: .slow) }
    XCTAssertTrue(s.waitForExistence(timeout: Self.short), "分析面板里没有 \(id) 开关")
    if (s.value as? String == "开") != on { s.tap() }
    XCTAssertTrue(waitUntil(timeout: Self.short) { (s.value as? String == "开") == on }, "\(id) 没切到 \(on ? "开" : "关")")
  }

  private func symbolSwitch(_ symbol: String) {
    XCTAssertTrue(app.openSymbolSearch(), "顶栏放大镜没开出搜索页")
    let query = app.textFields[Ids.searchQuery]
    query.tap(); query.typeText(symbol)
    let hit = app.descendants(matching: .any).matching(identifier: "symbols.row." + testInstrumentKey(symbol)).firstMatch
    XCTAssertTrue(hit.waitForExistence(timeout: Self.long), "搜 \(symbol) 没出那一行")
    hit.tap()
  }

  func testFullHouseGestures() throws {
    executionTimeAllowance = 900
    try FileManager.default.createDirectory(at: Self.out, withIntermediateDirectories: true)
    XCTAssertTrue(waitForLiveChart(), "BTCUSDT 1m 没起来")
    let price = try XCTUnwrap(chartInfo()["lastClose"] as? Double)
    let c = try XCTUnwrap(container(), "找不到 app 数据容器")
    app.terminate()
    try seedDrawings(into: c, around: price)
    app.launch()
    let chartTab = app.buttons[Ids.bottomChart]
    if chartTab.waitForExistence(timeout: 5), !app.symbolLabel.exists { chartTab.tap() }
    XCTAssertTrue(waitForLiveChart(), "重启后 BTCUSDT 1m 没起来")
    XCTAssertTrue(waitUntil(timeout: Self.long) { (self.chartInfo()["drawingCount"] as? Int) == 30 },
                  "图上不是 30 条线：\(chartInfo()["drawingCount"] ?? "?")")
    XCTAssertTrue(waitUntil(timeout: 60) { (self.chartInfo()["compareReady"] as? Int) == 2 },
                  "两条对比没到齐：\(chartInfo()["compareReady"] ?? "?")")

    XCTAssertTrue(app.openIndicatorPage(), "分析面板没开出来")
    setSwitch("VOL", on: true); setSwitch("MACD", on: true); setSwitch("RSI", on: true)
    setSwitch("ORDERFLOW", on: true)
    app.closeOpenPanel()
    XCTAssertTrue(waitUntil(timeout: 120, poll: 1) { self.chartInfo()["orderFlowPhase"] as? String == "ready" },
                  "订单流没就绪：\(chartInfo()["orderFlowPhase"] ?? "?")")
    let start = chartInfo()
    note("场景 bars=\(start["bars"] ?? 0) drawings=\(start["drawingCount"] ?? 0) compareReady=\(start["compareReady"] ?? 0) orderFlow=\(start["orderFlowPhase"] ?? "") orders=\(start["orderFlowOrders"] ?? 0) height=\(start["height"] ?? 0) mainH=\(start["mainH"] ?? 0)")

    // 量之前把之前的报告清掉，只留这一轮手势的。
    try? FileManager.default.removeItem(at: framesDir(c))
    let h0 = hangs()
    settle(0.5)

    // 1. 缩小三下（同一串连续手势，报告合成一份）。
    for _ in 0..<3 { canvas.pinch(withScale: 0.5, velocity: -2) }
    settle()
    note("缩小后（最新处）订单流 \(bandStats())")
    // 2. 往回甩历史，直到 6000 根以上（每 4 下读一次根数，读之前等探针停）。
    var bars = chartInfo()["bars"] as? Int ?? 0
    var flings = 0
    while bars < 6000 && flings < 80 {
      for _ in 0..<4 { canvas.swipeRight(velocity: .fast); flings += 1 }
      settle()
      bars = chartInfo()["bars"] as? Int ?? bars
    }
    note("往回甩 \(flings) 下 → bars=\(bars)；此处订单流 \(bandStats())")
    // 3. 在 6000 根上来回拖、再甩几下。
    let mid = canvas.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.3))
    for k in 0..<6 {
      mid.press(forDuration: 0.05, thenDragTo: mid.withOffset(CGVector(dx: k.isMultiple(of: 2) ? 180 : -180, dy: 0)),
                withVelocity: .default, thenHoldForDuration: 0)
    }
    for _ in 0..<3 { canvas.swipeLeft(velocity: .fast) }
    settle()
    // 4. 十字线：按住出十字线，横着拖一趟、竖着拖一趟。
    let a = canvas.coordinate(withNormalizedOffset: CGVector(dx: 0.3, dy: 0.25))
    a.press(forDuration: 0.8, thenDragTo: canvas.coordinate(withNormalizedOffset: CGVector(dx: 0.75, dy: 0.35)),
            withVelocity: .slow, thenHoldForDuration: 0.2)
    settle()
    // 5. 回到最新、放大回来。
    _ = returnToLatest(timeout: 20)
    for _ in 0..<3 { canvas.pinch(withScale: 2, velocity: 2) }
    settle()
    // 6. 最新处拖几下（订单流带 + 对比 + 30 条线都在视野里）。
    for k in 0..<6 {
      mid.press(forDuration: 0.05, thenDragTo: mid.withOffset(CGVector(dx: k.isMultiple(of: 2) ? 160 : -160, dy: 0)),
                withVelocity: .default, thenHoldForDuration: 0)
    }
    settle()
    let gestureHangs = hangs()

    // 7. 切周期、换品种再回来；切完各拖一下，量「刚切过去」的那几帧。
    app.tapIntervalChip("5m")
    XCTAssertTrue(waitUntil(timeout: 30) { self.chartInfo()["interval"] as? String == "5m" && (self.chartInfo()["bars"] as? Int ?? 0) > 100 })
    mid.press(forDuration: 0.05, thenDragTo: mid.withOffset(CGVector(dx: 160, dy: 0)))
    settle()
    app.tapIntervalChip("1m")
    XCTAssertTrue(waitUntil(timeout: 30) { self.chartInfo()["interval"] as? String == "1m" })
    symbolSwitch("ETHUSDT")
    XCTAssertTrue(waitUntil(timeout: 45) { self.chartInfo()["symbol"] as? String == testInstrumentKey("ETHUSDT") })
    mid.press(forDuration: 0.05, thenDragTo: mid.withOffset(CGVector(dx: 160, dy: 0)))
    settle()
    symbolSwitch("BTCUSDT")
    XCTAssertTrue(waitUntil(timeout: 45) { self.chartInfo()["symbol"] as? String == testInstrumentKey("BTCUSDT") })
    XCTAssertTrue(waitUntil(timeout: Self.short) { (self.chartInfo()["drawingCount"] as? Int) == 30 }, "换回 BTC 线数不对")
    mid.press(forDuration: 0.05, thenDragTo: mid.withOffset(CGVector(dx: 160, dy: 0)))
    settle(2.5)
    let h1 = hangs()
    note("卡顿（main.hangs）手势段 +\(gestureHangs.count - h0.count) 全程 +\(h1.count - h0.count) 最近 \(h1.recent)")
    XCTAssertFalse(h1.recent.contains { $0 >= 1000 }, "有一次 ≥ 1 秒的卡死：\(h1.recent)")

    let (frames, heavy) = summarize(framesDir(c))
    let text = lines.joined(separator: "\n")
    try? text.write(to: Self.out.appendingPathComponent("hotpath-\(Int(Date().timeIntervalSince1970)).txt"), atomically: true, encoding: .utf8)
    let att = XCTAttachment(string: text); att.name = "热路径帧报告"; att.lifetime = .keepAlways; add(att)
    // 重帧占比的上限（10-04 F 线）：同一台空闲的 16 Pro 模拟器上，主力快照比较还在拼字符串时 594–644 / 3401–3414 帧
    // 超 8 ms（17–19%），改掉之后 152–165 / 3458–3461（4.4–4.8%）。卡在 12%：回到旧代价就红，机器正常抖动不红。
    // 别的重活（并行编译、另一台模拟器跑用例）挤着时这条会飘，判红先看机器负载。
    //
    // 这个数只对 **Release 测试包** 成立（`RELEASE=1 Tools/ui-test.sh`，即 `make hotpath-test`）。Debug 包关了优化，
    // 同一场景 2026-10-04 收尾实测 16 Pro 689 / 3294（20.9%）、17 Pro Max 1442 / 3308（43.6%），多出来的是 Swift
    // 没内联、没去掉的运行时检查，不是产品的渲染代价；拿 Debug 的数去卡 Release 标定的线，红的只会是构建配置。
    // 所以 Debug 包里这条只记数不判（场景、帧数、≥ 1 秒卡死三条照判），占比的门留给 Release。按运行时的断言配置分，
    // 不用 `#if DEBUG`：条件编译的测试要进 ReleaseTestRosterTests 的名册。
    XCTAssertGreaterThan(frames, 1500, "帧报告太少，手势段没量到")
    let share = frames > 0 ? Double(heavy) / Double(frames) : 0
    if _isDebugAssertConfiguration() {
      note("Debug 测试包：超 8 ms 的帧 \(heavy) / \(frames)（\(String(format: "%.1f", share * 100))%）只记不判，占比的门走 make hotpath-test")
    } else {
      XCTAssertLessThanOrEqual(Double(heavy), Double(frames) * 0.12, "超 8 ms 的帧 \(heavy) / \(frames)，超过 12%")
    }
  }

  /// 此刻屏上的订单流带：按主次分几条、多少条还挂着、几条细线、填色总面积（pt²）占主图多少倍。
  /// 用来判断真盘口下订单流层的叠画有多重（10-04 F 线：合成的 2400 单全挤在最近 400 根时是 3.5 倍）。
  private func bandStats() -> String {
    let info = chartInfo()
    let bands = info["orderFlowBands"] as? [[String: Any]] ?? []
    var roles: [String: Int] = [:]
    var live = 0, thin = 0, area = 0.0
    for b in bands {
      roles[b["role"] as? String ?? "?", default: 0] += 1
      if b["live"] as? Bool == true { live += 1 }
      if b["thin"] as? Bool == true { thin += 1 }
      area += ((b["w"] as? NSNumber)?.doubleValue ?? 0) * ((b["h"] as? NSNumber)?.doubleValue ?? 0)
    }
    let plotW = (info["plotW"] as? NSNumber)?.doubleValue ?? 0, mainH = (info["mainH"] as? NSNumber)?.doubleValue ?? 0
    let ratio = plotW * mainH > 0 ? area / (plotW * mainH) : 0
    return "bands=\(bands.count) \(roles.sorted { $0.key < $1.key }.map { "\($0.key)=\($0.value)" }.joined(separator: " ")) "
      + "live=\(live) thin=\(thin) area=\(Int(area))pt² (主图 \(String(format: "%.2f", ratio)) 倍) spacing=\(info["spacing"] ?? "?")"
  }

  @discardableResult
  private func summarize(_ dir: URL) -> (frames: Int, heavy: Int) {
    let files = ((try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)) ?? [])
      .filter { $0.pathExtension == "json" }.sorted { $0.lastPathComponent < $1.lastPathComponent }
    note("帧报告 \(files.count) 份")
    var totalFrames = 0, totalHeavy = 0
    var heavyAll: [String: Int] = [:]
    for f in files {
      guard let data = try? Data(contentsOf: f),
            let r = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { continue }
      let frames = r["frameCount"] as? Int ?? 0
      let work = r["work"] as? [String: Any] ?? [:]
      let heavy = r["heavyBodies"] as? [String: Int] ?? [:]
      let bodies = r["bodies"] as? [String: Int] ?? [:]
      totalFrames += frames; totalHeavy += heavy["*"] ?? 0
      for (k, v) in heavy { heavyAll[k, default: 0] += v }
      let fmt: (String) -> String = { key in (work[key] as? Double).map { String(format: "%.2f", $0) } ?? "-" }
      let parts = bodies.filter { $0.key.hasPrefix("render.") && $0.key.contains(">") }
        .sorted { $0.value > $1.value }.prefix(6).map { "\($0.key)=\($0.value)" }
      note("\(f.lastPathComponent) frames=\(frames) hz=\(r["measuredHz"] ?? "-") work p50=\(fmt("p50")) p90=\(fmt("p90")) p99=\(fmt("p99")) max=\(fmt("max")) heavy=\(heavy["*"] ?? 0) hitch=\(r["hitchRatio"] ?? 0) worstHitch=\(r["worstHitchMs"] ?? 0) slowParts=\(parts)")
    }
    let top = heavyAll.filter { $0.key != "*" }.sorted { $0.value > $1.value }.prefix(12).map { "\($0.key)=\($0.value)" }
    note("合计 frames=\(totalFrames) heavy(>8ms)=\(totalHeavy) 重帧里出现最多：\(top)")
    return (totalFrames, totalHeavy)
  }
}
