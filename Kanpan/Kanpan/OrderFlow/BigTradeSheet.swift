import KanpanCore
import KanpanNetwork
import KanpanPresentation
import SwiftUI
import UIKit

/// 大单与爆仓的用词一律取三端共用的 terms.json（KanpanCore/Terms），这里不写字面文案。
private typealias BT = BigTradeTerm

// 「大单与爆仓」弹层（2026-10-08，照 docs/原型-手机大单与爆仓-2026-10-08.html 05–12）。
//
// 一个功能一个模块：弹层的状态（开没开、停在哪档、十字线看哪根、爆仓账）、纯算的摘要
// （`BigTradeSummary`，四张卡共用这一份）、卡片、挂到主界面的修饰器、分析面板里那一行的实时副文字，
// 全在这一个文件里。数据全来自已有的两条链路：
//   · 大单成交分钟账 `OrderFlowLink.trades`（行情流随订单流帧推来；弹层开着时两颗开关都关着也订）；
//   · 爆仓分钟账 `/liq`（kanpan-api，弹层开着时每 30 秒补一次，现货不取）。
//
// 入口两个：点图上的大单签（打开即整页，已开着只换根），分析面板「主力订单流 › 大单与爆仓」那一行。
// 十字线联动：按住 / 落在图上时弹层改读那一根，十字线收掉后再停 3 秒、淡回本根。

// MARK: - 状态

@MainActor
@Observable
final class BigTradeSheetModel {
  /// 换根的那一下多亮 1.2 秒（「每根」条上的那一格）。
  static let highlightSeconds = 1.2
  /// 十字线收掉后还停在那一根多久。
  static let holdSeconds = 3.0

  var presented = false
  /// 「门槛」那张表开着。
  var editing = false
  /// 十字线此刻停在主图哪一根（开盘时间）。
  private(set) var crossT: Int64?
  /// 十字线收掉后再留 3 秒的那一根。
  private(set) var heldT: Int64?
  /// 刚点过的那一根（签 / 「每根」条），亮 1.2 秒。
  private(set) var highlightT: Int64?
  private(set) var openedAt = Date.distantPast
  /// 爆仓分钟账（按 base 记；换品种就换一本）。
  private(set) var book: LiquidationBook?
  /// 爆仓取不到（行情线路不带订单流目录、服务端出错）：那张卡不出，不挂骨架。
  private(set) var liqUnavailable = false

  @ObservationIgnored private var holdTask: Task<Void, Never>?
  @ObservationIgnored private var highlightTask: Task<Void, Never>?
  @ObservationIgnored private var tapeCache: (flow: BigTradeFlow, tape: BigTradeTape)?

  /// 弹层此刻读哪一根：十字线那根，或刚收掉还在停留的那根；nil = 正在走那根。
  var focusT: Int64? { crossT ?? heldT }

  /// 点签 / 点分析面板那一行。一开就是整页；已经开着只换根。
  func open(at t: Int64?) {
    if !presented {
      openedAt = Date()
      presented = true
    }
    if let t { flash(t) }
  }

  func close() { presented = false; editing = false }

  /// 主图十字线变了（`MainChartView.onCrosshair`）：t = 十字线所在那根的开盘时间，nil = 收掉了 / 不在主图。
  func noteCrosshair(t: Int64?) {
    guard t != crossT else { return }
    if let t {
      holdTask?.cancel(); holdTask = nil
      heldT = nil
      crossT = t
      return
    }
    let last = crossT
    crossT = nil
    heldT = last
    holdTask?.cancel()
    holdTask = Task { [weak self] in
      try? await Task.sleep(for: .seconds(Self.holdSeconds))
      guard !Task.isCancelled, let self else { return }
      withAnimation(UIAccessibility.isReduceMotionEnabled ? nil : .easeInOut(duration: 0.3)) { self.heldT = nil }
    }
  }

  func flash(_ t: Int64) {
    highlightT = t
    highlightTask?.cancel()
    highlightTask = Task { [weak self] in
      try? await Task.sleep(for: .seconds(Self.highlightSeconds))
      guard !Task.isCancelled, let self else { return }
      self.highlightT = nil
    }
  }

  /// 全部分钟的买 / 卖（地板 0），「每根」条按 K 线开盘时间并成根；按成交账的版本缓存。
  func tape(_ flow: BigTradeFlow, nowMs: Int64) -> BigTradeTape {
    if let c = tapeCache, c.flow == flow { return c.tape }
    let tape = flow.tape(nowMs: nowMs, floor: 0)
    tapeCache = (flow, tape)
    return tape
  }

  /// 弹层开着时每 30 秒补一次爆仓账（`.task(id: base)` 跑它，弹层关了 / 换品种就取消）。
  func pollLiquidations(base: String, market: MarketModel) async {
    if book?.base != base { book = LiquidationBook(base: base); liqUnavailable = false }
    while !Task.isCancelled {
      let now = Self.nowMs()
      let from = book?.fetchFrom(nowMs: now) ?? now - LiquidationBook.keepMs
      let page = await market.liquidations(base: base, fromMs: from, toMs: now + 60_000)
      guard !Task.isCancelled, book?.base == base else { return }
      if let page {
        book?.merge(page, nowMs: now)
        liqUnavailable = false
      } else if book?.tracked == nil {
        liqUnavailable = true
      }
      try? await Task.sleep(for: .milliseconds(LiquidationBook.pollMs))
    }
  }

  static func nowMs(_ date: Date = Date()) -> Int64 { Int64(date.timeIntervalSince1970 * 1000) }
}

/// 截图 / UI 测试用：把弹层钉在某个不好现场造的状态上（DEBUG 包里才认）。
enum BigTradeSheetTestState: String {
  case loading, stale, liqEmpty, untracked

  static let current: BigTradeSheetTestState? = {
    #if DEBUG
      ProcessInfo.processInfo.environment["KANPAN_TEST_BIGTRADE_STATE"].flatMap(BigTradeSheetTestState.init(rawValue:))
    #else
      nil
    #endif
  }()
}

