import KanpanChart
import KanpanCore
import SwiftUI

/// 十字线读数的落脚点。
///
/// 从前十字线的每一次移动都写进 `MainScreen` 自己的 `@State crosshair`——那一层挂着
/// 整个主屏（顶栏、周期条、图、底栏、面板、复盘），手指在图上划一下，主屏的 body
/// 就跟着重求值一遍，而这一下真正变的只有头部那几行开高低收。
///
/// 所以把它下沉成一只只被读数容器观察的小对象：`ChartHost` 的回调只写它，
/// 读数视图只读它，主屏的 body 一次都不用动。导航与布局状态仍然留在主屏。
@MainActor @Observable final class CrosshairReadout {
  /// 十字线摆在哪根上；`nil` 就没有十字线。
  private(set) var crosshair: Crosshair?

  func set(_ value: Crosshair?) {
    guard crosshair != value else { return }
    crosshair = value
  }

  func clear() { set(nil) }
}

/// 读数要的那几样「不跟着手指走」的输入：哪条序列、几位小数、什么时区、这个模式开没开。
///
/// 它们只会随行情推进、换品种、改设置而变，那几件事本来就要重求值主屏的 body，
/// 所以在 body 里现取，不进 `CrosshairReadout`。
struct CrosshairContext {
  var series: BarSeries?
  var symbol: String
  var interval: Interval
  var decimals: Int
  var offsetMinutes: Int
  /// 「顶部」那档显示模式开着吗（`prefs.dataDisplay == .top`）。
  var enabled: Bool
}

/// 头部那几行开高低收。口径和从前的 `MainScreen.topCandleData` 逐字相同。
func crosshairOHLCText(_ crosshair: Crosshair?, _ context: CrosshairContext) -> String? {
  guard context.enabled, let c = crosshair, let series = context.series,
        series.symbol == context.symbol, series.interval == context.interval,
        series.close.indices.contains(c.index) else { return nil }
  let i = c.index, p = context.decimals
  return fmtFull(ms: Double(series.time(at: i)), offsetMinutes: context.offsetMinutes)
    + "\n开 " + fmtNum(series.open[i], p) + "  高 " + fmtNum(series.high[i], p)
    + "\n低 " + fmtNum(series.low[i], p) + "  收 " + fmtNum(series.close[i], p)
    + "  量 " + fmtVol(series.volume[i])
}

/// 十字线的开高低收那一块。**只有它跟着手指重求值**。
struct CrosshairOHLCLabel: View {
  let readout: CrosshairReadout
  let context: CrosshairContext
  var size: CGFloat = 11
  var color: Color
  var fillsWidth = false

  var body: some View {
    if let text = crosshairOHLCText(readout.crosshair, context) {
      Text(text)
        .font(.system(size: size, design: .monospaced))
        .foregroundStyle(color)
        .frame(maxWidth: fillsWidth ? .infinity : nil, alignment: .leading)
        .accessibilityIdentifier("chart.topOHLC")
    }
  }
}

/// 读数出来的时候把实时价格行让出去。
///
/// 做成修饰器而不是在主屏 body 里算 `opacity`：这一层跟着十字线重求值，
/// 被它包着的 `PriceRow` 是主屏那一次 body 求值造出来的值，不会跟着重造。
struct HiddenWhileCrosshairReads: ViewModifier {
  let readout: CrosshairReadout
  let context: CrosshairContext

  func body(content: Content) -> some View {
    content.opacity(crosshairOHLCText(readout.crosshair, context) == nil ? 1 : 0)
  }
}
