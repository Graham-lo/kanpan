import CoreGraphics
import KanpanCore
import Testing
import UIKit
@testable import KanpanChart

@MainActor
@Suite("洞察回图价位定位")
struct OrderFlowInsightLocationTests {
  @Test("同所证据价位在close模式也保持真实价、扩大价格视野、清除挂单悬停")
  func explicitEvidencePrice() throws {
    let renderer = BigTradeChartTests.renderer()
    var state = renderer.state
    state.options.crossPrice = .close
    let view = ChartView(state: state)
    view.frame = CGRect(origin: .zero, size: BigTradeChartTests.size)
    view.layoutIfNeeded()
    let time = state.series.lastTime
    let originalRange = try #require(view.renderer?.priceRange(size: view.bounds.size))
    let price = originalRange.hi + (originalRange.hi - originalRange.lo) * 2
    view.placeCrosshair(atTime: time, price: price)
    #expect(view.state?.crosshair?.price == price)
    #expect(view.state?.crosshair?.source == .bigTrade)
    #expect(view.state?.orderFlowSelected == nil)
    let range = try #require(view.renderer?.priceRange(size: view.bounds.size))
    #expect(range.lo < price && range.hi > price)
    let center = try #require(view.renderer?.crosshairCenter(size: view.bounds.size))
    let layout = try #require(view.chartLayout)
    #expect(Double(center.y) > layout.main.y + 7 && Double(center.y) < layout.main.y + layout.main.h - 7)
  }

  @Test("跨所只定位时间；坏价格不会污染十字线和价格轴")
  func timeOnlyAndInvalidPrices() throws {
    let renderer = BigTradeChartTests.renderer()
    let view = ChartView(state: renderer.state)
    view.frame = CGRect(origin: .zero, size: BigTradeChartTests.size)
    view.layoutIfNeeded()
    let index = renderer.state.series.count - 2
    let time = renderer.state.series.time(at: index)
    let originalPrice = view.state?.price
    view.placeCrosshair(atTime: time)
    #expect(view.state?.crosshair?.price == renderer.state.series.close[index])
    #expect(view.state?.price == originalPrice)
    for price in [Double.nan, .infinity, -1, 0] {
      view.placeCrosshair(atTime: time, price: price)
      #expect(view.state?.crosshair?.price == renderer.state.series.close[index])
      #expect(view.state?.price == originalPrice)
    }
  }
}
