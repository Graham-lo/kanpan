import Foundation
import KanpanCore

/// 币安 U 本位永续，包成一个 `MarketProvider`。
///
/// 线协议、限流、网关竞速都还是原来那几个文件（`RESTClient` / `WSClient` / `Route`），
/// 这里只做翻译：上层说「给我 BTC 的 1y」，这里换成「拉 1M 自己聚」；上层说
/// 「订逐笔」，这里换成 `btcusdt@trade`。
///
/// 网关线路上币安本家是被封的（451），服务端拿 OKX 的同名永续顶上——那是这一家
/// 自己的事，见 `BinanceUpstream` 与 `RouteResolver`：同一个 venue（`binance`），
/// 能力位不一样（首屏深度、没有标记价推送、没有盘口），上层照能力位办事就行。
public struct BinanceProvider: MarketProvider {
  public static let venue = "binance"
  public static let market = "usd_m"
  /// 出厂 REST 域名。用户可以在设置里改（换镜像域）。
  public static let defaultRestHost = "fapi.binance.com"
  /// 出厂推送域名（设置里「推送域名」的默认值）。
  ///
  /// 默认是 `dstream.binance.me`。这个值 2026-09-18 逐条实测定下来，两条理由：
  ///
  /// 一、**它是生产盘，不是测试网**。`stream.binancefuture.com` / `fstream.binancefuture.com`
  /// 虽然挂在官方文档上，实测推的是合约测试网的数据——同一时刻它的 24h 成交额是
  /// 1214 亿、成交笔数 31.6 万，和 `testnet.binancefuture.com` 的 REST 逐字段相同，
  /// 而生产盘 `fapi.binance.com` 是 139 亿、431 万笔。测试网上大多数山寨根本没有成交，
  /// 所以 K 线和自选列表看上去「不跳」。
  ///
  /// 二、**从国内这条出口看，`fstream` 这一族只剩盘口流**。`fstream.binance.me`（直连）
  /// 与 `fstream.binance.com`（走代理）都只发 `bookTicker`/`depth`，`kline`/`ticker`/
  /// `aggTrade`/`markPrice` 订阅回 `result:null` 之后一帧不发——`/ws`、`/stream`、
  /// `/public/ws`、`/public/stream` 四种路径都试过，20~30 秒窗口里 `bookTicker` 六千多帧、
  /// `kline` 零帧。同一时刻同一出口的 `dstream.binance.me` 一切正常。
  ///
  /// 这是**按出口而异**的，不要写成「币安把合约流搬走了」：同一天美国机房的网关上
  /// 实测 `fstream.binance.com` 的 `kline_1m` 是正常出帧的（30 秒 35 帧，生产盘量级）。
  /// 所以这条只是「国内这两条出口上 `fstream` 不可用」，服务端选域名要在服务端自己测。
  ///
  /// 顺带记一个容易看错的地方：`dstream` 上 `btcusdt@aggTrade` 的 id 是 34 亿量级，
  /// 而 `fapi` 的 24hrTicker 里 `firstId`/`lastId` 是 80 亿量级——这两个本来就是
  /// 不同的序列（聚合成交 id ≠ 逐笔成交 id），不是测试网的证据。要对生产盘就对
  /// `count` 和 `quoteVolume`：实测同一时刻 `fapi` 是 3393098 笔 / 108.91 亿，
  /// `dstream.binance.me` 的 `btcusdt@ticker` 是 3393408 笔 / 108.92 亿，同一个盘。
  ///
  /// 在 `.me` 和 `.com` 之间选 `.me`：国内 DNS 解析干净（返回真实的 AWS 东京地址，没有被投毒），
  /// 可以直连，实测比走代理快——握手 361~423ms 对 785~791ms，首帧 666~762ms 对 1148~1175ms，
  /// 同时并发跑两条连接测推送延迟，直连比代理低约 30ms，收到的帧数一致（不丢帧）。
  public static let defaultStreamHost = "dstream.binance.me"

  /// 该迁走的旧推送域名。存过它们的设备要换到新默认值，否则老配置会一直把人钉死在
  /// 对国内用户不可用的域名（`fstream.binance.com`）或测试网（`*.binancefuture.com`）上。
  public static let legacyStreamHosts = [
    "fstream.binance.com",          // 国内这条出口上只剩盘口流，且本身也解析不干净
    "stream.binancefuture.com",     // 测试网
    "fstream.binancefuture.com",    // 测试网
    "dstream.binancefuture.com",    // 测试网
  ]

