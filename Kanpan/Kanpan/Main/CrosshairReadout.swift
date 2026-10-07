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
  /// 「顶部」那档显示模式开着吗。2026-09-28 起 K 线数据位置定死在「顶部」，宿主恒传 `true`；
  /// 留着这个口子是给复盘、预览这类不想要头部读数的宿主。
  var enabled: Bool
  /// 品种带不带成交量（`ProviderCapabilities.hasVolume`）。没有的（美元指数）读数里不写「量」。
  var hasVolume = true
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
    + (context.hasVolume ? "  量 " + fmtVol(series.volume[i]) : "")
}

/// 周期条那一行左边的十字线读数（2026-10-08 走查）：`时间 · 开 高 低 收 · 涨跌幅`，一行。
///
/// 原来十字线一出来，头部的实时价格行就让给一块等宽字体的三行开高低收（像终端），周期条
/// 那一行只剩一颗「创建提醒」、副图上连那颗都没有——一整条空带。现在读数挪进这条带子的左边，
/// 头部价格、涨跌、六格一直实时；放不下时先收「开 高 低」，再收时间，收盘价和涨跌幅总在。
struct CrosshairBandReadout: Equatable {
  /// 日内周期写「10-08 14:30」，日线及以上写「2026-10-08」。
  let time: String
  let open: String
  let high: String
  let low: String
  let close: String
  /// 这一根相对上一根收盘的涨跌幅（第一根没有上一根，相对它自己的开盘），「+0.12%」。
  let change: String?

  /// 一档放不下就往下一档退：全量 → 收掉开高低 → 再收掉时间。
  enum Fit: CaseIterable { case full, closeOnly, bare }

  func text(_ fit: Fit) -> String {
    let tail = change.map { " · " + $0 } ?? ""
    switch fit {
    case .full: return "\(time) · 开 \(open) 高 \(high) 低 \(low) 收 \(close)\(tail)"
    case .closeOnly: return "\(time) · 收 \(close)\(tail)"
    case .bare: return "收 \(close)\(tail)"
    }
  }
}

