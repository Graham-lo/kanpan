import Foundation
import KanpanCore
import KanpanNetwork

/// 币安 U 本位合约账户的只读接入（自动复盘第一期唯一的一家）。
///
/// 为什么是这几个端点、为什么在手机上直连：
/// - 用户 2026-09-27 定的：只读 API「不是显示在上面，而是做成自动复盘」。要拼回合只需要成交、
///   资金费、当前持仓与杠杆，所以**只用四个只读端点**：
///   `GET /sapi/v1/account/apiRestrictions`（接入前查 Key 的权限）、
///   `GET /fapi/v1/income`（资金流水：已实现盈亏 / 资金费 / 手续费，顺带当「哪只品种哪一周有成交」的索引）、
///   `GET /fapi/v1/userTrades`（逐只品种、逐 7 天窗口拉成交）、
///   `GET /fapi/v2/positionRisk`（当前持仓、杠杆、标记价）。
///   下单、撤单、划转、提现的端点一个都不许出现，`ExchangeEndpointScanTests` 扫源码守着。
/// - Key 只在这台手机的 Keychain 里（`deviceOnly`），签名也在手机上做，Key 与 Secret 从不离开手机；
///   看盘网关与 kanpan-api 都在美国 VPS 上，币安的账户端点对美区 IP 直接回 451，服务端本来也调不了。
///   所以这里固定走直连域名（与 `BinanceProvider.upstream` 直连档同一个 `defaultRestHost`），
///   不看用户选的行情线路、不走网关。
/// - 请求权重记在行情共用的 `RateLimiter.sharedBinance` 上（同一个出口 IP、同一份每分钟配额），
///   同步拉历史时不会把行情请求挤到 418。
actor BinanceFuturesAccount: ExchangeAccountProvider {
  nonisolated let venue = BinanceProvider.venue
  nonisolated let market = BinanceProvider.market

  /// 合约账户端点的域名：直连档的 fapi 域名。
  static let futuresHost = BinanceProvider.defaultRestHost
  /// Key 权限只能在现货域名的 sapi 上查。
  static let spotHost = "api.binance.com"
  /// 币安允许的最大 60 秒；手机网络抖一下也不至于被判超时。
  static let recvWindow = 10_000
  /// userTrades 与 income 的单次时间窗上限（币安规定 7 天）。
  static let windowMs: Int64 = 7 * 86_400_000
  /// 单页条数上限（两个端点都是 1000）。
  static let maxPageLimit = 1000

  /// 各端点的请求权重（币安文档）。
  enum Weight {
    static let income = 30
    static let userTrades = 5
    static let positionRisk = 5
    static let apiRestrictions = 1
    static let serverTime = 1
  }

  /// sapi 走现货的权重池，和合约的分开记；只在接入时查一次权限，给一个小预算就够。
  static let sharedSpot = RateLimiter(budget: 600, minGapMs: 100)

  private let credentials: ExchangeCredentials
  private let signer: BinanceRequestSigner
  private let http: any ExchangeHTTP
  private let futuresLimiter: RateLimiter
  private let spotLimiter: RateLimiter
  private let pageLimit: Int
  private let clock: @Sendable () -> Int64
  /// 交易所时间 − 手机时间（毫秒）。遇到 -1021 才去校一次。
  private var clockOffsetMs: Int64 = 0

  init(credentials: ExchangeCredentials,
       http: any ExchangeHTTP = URLSessionExchangeHTTP(),
       futuresLimiter: RateLimiter = .sharedBinance,
       spotLimiter: RateLimiter = BinanceFuturesAccount.sharedSpot,
       pageLimit: Int = BinanceFuturesAccount.maxPageLimit,
       clock: @escaping @Sendable () -> Int64 = { Int64(Date().timeIntervalSince1970 * 1000) }) {
    self.credentials = credentials.trimmed
    self.signer = BinanceRequestSigner(secret: self.credentials.secret)
    self.http = http
    self.futuresLimiter = futuresLimiter
    self.spotLimiter = spotLimiter
    self.pageLimit = max(1, min(pageLimit, Self.maxPageLimit))
    self.clock = clock
  }

  // MARK: - 只读校验

  /// 这几项任何一个开着，这把 Key 就能动钱或下单，不收。
  /// 用户说的是「只读」，所以除了交易与提现，内部划转、万向划转、杠杆、期权、统一账户交易也一并算「非只读」。
  struct Restrictions: Decodable, Sendable {
    var enableReading: Bool?
    var enableWithdrawals: Bool?
    var enableSpotAndMarginTrading: Bool?
    var enableFutures: Bool?
    var enableInternalTransfer: Bool?
    var permitsUniversalTransfer: Bool?
    var enableMargin: Bool?
    var enableVanillaOptions: Bool?
    var enablePortfolioMarginTrading: Bool?
    var enableFixApiTrade: Bool?

    var isReadOnly: Bool {
      let risky: [Bool?] = [enableWithdrawals, enableSpotAndMarginTrading, enableFutures,
                            enableInternalTransfer, permitsUniversalTransfer, enableMargin,
                            enableVanillaOptions, enablePortfolioMarginTrading, enableFixApiTrade]
      return !risky.contains(true)
    }
  }

  func verifyReadOnly() async throws {
    guard !credentials.apiKey.isEmpty, !credentials.secret.isEmpty else {
      throw ExchangeAccountError.missingCredentials
    }
    let data = try await signedGet(host: Self.spotHost, path: "/sapi/v1/account/apiRestrictions",
                                   items: [], weight: Weight.apiRestrictions, limiter: spotLimiter)
    let restrictions = try Self.decode(Restrictions.self, data)
    guard restrictions.isReadOnly else { throw ExchangeAccountError.notReadOnly }
    // 再探一次合约账户：Key 的 IP 白名单不含这台手机、或者账户没开合约，都在接入这一步就说清楚。
    _ = try await positionRisk()
  }

  // MARK: - 拉取

  func fetch(from: Int64, to: Int64) async throws -> ExchangeAccountBatch {
    guard from <= to else { return ExchangeAccountBatch() }
    var batch = ExchangeAccountBatch()

    // 1. 资金流水：资金费直接收下；已实现盈亏与手续费只当索引——哪只品种、哪个 7 天窗口里有成交。
    let income = try await incomeEntries(from: from, to: to)
    var activeWindows: [String: Set<Int64>] = [:]
    for entry in income {
      switch entry.incomeType {
      case "FUNDING_FEE":
        guard let amount = TradeDecimal.parse(entry.income), !entry.symbol.isEmpty else { continue }
        batch.funding.append(FundingEntry(id: String(entry.tranId), symbol: entry.symbol, time: entry.time,
                                          amount: amount, asset: entry.asset))
      case "REALIZED_PNL", "COMMISSION":
        guard !entry.symbol.isEmpty else { continue }
        activeWindows[entry.symbol, default: []].insert((entry.time - from) / Self.windowMs)
      default:
        continue
      }
    }

    // 2. 逐只品种、只拉有动静的那几个 7 天窗口的成交。
    for symbol in activeWindows.keys.sorted() {
      for index in activeWindows[symbol, default: []].sorted() {
        let start = from + index * Self.windowMs
        let end = min(to, start + Self.windowMs - 1)
        batch.fills += try await userTrades(symbol: symbol, from: start, to: end)
      }
    }
    batch.fills.sort { ($0.time, $0.id) < ($1.time, $1.id) }

    // 3. 当前持仓、杠杆、标记价。
    let positions = try await positionRisk()
    let touched = Set(batch.fills.map(\.symbol)).union(batch.funding.map(\.symbol))
    for p in positions {
      if let mark = TradeDecimal.parse(p.markPrice), mark > 0 { batch.markPrices[p.symbol] = mark }
      let amount = TradeDecimal.parse(p.positionAmt) ?? 0
      if amount != 0, let side = PositionSide(rawValue: p.positionSide) {
        batch.positions[PositionKey(symbol: p.symbol, positionSide: side)] = amount
      }
      if amount != 0 || touched.contains(p.symbol), let lev = Int(p.leverage) {
        batch.leverage[p.symbol] = lev
      }
    }
    return batch
  }

  // MARK: - 端点

  struct IncomeDTO: Decodable, Sendable {
    var symbol: String
    var incomeType: String
    var income: String
    var asset: String
    var time: Int64
    var tranId: Int64
  }

  struct UserTradeDTO: Decodable, Sendable {
    var symbol: String
    var id: Int64
    var orderId: Int64
    var side: String
    var price: String
    var qty: String
    var quoteQty: String?
    var realizedPnl: String
    var marginAsset: String?
    var commission: String
    var commissionAsset: String
    var time: Int64
    var positionSide: String
    var maker: Bool
  }

  struct PositionDTO: Decodable, Sendable {
    var symbol: String
    var positionAmt: String
    var markPrice: String
    var leverage: String
    var positionSide: String
  }

  /// `/fapi/v1/income`：按 7 天切窗，窗内满页就把游标挪到最后一条的时间接着翻，按 tranId 去重。
  func incomeEntries(from: Int64, to: Int64) async throws -> [IncomeDTO] {
    var out: [IncomeDTO] = []
    var seen: Set<String> = []
    var windowStart = from
    while windowStart <= to {
      let windowEnd = min(to, windowStart + Self.windowMs - 1)
      try await paginate(from: windowStart, to: windowEnd) { cursor in
        let data = try await self.signedGet(
          host: Self.futuresHost, path: "/fapi/v1/income",
          items: [("startTime", String(cursor)), ("endTime", String(windowEnd)),
                  ("limit", String(self.pageLimit))],
          weight: Weight.income, limiter: self.futuresLimiter)
        let page = try Self.decode([IncomeDTO].self, data)
        for entry in page where seen.insert("\(entry.tranId)|\(entry.incomeType)|\(entry.asset)").inserted {
          out.append(entry)
        }
        return page.map(\.time)
      }
      windowStart = windowEnd + 1
    }
    return out
  }

  /// `/fapi/v1/userTrades`：窗口不超过 7 天。第一页按时间段拉；满页之后改用 `fromId`（上一页最大成交 id + 1）
  /// 接着翻——币安不许 `fromId` 与时间段同用，但成交 id 在同一只品种里单调递增，按 id 翻不会漏掉
  /// 同一毫秒里挤着的成交；翻到超出窗口末尾的那一条就停。按成交 id 去重。
  func userTrades(symbol: String, from: Int64, to: Int64) async throws -> [Fill] {
    var out: [Fill] = []
    var seen: Set<Int64> = []
    var items: [(String, String)] = [("symbol", symbol), ("startTime", String(from)),
                                     ("endTime", String(to)), ("limit", String(pageLimit))]
    while true {
      try Task.checkCancellation()
      let data = try await signedGet(host: Self.futuresHost, path: "/fapi/v1/userTrades", items: items,
                                     weight: Weight.userTrades, limiter: futuresLimiter)
      let page = try Self.decode([UserTradeDTO].self, data)
      var pastEnd = false
      for dto in page {
        guard dto.time >= from, dto.time <= to else { pastEnd = pastEnd || dto.time > to; continue }
        if seen.insert(dto.id).inserted { out.append(try Self.fill(from: dto)) }
      }
      guard page.count >= pageLimit, !pastEnd, let maxID = page.map(\.id).max() else { break }
      items = [("symbol", symbol), ("fromId", String(maxID + 1)), ("limit", String(pageLimit))]
    }
    return out
  }

  func positionRisk() async throws -> [PositionDTO] {
    let data = try await signedGet(host: Self.futuresHost, path: "/fapi/v2/positionRisk", items: [],
                                   weight: Weight.positionRisk, limiter: futuresLimiter)
    return try Self.decode([PositionDTO].self, data)
  }

  /// 资金流水的时间游标翻页：一页满了就从这一页最晚的时间再拉（同一毫秒的几条靠去重兜住）；
  /// 一整页都挤在同一毫秒时游标往后挪 1 毫秒，保证一定往前走、不会原地打转
  /// （代价是同一毫秒超过一整页——1000 条——的流水会漏掉尾巴，现实里碰不到）。
  private func paginate(from: Int64, to: Int64,
                        page: (Int64) async throws -> [Int64]) async throws {
    var cursor = from
    while cursor <= to {
      try Task.checkCancellation()
      let times = try await page(cursor)
      guard times.count >= pageLimit, let last = times.max() else { return }
      cursor = last > cursor ? last : cursor + 1
    }
  }

  static func fill(from dto: UserTradeDTO) throws -> Fill {
    guard let side = TradeSide(rawValue: dto.side),
          let positionSide = PositionSide(rawValue: dto.positionSide),
          let price = TradeDecimal.parse(dto.price),
          let qty = TradeDecimal.parse(dto.qty),
          let commission = TradeDecimal.parse(dto.commission),
          let pnl = TradeDecimal.parse(dto.realizedPnl) else {
      throw ExchangeAccountError.invalidResponse
    }
    return Fill(id: String(dto.id), orderId: String(dto.orderId), symbol: dto.symbol, time: dto.time,
                side: side, positionSide: positionSide, price: price, qty: qty,
                quoteQty: dto.quoteQty.flatMap(TradeDecimal.parse),
                commission: commission, commissionAsset: dto.commissionAsset, realizedPnl: pnl,
                maker: dto.maker, marginAsset: dto.marginAsset ?? "USDT")
  }

  // MARK: - 签名请求

  private struct ErrorBody: Decodable { var code: Int? }

  /// 发一次签名 GET。-1021（时间戳超出 recvWindow）时向交易所校一次时间再发一次，仍被拒就报 `clockSkew`。
  private func signedGet(host: String, path: String, items: [(String, String)], weight: Int,
                         limiter: RateLimiter) async throws -> Data {
    do {
      return try await signedGetOnce(host: host, path: path, items: items, weight: weight, limiter: limiter)
    } catch ExchangeAccountError.clockSkew {
      try await syncClock()
      return try await signedGetOnce(host: host, path: path, items: items, weight: weight, limiter: limiter)
    }
  }

  private func signedGetOnce(host: String, path: String, items: [(String, String)], weight: Int,
                             limiter: RateLimiter) async throws -> Data {
    let query = signer.signedQuery(items, timestamp: clock() + clockOffsetMs, recvWindow: Self.recvWindow)
    var request = URLRequest(url: URL(string: "https://\(host)\(path)?\(query)")!)
    request.httpMethod = "GET"
    request.timeoutInterval = 15
    request.setValue(credentials.apiKey, forHTTPHeaderField: "X-MBX-APIKEY")
    return try await send(request, weight: weight, limiter: limiter)
  }

  /// `GET /fapi/v1/time`（公开、只读）：拿交易所时间算出和手机的偏差。
  private func syncClock() async throws {
    var request = URLRequest(url: URL(string: "https://\(Self.futuresHost)/fapi/v1/time")!)
    request.httpMethod = "GET"
    request.timeoutInterval = 10
    let sentAt = clock()
    let data = try await send(request, weight: Weight.serverTime, limiter: futuresLimiter)
    let receivedAt = clock()
    struct ServerTime: Decodable { var serverTime: Int64 }
    let server = try Self.decode(ServerTime.self, data).serverTime
    clockOffsetMs = server - (sentAt + receivedAt) / 2
  }

  private func send(_ request: URLRequest, weight: Int, limiter: RateLimiter) async throws -> Data {
    do {
      try await limiter.acquire(weight: weight)
    } catch is CancellationError {
      throw CancellationError()
    } catch {
      throw ExchangeAccountError.rateLimited
    }
    let reply: HTTPReply
    do {
      reply = try await http.send(request)
    } catch let error as URLError {
      if error.code == .cancelled { throw CancellationError() }
      throw ExchangeAccountError.classify(error)
    }
    if let used = reply.header("x-mbx-used-weight-1m").flatMap(Int.init) {
      await limiter.observe(usedWeight: used)
    }
    switch reply.status {
    case 200..<300:
      await limiter.succeeded()
      return reply.body
    case 418, 429:
      await limiter.penalize(status: reply.status,
                             retryAfterSeconds: reply.header("retry-after").flatMap(Double.init))
      throw ExchangeAccountError.rateLimited
    case 451, 403:
      throw ExchangeAccountError.regionBlocked
    case 401:
      throw ExchangeAccountError.invalidKey
    default:
      let code = (try? JSONDecoder().decode(ErrorBody.self, from: reply.body))?.code
      switch code {
      case -1021: throw ExchangeAccountError.clockSkew
      case -2014, -2015, -1022, -2008: throw ExchangeAccountError.invalidKey
      default: throw ExchangeAccountError.server(status: reply.status)
      }
    }
  }

  static func decode<T: Decodable>(_ type: T.Type, _ data: Data) throws -> T {
    do { return try JSONDecoder().decode(type, from: data) } catch {
      throw ExchangeAccountError.invalidResponse
    }
  }
}
