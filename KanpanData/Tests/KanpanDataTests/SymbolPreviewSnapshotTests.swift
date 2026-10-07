import Foundation
import Testing
import KanpanCore
import KanpanNetwork
@testable import KanpanData

/// 长按预览卡先画盘上快照（体感 2026-10-07）：主图看过的那只，卡一弹出来就有走势。
@Suite("预览卡快照") struct SymbolPreviewSnapshotTests {
  let key = "binance/usd_m/BTCUSDT"
  let hour: Int64 = 3_600_000

  private func setUp() throws -> (SymbolPreviewService, Paths, URL) {
    let service = SymbolPreviewService(resolver: RouteResolver(policy: .direct, endpoints: MarketEndpoints()))
    let root = Paths(root: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString))
    let dir = RoutedMarketFeed.snapshotPaths(for: service.capabilities(for: key), in: root).series
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    return (service, root, dir)
  }

  private func bars(_ count: Int, step: Int64, end: Int64) -> [Bar] {
    (0..<count).map { i in
      Bar(openTime: end - Int64(count - 1 - i) * step, open: 10, high: 12, low: 9, close: 11, volume: 1)
    }
  }

  @Test func readsHourlySnapshotTail() throws {
    let (service, root, dir) = try setUp()
    defer { try? FileManager.default.removeItem(at: root.root) }
    let now = Date(timeIntervalSince1970: 1_760_000_000)
    let end = Aggregator.bucketStart(ms: Int64(now.timeIntervalSince1970 * 1000), interval: .h1)
    try SeriesStore.write(BarSeries(symbol: key, interval: .h1, bars: bars(100, step: hour, end: end)), in: dir)
    let rows = service.snapshotBars(for: key, root: root, now: now)
    #expect(rows.count == SymbolPreviewService.barCount)
    #expect(rows.last?.openTime == end)
  }

  @Test func aggregatesFinerSnapshotWhenNoHourly() throws {
    let (service, root, dir) = try setUp()
    defer { try? FileManager.default.removeItem(at: root.root) }
    let now = Date(timeIntervalSince1970: 1_760_000_000)
    let end = Aggregator.bucketStart(ms: Int64(now.timeIntervalSince1970 * 1000), interval: .h1)
    // 15 分钟 × 40 根 = 10 个小时。
    try SeriesStore.write(BarSeries(symbol: key, interval: .m15, bars: bars(40, step: hour / 4, end: end + 3 * hour / 4)), in: dir)
    let rows = service.snapshotBars(for: key, root: root, now: now)
    #expect(rows.count == 10)
    #expect(zip(rows, rows.dropFirst()).allSatisfy { $1.openTime - $0.openTime == hour })
  }

  @Test func staleOrMissingSnapshotGivesNothing() throws {
    let (service, root, dir) = try setUp()
    defer { try? FileManager.default.removeItem(at: root.root) }
    let now = Date(timeIntervalSince1970: 1_760_000_000)
    #expect(service.snapshotBars(for: key, root: root, now: now).isEmpty)
    let old = Int64(now.timeIntervalSince1970 * 1000) - SymbolPreviewService.snapshotMaxAgeMs - hour
    try SeriesStore.write(BarSeries(symbol: key, interval: .h1, bars: bars(60, step: hour, end: old)), in: dir)
    #expect(service.snapshotBars(for: key, root: root, now: now).isEmpty)
  }
}