extension MarketModel {
  /// 正在走那根的 [开盘, 收盘)。分析面板那一行的副文字用。
  var liveBarSpan: (t0: Int64, t1: Int64)? {
    guard let s = series, s.count > 0 else { return nil }
    let t0 = s.lastTime
    return (t0, t0 + s.interval.stepMs)
  }

  /// 当前品种是不是现货（现货没有爆仓）。
  var isSpotInstrument: Bool { InstrumentID(symbol).market == "spot" }
}

// MARK: - 摘要（纯算，四张卡共用）

struct BigTradeSummary: Equatable {
  struct Column: Equatable { var t: Int64; var buy: Double; var sell: Double }
  struct LadderRow: Equatable {
    var price: Double
    var buy: Double
    var sell: Double
    var now: Bool
    /// 这一行上的挂单墙（买墙在左、卖墙在右）；墙在五档以外时钉在首 / 末行，带上价。
    var bidWall: String?
    var askWall: String?
  }
  struct Liq: Equatable {
    var loading: Bool
    var hour = LiquidationSum()
    var today = LiquidationSum()
    var day = LiquidationSum()
    var timeline: [LiquidationSum] = []
    var timelineStart: Int64 = 0
  }
  enum Freshness: Equatable { case live, stale(Int64), offline }

  static let columnCount = 40
  static let timelineCells = 96
  static let timelineCellMs: Int64 = 15 * 60_000

  var barT: Int64
  var barIndex: Int
  var live: Bool
  var windows: BigTradeDigest.Windows
  var columns: [Column]
  var ladder: [LadderRow]
  var liq: Liq?
  var freshness: Freshness
  var untracked: Bool

  var muted: Bool { freshness != .live }

  // swiftlint:disable:next function_parameter_count
  static func make(flow: BigTradeFlow, tape: BigTradeTape, series: BarSeries, focusT: Int64?, nowMs now: Int64,
                   step: Double?, orders: [BigOrder], book: LiquidationBook?, liqUnavailable: Bool, spot: Bool,
                   linkDown: Bool, marketClosed: Bool, decimals: Int) -> BigTradeSummary? {
    let n = series.count
    guard n > 0 else { return nil }
    let stepMs = series.interval.stepMs
    var i = n - 1
    if let focusT { i = max(0, min(n - 1, series.firstIndex(atOrAfter: focusT + 1) - 1)) }
    let t0 = series.time(at: i)
    let t1 = i + 1 < n ? series.time(at: i + 1) : t0 + stepMs
    let windows = BigTradeDigest.windows(flow, barT0: t0, barT1: t1, nowMs: now)

    // 每根：最近 40 根。
    let start = max(0, n - columnCount)
    let opens = (start..<n).map { series.time(at: $0) }
    let lastEnd = series.time(at: n - 1) + stepMs
    let bars = tape.bars(opens: opens, lastEnd: lastEnd)
    let columns = opens.indices.map { Column(t: opens[$0], buy: bars.buy[$0], sell: bars.sell[$0]) }

    // 价位：现价上下五档、近 2 小时。服务端分钟行记在那一分钟所在 K 线的典型价上。
    var ladder: [LadderRow] = []
    if let step, step > 0, let price = series.close.last, price > 0 {
      let typical: (Int64) -> Double? = { m in
        let k = series.firstIndex(atOrAfter: m + 1) - 1
        guard k >= 0, k < n else { return nil }
        return (series.high[k] + series.low[k] + series.close[k]) / 3
      }
      let levels = BigTradeDigest.ladder(flow, step: step, price: price, levels: 5, nowMs: now, typical: typical)
      if !levels.isEmpty {
        ladder = levels.enumerated().map { k, l in
          LadderRow(price: l.price, buy: l.buyUsd, sell: l.sellUsd, now: k == levels.count / 2)
        }
        let center = (price / step + 1e-9).rounded(.down)
        let mid = levels.count / 2
        func row(_ p: Double) -> (Int, Bool) {
          let r = mid - Int((p / step + 1e-9).rounded(.down) - center)
          return (max(0, min(levels.count - 1, r)), r < 0 || r >= levels.count)
        }
        let walls = BigTradeDigest.nearestWalls(orders, mid: price)
        if let w = walls.bid {
          let (r, out) = row(w.price)
          ladder[r].bidWall = BT.buyWall.text + " " + fmtVol(w.usd) + (out ? " · " + fmtPrice(w.price, decimals: decimals) : "")
        }
        if let w = walls.ask {
          let (r, out) = row(w.price)
          ladder[r].askWall = BT.sellWall.text + " " + fmtVol(w.usd) + (out ? " · " + fmtPrice(w.price, decimals: decimals) : "")
        }
      }
    }

    // 爆仓：现货没有；服务端不跟这只、或取不到，整张卡不出。
    var liq: Liq?
    let test = BigTradeSheetTestState.current
    if !spot {
      if test == .liqEmpty {
        liq = Liq(loading: false, timeline: Array(repeating: LiquidationSum(), count: timelineCells),
                  timelineStart: (now / timelineCellMs - Int64(timelineCells - 1)) * timelineCellMs)
      } else if let book, book.tracked == true {
        let end = now + 60_000
        let lastStart = (now / timelineCellMs) * timelineCellMs
        liq = Liq(loading: false,
                  hour: book.sum(now - BigTradeDigest.hourMs, end),
                  today: book.sum(BigTradeDigest.dayStart8(now), end),
                  day: book.sum(now - BigTradeDigest.dayMs, end),
                  timeline: book.timeline(nowMs: now, cells: timelineCells, cellMs: timelineCellMs),
                  timelineStart: lastStart - Int64(timelineCells - 1) * timelineCellMs)
      } else if book?.tracked == false || liqUnavailable {
        liq = nil
      } else {
        liq = Liq(loading: true)
      }
    }

    var freshness = Freshness.live
    if linkDown {
      freshness = .offline
    } else if test == .stale {
      freshness = .stale(min(flow.lastTradeMs ?? now, now - 45_000))
    } else if let last = flow.lastTradeMs, now - last > 20_000, !marketClosed {
      freshness = .stale(last)
    }

    return BigTradeSummary(barT: t0, barIndex: i, live: i == n - 1, windows: windows, columns: columns,
                           ladder: ladder, liq: liq, freshness: freshness,
                           untracked: flow.tracked == false || test == .untracked)
  }

