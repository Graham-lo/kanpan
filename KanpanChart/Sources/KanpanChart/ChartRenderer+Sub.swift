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
    case .lsr, .taker, .basis: subExternal(ctx, box, L, lo, hi, key, s)
    case .oi: subOi(ctx, box, L, lo, hi, s)
    case .rsi, .srsi, .kdj, .atr, .dmi, .cvd: subLines(ctx, box, L, lo, hi, key, s)
    default: break
    }
    ctx.restoreGState()
    drawSubAxis(ctx, key: key, box: box, L: L, lo: lo, hi: hi)
    if legend { subLegend(ctx, pane: pane, key: key, plotW: L.plotW) }
  }

  private func subExternal(_ ctx: CGContext, _ box: Pane, _ L: Layout,
                           _ lo: Int, _ hi: Int, _ id: IndicatorID, _ scale: Double) {
    let values = displayed(id)?.lines.first ?? []
    if !state.externalSupported || !(lo...hi).contains(where: { values.indices.contains($0) && values[$0].isFinite }) {
      let text = !state.externalSupported ? "当前线路不提供" + id.name
        : state.external[id] == nil ? id.name + "暂无数据" : "该时段暂无" + id.name
      text.drawLeft(at: CGPoint(x: 8, y: box.y + box.h / 2),
                    font: ChartFont.notice, color: state.colors.dim)
      return
    }
    subLines(ctx, box, L, lo, hi, id, scale)
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
      let label = subValueText(value, indicator: key)
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
    ctx.setLineWidth(width)
    var pen = PolylinePen(ctx, color: Paint.cg(color), capacity: hi - lo + 1)
    for i in lo...hi where i < arr.count {
      if !arr[i].isFinite { pen.lift(); continue }
      let px = state.view.x(Double(b.time(at: i)), plotW: L.plotW)
      pen.add(CGPoint(x: px, y: subY(box, ext, arr[i])))
    }
    pen.finish()
  }

  /// RSI / StochRSI / KDJ / ATR / 动向指标：几条线加参考线。
  private func subLines(
    _ ctx: CGContext, _ box: Pane, _ L: Layout, _ lo: Int, _ hi: Int, _ key: IndicatorID, _ s: Double
  ) {
    guard let v = displayed(key) else { return }
    let t = state.colors
    let pal = t.sub
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
    // （实体 = 节距 × 2/3，两边各 节距/6），见 71bd340:docs/AICoin-安卓包-UI规格提取.md §3。
    let bodyW = Double(candlePixels(spacing: spacing, scale: s).body) / s
    // 量柱藏没藏、零线在哪、两种柱色，整帧都是同一个答案：从前写在逐根循环的 `where` 里，
    // 一屏几百根就把同一个字典查几百遍（审查 B·P3-4）。
    let barsVisible = outputVisible(.vol, displayed(.vol)?.lines.count ?? 0)
    let zero = subY(box, ext, 0)
    let cgUp = Paint.cg(t.volUp), cgDn = Paint.cg(t.volDn)
    for i in lo...hi where barsVisible {
      // 坏量（NaN / inf）不画：算出来的矩形是 NaN，CoreGraphics 要么吞掉要么报错，
      // 量轴区间（`extent`）也早就把它剔掉了，这里跟它保持同一个口径。
      let volume = b.volume[i]
      guard volume.isFinite else { continue }
      let xc = state.view.x(Double(b.time(at: i)), plotW: L.plotW)
      if xc < -4 || xc > L.plotW + 4 { continue }
      let y = subY(box, ext, volume)
      ctx.setFillColor(b.close[i] >= b.open[i] ? cgUp : cgDn)
      ctx.fill(CGRect(x: snap(xc - bodyW / 2, scale: s), y: min(y, zero), width: bodyW, height: abs(zero - y)))
    }
    if let v = displayed(.vol) {
      let pal = t.sub
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
    let pal = t.sub
    poly(ctx, box, e, L, v.lines[0], lo, hi, pal[0], width: 2 / s)
    poly(ctx, box, e, L, v.lines[1], lo, hi, pal[1], width: 2 / s)
  }

  /// 持仓量：无填充折线。
  ///
  /// 空着的时候说什么一律问 `OINotice`，这儿不自己编：从 2020-09-01 起的历史在归档站上
  /// 是全的，**没有哪个周期是「交易所不提供」**——1w / 1M / 1y 照画，1m / 3m 是一条
  /// 按五分钟走的阶梯（源的粒度就这么细）。画不出来只可能是线路不报、还没到、真没有。
  private func subOi(_ ctx: CGContext, _ box: Pane, _ L: Layout, _ lo: Int, _ hi: Int, _ s: Double) {
    let t = state.colors
    guard outputVisible(.oi, 0) else { return }
    let a = displayed(.oi)?.lines.first ?? []
    var has = false
    for i in lo...hi where i < a.count && a[i].isFinite { has = true; break }
    if !has {
      OINotice.forEmptyPane(routeSupportsOI: state.oiSupported, loaded: state.oi != nil).text
        .drawLeft(
          at: CGPoint(x: 8, y: box.y + box.h / 2),
          font: ChartFont.notice, color: t.dim)
      return
    }
    let b = state.series
    let ext = subExtent(.oi, lo: lo, hi: hi)
    ctx.setLineWidth(2 / s)
    var pen = PolylinePen(ctx, color: Paint.cg(t.oi), capacity: hi - lo + 1)
    for i in lo...hi where i < a.count {
      if !a[i].isFinite { pen.lift(); continue }
      let px = state.view.x(Double(b.time(at: i)), plotW: L.plotW)
      pen.add(CGPoint(x: px, y: subY(box, ext, a[i])))
    }
    pen.finish()

  }

  // ---------------------------------------------------------------- 图例

  /// 图例读哪一根：十字线在就读十字线那根，否则读最后一根。
  var legendIndex: Int {
    if let c = state.crosshair { return min(max(0, c.index), state.series.count - 1) }
    return state.series.count - 1
  }

  private func params(_ id: IndicatorID) -> [Int] { state.params[id] ?? id.defaultParams }

  /// 主图叠加图例：**单行**，放不下先换短称、再把尾巴收成「+N」（见 `LegendFit`）。
  func drawLegend(_ ctx: CGContext, pane: Pane, L: Layout) {
    if state.percentAxis { drawCompareLegend(ctx, pane: pane, L: L); return }
    let y = pane.y + 9
    guard y < pane.y + pane.h - 6 else { return }
    let x = LegendFit.draw(mainLegendItems(), x: 8, y: y, maxX: L.plotW - 4, more: state.colors.dim)
    drawOrderFlowLegend(ctx, pane: pane, L: L, x: x, y: y)
  }

  /// 主图叠加图例的各段（读数跟着十字线那根）。短称：每把指标第一段留个短名，后面几段只留读数（颜色认线）。
  func mainLegendItems() -> [LegendItem] {
    let t = state.colors
    let i = legendIndex
    let p = state.decimals
    var items: [LegendItem] = []
    /// 一把指标的几段：第一段能读出数的短称带名字，其余只留读数。
    func group(_ name: String, _ parts: [(full: String, value: String, color: Hex)]) {
      var named = false
      for part in parts {
        let item = LegendItem(part.full, short: named ? part.value : name + " " + part.value, color: part.color)
        if item.readable { named = true }
        items.append(item)
      }
    }
    for id in state.overlays {
      guard let v = displayed(id) else { continue }
      switch id {
      case .ma, .ema:
        group(id.name, params(id).enumerated().compactMap { k, n -> (full: String, value: String, color: Hex)? in
          guard k < v.lines.count, outputVisible(id, k) else { return nil }
          let value = indicatorNumber(reading(v.lines[k]), decimals: p)
          return ("\(id.name)\(n) " + value, value, indicatorColor(id, k))
        })
      case .boll:
        // `legendIndex` 在序列为空时是 −1，指标结果也可能比序列短一截（换品种那一拍）：
        // 裸下标会直接越界崩溃。读不到就是 NaN，`LegendItem.readable` 会把它剔掉。
        guard v.lines.count >= 3 else { break }
        let at = { (k: Int) -> String in fmtNum(v.lines[k].indices.contains(i) ? v.lines[k][i] : .nan, p) }
        group(IndicatorID.boll.name, [("上轨 " + at(1), at(1), t.band), ("中轨 " + at(0), at(0), t.amber), ("下轨 " + at(2), at(2), t.band)])
      case .vwap:
        guard let a = v.lines.first, outputVisible(id, 0) else { break }
        let value = indicatorNumber(reading(a), decimals: p)
        items.append(LegendItem(id.name + " " + value, short: id.name + " " + value, color: indicatorColor(id, 0)))
      case .supertrend, .sar:
        // 这两把的图例跟着它当前的多空走同一套涨跌色，和线上/点上看到的颜色对得上。
        guard let a = v.lines.first, outputVisible(id, 0) else { break }
        let d = v.dir.map { reading($0) } ?? .nan
        let value = indicatorNumber(reading(a), decimals: p)
        items.append(LegendItem(id.name + " " + value, short: (id == .sar ? "抛物 " : "趋势 ") + value,
                                color: d > 0 ? t.up : t.down))
      default: break
      }
    }
    // 至今涨幅挂在图例最后一段：它读的是十字线那根，和前面几段同源。
    if let (text, color) = sinceChangeChip {
      items.append(LegendItem(text, short: String(text.dropFirst(3)), color: color))
    }
    return items
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

  /// 副图图例：和主图一样**单行**，不折第二行压线；放不下先去参数、只留读数，再收「+N」。
  private func subLegend(_ ctx: CGContext, pane: Pane, key: IndicatorID, plotW: Double) {
    LegendFit.draw(subLegendItems(key), x: 8, y: pane.y + 8, maxX: plotW - 4, more: state.colors.dim)
  }

  /// 副图图例的各段。短称：标题去掉参数，读数去掉名字（颜色认线）。
  func subLegendItems(_ key: IndicatorID) -> [LegendItem] {
    let t = state.colors
    let i = legendIndex
    let pal = t.sub
    var items: [LegendItem] = []
    let put = { (full: String, short: String?, color: Hex) in items.append(LegendItem(full, short: short, color: color)) }
    let v = displayed(key)
    let at = { (a: [Double]) -> Double in reading(a) }
    let args = { (id: IndicatorID) in "(" + params(id).map(String.init).joined(separator: ",") + ")" }
    switch key {
    case .vol:
      if outputVisible(.vol, v?.lines.count ?? 0), state.series.volume.indices.contains(i) {
        let x = amountNumber(state.series.volume[i])
        put("\(IndicatorID.vol.name) " + x, "量 " + x, t.text)
      }
      if let v {
        for (k, n) in params(.vol).enumerated() where k < v.lines.count {
          let x = amountNumber(at(v.lines[k]))
          put("均量\(n) " + x, x, pal[k % pal.count])
        }
      }
    case .macd:
      put(IndicatorID.macd.name + args(.macd), IndicatorID.macd.name, t.dim)
      guard let v, let hist = v.histogram, v.lines.count >= 2 else { break }
      // MACD 三个值都是价差，量级跟着价格走：0.0033 的币种上它们在 1e-5 附近，
      // 按固定 2 位小数印出来全是 0.00。跟着品种的价格精度走才读得出东西。
      let d0 = indicatorNumber(at(v.lines[0]), decimals: state.decimals)
      let d1 = indicatorNumber(at(v.lines[1]), decimals: state.decimals)
      put("差值 " + d0, d0, pal[0])
      put("信号 " + d1, d1, pal[1])
      let h = at(hist)
      let hs = indicatorNumber(h, decimals: state.decimals)
      put("柱值 " + hs, hs, h >= 0 ? t.up : t.down)
    case .rsi:
      put("\(IndicatorID.rsi.name)(\(Int(state.rsiUpper))/\(Int(state.rsiLower)))", IndicatorID.rsi.name, t.dim)
      guard let v else { break }
      for (k, n) in params(.rsi).enumerated() where k < v.lines.count {
        let x = indicatorNumber(at(v.lines[k]), decimals: 1)
        put("\(n) " + x, x, pal[k % pal.count])
      }
    case .kdj:
      put(IndicatorID.kdj.name + args(.kdj), IndicatorID.kdj.name, t.dim)
      guard let v, v.lines.count >= 3 else { break }
      for (k, name) in ["快线", "慢线", "敏感线"].enumerated() {
        let x = indicatorNumber(at(v.lines[k]), decimals: 1)
        put(name + " " + x, x, pal[k])
      }
    case .srsi:
      put(IndicatorID.srsi.name, nil, t.dim)
      guard let v, v.lines.count >= 2 else { break }
      for (k, name) in ["快线", "慢线"].enumerated() {
        let x = indicatorNumber(at(v.lines[k]), decimals: 1)
        put(name + " " + x, x, pal[k])
      }
    case .atr:
      guard let v, let a = v.lines.first else { break }
      let x = fmtNum(at(a), state.decimals)
      put("\(IndicatorID.atr.name)\(params(.atr)[0]) " + x, "波幅 " + x, pal[0])
    case .lsr, .taker, .basis:
      put(key.name, nil, t.dim)
      if let values = v?.lines.first, reading(values).isFinite {
        put(subValueText(reading(values), indicator: key), nil, indicatorColor(key, 0))
      }
    case .dmi:
      put(IndicatorID.dmi.name + args(.dmi), IndicatorID.dmi.name, t.dim)
      guard let v, v.lines.count >= 3 else { break }
      for (k, name) in ["多头动向", "空头动向", "趋势强度"].enumerated() {
        let x = indicatorNumber(at(v.lines[k]), decimals: 1)
        put(name + " " + x, x, pal[k])
      }
    case .cvd:
      put(key.name, nil, t.dim)
      // 读数按涨跌色：为正是这一段被主动买上去的，为负是被主动卖下去的。
      if let x = (v?.lines.first).map({ at($0) }), x.isFinite {
        put(amountNumber(x), nil, x >= 0 ? t.up : t.down)
      }
    case .oi:
      let x0 = (v?.lines.first).map { at($0) }.flatMap { $0.isFinite ? amountNumber($0) : nil } ?? "--"
      put("\(IndicatorID.oi.name) " + x0, "持仓 " + x0, t.oi)

    default: break
    }
    return items
  }

  // ---------------------------------------------------------------- 画线

  func drawDrawings(_ ctx: CGContext, pane: Pane, r: PriceRange, L: Layout, scale s: Double) {
    // 关掉只是不画，`state.drawings` 一根不删——用户再打开还得在。
    guard state.options.drawings || !guestDrawings.isEmpty else { return }
    ctx.saveGState(); defer { ctx.restoreGState() }
    ctx.clip(to: CGRect(x: 0, y: pane.y, width: L.plotW, height: pane.h))
    // `decimals` 必须传：漏了就退回默认的 2 位，同一条线被底层和覆盖层画出两串
    // 不一样长的字（BTC 看不出来，PEPE 上就是「+0.00」压着「+0.0000147」）。
    let axes = DrawAxes(layout: L, pane: pane, range: r, mode: state.price.mode,
                        view: state.view, decimals: state.decimals)
    // `series` 也必须传：计算型工具（VWAP、成交量分布）的形状是从这段 K 线里算出来的，
    // 漏了它们在底层就只剩一个手柄，选中覆盖层却画得出来——一选中就多出一整块柱子。
    //
    // 没在编辑的线退后一步（`DrawPen.restAlpha`）：整批画进**一个**透明层再统一降不透明度，
    // 线与自己的填充、字叠在一起不会叠出更深的一块，几十条线也只开一层。选中的那条画满，
    // 排在最后（盖在别的线上面）；正在拖的那条底图跳过，由覆盖层整只画。
    ctx.saveGState()
    if ownDimmed { ctx.setAlpha(0.35); ctx.beginTransparencyLayer(auxiliaryInfo: nil) }
    if state.options.drawings {
      let rest = state.drawings.filter { $0.id != state.drawingPreviewID && $0.id != drawingSelected }
      paintFaded(ctx, alpha: drawingRestAlpha) {
        for d in rest { paintDrawing(d, ctx: ctx, axes: axes, colors: state.colors, series: state.series) }
      }
      if let sel = drawingSelected, sel != state.drawingPreviewID,
         let d = state.drawings.first(where: { $0.id == sel }) {
        paintDrawing(d, ctx: ctx, axes: axes, colors: state.colors, series: state.series)
      }
    }
    if ownDimmed { ctx.endTransparencyLayer() }
    ctx.restoreGState()
    paintFaded(ctx, alpha: drawingRestAlpha) {
      for d in guestDrawings {
        paintDrawing(d, ctx: ctx, axes: axes, colors: state.colors, series: state.series)
      }
    }
  }

  /// 没选中的画线此刻画多浓（系统「降低透明度」开着就是 1）。
  var drawingRestAlpha: CGFloat { reduceTransparency ? 1 : DrawPen.restAlpha }

  /// 在一只降了不透明度的透明层里画一批；`alpha == 1` 就直接画，不开层。
  func paintFaded(_ ctx: CGContext, alpha: CGFloat, _ body: () -> Void) {
    guard alpha < 1 else { body(); return }
    ctx.saveGState(); ctx.setAlpha(alpha); ctx.beginTransparencyLayer(auxiliaryInfo: nil)
    body()
    ctx.endTransparencyLayer(); ctx.restoreGState()
  }
}

extension ChartRenderer {
  /// No selection: each output's last valid sample. Selection: exact shared column, no fallback.
  func reading(_ values: [Double]) -> Double {
    if let cross = state.crosshair { return values.indices.contains(cross.index) ? values[cross.index] : .nan }
    return values.last(where: { $0.isFinite }) ?? .nan
  }
  func subValueText(_ value: Double, indicator: IndicatorID) -> String {
    if indicator == .basis { return fmtNum(value, 3) + "%" }
    // 累计成交量差和成交量、持仓量一样是「量」，按 K/M/B 印，不按小数位印。
    if indicator == .vol || indicator == .oi || indicator == .cvd { return fmtVol(value) }
    return fmtNum(value, indicator == .macd || indicator == .atr ? state.decimals : 2)
  }
  func subAxisLabels(_ id: IndicatorID) -> [String] {
    let b = visibleRange(view: state.view, series: state.series)
    let e = subExtent(id, lo: b.lo, hi: b.hi)
    return [e.lo, e.hi].map { subValueText($0, indicator: id) }
  }
}
