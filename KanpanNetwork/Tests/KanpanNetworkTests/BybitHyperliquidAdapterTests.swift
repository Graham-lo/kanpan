import Foundation
import Testing
@testable import KanpanNetwork
import KanpanNetworkTestSupport
import KanpanCore

// 主力订单流 · Bybit 与 Hyperliquid 两家的适配器。帧样本取自 2026-10-08 经 kanpan-api 中继录的真帧
// （Bybit 三个 category 各 7 分钟、Hyperliquid BTC/ETH/SOL/kPEPE 7 分钟），只把档位截短。

extension OrderFlowAdapterTests {
  static let bybitSpot = book("bybit", .spot, "BTCUSDT")
  static let bybitLinear = book("bybit", .usdtPerp, "BTCUSDT")
  static let bybitInverse = book("bybit", .coinPerp, "BTCUSD", .inverse(contractUsd: 1))
  static let hlBTC = book("hyperliquid", .usdtPerp, "BTC")
  static let hlPEPE = book("hyperliquid", .usdtPerp, "kPEPE", factor: 1)

  static func bybit(_ category: BybitBooksAdapter.Category, _ books: [DepthBook],
                    deck: ReplayDeck = ReplayDeck([.hang])) -> BybitBooksAdapter {
    BybitBooksAdapter(category: category, books: books, gateways: gateways,
                      sockets: ReplayFactory(deck: deck, pacer: FastPacer()))
  }

  static func hyperliquid(_ books: [DepthBook], deck: ReplayDeck = ReplayDeck([.hang])) -> HyperliquidBookAdapter {
    HyperliquidBookAdapter(books: books, gateways: gateways, sockets: ReplayFactory(deck: deck, pacer: FastPacer()))
  }

  /// Bybit 现货 BTCUSDT 的首帧快照（真帧前两档）。
  static let bybitSpotSnapshot = #"{"topic":"orderbook.1000.BTCUSDT","ts":1791457526753,"type":"snapshot","data":{"s":"BTCUSDT","b":[["82679.9","1.423576"],["82679","0.025287"]],"a":[["82680","0.99168"],["82681.9","0.000094"]],"u":58035068,"seq":115115350871},"cts":1791457526724}"#
  /// 紧跟着的第一帧增量（真帧，u 58035069）。
  static let bybitSpotDelta = #"{"topic":"orderbook.1000.BTCUSDT","ts":1791457526954,"type":"delta","data":{"s":"BTCUSDT","b":[["82679.9","1.424947"],["82679.8","0.023976"],["82679","0"]],"a":[["82680","0.989307"]],"u":58035069,"seq":115115350909},"cts":1791457526919}"#

  static func hlBook(_ coin: String = "BTC", time: Int64 = 1791457528657,
                     bids: String = #"[{"px":"82640.0","sz":"7.49922","n":31},{"px":"82630.0","sz":"25.77217","n":61},{"px":"82620.0","sz":"76.81878","n":71}]"#,
                     asks: String = #"[{"px":"82650.0","sz":"7.81391","n":30},{"px":"82660.0","sz":"31.65547","n":73},{"px":"82670.0","sz":"51.15626","n":69}]"#) -> String {
    #"{"channel":"l2Book","data":{"coin":""# + coin + #"","time":"# + String(time) + #","levels":["# + bids + "," + asks + "]}}"
  }

  // ---------------------------------------------------------------- Bybit

