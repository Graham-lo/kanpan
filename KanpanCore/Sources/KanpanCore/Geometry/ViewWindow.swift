import Foundation

/// 视野是**时间窗**，不是「第几根到第几根」（§5.1）。
///
/// 这是切周期能保住 K 线像素宽度的原因：周期变了，窗宽按新周期的根间距重算，
/// 右边缘不动，所以一根还是那么宽，变的是看见多长的时间。
///
/// 毫秒用 `Double` 而不是 `Int64`：原型里视野是 JS number，缩放 / 回弹都在小数上做；
/// 取整会在 `clamp` 和周期切换里累积漂移，A1.7 要求的 1e-9 就过不去。
///
/// 存的是**右缘 + 窗宽**，`from` 由这两个算出来。时间戳上万亿、窗宽可能只有几千毫秒，
/// 存 `from`/`to` 再相减会丢掉七八位有效数字，A1.7 的 1e-9 就是这么被吃掉的。
public struct ViewWindow: Sendable, Equatable {
  public var to: Double
  /// 窗宽（毫秒）。这是第一手数据，不是减出来的。
  public var span: Double

  public init(from: Double, to: Double) { self.to = to; self.span = to - from }
  public init(to: Double, span: Double) { self.to = to; self.span = span }

  public var from: Double {
    get { to - span }
    set { span = to - newValue }
  }

  /// 时间 → 像素。
  public func x(_ t: Double, plotW: Double) -> Double { (t - from) / span * plotW }
  /// 像素 → 时间。
  public func t(atX x: Double, plotW: Double) -> Double { from + x / plotW * span }

  /// 每根占多少 CSS 像素。
  public func barSpacing(step: Int64, plotW: Double) -> Double {
    plotW / (span / Double(step))
  }

  /// 平移：手指往左推 dx 像素，视野往右走。
  public func shifted(byPx dx: Double, plotW: Double) -> ViewWindow {
    let d = dx / plotW * span
    return ViewWindow(to: to + d, span: span)
  }
}
