import Foundation

/// 一根 K 线。序列内部是列式（SoA），这个结构只在增删末根这类单根操作时用。
public struct Bar: Sendable, Equatable {
  public var openTime: Int64
  public var open: Double
  public var high: Double
  public var low: Double
  public var close: Double
  public var volume: Double

  /// Validate exchange OHLCV before it can contaminate every derived indicator.
  public var isValidMarketBar: Bool {
    [open, high, low, close, volume].allSatisfy(\.isFinite)
      && low >= 0 && high >= max(open, close) && low <= min(open, close) && volume >= 0
  }

  public init(openTime: Int64, open: Double, high: Double, low: Double, close: Double, volume: Double) {
    self.openTime = openTime
    self.open = open
    self.high = high
    self.low = low
    self.close = close
    self.volume = volume
  }
}

/// 持仓量的一点。最细 5 分钟——REST 只给最近 30 天，更早的走归档站（§4.5）。
///
/// 后面四个是同一份 metrics 里顺手读出来的多空比。1.0 不画，留着是因为将来加一个
/// 「多空比」副图就只是加一条曲线的事，不用把归档再解一遍。
public struct OIPoint: Sendable, Equatable {
  public var time: Int64
  public var value: Double
  public var topTraderAccountRatio: Double?
  public var topTraderPositionRatio: Double?
  public var accountRatio: Double?
  public var takerVolumeRatio: Double?

  public init(time: Int64, value: Double,
              topTraderAccountRatio: Double? = nil, topTraderPositionRatio: Double? = nil,
              accountRatio: Double? = nil, takerVolumeRatio: Double? = nil) {
    self.time = time
    self.value = value
    self.topTraderAccountRatio = topTraderAccountRatio
    self.topTraderPositionRatio = topTraderPositionRatio
    self.accountRatio = accountRatio
    self.takerVolumeRatio = takerVolumeRatio
  }
}

/// 持仓量序列；保留旧等距存档，也支持按图表周期聚合后的真实时间戳。
public struct OISeries: Sendable, Equatable {
  // 和 `BarSeries` 一样挂 `didSet`：字段是 `public var`，外面能直接改，
  // 戳必须跟着动。`didSet` 里没碰 `oldValue`，不会多拷数组（SE-0268）。
  public var t0: Int64 { didSet { revision = SeriesStamp.next() } }
  public var step: Int64 { didSet { revision = SeriesStamp.next() } }
  public var values: [Double] { didSet { revision = SeriesStamp.next() } }
  /// Archived OI can span years and use a different cadence from recent REST samples.
  public var timestamps: [Int64]? { didSet { revision = SeriesStamp.next() } }
  /// 非空时仅对齐相同周期桶；缺失桶不能冒用前一个周期的持仓量。
  public var bucketInterval: Interval? { didSet { revision = SeriesStamp.next() } }

  /// 这一份持仓量的身份，全局唯一。
  ///
  /// 有它才能 O(1) 地回答「还是刚才那份吗」：`==` 拿它走快路，指标引擎拿它决定
  /// 能不能只对齐尾巴。一个 tick 里 `ChartRenderer.recalc` 和 `ChartView.sameFrame`
  /// 加起来要比好几次 `oi`，每次都逐个元素扫太亏。
  public private(set) var revision: UInt64 = 0

  public init(t0: Int64, step: Int64, values: [Double]) {
    self.t0 = t0; self.step = step; self.values = values; self.timestamps = nil; self.bucketInterval = nil
    self.revision = SeriesStamp.next()
  }

  /// Sparse historical samples retain their real timestamps without a dense 50,000-slot cutoff.
  public init(points: [OIPoint], step: Int64 = 300_000, bucketInterval: Interval? = nil) {
    let ordered = points.sorted { $0.time < $1.time }
    self.t0 = ordered.first?.time ?? 0; self.step = step
    self.values = ordered.map(\.value); self.timestamps = ordered.map(\.time)
    self.bucketInterval = bucketInterval
    self.revision = SeriesStamp.next()
  }

