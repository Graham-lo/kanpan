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

  /// Clear only the in-memory route backoff before an explicit user retry.
  public func resetRouteCooldowns() async {
    if let routed = transport as? MarketRESTTransport {
      await routed.resetRouteCooldowns()
    }
  }

  /// 把「行情线路」策略转给底下的 transport。假 transport（测试里）没有这层，
  /// 就是一次空操作。
  public func setRoutePolicy(_ policy: MarketRoutePolicy) async {
    if let routed = transport as? MarketRESTTransport {
      await routed.setPolicy(policy)
    }
  }

  // ------------------------------------------------------------------ 底层

  /// 发一次 GET。418 / 429 按 `Retry-After` 停够重发，最多 `attempts` 次。
  func fetch(_ url: URL, weight: Int, attempts: Int = 4, timeout: TimeInterval = 15) async throws -> Data {
    var tried = 0
    while true {
      tried += 1
      try await limiter.acquire(weight: weight)
      let t0 = await pacer.nowMs()
      let reply: HTTPReply
      do { reply = try await transport.get(url, timeout: timeout) }
      catch let error as BinanceError where error.isRateLimited {
        // 走网关/对冲那条路时，上游的状态码是被 transport 吞掉再抛出来的，
        // 到不了下面 `reply.status` 那段。不在这儿记一笔，限流器就永远不知道
        // 自己已经被 ban 了，只会接着往枪口上撞——表现成「用一会儿涨跌幅全空」。
        // 记完就抛：这一笔让调用方按自己的节奏重试，别占着并发位空等。
        log("限流 \(error.status)（上游），记录罚停")
        await limiter.penalize(retryAfterSeconds: nil)
        // 记完就在这儿重试，和下面 `reply.status` 那条 429 共用同一份 `attempts`。
        // 这里原来是直接抛，注释写的是「让调用方按自己的节奏重试」——可冷启动那个
        // 调用方（`MarketFeed.fillOnce`）从来没有重试过，于是上游随手回一个 429
        // 就能把整张 K 线钉死在 WS 推来的那一根上。罚停要等多久由下一圈开头的
        // `limiter.acquire` 兑现，这儿不自己睡。
        if tried < attempts { continue }
        throw error
      }
      let ms = await pacer.nowMs() - t0
      log("GET \(url.path)\(url.query.map { "?\($0)" } ?? "") → \(reply.status) \(reply.body.count)B \(Int(ms))ms")

      if reply.status == 200 {
        await limiter.succeeded()
        return reply.body
      }
      let err = decodeError(reply, url: url)
      if err.isRateLimited {
        let ra = reply.header("Retry-After").flatMap(Double.init)
        log("限流 \(reply.status)，Retry-After=\(ra.map { "\($0)s" } ?? "无")，记录罚停")
        await limiter.penalize(retryAfterSeconds: ra)
        if tried < attempts {
          continue
        }
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
    let data = try await fetch(url, weight: RateLimiter.klinesWeight(for: min(limit, Self.maxKlines)))
    let rows = try decode([KlineRow].self, data)
    return rows.map(\.bar)
  }

  /// 补一次缺要拉几根：`from` 到 `now` 之间有多少根就拉多少根，外加 2 根余量。
  ///
  /// 原来这儿走的是 `klines` 的默认 `limit = 1500`：切出去抽根烟回来只缺一根，
  /// 也照样收一份 250KB 的报文、在限流器上花掉权重 10。按需之后常见情形是
  /// 几根到几十根、权重 1，回前台那一下的等待和流量都少一个数量级。
  ///
  /// 下限 5 根：再往下省不出什么，留点余量反而能盖住时钟偏移和边界那一根。
  /// 上限仍是一页 1500，翻页逻辑不变。
  static func tailLimit(interval: Interval, from: Int64, now: Int64) -> Int {
    let step = max(interval.stepMs, 1)
    let needed = Int(max(0, (now - from) / step) + 1)
    return min(max(needed + 2, 5), maxKlines)
  }

  /// Reconnects can span several pages; never treat the first 1500 bars as the whole gap.
  public func contiguousTail(symbol: String, interval: Interval, from: Int64) async throws -> [Bar] {
    var cursor = from
    var result: [Bar] = []
    let now = Int64(Date().timeIntervalSince1970 * 1000)
    for p in 0..<4 {
      try Task.checkCancellation()
      // 只有第一页按需；能翻到第二页说明第一页被拉满了，那就是真的断了很久，
      // 后面几页照旧按整页拉。
      let limit = p == 0 ? Self.tailLimit(interval: interval, from: cursor, now: now) : Self.maxKlines
      let page = try await klines(symbol: symbol, interval: interval, limit: limit, startTime: cursor)
      guard let last = page.last else { return result }
      guard page.first!.openTime >= cursor, last.openTime >= cursor else { throw FeedError.badResponse("行情翻页没有推进") }
      result.append(contentsOf: page)
      if page.count < limit { return result }
      cursor = last.openTime + 1
    }
    throw FeedError.badResponse("断线时间较长，需要重新加载行情")
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
    let ticker = try decode(Ticker24hDTO.self, data).ticker
    guard ticker.symbol.uppercased() == symbol.uppercased(), ticker.last.isFinite, ticker.last > 0 else {
      throw FeedError.badResponse("报价品种或价格无效")
    }
    return ticker
  }

  /// 全市场 24h 统计，一次往返。权重 40（不带 symbol 的官方档位），
  /// 但省掉的是几十个请求各自的排队与往返——回前台整屏补价时用它。
  /// 网关只代理单品种 `ticker`，所以这条在非直连线路上会直接失败，
  /// 调用方要能退回逐个请求。
  public func tickers24h(timeout: TimeInterval = 8) async throws -> [Ticker] {
    let data = try await fetch(hosts.tickers24h(), weight: 40, attempts: 1, timeout: timeout)
    let rows = try decode([Ticker24hDTO].self, data)
    let tickers = rows.map(\.ticker).filter { $0.last.isFinite && $0.last > 0 && !$0.symbol.isEmpty }
    guard !tickers.isEmpty else { throw FeedError.badResponse("全市场报价为空") }
    return tickers
  }

  /// 近 30 天的 OI。`period` 是币安原生档；> 1d 的周期传 5m 由上层再聚。
  public func openInterestHist(symbol: String, period: String, limit: Int = 500,
                               startTime: Int64? = nil, endTime: Int64? = nil) async throws -> [OIPoint] {
    let url = hosts.openInterestHist(symbol: symbol, period: period, limit: min(limit, 500),
                                     startTime: startTime, endTime: endTime)
    let data = try await fetch(url, weight: 1)
    let rows = try decode([OIHistDTO].self, data)
    guard rows.allSatisfy({ $0.symbol.uppercased() == symbol.uppercased()
      && $0.point.value.isFinite && $0.point.value >= 0 && $0.timestamp > 0 }) else {
      throw FeedError.badResponse("持仓量品种或数值无效")
    }
    return rows.map(\.point).sorted { $0.time < $1.time }
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
