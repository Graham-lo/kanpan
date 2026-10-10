import UIKit
import XCTest

// ============================================================ 交易员走查（深度审查 2026-10-04 · G 线）
//
// 不是断言型验收，是「以交易员的身份把每个模块、每个操作走一遍、每一步拍一张」的工具：
// 截图落到 `KANPAN_WALK_DIR`（默认 /tmp/kanpan-G/shots/<模块>/），文件名两位序号 + 步骤名。
// 每一步尽力而为：没走通只记一行「跳过」，不打断后面的步骤；关键事实（诊断 JSON 里的
// 十字线坐标、画线条数、副图个数……）以「事实|」行写进日志，走完对着截图逐张看。
//
// 平时不跑（不进界面矩阵），要走查时点名：
//   ONLY_TESTING=KanpanUITests/WalkthroughUITests ONLY_DEVICE="iPhone 17 Pro Max" bash Tools/ui-test.sh
@MainActor
class WalkthroughCase: KanpanUICase {
  let profile = UUID().uuidString
  /// 序号按模块记、跨同一类里的几个用例接着数，免得第二个用例把第一个的截图盖掉。
  nonisolated(unsafe) private static var counters: [String: Int] = [:]
  var module: String { "走查" }

  override var extraLaunchEnvironment: [String: String] {
    ["KANPAN_PERSISTENCE_PROFILE": profile,
     "KANPAN_TEST_QUICK": "5m,30m,1h,4h,1d,1w",
     "KANPAN_TEST_FAVORITES": "BTCUSDT,ETHUSDT,SOLUSDT,XRPUSDT,DOGEUSDT,SUIUSDT,NVDAUSDT,XAUUSDT",
     "KANPAN_EXCHANGE_FIXTURE": "1",
     "KANPAN_EXCHANGE_FIXTURE_KEY": "DEMOREADONLY7C31"]
  }

  override func setUp() async throws {
    XCUIDevice.shared.orientation = .portrait
    try await super.setUp()
    continueAfterFailure = true
  }

  override func tearDown() async throws {
    XCUIDevice.shared.orientation = .portrait
    try await super.tearDown()
  }

  private lazy var outDir: URL = {
    let base = ProcessInfo.processInfo.environment["KANPAN_WALK_DIR"] ?? "/tmp/kanpan-G/shots"
    return URL(fileURLWithPath: base, isDirectory: true).appendingPathComponent(module, isDirectory: true)
  }()

  func note(_ line: String) {
    print("走查|" + line)
    let a = XCTAttachment(string: line); a.name = "走查"; a.lifetime = .keepAlways; add(a)
  }

  func fact(_ what: String, _ value: Any) { note("事实|\(what)|\(value)") }

  func settle(_ seconds: TimeInterval = 0.8) {
    RunLoop.main.run(until: Date().addingTimeInterval(seconds))
  }

  func shot(_ page: String) {
    let index = (Self.counters[module] ?? 0) + 1
    Self.counters[module] = index
    let screenshot = XCUIScreen.main.screenshot()
    let name = String(format: "%02d-", index) + page
    let a = XCTAttachment(screenshot: screenshot); a.name = name; a.lifetime = .keepAlways; add(a)
    try? FileManager.default.createDirectory(at: outDir, withIntermediateDirectories: true)
    do { try screenshot.pngRepresentation.write(to: outDir.appendingPathComponent(name + ".png")) }
    catch { note("落盘失败|\(name)|\(error)") }
    note("拍|\(name)")
  }

  func any(_ id: String) -> XCUIElement {
    app.descendants(matching: .any).matching(identifier: id).firstMatch
  }

  func step(_ what: String, _ body: () -> Bool) {
    if !body() { note("跳过|\(what)") }
  }

  func backToChart() {
    app.closeOpenPanel()
    let tab = app.buttons[Ids.bottomChart]
    if tab.waitForExistence(timeout: 5) { tab.tap() }
    _ = app.buttons[Ids.intervalChart].waitForExistence(timeout: 8)
  }

  func systemBack() {
    let back = app.navigationBars.buttons.firstMatch
    if back.waitForExistence(timeout: 3) { back.tap() }
    settle(0.6)
  }

  var canvas: XCUIElement { app.otherElements["chart.canvas"] }

  /// 诊断坐标（图自己的 pt）→ 屏幕上的点。
  func canvasPoint(_ x: Double, _ y: Double) -> XCUICoordinate {
    let scale = canvas.frame.height / max(1, chartInfo()["height"] as? Double ?? canvas.frame.height)
    return canvas.coordinate(withNormalizedOffset: .zero).withOffset(CGVector(dx: x * scale, dy: y * scale))
  }

  func mainH() -> Double { chartInfo()["mainH"] as? Double ?? 300 }
  func plotW() -> Double { chartInfo()["plotW"] as? Double ?? 360 }

  func swipeDownPanel() { app.windows.firstMatch.swipeDown(velocity: .fast); settle(0.6) }

  func scrollUntilHittable(_ el: XCUIElement, up: Bool = true, tries: Int = 8) -> Bool {
    let window = app.windows.firstMatch
    for _ in 0..<tries where !(el.exists && el.isHittable) {
      let from = window.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: up ? 0.8 : 0.35))
      let to = window.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: up ? 0.5 : 0.65))
      from.press(forDuration: 0.05, thenDragTo: to)
    }
    return el.exists && el.isHittable
  }

  /// 搜索换品种：顶栏放大镜 → 输代号 → 点第一行。
  func switchSymbol(_ code: String) -> Bool {
    guard app.openSymbolSearch() else { return false }
    let q = app.textFields[Ids.searchQuery]
    guard q.waitForExistence(timeout: 5) else { return false }
    q.typeText(code)
    settle(1.5)
    let row = app.descendants(matching: .any).matching(NSPredicate(format: "identifier ENDSWITH %@",
                                                                   "/" + code)).matching(NSPredicate(format: "identifier BEGINSWITH %@", "symbols.row.")).firstMatch
    if row.waitForExistence(timeout: 6) { row.tap() }
    else {
      let rows = app.descendants(matching: .any).matching(NSPredicate(format: "identifier BEGINSWITH %@", "symbols.row."))
      note("换品种|\(code) 没有精确行，搜索结果：\(rows.allElementsBoundByIndex.prefix(6).map(\.identifier))")
      shot("换品种失败-\(code)")
      // 没有精确行就不乱点第一行（会换成别的品种）：收掉搜索、留在原图上，免得下一只接着输在这个框里。
      let cancel = app.buttons["search.cancel"]
      if cancel.exists { cancel.tap(); settle(0.6) }
      return false
    }
    let ok = waitUntil(timeout: 15) { (self.chartInfo()["symbol"] as? String ?? "").hasSuffix(code) }
    if !ok { note("换品种|\(code) 之后图上是 \(chartInfo()["symbol"] ?? "")") }
    return ok
  }
}

