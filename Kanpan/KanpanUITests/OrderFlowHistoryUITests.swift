import XCTest

// ============================================================ 主力订单流 · 服务端历史回填验收（2026-09-24）
//
// 用户要的是：手机随时切后台、偶尔看一眼，也能看到 7 天 / 30 天内的过往大单。本机只记本机看见过的，
// 更早的由 kanpan-api 常驻跟簿、存 30 天，app 打开时取最近 24 小时并进来，往左拖再按 24 小时一段往前补。
//
// 用例：一份新档案（本机日志是空的）打开 BTCUSDT，在指标页打开「主力订单流」并落盘，杀掉 app 冷启动；
// 冷启动后 5 秒内图上要有大单，而且手上最早一条的「出现时刻」早于这条用例开始——本机在那之前
// 一条簿都没订过，所以早于它的只能是从服务端历史并进来的。
//
// 数字读两处：`chart.canvas` 诊断里的 `orderFlowOrders`（图拿到的条数），以及主界面 DEBUG 诊断
// `orderflow.diagnostics`（`orders=…;earliest=<毫秒>;live=…`）。图写进 `docs/acceptance/主力订单流-2026-09-24/`。
@MainActor
final class OrderFlowHistoryUITests: KanpanUICase {

  /// 每次一份新档案：缓存根（含订单流日志 `orderflow/`）按档案分目录，保证本机日志是空的。
  private let profile = UUID().uuidString

  override var extraLaunchEnvironment: [String: String] {
    ["KANPAN_TEST_INTERVAL": "1m",
     "KANPAN_TEST_DEEPLINK": "hkline://symbol/BTCUSDT?interval=1m",
     "KANPAN_PERSISTENCE_PROFILE": profile]
  }

  private static let outDir = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    .appendingPathComponent("docs/acceptance/主力订单流-2026-09-24", isDirectory: true)

  /// `orderflow.diagnostics` 解析成字典（orders / earliest / live）。
  private func flowInfo() -> [String: Int64] {
    let el = app.staticTexts["orderflow.diagnostics"].firstMatch
    guard el.exists, let text = el.value as? String else { return [:] }
    var out: [String: Int64] = [:]
    for pair in text.split(separator: ";") {
      let kv = pair.split(separator: "=", maxSplits: 1)
      if kv.count == 2, let v = Int64(kv[1]) { out[String(kv[0])] = v }
    }
    return out
  }

  /// `orderflow.diagnostics` 里的 `books=` 与 `counts=`：各本簿就绪与否、每本簿手上的单数。
  private func flowBooks() -> (ready: [String: Bool], counts: [String: Int]) {
    let el = app.staticTexts["orderflow.diagnostics"].firstMatch
    guard el.exists, let text = el.value as? String else { return ([:], [:]) }
    var ready: [String: Bool] = [:], counts: [String: Int] = [:]
    for pair in text.split(separator: ";") {
      let kv = pair.split(separator: "=", maxSplits: 1)
      guard kv.count == 2 else { continue }
      for item in kv[1].split(separator: "|") {
        guard let colon = item.lastIndex(of: ":") else { continue }
        let key = String(item[..<colon]); let value = String(item[item.index(after: colon)...])
        if kv[0] == "books" { ready[key] = value == "1" } else if kv[0] == "counts" { counts[key] = Int(value) ?? 0 }
      }
    }
    return (ready, counts)
  }

  private func turnOnOrderFlow() {
    app.buttons[Ids.intervalChart].tap()
    XCTAssertTrue(app.openIndicatorPage(), "图表设置面板里点「指标」没进到指标页")
    let toggle = app.buttons[Ids.indicatorSwitch("ORDERFLOW")]
    expectExists(toggle, Self.short, "主图叠加里没有「主力订单流」")
    toggle.tap()
    dismissSheet(until: app.buttons[Ids.indicatorSwitch("MACD")])
    let header = app.staticTexts[Ids.panelHeader].firstMatch
    dismissSheet(until: header)
    XCTAssertTrue(waitUntil(timeout: Self.short) { !header.exists }, "图表设置面板收不掉")
  }

