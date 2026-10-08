import KanpanCore
import QuartzCore
import UIKit

/// 大单签在视图这一侧的事（2026-10-08，原型 §07 / §08）：点中、点中那一下放大、正在走那根新来一笔大单的光环、
/// 宿主让十字线跳到某一根（弹层「每根」条）、读屏。摆放与绘制在 `ChartRenderer+BigTrades`。
extension ChartView {
  /// 点中那一下放大到多少、多久（来回各一半）。
  static let bigTradePopScale: CGFloat = 1.3
  static let bigTradePopDuration: CFTimeInterval = 0.12
  /// 光环：外扩 8 pt、600ms 缓出；「减少动效」开着改成 150ms 一闪。
  static let bigTradeRingGrow: CGFloat = 8
  static let bigTradeRingDuration: CFTimeInterval = 0.6
  static let bigTradeFlashDuration: CFTimeInterval = 0.15

  /// 轻点落在签上就交给它（宿主接了才算）：点在蜡烛上时只有点进签本身（外扩 8 pt）才算签，其余照旧出十字线。
  func handleBigTradeTap(at p: CGPoint) -> Bool {
    guard onBigTradeTap != nil, let renderer, let sign = renderer.bigTradeHit(at: p, size: bounds.size) else { return false }
    if renderer.candleHit(at: p, size: bounds.size), !sign.bounds.insetBy(dx: -8, dy: -8).contains(p) { return false }
    tapBigTrade(sign)
    return true
  }

  /// 点中一枚签：轻触感、放大一下、十字线落到那一根、告诉宿主。
  func tapBigTrade(_ sign: BigTradeSign) {
    ChartHaptics.magnetTick()
    popBigTrade(sign)
    placeCrosshair(atTime: sign.t)
    onBigTradeTap?(sign)
  }

  /// 十字线跳到开盘时间为 `t` 的那一根（没有正好的取其后最近一根）；滚出屏幕就把视野推到那一根的里侧。
  public func placeCrosshair(atTime t: Int64) {
    guard var s = state, s.series.count > 0 else { return }
    let i = min(s.series.firstIndex(atOrAfter: t), s.series.count - 1)
    s.crosshair = Crosshair(index: i, price: s.options.crossPrice == .close ? nil : s.series.close[i])
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
    let viewMoved = s.view != state?.view
    state = s
    if viewMoved { onViewChanged?(s.view) }
  }

  /// 这一屏的签（测试与宿主读）。
  public var bigTradeSigns: [BigTradeSign] { renderer?.bigTradeSigns(size: bounds.size) ?? [] }

  // MARK: 动效

  /// 点中那一下：把这枚签单独画一张，放大 1.3 倍再回来（「减少动效」开着不放大）。
  private func popBigTrade(_ sign: BigTradeSign) {
    guard !ChartHaptics.reduceMotion, window != nil, let colors = state?.colors else { return }
    let pad: CGFloat = 4
    let box = sign.bounds.insetBy(dx: -pad, dy: -pad)
    let img = UIGraphicsImageRenderer(bounds: box).image { c in
      ChartRenderer.paintBigTradeSign(c.cgContext, sign, colors: colors, scale: 1)
    }
    let l = CALayer()
    l.contents = img.cgImage
    l.contentsScale = img.scale
    let c = sign.markCenter
    l.anchorPoint = CGPoint(x: (c.x - box.minX) / box.width, y: (c.y - box.minY) / box.height)
    l.bounds = CGRect(origin: .zero, size: box.size)
    l.position = c
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

  /// 正在走的那一根新来了一笔大单：在它的签外圈扩一道光环。换品种、第一次灌账、签不在这一屏都不响。
  func pulseBigTradeIfNew(from old: ChartState?, to new: ChartState) {
    guard let o = old, let before = o.bigTrades, let tape = new.bigTrades, before.symbol == tape.symbol,
          let ms = tape.lastBigMs, ms > (before.lastBigMs ?? .min), !new.series.isEmpty,
          ms >= new.series.lastTime, ms < new.series.lastTime + new.series.step,
          window != nil, let sign = renderer?.bigTradeLiveSign(size: bounds.size)
    else { return }
    pulseBigTrade(sign)
    #if DEBUG
    bigTradePulseCount += 1
    #endif
  }

  func pulseBigTrade(_ sign: BigTradeSign) {
    guard let colors = state?.colors else { return }
    let color = Paint.cg(sign.buy ? colors.up : colors.down)
    let c = sign.pulseCenter
    let r0 = max(sign.markRect.width, sign.markRect.height) / 2 + 1
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

  /// 十字线（或最新一根）那一根有签就念一句「买方大单 1.2M，12:30 这根」。
  var bigTradeVoiceOver: String? {
    guard let s = state, let renderer, s.series.count > 0 else { return nil }
    let i = s.crosshair.map { min(max($0.index, 0), s.series.count - 1) } ?? (s.series.count - 1)
    guard let sign = renderer.bigTradeSigns(size: bounds.size).first(where: { $0.index == i }) else { return nil }
    return renderer.bigTradeAccessibilityLabel(sign)
  }

  /// 读屏的自定义动作：这一根有签、宿主接了，就给一个「打开大单与爆仓」。
  func bigTradeAccessibilityActions() -> [UIAccessibilityCustomAction] {
    guard onBigTradeTap != nil, let s = state, let renderer, s.series.count > 0 else { return [] }
    let i = s.crosshair.map { min(max($0.index, 0), s.series.count - 1) } ?? (s.series.count - 1)
    guard let sign = renderer.bigTradeSigns(size: bounds.size).first(where: { $0.index == i }) else { return [] }
    return [UIAccessibilityCustomAction(name: BigTradeTerm.open.text) { [weak self] _ in
      self?.tapBigTrade(sign); return true
    }]
  }
}
