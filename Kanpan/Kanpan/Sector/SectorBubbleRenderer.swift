import CoreGraphics
import Foundation
import KanpanCore
import SwiftUI
import UIKit

// MARK: - 色彩：全部从皮肤的涨跌两色现算

/// HSL 三元组，口径和原型的 `hex2hsl` 一致（h 度、s/l 百分比）。
///
/// 这一页一个字面色值都不许写：球胎、环光、辉光、落影、数字，全部从
/// `PanelTheme.chart.up` / `.down` 这两支颜色推出来，三套皮肤 × 深浅自动一致。
struct GlazeHSL: Equatable, Sendable {
  var h: Double
  var s: Double
  var l: Double

  init(h: Double, s: Double, l: Double) { self.h = h; self.s = s; self.l = l }

  init(_ hex: Hex) {
    let (r, g, b, _) = hex.rgba
    let mx = max(r, max(g, b)), mn = min(r, min(g, b))
    let l = (mx + mn) / 2
    var h = 0.0, s = 0.0
    if mx != mn {
      let d = mx - mn
      s = l > 0.5 ? d / (2 - mx - mn) : d / (mx + mn)
      if mx == r { h = (g - b) / d + (g < b ? 6 : 0) } else if mx == g { h = (b - r) / d + 2 } else { h = (r - g) / d + 4 }
      h *= 60
    }
    self.init(h: h, s: s * 100, l: l * 100)
  }
}

/// 原型里的 `H(h,s,l,a)`：HSL → 颜色。s/l 按 0…100 夹紧。
enum Glaze {
  static func rgb(_ h: Double, _ s: Double, _ l: Double) -> (Double, Double, Double) {
    let sat = min(max(s, 0), 100) / 100
    let lig = min(max(l, 0), 100) / 100
    let c = (1 - abs(2 * lig - 1)) * sat
    var hh = h.truncatingRemainder(dividingBy: 360)
    if hh < 0 { hh += 360 }
    hh /= 60
    let x = c * (1 - abs(hh.truncatingRemainder(dividingBy: 2) - 1))
    let m = lig - c / 2
    let (r, g, b): (Double, Double, Double) = switch hh {
    case ..<1: (c, x, 0)
    case ..<2: (x, c, 0)
    case ..<3: (0, c, x)
    case ..<4: (0, x, c)
    case ..<5: (x, 0, c)
    default: (c, 0, x)
    }
    return (r + m, g + m, b + m)
  }

  static func color(_ h: Double, _ s: Double, _ l: Double, _ a: Double = 1) -> Color {
    let (r, g, b) = rgb(h, s, l)
    return Color(.sRGB, red: r, green: g, blue: b, opacity: a)
  }

  static func cgColor(_ h: Double, _ s: Double, _ l: Double, _ a: Double = 1) -> CGColor {
    let (r, g, b) = rgb(h, s, l)
    return CGColor(srgbRed: r, green: g, blue: b, alpha: a)
  }

  /// 中性黑白，对应原型里的 `rgba(0,0,0,x)` / `rgba(255,255,255,x)`。
  static func ink(_ a: Double) -> CGColor { CGColor(srgbRed: 0, green: 0, blue: 0, alpha: a) }
  static func paper(_ a: Double) -> CGColor { CGColor(srgbRed: 1, green: 1, blue: 1, alpha: a) }

  static let space = CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB()

  static func ramp(_ stops: [(CGColor, CGFloat)]) -> CGGradient? {
    CGGradient(colorsSpace: space,
               colors: stops.map(\.0) as CFArray,
               locations: stops.map(\.1))
  }

  static func clamp(_ v: Double, _ lo: Double, _ hi: Double) -> Double { v < lo ? lo : (v > hi ? hi : v) }
  static func lerp(_ a: Double, _ b: Double, _ t: Double) -> Double { a + (b - a) * t }
}

// MARK: - 球面上的字

/// 球面上那两行字的排版结果。
///
/// **门槛按弦宽算，不按半径**：球是圆的，越靠上下两极可用宽度收得越快。
/// 第 dy 行、宽 w 的一行字，它两端离球心是 `hypot(w/2+1, |dy|+行高)`，
/// 这个距离必须落在「扣掉环光和两点余量」的安全半径以内。拿半径当阈值的写法，
/// 会在球只小一点点的时候把字甩到环光上。
///
/// 三档降级：记号 + 名称 + 涨跌幅 → 记号 + 涨跌幅 → 只剩记号。
struct SectorBubbleLabel: Equatable, Sendable {
  var name: String?
  var nameSize: CGFloat = 0
  /// 相对半径的纵向偏移，画的时候乘当前半径。
  var nameDY: Double = 0
  var pct: String?
  var pctSize: CGFloat = 0
  var pctDY: Double = 0
  var iconDY: Double = 0

