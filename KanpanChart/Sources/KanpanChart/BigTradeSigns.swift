import CoreGraphics
import Foundation

/// 图上「大单签」的纯函数：档位、摆放（翻面 / 退化）、命中（2026-10-08，设计源
/// `docs/原型-手机大单与爆仓-2026-10-08.html` §05–§12 与 `chartSVG`）。
///
/// 规则（和网页版 `Web/src/orderflow/bigTags.ts` 同一口径，手机按原型改了签的样子）：
/// - 档位按相对分布定：当前周期最近 `tierBars` 根里每根「大买 / 大卖里大的那一侧」的非零分布，
///   三档 = P85 / P95 / max(P99, 3 × P95)，每档再垫一道绝对下限（门槛 ÷ 5）。
/// - 一根只画一枚签：买卖里大的那一侧——买挂最高价上方、尖朝上；卖挂最低价下方、尖朝下（颜色与朝向翻面也不变）。
/// - 一档 = 直径 5 的圆点（方向色 70%）、离高 / 低点 3；二档 = 8 × 7 实心三角、离高 / 低点 4；
///   三档 = 三角 + 胶囊（高 16、左右各 5、11 号半粗白字、离三角尖 2）。密的周期（一根不到 3 pt）不出胶囊；
///   稀的周期（一根 ≥ 9 pt，日线这类）二档也出胶囊。
/// - 胶囊进了图例那一带（顶上 24 pt）/ 掉出主图 / 压到画线文字或别的签：先只把胶囊翻到 K 线另一侧，
///   再整枚翻过去，两侧都不行就退成三角（先本侧后另一侧），三角也放不下就不画——不往外挪。
/// - 命中：每枚签按 44 × 44 的热区算，几枚都中取离得最近的那枚。
///
/// 只聚合、门槛过滤、展示，不做判定。
public enum BigTradeSigns {
  /// 分布取多少根。
  public static let tierBars = 300
  public static let dotDiameter: CGFloat = 5
  public static let dotGap: CGFloat = 3
  public static let triangleWidth: CGFloat = 8
  public static let triangleHeight: CGFloat = 7
  public static let triangleGap: CGFloat = 4
  public static let capsuleHeight: CGFloat = 16
  public static let capsulePadding: CGFloat = 5
  public static let capsuleGap: CGFloat = 2
  /// 一根窄于这么多就一律不出胶囊（金额签会横跨十几根，看不出是哪根的）。
  public static let textMinSpacing: CGFloat = 3
  /// 一根宽到这么多（日线这类稀的周期）二档也出胶囊。
  public static let sparseCapsuleSpacing: CGFloat = 9
  /// 胶囊离主图左右边至少留这么多。
  public static let capsuleEdgeInset: CGFloat = 2
  /// 点击热区边长。
  public static let hitSize: CGFloat = 44

  // MARK: 档位

  /// 已升序排好的分位数，线性插值（同 numpy 默认）。
  public static func quantile(_ sorted: [Double], _ q: Double) -> Double {
    let n = sorted.count
    guard n > 0 else { return 0 }
    let pos = Double(n - 1) * min(1, max(0, q))
    let i = Int(pos.rounded(.down))
    let fr = pos - Double(i)
    return i + 1 < n ? sorted[i] + (sorted[i + 1] - sorted[i]) * fr : sorted[i]
  }

  /// 非零的每根金额 → 三档；`floor` = 绝对下限（门槛 ÷ 5）。一根有数的都没有给 nil。
  public static func tiers(_ values: [Double], floor: Double) -> BigTradeTiers? {
    let v = values.filter { $0 > 0 && $0.isFinite }.sorted()
    guard !v.isEmpty else { return nil }
    let f = floor > 0 && floor.isFinite ? floor : 0
    let p85 = quantile(v, 0.85), p95 = quantile(v, 0.95), p99 = quantile(v, 0.99)
    let t1 = max(p85, f)
    let t2 = max(p95, f, t1)
    let t3 = max(p99, 3 * p95, f, t2)
    return BigTradeTiers(t1: t1, t2: t2, t3: t3)
  }

