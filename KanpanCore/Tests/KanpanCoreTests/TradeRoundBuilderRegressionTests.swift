import Foundation
import Testing
@testable import KanpanCore

// 深度审查 E 线 · 拼回合的回归用例（R7 资金费与孤儿旧仓、R20 反手手续费拆分）。

@Suite struct TradeRoundBuilderRegressionTests {
  typealias F = TradeFixture

  @Test("R7 双向持仓：回溯前的多头旧仓 + 窗口里新开的空仓，资金费按名义额分，空仓只拿自己那份")
  func hedgeFundingSharesWithOrphan() throws {
    var b = F.builder()
    let long = PositionKey(symbol: "BTCUSDT", positionSide: .long)
    let short = PositionKey(symbol: "BTCUSDT", positionSide: .short)
    // 此刻多 1、空 1；窗口里只看到开空那一笔 → 多头 1 是窗口前的旧仓。
    let out = b.ingest(fills: [F.fill(1, .sell, "1", at: "60000", t: F.t0, ps: .short)],
                       funding: [F.funding(9, "-10", t: F.t0 + 8 * F.hour)],
                       context: .init(currentPositions: [long: 1, short: -1]))
    let r = try #require(out.first)
    #expect(out.count == 1 && r.positionSide == .short && r.status == .open)
    // 旧仓的均价不知道，按同品种开着的回合的均价折名义额：60000 : 60000，各一半。
    #expect(r.funding == -5)
  }

  @Test("R7 同品种没有开着的回合可借均价时，旧仓按这一轮的标记价折名义额")
  func orphanWeightFallsBackToMarkPrice() throws {
    var b = F.builder()
    let long = PositionKey(symbol: "BTCUSDT", positionSide: .long)
    let first = b.ingest(fills: [
      F.fill(1, .sell, "1", at: "100", t: F.t0, ps: .short),
      F.fill(2, .buy, "1", at: "110", t: F.t0 + 2 * F.hour, ps: .short, pnl: "-10"),
    ], funding: [], context: .init(currentPositions: [long: 1]))
    let closed = try #require(first.first)
    #expect(closed.status == .closed && closed.funding == 0)

    // 空仓开着期间的一条资金费，下一轮才拉到：空仓名义额 100，旧多头 1 × 标记价 300。
    let late = b.ingest(fills: [], funding: [F.funding(9, "-4", t: F.t0 + F.hour)],
                        context: .init(markPrices: ["BTCUSDT": 300]))
    let again = try #require(late.first)
    #expect(again.id == closed.id)
    #expect(again.funding == -1)
  }

  @Test("R7 没有旧仓时整条资金费照旧全归开着的回合")
  func noOrphanKeepsWholeFunding() throws {
    var b = F.builder()
    let out = b.ingest(fills: [F.fill(1, .sell, "1", at: "60000", t: F.t0, ps: .short)],
                       funding: [F.funding(9, "-10", t: F.t0 + 8 * F.hour)],
                       context: .init(currentPositions: [PositionKey(symbol: "BTCUSDT", positionSide: .short): -1]))
    #expect(out.first?.funding == -10)
  }

  @Test("R20 反手拆手续费：平仓那一半四舍五入，开仓那一半拿剩下的，两半加起来分毫不差", arguments: [
    ("0.00000003", "2"),  // 1.5e-8 各自舍入成 2e-8，两半合计 4e-8 ≠ 3e-8
    ("0.00000001", "2"),  // 0.5e-8 银行家舍入成 0，两半合计 0 ≠ 1e-8
    ("0.1", "3"),
  ])
  func reversalFeeHalvesSumExactly(fee: String, qty: String) throws {
    var b = F.builder()
    let out = b.ingest(fills: [
      F.fill(1, .buy, "1", at: "100", t: F.t0),
      F.fill(2, .sell, qty, at: "110", t: F.t0 + F.hour, pnl: "10", fee: fee),
    ], funding: [], context: .init())
    let long = try #require(out.first { $0.direction == .long })
    let short = try #require(out.first { $0.direction == .short })
    let closingHalf = try #require(long.fills.last)
    let openingHalf = try #require(short.fills.first)
    #expect(closingHalf.id == "2" && openingHalf.id == "2")
    #expect(closingHalf.commission + openingHalf.commission == F.d(fee))
    #expect(long.commission + short.commission == F.d(fee))
  }
}
