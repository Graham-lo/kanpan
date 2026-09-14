import Foundation

/// 惯性一帧的位置（§7，原型 `flingAt`）。
public struct FlingSample: Sendable, Equatable {
  /// 从抬手到现在总共走了多少像素。
  public var pastPx: Double
  /// 停了没有。
  public var done: Bool
}

public func flingAt(speedPxPerMs: Double, elapsedMs: Double, tauMs: Double = Chart.flingTauMs) -> FlingSample {
  let tau = tauMs == 0 ? Chart.flingTauMs : tauMs
  let time = max(0, elapsedMs)
  let left = exp(-time / tau)
  let total = speedPxPerMs * tau
  let pastPx = total * (1 - left)
  let done = time >= Chart.flingMaxMs || abs(total) * left < Chart.flingEpsPx
  return FlingSample(pastPx: pastPx, done: done)
}

/// 抬手时这个速度算不算「甩」（原型：只有下限，比 0.2 px/ms 慢就直接不甩）。
public func isFling(speedPxPerMs v: Double) -> Bool {
  abs(v) >= Chart.flingMinPxPerMs
}

/// 甩出去用的速度：方向保留，大小封顶 3 px/ms（原型 `Math.sign(speed) * Math.min(MAX, s)`）。
public func flingSpeed(_ v: Double) -> Double {
  (v < 0 ? -1 : 1) * min(Chart.flingMaxPxPerMs, abs(v))
}

/// 速度取样：只看最近 100 ms 的位移（§7）。
public struct VelocityTracker: Sendable {
  private var samples: [(t: Double, x: Double)] = []
  public let windowMs: Double
  public init(windowMs: Double = 100) { self.windowMs = windowMs }

  public mutating func add(x: Double, t: Double) {
    samples.append((t, x))
    while let first = samples.first, t - first.t > windowMs { samples.removeFirst() }
  }
  public mutating func reset() { samples.removeAll(keepingCapacity: true) }

  /// px/ms，正负同手指方向。
  public var velocity: Double {
    guard let a = samples.first, let b = samples.last, b.t > a.t else { return 0 }
    return (b.x - a.x) / (b.t - a.t)
  }
}
