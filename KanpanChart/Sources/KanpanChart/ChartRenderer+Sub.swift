import CoreGraphics
import Foundation
import KanpanCore
import UIKit

/// 副图与图例，1:1 移植自 `prototype/src/chart.js` 的 `drawSub` / `drawLegend` 段。
extension ChartRenderer {
  // ---------------------------------------------------------------- 副图

  /// 副图的内框：顶上留 15pt 给图例，底下再收 4pt（原型 `inner`）。
  private func inner(_ pane: Pane) -> Pane {
    {
      let top = min(pane.h * 0.4, pane.indicator == .vol ? 30.0 : 28.0)
      let bottom = pane.indicator == .vol ? 4.0 : 8.0
      return Pane(indicator: pane.indicator, y: pane.y + top, h: max(1, pane.h - top - bottom))
    }()
  }

  func drawSub(_ ctx: CGContext, pane: Pane, L: Layout, scale s: Double, legend: Bool = true) {
    guard let key = pane.indicator else { return }
    let t = state.colors
    let (lo, hi) = visibleRange(view: state.view, series: state.series)
    ctx.hairLine(from: 0, to: L.W, y: pane.y, scale: CGFloat(s), color: Paint.cg(t.axis))

    let box = inner(pane)
    ctx.saveGState()
    ctx.beginPath()
    ctx.addRect(CGRect(x: 0, y: box.y, width: L.plotW, height: box.h))
    ctx.clip()
    switch key {
    case .vol: subVol(ctx, box, L, lo, hi, s)
    case .macd: subMacd(ctx, box, L, lo, hi, s)
    case .oi: subOi(ctx, box, L, lo, hi, s)
    case .rsi, .srsi, .kdj, .atr: subLines(ctx, box, L, lo, hi, key, s)
    default: break
    }
    ctx.restoreGState()
    drawSubAxis(ctx, key: key, box: box, L: L, lo: lo, hi: hi)
    if legend { subLegend(ctx, pane: pane, key: key, plotW: L.plotW) }
  }

  /// All subpanes share extent calculation, NaN handling, and right-axis formatting.
  private func extent(_ arrs: [[Double]], _ lo: Int, _ hi: Int,
                      guides: [Double] = []) -> (lo: Double, hi: Double) {
    var mn = guides.min() ?? .infinity, mx = guides.max() ?? -.infinity
    for a in arrs where a.count > lo {
      for i in lo...min(hi, a.count - 1) where a[i].isFinite {
        mn = min(mn, a[i]); mx = max(mx, a[i])
      }
    }
    if !mn.isFinite || !mx.isFinite { return (0, 1) }
    if mn == mx { return (mn - 0.5, mx + 0.5) }
    return (mn, mx)
  }

  private func subExtent(_ key: IndicatorID, lo: Int, hi: Int) -> (lo: Double, hi: Double) {
    let value = displayed(key)
    let lines = value?.lines ?? []
    switch key {
    case .vol: return extent((outputVisible(.vol, lines.count) ? [state.series.volume] : []) + lines, lo, hi, guides: [0])
    case .macd: return extent(lines + [value?.histogram ?? []], lo, hi, guides: [0])
    default: return extent(lines, lo, hi, guides: key == .rsi ? [] : key == .kdj ? [0, 100] : key.guides)
    }
  }

  func subCrosshairValue(y: Double, pane: Pane) -> Double {
    guard let key = pane.indicator else { return 0 }
    let bounds = visibleRange(view: state.view, series: state.series)
    let ext = subExtent(key, lo: bounds.lo, hi: bounds.hi), box = inner(pane)
    let fraction = max(0, min(1, (y - box.y) / box.h))
    return state.subInverted.contains(key) ? ext.lo + fraction * (ext.hi - ext.lo) : ext.hi - fraction * (ext.hi - ext.lo)
  }

  func subCrosshairY(value: Double, pane: Pane) -> Double {
    guard let key = pane.indicator else { return pane.y }
    let bounds = visibleRange(view: state.view, series: state.series)
    let ext = subExtent(key, lo: bounds.lo, hi: bounds.hi)
    return subY(inner(pane), ext, value)
  }

