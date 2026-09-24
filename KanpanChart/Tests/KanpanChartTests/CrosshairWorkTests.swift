import CoreGraphics
import Foundation
import KanpanCore
import Testing
import UIKit

@testable import KanpanChart

private final class WorkTouch: UITouch {
  var point: CGPoint
  init(_ x: Double, _ y: Double) { point = CGPoint(x: x, y: y); super.init() }
  override func location(in view: UIView?) -> CGPoint { point }
}

private final class WorkEvent: UIEvent {
  let time: Double
  init(_ ms: Double) { time = ms / 1000; super.init() }
  override var timestamp: TimeInterval { time }
}

// MARK: - 十字线跟手时到底重算了什么（A6 第二轮审查：先测量再改）
//
// 十字线每移动一次就赋一次 `ChartRenderer.state`。指标输入一个没动——同一份 K 线、
// 同一批叠加与副图、同一组参数——所以布局、价格区间、隐藏输出掩码本该一次都不用重算。
// 这个套件就是那笔账的秤：`ChartWorkCounter` 数的是「某件事真的算了一遍」的次数，
// 不是调用次数（缓存命中不计数）。
//
// 口径：3 个副图 + 主副图都开着隐藏输出，一帧按 `ChartView` 的三层各画一次。
//
// # 为什么这里有 `#if DEBUG`（第五轮审查 C.5 / C.8）
//
// `ChartWorkCounter` 的存储**只在 DEBUG 下存在**，Release 里 `bump` 是空函数体、
// `count` 恒返回 0（见 `ChartWorkCounter` 的注释：这条计数趴在渲染热路径上，
// 出厂二进制里一个字节的开销都不该留）。于是这个套件在 Release 配置下有两种坏法：
//
// - **直接红**：`dataChangesStillRebuild` 与 `chartViewMovesFireOnceEach` 断言的是
//   「== 1」「== 100」，读回来的却是恒定的 0；
// - **更糟的是假绿**：`<= 1` / `== 0` 这类上界断言在 Release 下永远成立，
//   它们什么都没证明，却会让人以为「Release 也验过了」。
//
// 两条路二选一：把计数器在测试构建里也备齐，或者把靠计数器的用例圈进 DEBUG。
// **选后者**，理由和 `8733e3f` 修 KanpanAccount 时一样——那些钩子在 Release 里
// 本来就不该存在，为了让测试能跑而把它们装回去，等于为测试改产品。计数是「先测量
// 再改」留下的秤，不是产品行为；产品行为（一次移动一条回调、旧副本不串状态、
// 单击不连送两遍）在下面照旧两种配置都编、都跑。
@MainActor @Suite(.serialized) struct CrosshairWorkTests {
  let size = CGSize(width: 393, height: 780)

  /// 三个副图、主图和副图都藏了输出的一份 state。
  func heavyState() -> ChartState {
    var s = Evidence.state(
      dark: false, size: size,
      overlays: [.ma, .ema], subs: [.vol, .macd, .rsi])
    s.params[.ema] = [12, 26, 60]
    // 藏输出 = 每次重建缓存都要现开一条整列 NaN：这正是要数的那件事。
    s.hiddenOutputs = [.ma: [1], .ema: [2], .macd: [0], .rsi: [1]]
    return s
  }

  /// 画一帧：和 `ChartView` 的三层一致（plot / live / cross）。
  func frame(_ renderer: ChartRenderer) {
    let f = UIGraphicsImageRendererFormat.preferred()
    f.scale = 3
    f.opaque = false
    _ = UIGraphicsImageRenderer(size: size, format: f).image { ctx in
      renderer.drawPlot(in: ctx.cgContext, size: size, scale: 3)
      renderer.drawLive(in: ctx.cgContext, size: size, scale: 3)
      renderer.drawCross(in: ctx.cgContext, size: size, scale: 3)
    }
  }

  // 下面这三条（以及它们共用的 `counts()`）全靠 `ChartWorkCounter` 读数，而那份存储
  // 只在 DEBUG 下存在（见文件头「为什么这里有 `#if DEBUG`」）：Release 里读回来的是
  // 恒定的 0，断言要么直接红，要么为了错的理由变绿。所以整段圈进 DEBUG，
  // 并记在 `ReleaseTestRosterTests.debugOnly` 与 Makefile 的 Release 差集清单上。
  #if DEBUG
  func counts() -> (geometry: Int, layout: Int, range: Int, mask: Int) {
    (ChartWorkCounter.count(.geometryCache), ChartWorkCounter.count(.layout),
     ChartWorkCounter.count(.priceRange), ChartWorkCounter.count(.hiddenMask))
  }

