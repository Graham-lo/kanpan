import Foundation
import Testing
import KanpanCore
@testable import Kanpan

// 板块下钻那张品种列表的值与文案。
// 盯两件事：价格小数位到底听谁的（审查 B-07），以及排序在缺数时会不会自己换位（B.5）。

private func quote(_ base: String, pct: Double, volume: Double, price: Double) -> SectorQuote {
  SectorQuote(base: base, pct: pct, quoteVolume: volume, price: price)
}

@Suite("B-07 / B.5 板块品种列表")
struct SectorRowTests {

  // ---------------------------------------------------------------- B-07

  @Test("价格小数位听品种表的，不按数值大小现猜")
  func priceDecimalsComeFromTheSymbol() {
    // 同一个价（0.5）在不同品种上位数不同——猜的那一版会给两个都写 4 位。
    let four = SectorSymbolRow(base: "A", symbol: "AUSDT", price: 0.5, pct: 1,
                               quoteVolume: 1, isFrontier: false, decimals: 4)
    let two = SectorSymbolRow(base: "B", symbol: "BUSDT", price: 0.5, pct: 1,
                              quoteVolume: 1, isFrontier: false, decimals: 2)
    #expect(four.priceText == "0.5000")
    #expect(two.priceText == "0.50")
  }

  @Test("极小的正价绝不写成 0.00")
  func tinyPriceNeverReadsAsZero() {
    let row = SectorSymbolRow(base: "PEPE", symbol: "PEPEUSDT", price: 0.00000123, pct: 1,
                             quoteVolume: 1, isFrontier: false, decimals: 2)
    #expect(row.priceText != "0.00")
    #expect(row.priceText == "0.0000012")
  }

  @Test("品种表还没到才退回按大小猜")
  func unknownDecimalsFallBackToTheLadder() {
    let row = SectorSymbolRow(base: "BTC", symbol: "BTCUSDT", price: 76_585.1, pct: 1,
                             quoteVolume: 1, isFrontier: false, decimals: nil)
    #expect(row.priceText == "76,585.10")
  }

  @Test("build 把品种表的小数位带进每一行")
  func buildCarriesDecimals() {
    let rows = SectorSymbolRow.build(
      members: ["BTC", "PEPE"],
      quotes: ["BTC": quote("BTC", pct: 1, volume: 9, price: 76_585.123),
               "PEPE": quote("PEPE", pct: 2, volume: 8, price: 0.00000123)],
      symbolForBase: { $0 + "USDT" },
      decimalsForBase: { ["BTC": 2, "PEPE": 8][$0] })
    #expect(rows.map(\.base) == ["PEPE", "BTC"])
    #expect(rows[1].priceText == "76,585.12")
    #expect(rows[0].priceText == "0.00000123")
  }

  // ---------------------------------------------------------------- B.5

  @Test("排序只按涨跌幅，成交额再大也不插队，而且两次排出来一样")
  func rowsAreOrderedByChangeOnly() {
    // 板块品种列表的「成交额」那档排序 2026-09-28 收掉（收设置项 G）。
    let quotes: [String: SectorQuote] = [
      "AAA": quote("AAA", pct: 1, volume: 9_000_000, price: 1),
      "BBB": quote("BBB", pct: 3, volume: 5_000, price: 1),
      "CCC": quote("CCC", pct: 1, volume: .nan, price: 1),
      "DDD": quote("DDD", pct: -2, volume: 9_000, price: 1),
    ]
    let members = ["AAA", "BBB", "CCC", "DDD"]
    let first = SectorSymbolRow.build(members: members, quotes: quotes,
                                      symbolForBase: { $0 + "USDT" })
    #expect(first.map(\.base) == ["BBB", "AAA", "CCC", "DDD"])
    let again = SectorSymbolRow.build(members: members.reversed(), quotes: quotes,
                                      symbolForBase: { $0 + "USDT" })
    #expect(again.map(\.base) == first.map(\.base))
  }

  @Test("值格里缺成交额一律写「—」，和同页的价格 / 涨跌幅一个样")
  func missingVolumeReadsAsADash() {
    // 占着一格的那种（品种行的成交额列、自选详情的「24小时额」）缺数写「—」，
    // 不会一个写「—」一个写「--」（复核项 3）。
    #expect(sectorVolumeText(.nan) == "—")
    #expect(sectorVolumeText(.infinity) == "—")
    #expect(sectorVolumeText(1_234_000) == "1.23M")
    let row = SectorSymbolRow(base: "A", symbol: "AUSDT", price: 1, pct: 1,
                              quoteVolume: .nan, isFrontier: false, decimals: 2)
    #expect(row.volumeText == sectorVolumeText(.nan))
  }

  @Test("成交额值格缺数时写「—」，永远有字")
  func missingVolumeCellStillHasText() {
    #expect(!sectorVolumeText(.nan).isEmpty)
    #expect(sectorVolumeText(1_234_000) == "1.23M")
  }

