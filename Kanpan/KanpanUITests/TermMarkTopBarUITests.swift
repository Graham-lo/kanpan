import XCTest

// ============================================================ 术语问号 · 顶栏乙方案 · 行情停住变灰 · 底栏渐变（2026-09-28）
//
// 这一轮五件事人眼能看见的那一半：
// 1. 顶栏右侧三颗圆片（2026-10-08 起是「提醒铃 · ⋯ · 搜索」，记一笔 / 分享 / 添加对比收进「⋯」菜单），
//    图表设置里「这张图」整节没了；
// 2. 10-11 六格统计撤掉，只保留单行价格与右侧涨跌；半屏面板里的术语卡仍在最上层；
//    从涨跌额上起手横滑仍然换品种。
// 3. 断网之后价格与涨跌变灰，网回来恢复（`market.quote` 诊断串里的 `fresh=`）；
// 4. 板块品种列表拉到底，最后一行整行落在底栏上沿以上；
// 5. 板块副文案只有「a/n 跑赢大盘」。
//
// 截图落 docs/acceptance/术语问号与顶栏-2026-09-28/（iPhone 16 Pro，青苔浅为主，陶土、经典各一张）。
@MainActor
final class TermMarkTopBarUITests: KanpanUICase {

  static let outDir = URL(fileURLWithPath: "/Users/mdd/zhk/kanpan/docs/acceptance/术语问号与顶栏-2026-09-28",
                          isDirectory: true)

  override var extraLaunchEnvironment: [String: String] {
    var env: [String: String] = [:]
    if name.contains("Sheet") { env["KANPAN_TEST_GLOSSARY_PROBE"] = "1" }
    if name.contains("Scan") { env["KANPAN_TEST_FAVORITES"] = "PUMPBTCUSDT,BTCUSDT,ETHUSDT" }
    return env
  }

  override func setUp() async throws {
    XCUIDevice.shared.orientation = .portrait
    try? FileManager.default.createDirectory(at: Self.outDir, withIntermediateDirectories: true)
    try await super.setUp()
  }

  // ------------------------------------------------------------ 取证

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

  /// `market.quote` 的诊断串：`symbol=…;last=…;time=…;fresh=0|1`。
  private func quote() -> [String: String] {
    guard let text = any("market.quote").value as? String else { return [:] }
    var out: [String: String] = [:]
    for part in text.split(separator: ";") {
      let kv = part.split(separator: "=", maxSplits: 1).map(String.init)
      if kv.count == 2 { out[kv[0]] = kv[1] }
    }
    return out
  }

  private func symbolOnChart() -> String {
    (chartInfo()["symbol"] as? String ?? "").split(separator: "/").last.map(String.init) ?? ""
  }

  /// 点一颗问号 → 卡片出来 → 标题对得上。
  private func openCard(_ term: String, titleContains: String,
                        file: StaticString = #filePath, line: UInt = #line) {
    let mark = any("term." + term)
    XCTAssertTrue(mark.waitForExistence(timeout: Self.long), "顶栏没有 term.\(term)", file: file, line: line)
    mark.tap()
    XCTAssertTrue(card.waitForExistence(timeout: Self.short), "点 term.\(term) 没弹出解释卡", file: file, line: line)
    let title = any("glossary.title")
    XCTAssertTrue(title.label.contains(titleContains), "卡片标题是「\(title.label)」，不含「\(titleContains)」",
                  file: file, line: line)
  }

  private func closeCardWithOK(file: StaticString = #filePath, line: UInt = #line) {
    let ok = app.buttons["glossary.ok"]
    XCTAssertTrue(ok.waitForExistence(timeout: Self.short), "卡片上没有「知道了」", file: file, line: line)
    XCTAssertEqual(ok.label, "知道了", file: file, line: line)
    ok.tap()
    XCTAssertTrue(card.waitForNonExistence(timeout: Self.short), "点「知道了」卡片没关", file: file, line: line)
  }

