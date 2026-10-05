import Foundation

/// AICoin column offsets expressed as a time window. The final column includes half a cell.
public func clampView(_ v: ViewWindow, series: BarSeries, plotW: Double,
                      anchor: ViewAnchor = .right) -> ViewWindow {
  guard !series.isEmpty, plotW > 0 else { return v }
  let step = Double(series.step)
  let span = max(plotW / AICoinBehavior.maximumSpacing * step,
                 min(plotW / AICoinBehavior.minimumSpacing * step, v.span))
  return ViewMath.clampedOffset(ViewWindow(to: v.to, span: span), series: series, plotW: plotW, anchor: anchor)
}

public enum ViewMath {
  /// 单指在任一数据边界越界可拉出空白，松手回对应边界；历史中途不吸附。
  /// 阻力曲线是本项目实现参数，未宣称为原版iOS精确拟合。
  public static func dragging(_ proposed: ViewWindow, series: BarSeries, plotW: Double,
                              anchor: ViewAnchor = .right) -> ViewWindow {
    let settled = clampView(proposed, series: series, plotW: plotW, anchor: anchor)
    guard !series.isEmpty, plotW > 0, settled.span > 0 else { return settled }
    let beyond = (proposed.to - settled.to) / settled.span * plotW
    guard beyond != 0, beyond.isFinite else { return settled }
    let extent = min(32, plotW * 0.1)
    let pull = extent * (1 - 1 / (1 + 0.55 * abs(beyond) / extent))
    return ViewWindow(to: settled.to + (beyond > 0 ? pull : -pull) / plotW * settled.span, span: settled.span)
  }

  /// 只夹左右（视野在时间轴上的偏移），根宽原样不动。
  ///
  /// `clampView` = 先把根宽夹进 [1.6, 40]，再走这一步。捏合的软边界（`softSpacing`）那几帧
  /// 要的正是「根宽暂时越过去、左右照样不许出界」，所以单独拿出来。
  public static func clampedOffset(_ v: ViewWindow, series: BarSeries, plotW: Double,
                                   anchor: ViewAnchor = .right) -> ViewWindow {
    guard !series.isEmpty, plotW > 0, v.span > 0 else { return v }
    let step = Double(series.step)
    let span = v.span
    let spacing = plotW / span * step
    let first = Double(series.firstTime) - step / 2
    // 视野是时间窗，右边界得按**时间**量到末根，不能拿「根数 × 周期」去推：休市的品种
    // （美元指数周末、每天收盘那一小时）中间没有 K 线，根数推出来的末端比真实末根早出
    // 好几天，图一打开就被夹在历史中段、最新那一截永远拖不过去。不缺根的序列两者相等。
    let cells = max(Double(series.count), Double(series.lastTime - series.firstTime) / step + 1)
    let maximumOffset = maximumOffset(cells: cells, spacing: spacing, plotW: plotW, anchor: anchor)
    let offset = (v.to - span - first) / step * spacing
    let clampedOffset = max(0, min(maximumOffset, offset))
    return ViewWindow(to: first + clampedOffset / spacing * step + span, span: span)
  }

  /// 视野是不是「贴着最新」：右缘离「末根 + 右留白」不到一格。
  ///
  /// 捏合只认这一条判据（从前捏合里一条「一格以内」、`scaled` 里另一条「半个点以内」，
  /// 两条对不上，贴在半格处捏一下，这一帧算贴着、下一帧又不算，末根就抖一下）：
  /// - 贴着 → 末根钉住不动，两指中点的漂移不算数（不然人一边捏一边手指往旁边偏，最新那根就被推出屏）；
  /// - 不贴 → 绕两指中点缩放，视野跟着中点走。
  ///
  /// 「最新」按当前根宽摆（`spacing` 可以是捏合软越界那几帧的根宽），再照常夹左右：
  /// 整段序列不满一屏时，夹完的那个位置就是「最新」。
  public static func isPinnedToLatest(_ v: ViewWindow, series: BarSeries, plotW: Double,
                                      anchor: ViewAnchor = .right) -> Bool {
    guard !series.isEmpty, plotW > 0, v.span > 0, v.span.isFinite else { return false }
    let spacing = plotW / v.span * Double(series.step)
    let latest = latestView(series: series, plotW: plotW, spacing: spacing, anchor: anchor)
    return abs(v.to - latest.to) / v.span * plotW < spacing
  }

