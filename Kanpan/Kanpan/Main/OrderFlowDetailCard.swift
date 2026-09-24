import KanpanChart
import KanpanCore
import SwiftUI

/// 主力订单流的详情卡：一桶一卡（2026-09-24 晚改手机布局）。
///
/// 图上同一价位桶、同一侧、同一类（现货 / 合约）的单合成了一条带（`OrderFlowGroup`），
/// 轻点这条带或者十字线停在上面，就在主图里出这一桶的卡：
///   - 标题：「83,600 · 委托卖单 · 合约」，右边「持续 X」；
///   - 汇总两行：合计数量 / 合计金额（USDT）、成交金额与比例 / 最早挂单时间；
///   - 下面一本簿一行（按此刻名义从大到小）：交易所 产品 · 数量 · 金额 · 状态 · 成交比例；
///     最多六行，再多折成「还有 N 本」；主图矮、放不下就再少列几行。
/// 尺寸：宽不超过绘图区的 85%，高不超过主图的 55%，而且不越过那条带——摆在带的上面或下面
/// （哪边空得多摆哪边），横向摆在焦点（十字线 / 带中点）的另一侧。点空白处收起，点另一条换成那一条。
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
      let place = focus.cardPlacement
      let gap = OrderFlowCardBudget.bandGap
      // 焦点在右半边就摆左边，反之摆右边；带下空得多就贴着带下沿往下排，否则贴着带上沿往上排。
      let alignment = Alignment(horizontal: focus.anchorX > focus.plotW / 2 ? .leading : .trailing,
                                vertical: place.below ? .top : .bottom)
      let top = place.below ? focus.bandY + focus.bandHalf + gap : focus.bandY - focus.bandHalf - gap - place.maxHeight
      OrderFlowDetailCard(focus: focus, theme: theme, base: base, decimals: decimals, timeZone: timeZone,
                          maxWidth: focus.cardMaxWidth, maxHeight: place.maxHeight)
        .frame(width: max(0, focus.plotW - 16), height: max(0, place.maxHeight), alignment: alignment)
        .offset(x: 8, y: top)
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
  let maxWidth: Double
  let maxHeight: Double

  /// 排行数用的估高（pt）：内边距 12 × 2 + 标题一行 + 汇总两行 + 分隔线与间距；簿一行 12 pt 字 + 4 pt 行距。
  /// 实际高度超了还有 `.clipped()` 兜底，不会越过带或出主图。
  static let fixedHeight = 94.0
  static let rowHeight = 19.0

  private var group: OrderFlowGroup { focus.group }

  var body: some View {
    // 还挂着的单，持续时长数到此刻：半分钟一跳足够（显示到分钟）。
    TimelineView(.periodic(from: .now, by: 30)) { context in
      let now = Int64(context.date.timeIntervalSince1970 * 1000)
      let lines = OrderFlowCardText(group: group, base: base, decimals: decimals, timeZone: timeZone,
                                    nowMs: max(now, focus.asOfMs),
                                    lines: OrderFlowCardBudget.lines(maxHeight: maxHeight, fixedHeight: Self.fixedHeight,
                                                                     rowHeight: Self.rowHeight))
      // 卡内两级（UI 审查 2026-09-24 §4.3 #30）：标题 13 semibold，其余一律 12——
      // 状态 12 medium 状态色、正文 12 等宽 ink、标签 12 次墨色。
      VStack(alignment: .leading, spacing: Space.xs) {
        HStack(spacing: Space.s) {
          (Text(lines.price + " · ").foregroundStyle(theme.ink)
            + Text(lines.sideTitle).foregroundStyle(group.side == .bid ? theme.up : theme.down)
            + Text(" · " + lines.kind).foregroundStyle(theme.ink))
            .font(TypeScale.controlOn)
            .monospacedDigit()
          Spacer(minLength: Space.s)
          Text(lines.duration).font(TypeScale.caption).foregroundStyle(theme.ink3)
        }
        Grid(alignment: .leading, horizontalSpacing: Space.s, verticalSpacing: Space.xs) {
          ForEach(lines.pairs.indices, id: \.self) { i in
            let pair = lines.pairs[i]
            GridRow {
              Text(pair.0.label).foregroundStyle(theme.ink3)
              Text(pair.0.value).foregroundStyle(theme.ink)
              Text(pair.1.label).foregroundStyle(theme.ink3).padding(.leading, Space.s)
              Text(pair.1.value).foregroundStyle(theme.ink)
            }
          }
        }
        .font(TypeScale.caption)
        .monospacedDigit()
        Rectangle().fill(theme.line).frame(height: 1)
        Grid(alignment: .leading, horizontalSpacing: Space.s, verticalSpacing: Space.xs) {
          ForEach(lines.rows.indices, id: \.self) { i in
            let row = lines.rows[i]
            GridRow {
              Text(row.name).foregroundStyle(theme.ink2).layoutPriority(-1)
              Text(row.quantity).foregroundStyle(theme.ink).gridColumnAlignment(.trailing)
              Text(row.amount).foregroundStyle(theme.ink).gridColumnAlignment(.trailing)
              Text(row.status).font(TypeScale.captionEmph).foregroundStyle(color(row.state))
              Text(row.fill).foregroundStyle(theme.ink3).gridColumnAlignment(.trailing)
            }
          }
        }
        .font(TypeScale.caption)
        .monospacedDigit()
        if let folded = lines.folded {
          Text(folded).font(TypeScale.caption).foregroundStyle(theme.ink3)
        }
      }
      .lineLimit(1)
      .fixedSize(horizontal: false, vertical: true)
      .padding(Inset.cardCompact)
      .frame(maxWidth: maxWidth, alignment: .leading)
      .frame(maxHeight: maxHeight, alignment: .top)
      .background(theme.raised.opacity(0.96), in: RoundedRectangle(cornerRadius: Radius.m, style: .continuous))
      .overlay(RoundedRectangle(cornerRadius: Radius.m, style: .continuous).strokeBorder(theme.line, lineWidth: 1))
      .clipShape(RoundedRectangle(cornerRadius: Radius.m, style: .continuous))
      .dynamicTypeSize(...MarketChrome.typeCap)
      .accessibilityElement(children: .ignore)
      .accessibilityLabel(lines.spoken)
      .accessibilityIdentifier("chart.orderFlowCard")
    }
  }

  private func color(_ state: OrderFlowCardText.RowState) -> Color {
    switch state {
    case .live: theme.amber
    case .filled, .partial: theme.ink
    case .cancelled, .lost: theme.ink3
    }
  }
}

