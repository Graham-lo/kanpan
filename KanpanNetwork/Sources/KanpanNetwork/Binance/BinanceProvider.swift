import Foundation
import KanpanCore

/// 币安 U 本位永续，包成一个 `MarketProvider`。
///
/// 线协议、限流、线路都还是原来那几个文件（`RESTClient` / `WSClient` / `Route`），
/// 这里只做翻译：上层说「给我 BTC 的 1y」，这里换成「拉 1M 自己聚」；上层说
/// 「订逐笔」，这里换成 `btcusdt@trade`。
///
/// 两条线路供的都是币安本家的数（2026-10-08 起网关档不再有 OKX 替身）：
/// - 直连：币安自己的域名；
/// - 网关：REST 走 kanpan-api 的原样透传（`MarketRESTTransport`），推送走 Python 网关的共享 hub
///   （`SourceSocketFactory`）。hub 不转盘口与逐笔，所以网关档的能力位只少 `hasMicrostructure`。
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
  /// `RouteResolver` 定下的线路：直连 / 网关与网关表。
  let route: MarketRoute
  let sockets: any WSSocketFactory
  /// 订单流品种表（`orderFlowCatalog`）问 kanpan-api 走的传输。
  let http: any HTTPTransport

  /// - Parameters:
  ///   - rest: 测试注入用。不传就按 `route` 建一个走共享限流器的（`BinanceREST.routed`）。
  ///   - sockets: 最底层的 WS 拨号器（测试里换成假的）。
  ///   - http: 订单流品种表走的传输（测试里换成假的）。
  public init(hosts: BinanceHosts, route: MarketRoute,
              rest: BinanceREST? = nil, sockets: any WSSocketFactory = URLSessionSocketFactory(),
              http: any HTTPTransport = URLSessionTransport(),
              log: FeedLog = .silent) {
    self.hosts = hosts
    self.route = route
    self.sockets = sockets
    self.http = http
    self.rest = rest ?? BinanceREST.routed(hosts: hosts, route: route, log: log)
    self.capabilities = Self.capabilities(viaGateway: route.viaGateway)
  }

  /// 按线路建一个（`VenueRegistry.binance` 的工厂）：域名取出厂默认、网关表来自线路。
  public init(route: MarketRoute, log: FeedLog = .silent) {
    self.init(hosts: Self.hosts(route.endpoints), route: route, log: log)
  }

  /// 测试用的旧写法：只给线路档位，网关表取 `hosts.oiProxies`（同时当 kanpan-api 主机）。
  public init(hosts: BinanceHosts, policy: MarketRoutePolicy,
              rest: BinanceREST? = nil, sockets: any WSSocketFactory = URLSessionSocketFactory(),
              http: any HTTPTransport = URLSessionTransport(),
              log: FeedLog = .silent) {
    self.init(hosts: hosts,
              route: MarketRoute(policy: policy, endpoints: MarketEndpoints(gateways: hosts.oiProxies,
                                                                             api: hosts.oiProxies)),
              rest: rest, sockets: sockets, http: http, log: log)
  }

  /// 币安的域名：REST / 流都是出厂默认（直连用），网关表来自线路。
  /// 以前这里还能被「自定义 REST / 流域名」覆盖，那一层已经删了（见 `APIHost.swift`）。
  public static func hosts(_ endpoints: MarketEndpoints) -> BinanceHosts {
    BinanceHosts(fapi: defaultRestHost,
                 stream: defaultStreamHost,
                 oiProxy: endpoints.gateways.first,
                 oiProxyFallbacks: Array(endpoints.gateways.dropFirst()))
  }

  public static let nativeIntervals: Set<Interval> = Set(Interval.allCases).subtracting(BinanceREST.aggregatedFrom.keys)

  /// 直连：币安本家，能力位全开。
  public static let directCapabilities = ProviderCapabilities(
    venue: venue, market: market,
    nativeIntervals: nativeIntervals, aggregatedFrom: BinanceREST.aggregatedFrom,
    maxKlines: BinanceREST.maxKlines, maxTailBars: BinanceREST.maxTailBars,
    // 直连一次就要满深度：`MarketFeed.fillOnce` 看见首发深于一屏会另外并行发一发
    // 300 根的小页，谁先回谁先画（弱网上先看见图，满深度回来再铺开）。
    initialKlines: 1800,
    liveKlineIntervals: nativeIntervals,
    hasTickerStream: true, hasMarkPrice: true, hasFunding: true,
    openInterestSource: "binance", hasMicrostructure: true, hasDerivativeMetrics: true,
    hasOpenInterestHistory: true, hasOpenInterestArchive: true,
    hasBulkTickers: true, probesHistoryBoundary: true,
    quoteAssets: ["USDT"])

  /// 网关：同样是币安本家的数（REST 原样透传、推送走共享 hub），只少盘口与逐笔方向——
  /// hub 只转 `ticker` / `markPrice@1s` / `aggTrade` / `kline_*`，没有 `@depth5` 与 `@trade`。
  ///
  /// 首屏只要 300 根（一发），深度交给后台加深：直连的 1800 会让 `MarketFeed.fillOnce` 并行再发一发
  /// 300 根的小页，网关档首屏从一发变成两发，而且整页 1500 根要经新加坡转一道（性能底线：首屏请求数不增加）。
  public static let gatewayCapabilities: ProviderCapabilities = {
    var caps = directCapabilities
    caps.initialKlines = 300
    caps.hasMicrostructure = false
    return caps
  }()

  public static func capabilities(viaGateway: Bool) -> ProviderCapabilities {
    viaGateway ? gatewayCapabilities : directCapabilities
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

  /// 全市场资金费率整表（`/fapi/v1/premiumIndex`），键是完整品种 key。
  public func fundingAll() async throws -> [String: FundingSnapshot] {
    var out: [String: FundingSnapshot] = [:]
    for (symbol, row) in try await rest.fundingAll() { out[InstrumentID.canonical(symbol)] = row }
    return out
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

  /// 线路由 `SourceSocketFactory` 管（直连只拨币安、网关只拨网关的 hub）。网关档只把 hub 认的流交出去。
  public func makeStream(silenceMs: Double?, log: FeedLog) -> any MarketStream {
    BinanceWS(hosts: hosts,
              factory: SourceSocketFactory(factory: sockets, route: route, log: log),
              // 首帧前的静默窗口给 60 秒（A-07 第②层）：线路是用户定死的、没有竞速，
              // 冷门永续 15 秒内完全可能一帧都不推，收窄就会变成无休止的重连。
              silenceMs: silenceMs ?? 60_000, log: log,
              allows: route.viaGateway ? Self.gatewayAllows : nil)
  }

  /// 网关 hub 放行的流（`stream_hub.py` 的 `STREAM`）：`ticker`、`markPrice@1s`、`aggTrade`、`kline_*`。
  /// 别的（`@trade`、`@depth5@100ms`）订了会被 hub 以 1008 当场断开，整条连接上的行情都跟着断。
  public static let gatewayAllows: @Sendable (String) -> Bool = { name in
    guard let at = name.firstIndex(of: "@") else { return false }
    let channel = name[name.index(after: at)...]
    return channel == "ticker" || channel == "markPrice@1s" || channel == "aggTrade" || channel.hasPrefix("kline_")
  }

  public func probeStream(symbol: String, interval: Interval) async -> Bool {
    let factory = SourceSocketFactory(factory: sockets, route: route)
    let url = hosts.combinedStream([Self.streamName(.kline(symbol: symbol, interval: BinanceREST.source(interval)))])
    do {
      let socket = try await factory.connect(to: url)
      await socket.cancel()
      try Task.checkCancellation()
      return true
    } catch { return false }
  }

  /// 直连：REST 那台发一笔 `ping`（权重 1、无鉴权），推送那台只要 DNS + TLS 走通，用 HEAD。
  /// 网关：推送打网关表、REST 打 kanpan-api，每台各 HEAD 一下（线上是同一台）——以前这里不管线路
  /// 一律热直连域名，选了网关的人热的是一台他根本不会连的机器。
  public var prewarmTargets: [PrewarmTarget] {
    if route.viaGateway {
      var seen = Set<String>()
      return (route.gateways + route.apiHosts).filter { seen.insert($0).inserted }
        .compactMap { PrewarmTarget.make(host: $0, path: "/", method: "HEAD") }
    }
    return [PrewarmTarget.make(host: hosts.fapi, path: Self.warmPath, method: "GET"),
            PrewarmTarget.make(host: hosts.stream, path: "/", method: "HEAD")].compactMap { $0 }
  }

  /// 小组件补价：直连打币安 `/fapi/v1/*`；网关打 kanpan-api 的原样透传
  /// `/v1/market/raw/fapi/v1/*?…&source=binance`，载荷与直连同形（不包信封）。
  public var widgetRefresh: WidgetSnapshot.Refresh? {
    let market = "\(capabilities.venue)/\(capabilities.market)"
    if route.viaGateway {
      guard !route.apiHosts.isEmpty else { return nil }
      let raw = VenueEndpoints.rawPrefix, source = "&source=\(Self.venue)"
      return WidgetSnapshot.Refresh(market: market, hosts: route.apiHosts,
                                    ticker: raw + "fapi/v1/ticker/24hr?symbol={symbol}" + source,
                                    closes: raw + "fapi/v1/klines?symbol={symbol}&interval=1h&limit={limit}" + source,
                                    format: .binance)
    }
    return WidgetSnapshot.Refresh(market: market, hosts: [hosts.fapi],
                                  ticker: "/fapi/v1/ticker/24hr?symbol={symbol}",
                                  closes: "/fapi/v1/klines?symbol={symbol}&interval=1h&limit={limit}")
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
    start(streams: streamNames(topics))
  }
  public func replace(topics: [StreamTopic]) async {
    await replaceStreams(streamNames(topics))
  }
  /// 订阅 → 流名，只留这条线路认的（网关 hub 不认的那几种丢掉，见 `BinanceProvider.gatewayAllows`）。
  private func streamNames(_ topics: [StreamTopic]) -> [String] {
    let names = topics.map(BinanceProvider.streamName)
    guard let allows else { return names }
    return names.filter(allows)
  }
}
