import Foundation
import Testing

@testable import KanpanCore

/// 「盘口要点」半页与首页「异动 · 榜单」：接口解码（线上 10-10 抓的真答复）与拼字。
@Suite("盘口要点 · 首页异动")
struct HighlightsTests {
  static let utc8 = TZOffset.fixed(480)

  static func page(_ name: String) throws -> HighlightsPage {
    try JSONDecoder().decode(HighlightsPage.self, from: Fixture.data(name))
  }

  // MARK: 解码

  @Test("BTC 一份完整答复：四行流向、区间、价位、三格、事件全解出来")
  func decodesFullPage() throws {
    let p = try Self.page("highlights-btc")
    #expect(p.base == "BTC")
    #expect(p.tracked)
    #expect(p.staleMs == nil)
    #expect(p.flow?.rows.map(\.w) == [.m15, .h1, .h4, .range])
    #expect(p.flow?.rows.last?.sinceMs == 1_791_486_000_000)
    #expect(p.range?.lowTests == 4)
    #expect(p.levels.count == 3)
    #expect(p.levels.first?.wallState == .live)
    #expect(p.levels.first?.refs == ["dayHigh"])
    #expect(p.position?.show == true)
    #expect(p.position?.oi?.combo == .oiUpPxUp)
    #expect(p.position?.spotPremium?.pctile == 99)
    #expect(p.events.count == 4)
    #expect(p.events.first?.t == .wallEaten)
    #expect(p.hasPoints)
  }

  @Test("净主动没盖住整窗是 null：解成 nil，格子写「—」")
  func nullNetDecodesAsNil() throws {
    let p = try Self.page("highlights-zro")
    let rows = try #require(p.flow?.rows)
    #expect(rows[0].netUsd == 65_667)
    #expect(rows[1].netUsd == nil)
    #expect(HighlightsText.flowNet(rows[1]) == "—")
    #expect(HighlightsText.flowNet(rows[0]) == "+65.7K")
    #expect(p.levels.first?.wallState == nil)
  }

  @Test("未跟踪的品种：tracked=false、各块为空")
  func untracked() throws {
    let json = #"{"base":"QQQQ","generatedAtMs":1,"events":[],"flow":null,"levels":[],"position":null,"range":null,"staleMs":null,"tracked":false}"#
    let p = try JSONDecoder().decode(HighlightsPage.self, from: Data(json.utf8))
    #expect(!p.tracked)
    #expect(p.flow == nil)
    #expect(!p.hasPoints)
    #expect(HighlightsText.entrySentence(p, decimals: 1) == nil)
  }

  @Test("不认识的事件类型只丢它自己，整页照解")
  func unknownEventIsDropped() throws {
    let json = #"{"base":"X","generatedAtMs":1,"tracked":true,"events":[{"id":"a","t":"newThing","atMs":1},{"id":"b","t":"oiJump","atMs":2,"pct":1.4},7],"levels":[]}"#
    let p = try JSONDecoder().decode(HighlightsPage.self, from: Data(json.utf8))
    #expect(p.events.map(\.id) == ["b"])
  }

  @Test("首页异动一列：按 kind 解成价位 / 事件 / 三格")
  func decodesBoard() throws {
    let b = try JSONDecoder().decode(HighlightsBoard.self, from: Fixture.data("highlights-board"))
    #expect(b.rows.count == 8)
    #expect(b.rows[0].base == "BTC")
    #expect(b.rows[0].favorite)
    #expect(b.rows[0].count == 8)
    #expect(b.rows[0].tier == 3)
    guard case .level(let l) = b.rows[0].top else { Issue.record("BTC 应是价位"); return }
    #expect(l.id == "L:14153")
    guard case .position = b.rows[4].top else { Issue.record("ARPA 应是三格"); return }
    #expect(b.rows[4].cat == .funding)

    let ev = #"{"generatedAtMs":1,"rows":[{"atMs":1,"base":"ETH","cat":"book","changePct":0.6,"count":1,"favorite":true,"price":3812.4,"tier":1,"top":{"kind":"event","id":"E:wallCancel:1","t":"wallCancel","atMs":1791606780000,"price":3820,"usd":19600000,"side":"sell","distPct":0.05}},{"base":"BAD","cat":"book","top":{"kind":"mystery"}}]}"#
    let b2 = try JSONDecoder().decode(HighlightsBoard.self, from: Data(ev.utf8))
    #expect(b2.rows.count == 1)
    #expect(HighlightsText.homeFact(b2.rows[0], zone: Self.utc8).plain == "卖墙撤单 19.6M · 距价 0.05%")
    #expect(HighlightsText.focusID(b2.rows[0]) == "E:wallCancel:1")
  }

