import SwiftUI
import UIKit
import KanpanCore
import ReviewDomain

// 复盘本「交易」这一半的界面（自动复盘 3c）：列表、周报卡、详情、战绩。
// 数都是本机现算的（`RoundStats`），服务端只回写每一笔自己的结果（浮盈浮亏、离开后、复盘图的窗口）。

/// 一笔的短名、徽章、金额颜色这些小事，列表和详情共用。
extension TradeRound {
  var shortSymbol: String { TradeLabels.shortSymbol(instrument.key) }
}

private func pnlColor(_ value: Decimal, _ t: ReviewTheme) -> Color {
  // 颜色跟着摆出来的数走（`TradeLabels.moneyTone`）：写成「0.00」的不涂涨跌色。
  let tone = TradeLabels.moneyTone(value)
  return tone > 0 ? t.up : tone < 0 ? t.down : t.ink2
}

/// 百分比那一路（「离开后」的涨跌）：跟 `TradeLabels.percent` 摆出来的一位小数走，不借金额的两位小数。
private func percentColor(_ ratio: Decimal, _ t: ReviewTheme) -> Color {
  let tone = TradeLabels.percentTone(ratio)
  return tone > 0 ? t.up : tone < 0 ? t.down : t.ink2
}

// MARK: - 列表

/// 「交易」那一段：上周卡 + 持仓中 + 按天分组的回合。
struct TradeBookList: View {
  @Bindable var feature: ReviewFeature
  @Environment(\.reviewTheme) private var t
  private var trades: TradeReviewFeature { feature.trades }

  var body: some View {
    let items = trades.items
    let calendar = feature.calendar
    VStack(spacing: 0) {
      if trades.exchange.connected || !items.isEmpty {
        TradeWeekCard(feature: feature).reviewPageInset().padding(.vertical, ReviewSpace.s)
      }
      List {
        if items.isEmpty {
          if trades.exchange.connected {
            Text(trades.syncing ? "正在同步" : "还没有交易")
              .font(ReviewType.body).foregroundStyle(t.ink3)
              .frame(maxWidth: .infinity, minHeight: ReviewControl.hit)
              .listRowBackground(t.app).listRowSeparator(.hidden)
              .accessibilityIdentifier("review.trades.empty")
          } else {
            // 没接交易所：就这一行，点进去是接入页。不讲教程。
            Button { feature.bookOpen = false; trades.onConnect() } label: {
              HStack {
                Text("接入交易所后自动生成").font(ReviewType.body).foregroundStyle(t.ink2)
                Spacer()
                Image(systemName: "chevron.right").font(.system(size: ReviewControl.chevron, weight: .semibold)).foregroundStyle(t.ink3)
              }
              .frame(maxWidth: .infinity, minHeight: ReviewControl.hit)
              .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .listRowBackground(t.app)
            .accessibilityIdentifier("review.trades.connect")
          }
        }
        let open = items.filter(\.round.isOpen)
        if !open.isEmpty {
          Section { ForEach(open) { row($0) } } header: { ReviewSectionTitle("持仓中") }
        }
        ForEach(Self.days(items.filter { !$0.round.isOpen }, calendar: calendar, now: ReviewClock.now)) { day in
          Section { ForEach(day.items) { row($0) } } header: { ReviewSectionTitle(day.title) }
        }
      }
      .listStyle(.plain)
      .scrollContentBackground(.hidden)
      .background(t.app)
      .accessibilityIdentifier("review.trades.list")
    }
    .task { trades.onPull(); await trades.synchronize() }
  }

  private func row(_ item: TradeItem) -> some View {
    NavigationLink { TradeRecordView(feature: feature, id: item.id) } label: { TradeRow(item: item, feature: feature) }
      .listRowBackground(t.app)
      .accessibilityIdentifier("review.trades.row.\(item.round.shortSymbol)")
  }

  /// 按平仓那天分组的一组。`id` 是年月日（不是标题）：标题不带年份，跨年的同月同日
  /// 以前会被并成一组（审查 R17）。
  struct Day: Identifiable, Equatable {
    var id: String
    var title: String
    var items: [TradeItem]
  }
  /// 周几的写法（和以前 `zh_CN` 的 `EEE` 一致），按 `Calendar.weekday` 的 1…7（周日起）取。
  private static let weekdays = ["周日", "周一", "周二", "周三", "周四", "周五", "周六"]

  /// 按平仓那天分组（复盘本那一档日历，统一上海时间），新的在上。
  /// 不是今年的带上年份。不造 `DateFormatter`：这是每次 body 都要跑的，日期几段直接拿日历拆。
  static func days(_ items: [TradeItem], calendar: Calendar, now: Int64) -> [Day] {
    let today = Date(timeIntervalSince1970: Double(now) / 1000)
    let thisYear = calendar.component(.year, from: today)
    let todayStart = calendar.startOfDay(for: today)
    let yesterdayStart = calendar.date(byAdding: .day, value: -1, to: todayStart)
    var order: [Day] = []
    var index: [String: Int] = [:]
    for item in items {
      let date = Date(timeIntervalSince1970: Double(item.round.closedAt ?? item.round.openedAt) / 1000)
      let parts = calendar.dateComponents([.year, .month, .day, .weekday], from: date)
      let year = parts.year ?? 0, month = parts.month ?? 0, day = parts.day ?? 0
      let key = "\(year)-\(month)-\(day)"
      if let at = index[key] { order[at].items.append(item); continue }
      let start = calendar.startOfDay(for: date)
      let title: String
      if start == todayStart { title = "今天" }
      else if start == yesterdayStart { title = "昨天" }
      else {
        let weekday = parts.weekday.map { Self.weekdays[($0 - 1 + 7) % 7] } ?? ""
        title = (year == thisYear ? "" : "\(year) 年 ") + "\(month) 月 \(day) 日 " + weekday
      }
      index[key] = order.count
      order.append(Day(id: key, title: title, items: [item]))
    }
    return order
  }
}

/// 列表里的一行：徽章、短名、方向、净盈亏、持仓时长、右边一张小图。
struct TradeRow: View {
  let item: TradeItem
  let feature: ReviewFeature
  @Environment(\.reviewTheme) private var t
  static let thumb = CGSize(width: 72, height: 44)

