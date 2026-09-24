import Testing
import KanpanCore
@testable import Kanpan

// 「看细节」（§10.1）：选中一根大 K 线 → 换一档更细的 → 视野刚好铺满那一根。

@Suite("看细节：进哪一档、铺多宽")
struct DetailZoomTests {

  @Test("进的是还能把这根切成十几根的那一档，不是紧挨着的那一档")
  func picksAnIntervalThatActuallyShowsDetail() {
    // 4h 的下一档是 2h——一根拆成两根，铺满一屏就是两根蜡烛，白按一次。
    #expect(DetailZoom.finer(than: .h4) == .m15)      // 16 根
    #expect(DetailZoom.finer(than: .h1) == .m5)       // 12 根
    #expect(DetailZoom.finer(than: .d1) == .h2)       // 12 根
    #expect(DetailZoom.finer(than: .h12) == .h1)      // 12 根
    #expect(DetailZoom.finer(than: .h6) == .m30)      // 12 根
    #expect(DetailZoom.finer(than: .h2) == .m5)       // 24 根
    #expect(DetailZoom.finer(than: .w1) == .h12)      // 14 根
    #expect(DetailZoom.finer(than: .mo1) == .d1)      // 30 根
    #expect(DetailZoom.finer(than: .y1) == .mo1)      // 12 根
  }

  @Test("本来就很细的那几档退到 1m，1m 上这颗按钮不该存在")
  func bottomsOutAtOneMinute() {
    #expect(DetailZoom.finer(than: .m30) == .m1)
    #expect(DetailZoom.finer(than: .m15) == .m1)
    #expect(DetailZoom.finer(than: .m5) == .m1)
    #expect(DetailZoom.finer(than: .m3) == .m1)
    #expect(DetailZoom.finer(than: .m1) == nil)
  }

  @Test("视野刚好覆盖那一根，左右各留半根细 K 线的空隙")
  func coversExactlyOneBigCandle() {
    let open = 1_700_000_000_000.0
    let end = open + Double(Interval.h4.stepMs)
    let view = DetailZoom.window(barOpen: open, barEnd: end, finer: .m15)
    let s = Double(Interval.m15.stepMs)
    // 蜡烛骑在自己的开盘时刻上，所以这根大 K 线在细序列里占 [开-s/2, 末开+s/2]；
    // 两头再各让半根，就是下面这个窗口。
    #expect(view.from == open - s)
    #expect(view.to == end)
    #expect(view.span == end - open + s)
    // 一屏正好 16 根细 K 线 + 两头各半根。
    #expect(view.span / s == 17)
  }

  @Test("1M / 1y 这种长度不等的档按真的下一根开盘时刻算，不按名义步长")
  func honoursIrregularBarLengths() {
    let open = 1_700_000_000_000.0
    let end = open + 31 * 86_400_000.0            // 真实的 31 天，名义步长是 30 天
    let view = DetailZoom.window(barOpen: open, barEnd: end, finer: .d1)
    #expect(view.to == end)
    #expect(view.span == end - open + 86_400_000)
  }
}

@Suite("看细节：切回大周期的那个视野栈")
struct DetailZoomStackTests {

  private func window(_ to: Double) -> ViewWindow { ViewWindow(to: to, span: 1_000) }

  @Test("切回哪一档就还哪一档的视野，还完就销账")
  func restoresTheViewportOfThatInterval() {
    var stack = DetailZoomStack()
    stack.push(symbol: "binance/usd_m/BTCUSDT", interval: .h4, view: window(10))
    #expect(stack.pop(symbol: "binance/usd_m/BTCUSDT", interval: .h4) == window(10))
    // 只还一次：再切回来就是平常的换周期，贴最新。
    #expect(stack.pop(symbol: "binance/usd_m/BTCUSDT", interval: .h4) == nil)
  }

  @Test("一层层钻下去，往回切时把压在上面的几层一起弹掉")
  func popsTheFramesAboveIt() {
    var stack = DetailZoomStack()
    stack.push(symbol: "binance/usd_m/BTCUSDT", interval: .h4, view: window(10))
    stack.push(symbol: "binance/usd_m/BTCUSDT", interval: .m15, view: window(20))
    // 直接跳回 4h：15m 那一层没人要了。
    #expect(stack.pop(symbol: "binance/usd_m/BTCUSDT", interval: .h4) == window(10))
    #expect(stack.isEmpty)
  }

  @Test("换品种整栈作废——同一段时间在别的品种上什么都不是")
  func forgetsEverythingOnAnotherSymbol() {
    var stack = DetailZoomStack()
    stack.push(symbol: "binance/usd_m/BTCUSDT", interval: .h4, view: window(10))
    #expect(stack.pop(symbol: "binance/usd_m/ETHUSDT", interval: .h4) == nil)
    stack.push(symbol: "binance/usd_m/ETHUSDT", interval: .h4, view: window(30))
    #expect(stack.frames.count == 1)
    #expect(stack.pop(symbol: "binance/usd_m/BTCUSDT", interval: .h4) == nil)
    #expect(stack.pop(symbol: "binance/usd_m/ETHUSDT", interval: .h4) == window(30))
  }

  @Test("同一档只记最近那一次，钻太深的老账自己掉出去")
  func keepsOneFramePerIntervalAndAShallowStack() {
    var stack = DetailZoomStack()
    stack.push(symbol: "binance/usd_m/BTCUSDT", interval: .h4, view: window(10))
    stack.push(symbol: "binance/usd_m/BTCUSDT", interval: .h4, view: window(11))
    #expect(stack.frames.count == 1)
    #expect(stack.pop(symbol: "binance/usd_m/BTCUSDT", interval: .h4) == window(11))

    for (i, iv) in [Interval.mo1, .w1, .d1, .h4, .m15].enumerated() {
      stack.push(symbol: "binance/usd_m/BTCUSDT", interval: iv, view: window(Double(i)))
    }
    #expect(stack.frames.count == DetailZoomStack.maximumDepth)
    #expect(stack.pop(symbol: "binance/usd_m/BTCUSDT", interval: .mo1) == nil)
    #expect(stack.pop(symbol: "binance/usd_m/BTCUSDT", interval: .w1) == window(1))
  }
}
