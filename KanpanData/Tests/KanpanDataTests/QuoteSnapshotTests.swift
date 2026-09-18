import Foundation
import Testing
@testable import KanpanData
import KanpanNetworkTestSupport
import KanpanCore

@Suite("报价快照与整屏补价")
struct QuoteSnapshotTests {

  private func tempPaths() -> Paths {
    let dir = URL(fileURLWithPath: NSTemporaryDirectory())
      .appendingPathComponent("kanpan-quotes-\(UUID().uuidString)")
    let p = Paths(root: dir)
    try? p.ensureRoot()
    return p
  }

  private func ticker(_ symbol: String, last: Double, at ms: Int64) -> Ticker {
    Ticker(symbol: symbol, last: last, changePercent: 1.5, high: last + 1, low: last - 1,
           quoteVolume: 1_000, markPrice: last, open24h: last - 2, timeMs: ms, lastTradeID: 42)
  }

  @Test("冷启动读回上次看到的报价，值与交易所时间都不走样")
  func roundTrip() throws {
    let p = tempPaths()
    defer { try? FileManager.default.removeItem(at: p.root) }

    let written = [ticker("BTCUSDT", last: 78_000, at: 1_700_000_000_000),
                   ticker("ETHUSDT", last: 4_100, at: 1_700_000_000_500)]
    QuoteSnapshot.write(written, to: p.quotes)

    let back = QuoteSnapshot.read(p.quotes).sorted { $0.symbol < $1.symbol }
    #expect(back.count == 2)
    #expect(back[0].symbol == "BTCUSDT" && back[0].last == 78_000)
    // 交易所时钟要一起留下：显示层靠它判断这条还算不算「实时」。
    #expect(back[0].timeMs == 1_700_000_000_000)
    #expect(back[1].symbol == "ETHUSDT" && back[1].last == 4_100)
  }

  @Test("只留最近的一批，文件不会越滚越大")
  func capsEntries() throws {
    let p = tempPaths()
    defer { try? FileManager.default.removeItem(at: p.root) }

    let many = (0..<(QuoteSnapshot.maxEntries + 50)).map {
      ticker("SYM\($0)USDT", last: Double($0 + 1), at: 1_700_000_000_000)
    }
    QuoteSnapshot.write(many, to: p.quotes)
    #expect(QuoteSnapshot.read(p.quotes).count == QuoteSnapshot.maxEntries)
  }

  @Test("没有文件、或文件是坏的，就是空，不抛")
  func missingOrCorrupt() throws {
    let p = tempPaths()
    defer { try? FileManager.default.removeItem(at: p.root) }

    #expect(QuoteSnapshot.read(p.quotes).isEmpty)
    // 报价现在落在 `profiles/<档案>/` 底下（不串号）。生产代码那条路由
    // `QuoteSnapshot.write` 自己建目录；这儿是绕过它手写一个坏文件，得自己先建。
    try p.ensure(p.quotes.deletingLastPathComponent())
    try Data("not json".utf8).write(to: p.quotes)
    #expect(QuoteSnapshot.read(p.quotes).isEmpty)
    QuoteSnapshot.remove(p.quotes)
    #expect(!FileManager.default.fileExists(atPath: p.quotes.path))
  }

  @Test("全市场报价一次往返换回整屏，坏行被剔掉")
  func allTickersInOneTrip() async throws {
    let rows: [[String: Any]] = [
      ["symbol": "BTCUSDT", "lastPrice": "78000", "priceChangePercent": "1.2",
       "highPrice": "79000", "lowPrice": "76000", "quoteVolume": "9999", "openPrice": "77000"],
      ["symbol": "ETHUSDT", "lastPrice": "4100", "priceChangePercent": "-0.4",
       "highPrice": "4200", "lowPrice": "4000", "quoteVolume": "8888", "openPrice": "4120"],
      // 价格为 0 的行不该进列表。
      ["symbol": "DEADUSDT", "lastPrice": "0", "priceChangePercent": "0",
       "highPrice": "0", "lowPrice": "0", "quoteVolume": "0", "openPrice": "0"],
    ]
    let body = try JSONSerialization.data(withJSONObject: rows)
    let server = FakeServer { _ in HTTPReply(status: 200, body: body) }
    let rest = BinanceREST(transport: FakeTransport(server), pacer: StepPacer())
    let all = try await rest.tickers24h()
    #expect(all.map(\.symbol).sorted() == ["BTCUSDT", "ETHUSDT"])
    // 一次请求，不是一行一个。
    #expect(await server.urls().count == 1)
    #expect(await server.urls().first?.query == nil)
  }

  @Test("全市场报价不往网关转发：网关只代理单品种，转过去的载荷无从校验")
  func allTickersNeverReachGateway() async throws {
    let seen = FakeServer { _ in HTTPReply(status: 200, body: Data("[]".utf8)) }
    let transport = MarketRESTTransport(source: .okx, gateways: ["gateway.test"], transport: FakeTransport(seen))
    let url = URL(string: "https://fapi.binance.com/fapi/v1/ticker/24hr")!
    await #expect(throws: (any Error).self) { try await transport.get(url, timeout: 5) }
    #expect(await seen.urls().isEmpty)

    // 带 symbol 的单品种报价照常走网关。
    let single = URL(string: "https://fapi.binance.com/fapi/v1/ticker/24hr?symbol=BTCUSDT")!
    let gateway = FakeServer { _ in json(#"{"source":"okx","ticker":{}}"#) }
    let ok = MarketRESTTransport(source: .okx, gateways: ["gateway.test"], transport: FakeTransport(gateway))
    _ = try await ok.get(single, timeout: 5)
    #expect(await gateway.urls().first?.host == "gateway.test")
  }
}
