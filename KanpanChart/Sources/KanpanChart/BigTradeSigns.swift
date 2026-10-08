import CoreGraphics
import Foundation
import KanpanCore

/// 图上「大单与爆仓」气泡的纯函数：两级门槛、摆放（错层 / 退成点）、命中、读屏（2026-10-08 定版
/// 「统一透明泡」，设计源 `docs/prototypes/web-bigtrade-bubbles-2026-10-08.html` 的 `one()`，三端规格
/// `docs/design/大单爆仓气泡-三端规格-2026-10-08.md`）。
///
/// 规则（和网页版同一口径）：
/// - 每根只剩两个数：向上 U = 大买 + 空单爆仓，挂最高价之上；向下 D = 大卖 + 多单爆仓，挂最低价之下。
///   一根最多上下各一枚，图上不分大单还是爆仓。
/// - 两级门槛：当前周期最近 `tierBars` 根里每根 `max(U, D)` 的非零分布，点线 = P90、泡线 = P97，
///   都垫同一道绝对下限（门槛 ÷ 5）。不到点线不画，到点线画小圆点，到泡线画带字的透明泡。
/// - 一屏带字的泡最多 `maxBubbles` 枚：候选按金额降序摆，大的先占位，配额用完的退成点；一根窄于
///   `bubbleMinSpacing`（按整 pt 比）时全部只画点。
/// - 点：半径 = 一根宽 × 0.4（夹在 1.5…2.8），离高 / 低点 2；泡：半径 = 11 + 6 × min(1, (v − 泡线) / (泡线 × 2))，
///   至少容得下字（字宽 / 2 + 4），离高 / 低点 4（这段画柄）。
/// - 错层：同侧已摆的（点和泡都算）挨得太近就往外推一层，最多推 6 次。
/// - 贴着主图左右沿的根（最新那根常在最右）：泡往里收到整圆落在主图里，柄仍竖直接到圆周。
/// - 泡推完出了能落的竖直范围（图例那一带以下、主图下沿以上，各留 4）、或压到画线文字，
///   就退成点（不占配额）；点也落不下就不画。
/// - 命中：只认泡（点不响应），44 × 44 热区（泡比热区大就按泡本身），几枚都中取圆心最近的那枚。
///
/// 只聚合、门槛过滤、展示，不做判定。
public enum BigTradeBubbles {
  /// 分布取多少根。
  public static let tierBars = 300
  /// 点线 / 泡线的分位。
  public static let dotQuantile = 0.90
  public static let bubbleQuantile = 0.97
  /// 一屏带字的泡最多几枚。
  public static let maxBubbles = 6
  /// 一根窄于这么多（四舍五入到整 pt 比）就全部只画点。
  public static let bubbleMinSpacing: CGFloat = 4
  /// 泡的最小半径与随金额最多再长多少。
  public static let bubbleBaseRadius: CGFloat = 11
  public static let bubbleGrowRadius: CGFloat = 6
  /// 字到泡边至少留多少。
  public static let textPadding: CGFloat = 4
  /// 点离高 / 低点、泡离高 / 低点（柄长）。
  public static let dotStem: CGFloat = 2
  public static let bubbleStem: CGFloat = 4
  /// 同侧两枚之间至少留多少、最多错几层。
  public static let nudgeGap: CGFloat = 2
  public static let nudgeLimit = 6
  /// 泡离能落范围上下沿至少留多少。
  public static let edgeInset: CGFloat = 4
  /// 点击热区边长。
  public static let hitSize: CGFloat = 44

  /// 点的半径：跟着一根宽，夹在 1.5…2.8。
  public static func dotRadius(spacing bw: CGFloat) -> CGFloat { min(2.8, max(1.5, bw * 0.4)) }

  // MARK: 门槛

  /// 已升序排好的分位数，线性插值（同 numpy 默认）。
  public static func quantile(_ sorted: [Double], _ q: Double) -> Double {
    let n = sorted.count
    guard n > 0 else { return 0 }
    let pos = Double(n - 1) * min(1, max(0, q))
    let i = Int(pos.rounded(.down))
    let fr = pos - Double(i)
    return i + 1 < n ? sorted[i] + (sorted[i + 1] - sorted[i]) * fr : sorted[i]
  }

  /// 每根 `max(U, D)` → 点线 / 泡线；`floor` = 绝对下限（门槛 ÷ 5），两条线都垫。一根有数的都没有给 nil。
  public static func tiers(_ values: [Double], floor: Double) -> BigTradeTiers? {
    let v = values.filter { $0 > 0 && $0.isFinite }.sorted()
    guard !v.isEmpty else { return nil }
    let f = floor > 0 && floor.isFinite ? floor : 0
    let dot = max(quantile(v, dotQuantile), f)
    let bubble = max(quantile(v, bubbleQuantile), f, dot)
    return BigTradeTiers(dot: dot, bubble: bubble)
  }

  /// 0 = 不画；1 = 点；2 = 泡（够格，摆不摆得成泡还看配额与位置）。
  public static func level(of value: Double, _ k: BigTradeTiers?) -> Int {
    guard let k, value > 0, value.isFinite else { return 0 }
    if value >= k.bubble { return 2 }
    if value >= k.dot { return 1 }
    return 0
  }

