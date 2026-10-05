import Foundation
import Testing
@testable import KanpanNetwork
import KanpanNetworkTestSupport
import KanpanCore

// 美元指数（`macro/index/DXY`）。报文样本照 `docs/美元指数-协议-2026-10-05.md` 里线上抓回来的原文。

@Suite("美元指数报文")
struct MacroDTOTests {

  @Test("品种表：键是 macro/index/DXY，没有计价币，三位小数、步长 0.001、指数类")
  func instruments() throws {
    let body = Data(#"""
    {"symbols":[{"baseAsset":"DXY","displayName":"美元指数","filters":[{"filterType":"PRICE_FILTER","tickSize":"0.001"}],"key":"macro/index/DXY","keywords":["美元指数","DXY","USD","美元","美指"],"market":"index","pricePrecision":3,"quoteAsset":"USD","status":"TRADING","symbol":"DXY","tickSize":"0.001","underlyingType":"INDEX","venue":"macro"}]}
    """#.utf8)
    let info = try #require(try MacroDTO.instruments(body).first)
    #expect(info.symbol == "macro/index/DXY")
    #expect(info.base == "DXY" && info.quote == "")
    #expect(info.display == "DXY")
    #expect(info.pricePrecision == 3 && info.tickSize == 0.001)
    #expect(info.underlyingType == "INDEX" && info.status == .tradable)
    #expect(info == MacroDTO.builtin)
    #expect(InstrumentID.isSyncKey(info.symbol))
  }

  @Test("同步身份只收 macro/index/DXY")
  func syncIdentity() {
    #expect(InstrumentID.isSyncKey("macro/index/DXY"))
    #expect(!InstrumentID.isSyncKey("macro/index/dxy"))
    #expect(!InstrumentID.isSyncKey("macro/index/SPX"))
    #expect(!InstrumentID.isSyncKey("macro/spot/DXY"))
  }

  @Test("24h 行情：涨跌照服务端（相对上一交易日收盘），成交额是「没有」不是 0，开休市折进 marketClosed")
  func restTicker() throws {
    let body = Data(#"""
    {"closeTime":1791198990000,"highPrice":"102.534","lastPrice":"102.262","lowPrice":"101.855","marketState":"open","openPrice":"101.917","openTime":1791151200000,"prevClosePrice":"101.932","priceChange":"0.330","priceChangePercent":"0.324","priceSource":"official","quoteVolume":"0","symbol":"DXY","volume":"0"}
    """#.utf8)
    let t = try MacroDTO.restTicker(body)
    #expect(t.symbol == "macro/index/DXY")
    #expect(t.last == 102.262 && t.changePercent == 0.324 && t.priceChange == 0.330)
    #expect(t.high == 102.534 && t.low == 101.855 && t.open24h == 101.917)
    #expect(t.quoteVolume.isNaN)
    #expect(t.timeMs == 1_791_198_990_000)
    #expect(!t.marketClosed)

    let closed = Data(#"""
    [{"closeTime":1791198990000,"lastPrice":"102.262","marketState":"closed","priceChange":null,"priceChangePercent":"0.324","quoteVolume":"0","symbol":"DXY"}]
    """#.utf8)
    let list = try MacroDTO.restTickers(closed)
    #expect(list.count == 1 && list[0].marketClosed && list[0].priceChange == nil)
  }

  @Test("K 线：币安形状的数组直接解")
  func bars() throws {
    let body = Data(#"""
    [[1791198660000,"102.217","102.218","102.207","102.212","0",1791198719999,"0",0,"0","0","0"],
     [1791198720000,"102.212","102.230","102.210","102.229","0",1791198779999,"0",0,"0","0","0"]]
    """#.utf8)
    let bars = try MacroDTO.bars(body)
    #expect(bars.map(\.openTime) == [1_791_198_660_000, 1_791_198_720_000])
    #expect(bars[1].close == 102.229)
    #expect(try MacroDTO.bars(Data("[]".utf8)).isEmpty)
  }

  @Test("推送：行情帧、K 线帧、心跳、应答、报错各翻各的")
  func frames() {
    func f(_ s: String) -> MacroDTO.Frame { MacroDTO.frame(Data(s.utf8)) }
    guard case .ticker(let t, let stream) = f(#"""
    {"data":{"C":1791198967000,"E":1791198972794,"O":1791151200000,"P":"0.319","c":"102.257","e":"24hrTicker","h":"102.534","l":"101.855","marketState":"open","o":"101.917","p":"0.325","prevClosePrice":"101.932","priceSource":"official","q":"0","s":"DXY","v":"0"},"stream":"dxy@ticker"}
    """#) else { Issue.record("应该是行情帧"); return }
    #expect(stream == "dxy@ticker")
    #expect(t.symbol == "macro/index/DXY" && t.last == 102.257 && t.changePercent == 0.319)
    #expect(t.timeMs == 1_791_198_967_000 && !t.marketClosed)

    guard case .kline(let k, let ks) = f(#"""
    {"data":{"E":1791198972794,"e":"kline","k":{"B":"0","L":-1,"Q":"0","T":1791199019999,"V":"0","c":"102.257","f":-1,"h":"102.257","i":"1m","l":"102.257","n":0,"o":"102.257","q":"0","s":"DXY","t":1791198960000,"v":"0","x":false},"s":"DXY"},"stream":"dxy@kline_1m"}
    """#) else { Issue.record("应该是 K 线帧"); return }
    #expect(ks == "dxy@kline_1m")
    #expect(k.symbol == "macro/index/DXY" && k.interval == "1m" && !k.closed)
    #expect(k.openTime == 1_791_198_960_000 && k.lastTradeID == nil)

    guard case .heartbeat(let hb, let closed) = f(#"{"data":{"E":1791198972794,"e":"heartbeat","marketState":"closed"},"stream":"heartbeat"}"#)
    else { Issue.record("应该是心跳"); return }
    #expect(hb == 1_791_198_972_794 && closed)

    guard case .ack(let id) = f(#"{"result":null,"id":7}"#) else { Issue.record("应该是应答"); return }
    #expect(id == 7)
    guard case .error(let eid, _) = f(#"{"error":{"code":2,"msg":"Invalid stream"},"id":3}"#) else {
      Issue.record("应该是报错"); return
    }
    #expect(eid == 3)
    guard case .error(nil, _) = f(#"{"error":{"code":-1,"msg":"too many connections"},"id":null}"#) else {
      Issue.record("连接数超限的报错 id 是 null"); return
    }
  }

  @Test("流名：行情与 14 档 K 线；标记价、逐笔、盘口不订")
  func streamNames() {
    #expect(MacroDTO.streamName(.ticker(symbol: "macro/index/DXY")) == "dxy@ticker")
    #expect(MacroDTO.streamName(.kline(symbol: "macro/index/DXY", interval: .m15)) == "dxy@kline_15m")
    #expect(MacroDTO.streamName(.kline(symbol: "macro/index/DXY", interval: .mo1)) == "dxy@kline_1M")
    #expect(MacroDTO.streamName(.markPrice(symbol: "macro/index/DXY")) == nil)
    #expect(MacroDTO.streamName(.trade(symbol: "macro/index/DXY")) == nil)
  }
}

@Suite("美元指数 REST")
struct MacroRESTTests {
  private static func route(_ policy: MarketRoutePolicy) -> MarketRoute {
    MarketRoute(policy: policy, endpoints: MarketEndpoints(gateways: ["gw1.example", "gw2.example"],
                                                            api: ["api.example"]))
  }

  private func provider(_ server: FakeServer, policy: MarketRoutePolicy = .direct) -> MacroProvider {
    MacroProvider(route: Self.route(policy), transport: FakeTransport(server),
                  limiter: MacroRateLimiter(perSecond: 1_000_000, pacer: FastPacer()))
  }

  @Test("直连、网关两条线路都打 kanpan-api 的主机，带 source=macro")
  func bothRoutesHitKanpanAPI() async throws {
    for policy in MarketRoutePolicy.allCases {
      let server = FakeServer { _ in json("[]") }
      _ = try await provider(server, policy: policy).klines(symbol: "macro/index/DXY", interval: .h1, limit: 5,
                                                            startTime: nil, endTime: nil)
      let url = try #require(await server.urls().first)
      #expect(url.host == "api.example" && url.path == "/v1/market/raw/klines")
      #expect(url.query?.hasPrefix("source=macro&") == true)
      #expect(url.query?.contains("symbol=DXY") == true)
    }
    let e = MacroEndpoints(route: Self.route(.direct))
    #expect(e.streams.map(\.absoluteString) == ["wss://api.example/v1/market/stream?source=macro"])
    #expect(MacroEndpoints(route: Self.route(.gateway)).streams == e.streams)
  }

  /// 按请求造一页 1h K 线：休市段（每天 21–22 点 UTC）没有 K 线；`startTime` 往后数、否则往前数。
  private static func page(_ url: URL) -> HTTPReply {
    let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
    func q(_ k: String) -> Int64? { items.first { $0.name == k }?.value.flatMap { Int64($0) } }
    let step: Int64 = 3_600_000
    let now: Int64 = 1_791_000_000_000 / step * step
    let head: Int64 = now - 3000 * step   // 历史开头
    let all = stride(from: head, through: now, by: Int(step)).filter { ($0 / step) % 24 != 21 }
    let limit = Int(q("limit") ?? 500)
    guard limit <= 1500 else { return json(#"{"error":"invalid_limit"}"#, status: 400) }
    let rows: [Int64]
    if let s = q("startTime") {
      rows = Array(all.filter { $0 >= s && $0 <= (q("endTime") ?? .max) }.prefix(limit))
    } else {
      rows = Array(all.filter { $0 <= (q("endTime") ?? .max) }.suffix(limit))
    }
    let body = rows.map { #"[\#($0),"1","2","0.5","1.5","0",\#($0 + step - 1),"0",0,"0","0","0"]"# }
    return json("[" + body.joined(separator: ",") + "]")
  }

  @Test("往前翻：要 2000 根拆两页，按上一页头接，不重不漏，跳过休市段")
  func pagesBackward() async throws {
    let server = FakeServer { Self.page($0) }
    let bars = try await provider(server).klines(symbol: "macro/index/DXY", interval: .h1, limit: 2000,
                                                 startTime: nil, endTime: nil)
    #expect(bars.count == 2000)
    #expect(zip(bars, bars.dropFirst()).allSatisfy { $1.openTime > $0.openTime })
    #expect(bars.allSatisfy { ($0.openTime / 3_600_000) % 24 != 21 })
    let urls = await server.urls()
    #expect(urls.count == 2)
  }

  @Test("翻到历史开头：一页没取满就停")
  func stopsAtHistoryHead() async throws {
    let server = FakeServer { Self.page($0) }
    let head: Int64 = 1_791_000_000_000 / 3_600_000 * 3_600_000 - 3000 * 3_600_000
    let bars = try await provider(server).history(symbol: "macro/index/DXY", interval: .h1, pages: 1,
                                                  before: head + 10 * 3_600_000)
    #expect(bars.first?.openTime == head)
    #expect(bars.count <= 10)
    #expect(await server.urls().count == 1)
  }

  @Test("往后翻：从 startTime 起往后取，取到现在为止")
  func pagesForward() async throws {
    let server = FakeServer { Self.page($0) }
    let now: Int64 = 1_791_000_000_000 / 3_600_000 * 3_600_000
    let from = now - 100 * 3_600_000
    let bars = try await provider(server).klines(symbol: "macro/index/DXY", interval: .h1, limit: 3000,
                                                 startTime: from, endTime: nil)
    #expect(bars.first?.openTime == from)
    #expect(bars.last?.openTime == now)
    #expect(await server.urls().count == 1)
  }

  @Test("503 not_ready 换下一台、4xx 直接报不换主机；品种表取不到就用内置那一行")
  func errors() async throws {
    let server = FakeServer { _ in json(#"{"error":"invalid_symbol"}"#, status: 400) }
    await #expect(throws: UpstreamError.self) {
      _ = try await provider(server).ticker24h(symbol: "macro/index/DXY", timeout: 5)
    }
    #expect(await server.urls().count == 1)

    let down = FakeServer { _ in json(#"{"error":"not_ready"}"#, status: 503) }
    let list = try await provider(down).instruments()
    #expect(list == MacroProvider.builtinInstruments)
  }

  @Test("能力位：14 档原生且都有推送，没有订单流、衍生数据、标记价")
  func capabilities() {
    let c = MacroProvider.capabilities
    #expect(c.nativeIntervals == Set(Interval.allCases))
    #expect(c.liveKlineIntervals == Set(Interval.allCases))
    #expect(!c.hasOrderFlow && !c.hasDerivativeMetrics && !c.hasMarkPrice && !c.hasFunding)
    // 涨跌是服务端按交易日算好的（相对上一交易日收盘），客户端不再拿 UTC 0 点重算。
    #expect(c.hasSessionChange)
    #expect(!CoinbaseProvider.capabilities.hasSessionChange && CoinbaseProvider.capabilities.hasOrderFlow)
    #expect(c.openInterestSource == nil)
    #expect(VenueRegistry.descriptor(forSymbol: "macro/index/DXY").id == "macro")
    #expect(VenueRegistry.descriptor(forSymbol: "macro/index/DXY").favoriteCategory == "指数")
    #expect(!VenueRegistry.descriptor(forSymbol: "macro/index/DXY").joinsSectors)
  }
}

@Suite("美元指数推送", .timeLimit(.minutes(1)))
struct MacroWSTests {
  private static let url = URL(string: "wss://api.example/v1/market/stream?source=macro")!

  private struct Control: Decodable { var method: String; var params: [String]; var id: Int }

  private func sent(_ s: GateSocket) async -> [Control] {
    await s.sent.compactMap { try? JSONDecoder().decode(Control.self, from: Data($0.utf8)) }
  }

  @Test("连上发 SUBSCRIBE；切周期只退订 / 订阅，不重连；标记价不订")
  func subscribeAndSwitch() async throws {
    let bench = GateSocketBench()
    let ws = MacroWS(urls: [Self.url], factory: bench, pacer: FastPacer(scale: 0.0001),
                     silenceMs: 1e12, transportSilenceMs: 1e12)
    let stream = await ws.start(topics: [.ticker(symbol: "macro/index/DXY"),
                                         .kline(symbol: "macro/index/DXY", interval: .m15),
                                         .markPrice(symbol: "macro/index/DXY")])
    #expect(await waitUntil(5) { await bench.socket(1) != nil })
    let socket = try #require(await bench.socket(1))
    #expect(await waitUntil(5) { await socket.sent.count == 1 })
    let first = try #require(await sent(socket).first)
    #expect(first.method == "SUBSCRIBE" && first.params == ["dxy@kline_15m", "dxy@ticker"])
    await socket.push(.text(#"{"result":null,"id":\#(first.id)}"#))
    await socket.push(.text(#"""
    {"data":{"C":1791198967000,"E":1791198972794,"P":"0.319","c":"102.257","e":"24hrTicker","h":"102.534","l":"101.855","marketState":"open","o":"101.917","p":"0.325","s":"DXY"},"stream":"dxy@ticker"}
    """#))
    var got: Ticker?
    for await event in stream {
      if case .payload(.ticker(let t)) = event { got = t; break }
    }
    #expect(got?.symbol == "macro/index/DXY")

    await ws.replace(topics: [.ticker(symbol: "macro/index/DXY"), .kline(symbol: "macro/index/DXY", interval: .d1)])
    #expect(await waitUntil(5) { await socket.sent.count == 3 })
    let tail = Array(await sent(socket).dropFirst())
    #expect(tail[0].method == "UNSUBSCRIBE" && tail[0].params == ["dxy@kline_15m"])
    #expect(tail[1].method == "SUBSCRIBE" && tail[1].params == ["dxy@kline_1d"])
    #expect(await bench.connects == 1)
    await ws.stop()
    #expect(await socket.closed)
  }

  @Test("心跳报休市：把最后那帧行情改成休市再发一次，时间戳往后挪 1 毫秒")
  func heartbeatFlipsMarketState() async throws {
    let bench = GateSocketBench()
    let ws = MacroWS(urls: [Self.url], factory: bench, pacer: FastPacer(scale: 0.0001),
                     silenceMs: 1e12, transportSilenceMs: 1e12)
    let stream = await ws.start(topics: [.ticker(symbol: "macro/index/DXY")])
    #expect(await waitUntil(5) { await bench.socket(1) != nil })
    let socket = try #require(await bench.socket(1))
    await socket.push(.text(#"""
    {"data":{"C":1791198967000,"E":1791198972794,"P":"0.319","c":"102.257","e":"24hrTicker","marketState":"open","s":"DXY"},"stream":"dxy@ticker"}
    """#))
    await socket.push(.text(#"{"data":{"E":1791198987794,"e":"heartbeat","marketState":"open"},"stream":"heartbeat"}"#))
    await socket.push(.text(#"{"data":{"E":1791199002794,"e":"heartbeat","marketState":"closed"},"stream":"heartbeat"}"#))
    var tickers: [Ticker] = []
    for await event in stream {
      if case .payload(.ticker(let t)) = event { tickers.append(t); if tickers.count == 2 { break } }
    }
    #expect(tickers.map(\.marketClosed) == [false, true])
    #expect(tickers[1].timeMs == 1_791_198_967_001 && tickers[1].last == 102.257)
    #expect(LatestQuote.accepts(tickers[1], after: tickers[0]))
    await ws.stop()
  }

  @Test("订了东西却一帧行情都不来：到期主动重连")
  func silentSubscriptionReconnects() async throws {
    let bench = GateSocketBench()
    let ws = MacroWS(urls: [Self.url], factory: bench, pacer: FastPacer(scale: 0.001),
                     silenceMs: 100, transportSilenceMs: 1e12)
    _ = await ws.start(topics: [.ticker(symbol: "macro/index/DXY")])
    #expect(await waitUntil(5) { await bench.connects >= 2 })
    #expect(await bench.socket(1)?.closed == true)
    await ws.stop()
  }
}
