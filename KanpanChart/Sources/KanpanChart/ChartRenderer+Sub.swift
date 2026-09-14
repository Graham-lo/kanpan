import CoreGraphics
import Foundation
import KanpanCore
import UIKit

/// 副图与图例，1:1 移植自 `prototype/src/chart.js` 的 `drawSub` / `drawLegend` 段。
extension ChartRenderer {
  // ---------------------------------------------------------------- 副图

  /// 副图的内框：顶上留 15pt 给图例，底下再收 4pt（原型 `inner`）。
  private func inner(_ pane: Pane) -> Pane {
    Pane(indicator: pane.indicator, y: pane.y + 15, h: pane.h - 19)
  }

  func drawSub(_ ctx: CGContext, pane: Pane, L: Layout, scale s: Double, legend: Bool = true) {
    guard let key = pane.indicator else { return }
    let t = state.colors
    let (lo, hi) = visibleRange(view: state.view, series: state.series)
    ctx.hairLine(from: 0, to: L.W, y: pane.y, scale: CGFloat(s), color: Paint.cg(t.axis))

    let box = inner(pane)
    ctx.saveGState()
    ctx.beginPath()
    ctx.addRect(CGRect(x: 0, y: pane.y + 1, width: L.plotW, height: pane.h - 1))
    ctx.clip()
    switch key {
    case .vol: subVol(ctx, box, L, lo, hi, s)
    case .macd: subMacd(ctx, box, L, lo, hi, s)
    case .oi: subOi(ctx, box, L, lo, hi, s)
    case .rsi, .srsi, .kdj, .atr: subLines(ctx, box, L, lo, hi, key, s)
    default: break
    }
    ctx.restoreGState()
    if legend { subLegend(ctx, pane: pane, key: key) }
  }

  /// 可见段的上下界，自适应时上下各留 10%（原型 `extent`）。
  private func extent(_ arrs: [[Double]], _ lo: Int, _ hi: Int, fixed: (lo: Double, hi: Double)?)
    -> (lo: Double, hi: Double)
  {
    if let f = fixed { return f }
    var mn = Double.infinity, mx = -Double.infinity
    for a in arrs {
      for i in lo...hi where i < a.count && a[i].isFinite {
        if a[i] > mx { mx = a[i] }
        if a[i] < mn { mn = a[i] }
      }
    }
    if !mn.isFinite { mn = 0; mx = 1 }
    if mn == mx { mx = mn + 1 }
    let pad = (mx - mn) * 0.1
    return (mn - pad, mx + pad)
  }

