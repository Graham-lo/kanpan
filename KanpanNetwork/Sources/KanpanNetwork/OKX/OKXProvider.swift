import Foundation
import KanpanCore

/// OKX USDT 线性永续（v5 公开行情），包成一个 `MarketProvider`。
///
/// 和币安那一支比，差别全写在能力位里，上层不认识「OKX」这个名字：
///
/// - **周期**：13 档原生（日以上用 UTC 对齐的 `…utc` 那一族）；1y←1M 由上层聚。全部原生档都有 K 线推送。
/// - **K 线翻页**：最新一页走 `market/candles`（一页 300 根，只覆盖最近 1440 根）；更早的走
///   `market/history-candles`（一页 100 根），游标是 `after`（取比它更早的），一页接一页往前翻。
/// - **24h 行情**：没有计价成交额，额 = 币数 × 现价（近似，见 `OKXDTO.ticker`）。
/// - **持仓量历史**：OKX 的统计接口经 kanpan-api `/v1/market/open-interest/history?source=okx` 拿
///   （服务端替我们翻页、对齐币安的周期写法、缓存）；**两条线路都打 `route.apiHosts`**。
///   资金费率整表同理走 `/v1/market/funding?source=okx`。
/// - **没有**主动方向与五档盘口这一层（`hasMicrostructure = false`）、多空比 / 主动买卖比 / 基差、持仓量归档。
///
/// 两条线路：直连打 OKX 自己的域名；网关打看盘自己的 kanpan-api（REST 原样透传、推送是中继），
/// 报文一字不差，只换地址（`OKXVenue`）。两条线路的能力位相同。
/// REST 走通用的 `VenueREST`、推送走两条通用的 `VenueStream`（public / business 各一条）+ `OKXWire`，
/// 由 `SplitVenueStream` 合成一条；限速是 `OKXVenue.limiter`。
public struct OKXProvider: MarketProvider {
  public static let venue = OKXVenue.id
  public static let market = OKXVenue.market
  /// `market/candles` 一页最多多少根；它只覆盖最近 `recentDepth` 根。
  static let recentPage = 300
  static let recentDepth = 1440
  /// `market/history-candles` 一页最多多少根。
  static let historyPage = 100
  /// kanpan-api 持仓量历史一次最多多少条（服务端 `OI_HISTORY_MAX`）。
  static let oiHistoryMax = 500

  public static let nativeIntervals: Set<Interval> = [.m1, .m3, .m5, .m15, .m30, .h1, .h2, .h4, .h6, .h12,
                                                       .d1, .w1, .mo1]
  public static let aggregatedFrom: [Interval: Interval] = [.y1: .mo1]

  public static let capabilities = ProviderCapabilities(
    venue: venue, market: market, upstream: venue,
    nativeIntervals: nativeIntervals, aggregatedFrom: aggregatedFrom,
    // 首屏一发：最新一页 300 根就是一次 `candles`。更早的由 `history` 一页一页翻。
    // 补缺最多四页 `candles`（1200 根，都在最近 1440 根以内）。
    maxKlines: recentPage, maxTailBars: 4 * recentPage, initialKlines: recentPage,
    liveKlineIntervals: nativeIntervals,
    hasTickerStream: true, hasMarkPrice: true, hasFunding: true,
    openInterestSource: venue, hasMicrostructure: false, hasDerivativeMetrics: false,
    hasOpenInterestHistory: true, hasOpenInterestArchive: false,
    // `market/tickers?instType=SWAP` 一次拿回全部永续。
    hasBulkTickers: true, probesHistoryBoundary: false, snapshotNamespace: nil,
    quoteAssets: [OKXVenue.quote])

  public var capabilities: ProviderCapabilities { Self.capabilities }
  let rest: VenueREST
  var endpoints: VenueEndpoints { rest.endpoints }
  var route: MarketRoute { endpoints.route }
  var transport: any HTTPTransport { rest.transport }
  let sockets: any WSSocketFactory
  let clock: @Sendable () -> Date

  public init(route: MarketRoute,
              transport: any HTTPTransport = URLSessionTransport(),
              sockets: any WSSocketFactory = URLSessionSocketFactory(),
              log: FeedLog = .silent) {
    self.init(route: route, transport: transport, sockets: sockets, limiter: OKXVenue.limiter(route), log: log)
  }

