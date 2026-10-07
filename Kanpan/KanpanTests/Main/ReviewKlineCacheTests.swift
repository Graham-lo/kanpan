import Foundation
import Testing
import KanpanCore
import KanpanData
import KanpanNetwork
import ReviewDomain
@testable import Kanpan

/// 交易回放开图先垫缩略图取过的那一截、整卷在盘上时直接出（体感优化 2026-10-07）。
@MainActor
struct ReviewKlineCacheTests {
  /// 2026-09-21 00:00 UTC（周一）。
  let monday: Int64 = 1_789_948_800_000
  let hour: Int64 = 3_600_000

  func tempStore() -> (ReviewKlineStore, URL) {
    let dir = FileManager.default.temporaryDirectory.appendingPathComponent("rkl-app-\(UUID().uuidString)")
    return (ReviewKlineStore(directory: dir), dir)
  }

  var provider: any MarketProvider {
    RouteResolver(route: MarketRoute(policy: .direct, endpoints: .production)).ownDataProvider(venue: "binance")!
  }

  func round(opened: Int64, closed: Int64) -> TradeRound {
    TradeRound(id: "00000000-0000-8000-8000-000000000001", venue: "binance", market: "usd_m", symbol: "BTCUSDT",
               accountTag: "primary", positionSide: .both, direction: .long,
               status: .closed, quoteAsset: "USDT", openedAt: opened, closedAt: closed,
               holdingMs: closed - opened, openAvgPrice: 100, closeAvgPrice: 110,
               openedQty: 1, closedQty: 1, maxQty: 1, peakNotional: 100, leverage: 10, realizedPnl: 0,
               commission: 0, commissionByAsset: [:], commissionUnpriced: false, funding: 0, netPnl: 0,
               fills: [], updatedAt: 1)
  }

  func bars(_ from: Int64, to: Int64, step: Int64) -> [Bar] {
    stride(from: from, to: to, by: Int(step)).map {
      Bar(openTime: $0, open: 100, high: 101, low: 99, close: 100.5, volume: 1)
    }
  }

  @Test("回放周期没取过：垫缩略图那一档已有的那截，只画到回放起点之前，不先亮出结果")
  func previewFallsBackToThumbnailBars() async throws {
    let (store, dir) = tempStore(); defer { try? FileManager.default.removeItem(at: dir) }
    let r = round(opened: monday + 2 * hour, closed: monday + 4 * hour)
    let plan = try #require(TradeReplayPlan(round: r, spec: nil, preferred: .m1))
    #expect(plan.interval == .m1)
    let thumb = ReviewChartInterval.window(openedAt: r.openedAt, closedAt: r.closedAt, now: ReviewClock.now)
    #expect(thumb.interval == .m5)
    // 缩略图取过的那段（5 分钟线）落在盘上。
    await store.record(symbol: r.instrument.key, interval: .m5, from: thumb.start, to: thumb.end + 1,
                       bars: bars(thumb.start, to: thumb.end + 1, step: Interval.m5.stepMs), now: ReviewClock.now)
    let window = plan.fetchWindow(spec: nil)
    let preview = try #require(await ReviewChartBridge.tradePreview(plan: plan, window: window, round: r,
                                                                   provider: provider, key: r.instrument.key,
                                                                   store: store))
    #expect(preview.interval == .m5)
    #expect(preview.count >= 3)
    #expect(preview.lastTime <= plan.startBar)
  }

  @Test("整卷都在盘上：不垫（马上就是整卷），取数一页都不走网络")
  func fullTapeCachedSkipsPreviewAndNetwork() async throws {
    let (store, dir) = tempStore(); defer { try? FileManager.default.removeItem(at: dir) }
    let r = round(opened: monday + 2 * hour, closed: monday + 4 * hour)
    let plan = try #require(TradeReplayPlan(round: r, spec: nil, preferred: .m1))
    let window = plan.fetchWindow(spec: nil)
    await store.record(symbol: r.instrument.key, interval: .m1, from: window.start, to: window.end,
                       bars: bars(window.start, to: window.end, step: Interval.m1.stepMs), now: ReviewClock.now)
    let preview = await ReviewChartBridge.tradePreview(plan: plan, window: window, round: r,
                                                       provider: provider, key: r.instrument.key, store: store)
    #expect(preview == nil)
    // 区间完整命中：`sourceBars` 不发任何请求（这台测试机连不连网都一样）。
    let got = try await ReviewKlineCache.sourceBars(provider: provider, key: r.instrument.key, interval: .m1,
                                                    start: window.start, end: window.end, maxBars: 6000,
                                                    overflow: .fail, store: store)
    #expect(got.count == Int((window.end - window.start) / Interval.m1.stepMs))
  }

  @Test("超过上限报的是「区间过长」那句")
  func tooLargeMapsToBridgeError() async {
    let (store, dir) = tempStore(); defer { try? FileManager.default.removeItem(at: dir) }
    await #expect(throws: ReviewBridgeError.self) {
      _ = try await ReviewKlineCache.sourceBars(provider: provider, key: "BTCUSDT", interval: .m1,
                                                start: monday, end: monday + 30 * 24 * hour, maxBars: 6000,
                                                overflow: .fail, store: store)
    }
  }

  @Test("垫图截法：回放起点之前不够三根就退到开仓之前")
  func cutPreviewFallback() {
    let step = Interval.h1.stepMs
    let s = BarSeries(symbol: "BTCUSDT", interval: .h1, bars: bars(monday, to: monday + 10 * step, step: step))
    let early = ReviewChartBridge.cutPreview(s, startBar: monday + 4 * step, openBar: monday + 6 * step)
    #expect(early.count == 5)
    let late = ReviewChartBridge.cutPreview(s, startBar: monday + step, openBar: monday + 6 * step)
    #expect(late.count == 6)
    #expect(late.lastTime < monday + 6 * step)
  }

  @Test("交易回放的加载胶囊：文案短、晚一拍才露面")
  func loadingCapsuleCopy() {
    #expect(ReplayLoadingCapsule.title == "加载回放")
    #expect(ReplayLoadingCapsule.delay >= .milliseconds(200))
  }
}
