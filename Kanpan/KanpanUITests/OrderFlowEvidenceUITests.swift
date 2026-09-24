import XCTest

// ============================================================ 主力订单流 · 验收取证（2026-09-24，逐单模型）
//
// 以用户的身份打开「主力订单流」：图表面板 → 指标 → 主图叠加里的开关，等大单真的画出来再拍图。
// 模型照 CoinAnk「主力大额挂单」：一只币同时订现货（三家）、U 本位永续、币本位永续、交割各本簿，
// 某家某个产品上一个价位的挂单名义 ≥ 该产品门槛就是一条大单，从首次出现那根 K 线画到撤单 / 成交
// （还挂着的画到右缘）。用例：
//
// 1. 币安直连 BTCUSDT：青苔浅 / 青苔深 / 经典浅 / 经典深四张，再长按一条大单拍十字线读数。
// 2. BTC 的「指标 › 主力订单流」参数表：拍表，把 U 本位永续与现货门槛调低、保存，确认新门槛到了
//    簿那一层、图上的大单变多；再关掉「合约」确认只剩现货。
// 3. 网关线路（K 线上游换成 OKX 替身），品种 SOLUSDT。
// 4. Coinbase 现货 BTC-USD 页面（同一只币，簿照样三家现货 + 各家合约一起订）。
//
// 大单画在 CoreGraphics 上，读屏树里没有；等待与取点都读 `chart.canvas` 诊断里的
// `orderFlowPhase` / `orderFlowOrders` / `orderFlowBands` / `orderFlowThresholds` / `orderFlowHovered`（DEBUG 才有）。
// 图写进 `docs/acceptance/主力订单流-2026-09-24/`，同时挂一份附件进 xcresult。
@MainActor
final class OrderFlowEvidenceUITests: KanpanUICase {

  override var extraLaunchEnvironment: [String: String] {
    var env = ["KANPAN_TEST_INTERVAL": "1m"]
    // 网关线路的币安品种 K 线走 OKX 替身；大单那一层与线路无关，照样按品种表订全部簿。
    if name.contains("Gateway") {
      env["KANPAN_TEST_ROUTE_POLICY"] = "gateway"
      env["KANPAN_TEST_DEEPLINK"] = "hkline://symbol/SOLUSDT?interval=1m"
    }
    if name.contains("Coinbase") { env["KANPAN_TEST_DEEPLINK"] = "hkline://symbol/coinbase/spot/BTC-USD?interval=1m" }
    // 线路种子只在「档案里还没有存档」时生效（PrefsStore），所以取证用例每条都从一份新档案起步，
    // 不吃这台模拟器上一轮留下的线路 / 皮肤；只有首屏实测那条要用固定档案。
    env["KANPAN_PERSISTENCE_PROFILE"] = name.contains("ColdStartProfile") ? Self.coldStartProfile : UUID().uuidString
    return env
  }

  /// 首屏实测用的档案：这条用例在里面把开关打开并落盘，之后 `simctl launch` 带同一个档案冷启动。
  static let coldStartProfile = "0F10F10F-0000-4000-8000-000000000924"

  /// 截图文件名前缀：跑在哪台模拟器上就用哪台的名字（去空格），如 iPhone17ProMax。
  private static let device = (ProcessInfo.processInfo.environment["SIMULATOR_DEVICE_NAME"] ?? "iPhone").replacingOccurrences(of: " ", with: "")
  /// 取证图落在编出这份用例的那棵工作树里（按本文件路径推回仓库根），别的工作树跑时不写进共享工作树。
  private static let outDir = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    .appendingPathComponent("docs/acceptance/主力订单流-2026-09-24", isDirectory: true)

  private func shot(_ name: String) {
    let image = app.screenshot()
    let a = XCTAttachment(screenshot: image); a.name = name; a.lifetime = .keepAlways; add(a)
    try? FileManager.default.createDirectory(at: Self.outDir, withIntermediateDirectories: true)
    try? image.pngRepresentation.write(to: Self.outDir.appendingPathComponent("\(Self.device)-\(name).png"))
    print("取证|\(name)|phase=\(chartInfo()["orderFlowPhase"] ?? "")|orders=\(chartInfo()["orderFlowOrders"] ?? 0)|bands=\(bands().count)|hovered=\(chartInfo()["orderFlowHovered"] ?? false)|symbol=\(chartInfo()["symbol"] ?? "")")
  }