  /// 戳相同一定是同一份；不同就退回逐字段比（两份分别建出来的一样的数据，戳不一样）。
  public static func == (a: OISeries, b: OISeries) -> Bool {
    if a.revision == b.revision { return true }
    return a.t0 == b.t0 && a.step == b.step && a.bucketInterval == b.bucketInterval
      && a.values == b.values && a.timestamps == b.timestamps
  }

  /// 原型 `oiAligned()`：每根 K 线取 `floor((t - t0) / step)` 那一条，越界留 NaN。
  public func aligned(to series: BarSeries) -> [Double] {
    var out = [Double](repeating: .nan, count: series.count)
    guard step > 0 else { return out }
    if let times = timestamps {
      guard times.count == values.count, let last = times.last else { return out }
      var j = 0
      for i in 0..<series.count {
        let t = series.time(at: i)
        while j + 1 < times.count && times[j + 1] <= t { j += 1 }
        if let interval = bucketInterval {
          let matching = interval.stepMs >= 300_000
            ? times[j] == Aggregator.bucketStart(ms: t, interval: interval)
            : times[j] <= t && t - times[j] < 300_000
          if matching { out[i] = values[j] }
        } else if times[j] <= t && t < last + step { out[i] = values[j] }
      }
      return out
    }
    for i in 0..<series.count {
      let t = series.time(at: i)
      let j = Int(floor(Double(t - t0) / Double(step)))
      if j >= 0 && j < values.count { out[i] = values[j] }
    }
    return out
  }

  /// 只重算 `[start, count)` 那一段，前面的原样留用。
  ///
  /// 每个 tick 都把整列持仓量重新对齐一遍是纯浪费：K 线的前缀没动、这份持仓量
  /// 也没换（调用方拿 `revision` 确认过），那么 `out[i]`（只取决于第 i 根的时间
  /// 和这份持仓量）对 i < start 就一个字都不会变。
  ///
  /// 结果和整列 `aligned(to:)` **逐位相同**：稀疏分支里那个游标 `j` 是「最后一个
  /// `times[j] <= t`」，只跟 `t` 有关、跟从哪儿开始扫无关，这里用二分把它找回来
  /// 再接着往下走。
  public func aligned(to series: BarSeries, from start: Int, previous: [Double]) -> [Double] {
    guard previous.count <= series.count, start >= 0, start <= previous.count else {
      return aligned(to: series)
    }
    var out = previous
    if out.count < series.count {
      out.append(contentsOf: [Double](repeating: .nan, count: series.count - out.count))
    }
    guard step > 0 else { return aligned(to: series) }
    if let times = timestamps {
      guard times.count == values.count, let last = times.last else { return aligned(to: series) }
      guard start < series.count else { return out }
      // 二分出 start 这一根对应的游标，和从 0 一路推过来的那个 j 是同一个。
      var j = 0
      let t0Bar = series.time(at: start)
      var lo = 0, hi = times.count - 1
      while lo < hi {
        let mid = (lo + hi + 1) / 2
        if times[mid] <= t0Bar { lo = mid } else { hi = mid - 1 }
      }
      j = lo
      for i in start..<series.count {
        let t = series.time(at: i)
        while j + 1 < times.count && times[j + 1] <= t { j += 1 }
        out[i] = .nan
        if let interval = bucketInterval {
          let matching = interval.stepMs >= 300_000
            ? times[j] == Aggregator.bucketStart(ms: t, interval: interval)
            : times[j] <= t && t - times[j] < 300_000
          if matching { out[i] = values[j] }
        } else if times[j] <= t && t < last + step { out[i] = values[j] }
      }
      return out
    }
    for i in start..<series.count {
      let t = series.time(at: i)
      let j = Int(floor(Double(t - t0) / Double(step)))
      out[i] = (j >= 0 && j < values.count) ? values[j] : .nan
    }
    return out
  }
}

/// 持仓量在某个周期下的可用性。
public enum OIAvailability: Sendable, Equatable {
  case available(period: String)
  case unsupported   // 周期 > 1d，币安没有
}
