import Foundation

/// 回弹（原型 `Chart.settle`）。
///
/// 手指按着的时候 `clampView(soft:)` 允许越界 12%，松手要滑回硬边界。原型用 240ms
/// 三次缓出，位移不到 1ms 就直接认为已经在位、不起动画——这个 1 的单位是**毫秒**
/// （原型比的是 `target.from - view.from`，视野的单位就是毫秒），不是像素。
public enum Settle {
  public static let durationMs: Double = 240
  /// 差这么点就不值得动一帧。
  public static let epsMs: Double = 1

  /// 三次缓出，和原型 `1 - (1 - k) ** 3` 一样。
  public static func ease(_ k: Double) -> Double {
    let t = max(0, min(1, k))
    return 1 - pow(1 - t, 3)
  }

  /// 松手后该弹到哪。已经在界内就返回 `nil`，省掉一次空动画。
  public static func target(
    _ v: ViewWindow, series: BarSeries, plotW: Double
  ) -> ViewWindow? {
    let t = clampView(v, series: series, plotW: plotW)
    guard abs(t.from - v.from) >= epsMs || abs(t.to - v.to) >= epsMs else { return nil }
    return t
  }

  /// 回弹途中的某一帧。
  public static func frame(
    from a: ViewWindow, to b: ViewWindow, elapsedMs: Double
  ) -> (view: ViewWindow, done: Bool) {
    let k = min(1, max(0, elapsedMs / durationMs))
    let e = ease(k)
    // `from`/`to` 各自插值，不是插 `to` + `span`：越界回弹时两端走的量不一样
    // （`clampView` 可能同时改了窗宽），只插一端会把另一端拖歪。
    let from = a.from + (b.from - a.from) * e
    let to = a.to + (b.to - a.to) * e
    return (ViewWindow(from: from, to: to), k >= 1)
  }
}

/// 惯性滑行的一次完整过程（原型 `Chart.flick`）。
///
/// 抬手时定住起始视野与速度，之后每帧只按「从抬手到现在」算总位移——不逐帧累加，
/// 丢帧也不会走样。
public struct FlingRun: Sendable, Equatable {
  public let speedPxPerMs: Double
  public let start: ViewWindow
  public let plotW: Double

  /// 抬手速度够不够格甩。`gapMs` 是最后一次移动到抬手的间隔，原型超过 90ms 就当没甩
  /// （手指停在那儿停了一下再松开，不该飞出去）。
  public init?(speedPxPerMs v: Double, gapMs: Double, start: ViewWindow, plotW: Double) {
    guard gapMs <= 90, isFling(speedPxPerMs: v), plotW > 0 else { return nil }
    self.speedPxPerMs = flingSpeed(v)
    self.start = start
    self.plotW = plotW
  }

  /// 抬手之后第 `elapsedMs` 毫秒的视野。`done` 之后调用方该转进回弹。
  public func frame(elapsedMs: Double) -> (view: ViewWindow, done: Bool) {
    let s = flingAt(speedPxPerMs: speedPxPerMs, elapsedMs: elapsedMs)
    // 速度的符号是手指的，所以走 `dragged(byFingerPx:)`，和拖动同一条路。
    return (start.dragged(byFingerPx: s.pastPx, plotW: plotW), s.done)
  }
}