  /// 净额的写法：「净买入 +3.30M」/「净卖出 −1.2M」。
  static func netText(_ net: Double, signed: Bool) -> String {
    let side = net >= 0 ? BT.netBuy.text : BT.netSell.text
    let sign = signed ? (net >= 0 ? "+" : "−") : ""
    return "\(side) \(sign)\(fmtVol(abs(net)))"
  }

}

// MARK: - 分析面板入口

/// 分析面板「主力订单流」那一节的「大单与爆仓」一行：主界面递进来的开法与「正在走那根」。
struct BigTradeEntry {
  var open: () -> Void
  var liveBar: () -> (t0: Int64, t1: Int64)?
}

/// 那一行右边的实时副文字「本根 净买 +1.2M」。单拎一块：成交账每秒一换，只叫醒这一小块。
struct BigTradeEntryMeta: View {
  let link: OrderFlowLink
  let entry: BigTradeEntry
  @Environment(\.panelTheme) private var t

  var body: some View {
    Text(text).monospacedDigit().font(PanelFont.meta).foregroundStyle(t.ink3).lineLimit(1)
      .accessibilityIdentifier("orderflow.bigTrades.meta")
  }

  private var text: String {
    guard let flow = link.trades, let bar = entry.liveBar() else { return "" }
    let s = flow.sum(bar.t0, bar.t1, nowMs: BigTradeSheetModel.nowMs())
    guard s.total > 0 else { return BT.currentNoBigTrade.text }
    return BT.currentBar.text + " " + BigTradeSummary.netText(s.net, signed: true)
  }
}

// MARK: - 挂到主界面

extension View {
  /// 「大单与爆仓」弹层。`enabled == false`（横屏、复盘、画线）时不出，开着的也收掉。
  func bigTradeSheet(market: MarketModel, store: PrefsStore, proxy: ChartProxy, theme: PanelTheme,
                     scheme: ColorScheme?, enabled: Bool) -> some View {
    modifier(BigTradeSheetModifier(market: market, store: store, proxy: proxy, theme: theme, scheme: scheme,
                                   enabled: enabled))
  }
}

private struct BigTradeSheetModifier: ViewModifier {
  let market: MarketModel
  let store: PrefsStore
  let proxy: ChartProxy
  let theme: PanelTheme
  let scheme: ColorScheme?
  let enabled: Bool

  func body(content: Content) -> some View {
    @Bindable var model = market.orderFlow.sheet
    let shown = enabled && model.presented
    content
      .sheet(isPresented: Binding(get: { shown }, set: { if !$0 { model.close() } })) {
        BigTradeSheet(market: market, store: store, proxy: proxy)
          .environment(\.panelTheme, theme)
          // 一档到底：一开就把每张卡都摆出来，不再半屏 + 上拉。
          .presentationDetents([.large])
          .presentationDragIndicator(.visible)
          .presentationBackground { LiuliBackdrop(material: LiuliMaterial(theme), lobes: true) }
          .preferredColorScheme(scheme)
      }
      .onChange(of: shown, initial: true) { _, open in market.setBigTradeSheet(open: open) }
      .onChange(of: enabled) { _, on in if !on { model.close() } }
  }
}

// MARK: - 弹层

struct BigTradeSheet: View {
  let market: MarketModel
  let store: PrefsStore
  let proxy: ChartProxy
  @Environment(\.panelTheme) private var t
  @Environment(\.accessibilityReduceMotion) private var reduceMotion

  private var model: BigTradeSheetModel { market.orderFlow.sheet }
  private var link: OrderFlowLink { market.orderFlow }
  private var spot: Bool { market.isSpotInstrument }
  private var base: String? { link.currentFacts?.overrideKey }
  private var m: LiuliMaterial { LiuliMaterial(t) }
  private var tz: TZOffset { store.prefs.timeZone.offsetMinutes }

  var body: some View {
    @Bindable var model = model
    VStack(spacing: 0) {
      header
      TimelineView(.periodic(from: .now, by: 1)) { ctx in
        page(nowMs: BigTradeSheetModel.nowMs(ctx.date), now: ctx.date)
      }
    }
    .accessibilityElement(children: .contain)
    .accessibilityIdentifier("bigtrade.sheet")
    .task(id: spot || BigTradeSheetTestState.current == .liqEmpty ? nil : base) {
      guard let base, !spot, BigTradeSheetTestState.current != .liqEmpty else { return }
      await model.pollLiquidations(base: base, market: market)
    }
    .sheet(isPresented: $model.editing) {
      OrderFlowEditor(store: store, link: link, symbol: market.symbol)
        .environment(\.panelTheme, t)
        .preferredColorScheme(store.prefs.theme.forced)
    }
  }

  // MARK: 头

  /// 副标题只写品种（现货加「现货」）。用户 2026-10-08：标题没必要写交易所——他关心的是品种和数据，
  /// 哪几家合在一起权重不大；分家的信息留在读数卡与爆仓「最大一笔」里。
  private var subtitle: String {
    (base ?? SymbolInfo.placeholder(symbol: market.symbol).base) + (spot ? " " + BT.spot.text : "")
  }

  private var header: some View {
    HStack(spacing: Space.s) {
      Button { model.close() } label: {
        Image(systemName: "chevron.left").font(TypeScale.title).foregroundStyle(t.amber)
          .frame(width: Hit.min, height: Hit.min)
          .contentShape(Rectangle())
      }
      .buttonStyle(.plain)
      .padding(.leading, -Space.s - Space.xs)
      .accessibilityLabel("返回")
      .accessibilityIdentifier("bigtrade.back")
      VStack(alignment: .leading, spacing: 5) {
        Text(BT.title.text).font(.scaled(20, .bold, relativeTo: .title3)).foregroundStyle(t.ink)
          .accessibilityAddTraits(.isHeader)
        Text(subtitle).lineLimit(1)
          .font(TypeScale.captionEmph).foregroundStyle(t.ink3)
          .accessibilityIdentifier("bigtrade.subtitle")
      }
      Spacer(minLength: Space.s)
      Button { Haptics.tap(); model.editing = true } label: {
        Text(BT.threshold.text).font(TypeScale.controlOn).foregroundStyle(t.amber)
          .padding(.horizontal, Space.m).padding(.vertical, 7)
          .background(Capsule().fill(m.pane))
          .overlay(Capsule().strokeBorder(m.cardEdge, lineWidth: LiuliMaterial.hairline))
          .frame(minHeight: Hit.min)
          .contentShape(Rectangle())
      }
      .buttonStyle(.plain)
      .accessibilityIdentifier("bigtrade.threshold")
    }
    .padding(.horizontal, Space.l)
    .padding(.top, Space.l + Space.xs)
    .padding(.bottom, Space.xs)
  }