  private func bands() -> [[String: Any]] { chartInfo()["orderFlowBands"] as? [[String: Any]] ?? [] }

  /// 图表面板 → 指标 → 打开「主力订单流」→ 收面板。
  private func turnOnOrderFlow() {
    app.buttons[Ids.intervalChart].tap()
    XCTAssertTrue(app.openIndicatorPage(), "图表设置面板里点「指标」没进到指标页")
    let toggle = app.buttons[Ids.indicatorSwitch("ORDERFLOW")]
    expectExists(toggle, Self.short, "主图叠加里没有「主力订单流」")
    toggle.tap()
    let macd = app.buttons[Ids.indicatorSwitch("MACD")]
    dismissSheet(until: macd)
    // 上面那一下「完成」只从指标页退回面板根页；面板整张收掉，底栏和画布才点得到。
    let header = app.staticTexts[Ids.panelHeader].firstMatch
    dismissSheet(until: header)
    XCTAssertTrue(waitUntil(timeout: Self.short) { !header.exists }, "图表设置面板收不掉")
  }

  /// 等簿就绪并且至少画出一条大单；返回等了几秒。
  @discardableResult
  private func waitForBands(_ what: String, timeout: TimeInterval = 150) -> TimeInterval {
    let start = Date()
    let ok = waitUntil(timeout: timeout, poll: 1) {
      self.chartInfo()["orderFlowPhase"] as? String == "ready" && !self.bands().isEmpty
    }
    let waited = Date().timeIntervalSince(start)
    print("取证|\(what)|等大单 \(Int(waited)) 秒|phase=\(chartInfo()["orderFlowPhase"] ?? "")|orders=\(chartInfo()["orderFlowOrders"] ?? 0)|bands=\(bands())")
    XCTAssertTrue(ok, "\(what)：\(Int(timeout)) 秒内没画出大单（phase=\(chartInfo()["orderFlowPhase"] ?? "")，orders=\(chartInfo()["orderFlowOrders"] ?? 0)）")
    return waited
  }

  /// 大单要等簿里真有一个价位过门槛（出现还要连着两次评估、间隔 ≥ 300 ms）。当前品种等不到，
  /// 就用深链换下一只接着等；返回最终画出大单的品种（都没等到返回 nil，并记失败）。
  @discardableResult
  private func waitForBandsRotating(_ what: String, symbols: [String], perSymbol: TimeInterval = 150) -> String? {
    for (k, symbol) in symbols.enumerated() {
      if k > 0 {
        app.open(URL(string: "hkline://symbol/\(symbol)?interval=1m")!)
        _ = waitUntil(timeout: 45, poll: 0.5) {
          (self.chartInfo()["symbol"] as? String ?? "").hasSuffix("/" + symbol) && (self.chartInfo()["bars"] as? Int ?? 0) >= 20
        }
      }
      let start = Date()
      let ok = waitUntil(timeout: perSymbol, poll: 1) {
        self.chartInfo()["orderFlowPhase"] as? String == "ready" && !self.bands().isEmpty
      }
      print("取证|\(what)|\(symbol)|等大单 \(Int(Date().timeIntervalSince(start))) 秒|ok=\(ok)|orders=\(chartInfo()["orderFlowOrders"] ?? 0)|bands=\(bands())")
      if ok { return symbol }
    }
    XCTFail("\(what)：\(symbols) 轮了一遍都没等到大单（phase=\(chartInfo()["orderFlowPhase"] ?? "")）")
    return nil
  }

