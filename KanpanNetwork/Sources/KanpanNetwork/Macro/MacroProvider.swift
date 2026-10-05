import Foundation
import KanpanCore

/// 美元指数（DXY），包成一个 `MarketProvider`，当作一只普通品种：能搜、能加自选、
/// 能看完整的行情页、能建价格提醒、能当对比品种。
///
/// **数据只有一个来源：看盘自己的 `kanpan-api`**（`/v1/market/raw/*?source=macro`、
/// `/v1/market/stream?source=macro`）。直连、网关两条线路都打它（`MacroEndpoints`），
/// 不掺任何交易所的数。报文是币安形状，K 线直接用币安那份 `KlineRow` 解。
///
/// 和两家交易所比，差别全写在能力位里，上层不认识这个名字：
///
/// - **周期**：14 档全是服务端给好的（它从 1m / 5m / 1h / 1d 聚），末根 14 档都有推送，
///   不用逐笔拼、不用定时 REST 对表。
/// - **休市**：每天 17–18 点（美东）与周末没有 K 线，图上就空着；行情帧与心跳带着
///   `marketState`，休市时 `Ticker.marketClosed = true`，价格走「停住的价」那条路变灰。
/// - **没有**成交额、标记价、资金费率、持仓量、盘口、衍生统计、主力订单流——
///   头部六格写「—」，那几个副图与订单流那一层干脆不给。
/// - 涨跌相对**上一交易日收盘**（服务端算好的 `priceChangePercent`）。
/// - 一页最多 1500 根，翻到头回 `[]`。
public struct MacroProvider: MarketProvider {
  public static let venue = MacroDTO.venue
  public static let market = MacroDTO.market
  static let pageSize = 1500

  public static let capabilities = ProviderCapabilities(
    venue: venue, market: market, upstream: venue,
    nativeIntervals: Set(Interval.allCases), aggregatedFrom: [:],
    // 四页（4 × 1500）。首屏只要一页里的 300 根，深度交给后台加深。
    maxKlines: 4 * pageSize, maxTailBars: 4 * pageSize, initialKlines: 300,
    liveKlineIntervals: Set(Interval.allCases),
    hasTickerStream: true, hasMarkPrice: false, hasFunding: false,
    openInterestSource: nil, hasMicrostructure: false, hasDerivativeMetrics: false,
    // 不带 symbol 的 `ticker/24hr` 一次回全部（就一只）。
    hasBulkTickers: true, probesHistoryBoundary: false, snapshotNamespace: nil,
    quoteAssets: [], hasOrderFlow: false)

  public var capabilities: ProviderCapabilities { Self.capabilities }
  /// 服务端不通时品种表用的那一行（离线也能搜、能加自选）。
  public static var builtinInstruments: [SymbolInfo] { [MacroDTO.builtin] }

  let endpoints: MacroEndpoints
  let transport: any HTTPTransport
  let sockets: any WSSocketFactory
  let limiter: MacroRateLimiter
  let log: FeedLog

  public init(route: MarketRoute,
              transport: any HTTPTransport = URLSessionTransport(),
              sockets: any WSSocketFactory = URLSessionSocketFactory(),
              log: FeedLog = .silent) {
    self.init(route: route, transport: transport, sockets: sockets, limiter: .shared, log: log)
  }

  init(route: MarketRoute, transport: any HTTPTransport,
       sockets: any WSSocketFactory = URLSessionSocketFactory(),
       limiter: MacroRateLimiter, log: FeedLog = .silent) {
    self.endpoints = MacroEndpoints(route: route)
    self.transport = transport; self.sockets = sockets
    self.limiter = limiter; self.log = log
  }

  // ------------------------------------------------------------------ 底层

