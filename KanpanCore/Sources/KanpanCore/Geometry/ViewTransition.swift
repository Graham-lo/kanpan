import Foundation

/// 导航过渡及iPhone最新端松手回位；历史惯性仍在硬边界停止。
public enum ViewTransition {
  /// 无过冲、有限时长的回位。320ms和曲线系数属于实现取舍，非原版测量值。
  public static func rebound(from a: ViewWindow, to b: ViewWindow, elapsedMs: Double)
    -> (view: ViewWindow, done: Bool) {
    let t = max(0, min(1, elapsedMs / 320))
    guard t < 1 else { return (b, true) }
    let remaining = (1 + 9 * t) * exp(-9 * t)
    // 根宽也一起回（捏合软越界抬手弹回 [1.6, 40]）。左右两缘同一个权重线性插值，
    // 两指中点那一刻对着的时间在整段回弹里一直站在原地。只是拖出空白时两边根宽相同，照旧。
    return (ViewWindow(to: b.to + (a.to - b.to) * remaining,
                       span: b.span + (a.span - b.span) * remaining), false)
  }

  public static func frame(from a: ViewWindow, to b: ViewWindow, elapsedMs: Double)
    -> (view: ViewWindow, done: Bool) {
    let t = max(0, min(1, elapsedMs / 200))
    let e = t * t * (3 - 2 * t)
    return (ViewWindow(from: a.from + (b.from - a.from) * e,
                       to: a.to + (b.to - a.to) * e), t >= 1)
  }
}
