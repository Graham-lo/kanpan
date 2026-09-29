import Testing
import KanpanCore
@testable import Kanpan

/// A6.7：涨跌对调开了之后，K 线、成交量、MACD 柱、涨跌幅胶囊**一处不漏**。
///
/// 「不漏」在这份实现里是**结构上**保证的：所有涨跌色都只有
/// `Prefs.chartColors(dark:)` 这一个出口，谁也不许自己判 `redUp`。
/// 所以这里验的是这个出口本身对调得干净。
@Suite("涨跌对调")
struct PrefsColorTests {

  @Test("默认红涨绿跌")
  func 默认方向() {
    // 出厂跟国内看盘习惯：红涨绿跌。`redUp` 为真时 up/down 两色是对调过来取的。
    let p = Prefs.defaults
    #expect(p.redUp == true)
    #expect(p.chartColors(dark: false).up == Palette.lightSeed.down)   // 红
    #expect(p.chartColors(dark: false).down == Palette.lightSeed.up)   // 绿
    #expect(p.chartColors(dark: true).up == Palette.darkSeed.down)
    #expect(p.chartColors(dark: true).down == Palette.darkSeed.up)
  }

  @Test("关掉之后绿涨红跌，浅深都对调")
  func 对调() {
    var p = Prefs.defaults
    p.redUp = false
    #expect(p.chartColors(dark: false).up == Palette.lightSeed.up)
    #expect(p.chartColors(dark: false).down == Palette.lightSeed.down)
    #expect(p.chartColors(dark: true).up == Palette.darkSeed.up)
    #expect(p.chartColors(dark: true).down == Palette.darkSeed.down)
  }

  @Test("只动涨跌两色，其余令牌一个不变")
  func 只动两色() {
    for dark in [false, true] {
      var off = Prefs.defaults; off.redUp = false
      let a = Prefs.defaults.chartColors(dark: dark)
      let b = off.chartColors(dark: dark)
      #expect(a.up == b.down && a.down == b.up)
      #expect(a.bg == b.bg && a.grid == b.grid && a.axis == b.axis)
      #expect(a.text == b.text && a.ink == b.ink && a.amber == b.amber)
      #expect(a.palette == b.palette)
      #expect(a.crossBg == b.crossBg && a.crossInk == b.crossInk)
    }
  }

  @Test("开关能存下来")
  func 持久化() {
    // 出厂已经是红涨，所以这儿存的是「关掉」那一边，才验得到真的落了盘。
    var p = Prefs.defaults
    p.redUp = false
    #expect(!PrefsCodec.decode(PrefsCodec.encode(p)).redUp)
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

  @Test("副图最多三个，第四个挤掉最早打开的那个（成交量以外）")
  func 副图上限() {
    var p = Prefs.defaults
    p.subs = []
    let ids: [IndicatorID] = [.oi, .macd, .rsi]
    for id in ids { #expect(p.toggle(id) == nil) }
    #expect(p.subs == ids)
    // 第四个不再被拒绝：队首（最早打开的 OI）让位，并把「换下了谁」说回来。
    #expect(p.toggle(.kdj) == "副图最多三个 · 已换下 持仓量")
    #expect(p.subs == [.macd, .rsi, .kdj])
    // 关掉一个照旧只是关掉，不带提示，其余顺序不动。
    #expect(p.toggle(.rsi) == nil)
    #expect(p.subs == [.macd, .kdj])
  }

  /// 2026-09-29 与网页版对齐：成交量叠在主图底部、不占名额，口径是「成交量 + 最多三个」。
  @Test("成交量不占副图名额：满三个时再开成交量不挤人")
  func 成交量不占名额() {
    var p = Prefs.defaults
    p.subs = [.oi, .macd, .rsi]
    #expect(p.toggle(.vol) == nil)
    #expect(p.subs == [.oi, .macd, .rsi, .vol])
    #expect(p.isOn(.vol))
  }

  @Test("出厂量 / 仓 / MACD 再开一个不换人，第五个才换下最早的非成交量")
  func 成交量不被换下() {
    var p = Prefs.defaults
    #expect(p.subs == [.vol, .oi, .macd])
    #expect(p.toggle(.rsi) == nil)                       // 成交量不算，此时才三个
    #expect(p.subs == [.vol, .oi, .macd, .rsi])
    // 再开一个：换下的是最早的非成交量 OI，排在队首的成交量不动。
    #expect(p.toggle(.kdj) == "副图最多三个 · 已换下 持仓量")
    #expect(p.subs == [.vol, .macd, .rsi, .kdj])
    // 关掉成交量再开回来，也不挤任何人。
    #expect(p.toggle(.vol) == nil)
    #expect(p.toggle(.vol) == nil)
    #expect(p.subs == [.macd, .rsi, .kdj, .vol])
  }

  @Test("裁副图的尺子：成交量原位保留，别的按顺序留前三个")
  func 裁副图() {
    #expect(Prefs.cappedSubs([.macd, .vol, .rsi, .kdj, .oi]) == [.macd, .vol, .rsi, .kdj])
    #expect(Prefs.cappedSubs([.vol, .oi, .macd]) == [.vol, .oi, .macd])
    #expect(Prefs.cappedSubs([.oi, .macd, .rsi, .kdj]) == [.oi, .macd, .rsi])
    #expect(Prefs.cappedSubs([]) == [])
  }

  @Test("拖动排序")
  func 排序() {
    var p = Prefs.defaults
    p.subs = [.macd, .rsi]
    p.toggle(.kdj)
    p.moveSub(from: 2, to: 0)
    #expect(p.subs == [.kdj, .macd, .rsi])
    p.moveSub(from: 0, to: 99)                 // 越界的目标夹到末尾
    #expect(p.subs == [.macd, .rsi, .kdj])
    p.moveSub(from: 7, to: 0)                  // 越界的来源什么都不做
    #expect(p.subs == [.macd, .rsi, .kdj])
  }

  @Test("副图高度：拖过的用拖出来的倍率，没拖过的走出厂倍率")
  func 高度() {
    var p = Prefs.defaults
    #expect(p.scale(for: .macd) == Prefs.defaultSubScale)
    p.subHeightOverrides[.macd] = 1.3
    #expect(p.scale(for: .macd) == 1.3)
    #expect(p.scale(for: .rsi) == Prefs.defaultSubScale)   // 只动拖过的那一格
  }

  @Test("改参数只影响那一个指标")
  func 参数互不影响() {
    var p = Prefs.defaults
    p.setParam(.ma, at: 1, to: 35)
    #expect(p.params(for: .ma) == [10, 35, 120, 256])
    #expect(p.params(for: .ema) == Prefs.defaults.params(for: .ema))
    #expect(p.params(for: .macd) == [10, 30, 9])
    let back = PrefsCodec.decode(PrefsCodec.encode(p))
    #expect(back.params(for: .ma) == [10, 35, 120, 256])
  }
}
