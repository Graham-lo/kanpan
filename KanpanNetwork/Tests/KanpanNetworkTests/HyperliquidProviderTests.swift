import Foundation
import Testing
@testable import KanpanNetwork
import KanpanNetworkTestSupport
import KanpanCore

// Hyperliquid 永续行情（2026-10-08 接成独立的一家）。容器连不上交易所、录不了真帧：
// REST 与推送的夹具按官方文档（Info endpoint › Perpetuals、Websocket › Subscriptions）的字段与示例写，
// 数值改成 2026-10 前后的量级；订单流那两种帧（l2Book / trades）的真帧样本在 `BybitHyperliquidAdapterTests`。

/// 按 POST 正文答话的假服务器：Hyperliquid 全部 REST 都打同一个 `/info`，只能看 `type` 分。
private actor InfoServer {
  /// 一次 `candleSnapshot` 的 `req`（拆成可以跨 actor 的样子）。
  struct Req: Sendable {
    var keys: Set<String>
    var coin: String?
    var interval: String?
    var startTime: Int64?
    var endTime: Int64?
  }
  struct Hit: Sendable { var url: URL; var type: String; var req: Req? }
  private let handler: @Sendable (URL, String, Int64?) -> HTTPReply
  private(set) var hits: [Hit] = []
  /// `handler` 拿到 URL、`type` 与 `req.startTime`（够造 K 线页了）。
  init(_ handler: @escaping @Sendable (URL, String, Int64?) -> HTTPReply) { self.handler = handler }
  func serve(_ url: URL, _ body: Data) -> HTTPReply {
    let obj = (try? JSONSerialization.jsonObject(with: body)) as? [String: Any] ?? [:]
    let type = obj["type"] as? String ?? "?"
    let req = (obj["req"] as? [String: Any]).map {
      Req(keys: Set($0.keys), coin: $0["coin"] as? String, interval: $0["interval"] as? String,
          startTime: ($0["startTime"] as? NSNumber)?.int64Value, endTime: ($0["endTime"] as? NSNumber)?.int64Value)
    }
    hits.append(Hit(url: url, type: type, req: req))
    return handler(url, type, req?.startTime)
  }
  func types() -> [String] { hits.map(\.type) }
  func urls() -> [String] { hits.map(\.url.absoluteString) }
  func reqs() -> [Req] { hits.compactMap(\.req) }
  func count() -> Int { hits.count }
}

private struct InfoTransport: HTTPTransport {
  let server: InfoServer
  func get(_ url: URL, timeout: TimeInterval) async throws -> HTTPReply { json("GET not allowed", status: 405) }
  func post(_ url: URL, json body: Data, timeout: TimeInterval) async throws -> HTTPReply {
    await server.serve(url, body)
  }
}

private enum HL {
  /// 2026-10-08 00:30:00 UTC。
  static let nowMs: Int64 = 1_791_419_400_000
  static let now = Date(timeIntervalSince1970: Double(nowMs) / 1000)

