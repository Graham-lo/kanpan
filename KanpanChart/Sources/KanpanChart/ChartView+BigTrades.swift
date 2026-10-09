import KanpanCore
import QuartzCore
import UIKit

/// 大单与爆仓气泡在视图这一侧的事（2026-10-08 定版「统一透明泡」）：点中泡、点中那一下放大、
/// 正在走那根新来一笔大单的光环、宿主让十字线跳到某一根（弹层「每根」条）、读屏。
/// 小圆点只是画出来看的：不响应点击、不进读屏。摆放与绘制在 `ChartRenderer+BigTrades`。
extension ChartView {
  /// 点中那一下放大到多少、多久（来回各一半）。
  static let bigTradePopScale: CGFloat = 1.3
  static let bigTradePopDuration: CFTimeInterval = 0.12
  /// 光环：外扩 8 pt、600ms 缓出；「减少动效」开着改成 150ms 一闪。
  static let bigTradeRingGrow: CGFloat = 8
  static let bigTradeRingDuration: CFTimeInterval = 0.6
  static let bigTradeFlashDuration: CFTimeInterval = 0.15

  /// 轻点落在泡上就交给它（宿主接了才算）：点在蜡烛上时只有点进泡本身（外扩 8 pt）才算泡，其余照旧出十字线。
  func handleBigTradeTap(at p: CGPoint) -> Bool {
    guard onBigTradeTap != nil, let renderer, let bubble = renderer.bigTradeHit(at: p, size: bounds.size) else { return false }
    if renderer.candleHit(at: p, size: bounds.size), !bubble.bounds.insetBy(dx: -8, dy: -8).contains(p) { return false }
    tapBigTrade(bubble)
    return true
  }

  /// 点中一枚泡：轻触感、放大一下、十字线落到那一根、告诉宿主。
  func tapBigTrade(_ bubble: BigTradeBubble) {
    ChartHaptics.magnetTick()
    popBigTrade(bubble)
    placeCrosshair(atTime: bubble.t)
    onBigTradeTap?(bubble)
  }

  /// 十字线跳到时间 `t`（没有正好的取其后最近一根）；明确的证据价位保持真实价并纳入视野。
  public func placeCrosshair(atTime t: Int64, price: Double? = nil) {
    guard var s = state, s.series.count > 0 else { return }
    let i = min(s.series.firstIndex(atOrAfter: t), s.series.count - 1)
    let evidencePrice = price.flatMap { $0.isFinite && $0 > 0 ? $0 : nil }
    s.crosshair = Crosshair(index: i, price: evidencePrice ?? (s.options.crossPrice == .close ? nil : s.series.close[i]), source: .bigTrade)
    s.orderFlowSelected = nil
    if let L = chartLayout, L.plotW > 0 {
      let x = s.view.x(Double(s.series.time(at: i)), plotW: L.plotW)
      let inset = min(40, L.plotW * 0.1)
      if x < inset || x > L.plotW - inset {
        let dx = x < inset ? x - inset : x - (L.plotW - inset)
        s.view = clampView(s.view.shifted(byPx: dx, plotW: L.plotW),
                           series: s.series, plotW: L.plotW, anchor: s.options.anchor)
      }
    }
    // Explicit evidence prices must be visible at their actual Y coordinate, including outside the candle range.
    if let evidencePrice, let renderer, bounds.width > 0, bounds.height > 0 {
      let current = renderer.priceRange(size: bounds.size, view: s.view, transform: s.price)
      let pad = (current.hi - current.lo) * 0.04
      if evidencePrice < current.lo + pad || evidencePrice > current.hi - pad {
        var automatic = s.price; automatic.reset()
        let auto = renderer.priceRange(size: bounds.size, view: s.view, transform: automatic)
        let low = min(current.lo, evidencePrice), high = max(current.hi, evidencePrice)
        let span = high - low
        if span.isFinite, span > 0, auto.hi > auto.lo {
          s.price.zoom = min(0.98, max(0.03, (auto.hi - auto.lo) / (span * 1.12)))
          s.axisScaleAnchor = (low + high) / 2
        }
      }
    }
    let viewMoved = s.view != state?.view
    state = s
    if viewMoved { onViewChanged?(s.view) }
  }

  /// 这一屏的点与泡（测试与宿主读）。
  public var bigTradeBubbles: [BigTradeBubble] { renderer?.bigTradeBubbles(size: bounds.size) ?? [] }

  // MARK: 动效

