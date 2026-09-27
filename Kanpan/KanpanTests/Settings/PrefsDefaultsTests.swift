import Testing
import Foundation
import KanpanCore
import KanpanData
@testable import Kanpan

/// 默认值一律以原型为准：`prototype/src/chart.js` 358–369 与 `app.js` 的 `S` 初始化。
@Suite("默认值")
struct PrefsDefaultsTests {

  @Test("全新安装的一份（A6.4「首次安装即如此」）")
  func 全新安装() {
    let p = Prefs.defaults
    #expect(p.interval == .h1)                       // 原型 S.interval 恒从 '1h' 起步
    #expect(p.overlays == [.ma])                     // chart.js: this.overlays = ['MA']
    #expect(p.subs == [.vol, .oi, .macd])                 // chart.js: this.subs = ['MACD','RSI']
    #expect(p.priceMode == .log)                  // chart.js: price.mode = 'linear'
    #expect(p.timeZone == .exchange)                 // 2026-09-28 起不是设置项：全 app 一律上海 UTC+8
    #expect(p.redUp == true)                         // 国内习惯红涨绿跌，出厂即如此
    #expect(p.theme == .system)                      // app.js: 'auto'
    #expect(p.routePolicy == .direct)                // 行情线路出厂直连，没有「自动」
  }

  @Test("「图表设置」只剩画法：别的都是定值（收设置项 B 组）")
  func 图表默认() {
    let p = Prefs.defaults
    #expect(p.candleKind == .candle)      // 平均K线是可选项，不是默认口径
    #expect(p.chartOptions.drawings)      // 画好的线看得见；显隐只按品种管，没有全局开关
    // 根宽出厂就是图表底座那个常数：没缩放过的人看到的第一屏和以前一模一样。
    #expect(p.barSpacing == AICoinBehavior.initialSpacing)
    #expect(!p.mainInverted)              // 上下翻转出厂不翻
    #expect(p.subInverted.isEmpty)
  }

  @Test("chartOptions：收掉的十三项一律交定值给引擎，只有画法和网格跟人走")
  func 取用入口() {
    var p = Prefs.defaults
    p.candleKind = .heikin
    let o = p.chartOptions
    #expect(o.kind == .heikin)
    #expect(o.body == .solid)            // 阳线一律实心
    #expect(o.lastLine)                  // 实时价格线常在
    #expect(o.drawings)                  // 全局「显示画线」已撤，恒为 true
    #expect(o.countdown)                 // 本根倒计时常开（周期最短 1 分钟，每档都画）
    #expect(o.sinceChange)               // 十字线顺带报到最新价的涨跌幅
    #expect(o.anchor == .right)
    #expect(o.bias == .center)
    #expect(o.dataDisplay == .top)       // 长按时开高低收写在头部
    #expect(o.crossPrice == .selected)
    #expect(o.allowMainInversion && o.allowSubInversion)  // 翻转手势直接生效
    #expect(o.adaptiveIndicators)
  }

  @Test("网格按皮肤：经典照 AICoin 不画，青苔 / 陶土画自己皮肤色的淡网格")
  func 网格跟皮肤() {
    var p = Prefs.defaults
    p.skin = .classic
    #expect(p.chartOptions.grid == .off)
    p.skin = .sage
    #expect(p.chartOptions.grid == .on)
    p.skin = .terra
    #expect(p.chartOptions.grid == .on)
  }

  @Test("每个指标的默认参数直接取 Core，不另抄一份")
  func 默认参数() {
    let p = Prefs.defaults
    for id in IndicatorID.allCases {
      #expect(p.params(for: id) == (p.params[id] ?? id.defaultParams))
    }
    #expect(p.params(for: .ma) == [10, 30, 120, 256])
    #expect(p.params(for: .macd) == [10, 30, 9])
  }

  @Test("副图高度默认等高：谁都没拖过，每一格都是出厂倍率")
  func 默认高度() {
    for id in IndicatorID.allCases {
      #expect(Prefs.defaults.scale(for: id) == Prefs.defaultSubScale)
    }
  }
}

/// A6.6：周期 14 档，常用行 7 档。
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

  @Test("常用行 6 档放满，与 Interval.quick 相同")
  func 常用行() {
    // 出厂就把六格放满：5m 30m 1h 4h 1d 1w（2026-09-21 用户看了出厂第一屏的截图定的）。
    // 五档那一版条上少一格、行尾又留着空槽，读起来是「几颗药丸 + 一段空白」；
    // 放满之后六档等宽铺开，彼此隔得均匀。没钉住的档都在「更多」网格里，一个没少。
    #expect(Prefs.defaults.quickIntervals == [.m5, .m30, .h1, .h4, .d1, .w1])
    #expect(Prefs.defaults.quickIntervals.count == 6)
    #expect(Prefs.defaults.quickIntervals == Interval.quick)
    #expect(Prefs.defaults.quickIntervals.count == Prefs.maxQuick)        // 出厂 = 满钉
  }

  @Test("常用行增删：最多 6 档、至少留 1 档，且按 14 档的顺序排")
  func 常用行增删() {
    var p = Prefs.defaults
    // 上限 2026-09-21 从 10 收到 6：周期条不再横向滚动，一行只排得下六档。
    #expect(Prefs.maxQuick == 6)
    // 出厂已经满钉，先得腾一格才钉得进新的一档。
    #expect(p.toggleQuick(.h2) != nil)                                    // 第 7 档按不进去
    #expect(p.quickIntervals == Interval.quick)

    #expect(p.toggleQuick(.w1) == nil)                                    // 取下 1w
    #expect(p.quickIntervals == [.m5, .m30, .h1, .h4, .d1])
    #expect(p.toggleQuick(.h2) == nil)
    #expect(p.quickIntervals == [.m5, .m30, .h1, .h2, .h4, .d1])  // 插在 1h 与 4h 之间

    #expect(p.toggleQuick(.h2) == nil)                                    // 再按一次移出
    #expect(p.quickIntervals == [.m5, .m30, .h1, .h4, .d1])

    _ = p.toggleQuick(.m1)
    #expect(p.quickIntervals.count == 6)
    #expect(p.toggleQuick(.y1) != nil)                                    // 满了就按不进去
    #expect(p.quickIntervals.count == 6)
    #expect(!p.quickIntervals.contains(.y1))

    var one = Prefs.defaults
    one.quickIntervals = [.h1]
    #expect(one.toggleQuick(.h1) != nil)                                  // 最后一档删不掉
    #expect(one.quickIntervals == [.h1])
  }

  @Test("钉满六档时一步换档：换掉的那档出去、新的一档按 14 档的顺序插回，档数不变")
  func 钉满换档() {
    var p = Prefs.defaults
    #expect(p.quickIntervals == [.m5, .m30, .h1, .h4, .d1, .w1])
    p.replaceQuick(old: .w1, new: .h2)
    #expect(p.quickIntervals == [.m5, .m30, .h1, .h2, .h4, .d1])
    p.replaceQuick(old: .m5, new: .y1)
    #expect(p.quickIntervals == [.m30, .h1, .h2, .h4, .d1, .y1])
    // 没钉着的 old、已经钉着的 new、自己换自己：一律不做事。
    p.replaceQuick(old: .m1, new: .m3)
    p.replaceQuick(old: .h1, new: .h2)
    p.replaceQuick(old: .h4, new: .h4)
    #expect(p.quickIntervals == [.m30, .h1, .h2, .h4, .d1, .y1])
  }
}
