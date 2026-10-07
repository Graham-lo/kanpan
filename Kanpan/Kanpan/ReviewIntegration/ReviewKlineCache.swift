import Foundation
import KanpanCore
import KanpanData
import KanpanNetwork
import ReviewDomain

/// 复盘取历史 K 线的那一个口子：笔记重温、交易回放、复盘本缩略图都走这里。
///
/// 盘上那份（`ReviewKlineStore`，`Library/Caches/kanpan/review-klines`，48 MB 封顶、按最近使用淘汰）
/// 全 app 只有一个：同一笔单子的缩略图取过的那段，打开交易回放时直接就有；同一条记录第二次
/// 打开一页都不用再取。缺的部分切成整页、最多三页同时在路上（每页仍走 provider 自己的限频）。
enum ReviewKlineCache {
  static let shared = ReviewKlineStore(directory: testDelay == nil ? Paths.caches().reviewKlines
    : FileManager.default.temporaryDirectory.appendingPathComponent("review-klines-\(UUID().uuidString)"))

  /// 界面测试用：每一页先停这么多秒再取，并且换一份空盘（每次启动都从没缓存起），
  /// 好在快网上也看得见「加载回放」那一枚。线上不设。
  private static let testDelay: Double? = ProcessInfo.processInfo.environment["KANPAN_TEST_REVIEW_KLINE_DELAY"]
    .flatMap(Double.init).flatMap { $0 > 0 ? $0 : nil }

  /// 本家数据里 `[start, end)` 这一段的**源周期** K 线（交给 `MarketSeries.series` 聚成 `interval`）。
  ///
  /// - Parameter overflow: 交易回放 / 笔记重温给 `.fail`（超过 `maxBars` 根就报「区间过长」）；
  ///   缩略图给 `.truncate`（只画开头那一截）。
  static func sourceBars(provider: any MarketProvider, key: String, interval: Interval,
                         start: Int64, end: Int64, maxBars: Int,
                         overflow: ReviewKlineLoader.Overflow,
                         store: ReviewKlineStore? = ReviewKlineCache.shared) async throws -> [Bar] {
    let caps = provider.capabilities
    let source = caps.source(for: interval)
    do {
      return try await ReviewKlineLoader.load(
        symbol: key, interval: source, namespace: caps.snapshotNamespace,
        start: start, end: end, pageLimit: caps.maxKlines, maxBars: maxBars, overflow: overflow,
        now: ReviewClock.now, store: store
      ) { from, through, limit in
        if let delay = testDelay { try await Task.sleep(for: .seconds(delay)) }
        return try await provider.klines(symbol: key, interval: interval, limit: limit, startTime: from, endTime: through)
      }
    } catch is ReviewKlineLoader.TooLarge {
      throw ReviewBridgeError.rangeTooLarge
    }
  }

  /// 盘上现成有的那一截（一页都不取），聚成 `interval`。交易回放开图时先画它。
  static func cachedSeries(provider: any MarketProvider, key: String, interval: Interval,
                           start: Int64, end: Int64,
                           store: ReviewKlineStore = ReviewKlineCache.shared) async -> (series: BarSeries, complete: Bool) {
    let caps = provider.capabilities
    let hit = await store.lookup(symbol: key, interval: caps.source(for: interval),
                                 namespace: caps.snapshotNamespace, from: start, to: end)
    return (MarketSeries.series(symbol: key, interval: interval, bars: hit.bars, capabilities: caps), hit.isComplete)
  }
}
