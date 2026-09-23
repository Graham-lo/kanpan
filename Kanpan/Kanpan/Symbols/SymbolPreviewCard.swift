import Observation
import SwiftUI
import KanpanCore
import KanpanNetwork

/// 长按一行品种弹出来的那张小卡：徽章 · 名字 · 最新价 · 涨跌药丸 · 一段 K 线 · 四格数。
///
/// 它回答的是「这东西现在什么样」——不用切页就看一眼，松手就没了。所以它只摆
/// 已经有的事实，不做任何交互（要动手的都在旁边那份菜单里）。
///
/// 数据一律走现成的路：价和涨跌来自列表本来就订着的报价，持仓量和供应量走
/// 顶栏那四格同一个 `MarketStatsClient`（它自己带缓存），K 线走这个品种那一家的提供者
/// 拉一次 1 小时 × 60 根、按品种记着。费率读顶栏同一本 `FundingBook`（全市场整表 +
/// 图上 `markPrice` 流记下的那口），5 分钟内的都算数；簿里没有才走单品种
/// `premiumIndex`（公开、免鉴权、权重 1），和 K 线并发发出，问到了也记回簿里。
@MainActor @Observable
final class SymbolPreviewStore {
  /// 预览卡要的那两个后端数：持仓量（美元名义）和供应量（算市值）。
  struct Stats: Equatable {
    var openInterestValue: Double?
    var totalSupply: Double?
  }

  /// 卡上那段 K 线：1 小时 × 60 根。
  static let interval = Interval.h1
  static let barCount = 60
  /// 最多记多少个品种的 K 线。翻一页自选也就几十行，记 24 个够用，多了白占内存。
  static let capacity = 24

  /// 费率的保鲜期。资金费率几小时才结算一次，5 分钟内的那口足够代表「现在」，
  /// 又不至于让翻一页自选变成几十次往返。
  static let fundingMaxAge: TimeInterval = 5 * 60

  private(set) var bars: [String: [Bar]] = [:]
  private(set) var stats: [String: Stats] = [:]

  @ObservationIgnored private var resolver = RouteResolver(policy: .direct, endpoints: .default)
  @ObservationIgnored private var jobs: [String: Task<Void, Never>] = [:]
  /// 最近用过的在后面。满了从前面扔。
  @ObservationIgnored private var recent: [String] = []

  /// 换线路 / 换域名：手上这批数是上一条路取的，整批作废。
  func configure(endpoints next: MarketEndpoints, policy: MarketRoutePolicy) {
    guard next != resolver.endpoints || policy != resolver.policy else { return }
    resolver = RouteResolver(policy: policy, endpoints: next)
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
    let rest = resolver.provider(forSymbol: key)
    let proxies = resolver.endpoints.gateways
    let src = rest.capabilities.openInterestSource, upstream = rest.capabilities.upstream
    jobs[key] = Task { [weak self] in
      // 费率和 K 线同时出发：两笔都是这张卡等着画的，串起来等于让人多等一趟。
      async let rate: FundingSnapshot? = needsFunding
        ? try? await rest.funding(symbol: key) : nil
      if needsBars {
        let rows = (try? await rest.klines(symbol: key, interval: Self.interval,
                                           limit: Self.barCount)) ?? []
        if Task.isCancelled { return }
        let usable = rows.filter(\.isValidMarketBar).suffix(Self.barCount)
        if !usable.isEmpty { self?.put(Array(usable), for: key) }
      }
      if let snapshot = await rate, snapshot.rate.isFinite, !Task.isCancelled {
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

  var body: some View {
    VStack(alignment: .leading, spacing: 11) {
      head
      candles
      stats
    }
    .padding(14)
    .frame(width: 272)
    .background(t.app)
    .task { store.warm(symbol: symbol, base: base) }
  }

  private var head: some View {
    HStack(spacing: 9) {
      CoinBadge(base: base, size: 28)
      VStack(alignment: .leading, spacing: 2) {
        HStack(alignment: .firstTextBaseline, spacing: 3) {
          Text(base).font(.scaled(14, .semibold)).foregroundStyle(t.ink)
          Text(quote).font(.scaled(9)).foregroundStyle(t.ink3)
        }.lineLimit(1)
        Text(SymbolPreviewStore.interval.display + " · 近 \(SymbolPreviewStore.barCount) 根")
          .font(.scaled(9.5)).foregroundStyle(t.ink3)
      }
      Spacer(minLength: 6)
      VStack(alignment: .trailing, spacing: 3) {
        Text(price.map { grouped(fmtPrice($0, decimals: decimals)) } ?? "—")
          .font(.scaled(15, .medium)).monospacedDigit()
          .foregroundStyle(stale ? t.ink3 : (pct.map { $0 >= 0 ? t.up : t.down } ?? t.ink))
          .lineLimit(1).minimumScaleFactor(0.7)
        pill
      }
    }
  }

  private var pill: some View {
    HStack(spacing: 2.5) {
      if let pct {
        Image(systemName: pct >= 0 ? "arrowtriangle.up.fill" : "arrowtriangle.down.fill")
          .font(.system(size: 6.5))
      }
      Text(pct.map { ($0 >= 0 ? "+" : "") + toFixed($0, 2) + "%" } ?? "—")
        .font(.scaled(10.5, .semibold)).monospacedDigit()
    }
    .foregroundStyle(pct == nil ? t.ink3 : t.badgeInk)
    .padding(.horizontal, 6).padding(.vertical, 2.5)
    .background(pct.map { t.badgeFill(up: $0 >= 0) } ?? t.raised2,
                in: RoundedRectangle(cornerRadius: 6, style: .continuous))
  }

  /// 一段迷你 K 线。还没到货时摆一块底色，不写「加载中」——它一两秒就自己来了。
  @ViewBuilder private var candles: some View {
    ZStack {
      RoundedRectangle(cornerRadius: 8, style: .continuous).fill(t.chartBG)
      if bars.count > 1 {
        MiniCandles(bars: bars, up: t.up, down: t.down)
          .padding(.horizontal, 7).padding(.vertical, 6)
      }
    }
    .frame(height: 86)
  }

  private var stats: some View {
    Grid(alignment: .leading, horizontalSpacing: 14, verticalSpacing: 6) {
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
    HStack(alignment: .firstTextBaseline, spacing: 6) {
      Text(label).font(.scaled(10)).foregroundStyle(t.ink3)
      Spacer(minLength: 0)
      Text(value ?? "--")
        .font(.scaled(11, .medium)).monospacedDigit()
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
