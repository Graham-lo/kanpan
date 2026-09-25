import Foundation
import Testing
@testable import KanpanNetwork
import KanpanNetworkTestSupport
import KanpanCore

@Suite("补缺按需：一根就别拉一千五")
struct TailLimitTests {
  private let t0: Int64 = 1_700_000_000_000

  @Test("还在同一根上：拉下限 5 根，不是 1500")
  func sameCandle() {
    // 末根开在 t0，现在才过了 10 秒（1m 周期还没换根）：只需要刷新这一根。
    let n = BinanceREST.tailLimit(interval: .m1, from: t0, now: t0 + 10_000)
    #expect(n == 5)
    #expect(n < BinanceREST.maxKlines)
  }

  @Test("缺几十根就拉几十根，带 2 根余量")
  func dozens() {
    // 走开了 40 分钟，1m 周期欠 41 根（含末根自己），余量 2 → 43。
    #expect(BinanceREST.tailLimit(interval: .m1, from: t0, now: t0 + 40 * 60_000) == 43)
    // 同样 40 分钟，5m 周期只欠 9 根 → 11。
    #expect(BinanceREST.tailLimit(interval: .m5, from: t0, now: t0 + 40 * 60_000) == 11)
  }

  @Test("断了很久还是顶到一页 1500，翻页逻辑不受影响")
  func longGap() {
    let n = BinanceREST.tailLimit(interval: .m1, from: t0, now: t0 + 5 * 86_400_000)
    #expect(n == BinanceREST.maxKlines)
  }

  @Test("时钟倒挂也不会算出负数")
  func skew() {
    #expect(BinanceREST.tailLimit(interval: .h1, from: t0, now: t0 - 86_400_000) == 5)
  }
}

/// F1：断档超过提供者翻页能力（`maxTailBars`）时，`contiguousTail` 必须明说「接不上」
/// （`.gapTooLong`），不能悄悄只补回最后一段、把中间留成一个永久的洞。
@Suite("补缺上限：接不上就明说")
struct TailCapTests {

  private static let now = Date(timeIntervalSince1970: 1_790_119_186)

  /// Coinbase 蜡烛：按 start/end 回整段（跨度 < 350 步，和线上一样）。
  private static func candlePage(_ url: URL) -> HTTPReply {
    let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
    func q(_ k: String) -> Int64? { items.first { $0.name == k }?.value.flatMap { Int64($0) } }
    guard let start = q("start"), let end = q("end") else { return json("{}", status: 400) }
    guard (end - start) / 3600 < 350 else { return json(#"{"error":"INVALID_ARGUMENT"}"#, status: 400) }
    // 交易所不会回「未来」的蜡烛：截到当前这一小时。
    let nowHour = Int64(now.timeIntervalSince1970) / 3600 * 3600
    let rows = stride(from: min(end, nowHour), through: start, by: -3600).map {
      #"{"start":"\#($0)","low":"1","high":"2","open":"1","close":"2","volume":"1"}"#
    }
    return json(#"{"candles":[\#(rows.joined(separator: ","))]}"#)
  }

  private func coinbase(_ server: FakeServer) -> CoinbaseProvider {
    CoinbaseProvider(policy: .direct, gateways: ["gw1.example"], transport: FakeTransport(server),
                     limiter: CoinbaseRateLimiter(perSecond: 1_000_000, pacer: FastPacer()),
                     clock: { Self.now })
  }

  @Test("Coinbase：断档超过 1400 根直接报 gapTooLong，一个请求也不发")
  func coinbaseGapTooLong() async throws {
    let server = FakeServer { Self.candlePage($0) }
    let provider = coinbase(server)
    #expect(provider.capabilities.maxTailBars == 1400)
    let nowMs = Int64(Self.now.timeIntervalSince1970 * 1000)
    let from = nowMs / 3_600_000 * 3_600_000 - 2_000 * 3_600_000
    await #expect(throws: FeedError.gapTooLong) {
      _ = try await provider.contiguousTail(symbol: "coinbase/spot/BTC-USD", interval: .h1, from: from)
    }
    #expect(await server.urls().isEmpty)
  }

  @Test("Coinbase：上限以内照常接上，而且连续")
  func coinbaseGapWithinCap() async throws {
    let server = FakeServer { Self.candlePage($0) }
    let nowMs = Int64(Self.now.timeIntervalSince1970 * 1000)
    let from = nowMs / 3_600_000 * 3_600_000 - 1_000 * 3_600_000
    let bars = try await coinbase(server).contiguousTail(symbol: "coinbase/spot/BTC-USD", interval: .h1, from: from)
    #expect(bars.first?.openTime == from)
    #expect(bars.last?.openTime == nowMs / 3_600_000 * 3_600_000)
    #expect(zip(bars, bars.dropFirst()).allSatisfy { $1.openTime - $0.openTime == 3_600_000 })
  }

  @Test("币安：翻满 4 整页还没到头就报 gapTooLong，不把前 6000 根当成补齐")
  func binanceGapTooLong() async throws {
    // 永远回整页：模拟一段比 4 页还长的断档。
    let server = FakeServer { url in
      let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
      let start = items.first { $0.name == "startTime" }?.value.flatMap(Int64.init) ?? 0
      let limit = items.first { $0.name == "limit" }?.value.flatMap(Int.init) ?? 1500
      let first = (start + 59_999) / 60_000 * 60_000
      let rows = (0..<limit).map { i -> String in
        let t = first + Int64(i) * 60_000
        return "[\(t),\"1\",\"1\",\"1\",\"1\",\"1\",\(t + 59_999),\"1\",1,\"1\",\"1\",\"0\"]"
      }
      return json("[" + rows.joined(separator: ",") + "]")
    }
    let pacer = FastPacer()
    let rest = BinanceREST(transport: FakeTransport(server),
                           limiter: RateLimiter(pacer: pacer, minGapMs: 0), pacer: pacer)
    #expect(BinanceREST.maxTailBars == 6000)
    await #expect(throws: FeedError.gapTooLong) {
      _ = try await rest.contiguousTail(symbol: "BTCUSDT", interval: .m1, from: 1_600_000_000_000)
    }
    #expect(await server.urls().count == 4)
  }
}
