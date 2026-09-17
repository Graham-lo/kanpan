import SwiftUI
import UIKit
import KanpanCore
import KanpanChart
import ReviewDomain
import ReviewUI

struct ReviewRangeOverlay: UIViewRepresentable {
  var feature: ReviewFeature
  var bridge: ReviewChartBridge
  var liveProxy: ChartProxy
  /// 横屏画线时置真：这一层什么都不画（§2E5）。记录一条没少，只是这一帧不上图。
  var suppressed = false
  /// 刚记下的那一条（§2F2）：进来一个新 id 就闪一下，告诉用户「记号落在这儿了」。
  var flash: UUID?
  func makeUIView(context: Context) -> RangeOverlayView { RangeOverlayView() }
  func updateUIView(_ view: RangeOverlayView, context: Context) {
    view.feature = feature; view.bridge = bridge
    view.proxy = bridge.active ? bridge.proxy : liveProxy
    view.draft = (bridge.mode == .capture && !suppressed) ? feature.draft : nil
    view.records = suppressed ? [] : feature.records
    view.suppressed = suppressed
    view.flash(suppressed ? nil : flash)
    view.isUserInteractionEnabled = bridge.mode == .capture
    view.proxy?.box?.onOverlayUpdate = { [weak view] in view?.setNeedsDisplay() }
    view.setNeedsDisplay()
  }
}
final class RangeOverlayView: UIView {
  weak var feature: ReviewFeature?
  weak var bridge: ReviewChartBridge?
  weak var proxy: ChartProxy?
  var draft: ReviewDraft?
  var records: [ReviewRecord] = []
  /// 见 `ReviewRangeOverlay.suppressed`。回放态那一支不吃 `records`，所以得单独挡一道。
  var suppressed = false
  /// 闪一下的实现（§2F2）：只记「闪的是哪一条」和「这一帧是亮还是暗」，
  /// 剩下的交给一个短定时器。不用 CoreAnimation 是因为这一层是手绘的 `draw(_:)`，
  /// 没有可以动画的 layer 属性；三次明暗切换共 0.9 秒，够看见，不至于闪得人眼晕。
  private var flashID: UUID?
  private var flashOn = false
  private var flashTimer: Timer?
  private var dragPart = ""
  private var startIndex = 0
  private var before: ReviewDraft?
  override init(frame: CGRect) { super.init(frame: frame); isOpaque = false; backgroundColor = .clear; isMultipleTouchEnabled = false; accessibilityIdentifier = "review.range" }
  required init?(coder: NSCoder) { fatalError("init(coder:) unavailable") }
  private var chart: ChartView? { proxy?.box?.chart }
  func flash(_ id: UUID?) {
    guard id != flashID else { return }
    flashID = id; flashTimer?.invalidate(); flashOn = false
    guard id != nil else { setNeedsDisplay(); return }
    var left = 6   // 亮灭各三次
    flashTimer = Timer.scheduledTimer(withTimeInterval: 0.15, repeats: true) { [weak self] timer in
      guard let self else { timer.invalidate(); return }
      self.flashOn.toggle(); left -= 1
      if left <= 0 { timer.invalidate(); self.flashOn = false; self.flashTimer = nil }
      self.setNeedsDisplay()
    }
    setNeedsDisplay()
  }
  override func point(inside point: CGPoint, with event: UIEvent?) -> Bool {
    guard let layout = chart?.chartLayout else { return false }
    return point.x >= 0 && point.x <= layout.plotW && point.y >= 0 && point.y < layout.mainH
  }
  override func draw(_ rect: CGRect) {
    guard let chart, let state = chart.state, let layout = chart.chartLayout, let ctx = UIGraphicsGetCurrentContext() else { return }
    ctx.saveGState(); ctx.clip(to: CGRect(x: 0, y: 0, width: layout.plotW, height: layout.mainH))
    if let draft { paint(draft, state: state, layout: layout, ctx: ctx, editing: true, outcome: nil) }
    else if suppressed { ctx.restoreGState(); return }
    else if bridge?.mode == .live {
      // 落图的条件统一在 `ReviewRecord.paints(symbol:interval:)` 里（§2F3），
      // 那儿有单测盯着「BTC 的记号不许画到 ETH 上、1h 的不许画到 1m 上」。
      for record in records.filter({
        $0.paints(symbol: state.series.symbol, interval: state.series.interval.rawValue)
      }).prefix(50) {
        paint(record.draft, state: state, layout: layout, ctx: ctx, editing: false,
              outcome: record.outcome, emphasis: record.id == flashID && flashOn)
      }
    } else if let record = bridge?.replayRecord, state.series.lastTime >= record.draft.range.start {
      // Outcomes and target annotations stay hidden until the judgment is known.
      if ReviewChartBridge.closeTime(state.series.lastTime, interval: state.series.interval) >= record.draft.created {
        paint(record.draft, state: state, layout: layout, ctx: ctx, editing: false, outcome: nil)
      }
    }
    ctx.restoreGState()
  }
  private func paint(_ draft: ReviewDraft, state: ChartState, layout: KanpanCore.Layout, ctx: CGContext, editing: Bool, outcome: ReviewOutcome?, emphasis: Bool = false) {
    let a = state.view.x(Double(draft.range.start), plotW: layout.plotW)
    let b = state.view.x(Double(draft.range.end), plotW: layout.plotW)
    let color = UIColor.systemOrange
    ctx.setFillColor(color.withAlphaComponent(editing ? 0.1 : (emphasis ? 0.14 : 0.035)).cgColor)
    ctx.fill(CGRect(x: a, y: 0, width: b - a, height: layout.mainH))
    ctx.setStrokeColor(color.withAlphaComponent(editing ? 0.8 : (emphasis ? 0.9 : 0.35)).cgColor)
    ctx.setLineWidth(emphasis && !editing ? 1.5 : 1)
    for x in [a, b] { ctx.move(to: CGPoint(x: x, y: 0)); ctx.addLine(to: CGPoint(x: x, y: layout.mainH)); ctx.strokePath() }
    if editing {
      for x in [a, b] { handle(CGPoint(x: x, y: layout.mainH * 0.52), ctx: ctx) }
      let label = "\(draft.range.bars) 根 · \(date(draft.range.start)) – \(date(draft.range.end))"
      label.draw(at: CGPoint(x: 8, y: layout.mainH - 24), withAttributes: [.font: UIFont.systemFont(ofSize: 11), .foregroundColor: color])
    }
    if draft.rule.direction != .observe, let priceRange = chart?.chartPriceRange {
      for (value, title) in [(draft.rule.target, "目标"), (draft.rule.invalidation, "失效")] {
        let y = yOf(value, pane: layout.main, range: priceRange, mode: state.price.mode)
        ctx.setStrokeColor(color.withAlphaComponent(editing ? 0.75 : 0.3).cgColor)
        ctx.move(to: CGPoint(x: max(0, a), y: y)); ctx.addLine(to: CGPoint(x: layout.plotW, y: y)); ctx.strokePath()
        if editing {
          handle(CGPoint(x: layout.plotW - 18, y: max(18, min(layout.mainH - 42, y))), ctx: ctx)
          (title + " " + value.formatted(.number.precision(.fractionLength(0...6)))).draw(at: CGPoint(x: max(8, layout.plotW - 125), y: max(2, min(layout.mainH - 52, y - 17))), withAttributes: [.font: UIFont.systemFont(ofSize: 11), .foregroundColor: color])
        }
      }
      let expiry = min(layout.plotW - 18, max(18, state.view.x(Double(draft.rule.expires), plotW: layout.plotW)))
      ctx.setLineDash(phase: 0, lengths: [3, 4]); ctx.setStrokeColor(UIColor.secondaryLabel.cgColor)
      ctx.move(to: CGPoint(x: expiry, y: 0)); ctx.addLine(to: CGPoint(x: expiry, y: layout.mainH)); ctx.strokePath(); ctx.setLineDash(phase: 0, lengths: [])
      if editing { handle(CGPoint(x: expiry, y: 34), ctx: ctx) }
    }
    if !editing {
      let judgment = state.view.x(Double(draft.created), plotW: layout.plotW)
      ctx.setStrokeColor(color.withAlphaComponent(0.5).cgColor); ctx.move(to: CGPoint(x: judgment, y: 0)); ctx.addLine(to: CGPoint(x: judgment, y: layout.mainH)); ctx.strokePath()
      if let outcome { outcome.title.draw(at: CGPoint(x: max(3, a), y: layout.mainH - 20), withAttributes: [.font: UIFont.systemFont(ofSize: 10), .foregroundColor: color]) }
    }
  }
  private func handle(_ point: CGPoint, ctx: CGContext) {
    ctx.setFillColor(UIColor.systemOrange.cgColor); ctx.fillEllipse(in: CGRect(x: point.x - 5, y: point.y - 5, width: 10, height: 10))
    ctx.setStrokeColor(UIColor.white.cgColor); ctx.setLineWidth(1.5); ctx.strokeEllipse(in: CGRect(x: point.x - 5, y: point.y - 5, width: 10, height: 10))
  }
  private func date(_ time: Int64) -> String {
    let f = DateFormatter(); f.dateFormat = "M/d HH:mm"; return f.string(from: Date(timeIntervalSince1970: Double(time) / 1000))
  }
  override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
    guard let q = touches.first?.location(in: self), let draft, let state = chart?.state, let layout = chart?.chartLayout else { return }
    before = draft
    let a = state.view.x(Double(draft.range.start), plotW: layout.plotW), b = state.view.x(Double(draft.range.end), plotW: layout.plotW)
    let candidates: [(String, CGPoint)] = [("left", CGPoint(x: a, y: layout.mainH * 0.52)), ("right", CGPoint(x: b, y: layout.mainH * 0.52))]
    var handles = candidates
    if draft.rule.direction != .observe, let range = chart?.chartPriceRange {
      handles += [("target", CGPoint(x: layout.plotW - 18, y: max(18, min(layout.mainH - 42, yOf(draft.rule.target, pane: layout.main, range: range, mode: state.price.mode))))),
        ("invalid", CGPoint(x: layout.plotW - 18, y: max(18, min(layout.mainH - 42, yOf(draft.rule.invalidation, pane: layout.main, range: range, mode: state.price.mode))))),
        ("expiry", CGPoint(x: min(layout.plotW - 18, max(18, state.view.x(Double(draft.rule.expires), plotW: layout.plotW))), y: 34))]
    }
    dragPart = handles.filter { hypot($0.1.x - q.x, $0.1.y - q.y) <= 22 }.min { hypot($0.1.x - q.x, $0.1.y - q.y) < hypot($1.1.x - q.x, $1.1.y - q.y) }?.0 ?? "range"
    startIndex = state.series.index(atTime: state.view.t(atX: q.x, plotW: layout.plotW))
  }
  override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
    guard let q = touches.first?.location(in: self), var draft, let state = chart?.state, let layout = chart?.chartLayout else { return }
    let s = state.series, t = state.view.t(atX: max(0, min(layout.plotW, q.x)), plotW: layout.plotW)
    let index = s.index(atTime: t)
    if ["target", "invalid"].contains(dragPart), let range = chart?.chartPriceRange {
      let value = pOf(q.y, pane: layout.main, range: range, mode: state.price.mode)
      if dragPart == "target" { draft.rule.target = value; draft.rule.targetEdited = true }
      else { draft.rule.invalidation = value; draft.rule.invalidationEdited = true }
    } else if dragPart == "expiry" {
      draft.rule.expires = max(ReviewClock.now + 60_000, Int64(t)); draft.rule.expiryEdited = true
    } else {
      var left = s.index(atTime: Double(draft.range.start)), right = (0..<s.count).last(where: { s.time(at: $0) < draft.range.end }) ?? s.count - 1
      if dragPart == "left" { left = min(index, max(0, right - 2)) }
      else if dragPart == "right" { right = max(index, min(s.count - 1, left + 2)) }
      else { left = min(startIndex, index); right = max(startIndex, index); if right - left < 2 { right = min(s.count - 1, left + 2); left = max(0, right - 2) } }
      draft.range.start = s.time(at: left); draft.range.end = ReviewChartBridge.closeTime(s.time(at: right), interval: s.interval); draft.range.bars = right - left + 1
      let high = s.high[left...right].max() ?? draft.rule.target, low = s.low[left...right].min() ?? draft.rule.invalidation
      if !draft.rule.targetEdited { draft.rule.target = draft.rule.direction == .short ? low : high }
      if !draft.rule.invalidationEdited { draft.rule.invalidation = draft.rule.direction == .short ? high : low }
    }
    self.draft = draft; feature?.draft = draft; setNeedsDisplay()
  }
  override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) { feature?.saveDraft(); before = nil; dragPart = "" }
  override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) { if let before { draft = before; feature?.draft = before }; self.before = nil; dragPart = ""; setNeedsDisplay() }
}