  @Test("榜单一张卡")
  func decodesMarketBoard() throws {
    let b = try JSONDecoder().decode(MarketBoard.self, from: Fixture.data("market-board-oi"))
    #expect(b.rows.count == 6)
    #expect(b.rows[0].base == "LUMIA")
    #expect(b.rows[0].oiUsd == 13_449_956)
  }

  // MARK: 数

  @Test("金额短写")
  func usd() {
    #expect(HighlightsText.usd(35_000_000) == "35M")
    #expect(HighlightsText.usd(19_600_000) == "19.6M")
    #expect(HighlightsText.usd(4_000_000) == "4M")
    #expect(HighlightsText.usd(405_690_391) == "406M")
    #expect(HighlightsText.usd(7_043_845_231) == "7B")
    #expect(HighlightsText.usd(999_600) == "1M")
    #expect(HighlightsText.usd(2_454) == "2.5K")
    #expect(HighlightsText.usd(640) == "640")
    #expect(HighlightsText.signedUSD(-7_926_786) == "\u{2212}7.9M")
    #expect(HighlightsText.signedUSD(64_221_237) == "+64.2M")
    #expect(HighlightsText.signedUSD(0) == "0")
  }

  @Test("百分数、距离、费率")
  func percents() {
    #expect(HighlightsText.flowPct(-0.04) == "\u{2212}0.04%")
    #expect(HighlightsText.flowPct(1.62) == "+1.6%")
    #expect(HighlightsText.flowPct(0) == "0.00%")
    #expect(HighlightsText.flowPct(nil) == "—")
    #expect(HighlightsText.distance(-0.41) == "0.4%")
    #expect(HighlightsText.distance(0.05) == "0.05%")
    #expect(HighlightsText.funding(0.00045) == "0.045%")
    #expect(HighlightsText.funding(-0.0026) == "\u{2212}0.26%")
    #expect(HighlightsText.funding(-1.506e-05) == "\u{2212}0.0015%")
    #expect(HighlightsText.funding(0.0001) == "0.01%")
  }

  @Test("价格：≥ 1 的最多 5 位有效数字、千分位；不到 1 的照品种位数")
  func prices() {
    #expect(HighlightsText.price(82_939.8, decimals: 1) == "82,940")
    #expect(HighlightsText.price(3_812.43, decimals: 2) == "3,812.4")
    #expect(HighlightsText.price(114.92, decimals: 2) == "114.92")
    #expect(HighlightsText.price(1.97808, decimals: 4) == "1.9781")
    #expect(HighlightsText.price(0.0000077, decimals: 7) == "0.0000077")
    #expect(HighlightsText.band(low: 86_120, high: 86_180, decimals: 1) == "86,120–86,180")
    #expect(HighlightsText.band(low: 87_450, high: 87_450.2, decimals: 1) == "87,450")
  }

  @Test("时间：时刻、时段、多久以前、持续")
  func times() {
    let t: Int64 = 1_791_606_780_000  // 北京时间 12:33
    #expect(HighlightsText.clock(t, zone: Self.utc8) == "12:33")
    #expect(HighlightsText.span(from: t, to: t + 15 * 60_000, zone: Self.utc8, compact: true) == "12:33–48")
    #expect(HighlightsText.span(from: t, to: t + 40 * 60_000, zone: Self.utc8, compact: true) == "12:33–13:13")
    #expect(HighlightsText.ago(t, now: t + 20_000) == "刚才")
    #expect(HighlightsText.ago(t, now: t + 12 * 60_000) == "12 分前")
    #expect(HighlightsText.ago(t, now: t + 125 * 60_000) == "2 小时前")
    #expect(HighlightsText.duration(48 * 60_000) == "48 分")
    #expect(HighlightsText.duration(58_733_844) == "16 时")
    #expect(HighlightsText.duration(80 * 3_600_000) == "3 天")
  }

  // MARK: 句子

  @Test("入口条：离现价最近的价位；没有价位写 1 时净主动")
  func entrySentence() throws {
    let p = try Self.page("highlights-btc")
    let s = try #require(HighlightsText.entrySentence(p, decimals: 1))
    #expect(s.plain == "下方 82,609 买区 406M · 挂 16 时 · 测 26 次")
    #expect(s.first(where: \.strong)?.text == "82,609")

    let bare = HighlightsPage(base: "X", generatedAtMs: 1, tracked: true,
                              flow: .init(rows: [FlowRow(w: .h1, netUsd: 46_000_000, pxPct: 1.4, oiPct: 3.1)]))
    #expect(HighlightsText.entrySentence(bare, decimals: 1)?.plain == "1 时净主动 +46M")

    let fill = HighlightsPage(base: "X", generatedAtMs: 1, tracked: true, levels: [
      HighlightLevel(id: "a", low: 85_400, high: 85_400, side: .bid, distPct: -1.3, fillBuyUsd: 70e6, fillSellUsd: 50e6, tests: 5),
      HighlightLevel(id: "b", low: 87_450, high: 87_450, side: .ask, distPct: 1.1, fillBuyUsd: 20e6, fillSellUsd: 28e6, tests: 3),
    ])
    #expect(HighlightsText.entrySentence(fill, decimals: 1)?.plain == "上方 87,450 卖区 吃单 48M · 测 3 次")
  }

