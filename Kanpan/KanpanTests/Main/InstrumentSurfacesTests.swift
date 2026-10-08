import Foundation
import Testing
import KanpanChart
import KanpanCore
import KanpanNetwork
@testable import Kanpan

// 行情页上「永远给不出的东西干脆不摆」：头部右侧那块、成交量那一类副图与均价线。
// 只按能力位判，指标布局本身一个字不动。

@Suite("美元指数：给不出的块不摆")
struct InstrumentSurfacesTests {
  private let dxy = MacroProvider.capabilities
  private let perp = BinanceProvider.directCapabilities
  /// 网关档的币安（没有盘口与逐笔方向，其余同直连）。
  private let okx = BinanceProvider.gatewayCapabilities
  private let spot = CoinbaseProvider.capabilities

  @Test("头部右侧那块：一格都给不出（美元指数）才整块不摆，币、美股、现货照旧")
  func headerStatsBlock() {
    #expect(!InstrumentSurfaces.showsHeaderStats(capabilities: dxy, asset: .index))
    #expect(InstrumentSurfaces.showsHeaderStats(capabilities: perp, asset: .crypto))
    #expect(InstrumentSurfaces.showsHeaderStats(capabilities: perp, asset: .equity))
    #expect(InstrumentSurfaces.showsHeaderStats(capabilities: perp, asset: .preciousMetal))
    #expect(InstrumentSurfaces.showsHeaderStats(capabilities: okx, asset: .crypto))
    #expect(InstrumentSurfaces.showsHeaderStats(capabilities: spot, asset: .crypto))
    // 只要还有一格可能有数就摆：没有成交量、但这一类有市值（币）。
    var noVolume = spot; noVolume.hasVolume = false
    #expect(InstrumentSurfaces.showsHeaderStats(capabilities: noVolume, asset: .crypto))
    #expect(!InstrumentSurfaces.showsHeaderStats(capabilities: noVolume, asset: .other))
    // 有资金费率（永续）就有费率与结算两格。
    var fundingOnly = dxy; fundingOnly.hasFunding = true
    #expect(InstrumentSurfaces.showsHeaderStats(capabilities: fundingOnly, asset: .index))
  }

  @Test("副图：没有成交量的品种跳过成交量（连均量）与累计量差，其余顺序原样")
  func subsWithoutVolume() {
    let layout: [IndicatorID] = [.vol, .macd, .oi, .cvd, .rsi, .lsr]
    #expect(InstrumentSurfaces.subs(layout, capabilities: dxy) == [.macd, .rsi])
    #expect(InstrumentSurfaces.subs(layout, capabilities: perp) == layout)
    // 现货：外部指标不画，成交量照旧。
    #expect(InstrumentSurfaces.subs(layout, capabilities: spot) == [.vol, .macd, .cvd, .rsi])
    // 只剩成交量一格时整个副图区都收掉，不留一块空的。
    #expect(InstrumentSurfaces.subs([.vol], capabilities: dxy).isEmpty)
  }

  @Test("主图叠加：没有成交量时 VWAP 不画，MA、BOLL 照旧")
  func overlaysWithoutVolume() {
    let layout: [IndicatorID] = [.ma, .vwap, .boll]
    #expect(InstrumentSurfaces.overlays(layout, capabilities: dxy) == [.ma, .boll])
    #expect(InstrumentSurfaces.overlays(layout, capabilities: perp) == layout)
    #expect(InstrumentSurfaces.overlays(layout, capabilities: spot) == layout)
  }

  @Test("要成交量的只有成交量、累计量差、VWAP 三把")
  func needsVolume() {
    #expect(IndicatorID.allCases.filter(\.needsVolume) == [.vwap, .vol, .cvd])
  }

  @Test("十字线读数：没有成交量时不写「量」")
  @MainActor func crosshairWithoutVolume() {
    let series = BarSeries(symbol: "macro/index/DXY", interval: .h1,
                           bars: [Bar(openTime: 1_700_000_000_000, open: 99.1, high: 99.5, low: 98.9, close: 99.2, volume: 0)])
    let base = CrosshairContext(seriesSource: { series }, symbol: "macro/index/DXY", interval: .h1,
                                decimals: 3, offsetMinutes: .fixed(480), enabled: true)
    var noVolume = base; noVolume.hasVolume = false
    let c = Crosshair(index: 0, price: 99.2)
    #expect(crosshairOHLCText(c, base)?.contains("量 ") == true)
    let text = crosshairOHLCText(c, noVolume)
    #expect(text?.contains("量") == false)
    #expect(text?.hasSuffix("收 99.200") == true)
  }
}