  /// 冷启动热身用的连通性探测（权重 1、无鉴权）。
  public static let warmPath = "/fapi/v1/ping"

  public let capabilities: ProviderCapabilities
  public let rest: BinanceREST
  public let hosts: BinanceHosts
  public let upstream: BinanceUpstream
  let policy: MarketRoutePolicy
  let sockets: any WSSocketFactory
  /// 直接问网关（不经 `BinanceREST` 的路径翻译与限流器）的那几笔：替身的资金费率表。
  let http: any HTTPTransport

  /// - Parameters:
  ///   - rest: 测试注入用。不传就按 `upstream` + `policy` 建一个走共享限流器的。
  ///   - sockets: 最底层的 WS 拨号器（测试里换成假的）。
  ///   - http: 直接问网关的那几笔走的传输（测试里换成假的）。
  public init(upstream: BinanceUpstream, hosts: BinanceHosts, policy: MarketRoutePolicy,
              rest: BinanceREST? = nil, sockets: any WSSocketFactory = URLSessionSocketFactory(),
              http: any HTTPTransport = URLSessionTransport(),
              log: FeedLog = .silent) {
    self.upstream = upstream
    self.hosts = hosts
    self.policy = policy
    self.sockets = sockets
    self.http = http
    self.rest = rest ?? BinanceREST.upstream(upstream, hosts: hosts, log: log, policy: policy)
    self.capabilities = Self.capabilities(upstream)
  }

  /// 用户的线路 → 这一家实际由谁供数。直连是币安本家，网关上是 OKX 替身。
  public static func upstream(for policy: MarketRoutePolicy) -> BinanceUpstream {
    policy == .gateway ? .okx : .binance
  }

  public static func hosts(_ endpoints: MarketEndpoints) -> BinanceHosts {
    BinanceHosts(fapi: endpoints.restHost ?? defaultRestHost,
                 stream: endpoints.streamHost ?? defaultStreamHost,
                 oiProxy: endpoints.gateways.first,
                 oiProxyFallbacks: Array(endpoints.gateways.dropFirst()))
  }

  public static let nativeIntervals: Set<Interval> = Set(Interval.allCases).subtracting(BinanceREST.aggregatedFrom.keys)

  public static func capabilities(_ upstream: BinanceUpstream) -> ProviderCapabilities {
    switch upstream {
    case .binance:
      return ProviderCapabilities(
        venue: venue, market: market, upstream: upstream.rawValue,
        nativeIntervals: nativeIntervals, aggregatedFrom: BinanceREST.aggregatedFrom,
        maxKlines: BinanceREST.maxKlines,
        // 直连一次就要满深度：`MarketFeed.fillOnce` 看见首发深于一屏会另外并行发一发
        // 300 根的小页，谁先回谁先画（弱网上先看见图，满深度回来再铺开）。
        initialKlines: 1800,
        liveKlineIntervals: nativeIntervals,
        hasTickerStream: true, hasMarkPrice: true, hasFunding: true,
        openInterestSource: "binance", hasMicrostructure: true, hasDerivativeMetrics: true,
        hasOpenInterestHistory: true, hasOpenInterestArchive: true,
        hasBulkTickers: true, probesHistoryBoundary: true, snapshotNamespace: nil,
        quoteAssets: ["USDT"])
    case .okx:
      // OKX 替身：网关只有「最新窗口且 limit ≤ 300」才是一次请求，再深就要在 VPS 上
      // 按 100 根翻十几页拼出来（`Backend/kanpan-gateway/market_rest.py` 的 klines 分支），
      // 首屏反而更慢，所以首屏只要 300 根，深度交给后台加深。
      // 网关的 OKX 组合流（`Backend/kanpan-gateway/okx_hub.py`）转 K 线和 24h 行情：
      // 行情帧是 OKX `tickers` 频道原样换成币安写法，只是不带成交额（OKX 那边只有币的
      // 个数），「额」那一格由 `ticker24h` 走 kanpan-api 补（`GatewayTicker`，按 OKX 自己的
      // 成交均价换成 USDT）。没有标记价、逐笔方向与盘口。
      // 持仓量：顶栏「仓」走网关按 OKX 口径取（`openInterestSource`），持仓量副图走
      // kanpan-api 的 OKX 持仓量历史（`GatewayOIHistory`）；没有币安那份归档，也没有
      // 多空比、主动买卖比、基差那几个外部指标。
      // 资金费率有：没有标记价流，但网关按 OKX 官方整表给（`GatewayFunding`），
      // 顶栏「费率」「结算」两格由整表垫、按表的刷新续，数是 OKX 自己的。
      return ProviderCapabilities(
        venue: venue, market: market, upstream: upstream.rawValue,
        nativeIntervals: nativeIntervals, aggregatedFrom: BinanceREST.aggregatedFrom,
        maxKlines: BinanceREST.maxKlines, initialKlines: 300,
        liveKlineIntervals: nativeIntervals,
        hasTickerStream: true, hasMarkPrice: false, hasFunding: true,
        openInterestSource: "okx", hasMicrostructure: false, hasDerivativeMetrics: false,
        hasOpenInterestHistory: true, hasOpenInterestArchive: false,
        hasBulkTickers: false, probesHistoryBoundary: false, snapshotNamespace: "okx",
        quoteAssets: ["USDT"])
    }
  }

