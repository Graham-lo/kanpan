import Foundation
import KanpanCore

/// 日志出口。命令行工具打到 stdout，app 里丢给 os_log，测试里收进数组。
public struct FeedLog: Sendable {
  public var write: @Sendable (String) -> Void
  public init(_ write: @escaping @Sendable (String) -> Void = { _ in }) { self.write = write }
  public static let silent = FeedLog()
  public static let stdout = FeedLog { print($0) }
  public func callAsFunction(_ s: String) { write(s) }
}

/// 币安 REST（§4.1）。限流、重试、翻页都在这儿，上面只管要数据。
public actor BinanceREST {
  public let hosts: BinanceHosts
  private let transport: HTTPTransport
  private let limiter: RateLimiter
  private let pacer: Pacer
  private let log: FeedLog

  /// `klines` 一次最多 1500 根。
  public static let maxKlines = 1500

  public init(hosts: BinanceHosts = .default,
              transport: HTTPTransport = URLSessionTransport(),
              limiter: RateLimiter? = nil,
              pacer: Pacer = SystemPacer(),
              log: FeedLog = .silent) {
    self.hosts = hosts
    self.transport = transport
    self.pacer = pacer
    self.limiter = limiter ?? RateLimiter(pacer: pacer)
    self.log = log
  }

  // ------------------------------------------------------------------ 底层

  /// 发一次 GET。418 / 429 按 `Retry-After` 停够重发，最多 `attempts` 次。
  func fetch(_ url: URL, weight: Int, attempts: Int = 4, timeout: TimeInterval = 15) async throws -> Data {
    var tried = 0
    while true {
      tried += 1
      try await limiter.acquire(weight: weight)
      let t0 = await pacer.nowMs()
      let reply = try await transport.get(url, timeout: timeout)
      let ms = await pacer.nowMs() - t0
      log("GET \(url.path)\(url.query.map { "?\($0)" } ?? "") → \(reply.status) \(reply.body.count)B \(Int(ms))ms")

      if reply.status == 200 {
        await limiter.succeeded()
        return reply.body
      }
      let err = decodeError(reply, url: url)
      if err.isRateLimited, tried < attempts {
        let ra = reply.header("Retry-After").flatMap(Double.init)
        log("限流 \(reply.status)，Retry-After=\(ra.map { "\($0)s" } ?? "无")，停够再发")
        await limiter.penalize(retryAfterSeconds: ra)
        continue
      }
      throw err
    }
  }

  private func decodeError(_ reply: HTTPReply, url: URL) -> BinanceError {
    struct E: Decodable { var code: Int?; var msg: String? }
    let e = try? JSONDecoder().decode(E.self, from: reply.body)
    return BinanceError(status: reply.status, code: e?.code, msg: e?.msg, url: url.absoluteString)
  }

  private func decode<T: Decodable>(_ type: T.Type, _ data: Data) throws -> T {
    do { return try JSONDecoder().decode(T.self, from: data) }
    catch { throw FeedError.badResponse("解不开 \(T.self)：\(error)") }
  }

  // ------------------------------------------------------------------ 品种表

  /// 全部USDT普通与TradFi永续，只显示TRADING；按产品范围排除USD1等计价。
  public func exchangeInfo() async throws -> [SymbolInfo] {
    let data = try await fetch(hosts.exchangeInfo(), weight: 1, timeout: 30)
    return Self.parseExchangeInfo(data)
  }

  public static func parseExchangeInfo(_ data: Data) -> [SymbolInfo] {
    guard let dto = try? JSONDecoder().decode(ExchangeInfoDTO.self, from: data) else { return [] }
    return dto.symbols
      .filter {
        let type = $0.contractType ?? "PERPETUAL"
        let stableBases: Set<String> = ["USDC", "FDUSD", "TUSD", "USDP", "DAI", "USDE", "PYUSD", "USD1", "USDD"]
        let stablePair = type == "PERPETUAL" && stableBases.contains($0.baseAsset)
        return !stablePair && ($0.status ?? "TRADING") == "TRADING" && $0.quoteAsset == "USDT" &&
          ["PERPETUAL", "TRADIFI_PERPETUAL"].contains(type)
      }
      .map {
        SymbolInfo(symbol: $0.symbol, base: $0.baseAsset, quote: $0.quoteAsset,
                   pricePrecision: $0.pricePrecision, quantityPrecision: $0.quantityPrecision,
                   tickSize: $0.tickSize, underlyingType: $0.underlyingType,
                   underlyingSubTypes: $0.underlyingSubType, contractType: $0.contractType)
      }
      .sorted { $0.symbol < $1.symbol }
  }

  // ------------------------------------------------------------------ K 线

  /// 一页 K 线。`interval` 走 `Interval.source`（1y 拉的是 1M）。
  public func klines(symbol: String, interval: Interval, limit: Int = maxKlines,
                     startTime: Int64? = nil, endTime: Int64? = nil) async throws -> [Bar] {
    let api = interval.source.rawValue
    let url = hosts.klines(symbol: symbol, interval: api, limit: min(limit, Self.maxKlines),
                           startTime: startTime, endTime: endTime)
    let data = try await fetch(url, weight: RateLimiter.klinesWeight)
    let rows = try decode([KlineRow].self, data)
    return rows.map(\.bar)
  }

  /// 最新一屏：拉满 `limit` 根，返回 `BarSeries`。1y 会在这儿聚出来。
  public func latestSeries(symbol: String, interval: Interval, limit: Int = maxKlines) async throws -> BarSeries {
    let bars = try await klines(symbol: symbol, interval: interval, limit: limit)
    return Self.series(symbol: symbol, interval: interval, bars: bars)
  }

  /// 向前翻 `pages` 页，每页 1500 根，`endTime = 已有第一根 - 1`（§4.1）。
  /// 串行、限流器保证间隔 ≥ 120ms。返回的是从早到晚、无重复的一段。
  public func history(symbol: String, interval: Interval, pages: Int,
                      before firstOpen: Int64) async throws -> [Bar] {
    var out: [Bar] = []
    var end = firstOpen - 1
    for p in 0..<pages {
      let page = try await klines(symbol: symbol, interval: interval,
                                  limit: Self.maxKlines, endTime: end)
      guard let first = page.first else {
        log("第 \(p + 1) 页空，到头了")
        break
      }
      let kept = page.filter { $0.openTime < firstOpen }
      out.insert(contentsOf: kept, at: 0)
      log("第 \(p + 1) 页 \(page.count) 根，\(first.openTime) … \(page.last!.openTime)")
      if page.count < Self.maxKlines { break }
      end = first.openTime - 1
    }
    // 去重（币安偶尔在页边界重复一根），按 openTime 保留后来的。
    return Self.dedup(out)
  }

  // ------------------------------------------------------------------ 行情 / 持仓量

  public func ticker24h(symbol: String, timeout: TimeInterval = 15) async throws -> Ticker {
    let data = try await fetch(hosts.ticker24h(symbol: symbol), weight: 1, timeout: timeout)
    return try decode(Ticker24hDTO.self, data).ticker
  }

  /// 近 30 天的 OI。`period` 是币安原生档；> 1d 的周期传 5m 由上层再聚。
  public func openInterestHist(symbol: String, period: String, limit: Int = 500,
                               startTime: Int64? = nil, endTime: Int64? = nil) async throws -> [OIPoint] {
    let url = hosts.openInterestHist(symbol: symbol, period: period, limit: min(limit, 500),
                                     startTime: startTime, endTime: endTime)
    let data = try await fetch(url, weight: 1)
    return try decode([OIHistDTO].self, data).map(\.point).sorted { $0.time < $1.time }
  }

  // ------------------------------------------------------------------ 纯函数

  /// 一串 Bar → BarSeries。1y 在这儿从 1M 聚出来（§4.2）。
  public static func series(symbol: String, interval: Interval, bars: [Bar]) -> BarSeries {
    let clean = dedup(bars)
    let src = BarSeries(symbol: symbol, interval: interval.source, bars: clean)
    if interval.source != interval {
      return Aggregator.bucket(series: src, into: interval)
    }
    return src
  }

  /// 按 openTime 升序去重，同一 openTime 留最后出现的那根（网络上后到的更新）。
  public static func dedup(_ bars: [Bar]) -> [Bar] {
    guard bars.count > 1 else { return bars }
    var byTime: [Int64: Bar] = [:]
    byTime.reserveCapacity(bars.count)
    for b in bars { byTime[b.openTime] = b }
    return byTime.keys.sorted().map { byTime[$0]! }
  }
}
