import Foundation
import Testing
@testable import KanpanData
import KanpanCore

// 逐笔折线（§4.4 补充）。
//
// 背景：2026-09 起主网合约的 `@kline_*` / `@aggTrade` / `@ticker` 三路只回订阅确认、
// 一帧数据都不推（六条线路实测，见 M2 证据），末根就永远停在 REST 拉回来的那一刻。
// `@trade` 和 `@bookTicker` 是活的，所以改成自己收线：每笔成交按撮合时间算出属于
// 哪个桶，落在末根上就更新高/低/收并累加量，跨过去就开新的一根；REST 隔一会儿
// 拿权威值对一次表，但当前那根的收盘留自己折出来的，免得价格一秒往回跳一次。
@Suite("逐笔折线")
struct TickFoldTests {

  private func bars(t0: Int64, step: Int64, count: Int, px: Double = 100) -> [Bar] {
    (0..<count).map { i in
      Bar(openTime: t0 + Int64(i) * step, open: px, high: px, low: px, close: px, volume: 1)
    }
  }

  private func composer(_ iv: Interval = .m1, count: Int = 3) -> FeedComposer {
    FeedComposer(series: BarSeries(symbol: "BTCUSDT", interval: iv,
                                   bars: bars(t0: 0, step: iv.stepMs, count: count)))
  }

  @Test("落在末根上：收盘跟着走，高低取极值，量累加")
  func foldIntoLastBar() {
    var c = composer()
    let last = c.series.lastTime          // 2 * 60_000
    let r1 = c.applyTick(price: 105, qty: 0.5, timeMs: last + 1_000)
    #expect(r1 == .updated)
    #expect(c.series.count == 3)
    #expect(c.series.close[2] == 105)
    #expect(c.series.high[2] == 105)
    #expect(c.series.low[2] == 100)
    #expect(c.series.volume[2] == 1.5)

    let r2 = c.applyTick(price: 95, qty: 0.25, timeMs: last + 2_000)
    #expect(r2 == .updated)
    #expect(c.series.close[2] == 95)
    #expect(c.series.high[2] == 105)      // 高点不会被后来的低价抹掉
    #expect(c.series.low[2] == 95)
    #expect(c.series.volume[2] == 1.75)
    #expect(c.series.open[2] == 100)      // 开盘一直是原来那个
  }

  @Test("跨过周期边界就开新的一根，开=高=低=收=这一笔")
  func foldAppendsNewBar() {
    var c = composer()
    let last = c.series.lastTime
    let r3 = c.applyTick(price: 111, qty: 2, timeMs: last + 60_000)
    #expect(r3 == .appended)
    #expect(c.series.count == 4)
    #expect(c.series.lastTime == last + 60_000)
    #expect(c.series.open[3] == 111)
    #expect(c.series.high[3] == 111)
    #expect(c.series.low[3] == 111)
    #expect(c.series.close[3] == 111)
    #expect(c.series.volume[3] == 2)
  }

  @Test("桶按撮合时间算，同一根内的时间不会开新根")
  func bucketByTradeTime() {
    var c = composer(.h1)
    let last = c.series.lastTime
    // 这一小时里的任何时刻都该落在同一根上
    for ms: Int64 in [1, 59 * 60_000, 3_599_999] {
      let r4 = c.applyTick(price: 100 + Double(ms % 7), qty: 0.1, timeMs: last + ms)
      #expect(r4 == .updated)
    }
    #expect(c.series.count == 3)
    // 再多 1 毫秒就跨过去了
    let r5 = c.applyTick(price: 120, qty: 1, timeMs: last + 3_600_000)
    #expect(r5 == .appended)
    #expect(c.series.count == 4)
  }

  @Test("过期、补缺中、价格不合法、序列空着都不折")
  func foldIgnores() {
    var c = composer()
    let last = c.series.lastTime
    // 比末根还早
    let r6 = c.applyTick(price: 100, qty: 1, timeMs: last - 60_000)
    #expect(r6 == .ignored)
    #expect(c.droppedStale == 1)
    // 价格不合法
    let r7 = c.applyTick(price: 0, qty: 1, timeMs: last)
    #expect(r7 == .ignored)
    let r8 = c.applyTick(price: .nan, qty: 1, timeMs: last)
    #expect(r8 == .ignored)
    #expect(c.series.volume[2] == 1)
    // 补缺期间：REST 马上就要整段盖过来，这会儿改末根只会打架
    c.beginBackfill()
    let r9 = c.applyTick(price: 200, qty: 1, timeMs: last)
    #expect(r9 == .ignored)
    #expect(c.series.close[2] == 100)
    _ = c.endBackfill(with: [])
    // 序列空着没有锚点
    var empty = FeedComposer(series: BarSeries(symbol: "BTCUSDT", interval: .m1, t0: 0,
                                               open: [], high: [], low: [], close: [], volume: []))
    let r10 = empty.applyTick(price: 100, qty: 1, timeMs: 0)
    #expect(r10 == .ignored)
  }

  @Test("挂单心跳只改价不记量，也不凭它开新的一根")
  func bookTickerHeartbeat() {
    var c = composer()
    let last = c.series.lastTime
    let r11 = c.applyTick(price: 108, qty: 0, timeMs: last + 1_000, allowAppend: false)
    #expect(r11 == .updated)
    #expect(c.series.close[2] == 108)
    #expect(c.series.volume[2] == 1)              // 量一点没动
    // 跨桶了也不许开新根——买一卖一的中间价不是成交价
    let r12 = c.applyTick(price: 130, qty: 0, timeMs: last + 60_000, allowAppend: false)
    #expect(r12 == .ignored)
    #expect(c.series.count == 3)
  }

