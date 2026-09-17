import Foundation
import Testing
@testable import KanpanData
import KanpanNetworkTestSupport
import KanpanCore

@Suite(.enabled(if: ProcessInfo.processInfo.environment["KANPAN_LIVE_ROUTING"] == "1"))
struct LiveRoutingTests {
  @Test(.timeLimit(.minutes(1))) func completeOKXFeed() async throws {
    let hosts = BinanceHosts(streamFallbacks: ["kanpan.107-174-172-10.sslip.io"], oiProxy: "kanpan.107-174-172-10.sslip.io", oiProxyFallbacks: ["kanpan.96-44-162-222.sslip.io:8443"])
    let path = Paths(root: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString))
    defer { try? FileManager.default.removeItem(at: path.root) }
    try FileManager.default.createDirectory(at: path.root, withIntermediateDirectories: true)
    // 线路是用户定的：网关 = OKX。跑完还原，别把这台机器的线路改掉。
    let before = MarketRoutePolicyStore.current
    MarketRoutePolicyStore.set(.gateway)
    defer { MarketRoutePolicyStore.set(before) }
    let feed = RoutedMarketFeed(hosts: hosts, paths: path, log: .stdout)
    let events = await feed.events()
    await feed.start(symbol: "BTCUSDT", interval: .m1)
    var selected: MarketSource?, initial = 0, realPush = false, prepended = false
    for await update in events {
      switch update.event {
      case .source(let source): selected = source
      case .series(let series) where series.count >= 300 && initial == 0:
        #expect(selected == .okx)
        initial = series.count
        Task { await feed.loadMore() }
      case .lastBar: realPush = true
      case .prepend:
        let series = await feed.currentSeries
        #expect(series.count > initial)
        prepended = true
      default: break
      }
      if realPush && prepended { break }
    }
    await feed.stop()
    #expect(realPush && prepended)
    let reopened = RoutedMarketFeed(hosts: hosts, paths: path, log: .stdout)
    let restored = await reopened.events()
    await reopened.start(symbol: "BTCUSDT", interval: .m1)
    for await event in restored {
      if case .source(let source) = event.event { #expect(source == .okx); break }
    }
    await reopened.stop()
  }
}
