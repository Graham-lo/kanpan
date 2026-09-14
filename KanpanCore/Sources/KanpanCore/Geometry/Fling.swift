import Foundation

/// AICoin uses Android OverScroller. This is its AOSP SPLINE phase in reference dp units.
/// Reference friction/min/max need iPhone calibration; screen scale is not Android density.
public struct FlingCurve: Sendable, Equatable {
  public let durationMs: Double
  public let distance: Double
  public init(speedPointsPerSecond v: Double) {
    let rate = log(0.78) / log(0.9)
    let physical = 9.80665 * 39.37 * 160 * 0.84
    let friction = 0.015
    let speed = min(8000, abs(v))
    guard speed > 0, speed.isFinite else { durationMs = 0; distance = 0; return }
    let l = log(0.35 * speed / (friction * physical))
    durationMs = floor(1000 * exp(l / (rate - 1)))
    distance = (v < 0 ? -1 : 1) * floor(friction * physical * exp(rate * l / (rate - 1)))
  }

  private static let position: [Double] = (0...100).map { i in
    if i == 100 { return 1 }
    let time = Double(i) / 100
    var lo = 0.0, hi = 1.0, x = 0.0
    for _ in 0..<32 {
      x = (lo + hi) / 2
      let tx = 3 * x * (1 - x) * ((1 - x) * 0.175 + x * 0.35) + x * x * x
      if tx < time { lo = x } else { hi = x }
    }
    return 3 * x * (1 - x) * ((1 - x) * 0.5 + x) + x * x * x
  }

  public func sample(elapsedMs: Double) -> (pastPx: Double, done: Bool) {
    guard durationMs > 0, elapsedMs < durationMs else { return (distance, true) }
    if elapsedMs <= 0 { return (0, false) }
    let t = elapsedMs / durationMs * 100
    let i = min(99, Int(t)), f = t - Double(i)
    let p = Self.position[i] + (Self.position[i + 1] - Self.position[i]) * f
    return ((distance * p).rounded(), false)
  }
}

public struct FlingRun: Sendable, Equatable {
  public let curve: FlingCurve
  public let start: ViewWindow
  public let plotW: Double
  public init?(speedPxPerMs v: Double, start: ViewWindow, plotW: Double) {
    guard v.isFinite, abs(v * 1000) > 50, plotW > 0 else { return nil }
    curve = FlingCurve(speedPointsPerSecond: v * 1000)
    self.start = start; self.plotW = plotW
  }
  public func frame(elapsedMs: Double) -> (view: ViewWindow, done: Bool) {
    let sample = curve.sample(elapsedMs: elapsedMs)
    return (start.dragged(byFingerPx: sample.pastPx, plotW: plotW), sample.done)
  }
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