  /// 金额短写，三端同一口径（电脑网页 orderflow/state.ts `amt`、手机网页 bigTradeSigns.ts `amtShort`）：
  /// K / M / B / T，不足 100 一位小数、≥ 100 取整；取整后进位到 1000 就升一档（999.7M → 1.0B）。读屏用它。
  public static func amtShort(_ v: Double) -> String {
    guard v.isFinite else { return "—" }
    let units: [(Double, String)] = [(1, ""), (1e3, "K"), (1e6, "M"), (1e9, "B"), (1e12, "T")]
    let a = abs(v)
    var i = units.count - 1
    while i > 0 && a < units[i].0 { i -= 1 }
    while i < units.count {
      let (d, u) = units[i], x = v / d
      let t = abs(x) >= 100 || u.isEmpty ? toFixed(x, 0) : toFixed(x, 1)
      let n = Double(t) ?? 0
      if abs(n) < 1000 || i == units.count - 1 { return (n == 0 ? t.replacingOccurrences(of: "-", with: "") : t) + u }
      i += 1
    }
    return "—"
  }

  /// 泡上的字：`amtShort` 去掉末尾的 `M`（1.2M → 1.2、974M → 974），K / B / T 留着。
  public static func bubbleText(_ v: Double) -> String {
    let s = amtShort(v)
    return s.hasSuffix("M") ? String(s.dropLast()) : s
  }

  // MARK: 摆放

  /// 一屏的点与泡：每根上下各算一枚候选，金额大的先摆；返回摆得下的那些（按 `index` 升序，同根向上在前）。
  public static func plan(_ bars: [BigTradeBubbleInput], env: BigTradeBubbleEnv) -> [BigTradeBubble] {
    struct Cand { let b: BigTradeBubbleInput; let up: Bool; let usd: Double; let level: Int }
    var cands: [Cand] = []
    cands.reserveCapacity(bars.count * 2)
    for b in bars {
      let lu = level(of: b.up, env.tiers), ld = level(of: b.down, env.tiers)
      if lu > 0 { cands.append(Cand(b: b, up: true, usd: b.up, level: lu)) }
      if ld > 0 { cands.append(Cand(b: b, up: false, usd: b.down, level: ld)) }
    }
    cands.sort {
      if $0.usd != $1.usd { return $0.usd > $1.usd }
      if $0.b.index != $1.b.index { return $0.b.index > $1.b.index }
      return $0.up && !$1.up
    }

    let dotR = dotRadius(spacing: env.spacing)
    // 按整 pt 比：出厂间距是 4（铺满主图后实得 3.98 上下），不能因为差一丝就整屏只剩点。
    let bubblesAllowed = env.spacing.rounded() >= bubbleMinSpacing
    var placed: [[(x: CGFloat, y: CGFloat, r: CGFloat)]] = [[], []]  // [向上, 向下]
    var bubbles = 0
    var out: [BigTradeBubble] = []
    out.reserveCapacity(cands.count)

    func box(_ x: CGFloat, _ y: CGFloat, _ r: CGFloat) -> CGRect { CGRect(x: x - r, y: y - r, width: 2 * r, height: 2 * r) }
    func clearOfText(_ r: CGRect) -> Bool { !env.avoid.contains { $0.intersects(r) } }

    for c in cands {
      let side = c.up ? 0 : 1
      let x = c.b.x
      let anchor = c.up ? c.b.hiY : c.b.loY
      let dir: CGFloat = c.up ? -1 : 1
      var bubble = c.level >= 2 && bubblesAllowed && bubbles < maxBubbles
      var r = dotR
      var text = ""
      if bubble {
        text = env.text(c.usd)
        let grow = bubbleGrowRadius * CGFloat(min(1, (c.usd - env.tiers.bubble) / (env.tiers.bubble * 2)))
        r = max(bubbleBaseRadius + grow, env.measure(text) / 2 + textPadding)
      }
      // 贴着主图左右沿的那几根（最新那根常在最右）：泡往里收到整圆落在主图里，柄仍从这根竖直接到圆周。
      var cx = bubble ? min(max(x, r), env.plotW - r) : x
      var cy = anchor + dir * ((bubble ? bubbleStem : dotStem) + r)
      for _ in 0..<nudgeLimit {
        guard let p = placed[side].first(where: { hypot($0.x - cx, $0.y - cy) < $0.r + r + nudgeGap }) else { break }
        cy = p.y + dir * (p.r + r + nudgeGap)
      }
      if bubble {
        let outV = c.up ? cy - r < env.top + edgeInset : cy + r > env.bottom - edgeInset
        let outH = 2 * r > env.plotW
        if outV || outH || !clearOfText(box(cx, cy, r)) {
          bubble = false; r = dotR; text = ""
          cx = x
          cy = anchor + dir * (dotStem + r)
        }
      }
      if !bubble {
        let b = box(x, cy, r)
        guard b.minY >= env.top - 0.001, b.maxY <= env.bottom + 0.001, clearOfText(b) else { continue }
      } else {
        bubbles += 1
      }
      placed[side].append((cx, cy, r))
      out.append(BigTradeBubble(
        index: c.b.index, t: c.b.t, up: c.up, usd: c.usd, x: x, anchorY: anchor,
        center: CGPoint(x: cx, y: cy), r: r, isBubble: bubble, text: text))
    }
    out.sort { $0.index != $1.index ? $0.index < $1.index : ($0.up && !$1.up) }
    return out
  }

