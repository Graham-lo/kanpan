import Foundation
import KanpanCore
import KanpanNetwork
import Testing
@testable import Kanpan

@Suite("自动复盘 · 币安合约只读账户")
struct BinanceFuturesAccountTests {
  typealias F = ExchangeFixture

  @Test("签名对得上币安文档的示例向量")
  func signatureMatchesTheDocumentedVector() {
    // 来源：币安 API 文档「SIGNED (TRADE / USER_DATA / MARGIN) Endpoint security」→
    // 「HMAC Keys · Signature Examples」那组示例（Key vmPUZE6m…、Secret NhqPtmdS…）。
    // 这里只拿它验 HMAC 的算法与十六进制写法；示例查询串是文档原文，本 app 从不发那种请求。
    let signer = BinanceRequestSigner(secret: "NhqPtmdSJYdKjVHjA7PZj4Mge3R5YNiP1e3UZjInClVN65XAbvqqM6A7H5fATj0j")
    let query = "symbol=LTCBTC&side=BUY&type=LIMIT&timeInForce=GTC&quantity=1&price=0.1"
      + "&recvWindow=5000&timestamp=1499827319559"
    #expect(signer.signature(for: query) == "c8db56825ae71d6d79447849e617115f4a920fa2acdcab2b053c4b2838bd6b71")
  }

  @Test("签名请求：Key 在请求头，查询串末尾是 recvWindow、timestamp、signature，签的就是发的那一串")
  func signedRequestShape() async throws {
    let http = MockExchangeHTTP()
    http.onJSON("/sapi/v1/account/apiRestrictions", F.readOnlyRestrictions)
    http.onJSON("/fapi/v2/positionRisk", F.flatPositions)
    let clock = ExchangeTestClock(F.t0)
    try await F.account(http, clock: clock).verifyReadOnly()

    let request = try #require(http.requests(to: "/sapi/v1/account/apiRestrictions").first)
    #expect(request.httpMethod == "GET")
    #expect(request.url?.host == "api.binance.com")
    #expect(request.value(forHTTPHeaderField: "X-MBX-APIKEY") == "test-key-ABCD")
    let query = try #require(request.url?.query)
    let parts = query.components(separatedBy: "&signature=")
    #expect(parts.count == 2)
    #expect(parts[0] == "recvWindow=10000&timestamp=\(F.t0)")
    #expect(parts[1] == BinanceRequestSigner(secret: "test-secret").signature(for: parts[0]))
    // Secret 从不出站。
    #expect(!(request.url?.absoluteString.contains("test-secret") ?? true))
    #expect(request.allHTTPHeaderFields?.values.contains("test-secret") == false)

    let futures = try #require(http.requests(to: "/fapi/v2/positionRisk").first)
    #expect(futures.url?.host == BinanceProvider.defaultRestHost)
  }

