import Foundation
import Testing
@testable import KanpanNetwork
import KanpanNetworkTestSupport
import KanpanCore

/// 主力订单流的接入：一只币有哪几本簿（品种表 / 保底）、怎么分连接、各家的帧怎么解、快照从哪儿拿、
/// 价格口径怎么换（1000PEPE），以及连接客户端的重连与保活。
@Suite("主力订单流 · 深度适配器")
struct OrderFlowAdapterTests {
  static let gateways = ["gw-a.example", "gw-b.example:8443"]
  static let hosts = BinanceHosts()

  /// `api` 缺省时跟生产一样只有第一台（主机）：备用机跑 metrics 模式，订单流那几条它回 404。
  static func route(_ policy: MarketRoutePolicy, api: [String]? = nil) -> MarketRoute {
    MarketRoute(policy: policy, endpoints: MarketEndpoints(gateways: gateways, api: api))
  }

  static func book(_ exchange: String, _ product: OrderFlowProduct, _ instrument: String,
                   _ notional: OrderFlowNotional = .linear(multiplier: 1), factor: Double = 1) -> DepthBook {
    DepthBook(venue: OrderFlowCatalog.venue(exchange: exchange, product: product, instrument: instrument, notional: notional),
              priceFactor: factor)
  }

  static let umPerp = book("binance", .usdtPerp, "BTCUSDT")
  static let umQuarter = book("binance", .delivery, "BTCUSDT_260925")
  static let cmPerp = book("binance", .coinPerp, "BTCUSD_PERP", .inverse(contractUsd: 100))
  static let cmQuarter = book("binance", .delivery, "BTCUSD_260925", .inverse(contractUsd: 100))
  static let spot = book("binance", .spot, "BTCUSDT")

  static func binance(_ market: BinanceDepthAdapter.Market, _ books: [DepthBook], _ policy: MarketRoutePolicy,
                      server: FakeServer = FakeServer { _ in json("{}") },
                      deck: ReplayDeck = ReplayDeck([.hang]), api: [String]? = nil) -> BinanceDepthAdapter {
    BinanceDepthAdapter(market: market, books: books, hosts: hosts, route: route(policy, api: api),
                        sockets: ReplayFactory(deck: deck, pacer: FastPacer()), http: FakeTransport(server))
  }

  // ---------------------------------------------------------------- 币安

  @Test("币安 U 本位：一条组合流带永续与交割，按 s 分到各自的簿，带 U/u/pu")
  func binanceDelta() {
    let a = Self.binance(.um, [Self.umPerp, Self.umQuarter], .direct)
    let text = #"{"stream":"btcusdt@depth@100ms","data":{"e":"depthUpdate","E":1700000000123,"T":1700000000120,"s":"BTCUSDT","U":100,"u":105,"pu":99,"b":[["78450.1","3.5"],["78449.0","0"]],"a":[["78460.0","1.25"]]}}"#
    let delta = BookDelta(firstUpdateID: 100, finalUpdateID: 105, previousFinalUpdateID: 99,
                          bids: [BookLevel(price: 78450.1, quantity: 3.5), BookLevel(price: 78449, quantity: 0)],
                          asks: [BookLevel(price: 78460, quantity: 1.25)], eventTimeMs: 1700000000123)
    #expect(a.decode(text) == [VenueMessage(Self.umPerp.id, .delta(delta))])
    let quarter = text.replacingOccurrences(of: "\"s\":\"BTCUSDT\"", with: "\"s\":\"BTCUSDT_260925\"")
    #expect(a.decode(quarter) == [VenueMessage(Self.umQuarter.id, .delta(delta))])
    // 不在这条连接上的品种、坏档位一律不认。
    #expect(a.decode(text.replacingOccurrences(of: "\"s\":\"BTCUSDT\"", with: "\"s\":\"ETHUSDT\"")).isEmpty)
    #expect(a.decode(text.replacingOccurrences(of: "\"3.5\"", with: "\"x\"")).isEmpty)
  }

  @Test("币安：aggTrade 的 m=true 是主动卖，吃买盘；币本位的量是张数，原样给")
  func binanceTrade() {
    let a = Self.binance(.cm, [Self.cmPerp], .gateway)
    let sell = #"{"stream":"btcusd_perp@aggTrade","data":{"e":"aggTrade","s":"BTCUSD_PERP","p":"78450","q":"120","m":true,"T":1700000000500}}"#
    #expect(a.decode(sell) == [VenueMessage(Self.cmPerp.id, .trade(OrderFlowTrade(price: 78450, quantity: 120, hitSide: .bid, timeMs: 1700000000500)))])
    let buy = sell.replacingOccurrences(of: "\"m\":true", with: "\"m\":false")
    #expect(a.decode(buy) == [VenueMessage(Self.cmPerp.id, .trade(OrderFlowTrade(price: 78450, quantity: 120, hitSide: .ask, timeMs: 1700000000500)))])
  }

