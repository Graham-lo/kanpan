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

  /// 审查 B·P1-2 改了口径：主品种基准根上比价品种缺开盘价时，这条线不再整条作废，
  /// 而是改认它自己在视野里第一根有开盘价的那根当 0%。缺的收盘照旧是缺口。
  @Test func gapsAndMissingBaseStayMissing() {
    var s = fixture(); s.crosshair = Crosshair(index: 2)
    #expect(ChartRenderer(state: s).compareLegend[1].value == nil)
    s.compare[0].open[1] = nil
    // 底层读数仍是「给哪根当基准就认哪根」：那一根缺开盘价就是缺。
    #expect(s.compare[0].percent(at: 4, baseIndex: 1) == nil)
    // 图上的基准顺延到下一根有开盘价的（第 2 根，开 12）。
    s.crosshair = Crosshair(index: 4)
    #expect(ChartRenderer(state: s).compareLegend[1].value == 25)
    s.crosshair = Crosshair(index: 1)
    #expect(ChartRenderer(state: s).compareLegend[1].value == nil, "基准之前没有涨跌可言")
    #expect(ChartState.comparePercentLabel(nil) == "—")
    #expect(ChartState.comparePercentLabel(0) == "0%")
    #expect(ChartState.comparePercentLabel(3.214) == "+3.21%")
    #expect(ChartState.comparePercentLabel(-0.0001) == "0%")
    #expect(ChartState.comparePercentLabel(-3.214) == "-3.21%")
  }

  /// 审查 B·P1-2：比价品种在视野左段整段没数据（还没上市 / 数据没到）时，
  /// 从前整条线一个点都不画、图例一路「—」；现在从它第一根有数据的那根起画，那一根就是 0%。
  @Test func compareLineStartsAtFirstAvailableBar() {
    var s = fixture()
    s.compare[0].open = [nil, nil, nil, 13, 14]
    s.compare[0].close = [nil, nil, nil, 14, 15]
    let renderer = ChartRenderer(state: s)
    let anchor = renderer.compareAnchor(s.compare[0])
    #expect(anchor?.baseIndex == 3 && anchor?.from == 3)
    let L = renderer.layout(size: size), r = renderer.priceRange(size: size)
    let segments = renderer.compareSegments(pane: L.main, r: r, L: L)
    #expect(segments.count == 1 && segments[0].count == 1)
    #expect(segments[0].first?.count == 2, "应从第 3 根画到第 4 根：\(segments)")
    // 第 3 根的收盘相对于它自己的开盘（14 / 13），而不是相对于主品种基准根。
    let points = renderer.compareLines()[0].percents.compactMap { $0 }
    #expect(points.map(\.index) == [3, 4])
    #expect(abs(points[0].percent - (14.0 / 13 - 1) * 100) < 1e-9)
    var crossed = s; crossed.crosshair = Crosshair(index: 4)
    #expect(abs(ChartRenderer(state: crossed).compareLegend[1].value! - (15.0 / 13 - 1) * 100) < 1e-9)
    crossed.crosshair = Crosshair(index: 2)
    #expect(ChartRenderer(state: crossed).compareLegend[1].value == nil)
    // 基准就是主品种那根时照旧从可见段最左起画（左侧护栏根也画），老行为不变。
    let plain = ChartRenderer(state: fixture())
    #expect(plain.compareAnchor(fixture().compare[0])?.baseIndex == fixture().compareBaseIndex())
    // 整个可见段一根开盘价都没有：不画、不撑区间、图例「—」。
    var empty = fixture()
    empty.compare[0].open = [nil, nil, nil, nil, nil]
    let blank = ChartRenderer(state: empty)
    #expect(blank.compareAnchor(empty.compare[0]) == nil)
    #expect(blank.compareLegend[1].value == nil)
    let bl = blank.layout(size: size)
    #expect(blank.compareSegments(pane: bl.main, r: blank.priceRange(size: size), L: bl)[0].isEmpty)
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
      #expect(s.changedLayers(from: renderer.state) == .overlay)
      renderer.state = s
      #expect(renderer.priceRange(size: size) == baseline)
    }
    s.compare[0].close[4] = 100
    #expect(ChartView.changed(from: renderer.state, to: s) == .all)
    #expect(s.changedLayers(from: renderer.state).contains(.input))
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
