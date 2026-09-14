import Testing
import KanpanCore
@testable import KanpanSettings

/// A6.7：涨跌对调开了之后，K 线、成交量、MACD 柱、涨跌幅胶囊**一处不漏**。
///
/// 「不漏」在这份实现里是**结构上**保证的：所有涨跌色都只有
/// `Prefs.chartColors(dark:)` 这一个出口，谁也不许自己判 `redUp`。
/// 所以这里验的是这个出口本身对调得干净。
@Suite("涨跌对调")
struct PrefsColorTests {

  @Test("默认绿涨红跌")
  func 默认方向() {
    let p = Prefs.defaults
    #expect(p.redUp == false)
    #expect(p.upColor(dark: false) == Palette.lightSeed.up)     // 绿
    #expect(p.downColor(dark: false) == Palette.lightSeed.down) // 红
    #expect(p.upColor(dark: true) == Palette.darkSeed.up)
    #expect(p.downColor(dark: true) == Palette.darkSeed.down)
  }

  @Test("打开之后涨红跌绿，浅深都对调")
  func 对调() {
    var p = Prefs.defaults
    p.redUp = true
    #expect(p.upColor(dark: false) == Palette.lightSeed.down)
    #expect(p.downColor(dark: false) == Palette.lightSeed.up)
    #expect(p.upColor(dark: true) == Palette.darkSeed.down)
    #expect(p.downColor(dark: true) == Palette.darkSeed.up)
  }

  @Test("只动涨跌两色，其余令牌一个不变")
  func 只动两色() {
    for dark in [false, true] {
      var on = Prefs.defaults; on.redUp = true
      let a = Prefs.defaults.chartColors(dark: dark)
      let b = on.chartColors(dark: dark)
      #expect(a.up == b.down && a.down == b.up)
      #expect(a.bg == b.bg && a.grid == b.grid && a.axis == b.axis)
      #expect(a.text == b.text && a.ink == b.ink && a.amber == b.amber)
      #expect(a.palette == b.palette)
      #expect(a.crossBg == b.crossBg && a.crossInk == b.crossInk)
    }
  }

  @Test("K 线、成交量、MACD 柱、胶囊取的是同一对颜色")
  func 同一个出口() {
    var p = Prefs.defaults
    p.redUp = true
    let c = p.chartColors(dark: false)
    // 画 K 线的、画 VOL 柱的、画 MACD 柱的、画涨跌幅胶囊的，拿的都是这两个值。
    #expect(p.upColor(dark: false) == c.up)
    #expect(p.downColor(dark: false) == c.down)
    #expect(c.up != c.down)
  }

  @Test("开关能存下来")
  func 持久化() {
    var p = Prefs.defaults
    p.redUp = true
    #expect(PrefsCodec.decode(PrefsCodec.encode(p)).redUp)
  }
}

/// A6.4 / A6.6：指标开关、副图上限三个、参数与高度、排序。
@Suite("指标")
struct IndicatorToggleTests {

  @Test("主图叠加随便开几个，按打开先后排")
  func 主图() {
    var p = Prefs.defaults
    #expect(p.overlays == [.ma])
    #expect(p.toggle(.boll) == nil)
    #expect(p.toggle(.ema) == nil)
    #expect(p.overlays == [.ma, .boll, .ema])
    #expect(p.toggle(.ma) == nil)
    #expect(p.overlays == [.boll, .ema])
    #expect(p.isOn(.boll))
    #expect(!p.isOn(.ma))
  }

  @Test("副图开到第四个就按不下去，并且弹原型那句话")
  func 副图上限() {
    var p = Prefs.defaults
    #expect(p.subs == [.macd, .rsi])
    #expect(p.toggle(.kdj) == nil)
    #expect(p.subs.count == 3)
    #expect(p.toggle(.atr) == "副图最多同时开三个")
    #expect(p.subs == [.macd, .rsi, .kdj])     // 没动
    #expect(p.toggle(.rsi) == nil)             // 关掉一个就又能开
    #expect(p.toggle(.atr) == nil)
    #expect(p.subs == [.macd, .kdj, .atr])
  }

  @Test("拖动排序")
  func 排序() {
    var p = Prefs.defaults
    p.toggle(.kdj)
    p.moveSub(from: 2, to: 0)
    #expect(p.subs == [.kdj, .macd, .rsi])
    p.moveSub(from: 0, to: 99)                 // 越界的目标夹到末尾
    #expect(p.subs == [.macd, .rsi, .kdj])
    p.moveSub(from: 7, to: 0)                  // 越界的来源什么都不做
    #expect(p.subs == [.macd, .rsi, .kdj])
  }

  @Test("副图高度三档")
  func 高度() {
    var p = Prefs.defaults
    #expect(p.height(for: .macd) == .medium)
    p.subHeights[.macd] = .large
    #expect(p.height(for: .macd) == .large)
    #expect(p.height(for: .rsi) == .medium)
    #expect(SubPaneHeight.small.points(base: 84) < SubPaneHeight.medium.points(base: 84))
    #expect(SubPaneHeight.medium.points(base: 84) < SubPaneHeight.large.points(base: 84))
    #expect(SubPaneHeight.small.points(base: 10) >= 44)   // 再小也不能小到看不见
  }

  @Test("改参数只影响那一个指标")
  func 参数互不影响() {
    var p = Prefs.defaults
    p.setParam(.ma, at: 1, to: 30)
    #expect(p.params(for: .ma) == [7, 30, 99])
    #expect(p.params(for: .ema) == IndicatorID.ema.defaultParams)
    #expect(p.params(for: .macd) == [12, 26, 9])
    let back = PrefsCodec.decode(PrefsCodec.encode(p))
    #expect(back.params(for: .ma) == [7, 30, 99])
  }
}