  /// 测试用：网关表同时当 kanpan-api 主机（`OKXVenue.endpoints(policy:gateways:)`）。
  init(policy: MarketRoutePolicy, gateways: [String], transport: any HTTPTransport,
       sockets: any WSSocketFactory = URLSessionSocketFactory(),
       limiter: VenueRateLimiter, log: FeedLog = .silent,
       clock: @escaping @Sendable () -> Date = { Date() }) {
    self.init(endpoints: OKXVenue.endpoints(policy: policy, gateways: gateways),
              transport: transport, sockets: sockets, limiter: limiter, log: log, clock: clock)
  }

  init(route: MarketRoute, transport: any HTTPTransport,
       sockets: any WSSocketFactory = URLSessionSocketFactory(),
       limiter: VenueRateLimiter, log: FeedLog = .silent,
       clock: @escaping @Sendable () -> Date = { Date() }) {
    self.init(endpoints: OKXVenue.endpoints(route), transport: transport, sockets: sockets,
              limiter: limiter, log: log, clock: clock)
  }

  init(endpoints: VenueEndpoints, transport: any HTTPTransport, sockets: any WSSocketFactory,
       limiter: VenueRateLimiter, log: FeedLog, clock: @escaping @Sendable () -> Date) {
    self.rest = VenueREST(endpoints: endpoints, transport: transport, limiter: limiter, log: log)
    self.sockets = sockets; self.clock = clock
  }

  // ------------------------------------------------------------------ 底层

  /// 发一个 GET（`VenueREST`：网关主不通换备、4xx 直接报、429 罚这一家的限速器）。
  func get(_ path: String, query: [URLQueryItem] = [], timeout: TimeInterval = 15) async throws -> Data {
    try await rest.get(path, query: query, timeout: timeout)
  }

  private var nowMs: Int64 { Int64(clock().timeIntervalSince1970 * 1000) }
  private static let swapQuery = [URLQueryItem(name: "instType", value: "SWAP")]

  // ------------------------------------------------------------------ 品种表 / 行情

  public func instruments() async throws -> [SymbolInfo] {
    let data = try await get("api/v5/public/instruments", query: Self.swapQuery, timeout: 30)
    let rows: [OKXDTO.Instrument] = try OKXDTO.rows(data, "品种表")
    let listed = rows.filter(\.isListed)
    // 逐笔推送的 `sz` 是张数：面值表随品种表一起换新（`OKXVenue.contractValues`）。
    var values: [String: Double] = [:]
    for row in listed { if let v = row.contractValue { values[row.instId.uppercased()] = v } }
    OKXVenue.contractValues.set(values)
    let list = listed.compactMap(\.symbolInfo).sorted { $0.symbol < $1.symbol }
    guard !list.isEmpty else { throw FeedError.badResponse("OKX 品种表为空") }
    return list
  }

  public func ticker24h(symbol: String, timeout: TimeInterval) async throws -> Ticker {
    let inst = OKXVenue.instID(symbol)
    let data = try await get("api/v5/market/ticker", query: [URLQueryItem(name: "instId", value: inst)], timeout: timeout)
    let rows: [OKXDTO.TickerRow] = try OKXDTO.rows(data, "行情")
    guard let ticker = rows.first?.ticker, ticker.symbol == InstrumentID.canonical(symbol) else {
      throw FeedError.badResponse("报价品种或价格无效")
    }
    return ticker
  }

  /// - Parameter timeout: 总时限（`Deadline`）：限速器排队、换主机重试都算在内。
  public func tickers24h(timeout: TimeInterval) async throws -> [Ticker] {
    let data = try await Deadline.run(seconds: timeout) {
      try await self.get("api/v5/market/tickers", query: Self.swapQuery, timeout: timeout)
    }
    // 整表里还有币本位、USDC 永续：`ticker` 只认 `BASE-USDT-SWAP`，别的给 nil。
    let rows: [OKXDTO.TickerRow] = try OKXDTO.rows(data, "全市场行情")
    let tickers = rows.compactMap(\.ticker)
    guard !tickers.isEmpty else { throw FeedError.badResponse("全市场报价为空") }
    return tickers
  }

  public func funding(symbol: String) async throws -> FundingSnapshot {
    let data = try await get("api/v5/public/funding-rate",
                             query: [URLQueryItem(name: "instId", value: OKXVenue.instID(symbol))])
    let rows: [OKXDTO.FundingRow] = try OKXDTO.rows(data, "资金费率")
    guard let snapshot = rows.first?.snapshot else { throw FeedError.badResponse("OKX 资金费率为空") }
    return snapshot
  }