  var body: some View {
    let round = item.round
    HStack(spacing: ReviewSpace.m) {
      if let badge = feature.trades.badge { badge(round.instrument.key).frame(width: 28, height: 28) }
      VStack(alignment: .leading, spacing: ReviewSpace.xs) {
        HStack(alignment: .firstTextBaseline, spacing: ReviewSpace.s) {
          Text(round.shortSymbol).font(ReviewType.bodyEmph).foregroundStyle(t.ink)
          Text(TradeLabels.direction(round.direction))
            .font(ReviewType.captionEmph)
            .foregroundStyle(round.direction == .long ? t.up : t.down)
          if let leverage = round.leverage { Text("\(leverage)x").font(ReviewType.caption).foregroundStyle(t.ink3) }
        }
        // 持仓时长不许折行（09-27 截图里「已持 4 小时 22 分」被右边的胶囊和小图挤成两行）；
        // 挤不下时先截日期那一截的尾巴，时长整段保住。
        HStack(spacing: ReviewSpace.s) {
          Text(round.isOpen ? "已持 " + TradeLabels.holding(ReviewClock.now - round.openedAt) : TradeLabels.holding(round.holdingMs))
            .fixedSize(horizontal: true, vertical: false)
          Text(feature.dayTime(round.closedAt ?? round.openedAt))
            .truncationMode(.tail)
        }
        .lineLimit(1)
        .font(ReviewType.caption).foregroundStyle(t.ink3).monospacedDigit()
      }
      Spacer(minLength: ReviewSpace.xs)
      if round.isOpen {
        Text("持仓中").font(ReviewType.captionEmph).foregroundStyle(t.accent)
          .padding(.horizontal, ReviewSpace.s).frame(minHeight: 22)
          .background(t.accent.opacity(0.12), in: Capsule())
          .accessibilityIdentifier("review.trades.open")
      } else {
        Text(TradeLabels.money(round.netPnl)).font(ReviewType.bodyEmph).monospacedDigit()
          .foregroundStyle(pnlColor(round.netPnl, t))
      }
      TradeChartImage(feature: feature, item: item, size: Self.thumb)
        .frame(width: Self.thumb.width, height: Self.thumb.height)
        .clipShape(RoundedRectangle(cornerRadius: ReviewRadius.xs, style: .continuous))
    }
    .padding(.vertical, ReviewSpace.xs)
    .accessibilityElement(children: .combine)
  }
}

/// 一笔的复盘图：本页记着就直接给，没有就请宿主画一张。
struct TradeChartImage: View {
  let feature: ReviewFeature
  let item: TradeItem
  let size: CGSize
  @Environment(\.reviewTheme) private var t
  var body: some View {
    let trades = feature.trades
    let _ = trades.imageVersion
    Group {
      if let data = trades.image(item.round, size: size), let image = UIImage(data: data) {
        Image(uiImage: image).resizable().scaledToFill()
      } else {
        t.raised
      }
    }
    .task(id: "\(item.round.id)@\(item.round.updatedAt)@\(item.record?.result?.chart?.end ?? 0)") {
      await trades.loadImage(item.round, spec: item.record?.result?.chart, size: size)
    }
  }
}

/// 上周卡：笔数、净盈亏、胜率，最好 / 最差一笔，手续费。点开是交易那一面的战绩。
struct TradeWeekCard: View {
  @Bindable var feature: ReviewFeature
  @Environment(\.reviewTheme) private var t
  var body: some View {
    let week = feature.trades.weekly(now: ReviewClock.now, calendar: feature.calendar)
    let s = week.summary
    NavigationLink { ReviewStatisticsView(feature: feature) } label: {
      VStack(alignment: .leading, spacing: ReviewSpace.s) {
        HStack(alignment: .firstTextBaseline) {
          Text("上周").font(ReviewType.title).foregroundStyle(t.ink)
          Text(Self.span(week, calendar: feature.calendar)).font(ReviewType.caption).foregroundStyle(t.ink3).monospacedDigit()
          Spacer()
          Image(systemName: "chevron.right").font(.system(size: ReviewControl.chevron, weight: .semibold)).foregroundStyle(t.ink3)
        }
        HStack(spacing: ReviewSpace.xxl) {
          stat("笔数", "\(s.count)", t.ink)
          stat("净盈亏", s.count == 0 ? "—" : TradeLabels.money(s.netPnl), s.count == 0 ? t.ink : pnlColor(s.netPnl, t))
          stat("胜率", TradeLabels.percent(s.winRate), t.ink)
        }
        if s.count > 0 {
          HStack(spacing: ReviewSpace.m) {
            if let best = s.best { Text("最好 \(best.shortSymbol) \(TradeLabels.money(best.netPnl))") }
            if let worst = s.worst, worst.id != s.best?.id { Text("最差 \(worst.shortSymbol) \(TradeLabels.money(worst.netPnl))") }
            Text("手续费 \(TradeLabels.money(s.fees, signed: false))")
          }
          .font(ReviewType.caption).foregroundStyle(t.ink3).monospacedDigit().lineLimit(1).minimumScaleFactor(0.8)
        }
      }
      .padding(ReviewInset.cardCompact)
      .frame(maxWidth: .infinity, alignment: .leading)
      .background(t.raised, in: RoundedRectangle(cornerRadius: ReviewRadius.m, style: .continuous))
      .contentShape(RoundedRectangle(cornerRadius: ReviewRadius.m, style: .continuous))
    }
    .buttonStyle(.plain)
    .accessibilityIdentifier("review.trades.week")
  }
  private func stat(_ title: String, _ value: String, _ color: Color) -> some View {
    VStack(alignment: .leading, spacing: ReviewSpace.xxs) {
      Text(value).font(ReviewType.stat).foregroundStyle(color).monospacedDigit()
      Text(title).font(ReviewType.caption).foregroundStyle(t.ink3)
    }
  }
  /// 「9/21–9/27」。日期直接拿日历拆，不在每次 body 里造 `DateFormatter`。
  static func span(_ week: WeeklyReport, calendar: Calendar) -> String {
    func monthDay(_ ms: Int64) -> String {
      let parts = calendar.dateComponents([.month, .day], from: Date(timeIntervalSince1970: Double(ms) / 1000))
      return "\(parts.month ?? 0)/\(parts.day ?? 0)"
    }
    return monthDay(week.start) + "–" + monthDay(week.end - 1)
  }
}

// MARK: - 详情

public struct TradeRecordView: View {
  @Bindable var feature: ReviewFeature
  let id: String
  @State private var note = ""
  @State private var loadedNote: String?
  @FocusState private var typing: Bool
  @Environment(\.reviewTheme) private var t
  public init(feature: ReviewFeature, id: String) { self.feature = feature; self.id = id }

