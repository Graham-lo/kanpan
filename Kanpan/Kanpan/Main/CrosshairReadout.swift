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

/// 「顶部」读数那一档里，十字线活着的时候把实时价格行让给开高低收。
///
/// 做成修饰器而不是在主屏 body 里算 `opacity`：这一层跟着十字线重求值，
/// 被它包着的 `PriceRow` 是主屏那一次 body 求值造出来的值，不会跟着重造。
///
/// **只有 `.top` 那一档让位**（2026-09-23）。从前是「十字线一在就让」，因为头部那一行
/// 要腾出来放「上一根 / 下一根 / 按此价画线 / 看细节」——结果手指按在图上找位置的那几秒，
/// 顶栏最新价、涨跌和右边六格全没了，而那正是交易员最想同时盯着的东西。现在那几颗
/// 搬去了周期条那一行（`CrosshairActionBar`），价格行一直实时；只有读数摆在顶部的那一档，
/// 开高低收要借这一行的位置。让的是**同一行**：价格行照旧占着位置（只是透明），行高不变。
struct HiddenWhileCrosshairReads: ViewModifier {
  let readout: CrosshairReadout
  let context: CrosshairContext

  func body(content: Content) -> some View {
    content.opacity(context.enabled && crosshairAlive(readout.crosshair, context) ? 0 : 1)
  }
}

/// 十字线此刻是不是真的落在一根上（序列对得上、下标在范围里）。
func crosshairAlive(_ crosshair: Crosshair?, _ context: CrosshairContext) -> Bool {
  guard let c = crosshair, let series = context.series,
        series.symbol == context.symbol, series.interval == context.interval
  else { return false }
  return series.close.indices.contains(c.index)
}

/// 十字线的四颗动作：上一根 / 下一根 / 按此价画线 / 看细节。
///
/// **摆在周期条那一行的同一个 44pt 框里**（2026-09-23）：十字线活着时它整行顶替周期条
/// （周期条透明让位、点不着，但照旧占着位置、量着自己的宽度，所以十字线收起时不跳位），
/// 顶栏的价格、涨跌、六格一直实时。从前它们在头部价格行的位置上，一按住图价格就没了。
///
/// 画布上不许浮控件，而周期条那一行紧贴图的上沿、拇指够得着、也不压 K 线。
/// 和整只 `MainScreen` 的关系照旧：跟着手指重求值的只有这只小视图。
/// 四颗在最窄的受支持机型 iPhone 16 Pro（402pt）上一行放得下（实测约 290pt）。
struct CrosshairActionBar: View {
  let readout: CrosshairReadout
  let context: CrosshairContext
  let theme: PanelTheme
  /// 当前这一档还有更细的一档可进（`DetailZoom.finer`）。最细那一档不画「看细节」。
  var canDetail: Bool
  /// 往左 / 往右挪一根。
  var onStep: (Int) -> Void
  /// 按十字线此刻这口价画一条水平线。
  var onLine: (Double) -> Void
  /// 「看细节」：把选中的这一根换到更细的一档铺满一屏（§10.1）。
  var onDetail: (Crosshair) -> Void

  var body: some View {
    if crosshairAlive(readout.crosshair, context), let c = readout.crosshair {
      HStack(spacing: 6) {
        chip("上一根", icon: VectorIcon.chevronLeft(10), id: "chart.crosshair.prev") { onStep(-1) }
        chip("下一根", trailingIcon: VectorIcon.chevronRight(10), id: "chart.crosshair.next") { onStep(1) }
        // 副图上的十字线读的是指标值，不是价——那条线画到主图上毫无意义，所以不给。
        if c.pane == nil, let price = c.price ?? priceOfBar(c.index), price.isFinite {
          chip("按此价画线", id: "chart.crosshair.hline") { onLine(price) }
        }
        if canDetail {
          chip("看细节", id: "chart.detailZoom") { onDetail(c) }
            .accessibilityLabel("看这一根的细节")
        }
      }
      .fixedSize(horizontal: true, vertical: false)
      .frame(maxWidth: .infinity, alignment: .leading)
      .padding(.horizontal, 12)
      .frame(height: 44)
      .accessibilityElement(children: .contain)
      .accessibilityIdentifier("chart.crosshair.actions")
    }
  }

  private func priceOfBar(_ i: Int) -> Double? {
    guard let series = context.series, series.close.indices.contains(i) else { return nil }
    return series.close[i]
  }

  /// 和周期条行尾「最新」一模一样的做法：药丸自己 28pt 高，命中区 44pt。
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
    .accessibilityIdentifier(id)
  }
}

/// 十字线活着时周期条透明让位、点不着；十字线一出来顺手收起「更多」弹层。
///
/// 做成修饰器：跟着十字线重求值的只有这一层，被包着的 `IntervalBar` 不跟着重造。
/// 用透明而不是拿掉：条照旧占位、`rowWidth` 照旧量着，十字线收起时六档原地出现。
struct YieldsToCrosshair: ViewModifier {
  let readout: CrosshairReadout
  let context: CrosshairContext
  @Binding var gridOpen: Bool

  func body(content: Content) -> some View {
    let alive = crosshairAlive(readout.crosshair, context)
    content
      .opacity(alive ? 0 : 1)
      .allowsHitTesting(!alive)
      .accessibilityHidden(alive)
      .onChange(of: alive) { _, now in
        guard now, gridOpen else { return }
        withAnimation(.easeOut(duration: 0.2)) { gridOpen = false }
      }
  }
}