  private func pickSkin(_ skin: String, _ mode: String) {
    openSettingsPage()
    let card = app.buttons["display.theme." + skin]
    expectExists(card, Self.short, "设置页上没有皮肤卡 \(skin)")
    XCTAssertTrue(waitUntil(timeout: Self.short) { card.isHittable }, "皮肤卡点不到")
    if (card.value as? String) != "已选" { card.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap() }
    let segment = app.buttons["display.mode." + mode]
    expectExists(segment, Self.short, "设置页上没有深浅档")
    if !segment.isSelected { segment.tap() }
    XCTAssertTrue(waitUntil(timeout: Self.short) { (card.value as? String) == "已选" && segment.isSelected })
    leaveSettings()
    XCTAssertTrue(waitUntil(timeout: Self.short) { self.app.buttons[Ids.intervalChart].exists })
  }

  // ------------------------------------------------------------ 1. 币安直连：四套配色 + 十字线

  func testBinanceDirectSkinsAndCrosshair() {
    executionTimeAllowance = 2700
    XCTAssertTrue(waitForLiveChart(), "币安直连没出图：\(chartInfo())")
    turnOnOrderFlow()
    guard let symbol = waitForBandsRotating("币安直连", symbols: ["BTCUSDT", "ETHUSDT"]) else { return }
    print("取证|币安直连|拍摄品种 \(symbol)")
    for (skin, mode, title) in [("sage", "浅色", "青苔浅"), ("sage", "深色", "青苔深"),
                                ("classic", "浅色", "经典浅"), ("classic", "深色", "经典深")] {
      pickSkin(skin, mode)
      // 已结束的单也留在图上，换完皮肤回来大单照样在；保险起见仍等它出现才拍，不拍空图。
      let back = waitUntil(timeout: 240, poll: 1) { !self.bands().isEmpty }
      XCTAssertTrue(back, "\(title)：换完皮肤 240 秒没等回大单")
      shot(title)
    }

    // 十字线：长按到一条大单的横向中点、竖向中线上，读数换成这一单的明细，那一块亮到 1.0。
    let canvas = app.otherElements["chart.canvas"]
    let origin = canvas.coordinate(withNormalizedOffset: .zero)
    var hovered = false
    for attempt in 0..<6 where !hovered {
      guard waitUntil(timeout: 240, poll: 1, { !self.bands().isEmpty }) else { break }
      let info = chartInfo()
      let plotW = info["plotW"] as? Double ?? 300
      // 挑最宽的一块（最好按），几轮按不中就换下一块。
      let sorted = bands().sorted { ($0["w"] as? Double ?? 0) > ($1["w"] as? Double ?? 0) }
      let band = sorted[min(attempt, sorted.count - 1)]
      let bx = band["x"] as? Double ?? 0, bw = band["w"] as? Double ?? 0, by = band["y"] as? Double ?? 0
      // 这个点必须留在绘图区里（右边就是价格轴，按上去不出十字线）。
      let x = min(plotW - 2, max(1, bx + bw / 2))
      if chartInfo()["crosshair"] as? Bool == true { origin.withOffset(CGVector(dx: 40, dy: 40)).tap() }
      origin.withOffset(CGVector(dx: x, dy: by)).press(forDuration: 0.6)
      hovered = waitUntil(timeout: 3) { self.chartInfo()["orderFlowHovered"] as? Bool == true }
      print("取证|十字线|按在 (\(x), \(by))|band=\(band)|crossY=\(chartInfo()["crossY"] ?? -1)|hovered=\(hovered)")
    }
    XCTAssertTrue(hovered, "长按到大单上十字线没点亮它：\(bands())")
    shot("十字线读数")
  }

  // ------------------------------------------------------------ 2. 参数表：改门槛、显示开关

  private func thresholds() -> [String: Double] { chartInfo()["orderFlowThresholds"] as? [String: Double] ?? [:] }