  public var body: some View {
    Group {
      if let item = feature.trades.item(id) {
        content(item)
      } else {
        ContentUnavailableView("这笔暂不可用", systemImage: "chart.xyaxis.line")
      }
    }
    .readableColumn()
    .background(t.app)
    .tint(t.accent)
    .navigationTitle("交易详情").navigationBarTitleDisplayMode(.inline)
    .task(id: id) { await feature.trades.refreshDetail(id) }
  }

  @ViewBuilder private func content(_ item: TradeItem) -> some View {
    let round = item.round
    ScrollViewReader { scroller in
    List {
      Section { header(round) }.listRowBackground(t.raised)
      Section {
        GeometryReader { proxy in
          TradeChartImage(feature: feature, item: item, size: CGSize(width: max(200, proxy.size.width.rounded()), height: 220))
            .frame(width: proxy.size.width, height: 220)
        }
        .frame(height: 220)
        .clipShape(RoundedRectangle(cornerRadius: ReviewRadius.s, style: .continuous))
        .accessibilityIdentifier("trade.detail.chart")
        // 已平仓的一笔：点图（或正中那颗播放圆片）一下就回到行情图上把这笔从头播一遍（3d）。
        // 持仓中的没有圆片、图也不可点。
        .contentShape(Rectangle())
        .onTapGesture { if !round.isOpen { replay(item) } }
        .overlay { if !round.isOpen { TradeReplayPlayDisc { replay(item) } } }
        .listRowInsets(EdgeInsets(top: ReviewSpace.s, leading: ReviewSpace.m, bottom: ReviewSpace.s, trailing: ReviewSpace.m))
      }.listRowBackground(t.raised)
      ReviewSection("成交", term: "fills") {
        ForEach(round.fills, id: \.id) { fill in fillRow(fill, round) }
      }.listRowBackground(t.raised)
      ReviewSection("结算") {
        LabeledContent("开仓均价", value: price(round.openAvgPrice, round))
        if let close = round.closeAvgPrice { LabeledContent("平仓均价", value: price(close, round)) }
        LabeledContent("最大仓位", value: TradeLabels.qty(round.maxQty) + " · " + TradeLabels.money(round.peakNotional, signed: false))
        termRow("已实现", term: "realized", TradeLabels.money(round.realizedPnl))
        LabeledContent("手续费", value: TradeLabels.money(-round.commission))
        if round.funding != 0 { LabeledContent("资金费", value: TradeLabels.money(round.funding)) }
        LabeledContent("持仓", value: round.isOpen ? "已持 " + TradeLabels.holding(ReviewClock.now - round.openedAt) : TradeLabels.holding(round.holdingMs))
      }
      .monospacedDigit()
      .listRowBackground(t.raised)
      if !round.isOpen {
        excursion(item)
        after(item)
      }
      ReviewSection("当时怎么想") {
        if item.record != nil && feature.isConnected {
          TextField("开这一笔时在想什么", text: $note, axis: .vertical)
            .lineLimit(3...8).focused($typing)
            .accessibilityIdentifier("trade.detail.note")
          Button("保存") { typing = false; save(item) }
            .font(ReviewType.bodyEmph).foregroundStyle(t.accent)
            .disabled(note == (item.record?.note?.text ?? ""))
            .accessibilityIdentifier("trade.detail.note.save")
        } else {
          Text(feature.isConnected ? "同步后可写" : "登录后可写").font(ReviewType.body).foregroundStyle(t.ink3)
        }
      }
      .listRowBackground(t.raised)
      .id(Self.noteAnchor)
      let views = feature.views(for: round)
      if !views.isEmpty {
        ReviewSection("对应的观点") {
          ForEach(views) { record in
            NavigationLink { ReviewRecordView(feature: feature, id: record.id) } label: { ReviewRecordRow(record: record, feature: feature) }
          }
        }
        .listRowBackground(t.raised)
        .accessibilityIdentifier("trade.detail.views")
      }
    }
    .font(ReviewType.body)
    .scrollContentBackground(.hidden)
    .background(t.app)
    .accessibilityIdentifier("trade.detail")
    .onAppear { syncNote(item) }
    .onChange(of: item.record?.note) { syncNote(item) }
    .onDisappear { if item.record != nil, note != (item.record?.note?.text ?? "") { save(item) } }
    // 看完回放回到这里：这笔还没写过「当时怎么想」，就直接滚到那一节、把输入框点亮——
    // 刚看完当时的走势，正是写的时候；写过了就停在顶上。不弹任何提示。
    .task(id: feature.focusTradeNote) {
      guard feature.focusTradeNote else { return }
      feature.focusTradeNote = false
      guard (item.record?.note?.text ?? "").isEmpty else { return }
      // 等推入动画落定再滚，不然滚动和推入叠在一起会闪一下。
      try? await Task.sleep(for: .milliseconds(350))
      withAnimation { scroller.scrollTo(Self.noteAnchor, anchor: .center) }
      if item.record != nil && feature.isConnected { typing = true }
    }
    }
  }

