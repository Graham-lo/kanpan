import QuartzCore
import UIKit
import KanpanCore
import KanpanChart
import ReviewDomain

/// 交易回放（自动复盘 3d）画在 K 线上的那一层：每笔成交一个三角、「开 · 价」「平 · 价」小字、
/// 持仓那一段的开仓均价虚线。
///
/// **为什么不单独挂一层视图。** 图表那边「重画了叫我一声」（`ChartBox.onOverlayUpdate`）和
/// 「换盒子了叫我一声」（`ChartProxy.onBoxChanged`）都只有一个槽位，已经被复盘选区那一层
/// （`RangeOverlayView`）占着；再挂一层就会把它顶掉，笔记重温与取景的选区跟着不动了。
/// 所以这里只是一支画笔，由 `RangeOverlayView.draw` 在回放那一支里叫它，同一张画布、同一次重画。
///
/// 口径：
/// * 只画**已经发生**的成交（`TradeReplayPlan.visibleMarks(through:)`），不漏未来；
/// * 三角 8pt：买 ▲ 在那根最低价下方 6pt、卖 ▼ 在最高价上方 6pt，1pt 图底色描边；
///   同一根上的几笔往外叠；新出现的一枚 0.2 秒 easeOut 从 0.6 放到 1（减弱动态效果时直接出现）；
/// * 小字在三角外侧，不压价格轴、不压任何一枚三角、互相不压：右边放不下换左边，两边都不行就不写；
///   字底垫一圈图底色描边，落在影线上也读得清；
/// * 开仓均价虚线 1pt、`[3, 3]`、方向色四成，只画持仓那一段，加仓处换一段。
@MainActor final class TradeReplayPainter {
  var up: UIColor = .clear
  var down: UIColor = .clear
  var canvas: UIColor = .clear
  var label: UIColor = .clear
  /// 画完一帧、还有三角没放大到位时叫一声（`RangeOverlayView.setNeedsDisplay`）。
  var redraw: () -> Void = {}

  /// 三角的边长。
  static let size: CGFloat = 8
  /// 三角离 K 线高低点的距离。
  static let gap: CGFloat = 6
  /// 同一根上叠放两枚之间的空隙。
  static let stackGap: CGFloat = 2
  static let appear: CFTimeInterval = 0.2
  /// 小字底下那一圈图底色描边（字号的百分比，正数 = 只描不填）：约 2.5pt，字外露出 1pt 出头。
  static let haloWidth: CGFloat = 24
  private static let font = UIFont.monospacedDigitSystemFont(
    ofSize: UIFont.preferredFont(forTextStyle: .caption2).pointSize, weight: .medium)

  /// 每一枚三角第一次出现的时刻（按成交时刻认）。退回去看不见了就忘掉，再走到时重新放大一次。
  private var born: [Int64: CFTimeInterval] = [:]
  private var link: CADisplayLink?
  private var planID: String?

  func reset() { born = [:]; stopLink(); planID = nil }