  /// 把一格数字框改成 `value`：点进去（框会全选），删干净再打。
  private func retype(_ id: String, _ value: String) {
    let field = app.textFields[id]
    expectExists(field, Self.short, "参数表里没有 \(id)")
    field.tap()
    _ = waitUntil(timeout: 1) { false }
    field.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: 16) + value)
  }

  /// 图表面板 → 指标 → 「正在用」里的主力订单流那一行 → 参数表。
  private func openOrderFlowEditor() {
    app.buttons[Ids.intervalChart].tap()
    XCTAssertTrue(app.openIndicatorPage(), "图表设置面板里点「指标」没进到指标页")
    let edit = app.buttons["indicator.edit.ORDERFLOW"].firstMatch
    expectExists(edit, Self.short, "「正在用」里没有主力订单流那一行")
    edit.tap()
    expectExists(app.buttons["orderflow.save"], Self.short, "点了主力订单流没开出参数表")
  }

  /// 参数表收起后从指标页一路退回图表。
  private func closePanels() {
    let macd = app.buttons[Ids.indicatorSwitch("MACD")]
    if macd.waitForExistence(timeout: Self.short) { dismissSheet(until: macd) }
    let header = app.staticTexts[Ids.panelHeader].firstMatch
    if header.exists { dismissSheet(until: header) }
    XCTAssertTrue(waitUntil(timeout: Self.short) { !header.exists }, "图表设置面板收不掉")
  }

  func testThresholdEditTakesEffect() {
    executionTimeAllowance = 1800
    XCTAssertTrue(waitForLiveChart(), "币安直连没出图：\(chartInfo())")
    turnOnOrderFlow()
    XCTAssertTrue(waitUntil(timeout: 90, poll: 1) {
      self.chartInfo()["orderFlowPhase"] as? String == "ready" && self.thresholds()["usdtPerp"] != nil
    }, "簿没就绪：\(chartInfo())")
    // 给默认门槛一分钟攒单，拍一张「改之前」。
    _ = waitUntil(timeout: 60, poll: 1) { false }
    let before = thresholds(), ordersBefore = chartInfo()["orderFlowOrders"] as? Int ?? 0
    print("取证|改门槛前|thresholds=\(before)|orders=\(ordersBefore)|bands=\(bands().count)")
    XCTAssertEqual(before["usdtPerp"], 5_000_000, "BTC U本位永续默认门槛应为 500 万")
    shot("改门槛前")

    openOrderFlowEditor()
    shot("参数表")
    retype("orderflow.threshold.usdtPerp.field", "1000000")
    retype("orderflow.threshold.spot.field", "300000")
    shot("参数表-改门槛")
    app.buttons["orderflow.save"].tap()
    // 回到指标页，「正在用」那一行报「已改门槛」。
    let edit = app.buttons["indicator.edit.ORDERFLOW"].firstMatch
    XCTAssertTrue(waitUntil(timeout: Self.short) { edit.exists && edit.label.contains("已改门槛") },
                  "保存后「正在用」没报已改门槛：\(edit.label)")
    closePanels()

    XCTAssertTrue(waitUntil(timeout: 20, poll: 0.5) {
      self.thresholds()["usdtPerp"] == 1_000_000 && self.thresholds()["spot"] == 300_000
    }, "新门槛没到簿那一层：\(thresholds())")
    let more = waitUntil(timeout: 150, poll: 1) { (self.chartInfo()["orderFlowOrders"] as? Int ?? 0) > ordersBefore }
    print("取证|改门槛后|thresholds=\(thresholds())|orders=\(chartInfo()["orderFlowOrders"] ?? 0)|bands=\(bands().count)")
    XCTAssertTrue(more, "门槛调低后大单没变多（前 \(ordersBefore) 条）")
    // 门槛调低后，新出现的 U本位永续大单里应有名义在 100 万–500 万之间的（证据写在日志里）。
    shot("改门槛后")

    // 显示开关：关掉「合约」，图上只剩现货。
    openOrderFlowEditor()
    let contract = app.switches["orderflow.show.contract"]
    expectExists(contract, Self.short, "参数表里没有「合约」开关")
    if !contract.isHittable { app.swipeUp() }
    contract.coordinate(withNormalizedOffset: CGVector(dx: 0.9, dy: 0.5)).tap()
    XCTAssertTrue(waitUntil(timeout: 3) { (contract.value as? String) == "0" }, "「合约」开关没关上")
    shot("参数表-关合约")
    app.buttons["orderflow.save"].tap()
    closePanels()
    let onlySpot = waitUntil(timeout: 20, poll: 0.5) {
      let b = self.bands(); return b.allSatisfy { ($0["product"] as? String) == "spot" }
    }
    print("取证|关合约|bands=\(bands().map { $0["product"] ?? "" })")
    XCTAssertTrue(onlySpot, "关掉合约后图上还有合约大单：\(bands())")
    shot("只看现货")
  }

  // ------------------------------------------------------------ 3. 网关：OKX 替身

  func testGatewayOKX() {
    let source = app.staticTexts["market.source"]
    XCTAssertTrue(waitUntil(timeout: Self.long * 2, poll: 0.5) {
      source.exists && source.label == "okx" && (source.value as? String) == "live"
    }, "网关线路没换到 OKX：source=\(source.label)")
    XCTAssertTrue(waitUntil(timeout: 45, poll: 0.5) {
      (self.chartInfo()["symbol"] as? String ?? "").hasSuffix("/SOLUSDT") && (self.chartInfo()["bars"] as? Int ?? 0) >= 20
    }, "深链开 SOLUSDT 没出图：\(chartInfo())")
    executionTimeAllowance = 1200
    turnOnOrderFlow()
    guard let symbol = waitForBandsRotating("OKX 网关", symbols: ["SOLUSDT", "DOGEUSDT", "ETHUSDT"]) else { return }
    shot("OKX网关-" + symbol)
  }

  // ------------------------------------------------------------ 4. Coinbase 现货

  func testCoinbaseBTCUSD() {
    XCTAssertTrue(waitUntil(timeout: 45, poll: 0.5) {
      self.chartInfo()["symbol"] as? String == "coinbase/spot/BTC-USD" && (self.chartInfo()["bars"] as? Int ?? 0) >= 20
    }, "深链开 BTC-USD 没出图：\(chartInfo())")
    turnOnOrderFlow()
    waitForBands("Coinbase BTC-USD")
    shot("Coinbase-BTC-USD")
  }

  // ------------------------------------------------------------ 5. 静置 10 秒重画了几次（审查 31）

  /// 开着主力订单流、手不碰屏幕放 10 秒：底图（plot 层）真画了几次、订单流快照换了几次。
  /// 读数来自 `chart.canvas` 诊断里的 `renderCounts` / `orderFlowAdoptions`（DEBUG 才有），前后相减。
  /// 本身不判数，改 `sameContent` 前后各跑一遍对比；蜡烛跟着成交推进也会画 plot，所以两个数都报。
  func testIdleRedrawTenSeconds() {
    executionTimeAllowance = 900
    XCTAssertTrue(waitForLiveChart(), "币安直连没出图：\(chartInfo())")
    turnOnOrderFlow()
    guard waitForBandsRotating("静置重画", symbols: ["BTCUSDT", "ETHUSDT"]) != nil else { return }
    _ = waitUntil(timeout: 5, poll: 1) { false }
    func counts() -> (plot: Int, cross: Int, live: Int, frames: Int) {
      let info = chartInfo(), r = info["renderCounts"] as? [String: Int] ?? [:]
      return (r["plot"] ?? 0, r["cross"] ?? 0, r["live"] ?? 0, info["orderFlowAdoptions"] as? Int ?? 0)
    }
    let a = counts()
    _ = waitUntil(timeout: 10, poll: 10) { false }
    let b = counts()
    print("取证|静置10秒|plot=\(b.plot - a.plot)|cross=\(b.cross - a.cross)|live=\(b.live - a.live)|orderFlowFrames=\(b.frames - a.frames)|orders=\(chartInfo()["orderFlowOrders"] ?? 0)")
  }

  // ------------------------------------------------------------ 6. 首屏实测的档案

  /// 只做准备：在固定档案里打开「主力订单流」，等它真的开始订簿（阶段不再是空），开关已落盘。
  /// 冷启动计时在测试外面用 `simctl launch --console-pty` 做（见验收报告）。
  func testPrepareColdStartProfile() {
    XCTAssertTrue(waitForLiveChart(), "没出图：\(chartInfo())")
    turnOnOrderFlow()
    XCTAssertTrue(waitUntil(timeout: 30) { !(self.chartInfo()["orderFlowPhase"] as? String ?? "").isEmpty },
                  "打开开关后没开始订簿")
  }
}
