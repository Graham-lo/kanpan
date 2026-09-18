import CoreGraphics
import Foundation
import KanpanCore

/// 场上的一颗釉珠。
///
/// 只有两个判断通道：**大小 = |涨跌幅|**（半径 ∝ √|pct|，全视图一把尺子），
/// **位置 = 强端 / 弱端**。`upSide` 说的是「在哪一头」，不是涨跌的正负——
/// 数字自己带符号，最弱的那颗照样可能写 `+2.50%`。
struct SectorBubble: Identifiable, Equatable, Sendable {
  /// 选取结果里的那一项，点中之后原样回给上层。
  var pick: SectorPick
  /// 松弛收敛后的静止圆心。逐帧的呼吸和漂移只在它上面加偏移，不改这个值。
  var center: CGPoint
  /// 基准半径（呼吸前）。
  var radius: CGFloat
  /// |涨跌幅| / 全场最大，0…1。环光的亮度与厚度、辉光的强度、落影的浓度都按它走。
  var norm: Double
  /// 球身取强端色还是弱端色。
  var upSide: Bool
  /// 漂移与环光游走的两支相位，由板块 id 散列出来——重排之后同一个板块还是同一个相位，
  /// 不会因为换了口径就整屏重新抖一遍。
  let phase: Double
  let phase2: Double
  /// 版面锚点：y 是自己那一簇的高度，x 是按名次左右错开的那个位置。松弛时往它回拉。
  let anchor: CGPoint
  /// 陪衬球。**只影响松弛时的回拉力度和起手散布**，渲染上和主角一模一样。
  let isFiller: Bool

  var id: String { pick.id }
  var pct: Double { pick.stat.pct }
}

/// 板块气泡场的版面：两极锚点 + 碰撞松弛。
///
/// 移植自原型 `app.js` 的 `layout()` / `relax()` / `hash()`，纯值类型、无副作用，
/// 可以脱开 SwiftUI 单测。
///
/// **尺寸自适应**：原型的球场写死在 390×844 画布上的 `{x0:13,x1:377,y0:134,y1:784}`，
/// 真机上从 SE 的 375 宽到 16 Pro Max 的 440 宽都得成立，所以这里改成按传进来的 `size`
/// 等比内缩（左右 13/390，上下 2%，各带一个地板）。半径那一步本来就有「按球场面积
/// 反算 k」的自适应，屏幕小了 `fieldArea` 跟着小，k 自己就收，绝对值的 `rmax`/`rmin`
/// 也是乘过 k 之后才落到画面上，所以整套尺子跟着屏幕走，一个像素都不用写死。
struct SectorLayout: Equatable, Sendable {
  /// 重排时的冷启动松弛轮数，和原型的 `relax(420)` 一致。
  static let coldIterations = 420
  /// 行情跳动时只换半径，从当前位置热启动，跑几轮把新的重叠推开就够了。
  /// 轮数少 = 位移小 = 看不出「碰撞回弹」。
  static let warmIterations = 30

  private(set) var bubbles: [SectorBubble] = []
  /// 球场矩形（已内缩）。
  private(set) var field: CGRect = .zero
  /// 强弱两簇之间那条地平线的 y。页面上那层极缓的明度变化对齐它。
  private(set) var horizonY: CGFloat = 0
  private var knobs: SectorFieldKnobs = .default

  init() {}

