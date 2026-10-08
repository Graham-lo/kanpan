import Foundation
import Testing
@testable import KanpanNetwork
import KanpanNetworkTestSupport
import KanpanCore

// 交叉测试（2026-10-08）：四家同一只币并存、直连 / 网关两条线路。
//
// - 四家各给各的提供者，能力位互不串；四家的推送帧喂给别家的协议一条都解不出来（按键分发不串）。
// - 订单流按 base 币找簿：`KPEPE` / `kPEPE` / `1000PEPE` 三种写法都归 PEPE × 1000，`KAITO` 不拆。
// - 同一提供者在两条线路下的 REST 主机与顺序、推送地址、限速器实例；网关档任何请求都不打交易所域名。

private let gateways = ["gw1.example", "gw2.example:8443"]
private let apiHosts = ["api1.example", "api2.example"]
private func route(_ policy: MarketRoutePolicy) -> MarketRoute {
  MarketRoute(policy: policy, endpoints: MarketEndpoints(gateways: gateways, api: apiHosts))
}
/// 交易所自己的域名（网关档一个都不许出现）。
private let exchangeDomains = ["okx.com", "bybit.com", "bytick.com", "hyperliquid.xyz", "coinbase.com", "binance.com"]
private func isExchangeHost(_ host: String?) -> Bool {
  guard let host else { return false }
  return exchangeDomains.contains { host == $0 || host.hasSuffix("." + $0) }
}