  private static let noteAnchor = "trade.detail.noteSection"

  private func replay(_ item: TradeItem) {
    typing = false
    feature.bookOpen = false
    feature.onReplayTrade(item)
  }

  private func header(_ round: TradeRound) -> some View {
    VStack(alignment: .leading, spacing: ReviewSpace.s) {
      HStack(alignment: .firstTextBaseline, spacing: ReviewSpace.s) {
        if let badge = feature.trades.badge { badge(round.instrument.key).frame(width: 28, height: 28).alignmentGuide(.firstTextBaseline) { $0[VerticalAlignment.center] + 5 } }
        Text(round.shortSymbol).font(ReviewType.title).foregroundStyle(t.ink)
        Text(TradeLabels.direction(round.direction)).font(ReviewType.bodyEmph)
          .foregroundStyle(round.direction == .long ? t.up : t.down)
        if let leverage = round.leverage { Text("\(leverage)x").font(ReviewType.caption).foregroundStyle(t.ink3) }
        Spacer()
        if round.isOpen {
          Text("持仓中").font(ReviewType.bodyEmph).foregroundStyle(t.accent)
        } else {
          Text(TradeLabels.money(round.netPnl)).font(ReviewType.stat).monospacedDigit()
            .foregroundStyle(pnlColor(round.netPnl, t))
            .accessibilityIdentifier("trade.detail.net")
        }
      }
      HStack(spacing: ReviewSpace.s) {
        Text(feature.fullTime(round.openedAt))
        if let closed = round.closedAt { Text("→"); Text(feature.fullTime(closed)) }
      }
      .font(ReviewType.caption).foregroundStyle(t.ink3).monospacedDigit()
    }
    .padding(.vertical, ReviewSpace.xs)
  }

