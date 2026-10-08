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
///   - 两行键值：总金额 / 总数量，开始 / 状态（在场 / 在场 · 成交 X% / 成交 X% · 撤 Y% / 已成交 / 已撤）；
///     主图矮（能摆卡那段 < 200 pt）时两行：标题 + 总金额 / 状态。
/// 不列交易所：哪几家、哪种合约是聚合进来的，用户要的是「这里有多大一堵墙、挂了多久、还在不在」
/// （2026-09-25 用户：「详情卡不列交易所」），所以原先一本簿一行的表、折叠行都删了。
/// 尺寸：宽不超过绘图区的 85%，高不超过主图的 55%，而且不越过那条线的命中带；摆在带所在半边的对面、贴主图远端，
/// 横向摆在焦点（十字线 / 线中点）的另一侧，不盖住十字线那根 K 线（`OrderFlowCardBudget.placement`）。点空白处收起，点另一条换成那一条。
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
      let inset = OrderFlowCardBudget.sideInset
      // 卡在带的对面那一半、贴远端（带在上半边就贴主图下沿，反之贴上沿），横向贴焦点另一侧的边（D4）。
      let alignment = Alignment(horizontal: place.leading ? .leading : .trailing, vertical: place.below ? .bottom : .top)
      // 主图矮或那一段放不下三行就出两行卡（D6）；万一两行也放不下，照样整张画出来（不裁），
      // 按贴远端的方向往带那边伸——内容被裁掉比盖住一点带更糟（原来 `.clipped()` 把状态行裁掉一半）。
      Group {
        if place.compact {
          card(focus, compact: true, place: place)
        } else {
          ViewThatFits(in: .vertical) {
            card(focus, compact: false, place: place)
            card(focus, compact: true, place: place)
          }
        }
      }
      .frame(width: max(0, focus.plotW - 2 * inset), height: max(0, place.maxHeight), alignment: alignment)
      .offset(x: inset, y: place.top)
      .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
      .allowsHitTesting(false)
    }
  }

  private func card(_ focus: ChartOrderFlowFocus, compact: Bool, place: OrderFlowCardBudget.Placement) -> some View {
    OrderFlowDetailCard(focus: focus, theme: theme, base: base, decimals: decimals, timeZone: timeZone,
                        maxWidth: place.maxWidth, compact: compact)
  }
}

struct OrderFlowDetailCard: View {
  let focus: ChartOrderFlowFocus
  let theme: PanelTheme
  let base: String
  let decimals: Int
  let timeZone: TZOffset
  let maxWidth: Double
  /// 两行卡（主图矮时）：标题 + 总金额 / 状态，不写总数量与开始（D6）。
  var compact = false

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
            // 右上的时长让位，放不下「持续 2 小时 39 分」就写「2 小时 39 分」，再放不下写「2时39分」
            // （16 Pro 上 BTC 跨桶墙挂到几小时，前两种都放不下，原来截成「2 小…」）。
            // 1e-6 价位的区间（1000SATS 这类七八位小数）整行比卡宽，标题最多缩到 0.8 倍，不截字。
            .minimumScaleFactor(0.8)
            .layoutPriority(1)
          Spacer(minLength: 0)
          ViewThatFits(in: .horizontal) {
            Text(lines.duration)
            Text(lines.durationShort)
            Text(lines.durationCompact)
          }
          .font(TypeScale.caption2).foregroundStyle(theme.ink3)
        }
        OrderFlowCardPairs(lines: lines, theme: theme, compact: compact)
      }
      .lineLimit(1)
      .fixedSize(horizontal: false, vertical: true)
      .padding(Inset.cardCompact)
      .frame(maxWidth: maxWidth, alignment: .leading)
      // 高度贴着内容（三行约 77 pt、两行约 58 pt，`OrderFlowCardBudget.fullHeight / compactHeight` 按它留）。
      .background(theme.raised.opacity(0.96), in: RoundedRectangle(cornerRadius: Radius.m, style: .continuous))
      .overlay(RoundedRectangle(cornerRadius: Radius.m, style: .continuous).strokeBorder(theme.line, lineWidth: 1))
      .clipShape(RoundedRectangle(cornerRadius: Radius.m, style: .continuous))
      .dynamicTypeSize(...MarketChrome.typeCap)
      .accessibilityElement(children: .ignore)
      .accessibilityLabel(lines.spoken)
      .accessibilityIdentifier("chart.orderFlowCard")
    }
  }
}

