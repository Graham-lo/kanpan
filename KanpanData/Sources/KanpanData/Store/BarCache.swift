import Foundation
import KanpanCore

public struct SeriesKey: Hashable, Sendable, CustomStringConvertible {
  public var symbol: String
  public var interval: Interval
  public init(_ symbol: String, _ interval: Interval) { self.symbol = InstrumentID.canonical(symbol); self.interval = interval }
  public var description: String { "\(symbol)|\(interval.rawValue)" }
}

/// 内存缓存（§4.3）。
///
/// K 线**不永久存盘**：这里放内存，进程没了就没了。上限 160 MB（≈ 400 万根），
/// 按 LRU 淘汰；单个 (品种, 周期) 上限 20 万根；收到内存警告清到只剩当前那对。
///
/// 上限从 40 MB 抬到 160 MB，是拿内存换「本次会话里切回去不重拉」。
/// 机器有 8~12 G 内存也不再往上抬：iOS 的 jetsam 是按「这个进程占了多少」来挑
/// 杀谁的，前台占得越多，退到后台越早被杀——而被杀一次，恰恰就是「切回来要重新
/// 加载」的根因。也就是说这一档之上买不到速度，只会买到重启。
/// 真正拿来换体验的是磁盘（见 `SeriesStore`，512 MB）：磁盘没有这个惩罚。
///
/// 160 MB 本身也已经够用：1800 根 × 56 B ≈ 100 KB 一对，装得下 ~1600 对。
public actor BarCache {
  /// 一根的估算字节数：6 列 Double（含主动买成交量）。带 openTime 表的另算。
  public static let bytesPerBar = 48
  public static let bytesPerBarWithTime = 56
  public static let defaultLimitBytes = 160 * 1024 * 1024
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

  /// 带代次的放入：`since` 之后清过（内存警告 / 整个清空）就不放，返回假。
  ///
  /// 给后台预热用。预热从发请求到拿回数据隔着一趟网络，清缓存可能正好落在这中间；
  /// 原来拿回来照样 `put`，刚清出来的内存又被灌回去（压测 2026-09-26：
  /// 三个槽路上的 8 份在警告之后全部回填，缓存从 1 对回到 9 对）。判断和放入在同一个 actor 调用里，没有缝。
  @discardableResult
  public func put(_ series: BarSeries, ifGeneration since: Int) -> Bool {
    guard since == generation else { return false }
    put(series)
    return true
  }

  /// 清过几次（`purge` / `removeAll` 各加一）。见 `put(_:ifGeneration:)`。
  public private(set) var generation = 0

  public func remove(_ key: SeriesKey) {
    store[key] = nil
    lru.removeAll { $0 == key }
  }

  public func removeAll() {
    generation &+= 1
    store.removeAll()
    lru.removeAll()
  }

  /// 内存警告：只留当前这对（§4.3）。
  public func purge(keeping key: SeriesKey?) {
    generation &+= 1
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
    t.close.removeFirst(drop); t.volume.removeFirst(drop); t.takerBuy.removeFirst(drop)
    if !t.openTime.isEmpty { t.openTime.removeFirst(drop) }
    return BarSeries(symbol: t.symbol, interval: t.interval, t0: newT0, step: t.step,
                     open: t.open, high: t.high, low: t.low, close: t.close, volume: t.volume,
                     takerBuy: t.takerBuy, openTime: t.openTime)
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