  private func fillRow(_ fill: RoundFill, _ round: TradeRound) -> some View {
    VStack(alignment: .leading, spacing: ReviewSpace.xxs) {
      HStack(alignment: .firstTextBaseline, spacing: ReviewSpace.s) {
        Text(TradeLabels.role(fill.role)).font(ReviewType.bodyEmph)
          .foregroundStyle(fill.side == .buy ? t.up : t.down)
        Text(price(fill.price, round)).foregroundStyle(t.ink)
        Text("× " + TradeLabels.qty(fill.qty)).foregroundStyle(t.ink2)
        Spacer()
        if fill.realizedPnl != 0 {
          Text(TradeLabels.money(fill.realizedPnl)).foregroundStyle(pnlColor(fill.realizedPnl, t))
        }
      }
      .font(ReviewType.body)
      HStack(spacing: ReviewSpace.s) {
        Text(feature.dayTime(fill.time))
        Text(fill.maker ? "挂单" : "吃单")
        Text("手续费 " + TradeLabels.qty(fill.commission) + " " + fill.commissionAsset)
      }
      .font(ReviewType.caption).foregroundStyle(t.ink3)
    }
    .monospacedDigit()
    .padding(.vertical, ReviewSpace.xxs)
  }

  @ViewBuilder private func excursion(_ item: TradeItem) -> some View {
    ReviewSection("持仓期间") {
      switch item.record?.result?.excursionCell ?? .pending {
      case .value(let value):
        LabeledContent("最大浮盈", value: TradeLabels.money(value.maxFavorable) + " · " + TradeLabels.percent(value.maxFavorablePct, signed: true))
        LabeledContent("最大浮亏", value: TradeLabels.money(value.maxAdverse) + " · " + TradeLabels.percent(value.maxAdversePct, signed: true))
        termRow("盈亏比", term: "tradeRewardRisk", TradeLabels.ratio(value.rewardRisk))
      case .pending, .unavailable:
        LabeledContent("最大浮盈", value: "—")
        LabeledContent("最大浮亏", value: "—")
        termRow("盈亏比", term: "tradeRewardRisk", "—")
      }
    }
    .monospacedDigit()
    .listRowBackground(t.raised)
    .accessibilityIdentifier("trade.detail.excursion")
  }

