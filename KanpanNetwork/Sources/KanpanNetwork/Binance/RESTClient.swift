import Foundation
import KanpanCore

/// 币安 REST（§4.1）。限流、重试、翻页都在这儿，上面只管要数据。
public actor BinanceREST {
  public nonisolated let hosts: BinanceHosts
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

  /// 只清线路冷却，给用户点「点此重试」用。
  ///
  /// **不动限流器上的 IP 封禁**：418/429 是上游对我们整个出口 IP 下的判决，
  /// 用户点一下并不能让它提前结束。封禁期内点重试，`fetch` 开头的 `acquire`
  /// 照旧当场拒发，一个包都不出站（A-03 第 4 点）。
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

  /// 发一次 GET。429 按 `Retry-After` 停够重发，最多 `attempts` 次。
  ///
  /// 三种「别再撞了」的情形在这一层就收住，不往上叠（A-03 / A.3.4）：
  /// - 限流器还在封禁期内：`acquire` 直接抛 `.blocked`，这一笔不出站，当场抛给调用方；
  /// - 418（IP 级封禁）：只发一次，不占 `attempts`——秒级重试正是把 2 分钟滚成几天的做法；
  /// - 429：照旧按 `Retry-After` 停够重发，停多久由下一圈开头的 `acquire` 兑现。
  func fetch(_ url: URL, weight: Int, attempts: Int = 4, timeout: TimeInterval = 15,
             quota: EndpointQuota? = nil) async throws -> Data {
    var tried = 0
    while true {
      tried += 1
      do { try await limiter.acquire(weight: weight, quota: quota) }
      catch let error as BinanceError where error.isBlocked {
        log("上游封禁未解除（还剩 \(BinanceError.wholeSeconds(error.retryAfter ?? 0)) 秒），这一笔不发：\(url.path)")
        throw BinanceError(status: error.status, code: error.code, msg: error.msg,
                           url: url.absoluteString, retryAfter: error.retryAfter,
                           reason: .blocked)
      }
      // 调用方已经不要这一笔了（例如首屏小页：完整那发先回来了）就别出站。限流器放行
      // 这一步不一定让出执行权（`minGapMs == 0` 时一次都不睡），被取消的任务照样会
      // 走到这里；指望 transport 自己响应取消的话，请求已经发出去了、权重也花了。
      try Task.checkCancellation()
      let t0 = await pacer.nowMs()
      let reply: HTTPReply
      do { reply = try await transport.get(url, timeout: timeout) }
      catch let error as BinanceError where error.isRateLimited {
        // 走网关/对冲那条路时，上游的状态码是被 transport 吞掉再抛出来的，
        // 到不了下面 `reply.status` 那段。不在这儿记一笔，限流器就永远不知道
        // 自己已经被 ban 了，只会接着往枪口上撞——表现成「用一会儿涨跌幅全空」。
        log("限流 \(error.status)（\(error.proxied ? "网关上游" : "上游")），Retry-After=\(error.retryAfter.map { "\(BinanceError.wholeSeconds($0))s" } ?? "无")\(error.proxied ? "，只冷却那台网关" : "，记录罚停")")
        // 网关转述的限流不罚我们自己这把限流器：被限的是网关的出口 IP，
        // 该歇的是那台网关（`MarketRESTTransport` 已按 `Retry-After` 记下冷却）。
        if !error.proxied {
          await limiter.penalize(status: error.status, retryAfterSeconds: error.retryAfter)
        }
        // 记完就在这儿重试，和下面 `reply.status` 那条 429 共用同一份 `attempts`。
        // 这里原来是直接抛，注释写的是「让调用方按自己的节奏重试」——可冷启动那个
        // 调用方（`MarketFeed.fillOnce`）从来没有重试过，于是上游随手回一个 429
        // 就能把整张 K 线钉死在 WS 推来的那一根上。罚停要等多久由下一圈开头的
        // `limiter.acquire` 兑现，这儿不自己睡。418 例外：那是 IP 级封禁，重发没有意义。
        // 网关那条路上，这一笔失败意味着「本轮结束」：不许在同一次调用里改去打
        // 另一台网关、也不许叠加重试（A-05）。冷却按主机各记各的，下一轮自然分流。
        if tried < attempts, !error.isIPBan, !error.proxied { continue }
        throw error
      }
      let ms = await pacer.nowMs() - t0
      log("GET \(url.path)\(url.query.map { "?\($0)" } ?? "") → \(reply.status) \(reply.body.count)B \(Int(ms))ms")

      // 币安每个响应都带 `X-MBX-USED-WEIGHT-1M`，那是上游按我们这个出口 IP 记的账。
      // 本地只数自己发出去的，两者不一致时以上游为准（A.3.2 / A-T19）。
      if let used = reply.header("X-MBX-USED-WEIGHT-1M").flatMap(Int.init) {
        await limiter.observe(usedWeight: used)
      }

      if reply.status == 200 {
        await limiter.succeeded()
        return reply.body
      }
      let err = decodeError(reply, url: url)
      if err.isRateLimited {
        log("限流 \(reply.status)，Retry-After=\(err.retryAfter.map { "\(BinanceError.wholeSeconds($0))s" } ?? "无")，记录罚停")
        await limiter.penalize(status: err.status, retryAfterSeconds: err.retryAfter)
        if tried < attempts, !err.isIPBan {
          continue
        }
      }
      throw err
    }
  }

  /// 把响应翻成 `BinanceError`，并且**把上游说的话原样带上**：`Retry-After`
  /// （秒数或 HTTP-date）、错误体里的 `code`、以及 418/429/451 的类别（A-03 / A.10）。
  private func decodeError(_ reply: HTTPReply, url: URL) -> BinanceError {
    struct E: Decodable { var code: Int?; var msg: String? }
    let e = try? JSONDecoder().decode(E.self, from: reply.body)
    return BinanceError(status: reply.status, code: e?.code, msg: e?.msg,
                        url: url.absoluteString,
                        retryAfter: BinanceError.retryAfterSeconds(reply.header("Retry-After")))
  }

  private func decode<T: Decodable>(_ type: T.Type, _ data: Data) throws -> T {
    do { return try JSONDecoder().decode(T.self, from: data) }
    catch { throw FeedError.badResponse("解不开 \(T.self)：\(error)") }
  }

  // ------------------------------------------------------------------ 运行时限额

  /// 从 `exchangeInfo` 的响应里挑出 `rateLimits`（A.2）。
  ///
  /// 单独一个函数、不碰 `exchangeInfo()` 的解析路径：调用方拿到同一份 `data`
  /// 顺手调一次 `RateLimiter.sharedBinance.apply(rules:)` 就够了，解析不到就维持默认。
  public static func parseRateLimits(_ data: Data) -> [BinanceRateLimitRule] {
    (try? JSONDecoder().decode(RateLimitsDTO.self, from: data))?.rateLimits ?? []
  }

  // ------------------------------------------------------------------ 品种表

  /// 全部USDT普通与TradFi永续；按产品范围排除USD1等计价。
  ///
  /// 非 `TRADING` 的行**不再被扔掉**，而是带着 `SymbolInfo.status` 留在表里（审查 B-06）：
  /// 扔掉等于把「已下架」和「根本不存在」压成同一件事，用户自选里那一行会凭空消失。
  public func exchangeInfo() async throws -> [SymbolInfo] {
    let data = try await fetch(hosts.exchangeInfo(), weight: 1, timeout: 30)
    // A.2：上游在同一份响应里公布了 `rateLimits`，顺手把分钟预算对到它身上。
    await limiter.apply(rules: Self.parseRateLimits(data))
    return try Self.parseExchangeInfo(data)
  }

  /// 解不开就**抛**，不再给一张空表（审查 B-05）。
  ///
  /// 原来返回 `[]`：目录层看到空表分不清「交易所今天真的一个品种都没有」和
  /// 「我们解错了/收到的是一份错误 JSON」，于是把一张空目录当成功结果缓存下来，
  /// 单飞的等待方还会跟着一起拿到它。
  public static func parseExchangeInfo(_ data: Data) throws -> [SymbolInfo] {
    let dto: ExchangeInfoDTO
    do { dto = try JSONDecoder().decode(ExchangeInfoDTO.self, from: data) }
    catch { throw FeedError.badResponse("解不开品种表：\(error)") }
    // 坏行单独丢（`LenientList`）；一行都解不开才算整份解不开。
    if dto.symbols.isEmpty, dto.droppedSymbols > 0 {
      throw FeedError.badResponse("解不开品种表：\(dto.droppedSymbols) 行全部无效")
    }
    // 准入条件仍是原来那四条，只有第四条换了作用（审查 B-04 / B-06）：
    // ① `baseAsset` 不是稳定币（USDC/FDUSD… 的普通永续不进产品范围）；
    // ② `quoteAsset == "USDT"`；③ `contractType` 只收两种永续（交割合约不收）；
    // ④ `status`——过去它把非 TRADING 的行**滤掉**，现在改成**带上去**（`SymbolStatus`）。
    // 第四条不能再当滤子：滤掉等于把「已下架」和「根本不存在」压成一件事。
    // `underlyingType` 不做准入，只原样带给分类器：类型缺失时按 `.other`，不猜白名单。
    return dto.symbols
      .filter {
        let type = $0.contractType ?? "PERPETUAL"
        let stableBases: Set<String> = ["USDC", "FDUSD", "TUSD", "USDP", "DAI", "USDE", "PYUSD", "USD1", "USDD"]
        let stablePair = type == "PERPETUAL" && stableBases.contains($0.baseAsset)
        return !stablePair && $0.quoteAsset == "USDT" &&
          SymbolInfo.perpetualContractTypes.contains(type)
      }
      .map {
        SymbolInfo(symbol: $0.symbol, base: $0.baseAsset, quote: $0.quoteAsset,
                   pricePrecision: $0.pricePrecision, quantityPrecision: $0.quantityPrecision,
                   tickSize: $0.tickSize, underlyingType: $0.underlyingType,
                   underlyingSubTypes: $0.underlyingSubType, contractType: $0.contractType,
                   status: SymbolStatus.exchange($0.status), onboardDate: $0.onboardDate)
      }
      .sorted { $0.symbol < $1.symbol }
  }

  // ------------------------------------------------------------------ 资金费率

  /// 某一个品种此刻的资金费率（`/fapi/v1/premiumIndex`，公开、免鉴权、权重 1）。
  ///
  /// 正在看的那张图用不着它——`markPrice@1s` 流每秒都捎着费率过来。这条路是给
  /// **别的品种**准备的：长按自选行弹出来的预览卡要在那一格里写出费率，它没有
  /// 那条流。费率不是有限数就当没有（`nan` 顶上去和空着一样害人）。
  public func funding(symbol: String) async throws -> FundingSnapshot {
    let data = try await fetch(hosts.premiumIndex(symbol: symbol), weight: 1)
    let dto = try decode(PremiumIndexDTO.self, data)
    guard let rate = Double(dto.lastFundingRate), rate.isFinite else {
      throw FeedError.badResponse("费率不是数字：\(dto.lastFundingRate)")
    }
    let next = dto.nextFundingTime.flatMap { $0 > 0 ? $0 : nil }
    return FundingSnapshot(rate: rate, nextFundingTimeMs: next)
  }

  /// 全市场每个品种此刻的资金费率，按交易所代号（`BTCUSDT`）索引。
  ///
  /// 一次往返（权重 10）换回整张表，给「换品种时费率 / 结算先有个数」用；
  /// 费率不是有限数的那几行（交割合约回的是空串）直接略过，不拿 `nan` 顶位。
  public func fundingAll() async throws -> [String: FundingSnapshot] {
    let data = try await fetch(hosts.premiumIndexAll(), weight: 10)
    // 坏一行只丢那一行；一行都解不开才抛，不拿一张空表冒充「全市场都没有费率」。
    let list = try decode(LenientList<PremiumIndexDTO>.self, data)
    if list.items.isEmpty, list.dropped > 0 { throw FeedError.badResponse("全市场费率 \(list.dropped) 行全部无效") }
    let rows = list.items
    var out: [String: FundingSnapshot] = [:]
    out.reserveCapacity(rows.count)
    for dto in rows {
      guard let rate = Double(dto.lastFundingRate), rate.isFinite else { continue }
      out[dto.symbol.uppercased()] = FundingSnapshot(
        rate: rate, nextFundingTimeMs: dto.nextFundingTime.flatMap { $0 > 0 ? $0 : nil })
    }
    return out
  }

  // ------------------------------------------------------------------ K 线

  /// 币安原生没有的周期拿哪一档去聚：只有 1y，拉 1M 自己聚（§4.2）。
  /// 传 `1y` 过去是 `-1120 Invalid interval`。
  public static let aggregatedFrom: [Interval: Interval] = [.y1: .mo1]
  static func source(_ interval: Interval) -> Interval { aggregatedFrom[interval] ?? interval }

  /// 一页 K 线。`interval` 按 `aggregatedFrom` 换成源周期（1y 拉的是 1M）。
  public func klines(symbol: String, interval: Interval, limit: Int = maxKlines,
                     startTime: Int64? = nil, endTime: Int64? = nil) async throws -> [Bar] {
    let api = Self.source(interval).rawValue
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
    for p in 0..<Self.maxTailPages {
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
    throw FeedError.gapTooLong
  }

  /// `contiguousTail` 最多翻几页。
  static let maxTailPages = 4
  /// `contiguousTail` 最多能接上的根数（`ProviderCapabilities.maxTailBars`）。
  public static let maxTailBars = maxTailPages * maxKlines

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
    guard ticker.symbol == InstrumentID.canonical(symbol), ticker.last.isFinite, ticker.last > 0 else {
      throw FeedError.badResponse("报价品种或价格无效")
    }
    return ticker
  }

  /// 全市场 24h 统计，一次往返。权重 40（不带 symbol 的官方档位），
  /// 但省掉的是几十个请求各自的排队与往返——回前台整屏补价时用它。
  /// 网关只代理单品种 `ticker`，所以这条在非直连线路上会直接失败，
  /// 调用方要能退回逐个请求。
  /// - Parameter timeout: **总**时限，限流器里排队的那段也算在内（`Deadline`）。
  ///   只给 `URLRequest` 的话，排队那段没人管：出口 IP 的一分钟账接近上限时这一笔
  ///   （权重 40）会在限流器里一声不响地等到窗口滑过去，板块页就一直空着。
  public func tickers24h(timeout: TimeInterval = 8) async throws -> [Ticker] {
    let url = hosts.tickers24h()
    let data = try await Deadline.run(seconds: timeout) {
      try await self.fetch(url, weight: 40, attempts: 1, timeout: timeout)
    }
    // 坏一行只丢那一行（`LenientList`），全丢光由下面「为空」那句抛。
    let rows = try decode(LenientList<Ticker24hDTO>.self, data).items
    let tickers = rows.map(\.ticker).filter { $0.last.isFinite && $0.last > 0 && !$0.symbol.isEmpty }
    guard !tickers.isEmpty else { throw FeedError.badResponse("全市场报价为空") }
    return tickers
  }

  /// 近 30 天的 OI。`period` 是币安原生档；> 1d 的周期传 5m 由上层再聚。
  public func openInterestHist(symbol: String, period: String, limit: Int = 500,
                               startTime: Int64? = nil, endTime: Int64? = nil) async throws -> [OIPoint] {
    let url = hosts.openInterestHist(symbol: symbol, period: period, limit: min(limit, 500),
                                     startTime: startTime, endTime: endTime)
    // 这个端点权重算 1（上游标的是 0），但 `/futures/data/` 整族另有一条
    // 1000 次 / 5 分钟的共享限制，只按权重算等于不受限，翻长历史时会一路撞到 429（A.2）。
    let data = try await fetch(url, weight: 1, quota: .futuresData)
    let rows = try decode([OIHistDTO].self, data)
    guard rows.allSatisfy({ $0.symbol.uppercased() == InstrumentID(symbol).symbol
      && $0.point.value.isFinite && $0.point.value >= 0 && $0.timestamp > 0 }) else {
      throw FeedError.badResponse("持仓量品种或数值无效")
    }
    return rows.map(\.point).sorted { $0.time < $1.time }
  }

  // ------------------------------------------------------------------ 多空比 / 主动买卖比 / 基差

  // 这三条和持仓量是**同一族**（`/futures/data/*`）：权重 0、共用一条
  // 1000 次 / 5 分钟的 IP 限制（`EndpointQuota.futuresData`），`period` 也是同一套
  // 5m/15m/30m/1h/2h/4h/6h/12h/1d，`limit` 上限 500，历史只有近 30 天。
  //
  // 解析一律「字符串转不动就跳过这一条」，不整批判废：这一族的附带字段随时可能是
  // 空串（`basis` 的 `annualizedBasisRate` 实测就一直是 `""`），为一个附带字段扔掉
  // 整页数据，图上缺的是一整段曲线。
  //
  // 另外：网关不代理 `/futures/data/*`，所以这三条在网关线路下取不到，和持仓量今天
  // 的处境一样——调用方要走空态，不要因此自动切线路。

  /// 近 30 天的全市场多空账户数比。
  public func globalLongShortAccountRatio(symbol: String, period: String, limit: Int = 500,
                                          startTime: Int64? = nil, endTime: Int64? = nil) async throws -> [LongShortRatioPoint] {
    let url = hosts.globalLongShortAccountRatio(symbol: symbol, period: period, limit: min(limit, 500),
                                                startTime: startTime, endTime: endTime)
    let data = try await fetch(url, weight: 0, quota: .futuresData)
    let rows = try decode([LongShortRatioDTO].self, data)
    // 响应带 `symbol`，对不上的行直接不要：宁可少几个点，也不能把别人的数画到这张图上。
    return rows
      .filter { $0.symbol.map { $0.uppercased() == InstrumentID(symbol).symbol } ?? true }
      .compactMap(\.point)
      .sorted { $0.timeMs < $1.timeMs }
  }

  /// 近 30 天的主动买卖量比。响应里**没有品种字段**，认的是我们自己请求的那个。
  public func takerLongShortRatio(symbol: String, period: String, limit: Int = 500,
                                  startTime: Int64? = nil, endTime: Int64? = nil) async throws -> [TakerRatioPoint] {
    let url = hosts.takerLongShortRatio(symbol: symbol, period: period, limit: min(limit, 500),
                                        startTime: startTime, endTime: endTime)
    let data = try await fetch(url, weight: 0, quota: .futuresData)
    let rows = try decode([TakerRatioDTO].self, data)
    return rows.compactMap(\.point).sorted { $0.timeMs < $1.timeMs }
  }

  /// 近 30 天的永续基差。参数是 `pair` + `contractType`，不是 `symbol`。
  ///
  /// USDT 本位永续这边 `pair` 和 `symbol` 长得一样（`BTCUSDT`），所以调用方照旧
  /// 传品种名即可；真正不同的是交割合约，那时同一个 pair 下有好几条曲线。
  public func basis(pair: String, contractType: String = "PERPETUAL", period: String, limit: Int = 500,
                    startTime: Int64? = nil, endTime: Int64? = nil) async throws -> [BasisPoint] {
    let url = hosts.basis(pair: pair, contractType: contractType, period: period, limit: min(limit, 500),
                          startTime: startTime, endTime: endTime)
    let data = try await fetch(url, weight: 0, quota: .futuresData)
    let rows = try decode([BasisDTO].self, data)
    return rows
      .filter { $0.pair.map { $0.uppercased() == InstrumentID(pair).symbol } ?? true }
      .compactMap(\.point)
      .sorted { $0.timeMs < $1.timeMs }
  }

  // ------------------------------------------------------------------ 纯函数

  /// 一串 Bar → BarSeries。1y 在这儿从 1M 聚出来（§4.2）。
  public static func series(symbol: String, interval: Interval, bars: [Bar]) -> BarSeries {
    MarketSeries.series(symbol: symbol, interval: interval, source: source(interval), bars: bars)
  }

  /// 按 openTime 升序去重，同一 openTime 留最后出现的那根（网络上后到的更新）。
  public static func dedup(_ bars: [Bar]) -> [Bar] { MarketSeries.dedup(bars) }
}