  init(selection: SectorSelection, size: CGSize, knobs: SectorFieldKnobs) {
    self.knobs = knobs
    field = Self.field(in: size)
    horizonY = Self.horizonY(in: size, knobs: knobs)
    guard !selection.picks.isEmpty, field.width > 1, field.height > 1 else { return }

    let w = Double(field.width), h = Double(field.height)
    let sep = knobs.split / 100
    let yStrong = Double(field.minY) + h * Self.lerp(0.38, 0.20, sep)
    let yWeak = Double(field.minY) + h * Self.lerp(0.62, 0.82, sep)
    let yMid = (yStrong + yWeak) / 2

    let radii = Self.radii(selection, knobs: knobs, field: field)
    let strongCount = max(1, selection.picks.filter { $0.side == .strong }.count)
    let fillerCount = max(1, selection.picks.filter { $0.side == .filler }.count)

    bubbles = selection.picks.enumerated().map { index, pick in
      let hv = Self.hash(pick.id)
      let filler = pick.side == .filler
      let anchorY: Double = switch pick.side {
      case .strong: yStrong
      case .weak: yWeak
      case .filler: yMid
      }
      // 主角按名次左右错开，陪衬等距散在中带。起手位置只是种子，之后交给松弛。
      let t: Double = if filler {
        0.08 + 0.84 * (Double(pick.slot) + 0.5) / Double(fillerCount)
      } else if pick.slot % 2 == 1 {
        0.5 + 0.22 * Double(pick.slot + 1) / Double(strongCount)
      } else {
        0.5 - 0.26 * Double(pick.slot + 1) / Double(strongCount)
      }
      return SectorBubble(
        pick: pick,
        center: CGPoint(x: Double(field.minX) + Self.clamp(t + (hv - 0.5) * 0.16, 0.09, 0.91) * w,
                        y: anchorY + (hv - 0.5) * h * (filler ? 0.16 : 0.10)),
        radius: radii[index],
        norm: selection.norm(pick.stat.pct),
        upSide: pick.isUpSide(total: selection.total),
        phase: hv * 2 * .pi,
        phase2: Self.hash(pick.id + "b") * 2 * .pi,
        anchor: CGPoint(x: Double(field.minX) + Self.clamp(t, 0.1, 0.9) * w, y: anchorY),
        isFiller: filler)
    }

    relax(iterations: Self.coldIterations)
  }

  /// 上场名单没变、只是行情跳了一下：半径和读数原地换掉，从当前位置热松弛几轮。
  ///
  /// 不走完整重排是因为每来一批行情就重跑一次 `relax(420)` 会让整屏球换一个站位，
  /// 看着像在洗牌；热启动只把新出现的那点重叠推开，位移小到看不出来。
  mutating func retune(_ selection: SectorSelection) {
    guard bubbles.count == selection.picks.count else { return }
    let radii = Self.radii(selection, knobs: knobs, field: field)
    for index in bubbles.indices {
      let pick = selection.picks[index]
      bubbles[index].pick = pick
      bubbles[index].radius = radii[index]
      bubbles[index].norm = selection.norm(pick.stat.pct)
      bubbles[index].upSide = pick.isUpSide(total: selection.total)
    }
    relax(iterations: Self.warmIterations)
  }

  /// 命中测试：落在球里、并且圆心离得最近的那一颗。
  func hit(_ point: CGPoint) -> SectorPick? {
    var best = Double.greatestFiniteMagnitude
    var found: SectorPick?
    for bubble in bubbles {
      let d = hypot(Double(bubble.center.x - point.x), Double(bubble.center.y - point.y))
      if d <= Double(bubble.radius), d < best { best = d; found = bubble.pick }
    }
    return found
  }

  /// 大球先画、小球后画——小球压在大球边上才像堆在一起。
  var paintOrder: [Int] {
    bubbles.indices.sorted { bubbles[$0].radius > bubbles[$1].radius }
  }

  /// 上场名单的指纹。只要它没变就只做热调，变了才整场重排。
  static func signature(_ selection: SectorSelection) -> [String] {
    selection.picks.map { "\($0.stat.id)#\($0.slot)#\($0.side)" }
  }

  // MARK: - 球场

  static func field(in size: CGSize) -> CGRect {
    guard size.width > 0, size.height > 0 else { return .zero }
    // 原型是 13/390 的左右内缩；上下留一线，别让球贴着自己这块画布的边缘。
    let hInset = max(10, size.width * 13 / 390)
    let vInset = max(8, size.height * 0.02)
    let w = max(1, size.width - hInset * 2)
    let h = max(1, size.height - vInset * 2)
    return CGRect(x: hInset, y: vInset, width: w, height: h)
  }

  /// 地平线的 y。D 那边要把页面上那层光晕对齐它，所以做成不依赖实例的纯函数。
  static func horizonY(in size: CGSize, knobs: SectorFieldKnobs) -> CGFloat {
    let rect = field(in: size)
    let sep = knobs.split / 100
    let yStrong = Double(rect.minY) + Double(rect.height) * lerp(0.38, 0.20, sep)
    let yWeak = Double(rect.minY) + Double(rect.height) * lerp(0.62, 0.82, sep)
    return CGFloat((yStrong + yWeak) / 2)
  }