  private func drawSubAxis(_ ctx: CGContext, key: IndicatorID, box: Pane, L: Layout, lo: Int, hi: Int) {
    let ext = subExtent(key, lo: lo, hi: hi)
    let fractions = box.h < 35 ? [0.5] : box.h < 60 ? [0.0, 1.0] : [0.0, 0.5, 1.0]
    for fraction in fractions {
      let value = state.subInverted.contains(key) ? ext.lo + fraction * (ext.hi - ext.lo) : ext.hi - fraction * (ext.hi - ext.lo)
      let label = key == .vol || key == .oi ? fmtVol(value) : fmtNum(value, 2)
      let y = min(box.y + box.h - 4, max(box.y + 4, box.y + box.h * fraction))
      label.drawCentered(at: CGPoint(x: L.plotW + L.axisW / 2, y: y),
                         font: ChartFont.axis, color: state.colors.dim)
    }
  }

  private func subY(_ box: Pane, _ ext: (lo: Double, hi: Double), _ v: Double) -> Double {
    let y = yOfValue(v, pane: box, lo: ext.lo, hi: ext.hi)
    return box.indicator.map { state.subInverted.contains($0) } == true ? box.y * 2 + box.h - y : y
  }

  /// 把一条线画进副图；`NaN` 断线不连。
  private func poly(
    _ ctx: CGContext, _ box: Pane, _ ext: (lo: Double, hi: Double), _ L: Layout,
    _ arr: [Double], _ lo: Int, _ hi: Int, _ color: Hex, width: Double = 1
  ) {
    let b = state.series
    ctx.setStrokeColor(Paint.cg(color))
    ctx.setLineWidth(width)
    ctx.beginPath()
    var on = false
    for i in lo...hi where i < arr.count {
      if !arr[i].isFinite { on = false; continue }
      let px = state.view.x(Double(b.time(at: i)), plotW: L.plotW)
      let py = subY(box, ext, arr[i])
      if on { ctx.addLine(to: CGPoint(x: px, y: py)) } else { ctx.move(to: CGPoint(x: px, y: py)); on = true }
    }
    ctx.strokePath()
  }

  /// RSI / StochRSI / KDJ / ATR：几条线加参考线。
  private func subLines(
    _ ctx: CGContext, _ box: Pane, _ L: Layout, _ lo: Int, _ hi: Int, _ key: IndicatorID, _ s: Double
  ) {
    guard let v = displayed(key) else { return }
    let t = state.colors
    let pal = t.palette
    let ext = subExtent(key, lo: lo, hi: hi)
    let guides = key == .rsi ? [state.rsiLower, state.rsiUpper] : key.guides
    if key == .rsi {
      let a = subY(box, ext, state.rsiLower), b = subY(box, ext, state.rsiUpper)
      ctx.setFillColor(Paint.cg(t.band.alpha("18")))
      ctx.fill(CGRect(x: 0, y: min(a, b), width: L.plotW, height: abs(b - a)))
    }
    if !guides.isEmpty {
      ctx.saveGState()
      ctx.setLineDash(phase: 0, lengths: [2 / s, 3 / s])
      for g in guides {
        let y = subY(box, ext, g)
        if y < box.y || y > box.y + box.h { continue }
        ctx.hairLine(from: 0, to: L.plotW, y: y, scale: CGFloat(s), color: Paint.cg(t.grid))
      }
      ctx.restoreGState()
    }
    for (k, a) in v.lines.enumerated() {
      poly(ctx, box, ext, L, a, lo, hi, pal[k % pal.count], width: 2 / s)
    }
  }

  /// 成交量：柱 + 均量线。柱高从 0 起，顶到可见最大量的 1.1 倍。
  private func subVol(_ ctx: CGContext, _ box: Pane, _ L: Layout, _ lo: Int, _ hi: Int, _ s: Double) {
    let b = state.series, t = state.colors
    let ext = subExtent(.vol, lo: lo, hi: hi)
    let spacing = state.view.barSpacing(step: b.step, plotW: L.plotW)
    // 和主图蜡烛同宽：走 `candlePixels`（渲染口径），不是 `candleWidths`（原型对账口径）。
    // 后者没有「相邻两根至少留 1 个设备像素缝」的上限，捏小之后量柱会连成一堵实心墙——
    // 主图蜡烛在 37b8825 已经修掉这条，副图量柱漏了。AICoin 安卓包里量柱同样恒留缝
    // （实体 = 节距 × 2/3，两边各 节距/6），见 docs/AICoin-安卓包-UI规格提取.md §3。
    let bodyW = Double(candlePixels(spacing: spacing, scale: s).body) / s
    for i in lo...hi where outputVisible(.vol, (displayed(.vol)?.lines.count ?? 0)) {
      let xc = state.view.x(Double(b.time(at: i)), plotW: L.plotW)
      if xc < -4 || xc > L.plotW + 4 { continue }
      let y = subY(box, ext, b.volume[i])
      ctx.setFillColor(Paint.cg(b.close[i] >= b.open[i] ? t.volUp : t.volDn))
      let zero = subY(box, ext, 0)
      ctx.fill(CGRect(x: snap(xc - bodyW / 2, scale: s), y: min(y, zero), width: bodyW, height: abs(zero - y)))
    }
    if let v = displayed(.vol) {
      let pal = t.palette
      for (k, a) in v.lines.enumerated() { poly(ctx, box, ext, L, a, lo, hi, pal[k % pal.count], width: 2 / s) }
    }
  }

