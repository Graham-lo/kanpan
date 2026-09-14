import Foundation
import KanpanCore

public struct SeriesKey: Hashable, Sendable, CustomStringConvertible {
  public var symbol: String
  public var interval: Interval
  public init(_ symbol: String, _ interval: Interval) { self.symbol = symbol; self.interval = interval }
  public var description: String { "\(symbol)|\(interval.rawValue)" }
}

/// 内存缓存（§4.3）。
///
/// K 线**不永久存盘**：这里放内存，进程没了就没了。上限 40 MB（≈ 100 万根），
/// 按 LRU 淘汰；单个 (品种, 周期) 上限 20 万根；收到内存警告清到只剩当前那对。
public actor BarCache {
  /// 一根的估算字节数：5 列 Double。带 openTime 表的另算。
  public static let bytesPerBar = 40
  public static let bytesPerBarWithTime = 48
  public static let defaultLimitBytes = 40 * 1024 * 1024
  public static let maxBarsPerKey = 200_000

  private var store: [SeriesKey: BarSeries] = [:]
  /// 最近用过的排在后面。
  private var lru: [SeriesKey] = []
  private let limitBytes: Int
  private let perKeyCap: Int

  public init(limitBytes: Int = BarCache.defaultLimitBytes, perKeyCap: Int = BarCache.maxBarsPerKey) {
    self.limitBytes = limitBytes
    self.perKeyCap = perKeyCap
  }

  public static func bytes(of s: BarSeries) -> Int {
    s.count * (s.openTime.isEmpty ? bytesPerBar : bytesPerBarWithTime)
  }

  public var totalBytes: Int { store.values.reduce(0) { $0 + Self.bytes(of: $1) } }
  public var count: Int { store.count }
  /// 从最旧到最新，淘汰就是从头砍。
  public var lruOrder: [SeriesKey] { lru }
  public var keys: [SeriesKey] { lru }

  public func get(_ key: SeriesKey) -> BarSeries? {
    guard let s = store[key] else { return nil }
    touch(key)
    return s
  }

  public func put(_ series: BarSeries) {
    let key = SeriesKey(series.symbol, series.interval)
    store[key] = trim(series)
    touch(key)
    evict()
  }

  public func remove(_ key: SeriesKey) {
    store[key] = nil
    lru.removeAll { $0 == key }
  }

  public func removeAll() {
    store.removeAll()
    lru.removeAll()
  }

  /// 内存警告：只留当前这对（§4.3）。
  public func purge(keeping key: SeriesKey?) {
    for k in lru where k != key { store[k] = nil }
    lru = lru.filter { $0 == key }
  }

  // ------------------------------------------------------------------ 内部

  private func touch(_ key: SeriesKey) {
    lru.removeAll { $0 == key }
    lru.append(key)
  }

  /// 单键超过 20 万根就砍掉最左端（最旧的一段）——视野是绝对时间，回拖时按需重拉。
  private func trim(_ s: BarSeries) -> BarSeries {
    guard s.count > perKeyCap else { return s }
    let drop = s.count - perKeyCap
    var t = s
    let newT0 = s.time(at: drop)
    t.open.removeFirst(drop); t.high.removeFirst(drop); t.low.removeFirst(drop)
    t.close.removeFirst(drop); t.volume.removeFirst(drop)
    if !t.openTime.isEmpty { t.openTime.removeFirst(drop) }
    return BarSeries(symbol: t.symbol, interval: t.interval, t0: newT0, step: t.step,
                     open: t.open, high: t.high, low: t.low, close: t.close, volume: t.volume,
                     openTime: t.openTime)
  }

  private func evict() {
    var used = totalBytes
    // 最后一个是刚用过的，永远不淘汰。
    while used > limitBytes, lru.count > 1 {
      let k = lru.removeFirst()
      used -= store[k].map(Self.bytes(of:)) ?? 0
      store[k] = nil
    }
  }
}