// ------------------------------------------------------------ 行情页：头部、周期条、手势

@MainActor
final class WalkthroughChartUITests: WalkthroughCase {
  override var module: String { "1-行情页" }

  func testHeaderIntervalsAndGestures() throws {
    _ = waitForLiveChart()
    settle(1.5)
    shot("首屏")
    fact("涨跌额", any("top.priceChange").label)
    fact("最新价", any("top.lastPrice").label)
    fact("涨跌", any("top.changePercent").label)

    // 周期条：「更多」弹层、钉住 / 取消钉住。
    step("更多弹层") {
      app.buttons[Ids.intervalMore].tap()
      guard app.buttons["period.row.1m"].waitForExistence(timeout: 8) else { return false }
      settle(0.6); shot("周期更多弹层")
      let pin = app.buttons[Ids.periodPin("15m")]
      if pin.exists { pin.tap(); settle(0.6); shot("钉住15m") ; fact("钉住15m后", pin.value ?? "") }
      // 六格已满：图钉进「挑一档换掉」，再点一格钉着的（4h）把它换成 15m。
      let swap = app.buttons["period.row.4h"]
      if swap.exists { fact("可换格文案", swap.label); swap.tap(); settle(0.6); shot("15m换掉4h") }
      let region = app.otherElements["PopoverDismissRegion"].firstMatch
      if region.exists { region.tap() } else { app.buttons[Ids.intervalMore].tap() }
      settle(0.8); shot("钉住后周期条")
      fact("周期条", app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "interval.chip.")).allElementsBoundByIndex.map(\.identifier))
      // 取消钉住
      app.buttons[Ids.intervalMore].tap()
      if pin.waitForExistence(timeout: 5) { pin.tap(); settle(0.6) }
      if region.exists { region.tap() } else { app.buttons[Ids.intervalMore].tap() }
      settle(0.8); shot("取消钉住后周期条（五格铺满）")
      fact("周期条-取消15m后", app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "interval.chip.")).allElementsBoundByIndex.map(\.identifier))
      // 把 4h 钉回去，后面的用例按原来六格走。
      app.buttons[Ids.intervalMore].tap()
      let pin4h = app.buttons[Ids.periodPin("4h")]
      if pin4h.waitForExistence(timeout: 5) { pin4h.tap(); settle(0.6) }
      if region.exists { region.tap() } else { app.buttons[Ids.intervalMore].tap() }
      settle(0.8); shot("取消钉住后周期条")
      fact("周期条-取消后", app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "interval.chip.")).allElementsBoundByIndex.map(\.identifier))
      return true
    }

    // 周期逐个切。
    for raw in ["5m", "1h", "1d", "1w"] {
      step("切\(raw)") {
        app.tapIntervalChip(raw)
        guard waitUntil(timeout: 15, { self.chartInfo()["interval"] as? String == raw }) else { return false }
        settle(1.5); shot("周期-\(raw)")
        return true
      }
    }
    // 月线从「更多」里点。
    step("月线") {
      app.buttons[Ids.intervalMore].tap()
      let row = app.buttons[Ids.periodRow("1M")]
      guard row.waitForExistence(timeout: 6) else { return false }
      row.tap()
      _ = waitUntil(timeout: 15) { self.chartInfo()["interval"] as? String == "1M" }
      settle(1.5); shot("周期-1M")
      return true
    }
    app.tapIntervalChip("1h")
    _ = waitUntil(timeout: 15) { self.chartInfo()["interval"] as? String == "1h" }
    settle(1.0)

    // 平移、捏合。
    step("平移") {
      let before = chartInfo()["latestRightGap"] ?? ""
      dragChartRight(); settle(0.8)
      shot("平移后")
      fact("平移前后右缝", "\(before) → \(chartInfo()["latestRightGap"] ?? "")")
      return true
    }
    step("捏合放大") {
      let before = chartInfo()["spacing"] as? Double ?? 0
      canvas.pinch(withScale: 2.0, velocity: 2.0); settle(0.8)
      shot("捏合放大")
      fact("放大前后间距", "\(before) → \(chartInfo()["spacing"] ?? "")")
      canvas.pinch(withScale: 0.4, velocity: -2.0); settle(0.8)
      shot("捏合缩小")
      fact("缩小后间距", chartInfo()["spacing"] ?? "")
      return true
    }
    _ = returnToLatest()
    settle(0.6)

    // 十字线：轻点出、按住上下拖，横线跟着手指不吸附收盘。
    step("十字线跟手") {
      let x = plotW() * 0.6, h = mainH()
      canvasPoint(x, h * 0.3).tap()
      guard waitUntil(timeout: 6, { self.chartInfo()["crosshair"] as? Bool == true }) else { return false }
      settle(0.4); shot("十字线-轻点")
      let y1 = chartInfo()["crossY"] as? Double ?? -1
      canvasPoint(x, h * 0.3).press(forDuration: 0.6, thenDragTo: canvasPoint(x, h * 0.75), withVelocity: .slow, thenHoldForDuration: 0.6)
      settle(0.3)
      let y2 = chartInfo()["crossY"] as? Double ?? -1
      shot("十字线-拖到下方")
      fact("十字线Y（手指 \(h * 0.3) → \(h * 0.75)）", "\(y1) → \(y2)")
      canvasPoint(x, h * 0.75).tap()
      settle(0.6)
      fact("再点一下后十字线", chartInfo()["crosshair"] ?? "")
      return true
    }
    step("长按") {
      canvasPoint(plotW() * 0.4, mainH() * 0.5).press(forDuration: 1.2)
      settle(0.5); shot("长按")
      fact("长按后十字线", chartInfo()["crosshair"] ?? "")
      canvasPoint(plotW() * 0.4, mainH() * 0.5).tap()
      settle(0.5)
      return true
    }
    // 副图区域上的十字线。
    step("副图十字线") {
      guard let panes = chartInfo()["panes"] as? [[String: Any]], let p = panes.first,
            let y = p["y"] as? Double, let h = p["h"] as? Double else { return false }
      canvasPoint(plotW() * 0.5, y + h / 2).tap()
      settle(0.5); shot("副图十字线")
      fact("副图十字线", "\(chartInfo()["crossPane"] ?? "") \(chartInfo()["crossY"] ?? "")")
      canvasPoint(plotW() * 0.5, y + h / 2).tap()
      return true
    }

    // 顶栏横滑扫图。
    step("顶栏横滑") {
      // 扫图只在「从列表进来」时有那份冻结的名单：先回自选页点 BTC 进来。
      // 上一步留着十字线：先轻点画布收掉，免得第一下点底栏只是收十字线。
      canvas.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.3)).tap(); settle(0.5)
      let btc = app.buttons["favorites.open." + testInstrumentKey("BTCUSDT")]
      for _ in 0..<3 where !btc.exists {
        app.buttons[Ids.bottomFavorites].tap()
        let crypto = app.buttons["favorites.group.加密"]
        if crypto.waitForExistence(timeout: 3) { crypto.tap(); settle(0.6) }
        _ = btc.waitForExistence(timeout: 5)
      }
      guard btc.exists else { note("横滑|自选页没有 BTC 行"); shot("横滑-没进自选"); backToChart(); return false }
      btc.tap(); settle(1.5)
      let quote = any("market.quote")
      guard quote.waitForExistence(timeout: 8) else { note("横滑|没有 market.quote"); backToChart(); return false }
      let before = chartInfo()["symbol"] as? String ?? ""
      quote.coordinate(withNormalizedOffset: CGVector(dx: 0.85, dy: 0.5))
        .press(forDuration: 0.05, thenDragTo: quote.coordinate(withNormalizedOffset: CGVector(dx: 0.1, dy: 0.5)))
      _ = waitUntil(timeout: 10) { (self.chartInfo()["symbol"] as? String ?? "") != before }
      settle(1.5); shot("横滑后")
      fact("横滑", "\(before) → \(chartInfo()["symbol"] ?? "")")
      quote.coordinate(withNormalizedOffset: CGVector(dx: 0.15, dy: 0.5))
        .press(forDuration: 0.05, thenDragTo: quote.coordinate(withNormalizedOffset: CGVector(dx: 0.9, dy: 0.5)))
      _ = waitUntil(timeout: 10) { (self.chartInfo()["symbol"] as? String ?? "") == before }
      settle(1.0); shot("横滑回来")
      return true
    }

    // 横屏再回来。
    step("横屏") {
      if !canvas.exists { backToChart() }
      XCUIDevice.shared.orientation = .landscapeLeft
      _ = waitUntil(timeout: 8) { self.canvas.frame.width > self.canvas.frame.height }
      settle(2.0); shot("横屏")
      fact("横屏画布", canvas.frame)
      XCUIDevice.shared.orientation = .portrait
      _ = waitUntil(timeout: 8) { self.canvas.frame.width < self.canvas.frame.height || self.app.buttons[Ids.intervalChart].isHittable }
      settle(2.0); shot("转回竖屏")
      fact("竖屏画布", canvas.frame)
      return true
    }
  }

  /// 极小价、极大价、几乎不动的品种的价格轴。
  func testPriceAxisExtremes() throws {
    _ = waitForLiveChart()
    // 一价平盘不拿 USDCUSDT 测：稳定币为底的永续在 RESTClient.parseExchangeInfo 里是故意排除的，搜不到。
    for code in ["1000SHIBUSDT", "BTCUSDT", "1000PEPEUSDT"] {
      step("价格轴-\(code)") {
        guard switchSymbol(code) else { return false }
        _ = waitForLiveChart()
        settle(2.0); shot("价格轴-\(code)")
        fact("\(code)", "top=\(chartInfo()["mainPriceTop"] ?? "") bottom=\(chartInfo()["mainPriceBottom"] ?? "") 头部=\(any("top.lastPrice").label)")
        app.tapIntervalChip("1w")
        settle(2.0); shot("价格轴-\(code)-周线")
        app.tapIntervalChip("1h")
        settle(0.8)
        return true
      }
    }
  }
}

