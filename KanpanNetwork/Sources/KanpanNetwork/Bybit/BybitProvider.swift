import Foundation
import KanpanCore

/// Bybit USDT 线性永续（v5 公开行情），包成一个 `MarketProvider`。
///
/// 差别全写在能力位里，上层不认识「Bybit」这个名字：
///
/// - **周期**：13 档原生（1m … 1M），1y 由 1M 聚；每一档都有原生 K 线推送。
/// - **行情**：`tickers` 一行就有价、计价额、标记价、指数价、持仓量、资金费率与下次结算——整表一次（`hasBulkTickers`），
///   推送也是同一个频道（标记价与费率跟着它走）。
/// - **持仓量历史**：`/v5/market/open-interest`（最细 5 分钟，一页 200 条，翻页由这里做）；没有归档，
///   也没有多空比、主动买卖比、基差这类衍生统计。
/// - **没有**盘口五档与主动方向这一层（`hasMicrostructure = false`）；主力订单流另走 `BybitBooksAdapter`。
/// - 一页最多 1000 根，K 线与持仓量都是降序，在 `BybitDTO` 里翻平。
///
/// 两条线路：直连打 Bybit 自己的域名；网关打看盘自己的 kanpan-api（REST 原样透传、推送是中继），
/// 报文一字不差，只换地址（`BybitVenue`）。两条线路的能力位相同。
/// REST 走通用的 `VenueREST`、推送走通用的 `VenueStream` + `BybitWire`，限速是 `BybitVenue.limiter`。
public struct BybitProvider: MarketProvider {
  public static let venue = BybitVenue.id
  public static let market = BybitVenue.market
  /// K 线一次请求最多多少根（`/v5/market/kline` 的 `limit` 上限）。
  static let pageSize = 1000
  /// 持仓量历史一次请求最多多少条。
  static let oiPageSize = 200
  /// 品种表一页（linear 的上限）。
  static let instrumentsPageSize = 1000

  public static let nativeIntervals: Set<Interval> = [.m1, .m3, .m5, .m15, .m30, .h1, .h2, .h4, .h6, .h12,
                                                      .d1, .w1, .mo1]
  public static let aggregatedFrom: [Interval: Interval] = [.y1: .mo1]

  public static let capabilities = ProviderCapabilities(
    venue: venue, market: market,
    nativeIntervals: nativeIntervals, aggregatedFrom: aggregatedFrom,
    // 一页 1000 根。首屏只要 300 根：一次请求就画出来，深度交给后台加深。
    // 补缺最多四页：`contiguousTail` 先按时钟算要多少根，超过就直接报 `.gapTooLong`。
    maxKlines: pageSize, maxTailBars: 4 * pageSize, initialKlines: 300,
    liveKlineIntervals: nativeIntervals,
    hasTickerStream: true, hasMarkPrice: true, hasFunding: true,
    openInterestSource: venue, hasMicrostructure: false, hasDerivativeMetrics: false,
    hasOpenInterestHistory: true, hasOpenInterestArchive: false,
    hasBulkTickers: true, probesHistoryBoundary: false,
    quoteAssets: [BybitVenue.quote], hasOrderFlow: true)

  public var capabilities: ProviderCapabilities { Self.capabilities }
  let rest: VenueREST
  var endpoints: VenueEndpoints { rest.endpoints }
  var transport: any HTTPTransport { rest.transport }
  let sockets: any WSSocketFactory
  let clock: @Sendable () -> Date

  public init(route: MarketRoute,
              transport: any HTTPTransport = URLSessionTransport(),
              sockets: any WSSocketFactory = URLSessionSocketFactory(),
              log: FeedLog = .silent) {
    self.init(route: route, transport: transport, sockets: sockets, limiter: BybitVenue.limiter, log: log)
  }

  /// 测试用的旧写法：线路档位 + 地址表。
  public init(policy: MarketRoutePolicy, endpoints: MarketEndpoints,
              transport: any HTTPTransport = URLSessionTransport(),
              sockets: any WSSocketFactory = URLSessionSocketFactory(),
              log: FeedLog = .silent) {
    self.init(route: MarketRoute(policy: policy, endpoints: endpoints), transport: transport, sockets: sockets,
              limiter: BybitVenue.limiter, log: log)
  }

