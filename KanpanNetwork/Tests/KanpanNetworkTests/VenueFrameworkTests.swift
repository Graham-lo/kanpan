import Foundation
import Testing
@testable import KanpanNetwork
import KanpanNetworkTestSupport
import KanpanCore

// 交易所通用件（2026-10-08，从 Coinbase 抽出来）：地址表、REST 客户端、推送 actor。
// 不认识任何一家；这里用一家假的交易所「demo」把每条规矩钉住，接 OKX / Bybit / Hyperliquid 时照着用。

private enum Demo {
  static let spec = VenueEndpoints.Spec(
    source: "demo", restHost: "api.demo.example", restPrefix: "/api/v1/",
    directStreams: [URL(string: "wss://ws.demo.example/public")!, URL(string: "wss://ws2.demo.example/public")!],
    gatewayStream: .relay)
  static func route(_ policy: MarketRoutePolicy, gateways: [String] = ["gw1.test", "gw2.test:8443"],
                    api: [String] = ["api1.test", "api2.test"]) -> MarketRoute {
    MarketRoute(policy: policy, endpoints: MarketEndpoints(gateways: gateways, api: api))
  }
}

@Suite("交易所通用件 · 地址表")
struct VenueEndpointsTests {
  @Test("直连：交易所自己的主机与前缀，推送按出厂顺序")
  func direct() throws {
    let e = VenueEndpoints(Demo.spec, route: Demo.route(.direct))
    #expect(!e.viaGateway)
    #expect(e.restHosts == ["api.demo.example"])
    let url = try #require(e.rest("market/candles", query: [URLQueryItem(name: "instId", value: "BTC")], host: e.restHosts[0]))
    #expect(url.absoluteString == "https://api.demo.example/api/v1/market/candles?instId=BTC")
    #expect(e.streams == Demo.spec.directStreams)
    #expect(e.restTemplate("ticker", query: "instId={symbol}") == "/api/v1/ticker?instId={symbol}")
  }

  @Test("网关：REST 透传打 kanpan-api（apiHosts），source 排第一；中继打网关表，主、备都在、端口照拼")
  func gatewayRelay() throws {
    let e = VenueEndpoints(Demo.spec, route: Demo.route(.gateway))
    #expect(e.viaGateway)
    #expect(e.restHosts == ["api1.test", "api2.test"])
    let url = try #require(e.rest("market/candles", query: [URLQueryItem(name: "instId", value: "BTC")], host: "api2.test"))
    #expect(url.absoluteString == "https://api2.test/v1/market/raw/market/candles?source=demo&instId=BTC")
    #expect(e.streams.map(\.absoluteString) == ["wss://gw1.test/v1/market/ws/demo", "wss://gw2.test:8443/v1/market/ws/demo"])
    #expect(e.streams(query: [URLQueryItem(name: "category", value: "linear")]).first?.absoluteString
            == "wss://gw1.test/v1/market/ws/demo?category=linear")
    #expect(e.restTemplate("ticker", query: "instId={symbol}") == "/v1/market/raw/ticker?source=demo&instId={symbol}")
  }

  @Test("网关 hub：/v1/market/stream?source=<id>；没有网关推送的一家给空；没有直连的一家两条线路都走 kanpan-api")
  func hubNoneAndGatewayOnly() {
    var spec = Demo.spec
    spec.gatewayStream = .hub
    #expect(VenueEndpoints(spec, route: Demo.route(.gateway)).streams.first?.absoluteString
            == "wss://gw1.test/v1/market/stream?source=demo")
    spec.gatewayStream = .none
    #expect(VenueEndpoints(spec, route: Demo.route(.gateway)).streams.isEmpty)
    spec.restHost = nil
    let onlyGateway = VenueEndpoints(spec, route: Demo.route(.direct))
    #expect(onlyGateway.viaGateway && onlyGateway.restHosts == ["api1.test", "api2.test"])
  }

  @Test("带路径、账号的「主机」不拼；中继地址不看线路")
  func badHostsAndRelay() {
    #expect(VenueEndpoints.origin("https", "a.example/x") == nil)
    #expect(VenueEndpoints.origin("https", "user@a.example") == nil)
    #expect(VenueEndpoints.origin("https", "a.example:8443")?.port == 8443)
    let e = VenueEndpoints(Demo.spec, route: Demo.route(.direct, gateways: ["gw1.test", "bad/host"]))
    #expect(e.relayStreams().map(\.absoluteString) == ["wss://gw1.test/v1/market/ws/demo"])
  }
}