  // MARK: 页

  @ViewBuilder private func page(nowMs: Int64, now: Date) -> some View {
    let summary = makeSummary(nowMs: nowMs, now: now)
    ScrollView {
      VStack(spacing: 10) {
        if let summary {
          hero(summary)
          if let liq = summary.liq { liqCard(liq, muted: summary.muted) }
          columnsCard(summary)
          ladderCard(summary)
          if let liq = summary.liq, !liq.loading { liq24Card(liq, summary: summary) }
          thresholdRow
        } else {
          skeleton
        }
      }
      .padding(.horizontal, Space.l)
      .padding(.top, Space.xs)
      .padding(.bottom, Space.xxl)
    }
    .scrollBounceBehavior(.basedOnSize)
  }


  private func makeSummary(nowMs: Int64, now: Date) -> BigTradeSummary? {
    if BigTradeSheetTestState.current == .loading { return nil }
    guard let series = market.series, series.count > 0 else { return nil }
    let flow: BigTradeFlow
    if let f = link.trades, InstrumentID.canonical(f.symbol) == InstrumentID.canonical(market.symbol) {
      flow = f
    } else if now.timeIntervalSince(model.openedAt) < 1 {
      return nil
    } else {
      flow = BigTradeFlow(symbol: market.symbol)
    }
    let snap = link.snapshot.flatMap {
      InstrumentID.canonical($0.symbol) == InstrumentID.canonical(market.symbol) ? $0 : nil
    }
    return BigTradeSummary.make(
      flow: flow, tape: model.tape(flow, nowMs: nowMs), series: series, focusT: model.focusT, nowMs: nowMs,
      step: snap?.thresholds.step ?? link.effectiveThresholds(symbol: market.symbol)?.step,
      orders: snap?.orders ?? [], book: model.book, liqUnavailable: model.liqUnavailable, spot: spot,
      linkDown: market.linkDown, marketClosed: market.ticker?.marketClosed ?? false,
      decimals: market.info.priceDecimals)
  }

  private func time(_ ms: Int64, step: Int64? = nil) -> String {
    fmtTick(ms: Double(ms), step: Double(step ?? market.interval.stepMs), offsetMinutes: tz)
  }

  // MARK: 卡片外壳

  private func card<C: View>(thin: Bool = false, id: String, @ViewBuilder _ body: () -> C) -> some View {
    VStack(alignment: .leading, spacing: 0) { body() }
      .padding(.vertical, 14)
      .padding(.horizontal, Space.l)
      .frame(maxWidth: .infinity, alignment: .leading)
      .liuliCard(radius: 20, thin: thin)
      .accessibilityElement(children: .contain)
      .accessibilityIdentifier(id)
  }

  private func h5(_ title: String, right: String?, live: Bool = false, titleID: String? = nil,
                  rightID: String? = nil) -> some View {
    HStack(spacing: Space.s) {
      if live { LiveDot(color: t.up) }
      Text(title).font(.scaled(12, .semibold, relativeTo: .caption))
        .accessibilityIdentifier(titleID ?? "")
      Spacer(minLength: Space.s)
      if let right {
        Text(right).font(TypeScale.captionEmph).lineLimit(1).accessibilityIdentifier(rightID ?? "")
      }
    }
    .foregroundStyle(t.ink3)
    .padding(.bottom, 10)
  }

  private func amount(_ x: Double, color: Color, size: CGFloat, weight: Font.Weight = .semibold) -> some View {
    Text(fmtVol(x))
      .font(.scaled(size, weight, relativeTo: size > 15 ? .title2 : .caption2))
      .monospacedDigit()
      .foregroundStyle(color)
      .contentTransition(.numericText(value: x))
      .animation(reduceMotion ? nil : .easeOut(duration: 0.2), value: x)
  }

  // MARK: 本根

  private func hero(_ s: BigTradeSummary) -> some View {
    let bar = s.windows.bar
    let focused = model.focusT != nil
    let title = focused ? time(s.barT) : BT.currentBar.text
    let right: String = {
      switch s.freshness {
      case .stale(let last): return BT.staleSince.fill(["t": time(last, step: 60_000)])
      default:
        return market.interval.display
      }
    }()
    let up = s.muted ? t.ink3 : t.up, down = s.muted ? t.ink3 : t.down
    return card(id: "bigtrade.hero") {
      h5(title, right: right, live: !focused && s.live && !s.muted, titleID: "bigtrade.hero.title",
         rightID: "bigtrade.hero.right")
      if bar.total <= 0 {
        VStack(spacing: 6) {
          Text(BT.noBigTrade.text).font(TypeScale.bodyEmph).foregroundStyle(t.ink)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, Space.xs)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("bigtrade.hero.empty")
      } else {
        HStack(alignment: .firstTextBaseline) {
          HStack(alignment: .firstTextBaseline, spacing: 5) {
            amount(bar.buyUsd, color: up, size: 22)
            if let c = bar.buyCount { Text(BT.buyCount.fill(["n": "\(c)"])).font(TypeScale.caption2Emph).foregroundStyle(t.ink3) }
          }
          Spacer(minLength: Space.s)
          HStack(alignment: .firstTextBaseline, spacing: 5) {
            amount(bar.sellUsd, color: down, size: 22)
            if let c = bar.sellCount { Text(BT.sellCount.fill(["n": "\(c)"])).font(TypeScale.caption2Emph).foregroundStyle(t.ink3) }
          }
        }
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("bigtrade.hero.amounts")
        VersusBar(buy: bar.buyUsd, sell: bar.sellUsd, height: 22, muted: s.muted,
                  net: BigTradeSummary.netText(bar.net, signed: true), netColor: s.muted ? t.ink3 : (bar.net >= 0 ? t.up : t.down))
          .padding(.top, 10).padding(.bottom, 6)
      }
      Grid(alignment: .leading, horizontalSpacing: 10, verticalSpacing: 6) {
        windowRow(BT.hour.text, s.windows.hour, muted: s.muted)
        windowRow(BT.today.text, s.windows.today, muted: s.muted)
      }
      .padding(.top, bar.total <= 0 ? 6 : 4)
      if s.untracked {
        Text(BT.untracked.text).font(TypeScale.caption).foregroundStyle(t.ink3)
          .frame(maxWidth: .infinity)
          .padding(.top, 10)
          .accessibilityIdentifier("bigtrade.untracked")
      }
    }
  }