  /// 测试用：网关表同时当 kanpan-api 主机（`BybitVenue.endpoints(policy:gateways:)`）。
  init(policy: MarketRoutePolicy, gateways: [String], transport: any HTTPTransport,
       sockets: any WSSocketFactory = URLSessionSocketFactory(),
       limiter: VenueRateLimiter, log: FeedLog = .silent,
       clock: @escaping @Sendable () -> Date = { Date() }) {
    self.init(endpoints: BybitVenue.endpoints(policy: policy, gateways: gateways),
              transport: transport, sockets: sockets, limiter: limiter, log: log, clock: clock)
  }

  init(route: MarketRoute, transport: any HTTPTransport,
       sockets: any WSSocketFactory = URLSessionSocketFactory(),
       limiter: VenueRateLimiter, log: FeedLog = .silent,
       clock: @escaping @Sendable () -> Date = { Date() }) {
    self.init(endpoints: BybitVenue.endpoints(route), transport: transport, sockets: sockets,
              limiter: limiter, log: log, clock: clock)
  }

  init(endpoints: VenueEndpoints, transport: any HTTPTransport, sockets: any WSSocketFactory,
       limiter: VenueRateLimiter, log: FeedLog, clock: @escaping @Sendable () -> Date) {
    self.rest = VenueREST(endpoints: endpoints, transport: transport, limiter: limiter, log: log,
                          message: BybitDTO.errorMessage)
    self.sockets = sockets; self.clock = clock
  }

  // ------------------------------------------------------------------ 底层

  /// 发一个 GET（`VenueREST`：网关主不通换备、4xx 直接报、429 罚这一家的限速器）。
  func get(_ path: String, query: [URLQueryItem] = [], timeout: TimeInterval = 15) async throws -> Data {
    try await rest.get(path, query: query, timeout: timeout)
  }

  /// 解一份答复。HTTP 200 + `retCode 10006` 也是限流（`BybitDTO.result` 报成 429）：照 429 罚这一家的限速器再报。
  func checked<T>(_ decode: () throws -> T) async throws -> T {
    do { return try decode() }
    catch let error as UpstreamError where error.reason == .rateLimited {
      await rest.limiter.penalize(seconds: 1)
      throw error
    }
  }

  /// 拆 Bybit 的信封（见 `checked`）。
  func unwrap<R: Decodable>(_ type: R.Type, _ data: Data, what: String) async throws -> (result: R, timeMs: Int64?) {
    try await checked { try BybitDTO.result(type, data, what: what) }
  }

  private static func linear(_ more: [URLQueryItem] = []) -> [URLQueryItem] {
    [URLQueryItem(name: "category", value: BybitVenue.category)] + more
  }

  private var nowMs: Int64 { Int64(clock().timeIntervalSince1970 * 1000) }

  // ------------------------------------------------------------------ 品种表 / 行情

  /// 品种表按 `nextPageCursor` 翻页（linear 一页最多 1000 个，合约多起来会超一页）。
  public func instruments() async throws -> [SymbolInfo] {
    var rows: [BybitDTO.Instrument] = []
    var cursor: String?
    var seen = Set<String>()
    for _ in 0..<10 {
      var query = Self.linear([URLQueryItem(name: "limit", value: String(Self.instrumentsPageSize))])
      // 游标是 Bybit 发的、已经百分号编码过的一串；先解一次，交给 `URLComponents` 再编一次，
      // 线上才是原样那一串（直接塞进去会被编成 `%25…`）。
      if let cursor { query.append(URLQueryItem(name: "cursor", value: cursor.removingPercentEncoding ?? cursor)) }
      let data = try await get("v5/market/instruments-info", query: query, timeout: 30)
      let page = try await unwrap(BybitDTO.Instruments.self, data, what: "品种表").result
      rows += page.list
      guard let next = page.nextPageCursor, !next.isEmpty, seen.insert(next).inserted else { break }
      cursor = next
    }
    var bySymbol: [String: SymbolInfo] = [:]
    for row in rows where row.isListed {
      if let info = row.symbolInfo { bySymbol[info.symbol] = info }
    }
    let list = bySymbol.values.sorted { $0.symbol < $1.symbol }
    guard !list.isEmpty else { throw FeedError.badResponse("Bybit 品种表为空") }
    return list
  }

  public func ticker24h(symbol: String, timeout: TimeInterval) async throws -> Ticker {
    let (row, time) = try await tickerRow(symbol: symbol, timeout: timeout)
    guard let ticker = row.ticker(timeMs: time ?? nowMs), ticker.symbol == InstrumentID.canonical(symbol) else {
      throw FeedError.badResponse("报价品种或价格无效")
    }
    return ticker
  }

