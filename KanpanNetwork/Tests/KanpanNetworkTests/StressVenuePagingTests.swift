import Foundation
import Testing
@testable import KanpanNetwork
import KanpanNetworkTestSupport
import KanpanCore

// 压测（2026-10-08）：三家 K 线翻页与补缺的极端。
// 假上游按各家官方口径模拟（OKX `candles` 只覆盖最近 1440 根、`after` 取更早；Bybit `start` / `end`；
// Hyperliquid 只留最近 5000 根），再在上面做手脚：回空页、无视游标、一页里夹一行坏数、`end` 含 / 不含、
// 回得比要的多 / 少。判据：拼回来的 K 线连续、不重不漏，请求数有界，翻到头就不再问。

private enum Clock {
  /// 2026-09-22 23:19:46 UTC。
  static let now = Date(timeIntervalSince1970: 1_790_119_186)
  static let nowMs: Int64 = 1_790_119_186_000
  static let hour: Int64 = 3_600_000
  static let currentHour: Int64 = 1_790_118_000_000

  static func query(_ url: URL, _ name: String) -> String? {
    URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?.first { $0.name == name }?.value
  }
}

private func contiguous(_ bars: [Bar], step: Int64) -> Bool {
  zip(bars, bars.dropFirst()).allSatisfy { $1.openTime - $0.openTime == step }
}

// ---------------------------------------------------------------- OKX

/// OKX 的 1H K 线上游：`candles` 只覆盖最近 1440 根、一页 ≤ 300；`history-candles` 一页 ≤ 100；新的在前。
private struct OKXUpstream: Sendable {
  var listedAt: Int64 = Clock.currentHour - 6000 * Clock.hour
  /// 早于它的一律回空页（上游这一段没数据）。
  var emptyBefore: Int64?
  /// 无视 `after`，永远回最新那一页（游标不前进）。
  var ignoreCursor = false
  /// 每页第二行换成坏行（高 < 低）。
  var corruptSecondRow = false