  /// 换一套皮肤，再回行情页。皮肤卡的 id 是 `display.theme.<sage|terra|classic>`。
  private func setSkin(_ skin: String) {
    XCTAssertTrue(app.openSettingsFromMe() && app.buttons["display.theme.sage"].waitForExistence(timeout: Self.long),
                  "「我的 › 设置」没进设置页")
    let skinCard = app.buttons["display.theme." + skin]
    expectExists(skinCard, Self.long, "设置页上没有皮肤卡 \(skin)")
    if (skinCard.value as? String) != "已选" { skinCard.tap() }
    XCTAssertTrue(waitUntil(timeout: Self.short) { (skinCard.value as? String) == "已选" }, "皮肤没切到 \(skin)")
    XCTAssertTrue(tapButton(app.buttons[Ids.bottomChart], Self.long) {
      self.app.buttons[Ids.intervalChart].exists
    }, "点「图表」没回行情页")
  }

  // ------------------------------------------------------------ 1 + 2：三颗圆片、问号卡、图表设置

  func testTopBarDiscsTermCardsAndChartPanel() throws {
    XCTAssertTrue(waitForLiveChart(), "图一直没有数据：\(chartInfo())")

    // 三颗圆片从左到右：提醒铃 · ⋯ · 搜索（10-08 起记一笔 / 分享 / 添加对比收进「⋯」）。
    let alerts = app.buttons[Ids.topAlerts], more = app.buttons[Ids.topMore], search = app.buttons[Ids.searchButton]
    for (el, name) in [(alerts, "提醒"), (more, "更多"), (search, "搜索")] {
      XCTAssertTrue(el.waitForExistence(timeout: Self.short), "顶栏没有「\(name)」")
      XCTAssertTrue(el.isHittable, "「\(name)」点不到")
    }
    XCTAssertEqual(more.label, "更多", "「⋯」的无障碍名不是「更多」")
    XCTAssertLessThan(alerts.frame.midX, more.frame.midX, "「提醒」不在「⋯」左边")
    XCTAssertLessThan(more.frame.midX, search.frame.midX, "「⋯」不在「搜索」左边")
    XCTAssertEqual(alerts.frame.midY, search.frame.midY, accuracy: 1, "三颗不在一条线上")
    XCTAssertEqual(more.frame.midY, search.frame.midY, accuracy: 1, "三颗不在一条线上")
    // 圆心距 = 圆片 32 + 间距 12 = 44（命中框 44 宽，正好首尾相接）。
    XCTAssertEqual(more.frame.midX - alerts.frame.midX, 44, accuracy: 1, "「提醒」与「⋯」圆心距不是 44")
    XCTAssertEqual(search.frame.midX - more.frame.midX, 44, accuracy: 1, "「⋯」与「搜索」圆心距不是 44")
    XCTAssertFalse(app.buttons[Ids.topNote].exists || app.buttons[Ids.topShare].exists || app.buttons[Ids.topCompare].exists,
                   "「记一笔 / 分享 / 添加对比」还摆在顶栏上，没收进「⋯」")
    XCTAssertLessThan(app.symbolLabel.frame.maxX, alerts.frame.minX, "品种名压到了「提醒」上")

    // 10-11 六格统计已撤，价格右侧只保留涨跌额与涨跌幅。
    for id in ["top.stats", "term.openInterest", "term.turnover", "term.oiToMarketCap"] {
      XCTAssertFalse(any(id).exists, "已撤的头部统计仍在：\(id)")
    }
    XCTAssertTrue(any("top.priceChange").exists && any("top.changePercent").exists)
    shot("青苔浅-精简报价与顶栏三圆片")

    // 图表设置里「这张图」整节没了，只剩 K 线 · 显示 · 价格轴。
    app.buttons[Ids.intervalChart].tap()
    XCTAssertTrue(app.buttons[Ids.chartPanelMarker].waitForExistence(timeout: Self.short), "图表设置没开出来")
    XCTAssertFalse(app.staticTexts["这张图"].exists, "图表设置里还有「这张图」")
    XCTAssertFalse(app.buttons["chart.record"].exists, "图表设置里还有「记一笔」")
    XCTAssertFalse(app.buttons["chart.share"].exists, "图表设置里还有「分享」")
    for title in ["K 线", "显示", "价格轴"] {
      XCTAssertTrue(app.staticTexts[title].exists, "图表设置少了「\(title)」")
    }
    shot("青苔浅-图表设置只剩三组")
    XCTAssertTrue(app.closeChartPanel(), "图表设置收不起来")

    // 「⋯」菜单展开：从上到下 添加对比 · 记一笔 · 分享。
    let items = [Ids.topCompare, Ids.topNote, Ids.topShare].compactMap { app.topMenuItem($0) }
    XCTAssertEqual(items.count, 3, "「⋯」菜单里不是三项")
    if items.count == 3 {
      XCTAssertLessThan(items[0].frame.midY, items[1].frame.midY, "「添加对比」不在「记一笔」上面")
      XCTAssertLessThan(items[1].frame.midY, items[2].frame.midY, "「记一笔」不在「分享」上面")
      XCTAssertTrue(items[0].isEnabled, "没在对比时「添加对比」是灰的")
    }
    shot("青苔浅-顶栏更多菜单")
    app.closeTopMenu()
    XCTAssertTrue(waitUntil(timeout: Self.short) { !self.app.buttons[Ids.topShare].exists }, "「⋯」菜单收不起来")

    // 「⋯ › 分享」：图片 / 画线二选一那张面板。
    XCTAssertTrue(app.openTopMenuItem(Ids.topShare), "「⋯」菜单里没有「分享」")
    XCTAssertTrue(app.otherElements["share.chooser"].waitForExistence(timeout: Self.short), "点「分享」没弹出二选一")
    shot("青苔浅-顶栏分享二选一")
    app.closeOpenPanel()
    XCTAssertTrue(app.otherElements["share.chooser"].waitForNonExistence(timeout: Self.short), "分享面板收不掉")

    // 「⋯ › 记一笔」：开出取景卡。
    XCTAssertTrue(app.openTopMenuItem(Ids.topNote), "「⋯」菜单里没有「记一笔」")
    let save = app.buttons["记下"]
    XCTAssertTrue(save.waitForExistence(timeout: Self.short), "点「记一笔」没开出取景卡")
    shot("青苔浅-顶栏记一笔取景卡")
    let fold = app.buttons["收起"]
    if fold.exists { fold.tap() }

    for (skin, label) in [("terra", "陶土浅"), ("classic", "经典浅")] {
      setSkin(skin)
      shot("\(label)-精简报价")
    }
  }