// ------------------------------------------------------------ 分析面板、指标、图表设置、分享、记一笔

@MainActor
final class WalkthroughPanelsUITests: WalkthroughCase {
  override var module: String { "2-面板" }

  func testIndicatorsSettingsShareNote() throws {
    _ = waitForLiveChart()
    settle(1.0)
    step("分析面板") {
      guard app.openIndicatorPage() else { return false }
      settle(); shot("分析面板")
      fact("副图（开前）", chartInfo()["subs"] ?? "")
      for id in ["MACD", "RSI", "KDJ", "WR", "OBV"] {
        let sw = app.buttons[Ids.indicatorSwitch(id)]
        if !sw.exists || !sw.isHittable { _ = scrollUntilHittable(sw) }
        guard sw.exists else { note("没有开关|\(id)"); continue }
        sw.tap(); settle(0.6)
        fact("点 \(id) 后副图", chartInfo()["subs"] ?? "")
      }
      shot("分析面板-点了五个副图")
      let toast = app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "最多")).firstMatch
      fact("满三个提示", toast.exists ? toast.label : "无")
      for id in ["EMA", "BOLL"] {
        let sw = app.buttons[Ids.indicatorSwitch(id)]
        if !sw.exists || !sw.isHittable { _ = scrollUntilHittable(sw, up: false) }
        if sw.exists { sw.tap(); settle(0.5); fact("点主图 \(id) 后叠加", chartInfo()["overlays"] ?? "") }
      }
      shot("分析面板-主图叠加")
      _ = scrollUntilHittable(app.buttons["indicator.switch.ORDERFLOW"])
      settle(0.5); shot("分析面板-下半")
      app.closeOpenPanel()
      settle(1.0); shot("三副图下的行情页")
      return true
    }
    backToChart()

    step("指标参数") {
      openIndicatorEditor()
      settle(); shot("指标参数编辑")
      let field = app.textFields["indicator.param.0.field"]
      if field.waitForExistence(timeout: 5) {
        field.tap()
        field.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: 4) + "21")
        settle(0.5); shot("指标参数-改成21")
        let save = app.buttons["indicator.save"]
        if save.exists { save.tap(); settle(0.8) }
        fact("MA 参数", chartInfo()["ma"] ?? "")
      }
      if app.buttons["indicator.cancel"].exists { app.buttons["indicator.cancel"].tap() }
      swipeDownPanel()
      return true
    }
    backToChart()

    step("图表设置") {
      app.buttons[Ids.intervalChart].tap()
      guard app.buttons[Ids.chartPanelMarker].waitForExistence(timeout: 8) else { return false }
      settle(); shot("图表设置-上")
      let window = app.windows.firstMatch
      for i in 1...3 {
        window.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.85))
          .press(forDuration: 0.05, thenDragTo: window.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.45)))
        settle(0.5); shot("图表设置-下\(i)")
      }
      fact("图表设置按钮", app.buttons.allElementsBoundByIndex.filter { $0.isHittable }.map { $0.identifier.isEmpty ? $0.label : $0.identifier }.prefix(60).joined(separator: ","))
      fact("图表设置开关", app.switches.allElementsBoundByIndex.map(\.label).joined(separator: ","))
      _ = app.closeChartPanel()
      return true
    }
    backToChart()

    step("分享") {
      // 2026-10-08 起「分享」在顶栏「⋯」菜单里。
      guard app.openTopMenuItem(Ids.topShare, timeout: 5) else { return false }
      settle(1.5); shot("分享")
      let close = app.buttons["share.exit"]
      if close.exists { close.tap() } else { swipeDownPanel() }
      settle(0.8)
      return true
    }
    backToChart()

    step("记一笔") {
      // 2026-10-08 起「记一笔」在顶栏「⋯」菜单里。
      guard app.openTopMenuItem(Ids.topNote, timeout: 5) else { return false }
      guard app.buttons["记下"].waitForExistence(timeout: 10) else { shot("记一笔-没开出"); return false }
      settle(1.0); shot("记一笔-取景卡")
      app.buttons["记下"].tap(); settle(1.5); shot("记一笔-记下后")
      if app.buttons["记下"].exists { swipeDownPanel() }
      return true
    }
    backToChart()
  }
}

