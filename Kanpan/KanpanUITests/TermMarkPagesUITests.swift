import XCTest

// ============================================================ 术语问号 · 第二阶段：各页的问号（2026-09-28）
//
// 第一阶段（`TermMarkTopBarUITests`）只挂了行情页顶栏。这一轮把「有歧义的词挂问号」铺到：
// 分析面板（买卖比、量差、均价线、抛物线、基差、多空比、门槛 / 步长）、图表设置（刻度）、设置（线路、
// 波动提醒、自动适应）、我的 › 交易所（回溯）、复盘本（盈亏比、每笔期望、费用占毛利、成交、已实现、
// 离开后）、创建提醒页（条件、Webhook）。
// 判据（用户 2026-09-28）：只给交易员读不出指什么的词挂，行业标准词（布林带、平滑异同、主力订单流、
// 盘口、画法、净盈亏、最大浮盈……）一律不挂——这里也钉住它们不许长出问号来。
//
// 每一页都是同一件事：点一颗问号 → 屏幕正中弹出解释卡、标题对得上 → 「知道了」关掉 →
// 页面还在原地（没有被问号那一下顺带点开别的东西、没有退页）。整行可点的「门槛」那一行额外验：
// 点问号只开卡、不进门槛表；点行的其它地方照旧进表。
//
// 截图落 docs/acceptance/术语问号与顶栏-2026-09-28/（iPhone 16 Pro，青苔浅为主，陶土、经典各抽一张）。
@MainActor
final class TermMarkPagesUITests: KanpanUICase {

  static let outDir = URL(fileURLWithPath: "/Users/mdd/zhk/kanpan/docs/acceptance/术语问号与顶栏-2026-09-28",
                          isDirectory: true)

  private let profile = UUID().uuidString

  override var extraLaunchEnvironment: [String: String] {
    var env: [String: String] = [:]
    if name.contains("Exchange") {
      // 假交易所（DEBUG 包里的 `ExchangeDemoProvider`），开机用只读 Key 自动接入；不登录，回合只在本机拼。
      env["KANPAN_PERSISTENCE_PROFILE"] = profile
      env["KANPAN_EXCHANGE_FIXTURE"] = "1"
      env["KANPAN_EXCHANGE_FIXTURE_KEY"] = "DEMOREADONLY7C31"
    }
    return env
  }

  override func setUp() async throws {
    XCUIDevice.shared.orientation = .portrait
    try? FileManager.default.createDirectory(at: Self.outDir, withIntermediateDirectories: true)
    try await super.setUp()
  }

  // ------------------------------------------------------------ 小工具

  private var deviceTag: String {
    switch Int(app.windows.firstMatch.frame.width.rounded()) {
    case 402: "iPhone16Pro"
    case 440: "iPhone17ProMax"
    case 430: "iPhone15ProMax"
    case let w: "宽\(w)"
    }
  }

  private func shot(_ name: String) {
    let screenshot = app.screenshot()
    let attachment = XCTAttachment(screenshot: screenshot)
    attachment.name = name; attachment.lifetime = .keepAlways; add(attachment)
    try? screenshot.pngRepresentation.write(to: Self.outDir.appendingPathComponent("\(deviceTag)-\(name).png"))
  }

  private func any(_ id: String) -> XCUIElement {
    app.descendants(matching: .any).matching(identifier: id).firstMatch
  }

  private var card: XCUIElement { any("glossary.card") }

  private func labeled(_ text: String) -> XCUIElementQuery {
    app.descendants(matching: .any).matching(NSPredicate(format: "label == %@", text))
  }