  /// 发一个 GET。主机不通（连不上 / 5xx，含 `503 not_ready`）换下一台、都不行就抛最后那个错；
  /// 4xx 是这一笔本身的问题（代号、周期、参数不对），换主机也一样，直接报。
  func get(_ path: String, query: [URLQueryItem] = [], timeout: TimeInterval = 15) async throws -> Data {
    let hosts = endpoints.hosts
    guard !hosts.isEmpty else { throw FeedError.badResponse("行情暂不可用，请重试") }
    var failure: any Error = FeedError.badResponse("行情暂不可用，请重试")
    for host in hosts {
      guard let url = endpoints.rest(path, query: query, host: host) else { continue }
      var attempt = 0
      while true {
        attempt += 1
        try await limiter.acquire()
        let reply: HTTPReply
        do { reply = try await transport.get(url, timeout: timeout) }
        catch {
          if error is CancellationError || Task.isCancelled { throw CancellationError() }
          log("GET \(url.path) 失败：\(error)")
          failure = error
          break
        }
        log("GET \(url.path)\(url.query.map { "?\($0)" } ?? "") → \(reply.status) \(reply.body.count)B")
        if reply.status == 200 { return reply.body }
        let retry = UpstreamError.retryAfterSeconds(reply.header("Retry-After"))
        let error = UpstreamError(status: reply.status, msg: MacroDTO.errorCode(reply.body),
                                  url: url.absoluteString, retryAfter: retry, proxied: true)
        if reply.status == 429 {
          await limiter.penalize(seconds: retry ?? 1)
          failure = error
          if attempt < 3 { continue }
          throw error
        }
        if (400..<500).contains(reply.status) { throw error }
        failure = error
        break
      }
    }
    throw failure
  }

  // ------------------------------------------------------------------ 品种表 / 行情

  /// 取不到（服务端不通、表是空的）就给内置的那一行：这只的身份是写死的，
  /// 不能因为服务端一时不通就搜不到、加不了自选。
  public func instruments() async throws -> [SymbolInfo] {
    do {
      let list = try MacroDTO.instruments(try await get("instruments", timeout: 30))
      return list.isEmpty ? Self.builtinInstruments : list
    } catch {
      if error is CancellationError || Task.isCancelled { throw CancellationError() }
      log("美元指数品种表取不到，用内置那一行：\(error)")
      return Self.builtinInstruments
    }
  }

  public func ticker24h(symbol: String, timeout: TimeInterval) async throws -> Ticker {
    let data = try await get("ticker/24hr", query: [URLQueryItem(name: "symbol", value: MacroDTO.wireSymbol(symbol))],
                             timeout: timeout)
    let ticker = try MacroDTO.restTicker(data)
    guard ticker.symbol == InstrumentID.canonical(symbol) else { throw FeedError.badResponse("报价品种或价格无效") }
    return ticker
  }

  public func tickers24h(timeout: TimeInterval) async throws -> [Ticker] {
    let data = try await Deadline.run(seconds: timeout) { try await self.get("ticker/24hr", timeout: timeout) }
    let tickers = try MacroDTO.restTickers(data)
    guard !tickers.isEmpty else { throw FeedError.badResponse("全市场报价为空") }
    return tickers
  }

  // ------------------------------------------------------------------ K 线

  public func klines(symbol: String, interval: Interval, limit: Int,
                     startTime: Int64?, endTime: Int64?) async throws -> [Bar] {
    try await fetchBars(symbol: symbol, interval: interval, count: min(max(1, limit), capabilities.maxKlines),
                        startTime: startTime, endTime: endTime)
  }

