import KanpanChart
import KanpanCore
import SwiftUI

/// 主力订单流的详情卡（照 CoinAnk「主力大额挂单」悬停出的那张框，2026-09-24）。
///
/// 轻点图上一条主力色带选中它，或者十字线划到一条带上，就在主图里出这张卡：哪家交易所、
/// 哪个产品、买单还是卖单、挂在哪口价、多少币、多少 USDT、此刻什么状态、吃掉了多少、
/// 什么时候挂的、挂了多久。点空白处收起，点另一条换成那一条。
///
/// 挂法和十字线读数一样：这一层自己观察 `CrosshairReadout.orderFlow`，跟着焦点重求值的
/// 只有它，图和主屏的 body 不跟着动。卡片**不接触摸**（`allowsHitTesting(false)`）——
/// 点它等于点它下面的图，图那一侧按「点空白收起 / 点别的带换一条」处理，
/// 所以画布上并没有多出一个要点的控件（`kanpan-no-floating-controls-over-chart`）。
struct OrderFlowDetailLayer: View {
  let readout: CrosshairReadout
  let theme: PanelTheme
  /// 复盘态的图不是实时那张，不出卡。
  let hidden: Bool
  /// 品种的基础币（数量的单位，「BTC」）。
  let base: String
  let decimals: Int
  let timeZone: TZOffset

  var body: some View {
    if !hidden, let focus = readout.orderFlow {
      let upper = focus.bandY < focus.mainTop + (focus.mainBottom - focus.mainTop) * 0.45
      // 卡片躲开焦点：选中的带（或十字线）在右半边就摆左边，反之摆右边；
      // 带在主图上半截就摆下沿，否则摆上沿（上沿与图里开高低收框同一高度）。
      let alignment = Alignment(horizontal: focus.anchorX > focus.plotW / 2 ? .leading : .trailing,
                                vertical: upper ? .bottom : .top)
      OrderFlowDetailCard(focus: focus, theme: theme, base: base, decimals: decimals, timeZone: timeZone)
        .frame(width: max(0, focus.plotW - 16), height: max(0, focus.mainBottom - focus.mainTop - 6),
               alignment: alignment)
        .offset(x: 8, y: focus.mainTop)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .allowsHitTesting(false)
    }
  }
}

struct OrderFlowDetailCard: View {
  let focus: ChartOrderFlowFocus
  let theme: PanelTheme
  let base: String
  let decimals: Int
  let timeZone: TZOffset

  private var order: BigOrder { focus.order }

  var body: some View {
    // 还挂着的单，持续时长数到此刻：半分钟一跳足够（显示到分钟）。
    TimelineView(.periodic(from: .now, by: 30)) { context in
      let now = Int64(context.date.timeIntervalSince1970 * 1000)
      let lines = OrderFlowCardText(order: order, base: base, decimals: decimals, timeZone: timeZone,
                                    nowMs: max(now, focus.asOfMs))
      VStack(alignment: .leading, spacing: 4) {
        HStack(spacing: 6) {
          Text(lines.title).font(.system(size: 12, weight: .semibold)).foregroundStyle(theme.ink)
          Spacer(minLength: 8)
          Text(lines.status).font(.system(size: 11, weight: .semibold)).foregroundStyle(statusColor)
        }
        HStack(spacing: 6) {
          Text(lines.sideTitle).foregroundStyle(order.side == .bid ? theme.up : theme.down)
          Text(lines.headline).foregroundStyle(theme.ink)
        }
        .font(.system(size: 11, weight: .medium).monospacedDigit())
        Grid(alignment: .leading, horizontalSpacing: 6, verticalSpacing: 3) {
          ForEach(lines.pairs.indices, id: \.self) { i in
            let pair = lines.pairs[i]
            GridRow {
              Text(pair.0.label).foregroundStyle(theme.ink3)
              Text(pair.0.value).foregroundStyle(theme.ink)
              Text(pair.1.label).foregroundStyle(theme.ink3).padding(.leading, 6)
              Text(pair.1.value).foregroundStyle(theme.ink)
            }
          }
        }
        .font(.system(size: 11).monospacedDigit())
      }
      .lineLimit(1)
      .fixedSize()
      .padding(.horizontal, 10)
      .padding(.vertical, 8)
      .background(theme.raised.opacity(0.96), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
      .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(theme.line, lineWidth: 1))
      .accessibilityElement(children: .ignore)
      .accessibilityLabel(lines.spoken)
      .accessibilityIdentifier("chart.orderFlowCard")
    }
  }

