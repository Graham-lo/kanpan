import UIKit
import XCTest

// ============================================================ 回归压测（2026-10-05）
//
// 10-05 一天合进来的那一批（美元指数当一只品种、顶栏「对比＋」与铃铛「提醒」表、画线条只露常用几把、
// 横屏画线台默认画主图指标 + 眼睛 + 「主图˅」、横屏自己一份根宽与价格轴倍率、捏合手感）一次性压一遍。
// 用户：「全部做完后要压测，因为加入了新功能，可能有很多的 bug」。
//
// 一、交易员走查（`testWalk*`）：以人的身份带着真实任务把新旧功能各走一遍，每一步截图。
// 二、高频与边界（`testStress*`）：BTC ↔ 美元指数 ↔ ETH 各 20 次、周期狂切、对比 3 只 + 切周期 + 横屏 +
//     转屏 10 次、美元指数页与「提醒」表断网、杀进程重启后各项还在。
//
// 卡顿读 `main.hangs`（主线程晚过 100 ms 记一笔）；数据一行一行追加到 `<取证目录>/ui-数据.txt`，
// 截图落同一目录，文件名带机型。取证目录默认是入库的 `回归压测-2026-10-05/`，
// 复跑用 `TEST_RUNNER_KANPAN_STRESS_OUT=…` 指到别处。
@MainActor
final class StressRegression1005UITests: KanpanUICase {
  static let dxy = "macro/index/DXY"
  static let btc = "binance/usd_m/BTCUSDT"
  static let eth = "binance/usd_m/ETHUSDT"
  static let sol = "binance/usd_m/SOLUSDT"
  static let palette = [
    "hline", "trend", "vline", "channel", "fibonacci", "fibExtension", "measure", "note",
    "anchoredVWAP", "fixedVolumeProfile", "anchoredVolumeProfile", "position",
  ]

  static let outDir = URL(fileURLWithPath: ProcessInfo.processInfo.environment["KANPAN_STRESS_OUT"]
    ?? "/Users/mdd/zhk/kanpan/docs/acceptance/回归压测-2026-10-05", isDirectory: true)

  private let profile = UUID().uuidString
  /// 断网那条：开图后第 `outageDelay` 秒起断 `outageSeconds` 秒。启动环境在 setUp 里就要定，所以按启动时刻算。
  private let outageDelay = 45.0, outageSeconds = 40.0
  private lazy var outageStart = Date().timeIntervalSince1970 + outageDelay

  private var testName: String {
    name.components(separatedBy: " ").last?.trimmingCharacters(in: CharacterSet(charactersIn: "]")) ?? name
  }

  override var extraLaunchEnvironment: [String: String] {
    var env = ["KANPAN_PERSISTENCE_PROFILE": profile, "KANPAN_TEST_TOAST_SECONDS": "1"]
    let n = name
    if n.contains("BTCHeader") || n.contains("RapidIntervals") {
      env["KANPAN_TEST_DEEPLINK"] = "hkline://symbol/binance/usd_m/BTCUSDT?interval=15m"
    } else if n.contains("testStressHop") {
      env["KANPAN_TEST_FAVORITES"] = [Self.btc, Self.eth, Self.dxy].joined(separator: ",")
      env["KANPAN_TEST_DEEPLINK"] = "hkline://symbol/binance/usd_m/BTCUSDT?interval=15m"
    } else if n.contains("Compare3") {
      env["KANPAN_TEST_COMPARE_SYMBOLS"] = [Self.eth, Self.sol, Self.dxy].joined(separator: ",")
      env["KANPAN_TEST_DEEPLINK"] = "hkline://symbol/binance/usd_m/BTCUSDT?interval=1m"
      env["KANPAN_TEST_ROUTE_POLICY"] = "direct"
    } else if n.contains("testProbe") {
      env["KANPAN_TEST_FAVORITES"] = [Self.btc, Self.eth, Self.dxy].joined(separator: ",")
      env["KANPAN_TEST_DEEPLINK"] = "hkline://symbol/macro/index/DXY?interval=1h"
    } else if n.contains("testWalk1") {
      // 冷启动：什么都不给，和新装一样。
    } else {
      env["KANPAN_TEST_DEEPLINK"] = "hkline://symbol/macro/index/DXY?interval=1h"
    }
    // 重启那条要走产品真正的启动路径：测试档案下不给账号地址时 app 跳过账号桥、自选只在内存里，
    // 杀进程就没了（那是测试岔路，不是用户手上的行为）。指一个连不上的地址，账号桥照常装访客档案、落盘。
    if n.contains("testWalk6") { env["KANPAN_ACCOUNT_API_URL"] = "http://127.0.0.1:9" }
    if n.contains("Offline") { env["KANPAN_TEST_NET_OUTAGE"] = "\(Int(outageStart)):\(Int(outageSeconds))" }
    return env
  }

  override func setUp() async throws {
    XCUIDevice.shared.orientation = .portrait
    try? FileManager.default.createDirectory(at: Self.outDir, withIntermediateDirectories: true)
    try await super.setUp()
  }

  override func tearDown() async throws {
    if let app, (testRun?.failureCount ?? 0) > 0, app.state == .runningForeground {
      shot("失败现场")
      let a = XCTAttachment(string: String(describing: chartInfo())); a.name = "失败现场-读数"; a.lifetime = .keepAlways; add(a)
    }
    XCUIDevice.shared.orientation = .portrait
    if let app, app.state != .notRunning, app.state != .unknown { app.terminate() }
    try await super.tearDown()
  }

  // ------------------------------------------------------------ 取证

  private var deviceTag: String {
    let model = ProcessInfo.processInfo.environment["SIMULATOR_DEVICE_NAME"] ?? UIDevice.current.name
    return model.replacingOccurrences(of: "iPhone ", with: "").replacingOccurrences(of: " ", with: "")
  }

  private func note(_ line: String) {
    let text = "\(deviceTag)|\(testName)|\(line)"
    print("回归压测|" + text)
    let a = XCTAttachment(string: text); a.name = "压测数据"; a.lifetime = .keepAlways; add(a)
    let file = Self.outDir.appendingPathComponent("ui-数据.txt")
    let stamp = ISO8601DateFormatter().string(from: Date())
    let data = Data("\(stamp) \(text)\n".utf8)
    if let h = try? FileHandle(forWritingTo: file) { h.seekToEndOfFile(); h.write(data); try? h.close() }
    else { try? data.write(to: file) }
  }

  /// 横屏也取整屏（`XCUIScreen`），存下来是竖着的原始帧。
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

