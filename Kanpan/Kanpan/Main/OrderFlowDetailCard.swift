import KanpanChart
import KanpanCore
import SwiftUI

/// 主力订单流的详情卡：一堵墙一卡（2026-09-24 晚改手机布局；2026-09-25 相邻桶并成墙、卡只留关键信息）。
///
/// 图上同一侧、同一类（现货 / 合约）、相邻价位桶、时间上连着的单合成了一堵墙（`OrderFlowGroup`），
/// 轻点这条线或者十字线停在上面，就在主图里出这堵墙的卡。卡只有三行：
///   - 标题：「83,600.0 · 委托卖单 · 合约」；跨几个桶的墙写价位范围「83,900 – 84,400」
///     （最低桶的桶价 – 最高桶的桶价 + 步长），单价位的段写那一个价，都带千分位；右上「持续 X」
///     （标题优先，放不下时时长短写成「X 小时 Y 分」）；
///   - 两行键值：总金额 / 总数量，开始 / 状态（在场 / 已撤 / 已成交 X%）。
/// 不列交易所：哪几家、哪种合约是聚合进来的，用户要的是「这里有多大一堵墙、挂了多久、还在不在」
/// （2026-09-25 用户：「详情卡不列交易所」），所以原先一本簿一行的表、折叠行都删了。
/// 尺寸：宽不超过绘图区的 85%，高不超过主图的 55%，而且不越过那条线的命中带——摆在它的上面或下面
/// （哪边空得多摆哪边），横向摆在焦点（十字线 / 线中点）的另一侧。点空白处收起，点另一条换成那一条。
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
        .frame(width: max(0, focus.plotW - 2 * Space.s), height: max(0, place.maxHeight), alignment: alignment)
        .clipped()
        .offset(x: Space.s, y: top)
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

  private var group: OrderFlowGroup { focus.group }

  var body: some View {
    // 还挂着的单，持续时长数到此刻：半分钟一跳足够（显示到分钟）。
    TimelineView(.periodic(from: .now, by: 30)) { context in
      let now = Int64(context.date.timeIntervalSince1970 * 1000)
      let lines = OrderFlowCardText(group: group, base: base, decimals: decimals, timeZone: timeZone,
                                    nowMs: max(now, focus.asOfMs))
      // 卡内三级（HIG：标题与正文差一档，字重 + 颜色一起分层）：
      //   标题 13 semibold（TypeScale.controlOn；价 ink、方向用图外涨跌色 PanelTheme.up / down）；
      //   正文 12（TypeScale.caption）——值 ink、键 ink3，状态 12 medium（captionEmph）状态色；
      //   注脚 11（TypeScale.caption2）ink3——右上的「持续 X」。
      // 间距：内边距 Inset.cardCompact 12、行距 Space.xs 4、键值之间 Space.s 8、两列之间 Space.m 12；圆角 Radius.m。
      VStack(alignment: .leading, spacing: Space.xs) {
        HStack(spacing: Space.s) {
          (Text(lines.price + " · ").foregroundStyle(theme.ink)
            + Text(lines.sideTitle).foregroundStyle(group.side == .bid ? theme.up : theme.down)
            + Text(" · " + lines.kind).foregroundStyle(theme.ink))
            .font(TypeScale.controlOn)
            .monospacedDigit()
            // 标题先拿够宽度：价位范围 + 方向 + 类一个字都不许截（17 Pro Max 上 BTC 五桶墙曾截成「委托买单 ·…」）；
            // 右上的时长让位，放不下「持续 2 小时 39 分」就写「2 小时 39 分」。
            .layoutPriority(1)
          Spacer(minLength: 0)
          ViewThatFits(in: .horizontal) {
            Text(lines.duration)
            Text(lines.durationShort)
          }
          .font(TypeScale.caption2).foregroundStyle(theme.ink3)
        }
        Grid(alignment: .leading, horizontalSpacing: Space.s, verticalSpacing: Space.xs) {
          ForEach(lines.pairs.indices, id: \.self) { i in
            let pair = lines.pairs[i]
            GridRow {
              Text(pair.0.label).foregroundStyle(theme.ink3)
              Text(pair.0.value).foregroundStyle(theme.ink)
              Text(pair.1.label).foregroundStyle(theme.ink3).padding(.leading, Space.m - Space.s)
              if i == lines.pairs.count - 1 {
                Text(pair.1.value).font(TypeScale.captionEmph).foregroundStyle(color(lines.state))
              } else {
                Text(pair.1.value).foregroundStyle(theme.ink)
              }
            }
          }
        }
        .font(TypeScale.caption)
        .monospacedDigit()
      }
      .lineLimit(1)
      .fixedSize(horizontal: false, vertical: true)
      .padding(Inset.cardCompact)
      .frame(maxWidth: maxWidth, alignment: .leading)
      // 高度贴着内容（三行，约 80 pt）；万一主图矮到放不下，由外层按上限裁掉。
      .background(theme.raised.opacity(0.96), in: RoundedRectangle(cornerRadius: Radius.m, style: .continuous))
      .overlay(RoundedRectangle(cornerRadius: Radius.m, style: .continuous).strokeBorder(theme.line, lineWidth: 1))
      .clipShape(RoundedRectangle(cornerRadius: Radius.m, style: .continuous))
      .dynamicTypeSize(...MarketChrome.typeCap)
      .accessibilityElement(children: .ignore)
      .accessibilityLabel(lines.spoken)
      .accessibilityIdentifier("chart.orderFlowCard")
    }
  }

  private func color(_ state: OrderFlowCardText.State) -> Color {
    switch state {
    case .live: theme.amber
    case .filled: theme.ink
    case .cancelled: theme.ink3
    }
  }
}