  func paint(_ trade: ReviewChartBridge.TradeSession, state: ChartState, chart: ChartView,
             layout: KanpanCore.Layout, ctx: CGContext) {
    guard state.series.count > 0, let range = chart.chartPriceRange else { return }
    if planID != trade.id { born = [:]; planID = trade.id }
    let plan = trade.plan
    let now = state.series.lastTime
    let mode = state.price.mode
    func x(_ t: Int64) -> CGFloat { CGFloat(state.view.x(Double(t), plotW: layout.plotW)) }
    func y(_ p: Double) -> CGFloat { CGFloat(yOf(p, pane: layout.main, range: range, mode: mode)) }

    // 开仓均价：先画线，三角压在线上面。
    let tint = (plan.direction == .long ? up : down).withAlphaComponent(0.4)
    ctx.saveGState()
    ctx.setStrokeColor(tint.cgColor); ctx.setLineWidth(1); ctx.setLineDash(phase: 0, lengths: [3, 3])
    for segment in plan.entrySegments(through: now) {
      let py = y(segment.price)
      ctx.move(to: CGPoint(x: x(segment.from), y: py)); ctx.addLine(to: CGPoint(x: x(segment.to), y: py))
    }
    ctx.strokePath()
    ctx.restoreGState()

    let visible = plan.visibleMarks(through: now)
    let seen = Set(visible.map(\.time))
    born = born.filter { seen.contains($0.key) }
    let clock = CACurrentMediaTime()
    let reduceMotion = UIAccessibility.isReduceMotionEnabled
    var animating = false
    var stacks: [String: Int] = [:]
    var placed: [CGRect] = []
    var pending: [(CGFloat, CGFloat, String)] = []
    let bounds = CGRect(x: 0, y: 0, width: layout.plotW, height: layout.mainH)
    let attributes: [NSAttributedString.Key: Any] = [.font: Self.font, .foregroundColor: label]

    for mark in visible {
      let index = state.series.index(atTime: Double(mark.bar))
      guard index >= 0, index < state.series.count, state.series.time(at: index) == mark.bar else { continue }
      let cx = x(mark.bar)
      guard cx > -Self.size, cx < layout.plotW + Self.size else { continue }
      let key = "\(mark.bar)-\(mark.buy)"
      let k = stacks[key, default: 0]; stacks[key] = k + 1
      let offset = Self.gap + CGFloat(k) * (Self.size + Self.stackGap)
      // ▲ 顶点朝上、整枚在最低价下方；▼ 顶点朝下、整枚在最高价上方。
      let apex = mark.buy ? y(state.series.low[index]) + offset : y(state.series.high[index]) - offset
      let center = CGPoint(x: cx, y: mark.buy ? apex + Self.size / 2 : apex - Self.size / 2)

      var scale: CGFloat = 1
      if !reduceMotion {
        let start = born[mark.time] ?? { born[mark.time] = clock; return clock }()
        let progress = min(1, max(0, (clock - start) / Self.appear))
        if progress < 1 { animating = true }
        let eased = 1 - pow(1 - progress, 3)
        scale = 0.6 + 0.4 * CGFloat(eased)
      } else if born[mark.time] == nil {
        born[mark.time] = clock
      }
      triangle(at: center, up: mark.buy, scale: scale, color: mark.buy ? up : down, ctx: ctx)
      // 三角先全部落位、占好地方，小字再找空：字不许压到任何一枚三角（包括旁边那一根上的）。
      placed.append(CGRect(x: cx - Self.size / 2, y: center.y - Self.size / 2, width: Self.size, height: Self.size))
      pending.append((cx, center.y, (mark.entry ? "开 · " : "平 · ") + fmtPrice(mark.price, decimals: state.decimals)))
    }

    // 小字：「开 · 价」/「平 · 价」，放三角右边；压到价格轴、别的三角或别的字就换左边，还不行就不写。
    // 底下垫一圈图底色的描边：字常落在 K 线影线上，没有这一圈就和蜡烛搅在一起读不清。
    let halo: [NSAttributedString.Key: Any] = [.font: Self.font, .strokeColor: canvas, .strokeWidth: Self.haloWidth]
    for (cx, cy, text) in pending {
      let size = (text as NSString).size(withAttributes: attributes)
      let half = Self.size / 2 + Self.stackGap * 2
      let candidates = [
        CGRect(x: cx + half, y: cy - size.height / 2, width: size.width, height: size.height),
        CGRect(x: cx - half - size.width, y: cy - size.height / 2, width: size.width, height: size.height),
      ]
      guard let spot = candidates.first(where: { rect in
        bounds.contains(rect) && !placed.contains { $0.insetBy(dx: -2, dy: -1).intersects(rect) }
      }) else { continue }
      placed.append(spot)
      (text as NSString).draw(at: spot.origin, withAttributes: halo)
      (text as NSString).draw(at: spot.origin, withAttributes: attributes)
    }
    animating ? startLink() : stopLink()
  }

  private func triangle(at center: CGPoint, up: Bool, scale: CGFloat, color: UIColor, ctx: CGContext) {
    let s = Self.size * scale, h = s / 2
    let path = CGMutablePath()
    if up {
      path.move(to: CGPoint(x: center.x, y: center.y - h))
      path.addLine(to: CGPoint(x: center.x + h, y: center.y + h))
      path.addLine(to: CGPoint(x: center.x - h, y: center.y + h))
    } else {
      path.move(to: CGPoint(x: center.x, y: center.y + h))
      path.addLine(to: CGPoint(x: center.x + h, y: center.y - h))
      path.addLine(to: CGPoint(x: center.x - h, y: center.y - h))
    }
    path.closeSubpath()
    ctx.saveGState()
    ctx.addPath(path); ctx.setFillColor(color.cgColor); ctx.fillPath()
    ctx.addPath(path); ctx.setStrokeColor(canvas.cgColor); ctx.setLineWidth(1); ctx.setLineJoin(.round); ctx.strokePath()
    ctx.restoreGState()
  }

  private func startLink() {
    guard link == nil else { return }
    let link = CADisplayLink(target: LinkTarget { [weak self] in self?.redraw() }, selector: #selector(LinkTarget.fire))
    link.add(to: .main, forMode: .common)
    self.link = link
  }

  private func stopLink() { link?.invalidate(); link = nil }

  /// `CADisplayLink` 会强持有 target，隔一层免得画笔和视图被它拴住。
  private final class LinkTarget: NSObject {
    let action: () -> Void
    init(_ action: @escaping () -> Void) { self.action = action }
    @objc func fire() { action() }
  }
}
