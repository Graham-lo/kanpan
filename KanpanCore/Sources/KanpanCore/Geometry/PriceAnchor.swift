import Foundation

/// 拖价格轴时让按下那一点的价格钉住不动（§13 G6）。
///
/// 原型的价格轴拖只改 `price.zoom`，区间永远绕着 `mid` 缩放，按下点会跟着滑——任务书
/// 明确要求「按下点价格不动」，所以这里补一个 `shift` 的求解。改的只是 `shift`，
/// `priceRange` 的公式一个字没动。
///
/// 为什么用二分而不是解析式：`lo`/`hi` 是**价格**空间的平移，而对数与百分比模式下
/// `yOf` 先做一次 `log` / 归一化，平移在那两个空间里不是平移，解析解得按模式各写一套。
/// `yOf` 对 `shift` 单调（抬高区间，同一个价格就往下走），二分 60 步稳稳到 1e-12，
/// 一次手势一帧一次，代价可以忽略。
public enum PriceAnchor {
  /// 缩放到 `zoom` 之后，要让 `price` 仍旧落在 `y` 上，`shift` 该取多少。
  ///
  /// - Parameter range: 只依赖 `zoom`/`shift` 之外的部分，所以调用方传**同一套输入**
  ///   算出来的 `PriceRange` 工厂闭包：给一个 `shift`，还一个区间。
  public static func shift(
    keeping price: Double, at y: Double, pane: Pane, mode: PriceMode,
    zoom: Double, rangeFor: (_ shift: Double) -> PriceRange,
    limit: Double = 64
  ) -> Double {
    // 对数模式下区间下沿一旦跌到 0 以下，`log(max(1e-12, p))` 就把曲线压平，
    // `yOf` 不再单调，二分会收敛到一个离谱的值。所以先问一句这个 shift 合不合法。
    func usable(_ s: Double) -> Bool {
      let r = rangeFor(s)
      guard r.lo.isFinite, r.hi.isFinite, r.hi > r.lo else { return false }
      switch mode {
      case .log: return r.lo > 0
      case .percent: return r.base > 0
      case .linear: return true
      }
    }
    func err(_ s: Double) -> Double {
      yOf(price, pane: pane, range: rangeFor(s), mode: mode) - y
    }
    guard usable(0) else { return 0 }
    let e0 = err(0)
    if abs(e0) < 1e-12 { return 0 }

    // 从 0 往一边成倍地探，探到夹住目标为止。探不到（越探越不合法）就停在最后一个
    // 合法值上：能让按下点少跑一点是一点，总好过直接放弃。
    var lo = 0.0, hi = 0.0
    let outward = e0 > 0 ? -1.0 : 1.0
    var found = false
    var step = 0.25
    var edge = 0.0
    while step <= limit {
      let c = outward * step
      guard usable(c) else { break }
      edge = c
      if err(c) * e0 <= 0 { found = true; break }
      step *= 2
    }
    guard found else { return edge }
    if outward < 0 { lo = edge; hi = 0 } else { lo = 0; hi = edge }
    for _ in 0..<60 {
      let mid = (lo + hi) / 2
      if err(mid) < 0 { lo = mid } else { hi = mid }
    }
    return (lo + hi) / 2
  }

  /// 价格轴竖拖的缩放倍数（原型 `Math.exp(-dy / 220)`，上下限 0.25…6）。
  public static func zoom(from zoom0: Double, dy: Double) -> Double {
    max(0.25, min(6, zoom0 * exp(-dy / 220)))
  }

  /// 时间轴横拖的窗宽倍数。原型没有这条（§13 G7 要求补），沿用价格轴同一个 220 的手感常数：
  /// 往左拖看得更长，往右拖看得更细。
  public static func spanFactor(dx: Double) -> Double { exp(-dx / 220) }
}