  /// 按 `spacing` 摆到最新（末根 + 右留白），只夹左右、不夹根宽。`reset` 是它夹了根宽的版本。
  static func latestView(series: BarSeries, plotW: Double, spacing: Double,
                         anchor: ViewAnchor) -> ViewWindow {
    let step = Double(series.step)
    return clampedOffset(ViewWindow(to: Double(series.lastTime) + step / 2
                                      + rightInset(anchor, plotW: plotW) / spacing * step,
                                    span: plotW / spacing * step),
                         series: series, plotW: plotW, anchor: anchor)
  }

  /// 捏合的一帧：根宽换成 `spacing`，左右照常夹，根宽**不夹**（软越界由调用方经 `softSpacing` 给）。
  ///
  /// - `pinned`（见 `isPinnedToLatest`）：末根连同右留白钉在原处。
  /// - 否则以 `focus`（两指中点，图区内的 x）为不动点缩放；视野左缘已经顶着首根时以左缘为不动点，
  ///   不然往外一捏左边就空出一截。
  public static func pinched(_ v: ViewWindow, series: BarSeries, plotW: Double, spacing: Double,
                             focus: Double, pinned: Bool, anchor: ViewAnchor = .right) -> ViewWindow {
    guard !series.isEmpty, plotW > 0, v.span > 0, spacing > 0, spacing.isFinite else { return v }
    if pinned { return latestView(series: series, plotW: plotW, spacing: spacing, anchor: anchor) }
    let step = Double(series.step)
    let oldW = plotW / v.span * step
    let offset = (v.from - Double(series.firstTime)) / step * oldW + oldW / 2
    let pin = offset <= 0.5 ? 0 : max(0, min(plotW, focus))
    let span = plotW / spacing * step
    let time = v.t(atX: pin, plotW: plotW)
    return clampedOffset(ViewWindow(from: time - pin / plotW * span,
                                    to: time + (1 - pin / plotW) * span),
                         series: series, plotW: plotW, anchor: anchor)
  }

  /// 捏合软边界越过去最多多少：根宽最多捏到 1.6 × 0.85、40 × 1.15，抬手弹回 [1.6, 40]。
  public static let zoomOvershoot = 0.15

  /// 捏合软边界：把「手指要的根宽」`raw` 换成「这一帧画出来的根宽」。
  ///
  /// [1.6, 40] 之内原样；越过去带阻尼——越界那一点斜率是 1（不打顿），越往外越紧，
  /// 渐近到 `zoomOvershoot` 那条线却永远够不着。对数空间里算，放大缩小两头手感对称。
  public static func softSpacing(_ raw: Double) -> Double {
    let lo = AICoinBehavior.minimumSpacing, hi = AICoinBehavior.maximumSpacing
    guard raw.isFinite, raw > 0 else { return lo }
    if raw > hi {
      let room = Foundation.log(1 + zoomOvershoot)
      let e = Foundation.log(raw / hi)
      return hi * exp(room * (1 - 1 / (1 + e / room)))
    }
    if raw < lo {
      let room = -Foundation.log(1 - zoomOvershoot)
      let e = Foundation.log(lo / raw)
      return lo / exp(room * (1 - 1 / (1 + e / room)))
    }
    return raw
  }

  /// `softSpacing` 的反函数：画面上是 `soft` 这么宽时，手指「要的」根宽是多少。
  ///
  /// 回弹半途又按下去接着捏，得从画面上那个根宽倒推回手指那一侧接着攒，
  /// 直接拿画面根宽当起点会在第一帧跳一下。越过渐近线的（理论上画不出来）按上限给。
  public static func rawSpacing(forSoft soft: Double) -> Double {
    let lo = AICoinBehavior.minimumSpacing, hi = AICoinBehavior.maximumSpacing
    guard soft.isFinite, soft > 0 else { return lo }
    if soft > hi {
      let room = Foundation.log(1 + zoomOvershoot)
      let u = Foundation.log(soft / hi) / room
      guard u < 1 else { return boundedRawSpacing(.infinity) }
      return boundedRawSpacing(hi * exp(room * u / (1 - u)))
    }
    if soft < lo {
      let room = -Foundation.log(1 - zoomOvershoot)
      let u = Foundation.log(lo / soft) / room
      guard u < 1 else { return boundedRawSpacing(0) }
      return boundedRawSpacing(lo / exp(room * u / (1 - u)))
    }
    return soft
  }

  /// 「手指要的根宽」最多攒到越界三倍阻尼宽度为止。再往外捏画面已经几乎不动，
  /// 攒下来的只会让人回捏时要先白捏一大段才见图动。
  public static func boundedRawSpacing(_ raw: Double) -> Double {
    let lo = AICoinBehavior.minimumSpacing, hi = AICoinBehavior.maximumSpacing
    let up = hi * pow(1 + zoomOvershoot, 3), down = lo * pow(1 - zoomOvershoot, 3)
    guard !raw.isNaN else { return hi }
    return min(up, max(down, raw))
  }

