import XCTest

// ============================================================ Coinbase 现货（多交易所阶段 3/4/5）
//
// 以用户的身份走一遍 Coinbase BTC-USD：搜代号 → 加星 → 进图 → 1m / 1h / 1w 都有图、
// 顶栏最新价在跳 → 自选页里它落在「Coinbase」那一类 → 切到「网关」线路再看一遍
// （网关那条走 kanpan-api 的 `/v1/market/raw` 与 `/v1/market/stream` 透传）。
// 每一屏都查一次：界面上只出现显示代号 BTC/USD，绝不露出 `coinbase/spot/BTC-USD` 这种内部键。
//
// 要真网络（直连 api.coinbase.com / advanced-trade-ws.coinbase.com，网关走线上 kanpan-api）。

@MainActor
final class CoinbaseVenueUITests: KanpanUICase {

  private let profile = UUID().uuidString
  override var extraLaunchEnvironment: [String: String] {
    var env = ["KANPAN_PERSISTENCE_PROFILE": profile]
    // 「回前台接着跳」「画线加提醒」两条直接从深链开 BTC-USD，不走搜索。
    if name.contains("Background") { env["KANPAN_TEST_DEEPLINK"] = "hkline://symbol/coinbase/spot/BTC-USD?interval=1m" }
    if name.contains("Drawing") { env["KANPAN_TEST_DEEPLINK"] = "hkline://symbol/coinbase/spot/BTC-USD?interval=1h" }
    return env
  }

  private let key = "coinbase/spot/BTC-USD"

  private func shot(_ name: String) {
    let a = XCTAttachment(screenshot: app.screenshot()); a.name = name; a.lifetime = .keepAlways; add(a)
    let s = XCTAttachment(string: String(describing: chartInfo())); s.name = name + "-读数"; s.lifetime = .keepAlways
    add(s)
  }

  /// 当前这一屏上有没有哪个元素的文字露出了内部键。
  private func assertNoInternalKey(_ screen: String, file: StaticString = #filePath, line: UInt = #line) {
    let leak = app.descendants(matching: .any).matching(
      NSPredicate(format: "label CONTAINS[c] 'coinbase/spot' OR label CONTAINS[c] 'binance/usd_m' OR value CONTAINS[c] 'coinbase/spot/BTC'"))
    // `chart.canvas` 与 `review.range` 的 value、`market.*` 那几条 1pt 透明文字都是 DEBUG 诊断
    // （只有带 KANPAN_CHART_DIAGNOSTICS 才有，正式包里整块 `#if DEBUG` 掉），不是给人看的文字。
    let diagnostics: Set<String> = ["chart.canvas", "review.range"]
    let visible = leak.allElementsBoundByIndex.filter {
      !diagnostics.contains($0.identifier) && !$0.identifier.hasPrefix("market.")
    }
    XCTAssertTrue(visible.isEmpty, "\(screen)露出了内部键：\(visible.map { "\($0.identifier)=\($0.label)" })",
                  file: file, line: line)
  }

  private func waitChart(_ interval: String, _ seconds: TimeInterval = 45) -> Bool {
    waitUntil(timeout: seconds, poll: 0.5) {
      let d = self.chartInfo()
      return d["symbol"] as? String == self.key && d["interval"] as? String == interval
        && (d["bars"] as? Int ?? 0) >= 20 && (d["lastClose"] as? Double ?? 0) > 1000
    }
  }

  /// 顶栏最新价在 `seconds` 内变过一次（= 推送真的在来）。
  private func priceTicks(_ seconds: TimeInterval = 45) -> (Bool, String, String) {
    let price = app.descendants(matching: .any).matching(identifier: "top.lastPrice").firstMatch
    guard price.waitForExistence(timeout: Self.short) else { return (false, "", "") }
    let first = price.label
    let changed = waitUntil(timeout: seconds, poll: 0.3) { !price.label.isEmpty && price.label != first }
    return (changed, first, price.label)
  }

  private func openCoinbaseFromSearch() {
    XCTAssertTrue(app.openSymbolSearch(), "顶栏放大镜没进搜索页")
    let query = app.textFields[Ids.searchQuery]
    query.tap(); query.typeText("BTC-USD")
    let row = app.buttons["symbols.row." + key]
    XCTAssertTrue(row.waitForExistence(timeout: 30), "搜 BTC-USD 没出 Coinbase 那一行")
    // 行是个 `.contain` 容器，名字在它里面的文字上。
    let name = row.staticTexts.matching(NSPredicate(format: "label MATCHES '.*BTC ?/ ?USD.*'")).firstMatch
    XCTAssertTrue(name.waitForExistence(timeout: Self.short),
                  "搜索行没写成 BTC/USD：\(row.staticTexts.allElementsBoundByIndex.map(\.label))")
    shot("搜索-BTC-USD")
    assertNoInternalKey("搜索页")
    let star = app.buttons["symbols.star." + key]
    XCTAssertTrue(star.waitForExistence(timeout: Self.short), "搜索行上没有星")
    star.tap()
    row.tap()
  }

