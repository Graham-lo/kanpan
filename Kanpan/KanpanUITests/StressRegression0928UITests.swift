import XCTest

// ============================================================ 压测与回归（2026-09-28）
//
// 09-27 晚到 09-28 早合进来的那一批（周期条行尾三件、条件提醒 4b、交易回放 3d、收设置项 A–H、
// 按我的习惯自动调整）一次性压一遍：
//
// 1. 交易员走查主路：BTC → 切周期 → 分析里开一个副图、画一条趋势线、开主力订单流 → 建价格提醒 →
//    自选加减 → 板块今日 / 5 日 → 我的 › 设置每一行点进去 → 注册测试号 → 建条件提醒 →
//    复盘里回放一笔已平交易 → 退回详情写「当时怎么想」→ 退登（号在 tearDown 里注销）。
// 2. 高频：30 只 × 3 个周期连切；分析、图表设置各开关 50 次。
// 3. 回放里乱来：进度线快拖、横滑换品种、转屏、退后台再回来。
// 4. 规模：200 自选、50 提醒（10 条条件）、100 画线（BTC / ETH 各 50）——列表滚动、总表、启动时长。
// 5. 网络：断网启动、图表页上断网再恢复、回放中断网、直连 / 网关来回切。
//    断网走 DEBUG 包的 `KANPAN_TEST_NET_OUTAGE=<开始 Unix 秒>:<持续秒>`（只断这个 app 的行情出口，
//    不动 Mac 的网——Surge、别的窗口都在用）。
//
// 卡顿读 `main.hangs`（主线程晚过 100 ms 记一笔），报数；超过 250 ms 的单独列出来。
// 数据一行一行追加到 docs/acceptance/压测-2026-09-28/ui-数据.txt，截图落同一目录。
@MainActor
final class StressRegression0928UITests: KanpanUICase {
  private let freshProfile = UUID().uuidString
  /// 升级那一条用老包留下的档位（`upgradeState` 第一行），其余每条一个新档位。
  private var profile: String {
    name.contains("testUpgrade") ? (Self.upgradeState?.profile ?? freshProfile) : freshProfile
  }
  static let upgradeStateFile = "/tmp/kanpan-stress-0928/upgrade-state.txt"
  static var upgradeState: (profile: String, user: String)? {
    guard let text = try? String(contentsOfFile: upgradeStateFile, encoding: .utf8) else { return nil }
    let lines = text.split(separator: "\n").map(String.init)
    return lines.count >= 2 ? (lines[0], lines[1]) : nil
  }
  private let password = "Testpass2026"
  private var created: [String] = []

  static let outDir = URL(fileURLWithPath: "/Users/mdd/zhk/kanpan/docs/acceptance/压测-2026-09-28", isDirectory: true)
  static let top200 = "BTCUSDT,ETHUSDT,SOLUSDT,ZECUSDT,QNTUSDT,XRPUSDT,NEARUSDT,SUIUSDT,WLDUSDT,DOGEUSDT,QUSDT,HYPEUSDT,ENAUSDT,UNIUSDT,TAOUSDT,PUMPUSDT,SOONUSDT,BNBUSDT,AVAXUSDT,1000PEPEUSDT,XAUUSDT,BCHUSDT,ARBUSDT,ONDOUSDT,LINKUSDT,SOXLUSDT,CLUSDT,FILUSDT,ADAUSDT,DASHUSDT,LTCUSDT,AAVEUSDT,RAREUSDT,XPLUSDT,PENGUUSDT,USUSDT,BTWUSDT,TRUMPUSDT,SNDKUSDT,SAGAUSDT,WUSDT,BZUSDT,XAGUSDT,GRAMUSDT,PHAUSDT,MARSCOINUSDT,XLMUSDT,ONEUSDT,MSTRUSDT,DOTUSDT,CRCLUSDT,GRASSUSDT,RUNEUSDT,RAYSOLUSDT,NILUSDT,PYTHUSDT,PONSUSDT,MUUSDT,INJUSDT,BRUSDT,USELESSUSDT,JTOUSDT,SEIUSDT,ARXUSDT,FETUSDT,LSKUSDT,APTUSDT,SPCXUSDT,MUBARAKUSDT,AKEUSDT,ASTERUSDT,VIRTUALUSDT,ZROUSDT,TRXUSDT,INTCUSDT,SKHYNIXUSDT,LITUSDT,HBARUSDT,ETCUSDT,GRTUSDT,JUPUSDT,TIAUSDT,VVVUSDT,1000SHIBUSDT,ARKUSDT,2ZUSDT,OPUSDT,ICPUSDT,XMRUSDT,QQQUSDT,ETHFIUSDT,JASMYUSDT,1000BONKUSDT,ATOMUSDT,AEROUSDT,RENDERUSDT,ZAMAUSDT,MAGICUSDT,LDOUSDT,PENDLEUSDT,MONUSDT,INXUSDT,SOXSUSDT,ARUSDT,ZENUSDT,DRAMUSDT,XVGUSDT,FARTCOINUSDT,POLUSDT,ORCAUSDT,KMNOUSDT,CAKEUSDT,WIFUSDT,COWUSDT,TAIKOUSDT,CRVUSDT,BULLAUSDT,COTIUSDT,KORUUSDT,EIGENUSDT,WLFIUSDT,SPYUSDT,INUSDT,SUPERUSDT,GALAUSDT,APEUSDT,SKYUSDT,NVDAUSDT,TRIAUSDT,SNXXUSDT,ACEUSDT,AZTECUSDT,ALGOUSDT,TSLAUSDT,SKHYUSDT,STXUSDT,METUSDT,MMTUSDT,KITEUSDT,KASUSDT,NOMUSDT,ESPUSDT,ORDIUSDT,BIGTIMEUSDT,CHIPUSDT,MORPHOUSDT,CCUSDT,STRKUSDT,BEATUSDT,SAMSUNGUSDT,PHAROSUSDT,VTHOUSDT,OPNUSDT,AMDUSDT,PAXGUSDT,GOOGLUSDT,TRUSTUSDT,XAIUSDT,TUSDT,PROMUSDT,METAUSDT,LYNUSDT,NATGASUSDT,XAUTUSDT,SANDUSDT,IOSTUSDT,HUMAUSDT,HEIUSDT,UAIUSDT,MOVRUSDT,DYDXUSDT,VETUSDT,KAITOUSDT,TAKEUSDT,COMPUSDT,AXSUSDT,SPKUSDT,COINUSDT,CFGUSDT,FLOCKUSDT,REUSDT,SPXUSDT,EDGEUSDT,BILLUSDT,TNSRUSDT,LABUSDT,PLUMEUSDT,GIGGLEUSDT,ALLOUSDT,DOGSUSDT,RIVERUSDT,SPELLUSDT,PIEVERSEUSDT,EWYUSDT,BASEDUSDT,FOGOUSDT,TUTUSDT,TRBUSDT,DEEPUSDT,INTWUSDT".split(separator: ",").map(String.init)

  private var testName: String { name.components(separatedBy: " ").last?.trimmingCharacters(in: CharacterSet(charactersIn: "]")) ?? name }

  override var extraLaunchEnvironment: [String: String] {
    var env = ["KANPAN_PERSISTENCE_PROFILE": profile, "KANPAN_ACCOUNT_API_URL": TestAccounts.api]
    if !name.contains("testUpgrade") {
      env["KANPAN_EXCHANGE_FIXTURE"] = "1"; env["KANPAN_EXCHANGE_FIXTURE_KEY"] = "DEMOREADONLY7C31"
    }
    if name.contains("testScale") { env["KANPAN_TEST_FAVORITES"] = Self.top200.joined(separator: ",") }
    if name.contains("testChurn") { env["KANPAN_TEST_FAVORITES"] = Self.top200.prefix(30).joined(separator: ",") }
    return env
  }

  override func setUp() async throws {
    XCUIDevice.shared.orientation = .portrait
    try? FileManager.default.createDirectory(at: Self.outDir, withIntermediateDirectories: true)
    try await super.setUp()
  }

  override func tearDown() async throws {
    XCUIDevice.shared.orientation = .portrait
    if let app, app.state != .notRunning, app.state != .unknown { app.terminate() }
    let leftovers = created; created = []
    for name in leftovers { await TestAccounts.delete(name, password: password) }
    try await super.tearDown()
  }

  // ------------------------------------------------------------ 取证

  private var deviceTag: String {
    switch Int(app.windows.firstMatch.frame.width.rounded()) {
    case 402: "iPhone16Pro"
    case 440: "iPhone17ProMax"
    case let w: "宽\(w)"
    }
  }

