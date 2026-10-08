import Foundation
import KanpanCore

/// Coinbase 现货（Advanced Trade 公开行情），包成一个 `MarketProvider`。
///
/// 和币安那一支比，差别全写在能力位里，上层不认识「Coinbase」这个名字：
///
/// - **周期**：原生只有 9 档；3m←1m、12h←6h、1w/1M/1y←1d 由上层聚。
/// - **末根实时**：只有 5m 有 `candles` 推送，其它周期订 `market_trades` 在本地拼末根，
///   外加 `MarketFeed` 的定时 REST 对表。
/// - **没有**标记价、资金费率、持仓量、盘口与主动方向、衍生统计——六格里那几格写「—」，
///   持仓量副图不给。
/// - 一页最多 350 根（起止都含），数值是字符串、时间是秒、顺序是降序，都在
///   `CoinbaseDTO` 里翻平。
///
/// 两条线路：直连打 Coinbase 自己的域名；网关打看盘自己的 `kanpan-api`（REST 原样透传、
/// 推送是共享 hub），报文一字不差，只换地址（`CoinbaseVenue`）。两条线路的能力位相同。
/// REST 走通用的 `VenueREST`、推送走通用的 `VenueStream` + `CoinbaseWire`，限速是 `CoinbaseVenue.limiter`。
public struct CoinbaseProvider: MarketProvider {
  public static let venue = CoinbaseVenue.id
  public static let market = CoinbaseVenue.market
  /// 一次请求最多多少根（Coinbase 起止都含，跨度要小于 350 步）。
  static let pageSize = 350

  public static let nativeIntervals: Set<Interval> = [.m1, .m5, .m15, .m30, .h1, .h2, .h4, .h6, .d1]
  /// 1y 也直接从日线聚：1M 本身就是聚出来的，源周期只能是原生的那几档。
  public static let aggregatedFrom: [Interval: Interval] = [.m3: .m1, .h12: .h6, .w1: .d1, .mo1: .d1, .y1: .d1]