/// 卡片上的每一行字。拆出来是为了让文案口径单独可读、可测。
struct OrderFlowCardText {
  struct Cell { var label: String, value: String }
  enum RowState { case live, filled, partial, cancelled, lost }
  struct Row {
    /// 「币安 永续」。
    var name: String
    var quantity: String
    var amount: String
    var status: String
    var state: RowState
    /// 成交比例；一口没成交是「—」。
    var fill: String
  }

  /// 「83,600.0」。
  var price: String
  /// 「委托买单」/「委托卖单」。
  var sideTitle: String
  /// 「合约」/「现货」。
  var kind: String
  /// 「持续 15 小时 27 分」。
  var duration: String
  var pairs: [(Cell, Cell)]
  var rows: [Row]
  /// 「还有 N 本」；全列下了是 nil。
  var folded: String?

  init(group: OrderFlowGroup, base: String, decimals: Int, timeZone: TZOffset, nowMs: Int64,
       lines: Int = OrderFlowCardBudget.maxRows) {
    price = fmtPrice(group.price, decimals: decimals)
    sideTitle = group.side == .bid ? "委托买单" : "委托卖单"
    kind = group.contract ? "合约" : "现货"
    let end = group.endMs ?? nowMs
    duration = "持续 " + Self.duration(ms: end - group.firstSeenMs)
    let qty = { (usd: Double, price: Double) in price > 0 ? usd / price : 0 }
    let totalQty = group.books.reduce(0) { $0 + qty($1.notional, $1.latest.price) }
    let pct = toFixed(group.fillRatio * 100, 1) + "%"
    pairs = [
      (Cell(label: "数量", value: Self.quantity(totalQty) + " " + base),
       Cell(label: "金额", value: fmtVol(group.notional) + " USDT")),
      (Cell(label: "成交", value: group.hasFill ? fmtVol(group.filledNotional) + " (" + pct + ")" : "—"),
       Cell(label: "最早", value: Self.monthDayTime(ms: Double(group.firstSeenMs), timeZone: timeZone))),
    ]
    let budget = OrderFlowCardBudget.rows(books: group.books.count, lines: lines)
    rows = group.books.prefix(budget.shown).map { book in
      Row(name: book.exchange + " " + book.product.shortLabel,
          quantity: Self.quantity(qty(book.notional, book.latest.price)),
          amount: fmtVol(book.notional),
          status: Self.status(book.latest),
          state: Self.state(book.latest),
          fill: book.hasFill ? toFixed(book.fillRatio * 100, 1) + "%" : "—")
    }
    folded = budget.folded > 0 ? "还有 \(budget.folded) 本" : nil
  }

  /// 读屏与 UI 用例读的那一整段。
  var spoken: String {
    ([price + " " + sideTitle + " " + kind + " " + duration]
      + pairs.map { $0.0.label + " " + $0.0.value + "，" + $0.1.label + " " + $0.1.value }
      + rows.map { [$0.name, $0.quantity, $0.amount, $0.status, $0.fill].joined(separator: " ") }
      + (folded.map { [$0] } ?? []))
      .joined(separator: "\n")
  }

  /// 照 CoinAnk 四档：挂单中 / 已成交 / 部分成交 / 已撤销，外加失联结束。「部分成交」= 判成撤单但吃过（`hasFill`），
  /// 和图上「有成交就画深色」同一个判据；成交了多少看这一行的成交比例。
  static func status(_ order: BigOrder) -> String {
    switch order.status {
    case .live: "挂单中"
    case .filled: "已成交"
    case .cancelled: order.hasFill ? "部分成交" : "已撤销"
    case .lost: "失联结束"
    }
  }

  static func state(_ order: BigOrder) -> RowState {
    switch order.status {
    case .live: .live
    case .filled: .filled
    case .cancelled: order.hasFill ? .partial : .cancelled
    case .lost: .lost
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