  @Test("有提现 / 现货杠杆交易 / 合约交易任一权限的 Key 一律拒收", arguments: [
    (true, false, false), (false, true, false), (false, false, true),
  ])
  func nonReadOnlyKeysAreRejected(flags: (Bool, Bool, Bool)) async throws {
    let http = MockExchangeHTTP()
    http.onJSON("/sapi/v1/account/apiRestrictions",
                F.restrictions(withdrawals: flags.0, spot: flags.1, futures: flags.2))
    http.onJSON("/fapi/v2/positionRisk", F.flatPositions)
    await #expect(throws: ExchangeAccountError.notReadOnly) {
      try await F.account(http, clock: ExchangeTestClock(F.t0)).verifyReadOnly()
    }
  }

  @Test("交易所的错误码翻成固定的中文，不念原文")
  func errorMapping() async throws {
    let cases: [(Int, String, ExchangeAccountError)] = [
      (401, #"{"code":-2015,"msg":"Invalid API-key, IP, or permissions for action."}"#, .invalidKey),
      (400, #"{"code":-2014,"msg":"API-key format invalid."}"#, .invalidKey),
      (451, #"{"code":0,"msg":"Service unavailable from a restricted location"}"#, .regionBlocked),
      (403, "<html>WAF</html>", .regionBlocked),
      (429, #"{"code":-1003,"msg":"Too many requests"}"#, .rateLimited),
      (500, "oops", .server(status: 500)),
    ]
    for (status, body, expected) in cases {
      let http = MockExchangeHTTP()
      http.onJSON("/sapi/v1/account/apiRestrictions", status: status, body)
      await #expect(throws: expected) {
        try await F.account(http, clock: ExchangeTestClock(F.t0)).verifyReadOnly()
      }
      #expect(!expected.message.contains("Invalid"))
    }
    #expect(ExchangeAccountError.message(URLError(.notConnectedToInternet)) == ExchangeAccountError.offline.message)
    #expect(ExchangeAccountError.message(URLError(.badServerResponse)) == ExchangeAccountError.genericFailure)
  }

  @Test("-1021 时向交易所校一次时间再发，时间戳带上偏差")
  func clockSkewIsCorrectedOnce() async throws {
    let http = MockExchangeHTTP()
    let serverAhead: Int64 = 30_000
    let clock = ExchangeTestClock(F.t0)
    http.on("/sapi/v1/account/apiRestrictions") { _, q in
      let ts = Int64(q["timestamp"] ?? "0") ?? 0
      if abs(ts - (F.t0 + serverAhead)) > 1_000 {
        return HTTPReply(status: 400, body: Data(#"{"code":-1021,"msg":"Timestamp outside recvWindow"}"#.utf8))
      }
      return HTTPReply(status: 200, body: Data(F.readOnlyRestrictions.utf8))
    }
    http.onJSON("/fapi/v1/time", #"{"serverTime":\#(F.t0 + serverAhead)}"#)
    http.on("/fapi/v2/positionRisk") { _, q in
      #expect(Int64(q["timestamp"] ?? "0") == F.t0 + serverAhead)
      return HTTPReply(status: 200, body: Data(F.flatPositions.utf8))
    }
    try await F.account(http, clock: clock).verifyReadOnly()
    #expect(http.requests(to: "/fapi/v1/time").count == 1)
    #expect(http.requests(to: "/sapi/v1/account/apiRestrictions").count == 2)
  }

  @Test("分页拼接：资金流水按 7 天切窗、满页接着翻；成交只拉有动静的窗口，满页改用 fromId，一条不漏不重")
  func pagesAreStitched() async throws {
    let http = MockExchangeHTTP()
    let from = F.t0
    let to = F.t0 + 20 * F.day
    // 第 0 个窗口：三笔成交，其中两笔同一毫秒；第 2 个窗口：两笔。第 1 个窗口没有成交。
    let a = from + F.day
    let b = from + 15 * F.day
    let trades: [(id: Int64, time: Int64, json: String)] = [
      (101, a, F.trade(id: 101, time: a, side: "BUY", price: "60000", qty: "0.1")),
      (102, a, F.trade(id: 102, time: a, side: "BUY", price: "60010", qty: "0.1")),
      (103, a + 5_000, F.trade(id: 103, time: a + 5_000, side: "SELL", price: "61000", qty: "0.2", pnl: "199")),
      (201, b, F.trade(id: 201, time: b, side: "SELL", price: "62000", qty: "0.1")),
      (202, b + 60_000, F.trade(id: 202, time: b + 60_000, side: "BUY", price: "61500", qty: "0.1", pnl: "50")),
      // 窗口外（第 2 个窗口之后）的成交，fromId 翻页时会被带回来，必须丢掉。
      (301, to + F.day, F.trade(id: 301, time: to + F.day, side: "BUY", price: "1", qty: "1")),
    ]
    let income: [(time: Int64, json: String)] = [
      (a, F.income(tranId: 1, time: a, type: "COMMISSION", amount: "-0.1")),
      (a, F.income(tranId: 2, time: a, type: "COMMISSION", amount: "-0.1")),
      (a + 5_000, F.income(tranId: 3, time: a + 5_000, type: "REALIZED_PNL", amount: "199")),
      (a + 8 * 3_600_000, F.income(tranId: 4, time: a + 8 * 3_600_000, type: "FUNDING_FEE", amount: "-0.5")),
      (a + 9 * 3_600_000, F.income(tranId: 5, time: a + 9 * 3_600_000, type: "TRANSFER", amount: "100",
                                   symbol: "")),
      (b + 60_000, F.income(tranId: 6, time: b + 60_000, type: "REALIZED_PNL", amount: "50")),
    ]
    http.on("/fapi/v1/income", F.serveIncome(income))
    http.on("/fapi/v1/userTrades", F.serveTrades(trades))
    http.onJSON("/fapi/v2/positionRisk", F.flatPositions)

    let batch = try await F.account(http, clock: ExchangeTestClock(to), pageLimit: 2).fetch(from: from, to: to)

    #expect(batch.fills.map(\.id) == ["101", "102", "103", "201", "202"])
    #expect(batch.funding.map(\.id) == ["4"])
    #expect(batch.funding.first?.amount == Decimal(string: "-0.5"))
    #expect(batch.leverage["BTCUSDT"] == 10)
    #expect(batch.markPrices["BNBUSDT"] == Decimal(600))
    #expect(batch.positions.isEmpty)

    // 三个 7 天窗口都查了资金流水；第 0 个窗口满页（limit 2）要翻页。
    let incomeCalls = http.requests(to: "/fapi/v1/income").map(MockExchangeHTTP.query)
    #expect(Set(incomeCalls.compactMap { $0["endTime"] }).count == 3)
    #expect(incomeCalls.count >= 4)
    // 成交只拉了第 0 与第 2 个窗口；满页之后改用 fromId、不带时间段。
    let tradeCalls = http.requests(to: "/fapi/v1/userTrades").map(MockExchangeHTTP.query)
    let windows = Set(tradeCalls.compactMap { $0["startTime"].flatMap(Int64.init) })
    #expect(windows == [from, from + 14 * F.day])
    #expect(tradeCalls.contains { $0["fromId"] == "103" && $0["startTime"] == nil })
    #expect(tradeCalls.allSatisfy { $0["symbol"] == "BTCUSDT" })
    // 每一次都是 GET。
    #expect(http.requests.allSatisfy { $0.httpMethod == "GET" })
  }
}
