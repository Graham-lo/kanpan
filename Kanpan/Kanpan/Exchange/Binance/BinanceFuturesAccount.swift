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
///   `GET /fapi/v2/positionRisk`（当前持仓、杠杆、标记价），外加公开的 `GET /fapi/v1/time`（对时）。
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
  /// 交易所时间 − 手机时间（毫秒）。每轮 `fetch` 开头校一次，遇到 -1021 再校一次。
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
  ///
  /// 判定是「默认拒收」：能动钱、能下单的五项（提现、内部划转、万向划转、现货杠杆交易、合约交易）
  /// 必须**明明白白写着 false** 才收，字段缺了就当开着——不能因为交易所改了返回格式、少回一个字段
  /// 就把一把能提现的 Key 当只读收下。另外 `enableReading` 必须是 true，不然后面什么也读不到。
  /// 杠杆、期权、统一账户、FIX 下单这几项不是每类账户都回，缺了不算，回了 true 照样拒收。
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
      guard enableReading == true else { return false }
      let required: [Bool?] = [enableWithdrawals, enableInternalTransfer, permitsUniversalTransfer,
                               enableSpotAndMarginTrading, enableFutures]
      guard required.allSatisfy({ $0 == false }) else { return false }
      let optional: [Bool?] = [enableMargin, enableVanillaOptions, enablePortfolioMarginTrading, enableFixApiTrade]
      return !optional.contains(true)
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

  /// 拉一轮。顺序有讲究：
  ///
  /// 1. 先向交易所对时（`/fapi/v1/time`），拿到交易所此刻的时间——这一轮签名请求都带对过的时间戳，
  ///    不用每一轮都先吃一次 -1021 再补救（provider 每轮新建，偏差存不住）。
  /// 2. 再拿持仓快照（`positionRisk`），把「交易所此刻」与各仓位最后变动时间（`updateTime`）里较晚的那个
  ///    记作这一轮的截止点 `asOf`。
  /// 3. 资金流水与成交都只拉到 `asOf` 为止，水位也记 `asOf`（交易所时间）。
  ///
  /// 为什么持仓要先拿：拼回合时第一次回溯用「当前持仓 − 窗口里成交的净变动」反推窗口起点的旧仓。
  /// 以前持仓最后才拿，回溯跑好几分钟，中间要是又成交一笔，持仓里有它、成交里没有，就凭空多出一份「旧仓」，
  /// 那个方向从此永远回不到 0、之后的回合全被吞掉。现在快照在前、成交截到快照时刻，两边对的是同一个时点；
  /// 快照之后的成交留给下一轮。
  ///
  /// 为什么水位用交易所时间：手机时间快了一小时以上，下一轮从「手机时间 − 1 小时」拉，就跳过了真实成交。
  /// `to`（手机时间）只当提示，不参与截止。
  func fetch(from: Int64, to: Int64) async throws -> ExchangeAccountBatch {
    let serverNow = try await syncClock()
    let positions = try await positionRisk()
    let asOf = max(serverNow, positions.compactMap(\.updateTime).max() ?? 0)

    var batch = ExchangeAccountBatch()
    batch.asOf = asOf
    for p in positions {
      if let mark = TradeDecimal.parse(p.markPrice), mark > 0 { batch.markPrices[p.symbol] = mark }
      let amount = TradeDecimal.parse(p.positionAmt) ?? 0
      if amount != 0, let side = PositionSide(rawValue: p.positionSide) {
        batch.positions[PositionKey(symbol: p.symbol, positionSide: side)] = amount
      }
    }
    guard from <= asOf else { return batch }

    // 1. 资金流水：资金费直接收下；已实现盈亏与手续费只当索引——哪只品种、哪个 7 天窗口里有成交。
    let income = try await incomeEntries(from: from, to: asOf)
    var activeWindows: [String: Set<Int64>] = [:]
    var everyWindow = Set(batch.positions.keys.map(\.symbol))
    for entry in income {
      guard !entry.symbol.isEmpty else { continue }
      // USDC 本位挂单常常零手续费：零手续费的开仓既没有手续费流水、也没有已实现盈亏，索引里看不到它。
      // 这类品种一旦在流水里露面（平仓盈亏、资金费），就把整段回溯的每个窗口都扫一遍。
      if entry.symbol.hasSuffix("USDC") { everyWindow.insert(entry.symbol) }
      switch entry.incomeType {
      case "FUNDING_FEE":
        guard let amount = TradeDecimal.parse(entry.income) else { continue }
        batch.funding.append(FundingEntry(id: String(entry.tranId), symbol: entry.symbol, time: entry.time,
                                          amount: amount, asset: entry.asset))
      case "REALIZED_PNL", "COMMISSION":
        activeWindows[entry.symbol, default: []].insert((entry.time - from) / Self.windowMs)
      default:
        continue
      }
    }
    // 2. 逐只品种、只拉有动静的那几个 7 天窗口的成交。眼下还持着仓的品种（以及上面的零手续费品种）
    //    整段每个窗口都拉：开仓那笔要是零手续费，流水里找不到它所在的窗口，漏了它这一仓就成了「旧仓」。
    let windowCount = (asOf - from) / Self.windowMs + 1
    for symbol in everyWindow {
      activeWindows[symbol, default: []].formUnion(0..<windowCount)
    }
    for symbol in activeWindows.keys.sorted() {
      for index in activeWindows[symbol, default: []].sorted() {
        let start = from + index * Self.windowMs
        guard start <= asOf else { continue }
        let end = min(asOf, start + Self.windowMs - 1)
        batch.fills += try await userTrades(symbol: symbol, from: start, to: end)
      }
    }
    batch.fills.sort { ($0.time, $0.id) < ($1.time, $1.id) }

    // 3. 杠杆：持着仓的、或这一轮有动静的品种。
    let touched = Set(batch.fills.map(\.symbol)).union(batch.funding.map(\.symbol))
    for p in positions {
      let amount = TradeDecimal.parse(p.positionAmt) ?? 0
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
    /// 这个仓位最后一次变动的交易所时间（毫秒）；空仓多半是 0。
    var updateTime: Int64?
  }

  /// `/fapi/v1/income`：按 7 天切窗，窗内按时间二分翻页（见 `userTrades`），按 tranId 去重。
  /// 一整页都挤在同一毫秒时不再往下分（同一毫秒上千条流水现实里碰不到），收下这一页就算。
  func incomeEntries(from: Int64, to: Int64) async throws -> [IncomeDTO] {
    var out: [IncomeDTO] = []
    var seen: Set<String> = []
    var windowStart = from
    while windowStart <= to {
      let windowEnd = min(to, windowStart + Self.windowMs - 1)
      var pending: [ClosedRange<Int64>] = [windowStart...windowEnd]
      while let range = pending.popLast() {
        try Task.checkCancellation()
        let data = try await signedGet(
          host: Self.futuresHost, path: "/fapi/v1/income",
          items: [("startTime", String(range.lowerBound)), ("endTime", String(range.upperBound)),
                  ("limit", String(pageLimit))],
          weight: Weight.income, limiter: futuresLimiter)
        let page = try Self.decode([IncomeDTO].self, data)
        for entry in page where range.contains(entry.time)
          && seen.insert("\(entry.tranId)|\(entry.incomeType)|\(entry.asset)").inserted {
          out.append(entry)
        }
        if page.count >= pageLimit, let halves = Self.split(range) {
          pending.append(halves.1)
          pending.append(halves.0)
        }
      }
      windowStart = windowEnd + 1
    }
    out.sort { ($0.time, $0.tranId) < ($1.time, $1.tranId) }
    return out
  }

  /// `/fapi/v1/userTrades`：窗口不超过 7 天。
  ///
  /// 翻页用**时间二分**：一段时间拉回整整一页，就说明这段里可能还有没拿到的，把它对半分开各拉一次，
  /// 直到每一段都不满一页。这样不依赖交易所按什么顺序返回——币安文档没写顺序，
  /// 论坛上官方人员又说过带时间段时回的是「最新的 1000 条」；要是按「最后一条的 id 往后翻」，
  /// 遇到倒着给的那一页就把前面的全跳过了。
  ///
  /// 只有一整页都挤在同一毫秒、时间没法再分时，才改用 `fromId` 从这一页最小的成交 id 往后翻
  /// （币安不许 `fromId` 与时间段同用；成交 id 在同一只品种里单调递增），翻到超出这一毫秒就停。
  /// 按「成交 id + 买卖方向」去重：自成交时同一个 id 会有买、卖两条，只按 id 去重会丢掉一边
  /// （拼回合那一层的去重键也带方向，见 `Fill.dedupeKey`）。
  func userTrades(symbol: String, from: Int64, to: Int64) async throws -> [Fill] {
    var out: [Fill] = []
    var seen: Set<String> = []
    var pending: [ClosedRange<Int64>] = from <= to ? [from...to] : []
    while let range = pending.popLast() {
      try Task.checkCancellation()
      let page = try await userTradesPage([("symbol", symbol), ("startTime", String(range.lowerBound)),
                                           ("endTime", String(range.upperBound)), ("limit", String(pageLimit))])
      for dto in page where range.contains(dto.time) && seen.insert(Self.dedupeKey(dto)).inserted {
        out.append(try Self.fill(from: dto))
      }
      guard page.count >= pageLimit else { continue }
      if let halves = Self.split(range) {
        pending.append(halves.1)
        pending.append(halves.0)
        continue
      }
      // 同一毫秒挤满一整页：按成交 id 往后翻。
      guard var fromID = page.map(\.id).min() else { continue }
      while true {
        try Task.checkCancellation()
        let next = try await userTradesPage([("symbol", symbol), ("fromId", String(fromID)),
                                             ("limit", String(pageLimit))])
        var pastEnd = false
        for dto in next {
          guard range.contains(dto.time) else { pastEnd = pastEnd || dto.time > range.upperBound; continue }
          if seen.insert(Self.dedupeKey(dto)).inserted { out.append(try Self.fill(from: dto)) }
        }
        guard next.count >= pageLimit, !pastEnd, let maxID = next.map(\.id).max(), maxID >= fromID else { break }
        fromID = maxID + 1
      }
    }
    out.sort { ($0.time, $0.id) < ($1.time, $1.id) }
    return out
  }

  static func dedupeKey(_ dto: UserTradeDTO) -> String { "\(dto.id)|\(dto.side)|\(dto.positionSide)" }

  private func userTradesPage(_ items: [(String, String)]) async throws -> [UserTradeDTO] {
    let data = try await signedGet(host: Self.futuresHost, path: "/fapi/v1/userTrades", items: items,
                                   weight: Weight.userTrades, limiter: futuresLimiter)
    return try Self.decode([UserTradeDTO].self, data)
  }

  func positionRisk() async throws -> [PositionDTO] {
    let data = try await signedGet(host: Self.futuresHost, path: "/fapi/v2/positionRisk", items: [],
                                   weight: Weight.positionRisk, limiter: futuresLimiter)
    return try Self.decode([PositionDTO].self, data)
  }

  /// 把一段时间对半分成不重叠的两段；只剩一毫秒时分不开，返回 nil。
  static func split(_ range: ClosedRange<Int64>) -> (ClosedRange<Int64>, ClosedRange<Int64>)? {
    guard range.upperBound > range.lowerBound else { return nil }
    let mid = range.lowerBound + (range.upperBound - range.lowerBound) / 2
    return (range.lowerBound...mid, (mid + 1)...range.upperBound)
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
    // 查询串原样塞进 `percentEncodedQuery`，不让 `URL` 再替我们转义一遍：签的那一串必须就是发出去的那一串。
    var components = URLComponents()
    components.scheme = "https"
    components.host = host
    components.path = path
    components.percentEncodedQuery = query
    guard let url = components.url, url.query(percentEncoded: true) == query else {
      throw ExchangeAccountError.invalidResponse
    }
    var request = URLRequest(url: url)
    request.httpMethod = "GET"
    request.timeoutInterval = 15
    request.setValue(credentials.apiKey, forHTTPHeaderField: "X-MBX-APIKEY")
    return try await send(request, weight: weight, limiter: limiter)
  }

  /// `GET /fapi/v1/time`（公开、只读）：拿交易所时间算出和手机的偏差，并返回交易所此刻的时间。
  @discardableResult
  private func syncClock() async throws -> Int64 {
    var request = URLRequest(url: URL(string: "https://\(Self.futuresHost)/fapi/v1/time")!)
    request.httpMethod = "GET"
    request.timeoutInterval = 10
    let sentAt = clock()
    let data = try await send(request, weight: Weight.serverTime, limiter: futuresLimiter)
    let receivedAt = clock()
    struct ServerTime: Decodable { var serverTime: Int64 }
    let server = try Self.decode(ServerTime.self, data).serverTime
    clockOffsetMs = server - (sentAt + receivedAt) / 2
    return server
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
