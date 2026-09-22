import Foundation
import Testing
@testable import KanpanData
import KanpanNetworkTestSupport
import KanpanCore

@Suite("图表微观行情订阅")
struct MicrostructureSubscriptionTests {
  @Test("默认没有额外流，启用后连续切换二十次只留下当前品种，关闭即退订")
  func selections() async {
    let pacer = SystemPacer()
    let deck = ReplayDeck([.hang], answersKeepalive: true)
    let ws = BinanceWS(factory: ReplayFactory(deck: deck, pacer: pacer), pacer: pacer)
    let server = FakeServer { _ in json("[]") }
    let paths = Paths(root: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString))
    defer { try? FileManager.default.removeItem(at: paths.root) }
    let feed = MarketFeed(rest: BinanceREST(transport: FakeTransport(server)), ws: ws, paths: paths)
    await feed.setSnapshotEnabled(false)
    await feed.start(symbol: "BTCUSDT", interval: .h1)
    #expect(await ws.currentStreams.count == 3)
    await feed.setMicrostructure(taker: true, depth: true)
    for i in 0..<20 {
      let symbol = i.isMultiple(of: 2) ? "ETHUSDT" : "BTCUSDT"
      await feed.switchTo(symbol: symbol, interval: .h1)
      let streams = await ws.currentStreams
      #expect(streams.count == 5)
      #expect(streams.allSatisfy { $0.hasPrefix(symbol.lowercased() + "@") })
      #expect(streams.contains(symbol.lowercased() + "@aggTrade"))
      #expect(streams.contains(symbol.lowercased() + "@depth5@100ms"))
    }
    await feed.setMicrostructure(taker: false, depth: false)
    #expect(await ws.currentStreams.count == 3)
    await feed.stop()
  }
}
