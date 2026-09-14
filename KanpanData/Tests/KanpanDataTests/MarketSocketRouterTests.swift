import Foundation
import Testing
@testable import KanpanData

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

  @Test("选路期间换品种，连接完成后补订新流，不误记已同步")
  func switchDuringProbe() async throws {
    let local = RouteSocket(delay: 100), vps = RouteSocket(delay: 500)
    let factory = RouteFactory(["local.example": local, "vps.example": vps])
    let ws = BinanceWS(hosts: BinanceHosts(stream: "local.example", streamFallbacks: ["vps.example"]), factory: factory)
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

  @Test("历史OI网关时间戳、数值和坏响应检查")
  func archiveDecode() throws {
    let points = try OISource.decodeGateway(Data("[[1638316800000,102],[1638317100000,101]]".utf8))
    #expect(points.count == 2 && points[0].value == 102)
    #expect(throws: (any Error).self) { try OISource.decodeGateway(Data("[[1638316800000]]".utf8)) }
  }
}
