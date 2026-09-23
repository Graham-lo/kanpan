import Foundation
import Testing
@testable import KanpanNetwork
import KanpanNetworkTestSupport
import KanpanCore

// `/futures/data/*` 这一族（持仓量、多空比、主动买卖比、基差）与三条新流的解析。
// 下面每一段 JSON 都是 2026-09-22 当场打币安抓回来的原文，不是照文档编的。

@Suite("futures/data 三个端点")
struct FuturesDataRESTTests {

  private func rest(_ body: @escaping @Sendable (URL) -> HTTPReply)
    -> (BinanceREST, FakeServer, RateLimiter) {
    let pacer = StepPacer()
    let limiter = RateLimiter(pacer: pacer, minGapMs: 0)
    let server = FakeServer(pacer: pacer, handler: body)
    return (BinanceREST(transport: FakeTransport(server), limiter: limiter, pacer: pacer), server, limiter)
  }

  @Test("多空比：账户数比和两边占比都解得出，请求打在 globalLongShortAccountRatio 上", arguments: ["BTCUSDT", "binance/usd_m/BTCUSDT"])
  func longShortRatio(identity: String) async throws {
    let payload = #"[{"symbol":"BTCUSDT","longAccount":"0.4632","longShortRatio":"0.8629","shortAccount":"0.5368","timestamp":1790046000000}]"#
    let (client, server, _) = rest { _ in json(payload) }
    let points = try await client.globalLongShortAccountRatio(symbol: identity, period: "5m", limit: 500)
    #expect(points.count == 1)
    #expect(points[0].timeMs == 1_790_046_000_000)
    #expect(points[0].ratio == 0.8629)
    #expect(points[0].longAccount == 0.4632)
    #expect(points[0].shortAccount == 0.5368)
    let url = await server.urls().first
    #expect(url?.path == "/futures/data/globalLongShortAccountRatio")
    #expect(url?.query == "limit=500&period=5m&symbol=BTCUSDT")
  }

  /// 路径写成驼峰的 `takerLongShortRatio` 会 404。这条用例钉的就是那串小写。
  @Test("主动买卖比：路径是全小写的 takerlongshortRatio，响应里没有 symbol 也照解", arguments: ["BTCUSDT", "binance/usd_m/BTCUSDT"])
  func takerRatio(identity: String) async throws {
    let payload = #"[{"buySellRatio":"1.3692","sellVol":"186.4380","buyVol":"255.2790","timestamp":1790045700000}]"#
    let (client, server, _) = rest { _ in json(payload) }
    let points = try await client.takerLongShortRatio(symbol: identity, period: "5m", limit: 500)
    #expect(points.count == 1)
    #expect(points[0].buySellRatio == 1.3692)
    #expect(points[0].buyVolume == 255.2790)
    #expect(points[0].sellVolume == 186.4380)
    #expect(await server.urls().first?.path == "/futures/data/takerlongshortRatio")
  }

  /// 这条最容易写错两处：合约价的字段名是 `futuresPrice`（不是 `contractPrice`），
  /// 以及 `annualizedBasisRate` 实测就是空串——空串不能把整条记录判废。
  @Test("基差：pair + contractType 两个参数，futuresPrice 解得出，年化空串不判废", arguments: ["BTCUSDT", "binance/usd_m/BTCUSDT"])
  func basis(identity: String) async throws {
    let payload = #"[{"indexPrice":"85696.35239130","contractType":"PERPETUAL","basisRate":"-0.0003","futuresPrice":"85668.80","annualizedBasisRate":"","basis":"-27.55239130","pair":"BTCUSDT","timestamp":1790045700000}]"#
    let (client, server, _) = rest { _ in json(payload) }
    let points = try await client.basis(pair: identity, period: "5m", limit: 500)
    #expect(points.count == 1)                       // 空串没有把这条扔掉
    #expect(points[0].annualizedBasisRate == nil)    // 但它本身当「没有」
    #expect(points[0].basis == -27.55239130)
    #expect(points[0].basisRate == -0.0003)
    #expect(points[0].indexPrice == 85696.35239130)
    #expect(points[0].futuresPrice == 85668.80)
    let url = await server.urls().first
    #expect(url?.path == "/futures/data/basis")
    #expect(url?.query == "contractType=PERPETUAL&limit=500&pair=BTCUSDT&period=5m")
  }