  static func fmtPct(_ v: Double) -> String {
    (v >= 0 ? "+" : "") + String(format: "%.2f", v) + "%"
  }

  /// 量一次存起来。放在重排里算，不放在每帧算：一来省掉逐帧的字形测量，
  /// 二来 ±1.2% 的呼吸不会把某颗球在门槛上来回推，字就不会一帧有一帧没有。
  static func make(id: String, fallbackName: String, pct: Double,
                   radius r: Double, rimWidth: Double) -> SectorBubbleLabel {
    var label = SectorBubbleLabel()
    guard r > 1 else { return label }
    let text = SectorShortName.of(id) ?? fallbackName
    let pctText = fmtPct(pct)
    let safe = max(0, r - rimWidth * 1.15 - 2)
    let d = r * 2
    func fits(_ w: Double, _ dy: Double, _ hh: Double) -> Bool {
      hypot(w * 0.5 + 1, abs(dy) + hh) <= safe
    }

    if r >= 30 {
      var nameFs = Glaze.clamp(r * 0.235, 9.5, 14.5)
      while measure(text, nameFs, .medium) > d * 0.78, nameFs > 9.5 { nameFs -= 0.5 }
      let nw = measure(text, nameFs, .medium)
      let pf = Glaze.clamp(r * 0.245, 10, 16)
      let pw = measure(pctText, pf, .semibold, mono: true)
      let ny = r * 0.20
      let py = ny + pf * 1.12
      if fits(nw, ny, nameFs * 0.55), fits(pw, py, pf * 0.55) {
        label.name = text
        label.nameSize = nameFs
        label.nameDY = ny / r
        label.pct = pctText
        label.pctSize = pf
        label.pctDY = py / r
        label.iconDY = -0.30
        return label
      }
    }

    var pctFs = Glaze.clamp(r * 0.30, 9.5, 16)
    let pctDY = r * 0.30
    while !fits(measure(pctText, pctFs, .semibold, mono: true), pctDY, pctFs * 0.55), pctFs > 9.5 {
      pctFs -= 0.5
    }
    if fits(measure(pctText, pctFs, .semibold, mono: true), pctDY, pctFs * 0.55) {
      label.pct = pctText
      label.pctSize = pctFs
      label.pctDY = 0.30
      label.iconDY = -0.24
    } else {
      label.iconDY = 0
    }
    return label
  }

  private static func measure(_ text: String, _ size: Double,
                              _ weight: UIFont.Weight, mono: Bool = false) -> Double {
    let font = mono
      ? UIFont.monospacedDigitSystemFont(ofSize: size, weight: weight)
      : UIFont.systemFont(ofSize: size, weight: weight)
    return Double((text as NSString).size(withAttributes: [.font: font]).width)
  }
}

/// 球面上用的板块短名。列表页用全称，球上只放得下这么多字。
enum SectorShortName {
  static func of(_ id: String) -> String? { table[id] }

  private static let table: [String: String] = [
    "l1": "公链", "ai": "AI", "meme": "Meme", "sol-eco": "Solana", "defi-blue": "DeFi 蓝筹",
    "gamefi": "链游", "l2": "Layer-2", "depin": "DePIN", "nft-social": "NFT", "stable-yield": "稳定收益",
    "btc-eco": "BTC 生态", "storage-data": "存储", "zk": "ZK", "rwa": "RWA", "oracle-bridge": "预言机",
    "payment": "支付", "perp-dex": "永续 DEX", "pow": "PoW", "privacy": "隐私", "eth-eco": "ETH 生态",
    "metaverse": "元宇宙", "meme-cn": "华语 Meme", "fan-token": "粉丝代币", "desci": "DeSci",
    "tag-infrastructure": "基础设施", "tag-alpha": "币安 Alpha", "tag-defi": "DeFi 其他", "misc": "其他",
    "gpu": "算力芯片", "mem": "存储", "equip": "设备材料", "optic": "光通信", "hyper": "云厂商",
    "neo": "算力租赁", "server": "服务器", "edge": "端侧 AI", "robot": "机器人", "app": "模型应用",
  ]
}

// MARK: - 一颗球的配方