// ------------------------------------------------------------ 画线：十二把逐一画、选中、拖动、样式、锁定、删除

@MainActor
final class WalkthroughDrawingUITests: WalkthroughCase {
  override var module: String { "3-画线" }

  private let tools: [(String, Int)] = [
    ("hline", 1), ("trend", 2), ("vline", 1), ("channel", 3),
    ("fibonacci", 2), ("fibExtension", 3), ("measure", 2), ("note", 1),
    ("anchoredVWAP", 1), ("fixedVolumeProfile", 2), ("anchoredVolumeProfile", 1), ("position", 3),
  ]

  private func openTools() -> Bool {
    for _ in 0..<2 {
      app.buttons["draw.tools"].tap()
      if app.buttons["draw.sheet.done"].waitForExistence(timeout: 5) { return true }
    }
    return false
  }

  func testEveryToolAndEditing() throws {
    _ = waitForLiveChart()
    XCTAssertTrue(app.enterDrawingInPortrait(), "没能进入竖屏画线态")
    settle(1.0); shot("竖屏画线态")
    let w = plotW(), h = mainH()
    for (i, (kind, n)) in tools.enumerated() {
      step("画-\(kind)") {
        guard openTools() else { return false }
        if i == 0 { settle(0.6); shot("工具面板") }
        let tool = app.buttons["draw.tool.\(kind)"]
        if !tool.isHittable { _ = scrollUntilHittable(tool) }
        guard tool.exists else { return false }
        tool.tap(); settle(0.5)
        let before = chartInfo()["drawingCount"] as? Int ?? 0
        // 每把工具在图上不同的一片区域里点 n 下，免得点到已有的线上变成选中。
        let col = Double(i % 3), row = Double(i / 3)
        let x0 = w * (0.12 + 0.28 * col), y0 = h * (0.12 + 0.2 * row)
        let pts: [(Double, Double)] = [(x0, y0), (x0 + w * 0.14, y0 + h * 0.08), (x0 + w * 0.2, y0 + h * 0.03)]
        for k in 0..<n { canvasPoint(pts[k].0, pts[k].1).tap(); settle(0.35) }
        if kind == "note" {
          let text = app.textViews["draw.note.text"].exists ? app.textViews["draw.note.text"] : app.textFields["draw.note.text"]
          if text.waitForExistence(timeout: 3) { text.tap(); text.typeText("走查") ; settle(0.3) }
          let save = app.buttons["draw.save"]
          if save.exists { save.tap() }
        }
        let ok = waitUntil(timeout: 4) { (self.chartInfo()["drawingCount"] as? Int ?? 0) == before + 1 }
        settle(0.5); shot("画-\(kind)")
        fact("画 \(kind)", "条数 \(before) → \(chartInfo()["drawingCount"] ?? "")，ok=\(ok)")
        // 落完会选中它，点空白取消选中。
        canvasPoint(w * 0.95, h * 0.95).tap(); settle(0.4)
        return ok
      }
    }
    fact("全部画线", chartInfo()["drawingKinds"] ?? "")
    shot("十二把都画完")

    // 选中趋势线：拖动、换色、锁定、删除。
    step("选中拖动") {
      guard let kinds = chartInfo()["drawingKinds"] as? [String], let idx = kinds.firstIndex(of: "trend"),
            let anchors = chartInfo()["drawingAnchors"] as? [[[String: Double]]] else { return false }
      let before = anchors[idx]
      // 趋势线画在第 0 行第 1 列：两端中点上点一下。
      let x = w * (0.12 + 0.28) + w * 0.07, y = h * 0.12 + h * 0.04
      canvasPoint(x, y).tap()
      guard app.buttons["draw.style"].waitForExistence(timeout: 4) else { shot("选中失败"); return false }
      settle(0.4); shot("选中趋势线")
      canvasPoint(x, y).press(forDuration: 0.3, thenDragTo: canvasPoint(x + 30, y + 40), withVelocity: .slow, thenHoldForDuration: 0.2)
      settle(0.6); shot("拖动后")
      let after = (chartInfo()["drawingAnchors"] as? [[[String: Double]]])?[idx] ?? []
      fact("拖动锚点", "\(before) → \(after)")
      if app.openDrawingStyleSheet(pick: "down") {
        settle(0.5); shot("样式表")
        app.buttons["draw.save"].tap(); settle(0.6)
      }
      fact("颜色", chartInfo()["drawingColors"] ?? "")
      return true
    }
    step("锁定") {
      guard let kinds = chartInfo()["drawingKinds"] as? [String], let idx = kinds.firstIndex(of: "trend"),
            let anchors = chartInfo()["drawingAnchors"] as? [[[String: Double]]], anchors[idx].count == 2 else { return false }
      _ = anchors
      shot("锁定前")
      fact("锁定状态", chartInfo()["drawingLocked"] ?? "")
      return true
    }
    step("删除") {
      let del = app.buttons["draw.delete"]
      guard del.waitForExistence(timeout: 3) else { return false }
      let before = chartInfo()["drawingCount"] as? Int ?? 0
      del.tap(); settle(0.6)
      shot("删除后")
      fact("删除", "\(before) → \(chartInfo()["drawingCount"] ?? "")")
      return true
    }
    step("画线列表左滑删") {
      guard app.openDrawList() else { return false }
      settle(0.8); shot("画线列表")
      let rows = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "draw.object."))
      guard rows.firstMatch.waitForExistence(timeout: 5) else { return false }
      let before = chartInfo()["drawingCount"] as? Int ?? 0
      rows.firstMatch.swipeLeft(); settle(0.6); shot("画线列表-左滑")
      let delete = app.buttons["删除"].firstMatch
      if delete.exists { delete.tap(); settle(0.6) }
      shot("画线列表-删除后")
      fact("左滑删", "\(before) → \(chartInfo()["drawingCount"] ?? "")")
      let done = app.buttons["draw.sheet.done"]
      if done.exists { done.tap() } else { swipeDownPanel() }
      return true
    }
    step("回撤提醒铃铛") {
      // 选中回撤线，看「叫我」胶囊与铃铛。
      guard let kinds = chartInfo()["drawingKinds"] as? [String], kinds.contains("fibonacci") else { return false }
      let x = w * 0.12 + w * 0.07, y = h * 0.32 + h * 0.04
      canvasPoint(x, y).tap(); settle(0.6)
      shot("选中回撤")
      let chip = app.buttons["alert.line"]
      if chip.waitForExistence(timeout: 4) {
        fact("回撤胶囊", chip.label)
        chip.tap(); settle(0.8); shot("回撤开提醒")
        fact("挂铃铛的线", chartInfo()["drawingAlerted"] ?? "")
      }
      let opened = chip.exists
      canvasPoint(w * 0.95, h * 0.95).tap(); settle(0.6)
      shot("回撤提醒-取消选中后")
      return opened
    }
    let finish = app.buttons["draw.finish"]
    if finish.exists { finish.tap(); settle(1.0) }
    shot("退出画线态")
  }

  /// E-1 配套的肉眼验收：图上只有一把回撤、画在已经走完的那段行情上，开提醒后
  /// 提醒的那一级往右延到最新价、铃铛仍挂在画出来的右锚点上。
  func testRetracementAlertOnPastSegment() throws {
    _ = waitForLiveChart()
    XCTAssertTrue(app.enterDrawingInPortrait(), "没能进入竖屏画线态")
    let w = plotW(), h = mainH()
    step("画回撤") {
      guard openTools() else { return false }
      let tool = app.buttons["draw.tool.fibonacci"]
      if !tool.isHittable { _ = scrollUntilHittable(tool) }
      guard tool.exists else { return false }
      tool.tap(); settle(0.5)
      canvasPoint(w * 0.15, h * 0.25).tap(); settle(0.35)
      canvasPoint(w * 0.45, h * 0.7).tap(); settle(0.6)
      return waitUntil(timeout: 4) { (self.chartInfo()["drawingCount"] as? Int ?? 0) == 1 }
    }
    step("回撤开提醒") {
      let chip = app.buttons["alert.line"]
      if !chip.waitForExistence(timeout: 3) { canvasPoint(w * 0.3, h * 0.475).tap() }
      guard chip.waitForExistence(timeout: 4) else { shot("回撤-没有提醒胶囊"); return false }
      fact("回撤胶囊", chip.label)
      shot("回撤-选中")
      chip.tap(); settle(0.8)
      shot("回撤-开了提醒")
      fact("挂铃铛的线", (chartInfo()["drawingAlerted"] as? [Any]).map { "\($0)" } ?? "\(chartInfo()["drawingAlerted"] ?? "")")
      canvasPoint(w * 0.95, h * 0.95).tap(); settle(0.8)
      shot("回撤-提醒-取消选中")
      return true
    }
  }
}

