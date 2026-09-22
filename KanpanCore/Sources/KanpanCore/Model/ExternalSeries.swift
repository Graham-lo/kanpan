import Foundation

/// 外部采样序列：持仓量、多空比、主动买卖比和基差。
/// 每列对应一个指标输出；稀疏时间与桶边界沿用 OISeries 的对齐规则。
/// OISeries 由 init(oi:) 转入，保留 revision，避免每次行情更新重算整列。
public struct ExternalSeries: Sendable, Equatable {
  // 和 `BarSeries` / `OISeries` 一样挂 `didSet`：字段是 `public var`，外面能直接改，
  // 戳必须跟着动。`didSet` 里没碰 `oldValue`，不会多拷数组（SE-0268）。
  public var t0: Int64 { didSet { revision = SeriesStamp.next() } }
  public var step: Int64 { didSet { revision = SeriesStamp.next() } }
  /// 一列一条线，顺序与 `IndicatorID.lineNames` 一致。每列等长。
  public var columns: [[Double]] { didSet { revision = SeriesStamp.next() } }
  /// 稀疏采样的真实时刻。归档能横跨好几年，节拍和近期 REST 那段并不一样。
  public var timestamps: [Int64]? { didSet { revision = SeriesStamp.next() } }
  /// 非空时只对齐同一根桶；缺的桶不许冒用前一根的值。
  public var bucketInterval: Interval? { didSet { revision = SeriesStamp.next() } }

  /// 这一份的身份，全局唯一。引擎拿它 O(1) 地回答「还是刚才那份吗」，
  /// 是就只对齐尾巴。
  public private(set) var revision: UInt64 = 0

  public init(t0: Int64, step: Int64, columns: [[Double]],
              timestamps: [Int64]? = nil, bucketInterval: Interval? = nil) {
    self.t0 = t0; self.step = step; self.columns = columns
    self.timestamps = timestamps; self.bucketInterval = bucketInterval
    self.revision = SeriesStamp.next()
  }

  /// 持仓量转成单列。
  ///
  /// **戳原样带过来，不重新发一个**：引擎靠 `revision` 判断「还是刚才那份持仓量吗」，
  /// 而这次转换发生在每一帧的调用点上——每转一次就换个新戳的话，增量对齐这条路
  /// 一次都走不到，每个 tick 都要把整列重对一遍（几千根）。
  public init(oi: OISeries) {
    self.t0 = oi.t0; self.step = oi.step; self.columns = [oi.values]
    self.timestamps = oi.timestamps; self.bucketInterval = oi.bucketInterval
    self.revision = oi.revision
  }

  public var columnCount: Int { columns.count }
  /// 采样点数（各列等长，取第一列）。
  public var count: Int { columns.first?.count ?? 0 }

  /// 戳相同一定是同一份；不同就退回逐字段比（两份分别建出来的一样的数据，戳不一样）。
  public static func == (a: ExternalSeries, b: ExternalSeries) -> Bool {
    if a.revision == b.revision { return true }
    return a.t0 == b.t0 && a.step == b.step && a.bucketInterval == b.bucketInterval
      && a.columns == b.columns && a.timestamps == b.timestamps
  }

  // ---------------------------------------------------------------- 对齐

  /// 每根 K 线取哪一条采样：稀疏分支走游标 + 桶规则，等距分支走 `floor((t - t0) / step)`。
  public func aligned(to series: BarSeries) -> [[Double]] {
    var out = Self.blank(columns.count, series.count)
    guard step > 0, !columns.isEmpty else { return out }
    let n = count
    guard columns.allSatisfy({ $0.count == n }) else { return out }
    if let times = timestamps {
      guard times.count == n, let last = times.last else { return out }
      var j = 0
      for i in 0..<series.count {
        let t = series.time(at: i)
        while j + 1 < times.count && times[j + 1] <= t { j += 1 }
        guard matches(j, at: t, last: last, times: times) else { continue }
        for c in columns.indices { out[c][i] = columns[c][j] }
      }
      return out
    }
    for i in 0..<series.count {
      let t = series.time(at: i)
      let j = Int(floor(Double(t - t0) / Double(step)))
      if j >= 0 && j < n {
        for c in columns.indices { out[c][i] = columns[c][j] }
      }
    }
    return out
  }

  /// 只重算 `[start, count)` 那一段，前面的原样留用。理由与写法见 `OISeries.aligned`：
  /// K 线前缀没动、这一份也没换（调用方拿 `revision` 确认过），`out[i]` 对 i < start
  /// 就一个字都不会变。稀疏分支里的游标用二分找回来，和从 0 推过来的那个是同一个。
  public func aligned(to series: BarSeries, from start: Int, previous: [[Double]]) -> [[Double]] {
    guard previous.count == columns.count, start >= 0,
          previous.allSatisfy({ $0.count <= series.count && start <= $0.count })
    else { return aligned(to: series) }
    guard step > 0 else { return aligned(to: series) }
    let n = count
    guard columns.allSatisfy({ $0.count == n }) else { return aligned(to: series) }
    var out = previous
    for c in out.indices where out[c].count < series.count {
      out[c].append(contentsOf: [Double](repeating: .nan, count: series.count - out[c].count))
    }
    guard start < series.count else { return out }
    if let times = timestamps {
      guard times.count == n, let last = times.last else { return aligned(to: series) }
      var lo = 0, hi = times.count - 1
      let t0Bar = series.time(at: start)
      while lo < hi {
        let mid = (lo + hi + 1) / 2
        if times[mid] <= t0Bar { lo = mid } else { hi = mid - 1 }
      }
      var j = lo
      for i in start..<series.count {
        let t = series.time(at: i)
        while j + 1 < times.count && times[j + 1] <= t { j += 1 }
        let hit = matches(j, at: t, last: last, times: times)
        for c in columns.indices { out[c][i] = hit ? columns[c][j] : .nan }
      }
      return out
    }
    for i in start..<series.count {
      let t = series.time(at: i)
      let j = Int(floor(Double(t - t0) / Double(step)))
      let hit = j >= 0 && j < n
      for c in columns.indices { out[c][i] = hit ? columns[c][j] : .nan }
    }
    return out
  }

  /// 第 j 条采样能不能落在时刻 t 这根上。和 `OISeries` 那份同一套规矩。
  private func matches(_ j: Int, at t: Int64, last: Int64, times: [Int64]) -> Bool {
    if let interval = bucketInterval {
      return interval.stepMs >= 300_000
        ? times[j] == Aggregator.bucketStart(ms: t, interval: interval)
        : times[j] <= t && t - times[j] < 300_000
    }
    return times[j] <= t && t < last + step
  }

  /// `cols` 列 × `count` 根的全 NaN 底板。
  public static func blank(_ cols: Int, _ count: Int) -> [[Double]] {
    (0..<max(0, cols)).map { _ in [Double](repeating: .nan, count: count) }
  }
}