/// 一颗釉珠的「配方」。
///
/// 颜色只跟皮肤、涨跌两色和 |涨跌幅| 有关，跟位置和时间都无关，所以在重排／换行情时
/// 算一次存下来，逐帧只拿它去铺。否则 27 颗球 × 7 层渐变 = 每帧近两百个 `CGGradient`。
///
/// 几何量一律存成「相对半径的比例」，呼吸时直接乘当前半径。
struct SectorBubblePaint {
  var rimWidthRatio = 0.0
  var glowCapRatio = 1.0
  var poolInnerRatio = 0.0

  var shadow: CGGradient?
  var glow: CGGradient?
  var body: CGGradient?
  var env: CGGradient?
  var bounce: CGGradient?
  var terminator: CGGradient?
  var pool: CGGradient?

  var rim = Gradient(colors: [])
  var sheen = Color.clear
  var outline = Color.clear
  var nameColor = Color.white
  var pctColor = Color.white

  var label = SectorBubbleLabel()
  var art: SectorIconArt?
}

// MARK: - 釉珠

/// 釉珠本体的绘制：近黑的深釉球胎 + 球缘一圈随方位变亮的环光 + 上半一枚彩色实心记号
/// + 下面白色的名称与涨跌幅两行。逐行移植自原型 `app.js` 的 `drawBubble()`。
///
/// **球身只有强端／弱端两个色相，讲的是「在哪一头」，不是涨跌的正负**；
/// 数字自己按正负着色。陪衬球用完全相同的材质、光学和质量标准，不做任何弱化。
///
/// 深色档才放外溢辉光，而且半径硬封顶紧贴球缘；浅色档换成
/// 「被左上强光打亮的实体 + 有方向的接触投影 + 偏心的明暗交界」，靠明暗立体而不是靠亮。
struct SectorBubbleRenderer {
  let theme: PanelTheme
  let knobs: SectorFieldKnobs

  private var dark: Bool { theme.dark }

  // MARK: 配方

