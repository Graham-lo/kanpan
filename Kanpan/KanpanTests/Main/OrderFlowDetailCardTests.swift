import KanpanChart
import KanpanCore
import SwiftUI
import Testing
import UIKit

@testable import Kanpan

/// 主力订单流详情卡（订单簿压测第二轮 2026-09-28）：D5 状态文案、D6 两行卡、卡高与图表包里留的名义高对得上。
@MainActor
struct OrderFlowDetailCardTests {
  static let t0: Int64 = 1_790_000_000_000

  static func group(price: Double = 83_600, status: BigOrder.Status, notional: Double = 12_000_000,
                    filled: Double = 0, vanished: Double? = nil, end: Int64? = nil) -> OrderFlowGroup {
    let o = BigOrder(venueID: "binance:usdtPerp:BTCUSDT", exchange: "币安", product: .usdtPerp, side: .ask,
                     bucket: 836, price: price, firstSeenMs: t0, endMs: end, status: status,
                     initialNotional: notional, notional: notional, filledNotional: filled, threshold: 5_000_000,
                     vanishedNotional: vanished)
    return OrderFlowGroup(key: OrderFlowGroupKey(o), members: [o])!
  }

  static func text(_ g: OrderFlowGroup) -> OrderFlowCardText {
    OrderFlowCardText(group: g, base: "BTC", decimals: 1, timeZone: .fixed(480), nowMs: t0 + 9_000_000)
  }

  @Test("D5 结束的墙：部分成交后撤写「成交 X% · 撤单 Y%」（相加 100），全成交「已成交」，一口没吃「已撤单」")
  func endedStatus() {
    let end = Self.t0 + 3_600_000
    let partial = Self.text(Self.group(status: .cancelled, filled: 4_000_000, vanished: 10_000_000, end: end))
    #expect(partial.statusText == "成交 40% · 撤单 60%")
    #expect(partial.statusTight == "成交40%·撤单60%")
    #expect(partial.state == .filled)
    #expect(partial.pairs[1].1.value == "成交 40% · 撤单 60%")
    // 模型判「已成交」（成交 ≥ 八成）但没吃干净的，照样写出撤掉的那一截。
    let mostly = Self.text(Self.group(status: .filled, filled: 8_500_000, vanished: 10_000_000, end: end))
    #expect(mostly.statusText == "成交 85% · 撤单 15%")
    let full = Self.text(Self.group(status: .filled, filled: 10_000_000, vanished: 10_000_000, end: end))
    #expect(full.statusText == "已成交" && full.state == .filled)
    let rounds = Self.text(Self.group(status: .filled, filled: 9_960_000, vanished: 10_000_000, end: end))
    #expect(rounds.statusText == "已成交", "写出来是 100% 就算全成交")
    let none = Self.text(Self.group(status: .cancelled, vanished: 10_000_000, end: end))
    #expect(none.statusText == "已撤单" && none.state == .cancelled)
    let tiny = Self.text(Self.group(status: .cancelled, filled: 40_000, vanished: 10_000_000, end: end))
    #expect(tiny.statusText == "成交 0.4% · 撤单 99.6%")
    let crumb = Self.text(Self.group(status: .cancelled, filled: 1, vanished: 10_000_000, end: end))
    #expect(crumb.statusText == "成交 0.1% · 撤单 99.9%", "吃过一口就至少 0.1%")
    // 挂着的照旧。
    #expect(Self.text(Self.group(status: .live)).statusText == "挂单中")
    #expect(Self.text(Self.group(status: .live, filled: 1_900_000)).statusText == "成交中 16%")
    // 挂着的墙吃过一小口：至少写 0.1%，不写「成交 0.0%」（审查 A 线）。
    #expect(Self.text(Self.group(status: .live, filled: 3_000)).statusText == "成交中 0.1%")
    #expect(Self.text(Self.group(status: .live, filled: 600_000)).statusText == "成交中 5.0%")
    // 各档都是两数相加 100。
    for f in stride(from: 0.001, through: 0.994, by: 0.0137) {
      guard let s = OrderFlowCardText.fillSplit(f) else { Issue.record("\(f) 不该算全成交"); continue }
      let a = Double(s.filled.dropLast())!, b = Double(s.cancelled.dropLast())!
      #expect(abs(a + b - 100) < 1e-9, "\(f) → \(s)")
    }
  }

  static func size(_ card: OrderFlowDetailCard, width: Double) -> CGSize {
    let host = UIHostingController(rootView: card)
    return host.sizeThatFits(in: CGSize(width: width, height: 2000))
  }

