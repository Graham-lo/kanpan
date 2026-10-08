import Foundation
import KanpanCore

/// Hyperliquid 永续（USDC 保证金，看盘里按 U 本位永续记），包成一个 `MarketProvider`。
///
/// 和币安那一支比，差别全写在能力位里，上层不认识「Hyperliquid」这个名字：
///
/// - **全部 REST 是 `POST /info`**（`VenueREST.post`），正文按 `type` 区分。
/// - **周期**：原生 12 档；6h ← 2h、1y ← 1M 由上层聚。全部原生档都有 `candle` 推送。
/// - **K 线只给最近 5000 根**（官方文档 `candleSnapshot`），一页就是全部；更早的翻不到，`history` 到头就是空。
/// - **全市场一次**：`metaAndAssetCtxs` 一个请求就是全部品种的价、额、标记价、持仓量、费率（`hasBulkTickers`）。
///   单品种也只能从它取（没有单品种的 REST 行情）。没有 24h 最高 / 最低。
/// - **资金费率每小时一期**：费率是一小时的，下一次结算是下一个整点。
/// - **没有**持仓量历史、多空比、主动买卖比、基差、五档与主动方向。当前持仓量走服务端
///   `/v1/market/open-interest?source=hyperliquid`（`openInterestSource`）。
///
/// 两条线路：直连打 `api.hyperliquid.xyz`；网关打看盘自己的 kanpan-api（`/v1/market/raw/info?source=hyperliquid`
/// 白名单透传、推送是中继），报文一字不差，只换地址（`HyperliquidVenue`）。两条线路的能力位相同。
/// 限速按官方的**权重**记（`HyperliquidVenue.Weight`：`meta` / `metaAndAssetCtxs` 20、`candleSnapshot` 20 + 每 60 根 1），
/// 每条线路一把（`HyperliquidVenue.limiter(route)`），每分钟 1000 权重。
public struct HyperliquidProvider: MarketProvider {
  public static let venue = HyperliquidVenue.id
  public static let market = HyperliquidVenue.market
  /// 一次 `candleSnapshot` 最多多少根（也是交易所留着的全部）。
  static let pageSize = 5000

  public static let nativeIntervals: Set<Interval> = [.m1, .m3, .m5, .m15, .m30, .h1, .h2, .h4, .h12, .d1, .w1, .mo1]
  public static let aggregatedFrom: [Interval: Interval] = [.h6: .h2, .y1: .mo1]

  public static let capabilities = ProviderCapabilities(
    venue: venue, market: market, upstream: venue,
    nativeIntervals: nativeIntervals, aggregatedFrom: aggregatedFrom,
    // 一页 5000 根，交易所也只留这么多。首屏只要 300：一次请求就画出来，深度交给后台加深。
    maxKlines: pageSize, maxTailBars: pageSize, initialKlines: 300,
    liveKlineIntervals: nativeIntervals,
    // 费率每小时一期（`funding` 字段就是一小时的费率，下一次结算 = 下一个整点），不是别家的八小时。
    hasTickerStream: true, hasMarkPrice: true, hasFunding: true,
    fundingPeriod: TimeInterval(HyperliquidVenue.fundingIntervalMs) / 1000,
    openInterestSource: venue, hasMicrostructure: false, hasDerivativeMetrics: false,
    hasOpenInterestHistory: false, hasOpenInterestArchive: false,
    hasBulkTickers: true, probesHistoryBoundary: false, snapshotNamespace: nil,
    quoteAssets: [HyperliquidVenue.quote])

  public var capabilities: ProviderCapabilities { Self.capabilities }
  let rest: VenueREST
  var endpoints: VenueEndpoints { rest.endpoints }
  var transport: any HTTPTransport { rest.transport }
  let sockets: any WSSocketFactory
  let clock: @Sendable () -> Date
  /// 「大写 → 原名」表。app 里是进程共用的那一张（`HyperliquidVenue.names`），测试给自己的。
  let names: HyperliquidNames

  public init(route: MarketRoute,
              transport: any HTTPTransport = URLSessionTransport(),
              sockets: any WSSocketFactory = URLSessionSocketFactory(),
              log: FeedLog = .silent) {
    self.init(endpoints: HyperliquidVenue.endpoints(route), transport: transport, sockets: sockets,
              limiter: HyperliquidVenue.limiter(route), log: log, clock: { Date() }, names: HyperliquidVenue.names)
  }

  /// 测试用：网关表同时当 kanpan-api 主机（`HyperliquidVenue.endpoints(policy:gateways:)`）。
  init(policy: MarketRoutePolicy, gateways: [String], transport: any HTTPTransport,
       sockets: any WSSocketFactory = URLSessionSocketFactory(),
       limiter: VenueRateLimiter, log: FeedLog = .silent,
       clock: @escaping @Sendable () -> Date = { Date() }, names: HyperliquidNames = HyperliquidNames()) {
    self.init(endpoints: HyperliquidVenue.endpoints(policy: policy, gateways: gateways),
              transport: transport, sockets: sockets, limiter: limiter, log: log, clock: clock, names: names)
  }