  func paint(for bubble: SectorBubble) -> SectorBubblePaint {
    let rise = GlazeHSL(theme.chart.up)
    let fall = GlazeHSL(theme.chart.down)
    let base = bubble.upSide ? rise : fall
    let h = base.h
    let s = Glaze.clamp(base.s * 1.02, 30, 92)
    // 同样的饱和度，红在低明度下比青绿显色得多。球胎的着色按色相压一下，
    // 两头才读成同一种黑釉，而不是「黑珠 vs 酱色珠」。
    let hr = (h.truncatingRemainder(dividingBy: 360) + 360).truncatingRemainder(dividingBy: 360)
    let warm = max(0, cos((hr - 8) * .pi / 180))
    let bK = 1 - 0.36 * warm

    let n = bubble.norm
    let depth = knobs.depth / 100
    let shadowK = knobs.shadow / 100
    let rimL = knobs.rimL / 100
    var p = SectorBubblePaint()

    p.rimWidthRatio = (0.028 + knobs.rim / 100 * 0.060) * (0.78 + 0.34 * n)
    p.poolInnerRatio = max(0, 1 - p.rimWidthRatio * 3.4)
    p.glowCapRatio = 1 + 0.05 + knobs.glow / 100 * 0.16

    // 1 · 接触投影
    let sa = (dark ? 0.52 : 0.50) * shadowK * (0.7 + 0.3 * n)
    p.shadow = Glaze.ramp([(Glaze.ink(sa), 0),
                           (Glaze.ink(sa * (dark ? 0.42 : 0.50)), 0.55),
                           (Glaze.ink(0), 1)])

    // 2 · 外溢辉光：只有深色档有
    if dark, knobs.glow > 0 {
      let ga = knobs.glow / 100 * 0.40 * (0.45 + 0.55 * n)
      p.glow = Glaze.ramp([(Glaze.cgColor(h, s, 58, ga), 0),
                           (Glaze.cgColor(h, s, 54, ga * 0.38), 0.45),
                           (Glaze.cgColor(h, s, 50, 0), 1)])
    }

    // 3 · 釉身
    if dark {
      p.body = Glaze.ramp([
        (Glaze.cgColor(h, s * 0.52 * bK, Glaze.lerp(9, 17, depth) * (0.8 + 0.4 * n)), 0),
        (Glaze.cgColor(h, s * 0.46 * bK, Glaze.lerp(6, 11, depth)), 0.52),
        (Glaze.cgColor(h, s * 0.40 * bK, Glaze.lerp(3.5, 6, depth)), 1),
      ])
    } else {
      p.body = Glaze.ramp([
        (Glaze.cgColor(h, s * 0.58 * bK, Glaze.lerp(19, 26, depth) * (0.85 + 0.3 * n)), 0),
        (Glaze.cgColor(h, s * 0.52 * bK, Glaze.lerp(13, 18, depth)), 0.52),
        (Glaze.cgColor(h, s * 0.46 * bK, Glaze.lerp(8, 12, depth)), 1),
      ])
    }

    // 3b · 环境反射带
    p.env = Glaze.ramp([(Glaze.paper(dark ? 0.085 : 0.095), 0),
                        (Glaze.paper(dark ? 0.030 : 0.05), 0.6),
                        (Glaze.paper(0), 1)])

    // 3c · 底部回弹
    p.bounce = Glaze.ramp([(Glaze.cgColor(h, s, dark ? 46 : 52, dark ? 0.16 : 0.18), 0),
                           (Glaze.cgColor(h, s, dark ? 46 : 52, 0), 1)])

    // 3c2 · 明暗交界
    let ta = dark ? 0.26 : 0.46
    p.terminator = Glaze.ramp([(Glaze.ink(0), 0),
                               (Glaze.ink(ta * 0.26), 0.52),
                               (Glaze.ink(ta), 1)])

    // 3d · 积釉
    p.pool = Glaze.ramp([(Glaze.ink(0), 0), (Glaze.ink(dark ? 0.62 : 0.55), 1)])

    // 4 · 环光：一条随方位变亮的高光带，左上最亮，右下有一处弱回弹
    let hi = dark ? Glaze.lerp(50, 78, rimL) * (0.70 + 0.40 * n)
                  : Glaze.lerp(48, 68, rimL) * (0.76 + 0.32 * n)
    let lo = dark ? Glaze.lerp(7, 13, rimL) * (0.55 + 0.55 * n)
                  : Glaze.lerp(11, 18, rimL) * (0.6 + 0.5 * n)
    let sat = dark ? Glaze.clamp(s * 1.05, 0, 95) : Glaze.clamp(s * 1.0, 0, 92)
    p.rim = Gradient(stops: [
      .init(color: Glaze.color(h, sat * 0.9, hi), location: 0.00),
      .init(color: Glaze.color(h, sat, hi * 0.82), location: 0.07),
      .init(color: Glaze.color(h, sat, Glaze.lerp(lo, hi, 0.30)), location: 0.22),
      .init(color: Glaze.color(h, sat, lo), location: 0.42),
      .init(color: Glaze.color(h, sat, Glaze.lerp(lo, hi, 0.38)), location: 0.58),
      .init(color: Glaze.color(h, sat, lo * 1.05), location: 0.72),
      .init(color: Glaze.color(h, sat, Glaze.lerp(lo, hi, 0.55)), location: 0.90),
      .init(color: Glaze.color(h, sat * 0.9, hi), location: 1.00),
    ])

    // 4b · 内缘镜面丝 / 5 · 最外一圈暗轮廓
    p.sheen = Color.white.opacity((dark ? 0.22 : 0.20) * rimL * (0.45 + 0.55 * n))
    p.outline = Color.black.opacity(dark ? 0.55 : 0.40)

    // 6 · 记号与两行字
    p.nameColor = Color.white.opacity(dark ? 0.94 : 0.97)
    let signed = bubble.pct >= 0 ? rise : fall
    p.pctColor = Glaze.color(signed.h, Glaze.clamp(signed.s * 1.1, 0, 95), dark ? 76 : 70)
    p.art = SectorIcons.art(bubble.pick.stat.id)
    p.label = SectorBubbleLabel.make(id: bubble.pick.stat.id,
                                     fallbackName: bubble.pick.stat.name,
                                     pct: bubble.pct,
                                     radius: Double(bubble.radius),
                                     rimWidth: Double(bubble.radius) * p.rimWidthRatio)
    return p
  }

  // MARK: 画一颗