  // ------------------------------------------------------------------ REST

  public func instruments() async throws -> [SymbolInfo] { try await rest.exchangeInfo() }

  public func klines(symbol: String, interval: Interval, limit: Int,
                     startTime: Int64?, endTime: Int64?) async throws -> [Bar] {
    try await rest.klines(symbol: symbol, interval: interval, limit: limit, startTime: startTime, endTime: endTime)
  }

  public func contiguousTail(symbol: String, interval: Interval, from: Int64) async throws -> [Bar] {
    try await rest.contiguousTail(symbol: symbol, interval: interval, from: from)
  }

  public func history(symbol: String, interval: Interval, pages: Int, before firstOpen: Int64) async throws -> [Bar] {
    try await rest.history(symbol: symbol, interval: interval, pages: pages, before: firstOpen)
  }

  /// 直连是币安本家的 `/fapi/v1/ticker/24hr`。网关线路上先问 kanpan-api 的替身行情
  /// （`GatewayTicker`，带换算好的 USDT 成交额）；它不在时退回网关原有的那条
  /// （同是 OKX 的数，只是没有成交额）——两条都是替身自己的，不混源。
  public func ticker24h(symbol: String, timeout: TimeInterval) async throws -> Ticker {
    let proxies = hosts.oiProxies
    guard upstream != .binance, !proxies.isEmpty else {
      return try await rest.ticker24h(symbol: symbol, timeout: timeout)
    }
    do {
      return try await GatewayTicker.fetch(hosts: proxies, source: upstream.rawValue, symbol: symbol,
                                           timeout: min(timeout, 6), transport: http)
    } catch {
      if error is CancellationError || Task.isCancelled { throw CancellationError() }
      return try await rest.ticker24h(symbol: symbol, timeout: timeout)
    }
  }

  public func tickers24h(timeout: TimeInterval) async throws -> [Ticker] {
    try await rest.tickers24h(timeout: timeout)
  }

  public func funding(symbol: String) async throws -> FundingSnapshot {
    guard upstream == .binance else {
      // 替身没有单品种费率接口：整表只有几 KB，从表里取这一行。
      guard let row = try await fundingAll()[InstrumentID.canonical(symbol)] else {
        throw FeedError.badResponse("\(upstream.rawValue) 没有 \(symbol) 的资金费率")
      }
      return row
    }
    return try await rest.funding(symbol: symbol)
  }

  /// 全市场资金费率整表，键是完整品种 key。
  ///
  /// 直连是币安本家的 `/fapi/v1/premiumIndex`；网关线路上是替身自己的整表
  /// （`/v1/market/funding?source=okx`，见 `GatewayFunding`）——两家各给各的，
  /// 不拿币安的费率去垫替身那张图（不混源）。
  public func fundingAll() async throws -> [String: FundingSnapshot] {
    guard upstream == .binance else {
      let proxies = hosts.oiProxies
      guard !proxies.isEmpty else { throw FeedError.unsupported("全市场资金费率") }
      return try await GatewayFunding.fetch(hosts: proxies, source: upstream.rawValue,
                                            venue: Self.venue, market: Self.market, transport: http)
    }
    var out: [String: FundingSnapshot] = [:]
    for (symbol, row) in try await rest.fundingAll() { out[InstrumentID.canonical(symbol)] = row }
    return out
  }