  func reply(_ url: URL) -> HTTPReply {
    let history = url.path.hasSuffix("history-candles")
    let cap = history ? 100 : 300
    guard let limit = Clock.query(url, "limit").flatMap(Int.init), limit <= cap else {
      return json(#"{"code":"51000","msg":"Parameter limit error","data":[]}"#, status: 400)
    }
    var newest = Clock.currentHour
    if !ignoreCursor, let after = Clock.query(url, "after").flatMap({ Int64($0) }) {
      newest = (after - 1) / Clock.hour * Clock.hour
    }
    let floor = history ? listedAt : max(listedAt, Clock.currentHour - 1439 * Clock.hour)
    var rows: [String] = []
    var t = newest
    while t >= floor, rows.count < limit {
      if let emptyBefore, t < emptyBefore { break }
      if corruptSecondRow, rows.count == 1 {
        rows.append(#"["\#(t)","1","0.5","2","1.5","100","1","1.5","1"]"#)
      } else {
        rows.append(#"["\#(t)","1","2","0.5","1.5","100","1","1.5","\#(t == Clock.currentHour ? "0" : "1")"]"#)
      }
      t -= Clock.hour
    }
    return json(#"{"code":"0","msg":"","data":[\#(rows.joined(separator: ","))]}"#)
  }
}

private func okx(_ upstream: OKXUpstream) -> (OKXProvider, FakeServer) {
  let server = FakeServer { upstream.reply($0) }
  let route = MarketRoute(policy: .direct, endpoints: MarketEndpoints(gateways: ["gw.example"], api: ["api.example"]))
  return (OKXProvider(route: route, transport: FakeTransport(server),
                      limiter: VenueRateLimiter(perSecond: 1_000_000, pacer: FastPacer()), clock: { Clock.now }),
          server)
}

extension StressVenueSerial {
  @Suite("压测 · OKX 翻页极端", .timeLimit(.minutes(1)))
  struct StressOKXPagingTests {
    @Test("跨 1440 根边界：近处用 candles、过了边界换 history-candles；candles 从不问到它覆盖不到的地方；拼回来连续")
    func crossesRecentBoundary() async throws {
      let (p, server) = okx(OKXUpstream())
      let before = Clock.currentHour - 1000 * Clock.hour
      let bars = try await p.history(symbol: "okx/usd_m/BTCUSDT", interval: .h1, pages: 5, before: before)
      #expect(bars.count == 1500)
      #expect(bars.last?.openTime == before - Clock.hour)
      #expect(contiguous(bars, step: Clock.hour))
      let urls = await server.urls()
      for url in urls where url.path.hasSuffix("/candles") {
        let after = try #require(Clock.query(url, "after").flatMap { Int64($0) })
        let limit = try #require(Clock.query(url, "limit").flatMap { Int64($0) })
        // 这一页最早那根还在最近 1440 根以内。
        #expect(after - limit * Clock.hour >= Clock.currentHour - 1439 * Clock.hour, "candles 问到了覆盖不到的地方：\(url)")
      }
      #expect(urls.contains { $0.path.hasSuffix("/candles") } && urls.contains { $0.path.hasSuffix("history-candles") })
      #expect(urls.count <= 1500 / 100 + 3)
    }

    @Test("上游中途回空页：停下、把已拿到的交回去，不再往前问")
    func emptyPageStops() async throws {
      let cut = Clock.currentHour - 3150 * Clock.hour
      let (p, server) = okx(OKXUpstream(emptyBefore: cut))
      let before = Clock.currentHour - 3000 * Clock.hour
      let bars = try await p.history(symbol: "okx/usd_m/BTCUSDT", interval: .h1, pages: 3, before: before)
      #expect(bars.count == 150 && bars.first?.openTime == cut)
      #expect(contiguous(bars, step: Clock.hour))
      #expect(await server.urls().count == 2)
      // 再往前要一次：一发就知道到头了。
      let more = try await p.history(symbol: "okx/usd_m/BTCUSDT", interval: .h1, pages: 3, before: cut)
      #expect(more.isEmpty)
      #expect(await server.urls().count == 3)
    }

    @Test("上游无视游标（永远回最新一页）：不死循环、不拿更新的 K 线冒充更早的")
    func cursorNotAdvancing() async throws {
      let (p, server) = okx(OKXUpstream(ignoreCursor: true))
      let before = Clock.currentHour - 2000 * Clock.hour
      let bars = try await p.history(symbol: "okx/usd_m/BTCUSDT", interval: .h1, pages: 10, before: before)
      #expect(bars.allSatisfy { $0.openTime < before })
      #expect(await server.urls().count <= 2)
    }

    /// 原来按「解出来几根」判到没到头：一页 100 行里坏一行，解出 99 根 < 100，就当翻到了上线那一根，
    /// 后面再也不往前翻——图往左拖到这里就永远停住。
    @Test("一页里夹一行坏数：只丢那一行，照样往前翻（按上游给了几行判到头，不按解出几根）")
    func corruptRowDoesNotStopPaging() async throws {
      let (p, server) = okx(OKXUpstream(corruptSecondRow: true))
      let before = Clock.currentHour - 3000 * Clock.hour
      let bars = try await p.history(symbol: "okx/usd_m/BTCUSDT", interval: .h1, pages: 1, before: before)
      let pages = await server.urls().count
      #expect(pages >= 3 && pages <= 6, "翻了 \(pages) 页")
      #expect(bars.count == 300)
      #expect(bars.allSatisfy { $0.isValidMarketBar && $0.openTime < before })
    }

    @Test("补缺：缺口超过 maxTailBars 当场报 gapTooLong，一个请求都不发；刚好在上限内照常补")
    func tailLimit() async throws {
      let (p, server) = okx(OKXUpstream())
      let maxTail = Int64(OKXProvider.capabilities.maxTailBars)
      await #expect(throws: FeedError.gapTooLong) {
        _ = try await p.contiguousTail(symbol: "okx/usd_m/BTCUSDT", interval: .h1,
                                       from: Clock.currentHour - maxTail * Clock.hour)
      }
      #expect(await server.urls().isEmpty)
      let from = Clock.currentHour - (maxTail - 3) * Clock.hour
      let bars = try await p.contiguousTail(symbol: "okx/usd_m/BTCUSDT", interval: .h1, from: from)
      #expect(bars.first?.openTime == from && bars.last?.openTime == Clock.currentHour && contiguous(bars, step: Clock.hour))
    }
  }
}

// ---------------------------------------------------------------- Bybit

/// Bybit 的 1H K 线上游：`[start, end]`（或 `end` 不含）里最新的 `limit` 根，新的在前；最早一根是 `listedAt`。
private struct BybitUpstream: Sendable {
  var endInclusive = true
  var listedAt: Int64 = Clock.currentHour - 9000 * Clock.hour

  func reply(_ url: URL) -> HTTPReply {
    guard Clock.query(url, "interval") == "60", let limit = Clock.query(url, "limit").flatMap(Int.init), limit <= 1000 else {
      return json(#"{"retCode":10001,"retMsg":"params error"}"#)
    }
    let start = Clock.query(url, "start").flatMap { Int64($0) } ?? 0
    var end = Clock.query(url, "end").flatMap { Int64($0) } ?? Clock.nowMs
    if !endInclusive { end -= 1 }
    var t = min(Clock.currentHour, end / Clock.hour * Clock.hour)
    var rows: [String] = []
    while t >= max(start, listedAt), rows.count < limit {
      rows.append(#"["\#(t)","1","2","0.5","1.5","10","15"]"#)
      t -= Clock.hour
    }
    return json(#"{"retCode":0,"retMsg":"OK","result":{"category":"linear","symbol":"BTCUSDT","list":[\#(rows.joined(separator: ","))]},"time":\#(Clock.nowMs)}"#)
  }
}

private func bybit(_ upstream: BybitUpstream) -> (BybitProvider, FakeServer) {
  let server = FakeServer { upstream.reply($0) }
  return (BybitProvider(policy: .direct, gateways: ["gw.example"], transport: FakeTransport(server),
                        limiter: VenueRateLimiter(perSecond: 1_000_000, pacer: FastPacer()), clock: { Clock.now }),
          server)
}

extension StressVenueSerial {
  @Suite("压测 · Bybit 翻页极端", .timeLimit(.minutes(1)))
  struct StressBybitPagingTests {
    @Test("end 含 / 不含两种上游：三个窗口首尾相接拼回来 3000 根连续、不重不漏", arguments: [true, false])
    func endInclusiveOrNot(_ inclusive: Bool) async throws {
      let (p, server) = bybit(BybitUpstream(endInclusive: inclusive))
      let before = Clock.currentHour - 100 * Clock.hour
      let bars = try await p.history(symbol: "bybit/usd_m/BTCUSDT", interval: .h1, pages: 3, before: before)
      #expect(bars.count == 3000)
      #expect(bars.last?.openTime == before - Clock.hour && contiguous(bars, step: Clock.hour))
      #expect(await server.urls().count == 3)
      // 补缺也一样：从 1500 根前一直接到现在。
      let from = Clock.currentHour - 1500 * Clock.hour
      let tail = try await p.contiguousTail(symbol: "bybit/usd_m/BTCUSDT", interval: .h1, from: from)
      #expect(tail.first?.openTime == from && tail.last?.openTime == Clock.currentHour && contiguous(tail, step: Clock.hour))
    }

    @Test("翻过上线日：只交回上线之后的那几根；再往前要一律是空")
    func pastListing() async throws {
      let listed = Clock.currentHour - 1200 * Clock.hour
      let (p, _) = bybit(BybitUpstream(listedAt: listed))
      let bars = try await p.history(symbol: "bybit/usd_m/BTCUSDT", interval: .h1, pages: 3, before: Clock.currentHour - 100 * Clock.hour)
      #expect(bars.first?.openTime == listed && bars.count == 1100 && contiguous(bars, step: Clock.hour))
      #expect(try await p.history(symbol: "bybit/usd_m/BTCUSDT", interval: .h1, pages: 1, before: listed).isEmpty)
    }

    @Test("补缺超过 maxTailBars：当场 gapTooLong，不发请求")
    func tailLimit() async throws {
      let (p, server) = bybit(BybitUpstream())
      await #expect(throws: FeedError.gapTooLong) {
        _ = try await p.contiguousTail(symbol: "bybit/usd_m/BTCUSDT", interval: .h1,
                                       from: Clock.currentHour - Int64(BybitProvider.capabilities.maxTailBars) * Clock.hour)
      }
      #expect(await server.urls().isEmpty)
    }
  }
}

// ---------------------------------------------------------------- Hyperliquid

/// Hyperliquid 的 1h `candleSnapshot`：只留最近 5000 根；`more` 无视 `endTime` 一直回到现在，`fewer` 只回一半。
struct StressHLUpstream: Sendable {
  enum Mode: Sendable { case exact, more, fewer }
  var mode: Mode = .exact
  let asks = Counter()

  func reply(_ body: Data) -> HTTPReply {
    guard let o = try? JSONSerialization.jsonObject(with: body) as? [String: Any], o["type"] as? String == "candleSnapshot",
          let req = o["req"] as? [String: Any], let start = (req["startTime"] as? NSNumber)?.int64Value,
          let end = (req["endTime"] as? NSNumber)?.int64Value else { return json("[]") }
    _ = asks.bump()
    let earliest = Clock.currentHour - 4999 * Clock.hour
    let upper = mode == .more ? Clock.currentHour : min(Clock.currentHour, end / Clock.hour * Clock.hour)
    var opens: [Int64] = []
    var t = max(earliest, (start + Clock.hour - 1) / Clock.hour * Clock.hour)
    while t <= upper { opens.append(t); t += Clock.hour }
    if mode == .fewer { opens = Array(opens.suffix(opens.count / 2)) }
    return json("[" + opens.map {
      #"{"t":\#($0),"T":\#($0 + Clock.hour - 1),"s":"BTC","i":"1h","o":"1","c":"1.5","h":"2","l":"0.5","v":"3","n":1}"#
    }.joined(separator: ",") + "]")
  }
}

private func hl(_ upstream: StressHLUpstream) -> HyperliquidProvider {
  HyperliquidProvider(policy: .direct, gateways: ["gw.example"], transport: PostTransport { upstream.reply($0) },
                      limiter: VenueRateLimiter(weightPerMinute: 1_000_000, pacer: FastPacer()), clock: { Clock.now })
}

extension StressVenueSerial {
  @Suite("压测 · Hyperliquid 翻页极端", .timeLimit(.minutes(1)))
  struct StressHyperliquidPagingTests {
    @Test("5000 根上限：要 3 页也只发够得着的那一个窗口；翻到 5000 根之前一个请求都不发")
    func fiveThousandCap() async throws {
      let upstream = StressHLUpstream()
      let p = hl(upstream)
      let before = Clock.currentHour - 4000 * Clock.hour
      let bars = try await p.history(symbol: "hyperliquid/usd_m/BTC", interval: .h1, pages: 3, before: before)
      #expect(upstream.asks.value == 1)
      #expect(bars.count == 999 && bars.last?.openTime == before - Clock.hour && contiguous(bars, step: Clock.hour))
      let older = try await p.history(symbol: "hyperliquid/usd_m/BTC", interval: .h1, pages: 3,
                                      before: Clock.currentHour - 5002 * Clock.hour)
      #expect(older.isEmpty)
      #expect(upstream.asks.value == 1)
    }

    @Test("candleSnapshot 回得比要的多（无视 endTime）/ 比要的少：只交回要的那段，不越过 endTime、不重复", arguments: [StressHLUpstream.Mode.more, .fewer])
    func moreOrFewer(_ mode: StressHLUpstream.Mode) async throws {
      let p = hl(StressHLUpstream(mode: mode))
      let end = Clock.currentHour - 500 * Clock.hour
      let bars = try await p.klines(symbol: "hyperliquid/usd_m/BTC", interval: .h1, limit: 300, startTime: nil, endTime: end)
      #expect(bars.allSatisfy { $0.openTime <= end })
      #expect(bars.count <= 300 && contiguous(bars, step: Clock.hour))
      if mode == .more { #expect(bars.count == 300 && bars.last?.openTime == end) }
      let first = try await p.klines(symbol: "hyperliquid/usd_m/BTC", interval: .h1, limit: 300,
                                     startTime: Clock.currentHour - 1000 * Clock.hour, endTime: nil)
      #expect(first.allSatisfy { $0.openTime >= Clock.currentHour - 1000 * Clock.hour })
      #expect(first.count <= 300 && contiguous(first, step: Clock.hour))
    }

    @Test("补缺超过 5000 根：当场 gapTooLong，不发请求")
    func tailLimit() async throws {
      let upstream = StressHLUpstream()
      await #expect(throws: FeedError.gapTooLong) {
        _ = try await hl(upstream).contiguousTail(symbol: "hyperliquid/usd_m/BTC", interval: .h1,
                                                  from: Clock.currentHour - 5000 * Clock.hour)
      }
      #expect(upstream.asks.value == 0)
    }
  }
}
