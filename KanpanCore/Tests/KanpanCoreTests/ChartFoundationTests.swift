import Foundation
import Testing
@testable import KanpanCore

@Suite("图表底座补全")
struct ChartFoundationTests {
  @Test("高度联动所有pane而非横向时间映射")
  func heights() {
    for count in [3, 4] {
      let subs = Array([IndicatorID.vol, .oi, .macd, .kdj].prefix(count))
      let layouts = [0.0, 0.5, 1.0].map { control in
        let h = ChartContentLayout.height(viewport: 540, subs: subs, portrait: true)
        return Layout(width: 393, height: h, subs: subs,
          mainWeight: ChartContentLayout.mainWeight(height: h, control: control, count: count))
      }
      for layout in layouts {
        #expect(layout.H == 540)
        #expect(layout.plotW == layouts[0].plotW)
        #expect(abs(layout.panes.last!.y + layout.panes.last!.h - 540) < 1e-8)
        #expect(layout.panes.dropFirst().allSatisfy { $0.h >= 40 })
      }
      #expect(layouts[2].mainH > layouts[0].mainH)
      #expect(layouts[2].panes[1].h < layouts[0].panes[1].h)
    }
  }

  @Test("手调副图在固定屏幕内重新分配高度并约束极限")
  func panelResize() {
    let subs: [IndicatorID] = [.vol, .oi, .macd]
    let layout = Layout(width: 393, height: 540, subs: subs)
    let pane = layout.panes[1], content = layout.H - AICoinBehavior.timeHeight
    let scale = SubPaneResize.scale(initialHeight: pane.h, translation: 35, contentHeight: content, otherWeight: 5)
    let resized = Layout(width: 393, height: 540, subs: subs, subScale: [.vol: scale])
    #expect(abs(resized.panes[1].h - pane.h - 35) < 1e-8)
    #expect(resized.H == layout.H && resized.plotW == layout.plotW)
    #expect(resized.panes.last!.y + resized.panes.last!.h <= 540.00001)
    #expect(SubPaneResize.scale(initialHeight: pane.h, translation: -1e5, contentHeight: content, otherWeight: 5) == 0.5)
    #expect(SubPaneResize.scale(initialHeight: pane.h, translation: 1e5, contentHeight: content, otherWeight: 5) == 2)
  }

