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

extension PriceAnchor {
  /// 解出能把「自动贴合出来的区间」按住在 `target` 上的那组 `zoom`/`shift`。
  ///
  /// 用在双指缩放：价格轴本来每帧都按可见 K 线的高低重新贴合，捏合时可见根数一直变，
  /// 极值一进一出整张图就被上下拽（用户原话「缩放 k 线会自动上下跳」）。AiCoin 的做法是
  /// 框固定、内容在框里缩放，松手才重新贴合——这里就是「框固定」那一半。
  ///
  /// `raw` 是**同一套输入、`zoom = 1`/`shift = 0`** 时的区间。`priceRange` 拿到它之后是
  /// 这么叠变换的：
  ///
  ///     half = (rawSpan / 2) / zoom      off = half * 2 * shift
  ///     lo   = rawMid - half + off       hi  = rawMid + half + off
  ///
  /// 令它等于 `target`，反解即
  ///
  ///     zoom  = rawSpan / targetSpan
  ///     shift = (targetMid - rawMid) / targetSpan
  ///
  /// 线性和对数两档都精确。百分比档里 `base` 在「价格 → y」的归一化中会约掉
  /// （`(f - a) / (z - a)` 恒等于 `(p - lo) / (hi - lo)`），所以对齐 `lo`/`hi` 就够，
  /// 不用管 `base` 换没换根。
  ///
  /// 返回 `nil` 表示这一帧解不出来（区间退化成一条线，或者 `zoom` 会被 `0.15` 的下限
  /// 截掉、按不住）——调用方该原样留着上一帧的变换，别硬塞一个按不住的值进去。
  public static func freeze(
    target: PriceRange, raw: PriceRange, mode: PriceMode
  ) -> PriceTransform? {
    let span = target.hi - target.lo
    let rawSpan = raw.hi - raw.lo
    guard span > 0, rawSpan > 0, span.isFinite, rawSpan.isFinite else { return nil }
    let zoom = rawSpan / span
    guard zoom >= minZoom else { return nil }
    let shift = ((target.lo + target.hi) / 2 - (raw.lo + raw.hi) / 2) / span
    guard zoom.isFinite, shift.isFinite else { return nil }
    return PriceTransform(mode: mode, zoom: zoom, shift: shift)
  }

  /// `priceRange` 里 `max(0.15, zoom)` 的那个下限。低于它 `zoom` 会被截掉，框按不住。
  public static let minZoom: Double = 0.15
}

// MARK: - 手动定标（AiCoin 的「自动」关掉之后）

extension PriceAnchor {
  /// 把绝对区间 `range` 缩放 `factor` 倍，同时让 `price` 停在 `y` 上不动。
  ///
  /// 和上面 `shift(keeping:at:)` 的二分不同，这里区间是**绝对**的：`yOf` 在正向空间里
  /// 就是一条直线，锚点的归一化位置 `u` 保持不变即可，跨度除以 `factor` 就完事，
  /// 三个档位都有解析解。二分那套是因为 `zoom`/`shift` 要穿过「每帧重新贴合」那一层
  /// 才落到区间上，这里没有那一层。
  ///
  /// `factor` 沿用 `zoom(from:dy:)` 的语义：大于 1 ＝ 区间变窄 ＝ 看得更细。
  public static func pin(
    range: PriceRange, factor: Double, keeping price: Double, at y: Double,
    pane: Pane, mode: PriceMode
  ) -> (lo: Double, hi: Double)? {
    let a = mode.forward(range.lo, base: range.base)
    let z = mode.forward(range.hi, base: range.base)
    let span = z - a
    let f = mode.forward(price, base: range.base)
    guard span > 0, span.isFinite, f.isFinite, factor > 0, factor.isFinite, pane.h > 0
    else { return nil }
    // `yOf` 是 `pane.y + pane.h - u * pane.h`，反过来就是这个 `u`。
    let u = (pane.y + pane.h - y) / pane.h
    let newSpan = span / factor
    let newA = f - u * newSpan
    return clean(lo: mode.inverse(newA, base: range.base),
                 hi: mode.inverse(newA + newSpan, base: range.base), mode: mode)
  }

  /// 手动定标下的竖向平移：整段区间跟着手指走 `dy` 个像素（正向空间里是平移）。
  public static func pan(
    range: PriceRange, dy: Double, pane: Pane, mode: PriceMode
  ) -> (lo: Double, hi: Double)? {
    let a = mode.forward(range.lo, base: range.base)
    let z = mode.forward(range.hi, base: range.base)
    let span = z - a
    guard span > 0, span.isFinite, pane.h > 0 else { return nil }
    // 手指往下拖，图跟着往下走 ＝ 区间往上抬。
    let d = span * (dy / pane.h)
    return clean(lo: mode.inverse(a + d, base: range.base),
                 hi: mode.inverse(z + d, base: range.base), mode: mode)
  }

  /// 对数档位下正向空间一路平移是会把 `lo` 拖到 0 以下的（`exp` 出来就贴着 0），
  /// 这里统一把不能用的结果挡掉，宁可这一帧不动也不要画出一张压平的图。
  private static func clean(lo: Double, hi: Double, mode: PriceMode) -> (lo: Double, hi: Double)? {
    guard lo.isFinite, hi.isFinite, hi > lo else { return nil }
    if mode == .log, lo <= 0 { return nil }
    return (lo, hi)
  }
}