  private func windowRow(_ label: String, _ w: BigTradeSum, muted: Bool) -> some View {
    GridRow {
      Text(label).font(.scaled(12, .semibold, relativeTo: .caption)).foregroundStyle(t.ink2)
        .frame(width: 52, alignment: .leading)
      VStack(spacing: 4) {
        VersusBar(buy: w.buyUsd, sell: w.sellUsd, height: 10, muted: muted)
        HStack {
          amount(w.buyUsd, color: muted ? t.ink3 : t.ink, size: 11)
          Spacer(minLength: Space.xs)
          Text(BigTradeSummary.netText(w.net, signed: false)).font(TypeScale.caption2).monospacedDigit()
            .foregroundStyle(t.ink3)
          Spacer(minLength: Space.xs)
          amount(w.sellUsd, color: muted ? t.ink3 : t.ink, size: 11)
        }
      }
    }
    .accessibilityElement(children: .combine)
  }

  // MARK: 爆仓（薄卡）

  @ViewBuilder private func liqCard(_ liq: BigTradeSummary.Liq, muted: Bool) -> some View {
    card(thin: true, id: "bigtrade.liq") {
      h5(BT.liq.text, right: BT.hour.text)
      if liq.loading {
        VStack(alignment: .leading, spacing: 10) {
          SkeletonBlock(height: 10, fill: m.well, radius: 5)
          SkeletonBlock(width: 180, height: 14, fill: m.well)
        }
        .skeletonPulse()
      } else if liq.today.total <= 0 {
        VStack(spacing: 6) {
          Text(BT.noLiqToday.text).font(TypeScale.bodyEmph).foregroundStyle(t.ink)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, Space.xxs)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("bigtrade.liq.empty")
      } else {
        let up = muted ? t.ink3 : t.up, down = muted ? t.ink3 : t.down
        VersusBar(buy: liq.hour.shortUsd, sell: liq.hour.longUsd, height: 10, muted: muted)
          .padding(.top, 2).padding(.bottom, 4)
        HStack(spacing: Space.xs) {
          Text(BT.shortLiq.text + " " + fmtVol(liq.hour.shortUsd)).font(TypeScale.caption2Emph).foregroundStyle(up)
          Spacer(minLength: Space.xs)
          Text(BT.longLiq.text + " " + fmtVol(liq.hour.longUsd)).font(TypeScale.caption2Emph).foregroundStyle(down)
        }
        .monospacedDigit()
        .accessibilityElement(children: .combine)
        let maxLine = liq.today.max.map { r in
          Text(BT.todayMaxLiq.text + " ").foregroundStyle(t.ink3)
            + Text((r.maxIsLong ? BT.long : BT.short).text + " " + fmtVol(r.maxUsd)).fontWeight(.semibold)
              .foregroundStyle(muted ? t.ink3 : (r.maxIsLong ? t.down : t.up))
            + Text(" @ " + fmtPrice(r.maxPrice, decimals: market.info.priceDecimals) + " · "
              + time(r.minuteMs, step: 60_000)).foregroundStyle(t.ink3)
        }
        let dayLine = Text(BT.day.text + " " + BT.long.text + " ").foregroundStyle(t.ink3)
          + Text(fmtVol(liq.day.longUsd)).fontWeight(.semibold).foregroundStyle(muted ? t.ink3 : t.ink)
          + Text(" · " + BT.short.text + " ").foregroundStyle(t.ink3)
          + Text(fmtVol(liq.day.shortUsd)).fontWeight(.semibold).foregroundStyle(muted ? t.ink3 : t.ink)
        ViewThatFits(in: .horizontal) {
          HStack { maxLine; Spacer(minLength: Space.s); dayLine }
          VStack(alignment: .leading, spacing: Space.xs) { maxLine; dayLine }
        }
        .font(TypeScale.caption2).monospacedDigit().lineLimit(1)
        .padding(.top, Space.s)
      }
    }
  }

  // MARK: 每根

  private func columnsCard(_ s: BigTradeSummary) -> some View {
    let selected = s.columns.firstIndex { $0.t == s.barT && model.focusT != nil }
      ?? model.highlightT.flatMap { h in s.columns.firstIndex { $0.t == h } }
    let first = s.columns.first?.t, last = s.columns.last?.t
    let midT = s.columns.isEmpty ? nil : s.columns[s.columns.count / 2].t
    return card(id: "bigtrade.columns") {
      h5(BT.perBar.text, right: BT.recentBars.fill(["n": "\(BigTradeSummary.columnCount)"]))
      ColumnsChart(columns: s.columns, selected: selected, muted: s.muted, up: t.up, down: t.down,
                   accent: m.accent, axis: t.ink3, live: s.columns.last.map { _ in !s.muted } ?? false,
                   reduceMotion: reduceMotion) { k in
        let c = s.columns[k]
        Haptics.tap()
        model.flash(c.t)
        proxy.placeCrosshair(atTime: c.t)
      }
      .frame(height: 96)
      HStack {
        Text(first.map { time($0) } ?? "")
        Spacer()
        Text(midT.map { time($0) } ?? "")
        Spacer()
        Text(last.map { time($0) } ?? "")
      }
      .font(TypeScale.caption2).monospacedDigit().foregroundStyle(t.ink3)
      .padding(.top, Space.s)
    }
  }

