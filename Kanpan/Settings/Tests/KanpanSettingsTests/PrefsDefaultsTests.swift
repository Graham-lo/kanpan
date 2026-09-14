import Testing
import Foundation
import KanpanCore
@testable import KanpanSettings

/// 默认值一律以原型为准：`prototype/src/chart.js` 358–369 与 `app.js` 的 `S` 初始化。
@Suite("默认值")
struct PrefsDefaultsTests {

  @Test("全新安装的一份（A6.4「首次安装即如此」）")
  func 全新安装() {
    let p = Prefs.defaults
    #expect(p.styleID == "stout")                    // 原型 S.style 默认 'stout'（墩）
    #expect(p.style.name == "墩")
    #expect(p.interval == .h1)                       // 原型 S.interval 恒从 '1h' 起步
    #expect(p.overlays == [.ma])                     // chart.js: this.overlays = ['MA']
    #expect(p.subs == [.macd, .rsi])                 // chart.js: this.subs = ['MACD','RSI']
    #expect(p.priceMode == .linear)                  // chart.js: price.mode = 'linear'
    #expect(p.magnet)                                // chart.js: this.magnet = true
    #expect(p.timeZone == .local)                    // chart.js: this.tz = 'local'
    #expect(p.redUp == false)                        // app.js: S.redUp = !!saved.redUp
    #expect(p.theme == .system)                      // app.js: 'auto'
    #expect(p.apiHost == "fapi.binance.com")         // §4.1
    #expect(p.countdown)                             // §10.4 默认开
    #expect(p.keepAwake)                             // §10.4 默认开
    #expect(p.launchSnapshot)                        // §4.3 默认开
  }

  @Test("每个指标的默认参数直接取 Core，不另抄一份")
  func 默认参数() {
    let p = Prefs.defaults
    for id in IndicatorID.allCases {
      #expect(p.params(for: id) == id.defaultParams)
    }
    #expect(p.params(for: .ma) == [7, 25, 99])
    #expect(p.params(for: .macd) == [12, 26, 9])
  }

  @Test("副图高度默认「中」")
  func 默认高度() {
    for id in IndicatorID.allCases {
      #expect(Prefs.defaults.height(for: id) == .medium)
    }
  }
}

/// A6.6：周期 14 档，常用行 6 档。
@Suite("周期表")
struct IntervalTableTests {

  @Test("14 档，顺序与原型 ALL_PERIODS 一字不差")
  func 十四档() {
    let want = ["1m", "3m", "5m", "15m", "30m", "1h", "2h", "4h", "6h", "12h", "1d", "1w", "1M", "1y"]
    #expect(Interval.allCases.count == 14)
    #expect(Interval.allCases.map(\.rawValue) == want)
    // 任务书 §1.1 定死：不做 3d，不加 8h。
    #expect(!want.contains("3d"))
    #expect(!want.contains("8h"))
  }

  @Test("常用行 6 档，与原型 QUICK 相同")
  func 常用行() {
    #expect(Prefs.defaults.quickIntervals == [.m1, .m5, .m15, .h1, .h4, .d1])
    #expect(Prefs.defaults.quickIntervals.count == 6)
    #expect(Prefs.defaults.quickIntervals == Interval.quick)
  }

  @Test("常用行增删：最多 8 档、至少留 1 档，且按 14 档的顺序排")
  func 常用行增删() {
    var p = Prefs.defaults
    #expect(p.toggleQuick(.m30) == nil)
    #expect(p.quickIntervals == [.m1, .m5, .m15, .m30, .h1, .h4, .d1])   // 插在 15m 与 1h 之间

    #expect(p.toggleQuick(.m30) == nil)                                   // 再按一次移出
    #expect(p.quickIntervals == Interval.quick)

    for iv in [Interval.m3, .h2, .h6, .h12, .w1, .mo1] {
      _ = p.toggleQuick(iv)
    }
    #expect(p.quickIntervals.count == 8)
    #expect(p.toggleQuick(.y1) != nil)                                    // 第 9 档按不进去
    #expect(p.quickIntervals.count == 8)

    var one = Prefs.defaults
    one.quickIntervals = [.h1]
    #expect(one.toggleQuick(.h1) != nil)                                  // 最后一档删不掉
    #expect(one.quickIntervals == [.h1])
  }
}