  @ViewBuilder private func after(_ item: TradeItem) -> some View {
    ReviewSection("离开后", term: "afterClose") {
      ForEach([("h1", "1 小时"), ("h4", "4 小时"), ("h24", "24 小时")], id: \.0) { key, title in
        let point = item.record?.result?.afterCell(key).value
        LabeledContent(title) {
          if let point {
            Text(TradeLabels.percent(point.changePct, signed: true))
              .foregroundStyle(percentColor(point.changePct, t))
          } else {
            Text("—").foregroundStyle(t.ink3)
          }
        }
      }
      // 标识只挂在三行上：挂在整个 Section 上会盖住节头那颗问号的 `term.afterClose`。
      .accessibilityIdentifier("trade.detail.after")
    }
    .monospacedDigit()
    .listRowBackground(t.raised)
  }

  private func price(_ value: Decimal, _ round: TradeRound) -> String {
    feature.price(NSDecimalNumber(decimal: value).doubleValue, symbol: round.instrument.key)
  }

  /// `LabeledContent(title, value:)` 加一颗术语问号：左边标签后挂 `ReviewTermMark`，右边照旧。
  private func termRow(_ title: String, term: String, _ value: String) -> some View {
    LabeledContent { Text(value) } label: { ReviewTermLabel(title, term: term) }
  }

  private func syncNote(_ item: TradeItem) {
    let server = item.record?.note?.text ?? ""
    // 人正在写的不去冲掉；只有没动过（或刚存上）才跟服务端那份对齐。
    if loadedNote == nil || note == loadedNote { note = server }
    loadedNote = server
  }

