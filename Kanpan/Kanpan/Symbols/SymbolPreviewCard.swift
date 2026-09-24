import Observation
import SwiftUI
import KanpanCore
import KanpanData
import KanpanNetwork

/// 长按一行品种弹出来的那张小卡：徽章 · 名字 · 最新价 · 涨跌药丸 · 一段 K 线 · 几格数。
///
/// 品种详情全 app 只剩这一种形态（审查 U9）：自选页原来还有一套行内展开的详情，
/// 和这张卡摆的是同一批数、两种排法。展开那套收掉了，它独有的几格搬到了这儿——
/// 1 小时 / 4 小时涨跌（只有自选页有逐分钟的走势，所以只有它传 `recentChange`）、
/// 24 小时高 / 低；它的「移到分类」「打开」本来就在长按菜单里。
///
/// 它回答的是「这东西现在什么样」——不用切页就看一眼，松手就没了。所以它只摆
/// 已经有的事实，不做任何交互（要动手的都在旁边那份菜单里）。
///
/// 数据一律走现成的路：价和涨跌来自列表本来就订着的报价，持仓量和供应量走
/// 顶栏那四格同一个 `MarketStatsClient`（它自己带缓存），K 线与单品种费率由数据层的
/// `SymbolPreviewService` 取（按当前线路、走共享限流器，审查 18a），这里只按品种记着。
/// 费率读顶栏同一本 `FundingBook`（全市场整表 + 图上 `markPrice` 流记下的那口），
/// 5 分钟内的都算数；簿里没有才问单品种费率，和 K 线并发发出，问到了也记回簿里。
@MainActor @Observable
final class SymbolPreviewStore {
  /// 预览卡要的那两个后端数：持仓量（美元名义）和供应量（算市值）。
  struct Stats: Equatable {
    var openInterestValue: Double?
    var totalSupply: Double?
  }

  /// 卡上那段 K 线：1 小时 × 60 根（取数口径在 `SymbolPreviewService`）。
  static let interval = SymbolPreviewService.interval
  static let barCount = SymbolPreviewService.barCount
  /// 最多记多少个品种的 K 线。翻一页自选也就几十行，记 24 个够用，多了白占内存。
  static let capacity = 24

  /// 费率的保鲜期。资金费率几小时才结算一次，5 分钟内的那口足够代表「现在」，
  /// 又不至于让翻一页自选变成几十次往返。
  static let fundingMaxAge: TimeInterval = 5 * 60

  private(set) var bars: [String: [Bar]] = [:]
  private(set) var stats: [String: Stats] = [:]

  /// 一出生就是这台设备选的线路：从前是「直连 + 空网关表」，选了网关的人长按一行，
  /// K 线和费率照样直连交易所，持仓量和供应量干脆没得问（审查 14）。
  @ObservationIgnored private var resolver = RouteResolver.current
  @ObservationIgnored private var jobs: [String: Task<Void, Never>] = [:]
  /// 最近用过的在后面。满了从前面扔。
  @ObservationIgnored private var recent: [String] = []

  /// 换线路：手上这批数是上一条路取的，整批作废。
  func configure(route next: RouteResolver) {
    guard next.route != resolver.route else { return }
    resolver = next
    for job in jobs.values { job.cancel() }
    jobs.removeAll()
    bars.removeAll()
    stats.removeAll()
    recent.removeAll()
  }

  /// 正在看的那张图捎回来的费率（`markPrice@1s`）。它比 REST 那口还新，
  /// 直接覆盖缓存，省掉这个品种的一次往返。
  func note(funding rate: Double?, for symbol: String) {
    FundingBook.shared.note(rate: rate, for: symbol, upstream: upstream(of: symbol), live: false)
  }

  /// 这只在当前线路上由哪条上游供数：费率簿按它分开记，不混源。
  private func upstream(of symbol: String) -> String {
    resolver.provider(forSymbol: InstrumentID.canonical(symbol)).capabilities.upstream
  }

  func bars(for symbol: String) -> [Bar] { bars[InstrumentID.canonical(symbol)] ?? [] }
  func stats(for symbol: String) -> Stats? { stats[InstrumentID.canonical(symbol)] }
  func funding(for symbol: String) -> Double? {
    FundingBook.shared.entry(for: symbol, upstream: upstream(of: symbol), maxAge: Self.fundingMaxAge)?.rate
  }

