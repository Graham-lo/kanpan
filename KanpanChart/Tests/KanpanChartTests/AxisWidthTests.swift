import CoreGraphics
import Foundation
import KanpanCore
import Testing
import UIKit

@testable import KanpanChart

/// 右轴宽度按内容算（2026-09-20）。
///
/// 从前是「50pt 起跳、不够再按 8pt 一档往上加」，三位数的价位两边各空一大截白；
/// 现在是「这一屏最宽的那条刻度 + 两侧各 4pt」。这一组盯住三件事：
/// 贴着内容走、位数变了才变、胶囊不出右缘。
@MainActor
@Suite("右轴宽度按内容算")
struct AxisWidthTests {
  static let size = CGSize(width: 402, height: 520)

  /// 把定版快照整条按倍数搬到别的价位上，用来模拟别的品种。
  static func series(_ factor: Double, symbol: String) -> BarSeries {
    let s = Fixture.series
    func f(_ xs: [Double]) -> [Double] { xs.map { $0 * factor } }
    return BarSeries(symbol: symbol, interval: s.interval, t0: s.t0, step: s.step,
                     open: f(s.open), high: f(s.high), low: f(s.low), close: f(s.close),
                     volume: s.volume)
  }

  static func renderer(factor: Double = 1, decimals: Int = 2, symbol: String = "BTCUSDT",
                       subs: [IndicatorID] = [.vol, .macd],
                       options: ChartOptions = .init()) -> ChartRenderer {
    let b = series(factor, symbol: symbol)
    let L = Layout(width: size.width, height: size.height, subs: subs)
    let info = SymbolInfo(symbol: symbol, base: symbol, quote: "USDT",
                          pricePrecision: decimals, tickSize: pow(10, -Double(decimals)))
    let st = ChartState(
      series: b, symbol: info,
      view: ViewMath.reset(series: b, plotW: L.plotW, spacing: AICoinBehavior.initialSpacing),
      price: .init(mode: .linear), subs: subs, timezone: .utc, decimals: decimals,
      options: options, nowMs: Double(b.lastTime) + 1_800_000)
    return ChartRenderer(state: st)
  }

  @Test("图表价格与价差读数按报价步长，百分比保留独立口径")
  func priceReadoutsUseTickSize() {
    let cases: [(String, Int, Double, Double, Int)] = [
      ("SNDKUSDT", 5, 0.01, 1774.23, 2), ("MUUSDT", 5, 0.01, 1045.4, 2),
      ("BTCUSDT", 2, 0.1, 76800.0, 1), ("1000SATSUSDT", 8, 0.00000001, 0.00001234, 8)
    ]
    for (symbol, precision, tick, price, digits) in cases {
      let info = SymbolInfo(symbol: symbol, base: symbol, pricePrecision: precision, tickSize: tick)
      let series = Self.series(price / 80_000, symbol: symbol)
      let state = ChartState(series: series, symbol: info, view: ViewWindow(to: Double(series.lastTime), span: 3_600_000))
      #expect(state.decimals == digits)
      let r = ChartRenderer(state: state)
      let range = r.priceRange(size: Self.size)
      #expect(r.axisLabel(price, range: range) == fmtNum(price, digits))
      #expect(r.subValueText(price / 100, indicator: .macd) == fmtNum(price / 100, digits))
      #expect(r.subValueText(price / 100, indicator: .atr) == fmtNum(price / 100, digits))
      #expect(r.subValueText(54.321, indicator: .rsi) == "54.32")
    }
  }