  // MARK: 价位

  private func ladderCard(_ s: BigTradeSummary) -> some View {
    let peak = max(s.ladder.map { max($0.buy, $0.sell) }.max() ?? 0, 1)
    let decimals = market.info.priceDecimals
    return card(id: "bigtrade.ladder") {
      h5(BT.levels.text, right: BT.levelsRange.fill(["h": "\(BigTradeDigest.ladderWindowMs / 3_600_000)"]))
      if s.ladder.isEmpty {
        Text("—").font(TypeScale.footnote).foregroundStyle(t.ink3).frame(maxWidth: .infinity)
      } else {
        Grid(horizontalSpacing: Space.s, verticalSpacing: 5) {
          ForEach(Array(s.ladder.enumerated()), id: \.offset) { _, r in
            GridRow {
              LadderSide(value: r.buy, peak: peak, leading: false, color: t.up, muted: s.muted, wall: r.bidWall,
                         wallColor: t.candleUp, ink3: t.ink3)
              Text(fmtPrice(r.price, decimals: decimals))
                .font(.scaled(11, r.now ? .bold : .medium, relativeTo: .caption2)).monospacedDigit()
                .foregroundStyle(r.now ? m.accent : t.ink2)
                .lineLimit(1).minimumScaleFactor(0.8)
                .frame(width: 64)
                .padding(.vertical, Space.xxs)
                .background {
                  if r.now { RoundedRectangle(cornerRadius: 7, style: .continuous).fill(m.accent.opacity(0.14)) }
                }
              LadderSide(value: r.sell, peak: peak, leading: true, color: t.down, muted: s.muted, wall: r.askWall,
                         wallColor: t.candleDown, ink3: t.ink3)
            }
          }
        }
      }
    }
  }

  // MARK: 爆仓 24 小时

  private func liq24Card(_ liq: BigTradeSummary.Liq, summary s: BigTradeSummary) -> some View {
    let focusCell: Int? = model.focusT.flatMap { f in
      let k = Int((f - liq.timelineStart) / BigTradeSummary.timelineCellMs)
      return f >= liq.timelineStart && k < liq.timeline.count ? k : nil
    }
    return card(id: "bigtrade.liq24") {
      h5(BT.liq.text, right: BT.day.text)
      LiqTimeline(cells: liq.timeline, focus: focusCell, up: t.up, down: t.down, accent: m.accent, axis: t.ink3,
                  muted: s.muted)
        .frame(height: 64)
      HStack {
        Text(BT.yesterday.text + " " + time(liq.timelineStart, step: 60_000)).foregroundStyle(t.ink3)
        Spacer(minLength: Space.xs)
        (Text(BT.long.text + " ").foregroundStyle(t.ink3)
          + Text(fmtVol(liq.day.longUsd)).fontWeight(.semibold).foregroundStyle(s.muted ? t.ink3 : t.down)
          + Text(" · " + BT.short.text + " ").foregroundStyle(t.ink3)
          + Text(fmtVol(liq.day.shortUsd)).fontWeight(.semibold).foregroundStyle(s.muted ? t.ink3 : t.up))
        Spacer(minLength: Space.xs)
        Text(BT.now.text).foregroundStyle(t.ink3)
      }
      .font(TypeScale.caption2).monospacedDigit().lineLimit(1)
      .padding(.top, Space.s)
      if let r = liq.today.max { liqMax(r, muted: s.muted) }
    }
  }

  private func liqMax(_ r: LiquidationRow, muted: Bool) -> some View {
    let color = muted ? t.ink3 : (r.maxIsLong ? t.down : t.up)
    let venue = OrderFlowBase.exchanges[r.maxExchange.key] ?? r.maxExchange.key
    return HStack(spacing: Space.m) {
      Text((r.maxIsLong ? BT.longMark : BT.shortMark).text).font(.scaled(13, .bold, relativeTo: .footnote)).foregroundStyle(.white)
        .frame(width: 34, height: 34)
        .background(Circle().fill(muted ? t.ink3 : (r.maxIsLong ? t.candleDown : t.candleUp)))
      VStack(alignment: .leading, spacing: Space.xxs) {
        Text(BT.todayMaxLiq.text + " · " + (r.maxIsLong ? BT.longLiq : BT.shortLiq).text)
          .font(.scaled(13, .semibold, relativeTo: .footnote)).foregroundStyle(t.ink)
        Text(time(r.minuteMs, step: 60_000) + " · " + fmtPrice(r.maxPrice, decimals: market.info.priceDecimals)
          + " · " + venue)
          .font(TypeScale.caption2Emph).monospacedDigit().foregroundStyle(t.ink3)
      }
      Spacer(minLength: Space.s)
      Text(fmtVol(r.maxUsd)).font(.scaled(17, .semibold, relativeTo: .body)).monospacedDigit().foregroundStyle(color)
    }
    .padding(.vertical, 10).padding(.horizontal, Space.m)
    .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(m.well))
    .padding(.top, 10)
    .accessibilityElement(children: .combine)
    .accessibilityIdentifier("bigtrade.liqmax")
  }

  // MARK: 门槛

  private var thresholdText: String {
    guard let th = link.effectiveThresholds(symbol: market.symbol) else { return "" }
    let order: [OrderFlowProduct] = [.usdtPerp, .spot, .coinPerp, .delivery]
    return order.compactMap { p in th[p].map { p.shortLabel + " " + OrderFlowEditor.compact($0) } }
      .prefix(2).joined(separator: " · ")
  }

  private var thresholdRow: some View {
    Button { Haptics.tap(); model.editing = true } label: {
      HStack(spacing: 10) {
        Text(BT.threshold.text).font(.scaled(14, .medium, relativeTo: .subheadline)).foregroundStyle(t.ink2)
        Text(thresholdText).font(.scaled(14, relativeTo: .subheadline)).monospacedDigit().foregroundStyle(t.ink)
          .lineLimit(1)
        Spacer(minLength: Space.s)
        Text("›").font(TypeScale.controlOn).foregroundStyle(t.amber)
      }
      .padding(.vertical, Space.xs)
      .frame(minHeight: Hit.min - 2 * Space.s)
      .padding(.vertical, Space.s)
      .padding(.horizontal, Space.l)
      .frame(maxWidth: .infinity)
      .liuliCard(radius: 20, thin: true)
      .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
    .accessibilityIdentifier("bigtrade.thresholdRow")
  }

  // MARK: 第一次打开

  private var skeleton: some View {
    VStack(spacing: 10) {
      card(id: "bigtrade.skeleton") {
        h5(BT.currentBar.text, right: nil)
        HStack {
          SkeletonBlock(width: 88, height: 22, fill: m.well, radius: 6)
          Spacer()
          SkeletonBlock(width: 88, height: 22, fill: m.well, radius: 6)
        }
        SkeletonBlock(height: 22, fill: m.well, radius: 11).padding(.top, Space.m)
        VStack(spacing: Space.m) {
          SkeletonBlock(height: 10, fill: m.well, radius: 5)
          SkeletonBlock(height: 10, fill: m.well, radius: 5)
        }
        .padding(.leading, 62)
        .padding(.top, Space.m)
      }
      if !spot {
        card(thin: true, id: "bigtrade.liq.skeleton") {
          h5(BT.liq.text, right: nil)
          SkeletonBlock(height: 10, fill: m.well, radius: 5).padding(.bottom, 10)
          SkeletonBlock(width: 180, height: 14, fill: m.well)
        }
      }
    }
    .skeletonPulse()
  }
}