  /// 划到这颗元素点得着为止（面板、表单、列表都一样：划最上面那层可滚动的）。
  /// 按住拖一小段、停住再松手（不带惯性），元素在下面就往上拖、在上面就往下拖——
  /// 甩一下的惯性会把它直接带过可视区（半屏面板上实测过），所以先拖，拖不动才退回甩。
  @discardableResult
  private func reveal(_ el: XCUIElement, maxSwipes: Int = 12) -> Bool {
    for _ in 0..<maxSwipes where !(el.exists && el.isHittable) {
      // 半屏面板拖正文（`panel.content`），整页列表拖列表本身，都没有就拖整个 app。
      let panel = app.scrollViews["panel.content"]
      let list = app.collectionViews.firstMatch
      let surface: XCUIElement = panel.exists ? panel : list.exists ? list : app
      let box = surface.frame
      let goUp = !el.exists || el.frame.midY > box.midY   // 在下面 → 内容往上走
      let from = surface.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: goUp ? 0.7 : 0.3))
      let to = surface.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: goUp ? 0.3 : 0.7))
      let before = el.exists ? el.frame.midY : .nan
      from.press(forDuration: 0.05, thenDragTo: to, withVelocity: .slow, thenHoldForDuration: 0.2)
      _ = el.waitForExistence(timeout: 1)
      // 拖没拖动（起点压在不让拖的东西上）：退回甩一下，下一轮再按方向往回拖。
      if el.exists, abs(el.frame.midY - before) < 4 {
        if goUp { surface.swipeUp(velocity: .slow) } else { surface.swipeDown(velocity: .slow) }
        _ = el.waitForExistence(timeout: 1)
      }
    }
    // 等惯性停稳再交出去：滚动还没停时的第一下点按只会让它停下，不算点到。
    var last = el.exists ? el.frame.midY : 0
    for _ in 0..<10 {
      RunLoop.main.run(until: Date().addingTimeInterval(0.25))
      let now = el.exists ? el.frame.midY : 0
      if abs(now - last) < 1 { break }
      last = now
    }
    return el.exists && el.isHittable
  }

  /// 点一颗问号 → 卡片出来、标题对得上 → 截一张（可选）→「知道了」关掉 → `stillThere` 还在。
  private func checkTerm(_ term: String, titleContains: String, stillThere: XCUIElement,
                         bodyContains: String? = nil, shotName: String? = nil,
                         file: StaticString = #filePath, line: UInt = #line) {
    let mark = any("term." + term)
    _ = mark.waitForExistence(timeout: Self.short)
    XCTAssertTrue(reveal(mark), "term.\(term) 没有 / 划不出来 / 点不到", file: file, line: line)
    mark.tap()
    XCTAssertTrue(card.waitForExistence(timeout: Self.short), "点 term.\(term) 没弹出解释卡", file: file, line: line)
    let title = any("glossary.title")
    XCTAssertTrue(title.label.contains(titleContains), "term.\(term) 卡片标题是「\(title.label)」，不含「\(titleContains)」",
                  file: file, line: line)
    if let bodyContains {
      let body = any("glossary.body")
      XCTAssertTrue(body.label.contains(bodyContains), "term.\(term) 卡片正文不含「\(bodyContains)」：\(body.label)",
                    file: file, line: line)
    }
    if let shotName { RunLoop.main.run(until: Date().addingTimeInterval(0.4)); shot(shotName) }
    let ok = app.buttons["glossary.ok"]
    XCTAssertTrue(ok.waitForExistence(timeout: Self.short), "卡片上没有「知道了」", file: file, line: line)
    ok.tap()
    XCTAssertTrue(card.waitForNonExistence(timeout: Self.short), "term.\(term) 的卡片关不掉", file: file, line: line)
    XCTAssertTrue(stillThere.waitForExistence(timeout: Self.short), "关掉 term.\(term) 的卡片后页面变了",
                  file: file, line: line)
  }

  /// 换皮肤（和浅色），停在设置页上。皮肤卡 id 是 `display.theme.<sage|terra|classic>`。
  private func setSkin(_ skin: String) {
    XCTAssertTrue(app.openSettingsFromMe(), "「我的 › 设置」没进设置页")
    let skinCard = app.buttons["display.theme." + skin]
    expectExists(skinCard, Self.long, "设置页上没有皮肤卡 \(skin)")
    // 设置页可能停在下半截（上一步划下去过）：先划回顶上再点。
    for _ in 0..<4 where !skinCard.isHittable { app.swipeDown(velocity: .fast) }
    if (skinCard.value as? String) != "已选" { skinCard.tap() }
    XCTAssertTrue(waitUntil(timeout: Self.short) { (skinCard.value as? String) == "已选" },
                  "皮肤没切到 \(skin)：value=\(String(describing: skinCard.value))")
    let light = app.buttons["display.mode.浅色"]
    if light.waitForExistence(timeout: Self.short), !light.isSelected { light.tap() }
  }

  private func backToChart() {
    XCTAssertTrue(tapButton(app.buttons[Ids.bottomChart], Self.long) {
      self.app.buttons[Ids.intervalChart].exists
    }, "点「图表」没回行情页")
  }

  // ------------------------------------------------------------ 分析面板 · 图表设置

  func testIndicatorAndChartPanelTerms() throws {
    XCTAssertTrue(waitForLiveChart(), "图一直没有数据：\(chartInfo())")
    XCTAssertTrue(app.openIndicatorPage(), "「分析」面板没开出来")
    let header = app.staticTexts[Ids.panelHeader]
    // 指标名改短了：长的那版不许回来；均线 / 成交量 / 持仓量一看就懂，不挂问号。
    for old in ["主动买卖比", "累计成交量差", "当日均价线", "抛物线转向", "添加对比品种", "在图上显示"] {
      XCTAssertFalse(app.staticTexts[old].exists, "旧字面「\(old)」还在分析面板上")
    }
    for none in ["term.ma", "term.vol", "term.oi", "term.ema", "term.boll", "term.macd", "term.rsi", "term.kdj",
                 "term.dmi", "term.supertrend", "term.orderFlow"] {
      XCTAssertFalse(any(none).exists, "\(none) 不该挂问号")
    }
    shot("分析面板-青苔浅")
    checkTerm("vwap", titleContains: "均价线", stillThere: header)
    let cvd = app.buttons[Ids.indicatorSwitch("CVD")]
    let cvdBefore = "\(String(describing: cvd.value))|\(cvd.isSelected)"
    checkTerm("cvd", titleContains: "量差", stillThere: header, shotName: "分析面板-术语卡-量差-青苔浅")
    // 问号那一下没把开关顺带拨了。
    XCTAssertEqual("\(String(describing: cvd.value))|\(cvd.isSelected)", cvdBefore, "点量差的问号把开关也拨了")
    XCTAssertTrue(labeled("量差").firstMatch.exists, "副图里没有改名后的「量差」")
    checkTerm("takerRatio", titleContains: "买卖比", stillThere: header)

    // 门槛那一行整行是按钮：问号叠在按钮外面，点问号只开卡、不进表；点行的别处照旧进表。
    let flow = app.buttons[Ids.indicatorSwitch("ORDERFLOW")]
    let editRow = app.buttons["indicator.edit.ORDERFLOW"]
    XCTAssertTrue(reveal(flow), "主力订单流的开关划不出来")
    if !editRow.exists { flow.tap() }
    XCTAssertTrue(editRow.waitForExistence(timeout: Self.long), "开了主力订单流也没有「门槛」那一行")
    XCTAssertTrue(editRow.label.hasPrefix("门槛，"), "门槛行的读屏文字不对：\(editRow.label)")
    let editor = app.buttons["orderflow.save"]
    checkTerm("orderFlowThreshold", titleContains: "门槛", stillThere: header, shotName: "分析面板-门槛问号-青苔浅")
    XCTAssertFalse(editor.exists, "点门槛的问号把门槛表也打开了")
    reveal(editRow)
    editRow.tap()
    XCTAssertTrue(editor.waitForExistence(timeout: Self.short), "点「门槛」那一行没进门槛表")
    checkTerm("orderFlowStep", titleContains: "步长", stillThere: editor, shotName: "门槛表-步长问号-青苔浅")
    app.buttons["orderflow.cancel"].tap()
    XCTAssertTrue(editor.waitForNonExistence(timeout: Self.short), "门槛表关不掉")
    app.closeOpenPanel()

    // 图表设置：画法 / 盘口 / 刻度。
    XCTAssertTrue(tapButton(app.buttons[Ids.intervalChart], Self.short) {
      self.app.descendants(matching: .any)[Ids.chartPanelMarker].exists
    }, "图表设置没开出来")
    XCTAssertFalse(any("term.candleKind").exists || any("term.depth").exists, "画法 / 盘口不该挂问号")
    checkTerm("priceScale", titleContains: "刻度", stillThere: header, shotName: "图表设置-术语卡-刻度-青苔浅")
    shot("图表设置-青苔浅")
    app.closeChartPanel()
  }

  // ------------------------------------------------------------ 设置

  func testSettingsTerms() throws {
    setSkin("sage")
    let page = app.buttons[Ids.settingsPage]
    for text in ["涨跌色", "线路"] {
      XCTAssertTrue(labeled(text).firstMatch.waitForExistence(timeout: Self.short), "设置页上没有「\(text)」")
    }
    shot("设置-上半-青苔浅")
    checkTerm("route", titleContains: "线路", stillThere: page, shotName: "设置-术语卡-线路-青苔浅")
    let habitsSwitch = any("settings.habits")
    checkTerm("watchMove", titleContains: "波动提醒", stillThere: habitsSwitch)
    XCTAssertFalse(any("term.listing").exists, "上新下架不该挂问号")
    checkTerm("habits", titleContains: "自动适应", stillThere: habitsSwitch)
    for text in ["铃声", "波动提醒", "上新下架", "自动适应"] {
      XCTAssertTrue(labeled(text).firstMatch.exists || app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", text)).firstMatch.exists,
                    "设置页上没有「\(text)」")
    }
    shot("设置-下半-青苔浅")

    // 陶土抽一张。
    setSkin("terra")
    app.swipeUp(velocity: .slow)
    RunLoop.main.run(until: Date().addingTimeInterval(0.4))
    shot("设置-下半-陶土浅")
    setSkin("sage")
  }

  // ------------------------------------------------------------ 我的 › 交易所 · 复盘本

  func testExchangeAndReviewTerms() throws {
    setSkin("sage")
    XCTAssertTrue(app.openMePage(), "回不到「我的」")
    let row = app.buttons[Ids.meExchange]
    XCTAssertTrue(waitUntil(timeout: Self.long) { row.label.contains("币安合约") }, "开机没自动接入：\(row.label)")
    XCTAssertTrue(row.label.hasPrefix("交易所"), "「我的」那一行不叫「交易所」：\(row.label)")
    XCTAssertFalse(row.label.contains("交易所账户"), "「我的」那一行还叫「交易所账户」：\(row.label)")
    shot("我的-青苔浅")

    row.tap()
    let page = any("me.exchange.page")
    XCTAssertTrue(page.waitForExistence(timeout: Self.short), "交易所页没推出来")
    XCTAssertTrue(app.navigationBars["交易所"].exists, "页标题不是「交易所」")
    XCTAssertTrue(app.staticTexts["exchange.suffix"].waitForExistence(timeout: Self.long), "没接上")
    XCTAssertTrue(labeled("密钥").firstMatch.exists && labeled("回溯").firstMatch.exists, "没有「密钥」「回溯」两行")
    checkTerm("backfill", titleContains: "回溯", stillThere: page, shotName: "交易所-术语卡-回溯-青苔浅")
    shot("交易所-青苔浅")
    app.navigationBars.buttons.firstMatch.tap()

    // 复盘本 › 交易 › 上周卡 → 战绩（交易那一面）。
    let review = app.buttons[Ids.meReview]
    XCTAssertTrue(waitUntil(timeout: Self.long) { review.label.contains("笔 · 净盈亏") }, "本机没拼出上周的回合：\(review.label)")
    XCTAssertTrue(app.openReviewBookFromMe(), "「我的 › 复盘本」没开出复盘本")
    let tradesTab = app.buttons["review.segment.交易"]
    XCTAssertTrue(tradesTab.waitForExistence(timeout: Self.short), "复盘本没有「观点 · 交易」开关")
    tradesTab.tap()
    let week = app.buttons["review.trades.week"]
    XCTAssertTrue(week.waitForExistence(timeout: Self.long), "交易段没有上周卡")
    week.tap()
    let summary = any("review.stats.trades.summary")
    XCTAssertTrue(summary.waitForExistence(timeout: Self.short), "战绩没落在交易那一面")
    XCTAssertTrue(labeled("净盈亏").firstMatch.exists && labeled("费用占毛利").firstMatch.exists, "战绩里没有「净盈亏」「费用占毛利」")
    XCTAssertFalse(labeled("总净盈亏").firstMatch.exists || labeled("手续费占毛利").firstMatch.exists, "旧字面还在")
    let statsList = any("review.stats.trades")
    XCTAssertFalse(any("term.netPnl").exists, "净盈亏不该挂问号")
    checkTerm("rewardRisk", titleContains: "盈亏比", stillThere: statsList, shotName: "战绩-术语卡-盈亏比-青苔浅")
    checkTerm("expectancy", titleContains: "每笔期望", stillThere: statsList)
    checkTerm("feeShare", titleContains: "费用占毛利", stillThere: statsList)
    shot("战绩-交易-青苔浅")
    app.navigationBars.buttons.firstMatch.tap()

    // 交易详情：已平的那一笔 BTC（第二行；第一行是持仓中）。
    let btc = app.buttons.matching(identifier: "review.trades.row.BTC")
    XCTAssertTrue(waitUntil(timeout: Self.short) { btc.count >= 2 }, "BTC 应有一笔持仓中、一笔已平")
    btc.element(boundBy: 1).tap()
    let detail = app.navigationBars["交易详情"]
    XCTAssertTrue(detail.waitForExistence(timeout: Self.short), "没进交易详情")
    checkTerm("fills", titleContains: "成交", stillThere: detail, bodyContains: "吃单", shotName: "交易详情-术语卡-成交-青苔浅")
    checkTerm("realized", titleContains: "已实现", stillThere: detail)
    checkTerm("tradeRewardRisk", titleContains: "盈亏比", stillThere: detail)
    checkTerm("afterClose", titleContains: "离开后", stillThere: detail)
    for none in ["term.maxFavorable", "term.maxAdverse", "term.funding"] {
      XCTAssertFalse(any(none).exists, "\(none) 不该挂问号")
    }
    shot("交易详情-下半-青苔浅")
    detail.buttons.firstMatch.tap()
    if app.buttons["review.back"].waitForExistence(timeout: Self.short) { app.buttons["review.back"].tap() }
  }

  // ------------------------------------------------------------ 创建提醒页

  func testAlertFormTerms() throws {
    XCTAssertTrue(waitForLiveChart(), "图一直没有数据：\(chartInfo())")
    let page = any("alerts.new.page")
    XCTAssertTrue(openNewAlert(), "「创建提醒」没开出创建页")
    checkTerm("alertCondition", titleContains: "条件", stillThere: page, bodyContains: "收盘穿过",
              shotName: "创建提醒-术语卡-条件-青苔浅")
    checkTerm("webhook", titleContains: "Webhook", stillThere: page, bodyContains: "JSON")
    XCTAssertFalse(app.staticTexts["触发时向这个地址发一条 JSON"].exists, "那句 JSON 说明该挪进问号卡了")
    shot("创建提醒-青苔浅")
    closeAlertSheet()

    // 经典抽一张。
    setSkin("classic")
    backToChart()
    XCTAssertTrue(openNewAlert(), "经典皮肤下「创建提醒」没开出创建页")
    checkTerm("webhook", titleContains: "Webhook", stillThere: page, shotName: "创建提醒-术语卡-Webhook-经典浅")
    closeAlertSheet()
    setSkin("sage")
  }

  // ------------------------------------------------------------ 创建提醒页的进出（照 AlertsFlowUITests）

  private var canvas: XCUIElement { app.otherElements["chart.canvas"] }

  private func canvasInfo() -> [String: Any] {
    guard canvas.exists, let value = canvas.value as? String, let data = value.data(using: .utf8),
          let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return [:] }
    return object
  }

  /// 图上点一根 → 十字线 → 周期条那颗「创建提醒」→ 创建页。
  private func openNewAlert() -> Bool {
    let page = any("alerts.new.page")
    for _ in 0..<3 {
      if page.exists { return true }
      if canvasInfo()["crosshair"] as? Bool != true {
        guard let mainH = canvasInfo()["mainH"] as? Double, let plotW = canvasInfo()["plotW"] as? Double else { continue }
        let scale = canvas.frame.height / max(1, canvasInfo()["height"] as? Double ?? canvas.frame.height)
        canvas.coordinate(withNormalizedOffset: .zero)
          .withOffset(CGVector(dx: plotW * scale * 0.8, dy: mainH * scale * 0.78)).tap()
        guard waitUntil(timeout: Self.short, { self.canvasInfo()["crosshair"] as? Bool == true }) else { continue }
      }
      let chip = app.buttons["chart.crosshair.alert"]
      guard chip.waitForExistence(timeout: 5) else { continue }
      chip.tap()
      if app.textFields["alerts.new.price"].waitForExistence(timeout: 8) { return true }
    }
    return false
  }

  private func closeAlertSheet() {
    let page = any("alerts.new.page")
    for _ in 0..<4 where page.exists {
      let close = app.buttons["panel.done"]
      if close.waitForExistence(timeout: 2), close.isHittable {
        close.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
      }
      _ = page.waitForNonExistence(timeout: 5)
    }
  }
}