  /// 全市场资金费率：kanpan-api 的整表（服务端按 `instId=ANY` 抓、缓存 30 秒；透传白名单不放行 `ANY`）。
  public func fundingAll() async throws -> [String: FundingSnapshot] {
    let data = try await api("/v1/market/funding", query: [URLQueryItem(name: "source", value: OKXVenue.id)])
    return try OKXDTO.fundingTable(data)
  }

  /// 持仓量历史：kanpan-api `/v1/market/open-interest/history?source=okx`（参数照币安 `openInterestHist`：
  /// `period` 5m…1d、`limit` ≤ 500、`endTime` 含端点；答复按时间升序、单位是币的个数）。
  /// 服务端不认 `startTime`：给了就按 `endTime`（缺省为现在）取够条数再在本地截掉更早的。
  public func openInterestHist(symbol: String, period: String, limit: Int,
                               startTime: Int64?, endTime: Int64?) async throws -> [OIPoint] {
    var query = [URLQueryItem(name: "source", value: OKXVenue.id),
                 URLQueryItem(name: "symbol", value: InstrumentID(symbol).symbol),
                 URLQueryItem(name: "period", value: period),
                 URLQueryItem(name: "limit", value: String(max(1, min(limit, Self.oiHistoryMax))))]
    if let endTime { query.append(URLQueryItem(name: "endTime", value: String(endTime))) }
    let points = try OKXDTO.openInterestHistory(try await api("/v1/market/open-interest/history", query: query),
                                                symbol: symbol)
    guard let startTime else { return points }
    return points.filter { $0.time >= startTime }
  }

  /// 问 kanpan-api 自己的 `/v1/*`（不随线路：两条线路都打 `route.apiHosts`，主在前）。
  /// 出站不排 OKX 的限速器——打的不是 OKX，服务端自己有这一家的出站节拍。
  /// 连不上 / 5xx 换下一台；4xx（周期不认、品种不认）换主机也一样，直接报。
  func api(_ path: String, query: [URLQueryItem], timeout: TimeInterval = 15) async throws -> Data {
    var failure: any Error = FeedError.badResponse("行情服务暂不可用")
    for host in route.apiHosts {
      guard var c = VenueEndpoints.origin("https", host) else { continue }
      c.path = path
      c.queryItems = query
      guard let url = c.url else { continue }
      let reply: HTTPReply
      do { reply = try await transport.get(url, timeout: timeout) }
      catch {
        if error is CancellationError || Task.isCancelled { throw CancellationError() }
        failure = error
        continue
      }
      if reply.status == 200 { return reply.body }
      let error = UpstreamError(status: reply.status, msg: VenueREST.defaultMessage(reply.body),
                                url: url.absoluteString,
                                retryAfter: UpstreamError.retryAfterSeconds(reply.header("Retry-After")),
                                proxied: true)
      if (400..<500).contains(reply.status) { throw error }
      failure = error
    }
    throw failure
  }

  // ------------------------------------------------------------------ K 线

  public func klines(symbol: String, interval: Interval, limit: Int,
                     startTime: Int64?, endTime: Int64?) async throws -> [Bar] {
    try await fetchBars(symbol: symbol, interval: capabilities.source(for: interval),
                        count: min(max(1, limit), capabilities.maxKlines),
                        startTime: startTime, endTime: endTime)
  }