// ------------------------------------------------------------ 提醒

@MainActor
final class WalkthroughAlertsUITests: WalkthroughCase {
  override var module: String { "4-提醒" }

  func testCreateAndListAlerts() throws {
    _ = waitForLiveChart()
    settle(1.0)
    step("十字线建提醒") {
      canvasPoint(plotW() * 0.7, mainH() * 0.25).tap()
      guard waitUntil(timeout: 6, { self.chartInfo()["crosshair"] as? Bool == true }) else { return false }
      settle(0.4); shot("十字线-创建提醒胶囊")
      let chip = app.buttons["chart.crosshair.alert"]
      guard chip.waitForExistence(timeout: 5) else { return false }
      fact("胶囊文案", chip.label)
      chip.tap()
      guard app.textFields["alerts.new.price"].waitForExistence(timeout: 8) else { return false }
      settle(); shot("创建提醒页")
      _ = scrollUntilHittable(app.buttons["alerts.new.create"])
      shot("创建提醒页-下半")
      app.buttons["alerts.new.create"].tap(); settle(1.2)
      shot("创建后")
      if app.textFields["alerts.new.price"].exists { systemBack() }
      return true
    }
    backToChart()
    step("全部预警") {
      guard app.openMePage(), app.tapMeRow(Ids.meAlerts) else { return false }
      guard any("alerts.page").waitForExistence(timeout: 10) else { return false }
      settle(); shot("全部预警")
      let draw = app.buttons["alerts.section.画线"]
      if draw.exists { draw.tap(); settle(0.6); shot("全部预警-画线") }
      return true
    }
  }
}

