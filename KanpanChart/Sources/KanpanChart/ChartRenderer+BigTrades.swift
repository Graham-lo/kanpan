import CoreGraphics
import Foundation
import KanpanCore
import UIKit

/// 图上大单签（2026-10-08，设计源 `docs/原型-手机大单与爆仓-2026-10-08.html` §05–§08）：
/// 把 `state.bigTrades` 的分钟账按本图 K 线并成每根买 / 卖，最近 300 根定三档，交给 `BigTradeSigns.plan`
/// 摆好（躲图例那一带、画线文字、主图上下沿），画在底图里画线之上。
///
/// 两只缓存盒子：
/// - `BigTradeBarsCache`：每根的买 / 卖与档位，只认「序列身份 + 分钟账」，拖图、捏合不重算；
/// - `BigTradeSignCache`：这一屏摆好的签，`recalc` 跟订单流色带同一套失效（输入 / 视野 / 画线变了换盒子），
///   十字线动不换——底图、点击、动效三处取的是同一份。
extension ChartRenderer {
  final class BigTradeBarsCache {
    var key: (revision: UInt64, tape: BigTradeTape)?
    var buy: [Double] = []
    var sell: [Double] = []
    var tiers: BigTradeTiers?
    /// 真算了几次（测试核对）。
    var computed = 0
  }

  final class BigTradeSignCache {
    var entries: [(plotW: Double, paneY: Double, paneH: Double, signs: [BigTradeSign])] = []
  }

  /// 签上的字：11 号半粗、等宽数字。
  static let bigTradeFont = UIFont.monospacedDigitSystemFont(ofSize: 11, weight: .semibold)
  /// 图例那一带的高度：签一律不进去。
  static let bigTradeLegendBand = 24.0

  /// 分钟以下的周期（秒线）不出签：分钟账并不进去。
  var bigTradeActive: Bool {
    guard let tape = state.bigTrades, !state.percentAxis, !state.series.isEmpty else { return false }
    return state.series.step >= BigTradeFlow.minuteMs && !tape.minutes.isEmpty
  }

  /// 每根的买 / 卖与档位（按序列身份 + 分钟账缓存）。
  func bigTradeBars() -> (buy: [Double], sell: [Double], tiers: BigTradeTiers?)? {
    guard bigTradeActive, let tape = state.bigTrades else { return nil }
    let s = state.series
    let box = bigTradeBarsCache
    if let k = box.key, k.revision == s.revision, k.tape == tape { return (box.buy, box.sell, box.tiers) }
    var opens = [Int64](repeating: 0, count: s.count)
    for i in 0..<s.count { opens[i] = s.time(at: i) }
    let r = tape.bars(opens: opens, lastEnd: s.lastTime + s.step)
    let from = max(0, s.count - BigTradeSigns.tierBars)
    var vals: [Double] = []
    vals.reserveCapacity(s.count - from)
    for i in from..<s.count { vals.append(max(r.buy[i], r.sell[i])) }
    box.key = (s.revision, tape)
    box.buy = r.buy; box.sell = r.sell
    box.tiers = BigTradeSigns.tiers(vals, floor: tape.floor)
    box.computed += 1
    return (r.buy, r.sell, box.tiers)
  }

  /// 这一屏摆好的签（视图坐标）。
  public func bigTradeSigns(size: CGSize) -> [BigTradeSign] {
    guard bigTradeActive else { return [] }
    let L = layout(size: size)
    return bigTradeSigns(pane: L.main, range: priceRange(size: size), L: L)
  }

  func bigTradeSigns(pane: Pane, range: PriceRange, L: Layout) -> [BigTradeSign] {
    guard bigTradeActive else { return [] }
    if let hit = bigTradeSignCache.entries.first(where: { $0.plotW == L.plotW && $0.paneY == pane.y && $0.paneH == pane.h }) {
      return hit.signs
    }
    let signs = computeBigTradeSigns(pane: pane, range: range, L: L)
    if bigTradeSignCache.entries.count >= 3 { bigTradeSignCache.entries.removeFirst() }
    bigTradeSignCache.entries.append((L.plotW, pane.y, pane.h, signs))
    return signs
  }