  /// 点中那一下：把这枚泡单独画一张，以圆心放大 1.3 倍再回来（「减少动效」开着不放大）。
  private func popBigTrade(_ bubble: BigTradeBubble) {
    guard !ChartHaptics.reduceMotion, window != nil, let colors = state?.colors else { return }
    let dark = state?.dark ?? false
    let pad: CGFloat = 4
    let box = bubble.bounds.insetBy(dx: -pad, dy: -pad)
    let img = UIGraphicsImageRenderer(bounds: box).image { c in
      ChartRenderer.paintBigTradeBubble(c.cgContext, bubble, colors: colors, dark: dark, scale: 1)
    }
    let l = CALayer()
    l.contents = img.cgImage
    l.contentsScale = img.scale
    l.bounds = CGRect(origin: .zero, size: box.size)
    l.position = bubble.center
    let a = CABasicAnimation(keyPath: "transform.scale")
    a.fromValue = 1; a.toValue = Self.bigTradePopScale
    a.duration = Self.bigTradePopDuration / 2
    a.autoreverses = true
    a.timingFunction = CAMediaTimingFunction(name: .easeOut)
    CATransaction.begin()
    CATransaction.setCompletionBlock { l.removeFromSuperlayer() }
    bigTradeFXLayer.addSublayer(l)
    l.add(a, forKey: "pop")
    CATransaction.commit()
  }

  /// 正在走的那一根新来了一笔大单：在它那一侧的点或泡外圈扩一道光环。换品种、第一次灌账、这根没画都不响。
  func pulseBigTradeIfNew(from old: ChartState?, to new: ChartState) {
    guard let o = old, let before = o.bigTrades, let tape = new.bigTrades, before.symbol == tape.symbol,
          let ms = tape.lastBigMs, ms > (before.lastBigMs ?? .min), !new.series.isEmpty,
          ms >= new.series.lastTime, ms < new.series.lastTime + new.series.step,
          window != nil, let bubble = renderer?.bigTradeLiveBubble(size: bounds.size)
    else { return }
    pulseBigTrade(bubble)
    #if DEBUG
    bigTradePulseCount += 1
    #endif
  }

  func pulseBigTrade(_ bubble: BigTradeBubble) {
    guard let colors = state?.colors else { return }
    let color = Paint.cg(bubble.up ? colors.up : colors.down)
    let c = bubble.center
    let r0 = bubble.r + 1
    func circle(_ r: CGFloat) -> CGPath { CGPath(ellipseIn: CGRect(x: c.x - r, y: c.y - r, width: 2 * r, height: 2 * r), transform: nil) }
    let ring = CAShapeLayer()
    ring.frame = bounds
    CATransaction.begin()
    CATransaction.setCompletionBlock { ring.removeFromSuperlayer() }
    if ChartHaptics.reduceMotion {
      ring.path = circle(r0 + 3)
      ring.fillColor = color
      ring.opacity = 0
      let a = CAKeyframeAnimation(keyPath: "opacity")
      a.values = [0, 0.45, 0]
      a.keyTimes = [0, 0.4, 1]
      a.duration = Self.bigTradeFlashDuration
      bigTradeFXLayer.addSublayer(ring)
      ring.add(a, forKey: "flash")
    } else {
      ring.path = circle(r0 + Self.bigTradeRingGrow)
      ring.fillColor = nil
      ring.strokeColor = color
      ring.lineWidth = 1.5
      ring.opacity = 0
      let grow = CABasicAnimation(keyPath: "path")
      grow.fromValue = circle(r0); grow.toValue = circle(r0 + Self.bigTradeRingGrow)
      let fade = CABasicAnimation(keyPath: "opacity")
      fade.fromValue = 0.9; fade.toValue = 0
      let g = CAAnimationGroup()
      g.animations = [grow, fade]
      g.duration = Self.bigTradeRingDuration
      g.timingFunction = CAMediaTimingFunction(name: .easeOut)
      bigTradeFXLayer.addSublayer(ring)
      ring.add(g, forKey: "ring")
    }
    CATransaction.commit()
  }

  // MARK: 读屏

  /// 十字线（或最新一根）那一根的泡（只认泡，点不进读屏），向上在前。
  private var bigTradeFocusBubbles: [BigTradeBubble] {
    guard let s = state, let renderer, s.series.count > 0 else { return [] }
    let i = s.crosshair.map { min(max($0.index, 0), s.series.count - 1) } ?? (s.series.count - 1)
    return renderer.bigTradeBubbles(size: bounds.size).filter { $0.index == i && $0.isBubble }
  }

  /// 那一根有泡就念「10-08 12:30 向上 1.2M」，上下都有就两句。
  var bigTradeVoiceOver: String? {
    guard let renderer else { return nil }
    let items = bigTradeFocusBubbles
    guard !items.isEmpty else { return nil }
    return items.map { renderer.bigTradeAccessibilityLabel($0) }.joined(separator: "，")
  }

  /// 读屏的自定义动作：这一根有泡、宿主接了，就给一个「打开大单与爆仓」。
  func bigTradeAccessibilityActions() -> [UIAccessibilityCustomAction] {
    guard onBigTradeTap != nil, let bubble = bigTradeFocusBubbles.first else { return [] }
    return [UIAccessibilityCustomAction(name: BigTradeTerm.open.text) { [weak self] _ in
      self?.tapBigTrade(bubble); return true
    }]
  }
}