/// 卡上的键值行（三行卡两行、两行卡一行）。拆出来是为了单测量它的理想宽：16 Pro 上卡宽约 300 pt，
/// 「开始 09-28 20:44 状态 成交 40% · 撤 60%」要整句放得下（D5）。
struct OrderFlowCardPairs: View {
  let lines: OrderFlowCardText
  let theme: PanelTheme
  var compact = false
  /// 状态那格的写法：nil 由 ViewThatFits 按宽挑；单测用它量每一档的理想宽。
  var statusFit: StatusFit? = nil

  enum StatusFit { case spaced, tight, bare }

  var body: some View {
    Grid(alignment: .leading, horizontalSpacing: Space.s, verticalSpacing: Space.xs) {
      let rows = compact ? [lines.compactPair] : lines.pairs
      ForEach(rows.indices, id: \.self) { i in
        let pair = rows[i]
        GridRow {
          Text(pair.0.label).foregroundStyle(theme.ink3)
          Text(pair.0.value).foregroundStyle(theme.ink)
          if i == rows.count - 1 {
            // 状态：「状态」和值合成一格、跨后两列——「状态」比上一行的「总数量」窄一个字，不再按「总数量」
            // 占满第三列，值往左挪 12 pt。部分成交后撤写「成交 40% · 撤 60%」，16 Pro 上卡宽约 300 pt：
            // 放不下先去掉空格，再放不下（不到 1% 带小数那句）连「状态」两字也让掉，两个数都留着（D5）。
            Group {
              if let statusFit {
                status(statusFit, label: pair.1.label)
              } else {
                ViewThatFits(in: .horizontal) {
                  status(.spaced, label: pair.1.label)
                  status(.tight, label: pair.1.label)
                  status(.bare, label: pair.1.label)
                }
              }
            }
            .padding(.leading, Space.m - Space.s)
            .gridCellColumns(2)
          } else {
            Text(pair.1.label).foregroundStyle(theme.ink3).padding(.leading, Space.m - Space.s)
            Text(pair.1.value).foregroundStyle(theme.ink)
          }
        }
      }
    }
    .font(TypeScale.caption)
    .monospacedDigit()
    // 「总数量 12.35M 1000SATS」这类长币名 + 大金额整行比卡宽：数字缩一点，不截成「12.3…」。
    .minimumScaleFactor(0.8)
  }

