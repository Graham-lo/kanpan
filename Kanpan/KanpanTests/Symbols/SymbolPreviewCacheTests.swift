import Foundation
import Testing
import KanpanCore
import KanpanData
import KanpanNetwork

@testable import Kanpan

/// 长按预览卡的缓存（审查 P2-3）：最近用过的留着，超过容量扔最旧的；
/// 按过但一直取不到数的品种也算进容量，「最近」表不会无限长。
@Suite("预览卡缓存")
@MainActor
struct SymbolPreviewCacheTests {
  @Test("超过容量从最旧的扔，重新用过的挪到最新")
  func evictsLeastRecentlyUsed() {
    var lru = PreviewRecentKeys(capacity: 3)
    var evicted: [[String]] = []
    for key in ["A", "B", "C", "A"] { evicted.append(lru.touch(key)) }
    let nothingDropped = evicted.joined().isEmpty
    #expect(nothingDropped, "没满之前谁也不扔；A 已在表里，只是挪到最新")
    let dropped = lru.touch("D")
    #expect(dropped == ["B"], "最久没用的是 B")
    #expect(lru.keys == ["C", "A", "D"])
  }

  @Test("一直按新品种，表长永远不超过容量")
  func neverGrowsPastCapacity() {
    var lru = PreviewRecentKeys(capacity: SymbolPreviewStore.capacity)
    var evicted = 0
    for i in 0..<200 { evicted += lru.touch("S\(i)").count }
    #expect(lru.keys.count == SymbolPreviewStore.capacity)
    #expect(evicted == 200 - SymbolPreviewStore.capacity)
    #expect(lru.keys.last == "S199")
  }
}

/// 体感（2026-10-07）：长按那一刻先画盘上快照，不等 REST。
@Suite("预览卡先画快照")
@MainActor
struct SymbolPreviewSnapshotSeedTests {
  @Test("主图看过的那只：按住那一刻卡上就有 K 线")
  func warmDrawsSnapshotImmediately() throws {
    let key = "binance/usd_m/ETHUSDT"
    let root = Paths(root: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString))
    defer { try? FileManager.default.removeItem(at: root.root) }
    let store = SymbolPreviewStore()
    store.configure(route: RouteResolver(policy: .direct, endpoints: MarketEndpoints()))
    store.snapshotRoot = root
    let service = SymbolPreviewService(resolver: RouteResolver(policy: .direct, endpoints: MarketEndpoints()))
    let dir = RoutedMarketFeed.snapshotPaths(for: service.capabilities(for: key), in: root).series
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    let hour: Int64 = 3_600_000
    let end = Aggregator.bucketStart(ms: Int64(Date().timeIntervalSince1970 * 1000), interval: .h1)
    let rows = (0..<80).map { i in
      Bar(openTime: end - Int64(79 - i) * hour, open: 10, high: 12, low: 9, close: 11, volume: 1)
    }
    try SeriesStore.write(BarSeries(symbol: key, interval: .h1, bars: rows), in: dir)
    #expect(store.bars(for: key).isEmpty)
    store.warm(symbol: key, base: "ETH")
    #expect(store.bars(for: key).count == SymbolPreviewStore.barCount)
    #expect(store.bars(for: key).last?.openTime == end)
  }
}