  @Test("币安现货：没有 pu（带了也不用），序号模型是 rangeOverlap")
  func binanceSpotDelta() {
    let a = Self.binance(.spot, [Self.spot], .gateway)
    #expect(Self.spot.venue.sequenceModel == .rangeOverlap && !Self.spot.venue.snapshotInBand)
    let text = #"{"stream":"btcusdt@depth@100ms","data":{"e":"depthUpdate","E":5,"s":"BTCUSDT","U":7,"u":9,"pu":6,"b":[],"a":[["100","1"]]}}"#
    #expect(a.decode(text) == [VenueMessage(Self.spot.id, .delta(BookDelta(firstUpdateID: 7, finalUpdateID: 9, previousFinalUpdateID: nil,
                                                                       bids: [], asks: [BookLevel(price: 100, quantity: 1)], eventTimeMs: 5)))])
  }

  @Test("线路两档都一样：合约推送拨主机中继 /v1/market/ws/binance、快照打主机 kanpan-api 带 market；现货恒直连 binance.vision")
  func binanceRouteIgnoresPolicy() async throws {
    let streams = "btcusdt@depth@100ms/btcusdt@aggTrade/btcusdt_260925@depth@100ms/btcusdt_260925@aggTrade"
    for policy in [MarketRoutePolicy.direct, .gateway] {
      let deck = ReplayDeck([.hang])
      let server = FakeServer { _ in json(#"{"lastUpdateId":777,"E":1700000000000,"T":1,"bids":[["100","2"]],"asks":[["101","3"]]}"#) }
      let um = Self.binance(.um, [Self.umPerp, Self.umQuarter], policy, server: server, deck: deck)
      #expect(um.streamURLs.map(\.absoluteString) == ["wss://gw-a.example/v1/market/ws/binance?streams=" + streams], "\(policy)")
      let s = try await um.connect(candidate: 0); await s.cancel()
      #expect(await deck.stats().urls.first?.absoluteString == "wss://gw-a.example/v1/market/ws/binance?streams=" + streams)
      let snap = try await um.fetchSnapshot(venueID: Self.umQuarter.id)
      #expect(snap == BookSnapshot(lastUpdateID: 777, requestedLevels: 1000, bids: [BookLevel(price: 100, quantity: 2)],
                                   asks: [BookLevel(price: 101, quantity: 3)], eventTimeMs: 1700000000000))
      let cm = Self.binance(.cm, [Self.cmPerp], policy, server: server)
      _ = try await cm.fetchSnapshot(venueID: Self.cmPerp.id)
      let spot = Self.binance(.spot, [Self.spot], policy, server: server)
      #expect(spot.streamURLs.map(\.absoluteString) == ["wss://data-stream.binance.vision/stream?streams=btcusdt@depth@100ms/btcusdt@aggTrade"])
      _ = try await spot.fetchSnapshot(venueID: Self.spot.id)
      #expect(await server.urls().map(\.absoluteString) == [
        "https://gw-a.example/v1/market/depth?limit=1000&symbol=BTCUSDT_260925&market=um",
        "https://gw-a.example/v1/market/depth?limit=1000&symbol=BTCUSD_PERP&market=cm",
        "https://data-api.binance.vision/api/v3/depth?limit=1000&symbol=BTCUSDT",
      ], "\(policy)")
      await #expect(throws: (any Error).self) { try await um.fetchSnapshot(venueID: "binance:usdtPerp:ETHUSDT") }
    }
  }

  @Test("币安中继：主机 503 就报，不去问备用机（备用机没有这几条）")
  func binanceRelayPrimaryOnly() async throws {
    let server = FakeServer { _ in json(#"{"error":{"code":"market_upstream_unavailable"}}"#, status: 503, headers: ["Retry-After": "2"]) }
    let a = Self.binance(.cm, [Self.cmQuarter], .gateway, server: server)
    await #expect(throws: (any Error).self) { try await a.fetchSnapshot(venueID: Self.cmQuarter.id) }
    #expect(await server.urls().compactMap(\.host) == ["gw-a.example"])
  }

  @Test("币安中继：kanpan-api 若有多台，推送与快照按序换下一台")
  func binanceRelayFailsOverAcrossApiHosts() async throws {
    let deck = ReplayDeck([.hang])
    let server = FakeServer { url in
      url.host == "gw-a.example"
        ? json(#"{"error":{"code":"market_upstream_unavailable"}}"#, status: 503, headers: ["Retry-After": "2"])
        : json(#"{"lastUpdateId":9,"bids":[["100","2"]],"asks":[["101","3"]]}"#)
    }
    let a = Self.binance(.cm, [Self.cmPerp, Self.cmQuarter], .direct, server: server, deck: deck, api: Self.gateways)
    let s = try await a.connect(candidate: 0); await s.cancel()
    let streams = "btcusd_perp@depth@100ms/btcusd_perp@aggTrade/btcusd_260925@depth@100ms/btcusd_260925@aggTrade"
    #expect(await deck.stats().urls.first?.absoluteString == "wss://gw-a.example/v1/market/ws/binance?streams=" + streams)
    #expect(a.streamURLs.map(\.absoluteString) == [
      "wss://gw-a.example/v1/market/ws/binance?streams=" + streams,
      "wss://gw-b.example:8443/v1/market/ws/binance?streams=" + streams,
    ])
    let snap = try await a.fetchSnapshot(venueID: Self.cmQuarter.id)
    #expect(snap.lastUpdateID == 9)
    #expect(await server.urls().map(\.absoluteString) == [
      "https://gw-a.example/v1/market/depth?limit=1000&symbol=BTCUSD_260925&market=cm",
      "https://gw-b.example:8443/v1/market/depth?limit=1000&symbol=BTCUSD_260925&market=cm",
    ])
  }

  @Test("币安网关：4xx（品种不认）直接报，不换主机")
  func binanceGatewayClientError() async throws {
    let server = FakeServer { _ in json(#"{"error":{"code":"unknown_symbol"}}"#, status: 400) }
    let a = Self.binance(.um, [Self.umPerp], .gateway, server: server)
    await #expect(throws: DepthSnapshotError(status: 400, retryAfterMs: nil)) { try await a.fetchSnapshot(venueID: Self.umPerp.id) }
    #expect(await server.urls().count == 1)
  }

  @Test("币安：一条连接最多 4 本（中继一条最多 8 路流）")
  func binanceCapsBooks() {
    let books = (0..<6).map { Self.book("binance", .usdtPerp, "X\($0)USDT") }
    let a = Self.binance(.um, books, .gateway)
    #expect(a.books.count == 4)
    #expect(a.streams.count == 8)
  }

  // ---------------------------------------------------------------- 价格口径

  @Test("价格口径：看 1000PEPEUSDT 时 OKX 一个币的价乘 1000、正向数量除 1000，名义美元不变")
  func priceFactorKeepsNotional() throws {
    let pepe = Self.book("okx", .usdtPerp, "PEPE-USDT-SWAP", .linear(multiplier: 10_000_000), factor: 1000)
    let a = OKXBooksAdapter(books: [pepe], gateways: Self.gateways)
    let text = #"{"arg":{"channel":"books","instId":"PEPE-USDT-SWAP"},"action":"snapshot","data":[{"asks":[["0.00001234","50","0","1"]],"bids":[],"ts":"1","checksum":0,"prevSeqId":-1,"seqId":3}]}"#
    guard case .snapshot(let s)? = a.decode(text).first?.message else { Issue.record("不是快照"); return }
    let level = try #require(s.asks.first)
    #expect(abs(level.price - 0.01234) < 1e-12)
    #expect(abs(level.quantity - 0.05) < 1e-12)
    let raw = OrderFlowNotional.linear(multiplier: 10_000_000).usd(price: 0.00001234, quantity: 50)
    #expect(abs(pepe.venue.notional.usd(price: level.price, quantity: level.quantity) - raw) < 1e-6)
    // 反向合约的数量是张数，只换价格。
    let inverse = Self.book("okx", .coinPerp, "PEPE-USD-SWAP", .inverse(contractUsd: 10), factor: 1000)
    #expect(inverse.quantityFactor == 1)
  }

  // ---------------------------------------------------------------- OKX

  static let okxSwap = book("okx", .usdtPerp, "BTC-USDT-SWAP", .linear(multiplier: 0.01))
  static let okxCoin = book("okx", .coinPerp, "BTC-USD-SWAP", .inverse(contractUsd: 100))
  static let okxFuture = book("okx", .delivery, "BTC-USD-260925", .inverse(contractUsd: 100))

  static func okx(deck: ReplayDeck = ReplayDeck([.hang]), books: [DepthBook] = [okxSwap, okxCoin, okxFuture]) -> OKXBooksAdapter {
    OKXBooksAdapter(books: books, gateways: gateways, sockets: ReplayFactory(deck: deck, pacer: FastPacer()))
  }

  static func okxFrame(_ action: String, seq: Int64, prev: Int64, instId: String = "BTC-USDT-SWAP",
                       bids: String = #"[["78450.1","350","0","4"]]"#, asks: String = #"[["78460","20","0","1"]]"#) -> String {
    #"{"arg":{"channel":"books","instId":""# + instId + #""},"action":""# + action + #"","data":[{"asks":"# + asks + #","bids":"# + bids + #","ts":"1700000000999","checksum":0,"prevSeqId":"# + String(prev) + #","seqId":"# + String(seq) + "}]}"
  }

  @Test("OKX：books 首帧是流内快照，数量原样（张数）；update 按各自 instId 的 seqId/prevSeqId；倒退就重置")
  func okxBooks() {
    let a = Self.okx()
    #expect(Self.okxSwap.venue.sequenceModel == .previousFinalExact && Self.okxSwap.venue.snapshotInBand)
    #expect(a.decode(Self.okxFrame("snapshot", seq: 10, prev: -1)) == [VenueMessage(Self.okxSwap.id,
      .snapshot(BookSnapshot(lastUpdateID: 10, requestedLevels: 400, bids: [BookLevel(price: 78450.1, quantity: 350)],
                             asks: [BookLevel(price: 78460, quantity: 20)], eventTimeMs: 1700000000999)))])
    #expect(a.decode(Self.okxFrame("update", seq: 12, prev: 10, instId: "BTC-USD-260925", bids: "[]")) == [VenueMessage(Self.okxFuture.id,
      .delta(BookDelta(firstUpdateID: 12, finalUpdateID: 12, previousFinalUpdateID: 10, bids: [],
                       asks: [BookLevel(price: 78460, quantity: 20)], eventTimeMs: 1700000000999)))])
    #expect(a.decode(Self.okxFrame("update", seq: 5, prev: 12, instId: "BTC-USD-SWAP")) == [VenueMessage(Self.okxCoin.id, .reset)])
    // 不在这条连接上的 instId、订阅回执、错误、pong：不认。
    #expect(a.decode(Self.okxFrame("update", seq: 13, prev: 12, instId: "ETH-USDT-SWAP")).isEmpty)
    #expect(a.decode(#"{"event":"subscribe","arg":{"channel":"books","instId":"BTC-USDT-SWAP"},"connId":"a"}"#).isEmpty)
    #expect(a.decode(#"{"event":"error","code":"60012","msg":"Invalid request"}"#).isEmpty)
    #expect(a.decode("pong").isEmpty)
  }

  @Test("OKX：trades 的 side 是主动方，sz 原样（张数）")
  func okxTrades() {
    let a = Self.okx()
    let text = #"{"arg":{"channel":"trades","instId":"BTC-USDT-SWAP"},"data":[{"instId":"BTC-USDT-SWAP","tradeId":"1","px":"78450","sz":"30","side":"sell","ts":"1700000000001","count":"1"},{"instId":"BTC-USDT-SWAP","tradeId":"2","px":"78460","sz":"5","side":"buy","ts":"1700000000002","count":"1"}]}"#
    #expect(a.decode(text) == [
      VenueMessage(Self.okxSwap.id, .trade(OrderFlowTrade(price: 78450, quantity: 30, hitSide: .bid, timeMs: 1700000000001))),
      VenueMessage(Self.okxSwap.id, .trade(OrderFlowTrade(price: 78460, quantity: 5, hitSide: .ask, timeMs: 1700000000002))),
    ])
  }

  @Test("OKX：拨网关中继 /v1/market/ws/okx，连上后发订阅（一条最多 12 个 args），每 20 秒 ping")
  func okxRoute() async throws {
    let deck = ReplayDeck([.hang])
    let books = (0..<8).map { Self.book("okx", .spot, "C\($0)-USDT") }
    let s = try await Self.okx(deck: deck, books: books).connect(candidate: 1); await s.cancel()
    let stats = await deck.stats()
    #expect(stats.urls.map(\.absoluteString) == ["wss://gw-b.example:8443/v1/market/ws/okx"])
    #expect(stats.sent.count == 2)
    let first = try #require(stats.sent.first.flatMap { $0.data(using: .utf8) })
    let obj = try #require(try JSONSerialization.jsonObject(with: first) as? [String: Any])
    #expect(obj["op"] as? String == "subscribe")
    let args = try #require(obj["args"] as? [[String: String]])
    #expect(args.count == 12)
    #expect(args.prefix(2) == [["channel": "books", "instId": "C0-USDT"], ["channel": "trades", "instId": "C0-USDT"]])
    #expect(Self.okx().keepAlive == DepthKeepAlive(text: "ping", everyMs: 20_000))
    #expect(OKXBooksAdapter(books: (0..<20).map { Self.book("okx", .spot, "C\($0)-USDT") }, gateways: Self.gateways).books.count == 12)
  }

  // ---------------------------------------------------------------- Coinbase

  static let coinbaseBook = book("coinbase", .spot, "BTC-USD")

  @Test("Coinbase：直连订 level2 / market_trades / heartbeats 三个频道")
  func coinbaseSubscribe() async throws {
    let deck = ReplayDeck([.hang])
    let a = CoinbaseLevel2Adapter(book: Self.coinbaseBook, sockets: ReplayFactory(deck: deck, pacer: FastPacer()))
    #expect(a.symbol == "BTC-USD" && Self.coinbaseBook.venue.sequenceModel == .strictIncrementing)
    let s = try await a.connect(candidate: 0); await s.cancel()
    let stats = await deck.stats()
    #expect(stats.urls.map(\.absoluteString) == ["wss://advanced-trade-ws.coinbase.com"])
    #expect(stats.sent == [
      #"{"channel":"level2","product_ids":["BTC-USD"],"type":"subscribe"}"#,
      #"{"channel":"market_trades","product_ids":["BTC-USD"],"type":"subscribe"}"#,
      #"{"channel":"heartbeats","type":"subscribe"}"#,
    ])
  }

  @Test("Coinbase：整条连接一个序号，心跳与回执也推进；l2 快照整本在；成交只收 update")
  func coinbaseDecode() {
    let a = CoinbaseLevel2Adapter(book: Self.coinbaseBook)
    let id = Self.coinbaseBook.id
    let advance: (Int64) -> VenueMessage = { VenueMessage(id, .delta(BookDelta(firstUpdateID: $0, finalUpdateID: $0, previousFinalUpdateID: nil))) }
    #expect(a.decode(#"{"channel":"subscriptions","sequence_num":0,"events":[]}"#) == [advance(0)])
    #expect(a.decode(#"{"channel":"heartbeats","sequence_num":3,"events":[{"heartbeat_counter":1}]}"#) == [advance(3)])
    let snap = #"{"channel":"l2_data","sequence_num":1,"events":[{"type":"snapshot","product_id":"BTC-USD","updates":[{"side":"bid","event_time":"2026-09-24T01:02:03.456789Z","price_level":"60000","new_quantity":"1.5"},{"side":"bid","event_time":"2026-09-24T01:02:03.456789Z","price_level":"59990","new_quantity":"2"},{"side":"offer","event_time":"2026-09-24T01:02:03.456789Z","price_level":"60010","new_quantity":"0.5"}]}]}"#
    guard case .snapshot(let s)? = a.decode(snap).first?.message else { Issue.record("不是快照"); return }
    #expect(s.lastUpdateID == 1 && s.requestedLevels == 3 && s.bids.count == 2 && s.asks == [BookLevel(price: 60010, quantity: 0.5)])
    #expect(s.eventTimeMs == CoinbaseDTO.isoMs("2026-09-24T01:02:03.456Z"))
    let update = #"{"channel":"l2_data","sequence_num":2,"events":[{"type":"update","product_id":"BTC-USD","updates":[{"side":"offer","event_time":"2026-09-24T01:02:04Z","price_level":"60010","new_quantity":"0"}]}]}"#
    #expect(a.decode(update) == [VenueMessage(id, .delta(BookDelta(firstUpdateID: 2, finalUpdateID: 2, previousFinalUpdateID: nil, bids: [],
                                                                  asks: [BookLevel(price: 60010, quantity: 0)],
                                                                  eventTimeMs: CoinbaseDTO.isoMs("2026-09-24T01:02:04Z")!)))])
    let trades = #"{"channel":"market_trades","sequence_num":4,"events":[{"type":"snapshot","trades":[{"product_id":"BTC-USD","price":"1","size":"1","side":"BUY","time":"2026-09-24T01:00:00Z"}]},{"type":"update","trades":[{"trade_id":"9","product_id":"BTC-USD","price":"60010","size":"0.25","side":"BUY","time":"2026-09-24T01:02:05Z"},{"trade_id":"10","product_id":"BTC-USD","price":"60000","size":"0.1","side":"SELL","time":"2026-09-24T01:02:05Z"}]}]}"#
    let t = CoinbaseDTO.isoMs("2026-09-24T01:02:05Z")!
    #expect(a.decode(trades) == [advance(4),
                                 VenueMessage(id, .trade(OrderFlowTrade(price: 60010, quantity: 0.25, hitSide: .ask, timeMs: t))),
                                 VenueMessage(id, .trade(OrderFlowTrade(price: 60000, quantity: 0.1, hitSide: .bid, timeMs: t)))])
    #expect(a.decode(#"{"type":"error","message":"nope"}"#).isEmpty)
  }

  // ---------------------------------------------------------------- 品种表

  static let catalogJSON = #"""
  {"base":"BTC","asOfMs":1790000000000,"venues":[
   {"exchange":"binance","product":"usdtPerp","instrument":"BTCUSDT","notional":{"kind":"linear","multiplier":1.0},"tick":0.1},
   {"exchange":"binance","product":"delivery","instrument":"BTCUSDT_260925","margin":"usdt","notional":{"kind":"linear","multiplier":1.0},"tick":0.1,"expiryMs":1790323200000},
   {"exchange":"binance","product":"delivery","instrument":"BTCUSDT_250926","margin":"usdt","notional":{"kind":"linear","multiplier":1.0},"tick":0.1,"expiryMs":1758873600000},
   {"exchange":"binance","product":"coinPerp","instrument":"BTCUSD_PERP","notional":{"kind":"inverse","contractUsd":100.0},"tick":0.1},
   {"exchange":"binance","product":"delivery","instrument":"BTCUSD_260925","margin":"coin","notional":{"kind":"inverse","contractUsd":100.0},"tick":0.1,"expiryMs":1790323200000},
   {"exchange":"okx","product":"usdtPerp","instrument":"BTC-USDT-SWAP","notional":{"kind":"linear","multiplier":0.01},"tick":0.1},
   {"exchange":"okx","product":"coinPerp","instrument":"BTC-USD-SWAP","notional":{"kind":"inverse","contractUsd":100.0},"tick":0.1},
   {"exchange":"okx","product":"delivery","instrument":"BTC-USD-260925","margin":"coin","notional":{"kind":"inverse","contractUsd":100.0},"tick":0.1,"expiryMs":1790323200000},
   {"exchange":"binance","product":"spot","instrument":"BTCUSDT","notional":{"kind":"linear","multiplier":1.0},"tick":0.01},
   {"exchange":"okx","product":"spot","instrument":"BTC-USDT","notional":{"kind":"linear","multiplier":1.0},"tick":0.1},
   {"exchange":"coinbase","product":"spot","instrument":"BTC-USD","notional":{"kind":"linear","multiplier":1.0},"tick":0.01},
   {"exchange":"kraken","product":"spot","instrument":"XBT-USD","notional":{"kind":"linear","multiplier":1.0},"tick":0.1},
   {"exchange":"okx","product":"usdtPerp","instrument":"BAD-ZERO","notional":{"kind":"linear","multiplier":0},"tick":0.1}
  ]}
  """#

  static func catalog(_ policy: MarketRoutePolicy, server: FakeServer, gateways: [String] = gateways,
                      api: [String]? = nil) -> OrderFlowCatalog {
    OrderFlowCatalog(route: MarketRoute(policy: policy, endpoints: MarketEndpoints(gateways: gateways, api: api)),
                     binanceHosts: hosts, sockets: ReplayFactory(deck: ReplayDeck([.hang]), pacer: FastPacer()),
                     http: FakeTransport(server), cache: OrderFlowCatalogCache())
  }

  @Test("品种表：解析各家各产品，丢掉未知交易所、坏面值、已过交割时间的，分到 5 条连接")
  func catalogParses() async throws {
    let server = FakeServer { _ in json(Self.catalogJSON) }
    let c = Self.catalog(.direct, server: server)
    let got = await c.books(base: "btc", nowMs: 1_790_000_000_000)
    #expect(got.fromCatalog && got.base == "BTC" && got.chartScale == 1)
    #expect(got.books.map(\.id) == [
      "binance:usdtPerp:BTCUSDT", "binance:delivery:BTCUSDT_260925", "binance:coinPerp:BTCUSD_PERP",
      "binance:delivery:BTCUSD_260925", "okx:usdtPerp:BTC-USDT-SWAP", "okx:coinPerp:BTC-USD-SWAP",
      "okx:delivery:BTC-USD-260925", "binance:spot:BTCUSDT", "okx:spot:BTC-USDT", "coinbase:spot:BTC-USD",
    ])
    #expect(got.books.first { $0.id == "okx:coinPerp:BTC-USD-SWAP" }?.venue.notional == .inverse(contractUsd: 100))
    #expect(got.books.first { $0.id == "binance:delivery:BTCUSD_260925" }?.expiryMs == 1_790_323_200_000)
    #expect(await server.urls().map(\.absoluteString) == ["https://gw-a.example/v1/market/orderflow/instruments?base=BTC"])
    let adapters = c.adapters(got.books)
    #expect(adapters.map(\.name) == [
      "币安U 本位 BTCUSDT,BTCUSDT_260925", "币安币本位 BTCUSD_PERP,BTCUSD_260925", "币安现货 BTCUSDT",
      "OKX BTC-USDT-SWAP,BTC-USD-SWAP,BTC-USD-260925,BTC-USDT", "Coinbase BTC-USD",
    ])
    // 第二次同一只币走内存缓存，不再请求。
    _ = await c.books(base: "BTC", nowMs: 1_790_000_060_000)
    #expect(await server.urls().count == 1)
  }

  @Test("品种表：只问主机（备用机没有这条）；kanpan-api 若有多台才按序换；都不通给保底三本（币安永续、币安现货、Coinbase）")
  func catalogFallback() async throws {
    let flaky = FakeServer { url in url.host == "gw-a.example" ? json("{}", status: 502) : json(Self.catalogJSON) }
    let primaryOnly = await Self.catalog(.gateway, server: flaky).books(base: "BTC", nowMs: 1_790_000_000_000)
    #expect(!primaryOnly.fromCatalog)
    #expect(await flaky.urls().compactMap(\.host) == ["gw-a.example"])
    let ok = await Self.catalog(.gateway, server: flaky, api: Self.gateways).books(base: "BTC", nowMs: 1_790_000_000_000)
    #expect(ok.fromCatalog && ok.books.count == 10)
    let dead = FakeServer { _ in json("oops", status: 500) }
    let fallback = await Self.catalog(.gateway, server: dead, api: Self.gateways).books(base: "ETH", nowMs: 1)
    #expect(!fallback.fromCatalog)
    #expect(fallback.books.map(\.id) == ["binance:usdtPerp:ETHUSDT", "binance:spot:ETHUSDT", "coinbase:spot:ETH-USD"])
    #expect(await dead.urls().count == 2)
    // 两档线路下 OKX 都拨主机中继。
    for policy in [MarketRoutePolicy.direct, .gateway] {
      let names = Self.catalog(policy, server: dead).adapters([Self.okxSwap]).map(\.name)
      #expect(names == ["OKX BTC-USDT-SWAP"], "\(policy)")
    }
    // 没有网关：OKX 那几本订不了，不给连接。
    let noGateway = Self.catalog(.direct, server: dead, gateways: [])
    #expect(noGateway.adapters([Self.okxSwap, Self.umPerp]).map(\.name) == ["币安U 本位 BTCUSDT"])
  }

  @Test("服务端历史：带 base/from/to 问主机，解析成一页；主机不通、回了坏数据、别的币的页都当没有")
  func historyFetch() async throws {
    let body = #"{"base":"BTC","thresholds":{"spot":1000000.0,"usdtPerp":5000000.0,"coinPerp":5000000.0,"delivery":5000000.0,"step":100.0},"trackedSinceMs":1790256061037,"orders":[{"venueID":"binance:usdtPerp:BTCUSDT","exchange":"币安","product":"usdtPerp","side":"bid","bucket":1123,"price":112300.0,"firstSeenMs":1790256070000,"endMs":1790256130000,"status":"cancelled","initialNotional":6100000.0,"notional":0.0,"filledNotional":0.0,"threshold":5000000.0,"vanishedNotional":6100000.0}]}"#
    let server = FakeServer { _ in json(body) }
    let page = try #require(await Self.catalog(.direct, server: server)
      .history(base: "BTC", fromMs: 1_790_256_000_000, toMs: 1_790_256_200_000))
    #expect(page.base == "BTC" && page.thresholds.step == 100 && page.trackedSinceMs == 1_790_256_061_037)
    #expect(page.fromMs == 1_790_256_000_000 && page.toMs == 1_790_256_200_000)
    #expect(page.orders.map(\.id) == ["binance:usdtPerp:BTCUSDT|bid|1123|1790256070000"])
    #expect(await server.urls().map(\.absoluteString) ==
      ["https://gw-a.example/v1/market/orderflow/history?base=BTC&from=1790256000000&to=1790256200000"])
    let dead = FakeServer { _ in json("oops", status: 503) }
    #expect(await Self.catalog(.gateway, server: dead, api: Self.gateways).history(base: "BTC", fromMs: 0, toMs: 1) == nil)
    #expect(await dead.urls().count == 2)
    let other = FakeServer { _ in json(body) }
    #expect(await Self.catalog(.direct, server: other).history(base: "ETH", fromMs: 0, toMs: 1) == nil)
    #expect(await Self.catalog(.direct, server: other).history(base: "BTC", fromMs: 5, toMs: 1) == nil)
  }

  @Test("品种表：看 1000PEPEUSDT 时按 PEPE 查，币安带前缀那行不缩放，其他家乘 1000；保底也按这个口径")
  func catalogScaledBase() async throws {
    let body = #"{"base":"PEPE","asOfMs":1,"venues":[{"exchange":"binance","product":"usdtPerp","instrument":"1000PEPEUSDT","notional":{"kind":"linear","multiplier":1.0},"tick":0.0000001,"priceScale":1000},{"exchange":"okx","product":"usdtPerp","instrument":"PEPE-USDT-SWAP","notional":{"kind":"linear","multiplier":10000000},"tick":0.00000001}]}"#
    let server = FakeServer { _ in json(body) }
    let got = await Self.catalog(.direct, server: server).books(base: "1000PEPE", nowMs: 1)
    #expect(got.base == "PEPE" && got.chartScale == 1000)
    #expect(got.books.map(\.priceFactor) == [1, 1000])
    #expect(await server.urls().first?.absoluteString == "https://gw-a.example/v1/market/orderflow/instruments?base=PEPE")
    let fallback = OrderFlowCatalog.fallback(viewedBase: "1000PEPE", base: "PEPE", chartScale: 1000)
    #expect(fallback.map(\.id) == ["binance:usdtPerp:1000PEPEUSDT", "binance:spot:PEPEUSDT", "coinbase:spot:PEPE-USD"])
    #expect(fallback.map(\.priceFactor) == [1, 1000, 1000])
    for (raw, base, scale) in [("1MBABYDOGE", "BABYDOGE", 1_000_000.0), ("1000000MOG", "MOG", 1_000_000),
                               ("1INCH", "1INCH", 1), ("1000", "1000", 1), ("1000pepe", "PEPE", 1000)] {
      let n = OrderFlowBase.normalize(raw)
      #expect(n.base == base && n.scale == scale, "\(raw)")
    }
    #expect(!OrderFlowBase.isValid("BTC-USD") && !OrderFlowBase.isValid(""))
  }

  @Test("提供者：币安（两条线路）与 Coinbase 都给得出品种表，线路跟着提供者走")
  func providersSource() {
    let direct: any MarketProvider = BinanceProvider(upstream: .binance, hosts: Self.hosts, policy: .direct)
    let gateway: any MarketProvider = BinanceProvider(upstream: .okx, hosts: Self.hosts, policy: .gateway)
    let coinbase: any MarketProvider = CoinbaseProvider(policy: .gateway, endpoints: MarketEndpoints(gateways: ["gw-a.example"]))
    #expect((direct as? any OrderFlowSourcing)?.orderFlowCatalog.route.viaGateway == false)
    #expect((gateway as? any OrderFlowSourcing)?.orderFlowCatalog.route.viaGateway == true)
    #expect((coinbase as? any OrderFlowSourcing)?.orderFlowCatalog.route.gateways == ["gw-a.example"])
    #expect((coinbase as? any OrderFlowSourcing)?.orderFlowCatalog.route.apiHosts == ["gw-a.example"])
    // 旧的一品种一家入口 `MarketProvider.orderFlowAdapter(symbol:)` 已删，订单流只从这张品种表拿。
    #expect([direct, gateway, coinbase].allSatisfy { $0 is any OrderFlowSourcing })
  }

  // ---------------------------------------------------------------- 连接客户端

  @Test("连接客户端：断线退避重连，新连接号先于它的消息；主动 reconnect 立刻重拨")
  func streamReconnects() async throws {
    let first = Self.okxFrame("snapshot", seq: 10, prev: -1)
    let deck = ReplayDeck([.frame(.text(first)), .frame(.text("{}")), .drop("bye"),
                           .frame(.text(Self.okxFrame("snapshot", seq: 20, prev: -1))), .hang])
    let pacer = FastPacer()
    let stream = DepthStream(adapter: OKXBooksAdapter(books: [Self.okxSwap], gateways: Self.gateways,
                                                      sockets: ReplayFactory(deck: deck, pacer: pacer)),
                             pacer: pacer, silenceMs: 600_000)
    let events = await stream.start()
    let log = EventLog()
    let reader = Task { for await e in events { await log.note(e) } }
    #expect(await waitUntil(5) { await log.lines.count >= 5 })
    #expect(await log.lines.prefix(5) == ["connected 1", "snapshot 10", "disconnected", "connected 2", "snapshot 20"])
    await stream.reconnect()
    #expect(await waitUntil(5) { await log.lines.contains("connected 3") })
    #expect(await deck.stats().connects == 3)
    await stream.stop()
    reader.cancel()
  }

  @Test("连接客户端：主节点连上却一条消息都没有就断，下次拨备用那台")
  func streamFallsBackToBackupGateway() async throws {
    let deck = ReplayDeck([.drop("主节点没推"), .frame(.text(Self.okxFrame("snapshot", seq: 10, prev: -1))), .hang])
    let pacer = FastPacer()
    let stream = DepthStream(adapter: OKXBooksAdapter(books: [Self.okxSwap], gateways: Self.gateways,
                                                      sockets: ReplayFactory(deck: deck, pacer: pacer)),
                             pacer: pacer, silenceMs: 600_000)
    let events = await stream.start()
    let log = EventLog()
    let reader = Task { for await e in events { await log.note(e) } }
    #expect(await waitUntil(5) { await log.lines.contains("snapshot 10") })
    #expect(await deck.stats().urls.compactMap(\.host) == ["gw-a.example", "gw-b.example"])
    await stream.stop()
    reader.cancel()
  }

  @Test("连接客户端：静默超过窗口就掐掉重连")
  func streamSilenceWatchdog() async throws {
    let deck = ReplayDeck([.frame(.text(Self.okxFrame("snapshot", seq: 10, prev: -1))), .silence(120_000),
                           .frame(.text(Self.okxFrame("snapshot", seq: 30, prev: -1))), .hang])
    let pacer = FastPacer()
    let stream = DepthStream(adapter: OKXBooksAdapter(books: [Self.okxSwap], gateways: Self.gateways,
                                                      sockets: ReplayFactory(deck: deck, pacer: pacer)),
                             pacer: pacer, silenceMs: 30_000)
    let events = await stream.start()
    let log = EventLog()
    let reader = Task { for await e in events { await log.note(e) } }
    #expect(await waitUntil(5) { await log.lines.contains("connected 2") })
    await stream.stop()
    reader.cancel()
  }

  @Test("连接客户端：OKX 连上后发订阅，之后按保活间隔发 ping")
  func streamKeepAlive() async throws {
    let deck = ReplayDeck([.frame(.text(Self.okxFrame("snapshot", seq: 10, prev: -1))), .hang])
    let pacer = FastPacer()
    let stream = DepthStream(adapter: OKXBooksAdapter(books: [Self.okxSwap], gateways: Self.gateways,
                                                      sockets: ReplayFactory(deck: deck, pacer: pacer)),
                             pacer: pacer, silenceMs: 600_000_000)
    let events = await stream.start()
    let reader = Task { for await _ in events {} }
    #expect(await waitUntil(5) { await deck.stats().sent.filter { $0 == "ping" }.count >= 2 })
    #expect(await deck.stats().sent.first?.contains("\"subscribe\"") == true)
    await stream.stop()
    reader.cancel()
  }

  @Test("连接客户端：看门狗是常驻的——帧一直在来（间隔都小于窗口）就不掐，累计时长远超窗口也不掐；停了才掐，原因写明")
  func streamWatchdogIsResident() async throws {
    // 100× 快进：窗口 60 秒 = 真 600 ms，帧间隔 15 秒 = 真 150 ms，留足余量不怕机器忙时抖动。
    let pacer = FastPacer(scale: 0.01)
    var steps: [ReplayStep] = [.frame(.text(Self.okxFrame("snapshot", seq: 10, prev: -1)))]
    for i in 0..<6 {
      steps += [.silence(15_000), .frame(.text(Self.okxFrame("update", seq: 11 + Int64(i), prev: 10 + Int64(i))))]
    }
    steps += [.hang]
    let deck = ReplayDeck(steps)
    let stream = DepthStream(adapter: OKXBooksAdapter(books: [Self.okxSwap], gateways: Self.gateways,
                                                      sockets: ReplayFactory(deck: deck, pacer: pacer)),
                             pacer: pacer, silenceMs: 60_000)
    let events = await stream.start()
    let log = EventLog()
    let reader = Task { for await e in events { await log.note(e) } }
    // 六段 15 秒共 90 秒，比 60 秒的窗口长：旧的「每帧一个 sleep」和新的常驻看门狗都不该在这期间掐。
    #expect(await waitUntil(10) { await log.lines.filter { $0 == "message" }.count >= 6 })
    #expect(await deck.stats().connects == 1)
    // 之后一直不来帧：看门狗掐掉重连，断开原因是它记下的那句，不是「连接已取消」。
    #expect(await waitUntil(10) { await log.lines.contains("connected 2") })
    #expect(await log.reasons.first?.contains("60 秒没有收到深度推送") == true)
    await stream.stop()
    reader.cancel()
  }

  @Test("连接客户端：事件缓冲有上限，调用方跟不上被挤掉帧就整条重拨，不在内存里越积越多")
  func streamBoundedBufferReconnectsOnOverflow() async throws {
    let pacer = FastPacer()
    var steps: [ReplayStep] = [.frame(.text(Self.okxFrame("snapshot", seq: 10, prev: -1)))]
    for i in 0..<6 { steps.append(.frame(.text(Self.okxFrame("update", seq: 11 + Int64(i), prev: 10 + Int64(i))))) }
    steps += [.hang]
    let deck = ReplayDeck(steps)
    let lines = LineLog()
    let stream = DepthStream(adapter: OKXBooksAdapter(books: [Self.okxSwap], gateways: Self.gateways,
                                                      sockets: ReplayFactory(deck: deck, pacer: pacer)),
                             pacer: pacer, silenceMs: 600_000_000, bufferLimit: 3,
                             log: FeedLog { line in Task { await lines.add(line) } })
    // 故意先不读：缓冲 3 条，第 4 条进来时最旧的被挤掉。
    let events = await stream.start()
    #expect(await waitUntil(5) { await deck.stats().connects >= 2 })
    #expect(await waitUntil(5) { await lines.all.contains { $0.contains("缓冲满了丢了帧") } })
    // 立即重拨（不走退避）；读出来的是最新的几条，末尾是新连接。
    let log = EventLog()
    let reader = Task { for await e in events { await log.note(e) } }
    #expect(await waitUntil(5) { await log.lines.contains { $0.hasPrefix("connected") } })
    await stream.stop()
    reader.cancel()
  }

  @Test("OKX 单本重订：只退订再订那一个 instId 的 books，trades 不动；不认识的簿给 nil")
  func okxResubscribeOneBook() throws {
    let okx = Self.okx()
    let messages = try #require(okx.resubscribeMessages(venueID: Self.okxCoin.id))
    #expect(messages == [#"{"args":[{"channel":"books","instId":"BTC-USD-SWAP"}],"op":"unsubscribe"}"#,
                         #"{"args":[{"channel":"books","instId":"BTC-USD-SWAP"}],"op":"subscribe"}"#])
    #expect(okx.resubscribeMessages(venueID: "nope") == nil)
    // 币安、Coinbase 做不到单本重订（Coinbase 序号整条连接一个；币安快照走 REST 本来就不用重订）。
    #expect(Self.binance(.um, [Self.umPerp], .direct).resubscribeMessages(venueID: Self.umPerp.id) == nil)
  }

  @Test("连接客户端：单本重订在当前连接上发退订 + 订阅，不重拨；适配器不会单本重订的就整条重拨")
  func streamResubscribesOneBookInPlace() async throws {
    let pacer = FastPacer()
    let deck = ReplayDeck([.frame(.text(Self.okxFrame("snapshot", seq: 10, prev: -1))), .hang])
    let stream = DepthStream(adapter: OKXBooksAdapter(books: [Self.okxSwap, Self.okxCoin], gateways: Self.gateways,
                                                      sockets: ReplayFactory(deck: deck, pacer: pacer)),
                             pacer: pacer, silenceMs: 600_000_000)
    let events = await stream.start()
    let log = EventLog()
    let reader = Task { for await e in events { await log.note(e) } }
    #expect(await waitUntil(5) { await log.lines.contains("snapshot 10") })
    #expect(await stream.resubscribe([Self.okxSwap.id]))
    let sent = await deck.stats().sent
    #expect(sent.suffix(2) == [#"{"args":[{"channel":"books","instId":"BTC-USDT-SWAP"}],"op":"unsubscribe"}"#,
                               #"{"args":[{"channel":"books","instId":"BTC-USDT-SWAP"}],"op":"subscribe"}"#])
    #expect(await deck.stats().connects == 1)
    // 名单里混了一本认不出的：退回整条重拨。
    #expect(await stream.resubscribe(["nope"]) == false)
    #expect(await waitUntil(5) { await log.lines.contains("connected 2") })
    await stream.stop()
    reader.cancel()
  }

  @Test("适配器与本地簿对得上：三家的帧把各自那本簿带到就绪，互不干扰")
  func adaptersFeedTheModel() {
    let okx = Self.okx()
    let um = Self.binance(.um, [Self.umPerp], .direct)
    let thresholds = OrderFlowThresholds(spot: 1_000_000, usdtPerp: 5_000_000, coinPerp: 5_000_000, delivery: 5_000_000, step: 100)
    var model = OrderFlowModel(symbol: "BTCUSDT", thresholds: thresholds)
    for book in [Self.okxSwap, Self.okxCoin, Self.umPerp] { model.addVenue(book.venue) }
    #expect(model.connectionOpened(Self.okxSwap.id) == .none)
    #expect(model.connectionOpened(Self.okxCoin.id) == .none)
    for text in [Self.okxFrame("update", seq: 9, prev: 8), Self.okxFrame("snapshot", seq: 10, prev: -1),
                 Self.okxFrame("update", seq: 11, prev: 10)] {
      for m in okx.decode(text) { #expect(model.ingest(m.venueID, m.message, nowMs: 1) == .none) }
    }
    #expect(model.isReady(Self.okxSwap.id))
    #expect(!model.isReady(Self.okxCoin.id))
    // 币安要 REST 快照：连上先要快照，缓冲的增量对上序号就绪。
    _ = model.connectionOpened(Self.umPerp.id)
    let delta = #"{"stream":"btcusdt@depth@100ms","data":{"e":"depthUpdate","E":1,"s":"BTCUSDT","U":100,"u":105,"pu":99,"b":[["78450","1"]],"a":[]}}"#
    let actions = um.decode(delta).map { model.ingest($0.venueID, $0.message, nowMs: 2) }
    #expect(actions.contains(.fetchSnapshot) || actions == [.none])
    let snapshot = BookSnapshot(lastUpdateID: 102, requestedLevels: 1000, bids: [BookLevel(price: 78450, quantity: 2)],
                                asks: [BookLevel(price: 78460, quantity: 2)])
    #expect(model.applySnapshot(Self.umPerp.id, snapshot, nowMs: 3) == .none)
    #expect(model.isReady(Self.umPerp.id))
  }
}

private actor LineLog {
  var all: [String] = []
  func add(_ line: String) { all.append(line) }
}

private actor EventLog {
  var lines: [String] = []
  var reasons: [String] = []
  func note(_ e: DepthStreamEvent) {
    switch e {
    case .connected(let n): lines.append("connected \(n)")
    case .disconnected(let why): lines.append("disconnected"); reasons.append(why)
    case .messages(let ms):
      for m in ms {
        if case .snapshot(let s) = m.message { lines.append("snapshot \(s.lastUpdateID)") } else { lines.append("message") }
      }
    }
  }
}
