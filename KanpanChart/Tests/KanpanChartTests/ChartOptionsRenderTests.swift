import CoreGraphics
import Foundation
import KanpanCore
import Testing
import UIKit

@testable import KanpanChart

/// K 线设置的各档开关在渲染器这一侧真的生效（M6）。
///
/// 全部走探针而不是取样像素：这些开关改的是几何与有无，探针比图像稳，也不依赖模拟器的
/// 字体渲染。像素级的事交给 A3.11 的基线。
@MainActor
@Suite("K线设置·渲染")
struct ChartOptionsRenderTests {
  static let dev = Evidence.geometryDevice
  static var size: CGSize { dev.size }
  static var scale: CGFloat { CGFloat(dev.scale) }

  static func state(_ mutate: (inout ChartOptions) -> Void = { _ in },
                    crosshair: Crosshair? = nil) -> ChartState {
    var st = Evidence.state(dark: false, size: size, crosshair: crosshair)
    mutate(&st.options)
    return st
  }

  // ---------------------------------------------------------------- 默认档

  /// 这个套件的地基：`ChartOptions()` 不能改变任何一个探针数字。
  @Test("默认档不动任何几何")
  func defaultsAreInert() {
    let base = Evidence.state(dark: false, size: Self.size)
    var same = base
    same.options = ChartOptions()
    let a = ChartRenderer(state: base).probe(size: Self.size, scale: Self.scale)
    let b = ChartRenderer(state: same).probe(size: Self.size, scale: Self.scale)
    #expect(a == b, "aicoin 默认档漂了")
  }

  // ---------------------------------------------------------------- 网格

  /// `effectiveGrid`：`.style` 跟 AICoin 底座（无网格），另两档强制。竖细线数量是最直观的观测量。
  @Test("网格三档")
  func gridChoice() {
    #expect(Self.state({ $0.grid = .style }).effectiveGrid == .none)
    #expect(Self.state({ $0.grid = .on }).effectiveGrid == .both)
    #expect(Self.state({ $0.grid = .off }).effectiveGrid == .none)
    // 隐藏档下只剩价格轴那一条分隔线；显示档一定更多。
    let off = ChartRenderer(state: Self.state { $0.grid = .off })
      .verticalHairlineXs(size: Self.size, scale: Self.scale)
    let on = ChartRenderer(state: Self.state { $0.grid = .on })
      .verticalHairlineXs(size: Self.size, scale: Self.scale)
    #expect(off.count == 1, "隐藏档还画了 \(off.count) 条竖线")
    #expect(on.count > off.count, "显示档没多出时间网格线")
  }

  // ---------------------------------------------------------------- 实体

  @Test("实体两档")
  func bodyChoice() {
    #expect(Self.state({ $0.body = .solid }).effectiveShape == .solid)
    #expect(Self.state({ $0.body = .hollowUp }).effectiveShape == .hollowUp)
    // 选了「实心」就该一根空心都不剩。原来这儿用的是造型自己说全空心的那款「描」，
    // 风格表收成 AICoin 一套之后（见 `CandleStyle`）没有那种造型了，直接用默认这套验。
    let forced = ChartRenderer(state: Self.state({ $0.body = .solid }))
      .candleXs(size: Self.size, scale: Self.scale)
    #expect(!forced.isEmpty)
    #expect(forced.allSatisfy { !$0.hollow }, "强制实心还有空心实体")

    // 强制阳线空心：阳线空、阴线实（够胖的那些）。
    let hollow = ChartRenderer(state: Self.state({ $0.body = .hollowUp }))
      .candleXs(size: Self.size, scale: Self.scale)
    #expect(hollow.contains { $0.up && $0.hollow }, "阳线没空心")
    #expect(hollow.allSatisfy { $0.up || !$0.hollow }, "阴线也空心了")
  }

  // ---------------------------------------------------------------- 实时价格线

  @Test("实时价格线开关")
  func lastLineToggle() {
    let on = ChartRenderer(state: Self.state { $0.lastLine = true })
    let off = ChartRenderer(state: Self.state { $0.lastLine = false })
    #expect(on.lastPriceY(size: Self.size) != nil)
    #expect(off.lastPriceY(size: Self.size) == nil, "关掉了还报最新价位置")
  }

  // ---------------------------------------------------------------- 画线

