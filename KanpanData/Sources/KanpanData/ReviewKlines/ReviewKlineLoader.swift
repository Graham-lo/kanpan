import Foundation
import KanpanCore

/// 复盘取一段历史 K 线：先问盘上缓存（`ReviewKlineStore`），缺的那几段切成整页**并行**去取，
/// 取回来的已收盘部分记回盘上，最后拼成 `[start, end)` 里按时间排好的一列。
///
/// 并行是在限频预算之内的：每一页仍然走 provider 自己的那条限频（币安是共用的权重预算），
/// 这里只是不再「一页等一页」——同时在路上的最多 `maxConcurrent` 页。
public enum ReviewKlineLoader {
  /// 区间超出上限时怎么办。
  public enum Overflow: Sendable {
    /// 直接报错（交易回放：持仓太久、这档周期装不下）。
    case fail
    /// 只取开头那 `maxBars` 根（缩略图：画得下多少画多少）。
    case truncate
  }

  /// 区间超过 `maxBars` 根。
  public struct TooLarge: Error, Equatable {}

  /// 取一页：`[start, endInclusive]`，最多 `limit` 根，按 openTime 升序。
  public typealias Fetch = @Sendable (_ start: Int64, _ endInclusive: Int64, _ limit: Int) async throws -> [Bar]

  /// 把 `[start, end)` 切成要去取的那几块。不等距的周期（月、年）不切，一块里顺着翻页。
  static func chunks(_ missing: [Range<Int64>], interval: Interval, pageLimit: Int) -> [Range<Int64>] {
    guard !interval.isIrregular else { return missing }
    let span = interval.stepMs * Int64(max(1, pageLimit))
    var out: [Range<Int64>] = []
    for gap in missing {
      var s = gap.lowerBound
      while s < gap.upperBound {
        let e = min(gap.upperBound, s + span)
        out.append(s..<e)
        s = e
      }
    }
    return out
  }

  /// - Parameters:
  ///   - end: 不含。
  ///   - namespace: 行情源分区（替身上游的数据要和真身分开放），见 `ProviderCapabilities.snapshotNamespace`。
  ///   - store: 传 nil 就是不走盘（全都去取）。
  public static func load(symbol: String, interval: Interval, namespace: String? = nil,
                          start: Int64, end: Int64, pageLimit: Int, maxBars: Int,
                          overflow: Overflow, now: Int64, store: ReviewKlineStore?,
                          maxConcurrent: Int = 3, fetch: @escaping Fetch) async throws -> [Bar] {
    var end = end
    switch overflow {
    case .truncate:
      end = min(end, interval.advancing(start, by: maxBars))
    case .fail:
      // 名义步长估一下（月、年按 30 / 365 天，偏多估不会漏报）。
      if (end - start) / max(1, interval.stepMs) > Int64(maxBars) { throw TooLarge() }
    }
    guard end > start else { return [] }

    let cached: ReviewKlineStore.Lookup
    if let store {
      cached = await store.lookup(symbol: symbol, interval: interval, namespace: namespace, from: start, to: end)
    } else {
      cached = .init(bars: [], missing: [start..<end])
    }
    let pieces = chunks(cached.missing, interval: interval, pageLimit: pageLimit)

    var fetched: [Bar] = []
    if !pieces.isEmpty {
      fetched = try await withThrowingTaskGroup(of: [Bar].self) { group in
        var queue = pieces[...]
        var inFlight = 0
        var out: [Bar] = []
        func launch() {
          guard let piece = queue.popFirst() else { return }
          inFlight += 1
          group.addTask {
            let bars = try await page(piece, interval: interval, pageLimit: pageLimit, fetch: fetch)
            await store?.record(symbol: symbol, interval: interval, namespace: namespace,
                                from: piece.lowerBound, to: piece.upperBound, bars: bars, now: now)
            return bars
          }
        }
        for _ in 0..<max(1, maxConcurrent) { launch() }
        while inFlight > 0, let bars = try await group.next() {
          inFlight -= 1
          out.append(contentsOf: bars)
          if overflow == .fail, out.count + cached.bars.count > maxBars {
            group.cancelAll()
            throw TooLarge()
          }
          launch()
        }
        return out
      }
    }

    var byTime: [Int64: Bar] = [:]
    for bar in cached.bars { byTime[bar.openTime] = bar }
    for bar in fetched { byTime[bar.openTime] = bar }
    let merged = byTime.values.filter { $0.openTime >= start && $0.openTime < end }.sorted { $0.openTime < $1.openTime }
    if overflow == .fail, merged.count > maxBars { throw TooLarge() }
    return merged
  }

  /// 一块里顺着翻页，直到翻过块尾或交易所不再给。
  static func page(_ piece: Range<Int64>, interval: Interval, pageLimit: Int, fetch: Fetch) async throws -> [Bar] {
    var out: [Bar] = []
    var s = piece.lowerBound
    while s < piece.upperBound {
      try Task.checkCancellation()
      let page = try await fetch(s, piece.upperBound - 1, pageLimit)
      guard let last = page.last else { break }
      out.append(contentsOf: page.lazy.filter { $0.openTime >= piece.lowerBound && $0.openTime < piece.upperBound })
      let next = interval.advancing(last.openTime, by: 1)
      guard next > s else { break }
      s = next
    }
    return out
  }
}
