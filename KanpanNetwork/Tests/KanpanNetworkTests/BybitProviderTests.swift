import Foundation
import Testing
@testable import KanpanNetwork
import KanpanNetworkTestSupport
import KanpanCore

// Bybit v5 USDT 线性永续的行情提供者（2026-10-08）。
// 夹具来源：容器连不上交易所，REST 与行情推送的报文按 Bybit v5 官方文档的示例答复写
// （Market › Get Instruments Info / Get Tickers / Get Kline / Get Open Interest，
// WebSocket › Public › Ticker / Kline / Trade），只把代号换成 USDT 线性永续、数字截短；
// 订阅被拒那一帧的 `ret_msg` 措辞没有录到真帧，按「报错文里点了 topic 名」的形状写。

private func q(_ url: URL, _ name: String) -> String? {
  URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?.first { $0.name == name }?.value
}

@Suite("Bybit 报文翻译")
struct BybitDTOTests {
  /// 官方示例（linear）：BTCUSDT 永续；另加 USDC 永续、USDT 交割、预上线、下架各一行。
  static let instruments = #"""
  {"retCode":0,"retMsg":"OK","result":{"category":"linear","list":[
    {"symbol":"BTCUSDT","contractType":"LinearPerpetual","status":"Trading","baseCoin":"BTC","quoteCoin":"USDT",
     "launchTime":"1585526400000","deliveryTime":"0","priceScale":"2",
     "priceFilter":{"minPrice":"0.10","maxPrice":"199999.80","tickSize":"0.10"},
     "lotSizeFilter":{"maxOrderQty":"100.000","minOrderQty":"0.001","qtyStep":"0.001"},"settleCoin":"USDT"},
    {"symbol":"1000PEPEUSDT","contractType":"LinearPerpetual","status":"Trading","baseCoin":"1000PEPE","quoteCoin":"USDT",
     "launchTime":"1683100800000","priceScale":"7","priceFilter":{"tickSize":"0.0000001"},"lotSizeFilter":{"qtyStep":"100"}},
    {"symbol":"NEWUSDT","contractType":"LinearPerpetual","status":"PreLaunch","baseCoin":"NEW","quoteCoin":"USDT",
     "launchTime":"1791500000000","priceFilter":{"tickSize":"0.0001"},"lotSizeFilter":{"qtyStep":"1"}},
    {"symbol":"OLDUSDT","contractType":"LinearPerpetual","status":"Closed","baseCoin":"OLD","quoteCoin":"USDT",
     "priceFilter":{"tickSize":"0.001"},"lotSizeFilter":{"qtyStep":"0.1"}},
    {"symbol":"BTCPERP","contractType":"LinearPerpetual","status":"Trading","baseCoin":"BTC","quoteCoin":"USDC",
     "priceFilter":{"tickSize":"0.5"},"lotSizeFilter":{"qtyStep":"0.001"}},
    {"symbol":"BTCUSDT-26DEC25","contractType":"LinearFutures","status":"Trading","baseCoin":"BTC","quoteCoin":"USDT",
     "priceFilter":{"tickSize":"0.5"},"lotSizeFilter":{"qtyStep":"0.001"}},
    {"contractType":"LinearPerpetual"}
  ],"nextPageCursor":""},"retExtInfo":{},"time":1707186451514}
  """#

  @Test("品种表：只收 USDT 线性永续；键是 bybit/usd_m/…；精度按步长字面数；状态四档；坏行只丢那一行")
  func instrumentsFilter() throws {
    let page = try BybitDTO.result(BybitDTO.Instruments.self, Data(Self.instruments.utf8), what: "品种表").result
    #expect(page.list.count == 6)
    #expect(page.nextPageCursor == "")
    let listed = page.list.filter(\.isListed)
    #expect(listed.map(\.symbol) == ["BTCUSDT", "1000PEPEUSDT", "NEWUSDT", "OLDUSDT"])
    let btc = try #require(listed[0].symbolInfo)
    #expect(btc.symbol == "bybit/usd_m/BTCUSDT" && btc.base == "BTC" && btc.quote == "USDT")
    #expect(btc.tickSize == 0.1 && btc.pricePrecision == 1 && btc.quantityPrecision == 3)
    #expect(btc.underlyingType == "COIN" && btc.contractType == "PERPETUAL")
    #expect(btc.status == .tradable && btc.onboardDate == 1_585_526_400_000)
    let pepe = try #require(listed[1].symbolInfo)
    #expect(pepe.base == "1000PEPE" && pepe.pricePrecision == 7 && pepe.quantityPrecision == 0)
    #expect(listed[2].symbolInfo?.status == .pending)
    #expect(listed[3].symbolInfo?.status == .delisted)
  }

  @Test("K 线页：降序 → 升序、字符串 → 数；坏行丢掉")
  func klinesAscending() throws {
    let body = Data(#"""
    {"retCode":0,"retMsg":"OK","result":{"symbol":"BTCUSDT","category":"linear","list":[
      ["1670608800000","17071","17073","17027","17055.5","268611","15.74462667"],
      ["1670605200000","17071.5","17071.5","17061","17071","4177","0.24469757"],
      ["1670601600000","0","1","1","1","1","1"]]},"retExtInfo":{},"time":1672025956592}
    """#.utf8)
    let bars = try BybitDTO.bars(body)
    #expect(bars.map(\.openTime) == [1_670_605_200_000, 1_670_608_800_000])
    #expect(bars[1].close == 17055.5 && bars[1].volume == 268611 && bars[1].takerBuy.isNaN)
  }

  @Test("retCode 不是 0：10006 按限流报，其它按坏答复报，带 retMsg")
  func retCodes() {
    #expect(throws: UpstreamError.self) {
      _ = try BybitDTO.bars(Data(#"{"retCode":10006,"retMsg":"Too many visits!","result":{},"time":1}"#.utf8))
    }
    do {
      _ = try BybitDTO.bars(Data(#"{"retCode":10001,"retMsg":"params error: symbol invalid","result":{}}"#.utf8))
      Issue.record("应该报错")
    } catch let error as FeedError {
      #expect(error == .badResponse("Bybit K 线：params error: symbol invalid"))
    } catch { Issue.record("报错类型不对：\(error)") }
    #expect(BybitDTO.errorMessage(Data(#"{"retCode":10001,"retMsg":"bad"}"#.utf8)) == "bad")
  }

  @Test("24h 行情一行：涨跌幅是小数要 ×100，额是 turnover24h，24h 开盘取 prevPrice24h；资金费率与下次结算同一行")
  func tickerRow() throws {
    let body = Data(#"""
    {"retCode":0,"retMsg":"OK","result":{"category":"linear","list":[
      {"symbol":"BTCUSDT","lastPrice":"16597.00","indexPrice":"16598.54","markPrice":"16596.00","prevPrice24h":"16464.50",
       "price24hPcnt":"0.008047","highPrice24h":"30912.50","lowPrice24h":"15700.00","prevPrice1h":"16595.50",
       "openInterest":"373504107","openInterestValue":"22505.67","turnover24h":"2352.94950046","volume24h":"49337318",
       "fundingRate":"-0.001034","nextFundingTime":"1672387200000","predictedDeliveryPrice":"","basisRate":"",
       "deliveryFeeRate":"","deliveryTime":"0","ask1Size":"1","bid1Price":"16596.00","ask1Price":"16597.50","bid1Size":"1"},
      {"symbol":"BTCPERP","lastPrice":"1","fundingRate":"0.0001","nextFundingTime":"1"},
      {"symbol":"ETHUSDT","lastPrice":"","fundingRate":"","nextFundingTime":""}]},"retExtInfo":{},"time":1672376496682}
    """#.utf8)
    let (table, time) = try BybitDTO.result(BybitDTO.Tickers.self, body, what: "行情")
    #expect(time == 1_672_376_496_682)
    #expect(table.list.filter(\.isListed).map(\.symbol) == ["BTCUSDT", "ETHUSDT"])
    let t = try #require(table.list[0].ticker(timeMs: time))
    #expect(t.symbol == "bybit/usd_m/BTCUSDT" && t.last == 16597)
    #expect(abs(t.changePercent - 0.8047) < 1e-9)
    #expect(t.quoteVolume == 2352.94950046 && t.markPrice == 16596 && t.open24h == 16464.5)
    #expect(abs((t.priceChange ?? 0) - 132.5) < 1e-9 && t.high == 30912.5 && t.low == 15700)
    #expect(table.list[0].funding == FundingSnapshot(rate: -0.001034, nextFundingTimeMs: 1_672_387_200_000))
    #expect(table.list[2].ticker(timeMs: nil) == nil && table.list[2].funding == nil)
  }

  @Test("持仓量历史一页：降序 → 升序，值是币的个数")
  func openInterestPage() throws {
    let body = Data(#"""
    {"retCode":0,"retMsg":"OK","result":{"symbol":"BTCUSDT","category":"linear","list":[
      {"openInterest":"461134384.00000000","timestamp":"1669571400000"},
      {"openInterest":"461134292.00000000","timestamp":"1669571100000"}],"nextPageCursor":""},"retExtInfo":{},"time":1672053548579}
    """#.utf8)
    #expect(try BybitDTO.openInterest(body) == [OIPoint(time: 1_669_571_100_000, value: 461_134_292),
                                                OIPoint(time: 1_669_571_400_000, value: 461_134_384)])
  }

  @Test("代号与周期：键 ↔ 原生代号只换前缀；13 档原生、1y 没有；持仓量周期按币安口径映射，没有的取更细一档")
  func symbolsAndIntervals() {
    #expect(BybitVenue.key("BTCUSDT") == "bybit/usd_m/BTCUSDT")
    #expect(BybitVenue.symbol("bybit/usd_m/1000PEPEUSDT") == "1000PEPEUSDT")
    #expect(BybitVenue.isListedSymbol("1000PEPEUSDT") && !BybitVenue.isListedSymbol("BTCPERP")
            && !BybitVenue.isListedSymbol("BTCUSDT-26DEC25") && !BybitVenue.isListedSymbol("USDT"))
    let wire = Interval.allCases.map { BybitVenue.interval($0) }
    #expect(wire == ["1", "3", "5", "15", "30", "60", "120", "240", "360", "720", "D", "W", "M", nil])
    for iv in Interval.allCases where iv != .y1 { #expect(BybitVenue.interval(wire: BybitVenue.interval(iv)!) == iv) }
    #expect(BybitVenue.interval(wire: "1h") == nil)
    #expect(["5m", "15m", "30m", "1h", "2h", "4h", "6h", "12h", "1d", "1w"].map(BybitVenue.oiInterval) ==
            ["5min", "15min", "30min", "1h", "1h", "4h", "1h", "4h", "1d", nil])
    let caps = BybitProvider.capabilities
    #expect(caps.supports(.y1) && caps.source(for: .y1) == .mo1 && !caps.isAggregated(.h6))
    #expect(Interval.allCases.allSatisfy(caps.hasLiveKline))
    #expect(caps.venue == "bybit" && caps.market == "usd_m" && caps.openInterestSource == "bybit")
    #expect(caps.hasMarkPrice && caps.hasFunding && caps.hasOpenInterestHistory && !caps.hasOpenInterestArchive)
    #expect(!caps.hasMicrostructure && !caps.hasDerivativeMetrics && caps.hasBulkTickers && caps.hasOrderFlow)
    #expect(caps.maxKlines == 1000 && caps.initialKlines == 300 && caps.quoteAssets == ["USDT"])
  }
}

@Suite("Bybit REST 翻页与线路")
struct BybitRESTTests {
  /// 线上的「现在」：2026-09-22T23:19:46Z。
  static let now = Date(timeIntervalSince1970: 1_790_119_186)
  static let nowMs: Int64 = 1_790_119_186_000
  static let hour: Int64 = 3_600_000

  /// 按请求的 start / end / limit 造一页 1h K 线（开盘对齐整点、新的在前、最多 limit 根、不越过现在）——和线上一样。
  static func klinePage(_ url: URL) -> HTTPReply {
    guard q(url, "interval") == "60", q(url, "category") == "linear",
          let limit = q(url, "limit").flatMap({ Int($0) }), limit <= 1000 else {
      return json(#"{"retCode":10001,"retMsg":"params error"}"#)
    }
    let end = min(q(url, "end").flatMap { Int64($0) } ?? nowMs, nowMs)
    let start = q(url, "start").flatMap { Int64($0) } ?? 0
    var opens: [Int64] = []
    var t = end - ((end % hour) + hour) % hour
    while t >= start, opens.count < limit { opens.append(t); t -= hour }
    let rows = opens.map { #"["\#($0)","1","2","1","2","1","2"]"# }
    return json(#"{"retCode":0,"retMsg":"OK","result":{"symbol":"BTCUSDT","category":"linear","list":[\#(rows.joined(separator: ","))]},"time":\#(nowMs)}"#)
  }

  private func provider(_ server: FakeServer, policy: MarketRoutePolicy = .direct,
                        limiter: VenueRateLimiter = VenueRateLimiter(perSecond: 1_000_000, pacer: FastPacer())) -> BybitProvider {
    BybitProvider(policy: policy, gateways: ["gw1.example", "gw2.example"], transport: FakeTransport(server),
                  limiter: limiter, clock: { Self.now })
  }

  @Test("首屏一发：只带 category / symbol / interval / limit，不带起止；打 api.bybit.com")
  func firstScreenOneRequest() async throws {
    let server = FakeServer { Self.klinePage($0) }
    let bars = try await provider(server).klines(symbol: "bybit/usd_m/BTCUSDT", interval: .h1, limit: 300,
                                                 startTime: nil, endTime: nil)
    #expect(bars.count == 300 && bars.last?.openTime == 1_790_118_000_000)
    let urls = await server.urls()
    #expect(urls.count == 1)
    #expect(urls[0].absoluteString == "https://api.bybit.com/v5/market/kline?category=linear&symbol=BTCUSDT&interval=60&limit=300")
  }

  @Test("网关线路：打 /v1/market/raw/v5/… 带 source=bybit 排第一；主网关 5xx 换备用")
  func gatewayFallback() async throws {
    let server = FakeServer { url in url.host == "gw1.example" ? json("{}", status: 502) : Self.klinePage(url) }
    _ = try await provider(server, policy: .gateway).klines(symbol: "bybit/usd_m/ETHUSDT", interval: .h1, limit: 5,
                                                            startTime: nil, endTime: nil)
    let urls = await server.urls()
    #expect(urls.map(\.host) == ["gw1.example", "gw2.example"])
    #expect(urls[1].path == "/v1/market/raw/v5/market/kline")
    #expect(urls[1].query == "source=bybit&category=linear&symbol=ETHUSDT&interval=60&limit=5")
  }

  @Test("向前翻两页：两个 1000 根的窗口都带起止、并行，拼回来升序、连续、不重不漏、都早于第一根")
  func historyPages() async throws {
    let server = FakeServer { Self.klinePage($0) }
    let firstOpen: Int64 = 1_790_118_000_000 - 299 * Self.hour
    let bars = try await provider(server).history(symbol: "bybit/usd_m/BTCUSDT", interval: .h1, pages: 2,
                                                  before: firstOpen)
    #expect(bars.count == 2000)
    #expect(zip(bars, bars.dropFirst()).allSatisfy { $1.openTime - $0.openTime == Self.hour })
    #expect(bars.last?.openTime == firstOpen - Self.hour)
    let urls = await server.urls()
    #expect(urls.count == 2 && urls.allSatisfy { q($0, "start") != nil && q($0, "end") != nil && q($0, "limit") == "1000" })
  }

  @Test("补缺：从断点往后，终点在将来的窗口不带 end（不然网关会把最新一页当历史缓存）")
  func tailOmitsFutureEnd() async throws {
    let server = FakeServer { Self.klinePage($0) }
    let from: Int64 = 1_790_118_000_000 - 5 * Self.hour
    let bars = try await provider(server).contiguousTail(symbol: "bybit/usd_m/BTCUSDT", interval: .h1, from: from)
    #expect(bars.map(\.openTime) == (0...5).map { from + Int64($0) * Self.hour })
    let urls = await server.urls()
    #expect(urls.count == 1 && q(urls[0], "start") == String(from) && q(urls[0], "end") == nil)
    // 1y 由 1M 聚：按月线取。
    let monthly = FakeServer { url in
      #expect(q(url, "interval") == "M")
      return json(#"{"retCode":0,"retMsg":"OK","result":{"list":[]}}"#)
    }
    _ = try await provider(monthly).klines(symbol: "bybit/usd_m/BTCUSDT", interval: .y1, limit: 10,
                                           startTime: nil, endTime: nil)
    #expect(await monthly.urls().count == 1)
  }

  @Test("品种表按 nextPageCursor 翻页：游标原样带回去（不二次编码），空游标停")
  func instrumentsPaging() async throws {
    let page2 = BybitDTOTests.instruments
    let server = FakeServer { url in
      if q(url, "cursor") == nil {
        return json(#"{"retCode":0,"retMsg":"OK","result":{"category":"linear","list":[{"symbol":"ETHUSDT","contractType":"LinearPerpetual","status":"Trading","baseCoin":"ETH","quoteCoin":"USDT","priceFilter":{"tickSize":"0.01"},"lotSizeFilter":{"qtyStep":"0.01"}}],"nextPageCursor":"first%3D1%26last%3D2"},"time":1}"#)
      }
      return json(page2)
    }
    let list = try await provider(server).instruments()
    #expect(list.map(\.symbol) == ["bybit/usd_m/1000PEPEUSDT", "bybit/usd_m/BTCUSDT", "bybit/usd_m/ETHUSDT",
                                   "bybit/usd_m/NEWUSDT", "bybit/usd_m/OLDUSDT"])
    let urls = await server.urls()
    #expect(urls.count == 2)
    #expect(urls.allSatisfy { $0.path == "/v5/market/instruments-info" && q($0, "category") == "linear" && q($0, "limit") == "1000" })
    #expect(q(urls[1], "cursor") == "first=1&last=2")
  }

  @Test("全市场行情与费率：一次整表，只留 USDT 永续，键是完整品种 key；单品种带 symbol")
  func bulkTickersAndFunding() async throws {
    let body = #"""
    {"retCode":0,"retMsg":"OK","result":{"category":"linear","list":[
      {"symbol":"BTCUSDT","lastPrice":"100","prevPrice24h":"80","price24hPcnt":"0.25","highPrice24h":"110","lowPrice24h":"70",
       "turnover24h":"5000","markPrice":"100.5","fundingRate":"0.0001","nextFundingTime":"1790121600000"},
      {"symbol":"BTCPERP","lastPrice":"100","fundingRate":"0.0002","nextFundingTime":"1790121600000"}]},"time":1790119186000}
    """#
    let server = FakeServer { _ in json(body) }
    let p = provider(server)
    let tickers = try await p.tickers24h(timeout: 5)
    #expect(tickers.map(\.symbol) == ["bybit/usd_m/BTCUSDT"] && tickers[0].timeMs == 1_790_119_186_000)
    #expect(tickers[0].changePercent == 25 && tickers[0].quoteVolume == 5000)
    let all = try await p.fundingAll()
    #expect(all == ["bybit/usd_m/BTCUSDT": FundingSnapshot(rate: 0.0001, nextFundingTimeMs: 1_790_121_600_000)])
    let one = try await p.funding(symbol: "bybit/usd_m/BTCUSDT")
    #expect(one.rate == 0.0001)
    let t = try await p.ticker24h(symbol: "bybit/usd_m/BTCUSDT", timeout: 5)
    #expect(t.last == 100 && t.markPrice == 100.5)
    let urls = await server.urls()
    #expect(urls.count == 4)
    #expect(q(urls[0], "symbol") == nil && q(urls[1], "symbol") == nil)
    #expect(q(urls[2], "symbol") == "BTCUSDT" && q(urls[3], "symbol") == "BTCUSDT")
  }

  @Test("持仓量历史：要 500 条按 200 一页往回翻（endTime 退到上一页最早一条之前），2h 用 1h，结果升序")
  func openInterestPaging() async throws {
    let step: Int64 = 3_600_000
    let server = FakeServer { url in
      let limit = Int(q(url, "limit") ?? "") ?? 0
      let end = q(url, "endTime").flatMap { Int64($0) } ?? Self.nowMs
      var t = end - end % step
      var rows: [String] = []
      while rows.count < limit { rows.append(#"{"openInterest":"\#(t / step)","timestamp":"\#(t)"}"#); t -= step }
      return json(#"{"retCode":0,"retMsg":"OK","result":{"symbol":"BTCUSDT","category":"linear","list":[\#(rows.joined(separator: ","))],"nextPageCursor":"x"},"time":1}"#)
    }
    let points = try await provider(server).openInterestHist(symbol: "bybit/usd_m/BTCUSDT", period: "2h", limit: 500,
                                                             startTime: nil, endTime: nil)
    #expect(points.count == 500)
    #expect(zip(points, points.dropFirst()).allSatisfy { $1.time - $0.time == step })
    let urls = await server.urls()
    #expect(urls.map { q($0, "limit") } == ["200", "200", "100"])
    #expect(urls.allSatisfy { $0.path == "/v5/market/open-interest" && q($0, "intervalTime") == "1h" })
    #expect(q(urls[0], "endTime") == nil && q(urls[1], "endTime") == String(points[300].time - 1))
    await #expect(throws: FeedError.self) {
      _ = try await provider(server).openInterestHist(symbol: "bybit/usd_m/BTCUSDT", period: "1w", limit: 5,
                                                      startTime: nil, endTime: nil)
    }
  }

  @Test("HTTP 200 + retCode 10006：按限流报，并罚这一家的限速器")
  func retCodeRateLimitPenalizes() async throws {
    let pacer = StepPacer()
    let limiter = VenueRateLimiter(perSecond: 10, pacer: pacer)
    let server = FakeServer { _ in json(#"{"retCode":10006,"retMsg":"Too many visits!"}"#) }
    await #expect(throws: UpstreamError.self) {
      _ = try await provider(server, limiter: limiter).tickers24h(timeout: 5)
    }
    try await limiter.acquire()
    #expect(await pacer.sleepLog().contains(1000))
  }

  @Test("行情、订单流共用这一家的一把限速器；出厂的提供者就用它")
  func sharedLimiter() {
    let p = BybitProvider(route: MarketRoute(policy: .direct, endpoints: MarketEndpoints(gateways: ["gw.example"])))
    #expect(p.rest.limiter === BybitVenue.limiter)
    #expect(BybitVenue.perSecond == 20)
    #expect(p.orderFlowCatalog.route == p.endpoints.route)
  }

  @Test("推送地址：直连 stream.bybit.com 主、stream.bytick.com 备；网关是中继 ?category=linear")
  func streamURLs() {
    let server = FakeServer { _ in json("{}") }
    #expect(provider(server).streamURLs.map(\.absoluteString) ==
            ["wss://stream.bybit.com/v5/public/linear", "wss://stream.bytick.com/v5/public/linear"])
    #expect(provider(server, policy: .gateway).streamURLs.map(\.absoluteString) ==
            ["wss://gw1.example/v1/market/ws/bybit?category=linear", "wss://gw2.example/v1/market/ws/bybit?category=linear"])
  }
}

@Suite("Bybit 推送", .timeLimit(.minutes(1)))
struct BybitWireTests {
  private struct Control: Decodable { var op: String; var args: [String]? }
  /// 发出去的订阅 / 退订（保活的 ping 不算）。
  private func controls(_ s: GateSocket) async -> [Control] {
    await s.sent.compactMap { try? JSONDecoder().decode(Control.self, from: Data($0.utf8)) }.filter { $0.op != "ping" }
  }

  static let snapshot = #"{"topic":"tickers.BTCUSDT","type":"snapshot","data":{"symbol":"BTCUSDT","tickDirection":"PlusTick","price24hPcnt":"0.017103","lastPrice":"17216.00","prevPrice24h":"16926.50","highPrice24h":"17281.50","lowPrice24h":"16915.00","prevPrice1h":"17238.00","markPrice":"17217.33","indexPrice":"17227.36","openInterest":"68744.761","openInterestValue":"1183601235.91","turnover24h":"1570383121.943499","volume24h":"91705.276","nextFundingTime":"1673280000000","fundingRate":"-0.000212","bid1Price":"17215.50","bid1Size":"84.489","ask1Price":"17216.00","ask1Size":"83.020"},"cs":24987956059,"ts":1673272861686}"#
  static let delta = #"{"topic":"tickers.BTCUSDT","type":"delta","data":{"symbol":"BTCUSDT","tickDirection":"MinusTick","lastPrice":"17208.00","turnover24h":"1570383124.0","volume24h":"91705.5","bid1Price":"17207.50"},"cs":24987956060,"ts":1673272861786}"#
  static let markDelta = #"{"topic":"tickers.BTCUSDT","type":"delta","data":{"symbol":"BTCUSDT","markPrice":"17210.10","indexPrice":"17220.00","fundingRate":""},"cs":24987956061,"ts":1673272861886}"#

  @Test("订阅：行情与标记价是同一个 tickers 频道；K 线按 Bybit 周期名；1y 退到逐笔；盘口与主动成交不订")
  func subsMapping() throws {
    let wire = BybitWire()
    let s = "bybit/usd_m/BTCUSDT"
    #expect(wire.subs([.ticker(symbol: s), .markPrice(symbol: s), .kline(symbol: s, interval: .h1),
                       .kline(symbol: s, interval: .d1), .trade(symbol: s), .aggTrade(symbol: s), .depth(symbol: s)])
            == ["tickers.BTCUSDT", "kline.60.BTCUSDT", "kline.D.BTCUSDT", "publicTrade.BTCUSDT"])
    #expect(wire.subs([.kline(symbol: s, interval: .y1)]) == ["publicTrade.BTCUSDT"])
    let many = Set((0..<23).map { "tickers.C\($0)USDT" })
    #expect(wire.nextBatch(many).count == 10 && wire.nextBatch(many) == Array(many.sorted().prefix(10)))
    #expect(try wire.control(.subscribe, ["kline.1.BTCUSDT", "tickers.BTCUSDT"])
            == #"{"args":["kline.1.BTCUSDT","tickers.BTCUSDT"],"op":"subscribe"}"#)
    #expect(wire.keepAlive == VenueKeepAlive(text: #"{"op":"ping"}"#, everyMs: 20_000))
    #expect(wire.controlGapMs >= 100)
  }

  @Test("tickers：快照出行情 + 标记价；delta 只带变了的字段，按品种合并到快照上再出；只动标记价的 delta 只出标记价")
  func tickerDeltaMerge() throws {
    let wire = BybitWire()
    let first = wire.decode(Self.snapshot)
    #expect(first.confirmed == ["tickers.BTCUSDT"] && first.error == nil)
    #expect(first.payloads.count == 2)
    guard case .ticker(let t0) = first.payloads[0], case .markPrice(let sym, let mark, let tick) = first.payloads[1] else {
      Issue.record("快照应该出行情 + 标记价"); return
    }
    #expect(t0.symbol == "bybit/usd_m/BTCUSDT" && t0.last == 17216 && abs(t0.changePercent - 1.7103) < 1e-9)
    #expect(t0.quoteVolume == 1570383121.943499 && t0.timeMs == 1_673_272_861_686)
    #expect(sym == "bybit/usd_m/BTCUSDT" && mark == 17217.33)
    #expect(tick.fundingRate == -0.000212 && tick.nextFundingTimeMs == 1_673_280_000_000 && tick.indexPrice == 17227.36)

    let second = wire.decode(Self.delta)
    #expect(second.payloads.count == 1)
    guard case .ticker(let t1) = second.payloads.first else { Issue.record("delta 应该出一条行情"); return }
    // 变了的字段用新的，没带的沿用快照。
    #expect(t1.last == 17208 && t1.quoteVolume == 1570383124 && t1.high == 17281.5 && t1.open24h == 16926.5)
    #expect(t1.markPrice == 17217.33 && t1.timeMs == 1_673_272_861_786)

    let third = wire.decode(Self.markDelta)
    #expect(third.payloads.count == 1)
    guard case .markPrice(_, let mark2, let tick2) = third.payloads.first else { Issue.record("应该只出标记价"); return }
    // 空串不覆盖旧值：费率还是快照里那个。
    #expect(mark2 == 17210.1 && tick2.fundingRate == -0.000212 && tick2.indexPrice == 17220)

    // 另一条连接（另一个 wire）的合并簿是分开的：没有快照的 delta 拼不出现价以外的东西，但现价够出一条行情。
    let lone = BybitWire().decode(Self.delta)
    guard case .ticker(let t2) = lone.payloads.first else { Issue.record("有现价就出"); return }
    #expect(t2.high.isNaN && t2.open24h == nil)
  }

  @Test("kline 与 publicTrade：K 线带 confirm 与周期；成交按时刻升序，坏价量整帧丢掉")
  func klineAndTrades() throws {
    let wire = BybitWire()
    let kline = wire.decode(#"{"topic":"kline.5.BTCUSDT","data":[{"start":1672324800000,"end":1672325099999,"interval":"5","open":"16649.5","close":"16677","high":"16677","low":"16608","volume":"2.081","turnover":"34666.4005","confirm":false,"timestamp":1672324988882}],"ts":1672324988882,"type":"snapshot"}"#)
    #expect(kline.confirmed == ["kline.5.BTCUSDT"])
    guard case .kline(let k) = kline.payloads.first else { Issue.record("应该是一根 K 线"); return }
    #expect(k.symbol == "bybit/usd_m/BTCUSDT" && k.interval == "5m" && k.openTime == 1_672_324_800_000 && !k.closed)
    #expect(k.bar.close == 16677 && k.bar.volume == 2.081 && k.eventTime == 1_672_324_988_882)
    let closed = wire.decode(#"{"topic":"kline.D.BTCUSDT","data":[{"start":1672272000000,"end":1672358399999,"interval":"D","open":"1","close":"2","high":"2","low":"1","volume":"3","turnover":"4","confirm":true,"timestamp":1672358399999}],"ts":1672358399999,"type":"snapshot"}"#)
    guard case .kline(let d) = closed.payloads.first else { Issue.record("日线"); return }
    #expect(d.interval == "1d" && d.closed)

    let trades = wire.decode(#"{"topic":"publicTrade.BTCUSDT","type":"snapshot","ts":1672304486868,"data":[{"T":1672304486866,"s":"BTCUSDT","S":"Sell","v":"0.5","p":"16578.00","L":"MinusTick","i":"b","BT":false},{"T":1672304486865,"s":"BTCUSDT","S":"Buy","v":"0.001","p":"16578.50","L":"PlusTick","i":"20f43950-d8dd-5b31-9112-a178eb6023af","BT":false}]}"#)
    #expect(trades.confirmed == ["publicTrade.BTCUSDT"])
    let events = trades.payloads.compactMap { p -> TradeEvent? in if case .trade(let t) = p { t } else { nil } }
    #expect(events.map(\.timeMs) == [1_672_304_486_865, 1_672_304_486_866])
    #expect(events[0].price == 16578.5 && events[0].qty == 0.001 && events[0].symbol == "bybit/usd_m/BTCUSDT"
            && events[0].tradeID == nil)
    let bad = wire.decode(#"{"topic":"publicTrade.BTCUSDT","type":"snapshot","ts":1,"data":[{"T":1,"s":"BTCUSDT","S":"Buy","v":"1","p":"1"},{"T":2,"s":"BTCUSDT","S":"Buy","v":"1","p":"nan"}]}"#)
    #expect(bad.payloads.isEmpty)
  }

  @Test("控制应答：pong 与订阅成功不算数据；被拒且点了 topic 名的只记那几个；没点名的不指认；已经订过不算错")
  func controlFrames() {
    let wire = BybitWire()
    for text in [
      #"{"success":true,"ret_msg":"pong","conn_id":"0970e817-426e-429a-a679-ff7f55e0b16a","op":"ping"}"#,
      #"{"success":true,"ret_msg":"","conn_id":"db2937jvnhjo7n76nht0-ce4a","req_id":"","op":"subscribe"}"#,
      #"{"op":"pong","args":["1672304486000"],"conn_id":"x"}"#,
      #"{"topic":"allLiquidation.BTCUSDT","type":"snapshot","ts":1,"data":[]}"#,
      "not json",
    ] {
      let f = wire.decode(text)
      #expect(f.payloads.isEmpty && f.confirmed.isEmpty && f.error == nil, "\(text)")
    }
    let named = wire.decode(#"{"success":false,"ret_msg":"Invalid symbol :[tickers.NOPEUSDT]","conn_id":"x","req_id":"","op":"subscribe"}"#)
    #expect(named.error == "Invalid symbol :[tickers.NOPEUSDT]" && named.rejected == ["tickers.NOPEUSDT"])
    let unnamed = wire.decode(#"{"success":false,"ret_msg":"args size >10","conn_id":"x","op":"subscribe"}"#)
    #expect(unnamed.error == "args size >10" && unnamed.rejected == nil)
    let again = wire.decode(#"{"success":false,"ret_msg":"error:already subscribed,topic:kline.1.BTCUSDT","conn_id":"x","op":"subscribe"}"#)
    #expect(again.error == nil && again.confirmed == ["kline.1.BTCUSDT"])
  }

  @Test("一条连接多订阅：一帧最多 10 个 args；切品种只退订 / 订阅不重连；按点发 ping；行情帧翻成统一报文")
  func streamBatchesAndSwitches() async throws {
    let bench = GateSocketBench()
    let url = URL(string: "wss://stream.bybit.com/v5/public/linear")!
    // 保活 20 秒 × 0.0001 = 真实 2ms。
    let ws = VenueStream(wire: BybitWire(), urls: [url], factory: bench, pacer: FastPacer(scale: 0.0001),
                         silenceMs: 1e12, transportSilenceMs: 1e12)
    let symbols = ["AUSDT", "BUSDT", "CUSDT", "DUSDT"].map { "bybit/usd_m/\($0)" }
    let stream = await ws.start(topics: symbols.flatMap {
      [StreamTopic.ticker(symbol: $0), .markPrice(symbol: $0), .kline(symbol: $0, interval: .m1), .trade(symbol: $0)]
    })
    #expect(await waitUntil(5) { await bench.socket(1) != nil })
    let socket = try #require(await bench.socket(1))
    #expect(await waitUntil(5) { await self.controls(socket).count == 2 })
    let first = await controls(socket)
    #expect(first.map { $0.args?.count ?? 0 } == [10, 2] && first.allSatisfy { $0.op == "subscribe" })
    #expect(Set(first.flatMap { $0.args ?? [] }).count == 12)
    #expect(await waitUntil(5) { await socket.sent.contains(#"{"op":"ping"}"#) })

    await socket.push(.text(Self.snapshot.replacingOccurrences(of: "BTCUSDT", with: "AUSDT")))
    var got: Ticker?
    for await event in stream { if case .payload(.ticker(let t)) = event { got = t; break } }
    #expect(got?.symbol == "bybit/usd_m/AUSDT" && got?.last == 17216)

    await ws.replace(topics: [.ticker(symbol: symbols[0]), .ticker(symbol: "bybit/usd_m/EUSDT")])
    #expect(await waitUntil(5) { await self.controls(socket).count >= 4 })
    let tail = Array(await controls(socket).dropFirst(2))
    #expect(tail[0].op == "unsubscribe" && tail[0].args?.count == 10)
    #expect(await waitUntil(5) { await self.controls(socket).contains { $0.op == "subscribe" && $0.args == ["tickers.EUSDT"] } })
    #expect(await bench.connects == 1)
    await ws.stop()
  }
}

@Suite("Bybit 订单流走同一份地址与解码")
struct BybitOrderFlowVenueTests {
  @Test("订单流适配器：中继地址、保活、控制帧都来自 BybitVenue / BybitWire；解帧走 BybitDTO")
  func adapterUsesVenue() {
    let book = OrderFlowAdapterTests.bybitLinear
    let a = BybitBooksAdapter(category: .linear, books: [book], gateways: ["gw.example"])
    #expect(a.streamURLs == BybitVenue.relayStreams(hosts: ["gw.example"], category: "linear"))
    #expect(a.keepAlive?.text == BybitVenue.pingText && a.keepAlive?.everyMs == BybitVenue.pingEveryMs)
    #expect(BybitBooksAdapter.message("subscribe", ["publicTrade.BTCUSDT"]) == (try? BybitWire.control("subscribe", ["publicTrade.BTCUSDT"])))
    let frame = OrderFlowAdapterTests.bybitSpotDelta
    #expect(!a.decode(frame).isEmpty)
    #expect(a.decode(frame) == BybitDTO.orderFlow(frame, books: ["BTCUSDT": book], levels: 1000))
    #expect(OrderFlowExchange.bybit.key == BybitVenue.id && OrderFlowExchange.bybit.displayName == BybitVenue.displayName)
  }
}