  public static let capabilities = ProviderCapabilities(
    venue: venue, market: market, upstream: venue,
    nativeIntervals: nativeIntervals, aggregatedFrom: aggregatedFrom,
    // 四页（4 × 350）。首屏只要一页：一次请求就画出来，深度交给后台加深。
    // 补缺也是这四页：`contiguousTail` 先按时钟算要多少根，超过就直接报 `.gapTooLong`。
    maxKlines: 4 * pageSize, maxTailBars: 4 * pageSize, initialKlines: 300,
    liveKlineIntervals: [.m5],
    hasTickerStream: true, hasMarkPrice: false, hasFunding: false,
    openInterestSource: nil, hasMicrostructure: false, hasDerivativeMetrics: false,
    // 品种表那一个请求（`products`）就带着全部品种的 24h 行情。
    hasBulkTickers: true, probesHistoryBoundary: false, snapshotNamespace: nil,
    quoteAssets: [CoinbaseVenue.quote])

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
    self.init(route: route, transport: transport, sockets: sockets, limiter: CoinbaseVenue.limiter, log: log)
  }

  /// 测试用的旧写法：线路档位 + 地址表。
  public init(policy: MarketRoutePolicy, endpoints: MarketEndpoints,
              transport: any HTTPTransport = URLSessionTransport(),
              sockets: any WSSocketFactory = URLSessionSocketFactory(),
              log: FeedLog = .silent) {
    self.init(route: MarketRoute(policy: policy, endpoints: endpoints), transport: transport, sockets: sockets,
              limiter: CoinbaseVenue.limiter, log: log)
  }

  /// 测试用：网关表同时当 kanpan-api 主机（`CoinbaseVenue.endpoints(policy:gateways:)`）。
  init(policy: MarketRoutePolicy, gateways: [String], transport: any HTTPTransport,
       sockets: any WSSocketFactory = URLSessionSocketFactory(),
       limiter: VenueRateLimiter, log: FeedLog = .silent,
       clock: @escaping @Sendable () -> Date = { Date() }) {
    self.init(endpoints: CoinbaseVenue.endpoints(policy: policy, gateways: gateways),
              transport: transport, sockets: sockets, limiter: limiter, log: log, clock: clock)
  }

  init(route: MarketRoute, transport: any HTTPTransport,
       sockets: any WSSocketFactory = URLSessionSocketFactory(),
       limiter: VenueRateLimiter, log: FeedLog = .silent,
       clock: @escaping @Sendable () -> Date = { Date() }) {
    self.init(endpoints: CoinbaseVenue.endpoints(route), transport: transport, sockets: sockets,
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

  private func productsQuery() -> [URLQueryItem] { [URLQueryItem(name: "product_type", value: "SPOT")] }

  // ------------------------------------------------------------------ 品种表 / 行情

  public func instruments() async throws -> [SymbolInfo] {
    let data = try await get("products", query: productsQuery(), timeout: 30)
    let rows = try Self.products(data)
    let list = rows.filter(\.isListed).compactMap(\.symbolInfo).sorted { $0.symbol < $1.symbol }
    guard !list.isEmpty else { throw FeedError.badResponse("Coinbase 品种表为空") }
    return list
  }

  static func products(_ data: Data) throws -> [CoinbaseDTO.Product] {
    do { return try JSONDecoder().decode(CoinbaseDTO.Products.self, from: data).products }
    catch { throw FeedError.badResponse("解不开 Coinbase 品种表：\(error)") }
  }

  public func ticker24h(symbol: String, timeout: TimeInterval) async throws -> Ticker {
    let id = CoinbaseVenue.productID(symbol)
    let data = try await get("products/\(id)", timeout: timeout)
    let product: CoinbaseDTO.Product
    do { product = try JSONDecoder().decode(CoinbaseDTO.Product.self, from: data) }
    catch { throw FeedError.badResponse("解不开 Coinbase 行情：\(error)") }
    guard var ticker = product.ticker, ticker.symbol == InstrumentID.canonical(symbol) else {
      throw FeedError.badResponse("报价品种或价格无效")
    }
    ticker.timeMs = Int64(clock().timeIntervalSince1970 * 1000)
    return ticker
  }

  /// - Parameter timeout: 总时限（`Deadline`）：限速器排队、换主机重试都算在内。
  public func tickers24h(timeout: TimeInterval) async throws -> [Ticker] {
    let query = productsQuery()
    let data = try await Deadline.run(seconds: timeout) {
      try await self.get("products", query: query, timeout: timeout)
    }
    let now = Int64(clock().timeIntervalSince1970 * 1000)
    let tickers = try Self.products(data).filter(\.isListed).compactMap { p -> Ticker? in
      guard var t = p.ticker else { return nil }
      t.timeMs = now
      return t
    }
    guard !tickers.isEmpty else { throw FeedError.badResponse("全市场报价为空") }
    return tickers
  }

  // ------------------------------------------------------------------ K 线

  /// 源周期的 K 线，升序。`limit` 超过一页就按固定窗口并行翻页（窗口是算出来的，
  /// 不依赖上一页的结果，限速器负责把它们错开）。
  public func klines(symbol: String, interval: Interval, limit: Int,
                     startTime: Int64?, endTime: Int64?) async throws -> [Bar] {
    try await fetchBars(symbol: symbol, interval: capabilities.source(for: interval),
                        count: min(max(1, limit), capabilities.maxKlines),
                        startTime: startTime, endTime: endTime)
  }

  /// 不设上限的那一版（`history` 一次要翻好几页）。
  func fetchBars(symbol: String, interval source: Interval, count: Int,
                 startTime: Int64?, endTime: Int64?) async throws -> [Bar] {
    guard let granularity = CoinbaseVenue.granularity(source) else {
      throw FeedError.unsupported("Coinbase 没有 \(source.rawValue) 周期")
    }
    let id = CoinbaseVenue.productID(symbol)
    let step = source.stepMs / 1000
    let nowSec = Int64(clock().timeIntervalSince1970)
    // 每个窗口 = [start, end]（秒，两端都含），最多 `pageSize` 根。
    var windows: [(Int64, Int64)] = []
    if let startTime {
      var cursor = Self.floor(startTime / 1000, step)
      var left = count
      while left > 0, cursor <= nowSec {
        let n = Int64(min(Self.pageSize, left))
        windows.append((cursor, cursor + (n - 1) * step))
        cursor += n * step; left -= Int(n)
      }
    } else {
      var end = Self.floor(min(endTime.map { $0 / 1000 } ?? nowSec, nowSec), step)
      var left = count
      while left > 0, end > 0 {
        let n = Int64(min(Self.pageSize, left))
        windows.append((max(0, end - (n - 1) * step), end))
        end -= n * step; left -= Int(n)
      }
    }
    guard !windows.isEmpty else { return [] }
    let pages = try await withThrowingTaskGroup(of: [Bar].self) { group in
      for (start, end) in windows {
        group.addTask {
          let data = try await get("products/\(id)/candles", query: [
            URLQueryItem(name: "granularity", value: granularity),
            URLQueryItem(name: "start", value: String(start)),
            URLQueryItem(name: "end", value: String(end)),
          ])
          return try CoinbaseDTO.bars(data)
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

  static func floor(_ t: Int64, _ step: Int64) -> Int64 { step > 0 ? t - ((t % step) + step) % step : t }

  public func contiguousTail(symbol: String, interval: Interval, from: Int64) async throws -> [Bar] {
    let source = capabilities.source(for: interval)
    let now = Int64(clock().timeIntervalSince1970 * 1000)
    let needed = Int(max(0, (now - from) / max(source.stepMs, 1)) + 2)
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

  /// 小组件补价（深度审查 E-10）：自选里的 Coinbase 现货从前没有补价方式，app 不回前台就永远停在
  /// 快照那口价上。直连打 Coinbase 公开行情；网关打 `/v1/market/raw/*?source=coinbase` 原样透传，
  /// 两条线路载荷同形，所以不包信封。收盘价按起止时刻取最近 24 根 1 小时（`{start}` / `{end}`）。
  public var widgetRefresh: WidgetSnapshot.Refresh? {
    let hosts = endpoints.restHosts
    guard !hosts.isEmpty else { return nil }
    return WidgetSnapshot.Refresh(market: "\(capabilities.venue)/\(capabilities.market)", hosts: hosts,
                                  ticker: endpoints.restTemplate("products/{symbol}"),
                                  closes: endpoints.restTemplate("products/{symbol}/candles",
                                                                 query: "granularity=ONE_HOUR&start={start}&end={end}"),
                                  format: .coinbase)
  }

  // ------------------------------------------------------------------ 推送

  public func makeStream(silenceMs: Double?, log: FeedLog) -> any MarketStream {
    VenueStream(wire: CoinbaseWire(), urls: endpoints.streams, factory: sockets,
                silenceMs: silenceMs ?? 60_000, log: log)
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
