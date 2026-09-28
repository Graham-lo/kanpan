import XCTest

// ============================================================ 术语问号 · 顶栏乙方案 · 行情停住变灰 · 底栏渐变（2026-09-28）
//
// 这一轮五件事人眼能看见的那一半：
// 1. 顶栏右侧三颗圆片「记一笔 · 分享 · 搜索」，图表设置里「这张图」整节没了；
// 2. 六格里「仓 / 额 / 估值」后面各一颗问号（费率、结算、市值一看就懂，不挂），点开屏幕正中一张解释卡，
//    「知道了」和点遮罩都能关；从半屏面板（系统 sheet）里点开时卡片照样落在最上层；
//    从问号上起手横滑仍然换品种（不吞扫图）；
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

    // 三颗圆片从左到右：记一笔 · 分享 · 搜索。
    let note = app.buttons[Ids.topNote], share = app.buttons[Ids.topShare], search = app.buttons[Ids.searchButton]
    for (el, name) in [(note, "记一笔"), (share, "分享"), (search, "搜索")] {
      XCTAssertTrue(el.waitForExistence(timeout: Self.short), "顶栏没有「\(name)」")
      XCTAssertTrue(el.isHittable, "「\(name)」点不到")
    }
    XCTAssertLessThan(note.frame.midX, share.frame.midX, "「记一笔」不在「分享」左边")
    XCTAssertLessThan(share.frame.midX, search.frame.midX, "「分享」不在「搜索」左边")
    XCTAssertEqual(note.frame.midY, search.frame.midY, accuracy: 1, "三颗不在一条线上")
    XCTAssertLessThan(app.symbolLabel.frame.maxX, note.frame.minX, "品种名压到了「记一笔」上")

    // 六格：仓 · 额 · 估值（BTC 是 OI/MC）各一颗问号；市值、费率、结算一看就懂，不挂。
    for term in ["openInterest", "turnover", "oiToMarketCap"] {
      XCTAssertTrue(any("term." + term).waitForExistence(timeout: Self.long), "六格里没有 term.\(term)")
    }
    for term in ["marketCap", "fundingRate", "settlement"] {
      XCTAssertFalse(any("term." + term).exists, "term.\(term) 不该挂问号")
    }
    // 不换行：量的是值文字本身（`top.stats` 这个容器的无障碍框会被问号 32pt 的命中框撑出去，
    // 那不是排版）。每格一行（< 20pt），首行「仓」顶到末行「结算」底三行不超过 50pt（原排版约 47）。
    let rows = ["top.openInterest", "top.turnover", "top.marketCap", "top.funding", "top.settlement", "top.valuation"]
    for id in rows {
      let el = any(id)
      XCTAssertTrue(el.waitForExistence(timeout: Self.short), "六格里没有 \(id)")
      XCTAssertLessThan(el.frame.height, 20, "\(id) 折行了：\(el.frame)")
    }
    let band = any("top.settlement").frame.maxY - any("top.openInterest").frame.minY
    XCTAssertLessThan(band, 50, "六格三行撑高了：\(band)")
    // 问号不撑宽标签：「仓」标签那一格和「市值」同一列左对齐，值列也还是对齐的。
    XCTAssertEqual(any("top.openInterest").frame.maxX, any("top.marketCap").frame.maxX, accuracy: 1,
                   "左列值没对齐（问号撑宽了标签列？）")
    shot("青苔浅-顶栏三圆片与六格问号")

    // 问号 → 卡片 → 「知道了」关。
    openCard("openInterest", titleContains: "持仓")
    XCTAssertEqual(card.frame.width, 280, accuracy: 1, "卡片宽不是 280：\(card.frame)")
    XCTAssertEqual(card.frame.midX, app.windows.firstMatch.frame.midX, accuracy: 1, "卡片没有水平居中")
    shot("青苔浅-术语卡-仓")
    closeCardWithOK()

    // 点遮罩也能关（卡片外的上方空处）。
    openCard("oiToMarketCap", titleContains: "持仓÷市值")
    app.windows.firstMatch.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.1)).tap()
    XCTAssertTrue(card.waitForNonExistence(timeout: Self.short), "点遮罩卡片没关")

    // 「额」那颗也开得出来、关得掉。
    openCard("turnover", titleContains: "成交额")
    closeCardWithOK()

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

    // 顶栏「分享」：图片 / 画线二选一那张面板。
    share.tap()
    XCTAssertTrue(app.otherElements["share.chooser"].waitForExistence(timeout: Self.short), "点「分享」没弹出二选一")
    shot("青苔浅-顶栏分享二选一")
    app.closeOpenPanel()
    XCTAssertTrue(app.otherElements["share.chooser"].waitForNonExistence(timeout: Self.short), "分享面板收不掉")

    // 顶栏「记一笔」：开出取景卡。
    note.tap()
    let save = app.buttons["记下"]
    XCTAssertTrue(save.waitForExistence(timeout: Self.short), "点「记一笔」没开出取景卡")
    shot("青苔浅-顶栏记一笔取景卡")
    let fold = app.buttons["收起"]
    if fold.exists { fold.tap() }

    // 陶土、经典各看一眼卡片。
    for (skin, label) in [("terra", "陶土浅"), ("classic", "经典浅")] {
      setSkin(skin)
      openCard("turnover", titleContains: "成交额")
      shot("\(label)-术语卡-额")
      closeCardWithOK()
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
    app.buttons[Ids.topShare].tap()
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

  func testScanSwipeFromTermMarkAndLongSymbolWithBack() throws {
    XCTAssertTrue(app.openFavorites(), "进不了自选页")
    let row = app.buttons["favorites.open." + testInstrumentKey("PUMPBTCUSDT")]
    expectExists(row, Self.long, "自选页上没有 PUMPBTCUSDT")
    row.tap()
    XCTAssertTrue(waitUntil(timeout: Self.long) { self.symbolOnChart() == "PUMPBTCUSDT" },
                  "没进 PUMPBTC 的图（现在是 \(symbolOnChart())）")
    XCTAssertTrue(app.buttons[Ids.topBack].waitForExistence(timeout: Self.short), "从自选进来没有返回键")
    let symbol = app.symbolLabel
    XCTAssertTrue(symbol.label.contains("PUMPBTC"), "品种名读出来是「\(symbol.label)」")
    XCTAssertLessThan(symbol.frame.maxX, app.buttons[Ids.topNote].frame.minX, "品种名压到了「记一笔」")
    XCTAssertGreaterThan(app.buttons[Ids.topNote].frame.minX - app.buttons[Ids.topBack].frame.maxX, 170,
                         "返回键与右侧圆片之间给品种名留的不到 170pt")
    shot("青苔浅-有返回键-PUMPBTC不截断")

    // 从「仓」那颗问号上起手往左划：换到名单里的下一只（BTC），不弹卡片。
    let mark = any("term.openInterest")
    XCTAssertTrue(mark.waitForExistence(timeout: Self.long))
    let start = mark.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
    start.press(forDuration: 0.05, thenDragTo: start.withOffset(CGVector(dx: -220, dy: 0)))
    XCTAssertTrue(waitUntil(timeout: Self.long) { self.symbolOnChart() == "BTCUSDT" },
                  "从问号上起手横滑没换到下一只（现在是 \(symbolOnChart())）")
    XCTAssertFalse(card.exists, "横滑弹出了术语卡")
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
    app.buttons[Ids.bottomSectors].tap()
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
    let barTop = app.buttons[Ids.bottomSectors].frame.minY
    XCTAssertLessThanOrEqual(last.frame.maxY, barTop, "拉到底最后一行 \(last.frame) 压到底栏（上沿 \(barTop)）")
    shot("青苔浅-板块品种列表拉到底")
  }
}
