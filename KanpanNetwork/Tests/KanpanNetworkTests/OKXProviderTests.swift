import Foundation
import Testing
@testable import KanpanNetwork
import KanpanNetworkTestSupport
import KanpanCore

// OKX USDT 线性永续（2026-10-08 起是独立的一家行情交易所）。
//
// 夹具来源：容器连不上 OKX，录不了真帧。报文按 OKX 官方 API v5 文档（2026-09 现行版
// Public Data › Get instruments / Get funding rate、Market Data › Get tickers / Get candlesticks、
// WebSocket › tickers / candle / trades / mark-price / funding-rate 各节的示例）手写，
// 数值形状（字符串数值、毫秒字符串、K 线九列、新的在前）与服务端 `venues/okx/` 测试里的线上实录一致。

private enum Fixture {
  /// 2026-09-22 23:19:46 UTC。
  static let now = Date(timeIntervalSince1970: 1_790_119_186)
  static let nowMs: Int64 = 1_790_119_186_000
  static let hour: Int64 = 3_600_000
  /// 当前这一小时的开盘（`now` 向下取整）。
  static let currentHour: Int64 = 1_790_118_000_000

  static func query(_ url: URL, _ name: String) -> String? {
    URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?.first { $0.name == name }?.value
  }

  /// 按请求造一页 1H K 线：不带 `after` 给最新的 `limit` 根；带 `after` 给开盘早于它的 `limit` 根。
  /// 新的在前（和线上一样）；`candles` 只覆盖最近 1440 根，`history-candles` 一页最多 100 根。
  /// 最早一根是 `listedAt`（这只品种上线的那一小时）。
  static func candlePage(_ url: URL, listedAt: Int64 = currentHour - 5000 * hour) -> HTTPReply {
    let history = url.path.hasSuffix("history-candles")
    let cap = history ? 100 : 300
    guard let limit = query(url, "limit").flatMap(Int.init), limit <= cap, query(url, "bar") == "1H" else {
      return json(#"{"code":"51000","msg":"Parameter limit error","data":[]}"#, status: 400)
    }
    var newest = currentHour
    if let after = query(url, "after").flatMap({ Int64($0) }) {
      newest = (after - 1) / hour * hour
      if after % hour == 0 { newest = after - hour }
    }
    let floor = history ? listedAt : max(listedAt, currentHour - 1439 * hour)
    var rows: [String] = []
    var t = newest
    while t >= floor, rows.count < limit {
      let confirm = t == currentHour ? "0" : "1"
      rows.append(#"["\#(t)","1","2","0.5","1.5","100","1","1.5","\#(confirm)"]"#)
      t -= hour
    }
    return json(#"{"code":"0","msg":"","data":[\#(rows.joined(separator: ","))]}"#)
  }
}

@Suite("OKX 代号与周期")
struct OKXVenueTests {
  @Test("键 ↔ instId：BTCUSDT ↔ BTC-USDT-SWAP；不是 USDT 线性永续的不收")
  func codes() {
    #expect(OKXVenue.instID("okx/usd_m/BTCUSDT") == "BTC-USDT-SWAP")
    #expect(OKXVenue.instID("okx/usd_m/1INCHUSDT") == "1INCH-USDT-SWAP")
    #expect(OKXVenue.key(instID: "BTC-USDT-SWAP") == "okx/usd_m/BTCUSDT")
    #expect(OKXVenue.key(instID: "BTC-USD-SWAP") == nil)
    #expect(OKXVenue.key(instID: "BTC-USDT") == nil)
    #expect(OKXVenue.key(instID: "BTC-USDT-260925") == nil)
    #expect(OKXVenue.key(instID: "-USDT-SWAP") == nil)
  }

  @Test("周期：日以上用 UTC 对齐的 …utc；没有 1y（由 1M 聚）；频道名 candle<bar> 能译回来")
  func intervals() {
    #expect(OKXVenue.bar(.h1) == "1H" && OKXVenue.bar(.h4) == "4H" && OKXVenue.bar(.m3) == "3m")
    #expect(OKXVenue.bar(.h6) == "6Hutc" && OKXVenue.bar(.h12) == "12Hutc")
    #expect(OKXVenue.bar(.d1) == "1Dutc" && OKXVenue.bar(.w1) == "1Wutc" && OKXVenue.bar(.mo1) == "1Mutc")
    #expect(OKXVenue.bar(.y1) == nil)
    for iv in OKXProvider.nativeIntervals {
      let channel = OKXVenue.candleChannel(iv)
      #expect(channel.flatMap { OKXVenue.interval(bar: String($0.dropFirst("candle".count))) } == iv)
    }
    #expect(OKXVenue.interval(bar: "1D") == nil)
    let caps = OKXProvider.capabilities
    #expect(caps.source(for: .y1) == .mo1 && caps.supports(.y1) && !caps.isAggregated(.h6))
    #expect(caps.liveKlineIntervals == OKXProvider.nativeIntervals)
  }

  @Test("推送地址：直连 public / business 两个端点；网关走中继，business 加 ?endpoint=business")
  func streams() {
    let direct = MarketRoute(policy: .direct, endpoints: MarketEndpoints(gateways: ["gw1.test"], api: ["api1.test"]))
    #expect(OKXVenue.streams(.public, route: direct).map(\.absoluteString) == ["wss://ws.okx.com:8443/ws/v5/public"])
    #expect(OKXVenue.streams(.business, route: direct).map(\.absoluteString) == ["wss://ws.okx.com:8443/ws/v5/business"])
    let gateway = MarketRoute(policy: .gateway,
                              endpoints: MarketEndpoints(gateways: ["gw1.test", "gw2.test:8443"], api: ["api1.test"]))
    #expect(OKXVenue.streams(.public, route: gateway).map(\.absoluteString)
            == ["wss://gw1.test/v1/market/ws/okx", "wss://gw2.test:8443/v1/market/ws/okx"])
    #expect(OKXVenue.streams(.business, route: gateway).map(\.absoluteString)
            == ["wss://gw1.test/v1/market/ws/okx?endpoint=business", "wss://gw2.test:8443/v1/market/ws/okx?endpoint=business"])
  }

  @Test("限速器一家一条线路一把：同一条线路上几份提供者共用；直连与网关分开记；参数不放宽")
  func sharedLimiter() {
    let route = MarketRoute(policy: .gateway, endpoints: MarketEndpoints(gateways: ["gw1.test"], api: ["api1.test"]))
    let direct = MarketRoute(policy: .direct, endpoints: MarketEndpoints(gateways: ["gw1.test"], api: ["api1.test"]))
    #expect(OKXProvider(route: route).rest.limiter === OKXVenue.gatewayLimiter)
    #expect(OKXProvider(route: route).rest.limiter === OKXProvider(route: route).rest.limiter)
    #expect(OKXProvider(route: direct).rest.limiter === OKXVenue.limiter)
    #expect(OKXVenue.limiter !== OKXVenue.gatewayLimiter)
    // 低于客户端会打的最紧的接口（20 次 / 2 秒）。
    #expect(OKXVenue.perSecond * 2 < 20)
    #expect(OKXProvider(route: route).capabilities == OKXProvider.capabilities)
    let books = OKXBooksAdapter(books: [], gateways: ["api1.test"])
    #expect(books.streamURLs == OKXVenue.relayStreams(hosts: ["api1.test"]))
    #expect(books.keepAlive == DepthKeepAlive(text: OKXVenue.pingText, everyMs: OKXVenue.pingEveryMs))
    #expect(OrderFlowExchange.okx.key == OKXVenue.id)
  }
}

@Suite("OKX 报文翻译")
struct OKXDTOTests {
  @Test("品种表：只收 USDT 线性永续；键是币安形状；精度按字面数；live / suspend / preopen 三档；面值表随之填好")
  func instruments() throws {
    let body = Data(#"""
    {"code":"0","msg":"","data":[
      {"instType":"SWAP","instId":"BTC-USDT-SWAP","uly":"BTC-USDT","instFamily":"BTC-USDT","settleCcy":"USDT",
       "ctVal":"0.01","ctMult":"1","ctValCcy":"BTC","ctType":"linear","tickSz":"0.1","lotSz":"0.01",
       "state":"live","listTime":"1573557408000"},
      {"instType":"SWAP","instId":"QTR-USDT-SWAP","settleCcy":"USDT","ctVal":"10","ctValCcy":"QTR","ctType":"linear",
       "tickSz":"0.25","lotSz":"1","state":"suspend","listTime":"1790000000000"},
      {"instType":"SWAP","instId":"NEW-USDT-SWAP","settleCcy":"USDT","ctVal":"1","ctValCcy":"NEW","ctType":"linear",
       "tickSz":"0.0001","lotSz":"1","state":"preopen","listTime":"1790200000000"},
      {"instType":"SWAP","instId":"BTC-USD-SWAP","settleCcy":"BTC","ctVal":"100","ctValCcy":"USD","ctType":"inverse",
       "tickSz":"0.1","lotSz":"1","state":"live"},
      {"instType":"SWAP","instId":"BTC-USDC-SWAP","settleCcy":"USDC","ctVal":"0.0001","ctValCcy":"BTC","ctType":"linear",
       "tickSz":"0.1","lotSz":"0.01","state":"live"},
      {"instType":"SWAP","instId":"BAD-USDT-SWAP","settleCcy":"USDT","ctType":"linear","state":"live"},
      {"instType":"SWAP"}
    ]}
    """#.utf8)
    let rows: [OKXDTO.Instrument] = try OKXDTO.rows(body, "品种表")
    let listed = rows.filter(\.isListed)
    #expect(listed.map(\.instId) == ["BTC-USDT-SWAP", "QTR-USDT-SWAP", "NEW-USDT-SWAP", "BAD-USDT-SWAP"])
    let infos = listed.compactMap(\.symbolInfo)
    #expect(infos.map(\.symbol) == ["okx/usd_m/BTCUSDT", "okx/usd_m/QTRUSDT", "okx/usd_m/NEWUSDT"])
    let btc = infos[0]
    #expect(btc.base == "BTC" && btc.quote == "USDT" && btc.tickSize == 0.1 && btc.pricePrecision == 1)
    #expect(btc.quantityPrecision == 4)   // 0.01 张 × 0.01 BTC = 0.0001 BTC
    #expect(btc.underlyingType == "COIN" && btc.contractType == "PERPETUAL")
    #expect(btc.status == .tradable && btc.onboardDate == 1_573_557_408_000)
    #expect(infos[1].pricePrecision == 2 && infos[1].status == .halted)
    #expect(infos[2].status == .pending)
    #expect(listed[0].contractValue == 0.01 && listed[1].contractValue == 10)
  }

  @Test("信封：code 不是 \"0\" 当错误（HTTP 200 也一样），带上 OKX 的 msg")
  func envelopeError() {
    let body = Data(#"{"code":"51001","msg":"Instrument ID does not exist","data":[]}"#.utf8)
    #expect(throws: FeedError.badResponse("OKX K 线出错（51001）：Instrument ID does not exist")) {
      _ = try OKXDTO.bars(body)
    }
  }

  @Test("K 线：新的在前 → 升序；成交量取 volCcy（币）；坏行只丢那一行")
  func candles() throws {
    let body = Data(#"""
    {"code":"0","msg":"","data":[
      ["1790118000000","101","110","100","109","250","2.5","272.5","0"],
      ["1790114400000","95","105","90","101","100","1","98","1"],
      ["1790110800000","x","1","1","1","1","1","1","1"]
    ]}
    """#.utf8)
    let bars = try OKXDTO.bars(body)
    #expect(bars.map(\.openTime) == [1_790_114_400_000, 1_790_118_000_000])
    #expect(bars[1].close == 109 && bars[1].volume == 2.5 && bars[1].takerBuy.isNaN)
    #expect(OKXDTO.bar(["1", "1", "2", "1", "1", "5", "0.5", "1", "1"])?.closed == true)
    #expect(OKXDTO.bar(["1", "1", "2", "1", "1", "5", "0.5", "1", "0"])?.closed == false)
  }

  @Test("24h 行情：额 = volCcy24h × last（近似），涨跌按 open24h；别的计价、别的合约不收")
  func tickers() throws {
    let body = Data(#"""
    {"code":"0","msg":"","data":[
      {"instType":"SWAP","instId":"BTC-USDT-SWAP","last":"63000","lastSz":"1","askPx":"63000.1","bidPx":"63000",
       "open24h":"60000","high24h":"64000","low24h":"59000","volCcy24h":"10","vol24h":"1000",
       "sodUtc0":"61000","sodUtc8":"62000","ts":"1790119186000"},
      {"instType":"SWAP","instId":"BTC-USD-SWAP","last":"63000","open24h":"60000","volCcy24h":"5","ts":"1"},
      {"instType":"SWAP","instId":"ETH-USDT-SWAP","last":"0","open24h":"1","ts":"1"}
    ]}
    """#.utf8)
    let rows: [OKXDTO.TickerRow] = try OKXDTO.rows(body, "行情")
    let tickers = rows.compactMap(\.ticker)
    #expect(tickers.count == 1)
    let t = tickers[0]
    #expect(t.symbol == "okx/usd_m/BTCUSDT" && t.last == 63000 && t.high == 64000 && t.low == 59000)
    #expect(abs(t.changePercent - 5) < 1e-9 && t.priceChange == 3000 && t.open24h == 60000)
    #expect(t.quoteVolume == 630_000 && t.timeMs == 1_790_119_186_000)
  }

  @Test("资金费率：fundingTime 是下一次结算；kanpan-api 整表键翻成完整品种键")
  func funding() throws {
    let body = Data(#"""
    {"code":"0","msg":"","data":[{"instType":"SWAP","instId":"BTC-USDT-SWAP","fundingRate":"0.0000182","nextFundingRate":"",
      "fundingTime":"1790121600000","nextFundingTime":"1790150400000","ts":"1790119186000"}]}
    """#.utf8)
    let rows: [OKXDTO.FundingRow] = try OKXDTO.rows(body, "资金费率")
    #expect(rows.first?.snapshot == FundingSnapshot(rate: 0.0000182, nextFundingTimeMs: 1_790_121_600_000))
    let table = try OKXDTO.fundingTable(Data(#"""
    {"data":{"source":"okx","rows":[{"symbol":"BTCUSDT","rate":0.0001,"nextFundingTime":1790121600000},
      {"symbol":"ETHUSDT","rate":-0.0002,"nextFundingTime":0},{"bad":1}]}}
    """#.utf8))
    #expect(table == ["okx/usd_m/BTCUSDT": FundingSnapshot(rate: 0.0001, nextFundingTimeMs: 1_790_121_600_000),
                      "okx/usd_m/ETHUSDT": FundingSnapshot(rate: -0.0002, nextFundingTimeMs: nil)])
    #expect(throws: FeedError.self) { _ = try OKXDTO.fundingTable(Data(#"{"data":{"source":"bybit","rows":[]}}"#.utf8)) }
  }

  @Test("持仓量历史（kanpan-api）：取币的个数、升序；来源或品种对不上整页不收")
  func openInterestHistory() throws {
    let body = Data(#"""
    {"data":{"source":"okx","symbol":"BTCUSDT","period":"5m","rows":[
      [1790162400000,30860.1,2645000000.5],[1790162100000,30854.7563,null],[null,1,1],[1790161800000,-1,null]]}}
    """#.utf8)
    let points = try OKXDTO.openInterestHistory(body, symbol: "okx/usd_m/BTCUSDT")
    #expect(points == [OIPoint(time: 1_790_162_100_000, value: 30854.7563), OIPoint(time: 1_790_162_400_000, value: 30860.1)])
    #expect(throws: FeedError.self) { _ = try OKXDTO.openInterestHistory(body, symbol: "okx/usd_m/ETHUSDT") }
  }

  @Test("推送：tickers / candle1H / trades（张数 × 面值）/ mark-price 捎上最近一笔费率 / funding-rate 出一帧只带费率的标记价")
  func pushPayloads() throws {
    let memo = OKXDTO.FundingMemo()
    func decode(_ s: String) -> [StreamPayload] { OKXDTO.Frame(s).map { OKXDTO.payloads($0, memo: memo) } ?? [] }

    guard case .ticker(let t)? = decode(#"""
    {"arg":{"channel":"tickers","instId":"ETH-USDT-SWAP"},"data":[{"instType":"SWAP","instId":"ETH-USDT-SWAP",
     "last":"2500","open24h":"2400","high24h":"2600","low24h":"2300","volCcy24h":"100","vol24h":"10000","ts":"1790119186000"}]}
    """#).first else { Issue.record("应该是一条 24h 行情"); return }
    #expect(t.symbol == "okx/usd_m/ETHUSDT" && t.quoteVolume == 250_000)

    let candles = decode(#"""
    {"arg":{"channel":"candle1H","instId":"BTC-USDT-SWAP"},"data":[
      ["1790118000000","1","3","1","2","40","4","8","0"],["1790114400000","1","2","1","1","10","1","1","1"]]}
    """#)
    #expect(candles.count == 2)
    guard case .kline(let closed) = candles[0], case .kline(let open) = candles[1] else { Issue.record("应该是两根 K 线"); return }
    #expect(closed.openTime == 1_790_114_400_000 && closed.closed && closed.interval == "1h")
    #expect(open.openTime == 1_790_118_000_000 && !open.closed && open.bar.volume == 4 && open.symbol == "okx/usd_m/BTCUSDT")
    guard case .kline(let daily)? = decode(#"{"arg":{"channel":"candle1Dutc","instId":"BTC-USDT-SWAP"},"data":[["1790035200000","1","2","1","1","1","1","1","0"]]}"#).first else {
      Issue.record("应该是一根日线"); return
    }
    #expect(daily.interval == "1d")

    OKXVenue.contractValues.set(["BTC-USDT-SWAP": 0.01])
    let trades = decode(#"""
    {"arg":{"channel":"trades","instId":"BTC-USDT-SWAP"},"data":[
      {"instId":"BTC-USDT-SWAP","tradeId":"12","px":"63001","sz":"30","side":"sell","ts":"1790119186500","count":"2"},
      {"instId":"BTC-USDT-SWAP","tradeId":"11","px":"63000","sz":"5","side":"buy","ts":"1790119186100","count":"1"}]}
    """#)
    guard case .trade(let first) = trades[0], case .trade(let second) = trades[1] else { Issue.record("应该是两笔成交"); return }
    #expect(first.tradeID == 11 && abs(first.qty - 0.05) < 1e-12 && second.tradeID == 12 && abs(second.qty - 0.3) < 1e-12)
    // 面值不知道：量记 0，只推动价格。
    guard case .trade(let unknown)? = decode(#"{"arg":{"channel":"trades","instId":"ZZZ-USDT-SWAP"},"data":[{"instId":"ZZZ-USDT-SWAP","tradeId":"1","px":"2","sz":"7","side":"buy","ts":"1"}]}"#).first else {
      Issue.record("应该是一笔成交"); return
    }
    #expect(unknown.qty == 0 && unknown.price == 2)

    guard case .markPrice(let s0, let px0, let tick0)? = decode(#"{"arg":{"channel":"mark-price","instId":"BTC-USDT-SWAP"},"data":[{"instType":"SWAP","instId":"BTC-USDT-SWAP","markPx":"63000.5","ts":"1790119186000"}]}"#).first else {
      Issue.record("应该是标记价"); return
    }
    #expect(s0 == "okx/usd_m/BTCUSDT" && px0 == 63000.5 && tick0.timeMs == 1_790_119_186_000 && tick0.fundingRate == nil)
    guard case .markPrice(_, let px1, let tick1)? = decode(#"""
    {"arg":{"channel":"funding-rate","instId":"BTC-USDT-SWAP"},"data":[{"instType":"SWAP","instId":"BTC-USDT-SWAP",
     "fundingRate":"0.0001","nextFundingRate":"","fundingTime":"1790121600000","nextFundingTime":"1790150400000","ts":"1790119187000"}]}
    """#).first else { Issue.record("应该是只带费率的标记价"); return }
    #expect(px1.isNaN && tick1.fundingRate == 0.0001 && tick1.nextFundingTimeMs == 1_790_121_600_000 && tick1.timeMs == 1_790_119_187_000)
    guard case .markPrice(_, _, let tick2)? = decode(#"{"arg":{"channel":"mark-price","instId":"BTC-USDT-SWAP"},"data":[{"instId":"BTC-USDT-SWAP","markPx":"63001","ts":"1790119188000"}]}"#).first else {
      Issue.record("应该是标记价"); return
    }
    #expect(tick2.fundingRate == 0.0001 && tick2.nextFundingTimeMs == 1_790_121_600_000)

    // 不是 USDT 线性永续的、没有 arg 的、坏数的成交：不出报文。
    #expect(decode(#"{"arg":{"channel":"tickers","instId":"BTC-USD-SWAP"},"data":[{"instId":"BTC-USD-SWAP","last":"1"}]}"#).isEmpty)
    #expect(decode(#"{"event":"subscribe","arg":{"channel":"tickers","instId":"BTC-USDT-SWAP"}}"#).isEmpty)
    #expect(decode(#"{"arg":{"channel":"trades","instId":"BTC-USDT-SWAP"},"data":[{"px":"1e400","sz":"1","side":"buy","ts":"1"}]}"#).isEmpty)
  }
}

@Suite("OKX REST 翻页与线路")
struct OKXRESTTests {
  private func provider(_ server: FakeServer, policy: MarketRoutePolicy = .direct,
                        api: [String] = ["api1.example", "api2.example"]) -> OKXProvider {
    let route = MarketRoute(policy: policy, endpoints: MarketEndpoints(gateways: ["gw1.example", "gw2.example"], api: api))
    return OKXProvider(route: route, transport: FakeTransport(server),
                       limiter: VenueRateLimiter(perSecond: 1_000_000, pacer: FastPacer()),
                       clock: { Fixture.now })
  }

  @Test("首屏一发：最新 300 根就是一次 market/candles（直连打 OKX 自己的域名，bar 用 OKX 写法）")
  func firstScreenOneRequest() async throws {
    let server = FakeServer { Fixture.candlePage($0) }
    let bars = try await provider(server).klines(symbol: "okx/usd_m/BTCUSDT", interval: .h1,
                                                 limit: OKXProvider.capabilities.initialKlines,
                                                 startTime: nil, endTime: nil)
    #expect(bars.count == 300 && bars.last?.openTime == Fixture.currentHour)
    #expect(zip(bars, bars.dropFirst()).allSatisfy { $1.openTime - $0.openTime == Fixture.hour })
    let urls = await server.urls()
    #expect(urls.map(\.absoluteString)
            == ["https://www.okx.com/api/v5/market/candles?instId=BTC-USDT-SWAP&bar=1H&limit=300"])
  }

  @Test("网关线路：/v1/market/raw/api/v5/… 带 source=okx；主网关 5xx 换备用")
  func gatewayFallback() async throws {
    let server = FakeServer { url in
      url.host == "api1.example" ? json("{}", status: 502) : Fixture.candlePage(url)
    }
    _ = try await provider(server, policy: .gateway).klines(symbol: "okx/usd_m/BTCUSDT", interval: .h1, limit: 5,
                                                            startTime: nil, endTime: nil)
    let urls = await server.urls()
    #expect(urls.map(\.host) == ["api1.example", "api2.example"])
    #expect(urls[1].absoluteString
            == "https://api2.example/v1/market/raw/api/v5/market/candles?source=okx&instId=BTC-USDT-SWAP&bar=1H&limit=5")
  }

  @Test("向前翻：最近 1440 根以内用 candles（一页 300），更早的用 history-candles（一页 100），游标 after 接力")
  func historyPaging() async throws {
    let server = FakeServer { Fixture.candlePage($0) }
    let p = provider(server)
    // 紧挨着现在：一页 candles。
    let near = try await p.history(symbol: "okx/usd_m/BTCUSDT", interval: .h1, pages: 1,
                                   before: Fixture.currentHour - 299 * Fixture.hour)
    #expect(near.count == 300 && near.last?.openTime == Fixture.currentHour - 300 * Fixture.hour)
    #expect(zip(near, near.dropFirst()).allSatisfy { $1.openTime - $0.openTime == Fixture.hour })
    var urls = await server.urls()
    #expect(urls.count == 1 && urls[0].path == "/api/v5/market/candles")
    #expect(Fixture.query(urls[0], "after") == String(Fixture.currentHour - 299 * Fixture.hour))

    // 很早以前：三页 history-candles，每页 100 根，after 接力。
    let before = Fixture.currentHour - 3000 * Fixture.hour
    let far = try await p.history(symbol: "okx/usd_m/BTCUSDT", interval: .h1, pages: 1, before: before)
    #expect(far.count == 300 && far.last?.openTime == before - Fixture.hour && far.first?.openTime == before - 300 * Fixture.hour)
    urls = Array(await server.urls().dropFirst())
    #expect(urls.count == 3 && urls.allSatisfy { $0.path == "/api/v5/market/history-candles" && Fixture.query($0, "limit") == "100" })
    #expect(urls.map { Fixture.query($0, "after") } == [String(before), String(before - 100 * Fixture.hour),
                                                         String(before - 200 * Fixture.hour)])
  }

  @Test("翻到上线那一根就停：回得比要的少不再往前问")
  func stopsAtListing() async throws {
    let listed = Fixture.currentHour - 2050 * Fixture.hour
    let server = FakeServer { Fixture.candlePage($0, listedAt: listed) }
    let bars = try await provider(server).history(symbol: "okx/usd_m/NEWUSDT", interval: .h1, pages: 1,
                                                  before: listed + 120 * Fixture.hour)
    #expect(bars.count == 120 && bars.first?.openTime == listed)
    #expect(await server.urls().count == 2)
  }

  @Test("补缺：缺口在 300 根以内就是一发 candles；超过 maxTailBars 直接报接不上")
  func contiguousTail() async throws {
    let server = FakeServer { Fixture.candlePage($0) }
    let p = provider(server)
    let from = Fixture.currentHour - 10 * Fixture.hour
    let bars = try await p.contiguousTail(symbol: "okx/usd_m/BTCUSDT", interval: .h1, from: from)
    #expect(bars.first?.openTime == from && bars.last?.openTime == Fixture.currentHour && bars.count == 11)
    let urls = await server.urls()
    #expect(urls.count == 1 && urls[0].path == "/api/v5/market/candles" && Fixture.query(urls[0], "after") == nil)
    await #expect(throws: FeedError.gapTooLong) {
      _ = try await p.contiguousTail(symbol: "okx/usd_m/BTCUSDT", interval: .h1,
                                     from: Fixture.currentHour - 2000 * Fixture.hour)
    }
  }

  @Test("补缺跨四页：candles 带 after 接力，拼回来连续、不重不漏")
  func contiguousTailPaged() async throws {
    let server = FakeServer { Fixture.candlePage($0) }
    let from = Fixture.currentHour - 1000 * Fixture.hour
    let bars = try await provider(server).contiguousTail(symbol: "okx/usd_m/BTCUSDT", interval: .h1, from: from)
    #expect(bars.count == 1001 && bars.first?.openTime == from)
    #expect(zip(bars, bars.dropFirst()).allSatisfy { $1.openTime - $0.openTime == Fixture.hour })
    let urls = await server.urls()
    #expect(urls.count == 4 && urls.allSatisfy { $0.path == "/api/v5/market/candles" })
  }

  @Test("行情、整表、费率：路径与查询；整表只留 USDT 线性永续")
  func tickersAndFunding() async throws {
    let server = FakeServer { url in
      switch url.path {
      case "/api/v5/market/tickers":
        return json(#"{"code":"0","data":[{"instId":"BTC-USDT-SWAP","last":"2","open24h":"1","volCcy24h":"3","ts":"5"},{"instId":"BTC-USD-SWAP","last":"2"}]}"#)
      case "/api/v5/market/ticker":
        return json(#"{"code":"0","data":[{"instId":"BTC-USDT-SWAP","last":"2","open24h":"1","volCcy24h":"3","ts":"5"}]}"#)
      case "/api/v5/public/funding-rate":
        return json(#"{"code":"0","data":[{"instId":"BTC-USDT-SWAP","fundingRate":"0.0001","fundingTime":"1790121600000"}]}"#)
      default:
        return json("{}", status: 404)
      }
    }
    let p = provider(server)
    #expect(try await p.tickers24h().map(\.symbol) == ["okx/usd_m/BTCUSDT"])
    #expect(try await p.ticker24h(symbol: "okx/usd_m/BTCUSDT").quoteVolume == 6)
    #expect(try await p.funding(symbol: "okx/usd_m/BTCUSDT") == FundingSnapshot(rate: 0.0001, nextFundingTimeMs: 1_790_121_600_000))
    #expect(await server.urls().map(\.absoluteString) == [
      "https://www.okx.com/api/v5/market/tickers?instType=SWAP",
      "https://www.okx.com/api/v5/market/ticker?instId=BTC-USDT-SWAP",
      "https://www.okx.com/api/v5/public/funding-rate?instId=BTC-USDT-SWAP",
    ])
  }

  @Test("持仓量历史与费率整表：两条线路都打 kanpan-api 主机（不打 OKX、不打网关表）")
  func apiHostsOnBothRoutes() async throws {
    for policy in [MarketRoutePolicy.direct, .gateway] {
      let server = FakeServer { url in
        if url.host == "api1.example" { return json("{}", status: 503) }
        if url.path == "/v1/market/funding" { return json(#"{"data":{"source":"okx","rows":[]}}"#) }
        return json(#"{"data":{"source":"okx","symbol":"BTCUSDT","period":"5m","rows":[[1790162100000,1.5,null],[1790161800000,1,null]]}}"#)
      }
      let p = provider(server, policy: policy)
      let points = try await p.openInterestHist(symbol: "okx/usd_m/BTCUSDT", period: "5m", limit: 900,
                                                startTime: 1_790_162_000_000, endTime: 1_790_162_200_000)
      #expect(points == [OIPoint(time: 1_790_162_100_000, value: 1.5)], "\(policy)")
      #expect(try await p.fundingAll().isEmpty)
      let urls = await server.urls()
      #expect(urls.map { $0.host ?? "" } == ["api1.example", "api2.example", "api1.example", "api2.example"], "\(policy)")
      #expect(urls[1].absoluteString
              == "https://api2.example/v1/market/open-interest/history?source=okx&symbol=BTCUSDT&period=5m&limit=500&endTime=1790162200000")
      #expect(urls[3].absoluteString == "https://api2.example/v1/market/funding?source=okx")
    }
    // 4xx 不换主机。
    let refused = FakeServer { _ in json(#"{"error":"unsupported_period"}"#, status: 400) }
    await #expect(throws: UpstreamError.self) {
      _ = try await provider(refused).openInterestHist(symbol: "okx/usd_m/BTCUSDT", period: "1m", limit: 10,
                                                       startTime: nil, endTime: nil)
    }
    #expect(await refused.urls().count == 1)
  }

  @Test("品种表：instType=SWAP 一发；面值表随之换新")
  func instrumentsFillContractValues() async throws {
    let server = FakeServer { _ in
      json(#"{"code":"0","data":[{"instType":"SWAP","instId":"ABC-USDT-SWAP","settleCcy":"USDT","ctVal":"100","ctValCcy":"ABC","ctType":"linear","tickSz":"0.001","lotSz":"1","state":"live"}]}"#)
    }
    let list = try await provider(server, policy: .gateway).instruments()
    #expect(list.map(\.symbol) == ["okx/usd_m/ABCUSDT"])
    #expect(OKXVenue.contractValues.value("ABC-USDT-SWAP") == 100)
    #expect(await server.urls().map(\.absoluteString)
            == ["https://api1.example/v1/market/raw/api/v5/public/instruments?source=okx&instType=SWAP"])
  }
}

@Suite("OKX 推送", .timeLimit(.minutes(1)))
struct OKXWireTests {
  private struct Control: Decodable {
    struct Arg: Decodable, Equatable { var channel: String; var instId: String }
    var op: String
    var args: [Arg]
  }

  private func controls(_ s: GateSocket) async -> [Control] {
    await s.sent.compactMap { try? JSONDecoder().decode(Control.self, from: Data($0.utf8)) }
  }

  @Test("订阅分端点：K 线去 business，行情 / 逐笔 / 标记价（连带资金费率）去 public；主动成交、盘口没有")
  func subsByEndpoint() {
    let topics: [StreamTopic] = [.kline(symbol: "okx/usd_m/BTCUSDT", interval: .h1), .ticker(symbol: "okx/usd_m/BTCUSDT"),
                                 .markPrice(symbol: "okx/usd_m/BTCUSDT"), .trade(symbol: "okx/usd_m/ETHUSDT"),
                                 .aggTrade(symbol: "okx/usd_m/BTCUSDT"), .depth(symbol: "okx/usd_m/BTCUSDT"),
                                 .kline(symbol: "okx/usd_m/BTCUSDT", interval: .y1)]
    let business = OKXWire(endpoint: .business).subs(topics)
    #expect(business == [OKXWire.Sub(channel: "candle1H", instID: "BTC-USDT-SWAP")])
    let pub = OKXWire(endpoint: .public).subs(topics)
    #expect(pub == [OKXWire.Sub(channel: "tickers", instID: "BTC-USDT-SWAP"),
                    OKXWire.Sub(channel: "mark-price", instID: "BTC-USDT-SWAP"),
                    OKXWire.Sub(channel: "funding-rate", instID: "BTC-USDT-SWAP"),
                    OKXWire.Sub(channel: "trades", instID: "ETH-USDT-SWAP")])
    #expect(OKXWire.endpoint(of: .aggTrade(symbol: "okx/usd_m/BTCUSDT")) == nil)
  }

  @Test("控制帧：只有 op 与 args 两个键；一帧最多 12 个；保活是字面量 ping")
  func controlFrames() throws {
    let wire = OKXWire(endpoint: .public)
    let pending = Set((0..<30).map { OKXWire.Sub(channel: "tickers", instID: "C\($0)-USDT-SWAP") })
    #expect(wire.nextBatch(pending).count == 12)
    // 一帧装满 12 个才分下一帧（订退按帧计 480 次 / 小时）；最长的一帧也远小于 64 KB。
    let longest = try wire.control(.subscribe, (0..<12).map { OKXWire.Sub(channel: "funding-rate", instID: "ABCDEFGHIJKLMNOPQRST\($0)-USDT-SWAP") })
    #expect(longest.utf8.count < 64 * 1024)
    let chartSwitch = OKXWire(endpoint: .public).subs([.ticker(symbol: "okx/usd_m/BTCUSDT"), .markPrice(symbol: "okx/usd_m/BTCUSDT")])
    #expect(wire.nextBatch(chartSwitch).count == chartSwitch.count)
    let text = try wire.control(.subscribe, [OKXWire.Sub(channel: "tickers", instID: "BTC-USDT-SWAP")])
    #expect(text == #"{"args":[{"channel":"tickers","instId":"BTC-USDT-SWAP"}],"op":"subscribe"}"#)
    #expect(wire.keepAlive == VenueKeepAlive(text: "ping", everyMs: 20_000))
    #expect(wire.controlGapMs >= 334)
  }

  @Test("解帧：订阅回执算生效；pong / notice 只说明连接活着；报错点了名就只记那一个")
  func decodeEvents() {
    let wire = OKXWire(endpoint: .public)
    let btc = OKXWire.Sub(channel: "tickers", instID: "BTC-USDT-SWAP")
    #expect(wire.decode(#"{"event":"subscribe","arg":{"channel":"tickers","instId":"BTC-USDT-SWAP"},"connId":"a4d3ae55"}"#).confirmed == [btc])
    let pong = wire.decode("pong")
    #expect(pong.payloads.isEmpty && pong.confirmed.isEmpty && pong.error == nil)
    #expect(wire.decode(#"{"event":"notice","code":"64008","msg":"The connection will soon be closed for a service upgrade."}"#).error == nil)
    let named = wire.decode(#"{"event":"error","code":"60018","msg":"Wrong URL or channel:tickers,instId:NOPE-USDT-SWAP doesn't exist. Please use the correct URL, channel and parameters referring to API document.","connId":"a"}"#)
    #expect(named.error?.hasPrefix("60018 ") == true)
    #expect(named.rejected == [OKXWire.Sub(channel: "tickers", instID: "NOPE-USDT-SWAP")])
    let anonymous = wire.decode(#"{"event":"error","code":"60012","msg":"Invalid request: {\"op\": \"subscribe\"}","connId":"a"}"#)
    #expect(anonymous.error != nil && anonymous.rejected == nil)
    let data = wire.decode(#"{"arg":{"channel":"tickers","instId":"BTC-USDT-SWAP"},"data":[{"instId":"BTC-USDT-SWAP","last":"1","open24h":"1","ts":"1"}]}"#)
    #expect(data.confirmed == [btc] && data.payloads.count == 1)
  }

  @Test("一条推送 = public + business 两条连接：订阅按端点分过去，事件合成一条；切到只有行情就收掉 K 线那条")
  func splitStream() async throws {
    let bench = GateSocketBench()
    let route = MarketRoute(policy: .gateway, endpoints: MarketEndpoints(gateways: ["gw1.test"], api: ["api1.test"]))
    let provider = OKXProvider(route: route, transport: FakeTransport(FakeServer { _ in json("{}") }), sockets: bench)
    let ws = provider.makeStream(silenceMs: 1e12, log: .silent)
    let stream = await ws.start(topics: [.kline(symbol: "okx/usd_m/BTCUSDT", interval: .h1),
                                         .ticker(symbol: "okx/usd_m/BTCUSDT")])
    #expect(await waitUntil(5) { await bench.connects == 2 })
    let sockets = await bench.sockets
    let business = try #require(sockets.first { $0.url.query == "endpoint=business" })
    let pub = try #require(sockets.first { $0.url.query == nil })
    #expect(business.url.absoluteString == "wss://gw1.test/v1/market/ws/okx?endpoint=business")
    #expect(pub.url.absoluteString == "wss://gw1.test/v1/market/ws/okx")
    #expect(await waitUntil(5) {
      let b = await self.controls(business).count, p = await self.controls(pub).count
      return b == 1 && p == 1
    })
    #expect(await controls(business).first?.args == [.init(channel: "candle1H", instId: "BTC-USDT-SWAP")])
    #expect(await controls(pub).first?.args == [.init(channel: "tickers", instId: "BTC-USDT-SWAP")])

    await business.push(.text(#"{"arg":{"channel":"candle1H","instId":"BTC-USDT-SWAP"},"data":[["1790118000000","1","2","1","2","1","1","2","0"]]}"#))
    await pub.push(.text(#"{"arg":{"channel":"tickers","instId":"BTC-USDT-SWAP"},"data":[{"instId":"BTC-USDT-SWAP","last":"2","open24h":"1","ts":"1"}]}"#))
    var connected = 0, kline = false, ticker = false
    for await event in stream {
      switch event {
      case .connected: connected += 1
      case .payload(.kline(let k)): kline = k.symbol == "okx/usd_m/BTCUSDT" && k.interval == "1h"
      case .payload(.ticker(let t)): ticker = t.symbol == "okx/usd_m/BTCUSDT"
      default: break
      }
      if kline && ticker { break }
    }
    // 两条车道刚开时各连一次，不是重连：只报一次。
    #expect(connected == 1)

    await ws.replace(topics: [.ticker(symbol: "okx/usd_m/ETHUSDT")])
    #expect(await waitUntil(5) { await business.closed })
    #expect(await waitUntil(5) { await self.controls(pub).count == 3 })
    let tail = Array(await controls(pub).dropFirst())
    #expect(tail[0].op == "unsubscribe" && tail[0].args == [.init(channel: "tickers", instId: "BTC-USDT-SWAP")])
    #expect(tail[1].op == "subscribe" && tail[1].args == [.init(channel: "tickers", instId: "ETH-USDT-SWAP")])
    #expect(await bench.connects == 2)

    // 再要 K 线：business 那条重新连上（第三条连接），public 不动。
    await ws.replace(topics: [.ticker(symbol: "okx/usd_m/ETHUSDT"), .kline(symbol: "okx/usd_m/ETHUSDT", interval: .d1)])
    #expect(await waitUntil(5) { await bench.connects == 3 })
    let again = try #require(await bench.socket(3))
    #expect(again.url.query == "endpoint=business")
    #expect(await waitUntil(5) { await self.controls(again).first?.args == [.init(channel: "candle1Dutc", instId: "ETH-USDT-SWAP")] })
    await ws.stop()
    #expect(await pub.closed)
    #expect(await again.closed)
  }

  @Test("直连：只订行情时只连 public，一条连接；保活按点发 ping")
  func directPublicOnly() async throws {
    let bench = GateSocketBench()
    let ws = VenueStream(wire: OKXWire(endpoint: .public), urls: OKXVenue.streams(.public, route: MarketRoute(policy: .direct, endpoints: .default)),
                         factory: bench, pacer: FastPacer(scale: 0.0001), silenceMs: 1e12, transportSilenceMs: 1e12)
    _ = await ws.start(topics: [.ticker(symbol: "okx/usd_m/BTCUSDT")])
    #expect(await waitUntil(5) { await bench.socket(1) != nil })
    let socket = try #require(await bench.socket(1))
    #expect(socket.url.absoluteString == "wss://ws.okx.com:8443/ws/v5/public")
    #expect(await waitUntil(5) { await socket.sent.filter { $0 == "ping" }.count >= 2 })
    await ws.stop()
  }
}

// ---------------------------------------------------------------- 合流器（通用件，OKX 是第一个用它的）

/// 一条假车道：谁 start 就给谁一条事件流，测试从外面往里推事件。
private actor FakeLane: MarketStream {
  private var sink: AsyncStream<WSEvent>.Continuation?
  private(set) var topics: [StreamTopic] = []
  private(set) var starts = 0
  private(set) var stops = 0
  func start(topics: [StreamTopic]) async -> AsyncStream<WSEvent> {
    starts += 1; self.topics = topics
    let (stream, sink) = AsyncStream<WSEvent>.makeStream(bufferingPolicy: .unbounded)
    self.sink = sink
    return stream
  }
  func replace(topics: [StreamTopic]) async { self.topics = topics }
  func stop() async { stops += 1; sink?.finish(); sink = nil }
  var firstFrameSilenceMs: Double { 1 }
  var currentConnectionID: Int { starts }
  func emit(_ event: WSEvent) { sink?.yield(event) }
}

private final class EventLog: @unchecked Sendable {
  private let lock = NSLock()
  private var items: [String] = []
  func add(_ s: String) { lock.lock(); items.append(s); lock.unlock() }
  var all: [String] { lock.lock(); defer { lock.unlock() }; return items }
}

@Suite("交易所通用件 · 分端点合流", .timeLimit(.minutes(1)))
struct SplitVenueStreamTests {
  @Test("连接号：这一轮第一次连上报一次，之后哪条车道重连再报；状态取最差的那条、变了才报；分不到订阅的车道不开")
  func mergesEvents() async throws {
    let kline = FakeLane(), quote = FakeLane()
    let split = SplitVenueStream(lanes: [
      .init(kline) { if case .kline = $0 { return true } else { return false } },
      .init(quote) { if case .ticker = $0 { return true } else { return false } },
    ])
    let log = EventLog()
    let stream = await split.start(topics: [.kline(symbol: "x/y/A", interval: .m1), .ticker(symbol: "x/y/A"),
                                            .depth(symbol: "x/y/A")])
    let reader = Task {
      for await event in stream {
        switch event {
        case .connected(let id): log.add("connected \(id)")
        case .status(let s): log.add(s.rawValue)
        case .payload: log.add("payload")
        }
      }
    }
    #expect(await kline.topics == [.kline(symbol: "x/y/A", interval: .m1)])
    #expect(await quote.topics == [.ticker(symbol: "x/y/A")])

    await kline.emit(.connected(id: 1)); await kline.emit(.status(.live))
    #expect(await waitUntil(5) { log.all == ["connected 1", "live"] })
    await quote.emit(.connected(id: 1)); await quote.emit(.status(.live))
    await quote.emit(.payload(.other("x")))
    #expect(await waitUntil(5) { log.all == ["connected 1", "live", "payload"] })

    // 行情那条断了又连上：K 线那条还在推也报「重连中」，连上之后报一次连接号（上层据此补缺）。
    await quote.emit(.status(.reconnecting))
    #expect(await waitUntil(5) { log.all.last == "reconnecting" })
    await quote.emit(.connected(id: 2)); await quote.emit(.status(.live))
    #expect(await waitUntil(5) { log.all.suffix(2) == ["connected 2", "live"] })

    // 只剩行情：K 线那条收掉；再要 K 线就重新开。
    await split.replace(topics: [.ticker(symbol: "x/y/B")])
    #expect(await kline.stops == 1)
    #expect(await quote.topics == [.ticker(symbol: "x/y/B")])
    await split.replace(topics: [.ticker(symbol: "x/y/B"), .kline(symbol: "x/y/B", interval: .h1)])
    #expect(await kline.starts == 2)
    #expect(await quote.starts == 1)
    #expect(await split.currentConnectionID == 3)
    await split.stop()
    #expect(await waitUntil(5) { log.all.last == "offline" })
    #expect(await kline.stops == 2)
    #expect(await quote.stops == 1)
    reader.cancel()
  }
}