  @Test("Bybit：orderbook.1000 首帧流内快照（1000 档滑动窗口、严格 +1）；u 1 的快照整本重来；增量按 u 接；0 删档")
  func bybitBooks() {
    let a = Self.bybit(.spot, [Self.bybitSpot])
    #expect(Self.bybitSpot.venue.sequenceModel == .strictIncrementing && Self.bybitSpot.venue.snapshotInBand)
    #expect(Self.bybitSpot.venue.label == "Bybit")
    #expect(a.decode(Self.bybitSpotSnapshot) == [VenueMessage(Self.bybitSpot.id, .snapshot(BookSnapshot(
      lastUpdateID: 58035068, requestedLevels: 1000,
      bids: [BookLevel(price: 82679.9, quantity: 1.423576), BookLevel(price: 82679, quantity: 0.025287)],
      asks: [BookLevel(price: 82680, quantity: 0.99168), BookLevel(price: 82681.9, quantity: 0.000094)],
      eventTimeMs: 1791457526753, slidingWindow: true)))])
    #expect(a.decode(Self.bybitSpotDelta) == [VenueMessage(Self.bybitSpot.id, .delta(BookDelta(
      firstUpdateID: 58035069, finalUpdateID: 58035069, previousFinalUpdateID: nil,
      bids: [BookLevel(price: 82679.9, quantity: 1.424947), BookLevel(price: 82679.8, quantity: 0.023976),
             BookLevel(price: 82679, quantity: 0)],
      asks: [BookLevel(price: 82680, quantity: 0.989307)], eventTimeMs: 1791457526954)))])
    // Bybit 那边服务重启：u 回到 1 的快照，本地整本重来。
    let restart = Self.bybitSpotSnapshot.replacingOccurrences(of: "\"u\":58035068", with: "\"u\":1")
    guard case .snapshot(let s)? = a.decode(restart).first?.message else { Issue.record("没解出快照"); return }
    #expect(s.restartsSequence && s.lastUpdateID == 1)
    // 不在这条连接上的品种、topic 与 s 对不上、坏档位：不认。
    #expect(a.decode(Self.bybitSpotDelta.replacingOccurrences(of: "BTCUSDT", with: "ETHUSDT")).isEmpty)
    #expect(a.decode(Self.bybitSpotDelta.replacingOccurrences(of: "orderbook.1000.", with: "orderbook.50.")).isEmpty)
    #expect(a.decode(Self.bybitSpotDelta.replacingOccurrences(of: "\"1.424947\"", with: "\"x\"")).isEmpty)
  }

  @Test("Bybit：publicTrade 的 S 是主动方（Buy 吃卖盘）；币本位的量是张数原样给；回执与 pong 不认")
  func bybitTradesAndControlFrames() {
    let linear = Self.bybit(.linear, [Self.bybitLinear])
    let buy = #"{"topic":"publicTrade.BTCUSDT","type":"snapshot","ts":1791457528912,"data":[{"T":1791457528911,"s":"BTCUSDT","S":"Buy","v":"0.011","p":"82642.90","L":"PlusTick","i":"5be1261b-d231-533b-89cd-0653c4f333be","BT":false,"RPI":false,"seq":822323446907}]}"#
    #expect(linear.decode(buy) == [VenueMessage(Self.bybitLinear.id, .trade(OrderFlowTrade(
      price: 82642.9, quantity: 0.011, hitSide: .ask, timeMs: 1791457528911)))])
    let inverse = Self.bybit(.inverse, [Self.bybitInverse])
    let sell = #"{"topic":"publicTrade.BTCUSD","type":"snapshot","ts":1791457532051,"data":[{"T":1791457532050,"s":"BTCUSD","S":"Sell","v":"2238","p":"82586.40","L":"ZeroMinusTick","i":"4639ca04-a297-52c5-aa8d-d4799be02811","BT":false,"RPI":false,"seq":118895331123}]}"#
    #expect(inverse.decode(sell) == [VenueMessage(Self.bybitInverse.id, .trade(OrderFlowTrade(
      price: 82586.4, quantity: 2238, hitSide: .bid, timeMs: 1791457532050)))])
    #expect(abs(Self.bybitInverse.venue.notional.usd(price: 82586.4, quantity: 2238) - 2238) < 1e-6)
    for control in [
      #"{"success":true,"ret_msg":"pong","conn_id":"db294p9abbveig58ile0-ozeu","req_id":"","op":"ping"}"#,
      #"{"success":true,"ret_msg":"pong","conn_id":"d9avs2b4qcrtmm61rq50-gcwhk","op":"ping"}"#,
      #"{"success":true,"ret_msg":"subscribe","conn_id":"d9avs2b4qcrtmm61rq50-gcwhk","op":"subscribe"}"#,
      #"{"success":true,"ret_msg":"","conn_id":"db2937jvnhjo7n76nht0-ce4a","req_id":"","op":"subscribe"}"#,
      #"{"op":"pong","args":["1791457528000"],"conn_id":"x"}"#,
      // 强平推送由服务端聚合进 /liq，客户端这条连接不订，万一来了也不当成交。
      #"{"topic":"allLiquidation.BTCUSDT","type":"snapshot","ts":1791457584979,"data":[{"T":1791457584957,"s":"BTCUSDT","S":"Buy","v":"0.5","p":"82000"}]}"#,
    ] {
      #expect(linear.decode(control).isEmpty, "\(control)")
    }
  }

  @Test("Bybit：拨中继 /v1/market/ws/bybit?category=…，一条消息最多 10 个 args、一条连接最多 12 本，每 20 秒 ping")
  func bybitRoute() async throws {
    let deck = ReplayDeck([.hang])
    let books = (0..<14).map { Self.book("bybit", .usdtPerp, "C\($0)USDT") }
    let a = Self.bybit(.linear, books, deck: deck)
    #expect(a.books.count == 12)
    let s = try await a.connect(candidate: 1); await s.cancel()
    let stats = await deck.stats()
    #expect(stats.urls.map(\.absoluteString) == ["wss://gw-b.example:8443/v1/market/ws/bybit?category=linear"])
    #expect(stats.sent.count == 3)
    let objs = try stats.sent.map { try #require(try JSONSerialization.jsonObject(with: Data($0.utf8)) as? [String: Any]) }
    #expect(objs.allSatisfy { $0["op"] as? String == "subscribe" })
    let args = objs.map { ($0["args"] as? [String]) ?? [] }
    #expect(args.map(\.count) == [10, 10, 4])
    #expect(args[0].prefix(2) == ["orderbook.1000.C0USDT", "publicTrade.C0USDT"])
    #expect(a.keepAlive == DepthKeepAlive(text: #"{"op":"ping"}"#, everyMs: 20_000))
    #expect(Self.bybit(.spot, [Self.bybitSpot]).streamURLs.map(\.absoluteString) ==
      ["wss://gw-a.example/v1/market/ws/bybit?category=spot", "wss://gw-b.example:8443/v1/market/ws/bybit?category=spot"])
  }

  @Test("Bybit 单本重订：只退订再订那一本的 orderbook.1000，成交不动；不认识的簿给 nil")
  func bybitResubscribeOneBook() throws {
    let a = Self.bybit(.linear, [Self.bybitLinear, Self.book("bybit", .usdtPerp, "ETHUSDT")])
    let messages = try #require(a.resubscribeMessages(venueID: Self.bybitLinear.id))
    #expect(messages == [#"{"args":["orderbook.1000.BTCUSDT"],"op":"unsubscribe"}"#,
                         #"{"args":["orderbook.1000.BTCUSDT"],"op":"subscribe"}"#])
    #expect(a.resubscribeMessages(venueID: "nope") == nil)
  }

  @Test("Bybit：品种表的簿按 category 分连接（现货 / U 本位含正向交割 / 币本位含反向交割），没有 kanpan-api 主机不订")
  func bybitGroupsByCategory() {
    let dead = FakeServer { _ in json("oops", status: 500) }
    let books = [Self.bybitInverse, Self.bybitLinear, Self.bybitSpot,
                 Self.book("bybit", .delivery, "BTCUSDT-26DEC26"),
                 Self.book("bybit", .delivery, "BTCUSDH26", .inverse(contractUsd: 1))]
    #expect(Self.catalog(.direct, server: dead).adapters(books).map(\.name) == [
      "Bybit现货 BTCUSDT", "BybitU 本位 BTCUSDT,BTCUSDT-26DEC26", "Bybit币本位 BTCUSD,BTCUSDH26",
    ])
    #expect(Self.catalog(.gateway, server: dead, gateways: []).adapters(books).isEmpty)
  }

  // ---------------------------------------------------------------- Hyperliquid

  @Test("Hyperliquid：l2Book 每帧整本（snapshotOnly，20 档、nSigFigs 4 的格），time 当序号与事件时间")
  func hyperliquidBooks() {
    let a = Self.hyperliquid([Self.hlBTC, Self.hlPEPE])
    #expect(Self.hlBTC.venue.sequenceModel == .snapshotOnly && Self.hlBTC.venue.snapshotInBand)
    #expect(Self.hlBTC.venue.label == "Hyperliquid")
    #expect(a.decode(Self.hlBook()) == [VenueMessage(Self.hlBTC.id, .snapshot(BookSnapshot(
      lastUpdateID: 1791457528657, requestedLevels: 20,
      bids: [BookLevel(price: 82640, quantity: 7.49922), BookLevel(price: 82630, quantity: 25.77217),
             BookLevel(price: 82620, quantity: 76.81878)],
      asks: [BookLevel(price: 82650, quantity: 7.81391), BookLevel(price: 82660, quantity: 31.65547),
             BookLevel(price: 82670, quantity: 51.15626)],
      eventTimeMs: 1791457528657, slidingWindow: true)))])
    // kPEPE（千枚）：价格原样，1e-6 的格。
    let pepe = Self.hlBook("kPEPE",
      bids: #"[{"px":"0.004031","sz":"773030.0","n":4},{"px":"0.00403","sz":"5208676.0","n":11}]"#,
      asks: #"[{"px":"0.004032","sz":"243777.0","n":1},{"px":"0.004033","sz":"1833073.0","n":5}]"#)
    guard case .snapshot(let s)? = a.decode(pepe).first?.message else { Issue.record("kPEPE 没解出快照"); return }
    #expect(s.bids.first == BookLevel(price: 0.004031, quantity: 773030) && s.asks.count == 2)
    // 不在这条连接上的币、超过 20 档、坏档位：不认。
    #expect(a.decode(Self.hlBook("ETH")).isEmpty)
    let rows: [String] = (0..<21).map { (k: Int) -> String in
      let px = String(80000 - k * 10)
      return #"{"px":""# + px + #"","sz":"1","n":1}"#
    }
    let many = "[" + rows.joined(separator: ",") + "]"
    #expect(a.decode(Self.hlBook(bids: many)).isEmpty)
    #expect(a.decode(Self.hlBook(bids: #"[{"px":"x","sz":"1","n":1}]"#)).isEmpty)
  }

  @Test("Hyperliquid：trades 的 side B 吃卖盘、A 吃买盘；pong 与 subscriptionResponse 不认")
  func hyperliquidTradesAndControlFrames() {
    let a = Self.hyperliquid([Self.hlBTC])
    let text = #"{"channel":"trades","data":[{"coin":"BTC","side":"B","px":"82625.0","sz":"0.00025","time":1791457522600,"hash":"0x0c2736aecb9282fe0da004461b25370207a600946695a1d0afefe2018a965ce8","tid":615263281857618,"users":["0xf5d81a135f756ca16544e53c20fc20643ec3ad53","0xe4baa9cd51176265ef709a81307f9971030009e6"]},{"coin":"BTC","side":"A","px":"82620.0","sz":"1.5","time":1791457522700,"hash":"0x0","tid":1,"users":[]}]}"#
    #expect(a.decode(text) == [
      VenueMessage(Self.hlBTC.id, .trade(OrderFlowTrade(price: 82625, quantity: 0.00025, hitSide: .ask, timeMs: 1791457522600))),
      VenueMessage(Self.hlBTC.id, .trade(OrderFlowTrade(price: 82620, quantity: 1.5, hitSide: .bid, timeMs: 1791457522700))),
    ])
    for control in [
      #"{"channel":"pong"}"#,
      #"{"channel":"subscriptionResponse","data":{"method":"subscribe","subscription":{"type":"l2Book","coin":"BTC","nSigFigs":4,"mantissa":null,"fast":false}}}"#,
      #"{"channel":"subscriptionResponse","data":{"method":"subscribe","subscription":{"type":"trades","coin":"BTC"}}}"#,
    ] {
      #expect(a.decode(control).isEmpty, "\(control)")
    }
  }

  @Test("Hyperliquid：拨中继 /v1/market/ws/hyperliquid，每本订 l2Book（nSigFigs 4）+ trades，一条最多 8 本；30 秒 ping、60 秒没帧才算断")
  func hyperliquidRoute() async throws {
    let deck = ReplayDeck([.hang])
    let a = Self.hyperliquid([Self.hlBTC], deck: deck)
    let s = try await a.connect(candidate: 0); await s.cancel()
    let stats = await deck.stats()
    #expect(stats.urls.map(\.absoluteString) == ["wss://gw-a.example/v1/market/ws/hyperliquid"])
    #expect(stats.sent == [
      #"{"method":"subscribe","subscription":{"coin":"BTC","nSigFigs":4,"type":"l2Book"}}"#,
      #"{"method":"subscribe","subscription":{"coin":"BTC","type":"trades"}}"#,
    ])
    #expect(a.keepAlive == DepthKeepAlive(text: #"{"method":"ping"}"#, everyMs: 30_000))
    #expect(await DepthStream(adapter: a).silenceMs == 60_000)
    #expect(await DepthStream(adapter: a, silenceMs: 5_000).silenceMs == 5_000)
    #expect(await DepthStream(adapter: Self.okx()).silenceMs == DepthStream.defaultSilenceMs)
    #expect(Self.hyperliquid((0..<10).map { Self.book("hyperliquid", .usdtPerp, "C\($0)") }).books.count == 8)
    // 品种表里 10 本 → 两条连接（8 + 2）；没有 kanpan-api 主机不订。
    let dead = FakeServer { _ in json("oops", status: 500) }
    let ten = (0..<10).map { Self.book("hyperliquid", .usdtPerp, "C\($0)") }
    #expect(Self.catalog(.direct, server: dead).adapters(ten).count == 2)
    #expect(Self.catalog(.direct, server: dead, gateways: []).adapters(ten).isEmpty)
  }

  @Test("Bybit / Hyperliquid 的帧把各自那本簿带到就绪：Bybit 快照后按 u 接、跳号要单本重订；Hyperliquid 每帧整本替换")
  func bybitHyperliquidFeedTheModel() {
    let thresholds = OrderFlowThresholds(spot: 1_000_000, usdtPerp: 5_000_000, coinPerp: 5_000_000, delivery: 5_000_000, step: 100)
    var model = OrderFlowModel(symbol: "BTCUSDT", thresholds: thresholds)
    for book in [Self.bybitSpot, Self.hlBTC] { model.addVenue(book.venue) }
    #expect(model.connectionOpened(Self.bybitSpot.id) == .none)
    #expect(model.connectionOpened(Self.hlBTC.id) == .none)
    let bybit = Self.bybit(.spot, [Self.bybitSpot])
    for text in [Self.bybitSpotSnapshot, Self.bybitSpotDelta] {
      for m in bybit.decode(text) { #expect(model.ingest(m.venueID, m.message, nowMs: 1) == .none) }
    }
    #expect(model.isReady(Self.bybitSpot.id))
    // 跳号（u 58035069 → 58035071）：这一本要重来。
    let gap = Self.bybitSpotDelta.replacingOccurrences(of: "\"u\":58035069", with: "\"u\":58035071")
    let actions = bybit.decode(gap).map { model.ingest($0.venueID, $0.message, nowMs: 2) }
    #expect(actions.contains { $0 != .none })
    #expect(!model.isReady(Self.bybitSpot.id))

    let hl = Self.hyperliquid([Self.hlBTC])
    for m in hl.decode(Self.hlBook()) { #expect(model.ingest(m.venueID, m.message, nowMs: 3) == .none) }
    #expect(model.isReady(Self.hlBTC.id))
    // 下一帧时间相同（同一时刻两次推送）或更早也照样整本替换，不当跳号。
    for m in hl.decode(Self.hlBook(time: 1791457528657, bids: #"[{"px":"82645.0","sz":"2.48515","n":22}]"#)) {
      #expect(model.ingest(m.venueID, m.message, nowMs: 4) == .none)
    }
    #expect(model.isReady(Self.hlBTC.id))
  }
}