  /// MACD：共用蜡烛实体宽度，柱色按正负。
  /// 数值小于前柱时实心，否则空心；第一根空心。
  ///
  /// 原型 `subMacd` 画的是四色实心（涨/跌各分「继续」「转头」两档），这里是用户
  /// 2026-09-14 当面推翻原型后的新口径，记在 `docs/acceptance/M6.md`「与原型的分歧」。
  private func subMacd(_ ctx: CGContext, _ box: Pane, _ L: Layout, _ lo: Int, _ hi: Int, _ s: Double) {
    guard let v = displayed(.macd), let hist = v.histogram, v.lines.count >= 2 else { return }
    let b = state.series, t = state.colors
    let e = subExtent(.macd, lo: lo, hi: hi)
    let zero = subY(box, e, 0)
    let spacing = state.view.barSpacing(step: b.step, plotW: L.plotW)

    let cell = spacing * s
    let bw = max(1, (cell * 2 / 3).rounded()) / s
    let line = 2 / s

    for i in lo...hi where i < hist.count {
      let v0 = hist[i]
      if !v0.isFinite { continue }
      let xc = state.view.x(Double(b.time(at: i)), plotW: L.plotW)
      let y = subY(box, e, v0)
      let prev = i > 0 ? hist[i - 1] : Double.nan
      // 原始数值比较，不取绝对值。
      let solid = prev.isFinite && v0 < prev
      let col = Paint.cg(v0 >= 0 ? t.up : t.down)
      let top = snap(min(y, zero), scale: s)
      let rect = CGRect(
        x: snap(xc - bw / 2, scale: s), y: top,
        width: bw, height: max(line, snap(max(y, zero), scale: s) - top))
      // 空心：描边路径往内缩半个线宽，笔画外沿才正好压在 `rect` 上而不胖出去；
      // 缩完宽或高没了（柱只有 1 个设备像素细 / 扁）就退回实心，不然什么也画不出来。
      let stroked = rect.insetBy(dx: CGFloat(line / 2), dy: CGFloat(line / 2))
      if solid || stroked.width <= 0 || stroked.height <= 0 {
        ctx.setFillColor(col)
        ctx.fill(rect)
      } else {
        ctx.setStrokeColor(col)
        ctx.setLineWidth(line)
        ctx.stroke(stroked)
      }
    }
    ctx.hairLine(from: 0, to: L.plotW, y: zero, scale: CGFloat(s), color: Paint.cg(t.grid))
    let pal = t.palette
    poly(ctx, box, e, L, v.lines[0], lo, hi, pal[0], width: 2 / s)
    poly(ctx, box, e, L, v.lines[1], lo, hi, pal[1], width: 2 / s)
  }

  /// 持仓量：无填充折线。币安只给最近 30 天、最细 5 分钟，缺了就写清楚。
  private func subOi(_ ctx: CGContext, _ box: Pane, _ L: Layout, _ lo: Int, _ hi: Int, _ s: Double) {
    let t = state.colors
    let note = { (text: String) in
      text.drawLeft(
        at: CGPoint(x: 8, y: box.y + box.h / 2),
        font: UIFont.systemFont(ofSize: 11), color: t.dim)
    }
    guard outputVisible(.oi, 0) else { return }
    guard let v = displayed(.oi), let a = v.lines.first else {
      note("这个周期币安不提供持仓量历史（最细 5 分钟）")
      return
    }
    var has = false
    for i in lo...hi where i < a.count && a[i].isFinite { has = true; break }
    if !has {
      note(state.oi == nil ? "持仓量加载中" : "这一段暂无持仓量数据")
      return
    }
    let b = state.series
    let ext = subExtent(.oi, lo: lo, hi: hi)
    let path = CGMutablePath()
    var started = false
    for i in lo...hi where i < a.count {
      if !a[i].isFinite { started = false; continue }
      let px = state.view.x(Double(b.time(at: i)), plotW: L.plotW)
      let py = subY(box, ext, a[i])
      if started { path.addLine(to: CGPoint(x: px, y: py)) } else { path.move(to: CGPoint(x: px, y: py)); started = true }
    }
    ctx.addPath(path)
    ctx.setStrokeColor(Paint.cg(t.oi))
    ctx.setLineWidth(2 / s)
    ctx.strokePath()

  }

