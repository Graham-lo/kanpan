import CoreGraphics
import Foundation
import KanpanCore
import Testing
import UIKit
@testable import KanpanChart

@MainActor @Suite(.serialized) struct CompareChartTests {
  let size = CGSize(width: 402, height: 680)
  func fixture() -> ChartState {
    let bars = BarSeries(symbol: "BTCUSDT", interval: .m1, t0: 0,
      open: [100, 110, 120, 130, 140], high: [112, 122, 132, 142, 152],
      low: [98, 108, 118, 128, 138], close: [110, 120, 130, 140, 150], volume: [1, 2, 3, 4, 5])
    var state = ChartState(series: bars, symbol: Fixture.symbol,
      view: ViewWindow(from: 60_000, to: 240_000), subs: [.vol])
    state.percentAxis = true
    state.compare = [CompareSeries(key: "binance/usd_m/ETHUSDT", name: "ETH", color: "#FFB400",
      open: [10, 11, 12, 13, 14], close: [11, 12, nil, 14, 15])]
    return state
  }

  @Test func openBaseMovesWithPanAndZoom() {
    var s = fixture()
    #expect(ChartRenderer(state: s).priceRange(size: size).base == 110)
    #expect(abs(ChartRenderer(state: s).compareLegend[1].value! - (15.0 / 11 - 1) * 100) < 1e-9)
    s.view = ViewWindow(from: 120_000, to: 240_000)
    let moved = ChartRenderer(state: s)
    #expect(moved.priceRange(size: size).base == 120)
    #expect(moved.compareLegend[1].value == 25)
    #expect(moved.mainPriceTicks(range: moved.priceRange(size: size), paneHeight: 400).contains(0))
  }

  @Test func gapsAndMissingBaseStayMissing() {
    var s = fixture(); s.crosshair = Crosshair(index: 2)
    #expect(ChartRenderer(state: s).compareLegend[1].value == nil)
    s.compare[0].open[1] = nil
    #expect(s.compare[0].percent(at: 4, baseIndex: 1) == nil)
    #expect(ChartState.comparePercentLabel(nil) == "—")
    #expect(ChartState.comparePercentLabel(0) == "0%")
    #expect(ChartState.comparePercentLabel(3.214) == "+3.21%")
    #expect(ChartState.comparePercentLabel(-0.0001) == "0%")
    #expect(ChartState.comparePercentLabel(-3.214) == "-3.21%")
  }

  @Test func axisCandlesAndCrosshairUseSameBase() {
    var s = fixture(); s.crosshair = Crosshair(index: 1, price: 110)
    let renderer = ChartRenderer(state: s), range = renderer.priceRange(size: size)
    let center = renderer.crosshairCenter(size: size)!
    let pane = renderer.layout(size: size).main
    #expect(abs(center.y - yOf(110, pane: pane, range: range, mode: .percent)) < 1e-9)
    #expect(renderer.axisLabel(110, range: range) == "0%")
    #expect(renderer.axisLabel(121, range: range) == "+10.00%")
    #expect(renderer.compareLegend[1].value == renderer.compareLegend[0].value)
    #expect(renderer.candleXs(size: size, scale: 3).allSatisfy { $0.bodyTop.isFinite && $0.bodyHeight.isFinite })
  }

  @Test func crosshairDoesNotInvalidateCompareGeometry() {
    var s = fixture(), renderer = ChartRenderer(state: fixture())
    let baseline = renderer.priceRange(size: size)
    for i in 0..<5 {
      s.crosshair = Crosshair(index: i)
      #expect(s.sameGeometryInputs(as: renderer.state))
      renderer.state = s
      #expect(renderer.priceRange(size: size) == baseline)
    }
    s.compare[0].close[4] = 100
    #expect(ChartView.changed(from: renderer.state, to: s) == .all)
    #expect(!s.sameGeometryInputs(as: renderer.state))
    renderer.state = s
    #expect(renderer.priceRange(size: size).hi > baseline.hi)
  }

  @Test func fixtureRendersThreeSeriesAndExportsEvidence() throws {
    var s = Evidence.state(dark: false, size: size, subs: [.vol, .macd, .rsi])
    s.percentAxis = true
    for (k, name) in ["ETH", "SOL", "DOGE"].enumerated() {
      let factor = Double(k + 2)
      let closes: [Double?] = s.series.close.enumerated().map { i, v in
        i % 53 == 0 ? nil : v / factor * (1 + Double(k + 1) * sin(Double(i) / 11) * 0.002)
      }
      s.compare.append(CompareSeries(key: "binance/usd_m/" + name + "USDT", name: name, color: s.colors.palette[k],
        open: s.series.open.map { $0 / factor }, close: closes))
    }
    let image = Evidence.render(s, size: size, scale: 3)
    let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    try UIImage(cgImage: image).pngData()!.write(to: root.appendingPathComponent("docs/acceptance/对比K线-2026-09-22/阶段1-夹具.png"))
    #expect(image.width == 1206)
  }
}
