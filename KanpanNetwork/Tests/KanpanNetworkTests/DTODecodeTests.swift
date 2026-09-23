import Foundation
import Testing
@testable import KanpanNetwork
import KanpanNetworkTestSupport
import KanpanCore

// 币安 REST / WS 报文的解码：数字既可以是字符串也可以是数字、坏 OHLC 在进指标之前就被拒、
// REST 与 WS 两边的交易所时钟对得上。
@Suite("币安报文解码")
struct DTODecodeTests {
  @Test("涨跌额在 REST、单品种流与全市场流中保留同一数值")
  func priceChangeSurvivesBothTransports() throws {
    let rest = try JSONDecoder().decode(Ticker24hDTO.self, from: Data(#"{"symbol":"MUUSDT","lastPrice":"1052.18","priceChange":"6.72","priceChangePercent":"0.64","highPrice":"1053.60","lowPrice":"1044.11","quoteVolume":"36730000"}"#.utf8)).ticker
    let frame = #"{"e":"24hrTicker","s":"MUUSDT","c":"1052.18","p":"6.72","P":"0.64","h":"1053.60","l":"1044.11","q":"36730000"}"#
    let single = try JSONDecoder().decode(StreamPayload.self, from: Data(frame.utf8))
    let batch = try JSONDecoder().decode(StreamPayload.self, from: Data("[\(frame)]".utf8))
    guard case .ticker(let ticker) = single, case .tickerBatch(let tickers) = batch else {
      Issue.record("行情形状不匹配"); return
    }
    #expect(rest.priceChange == 6.72)
    #expect(ticker.priceChange == rest.priceChange)
    #expect(tickers.first?.priceChange == rest.priceChange)
  }
  @Test("kline 行数字可以是字符串也可以是数字")
  func klineRowDecode() throws {
    let a = Data(#"[[1700000000000,"1.5","2.5","0.5","2.0","10.0",1700003599999,"1",1,"1","1","0"]]"#.utf8)
    let b = Data(#"[[1700000000000,1.5,2.5,0.5,2.0,10.0,1700003599999,1,1,1,1,0]]"#.utf8)
    let ra = try JSONDecoder().decode([KlineRow].self, from: a)
    let rb = try JSONDecoder().decode([KlineRow].self, from: b)
    #expect(ra[0].bar == rb[0].bar)
    #expect(ra[0].bar == Bar(openTime: 1700000000000, open: 1.5, high: 2.5, low: 0.5, close: 2.0,
                             volume: 10.0, takerBuy: 1.0))
    // 第 9 格就是主动买成交量，字符串和数字两种写法都要读到同一个值。
    #expect(ra[0].bar.takerBuy == 1.0)
    #expect(rb[0].bar.takerBuy == 1.0)
  }

  @Test("行被截断到只剩收盘时间：主动买量算缺失，不算 0")
  func klineRowWithoutTakerColumn() throws {
    let short = Data(#"[[1700000000000,"1.5","2.5","0.5","2.0","10.0",1700003599999]]"#.utf8)
    let rows = try JSONDecoder().decode([KlineRow].self, from: short)
    #expect(rows[0].bar.volume == 10.0)
    // 0 会被 CVD 读成「整根都是主动卖」，那是凭空造出来的一段下跌。
    #expect(rows[0].bar.takerBuy.isNaN)
  }

  @Test("网关给 OKX 的行在主动买量那一格是 null")
  func klineRowWithNullTakerColumn() throws {
    let nulled = Data(#"[[1700000000000,"1.5","2.5","0.5","2.0","10.0",1700003599999,"1",0,null,null,"0"]]"#.utf8)
    let rows = try JSONDecoder().decode([KlineRow].self, from: nulled)
    #expect(rows[0].bar.close == 2.0)
    #expect(rows[0].bar.takerBuy.isNaN)
  }

  @Test func invalidOHLCVIsRejectedBeforeIndicators() throws {
    let bad = Data("[[60000,\"100\",\"99\",\"90\",\"105\",\"1\",119999]]".utf8)
    #expect(throws: FeedError.self) { try JSONDecoder().decode([KlineRow].self, from: bad) }
  }

  @Test func decoderRetainsExchangeClock() throws {
    let rest = try JSONDecoder().decode(Ticker24hDTO.self, from: Data(#"{"symbol":"BTCUSDT","lastPrice":"105","priceChangePercent":"1","highPrice":"110","lowPrice":"90","quoteVolume":"1000","closeTime":2000,"lastId":30}"#.utf8)).ticker
    let ws = try JSONDecoder().decode(StreamPayload.self, from: Data(#"{"e":"24hrTicker","s":"BTCUSDT","c":"105","P":"1","h":"110","l":"90","q":"1000","C":2000,"L":30}"#.utf8))
    guard case .ticker(let ticker) = ws else { Issue.record("Expected ticker"); return }
    #expect(ticker.timeMs == rest.timeMs)
    #expect(ticker.lastTradeID == rest.lastTradeID)
    #expect(!LatestQuote.accepts(rest, after: ticker))
  }
}

// ---------------------------------------------------------------- 资金费率

@Suite("单品种资金费率")
struct PremiumIndexTests {

  @Test("premiumIndex 拿得到费率和下一次结算时刻")
  func decodesFundingSnapshot() async throws {
    let pacer = StepPacer()
    let server = FakeServer { _ in
      json("""
      {"symbol":"BTCUSDT","markPrice":"80000.00","indexPrice":"80010.00",
       "lastFundingRate":"0.00010000","nextFundingTime":1700000000000,"time":1699990000000}
      """)
    }
    let rest = BinanceREST(transport: FakeTransport(server),
                           limiter: RateLimiter(pacer: pacer, minGapMs: 0), pacer: pacer)
    let snapshot = try await rest.funding(symbol: "BTCUSDT")
    #expect(snapshot.rate == 0.0001)
    #expect(snapshot.nextFundingTimeMs == 1_700_000_000_000)
    let path = await server.hits.first?.url
    #expect(path?.path == "/fapi/v1/premiumIndex")
    #expect(path?.query == "symbol=BTCUSDT")
  }

  /// 没有资金费率那回事的品种：`nextFundingTime` 是 0，当作「没有下一次」，
  /// 费率本身照旧算数。
  @Test("结算时刻是 0 就当没有")
  func zeroNextFundingTimeBecomesNil() async throws {
    let pacer = StepPacer()
    let server = FakeServer { _ in
      json(#"{"symbol":"XUSDT","lastFundingRate":"-0.00023000","nextFundingTime":0}"#)
    }
    let rest = BinanceREST(transport: FakeTransport(server),
                           limiter: RateLimiter(pacer: pacer, minGapMs: 0), pacer: pacer)
    let snapshot = try await rest.funding(symbol: "XUSDT")
    #expect(snapshot.rate == -0.00023)
    #expect(snapshot.nextFundingTimeMs == nil)
  }

  /// 扫图换品种时垫底用的那张全市场表：不带 symbol、一行一个品种，
  /// 交割合约那种空串费率要略过，不能让整张表解码失败。
  @Test("全市场费率表按代号索引，空费率的行略过")
  func decodesWholeMarketFunding() async throws {
    let pacer = StepPacer()
    let server = FakeServer { _ in
      json("""
      [{"symbol":"BTCUSDT","lastFundingRate":"0.00010000","nextFundingTime":1700000000000},
       {"symbol":"ETHUSDT","lastFundingRate":"-0.00005000","nextFundingTime":0},
       {"symbol":"BTCUSDT_251226","lastFundingRate":"","nextFundingTime":0}]
      """)
    }
    let rest = BinanceREST(transport: FakeTransport(server),
                           limiter: RateLimiter(pacer: pacer, minGapMs: 0), pacer: pacer)
    let table = try await rest.fundingAll()
    #expect(table.count == 2)
    #expect(table["BTCUSDT"] == FundingSnapshot(rate: 0.0001, nextFundingTimeMs: 1_700_000_000_000))
    #expect(table["ETHUSDT"] == FundingSnapshot(rate: -0.00005, nextFundingTimeMs: nil))
    let path = await server.hits.first?.url
    #expect(path?.path == "/fapi/v1/premiumIndex")
    #expect(path?.query == nil)
  }

  /// 提供者那一层：整表按完整品种 key 交出去。直连问币安本家；网关上的 OKX 替身
  /// 问网关的替身整表，绝不落到币安的 `premiumIndex` 上（不混源）。
  @Test("全市场费率：直连问本家，网关问替身自己的整表，键都是完整品种 key")
  func providerFundingAllStaysOnItsOwnSource() async throws {
    let pacer = StepPacer()
    let server = FakeServer { _ in
      json(#"[{"symbol":"BTCUSDT","lastFundingRate":"0.00010000","nextFundingTime":1700000000000}]"#)
    }
    let rest = BinanceREST(transport: FakeTransport(server),
                           limiter: RateLimiter(pacer: pacer, minGapMs: 0), pacer: pacer)
    let direct = BinanceProvider(upstream: .binance, hosts: BinanceHosts(), policy: .direct, rest: rest)
    let table = try await direct.fundingAll()
    #expect(table[InstrumentID.canonical("BTCUSDT")]?.rate == 0.0001)

    let gateway = FakeServer { url in
      if url.host == "gw-a.example" { return json("{}", status: 503) }
      return json(#"{"ok":true,"data":{"source":"okx","rows":[{"symbol":"BTCUSDT","rate":0.00008,"nextFundingTime":1790179200000},{"symbol":"ETHUSDT","rate":null,"nextFundingTime":1790179200000}]}}"#)
    }
    let hosts = BinanceHosts(oiProxy: "gw-a.example", oiProxyFallbacks: ["gw-b.example:8443"])
    let substitute = BinanceProvider(upstream: .okx, hosts: hosts, policy: .gateway, rest: rest,
                                     http: FakeTransport(gateway))
    let okx = try await substitute.fundingAll()
    #expect(okx[InstrumentID.canonical("BTCUSDT")] == FundingSnapshot(rate: 0.00008, nextFundingTimeMs: 1_790_179_200_000))
    #expect(okx[InstrumentID.canonical("ETHUSDT")] == nil)
    #expect(try await substitute.funding(symbol: "BTCUSDT").rate == 0.00008)
    let asked = await gateway.hits.map(\.url)
    // 主网关 503 就换备用那台（带端口），两次都一样。
    #expect(asked.map { $0.host ?? "" } == ["gw-a.example", "gw-b.example", "gw-a.example", "gw-b.example"])
    #expect(asked.filter { $0.host == "gw-b.example" }.allSatisfy { $0.port == 8443 })
    #expect(asked.allSatisfy { $0.path == "/v1/market/funding" && $0.query == "source=okx" })
    // 替身那两次一发也没打到币安本家那台假 server 上。
    #expect(await server.hits.count == 1)
  }

  @Test("网关费率表来源对不上就整表不收")
  func gatewayFundingRejectsForeignSource() {
    let body = Data(#"{"data":{"source":"binance","rows":[{"symbol":"BTCUSDT","rate":0.0001}]}}"#.utf8)
    #expect(throws: (any Error).self) {
      try GatewayFunding.decode(body, source: "okx", venue: "binance", market: "usd_m")
    }
  }
}