  @Test("解不动的那一条跳过，同一页里好的照收")
  func badRowsAreSkippedNotFatal() async throws {
    let payload = """
    [{"symbol":"BTCUSDT","longShortRatio":"","timestamp":1790045700000},
     {"symbol":"BTCUSDT","longShortRatio":"0.8629","longAccount":"0.4632","shortAccount":"0.5368","timestamp":1790046000000},
     {"symbol":"ETHUSDT","longShortRatio":"1.2000","timestamp":1790046000000}]
    """
    let (client, _, _) = rest { _ in json(payload) }
    let points = try await client.globalLongShortAccountRatio(symbol: "BTCUSDT", period: "5m", limit: 500)
    #expect(points.count == 1)                 // 空串那条跳过，别人的品种那条也不要
    #expect(points[0].ratio == 0.8629)
  }

  /// 币安那 1000 次 / 5 分钟是按 IP 记在 `/futures/data/` **路径族**上的。
  /// 四个端点必须从同一个计数器里扣——各给一个桶等于名义 4000 次，撞上去
  /// 会连带把今天工作正常的持仓量一起打挂。
  @Test("四种 futures/data 请求扣的是同一个计数器")
  func futuresDataQuotaIsShared() async throws {
    let pacer = StepPacer()
    let limiter = RateLimiter(pacer: pacer, minGapMs: 0)
    let server = FakeServer(pacer: pacer) { url in
      switch url.path {
      case "/futures/data/openInterestHist":
        return json(#"[{"symbol":"BTCUSDT","sumOpenInterest":"50.0","sumOpenInterestValue":"1","timestamp":1790046000000}]"#)
      case "/futures/data/globalLongShortAccountRatio":
        return json(#"[{"symbol":"BTCUSDT","longAccount":"0.4632","longShortRatio":"0.8629","shortAccount":"0.5368","timestamp":1790046000000}]"#)
      case "/futures/data/takerlongshortRatio":
        return json(#"[{"buySellRatio":"1.3692","sellVol":"186.4380","buyVol":"255.2790","timestamp":1790045700000}]"#)
      default:
        return json(#"[{"indexPrice":"85696.35","contractType":"PERPETUAL","basisRate":"-0.0003","futuresPrice":"85668.80","annualizedBasisRate":"","basis":"-27.55","pair":"BTCUSDT","timestamp":1790045700000}]"#)
      }
    }
    let client = BinanceREST(transport: FakeTransport(server), limiter: limiter, pacer: pacer)

    _ = try await client.openInterestHist(symbol: "BTCUSDT", period: "5m", limit: 500)
    _ = try await client.globalLongShortAccountRatio(symbol: "BTCUSDT", period: "5m", limit: 500)
    _ = try await client.takerLongShortRatio(symbol: "BTCUSDT", period: "5m", limit: 500)
    _ = try await client.basis(pair: "BTCUSDT", period: "5m", limit: 500)

    #expect(await limiter.usedRequests(.futuresData) == 4)
    // 只有持仓量那一笔按权重 1 记账，新三条权重 0（上游这一族的权重就是 0）。
    #expect(await limiter.usedWeight() == 1)

    // 桶里剩下的 996 次打满之后，第 1001 次要等 5 分钟的窗口滚出去——
    // 这四个端点是在同一条队里排，不是各排各的。
    for _ in 0..<996 { try await limiter.acquire(weight: 0, quota: .futuresData) }
    #expect(await limiter.usedRequests(.futuresData) == 1000)
    let t0 = await pacer.nowMs()
    try await limiter.acquire(weight: 0, quota: .futuresData)
    #expect(await pacer.nowMs() - t0 >= 300_000)
  }
}

@Suite("逐笔 / 五档盘口的帧")
struct AggTradeDepthTests {

  private func payload(_ text: String) throws -> StreamPayload {
    let env = try JSONDecoder().decode(StreamEnvelope.self, from: Data(text.utf8))
    guard let p = env.payload else { throw FeedError.badResponse("没有 payload") }
    return p
  }

  /// `m` 是「买方是不是挂单方」：true 表示这笔是主动卖出。
  @Test("aggTrade：m == false 是主动买入，m == true 是主动卖出")
  func aggTradeTakerSide() throws {
    let buy = #"{"stream":"btcusdt@aggTrade","data":{"e":"aggTrade","E":1790046465702,"a":3460311795,"s":"BTCUSDT","p":"85595.90","q":"0.411","nq":"0.411","f":8105706701,"l":8105706719,"T":1790046465580,"m":false,"st":1}}"#
    guard case .aggTrade(let a) = try payload(buy) else { Issue.record("不是 aggTrade"); return }
    #expect(a.symbol == "BTCUSDT")
    #expect(a.price == 85595.90)
    #expect(a.qty == 0.411)
    #expect(a.aggID == 3_460_311_795)
    #expect(a.timeMs == 1_790_046_465_580)
    #expect(a.isBuyerMaker == false)
    #expect(a.takerIsBuyer)

    let sell = #"{"e":"aggTrade","E":1790046465702,"a":1,"s":"BTCUSDT","p":"85595.90","q":"0.411","T":1790046465580,"m":true}"#
    guard case .aggTrade(let b) = try payload(sell) else { Issue.record("不是 aggTrade"); return }
    #expect(b.isBuyerMaker)
    #expect(!b.takerIsBuyer)
  }

  /// `@depth5` 的事件名也叫 `depthUpdate`，但它是全量快照，不是增量。
  @Test("depth5：买五卖五各解成 (价, 量)，顺序原样保留")
  func depth5Snapshot() throws {
    let text = #"{"stream":"btcusdt@depth5@100ms","data":{"e":"depthUpdate","E":1790046434001,"T":1790046434000,"s":"BTCUSDT","ps":"BTCUSDT","U":11622543872680,"u":11622543895639,"pu":11622543872538,"b":[["85606.30","16.972"],["85606.20","0.049"],["85606.10","0.001"],["85606.00","3.276"],["85605.70","1.664"]],"a":[["85606.40","0.094"],["85606.50","0.003"],["85606.60","0.001"],["85606.70","0.002"],["85608.00","0.002"]],"st":1}}"#
    guard case .depth(let d) = try payload(text) else { Issue.record("不是 depth"); return }
    #expect(d.symbol == "BTCUSDT")
    #expect(d.timeMs == 1_790_046_434_000)       // 撮合时间 T
    #expect(d.bids.count == 5)
    #expect(d.asks.count == 5)
    #expect(d.bids.first == DepthLevel(price: 85606.30, qty: 16.972))
    #expect(d.bids.last == DepthLevel(price: 85605.70, qty: 1.664))
    #expect(d.asks.first == DepthLevel(price: 85606.40, qty: 0.094))
    #expect(d.asks.last == DepthLevel(price: 85608.00, qty: 0.002))
    // 买盘价格从高到低、卖盘从低到高，币安给的顺序不要重排。
    #expect(d.bids.map(\.price) == d.bids.map(\.price).sorted(by: >))
    #expect(d.asks.map(\.price) == d.asks.map(\.price).sorted(by: <))
  }

  @Test("两条流的流名")
  func streamNames() {
    #expect(BinanceHosts.aggTradeStream(symbol: "BTCUSDT") == "btcusdt@aggTrade")
    #expect(BinanceHosts.depth5Stream(symbol: "BTCUSDT") == "btcusdt@depth5@100ms")
    let url = BinanceHosts.default.combinedStream([
      BinanceHosts.depth5Stream(symbol: "BTCUSDT"),
      BinanceHosts.aggTradeStream(symbol: "BTCUSDT"),
    ])
    #expect(url.query == "streams=btcusdt@depth5@100ms/btcusdt@aggTrade")
  }
}