extension StressVenueSerial {
  @Suite("交叉 · 四家同一只币并存")
  struct VenueCrossTests {
    @Test("RouteResolver：binance / okx / bybit / hyperliquid 的 BTC 各给各家的提供者，能力位各是各的，两条线路都一样")
    func fourVenuesOneCoin() {
      let cases: [(key: String, venue: String, caps: ProviderCapabilities)] = [
        ("binance/usd_m/BTCUSDT", "binance", RouteResolver(route: route(.direct)).provider(venue: "binance").capabilities),
        ("okx/usd_m/BTCUSDT", "okx", OKXProvider.capabilities),
        ("bybit/usd_m/BTCUSDT", "bybit", BybitProvider.capabilities),
        ("hyperliquid/usd_m/BTC", "hyperliquid", HyperliquidProvider.capabilities),
      ]
      for policy in [MarketRoutePolicy.direct, .gateway] {
        let resolver = RouteResolver(route: route(policy))
        var seen: [String] = []
        for c in cases {
          let p = resolver.provider(forSymbol: c.key)
          seen.append(p.capabilities.venue)
          #expect(p.capabilities.venue == c.venue && p.capabilities.upstream == c.venue, "\(c.key) \(policy)")
          #expect(!p.capabilities.isSubstitute && p.capabilities.snapshotNamespace == nil)
          if c.venue != "binance" { #expect(p.capabilities == c.caps, "\(c.key) \(policy) 的能力位串了") }
          #expect(InstrumentID.isSyncKey(c.key))
        }
        #expect(Set(seen).count == 4)
      }
      // 能力位彼此确实不同（不是同一份抄了四遍）：Hyperliquid 没有 6h 原生、计价是 USDC、一页 5000 根。
      #expect(!HyperliquidProvider.capabilities.nativeIntervals.contains(.h6))
      #expect(BybitProvider.capabilities.nativeIntervals.contains(.h6) && OKXProvider.capabilities.nativeIntervals.contains(.h6))
      #expect(HyperliquidProvider.capabilities.quoteAssets == ["USDC"] && OKXProvider.capabilities.quoteAssets == ["USDT"])
      #expect(Set([OKXProvider.capabilities.maxKlines, BybitProvider.capabilities.maxKlines,
                   HyperliquidProvider.capabilities.maxKlines]).count == 3)
      #expect(HyperliquidProvider.capabilities.hasOpenInterestHistory == false && OKXProvider.capabilities.hasOpenInterestHistory)
    }

    @Test("四家的推送帧喂给别家的协议：一条都解不出来；喂给本家的只落在本家的键上")
    func wiresDoNotCrossDecode() {
      OKXVenue.contractValues.set(["BTC-USDT-SWAP": 0.01])
      let okxFrames = [
        #"{"arg":{"channel":"tickers","instId":"BTC-USDT-SWAP"},"data":[{"instId":"BTC-USDT-SWAP","last":"65000","open24h":"64000","ts":"1700000000000"}]}"#,
        #"{"arg":{"channel":"trades","instId":"BTC-USDT-SWAP"},"data":[{"px":"65000","sz":"1","side":"buy","ts":"1700000000000"}]}"#,
        #"{"arg":{"channel":"candle1m","instId":"BTC-USDT-SWAP"},"data":[["1700000000000","1","2","0.5","1.5","10","10","15","0"]]}"#,
      ]
      let bybitFrames = Templates.bybitPush.prefix(4).map { $0 }
      let hlFrames = Templates.hlPush.prefix(4).map { $0 }
      let names = HyperliquidNames()
      names.record(["BTC", "kPEPE"])
      let decoders: [(venue: String, decode: (String) -> [StreamPayload])] = [
        ("okx", { OKXWire(endpoint: .public).decode($0).payloads + OKXWire(endpoint: .business).decode($0).payloads }),
        ("bybit", { BybitWire().decode($0).payloads }),
        ("hyperliquid", { HyperliquidWire(names: names, clock: { Date(timeIntervalSince1970: 1_700_000_000) }).decode($0).payloads }),
        ("coinbase", { CoinbaseWire().decode($0).payloads }),
      ]
      let frames: [(venue: String, texts: [String])] = [("okx", okxFrames), ("bybit", bybitFrames), ("hyperliquid", hlFrames)]
      for (owner, texts) in frames {
        for text in texts {
          for d in decoders {
            let out = d.decode(text)
            if d.venue == owner {
              #expect(!out.isEmpty, "\(owner) 自己的帧解不出来：\(text.prefix(60))")
              checkPayloads(out, venue: owner, text)
            } else {
              #expect(out.isEmpty, "\(d.venue) 把 \(owner) 的帧解出来了：\(text.prefix(60))")
            }
          }
        }
      }
    }

    @Test("订单流按 base 找簿：KPEPE / kPEPE / 1000PEPE 都归 PEPE × 1000；KAITO、KAS 是币名本身不拆", .timeLimit(.minutes(1)))
    func orderFlowBases() async {
      // 品种信息还没到、只能拿键拼 base 时是大写的 `KPEPE`：Hyperliquid 拉到过品种表（原名 `kPEPE`）就认得。
      HyperliquidNames().record(["BTC", "kPEPE", "KAITO", "kAITO", "KAS"])
      #expect(OrderFlowBase.normalize("kPEPE") == ("PEPE", 1000))
      #expect(OrderFlowBase.normalize("1000PEPE") == ("PEPE", 1000))
      #expect(OrderFlowBase.normalize("KPEPE") == ("PEPE", 1000))
      #expect(OrderFlowBase.normalize("KAITO") == ("KAITO", 1))
      #expect(OrderFlowBase.normalize("KAS") == ("KAS", 1))
      #expect(OrderFlowBase.normalize("KNC") == ("KNC", 1))
      // 先登记了千枚那只、后来才见到大写原名：大写原名赢，之前那条不再生效。
      OrderFlowBase.registerOriginalNames(["kZZTOP"])
      #expect(OrderFlowBase.normalize("KZZTOP") == ("ZZTOP", 1000))
      OrderFlowBase.registerOriginalNames(["KZZTOP"])
      #expect(OrderFlowBase.normalize("KZZTOP") == ("KZZTOP", 1))

      // 整条 books(base:)：服务端品种表不通，走保底簿；三种写法拿到同一组簿、同一个缩放。
      let down = FakeServer { _ in json("{}", status: 503) }
      let catalog = OrderFlowCatalog(route: route(.gateway), sockets: GateSocketBench(), http: FakeTransport(down),
                                     cache: OrderFlowCatalogCache(file: nil))
      let a = await catalog.books(base: "KPEPE", nowMs: 1_700_000_000_000)
      let b = await catalog.books(base: "kPEPE", nowMs: 1_700_000_000_000)
      let c = await catalog.books(base: "1000PEPE", nowMs: 1_700_000_000_000)
      for books in [a, b, c] {
        #expect(books.base == "PEPE" && books.chartScale == 1000)
        #expect(!books.books.isEmpty)
      }
      #expect(a.books.map(\.id) == b.books.map(\.id))
      // 问服务端的那一句：按折算后的 PEPE 问，不按 KPEPE。
      #expect(await down.urls().allSatisfy { URLComponents(url: $0, resolvingAgainstBaseURL: false)?.queryItems?.first?.value == "PEPE" })
    }
  }
}