  /// 单品种那一行（行情与资金费率共用）。
  private func tickerRow(symbol: String, timeout: TimeInterval = 15) async throws -> (BybitDTO.TickerRow, timeMs: Int64?) {
    let code = BybitVenue.symbol(symbol)
    let data = try await get("v5/market/tickers", query: Self.linear([URLQueryItem(name: "symbol", value: code)]),
                             timeout: timeout)
    let (table, time) = try await unwrap(BybitDTO.Tickers.self, data, what: "行情")
    guard let row = table.list.first(where: { $0.symbol == code }) else {
      throw FeedError.badResponse("Bybit 没有 \(code) 的行情")
    }
    return (row, time)
  }

  /// 全市场整表（一次请求）。
  private func tickerTable(timeout: TimeInterval) async throws -> (rows: [BybitDTO.TickerRow], timeMs: Int64?) {
    let data = try await get("v5/market/tickers", query: Self.linear(), timeout: timeout)
    let (table, time) = try await unwrap(BybitDTO.Tickers.self, data, what: "全市场行情")
    return (table.list.filter(\.isListed), time)
  }

  /// - Parameter timeout: 总时限（`Deadline`）：限速器排队、换主机重试都算在内。
  public func tickers24h(timeout: TimeInterval) async throws -> [Ticker] {
    let (rows, time) = try await Deadline.run(seconds: timeout) { try await self.tickerTable(timeout: timeout) }
    let stamp = time ?? nowMs
    let tickers = rows.compactMap { $0.ticker(timeMs: stamp) }
    guard !tickers.isEmpty else { throw FeedError.badResponse("全市场报价为空") }
    return tickers
  }

  public func funding(symbol: String) async throws -> FundingSnapshot {
    guard let snapshot = try await tickerRow(symbol: symbol).0.funding else {
      throw FeedError.badResponse("Bybit 没有 \(BybitVenue.symbol(symbol)) 的资金费率")
    }
    return snapshot
  }

  /// 全市场资金费率：同一张 `tickers` 整表，键是完整品种 key。
  public func fundingAll() async throws -> [String: FundingSnapshot] {
    var out: [String: FundingSnapshot] = [:]
    for row in try await tickerTable(timeout: 15).rows {
      if let f = row.funding { out[BybitVenue.key(row.symbol)] = f }
    }
    return out
  }

  // ------------------------------------------------------------------ 持仓量历史

  /// 上层按币安口径一次要 500 条；Bybit 一页 200 条，这里按 `endTime` 往回翻凑够（翻不满就是到头了）。
  /// `period` 是币安的写法（5m … 1d），Bybit 没有的档取更细的一档（`BybitVenue.oiInterval`）。
  public func openInterestHist(symbol: String, period: String, limit: Int,
                               startTime: Int64?, endTime: Int64?) async throws -> [OIPoint] {
    guard let intervalTime = BybitVenue.oiInterval(period: period) else {
      throw FeedError.unsupported("Bybit 没有 \(period) 的持仓量统计")
    }
    let code = BybitVenue.symbol(symbol)
    let want = max(1, limit)
    var out: [OIPoint] = []
    var end = endTime
    while out.count < want {
      let n = min(Self.oiPageSize, want - out.count)
      var query = Self.linear([URLQueryItem(name: "symbol", value: code),
                               URLQueryItem(name: "intervalTime", value: intervalTime),
                               URLQueryItem(name: "limit", value: String(n))])
      if let startTime { query.append(URLQueryItem(name: "startTime", value: String(startTime))) }
      if let end { query.append(URLQueryItem(name: "endTime", value: String(end))) }
      let data = try await get("v5/market/open-interest", query: query)
      let page = try await checked { try BybitDTO.openInterest(data) }
      out = page + out
      guard page.count >= n, let first = page.first?.time, startTime.map({ first > $0 }) ?? true else { break }
      end = first - 1
    }
    var byTime: [Int64: OIPoint] = [:]
    for p in out where (startTime.map { p.time >= $0 } ?? true) && (endTime.map { p.time <= $0 } ?? true) {
      byTime[p.time] = p
    }
    return Array(byTime.keys.sorted().map { byTime[$0]! }.suffix(want))
  }

  // ------------------------------------------------------------------ K 线