  private func subY(_ box: Pane, _ ext: (lo: Double, hi: Double), _ v: Double) -> Double {
    yOfValue(v, pane: box, lo: ext.lo, hi: ext.hi)
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
    guard let v = engine[key] else { return }
    let t = state.colors
    let pal = t.palette
    let ext = extent(v.lines, lo, hi, fixed: key.fixedScale)
    let guides = key.guides
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
      poly(ctx, box, ext, L, a, lo, hi, pal[k % pal.count])
    }
  }

  /// 成交量：柱 + 均量线。柱高从 0 起，顶到可见最大量的 1.1 倍。
  private func subVol(_ ctx: CGContext, _ box: Pane, _ L: Layout, _ lo: Int, _ hi: Int, _ s: Double) {
    let b = state.series, t = state.colors
    var mx = 0.0
    for i in lo...hi where b.volume[i] > mx { mx = b.volume[i] }
    if mx <= 0 { mx = 1 }
    let ext = (lo: 0.0, hi: mx * 1.1)
    let spacing = state.view.barSpacing(step: b.step, plotW: L.plotW)
    // 和主图蜡烛同宽：走 `candlePixels`（渲染口径），不是 `candleWidths`（原型对账口径）。
    // 后者没有「相邻两根至少留 1 个设备像素缝」的上限，捏小之后量柱会连成一堵实心墙——
    // 主图蜡烛在 37b8825 已经修掉这条，副图量柱漏了。AICoin 安卓包里量柱同样恒留缝
    // （实体 = 节距 × 2/3，两边各 节距/6），见 docs/AICoin-安卓包-UI规格提取.md §3。
    let bodyW = Double(candlePixels(spacing: spacing, scale: s, style: state.style).body) / s
    for i in lo...hi {
      let xc = state.view.x(Double(b.time(at: i)), plotW: L.plotW)
      if xc < -4 || xc > L.plotW + 4 { continue }
      let y = subY(box, ext, b.volume[i])
      ctx.setFillColor(Paint.cg(b.close[i] >= b.open[i] ? t.volUp : t.volDn))
      ctx.fill(CGRect(x: snap(xc - bodyW / 2, scale: s), y: y, width: bodyW, height: box.y + box.h - y))
    }
    if let v = engine[.vol] {
      let pal = t.palette
      for (k, a) in v.lines.enumerated() { poly(ctx, box, ext, L, a, lo, hi, pal[k % pal.count]) }
    }
  }

  /// MACD：柱对称压在零轴两侧。样式参照 AICoin——柱比蜡烛实体细一半、柱间留缝，
  /// 颜色只表示正负（跟着「红涨绿跌」走），**动能变强实心、动能变弱只描边**。
  ///
  /// 原型 `subMacd` 画的是四色实心（涨/跌各分「继续」「转头」两档），这里是用户
  /// 2026-09-14 当面推翻原型后的新口径，记在 `docs/acceptance/M6.md`「与原型的分歧」。
  private func subMacd(_ ctx: CGContext, _ box: Pane, _ L: Layout, _ lo: Int, _ hi: Int, _ s: Double) {
    guard let v = engine[.macd], let hist = v.histogram, v.lines.count >= 2 else { return }
    let b = state.series, t = state.colors
    let raw = extent([v.lines[0], v.lines[1], hist], lo, hi, fixed: nil)
    let span = max(abs(raw.lo), abs(raw.hi))
    let e = (lo: -span, hi: span)
    let zero = subY(box, e, 0)
    let spacing = state.view.barSpacing(step: b.step, plotW: L.plotW)

    // 柱宽取整数个设备像素，三条同时管着：
    //   ① 目标是蜡烛实体宽的一半（按 `candlePixels` 的**实画**宽度算，不是原型对账口径）；
    //   ② 上限 `floor(根间距 × scale) - 1`——`snap` 之后相邻两根左沿最少差
    //      `floor(spacing × s)` 个像素，减 1 就保证缝至少留得出 1 个设备像素；
    //   ③ 下限 1 个设备像素，挤到留不出缝时宁可贴着也不能让柱消失。
    let bodyPx = Double(candlePixels(spacing: spacing, scale: s, style: state.style).body)
    let barPx = max(1, min((bodyPx / 2).rounded(), (spacing * s).rounded(.down) - 1))
    let bw = barPx / s
    let line = 1 / s  // 空心柱的描边：1 个设备像素

    for i in lo...hi where i < hist.count {
      let v0 = hist[i]
      if !v0.isFinite { continue }
      let xc = state.view.x(Double(b.time(at: i)), plotW: L.plotW)
      let y = subY(box, e, v0)
      let prev = i > 0 ? hist[i - 1] : Double.nan
      // 动能：绝对值比前一根大就实心，比前一根小就空心。第一根没有前一根，按实心。
      let solid = !prev.isFinite || abs(v0) >= abs(prev)
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
    poly(ctx, box, e, L, v.lines[0], lo, hi, pal[0])
    poly(ctx, box, e, L, v.lines[1], lo, hi, pal[1])
  }

  /// 持仓量：一条线加一层渐变填充。币安只给最近 30 天、最细 5 分钟，缺了就写清楚。
  private func subOi(_ ctx: CGContext, _ box: Pane, _ L: Layout, _ lo: Int, _ hi: Int, _ s: Double) {
    let t = state.colors
    let note = { (text: String) in
      text.drawLeft(
        at: CGPoint(x: 8, y: box.y + box.h / 2),
        font: UIFont.systemFont(ofSize: 11), color: t.dim)
    }
    guard let v = engine[.oi], let a = v.lines.first else {
      note("这个周期币安不提供持仓量历史（最细 5 分钟）")
      return
    }
    var has = false
    for i in lo...hi where i < a.count && a[i].isFinite { has = true; break }
    if !has {
      note("这一段没有持仓量：币安只保留最近 30 天")
      return
    }
    let b = state.series
    let ext = extent([a], lo, hi, fixed: nil)
    let path = CGMutablePath()
    var started = false
    var lastX = 0.0
    for i in lo...hi where i < a.count {
      if !a[i].isFinite { continue }
      let px = state.view.x(Double(b.time(at: i)), plotW: L.plotW)
      let py = subY(box, ext, a[i])
      if started { path.addLine(to: CGPoint(x: px, y: py)) } else { path.move(to: CGPoint(x: px, y: py)); started = true }
      lastX = px
    }
    ctx.addPath(path)
    ctx.setStrokeColor(Paint.cg(t.oi))
    ctx.setLineWidth(1.2)
    ctx.strokePath()

    // 填充：把折线封到底边再刷一层从上到下透明的渐变
    let fill = path.mutableCopy()!
    fill.addLine(to: CGPoint(x: lastX, y: box.y + box.h))
    fill.addLine(to: CGPoint(x: state.view.x(Double(b.time(at: lo)), plotW: L.plotW), y: box.y + box.h))
    fill.closeSubpath()
    ctx.saveGState()
    ctx.addPath(fill)
    ctx.clip()
    let cs = CGColorSpaceCreateDeviceRGB()
    if let g = CGGradient(
      colorsSpace: cs,
      colors: [Paint.cg(t.oiFill), Paint.cg(t.oi.alpha("00"))] as CFArray,
      locations: [0, 1])
    {
      ctx.drawLinearGradient(
        g, start: CGPoint(x: 0, y: box.y), end: CGPoint(x: 0, y: box.y + box.h), options: [])
    }
    ctx.restoreGState()
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
    let pal = t.palette
    var x = 8.0
    let y = pane.y + 11
    let put = { (text: String, color: Hex) in
      text.drawLeft(at: CGPoint(x: x, y: y), font: ChartFont.axis, color: color)
      x += Double(text.width(ChartFont.axis)) + 8
    }
    for id in state.overlays {
      guard let v = engine[id] else { continue }
      switch id {
      case .ma, .ema:
        let off = id == .ema ? 3 : 0
        for (k, n) in params(id).enumerated() where k < v.lines.count {
          put("\(id.rawValue)\(n) " + fmtNum(v.lines[k][i], p), pal[(k + off) % pal.count])
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
      subLegend(ctx, pane: L.panes[k], key: key)
    }
    drawLegend(ctx, pane: L.main, L: L)
  }

  private func subLegend(_ ctx: CGContext, pane: Pane, key: IndicatorID) {
    let t = state.colors
    let i = legendIndex
    let pal = t.palette
    var x = 8.0
    let y = pane.y + 9
    let put = { (text: String, color: Hex) in
      text.drawLeft(at: CGPoint(x: x, y: y), font: ChartFont.axis, color: color)
      x += Double(text.width(ChartFont.axis)) + 8
    }
    let v = engine[key]
    let at = { (a: [Double]) -> Double in i < a.count ? a[i] : .nan }
    switch key {
    case .vol:
      put("VOL " + fmtVol(state.series.volume[i]), t.text)
      if let v {
        for (k, n) in params(.vol).enumerated() where k < v.lines.count {
          put("MA\(n) " + fmtVol(at(v.lines[k])), pal[k % pal.count])
        }
      }
    case .macd:
      put("MACD(" + params(.macd).map(String.init).joined(separator: ",") + ")", t.dim)
      guard let v, let hist = v.histogram, v.lines.count >= 2 else { break }
      put("DIF " + fmtNum(at(v.lines[0]), 2), pal[0])
      put("DEA " + fmtNum(at(v.lines[1]), 2), pal[1])
      let h = at(hist)
      put("M " + fmtNum(h, 2), h >= 0 ? t.up : t.down)
    case .rsi:
      put("RSI", t.dim)
      guard let v else { break }
      for (k, n) in params(.rsi).enumerated() where k < v.lines.count {
        put("\(n) " + fmtNum(at(v.lines[k]), 1), pal[k % pal.count])
      }
    case .kdj:
      put("KDJ(" + params(.kdj).map(String.init).joined(separator: ",") + ")", t.dim)
      guard let v, v.lines.count >= 3 else { break }
      put("K " + fmtNum(at(v.lines[0]), 1), pal[0])
      put("D " + fmtNum(at(v.lines[1]), 1), pal[1])
      put("J " + fmtNum(at(v.lines[2]), 1), pal[2])
    case .srsi:
      put("StochRSI", t.dim)
      guard let v, v.lines.count >= 2 else { break }
      put("K " + fmtNum(at(v.lines[0]), 1), pal[0])
      put("D " + fmtNum(at(v.lines[1]), 1), pal[1])
    case .atr:
      guard let v, let a = v.lines.first else { break }
      put("ATR\(params(.atr)[0]) " + fmtNum(at(a), state.decimals), pal[0])
    case .oi:
      let x0 = (v?.lines.first).map { at($0) }.flatMap { $0.isFinite ? fmtVol($0) : nil } ?? "--"
      put("持仓量 " + x0, t.oi)
      put("币安 · 近 30 天", t.dim)
    default: break
    }
  }

  // ---------------------------------------------------------------- 画线

  func drawDrawings(_ ctx: CGContext, pane: Pane, r: PriceRange, L: Layout, scale s: Double) {
    // 关掉只是不画，`state.drawings` 一根不删——用户再打开还得在。
    guard state.options.drawings else { return }
    let t = state.colors
    for d in state.drawings {
      // 选中态（amber + 1.8pt）是 M5 的事，M3 只画静态的那一档
      let col = d.color ?? t.band
      ctx.setStrokeColor(Paint.cg(col))
      ctx.setLineWidth(1.3)
      ctx.setLineDash(phase: 0, lengths: [])
      if d.kind == .hline {
        let y = KanpanCore.yOf(d.a.p, pane: pane, range: r, mode: state.price.mode)
        ctx.beginPath()
        ctx.move(to: CGPoint(x: 0, y: y))
        ctx.addLine(to: CGPoint(x: L.plotW, y: y))
        ctx.strokePath()
        let label = fmtNum(d.a.p, state.decimals)
        label.drawRightBottom(
          at: CGPoint(x: L.plotW - 4, y: y - 3), font: ChartFont.axis, color: col)
      } else if let b = d.b {
        let x1 = state.view.x(d.a.t, plotW: L.plotW)
        let y1 = KanpanCore.yOf(d.a.p, pane: pane, range: r, mode: state.price.mode)
        let x2 = state.view.x(b.t, plotW: L.plotW)
        let y2 = KanpanCore.yOf(b.p, pane: pane, range: r, mode: state.price.mode)
        ctx.beginPath()
        ctx.move(to: CGPoint(x: x1, y: y1))
        ctx.addLine(to: CGPoint(x: x2, y: y2))
        ctx.strokePath()
      }
    }
  }
}