  @Test("流向表：窗口名、第四行加粗")
  func flowRows() throws {
    let p = try Self.page("highlights-btc")
    let rows = try #require(p.flow?.rows)
    let names = rows.map { HighlightsText.windowName($0, nowMs: p.generatedAtMs) }
    #expect(names == ["15 分", "1 时", "4 时", "区间 37 时"])
    #expect(HighlightsText.isLongRow(rows[3]))
    #expect(!HighlightsText.isLongRow(rows[0]))
    #expect(HighlightsText.windowName(FlowRow(w: .h24, netUsd: nil, pxPct: nil, oiPct: nil), nowMs: 0) == "24 时")
  }

  @Test("价位：上下各取最近两条、状态词、两行说明、展开的证据")
  func levels() throws {
    let p = try Self.page("highlights-btc")
    #expect(p.above().map(\.id) == ["L:14163"])
    #expect(p.below().map(\.id) == ["L:14158", "L:14153"])
    #expect(HighlightsText.wallState(.live) == "挂单中")
    #expect(HighlightsText.wallState(.reducing) == "撤单中")
    #expect(HighlightsText.wallState(.broken) == "已破")
    #expect(HighlightsText.wallState(nil) == nil)

    let l = p.levels[0]
    #expect(HighlightsText.levelDistance(l) == "距 0.3% · = 今日高点")
    let meta = HighlightsText.levelMeta(l)
    #expect(meta.top.plain == "墙 50M · 挂 16 时")
    #expect(meta.bottom == "爆仓 8.8M · 测 13 次")

    let ev = HighlightsText.evidence(l, zone: Self.utc8)
    #expect(ev.map(\.label) == ["吃单", "墙", "触及", "叠加"])
    #expect(ev[0].runs.plain == "买 3.8B · 卖 3.6B")
    #expect(ev[1].runs.plain == "50M · 挂 16 时 · 挂单中")
    #expect(ev[2].runs.plain.hasSuffix("未破"))
    #expect(ev[3].runs.plain == "= 今日高点")

    let zro = try Self.page("highlights-zro").levels[0]
    #expect(HighlightsText.levelMeta(zro).top.plain == "吃单 17.4M")
    #expect(HighlightsText.evidence(zro, zone: Self.utc8).map(\.label) == ["吃单", "触及"])
  }

  @Test("区间行")
  func rangeLine() throws {
    let p = try Self.page("highlights-btc")
    let r = try #require(p.range)
    let line = HighlightsText.rangeLine(r, nowMs: p.generatedAtMs, decimals: 1)
    #expect(line.runs.plain == "区间 81,386–83,500 · 已走 37 时")
    #expect(line.edges == "下沿累计吃单 6.9B · 测 4 次 ｜ 上沿 10.7B · 测 9 次")
    #expect(HighlightsText.rangePosition(r, price: 81_386.2) == 0)
    #expect(HighlightsText.rangePosition(r, price: 90_000) == 1)
  }

  @Test("三格：事实词与分位")
  func tiles() throws {
    let p = try #require(try Self.page("highlights-btc").position)
    let t = HighlightsText.tiles(p)
    #expect(t.map(\.label) == ["持仓 1 时", "费率", "现货溢价"])
    #expect(t[0].value == "+0.2%")
    #expect(t[0].fact == "增仓上涨")
    #expect(t[1].value == "\u{2212}0.0015%")
    #expect(t[1].fact == "30 天第 5 位")
    #expect(t[2].value == "+0.06%")
    #expect(t[2].pctile == 99)
    #expect(HighlightsText.comboWord(.oiDownPxDown) == "减仓下跌")
  }

