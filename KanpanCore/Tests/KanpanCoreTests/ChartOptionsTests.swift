import Foundation
import Testing

@testable import KanpanCore

/// K 线设置的各档开关（§10.4 的图表侧）。
///
/// 这个套件的头号任务是守住「默认 = 现状」：`ChartOptions()` 的每一项都必须落回
/// 加这些开关之前的那条分支上，否则 A3.11 的 176 张基线会整片漂。
@Suite("K线设置")
struct ChartOptionsTests {
  @Test("默认值一律维持现状")
  func defaults() {
    let o = ChartOptions()
    #expect(o.kind == .candle)
    #expect(o.grid == .style && o.body == .style, "覆盖档默认必须是「跟随风格」")
    #expect(o.lastLine && o.drawings, "实时价格线和画线默认都画")
    #expect(!o.countdown && !o.sinceChange, "新画法默认一律关")
    #expect(o.bias == .center && o.anchor == .right)
    #expect(ChartOptions() == ChartOptions())
  }

  /// 设置页直接读 `display`，改名等于改用户看到的字，得钉住。
  @Test("中文档名")
  func displayNames() {
    #expect(CandleKind.allCases.map(\.display) == ["蜡烛", "平均K线"])
    #expect(GridChoice.allCases.map(\.display) == ["跟随风格", "显示", "隐藏"])
    #expect(BodyChoice.allCases.map(\.display) == ["跟随风格", "实心", "阳线空心"])
    #expect(PriceBias.allCases.map(\.display) == ["偏上", "居中", "偏下"])
    #expect(ViewAnchor.allCases.map(\.display) == ["偏左", "居中", "靠右"])
    // 存盘走 rawValue，不能跟着中文改。
    #expect(CandleKind.heikin.rawValue == "heikin" && ViewAnchor.left.rawValue == "left")
  }

  // MARK: - 留白偏置

  /// `bias` 只改留白的上下分配，**总跨度一点不变**——否则蜡烛会跟着缩放。
  @Test("三档偏置跨度完全相同")
  func biasKeepsSpan() {
    let s = synthSeries(count: 400, seed: 11)
    let v = ViewMath.reset(series: s, plotW: 353, spacing: 8)
    let st = CandleStyle.default
    let r = PriceBias.allCases.map {
      priceRange(view: v, series: s, style: st, bias: $0)
    }
    let spans = r.map { $0.hi - $0.lo }
    #expect(spans[0] == spans[1] && spans[1] == spans[2], "跨度变了：\(spans)")
  }