  /// 报这一段的卡顿：条数、最坏一次、超过 250 ms 的那几次。≥ 1 秒的卡死直接判红。
  @discardableResult
  private func reportHangs(_ label: String, since before: (count: Int, recent: [Int])) -> [Int] {
    let after = hangs()
    let n = max(0, after.count - before.count)
    let these = Array(after.recent.suffix(min(n, after.recent.count)))
    let over = these.filter { $0 > 250 }
    note("\(label) 卡顿>100ms=\(n) 最坏=\(these.max() ?? 0)ms >250ms=\(over)")
    XCTAssertFalse(these.contains { $0 >= 1000 }, "\(label)：有一次 ≥ 1 秒的卡死 \(these)")
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

  private func layout() -> [String: Double] {
    let probe = app.descendants(matching: .any).matching(identifier: "layout.diagnostics").firstMatch
    guard probe.exists, let text = probe.value as? String else { return [:] }
    var out: [String: Double] = [:]
    for pair in text.split(separator: ";") {
      let kv = pair.split(separator: "=", maxSplits: 1)
      if kv.count == 2, let v = Double(kv[1]) { out[String(kv[0])] = v }
    }
    return out
  }

  private func dwell(_ s: TimeInterval) { RunLoop.main.run(until: Date().addingTimeInterval(s)) }
  private var canvas: XCUIElement { app.otherElements["chart.canvas"] }
  private var symbol: String { chartInfo()["symbol"] as? String ?? "" }
  private var overlays: [String] { chartInfo()["overlays"] as? [String] ?? ["?"] }
  private var subs: [String] { chartInfo()["subs"] as? [String] ?? ["?"] }
  private func double(_ key: String) -> Double { (chartInfo()[key] as? NSNumber)?.doubleValue ?? 0 }

  private func waitChart(_ key: String, _ interval: String? = nil, minBars: Int = 20, _ seconds: TimeInterval = 45) -> Bool {
    waitUntil(timeout: seconds, poll: 0.5) {
      let d = self.chartInfo()
      return d["symbol"] as? String == key && (interval == nil || d["interval"] as? String == interval)
        && (d["bars"] as? Int ?? 0) >= minBars && ((d["lastClose"] as? NSNumber)?.doubleValue ?? 0) > 0
    }
  }

  // ------------------------------------------------------------ 动作

  /// 搜索框里换成 `text`。中文走剪贴板 + 「粘贴」（搜索框锁的是 ASCII 键盘），照 `DollarIndexUITests`。
  private func enter(_ text: String, into field: XCUIElement) {
    field.tap()
    let old = (field.value as? String) ?? ""
    if !old.isEmpty, old != field.placeholderValue {
      field.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: old.count + 2))
    }
    guard text.unicodeScalars.contains(where: { !$0.isASCII }) else { field.typeText(text); return }
    UIPasteboard.general.string = text
    defer { UIPasteboard.general.items = [] }
    for _ in 0..<2 {
      field.press(forDuration: 1.0)
      let paste = app.menuItems.matching(NSPredicate(format: "label IN %@", ["粘贴", "Paste"])).firstMatch
      let pasteButton = app.buttons.matching(NSPredicate(format: "label IN %@", ["粘贴", "Paste"])).firstMatch
      if paste.waitForExistence(timeout: 3) { paste.tap() } else if pasteButton.exists { pasteButton.tap() } else { continue }
      if waitUntil(timeout: 3, { (field.value as? String) == text }) { return }
    }
    field.typeText(text)
  }

  /// 顶栏放大镜 → 搜 `query` → 点 `key` 那一行进图。
  private func open(_ query: String, _ key: String, file: StaticString = #filePath, line: UInt = #line) {
    XCTAssertTrue(app.openSymbolSearch(), "顶栏放大镜没进搜索页", file: file, line: line)
    enter(query, into: app.textFields[Ids.searchQuery])
    let row = app.buttons["symbols.row." + key]
    XCTAssertTrue(row.waitForExistence(timeout: 30), "搜「\(query)」没出 \(key) 那一行", file: file, line: line)
    row.tap()
    XCTAssertTrue(waitUntil(timeout: 30) { self.symbol == key }, "点 \(key) 那一行没进它的图：\(chartInfo())",
                  file: file, line: line)
  }

  private func pick(_ raw: String, minBars: Int = 20, file: StaticString = #filePath, line: UInt = #line) {
    let t0 = Date()
    app.tapIntervalChip(raw)
    XCTAssertTrue(waitUntil(timeout: Self.long) {
      let d = self.chartInfo()
      return d["interval"] as? String == raw && (d["bars"] as? Int ?? 0) >= minBars
    }, "周期没落到 \(raw)：\(chartInfo())", file: file, line: line)
    note("\(code(symbol)) 切到 \(raw)：\(Int(Date().timeIntervalSince(t0) * 1000))ms bars=\(chartInfo()["bars"] ?? 0)")
  }

  private func code(_ key: String) -> String { key.split(separator: "/").last.map(String.init) ?? key }

  private func setSwitch(_ id: String, on: Bool, file: StaticString = #filePath, line: UInt = #line) {
    let s = app.buttons[Ids.indicatorSwitch(id)]
    for _ in 0..<6 where !s.exists || !s.isHittable { app.swipeUp(velocity: .slow) }
    XCTAssertTrue(s.waitForExistence(timeout: Self.short), "分析面板里没有 \(id) 开关", file: file, line: line)
    if (s.value as? String == "开") != on { s.tap() }
    XCTAssertTrue(waitUntil(timeout: Self.short) { (s.value as? String == "开") == on },
                  "\(id) 没切到 \(on ? "开" : "关")", file: file, line: line)
  }

  // 对比（顶栏「⋯ › 添加对比」→ 搜索页的对比模式；10-08 前是一颗加号圆片）

  private func openCompare(file: StaticString = #filePath, line: UInt = #line) {
    XCTAssertTrue(app.openTopMenuItem(Ids.topCompare, timeout: Self.short), "顶栏「⋯」菜单里没有「添加对比」", file: file, line: line)
    XCTAssertTrue(app.buttons["compare.done"].waitForExistence(timeout: Self.short), "「⋯ › 添加对比」没开出对比模式", file: file, line: line)
  }

  private func compareToggle(_ query: String, _ key: String, expect value: String, file: StaticString = #filePath, line: UInt = #line) {
    enter(query, into: app.textFields[Ids.searchQuery])
    let mark = app.buttons["compare.toggle." + key]
    XCTAssertTrue(mark.waitForExistence(timeout: 20), "对比搜「\(query)」没出 \(key)", file: file, line: line)
    mark.tap()
    XCTAssertTrue(waitUntil(timeout: 5) { mark.value as? String == value },
                  "\(key) 点完行尾不是「\(value)」：\(String(describing: mark.value))", file: file, line: line)
  }

  private func doneCompare(file: StaticString = #filePath, line: UInt = #line) {
    let done = app.buttons["compare.done"]
    XCTAssertTrue(done.waitForExistence(timeout: 5), file: file, line: line); done.tap()
    XCTAssertTrue(waitUntil(timeout: 10) { !self.app.textFields[Ids.searchQuery].exists }, "「完成」没收起对比搜索页",
                  file: file, line: line)
  }

  private var compareKeys: [String] { chartInfo()["compareKeys"] as? [String] ?? [] }

  // 提醒（铃铛 → 「提醒」表）

  private var bell: XCUIElement { app.buttons[Ids.topAlerts] }
  private var hubTab: XCUIElement { app.segmentedControls["alerts.hub.tab"] }

  private func openHub(file: StaticString = #filePath, line: UInt = #line) {
    XCTAssertTrue(bell.waitForExistence(timeout: Self.short), "顶栏没有铃铛", file: file, line: line)
    bell.tap()
    XCTAssertTrue(hubTab.waitForExistence(timeout: Self.short), "铃铛没开出「提醒」表", file: file, line: line)
  }

  private func hubPick(_ segment: String) {
    let button = hubTab.buttons[segment]
    XCTAssertTrue(button.waitForExistence(timeout: Self.short), "分段上没有「\(segment)」")
    button.tap()
    XCTAssertTrue(waitUntil(timeout: Self.short) { button.isSelected }, "没切到「\(segment)」")
  }

  private func closeHub() {
    let done = app.buttons[Ids.panelDone].firstMatch
    XCTAssertTrue(done.waitForExistence(timeout: Self.short), "「提醒」表没有关闭")
    done.tap()
    XCTAssertTrue(waitUntil(timeout: Self.short) { !self.hubTab.exists }, "「提醒」表没收起")
  }

  private func createFromHub(price: String, file: StaticString = #filePath, line: UInt = #line) {
    let create = app.buttons["alerts.hub.create"]
    XCTAssertTrue(create.waitForExistence(timeout: Self.short), "列表页底部没有「创建提醒」", file: file, line: line)
    create.tap()
    let field = app.textFields["alerts.new.price"]
    XCTAssertTrue(field.waitForExistence(timeout: Self.short), "没推出创建页", file: file, line: line)
    field.coordinate(withNormalizedOffset: CGVector(dx: 0.97, dy: 0.5)).tap()
    let old = (field.value as? String) ?? ""
    field.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: old.count + 2) + price)
    if app.keyboards.firstMatch.exists {
      app.buttons["完成"].firstMatch.tap()
      _ = app.keyboards.firstMatch.waitForNonExistence(timeout: 3)
    }
    let add = app.buttons["alerts.new.create"]
    XCTAssertTrue(waitUntil(timeout: Self.short) { add.isEnabled }, "创建页主按钮按不下去", file: file, line: line)
    for _ in 0..<3 where !add.isHittable { app.otherElements["alerts.new.page"].swipeUp() }
    add.tap()
    XCTAssertTrue(create.waitForExistence(timeout: Self.short), "建好没退回「提醒」表的列表页", file: file, line: line)
  }

  // 画线

  private func onBar() -> [String] { Self.palette.filter { app.buttons["draw." + $0].exists } }

  /// 条上从左到右的顺序。
  private func barOrder() -> [String] {
    onBar().map { ($0, app.buttons["draw." + $0].frame.minX) }.sorted { $0.1 < $1.1 }.map(\.0)
  }

  private func pickFromPanel(_ kind: String, file: StaticString = #filePath, line: UInt = #line) {
    app.buttons["draw.tools"].tap()
    let tile = app.buttons["draw.tool." + kind]
    XCTAssertTrue(tile.waitForExistence(timeout: Self.short), "「全部工具」没开出面板", file: file, line: line)
    tile.tap()
    XCTAssertTrue(waitUntil(timeout: Self.short) { !tile.exists }, "挑完工具面板没收起来", file: file, line: line)
  }

  private func mainPoint(x: Double, y: Double) -> XCUICoordinate {
    let info = chartInfo()
    let height = (info["height"] as? NSNumber)?.doubleValue ?? canvas.frame.height
    let mainH = (info["mainH"] as? NSNumber)?.doubleValue ?? canvas.frame.height * 0.6
    let scale = canvas.frame.height / max(1, height)
    return canvas.coordinate(withNormalizedOffset: .zero)
      .withOffset(CGVector(dx: canvas.frame.width * x, dy: mainH * scale * y))
  }

  private var drawingCount: Int { chartInfo()["drawingCount"] as? Int ?? -1 }

  private func enterLandscapeWorkbench(file: StaticString = #filePath, line: UInt = #line) {
    XCTAssertTrue(app.tapDrawEntry(), "分析面板里没有「画线」", file: file, line: line)
    XCTAssertTrue(app.landscapeMarker.waitForExistence(timeout: Self.long), "点「画线」没横过去", file: file, line: line)
    XCTAssertTrue(waitUntil(timeout: Self.long) { (self.chartInfo()["subs"] as? [String])?.isEmpty == true },
                  "画线横屏里还留着副图：\(subs)", file: file, line: line)
    dwell(1.0)
  }

  private func finishDrawing(file: StaticString = #filePath, line: UInt = #line) {
    let finish = app.buttons[Ids.drawFinish]
    XCTAssertTrue(finish.waitForExistence(timeout: Self.short), "画线栏上没有「完成」", file: file, line: line)
    finish.tap()
    XCTAssertTrue(app.buttons[Ids.bottomMe].waitForExistence(timeout: Self.long), "点「完成」没回竖屏行情页",
                  file: file, line: line)
  }

  private func applySkin(_ skin: String, _ mode: String) {
    XCTAssertTrue(app.openSettingsFromMe(), "「我的 › 设置」没进到设置页")
    let card = app.buttons["display.theme." + skin]
    XCTAssertTrue(card.waitForExistence(timeout: Self.short), "设置页上没有皮肤卡 \(skin)")
    for _ in 0..<3 {
      if (card.value as? String) == "已选" { break }
      if waitUntil(timeout: Self.short, { card.isHittable }) { card.tap() }
      else { card.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap() }
      if waitUntil(timeout: Self.short, { (card.value as? String) == "已选" }) { break }
    }
    XCTAssertEqual(card.value as? String, "已选", "皮肤没换到 \(skin)")
    let segment = app.buttons["display.mode." + mode]
    XCTAssertTrue(segment.waitForExistence(timeout: Self.short), "设置页上没有深浅档")
    if !segment.isSelected { segment.tap() }
    XCTAssertTrue(waitUntil(timeout: Self.short) { segment.isSelected }, "深浅没落在 \(mode)")
    app.buttons[Ids.bottomChart].tap()
    XCTAssertTrue(app.symbolLabel.waitForExistence(timeout: Self.short), "回不到行情页")
  }

  private func relaunch() {
    app.terminate()
    app.launch()
    let chartTab = app.buttons[Ids.bottomChart]
    if chartTab.waitForExistence(timeout: 5), !app.symbolLabel.exists { chartTab.tap() }
    XCTAssertTrue(app.symbolLabel.waitForExistence(timeout: Self.long), "重启后没回到行情页")
  }

  // ============================================================ 一、交易员走查

  /// 冷启动 → 自选三类 → 搜「美元」加美元指数 → 进图 → 1m / 1h / 1d / 更多里的 4h、1w →
  /// 分析里 MA / BOLL / MACD 开关。
  func testWalk1ColdStartFavoritesDollarIndexPeriodsIndicators() {
    executionTimeAllowance = 600
    XCTAssertTrue(waitForLiveChart(), "冷启动 \(Self.long)s 内图上没数据")
    note("冷启动品种 \(symbol) 周期 \(chartInfo()["interval"] ?? "?") bars=\(chartInfo()["bars"] ?? 0)")
    shot("走查01-冷启动")

    // 自选页：出厂分类。
    XCTAssertTrue(app.openFavorites(), "底栏「自选」没进自选页")
    let groups = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'favorites.group.'")).allElementsBoundByIndex
      .map { String($0.identifier.dropFirst("favorites.group.".count)) }
    note("自选出厂分类 \(groups)")
    // 一只自选都没有时，放大镜与「…」两颗圆片仍贴右边（10-05 回归压测前被挤到了屏幕正中）。
    let more = app.buttons["favorites.more"]
    XCTAssertGreaterThan(more.frame.maxX, app.frame.width - 32,
                         "空自选页「…」没贴右边：\(more.frame) 屏宽 \(app.frame.width)")
    XCTAssertFalse(groups.contains("指数"), "还没加美元指数，自选页就有「指数」一类：\(groups)")
    shot("走查02-自选出厂")
    app.buttons[Ids.bottomChart].tap()

    // 搜「美元」→ 星 → 进图。
    XCTAssertTrue(app.openSymbolSearch(), "顶栏放大镜没进搜索页")
    let field = app.textFields[Ids.searchQuery]
    enter("美元", into: field)
    let row = app.buttons["symbols.row." + Self.dxy]
    XCTAssertTrue(row.waitForExistence(timeout: 30), "搜「美元」没出美元指数")
    shot("走查03-搜美元")
    let star = app.buttons["symbols.star." + Self.dxy]
    XCTAssertTrue(star.waitForExistence(timeout: Self.short), "美元指数那一行没有星")
    star.tap()
    row.tap()
    XCTAssertTrue(waitChart(Self.dxy), "进美元指数的图没拿到 K 线：\(chartInfo())")
    shot("走查04-美元指数图")
    for id in ["top.stats", "top.openInterest", "top.funding", "top.valuation"] {
      XCTAssertFalse(app.descendants(matching: .any).matching(identifier: id).firstMatch.exists, "美元指数头部不该有 \(id)")
    }
    XCTAssertFalse(subs.contains("VOL"), "美元指数不该画成交量：\(subs)")

    // 自选页多出「指数」，美元指数在里面、有价。
    XCTAssertTrue(app.openFavorites(), "回不到自选页")
    let indexGroup = app.buttons["favorites.group.指数"]
    XCTAssertTrue(indexGroup.waitForExistence(timeout: Self.short), "加了美元指数，自选页没多出「指数」")
    indexGroup.tap()
    let cell = app.descendants(matching: .any).matching(identifier: "favorites.open." + Self.dxy).firstMatch
    XCTAssertTrue(cell.waitForExistence(timeout: Self.short), "「指数」里没有美元指数")
    let price = app.descendants(matching: .any).matching(identifier: "favorites.price." + Self.dxy).firstMatch
    XCTAssertTrue(waitUntil(timeout: 20) { price.exists && !price.label.isEmpty && price.label != "—" },
                  "自选里美元指数没价：\(price.exists ? price.label : "无")")
    shot("走查05-自选指数类")
    cell.tap()
    XCTAssertTrue(waitChart(Self.dxy), "从自选点美元指数没进图")

    // 周期：1m / 1h / 1d，再从「更多」里点 4h、1w。
    for raw in ["1m", "1h", "1d", "4h", "1w"] {
      pick(raw, minBars: raw == "1w" ? 10 : 20)
      XCTAssertGreaterThan(double("lastClose"), 50, "美元指数 \(raw) 收盘价不像美元指数：\(chartInfo())")
      if raw == "1m" || raw == "1d" { shot("走查06-美元指数-\(raw)") }
    }
    pick("1h")

    // 指标：MA 默认开着；BOLL、MACD 开了图上出、关了图上退。
    XCTAssertTrue(app.openIndicatorPage(), "「分析」没开出面板")
    shot("走查07-分析面板")
    setSwitch("BOLL", on: true); setSwitch("MACD", on: true)
    app.closeOpenPanel()
    XCTAssertTrue(waitUntil(timeout: Self.short) { self.overlays.contains("BOLL") && self.subs.contains("MACD") },
                  "开了 BOLL / MACD 图上没出：overlays=\(overlays) subs=\(subs)")
    shot("走查08-美元指数-BOLL-MACD")
    XCTAssertTrue(app.openIndicatorPage())
    setSwitch("MA", on: false); setSwitch("BOLL", on: false); setSwitch("MACD", on: false)
    app.closeOpenPanel()
    XCTAssertTrue(waitUntil(timeout: Self.short) { self.overlays.isEmpty && !self.subs.contains("MACD") },
                  "关了指标图上还在：overlays=\(overlays) subs=\(subs)")
    XCTAssertTrue(app.openIndicatorPage())
    setSwitch("MA", on: true)
    app.closeOpenPanel()
    XCTAssertTrue(waitUntil(timeout: Self.short) { self.overlays == ["MA"] }, "MA 没开回来：\(overlays)")
    reportHangs("走查一全程", since: (0, []))
  }

  /// 美元指数上：顶栏「⋯ › 添加对比」加 BTC、ETH、删一只，加满三只第四只「已满」；
  /// 铃铛建提醒 → 列表 → 日志 → 删。
  func testWalk2DollarIndexCompareAndAlerts() {
    executionTimeAllowance = 600
    XCTAssertTrue(waitChart(Self.dxy, "1h"), "美元指数 1h 没起来：\(chartInfo())")
    let h0 = hangs()

    openCompare()
    let selfMark = app.buttons["compare.toggle." + Self.dxy]
    if selfMark.exists { XCTAssertEqual(selfMark.value as? String, "主图", "主图那只那一行行尾不是「主图」") }
    compareToggle("BTCUSDT", Self.btc, expect: "已添加")
    compareToggle("ETHUSDT", Self.eth, expect: "已添加")
    shot("走查09-对比搜索页-两只")
    doneCompare()
    XCTAssertTrue(waitUntil(timeout: 60) { (self.chartInfo()["compareReady"] as? Int) == 2 },
                  "美元指数上叠 BTC / ETH 没到齐：\(chartInfo()["compareReady"] ?? "?") \(compareKeys)")
    shot("走查10-美元指数叠BTC-ETH")

    // 加满三只，第四只「已满」。
    openCompare()
    compareToggle("SOLUSDT", Self.sol, expect: "已添加")
    enter("DOGEUSDT", into: app.textFields[Ids.searchQuery])
    let doge = app.buttons["compare.toggle.binance/usd_m/DOGEUSDT"]
    XCTAssertTrue(doge.waitForExistence(timeout: 20))
    XCTAssertEqual(doge.value as? String, "已满", "三只满了第四只行尾不是「已满」")
    // 对比搜索页里搜出来的行要有价（10-05 回归压测前，这一页不算「看得见的列表」，价一直是「—」）。
    let dogeRow = app.descendants(matching: .any).matching(identifier: "symbols.row.binance/usd_m/DOGEUSDT").firstMatch
    let priced = NSPredicate(format: "label MATCHES %@", "^[0-9][0-9,]*\\.[0-9]+$")
    XCTAssertTrue(waitUntil(timeout: 10) { dogeRow.staticTexts.matching(priced).count > 0 },
                  "对比搜索页 DOGE 那一行 10 秒没出价：\(dogeRow.staticTexts.allElementsBoundByIndex.map(\.label))")
    doge.tap()
    dwell(0.5)
    // 搜索页盖着图，读不到图上的读数——数「正在对比」那条上的 ×。
    let removes = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'compare.remove.'")).allElementsBoundByIndex
      .map { String($0.identifier.dropFirst("compare.remove.".count)) }
    XCTAssertEqual(Set(removes), [Self.btc, Self.eth, Self.sol], "满了还能加第四只：\(removes)")
    shot("走查11-对比已满")
    // 从「正在对比」那条删掉 ETH 和 SOL。
    for key in [Self.eth, Self.sol] {
      let remove = app.buttons["compare.remove." + key]
      XCTAssertTrue(remove.waitForExistence(timeout: Self.short), "「正在对比」上没有 \(key) 的 ×")
      remove.tap()
      XCTAssertTrue(waitUntil(timeout: Self.short) { !remove.exists }, "点 × 没删掉 \(key)")
    }
    doneCompare()
    XCTAssertTrue(waitUntil(timeout: 30) { self.compareKeys == [Self.btc] && (self.chartInfo()["compareReady"] as? Int) == 1 },
                  "删完不是只剩 BTC：\(compareKeys)")
    shot("走查12-对比只剩BTC")

    // 提醒：铃铛 → 列表（置顶这只，空）→ 建一条 → 日志（没登录）→ 删。
    openHub()
    XCTAssertTrue(app.staticTexts["alerts.pinned.empty"].waitForExistence(timeout: Self.short), "美元指数还没提醒，置顶组不是「暂无提醒」")
    shot("走查13-提醒表-空")
    let last = double("lastClose")
    let target = String(format: "%.2f", (last > 0 ? last : 100) * 1.02)
    createFromHub(price: target)
    let pinned = app.descendants(matching: .any)["alerts.pinned.price"]
    XCTAssertTrue(pinned.waitForExistence(timeout: Self.short), "建完置顶组里没有那条价格提醒")
    let symbolText = app.descendants(matching: .any).matching(identifier: "alerts.symbol").firstMatch
    if symbolText.exists { note("提醒行品种写作「\(symbolText.label)」") }
    shot("走查14-提醒表-一条")
    hubPick("日志")
    XCTAssertTrue(app.descendants(matching: .any)["alerts.log.signedOut"].waitForExistence(timeout: Self.short),
                  "没登录时日志页不是「登录后可查看」")
    shot("走查15-提醒日志-未登录")
    hubPick("列表")
    let trash = app.buttons["alerts.delete"].firstMatch
    XCTAssertTrue(trash.waitForExistence(timeout: Self.short), "提醒行尾没有垃圾桶")
    trash.tap()
    XCTAssertTrue(app.staticTexts["alerts.pinned.empty"].waitForExistence(timeout: Self.short), "删完置顶组没回到「暂无提醒」")
    closeHub()
    reportHangs("走查二全程", since: h0)
  }

  /// 画线：竖屏四把 → 画一条趋势线 → 从「全部工具」挑一把冷门的顶掉最后一格 → 撤销 → 完成；
  /// 横屏画线台：默认画主图指标 → 眼睛关 / 开 → 「主图˅」换布林带 → 捏开 / 捏合 / 竖向捏 → 完成；
  /// 回竖屏根宽与价格轴倍率回到竖屏那份。
  func testWalk3DrawingBarAndLandscapeWorkbench() {
    executionTimeAllowance = 600
    XCTAssertTrue(waitChart(Self.dxy, "1h", minBars: 64), "美元指数 1h 没起来：\(chartInfo())")
    let portraitSpacing = double("spacing"), portraitZoom = double("zoomY")
    let h0 = hangs()

    var hStage = hangs()
    // 拆两段量：冷开「分析」面板一段，点「开始画线」（横过去再手动转回竖屏）一段。
    XCTAssertTrue(app.openIndicatorPage(), "分析面板没开")
    dwell(0.6)
    reportHangs("走查三·冷开分析面板", since: hStage); hStage = hangs()
    XCTAssertTrue(app.enterDrawingInPortrait(), "没进竖屏画线栏")
    XCTAssertTrue(waitUntil(timeout: Self.short) { self.onBar().count == 4 }, "竖屏条上不是四把：\(onBar())")
    XCTAssertEqual(barOrder(), ["trend", "hline", "fibonacci", "channel"], "新装四把的顺序不对")
    shot("走查16-竖屏画线条")
    reportHangs("走查三·进竖屏画线", since: hStage); hStage = hangs()
    app.buttons["draw.trend"].tap()
    mainPoint(x: 0.25, y: 0.3).tap()
    mainPoint(x: 0.6, y: 0.45).tap()
    XCTAssertTrue(waitUntil(timeout: Self.short) { self.drawingCount == 1 }, "趋势线没画上：\(chartInfo()["drawingCount"] ?? "?")")
    shot("走查17-画了一条趋势线")
    reportHangs("走查三·画趋势线", since: hStage); hStage = hangs()
    // 画完那条自动选中、上排换成选中栏；点空白处收掉选中，条回来。
    if !app.buttons["draw.tools"].exists || !app.buttons["draw.trend"].exists {
      mainPoint(x: 0.85, y: 0.85).tap(); dwell(0.5)
    }
    pickFromPanel("anchoredVWAP")
    XCTAssertTrue(waitUntil(timeout: Self.short) { self.app.buttons["draw.anchoredVWAP"].exists },
                  "从面板挑了锚定均价线，条上没出现它：\(onBar())")
    XCTAssertEqual(onBar().count, 4, "挑一把冷门的，条上该还是四把：\(onBar())")
    XCTAssertEqual(barOrder().last, "anchoredVWAP", "挑来的那把没落在最后一格：\(barOrder())")
    note("竖屏挑冷门工具后条上 \(barOrder())")
    shot("走查18-冷门工具顶掉最后一格")
    reportHangs("走查三·全部工具挑一把", since: hStage); hStage = hangs()
    let undo = app.buttons["draw.undo"]
    XCTAssertTrue(undo.waitForExistence(timeout: Self.short) && undo.isEnabled, "画过一笔「撤销」该能按")
    undo.tap()
    XCTAssertTrue(waitUntil(timeout: Self.short) { self.drawingCount == 0 }, "撤销没撤掉那条线：\(drawingCount)")
    finishDrawing()
    reportHangs("走查三·撤销与完成", since: hStage); hStage = hangs()

    // 横屏画线台。
    enterLandscapeWorkbench()
    let eye = app.descendants(matching: .any).matching(identifier: Ids.landscapeIndicators).firstMatch
    let picker = app.descendants(matching: .any).matching(identifier: Ids.landscapeIndicatorPicker).firstMatch
    XCTAssertTrue(waitUntil(timeout: Self.long) { self.overlays == ["MA"] }, "画线台里没默认画 MA：\(overlays)")
    XCTAssertTrue(eye.waitForExistence(timeout: Self.short), "画线台顶行没有眼睛")
    XCTAssertTrue(picker.waitForExistence(timeout: Self.short), "画线台顶行没有「主图˅」")
    XCTAssertEqual(onBar().count, 5, "横屏条上不是五把：\(onBar())")
    note("横屏条上 \(barOrder())")
    shot("走查19-横屏画线台默认")
    reportHangs("走查三·进横屏画线台", since: hStage); hStage = hangs()
    eye.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
    XCTAssertTrue(waitUntil(timeout: Self.short) { self.overlays.isEmpty }, "眼睛关了图上还有：\(overlays)")
    XCTAssertEqual(eye.value as? String, "关")
    shot("走查20-眼睛关")
    eye.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
    XCTAssertTrue(waitUntil(timeout: Self.short) { self.overlays == ["MA"] }, "眼睛开了 MA 没回来：\(overlays)")
    picker.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
    let boll = app.descendants(matching: .any).matching(identifier: Ids.indicatorSwitch("BOLL")).firstMatch
    XCTAssertTrue(boll.waitForExistence(timeout: Self.short), "「主图˅」没开出侧栏")
    shot("走查21-主图侧栏")
    boll.tap()
    app.descendants(matching: .any).matching(identifier: Ids.indicatorSwitch("MA")).firstMatch.tap()
    app.buttons[Ids.panelDone].tap()
    dwell(0.6)
    XCTAssertTrue(waitUntil(timeout: Self.short) { self.overlays == ["BOLL"] }, "换成 BOLL 图上不对：\(overlays)")
    shot("走查22-主图换成BOLL")
    reportHangs("走查三·眼睛与主图侧栏", since: hStage); hStage = hangs()

    // 捏合。
    let land0 = double("spacing")
    canvas.pinch(withScale: 2.0, velocity: 2.0)
    XCTAssertTrue(waitUntil(timeout: Self.short) { self.double("spacing") > land0 * 1.3 }, "横屏捏开根宽没变宽")
    dwell(0.8)
    shot("走查23-横屏捏开")
    let wide = double("spacing")
    canvas.pinch(withScale: 0.5, velocity: -2.0)
    XCTAssertTrue(waitUntil(timeout: Self.short) { self.double("spacing") < wide * 0.75 }, "横屏捏合根宽没变窄")
    dwell(0.8)
    let narrow = double("spacing")
    let zoom0 = double("zoomY")
    let center = canvas.coordinate(withNormalizedOffset: CGVector(dx: 0.4, dy: 0.5))
    XCTAssertTrue(LandscapePinchUITests.verticalPinch(center: center, from: 70, to: 230), "竖向捏没发出去")
    XCTAssertTrue(waitUntil(timeout: Self.short) { abs(self.double("zoomY") - zoom0) > 0.05 }, "竖向捏价格轴没缩放")
    dwell(0.8)
    XCTAssertEqual(double("spacing"), narrow, accuracy: narrow * 0.05, "竖向捏把根宽也改了")
    note("横屏根宽 \(land0) → 捏开 \(wide) → 捏合 \(narrow)；价格轴 \(zoom0) → \(double("zoomY")) layout=\(layout())")
    shot("走查24-横屏竖向捏价格轴")
    reportHangs("走查三·横屏捏合", since: hStage); hStage = hangs()
    finishDrawing()

    XCTAssertTrue(waitUntil(timeout: Self.long) { abs(self.double("spacing") - portraitSpacing) < portraitSpacing * 0.05 },
                  "回竖屏根宽没回到竖屏那份：\(portraitSpacing) → \(double("spacing"))")
    XCTAssertEqual(double("zoomY"), portraitZoom, accuracy: 0.01, "横屏竖向捏的价格轴倍率带回了竖屏")
    XCTAssertEqual(overlays, ["BOLL"], "画线台里换的主图指标没带回竖屏：\(overlays)")
    shot("走查25-回竖屏")
    reportHangs("走查三·回竖屏", since: hStage)
    reportHangs("走查三全程", since: h0)
  }

  /// BTC 永续：头部右侧六格、主力订单流、成交量副图都在。
  /// 进竖屏画线那一下的卡顿拆开量：点「开始画线」横过去一段、手动转回竖屏一段，连做三轮，
  /// 看是第一次才有（冷启动代价）还是每次转回竖屏都有。
  func testProbeEnterPortraitDrawingHang() {
    executionTimeAllowance = 600
    XCTAssertTrue(waitChart(Self.dxy, "1h", minBars: 64), "美元指数 1h 没起来：\(chartInfo())")
    for round in 1...3 {
      XCTAssertTrue(app.openIndicatorPage(), "分析面板没开")
      dwell(0.6)
      // 外面的采样脚本认这一行开始 `sample`（给它 2 秒起跑）。
      note("探针就绪 第\(round)轮")
      dwell(2.5)
      var h = hangs()
      app.buttons[Ids.indicatorDraw].tap()
      XCTAssertTrue(app.landscapeMarker.waitForExistence(timeout: Self.long), "点「画线」没横过去")
      dwell(1.5)
      reportHangs("探针第\(round)轮·点画线横过去", since: h); h = hangs()
      app.rotateDrawingToPortraitByHand()
      XCTAssertTrue(app.buttons[Ids.drawFinish].waitForExistence(timeout: Self.short), "没到竖屏画线栏")
      dwell(1.5)
      reportHangs("探针第\(round)轮·手动转回竖屏", since: h); h = hangs()
      if round == 1 {
        app.buttons["draw.tools"].tap()
        XCTAssertTrue(app.buttons["draw.tool.anchoredVWAP"].waitForExistence(timeout: Self.short), "「全部工具」没开出面板")
        dwell(0.8)
        shot("探针-全部工具面板")
        app.buttons["draw.tool.trend"].tap()
        dwell(0.6)
        shot("探针-竖屏画线条")
      }
      finishDrawing()
      dwell(1.0)
      reportHangs("探针第\(round)轮·完成", since: h)
    }
    // 长按自选里一行弹小卡（卡上那段 K 线原来也是 `Canvas` + `drawingGroup`）。
    XCTAssertTrue(app.openFavorites(), "底栏「自选」没进自选页")
    let g = app.buttons["favorites.group.加密"]
    if g.waitForExistence(timeout: Self.short), !g.isSelected { g.tap() }
    let cell = app.descendants(matching: .any).matching(identifier: "favorites.open." + Self.btc).firstMatch
    XCTAssertTrue(cell.waitForExistence(timeout: Self.short), "自选「加密」里没有 BTC")
    dwell(1.0)
    let h = hangs()
    cell.press(forDuration: 1.0)
    dwell(1.5)
    reportHangs("探针·长按自选弹小卡", since: h)
    shot("探针-长按小卡")
    app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.06)).tap()
    dwell(0.8)
  }

  func testWalk4BTCHeaderOrderFlowVolume() {
    executionTimeAllowance = 600
    XCTAssertTrue(waitChart(Self.btc, "15m", minBars: 64), "BTC 15m 没起来：\(chartInfo())")
    let stats = app.descendants(matching: .any).matching(identifier: "top.stats").firstMatch
    XCTAssertTrue(stats.waitForExistence(timeout: Self.short), "BTC 头部右侧那块不在")
    let cells = ["top.openInterest", "top.marketCap", "top.turnover", "top.funding", "top.valuation"]
    XCTAssertTrue(waitUntil(timeout: 20) {
      cells.allSatisfy { self.app.descendants(matching: .any).matching(identifier: $0).firstMatch.exists }
    }, "BTC 头部格子不全：\(cells.filter { !app.descendants(matching: .any).matching(identifier: $0).firstMatch.exists })")
    let valuation = app.descendants(matching: .any).matching(identifier: "top.valuation").firstMatch
    note("BTC 估值格「\(valuation.label)」 额「\(app.descendants(matching: .any).matching(identifier: "top.turnover").firstMatch.label)」")
    XCTAssertTrue(subs.contains("VOL"), "BTC 出厂该有成交量副图：\(subs)")
    XCTAssertTrue(app.openIndicatorPage())
    setSwitch("ORDERFLOW", on: true)
    app.closeOpenPanel()
    XCTAssertTrue(waitUntil(timeout: 120, poll: 1) { self.chartInfo()["orderFlowPhase"] as? String == "ready" },
                  "主力订单流没就绪：\(chartInfo()["orderFlowPhase"] ?? "?")")
    note("BTC 主力订单流 orders=\(chartInfo()["orderFlowOrders"] ?? 0)")
    dwell(2)
    shot("走查26-BTC头部六格-订单流-成交量")
    // 切到美元指数：订单流不画、成交量不画；切回 BTC 都回来。
    open("DXY", Self.dxy)
    XCTAssertTrue(waitChart(Self.dxy), "切到美元指数没起来")
    XCTAssertTrue(waitUntil(timeout: Self.short) { !self.subs.contains("VOL") }, "美元指数上还画成交量：\(subs)")
    XCTAssertEqual(chartInfo()["orderFlowOrders"] as? Int ?? 0, 0, "美元指数上不该有大单：\(chartInfo()["orderFlowOrders"] ?? 0)")
    shot("走查27-切到美元指数订单流与成交量都不画")
    open("BTCUSDT", Self.btc)
    XCTAssertTrue(waitUntil(timeout: 30) { self.subs.contains("VOL") }, "切回 BTC 成交量没回来：\(subs)")
    XCTAssertTrue(waitUntil(timeout: 120, poll: 1) { self.chartInfo()["orderFlowPhase"] as? String == "ready" },
                  "切回 BTC 订单流没回来：\(chartInfo()["orderFlowPhase"] ?? "?")")
  }

  /// 三套皮肤（各浅 / 深）下的美元指数行情页与「提醒」表。
  func testWalk5SkinsOnDollarIndexAndAlertSheet() {
    executionTimeAllowance = 900
    XCTAssertTrue(waitChart(Self.dxy, "1h"), "美元指数 1h 没起来")
    for skin in ["sage", "terra", "classic"] {
      for mode in ["浅色", "深色"] {
        applySkin(skin, mode)
        XCTAssertTrue(waitChart(Self.dxy, "1h"), "换皮肤后美元指数图没回来")
        dwell(0.8)
        shot("皮肤-\(skin)-\(mode)-美元指数")
        openHub()
        dwell(0.6)
        shot("皮肤-\(skin)-\(mode)-提醒表")
        closeHub()
      }
    }
    applySkin("sage", "浅色")
  }

  /// 杀进程重启：自选（美元指数）、对比、提醒、画线条顺序、横屏根宽都还在。
  /// 对比开着时画线是灰的（对比与画线互斥，App 的既定设计），所以先摆画线条与横屏根宽，再加对比；
  /// 重启后先核对比，再把对比摘掉去核画线条。
  func testWalk6RelaunchKeepsEverything() {
    executionTimeAllowance = 600
    XCTAssertTrue(waitChart(Self.dxy, "1h", minBars: 64), "美元指数 1h 没起来")
    // 自选：从搜索页点星。
    XCTAssertTrue(app.openSymbolSearch())
    enter("DXY", into: app.textFields[Ids.searchQuery])
    let star = app.buttons["symbols.star." + Self.dxy]
    XCTAssertTrue(star.waitForExistence(timeout: 20)); star.tap()
    app.buttons["symbols.row." + Self.dxy].tap()
    XCTAssertTrue(waitChart(Self.dxy))
    // 画线条：竖屏挑多空持仓框顶掉最后一格。
    XCTAssertTrue(app.enterDrawingInPortrait())
    pickFromPanel("position")
    XCTAssertTrue(waitUntil(timeout: Self.short) { self.app.buttons["draw.position"].exists })
    XCTAssertEqual(barOrder().last, "position", "挑来的那把这一回该在最后一格：\(barOrder())")
    finishDrawing()
    // 条的顺序在画线打开那一下按次数定、这一回里不重排；再开一次才是记过次数之后的顺序，重启后该一模一样。
    XCTAssertTrue(app.enterDrawingInPortrait())
    let portraitBar = barOrder()
    XCTAssertEqual(portraitBar.first, "position", "选过一次的多空持仓框（其余都没用过）重开该排第一：\(portraitBar)")
    finishDrawing()
    // 横屏捏开一次。
    enterLandscapeWorkbench()
    canvas.pinch(withScale: 1.8, velocity: 2.0)
    dwell(1.2)
    let landBar = barOrder()
    let landSpacing = double("spacing")
    XCTAssertTrue(waitUntil(timeout: Self.short) { abs((self.layout()["landStored"] ?? 0) - landSpacing) < 0.6 },
                  "横屏捏完没落盘：\(layout())")
    finishDrawing()
    XCTAssertTrue(waitUntil(timeout: Self.long) { self.app.buttons[Ids.topMore].exists }, "回竖屏顶栏没回来")
    let portraitSpacing = double("spacing")
    // 对比 BTC。
    openCompare(); compareToggle("BTCUSDT", Self.btc, expect: "已添加"); doneCompare()
    XCTAssertTrue(waitUntil(timeout: 60) { (self.chartInfo()["compareReady"] as? Int) == 1 }, "对比 BTC 没到")
    // 提醒一条。
    openHub()
    createFromHub(price: String(format: "%.2f", max(1, double("lastClose")) * 0.97))
    XCTAssertTrue(app.descendants(matching: .any)["alerts.pinned.price"].waitForExistence(timeout: Self.short))
    closeHub()
    note("重启前：竖屏条 \(portraitBar) 横屏条 \(landBar) 横屏根宽 \(landSpacing) 竖屏根宽 \(portraitSpacing) 对比 \(compareKeys)")
    shot("走查28-重启前")
    dwell(2.5)   // 让同步与落盘的尾巴走完（落盘本身是抬手即落，这里只等写文件的那一拍）。

    relaunch()
    XCTAssertTrue(waitChart(Self.dxy, minBars: 20, 60), "重启后不在美元指数上：\(chartInfo())")
    XCTAssertTrue(waitUntil(timeout: 60) { self.compareKeys == [Self.btc] && (self.chartInfo()["compareReady"] as? Int) == 1 },
                  "重启后对比没了：\(compareKeys)")
    XCTAssertEqual(double("spacing"), portraitSpacing, accuracy: portraitSpacing * 0.05, "重启后竖屏根宽变了")
    shot("走查29-重启后图")
    openHub()
    XCTAssertTrue(app.descendants(matching: .any)["alerts.pinned.price"].waitForExistence(timeout: Self.short), "重启后提醒没了")
    closeHub()
    // 摘掉对比，画线才点得动。
    openCompare(); compareToggle("BTCUSDT", Self.btc, expect: "可添加"); doneCompare()
    XCTAssertTrue(waitUntil(timeout: Self.short) { self.compareKeys.isEmpty }, "对比没摘掉：\(compareKeys)")
    XCTAssertTrue(app.enterDrawingInPortrait())
    XCTAssertEqual(barOrder(), portraitBar, "重启后竖屏画线条顺序变了")
    finishDrawing()
    enterLandscapeWorkbench()
    XCTAssertEqual(barOrder(), landBar, "重启后横屏画线条顺序变了")
    XCTAssertEqual(double("spacing"), landSpacing, accuracy: landSpacing * 0.05, "重启后横屏根宽没回到上次那份")
    shot("走查30-重启后横屏")
    finishDrawing()
    XCTAssertTrue(app.openFavorites())
    let indexGroup = app.buttons["favorites.group.指数"]
    XCTAssertTrue(indexGroup.waitForExistence(timeout: Self.short), "重启后自选页没有「指数」")
    indexGroup.tap()
    XCTAssertTrue(app.descendants(matching: .any).matching(identifier: "favorites.open." + Self.dxy).firstMatch
      .waitForExistence(timeout: Self.short), "重启后自选里没有美元指数")
    shot("走查31-重启后自选")
  }

  // ============================================================ 二、高频与边界

  /// 自选 BTC、ETH（加密）与美元指数（指数）：BTC → ETH 走顶栏价格区横滑（扫图名单 = 自选页当前那一类），
  /// ETH → 美元指数、美元指数 → BTC 走自选页点行。20 轮共 60 次换品种，每次都要落到对的那只并拿到 K 线。
  func testStressHopBTCDollarIndexETH() {
    executionTimeAllowance = 900
    XCTAssertTrue(waitChart(Self.btc, "15m"), "BTC 15m 没起来")
    let quoteEl = app.descendants(matching: .any).matching(identifier: "market.quote").firstMatch
    let h0 = hangs()
    var slow: [String] = [], times: [String: [Int]] = [:], nav: [Int] = []
    func land(_ key: String, _ label: String, _ i: Int, _ t0: Date) {
      let ready = waitChart(key, "15m", minBars: 20, 30)
      let ms = Int(Date().timeIntervalSince(t0) * 1000)
      times[label, default: []].append(ms)
      if !ready { slow.append("\(label)#\(i + 1)") }
      if ms > 1500 { note("第 \(i + 1) 轮 \(label) 点下去到 K 线 \(ms)ms") }
    }
    /// 回自选页、点那一行；返回点下那一刻（到 K 线的计时从这儿起，不含 XCUITest 找按钮的那几秒）。
    func fromFavorites(_ group: String, _ key: String) -> Date {
      let n0 = Date()
      // 先落到局部量再断言：Release 下嵌套函数里把 `app.openFavorites()` 直接塞进 XCTAssert 的 autoclosure，
      // 编译器按区域隔离判成「sending 'self' risks causing data races」，Release 测试包整包编不过。
      let opened = app.openFavorites()
      XCTAssertTrue(opened, "回不到自选页")
      let g = app.buttons["favorites.group." + group]
      XCTAssertTrue(g.waitForExistence(timeout: Self.short), "自选页没有「\(group)」")
      if !g.isSelected { g.tap() }
      let cell = app.descendants(matching: .any).matching(identifier: "favorites.open." + key).firstMatch
      XCTAssertTrue(cell.waitForExistence(timeout: Self.short), "「\(group)」里没有 \(key)")
      nav.append(Int(Date().timeIntervalSince(n0) * 1000))
      let t = Date()
      cell.tap()
      return t
    }
    for i in 0..<20 {
      var t0 = fromFavorites("加密", Self.btc)
      land(Self.btc, "→BTC", i, t0)
      t0 = Date()
      quoteEl.coordinate(withNormalizedOffset: CGVector(dx: 0.85, dy: 0.5))
        .press(forDuration: 0.02, thenDragTo: quoteEl.coordinate(withNormalizedOffset: CGVector(dx: 0.1, dy: 0.5)))
      XCTAssertTrue(waitUntil(timeout: 15, poll: 0.1) { self.symbol == Self.eth }, "第 \(i + 1) 轮横滑没从 BTC 换到 ETH：\(symbol)")
      land(Self.eth, "BTC→ETH 横滑", i, t0)
      t0 = fromFavorites("指数", Self.dxy)
      land(Self.dxy, "→美元指数", i, t0)
      XCTAssertFalse(app.descendants(matching: .any).matching(identifier: "top.stats").firstMatch.exists, "美元指数上摆着六格")
      if i == 0 || i == 19 { shot("高频切换-第\(i + 1)轮-美元指数") }
    }
    XCTAssertTrue(slow.isEmpty, "这些次换过去 30 秒没拿到 K 线：\(slow)")
    for (label, list) in times.sorted(by: { $0.key < $1.key }) {
      let sorted = list.sorted()
      note("\(label) \(list.count) 次 点下去到 K 线 p50=\(sorted[sorted.count / 2])ms p90=\(sorted[sorted.count * 9 / 10])ms max=\(sorted.last ?? 0)ms")
    }
    let navSorted = nav.sorted()
    note("XCUITest 回自选页找行（不算 app 的账）p50=\(navSorted[navSorted.count / 2])ms")
    reportHangs("换品种 60 次", since: h0)
  }

  /// 周期狂切：BTC、美元指数各 1m→5m→15m→1h→4h→1d 不等落地连点 8 轮，最后停在的那一档必须是对的、有 K 线；
  /// 再逐档等落地，确认每档的数据真是那一档的。
  func testStressRapidIntervalsBTCAndDollarIndex() {
    executionTimeAllowance = 900
    XCTAssertTrue(waitChart(Self.btc, "15m"), "BTC 15m 没起来")
    for (query, key) in [("BTCUSDT", Self.btc), ("DXY", Self.dxy)] {
      if symbol != key { open(query, key); XCTAssertTrue(waitChart(key)) }
      let h0 = hangs()
      let seq = ["1m", "5m", "15m", "1h", "4h", "1d"]
      for _ in 0..<8 { for raw in seq { app.tapIntervalChip(raw) } }
      app.tapIntervalChip("4h")
      XCTAssertTrue(waitChart(key, "4h", minBars: 20, 30), "\(code(key)) 狂切后没停在 4h：\(chartInfo())")
      dwell(3)
      XCTAssertEqual(chartInfo()["interval"] as? String, "4h", "\(code(key)) 停稳 3 秒后周期被晚到的回包改了：\(chartInfo())")
      reportHangs("\(code(key)) 周期狂切 49 下", since: h0)
      shot("周期狂切-\(code(key))-停在4h")
      for raw in seq { pick(raw) }
    }
  }

  /// 对比三只（ETH、SOL、美元指数）+ MA + BOLL：切周期三次对比都要回齐；对比期间「开始画线」置灰点不动
  /// （设计如此：对比时不画线）；把手机横过来看、横屏里甩动量帧、转屏 10 次，对比与指标一直在、不崩。
  func testStressCompare3IntervalLandscapeRotate() throws {
    executionTimeAllowance = 900
    XCTAssertTrue(waitChart(Self.btc, "1m", minBars: 100), "BTC 1m 没起来")
    XCTAssertTrue(waitUntil(timeout: 90) { (self.chartInfo()["compareReady"] as? Int) == 3 },
                  "三只对比没到齐：\(chartInfo()["compareReady"] ?? "?") \(compareKeys)")
    XCTAssertTrue(app.openIndicatorPage())
    setSwitch("BOLL", on: true)
    let draw = app.buttons[Ids.indicatorDraw]
    XCTAssertTrue(draw.waitForExistence(timeout: Self.short), "分析面板里没有「开始画线」")
    XCTAssertFalse(draw.isEnabled, "对比期间「开始画线」该置灰点不动")
    app.closeOpenPanel()
    let h0 = hangs()
    for raw in ["1h", "4h", "1m"] {
      pick(raw, minBars: 100)
      XCTAssertTrue(waitUntil(timeout: 90) { (self.chartInfo()["compareReady"] as? Int) == 3 },
                    "切到 \(raw) 后三只对比没回齐：\(chartInfo()["compareReady"] ?? "?")")
    }
    shot("对比三只-竖屏")
    reportHangs("对比三只切三次周期", since: h0)

    // 竖屏对比三只时甩：量帧（FrameProbe 报告从 app 沙盒里读）。
    flingAndMeasure("竖屏对比三只甩动")

    // 横过来：对比按设计暂退（横屏与对比互斥，对比集合本身不动，回竖屏恢复），主图 MA + BOLL 画出来。
    XCUIDevice.shared.orientation = .landscapeLeft
    XCTAssertTrue(waitUntil(timeout: Self.long) { self.app.windows.firstMatch.frame.width > self.app.windows.firstMatch.frame.height },
                  "手机横过来界面没跟着横")
    dwell(1.5)
    XCTAssertTrue(waitUntil(timeout: Self.short) { self.compareKeys.isEmpty }, "横屏里对比该暂退：\(compareKeys)")
    XCTAssertTrue(waitUntil(timeout: Self.short) { Set(self.overlays) == ["MA", "BOLL"] }, "横屏里主图指标不对：\(overlays)")
    shot("对比三只-横屏暂退")
    flingAndMeasure("横屏 MA + BOLL 甩动")

    // 转屏 10 次。
    let h2 = hangs()
    for i in 0..<10 {
      XCUIDevice.shared.orientation = i.isMultiple(of: 2) ? .portrait : .landscapeLeft
      Thread.sleep(forTimeInterval: 1.2)
      XCTAssertEqual(app.state, .runningForeground, "第 \(i + 1) 次转屏后 app 不在前台")
      // 竖屏顶栏是 `top.symbol`，横屏外壳顶上那颗是 `land.symbol`。
      let head = app.descendants(matching: .any).matching(identifier: i.isMultiple(of: 2) ? Ids.symbolButton : "land.symbol").firstMatch
      XCTAssertTrue(head.waitForExistence(timeout: Self.short), "第 \(i + 1) 次转屏后顶上的品种名没了")
    }
    XCUIDevice.shared.orientation = .portrait
    Thread.sleep(forTimeInterval: 1.2)
    XCTAssertTrue(waitUntil(timeout: 30) { (self.chartInfo()["compareReady"] as? Int) == 3 && !self.subs.isEmpty },
                  "转屏 10 次后对比或副图掉了：compare=\(chartInfo()["compareReady"] ?? "?") subs=\(subs)")
    // 对比态主图是百分比轴，主图叠加层按设计不画（`MainScreen.visibleOverlays`），设置本身不动。
    XCTAssertTrue(overlays.isEmpty, "竖屏对比态主图不该画叠加层：\(overlays)")
    reportHangs("转屏 10 次", since: h2)
    shot("对比三只-转屏10次后")
    // 再横一次：对比暂退，MA + BOLL 原样回来 = 10 次转屏没把指标设置弄丢。
    XCUIDevice.shared.orientation = .landscapeLeft
    XCTAssertTrue(waitUntil(timeout: Self.long) { Set(self.overlays) == ["MA", "BOLL"] },
                  "转屏 10 次后再横过来主图指标变了：\(overlays)")
    XCUIDevice.shared.orientation = .portrait
    Thread.sleep(forTimeInterval: 1.2)
  }

  /// 美元指数页上断网 40 秒：价格变灰（fresh=0）、「提醒」表照常能开能看；网回来价格自己活过来。
  func testStressOfflineDollarIndexAndAlertSheet() {
    executionTimeAllowance = 600
    XCTAssertTrue(waitChart(Self.dxy, "1h"), "美元指数 1h 没起来")
    note("断网窗口：开图后约 \(Int(outageStart - Date().timeIntervalSince1970))s 起断 \(Int(outageSeconds))s")
    // 先建一条提醒，断网时看它还在。
    openHub()
    createFromHub(price: String(format: "%.2f", max(1, double("lastClose")) * 1.05))
    closeHub()
    let wait = outageStart - Date().timeIntervalSince1970 + 3
    if wait > 0 { dwell(wait) }
    XCTAssertTrue(waitUntil(timeout: 30, poll: 0.5) { self.quote()["fresh"] == "0" },
                  "断网 30 秒价格还没标成不新鲜：\(quote())")
    let h0 = hangs()
    shot("断网-美元指数页")
    // 断网里切到一档从没拉过的周期（1d）：没缓存可给，图区要说「暂时无法连接，点此重试」，不能卡住、不能空转。
    app.tapIntervalChip("1d")
    let retry = app.buttons.matching(NSPredicate(format: "label CONTAINS '点此重试'")).firstMatch
    XCTAssertTrue(retry.waitForExistence(timeout: 30), "断网切到没拉过的 1d，30 秒没出「点此重试」")
    shot("断网-美元指数-切1d")
    // 切回刚看过的 1h：那一档刚拉过，断网时也该照样有图。
    let back = Date()
    app.tapIntervalChip("1h")
    let cached = waitChart(Self.dxy, "1h", minBars: 20, 10)
    note("断网切回刚看过的 1h：\(cached ? "有图 \(Int(Date().timeIntervalSince(back) * 1000))ms" : "10 秒内没图")")
    XCTAssertTrue(cached, "断网时切回刚看过的 1h 没图：\(chartInfo())")
    shot("断网-美元指数-切回1h")
    app.tapIntervalChip("1d")
    XCTAssertTrue(retry.waitForExistence(timeout: 30), "再切 1d 没出「点此重试」")
    openHub()
    XCTAssertTrue(app.descendants(matching: .any)["alerts.pinned.price"].waitForExistence(timeout: Self.short),
                  "断网时「提醒」表里本地那条提醒不见了")
    shot("断网-提醒表")
    hubPick("日志")
    dwell(1)
    shot("断网-提醒日志")
    hubPick("列表")
    closeHub()
    reportHangs("断网中", since: h0)
    let end = outageStart + outageSeconds - Date().timeIntervalSince1970 + 1
    if end > 0 { dwell(end) }
    XCTAssertTrue(waitUntil(timeout: 60, poll: 0.5) { self.quote()["fresh"] == "1" },
                  "网回来 60 秒价格还是灰的：\(quote())")
    // 停在 1d 的那张空图：网回来自己补上，不用人去点「点此重试」。
    let t0 = Date()
    let healed = waitChart(Self.dxy, "1d", minBars: 10, 60)
    note("网回来后 1d 自愈：\(healed ? "\(Int(Date().timeIntervalSince(t0) * 1000))ms" : "60 秒没自己补上")")
    XCTAssertTrue(healed, "网回来 60 秒，停在 1d 的空图没自己补上：\(chartInfo())")
    XCTAssertFalse(retry.exists, "图补上了「点此重试」还挂着")
    pick("1h")
    shot("断网恢复-美元指数页")
    openHub()
    app.buttons["alerts.delete"].firstMatch.tap()
    closeHub()
  }

  // ------------------------------------------------------------ 帧报告（同 HotPathFrameUITests）

  private func appContainer() -> URL? {
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

  /// 捏窄两下再快甩 24 下、慢拖 6 下，报卡顿与帧（超 8 ms 的帧占比）。
  private func flingAndMeasure(_ label: String) {
    let container = appContainer()
    if let c = container { try? FileManager.default.removeItem(at: framesDir(c)) }
    let h = hangs()
    for _ in 0..<2 { canvas.pinch(withScale: 0.6, velocity: -2) }
    for _ in 0..<12 { canvas.swipeRight(velocity: .fast) }
    dwell(1.6)
    for _ in 0..<12 { canvas.swipeLeft(velocity: .fast) }
    dwell(1.6)
    let mid = canvas.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.35))
    for k in 0..<6 {
      mid.press(forDuration: 0.05, thenDragTo: mid.withOffset(CGVector(dx: k.isMultiple(of: 2) ? 200 : -200, dy: 0)),
                withVelocity: .default, thenHoldForDuration: 0)
    }
    dwell(2)
    reportHangs(label, since: h)
    if let c = container {
      let (frames, heavy) = summarizeFrames(framesDir(c))
      let share = frames > 0 ? Double(heavy) / Double(frames) * 100 : 0
      note("\(label)：帧 \(frames) 超 8ms \(heavy)（\(String(format: "%.1f", share))%）构建=\(_isDebugAssertConfiguration() ? "Debug" : "Release")")
    } else {
      note("\(label)：没找到 app 数据容器，帧报告没读")
    }
  }

  private func framesDir(_ c: URL) -> URL {
    c.appendingPathComponent("Library/Application Support/kanpan/Diagnostics/frames", isDirectory: true)
  }

  private func summarizeFrames(_ dir: URL) -> (frames: Int, heavy: Int) {
    let files = ((try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)) ?? [])
      .filter { $0.pathExtension == "json" }
    var frames = 0, heavy = 0
    for f in files {
      guard let data = try? Data(contentsOf: f),
            let r = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { continue }
      frames += r["frameCount"] as? Int ?? 0
      heavy += (r["heavyBodies"] as? [String: Int] ?? [:])["*"] ?? 0
    }
    return (frames, heavy)
  }
}