  /// 0 = 不画；1 圆点；2 三角；3 三角 + 胶囊。
  public static func tier(of value: Double, _ k: BigTradeTiers?) -> Int {
    guard let k, value > 0 else { return 0 }
    if value >= k.t3 { return 3 }
    if value >= k.t2 { return 2 }
    if value >= k.t1 { return 1 }
    return 0
  }

  // MARK: 摆放

  /// 一屏的签：一根一枚（大的一侧）；金额大的先摆（先占位置）；返回摆得下的那些（按 `index` 升序）。
  public static func plan(_ bars: [BigTradeSignInput], env: BigTradeSignEnv) -> [BigTradeSign] {
    struct Cand { let b: BigTradeSignInput; let buy: Bool; let usd: Double; let tier: Int }
    var cands: [Cand] = []
    cands.reserveCapacity(bars.count)
    for b in bars {
      let buy = b.buy >= b.sell
      let usd = buy ? b.buy : b.sell
      let t = tier(of: usd, env.tiers)
      if t > 0 { cands.append(Cand(b: b, buy: buy, usd: usd, tier: t)) }
    }
    cands.sort { $0.usd != $1.usd ? $0.usd > $1.usd : $0.b.index > $1.b.index }

    var placedCaps: [CGRect] = []
    var placedMarks: [CGRect] = []
    var out: [BigTradeSign] = []
    out.reserveCapacity(cands.count)

    func insideV(_ r: CGRect) -> Bool { r.minY >= env.top - 0.001 && r.maxY <= env.bottom + 0.001 }
    func insideH(_ r: CGRect) -> Bool { r.minX >= -0.001 && r.maxX <= env.plotW + 0.001 }
    func clearOfText(_ r: CGRect) -> Bool { !env.avoid.contains { $0.intersects(r) } }
    func markOK(_ r: CGRect) -> Bool {
      insideV(r) && clearOfText(r) && !placedCaps.contains { $0.intersects(r) }
    }
    func capOK(_ r: CGRect) -> Bool {
      insideV(r) && insideH(r) && clearOfText(r)
        && !placedCaps.contains { $0.intersects(r) } && !placedMarks.contains { $0.intersects(r) }
    }

    for c in cands {
      let x = c.b.x
      let pref = c.buy  // 买默认在上
      var sign: BigTradeSign?
      let wantsCap: Bool = {
        if c.tier >= 3 { return env.spacing >= textMinSpacing }
        if c.tier == 2 { return env.spacing >= sparseCapsuleSpacing }
        return false
      }()
      if c.tier == 1 {
        for above in [pref, !pref] {
          let r = dotRect(x: x, bar: c.b, above: above)
          if markOK(r) { sign = make(c.b, c.buy, c.tier, c.usd, .dot, r, above, nil, env); break }
        }
      } else {
        if wantsCap {
          let text = env.text(c.usd)
          let w = (env.measure(text) + 2 * capsulePadding).rounded(.up)
          // 胶囊的候选：（三角在哪侧，胶囊在哪侧）
          let combos: [(Bool, Bool)] = [(pref, pref), (pref, !pref), (!pref, !pref)]
          for (triAbove, capAbove) in combos {
            let tri = triangleRect(x: x, bar: c.b, above: triAbove)
            guard markOK(tri) else { continue }
            guard let cap = capsuleRect(x: x, width: w, bar: c.b, tri: tri, triAbove: triAbove, above: capAbove, env: env),
                  capOK(cap), !cap.intersects(tri)
            else { continue }
            sign = make(c.b, c.buy, c.tier, c.usd, .triangle, tri, triAbove, (cap, text), env)
            break
          }
        }
        if sign == nil {
          for above in [pref, !pref] {
            let r = triangleRect(x: x, bar: c.b, above: above)
            if markOK(r) { sign = make(c.b, c.buy, c.tier, c.usd, .triangle, r, above, nil, env); break }
          }
        }
      }
      if let s = sign {
        out.append(s)
        placedMarks.append(s.markRect)
        if let cap = s.capsule { placedCaps.append(cap) }
      }
    }
    out.sort { $0.index < $1.index }
    return out
  }