// MARK: - 小件

private extension PanelTheme {
  /// 图上那支涨跌色（条、墙、圆片的底）；文字用 `up` / `down`。
  var candleUp: Color { Color(hex: chart.up) }
  var candleDown: Color { Color(hex: chart.down) }
}

/// 「本根」前那颗呼吸的点。
private struct LiveDot: View {
  let color: Color
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @State private var low = false
  var body: some View {
    Circle().fill(color).frame(width: 6, height: 6)
      .opacity(low && !reduceMotion ? 0.35 : 1)
      .onAppear {
        guard !reduceMotion else { return }
        withAnimation(.easeInOut(duration: 0.8).repeatForever(autoreverses: true)) { low = true }
      }
      .accessibilityHidden(true)
  }
}

/// 买从左、卖从右的对撞条；交汇点就是净方向。大条（22）上骑一颗净额药丸。
private struct VersusBar: View {
  var buy: Double
  var sell: Double
  var height: CGFloat
  var muted: Bool
  var net: String?
  var netColor: Color = .primary
  @Environment(\.panelTheme) private var t
  @Environment(\.accessibilityReduceMotion) private var reduceMotion

  var body: some View {
    let total = buy + sell
    let share = total > 0 ? buy / total : 0.5
    let big = height > 12
    let r = height / 2, inner: CGFloat = big ? 2 : r
    let gap: CGFloat = big ? 2 : 1
    let m = LiuliMaterial(t)
    GeometryReader { g in
      let w = g.size.width
      let bw = sell <= 0 ? w : max(0, CGFloat(share) * w - gap)
      let sw = buy <= 0 ? w : max(0, CGFloat(1 - share) * w - gap)
      ZStack(alignment: .leading) {
        Capsule().fill(m.well)
        if total > 0 {
          Group {
            if buy > 0 {
              UnevenRoundedRectangle(topLeadingRadius: r, bottomLeadingRadius: r,
                                     bottomTrailingRadius: sell > 0 ? inner : r, topTrailingRadius: sell > 0 ? inner : r,
                                     style: .continuous)
                .fill(LinearGradient(colors: [t.candleUp.opacity(0.7), t.candleUp], startPoint: .leading, endPoint: .trailing))
                .frame(width: bw)
            }
            if sell > 0 {
              UnevenRoundedRectangle(topLeadingRadius: buy > 0 ? inner : r, bottomLeadingRadius: buy > 0 ? inner : r,
                                     bottomTrailingRadius: r, topTrailingRadius: r, style: .continuous)
                .fill(LinearGradient(colors: [t.candleDown, t.candleDown.opacity(0.7)], startPoint: .leading, endPoint: .trailing))
                .frame(width: sw)
                .offset(x: w - sw)
            }
          }
          .saturation(muted ? 0.15 : 1)
          .opacity(muted ? 0.6 : 1)
        }
        if let net, total > 0 {
          Text(net).font(.scaled(11, .semibold, relativeTo: .caption2)).monospacedDigit()
            .foregroundStyle(netColor)
            .padding(.horizontal, Space.s).padding(.vertical, 5)
            .background(Capsule().fill(t.raised).shadow(color: .black.opacity(0.14), radius: 2, y: 1))
            .overlay(Capsule().strokeBorder(m.cardEdge, lineWidth: 0.5))
            .fixedSize()
            .position(x: min(max(CGFloat(share) * w, 48), w - 48), y: height / 2)
            .accessibilityIdentifier("bigtrade.hero.net")
        }
      }
      .animation(reduceMotion ? nil : .easeOut(duration: 0.24), value: share)
    }
    .frame(height: height)
  }
}

/// 价位梯的一侧：买在左（条贴着价格列往左长）、卖在右。金额字写在条外；墙用药丸压在外沿。
private struct LadderSide: View {
  var value: Double
  var peak: Double
  /// true = 条从左沿起（卖那一侧）。
  var leading: Bool
  var color: Color
  var muted: Bool
  var wall: String?
  var wallColor: Color
  var ink3: Color