  private func status(_ fit: StatusFit, label: String) -> some View {
    HStack(spacing: Space.s) {
      if fit != .bare { Text(label).foregroundStyle(theme.ink3) }
      Text(fit == .spaced ? lines.statusText : lines.statusTight)
        .font(TypeScale.captionEmph).foregroundStyle(color(lines.state))
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
  /// 再放不下的紧写「15时27分」（和头部结算倒计时一个写法）。
  var durationCompact: String
  /// 两行键值：总金额 / 总数量，开始 / 状态。
  var pairs: [(Cell, Cell)]
  /// 两行卡（主图矮时）的那一行键值：总金额 / 状态。
  var compactPair: (Cell, Cell)
  /// 状态：「在场」「在场 · 成交 19%」「成交 40% · 撤 60%」「已成交」「已撤」。
  var statusText: String
  /// 状态放不下时去掉空格的写法（「成交40%·撤60%」）。
  var statusTight: String
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
    durationCompact = durationShort.replacingOccurrences(of: " ", with: "").replacingOccurrences(of: "小时", with: "时")
    duration = "持续 " + durationShort
    let qty = { (usd: Double, price: Double) in price > 0 ? usd / price : 0 }
    let totalQty = group.books.reduce(0) { $0 + qty($1.notional, $1.latest.price) }
    let status = Self.status(group)
    state = status.state
    statusText = status.text
    statusTight = Self.tight(status.text)
    let amount = Cell(label: "总金额", value: fmtVol(group.notional) + " USDT")
    let statusCell = Cell(label: "状态", value: status.text)
    pairs = [
      (amount, Cell(label: "总数量", value: Self.quantity(totalQty) + " " + base)),
      (Cell(label: "开始", value: Self.monthDayTime(ms: Double(group.firstSeenMs), timeZone: timeZone)), statusCell),
    ]
    compactPair = (amount, statusCell)
  }

  /// 去掉数字、百分号、间隔点两边的空格：「成交 40% · 撤 60%」→「成交40%·撤60%」。
  static func tight(_ text: String) -> String {
    text.replacingOccurrences(of: " · ", with: "·").replacingOccurrences(of: " ", with: "")
  }

  /// 整堵墙的状态：还有一单挂着就是「在场」（吃过的补一句成交比例）；都结束了——
  ///   - 全吃掉（比例写出来是 100%）是「已成交」；
  ///   - 吃了一部分、剩下的撤了是「成交 40% · 撤 60%」（两数相加恰好 100，撤的按写出来的成交比例补齐）；
  ///   - 一口没吃（撤单、失联）是「已撤」。
  /// 原来吃过一口的一律写「已成交 38%」，读起来像成交了、其实六成多是撤的（订单簿压测第二轮 D5）。
  /// 比例和图上深浅同一个判据（`OrderFlowGroup.hasFill` / `fillRatio`）。
  static func status(_ group: OrderFlowGroup) -> (text: String, state: State) {
    // 挂着的写「成交中 19%」不写「已成交」：16 Pro 上卡宽约 300 pt，「开始 09-28 20:44 状态 挂单中 · 已成交 19%」
    // 一行放不下，截成「在场 · 已成交 1…」（压测 2026-09-28 十字线取证）——比例恰恰是被截掉的那一截。
    // 用词只在 terms.json 一份（三端同）：挂单中 / 成交中 X% / 已成交 / 成交 X% · 撤单 Y% / 已撤单。
    // 用户 2026-10-08：「挂着」「在场」这类口语不要，按实际情况给一目了然的词。
    if group.isLive {
      return (group.hasFill ? BigTradeTerm.statusFilling.fill(["p": percent(group.fillRatio)]) : BigTradeTerm.statusLive.text, .live)
    }
    guard group.hasFill else { return (BigTradeTerm.statusCancelled.text, .cancelled) }
    guard let split = fillSplit(group.fillRatio) else { return (BigTradeTerm.statusFilled.text, .filled) }
    return (BigTradeTerm.statusPartFilled.fill(["f": split.filled, "c": split.cancelled]), .filled)
  }

  /// 部分成交的「成交 / 撤」两个百分数，两数相加恰好 100：1% 以上按整数（「40%」「60%」），
  /// 不到 1% 留一位小数（「0.4%」「99.6%」，免得小成交写成 0%）。写出来是 100% 的返回 nil（算全成交）。
  static func fillSplit(_ ratio: Double) -> (filled: String, cancelled: String)? {
    let v = min(100, max(0, ratio * 100))
    if v >= 1 {
      let f = Int(v.rounded())
      return f >= 100 ? nil : ("\(f)%", "\(100 - f)%")
    }
    let tenths = max(1, Int((v * 10).rounded()))  // 吃过一口就至少 0.1%
    return (toFixed(Double(tenths) / 10, 1) + "%", toFixed(Double(1000 - tenths) / 10, 1) + "%")
  }

  /// 「38%」；不到 10% 留一位小数（「0.4%」），免得小成交写成 0%。
  /// 吃过一口就至少「0.1%」——原来不到 0.05% 的照样四舍五入成「在场 · 成交 0.0%」，
  /// 和「在场」后面跟一个成交比例这件事自相矛盾（结束的墙走 `fillSplit`，早就有这道底）。
  static func percent(_ ratio: Double) -> String {
    let v = ratio * 100
    if v >= 10 { return toFixed(v, 0) + "%" }
    let tenths = v > 0 ? max(1, Int((v * 10).rounded())) : 0
    return toFixed(Double(tenths) / 10, 1) + "%"
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