  static func card(_ g: OrderFlowGroup, compact: Bool, maxWidth: Double = 297, dark: Bool = false) -> OrderFlowDetailCard {
    let focus = ChartOrderFlowFocus(group: g, selected: true, anchorX: 100, bandY: 100, bandHalf: 4, plotW: 350,
                                    mainTop: 40, mainBottom: 400, mainHeight: 380, asOfMs: t0 + 9_000_000)
    return OrderFlowDetailCard(focus: focus, theme: PanelTheme(dark: dark), base: "BTC", decimals: 1,
                               timeZone: .fixed(480), maxWidth: maxWidth, compact: compact)
  }

  @Test("D6 卡高：三行、两行都不高于图表包里留的名义高（摆位按它算躲 K 线），也不矮出一截")
  func cardHeightsMatchBudget() {
    let g = Self.group(status: .cancelled, filled: 4_000_000, vanished: 10_000_000, end: Self.t0 + 3_600_000)
    let full = Self.size(Self.card(g, compact: false), width: 297)
    let compact = Self.size(Self.card(g, compact: true), width: 297)
    print("取证|详情卡|三行 \(full)|两行 \(compact)")
    #expect(full.height <= OrderFlowCardBudget.fullHeight && full.height >= OrderFlowCardBudget.fullHeight - 8)
    #expect(compact.height <= OrderFlowCardBudget.compactHeight && compact.height >= OrderFlowCardBudget.compactHeight - 8)
    #expect(compact.height < full.height - 10)
  }

  /// 16 Pro 竖屏的卡宽上限：绘图区约 350 pt × 85%。
  static let phoneCardWidth = 297.0

  static func idealWidth<V: View>(_ view: V) -> Double {
    let host = UIHostingController(rootView: view.lineLimit(1).dynamicTypeSize(...MarketChrome.typeCap))
    return host.sizeThatFits(in: CGSize(width: CGFloat.infinity, height: .infinity)).width
  }

  @Test("D5 部分成交后撤在 16 Pro 的卡宽（约 300 pt）里两个数都放得下：「成交 40% · 撤单 60%」与不到 1% 带小数那句，最多让掉「状态」两字（值本身已说明是状态，2026-10-08「撤」改「撤单」后两字标签放不下）")
  func partialStatusFitsPhoneWidth() {
    let end = Self.t0 + 3_600_000
    let room = Self.phoneCardWidth - 2 * Double(Inset.cardCompact)
    typealias Fit = OrderFlowCardPairs.StatusFit
    for (filled, label, worst) in [(4_000_000.0, "成交 40% · 撤单 60%", Fit.bare), (40_000.0, "成交 0.4% · 撤单 99.6%", Fit.bare)] {
      let g = Self.group(status: .cancelled, filled: filled, vanished: 10_000_000, end: end)
      let lines = Self.text(g)
      #expect(lines.statusText == label)
      var widths: [String] = []
      for compact in [false, true] {
        var fitted = false
        for fit in [Fit.spaced, .tight, .bare] {
          let w = Self.idealWidth(OrderFlowCardPairs(lines: lines, theme: PanelTheme(dark: false), compact: compact, statusFit: fit))
          widths.append("\(compact ? "两行卡" : "三行卡") \(fit) \(w)")
          if w <= room { fitted = true; break }
          #expect(fit != worst, "\(label)：\(compact ? "两行卡" : "三行卡") 退到 \(fit) 还是 \(w) > \(room)")
        }
        #expect(fitted)
      }
      print("取证|详情卡|\(label)|\(widths.joined(separator: "|"))|可用 \(room)")
    }
  }

  @Test("D4 摆位：焦点带在上半边时卡贴主图下沿，K 线伸进那一段就收窄或换边")
  func placementFromFocus() {
    let g = Self.group(status: .live)
    let f = ChartOrderFlowFocus(group: g, selected: false, anchorX: 60, bandY: 120, bandHalf: 4, plotW: 350,
                                mainTop: 40, mainBottom: 400, mainHeight: 380, asOfMs: Self.t0,
                                candle: .init(left: 56, right: 64, top: 330, bottom: 390))
    let p = f.cardPlacement
    #expect(p.below && !p.leading && abs(p.top + p.maxHeight - 400) < 1e-9)
    #expect(f.cardMaxWidth == p.maxWidth && p.maxWidth < 350 * 0.85 && !p.coversCandle)
  }
}
