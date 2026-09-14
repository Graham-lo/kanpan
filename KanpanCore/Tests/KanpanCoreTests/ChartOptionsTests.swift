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
    #expect(o.grid == .off && o.body == .style, "覆盖档默认必须是「跟随风格」")
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
      priceRange(view: v, series: s, bias: $0)
    }
    let spans = r.map { $0.hi - $0.lo }
    #expect(abs(spans[0] - spans[1]) < 1e-8 && abs(spans[1] - spans[2]) < 1e-8, "跨度变了：\(spans)")
  }

  /// `.up` = 蜡烛贴上去 = 整个区间往下挪（上下界都比居中低）。`.down` 反过来。
  @Test("偏上把蜡烛顶上去")
  func biasDirection() {
    let s = synthSeries(count: 400, seed: 12)
    let v = ViewMath.reset(series: s, plotW: 353, spacing: 8)
    let st = CandleStyle.default
    let up = priceRange(view: v, series: s, bias: .up)
    let mid = priceRange(view: v, series: s, bias: .center)
    let down = priceRange(view: v, series: s, bias: .down)
    #expect(up.lo < mid.lo && up.hi < mid.hi, "偏上没把区间往下挪")
    #expect(down.lo > mid.lo && down.hi > mid.hi, "偏下没把区间往上挪")
    // 蜡烛在 pane 里的 y：偏上必须更靠近顶。
    let pane = Pane(indicator: nil, y: 0, h: 400)
    let px = s.close[s.count - 1]
    #expect(yOf(px, pane: pane, range: up, mode: .linear)
      < yOf(px, pane: pane, range: mid, mode: .linear))
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
