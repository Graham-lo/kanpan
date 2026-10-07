import Foundation
import Testing
import KanpanCore
@testable import KanpanData

/// 外部指标（主动买卖、多空比、基差）的盘上缓存（体感 2026-10-07）：换品种先画旧的，再补。
@Suite("外部指标盘上缓存") struct MetricStoreTests {
  private func store() -> (OIStore, URL) {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    return (OIStore(paths: Paths(root: root)), root)
  }

  @Test func roundTripKeepsNegativeValuesAndIsPerIndicatorAndInterval() async {
    let (store, root) = store()
    defer { try? FileManager.default.removeItem(at: root) }
    let points = [OIPoint(time: 3_600_000, value: -12.5), OIPoint(time: 7_200_000, value: 0.83)]
    await store.saveMetric("basis", symbol: "binance/usd_m/BTCUSDT", interval: .h1, points: points, from: 3_600_000, to: 7_200_000)
    let back = await store.loadMetric("basis", symbol: "binance/usd_m/BTCUSDT", interval: .h1)
    #expect(back?.points == points)
    #expect(back?.from == 3_600_000 && back?.to == 7_200_000)
    #expect(await store.loadMetric("lsr", symbol: "binance/usd_m/BTCUSDT", interval: .h1) == nil)
    #expect(await store.loadMetric("basis", symbol: "binance/usd_m/BTCUSDT", interval: .h4) == nil)
    // 和持仓量那份互不相扰。
    #expect(await store.loadSeries(symbol: "binance/usd_m/BTCUSDT", interval: .h1) == nil)
  }

  @Test func keepsOnlyTheRecentTail() async {
    let (store, root) = store()
    defer { try? FileManager.default.removeItem(at: root) }
    let step: Int64 = 300_000
    let points = (0..<(OIStore.metricPointLimit + 100)).map { OIPoint(time: Int64($0) * step, value: Double($0)) }
    await store.saveMetric("taker", symbol: "binance/usd_m/ETHUSDT", interval: .m5, points: points, from: 0,
                           to: points.last!.time)
    let back = await store.loadMetric("taker", symbol: "binance/usd_m/ETHUSDT", interval: .m5)
    #expect(back?.points.count == OIStore.metricPointLimit)
    #expect(back?.from == 100 * step, "裁掉左边那截，区间左端跟着收")
    #expect(back?.points.last == points.last)
  }

  @Test func disabledStoreNeitherReadsNorWrites() async {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: root) }
    let store = OIStore(paths: Paths(root: root), enabled: false)
    await store.saveMetric("lsr", symbol: "binance/usd_m/BTCUSDT", interval: .h1,
                           points: [OIPoint(time: 0, value: 1)], from: 0, to: 0)
    #expect(await store.loadMetric("lsr", symbol: "binance/usd_m/BTCUSDT", interval: .h1) == nil)
  }
}