  /// 关掉只是不画，数据一根不删；顺带：看不见的线不许再把价格区间撑开。
  @Test("画线开关不删数据，也不再撑价格区间")
  func drawingsToggle() {
    var st = Evidence.state(dark: false, size: Self.size)
    let far = st.series.high.max()! * 3
    st.drawings = [Drawing(kind: .hline, a: DrawPoint(t: Double(st.series.lastTime), p: far))]

    var off = st
    off.options.drawings = false
    let rOn = ChartRenderer(state: st).probe(size: Self.size, scale: Self.scale)
    let rOff = ChartRenderer(state: off).probe(size: Self.size, scale: Self.scale)
    #expect(rOn.rangeHi == rOff.rangeHi, "画线显示开关不能改变自动价格范围")
    #expect(rOff.rangeHi < far, "隐藏的画线还在撑价格区间")
    #expect(off.drawings.count == 1, "关显示把数据删了")

    // 没有画线时这个开关不该改变任何东西。
    var plain = Evidence.state(dark: false, size: Self.size)
    plain.options.drawings = false
    let base = Evidence.state(dark: false, size: Self.size)
    #expect(ChartRenderer(state: plain).probe(size: Self.size, scale: Self.scale)
      == ChartRenderer(state: base).probe(size: Self.size, scale: Self.scale))
  }

  // ---------------------------------------------------------------- 至今涨幅

  @Test("至今涨幅：数值、符号、配色")
  func sinceChange() {
    let b = Fixture.series
    let last = b.count - 1
    let i = last - 30

    // 开关关着：没有这一段。
    #expect(ChartRenderer(state: Self.state(crosshair: Crosshair(index: i))).sinceChangeChip == nil)
    // 十字线没开：也没有（不然就是「至今 +0.00%」这种废话）。
    #expect(ChartRenderer(state: Self.state { $0.sinceChange = true }).sinceChangeChip == nil)

    let st = Self.state({ $0.sinceChange = true }, crosshair: Crosshair(index: i))
    let chip = ChartRenderer(state: st).sinceChangeChip
    let pct = (b.close[last] / b.close[i] - 1) * 100
    #expect(chip?.text == "至今 " + (pct >= 0 ? "+" : "") + toFixed(pct, 2) + "%")
    #expect(chip?.color == (pct >= 0 ? st.colors.up : st.colors.down))
    #expect(chip!.text.hasPrefix("至今 "))

    // 「红涨绿跌」开关照样管得住它：配色换了，这一段的颜色也得跟着换。
    var red = st
    red.redUp = true
    let redChip = ChartRenderer(state: red).sinceChangeChip
    #expect(redChip?.text == chip?.text, "换配色不该改数值")
    #expect(redChip?.color != chip?.color, "红涨绿跌没管住至今涨幅")

    // 停在最后一根：涨幅必然是 0。
    let zero = ChartRenderer(
      state: Self.state({ $0.sinceChange = true }, crosshair: Crosshair(index: last)))
    #expect(zero.sinceChangeChip?.text == "至今 +0.00%")
  }

  // ---------------------------------------------------------------- 倒计时

  @Test("倒计时文案跟着 nowMs 走")
  func countdown() {
    var st = Evidence.state(dark: false, size: Self.size)
    st.options.countdown = true
    let b = st.series
    let close = Double(b.time(at: b.count - 1)) + Double(b.step)

    st.nowMs = close - 90_000
    #expect(ChartRenderer(state: st).countdownText(now: st.nowMs!) == "01:30")
    st.nowMs = close - 3_600_000
    #expect(ChartRenderer(state: st).countdownText(now: st.nowMs!) == "1:00:00")
    // 收盘时刻已过：什么都不画。
    #expect(ChartRenderer(state: st).countdownText(now: close) == nil)
    #expect(ChartRenderer(state: st).countdownText(now: close + 1) == nil)
  }

  /// `nowMs == nil` 时整帧必须和倒计时关着一模一样——`ChartState` 是纯值，
  /// 同一份 state 必须给同一张图，时间只能从外面喂进来。
  @Test("nowMs 为空时不影响任何几何")
  func countdownNeedsNow() {
    var st = Evidence.state(dark: false, size: Self.size)
    st.options.countdown = true
    #expect(st.nowMs == nil)
    let base = Evidence.state(dark: false, size: Self.size)
    #expect(ChartRenderer(state: st).probe(size: Self.size, scale: Self.scale)
      == ChartRenderer(state: base).probe(size: Self.size, scale: Self.scale))
  }

  // ---------------------------------------------------------------- 平均 K 线

  @Test("平均K线改蜡烛，不改指标与最新价")
  func heikinAffectsCandlesOnly() {
    let real = Evidence.state(dark: false, size: Self.size)
    var ha = real
    ha.options.kind = .heikin

    let rr = ChartRenderer(state: real), rh = ChartRenderer(state: ha)
    #expect(rr.heikin == nil, "默认档不该算平均 K 线（热路径要零开销）")
    #expect(rh.heikin != nil)

    // 蜡烛的几何变了。
    let cr = rr.candleXs(size: Self.size, scale: Self.scale)
    let ch = rh.candleXs(size: Self.size, scale: Self.scale)
    #expect(cr.count == ch.count)
    #expect(zip(cr, ch).contains { $0.bodyTop != $1.bodyTop || $0.bodyHeight != $1.bodyHeight },
            "开了平均 K 线蜡烛一点没变")
    // 横向位置一根都不许动：只换画法，不换坐标。
    #expect(zip(cr, ch).allSatisfy { $0.center == $1.center && $0.bodyLeft == $1.bodyLeft })

    // 最新价线读真实收盘：位置只可能因为价格区间被 hh/hl 撑开而变，涨跌方向不变。
    #expect(rr.lastPriceY(size: Self.size)?.up == rh.lastPriceY(size: Self.size)?.up)

    // 图例里的 MA 读真实价：文案完全一样。
    #expect(rr.legendIndex == rh.legendIndex)
  }

  /// `hh` / `hl` 必须并进价格区间，否则平均 K 线的上下影会被裁掉一截。
  @Test("平均K线的极值进得了价格区间")
  func heikinExtremesInRange() {
    var ha = Evidence.state(dark: false, size: Self.size)
    ha.options.kind = .heikin
    let r = ChartRenderer(state: ha)
    let p = r.probe(size: Self.size, scale: Self.scale)
    let slice = r.heikin!
    let lo = max(0, p.visibleLo - slice.lo), hi = min(slice.high.count - 1, p.visibleHi - slice.lo)
    #expect(hi >= lo)
    for k in lo...hi {
      #expect(slice.high[k] <= p.rangeHi + 1e-9, "第 \(k) 根上影被裁了")
      #expect(slice.low[k] >= p.rangeLo - 1e-9, "第 \(k) 根下影被裁了")
    }
  }

  // ---------------------------------------------------------------- 收盘价

  /// P2.17「收盘价」画法：主图没有一根蜡烛，只有一条 `up` 色的收盘价折线；
  /// 指标、图例读数、最新价胶囊照旧；价格区间按收盘价收窄。
  @Test("收盘价画法：只画收盘折线，指标与最新价照旧")
  func lineDrawsClosesOnly() {
    let real = Evidence.state(dark: false, size: Self.size)
    var ln = real
    ln.options.kind = .line
    let rr = ChartRenderer(state: real), rl = ChartRenderer(state: ln)
    #expect(rl.heikin == nil, "收盘价画法不该算平均 K 线")
    #expect(!rr.candleXs(size: Self.size, scale: Self.scale).isEmpty)
    #expect(rl.candleXs(size: Self.size, scale: Self.scale).isEmpty, "收盘价画法不该有蜡烛")

    // 价格区间只按收盘撑：可见收盘全在区间里，而且比蜡烛档窄。
    let pr = rr.probe(size: Self.size, scale: Self.scale)
    let pl = rl.probe(size: Self.size, scale: Self.scale)
    #expect(pl.rangeHi - pl.rangeLo < pr.rangeHi - pr.rangeLo, "收盘价档没按收盘收窄区间")
    let b = ln.series
    for i in pl.visibleLo...pl.visibleHi {
      #expect(b.close[i] >= pl.rangeLo && b.close[i] <= pl.rangeHi, "第 \(i) 根收盘掉出区间")
    }
    // 横向坐标一根不动。
    #expect(pl.spacing == pr.spacing && pl.viewFrom == pr.viewFrom && pl.viewTo == pr.viewTo)

    // 最新价胶囊照常：还在主图里，涨跌方向读真实开收。
    #expect(rl.lastPriceY(size: Self.size) != nil, "收盘价画法把最新价胶囊弄丢了")
    #expect(rr.lastPriceY(size: Self.size)?.up == rl.lastPriceY(size: Self.size)?.up)
    // 图例读真实价，和蜡烛档是同一根。
    #expect(rr.legendIndex == rl.legendIndex)
  }

  /// 像素断言（替代基线）：关掉叠加指标、副图与最新价，主图里跌色一个满覆盖像素都不许有
  /// （蜡烛档有一大片），收盘价那几个点上必须落着 `up` 色的折线。
  @Test("收盘价画法的像素：没有蜡烛，折线过每根收盘")
  func linePixels() {
    let dev = Self.dev
    func st(_ kind: CandleKind) -> ChartState {
      var s = Evidence.state(dark: false, size: dev.size, overlays: [], subs: [])
      s.options.kind = kind
      s.options.lastLine = false
      return s
    }
    let s = Double(dev.scale)
    let down = st(.line).colors.down.rgb8, up = st(.line).colors.up.rgb8
    func downCount(_ kind: CandleKind) -> Int {
      let state = st(kind)
      let r = ChartRenderer(state: state)
      let L = r.layout(size: dev.size)
      let px = Pixels(Evidence.render(state, size: dev.size, scale: dev.scale))
      var n = 0
      for y in Int(L.main.y * s)..<Int((L.main.y + L.main.h) * s) {
        for x in 0..<Int(L.plotW * s) where chanDelta(px.rgb(x, y), down) <= 2 { n += 1 }
      }
      return n
    }
    #expect(downCount(.candle) > 500, "对照组：蜡烛档该有一片跌色")
    #expect(downCount(.line) == 0, "收盘价画法主图里还有跌色像素（蜡烛没撤干净）")

    // 折线过收盘：每根收盘点周围 2 个设备像素里能找到接近 up 色的像素。
    let state = st(.line)
    let r = ChartRenderer(state: state)
    let L = r.layout(size: dev.size)
    let range = r.priceRange(size: dev.size)
    let px = Pixels(Evidence.render(state, size: dev.size, scale: dev.scale))
    let b = state.series
    let (lo, hi) = visibleRange(view: state.view, series: b)
    var hits = 0, tried = 0
    for i in lo...hi {
      let xc = state.view.x(Double(b.time(at: i)), plotW: L.plotW)
      guard xc > 4, xc < L.plotW - 4 else { continue }
      let yc = KanpanCore.yOf(b.close[i], pane: L.main, range: range, mode: state.price.mode)
      tried += 1
      let cx = Int(xc * s), cy = Int(yc * s)
      var found = false
      for dy in -2...2 { for dx in -2...2 where chanDelta(px.rgb(cx + dx, cy + dy), up) <= 60 { found = true } }
      if found { hits += 1 }
    }
    #expect(tried > 20)
    #expect(hits == tried, "只有 \(hits)/\(tried) 根收盘点上落着折线")
  }

  // ---------------------------------------------------------------- 留白偏置

  @Test("偏置只挪位置不改大小")
  func biasMovesOnly() {
    func probe(_ b: PriceBias) -> ChartProbe {
      var st = Evidence.state(dark: false, size: Self.size)
      st.options.bias = b
      return ChartRenderer(state: st).probe(size: Self.size, scale: Self.scale)
    }
    let up = probe(.up), mid = probe(.center), down = probe(.down)
    for p in [up, mid, down] {
      #expect(p.bodyW == mid.bodyW && p.wickW == mid.wickW, "蜡烛被画小了")
      #expect(p.spacing == mid.spacing)
    }
    #expect(abs((up.rangeHi - up.rangeLo) - (mid.rangeHi - mid.rangeLo)) < 1e-9, "跨度变了")
    #expect(up.rangeLo < mid.rangeLo && down.rangeLo > mid.rangeLo, "三档没分开")
  }

  // ---------------------------------------------------------------- 副图高度

  @Test("副图高度倍率进得了布局")
  func subScaleReachesLayout() {
    var st = Evidence.state(dark: false, size: Self.size)
    let base = ChartRenderer(state: st).layout(size: Self.size)
    st.subScale = [.macd: 2.0]
    let big = ChartRenderer(state: st).layout(size: Self.size)
    #expect(big.panes[1].h > base.panes[1].h, "倍率没进布局")
    #expect(abs(big.panes[1].h / big.panes[2].h - 2) < 1e-9, "副图区权重比例不是2:1")
    #expect(big.mainH < base.mainH, "主图没让出高度")
    #expect(abs(big.panes[2].y - big.mainH - AICoinBehavior.timeHeight - big.panes[1].h) < 1e-9, "面板没接上")
  }

  // ---------------------------------------------------------------- 图例越界

  /// BOLL 图例曾经裸下标 `v.lines[1][i]`：序列为空时 `legendIndex` 是 −1，直接越界崩溃
  /// （审查 2026-09-24 §0.2 #4）。空序列、十字线两种入口都要画得过去。
  @Test("BOLL 图例：legendIndex 为 −1 时不越界")
  func bollLegendWithEmptySeries() throws {
    for crosshair in [nil, Crosshair(index: 5)] as [Crosshair?] {
      var st = Evidence.state(dark: false, size: Self.size, overlays: [.boll], subs: [],
                              crosshair: crosshair)
      st.series = BarSeries(symbol: st.series.symbol, interval: st.series.interval, bars: [])
      let r = ChartRenderer(state: st)
      #expect(r.legendIndex == -1)
      let boll = try #require(r.displayed(.boll), "空序列下 BOLL 没有结果，这条用例就没走到图例那一段")
      #expect(boll.lines.count >= 3)
      let L = r.layout(size: Self.size)
      let ctx = try #require(CGContext(data: nil, width: Int(Self.size.width), height: Int(Self.size.height),
                                       bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(),
                                       bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
      UIGraphicsPushContext(ctx)
      r.drawLegend(ctx, pane: L.main, L: L)
      UIGraphicsPopContext()
    }
  }
}
