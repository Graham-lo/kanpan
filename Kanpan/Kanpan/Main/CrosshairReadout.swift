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

  /// 主力订单流选中的那一桶（轻点选中，或十字线停在一条合并带上）；`nil` 就不出详情卡。
  /// 出卡时头部「顶部」那档的开高低收让位（图里那块开高低收框由渲染器自己不画）。
  private(set) var orderFlow: ChartOrderFlowFocus?

  func set(_ value: Crosshair?) {
    guard crosshair != value else { return }
    crosshair = value
  }

  func set(orderFlow value: ChartOrderFlowFocus?) {
    guard orderFlow != value else { return }
    orderFlow = value
  }

  func clear() {
    set(nil)
    set(orderFlow: nil)
  }
}

/// 读数要的那几样「不跟着手指走」的输入：哪条序列、几位小数、什么时区、这个模式开没开。
///
/// 品种、周期、位数、时区、模式只随换品种、改设置而变，宿主在 body 里现取，不进
/// `CrosshairReadout`。**序列例外**（审查 21）：它每根新 K 线都换一份，宿主 body 里读一次
/// 就等于让每笔推送叫醒整页。所以这里只存一个取法（`seriesSource`），读数视图在十字线
/// 真在场时才去取——那一刻读到的依赖记在读数视图自己身上。
struct CrosshairContext {
  /// 序列的现取法。只在十字线在场时调用（见上）。
  var seriesSource: @MainActor () -> BarSeries?
  @MainActor var series: BarSeries? { seriesSource() }
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
@MainActor func crosshairOHLCText(_ crosshair: Crosshair?, _ context: CrosshairContext) -> String? {
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
    // 十字线停在一条主力色带上：详情卡顶替开高低收，两块读数不同时出。
    if readout.orderFlow == nil, let text = crosshairOHLCText(readout.crosshair, context) {
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
/// 要腾出来放十字线的几颗动作——结果手指按在图上找位置的那几秒，
/// 顶栏最新价、涨跌和右边六格全没了，而那正是交易员最想同时盯着的东西。现在那一行的动作
/// 搬去了周期条那一行（`CrosshairActionBar`），价格行一直实时；只有读数摆在顶部的那一档，
/// 开高低收要借这一行的位置。让的是**同一行**：价格行照旧占着位置（只是透明），行高不变。
struct HiddenWhileCrosshairReads: ViewModifier {
  let readout: CrosshairReadout
  let context: CrosshairContext

  func body(content: Content) -> some View {
    content.opacity(context.enabled && readout.orderFlow == nil && crosshairAlive(readout.crosshair, context) ? 0 : 1)
  }
}

/// 十字线此刻是不是真的落在一根上（序列对得上、下标在范围里）。
@MainActor func crosshairAlive(_ crosshair: Crosshair?, _ context: CrosshairContext) -> Bool {
  guard let c = crosshair, let series = context.series,
        series.symbol == context.symbol, series.interval == context.interval
  else { return false }
  return series.close.indices.contains(c.index)
}

/// 十字线活着时周期条那一行换成的一颗药丸：铃铛 +「创建提醒」。
///
/// **摆在周期条那一行的同一个 44pt 框里**（2026-09-23）：十字线活着时它整行顶替周期条
/// （周期条透明让位、点不着，但照旧占着位置、量着自己的宽度，所以十字线收起时不跳位），
/// 顶栏的价格、涨跌、六格一直实时。画布上不许浮控件，而周期条那一行紧贴图的上沿、
/// 拇指够得着、也不压 K 线。跟着手指重求值的只有这只小视图。
///
/// 2026-09-25 起这一行只剩这一颗：原来的「上一根 / 下一根 / 按此价画线 / 看细节」四颗撤掉，
/// 换成从图上加提醒——这是新建提醒唯一的入口。
///
/// 2026-09-25 v2（用户看完真机）：药丸上的字固定写「创建提醒」，不再写「涨到 / 跌到 X 提醒我」、
/// 也不显示价——点空白是要**创建一条提醒**，涨跌方向与离现价多远交给页里那行小字说。
/// 十字线那口价照旧带进页里预填。
struct CrosshairActionBar: View {
  let readout: CrosshairReadout
  let context: CrosshairContext
  let theme: PanelTheme
  /// 点了：交出十字线那一口价（主图价；没有就那一根的收盘）。
  var onAlert: (Double) -> Void

  /// 药丸上的字。UI 用例按它认。
  static let title = "创建提醒"

  var body: some View {
    // 副图上的十字线读的是指标值，不是价——按它建价格提醒毫无意义，所以不给。
    if crosshairAlive(readout.crosshair, context), let c = readout.crosshair, c.pane == nil,
       let price = c.price ?? priceOfBar(c.index), price.isFinite, price > 0 {
      chip(price)
        .fixedSize(horizontal: true, vertical: false)
        .frame(maxWidth: .infinity, alignment: .leading)
        // 左缘和头部、周期条同一根线（`Inset.page`）；字号封顶也跟它们一起（UI 审查 2026-09-24 §4.3 #23/#24）。
        .pageHorizontalInset()
        .frame(height: Hit.min)
        .dynamicTypeSize(...MarketChrome.typeCap)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("chart.crosshair.actions")
    }
  }

  private func priceOfBar(_ i: Int) -> Double? {
    guard let series = context.series, series.close.indices.contains(i) else { return nil }
    return series.close[i]
  }

  private func chip(_ price: Double) -> some View {
    Button { onAlert(price) } label: {
      HStack(spacing: Space.xs) {
        Image(systemName: "bell")
          .font(.system(size: 12, weight: .semibold))
        Text(Self.title)
          .font(TypeScale.controlOn)
      }
      .foregroundStyle(theme.amber)
      .padding(.horizontal, Space.m)
      .frame(height: ControlMetrics.pillHeight)
      .background(Capsule().fill(theme.amberSoft))
      .overlay(Capsule().strokeBorder(theme.amberLine, lineWidth: 0.5))
      .frame(minHeight: Hit.min)
      .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
    .accessibilityLabel(Self.title)
    .accessibilityIdentifier("chart.crosshair.alert")
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