  init(endpoints: VenueEndpoints, transport: any HTTPTransport, sockets: any WSSocketFactory,
       limiter: VenueRateLimiter, log: FeedLog, clock: @escaping @Sendable () -> Date, names: HyperliquidNames) {
    self.rest = VenueREST(endpoints: endpoints, transport: transport, limiter: limiter, log: log,
                          message: Self.errorMessage)
    self.sockets = sockets; self.clock = clock; self.names = names
  }

  /// Hyperliquid 的错误体常常是一句纯文本（`Failed to deserialize the JSON body…`），不是 JSON。
  static let errorMessage: @Sendable (Data) -> String? = { body in
    if let m = VenueREST.defaultMessage(body) { return m }
    let text = String(decoding: body.prefix(200), as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
    return text.isEmpty ? nil : text
  }

  private var nowMs: Int64 { Int64(clock().timeIntervalSince1970 * 1000) }

  // ------------------------------------------------------------------ 底层

  /// 发一个 `info` 查询（`VenueREST.post`：网关主不通换备、4xx 直接报、429 罚这一家的限速器）。
  /// `weight` 是官方给这类查询记的权重（`HyperliquidVenue.Weight`），在按权重的限速器上排队。
  /// 正文按键排序：同一个查询每次一字不差，网关的答案缓存才认得出来。
  func info(_ body: [String: Any], weight: Double = HyperliquidVenue.Weight.info,
            timeout: TimeInterval = 15) async throws -> Data {
    let data = try JSONSerialization.data(withJSONObject: body, options: [.sortedKeys])
    return try await rest.post(HyperliquidVenue.infoPath, json: data, weight: weight, timeout: timeout)
  }

  /// 品种键 → 上游原名。`KPEPE` 这类 `K` 开头、表又还没拉过的，先拉一次品种表（整个进程一次）；别的不多发。
  func coin(_ key: String) async -> String {
    if HyperliquidVenue.needsNames(key, names: names) { _ = try? await meta(timeout: 15) }
    return HyperliquidVenue.coin(key, names: names)
  }

  /// 品种表，顺手记下原名表。大写后撞名、输掉的那只（`KAITO` 在时的 `kAITO`）不列：它没有自己的键，
  /// 列出来就是两只同键的品种，后到的那只（价差一千倍）会顶掉真的那只。
  @discardableResult
  private func meta(timeout: TimeInterval) async throws -> [HyperliquidDTO.Asset] {
    let assets = try HyperliquidDTO.meta(try await info(["type": "meta"], timeout: timeout))
    names.record(assets.map(\.name))
    return assets.filter { names.owns($0.name) }
  }

  /// 全市场上下文一次拿回，顺手记下原名表。撞名输掉的那只同样不列（见 `meta`）。
  private func contexts(timeout: TimeInterval) async throws -> [(asset: HyperliquidDTO.Asset, ctx: HyperliquidDTO.Ctx)] {
    let rows = try HyperliquidDTO.metaAndCtxs(try await info(["type": "metaAndAssetCtxs"], timeout: timeout))
    names.record(rows.map(\.asset.name))
    return rows.filter { names.owns($0.asset.name) }
  }

  // ------------------------------------------------------------------ 品种表 / 行情

  public func instruments() async throws -> [SymbolInfo] {
    let list = try await meta(timeout: 30).filter { !$0.isDelisted }.map(\.symbolInfo).sorted { $0.symbol < $1.symbol }
    guard !list.isEmpty else { throw FeedError.badResponse("Hyperliquid 品种表为空") }
    return list
  }

  /// 单品种也只能从全市场那一份里挑（Hyperliquid 没有单品种的 REST 行情）。
  public func ticker24h(symbol: String, timeout: TimeInterval) async throws -> Ticker {
    let want = InstrumentID.canonical(symbol)
    let now = nowMs
    let rows = try await Deadline.run(seconds: timeout) { try await self.contexts(timeout: timeout) }
    guard let row = rows.first(where: { HyperliquidVenue.key($0.asset.name) == want }),
          let ticker = HyperliquidDTO.ticker(coin: row.asset.name, ctx: row.ctx, timeMs: now) else {
      throw FeedError.badResponse("报价品种或价格无效")
    }
    return ticker
  }

  /// - Parameter timeout: 总时限（`Deadline`）：限速器排队、换主机重试都算在内。
  public func tickers24h(timeout: TimeInterval) async throws -> [Ticker] {
    let now = nowMs
    let rows = try await Deadline.run(seconds: timeout) { try await self.contexts(timeout: timeout) }
    let tickers = rows.filter { !$0.asset.isDelisted }.compactMap {
      HyperliquidDTO.ticker(coin: $0.asset.name, ctx: $0.ctx, timeMs: now)
    }
    guard !tickers.isEmpty else { throw FeedError.badResponse("全市场报价为空") }
    return tickers
  }

  /// 资金费率：一小时一期，下一次结算是下一个整点（`FundingSnapshot` 没有间隔字段，`rate` 就是一小时的费率）。
  public func funding(symbol: String) async throws -> FundingSnapshot {
    let want = InstrumentID.canonical(symbol)
    let now = nowMs
    guard let row = try await contexts(timeout: 15).first(where: { HyperliquidVenue.key($0.asset.name) == want }),
          let snapshot = HyperliquidDTO.funding(row.ctx, nowMs: now) else {
      throw FeedError.badResponse("Hyperliquid 没有 \(InstrumentID(symbol).symbol) 的资金费率")
    }
    return snapshot
  }

  public func fundingAll() async throws -> [String: FundingSnapshot] {
    let now = nowMs
    var out: [String: FundingSnapshot] = [:]
    for row in try await contexts(timeout: 15) where !row.asset.isDelisted {
      if let s = HyperliquidDTO.funding(row.ctx, nowMs: now) { out[HyperliquidVenue.key(row.asset.name)] = s }
    }
    guard !out.isEmpty else { throw FeedError.badResponse("Hyperliquid 资金费率为空") }
    return out
  }

  // ------------------------------------------------------------------ K 线

  /// 源周期的 K 线，升序。`limit` ≤ 5000 就是一个请求。
  public func klines(symbol: String, interval: Interval, limit: Int,
                     startTime: Int64?, endTime: Int64?) async throws -> [Bar] {
    try await fetchBars(symbol: symbol, interval: capabilities.source(for: interval),
                        count: min(max(1, limit), capabilities.maxKlines),
                        startTime: startTime, endTime: endTime)
  }

  /// 一根 K 线的宽度：月线按 31 天估（窗口宁宽勿窄，多出来的按根数裁掉）。
  static func width(_ interval: Interval) -> Int64 { interval == .mo1 ? 31 * 86_400_000 : interval.stepMs }

  /// 不设上限的那一版（`history` 一次要好几页）。
  ///
  /// 窗口是算出来的（不依赖上一页），每个窗口最多 5000 根：`[start, start + n × 宽 − 1]` 里不管 K 线怎么对齐，
  /// 恰好有 n 根的开盘时刻——所以不用猜交易所的周线从星期几开始。整个窗口都早于「最近 5000 根」的不发。
  func fetchBars(symbol: String, interval source: Interval, count: Int,
                 startTime: Int64?, endTime: Int64?) async throws -> [Bar] {
    guard let name = HyperliquidVenue.interval(source) else {
      throw FeedError.unsupported("Hyperliquid 没有 \(source.rawValue) 周期")
    }
    let coin = await coin(symbol)
    let width = Self.width(source)
    let now = nowMs
    let earliest = now - Int64(Self.pageSize + 1) * width
    var windows: [(start: Int64, end: Int64, bars: Int)] = []
    if let startTime {
      var cursor = max(0, startTime), left = count
      while left > 0, cursor <= now {
        let n = Int64(min(Self.pageSize, left))
        let end = cursor + n * width - 1
        if end >= earliest { windows.append((cursor, min(end, now), Int(n))) }
        cursor = end + 1; left -= Int(n)
      }
    } else {
      var end = min(endTime ?? now, now), left = count
      while left > 0, end >= 0, end >= earliest {
        let n = Int64(min(Self.pageSize, left))
        let start = max(0, end - n * width + 1)
        windows.append((start, end, Int(n)))
        end = start - 1; left -= Int(n)
      }
    }
    guard !windows.isEmpty else { return [] }
    let pages = try await withThrowingTaskGroup(of: [Bar].self) { group in
      for (start, end, n) in windows {
        group.addTask {
          // 月线窗口按 31 天一根估，最多多出一根：权重照窗口根数 + 1 记，宁多勿少。
          let weight = HyperliquidVenue.Weight.candles(source == .mo1 ? n + 1 : n)
          let data = try await info(["type": "candleSnapshot",
                                     "req": ["coin": coin, "interval": name, "startTime": start, "endTime": end]],
                                    weight: weight)
          return try HyperliquidDTO.bars(data)
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

  public func makeStream(silenceMs: Double?, log: FeedLog) -> any MarketStream {
    VenueStream(wire: HyperliquidWire(names: names, clock: clock), urls: endpoints.streams, factory: sockets,
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