  // MARK: - 半径

  /// 面积 ∝ |涨跌幅| → 半径 ∝ √|pct|，按 `selection.norm`（全场最大 |pct|、超出截到 1）
  /// 归一，带最小半径地板，
  /// 然后按「球场面积 × 铺满度 / 球面积和」反算一个自适应系数 k 整体缩放。
  private static func radii(_ selection: SectorSelection,
                            knobs: SectorFieldKnobs, field: CGRect) -> [CGFloat] {
    let raw = selection.picks.map {
      max(knobs.rmin, knobs.rmax * selection.norm($0.stat.pct).squareRoot())
    }
    let area = raw.reduce(0) { $0 + .pi * $1 * $1 }
    guard area > 0, field.width > 0, field.height > 0 else { return raw.map { CGFloat($0) } }
    let fieldArea = Double(field.width) * Double(field.height)
    // 上限原型里从 1.7 放到 2.2：1.7 时美股默认档（8 颗）正好顶满，
    // 「铺满度」那根滑杆在后半程等于失效。
    let k = clamp((fieldArea * (knobs.fill / 100) / area).squareRoot(), 0.55, 2.2)
    return raw.map { CGFloat($0 * k) }
  }

  // MARK: - 松弛

  private mutating func relax(iterations: Int) {
    guard !bubbles.isEmpty, iterations > 0 else { return }
    let pad = knobs.pad
    let minX = Double(field.minX), maxX = Double(field.maxX)
    let minY = Double(field.minY), maxY = Double(field.maxY)

    for iteration in 0..<iterations {
      let cool = 1 - Double(iteration) / Double(iterations) * 0.35

      // 两两推开
      for i in bubbles.indices {
        for j in bubbles.indices where j > i {
          var dx = Double(bubbles[j].center.x - bubbles[i].center.x)
          var dy = Double(bubbles[j].center.y - bubbles[i].center.y)
          var d = (dx * dx + dy * dy).squareRoot()
          if d <= 0 { d = 0.001 }
          let reach = Double(bubbles[i].radius) + Double(bubbles[j].radius) + pad
          guard d < reach else { continue }
          let push = (reach - d) / 2 * 0.92 * cool
          dx /= d; dy /= d
          bubbles[i].center.x -= dx * push
          bubbles[i].center.y -= dy * push
          bubbles[j].center.x += dx * push
          bubbles[j].center.y += dy * push
        }
      }

      // 回到自己那一头，并关在球场里
      for index in bubbles.indices {
        let r = Double(bubbles[index].radius)
        var x = Double(bubbles[index].center.x)
        var y = Double(bubbles[index].center.y)
        let anchor = bubbles[index].anchor
        y += (Double(anchor.y) - y) * (bubbles[index].isFiller ? 0.055 : 0.038) * cool
        x += (Double(anchor.x) - x) * 0.012 * cool
        x = Self.clamp(x, minX + r, maxX - r)
        y = Self.clamp(y, minY + r, maxY - r)
        bubbles[index].center = CGPoint(x: x, y: y)
      }
    }
  }

  // MARK: - 小工具

  /// FNV-1a，逐字对齐原型的 `hash()`（`Math.imul` 就是 32 位回绕乘）。
  /// 同一个 id 永远散列到同一个 0…1，相位和起手抖动因此是稳定的。
  static func hash(_ text: String) -> Double {
    var h: UInt32 = 2_166_136_261
    for unit in text.utf16 {
      h ^= UInt32(unit)
      h = h &* 16_777_619
    }
    return Double(h % 10_000) / 10_000
  }

  static func lerp(_ a: Double, _ b: Double, _ t: Double) -> Double { a + (b - a) * t }

  /// 和原型的 `clamp` 同一套边界语义（下界优先），免得球场比球还小时结果反过来。
  static func clamp(_ v: Double, _ lo: Double, _ hi: Double) -> Double {
    v < lo ? lo : (v > hi ? hi : v)
  }
}