  func testServerHistoryAfterColdStart() {
    let beforeMs = Int64(Date().timeIntervalSince1970 * 1000)
    XCTAssertTrue(waitForLiveChart(), "没出图：\(chartInfo())")
    turnOnOrderFlow()
    XCTAssertTrue(waitUntil(timeout: 30) { !(self.chartInfo()["orderFlowPhase"] as? String ?? "").isEmpty },
                  "打开开关后没开始订簿")

    // 冷启动：同一份档案（开关已落盘），K 线快照与品种表也都在盘上。
    app.terminate()
    let launch = Date()
    app.launch()
    let chartTab = app.buttons[Ids.bottomChart]
    if chartTab.waitForExistence(timeout: 3), !app.symbolLabel.exists { chartTab.tap() }
    var seen: (orders: Int, earliest: Int64, live: Int64) = (0, 0, 0)
    let ok = waitUntil(timeout: 5 - Date().timeIntervalSince(launch), poll: 0.2) {
      let flow = self.flowInfo()
      let orders = self.chartInfo()["orderFlowOrders"] as? Int ?? 0
      seen = (orders, flow["earliest"] ?? 0, flow["live"] ?? 0)
      return orders > 0 && seen.earliest > 0 && seen.earliest < beforeMs
    }
    let waited = Date().timeIntervalSince(launch)
    let flow = flowInfo()
    print("取证|历史回填|冷启动到有服务端大单 \(String(format: "%.2f", waited)) 秒|ok=\(ok)|chartOrders=\(seen.orders)|diag=\(flow)|用例开始=\(beforeMs)|最早早于用例开始 \((beforeMs - (flow["earliest"] ?? beforeMs)) / 60_000) 分钟|phase=\(chartInfo()["orderFlowPhase"] ?? "")|bands=\((chartInfo()["orderFlowBands"] as? [Any])?.count ?? 0)")
    XCTAssertTrue(ok, "冷启动 5 秒内没见到服务端历史：chartOrders=\(seen.orders) earliest=\(seen.earliest) 用例开始=\(beforeMs)")

    // 等簿也就绪、带画出来再拍（拍图不算进 5 秒）。
    _ = waitUntil(timeout: 20, poll: 0.5) { self.chartInfo()["orderFlowPhase"] as? String == "ready" }
    let image = app.screenshot()
    let a = XCTAttachment(screenshot: image); a.name = "历史回填-17ProMax"; a.lifetime = .keepAlways; add(a)
    try? FileManager.default.createDirectory(at: Self.outDir, withIntermediateDirectories: true)
    try? image.pngRepresentation.write(to: Self.outDir.appendingPathComponent("历史回填-17ProMax.png"))
    print("取证|历史回填|拍图|chartOrders=\(chartInfo()["orderFlowOrders"] ?? 0)|diag=\(flowInfo())|bands=\((chartInfo()["orderFlowBands"] as? [Any])?.count ?? 0)")
  }

  // ------------------------------------------------------------ 三家的簿都要接上（用户 2026-09-24：「btc okx现货也接上才行」）

  /// BTC 打开主力订单流后，币安四本、OKX 三本（含现货 BTC-USDT）、Coinbase 现货 BTC-USD 都要就绪，
  /// 而且 OKX 现货这本簿手上要有单（本机跟到的或服务端历史并进来的都算）。
  func testAllBooksReadyIncludingOKXSpot() {
    XCTAssertTrue(waitForLiveChart(), "没出图：\(chartInfo())")
    turnOnOrderFlow()
    let must = ["OKX/spot/BTC-USDT", "OKX/usdtPerp/BTC-USDT-SWAP", "Coinbase/spot/BTC-USD", "币安/spot/BTCUSDT", "币安/usdtPerp/BTCUSDT"]
    let ok = waitUntil(timeout: 90, poll: 1) {
      let books = self.flowBooks()
      return must.allSatisfy { books.ready[$0] == true } && (books.counts["okx:spot:BTC-USDT"] ?? 0) > 0
    }
    let books = flowBooks()
    let readyList = books.ready.keys.sorted().map { "\($0)=\(books.ready[$0]! ? 1 : 0)" }.joined(separator: " ")
    let countList = books.counts.keys.sorted().map { "\($0)=\(books.counts[$0]!)" }.joined(separator: " ")
    print("取证|三家簿|ok=\(ok)|books: \(readyList)|counts: \(countList)")
    XCTAssertTrue(ok, "簿没全就绪或 OKX 现货没出单：\(readyList) / \(countList)")
  }
}