  /// `{"type":"meta"}`（官方示例的形状；`isDelisted` 只在下架的那行出现）。
  static let meta = #"""
  {"universe":[
    {"name":"BTC","szDecimals":5,"maxLeverage":40,"marginTableId":56},
    {"name":"ETH","szDecimals":4,"maxLeverage":25,"marginTableId":55},
    {"name":"kPEPE","szDecimals":0,"maxLeverage":10,"marginTableId":51},
    {"name":"LUNA","szDecimals":1,"maxLeverage":3,"onlyIsolated":true,"isDelisted":true,"marginTableId":3}
  ],"marginTables":[]}
  """#

  /// `{"type":"metaAndAssetCtxs"}`：`[meta, [ctx…]]`，两个数组同序。ETH 那行 `midPx` 是 null（盘口一侧空着）。
  static let metaAndCtxs = #"""
  [{"universe":[
     {"name":"BTC","szDecimals":5,"maxLeverage":40},
     {"name":"ETH","szDecimals":4,"maxLeverage":25},
     {"name":"kPEPE","szDecimals":0,"maxLeverage":10},
     {"name":"LUNA","szDecimals":1,"maxLeverage":3,"isDelisted":true}]},
   [{"funding":"0.0000125","openInterest":"26085.29572","prevDayPx":"80000.0","dayNtlVlm":"3369196034.6","premium":"0.0003129",
     "oraclePx":"82218.0","markPx":"82266.0","midPx":"82256.5","impactPxs":["82256.0","82257.0"],"dayBaseVlm":"41652.27394"},
    {"funding":"-0.00000325","openInterest":"512345.1","prevDayPx":"2500.0","dayNtlVlm":"1000000.0","premium":"-0.0001",
     "oraclePx":"2449.0","markPx":"2450.0","midPx":null,"impactPxs":null,"dayBaseVlm":"408.0"},
    {"funding":"0.0000125","openInterest":"8723400000.0","prevDayPx":"0.0040","dayNtlVlm":"52000000.0","premium":"0.0",
     "oraclePx":"0.004031","markPx":"0.004031","midPx":"0.0040315","impactPxs":["0.004031","0.004032"],"dayBaseVlm":"12900000000.0"},
    {"funding":"0.0","openInterest":"0.0","prevDayPx":"0.1","dayNtlVlm":"0.0","premium":null,
     "oraclePx":"0.1","markPx":"0.1","midPx":null,"impactPxs":null,"dayBaseVlm":"0.0"}]]
  """#

  /// `candleSnapshot` 的一页（官方示例的字段；`t` 开盘毫秒、`T` 收盘毫秒、价量是字符串）。
  static func candles(_ opens: [Int64], interval: String = "1h", coin: String = "BTC") -> String {
    "[" + opens.map {
      #"{"t":\#($0),"T":\#($0 + 3_599_999),"s":"\#(coin)","i":"\#(interval)","o":"82000.0","c":"82100.0","h":"82200.0","l":"81900.0","v":"12.5","n":340}"#
    }.joined(separator: ",") + "]"
  }

  static func provider(_ server: InfoServer, policy: MarketRoutePolicy = .direct,
                       names: HyperliquidNames = HyperliquidNames()) -> HyperliquidProvider {
    HyperliquidProvider(policy: policy, gateways: ["gw1.example", "gw2.example:8443"],
                        transport: InfoTransport(server: server),
                        limiter: VenueRateLimiter(weightPerMinute: 1_000_000, pacer: FastPacer()),
                        clock: { now }, names: names)
  }

  static func answering(_ server: @escaping @Sendable (String, Int64?) -> HTTPReply) -> InfoServer {
    InfoServer { _, type, start in server(type, start) }
  }
}

@Suite("Hyperliquid 报文翻译")
struct HyperliquidDTOTests {
  @Test("品种表：价格精度 6 − szDecimals、数量精度 szDecimals；base 原样 kPEPE、键大写；计价 USDC；下架的不收")
  func meta() async throws {
    let server = HL.answering { _, _ in json(HL.meta) }
    let names = HyperliquidNames()
    let p = HL.provider(server, names: names)
    let list = try await p.instruments()
    #expect(await p.rest.limiter.spentWeight() == 20)
    #expect(list.map(\.symbol) == ["hyperliquid/usd_m/BTC", "hyperliquid/usd_m/ETH", "hyperliquid/usd_m/KPEPE"])
    let btc = try #require(list.first)
    #expect(btc.base == "BTC" && btc.quote == "USDC" && btc.pricePrecision == 1 && btc.quantityPrecision == 5)
    #expect(abs(btc.tickSize - 0.1) < 1e-12 && btc.underlyingType == "COIN" && btc.contractType == "PERPETUAL")
    let pepe = try #require(list.last)
    #expect(pepe.base == "kPEPE" && pepe.pricePrecision == 6 && pepe.quantityPrecision == 0)
    #expect(abs(pepe.tickSize - 1e-6) < 1e-15)
    // 拉过品种表就记下了原名，下架的也记（历史 K 线还拿得到）。
    #expect(names.original("KPEPE") == "kPEPE" && names.original("LUNA") == "LUNA" && names.loaded)
    #expect(await server.types() == ["meta"])
  }

  @Test("全市场行情：metaAndAssetCtxs 一次全有；价取中间价（没有用标记价），涨跌按 prevDayPx，额是 dayNtlVlm；没有最高最低")
  func tickers() async throws {
    let server = HL.answering { _, _ in json(HL.metaAndCtxs) }
    let tickers = try await HL.provider(server).tickers24h()
    #expect(tickers.map(\.symbol) == ["hyperliquid/usd_m/BTC", "hyperliquid/usd_m/ETH", "hyperliquid/usd_m/KPEPE"])
    let btc = tickers[0]
    #expect(btc.last == 82256.5 && btc.markPrice == 82266 && btc.open24h == 80000)
    #expect(abs(btc.changePercent - 2.8206_25) < 1e-6)
    #expect(abs(btc.quoteVolume - 3_369_196_034.6) < 1e-3 && btc.high.isNaN && btc.low.isNaN)
    #expect(btc.timeMs == HL.nowMs && abs((btc.priceChange ?? 0) - 2256.5) < 1e-9)
    let eth = tickers[1]
    #expect(eth.last == 2450 && abs(eth.changePercent - -2) < 1e-9)
    // 单品种也是这一个请求里挑出来的。
    let pepe = try await HL.provider(server).ticker24h(symbol: "hyperliquid/usd_m/KPEPE")
    #expect(pepe.last == 0.0040315 && pepe.symbol == "hyperliquid/usd_m/KPEPE")
    #expect(await server.types() == ["metaAndAssetCtxs", "metaAndAssetCtxs"])
  }

  @Test("两个数组按下标对齐：中间一行坏了只丢那一只，后面的不挪位")
  func ctxAlignment() throws {
    let body = #"[{"universe":[{"name":"BTC","szDecimals":5},{"bad":1},{"name":"SOL","szDecimals":2}]},[{"markPx":"1"},{"markPx":"2"},{"markPx":"3","prevDayPx":"3"}]]"#
    let rows = try HyperliquidDTO.metaAndCtxs(Data(body.utf8))
    #expect(rows.map(\.asset.name) == ["BTC", "SOL"])
    #expect(rows.map(\.ctx.markPx) == [1, 3])
    #expect(throws: FeedError.self) { try HyperliquidDTO.metaAndCtxs(Data(#"{"universe":[]}"#.utf8)) }
  }

  @Test("资金费率：一小时一期，下一次结算是下一个整点；整表一次")
  func funding() async throws {
    let server = HL.answering { _, _ in json(HL.metaAndCtxs) }
    let p = HL.provider(server)
    let btc = try await p.funding(symbol: "hyperliquid/usd_m/BTC")
    #expect(btc.rate == 0.0000125 && btc.nextFundingTimeMs == 1_791_421_200_000)
    let all = try await p.fundingAll()
    #expect(all.keys.sorted() == ["hyperliquid/usd_m/BTC", "hyperliquid/usd_m/ETH", "hyperliquid/usd_m/KPEPE"])
    #expect(all["hyperliquid/usd_m/ETH"]?.rate == -0.00000325)
    #expect(HyperliquidVenue.nextFundingTimeMs(nowMs: 1_791_421_200_000) == 1_791_424_800_000)
  }

  @Test("K 线：t 是开盘毫秒、字符串 → 数、乱序 → 升序；坏一根只丢那一根；没有主动买量")
  func bars() throws {
    let body = #"[{"t":7200000,"T":10799999,"s":"BTC","i":"1h","o":"2","c":"3","h":"4","l":"1","v":"5","n":1},"#
      + #"{"t":3600000,"T":7199999,"s":"BTC","i":"1h","o":"1","c":"2","h":"2","l":"1","v":"1","n":1},"#
      + #"{"t":0,"T":3599999,"s":"BTC","i":"1h","o":"x","c":"2","h":"2","l":"1","v":"1","n":1}]"#
    let bars = try HyperliquidDTO.bars(Data(body.utf8))
    #expect(bars.map(\.openTime) == [3_600_000, 7_200_000])
    #expect(bars[1] == Bar(openTime: 7_200_000, open: 2, high: 4, low: 1, close: 3, volume: 5))
    #expect(bars[1].takerBuy.isNaN)
    #expect(try HyperliquidDTO.bars(Data("null".utf8)).isEmpty)
  }
}

@Suite("Hyperliquid 地址、代号与周期")
struct HyperliquidVenueTests {
  @Test("身份：hyperliquid/usd_m、缩写 HL、计价 USDC；限速器一条线路一把（直连 / 网关两个出口），同线路共用")
  func identity() {
    #expect(HyperliquidVenue.id == "hyperliquid" && HyperliquidVenue.market == "usd_m")
    #expect(HyperliquidVenue.shortName == "HL" && HyperliquidVenue.displayName == "Hyperliquid")
    #expect(HyperliquidProvider.capabilities.quoteAssets == ["USDC"])
    func route(_ p: MarketRoutePolicy) -> MarketRoute {
      MarketRoute(policy: p, endpoints: MarketEndpoints(gateways: ["gw.example"]))
    }
    #expect(HyperliquidProvider(route: route(.direct)).rest.limiter === HyperliquidVenue.directLimiter)
    #expect(HyperliquidProvider(route: route(.direct)).rest.limiter === HyperliquidVenue.limiter(route(.direct)))
    #expect(HyperliquidProvider(route: route(.gateway)).rest.limiter === HyperliquidVenue.gatewayLimiter)
    #expect(HyperliquidVenue.directLimiter !== HyperliquidVenue.gatewayLimiter)
    #expect(OrderFlowExchange.hyperliquid.key == HyperliquidVenue.id)
    #expect(OrderFlowExchange.hyperliquid.displayName == HyperliquidVenue.displayName)
  }

  @Test("权重（官方表）：info 20、轻查询 2、candleSnapshot 20 + 每 60 根 1；预算每分钟 1000（官方 1200 留余量）")
  func weights() {
    #expect(HyperliquidVenue.weightPerMinute == 1000)
    #expect(HyperliquidVenue.Weight.info == 20 && HyperliquidVenue.Weight.light == 2)
    #expect(HyperliquidVenue.Weight.candles(0) == 20 && HyperliquidVenue.Weight.candles(60) == 21)
    #expect(HyperliquidVenue.Weight.candles(61) == 22 && HyperliquidVenue.Weight.candles(300) == 25)
    #expect(HyperliquidVenue.Weight.candles(5000) == 104)
  }

  @Test("代号：键里大写，出站译回原名（表里没有就原样）；只有 K 开头又没拉过表的才要先拉表")
  func coinNames() {
    let names = HyperliquidNames()
    #expect(HyperliquidVenue.key("kPEPE") == "hyperliquid/usd_m/KPEPE")
    #expect(HyperliquidVenue.coin("hyperliquid/usd_m/KPEPE", names: names) == "KPEPE")
    #expect(HyperliquidVenue.needsNames("hyperliquid/usd_m/KPEPE", names: names))
    #expect(!HyperliquidVenue.needsNames("hyperliquid/usd_m/BTC", names: names))
    names.record(["BTC", "kPEPE", "kSHIB"])
    #expect(HyperliquidVenue.coin("hyperliquid/usd_m/KPEPE", names: names) == "kPEPE")
    #expect(HyperliquidVenue.coin("hyperliquid/usd_m/kshib", names: names) == "kSHIB")
    #expect(HyperliquidVenue.coin("hyperliquid/usd_m/BTC", names: names) == "BTC")
    // 表拉过了、里面没有：不再拉，原样发（`KAS` 本来就是大写）。
    #expect(!HyperliquidVenue.needsNames("hyperliquid/usd_m/KAS", names: names))
    #expect(HyperliquidVenue.coin("hyperliquid/usd_m/KAS", names: names) == "KAS")
  }

  @Test("周期：12 档原生、6h ← 2h、1y ← 1M；全部原生档都有推送")
  func intervals() {
    let caps = HyperliquidProvider.capabilities
    #expect(Interval.allCases.filter { HyperliquidVenue.interval($0) != nil } ==
            [.m1, .m3, .m5, .m15, .m30, .h1, .h2, .h4, .h12, .d1, .w1, .mo1])
    #expect(HyperliquidVenue.interval(.mo1) == "1M" && HyperliquidVenue.interval(.h12) == "12h")
    #expect(caps.source(for: .h6) == .h2 && caps.source(for: .y1) == .mo1)
    #expect(Interval.allCases.allSatisfy(caps.supports))
    #expect(caps.liveKlineIntervals == caps.nativeIntervals)
    #expect(caps.aggregatedFrom.values.allSatisfy(caps.nativeIntervals.contains))
  }

  @Test("能力位：标记价、费率、持仓量（服务端）、整表行情都有；没有持仓量历史、衍生统计、五档；首屏 300、一页 5000")
  func capabilities() {
    let c = HyperliquidProvider.capabilities
    #expect(c.venue == "hyperliquid" && c.market == "usd_m" && !c.isSubstitute)
    #expect(c.hasTickerStream && c.hasMarkPrice && c.hasFunding && c.hasBulkTickers && c.hasOrderFlow)
    #expect(c.openInterestSource == "hyperliquid")
    #expect(!c.hasOpenInterestHistory && !c.hasOpenInterestArchive && !c.hasDerivativeMetrics && !c.hasMicrostructure)
    #expect(c.maxKlines == 5000 && c.initialKlines == 300 && c.maxTailBars == 5000)
    #expect(c.hasVolume && !c.hasSessionChange)
  }

  @Test("地址：直连 api.hyperliquid.xyz/info 与 /ws；网关打 kanpan-api 透传与中继；订单流的中继拿 kanpan-api 主机")
  func endpoints() throws {
    let direct = HyperliquidVenue.endpoints(policy: .direct, gateways: ["gw1.example", "gw2.example:8443"])
    #expect(direct.rest("info", host: direct.restHosts[0])?.absoluteString == "https://api.hyperliquid.xyz/info")
    #expect(direct.streams.map(\.absoluteString) == ["wss://api.hyperliquid.xyz/ws"])
    let gateway = HyperliquidVenue.endpoints(policy: .gateway, gateways: ["gw1.example", "gw2.example:8443"])
    #expect(gateway.restHosts == ["gw1.example", "gw2.example:8443"])
    #expect(gateway.rest("info", host: "gw2.example:8443")?.absoluteString
            == "https://gw2.example:8443/v1/market/raw/info?source=hyperliquid")
    #expect(gateway.streams.map(\.absoluteString) == ["wss://gw1.example/v1/market/ws/hyperliquid",
                                                      "wss://gw2.example:8443/v1/market/ws/hyperliquid"])
    let adapter = HyperliquidBookAdapter(books: [], gateways: ["api.example", "bad/host"])
    #expect(adapter.streamURLs.map(\.absoluteString) == ["wss://api.example/v1/market/ws/hyperliquid"])
    #expect(adapter.keepAlive == DepthKeepAlive(text: #"{"method":"ping"}"#, everyMs: 30_000))
    #expect(adapter.silenceMs == 60_000)
  }
}

@Suite("交易所通用件 · 按权重的限速")
struct VenueWeightLimiterTests {
  @Test("任意 60 秒里放行的权重不超过预算：花满了就等最早那笔出窗口；不额外错开")
  func budget() async throws {
    let pacer = StepPacer()
    let limiter = VenueRateLimiter(weightPerMinute: 100, pacer: pacer)
    for _ in 0..<5 { try await limiter.acquire(weight: 20) }
    #expect(await pacer.sleepLog().isEmpty)
    #expect(await limiter.spentWeight() == 100)
    try await limiter.acquire(weight: 20)
    #expect(await pacer.sleepLog() == [60_000])
    // 窗口滑过去了：头五笔出窗口，只剩刚放的那一笔。
    #expect(await limiter.spentWeight() == 20)
    // 还差 50 才够：等到够为止（这里是刚放的那笔出窗口）。
    try await limiter.acquire(weight: 70)
    try await limiter.acquire(weight: 30)
    #expect(await pacer.sleepLog() == [60_000, 60_000])
  }

  @Test("比整个预算还重的一笔：窗口空着就放，之后谁都得等它出窗口；不带权重的入口记 1")
  func oversizedAndDefault() async throws {
    let pacer = StepPacer()
    let limiter = VenueRateLimiter(weightPerMinute: 100, pacer: pacer)
    try await limiter.acquire(weight: 150)
    try await limiter.acquire()
    #expect(await pacer.sleepLog() == [60_000])
    #expect(await limiter.spentWeight() == 1)
  }

  @Test("按次数的那一把不受权重影响：照旧按间隔错开")
  func countModeUnchanged() async throws {
    let pacer = StepPacer()
    let limiter = VenueRateLimiter(perSecond: 10, pacer: pacer)
    try await limiter.acquire(weight: 500)
    try await limiter.acquire(weight: 500)
    #expect(await pacer.sleepLog() == [100])
  }
}

@Suite("Hyperliquid REST 线路与翻页")
struct HyperliquidRESTTests {
  @Test("首屏一发：POST /info，candleSnapshot 带原名、周期、起止；窗口恰好 300 根；直连打交易所")
  func firstScreen() async throws {
    let server = HL.answering { type, start in
      guard type == "candleSnapshot", let start else { return json("bad", status: 400) }
      let first = (start + 3_599_999) / 3_600_000 * 3_600_000
      return json(HL.candles(stride(from: first, through: HL.nowMs, by: 3_600_000).map { $0 }))
    }
    let p = HL.provider(server)
    let bars = try await p.klines(symbol: "hyperliquid/usd_m/BTC", interval: .h1, limit: 300)
    #expect(bars.count == 300)
    #expect(bars.last?.openTime == 1_791_417_600_000)
    #expect(zip(bars, bars.dropFirst()).allSatisfy { $1.openTime - $0.openTime == 3_600_000 })
    #expect(await server.urls() == ["https://api.hyperliquid.xyz/info"])
    let req = try #require(await server.reqs().first)
    #expect(req.coin == "BTC" && req.interval == "1h")
    #expect(req.endTime == HL.nowMs)
    #expect(req.startTime == HL.nowMs - 300 * 3_600_000 + 1)
    #expect(req.keys == ["coin", "interval", "startTime", "endTime"])
    // 首屏这一发在限速器上记 20 + ⌈300 / 60⌉ = 25 权重。
    #expect(await p.rest.limiter.spentWeight() == 25)
  }

  @Test("网关线路：打 /v1/market/raw/info?source=hyperliquid，正文与直连同形；主网关 5xx 换备用")
  func gatewayFallback() async throws {
    let server = InfoServer { url, _, _ in url.host == "gw1.example" ? json("{}", status: 502) : json("[]") }
    _ = try await HL.provider(server, policy: .gateway).klines(symbol: "hyperliquid/usd_m/ETH", interval: .m5, limit: 5)
    #expect(await server.urls() == ["https://gw1.example/v1/market/raw/info?source=hyperliquid",
                                    "https://gw2.example:8443/v1/market/raw/info?source=hyperliquid"])
    #expect(await server.types() == ["candleSnapshot", "candleSnapshot"])
  }

  @Test("聚出来的周期按源周期取：6h 取 2h、1y 取 1M")
  func aggregatedSource() async throws {
    let server = HL.answering { _, _ in json("[]") }
    let p = HL.provider(server)
    _ = try await p.klines(symbol: "hyperliquid/usd_m/BTC", interval: .h6, limit: 10)
    _ = try await p.klines(symbol: "hyperliquid/usd_m/BTC", interval: .y1, limit: 10)
    #expect(await server.reqs().map(\.interval) == ["2h", "1M"])
  }

  @Test("kPEPE：表还没拉过时先拉一次品种表，出站用原名；之后不再拉")
  func scaledCoinNeedsNames() async throws {
    let server = HL.answering { type, _ in json(type == "meta" ? HL.meta : "[]") }
    let p = HL.provider(server)
    _ = try await p.klines(symbol: "hyperliquid/usd_m/KPEPE", interval: .m1, limit: 10)
    _ = try await p.klines(symbol: "hyperliquid/usd_m/KPEPE", interval: .m1, limit: 10)
    #expect(await server.types() == ["meta", "candleSnapshot", "candleSnapshot"])
    #expect(await server.reqs().map(\.coin) == ["kPEPE", "kPEPE"])
  }

  @Test("补缺按起点往后取，历史按终点往前；整个窗口早于最近 5000 根的不发")
  func tailAndHistory() async throws {
    let server = HL.answering { _, _ in json("[]") }
    let p = HL.provider(server)
    _ = try await p.contiguousTail(symbol: "hyperliquid/usd_m/BTC", interval: .m1, from: HL.nowMs - 10 * 60_000)
    let tail = try #require(await server.reqs().first)
    #expect(tail.startTime == HL.nowMs - 10 * 60_000)
    #expect(tail.endTime == HL.nowMs)
    await #expect(throws: FeedError.self) {
      _ = try await p.contiguousTail(symbol: "hyperliquid/usd_m/BTC", interval: .m1, from: HL.nowMs - 6000 * 60_000)
    }
    // 1m 的最近 5000 根之前：交易所没有，不发请求，直接到头。
    let old = try await p.history(symbol: "hyperliquid/usd_m/BTC", interval: .m1, pages: 2,
                                  before: HL.nowMs - 6000 * 60_000)
    #expect(old.isEmpty)
    #expect(await server.count() == 1)
  }

  @Test("错误体是纯文本时原样带上；4xx 不换主机")
  func plainTextError() async throws {
    let server = InfoServer { _, _, _ in json("Failed to deserialize the JSON body into the target type", status: 422) }
    var thrown: UpstreamError?
    do { _ = try await HL.provider(server, policy: .gateway).instruments() } catch let e as UpstreamError { thrown = e }
    #expect(thrown?.status == 422 && thrown?.msg == "Failed to deserialize the JSON body into the target type")
    #expect(await server.count() == 1)
  }
}

@Suite("Hyperliquid 推送协议")
struct HyperliquidWireTests {
  private func wire(_ names: HyperliquidNames = HyperliquidNames(), now: Int64 = HL.nowMs) -> HyperliquidWire {
    HyperliquidWire(names: names, clock: { Date(timeIntervalSince1970: Double(now) / 1000) })
  }

  @Test("订阅：K 线 → candle（聚出来的周期丢掉）、成交 → trades、行情与标记价合成一个 activeAssetCtx；主动成交与盘口没有")
  func subs() {
    let names = HyperliquidNames()
    names.record(["BTC", "kPEPE"])
    let subs = wire(names).subs([
      .kline(symbol: "hyperliquid/usd_m/BTC", interval: .h1), .kline(symbol: "hyperliquid/usd_m/BTC", interval: .h6),
      .trade(symbol: "hyperliquid/usd_m/KPEPE"), .ticker(symbol: "hyperliquid/usd_m/BTC"),
      .markPrice(symbol: "hyperliquid/usd_m/BTC"), .aggTrade(symbol: "hyperliquid/usd_m/BTC"),
      .depth(symbol: "hyperliquid/usd_m/BTC"),
    ])
    #expect(subs.sorted() == [.assetCtx("BTC"), .candle("BTC", "1h"), .trades("kPEPE")])
  }

  @Test("控制帧：一帧一个订阅，字段与中继白名单一一对上；保活 20 秒一句 ping；控制帧间隔 100ms")
  func controlFrames() throws {
    let w = wire()
    #expect(w.nextBatch([.trades("ETH"), .candle("BTC", "1m"), .assetCtx("BTC")]) == [.assetCtx("BTC")])
    #expect(try w.control(.subscribe, [.candle("BTC", "1m")])
            == #"{"method":"subscribe","subscription":{"coin":"BTC","interval":"1m","type":"candle"}}"#)
    #expect(try w.control(.unsubscribe, [.assetCtx("kPEPE")])
            == #"{"method":"unsubscribe","subscription":{"coin":"kPEPE","type":"activeAssetCtx"}}"#)
    #expect(try w.control(.subscribe, [.trades("BTC")])
            == #"{"method":"subscribe","subscription":{"coin":"BTC","type":"trades"}}"#)
    #expect(w.keepAlive == VenueKeepAlive(text: #"{"method":"ping"}"#, everyMs: 20_000))
    #expect(w.controlGapMs == 100 && w.label(.candle("BTC", "1m")) == "candle BTC 1m")
  }

  @Test("K 线推送：一根一个对象（也认数组），出未收盘的末根，确认那个订阅")
  func candle() throws {
    let text = #"{"channel":"candle","data":{"t":1791417600000,"T":1791421199999,"s":"kPEPE","i":"1h","o":"0.004","c":"0.00403","h":"0.0041","l":"0.0039","v":"1200000.0","n":88}}"#
    let frame = wire().decode(text)
    #expect(frame.confirmed == [.candle("kPEPE", "1h")])
    guard case .kline(let k)? = frame.payloads.first else { Issue.record("应该是一根 K 线"); return }
    #expect(k.symbol == "hyperliquid/usd_m/KPEPE" && k.interval == "1h" && k.openTime == 1_791_417_600_000 && !k.closed)
    #expect(k.bar.close == 0.00403 && k.bar.volume == 1_200_000)
    let array = text.replacingOccurrences(of: #""data":{"#, with: #""data":[{"#).replacingOccurrences(of: "}}", with: "}]}")
    #expect(wire().decode(array).payloads.count == 1)
  }

  @Test("activeAssetCtx：一帧出一条行情和一条标记价（一小时费率、下一个整点、指数价取 oraclePx）")
  func assetCtx() throws {
    let text = #"{"channel":"activeAssetCtx","data":{"coin":"BTC","ctx":{"funding":"0.0000125","openInterest":"26085.3","prevDayPx":"80000.0","dayNtlVlm":"3369196034.6","premium":"0.0003","oraclePx":"82218.0","markPx":"82266.0","midPx":"82256.5","impactPxs":["82256.0","82257.0"],"dayBaseVlm":"41652.2"}}}"#
    let frame = wire().decode(text)
    #expect(frame.confirmed == [.assetCtx("BTC")] && frame.payloads.count == 2)
    guard case .ticker(let t) = frame.payloads[0], case .markPrice(let symbol, let price, let tick) = frame.payloads[1] else {
      Issue.record("应该是行情 + 标记价"); return
    }
    #expect(t.symbol == "hyperliquid/usd_m/BTC" && t.last == 82256.5 && t.markPrice == 82266)
    #expect(symbol == "hyperliquid/usd_m/BTC" && price == 82266)
    #expect(tick == MarkPriceTick(timeMs: HL.nowMs, fundingRate: 0.0000125, nextFundingTimeMs: 1_791_421_200_000,
                                  indexPrice: 82218))
  }

  @Test("成交：订上之后第一帧里早于订阅发出时刻的是回放，不收；之后照收；新连接重新记")
  func tradesReplay() throws {
    let w = wire()
    func trades(_ rows: [(Int64, String)]) -> String {
      #"{"channel":"trades","data":["# + rows.enumerated().map { i, r in
        #"{"coin":"BTC","side":"\#(r.1)","px":"82625.0","sz":"0.5","time":\#(r.0),"hash":"0x0","tid":\#(i + 1),"users":["0xa","0xb"]}"#
      }.joined(separator: ",") + "]}"
    }
    _ = try w.control(.subscribe, [.trades("BTC")])
    let first = w.decode(trades([(HL.nowMs - 60_000, "B"), (HL.nowMs - 1, "A"), (HL.nowMs + 5, "B")]))
    #expect(first.confirmed == [.trades("BTC")])
    #expect(first.payloads.count == 1)
    guard case .trade(let t)? = first.payloads.first else { Issue.record("应该是一笔成交"); return }
    #expect(t.symbol == "hyperliquid/usd_m/BTC" && t.timeMs == HL.nowMs + 5 && t.tradeID == 3 && t.qty == 0.5)
    // 第二帧起不再判回放（时间再旧也收：那是交易所的事）。
    #expect(w.decode(trades([(HL.nowMs - 60_000, "B")])).payloads.count == 1)
    // 新连接：上一条连接上等着的回放作废；这条连接上重新订再重新记。
    _ = try w.control(.subscribe, [.trades("BTC")])
    _ = try w.openingFrames()
    #expect(w.decode(trades([(HL.nowMs - 60_000, "B")])).payloads.count == 1)
    // 坏数整帧不收。
    #expect(w.decode(trades([(HL.nowMs, "B")]).replacingOccurrences(of: "82625.0", with: "nan")).payloads.isEmpty)
  }

  @Test("回执确认订阅；pong 是空帧；报错点名那个订阅，「已经订着」当生效")
  func controlReplies() {
    let w = wire()
    #expect(w.decode(#"{"channel":"subscriptionResponse","data":{"method":"subscribe","subscription":{"type":"candle","coin":"BTC","interval":"1m"}}}"#).confirmed
            == [.candle("BTC", "1m")])
    #expect(w.decode(#"{"channel":"subscriptionResponse","data":{"method":"unsubscribe","subscription":{"type":"trades","coin":"BTC"}}}"#).confirmed.isEmpty)
    let pong = w.decode(#"{"channel":"pong"}"#)
    #expect(pong.payloads.isEmpty && pong.confirmed.isEmpty && pong.error == nil)
    let bad = w.decode(#"{"channel":"error","data":"Invalid subscription {\"type\":\"candle\",\"coin\":\"NOPE\",\"interval\":\"1m\"}"}"#)
    #expect(bad.error?.hasPrefix("Invalid subscription") == true && bad.rejected == [.candle("NOPE", "1m")])
    let vague = w.decode(#"{"channel":"error","data":"Websocket error"}"#)
    #expect(vague.error == "Websocket error" && vague.rejected == nil)
    let again = w.decode(#"{"channel":"error","data":"Already subscribed: {\"type\":\"trades\",\"coin\":\"BTC\"}"}"#)
    #expect(again.error == nil && again.confirmed == [.trades("BTC")])
  }
}

@Suite("Hyperliquid 推送连接", .timeLimit(.minutes(1)))
struct HyperliquidStreamTests {
  @Test("一条连接多订阅：一帧一个订阅；行情帧翻成统一报文；按点 ping；被点名拒的不重连")
  func stream() async throws {
    let bench = GateSocketBench()
    let names = HyperliquidNames()
    names.record(["BTC", "kPEPE"])
    let server = HL.answering { _, _ in json("[]") }
    let provider = HyperliquidProvider(policy: .direct, gateways: [], transport: InfoTransport(server: server),
                                       sockets: bench, limiter: VenueRateLimiter(weightPerMinute: 1_000_000),
                                       clock: { HL.now }, names: names)
    let ws = VenueStream(wire: HyperliquidWire(names: names, clock: { HL.now }), urls: provider.endpoints.streams,
                         factory: bench, pacer: FastPacer(scale: 0.001), silenceMs: 600_000, transportSilenceMs: 1e12)
    let stream = await ws.start(topics: [.kline(symbol: "hyperliquid/usd_m/KPEPE", interval: .m1),
                                         .ticker(symbol: "hyperliquid/usd_m/BTC"),
                                         .markPrice(symbol: "hyperliquid/usd_m/BTC")])
    #expect(await waitUntil(5) { await bench.socket(1) != nil })
    let socket = try #require(await bench.socket(1))
    #expect(socket.url.absoluteString == "wss://api.hyperliquid.xyz/ws")
    #expect(await waitUntil(5) { await socket.sent.filter { $0.contains("subscribe") }.count == 2 })
    let subs = await socket.sent.filter { $0.contains("subscribe") }
    #expect(subs == [#"{"method":"subscribe","subscription":{"coin":"BTC","type":"activeAssetCtx"}}"#,
                     #"{"method":"subscribe","subscription":{"coin":"kPEPE","interval":"1m","type":"candle"}}"#])
    // 20 秒 × 0.001 = 真实 20ms 一句 ping。
    #expect(await waitUntil(5) { await socket.sent.filter { $0 == #"{"method":"ping"}"# }.count >= 2 })
    await socket.push(.text(#"{"channel":"candle","data":{"t":1791419400000,"T":1791419459999,"s":"kPEPE","i":"1m","o":"1","c":"1","h":"1","l":"1","v":"1","n":1}}"#))
    var got: KlineEvent?
    for await event in stream { if case .payload(.kline(let k)) = event { got = k; break } }
    #expect(got?.symbol == "hyperliquid/usd_m/KPEPE")
    await ws.replace(topics: [.kline(symbol: "hyperliquid/usd_m/KPEPE", interval: .m1),
                              .trade(symbol: "hyperliquid/usd_m/NOPE")])
    #expect(await waitUntil(5) { await socket.sent.contains { $0.contains(#""coin":"NOPE""#) } })
    await socket.push(.text(#"{"channel":"error","data":"Invalid subscription {\"type\":\"trades\",\"coin\":\"NOPE\"}"}"#))
    #expect(await waitUntil(5) { await ws.topicErrors["trades NOPE"] != nil })
    #expect(await socket.sent.contains(#"{"method":"unsubscribe","subscription":{"coin":"BTC","type":"activeAssetCtx"}}"#))
    #expect(await staysFalse(for: 0.3) { await bench.connects >= 2 })
    await ws.stop()
  }
}

@Suite("订单流 · 千枚计价的小写 k")
struct HyperliquidScaledBaseTests {
  @Test("kPEPE → PEPE × 1000；大写 K 开头的是币名本身；小写 k 后面不是大写币名的不认")
  func normalize() {
    for (raw, base, scale) in [("kPEPE", "PEPE", 1000.0), ("kSHIB", "SHIB", 1000), ("kBONK", "BONK", 1000),
                               ("KAS", "KAS", 1), ("KAITO", "KAITO", 1), ("kas", "KAS", 1), ("k", "K", 1),
                               ("k1000", "K1000", 1), ("1000PEPE", "PEPE", 1000)] {
      let n = OrderFlowBase.normalize(raw)
      #expect(n.base == base && n.scale == scale, "\(raw)")
    }
  }
}