  // ---------------------------------------------------------------- 图例

  /// 图例读哪一根：十字线在就读十字线那根，否则读最后一根。
  var legendIndex: Int {
    if let c = state.crosshair { return min(max(0, c.index), state.series.count - 1) }
    return state.series.count - 1
  }

  private func params(_ id: IndicatorID) -> [Int] { state.params[id] ?? id.defaultParams }

  func drawLegend(_ ctx: CGContext, pane: Pane, L: Layout) {
    let t = state.colors
    let i = legendIndex
    let p = state.decimals
    var x = 8.0
    var y = pane.y + 9
    let put = { (text: String, color: Hex) in
      guard !text.contains("NaN"), !text.contains("--") else { return }
      if x + Double(text.width(ChartFont.axis)) > L.plotW - 4 { x = 8; y += 12 }
      guard y < pane.y + min(pane.h - 6, mainLegendInset(plotW: L.plotW) - 4) else { return }
      text.drawLeft(at: CGPoint(x: x, y: y), font: ChartFont.axis, color: color)
      x += Double(text.width(ChartFont.axis)) + 8
    }
    for id in state.overlays {
      guard let v = displayed(id) else { continue }
      switch id {
      case .ma, .ema:
        for (k, n) in params(id).enumerated() where k < v.lines.count && outputVisible(id, k) {
          put("\(id.rawValue)\(n) " + indicatorNumber(reading(v.lines[k]), decimals: p), indicatorColor(id, k))
        }
      case .boll:
        guard v.lines.count >= 3 else { break }
        put("UP " + fmtNum(v.lines[1][i], p), t.band)
        put("MB " + fmtNum(v.lines[0][i], p), t.amber)
        put("DN " + fmtNum(v.lines[2][i], p), t.band)
      default: break
      }
    }
    // 至今涨幅挂在图例最后一段：它读的是十字线那根，和前面几段同源。
    if let (text, color) = sinceChangeChip { put(text, color) }
  }

  /// 「至今涨幅」那一段：从十字线那根的收盘到**最新一根**收盘的涨跌幅。
  ///
  /// 十字线关掉就没有——不开十字线时 `legendIndex` 本来就是最后一根，报「至今 +0.00%」
  /// 是废话。颜色走 `colors.up` / `colors.down`，所以「红涨绿跌」那个开关照样管得住它。
  ///
  /// 用真实收盘价算，平均 K 线开着也一样：平滑后的价拿来报涨幅会和详情、报警对不上。
  var sinceChangeChip: (text: String, color: Hex)? {
    guard state.options.sinceChange, state.crosshair != nil else { return nil }
    let b = state.series
    let i = legendIndex
    guard b.count > 0, i >= 0, i < b.count else { return nil }
    let from = b.close[i], to = b.close[b.count - 1]
    guard from.isFinite, to.isFinite, from != 0 else { return nil }
    let pct = (to / from - 1) * 100
    let t = state.colors
    return ("至今 " + (pct >= 0 ? "+" : "") + toFixed(pct, 2) + "%", pct >= 0 ? t.up : t.down)
  }

  /// 只画图例（主图 + 各副图），给 `crossLayer` 用。顺序和 `draw` 里一致。
  func drawLegends(_ ctx: CGContext, L: Layout) {
    for k in 1..<L.panes.count {
      guard let key = L.panes[k].indicator else { continue }
      subLegend(ctx, pane: L.panes[k], key: key, plotW: L.plotW)
    }
    drawLegend(ctx, pane: L.main, L: L)
  }

