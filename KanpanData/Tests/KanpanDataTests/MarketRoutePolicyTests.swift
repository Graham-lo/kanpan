import Foundation
import Testing
@testable import KanpanData
import KanpanCore

// 「行情线路」三档策略：自动 / 直连 / 网关。
// 用户真机自己的网络能直连币安，但自动探测偶发失败就把整套切到 OKX 且卡很久；
// 这套用例守的是「他选了直连之后，代码不许再自作主张」。

// `UserDefaults.standard` 是全局的，两条存取用例并行跑会互相踩；整套串行。
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

  /// 网关也一起坏掉，用来看「直连失败之后有没有记冷却」。
  private actor DeadRouteSpy: HTTPTransport {
    private(set) var hosts: [String] = []
    func get(_ url: URL, timeout: TimeInterval) async throws -> HTTPReply {
      hosts.append(url.host!)
      throw URLError(.cannotFindHost)
    }
  }

  // ---------------------------------------------------------------- 存取

  @Test("策略的默认值是自动，写进去能读回来")
  func storeRoundTrips() {
    let defaults = UserDefaults.standard
    let saved = defaults.string(forKey: MarketRoutePolicyStore.key)
    defer {
      if let saved { defaults.set(saved, forKey: MarketRoutePolicyStore.key) }
      else { defaults.removeObject(forKey: MarketRoutePolicyStore.key) }
    }

    defaults.removeObject(forKey: MarketRoutePolicyStore.key)
    #expect(MarketRoutePolicyStore.current == .auto)
    // 写进去的是垃圾也退回自动，不能把行情卡死在一个不存在的档上。
    defaults.set("nonsense", forKey: MarketRoutePolicyStore.key)
    #expect(MarketRoutePolicyStore.current == .auto)

    for policy in MarketRoutePolicy.allCases {
      MarketRoutePolicyStore.set(policy)
      #expect(MarketRoutePolicyStore.current == policy)
    }
    #expect(MarketRoutePolicy.allCases.map(\.title) == ["自动", "直连", "网关"])
  }

  @Test("换策略会广播，听的人能收到")
  func settingPostsNotification() async {
    let defaults = UserDefaults.standard
    let saved = defaults.string(forKey: MarketRoutePolicyStore.key)
    defer {
      if let saved { defaults.set(saved, forKey: MarketRoutePolicyStore.key) }
      else { defaults.removeObject(forKey: MarketRoutePolicyStore.key) }
    }
    let heard = Counter()
    let token = NotificationCenter.default.addObserver(
      forName: .marketRoutePolicyDidChange, object: nil, queue: nil) { _ in heard.bump() }
    defer { NotificationCenter.default.removeObserver(token) }

    MarketRoutePolicyStore.set(.direct)
    #expect(await waitUntil(2) { heard.value >= 1 })
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

  /// 对照组：`.auto` 下同样三笔，第一笔失败之后就退去网关了。
  /// 没有这一条，上面那条「不记冷却」证明不了什么。
  @Test("自动：失败之后进冷却，后面几笔退去网关")
  func autoCoolsDownAfterFailure() async {
    let spy = DeadRouteSpy()
    let transport = MarketRESTTransport(source: .binance, gateways: ["gw.test"], transport: spy, policy: .auto)
    _ = try? await transport.get(Self.klines, timeout: 10)
    _ = try? await transport.get(Self.klines, timeout: 10)
    let hosts = await spy.hosts
    #expect(hosts.first == "fapi.binance.com")
    #expect(hosts.contains("gw.test"))
    // 第二笔已经不碰直连了。
    #expect(hosts.filter { $0 == "fapi.binance.com" }.count == 1)
  }

  @Test("直连：OKX 源照旧走网关，不受影响")
  func directLeavesOKXAlone() async throws {
    let spy = RouteSpy()
    let transport = MarketRESTTransport(source: .okx, gateways: ["gw.test"], transport: spy, policy: .direct)
    let url = URL(string: "https://fapi.binance.com/fapi/v1/klines?symbol=BTCUSDT&interval=1m&limit=300")!
    _ = try? await transport.get(url, timeout: 10)
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

  // ---------------------------------------------------------------- WS 分流

  /// 记下每台被拨过的 WS 主机，然后一律连不上——只看路由把谁列进了候选。
  private final class SocketSpy: WSSocketFactory, @unchecked Sendable {
    private let lock = NSLock()
    private var dialed: [String] = []
    var hosts: [String] { lock.withLock { dialed } }
    func connect(to url: URL) async throws -> WSSocket {
      lock.withLock { dialed.append(url.host!) }
      throw FeedError.badResponse("测试：WS 不可用")
    }
  }

  private static let stream = URL(string: "wss://fstream.binance.com/stream?streams=btcusdt@kline_1m")!
  /// app 侧 `MainScreen.hosts` 就是这么填的：直连域名自己也排在 fallbacks 第一位。
  private static let appHosts = BinanceHosts(streamFallbacks: ["fstream.binance.com", "gw1.test", "gw2.test:8443"])

  @Test("网关：WS 只拨网关，直连域名混在 fallbacks 里也不算")
  func gatewaySocketsSkipDirect() async {
    let spy = SocketSpy()
    let factory = SourceSocketFactory(source: .binance, hosts: Self.appHosts, factory: spy, policy: .gateway)
    _ = try? await factory.connect(to: Self.stream)
    let dialed = Set(spy.hosts)
    #expect(!dialed.contains("fstream.binance.com"))
    #expect(dialed == ["gw1.test", "gw2.test"])
  }

  @Test("直连：WS 只拨币安自己的域名")
  func directSocketsOnlyDialBinance() async {
    let spy = SocketSpy()
    let factory = SourceSocketFactory(source: .binance, hosts: Self.appHosts, factory: spy, policy: .direct)
    _ = try? await factory.connect(to: Self.stream)
    #expect(spy.hosts == ["fstream.binance.com"])
  }

  // ---------------------------------------------------------------- 运行中换档

  @Test("换档会把上一档留下的冷却清掉")
  func switchingPolicyClearsCooldowns() async {
    let spy = DeadRouteSpy()
    let transport = MarketRESTTransport(source: .binance, gateways: ["gw.test"], transport: spy, policy: .auto)
    _ = try? await transport.get(Self.klines, timeout: 10)   // 直连失败，进冷却
    await transport.setPolicy(.direct)
    _ = try? await transport.get(Self.klines, timeout: 10)
    #expect(await spy.hosts.last == "fapi.binance.com")
  }

  // ---------------------------------------------------------------- 整条路由

  /// WS 一律连不上：这套用例只看 REST 的线路决策，别让 socket 掺和进来。
  private struct DeadSockets: WSSocketFactory {
    func connect(to url: URL) async throws -> WSSocket { throw FeedError.badResponse("测试：WS 不可用") }
  }

  private struct Rig {
    let dir: URL
    let hosts: BinanceHosts
    let binance: FakeServer
    let okx: FakeServer

    init() {
      dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
      try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
      hosts = BinanceHosts(streamFallbacks: ["gw.test"], oiProxy: "gw.test")
      // 两条线路都答 500：币安这边是为了逼出 historyError，OKX 那边只做「有没有
      // 被叫起来」的探针，答什么不重要。
      binance = FakeServer { _ in json("{}", status: 500) }
      okx = FakeServer { _ in json("{}", status: 500) }
    }

    func feed(_ policy: MarketRoutePolicy) -> RoutedMarketFeed {
      RoutedMarketFeed(
        hosts: hosts, paths: Paths(root: dir), log: .silent,
        primary: BinanceREST(hosts: hosts, transport: FakeTransport(binance), limiter: RateLimiter()),
        backup: BinanceREST(hosts: hosts, transport: FakeTransport(okx), limiter: RateLimiter()),
        sockets: DeadSockets(), policy: policy)
    }

    var preferenceURL: URL { dir.appendingPathComponent("market-source.json") }
    func cleanUp() { try? FileManager.default.removeItem(at: dir) }
  }

  @Test("直连：币安探测失败也不切 OKX，也不把 okx 写进偏好", .timeLimit(.minutes(1)))
  func directNeverSwitchesToOKX() async throws {
    let rig = Rig()
    defer { rig.cleanUp() }

    let feed = rig.feed(.direct)
    let events = await feed.events()
    await feed.start(symbol: "BTCUSDT", interval: .m1)

    var sawUnavailable = false
    var sawOKX = false
    for await update in events {
      if case .source(let source) = update.event, source == .okx { sawOKX = true }
      if case .historyError(let message) = update.event, message == "暂时无法连接，点此重试" {
        sawUnavailable = true
        break
      }
    }
    await feed.stop()

    #expect(sawUnavailable)      // 照实说「点此重试」，而不是偷偷换线路
    #expect(!sawOKX)
    #expect(await rig.okx.urls().isEmpty)   // OKX 那条线路一笔都没发出去
    // 也没有任何一步把 okx 记成「下次开机的起点」。
    let preference = try? JSONDecoder().decode(MarketSource.self, from: Data(contentsOf: rig.preferenceURL))
    #expect(preference != .okx)
  }

  @Test("直连：上次会话存下的 okx 偏好不算数，开机直接回币安", .timeLimit(.minutes(1)))
  func directIgnoresSavedOKXPreference() async throws {
    let rig = Rig()
    defer { rig.cleanUp() }
    try JSONEncoder().encode(MarketSource.okx).write(to: rig.preferenceURL)

    let feed = rig.feed(.direct)
    _ = await feed.events()
    await feed.start(symbol: "BTCUSDT", interval: .m1)
    // 起来就打币安；要是听了偏好文件，第一笔会打到 OKX 那条线路上。
    let onBinance = await waitUntil(20) { await !rig.binance.urls().isEmpty }
    await feed.stop()

    #expect(onBinance)
    #expect(await rig.okx.urls().isEmpty)
  }

  /// 对照组：同一套假件，`.auto` 下币安一失败就去叫 OKX。
  /// 没有它，上面那条用例在「探测根本没走到决策点」的情况下也会绿。
  @Test("对照：自动档下币安一失败就去叫 OKX", .timeLimit(.minutes(1)))
  func autoStillFallsBackToOKX() async throws {
    let rig = Rig()
    defer { rig.cleanUp() }

    let feed = rig.feed(.auto)
    _ = await feed.events()
    await feed.start(symbol: "BTCUSDT", interval: .m1)
    let called = await waitUntil(20) { await !rig.okx.urls().isEmpty }
    await feed.stop()
    #expect(called)
  }
}