  // ---------------------------------------------------------------- 对表

  @Test("对表：已收线的照单全收，还在走的那根收盘留自己的")
  func reconcileKeepsLiveClose() {
    var c = composer()
    let last = c.series.lastTime
    // 逐笔把末根推到 105
    let r13 = c.applyTick(price: 105, qty: 0.5, timeMs: last + 1_000)
    #expect(r13 == .updated)
    // REST 慢一拍：它看到的收盘还是 101，量是权威的 9
    let r14 = c.reconcile([Bar(openTime: last, open: 100, high: 103, low: 97, close: 101, volume: 9)])
    #expect(r14)
    #expect(c.series.close[2] == 105)     // 收盘不许往回跳
    #expect(c.series.high[2] == 105)      // 高低取并集
    #expect(c.series.low[2] == 97)
    #expect(c.series.volume[2] == 9)      // 量取两者的大者，权威值赢
  }

  @Test("对表：这根还没被折过就认 REST 的收盘")
  func reconcileTakesRestCloseWhenNoTick() {
    var c = composer()
    let last = c.series.lastTime
    let r15 = c.reconcile([Bar(openTime: last, open: 100, high: 103, low: 97, close: 101, volume: 9)])
    #expect(r15)
    #expect(c.series.close[2] == 101)
  }

  @Test("对表：REST 带回来的新一根直接接上，旧的那根拿权威值盖回去")
  func reconcileClosesBar() {
    var c = composer()
    let last = c.series.lastTime
    // 我们靠逐笔开了下一根，但它的开盘/量都是我们猜的
    let r16 = c.applyTick(price: 111, qty: 0.1, timeMs: last + 60_000)
    #expect(r16 == .appended)
    let nt = last + 60_000
    let rr = c.reconcile([
      // 上一根真正的收线值
      Bar(openTime: last, open: 100, high: 100, low: 100, close: 100, volume: 88),
      // 这一根的权威值
      Bar(openTime: nt, open: 110, high: 112, low: 109, close: 110.5, volume: 7),
    ])
    #expect(rr)
    #expect(c.series.count == 4)
    #expect(c.series.volume[2] == 88)     // 收了线的那根整根盖掉
    #expect(c.series.close[2] == 100)
    #expect(c.series.open[3] == 110)      // 开盘认权威
    #expect(c.series.close[3] == 111)     // 收盘还是我们折的（这根被折过）
    #expect(c.series.high[3] == 112)
    #expect(c.series.low[3] == 109)
    #expect(c.series.volume[3] == 7)
  }

  @Test("换一段序列，折线状态跟着清掉")
  func replaceResetsTickState() {
    var c = composer()
    let r17 = c.applyTick(price: 105, qty: 1, timeMs: c.series.lastTime)
    #expect(r17 == .updated)
    #expect(c.lastTickMs > 0)
    c.replace(BarSeries(symbol: "ETHUSDT", interval: .m5, bars: bars(t0: 0, step: 300_000, count: 2)))
    #expect(c.lastTickMs == 0)
    // 新序列没被折过，对表该认 REST 的收盘
    let r18 = c.reconcile([Bar(openTime: 300_000, open: 1, high: 2, low: 0.5, close: 1.5, volume: 3)])
    #expect(r18)
    #expect(c.series.close[1] == 1.5)
  }

  // ---------------------------------------------------------------- 报文

  @Test("trade / bookTicker 报文解得出来")
  func decodeStreams() throws {
    let trade = """
    {"stream":"btcusdt@trade","data":{"e":"trade","E":1789382760123,"T":1789382760100,\
    "s":"BTCUSDT","t":88,"p":"77930.10","q":"0.052","X":"MARKET","m":true}}
    """
    let env = try JSONDecoder().decode(StreamEnvelope.self, from: Data(trade.utf8))
    guard case .trade(let t)? = env.payload else {
      Issue.record("没解成 trade：\(String(describing: env.payload))"); return
    }
    #expect(t.symbol == "BTCUSDT")
    #expect(t.price == 77930.10)
    #expect(t.qty == 0.052)
    #expect(t.timeMs == 1789382760100)    // 用撮合时间 T，不是事件时间 E

    let book = """
    {"stream":"btcusdt@bookTicker","data":{"e":"bookTicker","u":400900217,\
    "E":1789382760893,"T":1789382760891,"s":"BTCUSDT","b":"77929.90","B":"31.2","a":"77930.20","A":"40.6"}}
    """
    let env2 = try JSONDecoder().decode(StreamEnvelope.self, from: Data(book.utf8))
    guard case .bookTicker(let sym, let bid, let ask, let ms)? = env2.payload else {
      Issue.record("没解成 bookTicker：\(String(describing: env2.payload))"); return
    }
    #expect(sym == "BTCUSDT")
    #expect(bid == 77929.90)
    #expect(ask == 77930.20)
    #expect(ms == 1789382760891)
  }

  @Test("组合行情端点使用 market 路由，替换品种仍可复用连接")
  func marketEndpoint() throws {
    let url = BinanceHosts.default.combinedStream(["btcusdt@kline_1m", "btcusdt@ticker", "btcusdt@markPrice@1s"])
    #expect(url.path == "/market/stream")
    let query = try #require(URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?.first?.value)
    #expect(query == "btcusdt@kline_1m/btcusdt@ticker/btcusdt@markPrice@1s")
    #expect(BinanceHosts(stream: "custom.example").combinedStream([]).host == "custom.example")
  }
}