  @Test("卡片在不同容器宽高内换边")
  func cards() {
    for width in [180.0, 343, 900] {
      for height in [80.0, 190, 500] {
        let left = CandleDataBox.rect(plotWidth: width, mainHeight: height, selectedX: 20, desiredWidth: 140, desiredHeight: 96)
        let right = CandleDataBox.rect(plotWidth: width, mainHeight: height, selectedX: width - 20, desiredWidth: 140, desiredHeight: 96)
        #expect(left.x >= right.x)
        // 框永远在十字线的另一侧：宽度放得下的时候，十字线那一侧的 K 线一根都不盖。
        if width - 8 > 140 * 2 {
          #expect(left.x > 20, "十字线在左半，框该贴右边")
          #expect(right.x + right.width < width - 20, "十字线在右半，框该贴左边")
        }
        for box in [left, right] {
          #expect(box.x >= 0 && box.y >= 0)
          #expect(box.x + box.width <= width && box.y + box.height <= height)
        }
      }
    }
    // 纵向从图例下沿起，不压均线读数；主图矮到放不下时才往上让。
    #expect(CandleDataBox.rect(plotWidth: 343, mainHeight: 400, selectedX: 20,
                               desiredWidth: 140, desiredHeight: 96, top: 52).y == 52)
    #expect(CandleDataBox.rect(plotWidth: 343, mainHeight: 110, selectedX: 20,
                               desiredWidth: 140, desiredHeight: 96, top: 52).y == 10)
  }

  @Test("价格三个模式正常倒置映射和百分比首个相交列")
  func coordinates() {
    let series = synthSeries(count: 100, seed: 312)
    let view = ViewWindow(from: Double(series.time(at: 25)) - Double(series.step) * 0.4,
                          to: Double(series.time(at: 50)))
    let auto = priceRange(view: view, series: series)
    #expect(auto.base == series.close[25])
    for mode in PriceMode.allCases {
      for inverted in [false, true] {
        var range = PriceRange(lo: 100, hi: 500, base: 250); range.inverted = inverted
        let pane = Pane(indicator: nil, y: 31, h: 173)
        for price in [100.0, 173, 250, 500] {
          let y = yOf(price, pane: pane, range: range, mode: mode)
          #expect(abs(pOf(y, pane: pane, range: range, mode: mode) - price) < 1e-9)
        }
      }
    }
  }

  @Test("宽容器少量数据使用完整400虚拟列边界，历史焦点不读靠右设置")
  func boundsAndFocus() {
    #expect(ViewMath.maximumOffset(count: 1, spacing: 1.6, plotW: 3000, anchor: .center) == 860)
    let series = synthSeries(count: 1200, seed: 4)
    for anchor in [ViewAnchor.left, .center, .right] {
      let v = ViewWindow(to: Double(series.time(at: 600)), span: Double(series.step) * 80)
      let scaled = ViewMath.scaled(v, series: series, plotW: 340, factor: 1.6, focus: 113, anchor: anchor)
      #expect(abs(scaled.t(atX: 113, plotW: 340) - v.t(atX: 113, plotW: 340)) < 0.01)
      let maxed = ViewMath.scaled(v, series: series, plotW: 340, factor: 1e9, focus: 113, anchor: anchor)
      let back = ViewMath.scaled(maxed, series: series, plotW: 340, factor: 0.9, focus: 113, anchor: anchor)
      #expect(abs(back.barSpacing(step: series.step, plotW: 340) - 36) < 1e-8)
    }
  }

  @Test("副图整区长按命中，排除主图、坐标轴、面板外与负坐标")
  func reorderWholePane() {
    let panes = [Pane(indicator: nil, y: 0, h: 300), Pane(indicator: .vol, y: 317, h: 100),
      Pane(indicator: .oi, y: 417, h: 80)]
    #expect(ChartGestureRoute.reorderPane(x: 200, y: 380, plotWidth: 340, panes: panes) == .vol)
    #expect(ChartGestureRoute.reorderPane(x: 339, y: 417, plotWidth: 340, panes: panes) == .oi)
    for (x, y) in [(200.0, 100.0), (340, 380), (-1, 380), (100, 497)] {
      #expect(ChartGestureRoute.reorderPane(x: x, y: y, plotWidth: 340, panes: panes) == nil)
    }
  }

  @Test("页面纵拖与图表手势路由互斥")
  func routing() {
    func page(_ x: Double = 100, _ y: Double = 100, dx: Double = 2, dy: Double = 40,
              touches: Int = 1, manual: Bool = false, selecting: Bool = false) -> Bool {
      ChartGestureRoute.pageScroll(x: x, y: y, dx: dx, dy: dy, touches: touches,
        plotWidth: 340, mainHeight: 300, manualY: manual, selecting: selecting)
    }
    #expect(page())
    #expect(!page(dx: 40, dy: 2))
    #expect(!page(touches: 2))
    #expect(!page(manual: true))
    #expect(!page(selecting: true))
    #expect(!page(360, 100))
    #expect(page(360, 400))
    #expect(page(100, 400, manual: true))
  }
}

@Suite("完整历史OI") struct HistoricalOITests {
  @Test("多年稀疏OI保留前后端，不在五万格处截断，也不提前使用未来样本")
  func sparseYears() {
    let year: Int64 = 365 * 86_400_000
    let oi = OISeries(points: [.init(time: 300_000, value: 10), .init(time: year, value: 20), .init(time: 3 * year, value: 30)])
    var bars = BarSeries(symbol: "BTCUSDT", interval: .d1, bars: [
      Bar(openTime: 0, open: 1, high: 1, low: 1, close: 1, volume: 1),
      Bar(openTime: year - 300_000, open: 1, high: 1, low: 1, close: 1, volume: 1),
      Bar(openTime: year, open: 1, high: 1, low: 1, close: 1, volume: 1),
      Bar(openTime: 3 * year, open: 1, high: 1, low: 1, close: 1, volume: 1)])
    bars.openTime = [0, year - 300_000, year, 3 * year]
    let values = oi.aligned(to: bars)
    #expect(values[0].isNaN)
    #expect(values[1] == 10 && values[2] == 20 && values[3] == 30)
    #expect(oi.values.count == 3)
  }
}