  /// - Parameters:
  ///   - center: 这一帧的圆心（静止位置 + 漂移）。
  ///   - radius: 这一帧的半径（基准半径 × 呼吸）。
  ///   - time: 毫秒，和原型的 `performance.now()` 同一把钟。
  func draw(_ bubble: SectorBubble, paint p: SectorBubblePaint,
            center: CGPoint, radius: CGFloat, time: Double,
            into context: inout GraphicsContext) {
    let r = Double(radius)
    guard r > 0.5 else { return }
    let cx = Double(center.x), cy = Double(center.y)
    let dark = self.dark
    let rimW = r * p.rimWidthRatio
    // 极慢的环光游走。原型里 `(S.spd/60||1)`：速度拧到 0 时退回 1。
    let sheen = time * 0.00013 * (knobs.spd == 0 ? 1 : knobs.spd / 60)
    let peak = -2.36 + sin(time * 0.00021 + bubble.phase) * 0.10 + sheen

    // 1 ~ 3d 全部走 CoreGraphics：球胎和明暗交界是**双圆心**径向渐变
    // （起点圆偏在左上、终点圆偏在右下），SwiftUI 的 `Shading.radialGradient`
    // 只有一个圆心，表达不了，只能落到 CGContext 上。
    // 每颗球单开一次 `withCGContext` 而不是整场合并成一次，是为了保住层序：
    // pad 可以拧到 0，小球会压在大球的环光上，合并画会把这层关系弄反。
    context.withCGContext { cg in
      drawGround(cg, r: r, cx: cx, cy: cy, dark: dark, paint: p)
      drawGlaze(cg, r: r, cx: cx, cy: cy, dark: dark, paint: p)
    }

    // 4 · 环光。锥形渐变留在 SwiftUI 这边画：`Shading.conicGradient` 的角度语义
    // 和 Canvas2D 的 `createConicGradient` 对得上，不用去赌 CGContext 在 y 轴朝下时的方向。
    let rr = r - rimW / 2 - 0.4
    if rr > 0.2 {
      context.stroke(Path(ellipseIn: CGRect(x: cx - rr, y: cy - rr, width: rr * 2, height: rr * 2)),
                     with: .conicGradient(p.rim, center: center, angle: .radians(peak)),
                     lineWidth: rimW)

      // 4b · 内缘镜面丝：釉面被点亮的那一道，只在迎光的一侧
      let sheenR = rr - rimW * 0.28
      if sheenR > 0.2 {
        var arc = Path()
        arc.addArc(center: center, radius: sheenR,
                   startAngle: .radians(peak - 0.70), endAngle: .radians(peak + 0.62),
                   clockwise: false)
        context.stroke(arc, with: .color(p.sheen), lineWidth: max(0.6, rimW * 0.20))
      }
    }

    // 5 · 最外一圈暗轮廓：任何皮肤下球都有明确的边
    let outlineR = r - 0.2
    context.stroke(Path(ellipseIn: CGRect(x: cx - outlineR, y: cy - outlineR,
                                          width: outlineR * 2, height: outlineR * 2)),
                   with: .color(p.outline), lineWidth: max(0.6, r * 0.012))

    // 6 · 板块记号 + 文字
    drawFace(&context, paint: p, cx: cx, cy: cy, r: r)
  }

  // MARK: 球下与球身

  /// 1 · 接触投影 + 2 · 外溢辉光，都在球外面。
  private func drawGround(_ cg: CGContext, r: Double, cx: Double, cy: Double,
                          dark: Bool, paint p: SectorBubblePaint) {
    // 浅色底上没有辉光可以借力，球全靠这道影子坐下去：更沉、更紧，
    // 并且顺着光（左上进来）往右下偏一点，方向感是立体感的一半。
    if let shadow = p.shadow {
      let shR = r * (dark ? 1.12 : 1.04)
      cg.saveGState()
      cg.translateBy(x: cx + (dark ? 0 : r * 0.07), y: cy + r * (dark ? 0.30 : 0.34))
      cg.scaleBy(x: 1, y: dark ? 0.34 : 0.30)
      cg.addEllipse(in: CGRect(x: -shR, y: -shR, width: shR * 2, height: shR * 2))
      cg.clip()
      cg.drawRadialGradient(shadow, startCenter: .zero, startRadius: r * 0.15,
                            endCenter: .zero, endRadius: shR,
                            options: .drawsBeforeStartLocation)
      cg.restoreGState()
    }

    // 半径硬封顶、紧贴球缘：宁可亮而锐，也不要大范围的低频雾——雾会吃掉旁边的球和字。
    if dark, let glow = p.glow {
      let cap = r * p.glowCapRatio
      let c = CGPoint(x: cx, y: cy)
      cg.saveGState()
      cg.addEllipse(in: CGRect(x: cx - cap, y: cy - cap, width: cap * 2, height: cap * 2))
      cg.clip()
      cg.drawRadialGradient(glow, startCenter: c, startRadius: r * 0.94,
                            endCenter: c, endRadius: cap,
                            options: .drawsBeforeStartLocation)
      cg.restoreGState()
    }
  }