  static func dotRect(x: CGFloat, bar: BigTradeSignInput, above: Bool) -> CGRect {
    let y = above ? bar.hiY - dotGap - dotDiameter : bar.loY + dotGap
    return CGRect(x: x - dotDiameter / 2, y: y, width: dotDiameter, height: dotDiameter)
  }

  static func triangleRect(x: CGFloat, bar: BigTradeSignInput, above: Bool) -> CGRect {
    let y = above ? bar.hiY - triangleGap - triangleHeight : bar.loY + triangleGap
    return CGRect(x: x - triangleWidth / 2, y: y, width: triangleWidth, height: triangleHeight)
  }

  /// 胶囊和三角同侧时贴在三角外沿（离尖 2）；三角在另一侧时胶囊照样离 K 线 4 + 7 + 2，留出三角的位置感。
  /// 胶囊横跨的那几根若比本根更高 / 更低，让开它们（`env.span`）。横向夹在主图里。
  static func capsuleRect(
    x: CGFloat, width w: CGFloat, bar: BigTradeSignInput, tri: CGRect, triAbove: Bool, above: Bool,
    env: BigTradeSignEnv
  ) -> CGRect? {
    let lo = capsuleEdgeInset + w / 2
    let hi = env.plotW - capsuleEdgeInset - w / 2
    guard hi >= lo else { return nil }
    let cx = min(max(x, lo), hi)
    let span = env.span?(cx - w / 2, cx + w / 2)
    let off = triangleGap + triangleHeight + capsuleGap
    if above {
      var bottom = (triAbove ? tri.minY : bar.hiY - off + capsuleGap) - capsuleGap
      if let s = span { bottom = min(bottom, s.hiY - capsuleGap) }
      return CGRect(x: cx - w / 2, y: bottom - capsuleHeight, width: w, height: capsuleHeight)
    } else {
      var top = (triAbove ? bar.loY + off - capsuleGap : tri.maxY) + capsuleGap
      if let s = span { top = max(top, s.loY + capsuleGap) }
      return CGRect(x: cx - w / 2, y: top, width: w, height: capsuleHeight)
    }
  }

  private static func make(
    _ b: BigTradeSignInput, _ buy: Bool, _ tier: Int, _ usd: Double, _ mark: BigTradeSign.Mark, _ r: CGRect,
    _ above: Bool, _ cap: (CGRect, String)?, _ env: BigTradeSignEnv
  ) -> BigTradeSign {
    BigTradeSign(
      index: b.index, t: b.t, buy: buy, tier: tier, usd: usd, x: b.x, mark: mark, markRect: r, markAbove: above,
      capsule: cap?.0, text: cap?.1 ?? env.text(usd))
  }

  // MARK: 命中

  /// 44 × 44 热区（以记号中心为中心；胶囊则整块再各向外扩到 44 高），几枚都中取离得最近的那枚。
  public static func hit(_ p: CGPoint, in signs: [BigTradeSign]) -> BigTradeSign? {
    var best: (BigTradeSign, CGFloat)?
    for s in signs {
      let d = s.distance(to: p)
      guard d.hit else { continue }
      if best == nil || d.dist < best!.1 { best = (s, d.dist) }
    }
    return best?.0
  }

  // MARK: 读屏

  /// 「买方大单 1.2M，12:30 这根」。
  public static func accessibilityLabel(_ s: BigTradeSign, time: String) -> String {
    "\(s.buy ? "买方" : "卖方")大单 \(s.text)，\(time) 这根"
  }
}

/// 三档的金额线（已垫过绝对下限）。
public struct BigTradeTiers: Equatable, Sendable {
  public var t1: Double
  public var t2: Double
  public var t3: Double
  public init(t1: Double, t2: Double, t3: Double) {
    self.t1 = t1
    self.t2 = t2
    self.t3 = t3
  }
}

/// 一根 K 线进摆放：横坐标、最高 / 最低价的 y、这根的大买 / 大卖金额。
public struct BigTradeSignInput: Equatable, Sendable {
  public var index: Int
  public var t: Int64
  public var x: CGFloat
  public var hiY: CGFloat
  public var loY: CGFloat
  public var buy: Double
  public var sell: Double
  public init(index: Int, t: Int64, x: CGFloat, hiY: CGFloat, loY: CGFloat, buy: Double, sell: Double) {
    self.index = index
    self.t = t
    self.x = x
    self.hiY = hiY
    self.loY = loY
    self.buy = buy
    self.sell = sell
  }
}