// ------------------------------------------------------------ 自选

@MainActor
final class WalkthroughFavoritesUITests: WalkthroughCase {
  override var module: String { "5-自选" }

  func testFavoritesOperations() throws {
    _ = waitForLiveChart()
    step("自选页") {
      guard app.openFavorites() else { return false }
      // 种子自选不带分类：分类要等品种表到了（`SymbolPickerModel.setCatalog` → 按资产类型归类）才开出来。
      // 新测试子树没有品种表缓存，机器忙时现拉要好几秒，固定睡 2 秒就会撞上「还没分类」那一刻。
      _ = app.buttons["favorites.group.加密"].waitForExistence(timeout: 20)
      settle(1.0); shot("自选-默认")
      for g in ["加密", "美股"] {
        let b = app.buttons["favorites.group.\(g)"]
        if b.exists { b.tap(); settle(1.2); shot("自选-\(g)") }
      }
      app.buttons["favorites.group.加密"].tap(); settle(0.8)
      return true
    }
    step("搜索") {
      let add = app.buttons["favorites.add"]
      guard add.waitForExistence(timeout: 5) else { return false }
      add.tap(); settle(1.0)
      shot("自选-搜索浮层（键盘不该自己起）")
      fact("键盘在不在", app.keyboards.firstMatch.exists)
      let q = app.textFields[Ids.searchQuery]
      if q.exists { q.tap(); settle(0.8); shot("自选-搜索键盘"); fact("键盘", app.keyboards.firstMatch.exists ? "在" : "不在")
        q.typeText("ADA"); settle(1.5); shot("自选-搜索ADA") }
      let star = app.descendants(matching: .any).matching(NSPredicate(format: "identifier BEGINSWITH %@ AND identifier CONTAINS %@", "symbols.star.", "ADAUSDT")).firstMatch
      if star.exists { star.tap(); settle(0.6); shot("自选-搜索里加星") }
      let cancel = app.buttons["search.cancel"]
      if cancel.exists { cancel.tap() }
      settle(1.0); shot("自选-加了ADA")
      return true
    }
    step("滚动位置") {
      let feed = any("favorites.feed")
      feed.swipeUp(); settle(0.8)
      shot("自选-滚下去")
      let rows = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "favorites.open."))
      func topRow() -> String {
        rows.allElementsBoundByIndex.filter { $0.isHittable }.min { $0.frame.minY < $1.frame.minY }?.identifier ?? ""
      }
      let before = topRow()
      app.buttons[Ids.bottomChart].tap(); settle(1.5)
      app.buttons[Ids.bottomFavorites].tap(); settle(1.5)
      shot("自选-离开再回来")
      fact("滚动位置（最上一行 离开前 → 回来后）", "\(before) → \(topRow())")
      return true
    }
    step("…菜单编辑") {
      let more = app.buttons["favorites.more"]
      guard more.waitForExistence(timeout: 5) else { return false }
      more.tap(); settle(0.6); shot("自选-…菜单")
      let edit = app.buttons["favorites.edit"]
      guard edit.waitForExistence(timeout: 4) else { return false }
      edit.tap(); settle(1.0); shot("自选-编辑态")
      shot("自选-编辑态里")
      let close0 = app.buttons["favorites.close"]
      if close0.exists { close0.tap() } else if app.buttons["完成"].exists { app.buttons["完成"].tap() }
      settle(0.8)
      // 拖动排序在列表上直接长按（不进编辑态）：把第四行拖到第一行上沿。加密那一类行最多。
      let crypto = app.buttons["favorites.group.加密"]
      if crypto.exists { crypto.tap(); settle(0.8) }
      let rows = app.descendants(matching: .any).matching(NSPredicate(format: "identifier BEGINSWITH %@", "favorites.open."))
      fact("拖前顺序", rows.allElementsBoundByIndex.map(\.identifier))
      if rows.count >= 4 {
        let lower = rows.element(boundBy: 3).frame, upper = rows.element(boundBy: 0).frame
        let origin = app.windows.firstMatch.coordinate(withNormalizedOffset: .zero)
        origin.withOffset(CGVector(dx: lower.midX, dy: lower.midY)).press(
          forDuration: 1, thenDragTo: origin.withOffset(CGVector(dx: upper.midX, dy: upper.minY)),
          withVelocity: .slow, thenHoldForDuration: 0.4)
        settle(0.8); shot("自选-拖动后")
        fact("拖后顺序", rows.allElementsBoundByIndex.map(\.identifier))
      }
      let close = app.buttons["favorites.close"]
      if close.exists { close.tap() } else if app.buttons["完成"].exists { app.buttons["完成"].tap() }
      settle(1.0); shot("自选-编辑完")
      fact("自选顺序", app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "favorites.open.")).allElementsBoundByIndex.map(\.identifier))
      return true
    }
    step("取消星") {
      let row = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "favorites.open.")).firstMatch
      guard row.exists else { return false }
      row.swipeLeft(); settle(0.6); shot("自选-左滑行")
      app.windows.firstMatch.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.95)).tap()
      return true
    }
  }

  override var extraLaunchEnvironment: [String: String] {
    var env = super.extraLaunchEnvironment
    if name.contains("Empty") { env["KANPAN_TEST_FAVORITES"] = "" }
    return env
  }

  func testFavoritesEmpty() throws {
    step("空自选") {
      guard app.openFavorites() else { return false }
      settle(2.0); shot("自选-空态")
      for g in ["加密", "美股"] {
        let b = app.buttons["favorites.group.\(g)"]
        if b.exists { b.tap(); settle(1.0); shot("自选-空态-\(g)") }
      }
      return true
    }
  }
}

// ------------------------------------------------------------ 板块

@MainActor
final class WalkthroughSectorsUITests: WalkthroughCase {
  override var module: String { "6-板块" }