  /// 手指按住那一刻才去取。已经有的那几样不再取：K 线取一次就一直留着，
  /// 那两个统计也是，费率过了保鲜期才重新取。三样都齐就什么都不做。
  func warm(symbol: String, base: String) {
    let key = InstrumentID.canonical(symbol)
    touch(key)
    let needsBars = bars[key] == nil
    let needsStats = stats[key] == nil
    let needsFunding = funding(for: key) == nil
    guard jobs[key] == nil, needsBars || needsStats || needsFunding else { return }
    let service = SymbolPreviewService(resolver: resolver)
    let proxies = resolver.route.apiHosts
    let caps = service.capabilities(for: key)
    let src = caps.openInterestSource, upstream = caps.upstream
    jobs[key] = Task { [weak self] in
      // 费率和 K 线同时出发：两笔都是这张卡等着画的，串起来等于让人多等一趟。
      async let rate: FundingSnapshot? = needsFunding ? await service.funding(for: key) : nil
      if needsBars {
        let usable = await service.bars(for: key)
        if Task.isCancelled { return }
        if !usable.isEmpty { self?.put(usable, for: key) }
      }
      if let snapshot = await rate, !Task.isCancelled {
        FundingBook.shared.note(rate: snapshot.rate, nextFundingTimeMs: snapshot.nextFundingTimeMs,
                                for: key, upstream: upstream)
      }
      guard needsStats, !proxies.isEmpty else { self?.jobs[key] = nil; return }
      async let meta = MarketStatsClient.shared.meta(symbol: key, base: base, hosts: proxies)
      async let oi = MarketStatsClient.shared.openInterest(symbol: key, source: src, hosts: proxies,
                                                           maxAge: MarketStatsClient.openInterestFresh)
      let row = Stats(
        openInterestValue: MarketStatsClient.notionalOpenInterest(await oi, previous: nil),
        totalSupply: (await meta)?.totalSupply.flatMap { $0.isFinite && $0 > 0 ? $0 : nil })
      if Task.isCancelled { return }
      self?.put(row, for: key)
      self?.jobs[key] = nil
    }
  }

  private func put(_ rows: [Bar], for key: String) {
    bars[key] = rows
    touch(key)
    trim()
  }

  private func put(_ row: Stats, for key: String) {
    stats[key] = row
    touch(key)
    trim()
  }

  private func touch(_ key: String) {
    recent.removeAll { $0 == key }
    recent.append(key)
  }

  private func trim() {
    while recent.count > Self.capacity {
      let victim = recent.removeFirst()
      bars.removeValue(forKey: victim)
      stats.removeValue(forKey: victim)
    }
  }
}

/// 预览卡本体。
struct SymbolPreviewCard: View {
  var symbol: String
  var info: SymbolInfo?
  var ticker: Ticker?
  var store: SymbolPreviewStore
  /// 已下架 / 还没开盘的行：由实时价算出来的几格一律空着，和列表里同一个判据。
  var stale = false
  /// 近 N 小时涨跌幅（百分数）。只有手上有逐分钟走势的页（自选）传；没传就不摆那一行——
  /// 拿卡上这段 1 小时 K 线去凑会差出将近一整根，宁可不写也不写个差不多的数。
  var recentChange: ((Int) -> Double?)? = nil

  @Environment(\.panelTheme) private var t

  private var base: String { info?.base ?? SymbolInfo.placeholder(symbol: symbol).base }
  private var quote: String { info?.quote ?? "USDT" }
  private var live: Ticker? { stale ? nil : ticker }
  private var pct: Double? {
    guard let value = live?.changePercent, value.isFinite else { return nil }
    return value
  }
  private var price: Double? {
    guard let value = ticker?.last, value.isFinite else { return nil }
    return value
  }
  private var decimals: Int {
    info?.displayDecimals(for: price ?? .nan) ?? priceDecimalsFallback(price ?? .nan)
  }
  private var bars: [Bar] { store.bars(for: symbol) }

  // 字号、间距、圆角全取令牌（UI 审查 2026-09-24：原来 9 / 9.5 / 10 / 10.5 的字、11 / 9 / 14 的距）。
  /// 品种名：15 semibold，和价格同一档、字重高一级。
  private static let nameFont = ScaledFont(TypeScale.body.size, .semibold, relativeTo: .subheadline)

  var body: some View {
    VStack(alignment: .leading, spacing: Space.m) {
      head
      candles
      stats
    }
    .padding(Inset.card)
    .frame(width: 272)
    .background(t.app)
    .task { store.warm(symbol: symbol, base: base) }
  }

  private var head: some View {
    HStack(spacing: Space.s) {
      CoinBadge(base: base, asset: info.map { SymbolClassifier.classify($0).asset },
                size: ControlMetrics.badge)
      VStack(alignment: .leading, spacing: Space.xxs) {
        HStack(alignment: .firstTextBaseline, spacing: Space.xs) {
          Text(base).font(Self.nameFont).foregroundStyle(t.ink)
          Text(quote).font(TypeScale.caption2).foregroundStyle(t.ink3)
        }.lineLimit(1)
        Text(SymbolPreviewStore.interval.shortLabel + " · 近 \(SymbolPreviewStore.barCount) 根")
          .font(TypeScale.caption2).foregroundStyle(t.ink3)
      }
      Spacer(minLength: Space.s)
      VStack(alignment: .trailing, spacing: Space.xs) {
        Text(price.map { SymbolRowText.price($0, decimals: decimals) } ?? SymbolRowText.missing)
          .font(TypeScale.bodyEmph).monospacedDigit()
          .foregroundStyle(stale ? t.ink3 : (pct.map { $0 >= 0 ? t.up : t.down } ?? t.ink))
          .lineLimit(1).minimumScaleFactor(0.7)
        pill
      }
    }
  }