  /// `.up` = 蜡烛贴上去 = 整个区间往下挪（上下界都比居中低）。`.down` 反过来。
  @Test("偏上把蜡烛顶上去")
  func biasDirection() {
    let s = synthSeries(count: 400, seed: 12)
    let v = ViewMath.reset(series: s, plotW: 353, spacing: 8)
    let st = CandleStyle.default
    let up = priceRange(view: v, series: s, style: st, bias: .up)
    let mid = priceRange(view: v, series: s, style: st, bias: .center)
    let down = priceRange(view: v, series: s, style: st, bias: .down)
    #expect(up.lo < mid.lo && up.hi < mid.hi, "偏上没把区间往下挪")
    #expect(down.lo > mid.lo && down.hi > mid.hi, "偏下没把区间往上挪")
    // 蜡烛在 pane 里的 y：偏上必须更靠近顶。
    let pane = Pane(indicator: nil, y: 0, h: 400)
    let px = s.close[s.count - 1]
    #expect(yOf(px, pane: pane, range: up, mode: .linear)
      < yOf(px, pane: pane, range: mid, mode: .linear))
  }

  /// 默认档必须和「没有 bias 这个参数」时逐比特相同（`× 2 × 0.5` 在 IEEE754 下是精确的）。
  @Test("居中档与旧式逐比特相同")
  func biasCenterIsBitIdentical() {
    let s = synthSeries(count: 300, seed: 13)
    for st in CandleStyle.all {
      let v = ViewMath.reset(series: s, plotW: 353, spacing: st.spacing)
      let r = priceRange(view: v, series: s, style: st, bias: .center)
      // 旧式子：pad 直接加在两头。
      let (lo, hi) = visibleRange(view: v, series: s)
      var minV = Double.infinity, maxV = -Double.infinity
      for i in lo...hi {
        minV = min(minV, s.low[i]); maxV = max(maxV, s.high[i])
      }
      let a = minV - (maxV - minV) * st.pad
      let z = maxV + (maxV - minV) * st.pad
      // 后半段（mid ± half + off）是原样保留的老代码，这里照抄一遍，比的是留白那一步。
      let mid = (a + z) / 2
      let half = (z - a) / 2
      #expect(r.lo == mid - half && r.hi == mid + half, "\(st.id) 默认档漂了")
    }
  }

  // MARK: - 复位锚点

  /// 三档「拖动位置」：靠右 = 原来的 6% 空白；居中、偏左依次把最新一根往左推。
  ///
  /// 偏左实测停在距左边缘 30%（不是名义上的 25%）：`clampView` 的
  /// `maxTo = lastT + span * 0.7` 截住了它，而那条 0.7 同时管拖动边界，不动它。
  @Test("三档复位锚点")
  func anchors() {
    let s = synthSeries(count: 600, seed: 21)
    let plotW = 353.0, spacing = 8.0
    func lastX(_ a: ViewAnchor) -> Double {
      let v = ViewMath.reset(series: s, plotW: plotW, spacing: spacing, anchor: a)
      return v.x(Double(s.lastTime), plotW: plotW) / plotW
    }
    let r = lastX(.right), c = lastX(.center), l = lastX(.left)
    #expect(abs(r - (1 - Chart.rightGap)) < 1e-9, "靠右档不是 6% 空白：\(r)")
    #expect(abs(c - 0.5) < 1e-9, "居中档不在正中：\(c)")
    #expect(abs(l - 0.30) < 1e-9, "偏左档落点变了：\(l)")
    #expect(l < c && c < r, "三档没按左中右排开")
    // 不带参数的老入口必须原样等于靠右档。
    #expect(ViewMath.reset(series: s, plotW: plotW, spacing: spacing)
      == ViewMath.reset(series: s, plotW: plotW, spacing: spacing, anchor: .right))
  }

  @Test("空序列复位不崩")
  func anchorEmpty() {
    let e = BarSeries(symbol: "X", interval: .h1, bars: [])
    for a in ViewAnchor.allCases {
      #expect(ViewMath.reset(series: e, plotW: 353, spacing: 8, anchor: a).span > 0)
    }
  }

  // MARK: - 本根倒计时

  @Test("倒计时三档文案")
  func countdownTiers() {
    #expect(fmtCountdown(msRemaining: 42_000) == "00:42")
    #expect(fmtCountdown(msRemaining: 59_999) == "00:59", "不足一秒不进位")
    #expect(fmtCountdown(msRemaining: 60_000) == "01:00")
    #expect(fmtCountdown(msRemaining: 59 * 60_000 + 59_000) == "59:59")
    #expect(fmtCountdown(msRemaining: 3_600_000) == "1:00:00", "整小时进 h:mm:ss")
    #expect(fmtCountdown(msRemaining: 3 * 3_600_000 + 5 * 60_000 + 12_000) == "3:05:12")
    #expect(fmtCountdown(msRemaining: 23 * 3_600_000 + 59 * 60_000 + 59_000) == "23:59:59")
    #expect(fmtCountdown(msRemaining: 86_400_000) == "1d 00:00", "满一天改报 Nd hh:mm")
    #expect(fmtCountdown(msRemaining: 6 * 86_400_000 + 7 * 3_600_000 + 8 * 60_000) == "6d 07:08")
  }

  /// 收盘时刻已经过了就不该画这一格：给 nil，不给 `00:00`。
  @Test("倒计时归零与非数给 nil")
  func countdownNil() {
    #expect(fmtCountdown(msRemaining: 0) == nil)
    #expect(fmtCountdown(msRemaining: -1) == nil)
    #expect(fmtCountdown(msRemaining: .nan) == nil)
    #expect(fmtCountdown(msRemaining: .infinity) == nil)
  }

  /// 文案宽度：同一档内位数固定，右轴那一格不会一秒一跳。
  @Test("同档内宽度稳定")
  func countdownWidthStable() {
    let short = (1...59).map { fmtCountdown(msRemaining: Double($0) * 1000)!.count }
    #expect(Set(short) == [5], "mm:ss 档出现了别的长度")
    let day = (1...9).map { fmtCountdown(msRemaining: Double($0) * 86_400_000)!.count }
    #expect(Set(day) == [8], "Nd hh:mm 档（个位数天）出现了别的长度")
  }
}