  private var statusColor: Color {
    switch order.status {
    case .live: theme.amber
    case .filled: theme.ink
    case .cancelled, .lost: theme.ink3
    }
  }
}

/// 卡片上的每一行字。拆出来是为了让文案口径单独可读、可测。
struct OrderFlowCardText {
  struct Cell { var label: String, value: String }

  /// 「币安 U本位永续」。
  var title: String
  var status: String
  /// 「委托买单」/「委托卖单」。
  var sideTitle: String
  /// 「87,380.00 / 15.06 BTC / 1.32M USDT」。
  var headline: String
  var pairs: [(Cell, Cell)]

  init(order: BigOrder, base: String, decimals: Int, timeZone: TZOffset, nowMs: Int64) {
    title = order.exchange + " " + order.product.label
    status = Self.status(order.status)
    sideTitle = order.side == .bid ? "委托买单" : "委托卖单"
    let price = order.price
    let qty = { (usd: Double) in price > 0 ? usd / price : 0 }
    headline = fmtPrice(price, decimals: decimals) + " / " + Self.quantity(qty(order.notional)) + " " + base
      + " / " + fmtVol(order.notional) + " USDT"
    let start = Double(order.firstSeenMs)
    let end = order.endMs ?? nowMs
    let pct = toFixed(order.fillRatio * 100, 2) + "%"
    pairs = [
      (Cell(label: "委托时间", value: Self.monthDayTime(ms: start, timeZone: timeZone)),
       Cell(label: "持续时间", value: Self.duration(ms: end - order.firstSeenMs))),
      (Cell(label: "成交金额", value: fmtVol(order.filledNotional) + " (" + pct + ")"),
       Cell(label: "初始金额", value: fmtVol(order.initialNotional))),
      (Cell(label: "成交数量", value: Self.quantity(qty(order.filledNotional)) + " " + base),
       Cell(label: "初始数量", value: Self.quantity(qty(order.initialNotional)) + " " + base)),
    ]
  }

  /// 读屏与 UI 用例读的那一整段。
  var spoken: String {
    ([title + " " + status, sideTitle + " " + headline]
      + pairs.map { $0.0.label + " " + $0.0.value + "，" + $0.1.label + " " + $0.1.value })
      .joined(separator: "\n")
  }

  static func status(_ s: BigOrder.Status) -> String {
    switch s {
    case .live: "挂单中"
    case .filled: "已成交"
    case .cancelled: "已撤销"
    case .lost: "失联结束"
    }
  }

  /// 币的数量：上千用 K/M/B，一个以上两位小数，不足一个给四位。
  static func quantity(_ q: Double) -> String {
    guard q.isFinite else { return "--" }
    if abs(q) >= 1000 { return fmtVol(q) }
    return toFixed(q, abs(q) >= 1 || q == 0 ? 2 : 4)
  }

  /// 「09-24 02:38」。
  static func monthDayTime(ms: Double, timeZone: TZOffset) -> String {
    let p = DateParts(ms: ms, offsetMinutes: timeZone)
    let two = { (n: Int) in n < 10 ? "0\(n)" : "\(n)" }
    return two(p.month) + "-" + two(p.day) + " " + two(p.hour) + ":" + two(p.minute)
  }

  /// 「15 小时 27 分」；一天以上「2 天 3 小时」；不到一分钟「不到 1 分」。
  static func duration(ms: Int64) -> String {
    let minutes = max(0, ms) / 60_000
    if minutes < 1 { return "不到 1 分" }
    let days = minutes / 1440, hours = (minutes % 1440) / 60, mins = minutes % 60
    if days > 0 { return "\(days) 天 \(hours) 小时" }
    if hours > 0 { return "\(hours) 小时 \(mins) 分" }
    return "\(mins) 分"
  }
}
