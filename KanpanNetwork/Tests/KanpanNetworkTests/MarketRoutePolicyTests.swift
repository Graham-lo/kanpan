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

  /// 记下每一笔打到哪台主机；币安直连一律报错，网关一律回一份合法载荷。
  private actor RouteSpy: HTTPTransport {
    private(set) var hosts: [String] = []
    func get(_ url: URL, timeout: TimeInterval) async throws -> HTTPReply {
      hosts.append(url.host!)
      if url.host == "fapi.binance.com" { throw URLError(.cannotFindHost) }
      return json("[]")
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

  @Test("出厂是网关（2026-10-08），写进去能读回来，认不出的值退回出厂")
  func storeRoundTrips() {
    let defaults = MarketRoutePolicyStore.defaults
    let saved = defaults.string(forKey: MarketRoutePolicyStore.key)
    defer {
      if let saved { defaults.set(saved, forKey: MarketRoutePolicyStore.key) }
      else { defaults.removeObject(forKey: MarketRoutePolicyStore.key) }
    }

    // 出厂网关：国内不开代理直连拿不到币安合约 REST，新装第一次打开不能是整页空白（和网页版一致）。
    #expect(MarketRoutePolicyStore.factoryDefault == .gateway)
    // 包测试进程没有 UI 沙盒的环境变量，起步档就是出厂档。
    #expect(MarketRoutePolicyStore.launchDefault == .gateway)
    defaults.removeObject(forKey: MarketRoutePolicyStore.key)
    #expect(MarketRoutePolicyStore.current == .gateway)
    // 旧版本存过「自动」、或者写进去的是垃圾：都退回出厂，不能把行情卡死在一个不存在的档上。
    defaults.set("auto", forKey: MarketRoutePolicyStore.key)
    #expect(MarketRoutePolicyStore.current == .gateway)
    defaults.set("nonsense", forKey: MarketRoutePolicyStore.key)
    #expect(MarketRoutePolicyStore.current == .gateway)

    for policy in MarketRoutePolicy.allCases {
      MarketRoutePolicyStore.set(policy)
      #expect(MarketRoutePolicyStore.current == policy)
    }
    #expect(MarketRoutePolicy.allCases.map(\.title) == ["直连", "网关"])
    // 两档供的都是币安本家的数（2026-10-08 起网关档不再有 OKX 替身）。
    for policy in MarketRoutePolicy.allCases {
      let caps = BinanceProvider(route: MarketRoute(policy: policy, endpoints: .production)).capabilities
      #expect(caps.upstream == "binance" && !caps.isSubstitute && caps.snapshotNamespace == nil)
    }
  }

  @Test("线路两档只管币安主行情：apiHosts 与 gateways 两档都只有新加坡主机一台（2026-10-02 起没有备机兜底）")
  func apiHostsIgnorePolicy() {
    for policy in MarketRoutePolicy.allCases {
      let route = MarketRoute(policy: policy, endpoints: .production)
      #expect(route.apiHosts == [ServerHosts.primary], "\(policy)")
      #expect(route.gateways == ServerHosts.gateways, "\(policy)")
    }
    #expect(ServerHosts.gateways == [ServerHosts.primary])
    #expect(ServerHosts.names == [ServerHosts.primary])
    #expect(ServerHosts.ports == [443])
    #expect(ServerHosts.api == [ServerHosts.primary])
    // 只给 gateways 时 apiHosts 取第一台；重复的去掉；没有网关就没有 kanpan-api。
    #expect(MarketEndpoints(gateways: ["a", "b"]).api == ["a"])
    #expect(MarketEndpoints(gateways: ["a", "a", "b"], api: ["x", "x"]).api == ["x"])
    #expect(MarketEndpoints(gateways: []).api.isEmpty)
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

    // `PrefsStore` 每落一次盘都会 set 一次，值没变不能把行情重开（没存过就是出厂的网关）。
    MarketRoutePolicyStore.set(MarketRoutePolicyStore.factoryDefault)
    #expect(await staysFalse(for: 0.3) { heard.value >= 1 })
    MarketRoutePolicyStore.set(.direct)
    #expect(await waitUntil(2) { heard.value == 1 })
  }

  // ---------------------------------------------------------------- 直连

  @Test("直连：币安一笔都不打到网关")
  func directNeverTouchesGateway() async {
    let spy = RouteSpy()
    let transport = MarketRESTTransport(gateways: ["gw.test"], transport: spy, policy: .direct)
    _ = try? await transport.get(Self.klines, timeout: 10)
    #expect(await spy.hosts == ["fapi.binance.com"])
  }

  @Test("直连：失败不记冷却，下一笔照样直连")
  func directDoesNotCoolDown() async {
    let spy = DeadRouteSpy()
    let transport = MarketRESTTransport(gateways: ["gw.test"], transport: spy, policy: .direct)
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
    let transport = MarketRESTTransport(gateways: ["gw.test"], transport: spy, policy: .direct)
    _ = try await transport.get(Self.klines, timeout: 12)
    #expect(await spy.timeouts == [12])
  }

  // ---------------------------------------------------------------- 网关

  @Test("网关：一笔都不打直连")
  func gatewayNeverTouchesDirect() async throws {
    let spy = RouteSpy()
    let transport = MarketRESTTransport(gateways: ["gw.test"], transport: spy, policy: .gateway)
    let reply = try await transport.get(Self.klines, timeout: 10)
    #expect(reply.status == 200)
    #expect(await spy.hosts == ["gw.test"])
  }

  /// 网关这一档不记冷却：主机按顺序试、每笔从头试（线上只有一台，歇着就等于整条线路停摆）。
  @Test("网关：失败也不记冷却，下一笔照样问那台网关、不退直连")
  func gatewayFailureDoesNotFallBackToDirect() async {
    let spy = DeadRouteSpy()
    let transport = MarketRESTTransport(gateways: ["gw.test"], transport: spy, policy: .gateway)
    _ = try? await transport.get(Self.klines, timeout: 10)
    _ = try? await transport.get(Self.klines, timeout: 10)
    #expect(await spy.hosts == ["gw.test", "gw.test"])
  }

  @Test("网关：透传白名单之外的地址直接失败，不偷偷走直连")
  func gatewayNeverFallsBackToDirect() async {
    let spy = RouteSpy()
    let transport = MarketRESTTransport(gateways: ["gw.test"], transport: spy, policy: .gateway)
    let zip = URL(string: "https://data.binance.vision/data/futures/um/daily/metrics/BTCUSDT/BTCUSDT-metrics-2026-10-01.zip")!
    await #expect(throws: (any Error).self) { try await transport.get(zip, timeout: 10) }
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

  @Test("网关：币安的流拨 Python 网关的 /market/stream hub（组合流同形），主、备都在候选里、查询原样带上")
  func gatewaySocketsDialTheHub() async {
    let spy = SocketSpy()
    let factory = SourceSocketFactory(gateways: ["gw1.test", "gw2.test:8443"], factory: spy, policy: .gateway)
    _ = try? await factory.connect(to: Self.stream)
    #expect(Set(spy.hosts).isSubset(of: ["gw1.test", "gw2.test"]) && spy.hosts.contains("gw1.test"))
    #expect(Set(spy.paths) == ["/market/stream"])
    #expect(!spy.hosts.contains("dstream.binance.me"))
  }

  @Test("网关：没有网关就明确报错，不悄悄退回直连、也不拨任何主机")
  func gatewayWithoutGatewaysThrows() async {
    let spy = SocketSpy()
    let factory = SourceSocketFactory(gateways: [], factory: spy, policy: .gateway)
    await #expect(throws: FeedError.self) { _ = try await factory.connect(to: Self.stream) }
    #expect(spy.hosts.isEmpty)
  }

  @Test("直连：WS 只拨币安自己的域名")
  func directSocketsOnlyDialBinance() async {
    let spy = SocketSpy()
    let factory = SourceSocketFactory(gateways: ["gw1.test", "gw2.test:8443"], factory: spy, policy: .direct)
    _ = try? await factory.connect(to: Self.stream)
    #expect(spy.hosts == ["dstream.binance.me"])
    // 直连不许改路径：币安只有 `/stream`，拨到 `/market/stream` 会被当场拒掉。
    #expect(spy.paths == ["/stream"])
  }

  @Test("网关 hub 只放行 ticker / markPrice@1s / aggTrade / kline_*：逐笔与五档在网关档不订")
  func gatewayStreamFilter() {
    let allows = BinanceProvider.gatewayAllows
    let topics: [StreamTopic] = [.kline(symbol: "BTCUSDT", interval: .y1), .kline(symbol: "BTCUSDT", interval: .m1),
                                 .ticker(symbol: "BTCUSDT"), .markPrice(symbol: "BTCUSDT"),
                                 .aggTrade(symbol: "BTCUSDT"), .trade(symbol: "BTCUSDT"), .depth(symbol: "BTCUSDT")]
    let names = topics.map(BinanceProvider.streamName)
    #expect(names.filter(allows) == ["btcusdt@kline_1M", "btcusdt@kline_1m", "btcusdt@ticker",
                                     "btcusdt@markPrice@1s", "btcusdt@aggTrade"])
  }

  @Test("网关档的推送连接只把 hub 认的流交出去，直连照旧全订", .timeLimit(.minutes(1)))
  func gatewayStreamDropsUnsupportedTopics() async throws {
    let topics: [StreamTopic] = [.kline(symbol: "BTCUSDT", interval: .m1), .trade(symbol: "BTCUSDT"),
                                 .depth(symbol: "BTCUSDT"), .ticker(symbol: "BTCUSDT")]
    for policy in MarketRoutePolicy.allCases {
      let bench = GateSocketBench()
      let provider = BinanceProvider(hosts: BinanceHosts(oiProxy: "gw.test"), policy: policy, sockets: bench)
      let stream = provider.makeStream(silenceMs: 1e12, log: .silent)
      _ = await stream.start(topics: topics)
      // 网关档：MarketSocketRouter 要先等到一帧行情才选中这条连接，这里只看拨出去的地址。
      #expect(await waitUntil(5) { await bench.socket(1) != nil })
      let dialed = try #require(await bench.socket(1)).url
      let query = URLComponents(url: dialed, resolvingAgainstBaseURL: false)?.queryItems?.first?.value ?? ""
      if policy == .gateway {
        #expect(dialed.host == "gw.test" && dialed.path == "/market/stream")
        #expect(query == "btcusdt@kline_1m/btcusdt@ticker")
      } else {
        #expect(dialed.host == "dstream.binance.me" && dialed.path == "/stream")
        #expect(query.contains("@trade") && query.contains("@depth5@100ms"))
      }
      await stream.stop()
    }
  }

  // ---------------------------------------------------------------- 运行中换档

  @Test("运行中换档：下一笔就按新档走")
  func switchingPolicyTakesEffect() async {
    let spy = DeadRouteSpy()
    let transport = MarketRESTTransport(gateways: ["gw.test"], transport: spy, policy: .gateway)
    _ = try? await transport.get(Self.klines, timeout: 10)
    await transport.setPolicy(.direct)
    _ = try? await transport.get(Self.klines, timeout: 10)
    #expect(await spy.hosts == ["gw.test", "fapi.binance.com"])
  }
}
