import Testing
import Foundation
import KanpanCore
import KanpanData
@testable import KanpanSettings

/// 默认值一律以原型为准：`prototype/src/chart.js` 358–369 与 `app.js` 的 `S` 初始化。
@Suite("默认值")
struct PrefsDefaultsTests {

  @Test("全新安装的一份（A6.4「首次安装即如此」）")
  func 全新安装() {
    let p = Prefs.defaults
    #expect(p.style.name == "AICoin")                // 造型只有 AICoin 这一套
    #expect(p.interval == .h1)                       // 原型 S.interval 恒从 '1h' 起步
    #expect(p.overlays == [.ma])                     // chart.js: this.overlays = ['MA']
    #expect(p.subs == [.vol, .oi, .macd])                 // chart.js: this.subs = ['MACD','RSI']
    #expect(p.priceMode == .log)                  // chart.js: price.mode = 'linear'
    #expect(!p.magnet)                                // chart.js: this.magnet = true
    #expect(p.timeZone == .local)                    // chart.js: this.tz = 'local'
    #expect(p.redUp == true)                         // 国内习惯红涨绿跌，出厂即如此
    #expect(p.theme == .system)                      // app.js: 'auto'
    #expect(p.apiHost == "fapi.binance.com")         // §4.1
    #expect(!p.countdown)                             // §10.4 默认开
    #expect(p.keepAwake)                             // §10.4 默认开
    #expect(p.launchSnapshot)                        // §4.3 默认开
    #expect(p.routePolicy == .direct)                // 行情线路出厂直连，没有「自动」
  }

  @Test("「图表」那一页：三个分段都从「跟随风格」起步，覆盖不主动生效")
  func 图表默认() {
    let p = Prefs.defaults
    #expect(p.candleKind == .candle)      // 平均K线是可选项，不是默认口径
    #expect(p.gridChoice == .off)       // 不画网格，和手机 AICoin 一致
    #expect(p.bodyChoice == .solid)       // 阳线实心，同上
    #expect(p.viewAnchor == .right)       // 复位到最新时最新一根靠右——现状
    #expect(p.priceBias == .center)       // 蜡烛在主图区里居中——现状
    #expect(p.lastLine)                   // 最新价横线 + 右轴胶囊，默认开
    #expect(p.showDrawings)               // 画好的线默认看得见
    #expect(p.sinceChange == false)       // 十字线上多报一段涨跌幅，默认不报
    // 根宽出厂就是图表底座那个常数：没缩放过的人看到的第一屏和以前一模一样。
    #expect(p.barSpacing == AICoinBehavior.initialSpacing)
    #expect(!p.mainInverted)              // 上下翻转是可选项，出厂不翻
    #expect(p.subInverted.isEmpty)
  }

  @Test("chartOptions 把这一页每一项加已有的 countdown 一并交给引擎，一项不漏")
  func 取用入口() {
    #expect(!Prefs.defaults.chartOptions.countdown)   // 接的是已有的 countdown，不是另一个开关

    var p = Prefs.defaults
    p.candleKind = .heikin
    p.gridChoice = .off
    p.bodyChoice = .hollowUp
    p.lastLine = false
    p.showDrawings = false
    p.sinceChange = true
    p.viewAnchor = .left
    p.priceBias = .up
    p.countdown = false

    let o = p.chartOptions
    #expect(o.kind == .heikin)
    #expect(o.grid == .off)
    #expect(o.body == .hollowUp)
    #expect(o.lastLine == false)
    #expect(o.drawings)                  // 全局「显示画线」已撤，存档里是 false 也照样画
    #expect(o.sinceChange)
    #expect(o.anchor == .left)
    #expect(o.bias == .up)
    #expect(o.countdown == false)
    #expect(o != ChartOptions())
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

  @Test("副图高度默认「中」")
  func 默认高度() {
    for id in IndicatorID.allCases {
      #expect(Prefs.defaults.height(for: id) == .medium)
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
}