  @Test("涨跌幅缺数的行也沉到最后并按代号定序")
  func invalidPercentsSinkToTheBottom() {
    let quotes: [String: SectorQuote] = [
      "AAA": quote("AAA", pct: .nan, volume: 1, price: 1),
      "BBB": quote("BBB", pct: -3, volume: 1, price: 1),
      "CCC": quote("CCC", pct: .nan, volume: 1, price: 1),
      "DDD": quote("DDD", pct: 4, volume: 1, price: 1),
    ]
    let members = ["CCC", "AAA", "DDD", "BBB"]
    let rows = SectorSymbolRow.build(members: members, quotes: quotes,
                                     symbolForBase: { $0 + "USDT" })
    #expect(rows.map(\.base) == ["DDD", "BBB", "AAA", "CCC"])
    #expect(rows[2].signedText == "—")
  }

  // ---------------------------------------------------------------- 板块列表（2026-09-24 起的首页）

  private func board(_ id: String, pct: Double, members: Int = 5, breadth: Double = 0.6,
                     volume: Double = 1_200_000_000) -> SectorStat {
    SectorStat(id: id, name: id, market: .crypto, pct: pct, memberCount: members,
               quoteVolume: volume, isFallback: false, breadth: breadth)
  }

  @Test("板块列表按涨跌幅降序，并列按 id，非数沉底")
  func boardOrderIsByChangeDescending() {
    let got = SectorBoardOrder.sorted([
      board("b", pct: 1), board("nan", pct: .nan), board("a", pct: 1),
      board("up", pct: 7), board("down", pct: -3),
    ])
    #expect(got.map(\.id) == ["up", "a", "b", "down", "nan"])
    // 换个进场次序排出来一样——两次刷新之间不换位。
    #expect(SectorBoardOrder.sorted(got.reversed()).map(\.id) == got.map(\.id))
  }

  @Test("成员不到三只的板块整档排在后面，一只币拉一根也顶不到第一")
  func thinBoardsSinkBelowRealSectors() {
    let got = SectorBoardOrder.sorted([
      board("desci", pct: 38, members: 1), board("pair", pct: 12, members: 2),
      board("ai", pct: 4), board("meme", pct: -2), board("nan", pct: .nan),
    ])
    #expect(got.map(\.id) == ["ai", "meme", "nan", "desci", "pair"])
    #expect(SectorBoardOrder.sorted(got.reversed()).map(\.id) == got.map(\.id))
  }

  @Test("副文案只有一句：x/N 跑赢大盘（2026-09-28 起不写品种数与成交额）")
  func boardSubtitleSpellsOutTheBenchmark() {
    #expect(SectorSubtitle.row(board("l1", pct: 1, members: 5, breadth: 0.6)) == "3/5 跑赢大盘")
    // 成交额有没有都一样：这一句里没有它。
    #expect(SectorSubtitle.row(board("l1", pct: 1, members: 5, breadth: 0.6, volume: .nan)) == "3/5 跑赢大盘")
    // 成员不够三家：没有广度可言，给空串（调用处整行不画）。
    #expect(SectorSubtitle.row(board("l1", pct: 1, members: 2, breadth: 0.5)) == "")
    // 下钻页头部和列表行同一个出口、同一句。
    #expect(SectorSubtitle.text(board("l1", pct: 1)) == SectorSubtitle.row(board("l1", pct: 1)))
    #expect(!SectorSubtitle.row(board("l1", pct: 1)).contains("个品种"))
    #expect(!SectorSubtitle.row(board("l1", pct: 1)).contains("成交额"))
  }

  @Test("页头规模：N 个板块 · M 个品种")
  func scaleLine() {
    #expect(SectorSubtitle.scale(sectors: 28, symbols: 526) == "28 个板块 · 526 个品种")
  }

  // ---------------------------------------------------------------- 领涨

  @Test("板块行的「领涨 X」：算数的板块才写，读不出的代号换中文简称")
  func leaderLabel() {
    func stat(_ leader: String?, n: Int = 5, pct: Double = 1) -> SectorStat {
      SectorStat(id: "x", name: "x", market: .us, pct: pct, memberCount: n,
                 quoteVolume: 1, isFallback: false, leader: leader)
    }
    #expect(SectorLeaderLabel.text(stat("NVDA")) == "领涨 NVDA")
    #expect(SectorLeaderLabel.text(stat("HK0992")) == "领涨 联想")
    #expect(SectorLeaderLabel.text(stat("LGELECTRONICS")) == "领涨 LG 电子")
    #expect(SectorLeaderLabel.text(stat("1000PEPE")) == "领涨 1000PEPE")
    #expect(SectorLeaderLabel.text(stat(nil)) == "")
    #expect(SectorLeaderLabel.text(stat("NVDA", n: 2)) == "", "成员不够不算数")
    #expect(SectorLeaderLabel.text(stat("NVDA", pct: .nan)) == "", "覆盖不够不算数")
  }
}