  private func note(_ line: String) {
    let text = "\(testName)|\(line)"
    print("压测|" + text)
    let a = XCTAttachment(string: text); a.name = "压测数据"; a.lifetime = .keepAlways; add(a)
    let file = Self.outDir.appendingPathComponent("ui-数据.txt")
    let stamp = ISO8601DateFormatter().string(from: Date())
    let data = Data("\(stamp) \(text)\n".utf8)
    if let h = try? FileHandle(forWritingTo: file) { h.seekToEndOfFile(); h.write(data); try? h.close() }
    else { try? data.write(to: file) }
  }

  private func shot(_ name: String) {
    let screenshot = XCUIScreen.main.screenshot()
    let full = "\(deviceTag)-\(name)"
    let a = XCTAttachment(screenshot: screenshot); a.name = full; a.lifetime = .keepAlways; add(a)
    try? screenshot.pngRepresentation.write(to: Self.outDir.appendingPathComponent(full + ".png"))
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

  /// 报这一段的卡顿：条数、最坏一次、超过 250 ms 的那几次。
  @discardableResult
  private func reportHangs(_ label: String, since before: (count: Int, recent: [Int])) -> [Int] {
    let after = hangs()
    let n = max(0, after.count - before.count)
    let these = Array(after.recent.suffix(min(n, after.recent.count)))
    let over = these.filter { $0 > 250 }
    note("\(label) 卡顿>100ms=\(n) 最坏=\(these.max() ?? 0)ms >250ms=\(over)")
    return over
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

  private func code(_ key: String) -> String { key.split(separator: "/").last.map(String.init) ?? key }
  private func symbolOnChart() -> String { code(chartInfo()["symbol"] as? String ?? "") }
  private func dwell(_ s: TimeInterval) { RunLoop.main.run(until: Date().addingTimeInterval(s)) }
  private var canvas: XCUIElement { app.otherElements["chart.canvas"] }

  // ------------------------------------------------------------ 动作

  private func open(_ symbol: String, file: StaticString = #filePath, line: UInt = #line) {
    XCTAssertTrue(app.openSymbolSearch(), "顶栏放大镜没开出搜索页", file: file, line: line)
    let query = app.textFields[Ids.searchQuery]
    query.tap(); query.typeText(symbol)
    let hit = app.descendants(matching: .any).matching(identifier: "symbols.row." + testInstrumentKey(symbol)).firstMatch
    XCTAssertTrue(hit.waitForExistence(timeout: Self.long), "搜 \(symbol) 没出那一行", file: file, line: line)
    hit.tap()
    XCTAssertTrue(waitUntil(timeout: 45) { self.chartInfo()["symbol"] as? String == testInstrumentKey(symbol) },
                  "点了 \(symbol) 图上没换过去：\(chartInfo())", file: file, line: line)
  }

  private func pick(_ raw: String, file: StaticString = #filePath, line: UInt = #line) {
    app.tapIntervalChip(raw)
    XCTAssertTrue(waitUntil(timeout: Self.long) { (self.chartInfo()["interval"] as? String) == raw && (self.chartInfo()["bars"] as? Int ?? 0) > 0 },
                  "周期没落到 \(raw)：\(chartInfo())", file: file, line: line)
  }

  private func swipePrice(next: Bool) {
    let quote = app.descendants(matching: .any).matching(identifier: "market.quote").firstMatch
    guard quote.exists else { return }
    quote.coordinate(withNormalizedOffset: CGVector(dx: next ? 0.85 : 0.15, dy: 0.5))
      .press(forDuration: 0.02, thenDragTo: quote.coordinate(withNormalizedOffset: CGVector(dx: next ? 0.1 : 0.9, dy: 0.5)))
  }

  private func canvasPoint(_ x: CGFloat, _ y: CGFloat) -> XCUICoordinate {
    canvas.coordinate(withNormalizedOffset: .zero).withOffset(CGVector(dx: x, dy: y))
  }

  /// 像人一样点一根 K 线出十字线：先点最新价那一带（最近几根蜡烛就在这附近，大单带子也扎堆在这里——
  /// 以前开着主力订单流时这一下出的是大单详情卡），不成再换几处；点成了大单就在原处再点一下收掉。
  private func selectACandle() -> Bool {
    let info = chartInfo()
    guard let mainH = info["mainH"] as? Double, let plotW = info["plotW"] as? Double else { return false }
    let scale = canvas.frame.height / max(1, info["height"] as? Double ?? canvas.frame.height)
    let origin = canvas.coordinate(withNormalizedOffset: .zero)
    var ys: [Double] = []
    if let last = Double(quote()["last"] ?? ""), let top = info["mainPriceTop"] as? Double,
       let bottom = info["mainPriceBottom"] as? Double, top > bottom, last < top, last > bottom {
      ys.append(mainH * (top - last) / (top - bottom))
    }
    ys += [0.78, 0.5, 0.3, 0.9, 0.15].map { mainH * $0 }
    for (k, y) in ys.enumerated() {
      let at = origin.withOffset(CGVector(dx: plotW * scale * 0.8, dy: y * scale))
      at.tap()
      _ = waitUntil(timeout: 4) { self.chartInfo()["crosshair"] as? Bool == true
        || !(self.chartInfo()["orderFlowSelected"] as? String ?? "").isEmpty }
      if chartInfo()["crosshair"] as? Bool == true {
        if k > 0 { note("点 K 线：第 \(k + 1) 处才出十字线（前面几处点到了 \(ys.prefix(k).map { Int($0) })）") }
        return true
      }
      if !(chartInfo()["orderFlowSelected"] as? String ?? "").isEmpty {
        note("点 K 线：第 \(k + 1) 处（y=\(Int(y))）点出的是大单详情卡，不是十字线")
        at.tap()
        _ = waitUntil(timeout: 3) { (self.chartInfo()["orderFlowSelected"] as? String ?? "").isEmpty }
      }
    }
    return false
  }

  private var newAlertPage: XCUIElement { app.descendants(matching: .any).matching(identifier: "alerts.new.page").firstMatch }
  private var alertsPage: XCUIElement { app.descendants(matching: .any).matching(identifier: "alerts.page").firstMatch }

  @discardableResult private func openNewAlertFromChart() -> Bool {
    for _ in 0..<3 {
      if newAlertPage.exists { return true }
      if chartInfo()["crosshair"] as? Bool != true, !selectACandle() { continue }
      let chip = app.buttons["chart.crosshair.alert"]
      guard chip.waitForExistence(timeout: 5) else { continue }
      chip.tap()
      if newAlertPage.waitForExistence(timeout: 8) { return true }
    }
    return false
  }

  private func dismissKeyboard() {
    guard app.keyboards.firstMatch.exists else { return }
    let done = app.buttons["完成"].firstMatch
    if done.exists { done.tap() } else { app.keyboards.buttons["Done"].firstMatch.tap() }
    _ = app.keyboards.firstMatch.waitForNonExistence(timeout: 3)
  }

  private func replace(_ field: XCUIElement, with text: String) {
    field.coordinate(withNormalizedOffset: CGVector(dx: 0.97, dy: 0.5)).tap()
    let old = (field.value as? String) ?? ""
    field.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: old.count + 2) + text)
  }

  private func createAlert(_ what: String, file: StaticString = #filePath, line: UInt = #line) {
    let add = app.buttons["alerts.new.create"]
    XCTAssertTrue(add.waitForExistence(timeout: 5) && add.isEnabled, "\(what)：「创建提醒」按不下去", file: file, line: line)
    dismissKeyboard()
    for _ in 0..<3 where !add.isHittable { newAlertPage.swipeUp() }
    add.tap()
    XCTAssertTrue(newAlertPage.waitForNonExistence(timeout: 8), "\(what)：建完新建页没收起", file: file, line: line)
  }

  private func closeSheets() {
    for _ in 0..<4 {
      if !alertsPage.exists && !newAlertPage.exists { return }
      let close = app.buttons["panel.done"]
      if close.waitForExistence(timeout: 2), close.isHittable {
        close.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
      } else if app.navigationBars.buttons.firstMatch.exists {
        app.navigationBars.buttons.firstMatch.tap()
      }
      _ = waitUntil(timeout: 5) { !self.alertsPage.exists && !self.newAlertPage.exists }
    }
  }

  private func back() {
    let bar = app.navigationBars.buttons.firstMatch
    if bar.exists { bar.tap() }
  }

  // ------------------------------------------------------------ 账号

  private func fillPassword() {
    let secure = app.secureTextFields["account.password"]
    XCTAssertTrue(secure.waitForExistence(timeout: 20), "没有口令输入框")
    secure.tap()
    if app.buttons["GenerateStrongPasswordButton"].waitForExistence(timeout: 2) { app.buttons["xmark"].tap() }
    for character in password { secure.typeText(String(character)) }
  }

  private func register(_ username: String) {
    XCTAssertTrue(app.openAccountFromMe(), "「我的 › 账号」没推出账号页")
    let entry = app.buttons["注册"]
    XCTAssertTrue(entry.waitForExistence(timeout: 20), "登录页上没有「注册」入口")
    entry.tap()
    let field = app.textFields["account.email"]
    XCTAssertTrue(field.waitForExistence(timeout: 20)); field.tap(); field.typeText(username)
    fillPassword()
    app.buttons["account.submit"].tap()
    XCTAssertTrue(waitUntil(timeout: 60) { !self.app.accountView.exists }, "注册 \(username) 没闭合账号页")
  }

