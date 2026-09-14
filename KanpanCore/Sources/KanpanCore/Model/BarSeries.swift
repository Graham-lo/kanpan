import Foundation

/// 列式 K 线序列（§4.2）。
///
/// 列式而不是 `[Bar]`：指标逐列扫、绘制逐列扫、快照逐列写，三处都省一次拆包。
public struct BarSeries: Sendable, Equatable {
  public let symbol: String
  public let interval: Interval
  /// 第一根 openTime，毫秒。
  public private(set) var t0: Int64
  /// 周期毫秒。1M 是名义 30 天，真实位置看 `openTime`。
  public let step: Int64

  public var open: [Double]
  public var high: [Double]
  public var low: [Double]
  public var close: [Double]
  public var volume: [Double]
  /// 不等距周期（1M）必须带；等距周期留空，由 `t0 + i*step` 推。
  public var openTime: [Int64]

  public var count: Int { close.count }
  public var isEmpty: Bool { close.isEmpty }

  public init(
    symbol: String, interval: Interval, t0: Int64, step: Int64? = nil,
    open: [Double], high: [Double], low: [Double], close: [Double], volume: [Double],
    openTime: [Int64] = []
  ) {
    self.symbol = symbol
    self.interval = interval
    self.t0 = t0
    self.step = step ?? interval.stepMs
    self.open = open
    self.high = high
    self.low = low
    self.close = close
    self.volume = volume
    self.openTime = openTime
  }

  public init(symbol: String, interval: Interval, bars: [Bar]) {
    self.init(
      symbol: symbol, interval: interval,
      t0: bars.first?.openTime ?? 0, step: interval.stepMs,
      open: bars.map(\.open), high: bars.map(\.high), low: bars.map(\.low),
      close: bars.map(\.close), volume: bars.map(\.volume),
      openTime: interval.isIrregular ? bars.map(\.openTime) : []
    )
  }

  // ------------------------------------------------------------ 时间 ↔ 下标

  /// 第 i 根的 openTime。等距周期算出来，不等距周期查表。
  public func time(at i: Int) -> Int64 {
    if !openTime.isEmpty { return openTime[max(0, min(openTime.count - 1, i))] }
    return t0 + Int64(i) * step
  }

  /// 最后一根的 openTime。空序列返回 `t0`。
  public var lastTime: Int64 { count > 0 ? time(at: count - 1) : t0 }
  public var firstTime: Int64 { t0 }

  /// 距离 `t` 最近的一根（原型 `indexAt` 的 `Math.round`；不等距周期改二分）。
  public func index(atTime t: Double) -> Int {
    guard count > 0 else { return 0 }
    if openTime.isEmpty {
      let i = Int(((t - Double(t0)) / Double(step)).jsRounded())
      return max(0, min(count - 1, i))
    }
    // 二分找最后一个 openTime <= t，再和下一根比距离，取近的。
    var lo = 0, hi = count - 1
    if t <= Double(openTime[0]) { return 0 }
    if t >= Double(openTime[hi]) { return hi }
    while lo + 1 < hi {
      let mid = (lo + hi) / 2
      if Double(openTime[mid]) <= t { lo = mid } else { hi = mid }
    }
    let dLo = abs(t - Double(openTime[lo]))
    let dHi = abs(Double(openTime[hi]) - t)
    return dHi < dLo ? hi : lo
  }

  public func bar(at i: Int) -> Bar {
    Bar(openTime: time(at: i), open: open[i], high: high[i], low: low[i], close: close[i], volume: volume[i])
  }

  // ------------------------------------------------------------ 实时合成（§4.4）

  /// 覆盖末根。openTime 不同则是新根，走 `append`。
  public mutating func replaceLast(with bar: Bar) {
    guard count > 0 else { append(bar); return }
    let i = count - 1
    open[i] = bar.open; high[i] = bar.high; low[i] = bar.low
    close[i] = bar.close; volume[i] = bar.volume
    if !openTime.isEmpty { openTime[i] = bar.openTime }
  }

  public mutating func append(_ bar: Bar) {
    if count == 0 { t0 = bar.openTime }
    open.append(bar.open); high.append(bar.high); low.append(bar.low)
    close.append(bar.close); volume.append(bar.volume)
    if !openTime.isEmpty || interval.isIrregular {
      if openTime.isEmpty { openTime = (0..<count - 1).map { t0 + Int64($0) * step } }
      openTime.append(bar.openTime)
    }
  }

  /// WS 事件合成：openTime 等于末根就覆盖，大于就追加，更早就忽略。
  @discardableResult
  public mutating func upsert(_ bar: Bar) -> Bool {
    guard count > 0 else { append(bar); return true }
    let last = lastTime
    if bar.openTime == last { replaceLast(with: bar); return true }
    if bar.openTime > last { append(bar); return true }
    return false
  }

  /// 向前补历史：接在最前面，`t0` 跟着走（§7 补历史触发）。
  public mutating func prepend(_ bars: [Bar]) {
    guard !bars.isEmpty else { return }
    let sorted = bars.sorted { $0.openTime < $1.openTime }
    let cut = sorted.filter { count == 0 || $0.openTime < t0 }
    guard !cut.isEmpty else { return }
    if !openTime.isEmpty || interval.isIrregular {
      if openTime.isEmpty { openTime = (0..<count).map { t0 + Int64($0) * step } }
      openTime.insert(contentsOf: cut.map(\.openTime), at: 0)
    }
    open.insert(contentsOf: cut.map(\.open), at: 0)
    high.insert(contentsOf: cut.map(\.high), at: 0)
    low.insert(contentsOf: cut.map(\.low), at: 0)
    close.insert(contentsOf: cut.map(\.close), at: 0)
    volume.insert(contentsOf: cut.map(\.volume), at: 0)
    t0 = cut[0].openTime
  }
}

extension Double {
  /// JS 的 `Math.round`：.5 一律往 +∞ 走（Swift 的 `rounded()` 是离零远，负半数上不同）。
  func jsRounded() -> Double { (self + 0.5).rounded(.down) }
}