  /// 网关线路上是替身自己的持仓量历史（`GatewayOIHistory`，OKX 的币数）。它只认
  /// `endTime`：往前翻页由调用方（`OISource`）按页头时间接着问。
  public func openInterestHist(symbol: String, period: String, limit: Int,
                               startTime: Int64?, endTime: Int64?) async throws -> [OIPoint] {
    guard upstream == .binance else {
      let proxies = hosts.oiProxies
      guard !proxies.isEmpty else { throw FeedError.unsupported("持仓量历史") }
      let rows = try await GatewayOIHistory.fetch(hosts: proxies, source: upstream.rawValue, symbol: symbol,
                                                  period: period, limit: limit, endTime: endTime, transport: http)
      guard let startTime else { return rows }
      return rows.filter { $0.time >= startTime }
    }
    return try await rest.openInterestHist(symbol: symbol, period: period, limit: limit,
                                    startTime: startTime, endTime: endTime)
  }

  public func globalLongShortAccountRatio(symbol: String, period: String, limit: Int,
                                          startTime: Int64?, endTime: Int64?) async throws -> [LongShortRatioPoint] {
    try await rest.globalLongShortAccountRatio(symbol: symbol, period: period, limit: limit,
                                               startTime: startTime, endTime: endTime)
  }

  public func takerLongShortRatio(symbol: String, period: String, limit: Int,
                                  startTime: Int64?, endTime: Int64?) async throws -> [TakerRatioPoint] {
    try await rest.takerLongShortRatio(symbol: symbol, period: period, limit: limit,
                                       startTime: startTime, endTime: endTime)
  }

  public func basis(symbol: String, period: String, limit: Int,
                    startTime: Int64?, endTime: Int64?) async throws -> [BasisPoint] {
    try await rest.basis(pair: symbol, period: period, limit: limit, startTime: startTime, endTime: endTime)
  }

  public func metricsArchiveURL(symbol: String, day: String) -> URL? {
    hosts.metricsZip(symbol: symbol, day: day)
  }

  public func resetRouteCooldowns() async { await rest.resetRouteCooldowns() }

  // ------------------------------------------------------------------ WS

  /// 线路由 `SourceSocketFactory` 管（直连只拨币安、网关只拨网关）。
  public func makeStream(silenceMs: Double?, log: FeedLog) -> any MarketStream {
    BinanceWS(hosts: hosts,
                     factory: SourceSocketFactory(source: upstream, hosts: hosts, factory: sockets,
                                                  policy: policy, log: log),
                     // 首帧前的静默窗口给 60 秒（A-07 第②层）：线路是用户定死的、没有竞速，
                     // 冷门永续 15 秒内完全可能一帧都不推，收窄就会变成无休止的重连。
                     silenceMs: silenceMs ?? 60_000, log: log)
  }

  public func probeStream(symbol: String, interval: Interval) async -> Bool {
    let factory = SourceSocketFactory(source: upstream, hosts: hosts, factory: sockets, policy: policy)
    let url = hosts.combinedStream([Self.streamName(.kline(symbol: symbol, interval: BinanceREST.source(interval)))])
    do {
      let socket = try await factory.connect(to: url)
      await socket.cancel()
      try Task.checkCancellation()
      return true
    } catch { return false }
  }

  public func rawStreamURL(topics: [StreamTopic]) -> URL? {
    hosts.combinedStream(topics.map(Self.streamName))
  }

  /// 订阅 → 币安组合流的流名。
  public static func streamName(_ topic: StreamTopic) -> String {
    switch topic {
    case .kline(let s, let iv): return BinanceHosts.klineStream(symbol: s, interval: BinanceREST.source(iv).rawValue)
    case .ticker(let s): return BinanceHosts.tickerStream(symbol: s)
    case .markPrice(let s): return BinanceHosts.markPriceStream(symbol: s)
    case .trade(let s): return BinanceHosts.tradeStream(symbol: s)
    case .aggTrade(let s): return BinanceHosts.aggTradeStream(symbol: s)
    case .depth(let s): return BinanceHosts.depth5Stream(symbol: s)
    }
  }
}

extension BinanceWS: MarketStream {
  public func start(topics: [StreamTopic]) async -> AsyncStream<WSEvent> {
    start(streams: topics.map(BinanceProvider.streamName))
  }
  public func replace(topics: [StreamTopic]) async {
    await replaceStreams(topics.map(BinanceProvider.streamName))
  }
}