  // ------------------------------------------------------------ 2：卡片落在 sheet 之上

  /// 面板（系统 sheet 里的 `PanelSheet`）标题后挂着 DEBUG 探针问号（`term.probe`）。
  /// 点开之后卡片要整个在最上层：「知道了」点得到、点了关掉卡片而面板还在。
  func testCardLandsAboveTheSheet() throws {
    app.buttons[Ids.intervalChart].tap()
    XCTAssertTrue(app.buttons[Ids.chartPanelMarker].waitForExistence(timeout: Self.short), "图表设置没开出来")
    let probe = any("term.probe")
    XCTAssertTrue(probe.waitForExistence(timeout: Self.short), "面板标题后没有探针问号")
    probe.tap()
    XCTAssertTrue(card.waitForExistence(timeout: Self.short), "从面板里点问号没弹出卡片")
    let ok = app.buttons["glossary.ok"]
    XCTAssertTrue(ok.isHittable, "卡片在面板底下：「知道了」点不到")
    // 卡片中心那一点，命中的是卡片而不是面板。
    XCTAssertTrue(card.isHittable, "卡片被面板盖住了")
    shot("青苔浅-面板里点开术语卡")
    ok.tap()
    XCTAssertTrue(card.waitForNonExistence(timeout: Self.short), "卡片没关")
    XCTAssertTrue(app.buttons[Ids.chartPanelMarker].exists, "关卡片把面板也带走了")

    // 半屏分享面板里同样（第二张 sheet，关掉再开）。
    XCTAssertTrue(app.closeChartPanel())
    XCTAssertTrue(app.openTopMenuItem(Ids.topShare), "「⋯」菜单里没有「分享」")
    XCTAssertTrue(app.otherElements["share.chooser"].waitForExistence(timeout: Self.short))
    any("term.probe").tap()
    XCTAssertTrue(card.waitForExistence(timeout: Self.short), "分享面板里点问号没弹出卡片")
    XCTAssertTrue(app.buttons["glossary.ok"].isHittable, "卡片在分享面板底下")
    // 点遮罩关卡片，面板留着。
    app.windows.firstMatch.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.08)).tap()
    XCTAssertTrue(card.waitForNonExistence(timeout: Self.short), "点遮罩卡片没关")
    XCTAssertTrue(app.otherElements["share.chooser"].exists, "点卡片遮罩把分享面板也关了")
    app.closeOpenPanel()
  }

  // ------------------------------------------------------------ 2：有返回键时品种名不截断；问号上起手横滑照样换品种

  func testScanSwipeFromChangeAndLongSymbolWithBack() throws {
    XCTAssertTrue(app.openFavorites(), "进不了自选页")
    let row = app.buttons["favorites.open." + testInstrumentKey("PUMPBTCUSDT")]
    expectExists(row, Self.long, "自选页上没有 PUMPBTCUSDT")
    row.tap()
    XCTAssertTrue(waitUntil(timeout: Self.long) { self.symbolOnChart() == "PUMPBTCUSDT" },
                  "没进 PUMPBTC 的图（现在是 \(symbolOnChart())）")
    XCTAssertTrue(app.buttons[Ids.topBack].waitForExistence(timeout: Self.short), "从自选进来没有返回键")
    let symbol = app.symbolLabel
    XCTAssertTrue(symbol.label.contains("PUMPBTC"), "品种名读出来是「\(symbol.label)」")
    // 10-08 起右侧只剩「提醒 · ⋯ · 搜索」三颗（32×3 + 12×2 = 120pt）。16 Pro 可用 370pt，有返回键时
    // 品种块排版宽 370 − 32 − 8 − 120 − 16 = 194pt；量的是命中框（各往外伸 6pt），返回键命中框右沿到
    // 「提醒」命中框左沿 194 + 6 + 6 = 206pt，门槛取 200（原五颗时是 170），品种名也不许压到「提醒」和「⋯」。
    let alerts = app.buttons[Ids.topAlerts], more = app.buttons[Ids.topMore]
    XCTAssertTrue(more.waitForExistence(timeout: Self.short), "有返回键时顶栏没有「⋯」")
    XCTAssertLessThan(symbol.frame.maxX, alerts.frame.minX, "品种名压到了「提醒」")
    XCTAssertLessThan(symbol.frame.maxX, more.frame.minX, "品种名压到了「⋯」")
    XCTAssertGreaterThan(alerts.frame.minX - app.buttons[Ids.topBack].frame.maxX, 200,
                         "返回键与右侧圆片之间给品种块留的不到 200pt")
    shot("青苔浅-有返回键-PUMPBTC不截断")

    // 从右侧涨跌额上起手往左划：换到名单里的下一只（BTC），不弹卡片。
    let mark = any("top.priceChange")
    XCTAssertTrue(mark.waitForExistence(timeout: Self.long))
    let start = mark.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
    start.press(forDuration: 0.05, thenDragTo: start.withOffset(CGVector(dx: -220, dy: 0)))
    XCTAssertTrue(waitUntil(timeout: Self.long) { self.symbolOnChart() == "BTCUSDT" },
                  "从涨跌额上起手横滑没换到下一只（现在是 \(symbolOnChart())）")
    XCTAssertFalse(card.exists, "横滑弹出了术语卡")
    // 扫到 BTC 返回键还在：「徽章 BTC/USDT 永续」约 143pt，194pt 的品种块整行放得下（10-08 起右侧三颗）。
    XCTAssertTrue(app.buttons[Ids.topBack].exists, "横滑扫图后返回键没了")
    XCTAssertLessThan(app.symbolLabel.frame.maxX, app.buttons[Ids.topAlerts].frame.minX, "BTC 品种块压到了「提醒」")
    shot("青苔浅-有返回键-BTC整行")
  }

  // ------------------------------------------------------------ 3：断网变灰、网回来恢复

  func testStaleGreysThenRecovers() throws {
    XCTAssertTrue(waitForLiveChart(), "图一直没有数据")
    XCTAssertTrue(waitUntil(timeout: Self.long) { self.quote()["fresh"] == "1" }, "开局就不新鲜：\(quote())")
    let start = Date().timeIntervalSince1970 + 20
    let seconds = 30.0
    app.terminate()
    app.launchEnvironment["KANPAN_TEST_NET_OUTAGE"] = "\(Int(start)):\(Int(seconds))"
    app.launch()
    let chartTab = app.buttons[Ids.bottomChart]
    if chartTab.waitForExistence(timeout: 5), !app.symbolLabel.exists { chartTab.tap() }
    XCTAssertTrue(app.symbolLabel.waitForExistence(timeout: Self.long))
    XCTAssertTrue(waitUntil(timeout: 20) { self.quote()["fresh"] == "1" }, "断网前没活过来：\(quote())")
    shot("青苔浅-断网前-实时")
    XCTAssertTrue(waitUntil(timeout: 50) { self.quote()["fresh"] == "0" },
                  "断网 \(Int(Date().timeIntervalSince1970 - start))s 了价格还标着新鲜：\(quote())")
    let greyedAfter = Int(Date().timeIntervalSince1970 - start)
    shot("青苔浅-断网-价格变灰")
    XCTAssertTrue(waitUntil(timeout: 90) { Date().timeIntervalSince1970 > start + seconds && self.quote()["fresh"] == "1" },
                  "网回来之后没恢复：\(quote())")
    let recoveredAfter = Int(Date().timeIntervalSince1970 - start - seconds)
    shot("青苔浅-网回来-恢复")
    let a = XCTAttachment(string: "断网后 \(greyedAfter)s 变灰；网回来后 \(recoveredAfter)s 恢复")
    a.name = "变灰时序"; a.lifetime = .keepAlways; add(a)
    print("变灰时序|断网后 \(greyedAfter)s 变灰；网回来后 \(recoveredAfter)s 恢复")
  }

  // ------------------------------------------------------------ 4 + 5：板块副文案、列表拉到底

  func testSectorSubtitleAndListBottomClearance() throws {
    app.openSectors()
    XCTAssertTrue(any("sector.page").waitForExistence(timeout: Self.long), "没进板块页")
    let breadth = app.staticTexts.matching(NSPredicate(format: "identifier BEGINSWITH %@", "sector.board.breadth."))
    XCTAssertTrue(waitUntil(timeout: Self.long) { breadth.count > 0 }, "板块列表里没有副文案")
    let labels = breadth.allElementsBoundByIndex.prefix(10).map(\.label)
    let pattern = #"^\d+/\d+ 跑赢大盘$"#
    XCTAssertTrue(labels.allSatisfy { $0.range(of: pattern, options: .regularExpression) != nil },
                  "板块副文案不是「a/n 跑赢大盘」：\(labels)")
    shot("青苔浅-板块列表副文案")

    // 下钻成员最多的那一块（要一屏装不下才量得出「拉到底」），头上那句同样只有「a/n 跑赢大盘」。
    func members(_ label: String) -> Int { Int(label.split(separator: "/").last?.split(separator: " ").first ?? "") ?? 0 }
    let biggest = try XCTUnwrap(breadth.allElementsBoundByIndex.max { members($0.label) < members($1.label) })
    XCTAssertGreaterThanOrEqual(members(biggest.label), 16, "首屏最大的板块也只有「\(biggest.label)」，一屏装得下，量不出拉到底")
    let boardID = biggest.identifier.replacingOccurrences(of: "sector.board.breadth.", with: "")
    any("sector.row." + boardID).tap()
    XCTAssertTrue(any("sector.list").waitForExistence(timeout: Self.short), "没进板块品种列表")
    let header = any("sector.list.breadth")
    XCTAssertTrue(header.waitForExistence(timeout: Self.short), "品种列表头上没有副文案")
    XCTAssertNotNil(header.label.range(of: pattern, options: .regularExpression),
                    "品种列表头上副文案是「\(header.label)」")

    // 拉到底：最后一行整行在底栏上沿以上。
    for _ in 0..<12 { app.swipeUp(velocity: .fast) }
    Thread.sleep(forTimeInterval: 1.5)
    let rows = app.descendants(matching: .any).matching(NSPredicate(format: "identifier BEGINSWITH %@", "sector.open."))
      .allElementsBoundByIndex.filter { $0.exists && $0.frame.height > 1 }
    let last = try XCTUnwrap(rows.max { $0.frame.maxY < $1.frame.maxY }, "列表里一行都没读到")
    // 真的滚过了：第一行已经出了屏幕上沿（否则这张列表一屏就装下了，底边距没被考到）。
    XCTAssertGreaterThan(last.frame.maxY, app.windows.firstMatch.frame.height * 0.6, "最后一行离底栏太远，列表没滚起来")
    let barTop = app.buttons[Ids.bottomHome].frame.minY
    XCTAssertLessThanOrEqual(last.frame.maxY, barTop, "拉到底最后一行 \(last.frame) 压到底栏（上沿 \(barTop)）")
    shot("青苔浅-板块品种列表拉到底")
  }
}
