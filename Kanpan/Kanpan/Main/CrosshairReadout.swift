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
  /// 时区**口径**，不是一个偏移数（审查 B-08）。本地那一档要按被格式化的那一刻
  /// 去问时区数据库，否则夏天看冬季的历史 K 线，整段时间会整体平移一小时。
  var offsetMinutes: TZOffset
  /// 「顶部」那档显示模式开着吗（`prefs.dataDisplay == .top`）。
  var enabled: Bool
}

/// 头部那几行开高低收。口径和从前的 `MainScreen.topCandleData` 逐字相同。
func crosshairOHLCText(_ crosshair: Crosshair?, _ context: CrosshairContext) -> String? {
  guard context.enabled, let c = crosshair, let series = context.series,
        series.symbol == context.symbol, series.interval == context.interval,
        series.close.indices.contains(c.index) else { return nil }
  let i = c.index, p = context.decimals
  // 价格一律 `fmtPrice`：按品种的位数四舍五入之后变成 0 的极小正价会自动多给几位，
  // 不会在读数里写出「开 0.00 高 0.00」（审查 B-07）。
  return fmtFull(ms: Double(series.time(at: i)), offsetMinutes: context.offsetMinutes)
    + "\n开 " + fmtPrice(series.open[i], decimals: p) + "  高 " + fmtPrice(series.high[i], decimals: p)
    + "\n低 " + fmtPrice(series.low[i], decimals: p) + "  收 " + fmtPrice(series.close[i], decimals: p)
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

/// 十字线活着的时候把实时价格行让出去。
///
/// 做成修饰器而不是在主屏 body 里算 `opacity`：这一层跟着十字线重求值，
/// 被它包着的 `PriceRow` 是主屏那一次 body 求值造出来的值，不会跟着重造。
///
/// 从前的条件是「顶部读数出来了」，现在是「十字线在」（§P3-7）：读数摆在图里那两档
/// （`dataDisplay == .inside / .follow`，出厂默认就是 `.inside`）头部本来是不让位的，
/// 但十字线一活，头部那一行就要腾出来放「上一根 / 下一根 / 按此价画线」这三颗。
/// 让的是**同一行**：价格行照旧占着位置（只是透明），行高一个 pt 都不变，图不会跳。
struct HiddenWhileCrosshairReads: ViewModifier {
  let readout: CrosshairReadout
  let context: CrosshairContext

  func body(content: Content) -> some View {
    content.opacity(crosshairAlive(readout.crosshair, context) ? 0 : 1)
  }
}

/// 十字线此刻是不是真的落在一根上（序列对得上、下标在范围里）。
func crosshairAlive(_ crosshair: Crosshair?, _ context: CrosshairContext) -> Bool {
  guard let c = crosshair, let series = context.series,
        series.symbol == context.symbol, series.interval == context.interval
  else { return false }
  return series.close.indices.contains(c.index)
}

/// 读数行：左边开高低收（只有「顶部」那一档有），右边三颗动作（§P3-7）。
///
/// **三颗都在图外**——画布上不许浮控件，而十字线活着的时候人正盯着这一屏，
/// 头部那一行是唯一一块既看得见、拇指又够得着、还不压着 K 线的地方。
///
/// 和整只 `MainScreen` 的关系照旧：跟着手指重求值的只有这只小视图，
/// 主屏的 body 一次都不用动（这也是三颗动作没做成主屏 `@State` 的原因）。
struct CrosshairReadoutRow: View {
  let readout: CrosshairReadout
  let context: CrosshairContext
  let theme: PanelTheme
  /// 往左 / 往右挪一根。
  var onStep: (Int) -> Void
  /// 按十字线此刻这口价画一条水平线。
  var onLine: (Double) -> Void
  /// 「看细节」：把选中的这一根换到更细的一档铺满一屏（§10.1）。
  ///
  /// 它从前在周期条行尾，和「最新」并排——两颗一起摆要 143pt，16 Pro 上把钉住的
  /// 周期挤得只剩三档半。它本来就只在十字线活着的时候出现，和这儿的三颗是一伙的，
  /// 2026-09-20 整体搬过来。当前这一档已经是最细的一档时（`canDetail == false`）不画。
  var canDetail: Bool = false
  var onDetail: ((Crosshair) -> Void)? = nil

  var body: some View {
    if crosshairAlive(readout.crosshair, context), let c = readout.crosshair {
      let text = crosshairOHLCText(c, context)
      if let text {
        // 装得下就并排，装不下就让这一行长高一点——字一个都不缩、一个都不截
        // （用户 2026-09-20 定的版面原则）。
        ViewThatFits(in: .horizontal) {
          HStack(alignment: .top, spacing: 8) { label(text); Spacer(minLength: 0); chips(c) }
          VStack(alignment: .leading, spacing: 5) { label(text); chips(c) }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
      } else {
        chips(c).frame(maxWidth: .infinity, alignment: .trailing)
      }
    }
  }

  private func label(_ text: String) -> some View {
    Text(text)
      .font(.system(size: 11, design: .monospaced))
      .foregroundStyle(theme.ink)
      .fixedSize(horizontal: false, vertical: true)
      .accessibilityIdentifier("chart.topOHLC")
  }

  @ViewBuilder private func chips(_ c: Crosshair) -> some View {
    HStack(spacing: 6) {
      chip("上一根", icon: VectorIcon.chevronLeft(10), id: "chart.crosshair.prev") { onStep(-1) }
      chip("下一根", trailingIcon: VectorIcon.chevronRight(10), id: "chart.crosshair.next") { onStep(1) }
      // 副图上的十字线读的是指标值，不是价——那条线画到主图上毫无意义，所以不给。
      if c.pane == nil, let price = c.price ?? priceOfBar(c.index), price.isFinite {
        chip("按此价画线", id: "chart.crosshair.hline") { onLine(price) }
      }
      if canDetail, let onDetail {
        chip("看细节", id: "chart.detailZoom") { onDetail(c) }
          .accessibilityLabel("看这一根的细节")
      }
    }
    .fixedSize(horizontal: true, vertical: false)
  }

  private func priceOfBar(_ i: Int) -> Double? {
    guard let series = context.series, series.close.indices.contains(i) else { return nil }
    return series.close[i]
  }

  /// 和周期条行尾那几颗一模一样的做法：药丸自己 28pt 高，命中区 44pt，
  /// 多出来的两圈用负边距收回去，所以这一行的高度不因为它们而变。
  private func chip(
    _ title: String, icon: VectorIcon? = nil, trailingIcon: VectorIcon? = nil,
    id: String, action: @escaping () -> Void
  ) -> some View {
    Button(action: action) {
      HStack(spacing: 3) {
        if let icon { icon }
        Text(title).font(.system(size: 12.5, weight: .semibold))
        if let trailingIcon { trailingIcon }
      }
      .foregroundStyle(theme.ink2)
      .padding(.horizontal, 9)
      .frame(height: 28)
      .background(theme.raised2, in: Capsule())
      .frame(minWidth: 44, minHeight: 44)
      .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
    .padding(.vertical, -8)
    .accessibilityIdentifier(id)
  }
}