  /// 3 ~ 3d：釉身、环境反射带、底部回弹、明暗交界、积釉，全部关在球里。
  private func drawGlaze(_ cg: CGContext, r: Double, cx: Double, cy: Double,
                         dark: Bool, paint p: SectorBubblePaint) {
    let c = CGPoint(x: cx, y: cy)
    cg.saveGState()
    cg.addEllipse(in: CGRect(x: cx - r, y: cy - r, width: r * 2, height: r * 2))
    cg.clip()

    // 3 · 近黑的深釉：光从左上进来，只把中心稍稍抬亮一点点
    if let body = p.body {
      let fx = dark ? 0.30 : 0.32, fy = dark ? 0.36 : 0.38
      cg.drawRadialGradient(body,
                            startCenter: CGPoint(x: cx - r * fx, y: cy - r * fy), startRadius: r * 0.05,
                            endCenter: c, endRadius: r * (dark ? 1.04 : 1.05),
                            options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])
    }

    // 3b · 上三分之一一道很宽很淡的横向反光，低对比
    if let env = p.env {
      cg.saveGState()
      cg.translateBy(x: cx, y: cy - r * 0.44)
      cg.scaleBy(x: 1, y: 0.30)
      cg.drawRadialGradient(env, startCenter: .zero, startRadius: 0,
                            endCenter: .zero, endRadius: r * 0.95, options: [])
      cg.restoreGState()
    }

    // 3c · 环境从下方补一点点冷光，球才不是贴纸
    if let bounce = p.bounce {
      cg.saveGState()
      cg.translateBy(x: cx, y: cy + r * 0.62)
      cg.scaleBy(x: 1, y: 0.26)
      cg.drawRadialGradient(bounce, startCenter: .zero, startRadius: 0,
                            endCenter: .zero, endRadius: r * 0.7, options: [])
      cg.restoreGState()
    }

    // 3c2 · 明暗交界：浅色档没有自发光可用，立体全靠这一道方向性的暗面，
    // 而不是在球面中上部点一块亮椭圆。
    if let terminator = p.terminator {
      cg.drawRadialGradient(terminator,
                            startCenter: CGPoint(x: cx - r * 0.46, y: cy - r * 0.52), startRadius: r * 0.10,
                            endCenter: CGPoint(x: cx + r * 0.30, y: cy + r * 0.34), endRadius: r * 1.34,
                            options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])
    }

    // 3d · 积釉：靠边一圈比球心更沉，环光才有可以坐的槽
    if let pool = p.pool {
      cg.drawRadialGradient(pool, startCenter: c, startRadius: r * p.poolInnerRatio,
                            endCenter: c, endRadius: r,
                            options: .drawsBeforeStartLocation)
    }

    cg.restoreGState()
  }

  // MARK: 球面

  private func drawFace(_ context: inout GraphicsContext, paint p: SectorBubblePaint,
                        cx: Double, cy: Double, r: Double) {
    let iconD = 2 * r * (knobs.icon / 100)
    if let art = p.art, iconD > 1 {
      let iconY = cy + r * p.label.iconDY
      let rect = CGRect(x: cx - iconD / 2, y: iconY - iconD / 2, width: iconD, height: iconD)
      SectorMarkDraw.draw(art, in: rect, context: &context, theme: theme)
    }

    if let name = p.label.name {
      var text = context.resolve(Text(name).font(.system(size: p.label.nameSize, weight: .medium)))
      text.shading = .color(p.nameColor)
      context.drawLayer { layer in
        layer.addFilter(.shadow(color: .black.opacity(0.45), radius: 3, x: 0, y: 0.5))
        layer.draw(text, at: CGPoint(x: cx, y: cy + r * p.label.nameDY), anchor: .center)
      }
    }

    if let pct = p.label.pct {
      // 数字按正负着色，和球在哪一头无关：最弱的那一头照样可能是 +2.50%
      var text = context.resolve(
        Text(pct).font(.system(size: p.label.pctSize, weight: .semibold).monospacedDigit()))
      text.shading = .color(p.pctColor)
      context.drawLayer { layer in
        layer.addFilter(.shadow(color: .black.opacity(0.5), radius: 3, x: 0, y: 0))
        layer.draw(text, at: CGPoint(x: cx, y: cy + r * p.label.pctDY), anchor: .center)
      }
    }
  }
}