/// 卡片上的每一行字。拆出来是为了让文案口径单独可读、可测。
struct OrderFlowCardText {
  struct Cell { var label: String, value: String }
  enum State { case live, filled, cancelled }

  /// 「83,600.0」；跨几个桶的墙是价位范围「2,682 – 2,685」（最低桶的桶价 – 最高桶的桶价 + 步长）。
  var price: String
  /// 跨了不止一个桶：标题写范围。
  var isRange: Bool
  /// 「委托买单」/「委托卖单」。
  var sideTitle: String
  /// 「合约」/「现货」。
  var kind: String
  /// 「持续 15 小时 27 分」。
  var duration: String
  /// 标题行放不下时的短写「15 小时 27 分」。
  var durationShort: String
  /// 两行键值：总金额 / 总数量，开始 / 状态。
  var pairs: [(Cell, Cell)]
  /// 状态的颜色档。
  var state: State

  init(group: OrderFlowGroup, base: String, decimals: Int, timeZone: TZOffset, nowMs: Int64) {
    isRange = group.isRange
    // 范围两端按步长的位数写（步长 1 写整数、0.1 写一位），不多于品种的价格位数。
    let bucketDecimals = min(decimals, group.step.map(Self.stepDecimals) ?? decimals)
    // 卡是给人读的一句话，价和头部一个写法带千分位（`grouped`）；价格轴那种密排数据才不加。
    price = isRange
      ? grouped(fmtPrice(group.priceLow, decimals: bucketDecimals)) + " – " + grouped(fmtPrice(group.priceHigh, decimals: bucketDecimals))
      : grouped(fmtPrice(group.price, decimals: decimals))
    sideTitle = group.side == .bid ? "委托买单" : "委托卖单"
    kind = group.contract ? "合约" : "现货"
    let end = group.endMs ?? nowMs
    durationShort = Self.duration(ms: end - group.firstSeenMs)
    duration = "持续 " + durationShort
    let qty = { (usd: Double, price: Double) in price > 0 ? usd / price : 0 }
    let totalQty = group.books.reduce(0) { $0 + qty($1.notional, $1.latest.price) }
    let status = Self.status(group)
    state = status.state
    pairs = [
      (Cell(label: "总金额", value: fmtVol(group.notional) + " USDT"),
       Cell(label: "总数量", value: Self.quantity(totalQty) + " " + base)),
      (Cell(label: "开始", value: Self.monthDayTime(ms: Double(group.firstSeenMs), timeZone: timeZone)),
       Cell(label: "状态", value: status.text)),
    ]
  }

  /// 整堵墙的状态：还有一单挂着就是「在场」（吃过的补一句成交比例）；都结束了，吃过就是「已成交 X%」，
  /// 一口没吃（撤单、失联）是「已撤」。比例和图上深浅同一个判据（`OrderFlowGroup.hasFill` / `fillRatio`）。
  static func status(_ group: OrderFlowGroup) -> (text: String, state: State) {
    let pct = percent(group.fillRatio)
    if group.isLive { return (group.hasFill ? "在场 · 已成交 " + pct : "在场", .live) }
    if group.hasFill { return ("已成交 " + pct, .filled) }
    return ("已撤", .cancelled)
  }

  /// 「38%」；不到 10% 留一位小数（「0.4%」），免得小成交写成 0%。
  static func percent(_ ratio: Double) -> String {
    let v = ratio * 100
    return (v >= 10 ? toFixed(v, 0) : toFixed(v, 1)) + "%"
  }

  /// 步长要几位小数才写得下（1 → 0、0.1 → 1、0.25 → 2、0.005 → 3）。
  static func stepDecimals(_ step: Double) -> Int {
    guard step.isFinite, step > 0 else { return 0 }
    for d in 0...8 {
      let scaled = step * pow(10, Double(d))
      if abs(scaled - scaled.rounded()) <= 1e-9 * max(1, scaled) { return d }
    }
    return 8
  }

  /// 读屏与 UI 用例读的那一整段。
  var spoken: String {
    ([price + " " + sideTitle + " " + kind + " " + duration]
      + pairs.map { $0.0.label + " " + $0.0.value + "，" + $0.1.label + " " + $0.1.value })
      .joined(separator: "\n")
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
