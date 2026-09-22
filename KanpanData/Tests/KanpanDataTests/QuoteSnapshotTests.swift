import Foundation
import Testing
@testable import KanpanData
import KanpanNetworkTestSupport
import KanpanCore
import KanpanNetwork

@Suite("报价快照与整屏补价")
struct QuoteSnapshotTests {
  @Test("涨跌额往返落盘，旧快照缺字段仍可读")
  func priceChangeRoundTrip() throws {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: url) }
    let value = Ticker(symbol: "MUUSDT", last: 1052.18, changePercent: 0.64,
      high: 1053.6, low: 1044.11, quoteVolume: 36_730_000, priceChange: 6.72)
    QuoteSnapshot.write([value], to: url)
    #expect(QuoteSnapshot.read(url).first?.priceChange == 6.72)
    try Data(#"[{"s":"MUUSDT","l":1052.18,"c":0.64}]"#.utf8).write(to: url)
    #expect(QuoteSnapshot.read(url).first?.priceChange == nil)
    #expect(QuoteSnapshot.read(url).first?.last == 1052.18)
  }

  private func tempPaths() -> Paths {
    let dir = URL(fileURLWithPath: NSTemporaryDirectory())
      .appendingPathComponent("kanpan-quotes-\(UUID().uuidString)")
    let p = Paths(root: dir)
    try? p.ensureRoot()
    return p
  }

  /// 收日志的小盒子（`FeedLog` 的闭包是 `@Sendable`，不能直接捕获局部 var）。
  private final class Lines: @unchecked Sendable {
    private let lock = NSLock()
    private var lines: [String] = []
    func note(_ s: String) { lock.lock(); lines.append(s); lock.unlock() }
    var all: [String] { lock.lock(); defer { lock.unlock() }; return lines }
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

    // 读的时候要给「现在几点」：超过 24 小时的行不再返回（审查 B-06），
    // 所以夹具里的时间和 `now` 得对上。
    let back = QuoteSnapshot.read(p.quotes, now: 1_700_000_001_000)
      .sorted { $0.symbol < $1.symbol }
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
    #expect(QuoteSnapshot.read(p.quotes, now: 1_700_000_000_000).count == QuoteSnapshot.maxEntries)
  }

  // -------------------------------------------------------------- B-T15

  @Test("B-T15 隔了一天以上的那口价不再摆出来，昨天的还摆")
  func staleRowsAreNotReturned() throws {
    let p = tempPaths()
    defer { try? FileManager.default.removeItem(at: p.root) }

    let now: Int64 = 1_700_000_000_000
    QuoteSnapshot.write([ticker("BTCUSDT", last: 78_000, at: now - 3_600_000),                 // 1 小时前
                         ticker("ETHUSDT", last: 4_100, at: now - 23 * 3_600_000),             // 23 小时前
                         ticker("GONEUSDT", last: 9, at: now - 25 * 3_600_000),                // 25 小时前
                         ticker("OLDUSDT", last: 7, at: now - 30 * 86_400_000)],               // 一个月前
                        to: p.quotes)

    let back = QuoteSnapshot.read(p.quotes, now: now).map(\.symbol).sorted()
    #expect(back == ["BTCUSDT", "ETHUSDT"])
    // 正好 24 小时算还在；多一毫秒就不算。
    #expect(QuoteSnapshot.read(p.quotes, now: now - 3_600_000 + QuoteSnapshot.maxAgeMs)
              .map(\.symbol) == ["BTCUSDT"])
    #expect(QuoteSnapshot.read(p.quotes, now: now - 3_600_000 + QuoteSnapshot.maxAgeMs + 1).isEmpty)
    // 落盘的行一条都没少——筛的是「摆不摆出来」，不是删数据。
    #expect(QuoteSnapshot.read(p.quotes, now: now, maxAgeMs: nil).count == 4)
  }

  @Test("B-T15 老版本写下的行没有交易所时钟，按文件自己的修改时间算年龄")
  func rowsWithoutClockUseFileTime() throws {
    let p = tempPaths()
    defer { try? FileManager.default.removeItem(at: p.root) }
    try p.ensure(p.quotes.deletingLastPathComponent())

    // 手写一份老格式：没有 `t`。
    let rows: [[String: Any]] = [["s": "BTCUSDT", "l": 78_000, "c": 1.2, "h": 79_000,
                                  "lo": 76_000, "v": 9_999]]
    try JSONSerialization.data(withJSONObject: rows).write(to: p.quotes)
    let fileMs = Int64((try #require(try FileManager.default
      .attributesOfItem(atPath: p.quotes.path)[.modificationDate] as? Date))
      .timeIntervalSince1970 * 1000)

    #expect(QuoteSnapshot.read(p.quotes, now: fileMs + 1_000).map(\.symbol) == ["BTCUSDT"])
    #expect(QuoteSnapshot.read(p.quotes, now: fileMs + QuoteSnapshot.maxAgeMs + 60_000).isEmpty)
  }

  // ---------------------------------------------------- 复核项 1a：NaN 不许毒死整份快照

  @Test("一行成交额是 NaN，整份快照照样落得下去")
  func nonFiniteFieldsDoNotKillTheWholeSnapshot() throws {
    let p = tempPaths()
    defer { try? FileManager.default.removeItem(at: p.root) }

    let now: Int64 = 1_700_000_000_000
    // BTC 的成交额缺了（交易所没给 / 网关合成行算不出来），别的字段都好。
    var btc = ticker("BTCUSDT", last: 78_000, at: now)
    btc.quoteVolume = .nan
    // 更狠的一行：只有价是真的。
    var weird = ticker("PEPEUSDT", last: 0.0000004, at: now)
    weird.quoteVolume = .infinity
    weird.high = .nan; weird.low = .nan; weird.changePercent = .nan
    weird.open24h = .nan; weird.markPrice = .nan
    let eth = ticker("ETHUSDT", last: 4_100, at: now)

    let lines = Lines()
    QuoteSnapshot.write([btc, weird, eth], to: p.quotes, log: FeedLog { lines.note($0) })
    // 关键一条：文件真的写下去了。`JSONEncoder` 碰到 NaN 会抛
    // `EncodingError.invalidValue`，而 write 是一次性编整批——从前这一行
    // 就把另外两行（以及整个冷启动第一帧）一起带走了。
    #expect(FileManager.default.fileExists(atPath: p.quotes.path))
    #expect(lines.all.isEmpty, "写成功不该有日志：\(lines.all)")

    let back = Dictionary(uniqueKeysWithValues:
      QuoteSnapshot.read(p.quotes, now: now).map { ($0.symbol, $0) })
    #expect(back.count == 3)
    // 好行一个字没变。
    #expect(back["ETHUSDT"]?.quoteVolume == 1_000)
    #expect(back["BTCUSDT"]?.last == 78_000)
    #expect(back["BTCUSDT"]?.changePercent == 1.5)
    #expect(back["BTCUSDT"]?.timeMs == now)
    // 缺的那一格读回来还是「缺」：不是 0。0 会在自选表上写成 `0.00`，
    // 在板块页上被当成真的零成交额去参与排序和聚合。
    #expect(back["BTCUSDT"]?.quoteVolume.isNaN == true)
    #expect(back["PEPEUSDT"]?.last == 0.0000004)
    #expect(back["PEPEUSDT"]?.quoteVolume.isNaN == true)
    #expect(back["PEPEUSDT"]?.high.isNaN == true)
    #expect(back["PEPEUSDT"]?.low.isNaN == true)
    #expect(back["PEPEUSDT"]?.changePercent.isNaN == true)
    #expect(back["PEPEUSDT"]?.open24h == nil)
    #expect(back["PEPEUSDT"]?.markPrice == nil)
  }

  @Test("落盘失败要留一行日志，不许悄悄吞掉")
  func writeFailuresAreLogged() throws {
    let p = tempPaths()
    defer { try? FileManager.default.removeItem(at: p.root) }
    // 把快照该待的那个目录位置先占成一个普通文件：建目录必然失败。
    let dir = p.quotes.deletingLastPathComponent()
    try? FileManager.default.removeItem(at: dir)
    try FileManager.default.createDirectory(at: dir.deletingLastPathComponent(),
                                           withIntermediateDirectories: true)
    try Data("occupied".utf8).write(to: dir)

    let lines = Lines()
    QuoteSnapshot.write([ticker("BTCUSDT", last: 78_000, at: 1_700_000_000_000)],
                        to: p.quotes, log: FeedLog { lines.note($0) })
    #expect(lines.all.count == 1)
    #expect(lines.all.first?.contains("自选报价快照落盘失败") == true)
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

  @Test("全市场报价走网关自己的 tickers 端点，载荷仍要同源校验")
  func allTickersGoThroughTheGatewaysOwnEndpoint() async throws {
    // 网关这一档下板块页原来永久取不到全市场报价（审查 A-04）：`/fapi/v1/ticker/24hr`
    // 不带 `symbol`，路由层就当「网关代理不了」直接退直连。现在它转去网关自己的
    // `/market/v1/tickers`，信封和单品种一样（`source` + `ticker`）。
    let rows = #"[{"symbol":"BTCUSDT","lastPrice":"78000","priceChangePercent":"1.2","highPrice":"79000","lowPrice":"76000","quoteVolume":"9999","openPrice":"77000"}]"#
    let seen = FakeServer { _ in json(#"{"source":"okx","ticker":"# + rows + "}") }
    let transport = MarketRESTTransport(source: .okx, gateways: ["gateway.test"], transport: FakeTransport(seen))
    let url = URL(string: "https://fapi.binance.com/fapi/v1/ticker/24hr")!
    let reply = try await transport.get(url, timeout: 5)
    #expect(await seen.urls().first?.host == "gateway.test")
    #expect(await seen.urls().first?.path == "/market/v1/tickers")
    // 回给上层的是剥掉信封的币安形状数组。
    let back = try #require(try JSONSerialization.jsonObject(with: reply.body) as? [[String: Any]])
    #expect(back.compactMap { $0["symbol"] as? String } == ["BTCUSDT"])

    // 换源了的载荷照旧不收：这是同源校验，不是「只代理单品种」。
    let wrongSource = FakeServer { _ in json(#"{"source":"binance","ticker":[]}"#) }
    let strict = MarketRESTTransport(source: .okx, gateways: ["gateway.test"],
                                     transport: FakeTransport(wrongSource))
    await #expect(throws: (any Error).self) { try await strict.get(url, timeout: 5) }

    // 带 symbol 的单品种报价照常走网关。
    let single = URL(string: "https://fapi.binance.com/fapi/v1/ticker/24hr?symbol=BTCUSDT")!
    let gateway = FakeServer { _ in json(#"{"source":"okx","ticker":{}}"#) }
    let ok = MarketRESTTransport(source: .okx, gateways: ["gateway.test"], transport: FakeTransport(gateway))
    _ = try await ok.get(single, timeout: 5)
    #expect(await gateway.urls().first?.host == "gateway.test")
  }
}