  /// 和列表里同一颗药丸（`ChangePill`）：方向只靠「+ / −」和颜色说，不挂小三角。
  private var pill: some View {
    ChangePill(value: pct ?? .nan, text: pct.map { changePercentText($0) } ?? SymbolRowText.missing)
  }

  /// 一段迷你 K 线。还没到货时摆一块底色，不写「加载中」——它一两秒就自己来了。
  @ViewBuilder private var candles: some View {
    ZStack {
      RoundedRectangle(cornerRadius: Radius.s, style: .continuous).fill(t.chartBG)
      if bars.count > 1 {
        MiniCandles(bars: bars, up: Color(hex: t.chart.up), down: Color(hex: t.chart.down))  // 蜡烛取图上色
          .padding(Space.s)
      }
    }
    .frame(height: 86)
  }

  private var stats: some View {
    Grid(alignment: .leading, horizontalSpacing: Space.l, verticalSpacing: Space.s) {
      if let recentChange {
        GridRow {
          cell("1小时", stale ? nil : recentChange(1).map { changePercentText($0) })
          cell("4小时", stale ? nil : recentChange(4).map { changePercentText($0) })
        }
      }
      GridRow {
        cell("24小时高", live.flatMap { $0.high.isFinite && $0.high > 0 ? SymbolRowText.price($0.high, decimals: decimals) : nil })
        cell("24小时低", live.flatMap { $0.low.isFinite && $0.low > 0 ? SymbolRowText.price($0.low, decimals: decimals) : nil })
      }
      GridRow {
        cell("持仓量", HeaderStats.openInterestText(value: store.stats(for: symbol)?.openInterestValue,
                                                 unit: nil))
        cell("成交额", HeaderStats.turnoverText(quoteVolume: live?.quoteVolume, unit: nil, fresh: !stale))
      }
      GridRow {
        cell("市值", HeaderStats.marketCapText(totalSupply: store.stats(for: symbol)?.totalSupply,
                                             price: price, fresh: !stale))
        cell("费率", HeaderStats.fundingText(rate: store.funding(for: symbol), fresh: !stale))
      }
    }
  }

  private func cell(_ label: String, _ value: String?) -> some View {
    HStack(alignment: .firstTextBaseline, spacing: Space.s) {
      // 标签永远整字显示，挤的时候让数值缩（数值有 minimumScaleFactor）。
      Text(label).font(TypeScale.caption2).foregroundStyle(t.ink3)
        .lineLimit(1).fixedSize()
      Spacer(minLength: 0)
      Text(value ?? SymbolRowText.missing)
        .font(TypeScale.caption2Emph).monospacedDigit()
        .foregroundStyle(value == nil ? t.ink3 : t.ink2)
        .lineLimit(1).minimumScaleFactor(0.8)
    }
    .frame(maxWidth: .infinity, alignment: .leading)
  }
}

/// 卡上那段 K 线。只画蜡烛：没有轴、没有网格、没有图例——那些是整张图的事，
/// 这儿只要一个形状。
struct MiniCandles: View {
  var bars: [Bar]
  var up: Color
  var down: Color

  var body: some View {
    Canvas(opaque: false) { ctx, size in
      guard bars.count > 1 else { return }
      let lo = bars.map(\.low).min() ?? 0
      let hi = bars.map(\.high).max() ?? 0
      guard hi > lo, lo.isFinite, hi.isFinite else { return }
      let slot = size.width / CGFloat(bars.count)
      let body = max(1.2, min(5, slot * 0.62))
      func y(_ value: Double) -> CGFloat {
        size.height - CGFloat((value - lo) / (hi - lo)) * size.height
      }
      for (index, bar) in bars.enumerated() {
        let x = (CGFloat(index) + 0.5) * slot
        let color = bar.close >= bar.open ? up : down
        var wick = Path()
        wick.move(to: CGPoint(x: x, y: y(bar.high)))
        wick.addLine(to: CGPoint(x: x, y: y(bar.low)))
        ctx.stroke(wick, with: .color(color), lineWidth: 1)
        let top = y(max(bar.open, bar.close))
        let bottom = y(min(bar.open, bar.close))
        ctx.fill(Path(CGRect(x: x - body / 2, y: top, width: body,
                             height: max(1, bottom - top))),
                 with: .color(color))
      }
    }
    .drawingGroup()
  }
}