  /// 轴宽正好是「最宽的那条刻度 + 两侧各 `axisLabelPadding`」，一个像素都不多。
  @Test("轴宽贴着最宽的那条刻度走")
  func hugsContent() {
    for (factor, decimals) in [(1.0, 2), (1.234e-5 / 80_000, 8), (420.0 / 80_000, 2)] {
      let r = Self.renderer(factor: factor, decimals: decimals)
      let L = r.layout(size: Self.size)
      let range = r.priceRange(size: Self.size)
      var labels = [range.lo, range.hi].map { r.axisLabel($0, range: range) }
      for pane in L.panes.dropFirst() { if let id = pane.indicator { labels += r.subAxisLabels(id) } }
      let widest = labels.map { Double($0.width(ChartFont.axis)) }.max() ?? 0
      #expect(abs(L.axisW - (widest.rounded(.up) + 2 * AICoinBehavior.axisLabelPadding)) < 0.001,
              "刻度 \(labels) 量出来 \(widest)，轴却是 \(L.axisW)")
    }
  }

  /// 位数多的品种宽、少的窄；同一套刻度位数下换数字不影响宽度（等宽数字 + 模板量法）。
  @Test("位数决定宽度，数字本身不决定")
  func stepsFollowDigits() {
    let btc = Self.renderer().layout(size: Self.size).axisW
    let stock = Self.renderer(factor: 420.0 / 80_000).layout(size: Self.size).axisW
    let shib = Self.renderer(factor: 1.234e-5 / 80_000, decimals: 8).layout(size: Self.size).axisW
    #expect(stock < btc && btc < shib, "三位数 \(stock) / 五位数 \(btc) / 八位小数 \(shib)")

    // 同样位数、不同数字：一个像素都不许动（最新价每跳一下都重排右轴就是抖）。
    let a = Self.renderer(factor: 1).layout(size: Self.size).axisW
    let b = Self.renderer(factor: 1.0001).layout(size: Self.size).axisW
    #expect(a == b, "同位数换了数字，轴宽从 \(a) 变成 \(b)")
    #expect(ChartRenderer(state: Self.renderer().state).axisWidthTemplate("81,234.56K")
            == "00,000.00K")
  }

  /// 最新价胶囊、十字线读数、倒计时都关在轴里：不出右缘，也不被裁掉。
  @Test("右轴上的胶囊不出右缘")
  func chipsStayInside() {
    for (factor, decimals) in [(1.0, 2), (1.234e-5 / 80_000, 8), (420.0 / 80_000, 2)] {
      var options = ChartOptions()
      options.countdown = true
      let r = Self.renderer(factor: factor, decimals: decimals, options: options)
      let L = r.layout(size: Self.size)
      let range = r.priceRange(size: Self.size)
      let label = r.axisLabel(r.state.series.close.last ?? 0, range: range)
      let chip = r.axisChip(L, text: label)
      #expect(chip.x >= L.plotW)
      #expect(chip.x + chip.w <= L.W - 1, "最新价胶囊右缘 \(chip.x + chip.w) 越过了 \(L.W)")
      #expect(chip.w >= Double(label.width(ChartFont.axis)), "\(label) 被胶囊裁掉了")

      let stamp = try! #require(r.countdownTemplate())
      let clock = r.axisChip(L, text: stamp, font: ChartFont.tiny, minWidth: chip.w)
      #expect(clock.x + clock.w <= L.W - 1, "倒计时 \(stamp) 右缘 \(clock.x + clock.w) 越过了 \(L.W)")
      #expect(clock.w >= Double(stamp.width(ChartFont.tiny)), "倒计时 \(stamp) 被裁掉了")
    }
  }

  /// 倒计时关着（出厂默认）不占一个像素。
  @Test("倒计时关着就不为它留地方")
  func countdownCostsNothingWhenOff() {
    var on = ChartOptions()
    on.countdown = true
    let off = Self.renderer(factor: 420.0 / 80_000, options: .init()).layout(size: Self.size).axisW
    let with = Self.renderer(factor: 420.0 / 80_000, options: on).layout(size: Self.size).axisW
    #expect(off <= with)
    #expect(off == Self.renderer(factor: 420.0 / 80_000).layout(size: Self.size).axisW)
  }
}