  @Test("100 次十字线移动不重算几何、布局与隐藏掩码")
  func crosshairMovesDoNotRebuildGeometry() {
    var s = heavyState()
    var renderer = ChartRenderer(state: s)
    frame(renderer)  // 预热：该建的缓存先建起来，后面数的才是「移动带来的」

    ChartWorkCounter.reset()
    let moves = 100
    for k in 0..<moves {
      s.crosshair = Crosshair(index: 120 + k % 60, price: s.series.close[120 + k % 60] * 1.001)
      renderer.state = s
      frame(renderer)
    }
    let c = counts()
    print(ChartWorkCounter.line("crosshair-moves=\(moves)"))

    #expect(c.geometry <= 1, "十字线移动不该新建几何缓存：\(c.geometry)")
    #expect(c.layout <= 1, "十字线移动不该重算布局：\(c.layout)")
    #expect(c.range <= 1, "十字线移动不该重扫价格区间：\(c.range)")
    #expect(c.mask <= 1, "十字线移动不该重建隐藏输出掩码：\(c.mask)")
  }

  @Test("100 步拖图、100 步拖画线：输入层一次都不作废，画线连视野层也不碰")
  func panAndDrawingDragKeepInputTier() {
    var s = heavyState()
    s.drawings = [Drawing(kind: .trend, points: [
      DrawPoint(t: Double(s.series.time(at: 150)), p: s.series.close[150]),
      DrawPoint(t: Double(s.series.time(at: 190)), p: s.series.close[190]),
    ])]
    var renderer = ChartRenderer(state: s)
    frame(renderer)

    ChartWorkCounter.reset()
    for _ in 0..<100 {
      s.view.to -= Double(s.series.step) * 0.5
      renderer.state = s
      frame(renderer)
    }
    var c = counts()
    print(ChartWorkCounter.line("pan-100"))
    #expect(c.geometry == 0 && c.mask == 0, "拖图不该作废输入层：\(c)")
    #expect(ChartWorkCounter.count(.viewportCache) == 100)

    ChartWorkCounter.reset()
    for k in 0..<100 {
      s.drawings[0].points[1].p *= (k % 2 == 0 ? 1.001 : 0.9995)
      renderer.state = s
      frame(renderer)
    }
    c = counts()
    print(ChartWorkCounter.line("drawing-drag-100"))
    #expect(c.geometry == 0 && c.layout == 0 && c.range == 0 && c.mask == 0, "拖画线不该碰几何：\(c)")
    #expect(ChartWorkCounter.count(.viewportCache) == 0)
  }

  @Test("倒计时每秒走一格也不重算几何")
  func countdownDoesNotRebuildGeometry() {
    var s = heavyState()
    s.options.countdown = true
    s.nowMs = 1_600_000_000_000
    var renderer = ChartRenderer(state: s)
    frame(renderer)

    ChartWorkCounter.reset()
    for k in 1...60 {
      s.nowMs = 1_600_000_000_000 + Double(k) * 1000
      renderer.state = s
      frame(renderer)
    }
    let c = counts()
    print(ChartWorkCounter.line("countdown-ticks=60"))
    #expect(c.geometry <= 1 && c.layout <= 1 && c.range <= 1 && c.mask <= 1)
  }

  @Test("数据、周期、副图数一变，缓存照样作废重建")
  func dataChangesStillRebuild() {
    var s = heavyState()
    var renderer = ChartRenderer(state: s)
    frame(renderer)

    // ① 末根跳动
    ChartWorkCounter.reset()
    var ticked = s.series
    let last = ticked.bar(at: ticked.count - 1)
    ticked.replaceLast(with: Bar(openTime: last.openTime, open: last.open,
                                 high: last.high * 1.01, low: last.low,
                                 close: last.close * 1.005, volume: last.volume + 1))
    s.series = ticked
    renderer.state = s
    frame(renderer)
    var c = counts()
    print(ChartWorkCounter.line("last-bar-tick"))
    #expect(c.geometry == 1, "末根变了必须换一只新缓存：\(c.geometry)")
    #expect(c.layout == 1 && c.range >= 1, "末根变了布局与价格区间必须重算：\(c)")

    // ② 新开一根（相当于周期到点）
    ChartWorkCounter.reset()
    var grown = s.series
    let tail = grown.bar(at: grown.count - 1)
    grown.append(Bar(openTime: tail.openTime + s.series.step, open: tail.close,
                     high: tail.close * 1.002, low: tail.close * 0.998,
                     close: tail.close * 1.001, volume: 10))
    s.series = grown
    renderer.state = s
    frame(renderer)
    c = counts()
    print(ChartWorkCounter.line("new-bar"))
    #expect(c.geometry == 1 && c.layout == 1)

    // ③ 换周期：整条序列换人
    ChartWorkCounter.reset()
    s.series = BarSeries(symbol: s.series.symbol, interval: .m15, t0: s.series.t0,
                         open: s.series.open, high: s.series.high, low: s.series.low,
                         close: s.series.close, volume: s.series.volume)
    renderer.state = s
    frame(renderer)
    c = counts()
    print(ChartWorkCounter.line("interval-switch"))
    #expect(c.geometry == 1 && c.layout == 1)

    // ④ 副图数量变（3 → 2）：面板高度全变了
    ChartWorkCounter.reset()
    s.subs = [.vol, .macd]
    renderer.state = s
    frame(renderer)
    c = counts()
    print(ChartWorkCounter.line("subs-3-to-2"))
    #expect(c.geometry == 1 && c.layout == 1)

    // ⑤ 视野（滚动 / 缩放）：只换视野层——布局（轴宽按这一屏的刻度量）与价格区间
    // 重算，输入层（掩码、叠加线、图例内缩）留着（审查 23.4）。
    ChartWorkCounter.reset()
    s.view.to += Double(s.series.step) * 3
    renderer.state = s
    frame(renderer)
    c = counts()
    print(ChartWorkCounter.line("view-pan"))
    #expect(c.geometry == 0 && c.mask == 0, "拖图不该作废输入层：\(c)")
    #expect(ChartWorkCounter.count(.viewportCache) == 1 && c.layout == 1)

    // ⑤b 拖分隔线（副图倍率）：视野层作废，输入层留着
    ChartWorkCounter.reset()
    s.subScale[.macd] = 1.2
    renderer.state = s
    frame(renderer)
    c = counts()
    print(ChartWorkCounter.line("divider"))
    #expect(c.geometry == 0 && c.mask == 0 && c.layout == 1)

    // ⑤c 换皮肤：输入层作废
    ChartWorkCounter.reset()
    s.dark.toggle()
    renderer.state = s
    frame(renderer)
    c = counts()
    print(ChartWorkCounter.line("skin"))
    #expect(c.geometry == 1 && c.layout == 1)

    // ⑥ 隐藏输出改了：掩码必须跟着重建
    ChartWorkCounter.reset()
    s.hiddenOutputs[.rsi] = [0]
    renderer.state = s
    frame(renderer)
    c = counts()
    print(ChartWorkCounter.line("hidden-outputs"))
    #expect(c.geometry == 1 && c.mask >= 1)
  }
  #endif

