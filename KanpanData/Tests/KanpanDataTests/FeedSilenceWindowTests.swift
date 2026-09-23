import Foundation
import Testing
@testable import KanpanData
import KanpanNetwork
import KanpanNetworkTestSupport
import KanpanCore

/// A-07 第②层：**第一帧有效行情之前**的静默窗口，两档线路都是 60 秒。
///
/// 报告原来写的是「直连 60 秒 / 网关 15 秒」，那是给「一条 WS 同时竞速几个域名」
/// 准备的：竞速时 15 秒换一条候选才有意义。这件事已经不存在了——线路是用户在设置里
/// 定死的，只有直连/网关两档，绝不自动混源；`streamFallbacks` 与那道「有竞速候选就夹到
/// 15 秒」的钳子 2026-09-24 已整条删掉。网关档（OKX）只订 kline 一种流，冷门永续
/// 15 秒内完全可能一帧都不推。
/// 窗口要是真的按 15 秒算，那些品种就会陷进「静默→重连→再静默」的循环。
///
/// 这条用例守的就是**实际生效的那个数**，不是调用处写了什么字面量。
@Suite("A-07 第②层：首帧窗口")
struct FeedSilenceWindowTests {

  /// WS 一律连不上。这条用例只看窗口配置，socket 通不通无关。
  private struct DeadSockets: WSSocketFactory {
    func connect(to url: URL) async throws -> WSSocket { throw FeedError.badResponse("测试：WS 不可用") }
  }

  private struct Rig {
    let dir: URL
    let hosts: BinanceHosts
    init() {
      dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
      try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
      hosts = BinanceHosts(oiProxy: "gw.test")
    }
    func feed(_ policy: MarketRoutePolicy) -> RoutedMarketFeed {
      let dead = FakeServer { _ in json("{}", status: 500) }
      return RoutedMarketFeed(
        hosts: hosts, paths: Paths(root: dir), log: .silent,
        primary: BinanceREST(hosts: hosts, transport: FakeTransport(dead), limiter: RateLimiter()),
        backup: BinanceREST(hosts: hosts, transport: FakeTransport(dead), limiter: RateLimiter()),
        sockets: DeadSockets(), policy: policy)
    }
    func cleanUp() { try? FileManager.default.removeItem(at: dir) }
  }

  @Test("网关档（OKX）等第一帧的窗口实际就是 60 秒，不被 15 秒钳子咬住", .timeLimit(.minutes(1)))
  func gatewayFirstFrameWindowIsSixtySeconds() async throws {
    let rig = Rig()
    defer { rig.cleanUp() }
    let feed = rig.feed(.gateway)
    _ = await feed.events()
    await feed.start(symbol: "BTCUSDT", interval: .m1)
    #expect(await waitUntil(20) { await feed.wsSilenceMsForTests() != nil })
    let window = await feed.wsSilenceMsForTests()
    await feed.stop()
    #expect(window == 60_000, "网关档的首帧窗口是 \(window ?? -1) 毫秒；冷门永续会被它反复拆连接")
  }

  @Test("直连档的窗口也是 60 秒（两档一视同仁）", .timeLimit(.minutes(1)))
  func directFirstFrameWindowIsSixtySeconds() async throws {
    let rig = Rig()
    defer { rig.cleanUp() }
    let feed = rig.feed(.direct)
    _ = await feed.events()
    await feed.start(symbol: "BTCUSDT", interval: .m1)
    #expect(await waitUntil(20) { await feed.wsSilenceMsForTests() != nil })
    let window = await feed.wsSilenceMsForTests()
    await feed.stop()
    #expect(window == 60_000)
  }
}