  private func computeBigTradeSigns(pane: Pane, range: PriceRange, L: Layout) -> [BigTradeSign] {
    guard let bars = bigTradeBars(), let tiers = bars.tiers else { return [] }
    let s = state.series
    let (lo, hi) = visibleRange(view: state.view, series: s)
    guard lo <= hi, s.close.indices.contains(lo), s.close.indices.contains(hi) else { return [] }
    let mode = state.effectivePriceMode
    let heikinOn = state.options.kind == .heikin
    func hiLo(_ i: Int) -> (CGFloat, CGFloat) {
      var h = s.high[i], l = s.low[i]
      if heikinOn, let ha = heikin?.bar(i) { h = max(h, ha.h); l = min(l, ha.l) }
      return (CGFloat(KanpanCore.yOf(h, pane: pane, range: range, mode: mode)),
              CGFloat(KanpanCore.yOf(l, pane: pane, range: range, mode: mode)))
    }
    var inputs: [BigTradeSignInput] = []
    for i in lo...hi where bars.buy[i] > 0 || bars.sell[i] > 0 {
      let t = s.time(at: i)
      let x = CGFloat(state.view.x(Double(t), plotW: L.plotW))
      guard x >= 0, x <= CGFloat(L.plotW) else { continue }
      let (hy, ly) = hiLo(i)
      inputs.append(BigTradeSignInput(index: i, t: t, x: x, hiY: hy, loY: ly, buy: bars.buy[i], sell: bars.sell[i]))
    }
    guard !inputs.isEmpty else { return [] }
    let plotW = L.plotW
    let span: (CGFloat, CGFloat) -> (hiY: CGFloat, loY: CGFloat)? = { x0, x1 in
      var a = s.index(atTime: state.view.t(atX: Double(x0), plotW: plotW))
      var b = s.index(atTime: state.view.t(atX: Double(x1), plotW: plotW))
      if a > b { swap(&a, &b) }
      a = max(a, lo); b = min(b, hi)
      guard a <= b else { return nil }
      var top = CGFloat.greatestFiniteMagnitude, bottom = -CGFloat.greatestFiniteMagnitude
      for i in a...b {
        let x = CGFloat(state.view.x(Double(s.time(at: i)), plotW: plotW))
        guard x >= x0 - 1, x <= x1 + 1 else { continue }
        let (hy, ly) = hiLo(i)
        top = min(top, hy); bottom = max(bottom, ly)
      }
      return top <= bottom ? (top, bottom) : nil
    }
    let env = BigTradeSignEnv(
      tiers: tiers,
      spacing: CGFloat(state.view.barSpacing(step: s.step, plotW: L.plotW)),
      top: CGFloat(pane.y + max(Self.bigTradeLegendBand, mainLegendInset(plotW: L.plotW))),
      bottom: CGFloat(pane.y + pane.h),
      plotW: CGFloat(L.plotW),
      avoid: drawingLabelBoxes(pane: pane, range: range, L: L),
      measure: { $0.width(Self.bigTradeFont) },
      text: { Self.orderFlowAmount($0) },
      span: span)
    return BigTradeSigns.plan(inputs, env: env)
  }

  /// 底图上画签（画线之上、最新价之下）。返回画了几枚。
  @discardableResult
  func drawBigTrades(_ ctx: CGContext, pane: Pane, range: PriceRange, L: Layout) -> Int {
    let signs = bigTradeSigns(pane: pane, range: range, L: L)
    guard !signs.isEmpty else { return 0 }
    ctx.saveGState()
    defer { ctx.restoreGState() }
    ctx.clip(to: CGRect(x: 0, y: pane.y, width: L.plotW, height: pane.h))
    for s in signs { Self.paintBigTradeSign(ctx, s, colors: state.colors, scale: 1) }
    return signs.count
  }

  /// 画一枚签（底图与点击放大的那一下共用）。`scale` 以记号中心为原点放大。
  static func paintBigTradeSign(_ ctx: CGContext, _ s: BigTradeSign, colors: ChartColors, scale k: CGFloat) {
    let color = Paint.cg(s.buy ? colors.up : colors.down)
    ctx.saveGState()
    defer { ctx.restoreGState() }
    if k != 1 {
      let c = s.markCenter
      ctx.translateBy(x: c.x, y: c.y); ctx.scaleBy(x: k, y: k); ctx.translateBy(x: -c.x, y: -c.y)
    }
    switch s.mark {
    case .dot:
      ctx.setFillColor(color.copy(alpha: 0.7) ?? color)
      ctx.fillEllipse(in: s.markRect)
    case .triangle:
      let p = s.trianglePoints
      ctx.setFillColor(color)
      ctx.beginPath()
      ctx.move(to: p[0]); ctx.addLine(to: p[1]); ctx.addLine(to: p[2])
      ctx.closePath()
      ctx.fillPath()
    }
    if let cap = s.capsule {
      ctx.setFillColor(color)
      ctx.addRoundRect(cap, radius: cap.height / 2)
      ctx.fillPath()
      s.text.drawCentered(at: CGPoint(x: cap.midX, y: cap.midY), font: bigTradeFont, color: "#FFFFFF")
    }
  }

  /// 点在哪枚签上（视图坐标；44 × 44 热区，取最近）。
  public func bigTradeHit(at p: CGPoint, size: CGSize) -> BigTradeSign? {
    let signs = bigTradeSigns(size: size)
    guard !signs.isEmpty else { return nil }
    let L = layout(size: size)
    guard p.x >= 0, Double(p.x) <= L.plotW, Double(p.y) >= L.main.y - 22, Double(p.y) <= L.main.y + L.main.h + 22
    else { return nil }
    return BigTradeSigns.hit(p, in: signs)
  }

  /// 读屏一句：「买方大单 1.2M，10-08 12:30 这根」。
  public func bigTradeAccessibilityLabel(_ s: BigTradeSign) -> String {
    BigTradeSigns.accessibilityLabel(s, time: fmtFull(ms: Double(s.t), offsetMinutes: state.timezone.offsetMinutes))
  }

  /// 正在走那一根的签（光环动效挂在它上面）。
  public func bigTradeLiveSign(size: CGSize) -> BigTradeSign? {
    let last = state.series.count - 1
    return bigTradeSigns(size: size).first { $0.index == last }
  }
}