  @Test("ChartView 上 100 次十字线移动：一次移动一条回调，几何不重建")
  func chartViewMovesFireOnceEach() {
    let v = ChartView(frame: CGRect(origin: .zero, size: size))
    v.state = heavyState()
    var delivered: [Crosshair?] = []
    v.onCrosshairChanged = { delivered.append($0) }

    ChartWorkCounter.reset()
    for k in 0..<100 {
      let i = 120 + k % 60
      v.state?.crosshair = Crosshair(index: i, price: v.state!.series.close[i] * 1.001)
    }
    print(ChartWorkCounter.line("chartview-moves=100"))

    // 「一次移动一条回调」是产品行为，两种配置都验。
    #expect(delivered.count == 100, "一次移动应当只回调一次：\(delivered.count)")
    #if DEBUG
    // 秤上的读数只有 DEBUG 才有；Release 下这两条读回来的是恒定的 0（见文件头）。
    #expect(ChartWorkCounter.count(.crosshairCallback) == 100)
    #expect(ChartWorkCounter.count(.geometryCache) == 0, "十字线移动不该新建几何缓存")
    #endif
  }

  @Test("单击落十字线不把同一份读数连送两遍")
  func tapDoesNotDeliverTheSameCrosshairTwice() {
    let v = ChartView(frame: CGRect(origin: .zero, size: size))
    v.state = heavyState()
    var delivered: [Crosshair?] = []
    v.onCrosshairChanged = { delivered.append($0) }

    ChartWorkCounter.reset()
    let t = WorkTouch(180, 300)
    v.touchesBegan([t], with: WorkEvent(1000))
    v.touchesEnded([t], with: WorkEvent(1020))
    print(ChartWorkCounter.line("single-tap"))

    #expect(v.state?.crosshair != nil, "单击应当落下十字线")
    #expect(!delivered.isEmpty)
    #expect(zip(delivered, delivered.dropFirst()).allSatisfy { $0 != $1 },
            "同一份十字线被连送了两遍：\(delivered.count) 次回调")
  }

  @Test("留着旧 state 的副本仍然画得对——缓存不许串状态")
  func staleCopiesStayCorrect() {
    var s = heavyState()
    s.crosshair = Crosshair(index: 100, price: s.series.close[100])
    let a = ChartRenderer(state: s)
    let aRange = a.priceRange(size: size)
    let aLayout = a.layout(size: size)

    // 从 a 复制一份，只动十字线（几何输入没变）→ 两边的几何必须仍然各自正确。
    var b = a
    var s2 = s
    s2.crosshair = Crosshair(index: 40, price: s.series.close[40])
    b.state = s2
    #expect(b.priceRange(size: size) == aRange)
    #expect(a.priceRange(size: size) == aRange)

    // 再从 a 复制一份，动视野（几何输入变了）→ b2 必须重算，a 一个数都不能被改。
    var b2 = a
    var s3 = s
    s3.view.to += Double(s.series.step) * 40
    s3.view.span *= 1.5
    b2.state = s3
    let movedRange = b2.priceRange(size: size)
    #expect(a.priceRange(size: size) == aRange, "旧副本的价格区间被新 state 串了")
    #expect(a.layout(size: size) == aLayout)
    #expect(movedRange == ChartRenderer(state: s3).priceRange(size: size),
            "新 state 必须重算出自己的价格区间，不许复用旧缓存")
    #expect(b2.layout(size: size) == ChartRenderer(state: s3).layout(size: size))
  }
}
