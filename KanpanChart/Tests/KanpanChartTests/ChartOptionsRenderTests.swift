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
                    style: CandleStyle = .default,
                    crosshair: Crosshair? = nil) -> ChartState {
    var st = Evidence.state(style: style, dark: false, size: size, crosshair: crosshair)
    mutate(&st.options)
    return st
  }

  // ---------------------------------------------------------------- 默认档

  /// 这个套件的地基：`ChartOptions()` 不能改变任何一个探针数字。
  @Test("默认档不动任何几何")
  func defaultsAreInert() {
    for style in CandleStyle.all {
      let base = Evidence.state(style: style, dark: false, size: Self.size)
      var same = base
      same.options = ChartOptions()
      let a = ChartRenderer(state: base).probe(size: Self.size, scale: Self.scale)
      let b = ChartRenderer(state: same).probe(size: Self.size, scale: Self.scale)
      #expect(a == b, "\(style.id) 默认档漂了")
    }
  }

  // ---------------------------------------------------------------- 网格

  /// `effectiveGrid`：`.style` 读风格表，另两档强制。竖细线数量是最直观的观测量。
  @Test("网格三档")
  func gridChoice() {
    for style in CandleStyle.all {
      #expect(Self.state({ $0.grid = .style }, style: style).effectiveGrid == .none)
      #expect(Self.state({ $0.grid = .on }, style: style).effectiveGrid == .both)
      #expect(Self.state({ $0.grid = .off }, style: style).effectiveGrid == .none)
    }
    // 隐藏档下只剩价格轴那一条分隔线；显示档一定更多。
    let off = ChartRenderer(state: Self.state { $0.grid = .off })
      .verticalHairlineXs(size: Self.size, scale: Self.scale)
    let on = ChartRenderer(state: Self.state { $0.grid = .on })
      .verticalHairlineXs(size: Self.size, scale: Self.scale)
    #expect(off.count == 1, "隐藏档还画了 \(off.count) 条竖线")
    #expect(on.count > off.count, "显示档没多出时间网格线")
  }

  // ---------------------------------------------------------------- 实体

  @Test("实体三档")
  func bodyChoice() {
    for style in CandleStyle.all {
      #expect(Self.state({ $0.body = .style }, style: style).effectiveShape == style.shape)
      #expect(Self.state({ $0.body = .solid }, style: style).effectiveShape == .solid)
      #expect(Self.state({ $0.body = .hollowUp }, style: style).effectiveShape == .hollowUp)
    }
    // 「描」默认全空心：强制实心之后一根空心都不该剩。
    let outline = CandleStyle.style(id: "outline")
    let forced = ChartRenderer(state: Self.state({ $0.body = .solid }, style: outline))
      .candleXs(size: Self.size, scale: Self.scale)
    #expect(!forced.isEmpty)
    #expect(forced.allSatisfy { !$0.hollow }, "强制实心还有空心实体")

    // 强制阳线空心：阳线空、阴线实（够胖的那些）。
    let hollow = ChartRenderer(state: Self.state({ $0.body = .hollowUp }, style: .default))
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
    var st = Evidence.state(style: .default, dark: false, size: Self.size)
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
    var plain = Evidence.state(style: .default, dark: false, size: Self.size)
    plain.options.drawings = false
    let base = Evidence.state(style: .default, dark: false, size: Self.size)
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
    var st = Evidence.state(style: .default, dark: false, size: Self.size)
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
    var st = Evidence.state(style: .default, dark: false, size: Self.size)
    st.options.countdown = true
    #expect(st.nowMs == nil)
    let base = Evidence.state(style: .default, dark: false, size: Self.size)
    #expect(ChartRenderer(state: st).probe(size: Self.size, scale: Self.scale)
      == ChartRenderer(state: base).probe(size: Self.size, scale: Self.scale))
  }

  // ---------------------------------------------------------------- 平均 K 线

  @Test("平均K线改蜡烛，不改指标与最新价")
  func heikinAffectsCandlesOnly() {
    let real = Evidence.state(style: .default, dark: false, size: Self.size)
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
    var ha = Evidence.state(style: .default, dark: false, size: Self.size)
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

  // ---------------------------------------------------------------- 留白偏置

  @Test("偏置只挪位置不改大小")
  func biasMovesOnly() {
    func probe(_ b: PriceBias) -> ChartProbe {
      var st = Evidence.state(style: .default, dark: false, size: Self.size)
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
    var st = Evidence.state(style: .default, dark: false, size: Self.size)
    let base = ChartRenderer(state: st).layout(size: Self.size)
    st.subScale = [.macd: 2.0]
    let big = ChartRenderer(state: st).layout(size: Self.size)
    #expect(big.panes[1].h > base.panes[1].h, "倍率没进布局")
    #expect(abs(big.panes[1].h / big.panes[2].h - 2) < 1e-9, "副图区权重比例不是2:1")
    #expect(big.mainH < base.mainH, "主图没让出高度")
    #expect(abs(big.panes[2].y - big.mainH - AICoinBehavior.timeHeight - big.panes[1].h) < 1e-9, "面板没接上")
  }
}
