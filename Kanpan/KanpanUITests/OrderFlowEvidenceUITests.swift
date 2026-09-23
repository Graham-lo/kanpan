import XCTest

// ============================================================ 主力订单流 · 验收取证（2026-09-24）
//
// 以用户的身份打开「主力订单流」：图表面板 → 指标 → 主图叠加第七行的开关，等挂单簿就绪、
// 色带真的画出来，然后拍图。三条用例：
//
// 1. 币安直连 BTCUSDT：青苔浅 / 青苔深 / 经典浅 / 经典深四张，再长按一条色带拍十字线读数。
// 2. 网关线路（上游换成 OKX 替身，深度走 `/market/okx/stream`），品种 SOLUSDT。
// 3. Coinbase 现货 BTC-USD（深度恒走 Coinbase 直连）。
//
// 色带画在 CoreGraphics 上，读屏树里没有；等待与取点都读 `chart.canvas` 诊断里的
// `orderFlowPhase` / `orderFlowBands` / `orderFlowHovered`（DEBUG 才有）。
// 图写进 `docs/acceptance/主力订单流-2026-09-24/`，同时挂一份附件进 xcresult。
@MainActor
final class OrderFlowEvidenceUITests: KanpanUICase {

  override var extraLaunchEnvironment: [String: String] {
    var env = ["KANPAN_TEST_INTERVAL": "1m"]
    // 网关线路的币安品种走 OKX 替身。OKX `books` 只给 400 档：BTC 那 400 档只摊到中间价两侧 6–8 bps
    // （= 一个 8 bps 桶），天生挑不出大单，所以 OKX 这张拍 SOLUSDT（400 档摊到两侧约 350 bps）。
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
  private static let outDir = URL(
    fileURLWithPath: "/Users/mdd/zhk/kanpan/docs/acceptance/主力订单流-2026-09-24", isDirectory: true)

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

  /// 等簿就绪并且至少画出一条色带；返回等了几秒。
  @discardableResult
  private func waitForBands(_ what: String, timeout: TimeInterval = 150) -> TimeInterval {
    let start = Date()
    let ok = waitUntil(timeout: timeout, poll: 1) {
      self.chartInfo()["orderFlowPhase"] as? String == "ready" && !self.bands().isEmpty
    }
    let waited = Date().timeIntervalSince(start)
    print("取证|\(what)|等色带 \(Int(waited)) 秒|phase=\(chartInfo()["orderFlowPhase"] ?? "")|orders=\(chartInfo()["orderFlowOrders"] ?? 0)|bands=\(bands())")
    XCTAssertTrue(ok, "\(what)：\(Int(timeout)) 秒内没画出色带（phase=\(chartInfo()["orderFlowPhase"] ?? "")，orders=\(chartInfo()["orderFlowOrders"] ?? 0)）")
    return waited
  }

  /// 真墙是稀有事件：原项目判据（5 倍局部中位数、深度占比 ≥ 0.20、绝对下限）下，
  /// 2026-09-24 实测币安 BTC/ETH 过了 60 秒热身后常常一两分钟一条都没有。当前品种等不到，
  /// 就用深链换下一只接着等；返回最终画出色带的品种（都没等到返回 nil，并记失败）。
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
      print("取证|\(what)|\(symbol)|等色带 \(Int(Date().timeIntervalSince(start))) 秒|ok=\(ok)|orders=\(chartInfo()["orderFlowOrders"] ?? 0)|bands=\(bands())")
      if ok { return symbol }
    }
    XCTFail("\(what)：\(symbols) 轮了一遍都没等到色带（phase=\(chartInfo()["orderFlowPhase"] ?? "")）")
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
    guard let symbol = waitForBandsRotating("币安直连", symbols: ["BTCUSDT", "DOGEUSDT", "SOLUSDT", "ETHUSDT"]) else { return }
    print("取证|币安直连|拍摄品种 \(symbol)")
    for (skin, mode, title) in [("sage", "浅色", "青苔浅"), ("sage", "深色", "青苔深"),
                                ("classic", "浅色", "经典浅"), ("classic", "深色", "经典深")] {
      pickSkin(skin, mode)
      // 墙是来来去去的：换皮肤那十几秒里它可能撤了，等它（或新的一条）再出现才拍，不拍空图。
      let back = waitUntil(timeout: 240, poll: 1) { !self.bands().isEmpty }
      XCTAssertTrue(back, "\(title)：换完皮肤 240 秒没等回色带")
      shot(title)
    }

    // 十字线：长按到离最新价最近的那条色带上，读数换成这一条的明细，那一条亮到 0.9。
    let canvas = app.otherElements["chart.canvas"]
    let origin = canvas.coordinate(withNormalizedOffset: .zero)
    var hovered = false
    for _ in 0..<6 where !hovered {
      // 墙来来去去，撤了就等下一条（或它回来）再按。
      guard waitUntil(timeout: 240, poll: 1, { !self.bands().isEmpty }), let band = bands().first else { break }
      let info = chartInfo()
      let plotW = info["plotW"] as? Double ?? 300
      let spacing = info["spacing"] as? Double ?? 6
      let gap = info["latestRightGap"] as? Double ?? 0
      // 按在最新一根 K 线的中心上：刚冒出来的墙只从最新那根起画，十字线得吸到这根上才算停在色带上。
      // 这个点必须留在绘图区里（右边就是价格轴，按上去不出十字线）。
      let lastX = plotW - gap - spacing / 2
      let bx = band["x"] as? Double ?? 0, by = band["y"] as? Double ?? 0
      let x = min(plotW - 1, max(lastX, bx))
      if chartInfo()["crosshair"] as? Bool == true { origin.withOffset(CGVector(dx: 40, dy: 40)).tap() }
      origin.withOffset(CGVector(dx: x, dy: by)).press(forDuration: 0.6)
      hovered = waitUntil(timeout: 3) { self.chartInfo()["orderFlowHovered"] as? Bool == true }
      print("取证|十字线|按在 (\(x), \(by))|plotW=\(plotW)|crossY=\(chartInfo()["crossY"] ?? -1)|hovered=\(hovered)")
    }
    XCTAssertTrue(hovered, "长按到色带上十字线没点亮它：\(bands())")
    shot("十字线读数")
  }

  // ------------------------------------------------------------ 2. 网关：OKX 替身

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

  // ------------------------------------------------------------ 3. Coinbase 现货

  func testCoinbaseBTCUSD() {
    XCTAssertTrue(waitUntil(timeout: 45, poll: 0.5) {
      self.chartInfo()["symbol"] as? String == "coinbase/spot/BTC-USD" && (self.chartInfo()["bars"] as? Int ?? 0) >= 20
    }, "深链开 BTC-USD 没出图：\(chartInfo())")
    turnOnOrderFlow()
    waitForBands("Coinbase BTC-USD")
    shot("Coinbase-BTC-USD")
  }

  // ------------------------------------------------------------ 4. 首屏实测的档案

  /// 只做准备：在固定档案里打开「主力订单流」，等它真的开始订簿（阶段不再是空），开关已落盘。
  /// 冷启动计时在测试外面用 `simctl launch --console-pty` 做（见验收报告）。
  func testPrepareColdStartProfile() {
    XCTAssertTrue(waitForLiveChart(), "没出图：\(chartInfo())")
    turnOnOrderFlow()
    XCTAssertTrue(waitUntil(timeout: 30) { !(self.chartInfo()["orderFlowPhase"] as? String ?? "").isEmpty },
                  "打开开关后没开始订簿")
  }
}