  private func login(_ username: String) {
    XCTAssertTrue(app.openAccountFromMe(), "「我的 › 账号」没推出账号页")
    let field = app.textFields["account.email"]
    XCTAssertTrue(field.waitForExistence(timeout: 20)); field.tap(); field.typeText(username)
    fillPassword()
    app.buttons["account.submit"].tap()
    XCTAssertTrue(waitUntil(timeout: 60) { !self.app.accountView.exists }, "登录 \(username) 没闭合账号页")
  }

  private func logout() {
    XCTAssertTrue(app.openAccountFromMe(), "「我的 › 账号」没推出账号页")
    let button = app.buttons["退出登录"]
    XCTAssertTrue(button.waitForExistence(timeout: 20), "账号页上没有「退出登录」")
    button.tap()
    XCTAssertTrue(waitUntil(timeout: 30) { !self.app.accountView.exists }, "退出登录没关账号页")
  }

  private static func newName() -> String {
    "test_" + UUID().uuidString.replacingOccurrences(of: "-", with: "").prefix(10).lowercased()
  }

  // ------------------------------------------------------------ 回放

  private var replayTitle: XCUIElement { app.descendants(matching: .any)["review.replay.title"] }
  private var replayProgress: XCUIElement { app.descendants(matching: .any)["review.replay.progress"] }
  private var detailBar: XCUIElement { app.navigationBars["交易详情"] }

