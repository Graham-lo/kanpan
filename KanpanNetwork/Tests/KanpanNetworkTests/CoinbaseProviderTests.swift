import Foundation
import Testing
@testable import KanpanNetwork
import KanpanNetworkTestSupport
import KanpanCore

// 多交易所 阶段 3：Coinbase 现货提供者。报文样本都是 2026-09-22 实测抓回来的原样格式。

@Suite("Coinbase 报文翻译")
struct CoinbaseDTOTests {

  @Test("ISO 时间：九位小数、四位小数、无小数都认；不是 UTC 写法的丢掉")
  func isoMs() {
    #expect(CoinbaseDTO.isoMs("1970-01-01T00:00:00Z") == 0)
    #expect(CoinbaseDTO.isoMs("2026-09-22T23:19:46.9835Z") == 1_790_119_186_983)
    #expect(CoinbaseDTO.isoMs("2026-09-22T23:19:46.408897699Z") == 1_790_119_186_408)
    #expect(CoinbaseDTO.isoMs("2024-02-29T12:00:00Z") == 1_709_208_000_000)
    #expect(CoinbaseDTO.isoMs("2026-09-22T23:19:46+08:00") == nil)
    #expect(CoinbaseDTO.isoMs("garbage") == nil)
  }

  /// 步长不是 10 的整数次幂时（`0.25`、`0.5`、`0.005`），小数位按字面数，不按 `⌈-log10⌉`。
  @Test("小数位按步长的字面数：0.25 是两位，末尾的 0 不算，科学计数法按指数折算")
  func decimalsFromLiteral() throws {
    #expect(CoinbaseDTO.decimals("0.25") == 2)
    #expect(CoinbaseDTO.decimals("0.5") == 1)
    #expect(CoinbaseDTO.decimals("0.005") == 3)
    #expect(CoinbaseDTO.decimals("0.01") == 2)
    #expect(CoinbaseDTO.decimals("0.010") == 2)
    #expect(CoinbaseDTO.decimals("0.00000001") == 8)
    #expect(CoinbaseDTO.decimals("1") == 0)
    #expect(CoinbaseDTO.decimals("10") == 0)
    #expect(CoinbaseDTO.decimals("1.0") == 0)
    #expect(CoinbaseDTO.decimals("1e-8") == 8)
    #expect(CoinbaseDTO.decimals("2.5E-3") == 4)
    let body = Data(#"""
    {"products":[{"product_id":"QTR-USD","price":"3.25","price_increment":"0.25","base_increment":"0.5",
      "quote_currency_id":"USD","status":"online","product_type":"SPOT"}]}
    """#.utf8)
    let info = try #require(try CoinbaseProvider.products(body).first?.symbolInfo)
    #expect(info.pricePrecision == 2 && info.quantityPrecision == 1 && info.tickSize == 0.25)
  }

  @Test("K 线页：降序 → 升序，秒 → 毫秒，字符串 → 数")
  func candlesAscending() throws {
    let body = Data(#"""
    {"candles":[
      {"start":"1790118000","low":"100","high":"110","open":"101","close":"109","volume":"2.5"},
      {"start":"1790114400","low":"90","high":"105","open":"95","close":"101","volume":"1"}
    ]}
    """#.utf8)
    let bars = try CoinbaseDTO.bars(body)
    #expect(bars.map(\.openTime) == [1_790_114_400_000, 1_790_118_000_000])
    #expect(bars[1].close == 109 && bars[1].volume == 2.5)
  }

  @Test("品种表：只收美元、在线、现货、非只读；tickSize 取 price_increment；键是 coinbase/spot/…")
  func productsFilter() throws {
    let body = Data(#"""
    {"products":[
      {"product_id":"BTC-USD","price":"63000.01","price_percentage_change_24h":"2","volume_24h":"10",
       "high_24h":"64000","low_24h":"61000","base_increment":"0.00000001","price_increment":"0.01",
       "base_display_symbol":"BTC","quote_currency_id":"USD","status":"online","product_type":"SPOT",
       "view_only":false,"trading_disabled":false,"cancel_only":false,"is_disabled":false},
      {"product_id":"BTC-USDC","price":"63000","price_increment":"0.01","quote_currency_id":"USDC",
       "status":"online","product_type":"SPOT"},
      {"product_id":"OLD-USD","price":"1","price_increment":"0.001","quote_currency_id":"USD",
       "status":"delisted","product_type":"SPOT"},
      {"product_id":"VIEW-USD","price":"1","price_increment":"0.001","quote_currency_id":"USD",
       "status":"online","product_type":"SPOT","view_only":true},
      {"product_id":"BTC-PERP-INTX","price":"1","price_increment":"0.1","quote_currency_id":"USD",
       "status":"online","product_type":"FUTURE"}
    ]}
    """#.utf8)
    let listed = try CoinbaseProvider.products(body).filter(\.isListed)
    #expect(listed.map(\.product_id) == ["BTC-USD"])
    let info = try #require(listed[0].symbolInfo)
    #expect(info.symbol == "coinbase/spot/BTC-USD")
    #expect(info.base == "BTC" && info.quote == "USD")
    #expect(info.tickSize == 0.01 && info.pricePrecision == 2)
    let t = try #require(listed[0].ticker)
    #expect(t.last == 63000.01)
    #expect(abs(t.quoteVolume - 630_000.1) < 1e-6)   // 额 = base 量 × 现价
    #expect(abs((t.open24h ?? 0) - 63000.01 / 1.02) < 1e-6)
  }

  @Test("推送：成交快照不收、更新翻成升序；K 线快照只留最新一根；24h 行情照收")
  func wsPayloads() throws {
    func frame(_ s: String) throws -> CoinbaseDTO.Frame {
      try JSONDecoder().decode(CoinbaseDTO.Frame.self, from: Data(s.utf8))
    }
    let trades = try frame(#"""
    {"channel":"market_trades","timestamp":"2026-09-22T23:19:47Z","sequence_num":3,"events":[
      {"type":"snapshot","trades":[{"product_id":"BTC-USD","trade_id":"1","price":"1","size":"1","time":"2026-09-22T23:00:00Z","side":"BUY"}]},
      {"type":"update","trades":[
        {"product_id":"BTC-USD","trade_id":"11","price":"63001","size":"0.2","time":"2026-09-22T23:19:46.5Z","side":"SELL"},
        {"product_id":"BTC-USD","trade_id":"10","price":"63000","size":"0.1","time":"2026-09-22T23:19:46.1Z","side":"BUY"}]}]}
    """#)
    let tp = CoinbaseDTO.payloads(trades, candleInterval: .m5)
    #expect(tp.count == 2)
    guard case .trade(let first) = tp[0], case .trade(let second) = tp[1] else {
      Issue.record("应该是两笔成交"); return
    }
    #expect(first.tradeID == 10 && second.tradeID == 11)
    #expect(first.symbol == "coinbase/spot/BTC-USD" && first.timeMs < second.timeMs)

    let candles = try frame(#"""
    {"channel":"candles","timestamp":"2026-09-22T23:19:47Z","events":[{"type":"snapshot","candles":[
      {"start":"1790118900","high":"2","low":"1","open":"1","close":"2","volume":"3","product_id":"BTC-USD"},
      {"start":"1790119200","high":"3","low":"1","open":"2","close":"3","volume":"4","product_id":"BTC-USD"}]}]}
    """#)
    let cp = CoinbaseDTO.payloads(candles, candleInterval: .m5)
    #expect(cp.count == 1)
    guard case .kline(let k) = cp.first else { Issue.record("应该是一根 K 线"); return }
    #expect(k.openTime == 1_790_119_200_000 && k.interval == "5m" && !k.closed)

    let ticker = try frame(#"""
    {"channel":"ticker","timestamp":"2026-09-22T23:19:47Z","events":[{"type":"update","tickers":[
      {"type":"ticker","product_id":"ETH-USD","price":"2500","volume_24_h":"100","low_24_h":"2400",
       "high_24_h":"2600","price_percent_chg_24_h":"-1.5"}]}]}
    """#)
    guard case .ticker(let t) = CoinbaseDTO.payloads(ticker, candleInterval: .m5).first else {
      Issue.record("应该是一条 24h 行情"); return
    }
    #expect(t.symbol == "coinbase/spot/ETH-USD" && t.high == 2600 && t.low == 2400 && t.quoteVolume == 250_000)
  }
}

@Suite("Coinbase REST 翻页与线路")
struct CoinbaseRESTTests {
  /// 按请求的 [start, end]（秒，两端都含）造一页 1h K 线，降序给——和线上一样。
  private static func candlePage(_ url: URL) -> HTTPReply {
    let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
    func q(_ k: String) -> Int64? { items.first { $0.name == k }?.value.flatMap { Int64($0) } }
    guard let start = q("start"), let end = q("end") else { return json("{}", status: 400) }
    // 线上规矩：跨度要小于 350 步。
    guard (end - start) / 3600 < 350 else { return json(#"{"error":"INVALID_ARGUMENT"}"#, status: 400) }
    let rows = stride(from: end, through: start, by: -3600).map {
      #"{"start":"\#($0)","low":"1","high":"2","open":"1","close":"2","volume":"1"}"#
    }
    return json(#"{"candles":[\#(rows.joined(separator: ","))]}"#)
  }

  private static let now = Date(timeIntervalSince1970: 1_790_119_186)

  private func provider(_ server: FakeServer, policy: MarketRoutePolicy = .direct) -> CoinbaseProvider {
    CoinbaseProvider(policy: policy, gateways: ["gw1.example", "gw2.example"], transport: FakeTransport(server),
                     limiter: CoinbaseRateLimiter(perSecond: 1_000_000, pacer: FastPacer()),
                     clock: { Self.now })
  }

  @Test("要 700 根：拆成两个 350 根的窗口，拼回来升序、连续、不重不漏")
  func pagesBackward() async throws {
    let server = FakeServer { Self.candlePage($0) }
    let bars = try await provider(server).klines(symbol: "coinbase/spot/BTC-USD", interval: .h1, limit: 700,
                                                 startTime: nil, endTime: nil)
    #expect(bars.count == 700)
    #expect(zip(bars, bars.dropFirst()).allSatisfy { $1.openTime - $0.openTime == 3_600_000 })
    let last: Int64 = try #require(bars.last?.openTime)
    #expect(last == 1_790_118_000_000)   // 当前这一小时（1_790_119_186 秒向下取整）
    let urls = await server.urls()
    #expect(urls.count == 2)
    #expect(urls.allSatisfy { $0.host == "api.coinbase.com" && $0.path == "/api/v3/brokerage/market/products/BTC-USD/candles" })
  }

  @Test("聚合周期按源周期取：3m 取 1m，一周取日线")
  func aggregatedSource() async throws {
    let server = FakeServer { url in
      let g = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?.first { $0.name == "granularity" }?.value
      #expect(g == "ONE_DAY")
      return json(#"{"candles":[]}"#)
    }
    _ = try await provider(server).klines(symbol: "coinbase/spot/BTC-USD", interval: .w1, limit: 10,
                                          startTime: nil, endTime: nil)
    #expect(await server.urls().count == 1)
  }

  @Test("网关线路：打 /v1/market/raw/… 带 source=coinbase；主网关 5xx 换备用")
  func gatewayFallback() async throws {
    let server = FakeServer { url in
      url.host == "gw1.example" ? json("{}", status: 502) : json(#"{"candles":[]}"#)
    }
    _ = try await provider(server, policy: .gateway).klines(symbol: "coinbase/spot/ETH-USD", interval: .m5, limit: 5,
                                                            startTime: nil, endTime: nil)
    let urls = await server.urls()
    #expect(urls.map(\.host) == ["gw1.example", "gw2.example"])
    #expect(urls[1].path == "/v1/market/raw/products/ETH-USD/candles")
    #expect(urls[1].query?.hasPrefix("source=coinbase&") == true)
  }

  @Test("备用网关带端口：REST 与推送地址都拼得出来")
  func gatewayWithPort() {
    let e = CoinbaseEndpoints(policy: .gateway, gateways: ["a.example", "b.example:8443"])
    #expect(e.rest("products", host: "b.example:8443")?.absoluteString
            == "https://b.example:8443/v1/market/raw/products?source=coinbase")
    #expect(e.streams.map(\.absoluteString) == ["wss://a.example/v1/market/stream?source=coinbase",
                                                "wss://b.example:8443/v1/market/stream?source=coinbase"])
    #expect(CoinbaseEndpoints(policy: .direct, gateways: []).rest("products", host: "api.coinbase.com")?.absoluteString
            == "https://api.coinbase.com/api/v3/brokerage/market/products")
  }

  @Test("4xx 不换主机，直接报")
  func clientErrorThrows() async throws {
    let server = FakeServer { _ in json(#"{"error":"NOT_FOUND","message":"product not found"}"#, status: 404) }
    await #expect(throws: UpstreamError.self) {
      _ = try await provider(server, policy: .gateway).ticker24h(symbol: "coinbase/spot/NOPE-USD", timeout: 5)
    }
    #expect(await server.urls().count == 1)
  }
}

@Suite("Coinbase 推送", .timeLimit(.minutes(1)))
struct CoinbaseWSTests {
  private static let url = URL(string: "wss://advanced-trade-ws.coinbase.com")!

  private struct Control: Decodable { var type: String; var channel: String; var product_ids: [String]? }

  private func sent(_ s: GateSocket) async -> [Control] {
    await s.sent.compactMap { try? JSONDecoder().decode(Control.self, from: Data($0.utf8)) }
  }

  @Test("连上先订心跳，再按频道订；切品种只退订 / 订阅，不重连；行情帧翻成统一报文")
  func subscribeAndSwitch() async throws {
    let bench = GateSocketBench()
    let ws = CoinbaseWS(urls: [Self.url], factory: bench, pacer: FastPacer(scale: 0.0001),
                        silenceMs: 1e12, transportSilenceMs: 1e12)
    let stream = await ws.start(topics: [.kline(symbol: "coinbase/spot/BTC-USD", interval: .m5),
                                         .ticker(symbol: "coinbase/spot/BTC-USD"),
                                         .markPrice(symbol: "coinbase/spot/BTC-USD")])
    #expect(await waitUntil(5) { await bench.socket(1) != nil })
    let socket = try #require(await bench.socket(1))
    #expect(await waitUntil(5) { await socket.sent.count == 3 })
    let first = await sent(socket)
    #expect(first.first?.channel == "heartbeats")
    #expect(Set(first.dropFirst().map(\.channel)) == ["candles", "ticker"])
    #expect(first.dropFirst().allSatisfy { $0.type == "subscribe" && $0.product_ids == ["BTC-USD"] })

    await socket.push(.text(#"""
    {"channel":"ticker","timestamp":"2026-09-22T23:19:47Z","events":[{"type":"snapshot","tickers":[
      {"product_id":"BTC-USD","price":"63000","volume_24_h":"1","low_24_h":"1","high_24_h":"2","price_percent_chg_24_h":"0"}]}]}
    """#))
    var got: Ticker?
    for await event in stream {
      if case .payload(.ticker(let t)) = event { got = t; break }
    }
    #expect(got?.symbol == "coinbase/spot/BTC-USD")

    await ws.replace(topics: [.trade(symbol: "coinbase/spot/ETH-USD")])
    #expect(await waitUntil(5) { await socket.sent.count == 6 })
    let tail = Array(await sent(socket).dropFirst(3))
    #expect(tail.filter { $0.type == "unsubscribe" }.count == 2)
    #expect(tail.last?.type == "subscribe" && tail.last?.channel == "market_trades")
    #expect(tail.last?.product_ids == ["ETH-USD"])
    #expect(await bench.connects == 1)
    await ws.stop()
    #expect(await socket.closed)
  }

  @Test("订了东西却一帧行情都不来：到期主动重连")
  func silentSubscriptionReconnects() async throws {
    let bench = GateSocketBench()
    let ws = CoinbaseWS(urls: [Self.url], factory: bench, pacer: FastPacer(scale: 0.001),
                        silenceMs: 100, transportSilenceMs: 1e12)
    _ = await ws.start(topics: [.ticker(symbol: "coinbase/spot/BTC-USD")])
    #expect(await waitUntil(5) { await bench.connects >= 2 })
    #expect(await bench.socket(1)?.closed == true)
    await ws.stop()
  }
}

@Suite("Coinbase 限速")
struct CoinbaseRateLimiterTests {
  /// 排着队的请求被整批撤掉（换品种、离开页面）之后，下一笔真请求只等正常的一格间隔，
  /// 不替那些撤掉的请求把它们订过的格子一格格等过去。
  @Test("取消的排队请求不留下占位")
  func cancelledWaitersReleaseTheirSlots() async throws {
    let pacer = ManualPacer()
    let limiter = CoinbaseRateLimiter(perSecond: 10, pacer: pacer)
    try await limiter.acquire()
    let queued = (0..<5).map { _ in Task { try await limiter.acquire() } }
    for _ in 0..<200 where await pacer.sleeping < queued.count { await Task.yield() }
    #expect(await pacer.sleeping == queued.count)
    queued.forEach { $0.cancel() }
    for task in queued { _ = try? await task.value }
    await pacer.advance(100)
    let next = Task { try await limiter.acquire() }
    for _ in 0..<50 { await Task.yield() }
    let stuck = await pacer.sleeping
    await pacer.drain()
    _ = try? await next.value
    #expect(stuck == 0)
  }

  @Test("429 罚停：从现在起整把歇够再放行，之后恢复正常间隔")
  func penaltyBlocksEveryone() async throws {
    let pacer = StepPacer()
    let limiter = CoinbaseRateLimiter(perSecond: 10, pacer: pacer)
    try await limiter.acquire()
    await limiter.penalize(seconds: 2)
    try await limiter.acquire()
    try await limiter.acquire()
    #expect(await pacer.sleepLog() == [2000, 100])
  }
}