  static func maximumOffset(count: Int, spacing: Double, plotW: Double, anchor: ViewAnchor) -> Double {
    maximumOffset(cells: Double(count), spacing: spacing, plotW: plotW, anchor: anchor)
  }

  /// `cells`：从首根到末根按周期量出来的格数（缺根的序列比根数多）。
  static func maximumOffset(cells: Double, spacing: Double, plotW: Double, anchor: ViewAnchor) -> Double {
    let total = max(0, (cells + 400) * spacing - plotW)
    let reserved = min(400 * spacing - rightInset(anchor, plotW: plotW), total)
    return max(0, total - reserved)
  }

  public static func rightInset(_ anchor: ViewAnchor, plotW: Double) -> Double {
    switch anchor {
    case .right: AICoinBehavior.rightInset
    case .center: floor(plotW / 2)
    case .left: 2 * floor(plotW / 3)
    }
  }

  public static func reset(series: BarSeries, plotW: Double, spacing: Double,
                           anchor: ViewAnchor = .right) -> ViewWindow {
    guard !series.isEmpty else { return ViewWindow(from: 0, to: 1) }
    let w = min(AICoinBehavior.maximumSpacing, max(AICoinBehavior.minimumSpacing, spacing))
    let step = Double(series.step)
    let view = ViewWindow(to: Double(series.lastTime) + step / 2
                           + rightInset(anchor, plotW: plotW) / w * step,
                          span: plotW / w * step)
    return clampView(view, series: series, plotW: plotW, anchor: anchor)
  }

  /// Layout resizing preserves cell width and historical right time.
  public static func resized(_ v: ViewWindow, series: BarSeries, plotW: Double,
                             spacing: Double, anchor: ViewAnchor = .right) -> ViewWindow {
    guard !series.isEmpty else { return v }
    return clampView(ViewWindow(to: v.to, span: plotW / spacing * Double(series.step)),
                     series: series, plotW: plotW, anchor: anchor)
  }

  /// 换周期：根宽（一根占多少像素）照旧，看见的时间跨度跟着新周期走。
  ///
  /// `anchorRight` 是「切之前视野的右缘时刻」，只有在**看历史**的时候才该传：
  /// 人正翻着三个月前的那一段，切个周期就被送回最新，等于把刚找到的位置弄丢了（A-05）。
  /// 反过来，**跟着最新**的时候必须传 nil——那时右缘本来就该重新贴到新序列的末根上，
  /// 拿旧右缘去夹会在右边留下一截空白（新周期的末根时间往往比旧的更靠后）。
  /// 「在看历史还是跟着最新」由调用方判断（它才知道切之前那张图的状态）。
  public static func switchInterval(to series: BarSeries, plotW: Double, spacing: Double,
                                    anchorRight: Double?) -> ViewWindow {
    let latest = reset(series: series, plotW: plotW, spacing: spacing)
    guard let anchorRight, !series.isEmpty else { return latest }
    return clampView(ViewWindow(to: min(anchorRight, latest.to), span: latest.span),
                     series: series, plotW: plotW)
  }

  /// One accepted scale event. Boundary state, not the user's inset setting, chooses the anchor.
  /// 贴不贴最新只认 `isPinnedToLatest` 一条判据；根宽夹进 [1.6, 40]（软越界只在捏合手势里有）。
  public static func scaled(_ v: ViewWindow, series: BarSeries, plotW: Double,
                            factor: Double, focus: Double, anchor: ViewAnchor = .right) -> ViewWindow {
    guard factor > 0, factor.isFinite, !series.isEmpty, plotW > 0 else { return v }
    let oldW = v.barSpacing(step: series.step, plotW: plotW)
    let newW = min(AICoinBehavior.maximumSpacing, max(AICoinBehavior.minimumSpacing, oldW * factor))
    let pinned = isPinnedToLatest(v, series: series, plotW: plotW, anchor: anchor)
    return clampView(pinched(v, series: series, plotW: plotW, spacing: newW, focus: focus,
                             pinned: pinned, anchor: anchor),
                     series: series, plotW: plotW, anchor: anchor)
  }

  public static func needsMoreHistory(_ v: ViewWindow, series: BarSeries) -> Bool {
    !series.isEmpty && v.from <= Double(series.firstTime) + Chart.loadMoreBars * Double(series.step)
  }
}