@Suite("交易所通用件 · REST")
struct VenueRESTTests {
  private func rest(_ server: FakeServer, _ policy: MarketRoutePolicy, pacer: Pacer = FastPacer()) -> (VenueREST, VenueRateLimiter) {
    let limiter = VenueRateLimiter(perSecond: 1_000_000, pacer: pacer)
    return (VenueREST(endpoints: VenueEndpoints(Demo.spec, route: Demo.route(policy)),
                      transport: FakeTransport(server), limiter: limiter), limiter)
  }

  @Test("POST JSON：正文原样发出，网关线路打透传路径；主机 5xx 换下一台")
  func postWithFallback() async throws {
    let server = FakeServer { url in url.host == "api1.test" ? json("{}", status: 503) : json(#"{"ok":1}"#) }
    let body = Data(#"{"type":"meta"}"#.utf8)
    let data = try await rest(server, .gateway).0.post("info", json: body)
    #expect(String(decoding: data, as: UTF8.self) == #"{"ok":1}"#)
    let hits = await server.hits
    #expect(hits.map(\.method) == ["POST", "POST"])
    #expect(hits.map { $0.url.host ?? "" } == ["api1.test", "api2.test"])
    #expect(hits.allSatisfy { $0.body == body && $0.url.path == "/v1/market/raw/info" && $0.url.query == "source=demo" })
  }

  @Test("4xx 不换主机直接报，错误体读 msg / message / error")
  func clientErrorStops() async throws {
    let server = FakeServer { _ in json(#"{"msg":"Instrument ID does not exist"}"#, status: 400) }
    var thrown: UpstreamError?
    do { _ = try await rest(server, .gateway).0.get("market/ticker") } catch let e as UpstreamError { thrown = e }
    #expect(thrown?.status == 400 && thrown?.msg == "Instrument ID does not exist" && thrown?.proxied == true)
    #expect(await server.urls().count == 1)
  }

  @Test("429：按 Retry-After 罚这一家的限速器，歇够了在同一台上再试")
  func rateLimitPenalizes() async throws {
    let pacer = StepPacer()
    let calls = Counter()
    let server = FakeServer(pacer: pacer) { _ in
      calls.bump() == 1 ? json("{}", status: 429, headers: ["Retry-After": "2"]) : json("[]")
    }
    _ = try await rest(server, .direct, pacer: pacer).0.get("market/ticker")
    #expect(await server.urls().map { $0.host ?? "" } == ["api.demo.example", "api.demo.example"])
    #expect(await pacer.sleepLog().contains(2000))
  }

  @Test("没有 POST 的传输默认报不支持")
  func postUnsupportedByDefault() async {
    struct GetOnly: HTTPTransport {
      func get(_ url: URL, timeout: TimeInterval) async throws -> HTTPReply { json("{}") }
    }
    await #expect(throws: FeedError.self) {
      _ = try await GetOnly().post(URL(string: "https://a.example")!, json: Data(), timeout: 1)
    }
  }
}

// ---------------------------------------------------------------- 推送

/// 假交易所的推送协议：`{"op":"subscribe","args":["ticker:BTC",…]}`，一帧最多两个；
/// 数据帧 `{"arg":"ticker:BTC","px":"1"}`，报错帧 `{"event":"error","arg":"ticker:NOPE","msg":…}`（点了名），
/// 每 `everyMs` 发一句 `ping`，回 `pong`。
private struct DemoWire: VenueWire {
  typealias Sub = String
  var everyMs: Double = 1_000
  var name: String { "Demo" }
  var controlGapMs: Double { 10 }
  var keepAlive: VenueKeepAlive? { VenueKeepAlive(text: "ping", everyMs: everyMs) }
  func subs(_ topics: [StreamTopic]) -> Set<String> {
    Set(topics.compactMap { if case .ticker(let s) = $0 { return "ticker:" + InstrumentID(s).symbol } else { return nil } })
  }
  func nextBatch(_ pending: Set<String>) -> [String] { Array(pending.sorted().prefix(2)) }
  func control(_ op: VenueControl, _ subs: [String]) throws -> String {
    String(decoding: try JSONSerialization.data(withJSONObject: ["op": op.rawValue, "args": subs], options: [.sortedKeys]),
           as: UTF8.self)
  }
  func decode(_ text: String) -> VenueWireFrame<String> {
    guard text != "pong", let obj = try? JSONSerialization.jsonObject(with: Data(text.utf8)) as? [String: Any],
          let arg = obj["arg"] as? String else { return .ignored }
    if obj["event"] as? String == "error" { return VenueWireFrame(error: obj["msg"] as? String ?? "?", rejected: [arg]) }
    guard let px = (obj["px"] as? String).flatMap(Double.init) else { return VenueWireFrame(confirmed: [arg]) }
    let symbol = InstrumentID(venue: "demo", market: "spot", symbol: String(arg.dropFirst("ticker:".count))).key
    return VenueWireFrame(payloads: [.ticker(Ticker(symbol: symbol, last: px, changePercent: .nan, high: .nan,
                                                    low: .nan, quoteVolume: .nan))],
                          confirmed: [arg])
  }
  func label(_ sub: String) -> String { sub }
}

@Suite("交易所通用件 · 推送", .timeLimit(.minutes(1)))
struct VenueStreamTests {
  private struct Control: Decodable { var op: String; var args: [String] }
  private func controls(_ s: GateSocket) async -> [Control] {
    await s.sent.compactMap { try? JSONDecoder().decode(Control.self, from: Data($0.utf8)) }
  }

  @Test("一条连接多个订阅：按那一家的批量上限分帧；切品种只退订 / 订阅不重连；数据帧翻成统一报文")
  func batchesAndSwitches() async throws {
    let bench = GateSocketBench()
    let ws = VenueStream(wire: DemoWire(everyMs: 1e12), urls: [URL(string: "wss://ws.demo.example")!], factory: bench,
                         pacer: FastPacer(scale: 0.0001), silenceMs: 1e12, transportSilenceMs: 1e12)
    let stream = await ws.start(topics: ["A", "B", "C"].map { .ticker(symbol: "demo/spot/\($0)") })
    #expect(await waitUntil(5) { await bench.socket(1) != nil })
    let socket = try #require(await bench.socket(1))
    #expect(await waitUntil(5) { await self.controls(socket).count == 2 })
    let first = await controls(socket)
    #expect(first.map(\.args) == [["ticker:A", "ticker:B"], ["ticker:C"]])
    await socket.push(.text(#"{"arg":"ticker:B","px":"42"}"#))
    var got: Ticker?
    for await event in stream { if case .payload(.ticker(let t)) = event { got = t; break } }
    #expect(got?.symbol == "demo/spot/B" && got?.last == 42)

    await ws.replace(topics: [.ticker(symbol: "demo/spot/A"), .ticker(symbol: "demo/spot/D")])
    #expect(await waitUntil(5) { await self.controls(socket).count == 4 })
    let tail = Array(await controls(socket).dropFirst(2))
    #expect(tail[0].op == "unsubscribe" && tail[0].args == ["ticker:B", "ticker:C"])
    #expect(tail[1].op == "subscribe" && tail[1].args == ["ticker:D"])
    #expect(await bench.connects == 1)
    await ws.stop()
  }

  @Test("应用层保活：按点发 ping；点了名的报错只记那一个订阅，不重发、不重连")
  func keepAliveAndNamedRejection() async throws {
    let bench = GateSocketBench()
    // 保活 1 秒 × 0.01 = 真实 10ms；首帧窗口 20 秒 × 0.01 = 200ms。
    let ws = VenueStream(wire: DemoWire(everyMs: 1_000), urls: [URL(string: "wss://ws.demo.example")!], factory: bench,
                         pacer: FastPacer(scale: 0.01), silenceMs: 20_000, transportSilenceMs: 1e12)
    _ = await ws.start(topics: [.ticker(symbol: "demo/spot/BTC")])
    #expect(await waitUntil(5) { await bench.socket(1) != nil })
    let socket = try #require(await bench.socket(1))
    #expect(await waitUntil(5) { await socket.sent.filter { $0 == "ping" }.count >= 2 })
    await socket.push(.text(#"{"arg":"ticker:BTC","px":"1"}"#))
    #expect(await waitUntil(5) { await self.controls(socket).count == 1 })
    await ws.replace(topics: [.ticker(symbol: "demo/spot/BTC"), .ticker(symbol: "demo/spot/NOPE")])
    #expect(await waitUntil(5) { await self.controls(socket).contains { $0.args == ["ticker:NOPE"] } })
    await socket.push(.text(#"{"event":"error","arg":"ticker:NOPE","msg":"doesn't exist"}"#))
    #expect(await waitUntil(5) { await ws.topicErrors == ["ticker:NOPE": "doesn't exist"] })
    #expect(await staysFalse(for: 0.6) { await bench.connects >= 2 })
    #expect(await controls(socket).filter { $0.args == ["ticker:NOPE"] }.count == 1)
    await ws.stop()
  }
}