  // MARK: 命中

  /// 只认泡：44 × 44 热区（泡比热区大就按泡的外框），几枚都中取圆心最近的那枚。
  public static func hit(_ p: CGPoint, in items: [BigTradeBubble]) -> BigTradeBubble? {
    var best: (BigTradeBubble, CGFloat)?
    for b in items where b.isBubble {
      let half = max(hitSize / 2, b.r)
      guard abs(p.x - b.center.x) <= half, abs(p.y - b.center.y) <= half else { continue }
      let d = hypot(p.x - b.center.x, p.y - b.center.y)
      if best == nil || d < best!.1 { best = (b, d) }
    }
    return best?.0
  }

  // MARK: 读屏

  /// 「10-08 12:30 向上 1.2M」（用词从三端共用的 terms.json 来）。`amount` = 金额全写（带单位）。
  public static func accessibilityLabel(_ b: BigTradeBubble, time: String, amount: String) -> String {
    BigTradeTerm.signA11y.fill(["t": time, "side": (b.up ? BigTradeTerm.up : .down).text, "v": amount])
  }
}

/// 两级金额线（已垫过绝对下限）：到 `dot` 画点，到 `bubble` 画泡。
public struct BigTradeTiers: Equatable, Sendable {
  public var dot: Double
  public var bubble: Double
  public init(dot: Double, bubble: Double) {
    self.dot = dot
    self.bubble = bubble
  }
}

/// 一根 K 线进摆放：横坐标、最高 / 最低价的 y、这根向上（大买 + 空单爆仓）/ 向下（大卖 + 多单爆仓）的金额。
public struct BigTradeBubbleInput: Equatable, Sendable {
  public var index: Int
  public var t: Int64
  public var x: CGFloat
  public var hiY: CGFloat
  public var loY: CGFloat
  public var up: Double
  public var down: Double
  public init(index: Int, t: Int64, x: CGFloat, hiY: CGFloat, loY: CGFloat, up: Double, down: Double) {
    self.index = index
    self.t = t
    self.x = x
    self.hiY = hiY
    self.loY = loY
    self.up = up
    self.down = down
  }
}

/// 摆放的环境：门槛、一根宽、能落的竖直范围（图例那一带以下、主图下沿以上）、主图宽（价格轴左沿）、
/// 要让开的文字框（画线文字）、量字宽、泡上的字。
public struct BigTradeBubbleEnv {
  public var tiers: BigTradeTiers
  public var spacing: CGFloat
  public var top: CGFloat
  public var bottom: CGFloat
  public var plotW: CGFloat
  public var avoid: [CGRect]
  public var measure: (String) -> CGFloat
  public var text: (Double) -> String
  public init(
    tiers: BigTradeTiers, spacing: CGFloat, top: CGFloat, bottom: CGFloat, plotW: CGFloat, avoid: [CGRect] = [],
    measure: @escaping (String) -> CGFloat, text: @escaping (Double) -> String = BigTradeBubbles.bubbleText
  ) {
    self.tiers = tiers
    self.spacing = spacing
    self.top = top
    self.bottom = bottom
    self.plotW = plotW
    self.avoid = avoid
    self.measure = measure
    self.text = text
  }
}

/// 摆好的一枚：带字的泡，或不带字的小圆点。
public struct BigTradeBubble: Equatable, Sendable {
  public var index: Int
  public var t: Int64
  /// 向上（挂最高价之上、涨色）还是向下（挂最低价之下、跌色）。
  public var up: Bool
  public var usd: Double
  /// 这根的横坐标（柄的横坐标；泡贴主图左右沿时圆心往里收，不一定等于它）。
  public var x: CGFloat
  /// 锚点：向上是最高价的 y，向下是最低价的 y（柄从这里起）。
  public var anchorY: CGFloat
  public var center: CGPoint
  public var r: CGFloat
  /// 带字的泡（可点、进读屏）还是小圆点。
  public var isBubble: Bool
  /// 泡上的字（点为空）。
  public var text: String

  /// 圆的外框。
  public var bounds: CGRect { CGRect(x: center.x - r, y: center.y - r, width: 2 * r, height: 2 * r) }

  /// 柄：从锚点到泡的近边（只有泡画）。
  /// 泡贴边往里收过时圆心不在这根正上 / 下方，柄仍竖直、接到这根横坐标处的圆周。
  public var stem: (from: CGPoint, to: CGPoint) {
    let dx = x - center.x
    let h = (max(0, r * r - dx * dx)).squareRoot()
    return (CGPoint(x: x, y: anchorY), CGPoint(x: x, y: up ? center.y + h : center.y - h))
  }
}