  @Test("事件句")
  func events() throws {
    let p = try Self.page("highlights-btc")
    let s = HighlightsText.eventSentence(p.events[0], decimals: 1)
    #expect(s.plain == "卖墙被吃 11.3M @ 82,780 · 距价 0.01%")
    #expect(HighlightsText.eventTime(p.events[0], zone: Self.utc8) == HighlightsText.clock(p.events[0].atMs!, zone: Self.utc8))

    let zro = try Self.page("highlights-zro")
    #expect(HighlightsText.eventSentence(zro.events[0], decimals: 4).plain == "主动买入 +341K · 价格 \u{2212}0.2%")
    #expect(HighlightsText.eventSentence(zro.events[1], decimals: 4).plain == "空单爆仓 2.5K · 价格 \u{2212}0.2%")
    let oi = HighlightEvent(id: "o", t: .oiJump, atMs: 1, pct: 1.4)
    #expect(HighlightsText.eventSentence(oi, decimals: 2).plain == "持仓 5 分钟 +1.4%")
    let broken = HighlightEvent(id: "k", t: .levelBroken, atMs: 1, low: 82_500, high: 82_560, side: "bid")
    #expect(HighlightsText.eventSentence(broken, decimals: 1).plain == "买区 82,500–82,560 已破")
  }

  @Test("首页事实句：价位 / 三格")
  func homeFacts() throws {
    let b = try JSONDecoder().decode(HighlightsBoard.self, from: Fixture.data("highlights-board"))
    #expect(HighlightsText.homeFact(b.rows[0], zone: Self.utc8).plain == "下方 82,279 买区 · 130M")
    let oiRow = HighlightsBoard.Row(base: "AXS", favorite: true, count: 2, cat: .oi, tier: 3,
                                    top: .position(.init(show: true, oi: .init(pct1h: 11.6, combo: .oiUpPxUp, pctile: 99), funding: nil, spotPremium: nil)),
                                    price: 0.6214, changePct: 5.2, atMs: 0)
    #expect(HighlightsText.homeFact(oiRow, zone: Self.utc8).plain == "持仓 1 时 +11.6% · 增仓上涨")
    let fr = HighlightsBoard.Row(base: "XDP", favorite: false, count: 1, cat: .funding, tier: 2,
                                 top: .position(.init(show: true, oi: nil, funding: .init(rate: -0.0026, pctile: 1), spotPremium: .init(pct: 0.02, pctile: 60))),
                                 price: 0.1072, changePct: 4.3, atMs: 0)
    #expect(HighlightsText.homeFact(fr, zone: Self.utc8).plain == "费率 \u{2212}0.26% · 30 天第 1 位")
    #expect(HighlightsText.focusID(fr) == nil)
  }

  @Test("价区包住现价：写「现价内 a–b」、优先当最近那条、梯子上不算上方 / 下方")
  func straddlingBand() {
    let inside = HighlightLevel(id: "in", low: 63.405, high: 63.659, side: .ask, distPct: 0.05, wallUsd: 2_300_000,
                                wallHeldMs: 3_600_000, tests: 2)
    let below = HighlightLevel(id: "dn", low: 63.10, high: 63.20, side: .bid, distPct: -0.02, wallUsd: 9_000_000, tests: 1)
    let above = HighlightLevel(id: "up", low: 64.0, high: 64.1, side: .ask, distPct: 0.6, fillBuyUsd: 1e6, tests: 1)
    let p = HighlightsPage(base: "HYPE", generatedAtMs: 1, tracked: true, levels: [below, inside, above])
    let price = 63.5
    #expect(inside.straddles(price))
    #expect(!below.straddles(price))
    // 服务端距离正好是 0 也算（不知道现价时）。
    #expect(HighlightLevel(id: "z", low: 1, high: 2, side: .bid, distPct: 0).straddles(nil))

    // 距离上 `dn` 更近，但包住现价的那条赢。
    #expect(p.nearestLevel(price: price)?.id == "in")
    #expect(p.nearestLevel()?.id == "dn")
    let s = HighlightsText.entrySentence(p, decimals: 3, price: price)
    #expect(s?.plain == "现价内 63.405–63.659 卖区 2.3M · 挂 1 时 · 测 2 次")
    #expect(s?.first(where: \.strong)?.text == "63.405–63.659")

    #expect(p.atPrice(price).map(\.id) == ["in"])
    #expect(p.above(price: price).map(\.id) == ["up"])
    #expect(p.below(price: price).map(\.id) == ["dn"])
    #expect(HighlightsText.levelDistance(inside, price: price) == "现价内")
    #expect(HighlightsText.levelDistance(inside) == "距 0.05%")

    let row = HighlightsBoard.Row(base: "HYPE", favorite: false, count: 1, cat: .book, tier: 2, top: .level(inside),
                                  price: price, changePct: 1.2, atMs: 0)
    #expect(HighlightsText.homeFact(row, zone: Self.utc8).plain == "现价内 63.405–63.659 卖区 · 2.3M")
  }
}