/// 十字线那一根的读数（纯函数，跟 `crosshairOHLCText` 同一个对得上序列的口径）。
/// 副图上的十字线也给——它对着的仍是那一根 K 线。
@MainActor func crosshairBandReadout(_ crosshair: Crosshair?, _ context: CrosshairContext) -> CrosshairBandReadout? {
  guard context.enabled, let c = crosshair, let series = context.series,
        series.symbol == context.symbol, series.interval == context.interval,
        series.close.indices.contains(c.index) else { return nil }
  let i = c.index, p = context.decimals
  let ms = Double(series.time(at: i))
  let parts = DateParts(ms: ms, offsetMinutes: context.offsetMinutes)
  func pad(_ n: Int) -> String { n < 10 ? "0\(n)" : "\(n)" }
  let time = context.interval.stepMs >= 86_400_000
    ? "\(parts.year)-\(pad(parts.month))-\(pad(parts.day))"
    : "\(pad(parts.month))-\(pad(parts.day)) \(pad(parts.hour)):\(pad(parts.minute))"
  let close = series.close[i]
  let base = i > 0 ? series.close[i - 1] : series.open[i]
  var change: String?
  if base.isFinite, close.isFinite, base != 0 {
    let pct = (close - base) / base * 100
    // 四舍五入到两位之后是 0 的写「0.00%」，不写「-0.00%」。
    change = abs(pct) < 0.005 ? "0.00%" : String(format: "%+.2f%%", pct)
  }
  return CrosshairBandReadout(
    time: time,
    open: fmtPrice(series.open[i], decimals: p), high: fmtPrice(series.high[i], decimals: p),
    low: fmtPrice(series.low[i], decimals: p), close: fmtPrice(close, decimals: p),
    change: change)
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

/// 十字线此刻是不是真的落在一根上（序列对得上、下标在范围里）。
@MainActor func crosshairAlive(_ crosshair: Crosshair?, _ context: CrosshairContext) -> Bool {
  guard let c = crosshair, let series = context.series,
        series.symbol == context.symbol, series.interval == context.interval
  else { return false }
  return series.close.indices.contains(c.index)
}

/// 十字线活着时周期条那一行换成的那条带子：左边是这一根的读数，右边一颗「创建提醒」。
///
/// **摆在周期条那一行的同一个 44pt 框里**（2026-09-23）：十字线活着时它整行顶替周期条
/// （周期条透明让位、点不着，但照旧占着位置、量着自己的宽度，所以十字线收起时不跳位），
/// 顶栏的价格、涨跌、六格一直实时。画布上不许浮控件，而周期条那一行紧贴图的上沿、
/// 拇指够得着、也不压 K 线。跟着手指重求值的只有这只小视图。
///
/// 2026-09-25 起药丸上的字固定写「创建提醒」（不写价、不写涨到跌到），十字线那口价带进页里预填。
///
/// 2026-10-08 走查：读数从头部挪进这条带子的左边（`CrosshairBandReadout`），11pt 二级墨色，
/// 等宽数字但不用等宽字体；药丸挪到右边。副图上的十字线没有药丸（指标值建不了价格提醒），
/// 读数照给，不再是一整条空带。出主力订单流详情卡时读数让位给卡片（两块读数不同时出）。
struct CrosshairActionBar: View {
  let readout: CrosshairReadout
  let context: CrosshairContext
  let theme: PanelTheme
  /// 点了：交出十字线那一口价（主图价；没有就那一根的收盘）。
  var onAlert: (Double) -> Void

  /// 药丸上的字。UI 用例按它认。
  static let title = "创建提醒"

  var body: some View {
    if crosshairAlive(readout.crosshair, context), let c = readout.crosshair {
      // 副图上的十字线读的是指标值，不是价——按它建价格提醒毫无意义，所以不给。
      let price = c.pane == nil ? (c.price ?? priceOfBar(c.index)).flatMap { $0.isFinite && $0 > 0 ? $0 : nil } : nil
      let reading = readout.orderFlow == nil ? crosshairBandReadout(c, context) : nil
      HStack(spacing: Space.s) {
        if let reading { band(reading) }
        Spacer(minLength: 0)
        if let price {
          chip(price).fixedSize(horizontal: true, vertical: false)
        }
      }
      // 左缘和头部、周期条同一根线（`Inset.page`）；字号封顶也跟它们一起（UI 审查 2026-09-24 §4.3 #23/#24）。
      .pageHorizontalInset()
      .frame(height: Hit.min)
      .dynamicTypeSize(...MarketChrome.typeCap)
      .accessibilityElement(children: .contain)
      .accessibilityIdentifier("chart.crosshair.actions")
    }
  }

  /// 左边那行读数：一档放不下退一档（先收开高低，再收时间）。
  private func band(_ reading: CrosshairBandReadout) -> some View {
    ViewThatFits(in: .horizontal) {
      ForEach(CrosshairBandReadout.Fit.allCases, id: \.self) { fit in
        Text(reading.text(fit))
      }
    }
    .font(.system(size: 11).monospacedDigit())
    .foregroundStyle(theme.ink2)
    .lineLimit(1)
    // 读屏仍按原来那三行念（时间一行、开高一行、低收量一行），UI 用例按第一行认时间。
    .accessibilityElement(children: .ignore)
    .accessibilityLabel(crosshairOHLCText(readout.crosshair, context) ?? reading.text(.full))
    .accessibilityIdentifier("chart.topOHLC")
    .accessibilityAddTraits(.isStaticText)
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

extension ChartState {
  /// 同一张图，十字线读数改画在图里（「K 线内」那一档）。给没有头部读数的宿主用——
  /// 眼下只有复盘回放：它的页头（`ReplayHeaderView`）只写回放走到的那根，不跟十字线。
  var readingInside: ChartState {
    var copy = self
    copy.options.dataDisplay = .inside
    return copy
  }
}
