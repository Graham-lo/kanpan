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
/// 能力位不一样（首屏深度、没有 24h 推送、没有盘口），上层照能力位办事就行。
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

  /// - Parameters:
  ///   - rest: 测试注入用。不传就按 `upstream` + `policy` 建一个走共享限流器的。
  ///   - sockets: 最底层的 WS 拨号器（测试里换成假的）。
  public init(upstream: BinanceUpstream, hosts: BinanceHosts, policy: MarketRoutePolicy,
              rest: BinanceREST? = nil, sockets: any WSSocketFactory = URLSessionSocketFactory(),
              log: FeedLog = .silent) {
    self.upstream = upstream
    self.hosts = hosts
    self.policy = policy
    self.sockets = sockets
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
                 streamFallbacks: endpoints.streamFallbacks,
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
        hasBulkTickers: true, probesHistoryBoundary: true, snapshotNamespace: nil,
        quoteAssets: ["USDT"])
    case .okx:
      // OKX 替身：网关只有「最新窗口且 limit ≤ 300」才是一次请求，再深就要在 VPS 上
      // 按 100 根翻十几页拼出来（`Backend/kanpan-gateway/market_rest.py` 的 klines 分支），
      // 首屏反而更慢，所以首屏只要 300 根，深度交给后台加深。
      // 网关这条组合流只转 kline：没有 24h 推送、标记价、逐笔方向与盘口；
      // 持仓量历史副图与那几个外部指标也只在币安本家上开（顶栏「仓」那一格走网关按
      // OKX 口径取，见 `openInterestSource`）。
      return ProviderCapabilities(
        venue: venue, market: market, upstream: upstream.rawValue,
        nativeIntervals: nativeIntervals, aggregatedFrom: BinanceREST.aggregatedFrom,
        maxKlines: BinanceREST.maxKlines, initialKlines: 300,
        liveKlineIntervals: nativeIntervals,
        hasTickerStream: false, hasMarkPrice: false, hasFunding: false,
        openInterestSource: "okx", hasMicrostructure: false, hasDerivativeMetrics: false,
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

  public func ticker24h(symbol: String, timeout: TimeInterval) async throws -> Ticker {
    try await rest.ticker24h(symbol: symbol, timeout: timeout)
  }

  public func tickers24h(timeout: TimeInterval) async throws -> [Ticker] {
    try await rest.tickers24h(timeout: timeout)
  }

  public func funding(symbol: String) async throws -> FundingSnapshot {
    try await rest.funding(symbol: symbol)
  }

  public func openInterestHist(symbol: String, period: String, limit: Int,
                               startTime: Int64?, endTime: Int64?) async throws -> [OIPoint] {
    try await rest.openInterestHist(symbol: symbol, period: period, limit: limit,
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

  /// 线路由 `SourceSocketFactory` 管（直连只拨币安、网关只拨网关），所以交给 `BinanceWS`
  /// 的那份主机表要把通用的 `streamFallbacks` 清掉，免得两层各包一次候选。
  public func makeStream(silenceMs: Double?, log: FeedLog) -> any MarketStream {
    var direct = hosts; direct.streamFallbacks = []
    return BinanceWS(hosts: direct,
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
    case .bookTicker(let s): return BinanceHosts.bookTickerStream(symbol: s)
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