  func testSectorPage() throws {
    step("板块") {
      app.openSectors()
      guard app.otherElements["sector.page"].waitForExistence(timeout: 15) else { return false }
      let row = app.descendants(matching: .any).matching(NSPredicate(format: "identifier BEGINSWITH %@", "sector.row.")).firstMatch
      _ = waitUntil(timeout: 20) { row.exists }
      settle(1.5); shot("板块-加密")
      let windows = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "sector.window."))
      fact("窗口档", windows.allElementsBoundByIndex.map(\.identifier))
      for i in 0..<windows.count {
        windows.element(boundBy: i).tap(); settle(1.5); shot("板块-窗口\(i)")
      }
      any("sector.board").swipeUp(); settle(0.8); shot("板块-滚到下面")
      let us = app.buttons["sector.market.us"]
      if us.exists { us.tap(); settle(2.0); shot("板块-美股") }
      let rows = app.descendants(matching: .any).matching(NSPredicate(format: "identifier BEGINSWITH %@", "sector.row."))
      fact("美股板块行", rows.allElementsBoundByIndex.map(\.identifier))
      if rows.count > 0 {
        rows.element(boundBy: rows.count - 1).tap()
        if app.buttons["sector.list.back"].waitForExistence(timeout: 10) { settle(1.5); shot("板块-美股末行下钻"); app.buttons["sector.list.back"].tap(); settle(0.6) }
      }
      app.buttons["sector.market.crypto"].tap(); settle(1.0)
      if row.exists {
        row.tap()
        if app.buttons["sector.list.back"].waitForExistence(timeout: 10) {
          settle(1.5); shot("板块-下钻品种列表")
          let sym = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "sector.symbol.")).firstMatch
          if sym.exists { sym.tap(); settle(2.0); shot("板块-点进品种") }
        }
      }
      return true
    }
  }
}

// ------------------------------------------------------------ 我的：账号注册 / 退出 / 登录

@MainActor
final class WalkthroughAccountUITests: WalkthroughCase {
  override var module: String { "7-账号" }
  private let username = "test_" + String(UUID().uuidString.replacingOccurrences(of: "-", with: "").lowercased().prefix(10))
  private let password = "Testpass2026"

  override var extraLaunchEnvironment: [String: String] {
    var env = super.extraLaunchEnvironment
    env["KANPAN_ACCOUNT_API_URL"] = TestAccounts.api
    return env
  }

  override func tearDown() async throws {
    await TestAccounts.delete(username, password: password, api: TestAccounts.api)
    try await super.tearDown()
  }

  private func typeSlow(_ field: XCUIElement, _ text: String) {
    field.tap()
    for ch in text { field.typeText(String(ch)) }
    let strong = app.buttons["GenerateStrongPasswordButton"]
    if strong.exists { app.buttons["xmark"].firstMatch.tap() }
  }

  func testRegisterLogoutLogin() throws {
    _ = waitForLiveChart()
    step("注册") {
      guard app.openAccountFromMe() else { return false }
      settle(); shot("账号-未登录")
      let sw = app.buttons["account.switch"]
      if sw.exists, !app.buttons["account.submit"].label.contains("注册") { sw.tap(); settle(0.5) }
      shot("账号-注册表单")
      let email = app.textFields["account.email"]
      guard email.waitForExistence(timeout: 5) else { return false }
      typeSlow(email, username)
      typeSlow(app.secureTextFields["account.password"], password)
      settle(0.4); shot("账号-填好")
      app.buttons["account.submit"].tap()
      let ok = waitUntil(timeout: 20) { !self.app.buttons["account.submit"].exists }
      settle(2.0); shot("账号-注册后")
      if app.staticTexts["account.error"].exists { fact("注册错误", app.staticTexts["account.error"].label) }
      return ok
    }
    step("同步浮层") {
      _ = app.openMePage()
      settle(1.0); shot("我的-已登录")
      fact("账号行", app.buttons[Ids.meAccount].label)
      return true
    }
    step("导出") {
      guard app.openAccountFromMe() else { return false }
      settle(0.8); shot("账号页-已登录")
      let export = app.buttons["account.export"]
      if export.exists { export.tap(); settle(2.0); shot("导出"); swipeDownPanel()
        if app.buttons["关闭"].exists { app.buttons["关闭"].tap() } }
      return true
    }
    step("朋友") {
      guard app.openFriendsFromMe() else { return false }
      settle(1.0); shot("朋友-已登录")
      return true
    }
    step("退出") {
      guard app.openAccountFromMe() else { return false }
      let exit = app.buttons["退出登录"]
      guard exit.waitForExistence(timeout: 10) else { shot("账号页-找不到退出"); return false }
      _ = scrollUntilHittable(exit)
      shot("账号页-退出登录")
      exit.tap()
      let closed = waitUntil(timeout: 30) { !self.app.accountView.exists }
      settle(2.0); shot("退出后（照设计回行情页）")
      _ = app.openMePage(); settle(1.0); shot("退出后-我的")
      fact("退出后账号行", any(Ids.meAccount).label)
      return closed
    }
    step("登录") {
      if !app.textFields["account.email"].exists { guard app.openAccountFromMe() else { return false } }
      guard app.textFields["account.email"].waitForExistence(timeout: 8) else { shot("登录-没有表单"); return false }
      let sw = app.buttons["account.switch"]
      if app.buttons["account.submit"].label.contains("注册"), sw.exists { sw.tap(); settle(0.5) }
      shot("登录表单")
      typeSlow(app.textFields["account.email"], username)
      typeSlow(app.secureTextFields["account.password"], password)
      app.buttons["account.submit"].tap()
      let ok = waitUntil(timeout: 20) { !self.app.buttons["account.submit"].exists }
      settle(2.0); shot("登录后")
      return ok
    }
  }
}

// ------------------------------------------------------------ 我的：皮肤 / 涨跌色 / 深浅 / 线路 / 交易所 / 复盘

@MainActor
final class WalkthroughMeUITests: WalkthroughCase {
  override var module: String { "8-我的" }

