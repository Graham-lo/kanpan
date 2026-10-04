import Foundation
import Testing
import KanpanCore
import ReviewDomain

/// 审查 R19：回放里的开仓均价要按成交先后滚着算（和 `RoundBuilder` 同一口径），
/// 先减仓再加仓时不能把减掉的那部分仍按原价算进去。
struct TradeReplayEntryAverageTests {
  private let hour: Int64 = 3_600_000
  private let monday: Int64 = 1_789_948_800_000

  private func fill(_ n: Int, _ time: Int64, _ side: TradeSide, _ price: Decimal, _ qty: Decimal, _ role: FillRole) -> RoundFill {
    RoundFill(id: "f\(n)", orderId: "o\(n)", time: time, side: side, positionSide: .both, price: price, qty: qty,
              quoteQty: price * qty, commission: 0, commissionAsset: "USDT", realizedPnl: 0, maker: false,
              role: role, split: false)
  }

  private func round(fills: [RoundFill], opened: Int64, closed: Int64) -> TradeRound {
    TradeRound(id: "00000000-0000-8000-8000-000000000001", venue: "binance", market: "usd_m", symbol: "BTCUSDT",
               accountTag: "primary", positionSide: .both, direction: .long, status: .closed, quoteAsset: "USDT",
               openedAt: opened, closedAt: closed, holdingMs: closed - opened, openAvgPrice: 115, closeAvgPrice: 140,
               openedQty: 3, closedQty: 3, maxQty: 2, peakNotional: 230, leverage: 10, realizedPnl: 0,
               commission: 0, commissionByAsset: [:], commissionUnpriced: false, funding: 0, netPnl: 0,
               fills: fills, updatedAt: 1)
  }

  @Test func entryAverageAfterReduceThenAdd() throws {
    let open = monday + 2 * hour, reduce = monday + 5 * hour, add = monday + 8 * hour, close = monday + 12 * hour
    // 100 买 2 → 120 卖 1（剩 1 @100）→ 130 买 1（2 @115）→ 140 卖 2。
    let r = round(fills: [fill(1, open, .buy, 100, 2, .open), fill(2, reduce, .sell, 120, 1, .reduce),
                          fill(3, add, .buy, 130, 1, .add), fill(4, close, .sell, 140, 2, .close)],
                  opened: open, closed: close)
    let plan = try #require(TradeReplayPlan(round: r, spec: nil, preferred: .h1))
    #expect(plan.entryAverage(through: open - hour) == nil)
    let opened = try #require(plan.entryAverage(through: open))
    let reduced = try #require(plan.entryAverage(through: reduce))
    let added = try #require(plan.entryAverage(through: add))
    #expect(abs(opened - 100) < 1e-9)
    #expect(abs(reduced - 100) < 1e-9, "减仓只减量，均价不动")
    // 以前一锅加权是 (100×2 + 130×1) / 3 = 110。
    #expect(abs(added - 115) < 1e-9)
    #expect(plan.entrySegments(through: close) == [TradeReplayPlan.Segment(from: open, to: add, price: 100),
                                                   TradeReplayPlan.Segment(from: add, to: close, price: 115)])
    // 加仓后涨到 126.5：对 115 是 +10%。
    let floating = try #require(plan.floatingReturn(close: 126.5, at: add))
    #expect(abs(floating - 0.1) < 1e-9)
  }
}
