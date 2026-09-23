import Foundation
import Testing
@testable import KanpanNetwork
import KanpanNetworkTestSupport

private let marketFrame = "{\"e\":\"markPriceUpdate\",\"s\":\"BTCUSDT\",\"p\":\"123.45\"}"
private actor RouteSocket: WSSocket {
  let delay: Double
  let fails: Bool
  var closed = false
  var acknowledgement = true
  var sent: [String] = []
  init(delay: Double, fails: Bool = false) { self.delay = delay; self.fails = fails }
  func send(_ text: String) async throws { sent.append(text) }
  func pong() async throws {}
  func cancel() async { closed = true }
  func receive() async throws -> WSFrame {
    if acknowledgement { acknowledgement = false; return .text("{\"result\":null,\"id\":1}") }
    try await Task.sleep(for: .milliseconds(delay))
    if fails || closed { throw FeedError.badResponse("unavailable") }
    return .text(marketFrame)
  }
}
/// 只回订阅应答和 ping、一帧行情都不推的线路（A-T14）。
/// 网关那一档最典型的坏法：连接握手成功、`SUBSCRIBE` 也回了 `{"result":null}`，
/// 但上游的行情压根没到网关这边来。
private actor AckOnlySocket: WSSocket {
  private var acked = false
  var closed = false
  var pongs = 0
  func send(_ text: String) async throws {}
  func pong() async throws { pongs += 1 }
  func cancel() async { closed = true }
  /// 传输层探得通——正是要点：通不等于我们要的流在推。
  func keepalive(timeoutMs: Double) async -> Bool { !closed }
  func receive() async throws -> WSFrame {
    if !acked { acked = true; return .text("{\"result\":null,\"id\":1}") }
    try await Task.sleep(for: .milliseconds(10))
    if closed { throw FeedError.badResponse("closed") }
    return .ping
  }
}

private actor RouteFactory: WSSocketFactory {
  let sockets: [String: RouteSocket]
  var connections = 0
  var urls: [URL] = []
  init(_ sockets: [String: RouteSocket]) { self.sockets = sockets }
  func connect(to url: URL) async throws -> any WSSocket {
    connections += 1
    urls.append(url)
    return sockets[url.host!]!
  }
}

private actor AckFactory: WSSocketFactory {
  let sockets: [String: AckOnlySocket]
  var urls: [URL] = []
  init(_ sockets: [String: AckOnlySocket]) { self.sockets = sockets }
  func connect(to url: URL) async throws -> any WSSocket {
    urls.append(url)
    return sockets[url.host!]!
  }
}

@Suite("无感行情选路") struct MarketSocketRouterTests {
  let url = URL(string: "wss://local.example/market/stream?streams=btcusdt@kline_1m")!

  @Test("选择更快有效线路，首帧不丢失，正常收数不反复选路", arguments: [true, false])
  func localWinsAndStays(localFast: Bool) async throws {
    let local = RouteSocket(delay: localFast ? 10 : 100), vps = RouteSocket(delay: localFast ? 100 : 10)
    let factory = RouteFactory(["local.example": local, "vps.example": vps])
    let router = MarketSocketRouter(factory: factory, fallbacks: ["vps.example"], timeoutMs: 500)
    let socket = try await router.connect(to: url)
    #expect(await vps.closed == localFast)
    #expect(await local.closed != localFast)
    for _ in 0..<3 {
      guard case .text(let text) = try await socket.receive() else { Issue.record("missing market frame"); return }
      #expect(text == marketFrame)
    }
    #expect(await factory.connections == 2)
    await socket.cancel()
  }

  @Test("本地失败时自动兜底，订阅确认不算有效行情")
  func fallback() async throws {
    let local = RouteSocket(delay: 1, fails: true), vps = RouteSocket(delay: 30)
    let factory = RouteFactory(["local.example": local, "vps.example": vps])
    let socket = try await MarketSocketRouter(factory: factory, fallbacks: ["vps.example"], timeoutMs: 500).connect(to: url)
    #expect(await local.closed)
    #expect(!(await vps.closed))
    guard case .text(let text) = try await socket.receive() else { Issue.record("no first event"); return }
    #expect(text == marketFrame)
    await socket.cancel()
  }

  @Test("备用HTTPS独立端口保留路径及订阅参数")
  func fallbackPort() async throws {
    let factory = RouteFactory(["local.example": RouteSocket(delay: 1, fails: true),
                                "vps.example": RouteSocket(delay: 10)])
    let socket = try await MarketSocketRouter(factory: factory,
      fallbacks: ["vps.example:8443"], timeoutMs: 100).connect(to: url)
    let backup = await factory.urls.first { $0.host == "vps.example" }
    #expect(backup?.port == 8443 && backup?.path == url.path && backup?.query == url.query)
    await socket.cancel()
  }

  @Test("所有线路超时后释放连接，不无限等待")
  func timeout() async {
    let local = RouteSocket(delay: 500), vps = RouteSocket(delay: 500)
    let factory = RouteFactory(["local.example": local, "vps.example": vps])
    do {
      _ = try await MarketSocketRouter(factory: factory, fallbacks: ["vps.example"], timeoutMs: 20).connect(to: url)
      Issue.record("timeout expected")
    } catch {}
    #expect(await local.closed)
    #expect(await vps.closed)
  }

  /// A-T14：网关只回订阅成功 + pong，6 秒没有任何有效行情。
  ///
  /// 两件事都要成立：① 这些候选连接必须被关掉（不许留着一条永远不推数据的连接
  /// 在后台耗着）；② 选路失败就是失败，**绝不自动改去连币安**——线路是用户在
  /// 设置里定的两档之一，自动混源是明令禁止的。
  @Test("A-T14 网关只回订阅成功和 pong：候选全关，且不自动改连币安")
  func ackAndPongOnlyIsNotAValidRoute() async throws {
    let one = AckOnlySocket(), two = AckOnlySocket()
    let factory = AckFactory(["local.example": one, "gw2.example": two])
    let router = MarketSocketRouter(factory: factory, fallbacks: ["gw2.example"], timeoutMs: 120)
    await #expect(throws: (any Error).self) { _ = try await router.connect(to: url) }
    #expect(await one.closed)
    #expect(await two.closed)
    // 只拨过这两台网关，币安自己的域名一次都没有出现。
    let hosts = Set(await factory.urls.compactMap(\.host))
    #expect(hosts == ["local.example", "gw2.example"])
    // ping 照回了（传输层是通的），但通不算「订阅生效」。
    #expect(await one.pongs >= 1)
  }

  @Test("选路期间换品种，连接完成后补订新流，不误记已同步")
  func switchDuringProbe() async throws {
    let local = RouteSocket(delay: 100), vps = RouteSocket(delay: 500)
    let factory = RouteFactory(["local.example": local, "vps.example": vps])
    let ws = BinanceWS(hosts: BinanceHosts(stream: "local.example"),
                       factory: MarketSocketRouter(factory: factory, fallbacks: ["vps.example"]))
    _ = await ws.start(streams: ["btcusdt@ticker"])
    for _ in 0..<100 {
      if await factory.connections >= 2 { break }
      try await Task.sleep(for: .milliseconds(5))
    }
    await ws.replaceStreams(["ethusdt@ticker"])
    for _ in 0..<200 {
      if await ws.currentConnectionID == 1 {
        if await ws.streamsInSync { break }
      }
      try await Task.sleep(for: .milliseconds(5))
    }
    #expect(await ws.currentConnectionID == 1)
    #expect(await local.sent.contains { $0.contains("SUBSCRIBE") && $0.contains("ethusdt@ticker") })
    await ws.stop()
  }
}