  private func save(_ item: TradeItem) {
    let text = note
    Task { if await feature.trades.saveNote(item.id, text: text) { loadedNote = text } }
  }
}

// MARK: - 观点详情里的「对应的交易」

struct TradeLinksSection: View {
  @Bindable var feature: ReviewFeature
  let record: ReviewRecord
  @Environment(\.reviewTheme) private var t
  var body: some View {
    let items = feature.trades(for: record)
    if !items.isEmpty {
      ReviewSection("对应的交易") {
        ForEach(items) { item in
          NavigationLink { TradeRecordView(feature: feature, id: item.id) } label: { TradeRow(item: item, feature: feature) }
        }
      }
      .listRowBackground(t.raised)
      .accessibilityIdentifier("review.detail.trades")
    }
  }
}

// MARK: - 战绩：交易那一面

struct TradeStatisticsList: View {
  @Bindable var feature: ReviewFeature
  @Environment(\.reviewTheme) private var t
  var body: some View {
    let rounds = feature.trades.rounds
    let calendar = feature.calendar
    let s = RoundStats.summarize(rounds)
    List {
      if s.count == 0 {
        if feature.trades.exchange.connected || !rounds.isEmpty {
          Text("暂无平仓的交易").font(ReviewType.body).foregroundStyle(t.ink3).listRowBackground(t.app)
        } else {
          Button { feature.bookOpen = false; feature.trades.onConnect() } label: {
            Text("接入交易所后自动生成").font(ReviewType.body).foregroundStyle(t.ink2)
              .frame(maxWidth: .infinity, minHeight: ReviewControl.hit, alignment: .leading)
          }
          .buttonStyle(.plain).listRowBackground(t.app)
          .accessibilityIdentifier("review.stats.trades.connect")
        }
      } else {
        Section {
          metric("笔数", "\(s.count)")
          metric("胜率", TradeLabels.percent(s.winRate))
          metric("盈亏比", TradeLabels.ratio(s.rewardRisk), term: "rewardRisk")
          metric("每笔期望", s.expectancy.map { TradeLabels.money($0) } ?? "—", term: "expectancy")
          metric("净盈亏", TradeLabels.money(s.netPnl), color: pnlColor(s.netPnl, t))
          metric("费用占毛利", TradeLabels.percent(s.feeShareOfGross), term: "feeShare")
          metric("最长连亏", "\(s.longestLosingStreak) 笔")
          metric("平均持仓", TradeLabels.holding(s.averageHoldingMs))
        }
        .listRowBackground(t.app)
        .accessibilityIdentifier("review.stats.trades.summary")
        group("按品种", Self.symbolRows(rounds))
        group("按方向", RoundStats.byDirection(rounds).map { Row(id: $0.key.rawValue, name: $0.key == .long ? "做多" : "做空", summary: $0.summary) })
        group("按持仓时长", RoundStats.byHolding(rounds).map { Row(id: $0.key.title, name: $0.key.title, summary: $0.summary) })
        group("按开仓时段", RoundStats.bySession(rounds, calendar: calendar).map { Row(id: $0.key.title, name: $0.key.title, summary: $0.summary) })
        group("按周几", RoundStats.byWeekday(rounds, calendar: calendar).map { Row(id: $0.key.title, name: $0.key.title, summary: $0.summary) })
      }
    }
    .listStyle(.plain)
    .scrollContentBackground(.hidden)
    .background(t.app)
    .accessibilityIdentifier("review.stats.trades")
  }
  private func metric(_ title: String, _ value: String, color: Color? = nil, term: String? = nil) -> some View {
    LabeledContent { Text(value).font(ReviewType.bodyEmph).foregroundStyle(color ?? t.ink).monospacedDigit() }
      label: { ReviewTermLabel(title, term: term) }
      .font(ReviewType.body).foregroundStyle(t.ink2)
      .frame(minHeight: ReviewControl.hit)
  }
  /// 一组里的一行。`id` 与给人看的 `name` 分开：「按品种」的 id 是整串代号，
  /// 名字是短名——BTCUSDT 与 BTCUSDC 以前都叫「BTC」又拿它当 id，两行撞 id（审查 R8）。
  struct Row: Equatable {
    var id: String
    var name: String
    var summary: RoundSummary
  }
  static func symbolRows(_ rounds: [TradeRound]) -> [Row] {
    RoundStats.bySymbol(rounds).map { Row(id: $0.key, name: TradeLabels.shortSymbol($0.key), summary: $0.summary) }
  }
  @ViewBuilder private func group(_ title: String, _ rows: [Row]) -> some View {
    if !rows.isEmpty {
      Section {
        ForEach(rows, id: \.id) { row in
          let name = row.name, s = row.summary
          HStack {
            VStack(alignment: .leading, spacing: ReviewSpace.xxs) {
              Text(name).font(ReviewType.body).foregroundStyle(t.ink)
              Text("\(s.count) 笔 · 胜率 \(TradeLabels.percent(s.winRate))").font(ReviewType.caption).foregroundStyle(t.ink3).monospacedDigit()
            }
            Spacer()
            Text(TradeLabels.money(s.netPnl)).font(ReviewType.bodyEmph).monospacedDigit().foregroundStyle(pnlColor(s.netPnl, t))
          }
          .frame(minHeight: ReviewControl.hit)
          .listRowBackground(t.app)
        }
      } header: { ReviewSectionTitle(title) }
    }
  }
}