/// 摆放的环境：档位、一根宽、签能落的竖直范围（图例那一带以下、主图下沿以上）、主图宽（价格轴左沿）、
/// 要让开的文字框（图例、画线文字）、量字宽、金额文案、胶囊横跨那几根的最高 / 最低（可选）。
public struct BigTradeSignEnv {
  public var tiers: BigTradeTiers
  public var spacing: CGFloat
  public var top: CGFloat
  public var bottom: CGFloat
  public var plotW: CGFloat
  public var avoid: [CGRect]
  public var measure: (String) -> CGFloat
  public var text: (Double) -> String
  public var span: ((CGFloat, CGFloat) -> (hiY: CGFloat, loY: CGFloat)?)?
  public init(
    tiers: BigTradeTiers, spacing: CGFloat, top: CGFloat, bottom: CGFloat, plotW: CGFloat, avoid: [CGRect] = [],
    measure: @escaping (String) -> CGFloat, text: @escaping (Double) -> String,
    span: ((CGFloat, CGFloat) -> (hiY: CGFloat, loY: CGFloat)?)? = nil
  ) {
    self.tiers = tiers
    self.spacing = spacing
    self.top = top
    self.bottom = bottom
    self.plotW = plotW
    self.avoid = avoid
    self.measure = measure
    self.text = text
    self.span = span
  }
}

/// 摆好的一枚签。
public struct BigTradeSign: Equatable, Sendable {
  public enum Mark: Sendable { case dot, triangle }
  public var index: Int
  public var t: Int64
  /// 买方（涨色、尖朝上）还是卖方（跌色、尖朝下）——翻面也不变。
  public var buy: Bool
  public var tier: Int
  public var usd: Double
  /// 这根的横坐标。
  public var x: CGFloat
  public var mark: Mark
  /// 圆点 / 三角的外框。
  public var markRect: CGRect
  /// 记号落在最高价上方（true）还是最低价下方。
  public var markAbove: Bool
  public var capsule: CGRect?
  /// 金额文案（胶囊上写的；没胶囊也给，读屏用）。
  public var text: String

  public var markCenter: CGPoint { CGPoint(x: markRect.midX, y: markRect.midY) }

  /// 三角的三个顶点（买尖朝上、卖尖朝下）。
  public var trianglePoints: [CGPoint] {
    let r = markRect
    return buy
      ? [CGPoint(x: r.minX, y: r.maxY), CGPoint(x: r.maxX, y: r.maxY), CGPoint(x: r.midX, y: r.minY)]
      : [CGPoint(x: r.minX, y: r.minY), CGPoint(x: r.maxX, y: r.minY), CGPoint(x: r.midX, y: r.maxY)]
  }

  /// 圆环动效的圆心（三角的形心附近 / 圆点中心）。
  public var pulseCenter: CGPoint { markCenter }

  /// 整枚签的外框（记号 ∪ 胶囊）。
  public var bounds: CGRect { capsule.map { $0.union(markRect) } ?? markRect }

  func distance(to p: CGPoint) -> (hit: Bool, dist: CGFloat) {
    let half = BigTradeSigns.hitSize / 2
    let c = markCenter
    var best = hypot(p.x - c.x, p.y - c.y)
    var hit = abs(p.x - c.x) <= half && abs(p.y - c.y) <= half
    if let cap = capsule {
      let padY = max(0, (BigTradeSigns.hitSize - cap.height) / 2)
      let zone = cap.insetBy(dx: -max(0, (BigTradeSigns.hitSize - cap.width) / 2), dy: -padY)
      if zone.contains(p) { hit = true }
      let dx = max(cap.minX - p.x, 0, p.x - cap.maxX)
      let dy = max(cap.minY - p.y, 0, p.y - cap.maxY)
      best = min(best, hypot(dx, dy))
    }
    return (hit, best)
  }
}
