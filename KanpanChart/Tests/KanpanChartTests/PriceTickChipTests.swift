import CoreGraphics
import Foundation
import KanpanCore
import Testing
import UIKit

@testable import KanpanChart

/// 右轴上的刻度字不许被最新价胶囊盖掉半截（2026-10-04 深度审查 G 线走查）。
///
/// 走查截到 BTC 1h：最新价胶囊 84895.1 压在刻度 84965.5 上，刻度上半截被实底盖住、
/// 下半截从胶囊底下露出来。现在和胶囊有一点交叠的刻度字整条不写，网格线照画。
@MainActor
@Suite("最新价胶囊让开刻度字")
struct PriceTickChipTests {
  static let size = CGSize(width: 402, height: 520)

  /// 定版快照，把末根收盘挪到 `close`（高低跟着包住它），其余不动。
  static func renderer(close: Double? = nil, lastLine: Bool = true) -> ChartRenderer {
    let s = Fixture.series
    var c = s.close, h = s.high, l = s.low
    if let close {
      c[c.count - 1] = close
      h[h.count - 1] = max(h[h.count - 1], close)
      l[l.count - 1] = min(l[l.count - 1], close)
    }
    let b = BarSeries(symbol: "BTCUSDT", interval: s.interval, t0: s.t0, step: s.step,
                      open: s.open, high: h, low: l, close: c, volume: s.volume)
    let L = Layout(width: size.width, height: size.height, subs: [.vol, .macd])
    let info = SymbolInfo(symbol: "BTCUSDT", base: "BTC", quote: "USDT", pricePrecision: 2, tickSize: 0.1)
    var options = ChartOptions()
    options.lastLine = lastLine
    let st = ChartState(
      series: b, symbol: info,
      view: ViewMath.reset(series: b, plotW: L.plotW, spacing: AICoinBehavior.initialSpacing),
      price: .init(mode: .linear), subs: [.vol, .macd], timezone: .utc, decimals: 2,
      options: options, nowMs: Double(b.lastTime) + 1_800_000)
    return ChartRenderer(state: st)
  }

  /// 把收盘价放在一条刻度上、以及离刻度不到一行字的几个位置：那条刻度的字都得让开，
  /// 网格线还在；离胶囊够远的刻度一条不少。
  @Test("和胶囊交叠的刻度字整条不写，网格线照画，其余刻度不受影响")
  func overlappingTickLabelYields() throws {
    let base = Self.renderer()
    let L0 = base.layout(size: Self.size)
    let r0 = base.priceRange(size: Self.size)
    let ticks = base.mainPriceTicks(range: r0, paneHeight: L0.main.h)
    try #require(ticks.count >= 4, "这份快照刻度太少，测不出来")
    let mid = ticks[ticks.count / 2]
    let gap = ticks[ticks.count / 2 + 1] - mid
    let half = Double(ChartFont.axis.lineHeight) / 2

    // 正落在刻度上，以及往上、往下各偏一点（胶囊仍与那条刻度的字交叠）。
    for offset in [0.0, 0.08, -0.08] {
      let r = Self.renderer(close: mid + gap * offset)
      let L = r.layout(size: Self.size)
      let range = r.priceRange(size: Self.size)
      let band = try #require(r.lastPriceChipBand(pane: L.main, r: range))
      let labels = r.priceTickLabels(pane: L.main, r: range, L: L)
      for tick in labels {
        #expect(tick.y <= band.lo - half || tick.y >= band.hi + half,
                "偏 \(offset) 格：刻度「\(tick.text)」y=\(tick.y) 的字与胶囊 \(band) 交叠，会被盖掉半截")
      }
      let midText = fmtNum(mid, r.state.decimals)
      #expect(!labels.contains { $0.text == midText }, "偏 \(offset) 格：被胶囊压住的刻度「\(midText)」还在写")

      // 网格线不让：这条刻度的线还在。
      let ys = r.priceTickYs(pane: L.main, r: range)
      let center = (band.lo + band.hi) / 2
      #expect(ys.contains { abs($0 - center) < half + Self.chipHalf }, "偏 \(offset) 格：被让开字的那条刻度连网格线也没了")

      // 关掉实时价格线（没有胶囊）时同一份数据的刻度字：离胶囊够远的一条都不能少。
      let bare = Self.renderer(close: mid + gap * offset, lastLine: false)
      let bareLabels = bare.priceTickLabels(pane: L.main, r: range, L: L)
      #expect(bareLabels.contains { $0.text == midText }, "没有胶囊时那条刻度本该写出来")
      for tick in bareLabels where tick.y <= band.lo - half || tick.y >= band.hi + half {
        #expect(labels.contains { $0.text == tick.text }, "偏 \(offset) 格：离胶囊够远的刻度「\(tick.text)」也被删了")
      }
    }
  }

  static let chipHalf = ChartRenderer.lastPriceChipHeight / 2
}