// ---------------------------------------------------------------- 直连 / 网关两条线路

/// 各家的假上游：按路径回最小的合法报文。`api1.example` 一律 503（网关主挂了），逼出「主 → 备」。
private func upstream(_ url: URL) -> HTTPReply {
  if url.host == "api1.example" { return json("{}", status: 503) }
  let path = url.path
  if path.hasSuffix("market/candles") || path.hasSuffix("history-candles") {
    return json(#"{"code":"0","data":[["1700000000000","1","2","0.5","1.5","10","10","15","1"]]}"#)
  }
  if path.hasSuffix("public/instruments") {
    return json(#"{"code":"0","data":[{"instId":"BTC-USDT-SWAP","instType":"SWAP","ctType":"linear","settleCcy":"USDT","ctVal":"0.01","ctValCcy":"BTC","tickSz":"0.1","lotSz":"0.01","state":"live"}]}"#)
  }
  if path.hasSuffix("v5/market/kline") {
    return json(#"{"retCode":0,"retMsg":"OK","result":{"list":[["1700000000000","1","2","0.5","1.5","10","15"]]}}"#)
  }
  if path.hasSuffix("instruments-info") {
    return json(#"{"retCode":0,"retMsg":"OK","result":{"list":[{"symbol":"BTCUSDT","contractType":"LinearPerpetual","status":"Trading","baseCoin":"BTC","quoteCoin":"USDT","priceFilter":{"tickSize":"0.1"},"lotSizeFilter":{"qtyStep":"0.001"}}]}}"#)
  }
  if path.hasSuffix("/candles") {
    return json(#"{"candles":[{"start":"1700000000","low":"0.5","high":"2","open":"1","close":"1.5","volume":"1"}]}"#)
  }
  return json("{}", status: 404)
}

/// 记 URL 的 POST 传输（Hyperliquid）。
private actor PostLog {
  var urls: [URL] = []
  func add(_ url: URL) { urls.append(url) }
}
private struct RecordingPost: HTTPTransport {
  let log = PostLog()
  func get(_ url: URL, timeout: TimeInterval) async throws -> HTTPReply { await log.add(url); return json("{}", status: 404) }
  func post(_ url: URL, json body: Data, timeout: TimeInterval) async throws -> HTTPReply {
    await log.add(url)
    if url.host == "api1.example" { return json("{}", status: 503) }
    let text = String(decoding: body, as: UTF8.self)
    if text.contains("candleSnapshot") {
      return json(#"[{"t":1700000000000,"T":1700000059999,"s":"BTC","i":"1m","o":"1","c":"1.5","h":"2","l":"0.5","v":"1"}]"#)
    }
    return json(#"{"universe":[{"name":"BTC","szDecimals":5},{"name":"kPEPE","szDecimals":0}]}"#)
  }
}

extension StressVenueSerial {
  @Suite("交叉 · 直连 / 网关两条线路", .timeLimit(.minutes(1)))
  struct VenueRouteCrossTests {
    private static func fast() -> VenueRateLimiter { VenueRateLimiter(perSecond: 1_000_000, pacer: FastPacer()) }

    /// 一家在一条线路下打过的 REST 地址。
    private func restHits(_ venue: String, _ policy: MarketRoutePolicy) async throws -> [URL] {
      let r = route(policy)
      switch venue {
      case "okx":
        let server = FakeServer { upstream($0) }
        let p = OKXProvider(route: r, transport: FakeTransport(server), limiter: Self.fast(), clock: { Date(timeIntervalSince1970: 1_700_000_100) })
        _ = try await p.instruments()
        _ = try await p.klines(symbol: "okx/usd_m/BTCUSDT", interval: .m1, limit: 5, startTime: nil, endTime: nil)
        return await server.urls()
      case "bybit":
        let server = FakeServer { upstream($0) }
        let p = BybitProvider(route: r, transport: FakeTransport(server), limiter: Self.fast(), clock: { Date(timeIntervalSince1970: 1_700_000_100) })
        _ = try await p.instruments()
        _ = try await p.klines(symbol: "bybit/usd_m/BTCUSDT", interval: .m1, limit: 5, startTime: nil, endTime: nil)
        return await server.urls()
      case "coinbase":
        let server = FakeServer { upstream($0) }
        let p = CoinbaseProvider(route: r, transport: FakeTransport(server), limiter: Self.fast(), clock: { Date(timeIntervalSince1970: 1_700_000_100) })
        _ = try await p.klines(symbol: "coinbase/spot/BTC-USD", interval: .m1, limit: 5, startTime: nil, endTime: nil)
        return await server.urls()
      default:
        let transport = RecordingPost()
        let p = HyperliquidProvider(endpoints: HyperliquidVenue.endpoints(r), transport: transport, sockets: GateSocketBench(),
                                    limiter: VenueRateLimiter(weightPerMinute: 1_000_000, pacer: FastPacer()), log: .silent,
                                    clock: { Date(timeIntervalSince1970: 1_700_000_100) }, names: HyperliquidNames())
        _ = try await p.klines(symbol: "hyperliquid/usd_m/KPEPE", interval: .m1, limit: 5, startTime: nil, endTime: nil)
        return await transport.log.urls
      }
    }

    @Test("REST：直连只打交易所自己那台；网关只打 kanpan-api（主 503 换备）、/v1/market/raw/ 透传、source 排第一，一个交易所域名都不碰",
          arguments: ["okx", "bybit", "hyperliquid", "coinbase"])
    func restRoutes(_ venue: String) async throws {
      let direct = try await restHits(venue, .direct)
      #expect(!direct.isEmpty)
      #expect(direct.allSatisfy { isExchangeHost($0.host) }, "\(venue) 直连打到了别处：\(direct)")
      #expect(Set(direct.compactMap(\.host)).count == 1)
      #expect(direct.allSatisfy { !$0.path.hasPrefix("/v1/") })

      let gateway = try await restHits(venue, .gateway)
      #expect(!gateway.isEmpty)
      #expect(!gateway.contains { isExchangeHost($0.host) }, "\(venue) 网关档打了交易所域名：\(gateway)")
      #expect(gateway.allSatisfy { apiHosts.contains($0.host ?? "") })
      #expect(gateway.allSatisfy { $0.path.hasPrefix(VenueEndpoints.rawPrefix) })
      #expect(gateway.allSatisfy { ($0.query ?? "").hasPrefix("source=\(venue)") })
      // 主在前：每一笔都先问 api1，503 了才问 api2。
      let hosts = gateway.compactMap(\.host)
      #expect(hosts.enumerated().allSatisfy { $0.element == ($0.offset % 2 == 0 ? "api1.example" : "api2.example") }, "\(hosts)")
    }

    @Test("推送：直连连交易所自己的 wss；网关连网关表上的中继 / hub（主在前、端口照拼）；巡检握手按同一张表")
    func streamRoutes() async {
      func check(_ venue: String, direct: [URL], gateway: [URL]) {
        #expect(!direct.isEmpty && direct.allSatisfy { isExchangeHost($0.host) }, "\(venue) 直连推送 \(direct)")
        #expect(gateway.count == 2, "\(venue) 网关推送 \(gateway)")
        #expect(gateway.map(\.host) == ["gw1.example", "gw2.example"] && gateway[1].port == 8443)
        #expect(!gateway.contains { isExchangeHost($0.host) })
        #expect(gateway.allSatisfy { $0.path.hasPrefix("/v1/market/") })
      }
      for endpoint in OKXVenue.Endpoint.allCases {
        check("okx \(endpoint)", direct: OKXVenue.streams(endpoint, route: route(.direct)),
              gateway: OKXVenue.streams(endpoint, route: route(.gateway)))
      }
      check("bybit", direct: BybitProvider(route: route(.direct)).streamURLs, gateway: BybitProvider(route: route(.gateway)).streamURLs)
      check("hyperliquid", direct: HyperliquidVenue.endpoints(route(.direct)).streams,
            gateway: HyperliquidVenue.endpoints(route(.gateway)).streams)
      check("coinbase", direct: CoinbaseVenue.endpoints(route(.direct)).streams,
            gateway: CoinbaseVenue.endpoints(route(.gateway)).streams)

      // 巡检：网关档第一条握手就是网关主，不是交易所。
      for policy in [MarketRoutePolicy.direct, .gateway] {
        let bench = GateSocketBench()
        let providers: [any MarketProvider] = [
          OKXProvider(route: route(policy), sockets: bench), BybitProvider(route: route(policy), sockets: bench),
          HyperliquidProvider(route: route(policy), sockets: bench), CoinbaseProvider(route: route(policy), sockets: bench),
        ]
        for p in providers { _ = await p.probeStream(symbol: p.capabilities.venue, interval: .m1) }
        let urls = await bench.sockets.map(\.url)
        #expect(urls.count == 4)
        if policy == .gateway {
          #expect(urls.allSatisfy { $0.host == "gw1.example" }, "\(urls)")
        } else {
          #expect(urls.allSatisfy { isExchangeHost($0.host) }, "\(urls)")
        }
      }
    }

    /// 原来 Bybit、Coinbase 两条线路共用一把：网关线路上的请求替直连排队（花的根本不是同一个出口 IP 的额度），
    /// 违反接入指南第 6 节「直连与网关是两把」。
    @Test("限速器：每家直连、网关各一把且不同；同一条线路上建几个提供者都是同一把；订单流的品种表与连接随同一条线路")
    func limitersPerRoute() {
      func limiter(_ p: any MarketProvider) -> VenueRateLimiter? {
        switch p {
        case let x as OKXProvider: x.rest.limiter
        case let x as BybitProvider: x.rest.limiter
        case let x as HyperliquidProvider: x.rest.limiter
        case let x as CoinbaseProvider: x.rest.limiter
        default: nil
        }
      }
      for venue in ["okx", "bybit", "hyperliquid", "coinbase"] {
        let resolverD = RouteResolver(route: route(.direct)), resolverG = RouteResolver(route: route(.gateway))
        let d1 = resolverD.provider(venue: venue), d2 = resolverD.provider(venue: venue)
        let g1 = resolverG.provider(venue: venue), g2 = resolverG.provider(venue: venue)
        guard let ld1 = limiter(d1), let ld2 = limiter(d2), let lg1 = limiter(g1), let lg2 = limiter(g2) else {
          Issue.record("\(venue) 拿不到限速器"); continue
        }
        #expect(ld1 === ld2, "\(venue) 直连两个提供者不是同一把")
        #expect(lg1 === lg2, "\(venue) 网关两个提供者不是同一把")
        #expect(ld1 !== lg1, "\(venue) 直连与网关共用了一把")
        for (p, r) in [(d1, route(.direct)), (g1, route(.gateway))] {
          #expect((p as? any OrderFlowSourcing)?.orderFlowCatalog.route == r, "\(venue) 订单流没跟线路走")
        }
      }
    }

    /// 已知例外：Coinbase 现货的 `level2` 恒走直连（kanpan-api 的 Coinbase hub 不收 level2，`CoinbaseLevel2Adapter`
    /// 注释写明）。要让网关档也不碰 coinbase.com，得先在服务端给 level2 开中继——这里钉住现状，别的四家一条都不许漏。
    @Test("网关档的订单流：除了 Coinbase level2（服务端没有中继、恒走直连），其余连接一条都不连交易所域名")
    func orderFlowGatewayNoExchange() {
      let catalog = OrderFlowCatalog(route: route(.gateway), sockets: GateSocketBench(),
                                     http: FakeTransport(FakeServer { _ in json("{}", status: 503) }),
                                     cache: OrderFlowCatalogCache(file: nil))
      let books = OrderFlowCatalog.fallback(viewedBase: "BTC", base: "BTC", chartScale: 1)
      let adapters = catalog.adapters(books)
      #expect(!adapters.isEmpty)
      var direct: [String] = []
      for a in adapters {
        #expect(!a.streamURLs.isEmpty, "\(a.name) 没有地址")
        if a.streamURLs.contains(where: { isExchangeHost($0.host) }) { direct.append(a.name) }
      }
      #expect(direct.allSatisfy { $0.hasPrefix(CoinbaseVenue.displayName) }, "网关档连了交易所：\(direct)")
      #expect(adapters.count > direct.count)
    }
  }
}