  var body: some View {
    GeometryReader { g in
      let w = value > 0 ? max(4, CGFloat(value / peak) * g.size.width * 0.62) : 0
      ZStack(alignment: leading ? .leading : .trailing) {
        Color.clear
        if w > 0 {
          UnevenRoundedRectangle(topLeadingRadius: leading ? 2 : 6, bottomLeadingRadius: leading ? 2 : 6,
                                 bottomTrailingRadius: leading ? 6 : 2, topTrailingRadius: leading ? 6 : 2,
                                 style: .continuous)
            .fill(color.opacity(0.78))
            .frame(width: w, height: 12)
            .saturation(muted ? 0.15 : 1).opacity(muted ? 0.6 : 1)
        }
        if wall == nil, value / peak > 0.06 {
          Text(fmtVol(value)).font(.scaled(11, relativeTo: .caption2)).monospacedDigit().foregroundStyle(ink3)
            .fixedSize()
            .offset(x: leading ? w + 5 : -(w + 5))
        }
        if let wall {
          Text(wall).font(.scaled(11, .semibold, relativeTo: .caption2)).monospacedDigit().foregroundStyle(.white)
            .padding(.horizontal, 6).padding(.vertical, 3)
            .background(Capsule().fill(muted ? ink3 : wallColor))
            .fixedSize()
            .frame(maxWidth: .infinity, alignment: leading ? .trailing : .leading)
            .accessibilityIdentifier("bigtrade.wall")
        }
      }
    }
    .frame(height: 12)
  }
}

/// 「每根」：近 40 根的买（上）/ 卖（下）对撞柱。点一根把十字线落过去。
private struct ColumnsChart: View {
  var columns: [BigTradeSummary.Column]
  var selected: Int?
  var muted: Bool
  var up: Color
  var down: Color
  var accent: Color
  var axis: Color
  var live: Bool
  var reduceMotion: Bool
  var onTap: (Int) -> Void
  @State private var dim = false

  private static let slots = BigTradeSummary.columnCount

  var body: some View {
    GeometryReader { g in
      let slot = g.size.width / CGFloat(Self.slots)
      let offset = Self.slots - columns.count
      Canvas { ctx, size in
        let mid = size.height / 2
        let bw = max(2, slot - 1)
        var line = Path()
        line.move(to: CGPoint(x: 0, y: mid)); line.addLine(to: CGPoint(x: size.width, y: mid))
        ctx.stroke(line, with: .color(axis.opacity(0.6)), lineWidth: 0.5)
        let peak = max(columns.map { max($0.buy, $0.sell) }.max() ?? 0, 1)
        for (k, c) in columns.enumerated() {
          let x = CGFloat(offset + k) * slot
          let on = k == selected
          let hb = CGFloat(c.buy / peak) * (mid - 4), hs = CGFloat(c.sell / peak) * (mid - 4)
          let alpha = on ? 1 : 0.75
          if hb > 0 {
            ctx.fill(Path(roundedRect: CGRect(x: x, y: mid - hb, width: bw, height: hb), cornerRadius: min(1.5, hb / 2)),
                     with: .color(muted ? axis : up.opacity(alpha)))
          }
          if hs > 0 {
            ctx.fill(Path(roundedRect: CGRect(x: x, y: mid, width: bw, height: hs), cornerRadius: min(1.5, hs / 2)),
                     with: .color(muted ? axis : down.opacity(alpha)))
          }
          if on {
            ctx.stroke(Path(roundedRect: CGRect(x: x - 2, y: 1, width: bw + 4, height: size.height - 2), cornerRadius: 4),
                       with: .color(accent), lineWidth: 1.2)
          }
        }
      }
      .overlay(alignment: .topLeading) {
        if live, !columns.isEmpty {
          Circle().fill(accent).frame(width: 5, height: 5)
            .opacity(dim && !reduceMotion ? 0.2 : 1)
            .offset(x: CGFloat(Self.slots - 1) * slot + max(2, slot - 1) / 2 - 2.5, y: 1.5)
            .onAppear {
              guard !reduceMotion else { return }
              withAnimation(.easeInOut(duration: 0.8).repeatForever(autoreverses: true)) { dim = true }
            }
        }
      }
      .contentShape(Rectangle())
      .gesture(SpatialTapGesture().onEnded { v in
        let k = Int(v.location.x / slot) - offset
        if columns.indices.contains(k) { onTap(k) }
      })
    }
    .accessibilityElement()
    .accessibilityLabel(BT.barsA11y.fill(["n": "\(columns.count)"]))
    .accessibilityAdjustableAction { dir in
      guard !columns.isEmpty else { return }
      let cur = selected ?? columns.count - 1
      let next = dir == .increment ? min(columns.count - 1, cur + 1) : max(0, cur - 1)
      onTap(next)
    }
    .accessibilityIdentifier("bigtrade.columns.chart")
  }
}

/// 24 小时爆仓：96 格，空爆（上）/ 多爆（下）。
private struct LiqTimeline: View {
  var cells: [LiquidationSum]
  var focus: Int?
  var up: Color
  var down: Color
  var accent: Color
  var axis: Color
  var muted: Bool

  var body: some View {
    Canvas { ctx, size in
      guard !cells.isEmpty else { return }
      let mid = size.height / 2
      let slot = size.width / CGFloat(cells.count)
      let bw = max(1, slot * 0.7)
      var line = Path()
      line.move(to: CGPoint(x: 0, y: mid)); line.addLine(to: CGPoint(x: size.width, y: mid))
      ctx.stroke(line, with: .color(axis.opacity(0.6)), lineWidth: 0.5)
      let peak = max(cells.map { max($0.longUsd, $0.shortUsd) }.max() ?? 0, 1)
      for (i, c) in cells.enumerated() {
        let x = CGFloat(i) * slot
        let hu = CGFloat(c.shortUsd / peak) * (mid - 2), hd = CGFloat(c.longUsd / peak) * (mid - 2)
        if hu > 0 { ctx.fill(Path(CGRect(x: x, y: mid - hu, width: bw, height: hu)), with: .color((muted ? axis : up).opacity(0.8))) }
        if hd > 0 { ctx.fill(Path(CGRect(x: x, y: mid, width: bw, height: hd)), with: .color((muted ? axis : down).opacity(0.8))) }
      }
      if let focus {
        let x = CGFloat(focus) * slot
        ctx.stroke(Path(roundedRect: CGRect(x: x - 1, y: 2, width: bw + 2, height: size.height - 4), cornerRadius: 2),
                   with: .color(accent), lineWidth: 1)
      }
    }
    .accessibilityElement()
    .accessibilityLabel(BT.liqDayA11y.text)
    .accessibilityIdentifier("bigtrade.liq24.chart")
  }
}