  private func subLegend(_ ctx: CGContext, pane: Pane, key: IndicatorID, plotW: Double) {
    let t = state.colors
    let i = legendIndex
    let pal = t.palette
    var x = 8.0
    var y = pane.y + 8
    let put = { (text: String, color: Hex) in
      guard !text.contains("NaN"), !text.contains("--") else { return }
      if x + Double(text.width(ChartFont.axis)) > plotW - 4 { x = 8; y += 11 }
      guard y < pane.y + (key == .vol ? 24 : 26) else { return }
      text.drawLeft(at: CGPoint(x: x, y: y), font: ChartFont.axis, color: color)
      x += Double(text.width(ChartFont.axis)) + 8
    }
    let v = displayed(key)
    let at = { (a: [Double]) -> Double in reading(a) }
    switch key {
    case .vol:
      if outputVisible(.vol, v?.lines.count ?? 0) { put("VOL " + indicatorNumber(state.series.volume[i]), t.text) }
      if let v {
        for (k, n) in params(.vol).enumerated() where k < v.lines.count {
          put("MA\(n) " + indicatorNumber(at(v.lines[k])), pal[k % pal.count])
        }
      }
    case .macd:
      put("MACD(" + params(.macd).map(String.init).joined(separator: ",") + ")", t.dim)
      guard let v, let hist = v.histogram, v.lines.count >= 2 else { break }
      put("DIF " + indicatorNumber(at(v.lines[0])), pal[0])
      put("DEA " + indicatorNumber(at(v.lines[1])), pal[1])
      let h = at(hist)
      put("M " + indicatorNumber(h), h >= 0 ? t.up : t.down)
    case .rsi:
      put("RSI(\(Int(state.rsiUpper))/\(Int(state.rsiLower)))", t.dim)
      guard let v else { break }
      for (k, n) in params(.rsi).enumerated() where k < v.lines.count {
        put("\(n) " + indicatorNumber(at(v.lines[k]), decimals: 1), pal[k % pal.count])
      }
    case .kdj:
      put("KDJ(" + params(.kdj).map(String.init).joined(separator: ",") + ")", t.dim)
      guard let v, v.lines.count >= 3 else { break }
      put("K " + indicatorNumber(at(v.lines[0]), decimals: 1), pal[0])
      put("D " + indicatorNumber(at(v.lines[1]), decimals: 1), pal[1])
      put("J " + indicatorNumber(at(v.lines[2]), decimals: 1), pal[2])
    case .srsi:
      put("StochRSI", t.dim)
      guard let v, v.lines.count >= 2 else { break }
      put("K " + indicatorNumber(at(v.lines[0]), decimals: 1), pal[0])
      put("D " + indicatorNumber(at(v.lines[1]), decimals: 1), pal[1])
    case .atr:
      guard let v, let a = v.lines.first else { break }
      put("ATR\(params(.atr)[0]) " + fmtNum(at(a), state.decimals), pal[0])
    case .oi:
      let x0 = (v?.lines.first).map { at($0) }.flatMap { $0.isFinite ? indicatorNumber($0) : nil } ?? "--"
      put("持仓量 " + x0, t.oi)

    default: break
    }
  }

  // ---------------------------------------------------------------- 画线

  func drawDrawings(_ ctx: CGContext, pane: Pane, r: PriceRange, L: Layout, scale s: Double) {
    // 关掉只是不画，`state.drawings` 一根不删——用户再打开还得在。
    guard state.options.drawings else { return }
    ctx.saveGState(); defer { ctx.restoreGState() }
    ctx.clip(to: CGRect(x: 0, y: pane.y, width: L.plotW, height: pane.h))
    let axes = DrawAxes(layout: L, pane: pane, range: r, mode: state.price.mode, view: state.view)
    for d in state.drawings where d.id != state.drawingPreviewID { paintDrawing(d, ctx: ctx, axes: axes, colors: state.colors) }
  }
}

extension ChartRenderer {
  /// No selection: each output's last valid sample. Selection: exact shared column, no fallback.
  func reading(_ values: [Double]) -> Double {
    if let cross = state.crosshair { return values.indices.contains(cross.index) ? values[cross.index] : .nan }
    return values.last(where: { $0.isFinite }) ?? .nan
  }
  func subAxisLabels(_ id: IndicatorID) -> [String] {
    let b = visibleRange(view: state.view, series: state.series)
    let e = subExtent(id, lo: b.lo, hi: b.hi)
    return [e.lo, e.hi].map { id == .vol || id == .oi ? fmtVol($0) : fmtNum($0, 2) }
  }
}