  /// 源周期的 K 线，升序。
  public func klines(symbol: String, interval: Interval, limit: Int,
                     startTime: Int64?, endTime: Int64?) async throws -> [Bar] {
    try await fetchBars(symbol: symbol, interval: capabilities.source(for: interval),
                        count: min(max(1, limit), capabilities.maxKlines),
                        startTime: startTime, endTime: endTime)
  }

  /// 一个窗口最长覆盖多久：等距周期是 `n` 步；月线按 31 天一步算，宁可多盖、不漏一根（窗口之间首尾相接，多出来的去重）。
  static func spanMs(_ interval: Interval) -> Int64 {
    interval.isIrregular ? 31 * 86_400_000 : interval.stepMs
  }

  /// 不设上限的那一版（`history` 一次要翻好几页）。
  ///
  /// - 只要最新一屏（没有起止、不超过一页）：一次请求只带 `limit`——**首屏一发**，网关上这条是「最新」的短缓存。
  /// - 其余按时间切成首尾相接的窗口（每个窗口最多一页），并行发、限速器负责错开，不依赖上一页的结果；
  ///   窗口的终点在将来时不带 `end`（不然网关会把「最新」当成历史页缓存一分钟）。
  func fetchBars(symbol: String, interval source: Interval, count: Int,
                 startTime: Int64?, endTime: Int64?) async throws -> [Bar] {
    guard let wire = BybitVenue.interval(source) else {
      throw FeedError.unsupported("Bybit 没有 \(source.rawValue) 周期")
    }
    let code = BybitVenue.symbol(symbol)
    let now = nowMs
    let span = Self.spanMs(source)
    var windows: [(start: Int64?, end: Int64?, limit: Int)] = []
    if let startTime {
      var cursor = startTime
      var left = count
      while left > 0, cursor <= now {
        let n = min(Self.pageSize, left)
        let end = cursor + Int64(n) * span - 1
        windows.append((cursor, end >= now ? nil : end, Self.pageSize))
        cursor = end + 1; left -= n
      }
    } else if endTime == nil, count <= Self.pageSize {
      windows = [(nil, nil, count)]
    } else {
      var end = min(endTime ?? now, now)
      var left = count
      while left > 0, end > 0 {
        let n = min(Self.pageSize, left)
        let start = max(0, end - Int64(n) * span + 1)
        windows.append((start, end, Self.pageSize))
        end = start - 1; left -= n
      }
    }
    guard !windows.isEmpty else { return [] }
    let pages = try await withThrowingTaskGroup(of: [Bar].self) { group in
      for window in windows {
        group.addTask {
          var query = Self.linear([URLQueryItem(name: "symbol", value: code),
                                   URLQueryItem(name: "interval", value: wire)])
          if let s = window.start { query.append(URLQueryItem(name: "start", value: String(s))) }
          if let e = window.end { query.append(URLQueryItem(name: "end", value: String(e))) }
          query.append(URLQueryItem(name: "limit", value: String(window.limit)))
          let data = try await get("v5/market/kline", query: query)
          return try await checked { try BybitDTO.bars(data) }
        }
      }
      var all: [Bar] = []
      for try await page in group { all.append(contentsOf: page) }
      return all
    }
    var bars = MarketSeries.dedup(pages)
    if let startTime { bars.removeAll { $0.openTime < startTime } }
    if let endTime { bars.removeAll { $0.openTime > endTime } }
    return startTime != nil ? Array(bars.prefix(count)) : Array(bars.suffix(count))
  }

  public func contiguousTail(symbol: String, interval: Interval, from: Int64) async throws -> [Bar] {
    let source = capabilities.source(for: interval)
    let needed = Int(max(0, (nowMs - from) / max(source.stepMs, 1)) + 2)
    guard needed <= capabilities.maxTailBars else { throw FeedError.gapTooLong }
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

  /// 推送地址：直连是 `stream.bybit.com`（备 `stream.bytick.com`）的 linear；网关是中继 `?category=linear`。
  var streamURLs: [URL] { endpoints.streams(query: BybitVenue.categoryQuery(BybitVenue.category)) }

  public func makeStream(silenceMs: Double?, log: FeedLog) -> any MarketStream {
    VenueStream(wire: BybitWire(), urls: streamURLs, factory: sockets, silenceMs: silenceMs ?? 60_000, log: log)
  }

  public func probeStream(symbol: String, interval: Interval) async -> Bool {
    for url in streamURLs {
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
