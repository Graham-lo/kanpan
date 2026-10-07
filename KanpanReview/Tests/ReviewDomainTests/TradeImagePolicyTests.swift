import Foundation
import Testing
import KanpanCore
import ReviewDomain

/// 哪些缩略图落盘：画完不会再变的才存（体感优化 2026-10-07）。
struct TradeImagePolicyTests {
  let hour: Int64 = 3_600_000
  let monday: Int64 = 1_789_948_800_000

  func round(opened: Int64, closed: Int64?, updated: Int64 = 1) -> TradeRound {
    TradeRound(id: "00000000-0000-8000-8000-000000000001", venue: "binance", market: "usd_m", symbol: "BTCUSDT",
               accountTag: "primary", positionSide: .both, direction: .long,
               status: closed == nil ? .open : .closed, quoteAsset: "USDT", openedAt: opened, closedAt: closed,
               holdingMs: closed.map { $0 - opened }, openAvgPrice: 100, closeAvgPrice: closed == nil ? nil : 110,
               openedQty: 1, closedQty: 1, maxQty: 1, peakNotional: 100, leverage: 10, realizedPnl: 0,
               commission: 0, commissionByAsset: [:], commissionUnpriced: false, funding: 0, netPnl: 0,
               fills: [], updatedAt: updated)
  }

  @Test func openRoundNeverPersists() {
    let r = round(opened: monday, closed: nil)
    #expect(!TradeImagePolicy.isFinal(r, spec: nil, now: monday + 100 * hour))
  }

  @Test func justClosedWaitsForRightPadding() {
    // 持仓 2 小时 → 5 分钟线，右侧留 50 分钟：平仓后半小时窗口还在长，不存；一天后存。
    let r = round(opened: monday, closed: monday + 2 * hour)
    #expect(!TradeImagePolicy.isFinal(r, spec: nil, now: monday + 2 * hour + hour / 2))
    #expect(TradeImagePolicy.isFinal(r, spec: nil, now: monday + 26 * hour))
  }

  @Test func serverSpecWindowDecides() {
    let r = round(opened: monday, closed: monday + 2 * hour)
    let spec = TradeChartSpec(interval: "1h", start: monday - 10 * hour, end: monday + 12 * hour)
    #expect(!TradeImagePolicy.isFinal(r, spec: spec, now: monday + 12 * hour + 1))
    #expect(TradeImagePolicy.isFinal(r, spec: spec, now: monday + 13 * hour))
  }

  @Test func onlyThumbnailsPersist() {
    let r = round(opened: monday, closed: monday + 2 * hour)
    let later = monday + 48 * hour
    #expect(TradeImagePolicy.persists(r, spec: nil, size: CGSize(width: 72, height: 44), now: later))
    #expect(!TradeImagePolicy.persists(r, spec: nil, size: CGSize(width: 360, height: 220), now: later))
  }

  @Test func diskKeyChangesWithVersionStyleAndSpec() {
    let size = CGSize(width: 72, height: 44)
    let a = TradeImagePolicy.diskKey(round(opened: monday, closed: monday + hour), spec: nil, size: size, style: "dark")
    let b = TradeImagePolicy.diskKey(round(opened: monday, closed: monday + hour, updated: 2), spec: nil, size: size, style: "dark")
    let c = TradeImagePolicy.diskKey(round(opened: monday, closed: monday + hour), spec: nil, size: size, style: "light")
    let d = TradeImagePolicy.diskKey(round(opened: monday, closed: monday + hour),
                                     spec: TradeChartSpec(interval: "1h", start: 0, end: 1), size: size, style: "dark")
    #expect(Set([a, b, c, d]).count == 4)
  }
}
