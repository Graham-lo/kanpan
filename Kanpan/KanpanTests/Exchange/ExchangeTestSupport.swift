import Foundation
import KanpanCore
import KanpanNetwork
@testable import Kanpan

/// 假的交易所：按路径分派，记下每一次请求。
final class MockExchangeHTTP: ExchangeHTTP, @unchecked Sendable {
  typealias Handler = @Sendable (URLRequest, [String: String]) throws -> HTTPReply
  private let lock = NSLock()
  private var handlers: [String: Handler] = [:]
  private var log: [URLRequest] = []

  func on(_ path: String, _ handler: @escaping Handler) {
    lock.withLock { handlers[path] = handler }
  }

  func onJSON(_ path: String, status: Int = 200, _ json: String) {
    on(path) { _, _ in HTTPReply(status: status, body: Data(json.utf8)) }
  }

  var requests: [URLRequest] { lock.withLock { log } }

  func requests(to path: String) -> [URLRequest] { requests.filter { $0.url?.path == path } }

  func send(_ request: URLRequest) async throws -> HTTPReply {
    let handler: Handler? = lock.withLock {
      log.append(request)
      return handlers[request.url?.path ?? ""]
    }
    guard let handler else { return HTTPReply(status: 404, body: Data(#"{"code":-1,"msg":"x"}"#.utf8)) }
    return try handler(request, Self.query(request))
  }

  static func query(_ request: URLRequest) -> [String: String] {
    let items = URLComponents(url: request.url!, resolvingAgainstBaseURL: false)?.queryItems ?? []
    return Dictionary(items.map { ($0.name, $0.value ?? "") }, uniquingKeysWith: { $1 })
  }
}

/// 测试用的时钟。
final class ExchangeTestClock: @unchecked Sendable {
  private let lock = NSLock()
  private var value: Int64
  init(_ start: Int64) { value = start }
  var now: Int64 { lock.withLock { value } }
  func advance(_ ms: Int64) { lock.withLock { value += ms } }
  var closure: @Sendable () -> Int64 { { [self] in now } }
}

/// 收回合的地方。
actor RoundSink {
  private(set) var batches: [[TradeRound]] = []
  func take(_ rounds: [TradeRound]) { batches.append(rounds) }
}

enum ExchangeFixture {
  static let day: Int64 = 86_400_000
  /// 2026-09-01 00:00 UTC。
  static let t0: Int64 = 1_788_220_800_000

  static let readOnlyRestrictions = #"""
  {"ipRestrict":true,"createTime":1698645219000,"enableReading":true,"enableWithdrawals":false,
   "enableInternalTransfer":false,"enableMargin":false,"enableFutures":false,"permitsUniversalTransfer":false,
   "enableVanillaOptions":false,"enableFixApiTrade":false,"enableFixReadOnly":true,
   "enableSpotAndMarginTrading":false,"enablePortfolioMarginTrading":false}
  """#

  static func restrictions(withdrawals: Bool = false, spot: Bool = false, futures: Bool = false) -> String {
    readOnlyRestrictions
      .replacingOccurrences(of: #""enableWithdrawals":false"#, with: #""enableWithdrawals":\#(withdrawals)"#)
      .replacingOccurrences(of: #""enableSpotAndMarginTrading":false"#,
                            with: #""enableSpotAndMarginTrading":\#(spot)"#)
      .replacingOccurrences(of: #""enableFutures":false"#, with: #""enableFutures":\#(futures)"#)
  }

  static let flatPositions = #"""
  [{"symbol":"BTCUSDT","positionAmt":"0.000","entryPrice":"0.0","markPrice":"60000.00","unRealizedProfit":"0",
    "liquidationPrice":"0","leverage":"10","maxNotionalValue":"1000000","marginType":"cross",
    "isolatedMargin":"0","isAutoAddMargin":"false","positionSide":"BOTH","notional":"0",
    "isolatedWallet":"0","updateTime":0},
   {"symbol":"BNBUSDT","positionAmt":"0","entryPrice":"0","markPrice":"600.0","leverage":"20",
    "positionSide":"BOTH"}]
  """#

  static func trade(id: Int64, time: Int64, side: String, price: String, qty: String,
                    pnl: String = "0", symbol: String = "BTCUSDT") -> String {
    #"{"symbol":"\#(symbol)","id":\#(id),"orderId":\#(id * 10),"side":"\#(side)","price":"\#(price)","#
      + #""qty":"\#(qty)","realizedPnl":"\#(pnl)","marginAsset":"USDT","quoteQty":"0","commission":"0.1","#
      + #""commissionAsset":"USDT","time":\#(time),"positionSide":"BOTH","buyer":\#(side == "BUY"),"maker":false}"#
  }

  static func income(tranId: Int64, time: Int64, type: String, amount: String,
                     symbol: String = "BTCUSDT") -> String {
    #"{"symbol":"\#(symbol)","incomeType":"\#(type)","income":"\#(amount)","asset":"USDT","info":"","#
      + #""time":\#(time),"tranId":\#(tranId),"tradeId":""}"#
  }

  static func limiter() -> RateLimiter { RateLimiter(budget: 1_000_000, minGapMs: 0) }

  static func account(_ http: MockExchangeHTTP, clock: ExchangeTestClock, pageLimit: Int = 1000) -> BinanceFuturesAccount {
    BinanceFuturesAccount(credentials: ExchangeCredentials(apiKey: "test-key-ABCD", secret: "test-secret"),
                          http: http, futuresLimiter: limiter(), spotLimiter: limiter(),
                          pageLimit: pageLimit, clock: clock.closure)
  }

  /// 按查询参数从一份成交表里切页，行为照币安：时间段或 fromId 二选一，升序，截到 limit。
  static func serveTrades(_ rows: [(id: Int64, time: Int64, json: String)]) -> MockExchangeHTTP.Handler {
    { _, q in
      let limit = Int(q["limit"] ?? "500") ?? 500
      var picked = rows.sorted { $0.id < $1.id }
      if let fromId = q["fromId"].flatMap(Int64.init) {
        // 币安不许 fromId 与时间段同用。
        if q["startTime"] != nil || q["endTime"] != nil {
          return HTTPReply(status: 400, body: Data(#"{"code":-1128,"msg":"x"}"#.utf8))
        }
        picked = picked.filter { $0.id >= fromId }
      } else {
        let start = Int64(q["startTime"] ?? "0") ?? 0
        let end = Int64(q["endTime"] ?? "\(Int64.max)") ?? .max
        picked = picked.filter { $0.time >= start && $0.time <= end }
      }
      let page = picked.prefix(limit).map(\.json).joined(separator: ",")
      return HTTPReply(status: 200, body: Data("[\(page)]".utf8))
    }
  }

  static func serveIncome(_ rows: [(time: Int64, json: String)]) -> MockExchangeHTTP.Handler {
    { _, q in
      let limit = Int(q["limit"] ?? "100") ?? 100
      let start = Int64(q["startTime"] ?? "0") ?? 0
      let end = Int64(q["endTime"] ?? "\(Int64.max)") ?? .max
      let page = rows.filter { $0.time >= start && $0.time <= end }.sorted { $0.time < $1.time }
        .prefix(limit).map(\.json).joined(separator: ",")
      return HTTPReply(status: 200, body: Data("[\(page)]".utf8))
    }
  }
}