  /// 源周期的 K 线，升序，不设上限（`history` 一次要翻好几页）。
  ///
  /// 从一个上界（不给就是「现在」）往前一页接一页翻，游标是 `after`（OKX：取开盘时间**早于**它的）：
  /// - 上界就是现在：`candles` 不带游标，一页 300 根——首屏就这一发；
  /// - 这一页整个落在最近 1440 根以内：还是 `candles`（一页 300 根）；
  /// - 更早：`history-candles`，一页 100 根。
  ///
  /// 给了 `startTime` 就是「从它起往后 count 根」：上界取 `startTime + (count − 1) 步`（不超过现在），
  /// 翻到 `startTime` 为止。翻页是接力的（下一页的游标是上一页最早那根），不预先按时钟切窗口：
  /// 停盘、维护留下的空档不会让窗口错位。
  func fetchBars(symbol: String, interval source: Interval, count: Int,
                 startTime: Int64?, endTime: Int64?) async throws -> [Bar] {
    guard let bar = OKXVenue.bar(source) else {
      throw FeedError.unsupported("OKX 没有 \(source.rawValue) 周期")
    }
    guard count > 0 else { return [] }
    let inst = OKXVenue.instID(symbol)
    let step = max(source.stepMs, 1)
    let now = nowMs
    // 上界（含）。nil = 到现在为止（不带游标，含正在走的那一根）。
    var upper: Int64?
    if let startTime {
      let end = startTime + Int64(count - 1) * step
      upper = end < now ? end : nil
    } else if let endTime, endTime < now {
      upper = endTime
    }
    var cursor = upper.map { $0 + 1 }
    var collected: [Bar] = []
    // 每一页至少前进一根，页数有上限：不会因为一页回得不对就无限翻下去。
    let maxRounds = count / Self.historyPage + 3
    for _ in 0..<maxRounds {
      if let startTime, let oldest = collected.first?.openTime, oldest <= startTime { break }
      let remaining: Int
      if let startTime, let cursor {
        remaining = Int(max(1, (cursor - startTime + step - 1) / step))
      } else if let startTime {
        remaining = Int(max(1, (now - startTime) / step + 1))
      } else {
        remaining = count - collected.count
      }
      guard remaining > 0 else { break }
      let recent = cursor.map { now - $0 <= Int64(Self.recentDepth - Self.recentPage - 20) * step } ?? true
      let (path, page) = recent ? ("api/v5/market/candles", Self.recentPage)
                                : ("api/v5/market/history-candles", Self.historyPage)
      let ask = min(page, remaining)
      var query = [URLQueryItem(name: "instId", value: inst), URLQueryItem(name: "bar", value: bar),
                   URLQueryItem(name: "limit", value: String(ask))]
      if let cursor { query.append(URLQueryItem(name: "after", value: String(cursor))) }
      let bound = cursor
      let reply = try OKXDTO.barsPage(try await get(path, query: query))
      let rows = reply.bars.filter { bound == nil || $0.openTime < bound! }
      guard let oldest = rows.first?.openTime else { break }
      collected = MarketSeries.dedup(rows + collected)
      cursor = oldest
      // 上游回得比要的少：翻到这只品种上线那一根了。按上游给了几行判（坏行也算），
      // 不按解出来几根判——一页里坏一行不等于到头了。
      if reply.rows < ask { break }
      if startTime == nil, collected.count >= count { break }
    }
    var bars = collected
    if let startTime { bars.removeAll { $0.openTime < startTime } }
    if let endTime { bars.removeAll { $0.openTime > endTime } }
    return startTime != nil ? Array(bars.prefix(count)) : Array(bars.suffix(count))
  }

  public func contiguousTail(symbol: String, interval: Interval, from: Int64) async throws -> [Bar] {
    let source = capabilities.source(for: interval)
    let needed = Int(max(0, (nowMs - from) / max(source.stepMs, 1)) + 2)
    guard needed <= capabilities.maxTailBars else { throw FeedError.gapTooLong }
    // 缺口一直接到现在：直接从现在往前翻到 `from`（最新一页就是一发 `candles`）。
    return try await fetchBars(symbol: symbol, interval: source, count: needed, startTime: from, endTime: nil)
  }

  public func history(symbol: String, interval: Interval, pages: Int, before firstOpen: Int64) async throws -> [Bar] {
    guard pages > 0 else { return [] }
    let bars = try await fetchBars(symbol: symbol, interval: capabilities.source(for: interval),
                                   count: pages * capabilities.maxKlines, startTime: nil, endTime: firstOpen - 1)
    return bars.filter { $0.openTime < firstOpen }
  }

  public func resetRouteCooldowns() async {}

  // ------------------------------------------------------------------ 推送

  /// 一条行情推送 = public（行情、逐笔、标记价、资金费率）+ business（K 线）两条连接，
  /// 订阅按端点分过去，事件合成一条；哪个端点分不到订阅就不连（`SplitVenueStream`）。
  public func makeStream(silenceMs: Double?, log: FeedLog) -> any MarketStream {
    let lanes = OKXVenue.Endpoint.allCases.map { endpoint in
      SplitVenueStream.Lane(
        VenueStream(wire: OKXWire(endpoint: endpoint), urls: OKXVenue.streams(endpoint, route: route),
                    factory: sockets, silenceMs: silenceMs ?? 60_000, log: log),
        accepts: { OKXWire.endpoint(of: $0) == endpoint })
    }
    return SplitVenueStream(lanes: lanes)
  }

  /// 巡检：K 线所在的那个端点能不能连上（只握手）。
  public func probeStream(symbol: String, interval: Interval) async -> Bool {
    for url in OKXVenue.streams(.business, route: route) {
      do {
        let socket = try await sockets.connect(to: url)
        await socket.cancel()
        try Task.checkCancellation()
        return true
      } catch { continue }
    }
    return false
  }
}