  func testSkinsColorsRouteExchange() throws {
    _ = waitForLiveChart()
    step("我的") { guard app.openMePage() else { return false }; settle(1.5); shot("我的"); return true }
    step("设置") {
      guard app.openSettingsFromMe() else { return false }
      settle(); shot("设置-上")
      app.swipeUp(); settle(0.6); shot("设置-中")
      app.swipeUp(); settle(0.6); shot("设置-下")
      return true
    }
    step("涨跌色") {
      guard app.openSettingsFromMe() else { return false }
      let basis = app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "红涨")).firstMatch
      fact("涨跌色按钮", basis.exists ? basis.label : "无")
      if basis.exists { _ = scrollUntilHittable(basis); basis.tap(); settle(0.6); shot("设置-红涨绿跌")
        leaveSettings(); _ = waitForLiveChart(); settle(1.5); shot("行情页-红涨绿跌")
        _ = app.openSettingsFromMe()
        let back = app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "绿涨")).firstMatch
        if back.exists { _ = scrollUntilHittable(back); back.tap(); settle(0.5) }
      }
      return true
    }
    step("线路切网关") {
      guard app.openSettingsFromMe() else { return false }
      let gw = app.buttons["settings.routePolicy.网关"]
      guard gw.waitForExistence(timeout: 5) else { return false }
      _ = scrollUntilHittable(gw)
      gw.tap(); settle(0.6); shot("设置-网关")
      leaveSettings()
      _ = waitForLiveChart()
      let p1 = any("top.lastPrice").label
      settle(6.0)
      let p2 = any("top.lastPrice").label
      shot("行情页-网关")
      fact("网关下价格", "\(p1) → \(p2)；涨跌额 \(any("top.priceChange").label)")
      _ = app.openSettingsFromMe()
      let direct = app.buttons["settings.routePolicy.直连"]
      _ = scrollUntilHittable(direct)
      direct.tap(); settle(0.5)
      leaveSettings(); _ = waitForLiveChart(); settle(4.0)
      fact("直连回来价格", any("top.lastPrice").label)
      shot("行情页-直连回来")
      return true
    }
    for (skin, tag) in [("terra", "陶土"), ("classic", "经典"), ("sage", "青苔")] {
      for mode in ["浅色", "深色"] {
        step("\(tag)\(mode)") {
          guard app.openSettingsFromMe() else { return false }
          let card = app.buttons["display.theme." + skin]
          guard card.waitForExistence(timeout: 8) else { return false }
          for _ in 0..<4 where !card.isHittable { app.swipeDown() }
          card.tap()
          let m = app.buttons["display.mode.\(mode)"]
          if m.waitForExistence(timeout: 4) { m.tap() }
          settle(0.6)
          leaveSettings()
          _ = waitForLiveChart()
          settle(1.5); shot("行情页-\(tag)\(mode)")
          // 图表设置弹层（琉璃底 + 玻璃卡，高度跟内容走）。
          let chartPanel = app.buttons["interval.chart"]
          if chartPanel.waitForExistence(timeout: 5) {
            chartPanel.tap(); settle(1.0); shot("图表设置-\(tag)\(mode)")
            let done = app.buttons["panel.done"]
            if done.waitForExistence(timeout: 3) { done.tap(); settle(0.6) }
          }
          if app.openFavorites() { settle(1.2); shot("自选-\(tag)\(mode)") }
          app.openSectors(); settle(2.0); shot("板块-\(tag)\(mode)")
          if app.openMePage() { settle(1.0); shot("我的-\(tag)\(mode)") }
          backToChart()
          return true
        }
      }
    }
    step("交易所") {
      guard app.openMePage(), app.tapMeRow(Ids.meExchange) else { return false }
      guard any("me.exchange.page").waitForExistence(timeout: 10) else { return false }
      settle(1.5); shot("交易所")
      return true
    }
    step("复盘本") {
      guard app.openReviewBookFromMe() else { return false }
      settle(2.0); shot("复盘本")
      return true
    }
  }
}

// ------------------------------------------------------------ 系统路径：深链、前后台

@MainActor
final class WalkthroughSystemUITests: WalkthroughCase {
  override var module: String { "9-系统路径" }

  override var extraLaunchEnvironment: [String: String] {
    var env = super.extraLaunchEnvironment
    env["KANPAN_TEST_DEEPLINK"] = "hkline://symbol/ETHUSDT?interval=4h"
    return env
  }

  func testDeepLinkAndBackground() throws {
    step("深链") {
      _ = waitUntil(timeout: 20) { (self.chartInfo()["symbol"] as? String ?? "").hasSuffix("ETHUSDT") }
      settle(2.0); shot("深链-ETH-4h")
      fact("深链后", "\(chartInfo()["symbol"] ?? "") \(chartInfo()["interval"] ?? "")")
      return true
    }
    step("后台回前台") {
      let p1 = any("top.lastPrice").label
      XCUIDevice.shared.press(.home); settle(8)
      app.activate()
      _ = waitForLiveChart()
      settle(4.0); shot("回前台")
      fact("回前台价格", "\(p1) → \(any("top.lastPrice").label)")
      return true
    }
    step("系统打开提醒深链") {
      // 系统把 hkline:// 交给 app（运行中的那份），等同于桌面小组件 / 通知点进来。
      app.open(URL(string: "hkline://alerts")!)
      let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
      let open = springboard.buttons["打开"]
      if open.waitForExistence(timeout: 3) { open.tap() }
      let page = any("alerts.page")
      fact("提醒页", page.waitForExistence(timeout: 10))
      settle(1.0); shot("深链-全部预警")
      return page.exists
    }
    step("提醒深链关掉后回行情页") {
      swipeDownPanel()
      settle(1.0); shot("深链-关掉提醒后")
      return app.buttons[Ids.intervalChart].waitForExistence(timeout: 5)
    }
  }
}

// ------------------------------------------------------------ 探针：换到非自选品种后头部涨跌多久有数

@MainActor
final class WalkthroughTickerProbeUITests: WalkthroughCase {
  override var module: String { "探针-头部涨跌" }

  func testChangeLineFillsAfterSwitch() throws {
    _ = waitForLiveChart()
    for code in ["1000SHIBUSDT", "BTCUSDT", "1000PEPEUSDT"] {
      guard switchSymbol(code) else { note("跳过|换到\(code)"); continue }
      let start = Date()
      var filled: Double?
      while Date().timeIntervalSince(start) < 30 {
        let label = any("top.changePercent").label
        if !label.contains("—") && !label.isEmpty { filled = Date().timeIntervalSince(start); break }
        settle(0.5)
      }
      fact("\(code) 涨跌有数用时", filled.map { String(format: "%.1fs", $0) } ?? "30s 内一直是破折号")
      fact("\(code) 涨跌", any("top.changePercent").label)
      fact("\(code) 涨跌额", any("top.priceChange").label)
      shot(code)
    }
  }
}
