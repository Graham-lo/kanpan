import Foundation
import Testing
@testable import KanpanData
import KanpanNetworkTestSupport
import KanpanCore

@Suite("REST 与 DTO")
struct RESTTests {

  @Test("全市场WS数组包含普通与TradFi报价，保持真实24h涨跌幅")
  func marketTickerArray() throws {
    let frame = Data(#"{"stream":"!ticker@arr","data":[{"e":"24hrTicker","s":"SNDKUSDT","o":"102.5","c":"100.25","P":"-2.3","h":"104","l":"98","q":"1000"},{"e":"24hrTicker","s":"BTCUSDT","c":"78000","P":"1.2","h":"79000","l":"76000","q":"999999"}]}"#.utf8)
    let envelope = try JSONDecoder().decode(StreamEnvelope.self, from: frame)
    guard case .tickerBatch(let batch) = envelope.payload else { Issue.record("没有解出全市场报价"); return }
    #expect(batch.count == 2)
    #expect(batch[0].open24h == 102.5)
    #expect(batch[0].symbol == "binance/usd_m/SNDKUSDT" && batch[0].last == 100.25 && batch[0].changePercent == -2.3)
  }

  @Test("USDT TradFi全保留，USD1、普通USDC、交割排除；停牌的行留在表里带下架标记；旧目录即时刷新")
  func tradFiAndOldCatalog() async throws {
    let names = ["SNDKUSDT", "MUUSDT", "SKHYUSDT", "SKHYNIXUSDT", "FUTUREUSDT", "STOPUSDT", "XUSDC", "SPCXUSD1", "USDCUSDT"]
    let rows: [[String: Any]] = names.enumerated().map { index, symbol in
      ["symbol": symbol, "baseAsset": symbol.replacingOccurrences(of: "USDT", with: ""),
       "quoteAsset": index == 7 ? "USD1" : (index == 6 ? "USDC" : "USDT"), "pricePrecision": 2, "quantityPrecision": 3,
       "contractType": index == 4 ? "CURRENT_QUARTER" : ((index == 6 || index == 8) ? "PERPETUAL" : "TRADIFI_PERPETUAL"),
       "status": index == 5 ? "SETTLING" : "TRADING", "filters": []]
    }
    let body = try JSONSerialization.data(withJSONObject: ["symbols": rows])
    // 停牌那一行（STOPUSDT）现在**留在表里**，带 `.delisted`（审查 B-06）：
    // 扔掉它等于把「已下架」和「根本不存在」压成同一件事。
    let parsed = try BinanceREST.parseExchangeInfo(body)
    #expect(parsed.map(\.id.symbol) == (Array(names.prefix(4)) + ["STOPUSDT"]).sorted())
    #expect(parsed.filter { $0.status.hasLivePrice }.map(\.id.symbol) == Array(names.prefix(4)).sorted())
    #expect(parsed.first { $0.symbol == "binance/usd_m/STOPUSDT" }?.status == .delisted)
    #expect(parsed.first { $0.symbol == "binance/usd_m/SPCXUSD1" } == nil)
    let server = FakeServer { _ in HTTPReply(status: 200, body: body) }
    let dir = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("catalog-\(UUID())")
    defer { try? FileManager.default.removeItem(at: dir) }
    let paths = Paths(root: dir); try paths.ensureRoot()
    let oldList = try JSONSerialization.jsonObject(with: JSONEncoder().encode([
      SymbolInfo(symbol: "BTCUSDT", base: "BTC", pricePrecision: 2, tickSize: 0.1)]))
    try JSONSerialization.data(withJSONObject: ["at": 1000, "list": oldList]).write(to: paths.exchangeInfo)
    let catalog = SymbolCatalog(rest: BinanceREST(transport: FakeTransport(server), pacer: StepPacer()), paths: paths)
    #expect(await catalog.all(now: 1100).count == 5)
    #expect(await catalog.all(now: 1200).count == 5)
    #expect(await server.urls().count == 1)
  }

  @Test("当前全部717个产品品种进入独立分类模块，保留细分元数据；停牌与待开盘的行带状态留着")
  func completeCatalogClassification() throws {
    let list = try BinanceREST.parseExchangeInfo(Fixture.data("catalog-classification-2026-09-15.json"))
    // 全表 847 行：717 在交易、129 已停止交易、1 还没开盘（审查 B-06 起不再丢弃后两类）。
    #expect(list.count == 847)
    #expect(list.filter { $0.status == .delisted }.count == 129)
    #expect(list.filter { $0.status == .pending }.count == 1)
    let trading = list.filter { $0.status.hasLivePrice }
    #expect(trading.count == 717)
    let classified = trading.map(SymbolClassifier.classify)
    #expect(classified.filter { $0.asset == .crypto }.count == 525)
    #expect(classified.filter { $0.asset == .equity }.count == 180)
    #expect(classified.filter { $0.asset == .preciousMetal }.count == 4)
    #expect(classified.filter { $0.asset == .commodity }.count == 4)
    #expect(classified.filter { $0.asset == .index }.count == 2)
    #expect(classified.filter { $0.asset == .preMarket }.count == 2)
    #expect(classified.filter { $0.source == .unknown }.isEmpty)
    #expect(trading.allSatisfy { $0.underlyingSubTypes != nil && $0.contractType != nil })
  }

  // ---------------------------------------------------------------- A2.1

  @Test("exchangeInfo 只留 USDT 永续，tickSize 解析正确")
  func exchangeInfo() throws {
    let list = try BinanceREST.parseExchangeInfo(Fixture.data("exchangeInfo-sample.json"))
    // 样本里塞了 USDC 永续（滤掉）和 SETTLING 的负样本（留着，带 `.delisted`）。
    #expect(list.filter { $0.status.hasLivePrice }.map(\.id.symbol)
              == ["1000BONKUSDT", "BTCUSDT", "ETHUSDT", "SOLUSDT"])
    #expect(list.filter { $0.status == .delisted }.map(\.id.symbol)
              == ["DEFIUSDT", "MKRUSDT", "OMGUSDT", "WAVESUSDT"])
    let btc = try #require(list.first { $0.symbol == "binance/usd_m/BTCUSDT" })
    #expect(btc.base == "BTC")
    #expect(btc.quote == "USDT")
    #expect(btc.tickSize == 0.1)
    #expect(btc.pricePrecision == 2)
    #expect(btc.priceDecimals == 1)          // tickSize 0.1 → 小数 1 位
    let bonk = try #require(list.first { $0.symbol == "binance/usd_m/1000BONKUSDT" })
    #expect(bonk.tickSize == 0.000001)
    #expect(bonk.priceDecimals == 6)
  }

  @Test("exchangeInfo 走一遍 transport，请求路径正确")
  func exchangeInfoOverTransport() async throws {
    let body = Fixture.data("exchangeInfo-sample.json")
    let server = FakeServer { _ in HTTPReply(status: 200, body: body) }
    let rest = BinanceREST(transport: FakeTransport(server), pacer: StepPacer())
    let list = try await rest.exchangeInfo()
    #expect(list.count == 8)
    #expect(list.filter { $0.status.hasLivePrice }.count == 4)
    #expect(await server.urls().first?.path == "/fapi/v1/exchangeInfo")
  }

  // ---------------------------------------------------------------- A2.2

  @Test("1500 根 klines：严格递增、等距、无重复")
  func klinesShape() async throws {
    let body = Fixture.data("klines-btcusdt-1h.json")
    let server = FakeServer { _ in HTTPReply(status: 200, body: body) }
    let rest = BinanceREST(transport: FakeTransport(server), pacer: StepPacer())
    let s = try await rest.latestSeries(symbol: "BTCUSDT", interval: .h1)
    #expect(s.count == 1500)
    #expect(s.step == 3_600_000)
    for i in 1..<s.count {
      #expect(s.time(at: i) == s.time(at: i - 1) + 3_600_000)
    }
    #expect(Set((0..<s.count).map { s.time(at: $0) }).count == s.count)
    #expect(s.high[0] >= s.low[0])
    // 请求串固定字典序，日志可比对。
    let q = try #require(await server.urls().first?.query)
    #expect(q == "interval=1h&limit=1500&symbol=BTCUSDT")
  }

  // ---------------------------------------------------------------- A2.3

  @Test("向前翻 10 页：endTime 一页页往前、无缝无重复、每页间隔 ≥ 120ms")
  func history() async throws {
    // 假 server 按 endTime 造连续的 1500 根，边界严丝合缝。
    let step: Int64 = 3_600_000
    let server = FakeServer(pacer: SystemPacer()) { url in
      let q = URLComponents(url: url, resolvingAgainstBaseURL: false)!.queryItems ?? []
      let end = q.first { $0.name == "endTime" }?.value.flatMap { Int64($0) } ?? 1_800_000_000_000
      let last = (end / step) * step
      let rows = (0..<1500).map { i -> String in
        let t = last - Int64(1499 - i) * step
        return "[\(t),\"1\",\"2\",\"0\",\"1.5\",\"9\",\(t + step - 1),\"1\",1,\"1\",\"1\",\"0\"]"
      }
      return json("[" + rows.joined(separator: ",") + "]")
    }
    let pacer = StepPacer()
    let rest = BinanceREST(transport: FakeTransport(server), pacer: pacer)
    let bars = try await rest.history(symbol: "BTCUSDT", interval: .h1, pages: 10,
                                      before: 1_800_000_000_000)
    #expect(bars.count == 15000)
    #expect(Set(bars.map(\.openTime)).count == 15000)
    for i in 1..<bars.count { #expect(bars[i].openTime == bars[i - 1].openTime + step) }
    // 限流器的最小间隔：10 页 → 至少 9 次等待，每次 ≥ 120ms。
    let gaps = await pacer.sleepLog()
    #expect(gaps.count >= 9)
    #expect(gaps.allSatisfy { $0 >= 120 } == true)
    #expect(await server.urls().count == 10)
  }

  // ---------------------------------------------------------------- 聚合

  @Test("1y 由 1M 聚出来")
  func yearlyAggregate() throws {
    // 12 根月线聚成 1 根年线。
    var bars: [Bar] = []
    for m in 1...12 {
      let t = Aggregator.utcMs(year: 2024, month: m, day: 1)
      bars.append(Bar(openTime: t, open: Double(m), high: Double(m) + 10,
                      low: Double(m) - 10, close: Double(m) + 1, volume: Double(m)))
    }
    let monthly = BarSeries(symbol: "BTCUSDT", interval: .mo1, bars: bars)
    let yearly = Aggregator.bucket(series: monthly, into: .y1)
    #expect(yearly.count == 1)
    #expect(yearly.open[0] == 1)
    #expect(yearly.close[0] == 13)
    #expect(yearly.high[0] == 22)
    #expect(yearly.low[0] == -9)
    #expect(yearly.volume[0] == 78)
  }

  @Test("dedup 去重并排序")
  func dedup() {
    let raw = [Bar(openTime: 3, open: 1, high: 1, low: 1, close: 1, volume: 1),
               Bar(openTime: 1, open: 1, high: 1, low: 1, close: 1, volume: 1),
               Bar(openTime: 3, open: 9, high: 9, low: 9, close: 9, volume: 9),
               Bar(openTime: 2, open: 1, high: 1, low: 1, close: 1, volume: 1)]
    let out = BinanceREST.dedup(raw)
    #expect(out.map(\.openTime) == [1, 2, 3])
    #expect(out.last?.close == 9)     // 同 openTime 后到的更新
  }

  // ---------------------------------------------------------------- 错误

  @Test("404 / 451 / 429 分类")
  func errors() {
    #expect(BinanceError(status: 404, code: nil, msg: nil, url: nil).isNotFound)
    #expect(BinanceError(status: 451, code: nil, msg: nil, url: nil).isGeoBlocked)
    #expect(BinanceError(status: 429, code: nil, msg: nil, url: nil).isRateLimited)
    #expect(BinanceError(status: 418, code: nil, msg: nil, url: nil).isRateLimited)
    #expect(!BinanceError(status: 400, code: -1121, msg: "Invalid symbol", url: nil).isRateLimited)
  }
}