  private func replayReport() -> [String: Int64]? {
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

  private func openClosedBTCTrade(file: StaticString = #filePath, line: UInt = #line) -> Bool {
    let review = app.buttons[Ids.meReview]
    XCTAssertTrue(app.openMePage(), "开不出「我的」", file: file, line: line)
    XCTAssertTrue(waitUntil(timeout: Self.long) { review.label.contains("笔 · 净盈亏") },
                  "本机没拼出上周的回合：\(review.label)", file: file, line: line)
    guard app.openReviewBookFromMe() else { XCTFail("没开出复盘本", file: file, line: line); return false }
    let tradesTab = app.buttons["review.segment.交易"]
    if tradesTab.waitForExistence(timeout: Self.short) { tradesTab.tap() }
    let btc = app.buttons.matching(identifier: "review.trades.row.BTC")
    guard waitUntil(timeout: Self.long, { btc.count >= 2 }) else { XCTFail("BTC 不是两笔", file: file, line: line); return false }
    btc.element(boundBy: 1).tap()
    return detailBar.waitForExistence(timeout: Self.short)
  }

  private func startReplay(file: StaticString = #filePath, line: UInt = #line) -> [String: Int64]? {
    let disc = app.buttons["trade.detail.replay"]
    guard disc.waitForExistence(timeout: Self.short) else { XCTFail("没有播放记号", file: file, line: line); return nil }
    disc.tap()
    XCTAssertTrue(waitUntil(timeout: Self.short) { self.replayTitle.exists }, "回放没起来", file: file, line: line)
    XCTAssertTrue(app.buttons["暂停"].waitForExistence(timeout: Self.long), "回放没自己播起来", file: file, line: line)
    guard waitUntil(timeout: Self.short, { self.replayReport() != nil }) else { XCTFail("记号层没报回放", file: file, line: line); return nil }
    return replayReport()
  }

  private func dragProgress(from: CGFloat, to: CGFloat, hold: TimeInterval = 0.05) {
    let a = replayProgress.coordinate(withNormalizedOffset: CGVector(dx: min(max(from, 0.01), 0.99), dy: 0.5))
    let b = replayProgress.coordinate(withNormalizedOffset: CGVector(dx: min(max(to, 0), 1), dy: 0.5))
    a.press(forDuration: hold, thenDragTo: b)
  }

  // ------------------------------------------------------------ 1. 交易员走查主路

  func testWalkthroughAsATrader() throws {
    executionTimeAllowance = 900
    XCTAssertTrue(waitForLiveChart(), "图没活")
    let h0 = hangs()
    // 分段记卡顿：哪一段出了 >250 ms 一眼看得出。
    var mark = h0
    func phase(_ name: String) { reportHangs("走查·" + name, since: mark); mark = hangs() }
    open("BTCUSDT")
    for raw in ["1h", "4h", "15m"] { pick(raw) }
    note("BTC 切周期 ok bars=\(chartInfo()["bars"] ?? 0)")

    phase("切品种与周期")
    // 分析：开 RSI（副图最多三个，开了它换下最早那个）、画趋势线、开主力订单流。
    XCTAssertTrue(app.openIndicatorPage(), "分析面板没开出来")
    let scroll = app.scrollViews["panel.content"]
    let rsi = app.buttons["indicator.switch.RSI"]
    for _ in 0..<5 where !(rsi.isHittable && scroll.frame.contains(rsi.frame)) { scroll.swipeUp() }
    rsi.tap()
    app.closeOpenPanel()
    XCTAssertTrue(waitUntil(timeout: Self.short) { (self.chartInfo()["subs"] as? [String])?.contains("RSI") == true },
                  "RSI 没上图：\(chartInfo()["subs"] ?? "?")")
    XCTAssertLessThanOrEqual((chartInfo()["subs"] as? [String])?.count ?? 0, 3, "副图超过三个")

    XCTAssertTrue(app.enterDrawingInPortrait(), "进不了竖屏画线")
    let before = chartInfo()["drawingCount"] as? Int ?? 0
    app.buttons[Ids.drawTrend].tap()
    canvasPoint(100, 60).tap(); canvasPoint(240, 120).tap()
    XCTAssertTrue(waitUntil(timeout: Self.short) { (self.chartInfo()["drawingCount"] as? Int ?? 0) == before + 1 },
                  "趋势线没画上：\(before) → \(chartInfo()["drawingCount"] ?? "?")")
    app.buttons[Ids.drawFinish].tap()
    XCTAssertTrue(app.buttons[Ids.drawFinish].waitForNonExistence(timeout: Self.short), "画完退不出画线态")

    XCTAssertTrue(app.openIndicatorPage(), "分析面板第二次没开出来")
    let flow = app.buttons["indicator.switch.ORDERFLOW"]
    for _ in 0..<6 where !(flow.exists && flow.isHittable && scroll.frame.contains(flow.frame)) { scroll.swipeUp() }
    XCTAssertTrue(flow.exists, "分析面板里没有主力订单流开关")
    flow.tap()
    app.closeOpenPanel()
    XCTAssertTrue(waitUntil(timeout: 60) { (self.chartInfo()["orderFlowPhase"] as? String) == "ready" },
                  "主力订单流没到 ready：\(chartInfo()["orderFlowPhase"] ?? "?")")
    note("订单流 ready 大单=\(chartInfo()["orderFlowOrders"] ?? 0)")
    shot("走查-BTC-RSI-趋势线-订单流")

    phase("分析面板·画线·订单流")
    // 价格提醒（没登录）。
    XCTAssertTrue(openNewAlertFromChart(), "十字线上的「创建提醒」没开出创建页")
    createAlert("BTC 价格提醒")

    phase("价格提醒")
    // 自选加减：搜 LINK → 星 → 自选页有 → 再点星 → 自选页没了。
    let link = testInstrumentKey("LINKUSDT")
    XCTAssertTrue(app.openSymbolSearch())
    app.textFields[Ids.searchQuery].tap(); app.textFields[Ids.searchQuery].typeText("LINKUSDT")
    let star = app.buttons["symbols.star." + link]
    XCTAssertTrue(star.waitForExistence(timeout: Self.long), "搜索页上没有 LINK 的星")
    if star.label == "取消自选" { star.tap(); _ = waitUntil(timeout: 3) { star.label == "加入自选" } }
    star.tap()
    XCTAssertTrue(waitUntil(timeout: 5) { star.label == "取消自选" }, "点星没加进自选：\(star.label)")
    app.descendants(matching: .any).matching(identifier: "symbols.row." + link).firstMatch.tap()
    XCTAssertTrue(app.openFavorites(), "进不了自选页")
    XCTAssertTrue(app.buttons["favorites.open." + link].waitForExistence(timeout: Self.short), "自选页上没有刚加的 LINK")
    app.buttons[Ids.bottomChart].tap()
    XCTAssertTrue(app.openSymbolSearch())
    app.textFields[Ids.searchQuery].tap(); app.textFields[Ids.searchQuery].typeText("LINKUSDT")
    XCTAssertTrue(star.waitForExistence(timeout: Self.long)); star.tap()
    XCTAssertTrue(waitUntil(timeout: 5) { star.label == "加入自选" }, "再点星没取消：\(star.label)")
    app.descendants(matching: .any).matching(identifier: "symbols.row." + link).firstMatch.tap()
    XCTAssertTrue(app.openFavorites())
    XCTAssertTrue(waitUntil(timeout: 5) { !self.app.buttons["favorites.open." + link].exists }, "取消后自选页上还有 LINK")

    phase("自选加减")
    // 板块：今日 / 5 日，点进一个板块，列表没有排序小块。
    app.buttons[Ids.bottomSectors].tap()
    let d5 = app.buttons["sector.window.d5"], today = app.buttons["sector.window.today"]
    XCTAssertTrue(today.waitForExistence(timeout: Self.long), "板块页没有「今日」")
    if d5.waitForExistence(timeout: Self.short) {
      d5.tap(); XCTAssertTrue(waitUntil(timeout: 5) { d5.isSelected }, "5 日没选上")
      today.tap(); XCTAssertTrue(waitUntil(timeout: 5) { today.isSelected }, "今日没选上")
    } else { note("板块 5 日那一行此刻不在（snap.hasD5=false）") }
    let firstSector = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'sector.row.'")).firstMatch
    XCTAssertTrue(firstSector.waitForExistence(timeout: Self.long), "板块列表没有行")
    firstSector.tap()
    XCTAssertTrue(app.descendants(matching: .any)["sector.list"].waitForExistence(timeout: Self.short) ||
                  app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'sector.symbol.' OR identifier BEGINSWITH 'favorites.open.'")).count > 0,
                  "板块点进去没有品种列表")
    XCTAssertFalse(app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'sector.sort'")).firstMatch.exists, "板块品种列表不该有排序小块")
    shot("走查-板块品种列表")
    back()

    phase("板块")
    // 我的 › 设置：每一行点进去再退出来。
    walkEverySettingsRow()

    phase("设置逐行")
    // 注册测试号 → 条件提醒（均线站上）。
    let user = Self.newName(); created.append(user)
    register(user)
    app.buttons[Ids.bottomChart].tap()
    XCTAssertTrue(openNewAlertFromChart(), "登录后没开出创建页")
    let menu = app.buttons["alerts.new.condition"]
    XCTAssertTrue(menu.waitForExistence(timeout: 8), "登录后「条件」没变成菜单")
    menu.tap()
    let ma = app.buttons["alerts.new.kind.ma"]
    XCTAssertTrue(ma.waitForExistence(timeout: 5), "条件菜单里没有均线"); ma.tap()
    let length = app.textFields["alerts.new.length"]
    XCTAssertTrue(length.waitForExistence(timeout: 5))
    replace(length, with: "200"); dismissKeyboard()
    app.buttons["alerts.new.side.站上"].tap()
    createAlert("BTC 均线条件提醒")
    XCTAssertTrue(app.openMePage())
    XCTAssertTrue(app.tapMeRow(Ids.meAlerts), "「我的 › 全部预警」没开")
    XCTAssertTrue(alertsPage.waitForExistence(timeout: Self.short), "总表没开出来")
    XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label CONTAINS 'MA 200'")).firstMatch.waitForExistence(timeout: 5),
                  "总表里没有刚建的均线条件提醒")
    shot("走查-总表-价格加条件")
    back()

    phase("注册与条件提醒")
    // 复盘：回放已平那笔 → 退回详情 → 写「当时怎么想」。
    XCTAssertTrue(openClosedBTCTrade(), "没进已平那笔")
    let r = try XCTUnwrap(startReplay())
    note("回放 起 \(r)")
    app.buttons["开仓处"].tap()
    XCTAssertTrue(waitUntil(timeout: Self.short) { (self.replayReport()?["last"] ?? 0) >= r["open"]! }, "开仓处没跳过去")
    app.buttons["退出"].tap()
    XCTAssertTrue(detailBar.waitForExistence(timeout: Self.short), "退出没回到交易详情")
    let field = app.textViews["trade.detail.note"].exists ? app.textViews["trade.detail.note"] : app.textFields["trade.detail.note"]
    for _ in 0..<4 where !(field.exists && field.isHittable) { app.swipeUp() }
    XCTAssertTrue(field.waitForExistence(timeout: Self.short), "登录后详情里没有「当时怎么想」")
    field.tap(); field.typeText("压测走查：突破追多")
    app.buttons["trade.detail.note.save"].tap()
    XCTAssertTrue(waitUntil(timeout: Self.long) { !self.app.buttons["trade.detail.note.save"].isEnabled }, "「当时怎么想」没存上")
    shot("走查-交易详情-当时怎么想")
    detailBar.buttons.firstMatch.tap()
    if app.buttons["review.back"].waitForExistence(timeout: Self.short) { app.buttons["review.back"].tap() }

    phase("复盘回放与笔记")
    // 退登：自选、提醒不丢（本机那份）。
    logout()
    reportHangs("走查全程", since: h0)
    XCTAssertEqual(app.state, .runningForeground, "走查中 app 掉了")
  }

  /// 「我的 › 设置」从上到下每一行：推进去的页不是空的、退得回来；开关点两下回原状；
  /// 收掉的那些 id 一个都不在。
  private func walkEverySettingsRow() {
    XCTAssertTrue(app.openSettingsFromMe(), "「我的 › 设置」没开")
    for gone in ["display.ambient", "settings.changeBasis", "settings.keepAwake", "settings.clearCache", "settings.magnet",
                 "alerts.watchMove.threshold", "settings.replaySpeed", "settings.timeZone"] {
      XCTAssertFalse(app.descendants(matching: .any)[gone].exists, "收掉的设置项 \(gone) 还在")
    }
    shot("走查-设置-上")
    let pushRows = ["alerts.sound.open", "settings.habits.learned"]
    for id in pushRows {
      let row = app.descendants(matching: .any).matching(identifier: id).firstMatch
      for _ in 0..<8 where !(row.exists && row.isHittable) { app.swipeUp(velocity: .slow) }
      guard row.exists, row.isHittable else { XCTFail("设置页上翻不出 \(id)"); continue }
      let before = app.staticTexts.count
      row.tap()
      dwell(0.8)
      let texts = app.staticTexts.allElementsBoundByIndex.prefix(40).map(\.label)
        .filter { !$0.isEmpty && !$0.contains("\n") && $0.count <= 24 }
      XCTAssertGreaterThan(texts.count, 2, "\(id) 推进去是空页：\(texts)")
      note("设置行 \(id) 推进去 \(texts.count) 段字（前 \(before)）：\(texts.prefix(6).joined(separator: "/"))")
      back()
      XCTAssertTrue(app.buttons["display.theme.sage"].waitForExistence(timeout: 5) || app.buttons["settings.habits"].waitForExistence(timeout: 3),
                    "\(id) 退不回设置页")
    }
    // 「关于」不是推进去的一页：同一行上两条链接，用系统浏览器打开账号服务上的静态页。点一条看 Safari 起来，再切回来。
    let about = app.descendants(matching: .any).matching(identifier: "settings.about").firstMatch
    for _ in 0..<8 where !(about.exists && about.isHittable) { app.swipeUp(velocity: .slow) }
    XCTAssertTrue(about.exists, "设置页上没有「关于」")
    note("关于行：\(about.label)")
    // 链接按 id 或按字找（AccountExportUITests 同一口径）：SwiftUI 的 Link 有时只以「link + 字」暴露。
    for (sub, title) in [("settings.privacy", "隐私政策"), ("settings.terms", "服务条款")] {
      let byId = app.descendants(matching: .any).matching(identifier: sub).firstMatch.exists
      let byTitle = app.links[title].exists || app.buttons[title].exists
      note("关于行链接 \(title)：按 id \(byId)、按字 \(byTitle)")
      XCTAssertTrue(byId || byTitle, "关于行上没有「\(title)」")
    }
    let privacy = app.descendants(matching: .any).matching(identifier: "settings.privacy").firstMatch
    if privacy.exists, privacy.isHittable {
      privacy.tap()
      let safari = XCUIApplication(bundleIdentifier: "com.apple.mobilesafari")
      note("点隐私政策 → Safari 前台：\(safari.wait(for: .runningForeground, timeout: 10))")
      app.activate()
      XCTAssertTrue(app.wait(for: .runningForeground, timeout: 10), "从 Safari 切不回来")
    }
    // 开关类：点两下回原状。
    for id in ["alerts.watchMove", "alerts.listing", "settings.habits"] {
      let toggle = app.switches[id].exists ? app.switches[id] : app.buttons[id]
      for _ in 0..<8 where !(toggle.exists && toggle.isHittable) { app.swipeUp(velocity: .slow) }
      guard toggle.exists else { XCTFail("设置页上没有 \(id)"); continue }
      let v0 = toggle.value as? String
      toggle.tap()
      _ = waitUntil(timeout: 3) { (toggle.value as? String) != v0 }
      toggle.tap()
      XCTAssertTrue(waitUntil(timeout: 3) { (toggle.value as? String) == v0 }, "\(id) 点两下没回原状")
    }
    // 恢复默认：不弹确认框，直接恢复、底下给五秒「撤销」。先把「按我的习惯自动调整」翻一下当记号，
    // 恢复后它回出厂值，点撤销又回到翻过的那一档，最后翻回原状。
    let habits = app.switches["settings.habits"].exists ? app.switches["settings.habits"] : app.buttons["settings.habits"]
    let reset = app.buttons["settings.reset"]
    if habits.exists {
      for _ in 0..<8 where !habits.isHittable { app.swipeUp(velocity: .slow) }
      let original = habits.value as? String
      habits.tap()
      _ = waitUntil(timeout: 3) { (habits.value as? String) != original }
      let flipped = habits.value as? String
      // 标签栏没有自己的底、页面从它身后穿过去：最后一行停在标签栏那一截里时 XCUITest 仍认它 hittable，
      // 点下去落在标签栏上。像人一样把它推到标签栏上沿以上再点。
      let barTop = app.buttons[Ids.bottomMe].frame.minY
      for _ in 0..<6 where !(reset.exists && reset.isHittable && reset.frame.maxY <= barTop) { app.swipeUp(velocity: .slow) }
      XCTAssertTrue(reset.exists, "设置页底上没有「恢复默认」")
      XCTAssertLessThanOrEqual(reset.frame.maxY, barTop + 1, "「恢复默认」推不到标签栏上沿以上：行底 \(reset.frame.maxY) 栏顶 \(barTop)")
      reset.tap()
      let undo = app.buttons["toast.undo"]
      XCTAssertTrue(undo.waitForExistence(timeout: 5), "恢复默认之后底下没有「撤销」")
      XCTAssertTrue(waitUntil(timeout: 3) { (habits.value as? String) != flipped }, "恢复默认后习惯开关没回出厂")
      undo.tap()
      XCTAssertTrue(waitUntil(timeout: 5) { (habits.value as? String) == flipped }, "撤销没把习惯开关还原")
      for _ in 0..<8 where !habits.isHittable { app.swipeDown(velocity: .slow) }
      habits.tap()
      XCTAssertTrue(waitUntil(timeout: 3) { (habits.value as? String) == original }, "习惯开关翻不回原状")
      note("恢复默认 → 撤销：习惯开关 \(original ?? "?") → \(flipped ?? "?") → 恢复 → 撤销回 \(flipped ?? "?")")
    } else { XCTFail("设置页上没有 settings.habits") }
    shot("走查-设置-底")
    // 直连 / 网关的那一行在不在。
    for _ in 0..<8 where !app.buttons[Ids.settingsPage].isHittable { app.swipeDown(velocity: .slow) }
    XCTAssertTrue(app.buttons[Ids.settingsPage].exists, "设置页上没有行情线路")
    back()
  }

  // ------------------------------------------------------------ 2. 高频

  /// 30 只 × 3 个周期：顶栏横滑换品种，每只上点三档周期，最后停下来看图是否自洽。
  func testChurnThirtySymbolsTimesThreeIntervals() throws {
    executionTimeAllowance = 1200
    XCTAssertTrue(app.openFavorites())
    let first = app.buttons["favorites.open." + testInstrumentKey(Self.top200[0])]
    XCTAssertTrue(first.waitForExistence(timeout: Self.long)); first.tap()
    XCTAssertTrue(waitForLiveChart(), "BTC 没活")
    let h0 = hangs()
    let started = Date()
    let intervals = ["5m", "1h", "4h"]
    var last = ""
    for i in 0..<30 {
      for raw in intervals { app.tapIntervalChip(raw); last = raw; usleep(120_000) }
      if i < 29 { swipePrice(next: true); usleep(150_000) }
    }
    let spent = Date().timeIntervalSince(started)
    let want = code(testInstrumentKey(Self.top200[29]))
    XCTAssertTrue(waitUntil(timeout: Self.long) {
      self.symbolOnChart() == want && (self.chartInfo()["interval"] as? String) == last && (self.chartInfo()["bars"] as? Int ?? 0) > 0
    }, "停手之后图不是第 30 只 \(want) 的 \(last)：\(symbolOnChart()) \(chartInfo()["interval"] ?? "?") bars=\(chartInfo()["bars"] ?? 0)")
    XCTAssertTrue(waitUntil(timeout: Self.long) { self.code(self.quote()["symbol"] ?? "") == want }, "顶栏报价不是 \(want)：\(quote())")
    note("30×3 用时 \(Int(spent))s 停在 \(symbolOnChart()) \(chartInfo()["interval"] ?? "?")")
    reportHangs("30 只 × 3 周期", since: h0)
    shot("高频-30x3-停手")
  }

  /// 泡 5 分钟：换品种、换周期、开关分析面板、切四个标签页轮着来。开始时在 /tmp 留个记号，
  /// 外面的采样脚本（ps 采内存 + xctrace）看到记号就挂上这只进程，采满 5 分钟。
  func testSoakFiveMinutes() throws {
    executionTimeAllowance = 900
    XCTAssertTrue(app.openFavorites())
    let first = app.buttons["favorites.open." + testInstrumentKey(Self.top200[0])]
    XCTAssertTrue(first.waitForExistence(timeout: Self.long)); first.tap()
    XCTAssertTrue(waitForLiveChart(), "BTC 没活")
    let h0 = hangs()
    let marker = URL(fileURLWithPath: "/tmp/kanpan-stress-0928/soak-start")
    try? "\(Date().timeIntervalSince1970)".write(to: marker, atomically: true, encoding: .utf8)
    let started = Date()
    let intervals = ["5m", "15m", "1h", "4h"]
    var i = 0
    while Date().timeIntervalSince(started) < 300 {
      app.tapIntervalChip(intervals[i % intervals.count]); usleep(300_000)
      swipePrice(next: i % 7 != 6); usleep(400_000)
      if i % 5 == 4 { XCTAssertTrue(app.openIndicatorPage(), "第 \(i) 轮分析没开出来"); app.closeOpenPanel() }
      if i % 9 == 8 {
        for tab in [Ids.bottomFavorites, Ids.bottomSectors, Ids.bottomMe] where app.buttons[tab].exists { app.buttons[tab].tap(); usleep(500_000) }
        app.buttons[Ids.bottomChart].tap(); usleep(500_000)
      }
      i += 1
    }
    try? FileManager.default.removeItem(at: marker)
    note("泡 5 分钟：\(i) 轮，停在 \(symbolOnChart()) \(chartInfo()["interval"] ?? "?") bars=\(chartInfo()["bars"] ?? 0)")
    reportHangs("泡 5 分钟", since: h0)
    XCTAssertTrue(waitUntil(timeout: Self.long) { (self.chartInfo()["bars"] as? Int ?? 0) > 0 }, "泡完图没了")
  }

  /// 分析面板里按住一行再往上拖（手指先停一下再划，人找指标时常这样）：应当是滚动，不该点开那一行的参数页。
  /// 2026-09-28 lane 2 里 `IndicatorLayoutGroupsEvidenceUITests` 一次「按 0.1 s 再拖」滚了 50pt 后点开了平滑异同。
  func testPanelDragScrollsNotTaps() throws {
    executionTimeAllowance = 900
    XCTAssertTrue(waitForLiveChart())
    var opened: [String] = []
    // 先半屏（medium）按住再拖：这一下是把面板往上拉到大屏；再在大屏里按住再拖：这一下是滚内容。
    for large in [false, true] {
      for (i, hold) in [0.1, 0.1, 0.1, 0.1, 0.3, 0.3, 0.3, 0.05].enumerated() {
        XCTAssertTrue(app.openIndicatorPage(), "第 \(i) 次分析没开出来")
        let content = app.scrollViews["panel.content"]
        XCTAssertTrue(content.waitForExistence(timeout: Self.short))
        if large {
          // 快甩一下拉到大屏（快甩不会点开，见上一轮：0.05 秒、1500 的都没点开）。
          content.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.2))
            .press(forDuration: 0.02, thenDragTo: app.windows.firstMatch.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.05)),
                   withVelocity: 2500, thenHoldForDuration: 0)
          dwell(0.8)
          if app.buttons["取消"].exists && app.buttons["保存"].exists { app.buttons["取消"].tap(); dwell(0.6) }
        }
        let before = content.frame
        content.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.7))
          .press(forDuration: hold, thenDragTo: content.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.3)), withVelocity: 500, thenHoldForDuration: 0)
        dwell(1.2)
        let editor = app.buttons["取消"].exists && app.buttons["保存"].exists
        let tag = "\(large ? "大屏" : "半屏")#\(i) hold=\(hold) 面板顶 \(Int(before.minY))"
        if editor { opened.append(tag); app.buttons["取消"].tap(); dwell(0.6) }
        else { note("面板拖 \(tag) → \(content.exists ? Int(content.frame.minY) : -1)，没点开") }
        app.closeOpenPanel()
        dwell(0.4)
      }
    }
    note("分析面板按住再拖 16 次，点开参数页 \(opened.count) 次：\(opened)")
    XCTAssertTrue(opened.isEmpty, "按住再拖点开了参数页：\(opened)")
  }

  /// 分析、图表设置各开关 50 次。
  func testChurnPanelsFiftyTimesEach() throws {
    executionTimeAllowance = 1200
    XCTAssertTrue(waitForLiveChart())
    let h0 = hangs()
    var t = Date()
    for i in 0..<50 {
      XCTAssertTrue(app.openIndicatorPage(), "第 \(i + 1) 次分析没开出来")
      app.closeOpenPanel()
      XCTAssertTrue(app.buttons[Ids.intervalIndicators].waitForExistence(timeout: 5), "第 \(i + 1) 次分析收不掉")
    }
    note("分析开关 50 次 \(Int(Date().timeIntervalSince(t)))s")
    let h1 = hangs()
    reportHangs("分析 ×50", since: h0)
    t = Date()
    let chartEntry = app.buttons[Ids.intervalChart]
    let marker = app.buttons[Ids.chartPanelMarker]
    for i in 0..<50 {
      XCTAssertTrue(chartEntry.waitForExistence(timeout: 5)); chartEntry.tap()
      XCTAssertTrue(marker.waitForExistence(timeout: 5), "第 \(i + 1) 次图表设置没开出来")
      XCTAssertTrue(app.closeChartPanel(), "第 \(i + 1) 次图表设置收不掉")
    }
    note("图表设置开关 50 次 \(Int(Date().timeIntervalSince(t)))s")
    reportHangs("图表设置 ×50", since: h1)
    XCTAssertTrue(waitUntil(timeout: Self.short) { (self.chartInfo()["bars"] as? Int ?? 0) > 0 }, "开关完图没了")
    shot("高频-面板开关后")
  }

  // ------------------------------------------------------------ 3. 回放里乱来

  func testReplayAbuseScrubSwipeRotateBackground() throws {
    executionTimeAllowance = 900
    XCTAssertTrue(openClosedBTCTrade())
    let r = try XCTUnwrap(startReplay())
    let h0 = hangs()
    // 进度线来回快拖 40 下。
    var seed: UInt64 = 20260928
    for _ in 0..<40 {
      seed = seed &* 6364136223846793005 &+ 1442695040888963407
      let a = CGFloat((seed >> 33) % 100) / 100
      seed = seed &* 6364136223846793005 &+ 1442695040888963407
      let b = CGFloat((seed >> 33) % 100) / 100
      dragProgress(from: a, to: b, hold: 0.02)
    }
    XCTAssertNotNil(replayReport(), "快拖之后回放没了")
    XCTAssertTrue(replayTitle.exists, "快拖之后回放标题没了")
    note("快拖 40 下后 \(replayReport() ?? [:])")
    // 横滑顶栏（想换品种）：回放要么不理，要么干净地退出，不许卡在半截。
    for next in [true, false, true] { swipePrice(next: next); usleep(300_000) }
    dwell(1)
    let stillReplay = replayTitle.exists
    if stillReplay {
      XCTAssertTrue(code(chartInfo()["symbol"] as? String ?? "").hasPrefix("BTC"), "回放里横滑把图换了但回放标题还挂着：\(chartInfo()["symbol"] ?? "?")")
    }
    note("回放中横滑 → \(stillReplay ? "回放不理，仍是 BTC" : "回放退出，图在 \(symbolOnChart())")")
    if stillReplay {
      // 转屏再转回来。
      XCUIDevice.shared.orientation = .landscapeLeft; dwell(2)
      shot("回放-横屏")
      XCUIDevice.shared.orientation = .portrait; dwell(2)
      XCTAssertTrue(replayTitle.waitForExistence(timeout: Self.short), "转屏回来回放没了")
      // 退后台 5 秒再回来。
      XCUIDevice.shared.press(.home); dwell(5)
      app.activate()
      XCTAssertTrue(replayTitle.waitForExistence(timeout: Self.long), "回前台回放没了")
      XCTAssertNotNil(replayReport(), "回前台记号层没报")
      // 还能播、还能拖到底变重播。
      dragProgress(from: 0.5, to: 1, hold: 0.15)
      XCTAssertTrue(app.buttons["重播"].waitForExistence(timeout: Self.short), "拖到底没变重播")
      XCTAssertEqual(replayReport()?["last"], r["close"]! + 5 * r["step"]!, "拖到底游标不在平仓后第 5 根")
      app.buttons["退出"].tap()
      XCTAssertTrue(detailBar.waitForExistence(timeout: Self.short), "退出没回到详情")
    }
    reportHangs("回放乱来", since: h0)
    XCTAssertEqual(app.state, .runningForeground)
  }

  // ------------------------------------------------------------ 4. 规模

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

  private func seedAlertsAndDrawings(into container: URL) throws {
    let support = container.appendingPathComponent("Library/Application Support", isDirectory: true)
    let now = Date().timeIntervalSince1970 * 1000
    var alerts: [[String: Any]] = []
    let symbols = Array(Self.top200.prefix(20))
    for i in 0..<40 {
      let s = symbols[i % symbols.count]
      alerts.append(["id": "a" + UUID().uuidString, "kind": "price", "symbol": s, "market": "binance/usd_m",
                     "lines": [["extendLeft": true, "extendRight": true, "points": [["p": 0.0001 * Double(i + 1), "t": now]]]],
                     "condition": "touch", "status": "active", "armedAt": now, "once": true,
                     "title": "\(s.replacingOccurrences(of: "USDT", with: "")) 跌到 \(0.0001 * Double(i + 1))",
                     "created": now - Double(i) * 60_000, "webhook": NSNull(), "webhookText": NSNull(), "note": NSNull(),
                     "rule": NSNull(), "drawingID": NSNull(), "dueAt": NSNull(), "firedAt": NSNull(), "firedPrice": NSNull(), "reviewID": NSNull()])
    }
    let rules: [[String: Any]] = [
      ["type": "funding", "side": "above", "rate": "0.5"],
      ["type": "openInterestChange", "threshold": "0.9"],
      ["type": "orderflowWall", "threshold": "1000000000000"],
      ["type": "funding", "side": "below", "rate": "-0.5"],
      ["type": "orderflowWall", "threshold": "2000000000000"],
    ]
    for i in 0..<10 {
      let s = symbols[i]
      alerts.append(["id": "a" + UUID().uuidString, "kind": "condition", "symbol": s, "market": "binance/usd_m",
                     "lines": [], "condition": "touch", "status": "active", "armedAt": now, "once": true,
                     "title": "\(s) 条件 \(i)", "created": now - Double(i) * 30_000, "rule": rules[i % rules.count],
                     "webhook": NSNull(), "webhookText": NSNull(), "note": NSNull(), "drawingID": NSNull(), "dueAt": NSNull(),
                     "firedAt": NSNull(), "firedPrice": NSNull(), "reviewID": NSNull()])
    }
    // 真正装进来的是账号档案目录（`AppAccountBridge.prepare` → `AccountFiles.directory`）：
    // 测试档案的根是 `kanpan/accounts/tests/<profile>`，没登录时的档案在 `local/<registry.guest>` 下。
    // `kanpan-alert-tests` / `kanpan-drawing-tests` 那两处是 store 的默认路径，prepare 之后就被换掉了，写那里不生效。
    let root = support.appendingPathComponent("kanpan/accounts/tests/\(profile)", isDirectory: true)
    let registry = try JSONSerialization.jsonObject(with: Data(contentsOf: root.appendingPathComponent("registry.json"))) as? [String: Any]
    let guest = try XCTUnwrap(registry?["guest"] as? String, "registry.json 里没有访客批次").lowercased()
    let personal = root.appendingPathComponent("local/\(guest)", isDirectory: true)
    try FileManager.default.createDirectory(at: personal, withIntermediateDirectories: true)
    try JSONSerialization.data(withJSONObject: ["a": alerts, "v": 1]).write(to: personal.appendingPathComponent("alerts.json"))

    func lines(_ base: Double, _ step: Double, kind: String) -> [[String: Any]] {
      (0..<50).map { k in
        let t0 = now - Double(200 - k * 3) * 3_600_000
        let pts: [[String: Any]] = kind == "hline" ? [["t": t0, "p": base + Double(k) * step]]
          : [["t": t0, "p": base + Double(k) * step], ["t": t0 + 20 * 3_600_000, "p": base + Double(k) * step * 1.5]]
        return ["id": "d" + UUID().uuidString, "kind": kind, "points": pts, "dash": "solid", "locked": k % 7 == 0,
                "hidden": false, "lineWidth": 1.3, "filled": true, "levels": [0, 0.236, 0.382, 0.5, 0.618, 0.786, 1]]
      }
    }
    let draws: [String: Any] = [
      "v": 3,
      "preferences": ["magnet": true, "favorites": ["trend", "hline"], "continuous": false, "variants": [:], "styles": [:]],
      "d": ["binance/usd_m/BTCUSDT": lines(60000, 400, kind: "trend"), "binance/usd_m/ETHUSDT": lines(2000, 20, kind: "hline")],
    ]
    try JSONSerialization.data(withJSONObject: draws).write(to: personal.appendingPathComponent("draws.json"))
  }

  private func relaunchMeasured(_ label: String) -> (first: TimeInterval, live: TimeInterval) {
    app.terminate()
    let t0 = Date()
    app.launch()
    let chartTab = app.buttons[Ids.bottomChart]
    if chartTab.waitForExistence(timeout: 5), !app.symbolLabel.exists { chartTab.tap() }
    XCTAssertTrue(app.symbolLabel.waitForExistence(timeout: Self.long), "\(label)：顶栏没出来")
    let first = Date().timeIntervalSince(t0)
    XCTAssertTrue(waitUntil(timeout: 60, poll: 0.1) { (self.chartInfo()["bars"] as? Int ?? 0) > 0 }, "\(label)：K 线没来")
    let live = Date().timeIntervalSince(t0)
    note("\(label) 启动→顶栏 \(String(format: "%.2f", first))s →K线 \(String(format: "%.2f", live))s")
    return (first, live)
  }

  func testScaleTwoHundredFavoritesFiftyAlertsHundredDrawings() throws {
    executionTimeAllowance = 1200
    XCTAssertTrue(waitForLiveChart())
    // 空档的启动时长作对照。
    let bare = relaunchMeasured("对照-只有 200 自选")
    let container = try XCTUnwrap(appDataContainer(), "找不到 app 的数据容器")
    app.terminate()
    try seedAlertsAndDrawings(into: container)
    note("已写入 50 提醒（10 条件）+ 100 画线 → \(container.lastPathComponent)")
    var runs: [TimeInterval] = []
    for i in 0..<3 { runs.append(relaunchMeasured("满载启动 \(i + 1)").live) }
    note("满载启动→K线 三次 \(runs.map { String(format: "%.2f", $0) }) 对照 \(String(format: "%.2f", bare.live))")

    // BTC 上 50 条、ETH 上 50 条。
    open("BTCUSDT")
    XCTAssertTrue(waitUntil(timeout: Self.short) { (self.chartInfo()["drawingCount"] as? Int ?? 0) == 50 },
                  "BTC 上不是 50 条线：\(chartInfo()["drawingCount"] ?? "?")")
    let h0 = hangs()
    for _ in 0..<6 { canvas.swipeRight(); usleep(100_000) }
    canvas.pinch(withScale: 0.5, velocity: -1); canvas.pinch(withScale: 2, velocity: 1)
    reportHangs("BTC 50 线上拖 / 捏", since: h0)
    shot("规模-BTC-50线")
    open("ETHUSDT")
    XCTAssertTrue(waitUntil(timeout: Self.short) { (self.chartInfo()["drawingCount"] as? Int ?? 0) == 50 },
                  "ETH 上不是 50 条线：\(chartInfo()["drawingCount"] ?? "?")")

    // 自选 200 行：翻到底再翻回来。
    XCTAssertTrue(app.openFavorites())
    XCTAssertTrue(app.buttons["favorites.open." + testInstrumentKey(Self.top200[0])].waitForExistence(timeout: Self.long))
    let h1 = hangs()
    let tScroll = Date()
    for _ in 0..<25 { app.swipeUp(velocity: .fast) }
    // 自选页按类别分胶囊（加密 / 贵金属 / 美股 / 其他），默认在「加密」：200 只里最后一只加密是 DEEP
    // （INTW 是美股，在「美股」那一格里）。
    let lastCrypto = "DEEPUSDT"
    let tail = app.buttons["favorites.open." + testInstrumentKey(lastCrypto)]
    for _ in 0..<10 where !tail.exists { app.swipeUp(velocity: .fast) }
    XCTAssertTrue(tail.exists, "「加密」翻到底没见到 \(lastCrypto)")
    shot("规模-自选-底")
    for _ in 0..<35 { app.swipeDown(velocity: .fast) }
    note("自选 200 行来回翻 \(Int(Date().timeIntervalSince(tScroll)))s")
    reportHangs("自选 200 行滚动", since: h1)
    // 从底部那一只进图。
    // 美股那一格里有 INTW（200 只的最后一只）。
    let stocks = app.buttons.matching(NSPredicate(format: "label == '美股'")).firstMatch
    if stocks.exists {
      stocks.tap()
      let intw = app.buttons["favorites.open." + testInstrumentKey(Self.top200[199])]
      for _ in 0..<10 where !intw.exists { app.swipeUp(velocity: .fast) }
      XCTAssertTrue(intw.exists, "「美股」里翻不到 \(Self.top200[199])")
      app.buttons.matching(NSPredicate(format: "label == '加密'")).firstMatch.tap()
    }
    for _ in 0..<35 where !tail.exists { app.swipeUp(velocity: .fast) }
    tail.tap()
    XCTAssertTrue(waitUntil(timeout: Self.long) { self.symbolOnChart() == lastCrypto }, "点 \(lastCrypto) 没进图：\(symbolOnChart())")

    // 总表 50 条：价格段在、条件那 10 条也在、翻得动。
    XCTAssertTrue(app.openMePage())
    let alertsRow = app.buttons[Ids.meAlerts]
    XCTAssertTrue(alertsRow.waitForExistence(timeout: Self.short))
    note("我的 › 全部预警 行文案：\(alertsRow.label)")
    XCTAssertTrue(app.tapMeRow(Ids.meAlerts))
    XCTAssertTrue(alertsPage.waitForExistence(timeout: Self.short), "总表没开出来")
    XCTAssertTrue(app.descendants(matching: .any)["alerts.section.price"].waitForExistence(timeout: 5), "总表没有价格段")
    let h2 = hangs()
    for _ in 0..<20 { app.swipeUp(velocity: .fast) }
    let condition = app.staticTexts.matching(NSPredicate(format: "label CONTAINS '资金费率' OR label CONTAINS '挂单墙' OR label CONTAINS '持仓'")).firstMatch
    XCTAssertTrue(condition.exists || { for _ in 0..<20 { app.swipeDown(velocity: .fast); if condition.exists { return true } }; return false }(),
                  "总表里翻不出条件提醒")
    reportHangs("总表 50 条滚动", since: h2)
    shot("规模-总表")
    back()
    XCTAssertEqual(app.state, .runningForeground)
  }

  // ------------------------------------------------------------ 5. 网络

  private func relaunch(outage start: Double, seconds: Double) {
    app.terminate()
    app.launchEnvironment["KANPAN_TEST_NET_OUTAGE"] = "\(Int(start)):\(Int(seconds))"
    app.launch()
    let chartTab = app.buttons[Ids.bottomChart]
    if chartTab.waitForExistence(timeout: 5), !app.symbolLabel.exists { chartTab.tap() }
    XCTAssertTrue(app.symbolLabel.waitForExistence(timeout: Self.long), "断网窗口下顶栏没出来")
  }

  private func quoteTime() -> Double { Double(quote()["time"] ?? "") ?? 0 }

  func testNetworkOfflineLaunchThenRecover() throws {
    executionTimeAllowance = 600
    XCTAssertTrue(waitForLiveChart())
    let now = Date().timeIntervalSince1970
    relaunch(outage: now - 1, seconds: 25)
    dwell(4)
    let offlineBars = chartInfo()["bars"] as? Int ?? 0
    shot("网络-断网启动")
    note("断网启动 4s 后 bars=\(offlineBars)（有缓存就非 0）顶栏=\(quote())")
    XCTAssertEqual(app.state, .runningForeground, "断网启动 app 掉了")
    let end = now + 25
    XCTAssertTrue(waitUntil(timeout: 90) { Date().timeIntervalSince1970 > end && (self.chartInfo()["bars"] as? Int ?? 0) > 0 && self.quoteTime() > end * 1000 - 5000 },
                  "网回来 60 秒内图没活：bars=\(chartInfo()["bars"] ?? 0) quote=\(quote())")
    note("断网启动 → 恢复 用时 \(Int(Date().timeIntervalSince1970 - end))s（网回来之后）")
  }

  func testNetworkDropOnChartThenRestore() throws {
    executionTimeAllowance = 600
    XCTAssertTrue(waitForLiveChart())
    let start = Date().timeIntervalSince1970 + 25
    relaunch(outage: start, seconds: 30)
    XCTAssertTrue(waitForLiveChart(timeout: 25), "断网前图没活")
    while Date().timeIntervalSince1970 < start + 5 { dwell(1) }
    // 断网中：切个周期、开个面板，不许卡死。
    let h0 = hangs()
    app.tapIntervalChip("1h"); dwell(2)
    XCTAssertTrue(app.openIndicatorPage(), "断网中分析开不出来"); app.closeOpenPanel()
    shot("网络-图表页断网中")
    note("断网中 顶栏=\(quote()) bars=\(chartInfo()["bars"] ?? 0)")
    let end = start + 30
    XCTAssertTrue(waitUntil(timeout: 120) {
      Date().timeIntervalSince1970 > end && (self.chartInfo()["interval"] as? String) == "1h" && (self.chartInfo()["bars"] as? Int ?? 0) > 0 && self.quoteTime() > end * 1000
    }, "网回来后图 / 报价没恢复：\(chartInfo()["interval"] ?? "?") bars=\(chartInfo()["bars"] ?? 0) quote=\(quote())")
    note("图表页断网 30s → 恢复 用时 \(Int(Date().timeIntervalSince1970 - end))s")
    reportHangs("图表页断网", since: h0)
  }

  func testNetworkDropDuringReplay() throws {
    executionTimeAllowance = 600
    XCTAssertTrue(openClosedBTCTrade())
    let r = try XCTUnwrap(startReplay())
    // 在回放中途重开一次 app 太重；这里用「下一次启动」的断网窗口：重启进回放，窗口开在进回放之后。
    app.buttons["退出"].tap()
    _ = detailBar.waitForExistence(timeout: Self.short)
    let start = Date().timeIntervalSince1970 + 60
    relaunch(outage: start, seconds: 30)
    XCTAssertTrue(openClosedBTCTrade())
    _ = try XCTUnwrap(startReplay())
    while Date().timeIntervalSince1970 < start + 3 { dwell(1) }
    app.buttons["开仓处"].tap()
    XCTAssertTrue(waitUntil(timeout: Self.short) { (self.replayReport()?["last"] ?? 0) >= r["open"]! }, "断网中「开仓处」没跳")
    dragProgress(from: 0.3, to: 0.95, hold: 0.15)
    XCTAssertTrue(replayTitle.exists, "断网中拖进度回放没了")
    shot("网络-回放中断网")
    note("回放中断网 \(replayReport() ?? [:])")
    while Date().timeIntervalSince1970 < start + 32 { dwell(1) }
    app.buttons["退出"].tap()
    XCTAssertTrue(detailBar.waitForExistence(timeout: Self.short), "网回来后退不出回放")
    detailBar.buttons.firstMatch.tap()
    if app.buttons["review.back"].waitForExistence(timeout: Self.short) { app.buttons["review.back"].tap() }
    app.buttons[Ids.bottomChart].tap()
    XCTAssertTrue(waitUntil(timeout: 90) { self.quoteTime() > (start + 30) * 1000 }, "回放断网后回到图表页行情没恢复：\(quote())")
  }

  func testNetworkRouteToggleBackAndForth() throws {
    executionTimeAllowance = 600
    XCTAssertTrue(waitForLiveChart())
    let h0 = hangs()
    for i in 0..<6 {
      let choice = i % 2 == 0 ? "网关" : "直连"
      XCTAssertTrue(app.openSettingsFromMe(), "设置没开")
      let seg = app.buttons["settings.routePolicy." + choice]
      for _ in 0..<6 where !(seg.exists && seg.isHittable) { app.swipeUp(velocity: .slow) }
      XCTAssertTrue(seg.exists, "没有 \(choice)"); seg.tap()
      XCTAssertTrue(waitUntil(timeout: 3) { seg.isSelected }, "\(choice) 没选上")
      back()
      app.buttons[Ids.bottomChart].tap()
      let t = Date(), mark = Date().timeIntervalSince1970 * 1000
      XCTAssertTrue(waitUntil(timeout: 45) { self.quoteTime() > mark }, "切到\(choice)后 45 秒没来新报价：\(quote())")
      note("切到\(choice) → 首个新报价 \(String(format: "%.1f", Date().timeIntervalSince(t)))s")
    }
    reportHangs("直连 / 网关来回切 6 次", since: h0)
    // 收尾回直连（出厂）。
    XCTAssertTrue(app.openSettingsFromMe())
    let direct = app.buttons["settings.routePolicy.直连"]
    for _ in 0..<6 where !(direct.exists && direct.isHittable) { app.swipeUp(velocity: .slow) }
    direct.tap()
  }

  // ------------------------------------------------------------ 6. 登录 / 退登 10 次

  func testLoginLogoutTenTimes() throws {
    executionTimeAllowance = 1500
    XCTAssertTrue(waitForLiveChart())
    let user = Self.newName(); created.append(user)
    register(user)
    let h0 = hangs()
    var times: [String] = []
    for i in 0..<10 {
      let t = Date()
      logout()
      XCTAssertTrue(app.openFavorites(), "第 \(i + 1) 次退登后自选页进不去")
      login(user)
      times.append(String(format: "%.1f", Date().timeIntervalSince(t)))
      XCTAssertEqual(app.state, .runningForeground)
    }
    note("退登+登录 10 轮用时 \(times)")
    reportHangs("登录退登 10 轮", since: h0)
    app.buttons[Ids.bottomChart].tap()
    XCTAssertTrue(waitUntil(timeout: Self.long) { (self.chartInfo()["bars"] as? Int ?? 0) > 0 }, "10 轮之后图没了")
  }

  // ------------------------------------------------------------ 7. 从 settings-before-trim-2026-09-28 升级

  /// 老包（收设置项之前那个 tag）先在同一台模拟器、同一个存档档位上留下状态：三只自选、一条水平线、
  /// 一条价格提醒、图表设置里关倒计时开至今涨幅、设置里翻吸附与不锁屏、注册一个号并关掉「自动同步」
  /// （那一步在 /tmp/kanpan-oldtag 的 UpgradeSeedOldUITests 里做，不入库）。然后不卸载、直接跑这一条：
  /// 新包读老存档不崩，自选、画线、提醒一个不丢，号还登着，同步页没有「已暂停」、没有「自动同步」开关。
  /// 没有老包留下的状态文件就跳过——这条只在压测时串着老包跑。
  func testUpgradeFromBeforeTrimKeepsState() async throws {
    guard let state = Self.upgradeState else { throw XCTSkip("没有老包留下的状态（\(Self.upgradeStateFile)）") }
    executionTimeAllowance = 600
    created.append(state.user)
    XCTAssertEqual(app.state, .runningForeground, "新包读老存档启动就掉了")
    XCTAssertTrue(waitForLiveChart(), "升级后图没活")
    // 自选三只都在。
    XCTAssertTrue(app.openFavorites(), "升级后进不了自选页")
    for s in ["LINKUSDT", "ADAUSDT", "BTCUSDT"] {
      XCTAssertTrue(app.buttons["favorites.open." + testInstrumentKey(s)].waitForExistence(timeout: Self.short), "升级后自选里丢了 \(s)")
    }
    shot("升级-自选")
    app.buttons["favorites.open." + testInstrumentKey("BTCUSDT")].tap()
    XCTAssertTrue(waitUntil(timeout: Self.long) { self.symbolOnChart() == "BTCUSDT" })
    XCTAssertTrue(waitUntil(timeout: Self.short) { (self.chartInfo()["drawingCount"] as? Int ?? 0) >= 1 },
                  "升级后 BTC 上的水平线丢了：\(chartInfo()["drawingCount"] ?? "?")")
    // 提醒还在。
    XCTAssertTrue(app.tapMeRow(Ids.meAlerts))
    XCTAssertTrue(alertsPage.waitForExistence(timeout: Self.short), "升级后总表没开出来")
    XCTAssertFalse(app.descendants(matching: .any)["alerts.empty"].waitForExistence(timeout: 3), "升级后提醒全丢了")
    shot("升级-总表")
    back()
    // 号还登着、同步没暂停、没有「自动同步」开关。
    XCTAssertTrue(app.openAccountFromMe(), "升级后账号页开不出来")
    XCTAssertTrue(app.buttons["退出登录"].waitForExistence(timeout: Self.long), "升级后号掉了（没有「退出登录」）")
    XCTAssertFalse(app.switches["自动同步"].exists, "升级后账号页还有「自动同步」")
    XCTAssertFalse(app.staticTexts.matching(NSPredicate(format: "label CONTAINS '已暂停'")).firstMatch.exists, "升级后同步还写着已暂停")
    shot("升级-账号")
    note("升级：自选 3、画线 \(chartInfo()["drawingCount"] ?? "?")、提醒在、号 \(state.user) 登着")
    back()
    // 设置页能开、收掉的开关不在。
    XCTAssertTrue(app.openSettingsFromMe(), "升级后设置开不出来")
    for gone in ["settings.keepAwake", "settings.magnet", "settings.changeBasis"] {
      XCTAssertFalse(app.descendants(matching: .any)[gone].exists, "升级后 \(gone) 还在")
    }
    back()
    try? FileManager.default.removeItem(atPath: Self.upgradeStateFile)
  }
}
