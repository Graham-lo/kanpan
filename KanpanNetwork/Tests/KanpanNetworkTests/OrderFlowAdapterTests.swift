import Foundation
import Testing
@testable import KanpanNetwork
import KanpanNetworkTestSupport
import KanpanCore

/// 主力订单流三家适配器：连哪儿、订什么、帧怎么解、快照从哪儿拿；以及连接客户端的重连。
@Suite("主力订单流 · 深度适配器")
struct OrderFlowAdapterTests {
  static let hosts = BinanceHosts(oiProxy: "gw-a.example", oiProxyFallbacks: ["gw-b.example:8443"])

  static func binance(_ policy: MarketRoutePolicy, server: FakeServer = FakeServer { _ in json("{}") },
                      deck: ReplayDeck = ReplayDeck([.hang])) -> BinanceDepthAdapter {
    BinanceDepthAdapter(symbol: "BTCUSDT", hosts: hosts, route: MarketRoute(policy: policy, endpoints: MarketEndpoints(gateways: hosts.oiProxies)),
                        sockets: ReplayFactory(deck: deck, pacer: FastPacer()), http: FakeTransport(server))
  }

  // ---------------------------------------------------------------- 币安

  @Test("币安：组合流里的 depthUpdate 解成带 U/u/pu 的增量")
  func binanceDelta() {
    let a = Self.binance(.direct)
    let text = #"{"stream":"btcusdt@depth@100ms","data":{"e":"depthUpdate","E":1700000000123,"T":1700000000120,"s":"BTCUSDT","U":100,"u":105,"pu":99,"b":[["78450.1","3.5"],["78449.0","0"]],"a":[["78460.0","1.25"]]}}"#
    let out = a.decode(text)
    #expect(out == [.delta(BookDelta(firstUpdateID: 100, finalUpdateID: 105, previousFinalUpdateID: 99,
                                     bids: [BookLevel(price: 78450.1, quantity: 3.5), BookLevel(price: 78449, quantity: 0)],
                                     asks: [BookLevel(price: 78460, quantity: 1.25)], eventTimeMs: 1700000000123))])
    // 别的品种、坏档位一律不认。
    #expect(a.decode(text.replacingOccurrences(of: "\"s\":\"BTCUSDT\"", with: "\"s\":\"ETHUSDT\"")).isEmpty)
    #expect(a.decode(text.replacingOccurrences(of: "\"3.5\"", with: "\"x\"")).isEmpty)
  }

  @Test("币安：aggTrade 的 m=true 是主动卖，吃买盘")
  func binanceTrade() {
    let a = Self.binance(.gateway)
    let sell = #"{"stream":"btcusdt@aggTrade","data":{"e":"aggTrade","s":"BTCUSDT","p":"78450","q":"0.5","m":true,"T":1700000000500}}"#
    #expect(a.decode(sell) == [.trade(OrderFlowTrade(price: 78450, quantity: 0.5, hitSide: .bid, timeMs: 1700000000500))])
    let buy = sell.replacingOccurrences(of: "\"m\":true", with: "\"m\":false")
    #expect(a.decode(buy) == [.trade(OrderFlowTrade(price: 78450, quantity: 0.5, hitSide: .ask, timeMs: 1700000000500))])
  }

  @Test("币安直连：推送拨 dstream 组合流（深度 + 成交），快照打 fapi 1000 档")
  func binanceDirectRoute() async throws {
    let deck = ReplayDeck([.hang])
    let server = FakeServer { _ in json(#"{"lastUpdateId":777,"E":1700000000000,"T":1,"bids":[["100","2"]],"asks":[["101","3"]]}"#) }
    let a = Self.binance(.direct, server: server, deck: deck)
    #expect(a.sequenceModel == .previousFinalOverlap)
    #expect(!a.snapshotInBand)
    let s = try await a.connect(candidate: 0); await s.cancel()
    let url = try #require(await deck.stats().urls.first)
    #expect(url.absoluteString == "wss://dstream.binance.me/stream?streams=btcusdt@depth@100ms/btcusdt@aggTrade")
    let snap = try await a.fetchSnapshot()
    #expect(snap == BookSnapshot(lastUpdateID: 777, requestedLevels: 1000, bids: [BookLevel(price: 100, quantity: 2)],
                                 asks: [BookLevel(price: 101, quantity: 3)], eventTimeMs: 1700000000000))
    #expect(await server.urls().map(\.absoluteString) == ["https://fapi.binance.com/fapi/v1/depth?limit=1000&symbol=BTCUSDT"])
  }

  @Test("币安网关：推送拨网关 /market/stream，快照打 kanpan-api，主节点 503 就换备用")
  func binanceGatewayRoute() async throws {
    let deck = ReplayDeck([.hang])
    let server = FakeServer { url in
      url.host == "gw-a.example"
        ? json(#"{"error":{"code":"market_upstream_unavailable"}}"#, status: 503, headers: ["Retry-After": "2"])
        : json(#"{"lastUpdateId":9,"bids":[["100","2"]],"asks":[["101","3"]]}"#)
    }
    let a = Self.binance(.gateway, server: server, deck: deck)
    let s = try await a.connect(candidate: 0); await s.cancel()
    let url = try #require(await deck.stats().urls.first)
    #expect(url.absoluteString == "wss://gw-a.example/market/stream?streams=btcusdt@depth@100ms/btcusdt@aggTrade")
    #expect(a.streamURLs.map(\.absoluteString) == [
      "wss://gw-a.example/market/stream?streams=btcusdt@depth@100ms/btcusdt@aggTrade",
      "wss://gw-b.example:8443/market/stream?streams=btcusdt@depth@100ms/btcusdt@aggTrade",
    ])
    let snap = try await a.fetchSnapshot()
    #expect(snap.lastUpdateID == 9)
    #expect(await server.urls().map(\.absoluteString) == [
      "https://gw-a.example/v1/market/depth?symbol=BTCUSDT&limit=1000",
      "https://gw-b.example:8443/v1/market/depth?symbol=BTCUSDT&limit=1000",
    ])
  }

  @Test("币安网关：4xx（品种不认）直接报，不换主机")
  func binanceGatewayClientError() async throws {
    let server = FakeServer { _ in json(#"{"error":{"code":"unknown_symbol"}}"#, status: 400) }
    let a = Self.binance(.gateway, server: server)
    await #expect(throws: DepthSnapshotError(status: 400, retryAfterMs: nil)) { try await a.fetchSnapshot() }
    #expect(await server.urls().count == 1)
  }

  // ---------------------------------------------------------------- OKX

  static func okx(deck: ReplayDeck = ReplayDeck([.hang])) -> OKXBooksAdapter {
    OKXBooksAdapter(symbol: "BTCUSDT", gateways: hosts.oiProxies, sockets: ReplayFactory(deck: deck, pacer: FastPacer()))
  }

  static func okxFrame(_ action: String, seq: Int64, prev: Int64, bids: String = #"[["78450.1","350","0","4"]]"#,
                       asks: String = #"[["78460","20","0","1"]]"#) -> String {
    #"{"stream":"btcusdt@depth@100ms","source":"okx","ctVal":"0.01","data":{"arg":{"channel":"books","instId":"BTC-USDT-SWAP"},"action":""# + action + #"","data":[{"asks":"# + asks + #","bids":"# + bids + #","ts":"1700000000999","checksum":0,"prevSeqId":"# + String(prev) + #","seqId":"# + String(seq) + "}]}}"
  }

  @Test("OKX：books 首帧是流内快照，张数乘 ctVal；update 按 seqId/prevSeqId；倒退就重置")
  func okxBooks() {
    let a = Self.okx()
    #expect(a.sequenceModel == .previousFinalExact && a.snapshotInBand)
    #expect(a.decode(Self.okxFrame("snapshot", seq: 10, prev: -1)) == [
      .snapshot(BookSnapshot(lastUpdateID: 10, requestedLevels: 400, bids: [BookLevel(price: 78450.1, quantity: 3.5)],
                             asks: [BookLevel(price: 78460, quantity: 0.2)], eventTimeMs: 1700000000999))])
    #expect(a.decode(Self.okxFrame("update", seq: 12, prev: 10, bids: "[]")) == [
      .delta(BookDelta(firstUpdateID: 12, finalUpdateID: 12, previousFinalUpdateID: 10, bids: [],
                       asks: [BookLevel(price: 78460, quantity: 0.2)], eventTimeMs: 1700000000999))])
    #expect(a.decode(Self.okxFrame("update", seq: 5, prev: 12)) == [.reset])
    // 别的频道名、没有 ctVal、订阅回执：不认。
    #expect(a.decode(Self.okxFrame("update", seq: 13, prev: 12).replacingOccurrences(of: "btcusdt@", with: "ethusdt@")).isEmpty)
    #expect(a.decode(Self.okxFrame("update", seq: 13, prev: 12).replacingOccurrences(of: #""ctVal":"0.01","#, with: "")).isEmpty)
    #expect(a.decode(#"{"stream":"btcusdt@depth@100ms","source":"okx","ctVal":"0.01","data":{"event":"subscribe","arg":{"channel":"books"}}}"#).isEmpty)
  }

  @Test("OKX：trades 的 side 是主动方，sz 也是张数")
  func okxTrades() {
    let a = Self.okx()
    let text = #"{"stream":"btcusdt@aggTrade","source":"okx","ctVal":"0.01","data":{"arg":{"channel":"trades","instId":"BTC-USDT-SWAP"},"data":[{"instId":"BTC-USDT-SWAP","tradeId":"1","px":"78450","sz":"30","side":"sell","ts":"1700000000001","count":"1"},{"instId":"BTC-USDT-SWAP","tradeId":"2","px":"78460","sz":"5","side":"buy","ts":"1700000000002","count":"1"}]}}"#
    #expect(a.decode(text) == [
      .trade(OrderFlowTrade(price: 78450, quantity: 0.3, hitSide: .bid, timeMs: 1700000000001)),
      .trade(OrderFlowTrade(price: 78460, quantity: 0.05, hitSide: .ask, timeMs: 1700000000002)),
    ])
  }

  @Test("OKX：只走网关 /market/okx/stream，深度与成交同一条连接")
  func okxRoute() async throws {
    let deck = ReplayDeck([.hang])
    let s = try await Self.okx(deck: deck).connect(candidate: 0); await s.cancel()
    let url = try #require(await deck.stats().urls.first)
    #expect(url.absoluteString == "wss://gw-a.example/market/okx/stream?streams=btcusdt@depth@100ms/btcusdt@aggTrade")
  }

  // ---------------------------------------------------------------- Coinbase

  @Test("Coinbase：直连订 level2 / market_trades / heartbeats 三个频道")
  func coinbaseSubscribe() async throws {
    let deck = ReplayDeck([.hang])
    let a = CoinbaseLevel2Adapter(symbol: "coinbase/spot/BTC-USD", sockets: ReplayFactory(deck: deck, pacer: FastPacer()))
    #expect(a.symbol == "BTC-USD" && a.sequenceModel == .strictIncrementing && a.snapshotInBand)
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
    let a = CoinbaseLevel2Adapter(symbol: "BTC-USD")
    let advance: (Int64) -> DepthMessage = { .delta(BookDelta(firstUpdateID: $0, finalUpdateID: $0, previousFinalUpdateID: nil)) }
    #expect(a.decode(#"{"channel":"subscriptions","sequence_num":0,"events":[]}"#) == [advance(0)])
    #expect(a.decode(#"{"channel":"heartbeats","sequence_num":3,"events":[{"heartbeat_counter":1}]}"#) == [advance(3)])
    let snap = #"{"channel":"l2_data","sequence_num":1,"events":[{"type":"snapshot","product_id":"BTC-USD","updates":[{"side":"bid","event_time":"2026-09-24T01:02:03.456789Z","price_level":"60000","new_quantity":"1.5"},{"side":"bid","event_time":"2026-09-24T01:02:03.456789Z","price_level":"59990","new_quantity":"2"},{"side":"offer","event_time":"2026-09-24T01:02:03.456789Z","price_level":"60010","new_quantity":"0.5"}]}]}"#
    guard case .snapshot(let s)? = a.decode(snap).first else { Issue.record("不是快照"); return }
    #expect(s.lastUpdateID == 1 && s.requestedLevels == 3 && s.bids.count == 2 && s.asks == [BookLevel(price: 60010, quantity: 0.5)])
    #expect(s.eventTimeMs == CoinbaseDTO.isoMs("2026-09-24T01:02:03.456Z"))
    let update = #"{"channel":"l2_data","sequence_num":2,"events":[{"type":"update","product_id":"BTC-USD","updates":[{"side":"offer","event_time":"2026-09-24T01:02:04Z","price_level":"60010","new_quantity":"0"}]}]}"#
    #expect(a.decode(update) == [.delta(BookDelta(firstUpdateID: 2, finalUpdateID: 2, previousFinalUpdateID: nil, bids: [],
                                                  asks: [BookLevel(price: 60010, quantity: 0)],
                                                  eventTimeMs: CoinbaseDTO.isoMs("2026-09-24T01:02:04Z")!))])
    let trades = #"{"channel":"market_trades","sequence_num":4,"events":[{"type":"snapshot","trades":[{"product_id":"BTC-USD","price":"1","size":"1","side":"BUY","time":"2026-09-24T01:00:00Z"}]},{"type":"update","trades":[{"trade_id":"9","product_id":"BTC-USD","price":"60010","size":"0.25","side":"BUY","time":"2026-09-24T01:02:05Z"},{"trade_id":"10","product_id":"BTC-USD","price":"60000","size":"0.1","side":"SELL","time":"2026-09-24T01:02:05Z"}]}]}"#
    let t = CoinbaseDTO.isoMs("2026-09-24T01:02:05Z")!
    #expect(a.decode(trades) == [advance(4),
                                 .trade(OrderFlowTrade(price: 60010, quantity: 0.25, hitSide: .ask, timeMs: t)),
                                 .trade(OrderFlowTrade(price: 60000, quantity: 0.1, hitSide: .bid, timeMs: t))])
    #expect(a.decode(#"{"type":"error","message":"nope"}"#).isEmpty)
  }

  // ---------------------------------------------------------------- 工厂

  @Test("工厂：币安直连 → 币安适配器，网关（OKX 替身）→ OKX 适配器，Coinbase 恒直连")
  func factory() {
    let direct: any MarketProvider = BinanceProvider(upstream: .binance, hosts: Self.hosts, policy: .direct)
    let gateway: any MarketProvider = BinanceProvider(upstream: .okx, hosts: Self.hosts, policy: .gateway)
    let coinbase: any MarketProvider = CoinbaseProvider(policy: .gateway, endpoints: MarketEndpoints(gateways: ["gw-a.example"]))
    #expect(direct.orderFlowAdapter(symbol: "BTCUSDT") is BinanceDepthAdapter)
    #expect(gateway.orderFlowAdapter(symbol: "BTCUSDT") is OKXBooksAdapter)
    #expect(coinbase.orderFlowAdapter(symbol: "coinbase/spot/BTC-USD") is CoinbaseLevel2Adapter)
    #expect(direct.orderFlowAdapter(symbol: "BTCUSDT")?.upstream == "binance")
    #expect(gateway.orderFlowAdapter(symbol: "BTCUSDT")?.upstream == "okx")
    #expect(coinbase.orderFlowAdapter(symbol: "BTC-USD")?.upstream == "coinbase")
  }

  // ---------------------------------------------------------------- 连接客户端

  @Test("连接客户端：断线退避重连，新连接号先于它的消息；主动 reconnect 立刻重拨")
  func streamReconnects() async throws {
    let first = Self.okxFrame("snapshot", seq: 10, prev: -1)
    let deck = ReplayDeck([.frame(.text(first)), .frame(.text("{}")), .drop("bye"),
                           .frame(.text(Self.okxFrame("snapshot", seq: 20, prev: -1))), .hang])
    let pacer = FastPacer()
    let stream = DepthStream(adapter: OKXBooksAdapter(symbol: "BTCUSDT", gateways: Self.hosts.oiProxies,
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
    let stream = DepthStream(adapter: OKXBooksAdapter(symbol: "BTCUSDT", gateways: Self.hosts.oiProxies,
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
    let stream = DepthStream(adapter: OKXBooksAdapter(symbol: "BTCUSDT", gateways: Self.hosts.oiProxies,
                                                      sockets: ReplayFactory(deck: deck, pacer: pacer)),
                             pacer: pacer, silenceMs: 30_000)
    let events = await stream.start()
    let log = EventLog()
    let reader = Task { for await e in events { await log.note(e) } }
    #expect(await waitUntil(5) { await log.lines.contains("connected 2") })
    await stream.stop()
    reader.cancel()
  }

  @Test("适配器与本地簿对得上：OKX 快照 + 增量把模型带到就绪")
  func okxFeedsTheModel() {
    let a = Self.okx()
    var model = OrderFlowModel(symbol: "BTCUSDT", sequenceModel: a.sequenceModel, snapshotInBand: a.snapshotInBand,
                               scheme: nil, calibration: FloorCalibration())
    #expect(model.connectionOpened() == .none)
    for text in [Self.okxFrame("update", seq: 9, prev: 8), Self.okxFrame("snapshot", seq: 10, prev: -1),
                 Self.okxFrame("update", seq: 11, prev: 10)] {
      for m in a.decode(text) { #expect(model.ingest(m, nowMs: 1) == .none) }
    }
    #expect(model.isReady)
  }
}

private actor EventLog {
  var lines: [String] = []
  func note(_ e: DepthStreamEvent) {
    switch e {
    case .connected(let n): lines.append("connected \(n)")
    case .disconnected: lines.append("disconnected")
    case .messages(let ms):
      for m in ms {
        if case .snapshot(let s) = m { lines.append("snapshot \(s.lastUpdateID)") } else { lines.append("message") }
      }
    }
  }
}
