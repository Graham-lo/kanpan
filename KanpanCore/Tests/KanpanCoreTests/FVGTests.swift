import Foundation
import Testing
@testable import KanpanCore

/// 公允价值缺口的黄金样例：`Fixtures/fvg.json`，手机网页与电脑网页的 `Web/tests/fvg.test.ts` 读同一份。
/// 比的是逐位相等（缺口边界都是原样的高低价或两者之半，没有舍入可言）。
@Suite("公允价值缺口 fvg.json")
struct FVGTests {
  struct Case: Decodable, Sendable {
    struct Want: Decodable, Equatable, Sendable {
      var side: String
      var startMs: Int64
      var top: Double
      var bottom: Double
      var mid: Double
      var midVisible: Bool
    }
    var name: String
    var closedCount: Int
    var config: FVGConfig
    var bars: [[Double]]
    var expected: [Want]

    var barList: [Bar] {
      bars.map { Bar(openTime: Int64($0[0]), open: $0[1], high: $0[2], low: $0[3], close: $0[4], volume: 0) }
    }
  }

  static let cases: [Case] = try! JSONDecoder().decode([Case].self, from: Fixture.data("fvg"))

  static func shape(_ zs: [FVGZone]) -> [Case.Want] {
    zs.map { .init(side: $0.side.rawValue, startMs: $0.startMs, top: $0.top, bottom: $0.bottom, mid: $0.mid, midVisible: $0.midVisible) }
  }

  @Test("黄金样例逐例一致（单根数组与列式序列两条入口）", arguments: FVGTests.cases.indices)
  func golden(_ i: Int) {
    let c = Self.cases[i]
    let bars = c.barList
    let got = Self.shape(fvgZones(bars: bars, closedCount: c.closedCount, config: c.config))
    #expect(got == c.expected, "\(c.name)")
    let series = BarSeries(symbol: "FVG", interval: .m1, bars: bars)
    let viaSeries = Self.shape(fvgZones(series: series, closedCount: c.closedCount, config: c.config))
    #expect(viaSeries == c.expected, "\(c.name)（列式）")
  }

  @Test("样例覆盖面：至少一例出厂参数、一例多空都有")
  func coverage() {
    #expect(Self.cases.contains { $0.config == .standard && $0.bars.count >= 40 })
    #expect(Self.cases.contains { c in Set(c.expected.map(\.side)) == ["bull", "bear"] })
  }

  @Test("出厂参数只来自 Analysis/fvg.json")
  func standardConfig() {
    #expect(FVGConfig.standard == FVGConfig(trPeriod: 14, minTrRatio: 0.25, maxAgeBars: 500, perSide: 6))
  }

  @Test("自动图层白名单")
  func autoLayers() {
    #expect(AutoLayer.allCases.map(\.rawValue) == ["FVG"])
  }
}