  /// 按币安的语义翻页：给了 `startTime` 往后数、否则从 `endTime`（缺省现在）往前数。
  /// 休市段没有 K 线，所以页与页之间只能顺着上一页的头 / 尾接，不能按时钟算窗口。
  /// 一页没取满就是到头了（往后到了现在、往前到了历史开头）。
  func fetchBars(symbol: String, interval: Interval, count: Int,
                 startTime: Int64?, endTime: Int64?) async throws -> [Bar] {
    let wire = MacroDTO.wireSymbol(symbol)
    func page(limit: Int, start: Int64?, end: Int64?) async throws -> [Bar] {
      var query = [URLQueryItem(name: "symbol", value: wire),
                   URLQueryItem(name: "interval", value: interval.rawValue),
                   URLQueryItem(name: "limit", value: String(limit))]
      if let start { query.append(URLQueryItem(name: "startTime", value: String(start))) }
      if let end { query.append(URLQueryItem(name: "endTime", value: String(end))) }
      return try MacroDTO.bars(try await get("klines", query: query))
    }
    var chunks: [[Bar]] = []
    var got = 0
    if let startTime {
      var cursor = startTime
      while got < count {
        let n = min(Self.pageSize, count - got)
        let bars = try await page(limit: n, start: cursor, end: endTime)
        chunks.append(bars); got += bars.count
        guard bars.count >= n, let last = bars.last, last.openTime >= cursor else { break }
        cursor = last.openTime + 1
      }
    } else {
      var end = endTime
      while got < count {
        let n = min(Self.pageSize, count - got)
        let bars = try await page(limit: n, start: nil, end: end)
        chunks.insert(bars, at: 0); got += bars.count
        guard bars.count >= n, let first = bars.first else { break }
        end = first.openTime - 1
      }
    }
    var bars = MarketSeries.dedup(chunks.flatMap { $0 })
    if let startTime { bars.removeAll { $0.openTime < startTime } }
    if let endTime { bars.removeAll { $0.openTime > endTime } }
    return startTime != nil ? Array(bars.prefix(count)) : Array(bars.suffix(count))
  }

  /// 接缺口：从 `from` 往后取到现在。休市段没有 K 线，按「最多四页」兜住，
  /// 取满四页还没到现在就报 `.gapTooLong`（上层整段重拉一屏）。
  public func contiguousTail(symbol: String, interval: Interval, from: Int64) async throws -> [Bar] {
    let needed = Int(max(0, (Int64(Date().timeIntervalSince1970 * 1000) - from) / max(interval.stepMs, 1)) + 2)
    let count = min(needed, capabilities.maxTailBars)
    let bars = try await fetchBars(symbol: symbol, interval: interval, count: count, startTime: from, endTime: nil)
    // 按时钟要的根数超过上限、而且真取满了上限：中间还有没取到的，接不上。
    if needed > capabilities.maxTailBars, bars.count >= capabilities.maxTailBars { throw FeedError.gapTooLong }
    return bars
  }

  public func history(symbol: String, interval: Interval, pages: Int, before firstOpen: Int64) async throws -> [Bar] {
    guard pages > 0 else { return [] }
    let bars = try await fetchBars(symbol: symbol, interval: interval, count: pages * capabilities.maxKlines,
                                   startTime: nil, endTime: firstOpen - 1)
    return bars.filter { $0.openTime < firstOpen }
  }

  public func resetRouteCooldowns() async {}

  /// 小组件补价：载荷是币安形状（`ticker/24hr` 对象 + `klines` 数组），直接回载荷、不包信封。
  public var widgetRefresh: WidgetSnapshot.Refresh? {
    let hosts = endpoints.hosts
    guard !hosts.isEmpty else { return nil }
    let prefix = MacroEndpoints.restPrefix, source = "source=\(MacroEndpoints.source)"
    return WidgetSnapshot.Refresh(market: "\(capabilities.venue)/\(capabilities.market)", hosts: hosts,
                                  ticker: prefix + "ticker/24hr?" + source + "&symbol={symbol}",
                                  closes: prefix + "klines?" + source + "&symbol={symbol}&interval=1h&limit={limit}",
                                  format: .binance)
  }

  // ------------------------------------------------------------------ 推送

  public func makeStream(silenceMs: Double?, log: FeedLog) -> any MarketStream {
    MacroWS(urls: endpoints.streams, factory: sockets, silenceMs: silenceMs ?? 60_000, log: log)
  }

  public func probeStream(symbol: String, interval: Interval) async -> Bool {
    for url in endpoints.streams {
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