  func testCoinbaseBTCUSDChartsLiveInBothRoutes() {
    openCoinbaseFromSearch()

    // 进图：1m / 1h / 1w 都要有图（1w 是由日线聚出来的，Coinbase 没有原生周线）。
    for raw in ["1m", "1h", "1w"] {
      app.tapIntervalChip(raw)
      XCTAssertTrue(waitChart(raw), "直连下 \(raw) 没出 Coinbase 的图：\(chartInfo())")
      shot("直连-\(raw)")
    }
    let top = app.symbolLabel.label.replacingOccurrences(of: " ", with: "")
    XCTAssertTrue(top.contains("BTC/USD"), "顶栏品种名不是 BTC/USD：\(app.symbolLabel.label)")
    assertNoInternalKey("行情页")
    app.tapIntervalChip("1m")
    XCTAssertTrue(waitChart("1m"))
    let direct = priceTicks()
    XCTAssertTrue(direct.0, "直连下顶栏最新价 45s 没跳过：\(direct.1)")
    shot("直连-实时价")

    // 自选页：落在「Coinbase」那一类。
    app.buttons[Ids.bottomFavorites].tap()
    let group = app.buttons["favorites.group.Coinbase"]
    XCTAssertTrue(group.waitForExistence(timeout: Self.short), "自选页没有「Coinbase」这一类")
    // 只有这一类时它本来就是选中的；切页动画没停时 XCUI 会判它「not hittable」，按坐标点。
    if !group.isSelected { group.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap() }
    let open = app.descendants(matching: .any).matching(NSPredicate(format: "identifier BEGINSWITH 'favorites.open.' AND identifier CONTAINS 'BTC-USD'")).firstMatch
    XCTAssertTrue(open.waitForExistence(timeout: Self.short), "「Coinbase」这一类里没有 BTC/USD")
    let price = app.descendants(matching: .any).matching(NSPredicate(format: "identifier BEGINSWITH 'favorites.price.' AND identifier CONTAINS 'BTC-USD'")).firstMatch
    XCTAssertTrue(waitUntil(timeout: 30) { price.exists && price.label.contains(where: \.isNumber) },
                  "自选行没有价格：\(price.label)")
    shot("自选-Coinbase")
    assertNoInternalKey("自选页")

    // 切到「网关」：Coinbase 的 REST 与推送都改走 kanpan-api 的透传。
    openSettingsPage()
    let gateway = app.buttons["settings.routePolicy.网关"]
    XCTAssertTrue(gateway.waitForExistence(timeout: Self.short)); gateway.tap()
    XCTAssertTrue(waitUntil(timeout: Self.short) { gateway.isSelected }, "「网关」没选中")
    leaveSettings()
    for raw in ["1h", "1m"] {
      app.tapIntervalChip(raw)
      XCTAssertTrue(waitChart(raw), "网关下 \(raw) 没出 Coinbase 的图：\(chartInfo())")
      shot("网关-\(raw)")
    }
    // 真的走了网关：DEBUG 网络诊断里 Coinbase 的推送连到 kanpan-api 的透传口。
    let network = app.descendants(matching: .any).matching(identifier: "market.network").firstMatch
    XCTAssertTrue(waitUntil(timeout: 30) {
      network.exists && network.label.contains("sslip.io/v1/market/stream?source=coinbase")
    }, "网关下 Coinbase 推送没连到 kanpan-api 透传口：\(network.label.suffix(1500))")
    let wire = XCTAttachment(string: network.label); wire.name = "网关-网络诊断"; wire.lifetime = .keepAlways
    add(wire)
    let viaGateway = priceTicks()
    XCTAssertTrue(viaGateway.0, "网关下顶栏最新价 45s 没跳过：\(viaGateway.1)")
    shot("网关-实时价")
    assertNoInternalKey("网关-行情页")

    // 切回「直连」，图接着活。
    openSettingsPage()
    let directButton = app.buttons["settings.routePolicy.直连"]
    directButton.tap()
    XCTAssertTrue(waitUntil(timeout: Self.short) { directButton.isSelected })
    leaveSettings()
    XCTAssertTrue(waitChart("1m"))
    XCTAssertTrue(priceTicks().0, "切回直连后最新价不跳")
    shot("切回直连")
  }
  /// 在 Coinbase 的图上画一条水平线、挂上提醒：选中栏那颗「涨到 / 跌到 X 叫我」点一下
  /// 就挂上，提醒总表里这一条写的是 BTC/USD（不是和币安 BTC 永续分不出来的「BTC」），
  /// 两屏都不露内部键。
  func testCoinbaseDrawingAndLineAlert() {
    XCTAssertTrue(waitChart("1h"), "深链开 BTC-USD 1h 没出图：\(chartInfo())")
    XCTAssertTrue(app.enterDrawingInPortrait(), "没进竖屏画线态")
    let canvas = app.otherElements["chart.canvas"]
    let chip = app.buttons["alert.line"]
    var drawn = false
    for round in 0..<3 where !drawn {
      let before = (chartInfo()["drawingIDs"] as? [String])?.count ?? 0
      let hline = app.buttons["draw.hline"]
      if !hline.waitForExistence(timeout: 5) {
        // 上一轮落了笔、线自动选中后顶栏换成了选中栏，工具从「工具」面板里拿。
        app.buttons["draw.tools"].tap()
        let tool = app.buttons["draw.tool.hline"]
        guard tool.waitForExistence(timeout: 5) else { continue }
        tool.tap()
      } else {
        hline.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
      }
      canvas.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.18 + Double(round) * 0.05)).tap()
      drawn = waitUntil(timeout: 5) { ((self.chartInfo()["drawingIDs"] as? [String])?.count ?? 0) > before }
        && chip.waitForExistence(timeout: 5)
    }
    XCTAssertTrue(drawn, "Coinbase 图上画不出水平线 / 选中栏没有提醒胶囊：\(chartInfo())")
    shot("画线-选中栏")
    assertNoInternalKey("画线选中栏")
    chip.tap()
    // 新装的模拟器第一次挂提醒会弹系统通知授权，放行它。
    let allow = XCUIApplication(bundleIdentifier: "com.apple.springboard").alerts.buttons
      .matching(NSPredicate(format: "label IN %@", ["允许", "Allow"])).firstMatch
    if allow.waitForExistence(timeout: 4) { allow.tap() }
    XCTAssertTrue(waitUntil(timeout: 10) { !((self.chartInfo()["drawingAlerted"] as? [String]) ?? []).isEmpty },
                  "点了提醒胶囊线上没挂上铃：\(chartInfo())")
    shot("画线-已挂提醒")
    let finish = app.buttons["draw.finish"]
    if finish.exists { finish.tap() }

    // 提醒总表：这一条写 BTC/USD。设置里没有「提醒」那一行了（2026-09-25），走深链开总表。
    app.open(URL(string: "hkline://alerts")!)
    let page = app.descendants(matching: .any).matching(identifier: "alerts.page").firstMatch
    XCTAssertTrue(page.waitForExistence(timeout: Self.short), "提醒总表没打开")
    let named = app.staticTexts.matching(NSPredicate(format: "label CONTAINS 'BTC/USD'")).firstMatch
    XCTAssertTrue(named.waitForExistence(timeout: Self.short),
                  "提醒总表里这一条没写成 BTC/USD：\(app.staticTexts.allElementsBoundByIndex.prefix(40).map(\.label))")
    shot("提醒总表")
    assertNoInternalKey("提醒总表")
  }

  /// 断流后接得上：退到后台 40 秒（系统会挂起 app、推送连接跟着断），再回前台，
  /// 图还是 BTC/USD、最新价接着跳。真拔网会把整台 Mac（含 Surge）一起断掉，所以用
  /// 挂起这条同样会让 socket 失效的路来验重连；网络诊断全文附在结果里。
  func testCoinbaseResumesAfterBackground() {
    XCTAssertTrue(waitChart("1m"), "深链开 BTC-USD 没出图：\(chartInfo())")
    XCTAssertTrue(priceTicks().0, "起来后最新价不跳")
    XCUIDevice.shared.press(.home)
    XCTAssertTrue(app.wait(for: .runningBackgroundSuspended, timeout: 20) || app.state == .runningBackground,
                  "按了主屏键 app 没退到后台：\(app.state.rawValue)")
    Thread.sleep(forTimeInterval: 40)
    app.activate()
    XCTAssertTrue(waitChart("1m"), "回前台后图没了：\(chartInfo())")
    let resumed = priceTicks()
    XCTAssertTrue(resumed.0, "回前台 45s 最新价没再跳：\(resumed.1)")
    shot("回前台-实时价")
    let network = app.descendants(matching: .any).matching(identifier: "market.network").firstMatch
    let wire = XCTAttachment(string: network.exists ? network.label : "(无诊断)")
    wire.name = "回前台-网络诊断"; wire.lifetime = .keepAlways; add(wire)
    assertNoInternalKey("回前台-行情页")
  }
}
