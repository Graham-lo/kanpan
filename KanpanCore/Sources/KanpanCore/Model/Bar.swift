import Foundation

/// 一根 K 线。序列内部是列式（SoA），这个结构只在增删末根这类单根操作时用。
public struct Bar: Sendable, Equatable {
  public var openTime: Int64
  public var open: Double
  public var high: Double
  public var low: Double
  public var close: Double
  public var volume: Double

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

/// 持仓量序列。等距（period 固定），对齐时按「不晚于这根开盘」取。
public struct OISeries: Sendable, Equatable {
  public var t0: Int64
  public var step: Int64
  public var values: [Double]

  public init(t0: Int64, step: Int64, values: [Double]) {
    self.t0 = t0; self.step = step; self.values = values
  }

  /// 原型 `oiAligned()`：每根 K 线取 `floor((t - t0) / step)` 那一条，越界留 NaN。
  public func aligned(to series: BarSeries) -> [Double] {
    var out = [Double](repeating: .nan, count: series.count)
    guard step > 0 else { return out }
    for i in 0..<series.count {
      let t = series.time(at: i)
      let j = Int(floor(Double(t - t0) / Double(step)))
      if j >= 0 && j < values.count { out[i] = values[j] }
    }
    return out
  }
}

/// 持仓量在某个周期下的可用性。
public enum OIAvailability: Sendable, Equatable {
  case available(period: String)
  case unsupported   // 周期 > 1d，币安没有
}
