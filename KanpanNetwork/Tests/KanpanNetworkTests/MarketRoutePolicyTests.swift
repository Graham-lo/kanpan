import Foundation
import Testing
@testable import KanpanNetwork
import KanpanNetworkTestSupport
import KanpanCore

// 「行情线路」两档：直连 / 网关，出厂默认直连，没有「自动」。
// 用户真机自己的网络能直连币安，但原来的自动探测偶发失败就把整套切到 OKX 且卡很久；
// 这套用例守的是「他选了哪条就走哪条，代码不许再自作主张」。

// `UserDefaults` 是全局的，两条存取用例并行跑会互相踩；整套串行。
@Suite("行情线路策略", .serialized)
struct MarketRoutePolicyTests {

  private static let klines = URL(string: "https://fapi.binance.com/fapi/v1/klines?symbol=BTCUSDT&interval=1m&limit=300")!

  /// 记下每一笔打到哪台主机；币安直连一律报错，网关一律回一份合法信封。
  private actor RouteSpy: HTTPTransport {
    private(set) var hosts: [String] = []
    func get(_ url: URL, timeout: TimeInterval) async throws -> HTTPReply {
      hosts.append(url.host!)
      if url.host == "fapi.binance.com" { throw URLError(.cannotFindHost) }
      return json(#"{"source":"binance","symbol":"BTCUSDT","interval":"1m","bars":[]}"#)
    }
  }

  /// 哪条路都坏，用来看「失败之后有没有记冷却」。
  private actor DeadRouteSpy: HTTPTransport {
    private(set) var hosts: [String] = []
    func get(_ url: URL, timeout: TimeInterval) async throws -> HTTPReply {
      hosts.append(url.host!)
      throw URLError(.cannotFindHost)
    }
  }

  // ---------------------------------------------------------------- 存取

  @Test("默认是直连，写进去能读回来，认不出的值退回直连")
  func storeRoundTrips() {
    let defaults = MarketRoutePolicyStore.defaults
    let saved = defaults.string(forKey: MarketRoutePolicyStore.key)
    defer {
      if let saved { defaults.set(saved, forKey: MarketRoutePolicyStore.key) }
      else { defaults.removeObject(forKey: MarketRoutePolicyStore.key) }
    }

    defaults.removeObject(forKey: MarketRoutePolicyStore.key)
    #expect(MarketRoutePolicyStore.current == .direct)
    // 旧版本存过「自动」、或者写进去的是垃圾：都退回直连，不能把行情卡死在一个不存在的档上。
    defaults.set("auto", forKey: MarketRoutePolicyStore.key)
    #expect(MarketRoutePolicyStore.current == .direct)
    defaults.set("nonsense", forKey: MarketRoutePolicyStore.key)
    #expect(MarketRoutePolicyStore.current == .direct)

    for policy in MarketRoutePolicy.allCases {
      MarketRoutePolicyStore.set(policy)
      #expect(MarketRoutePolicyStore.current == policy)
    }
    #expect(MarketRoutePolicy.allCases.map(\.title) == ["直连", "网关"])
    #expect(BinanceProvider.upstream(for: MarketRoute(policy: .direct, endpoints: .production)) == .binance)
    #expect(BinanceProvider.upstream(for: MarketRoute(policy: .gateway, endpoints: .production)) == .okx)
  }

  @Test("换线路会广播；没变就不广播")
  func settingPostsNotification() async {
    let defaults = MarketRoutePolicyStore.defaults
    let saved = defaults.string(forKey: MarketRoutePolicyStore.key)
    defer {
      if let saved { defaults.set(saved, forKey: MarketRoutePolicyStore.key) }
      else { defaults.removeObject(forKey: MarketRoutePolicyStore.key) }
    }
    defaults.removeObject(forKey: MarketRoutePolicyStore.key)
    let heard = Counter()
    let token = NotificationCenter.default.addObserver(
      forName: .marketRoutePolicyDidChange, object: nil, queue: nil) { _ in heard.bump() }
    defer { NotificationCenter.default.removeObserver(token) }

    // `PrefsStore` 每落一次盘都会 set 一次，值没变不能把行情重开。
    MarketRoutePolicyStore.set(.direct)
    #expect(await staysFalse(for: 0.3) { heard.value >= 1 })
    MarketRoutePolicyStore.set(.gateway)
    #expect(await waitUntil(2) { heard.value == 1 })
  }

  // ---------------------------------------------------------------- 直连

  @Test("直连：币安一笔都不打到网关")
  func directNeverTouchesGateway() async {
    let spy = RouteSpy()
    let transport = MarketRESTTransport(source: .binance, gateways: ["gw.test"], transport: spy, policy: .direct)
    _ = try? await transport.get(Self.klines, timeout: 10)
    #expect(await spy.hosts == ["fapi.binance.com"])
  }

  @Test("直连：失败不记冷却，下一笔照样直连")
  func directDoesNotCoolDown() async {
    let spy = DeadRouteSpy()
    let transport = MarketRESTTransport(source: .binance, gateways: ["gw.test"], transport: spy, policy: .direct)
    _ = try? await transport.get(Self.klines, timeout: 10)
    _ = try? await transport.get(Self.klines, timeout: 10)
    _ = try? await transport.get(Self.klines, timeout: 10)
    #expect(await spy.hosts == ["fapi.binance.com", "fapi.binance.com", "fapi.binance.com"])
  }

  /// 直连用满调用方给的超时，不再有 3/8 秒的「快速让位」——没有网关可让。
  private actor TimeoutSpy: HTTPTransport {
    private(set) var timeouts: [TimeInterval] = []
    func get(_ url: URL, timeout: TimeInterval) async throws -> HTTPReply {
      timeouts.append(timeout); return json("[]")
    }
  }

  @Test("直连：用满请求超时，不做快速让位")
  func directUsesFullTimeout() async throws {
    let spy = TimeoutSpy()
    let transport = MarketRESTTransport(source: .binance, gateways: ["gw.test"], transport: spy, policy: .direct)
    _ = try await transport.get(Self.klines, timeout: 12)
    #expect(await spy.timeouts == [12])
  }

  @Test("直连：OKX 源照旧走网关，不受影响")
  func directLeavesOKXAlone() async throws {
    let spy = RouteSpy()
    let transport = MarketRESTTransport(source: .okx, gateways: ["gw.test"], transport: spy, policy: .direct)
    _ = try? await transport.get(Self.klines, timeout: 10)
    #expect(await spy.hosts == ["gw.test"])
  }

  // ---------------------------------------------------------------- 网关

  @Test("网关：一笔都不打直连")
  func gatewayNeverTouchesDirect() async throws {
    let spy = RouteSpy()
    let transport = MarketRESTTransport(source: .binance, gateways: ["gw.test"], transport: spy, policy: .gateway)
    let reply = try await transport.get(Self.klines, timeout: 10)
    #expect(reply.status == 200)
    #expect(await spy.hosts == ["gw.test"])
  }

  /// 对照组：网关那边的冷却还在。没有这一条，「直连不记冷却」证明不了什么。
  @Test("网关：失败之后这台网关先歇着，下一笔不再打它")
  func gatewayCoolsDownAfterFailure() async {
    let spy = DeadRouteSpy()
    let transport = MarketRESTTransport(source: .binance, gateways: ["gw.test"], transport: spy, policy: .gateway)
    _ = try? await transport.get(Self.klines, timeout: 10)
    _ = try? await transport.get(Self.klines, timeout: 10)
    #expect(await spy.hosts == ["gw.test"])
  }

  @Test("网关：没有网关路线的请求直接失败，不偷偷走直连")
  func gatewayNeverFallsBackToDirect() async {
    let spy = RouteSpy()
    let transport = MarketRESTTransport(source: .binance, gateways: ["gw.test"], transport: spy, policy: .gateway)
    let oi = URL(string: "https://fapi.binance.com/futures/data/openInterestHist?symbol=BTCUSDT&period=5m")!
    await #expect(throws: (any Error).self) { try await transport.get(oi, timeout: 10) }
    #expect(await spy.hosts.isEmpty)
  }

  // ---------------------------------------------------------------- WS 分流

  /// 记下每台被拨过的 WS 主机，然后一律连不上——只看路由把谁列进了候选。
  private final class SocketSpy: WSSocketFactory, @unchecked Sendable {
    private let lock = NSLock()
    private var dialed: [URL] = []
    var hosts: [String] { lock.withLock { dialed.map { $0.host! } } }
    var paths: [String] { lock.withLock { dialed.map(\.path) } }
    func connect(to url: URL) async throws -> WSSocket {
      lock.withLock { dialed.append(url) }
      throw FeedError.badResponse("测试：WS 不可用")
    }
  }

  private static let stream = URL(string: "wss://dstream.binance.me/stream?streams=btcusdt@kline_1m")!
  /// 网关表（主、备）就是 REST / OI 代理那一份；故意把直连域名也混进去，看它会不会被剔掉。
  private static let appHosts = BinanceHosts(oiProxy: "dstream.binance.me", oiProxyFallbacks: ["gw1.test", "gw2.test:8443"])

  @Test("网关线路下不开币安本家的流：明确报错，不悄悄退回直连、也不拨任何主机")
  func gatewayBinanceSocketThrows() async {
    let spy = SocketSpy()
    let factory = SourceSocketFactory(source: .binance, hosts: Self.appHosts, factory: spy, policy: .gateway)
    await #expect(throws: FeedError.self) { _ = try await factory.connect(to: Self.stream) }
    #expect(spy.hosts.isEmpty)
  }

  @Test("替身（OKX）的流只拨网关的 /market/okx/stream，主、备按顺序")
  func substituteSocketsDialGateways() async {
    let spy = SocketSpy()
    let hosts = BinanceHosts(oiProxy: "gw1.test", oiProxyFallbacks: ["gw2.test:8443"])
    let factory = SourceSocketFactory(source: .okx, hosts: hosts, factory: spy, policy: .gateway)
    _ = try? await factory.connect(to: Self.stream)
    #expect(Set(spy.hosts).isSubset(of: ["gw1.test", "gw2.test"]) && !spy.hosts.isEmpty)
    #expect(Set(spy.paths) == ["/market/okx/stream"])
  }

  @Test("直连：WS 只拨币安自己的域名")
  func directSocketsOnlyDialBinance() async {
    let spy = SocketSpy()
    let factory = SourceSocketFactory(source: .binance, hosts: Self.appHosts, factory: spy, policy: .direct)
    _ = try? await factory.connect(to: Self.stream)
    #expect(spy.hosts == ["dstream.binance.me"])
    // 直连不许改路径：币安只有 `/stream`，拨到 `/market/stream` 会被当场拒掉。
    #expect(spy.paths == ["/stream"])
  }

  // ---------------------------------------------------------------- 运行中换档

  @Test("换档会把上一档留下的网关冷却清掉")
  func switchingPolicyClearsCooldowns() async {
    let spy = DeadRouteSpy()
    let transport = MarketRESTTransport(source: .binance, gateways: ["gw.test"], transport: spy, policy: .gateway)
    _ = try? await transport.get(Self.klines, timeout: 10)   // 网关失败，进冷却
    await transport.setPolicy(.gateway)                       // 用户又按了一次
    _ = try? await transport.get(Self.klines, timeout: 10)
    #expect(await spy.hosts == ["gw.test", "gw.test"])
  }
}
