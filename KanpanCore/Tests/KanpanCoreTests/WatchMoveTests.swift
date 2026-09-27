import Foundation
import Testing
@testable import KanpanCore

/// 自选五分钟波动提醒的判定（P3.1）。服务端 `watch_move.rs` 的单测按同一组场景写。
@Suite struct WatchMoveTests {
  static let m0: Int64 = 1_800_000_000_000 - 1_800_000_000_000 % 300_000
  func minute(_ n: Int64) -> Int64 { Self.m0 + n * 60_000 }

  /// 连着喂五根已收的：第 0～4 分钟都收在 `base`，第 5 分钟那一口就有参照了。
  private func warm(_ t: inout WatchMove.Tracker, base: Double = 100, symbol: String = "BTCUSDT") {
    for n in Int64(0)..<5 { _ = t.observe(symbol: symbol, barOpen: minute(n), price: base, closed: true) }
  }

  @Test("涨过幅度响一次，方向是涨")
  func upwardMoveFires() throws {
    var t = WatchMove.Tracker()
    warm(&t)
    let fired = t.observe(symbol: "BTCUSDT", barOpen: minute(5), price: 101.6)
    let e = try #require(fired)
    #expect(e.direction == .up)
    #expect(abs(e.change - 0.016) < 1e-9)
    #expect(e.window == minute(5))
    #expect(WatchMove.title(for: e) == "BTC 五分钟涨 1.60%")
  }

  @Test("跌过幅度同样响，方向是跌")
  func downwardMoveFires() throws {
    var t = WatchMove.Tracker()
    warm(&t)
    let fired = t.observe(symbol: "BTCUSDT", barOpen: minute(5), price: 98.4)
    let e = try #require(fired)
    #expect(e.direction == .down)
    #expect(e.change < 0)
    #expect(WatchMove.title(for: e) == "BTC 五分钟跌 1.60%")
  }

  @Test("没过幅度不响")
  func smallMoveIsQuiet() {
    var t = WatchMove.Tracker()
    warm(&t)
    #expect(t.observe(symbol: "BTCUSDT", barOpen: minute(5), price: 101.4) == nil)
    #expect(t.observe(symbol: "BTCUSDT", barOpen: minute(5), price: 98.6) == nil)
  }

  @Test("五分钟前那一根缺着就不判：缺口不当零波动，也不当大波动")
  func aGapIsNotJudged() {
    var t = WatchMove.Tracker()
    // 刚开始盯：第一口就是大涨，但没有五分钟前的参照。
    #expect(t.observe(symbol: "BTCUSDT", barOpen: minute(5), price: 150) == nil)
    // 中间断了三分钟：第 1、2、3 分钟一口价都没有，第 6 分钟的参照（第 1 分钟）缺着。
    var g = WatchMove.Tracker()
    _ = g.observe(symbol: "BTCUSDT", barOpen: minute(0), price: 100, closed: true)
    _ = g.observe(symbol: "BTCUSDT", barOpen: minute(4), price: 100, closed: true)
    #expect(g.observe(symbol: "BTCUSDT", barOpen: minute(6), price: 120) == nil)
    #expect(g.observe(symbol: "BTCUSDT", barOpen: minute(7), price: 120) == nil,
            "第 7 分钟的参照是第 2 分钟，也缺")
  }

  @Test("同品种同方向同窗口只响一次；回到阈值以内再冲过去、换了窗口才再响")
  func dedupeWithinWindowAndRearmAfterExit() throws {
    var t = WatchMove.Tracker()
    warm(&t)
    #expect(t.observe(symbol: "BTCUSDT", barOpen: minute(5), price: 102) != nil)
    // 同一根里继续涨：不再响。
    #expect(t.observe(symbol: "BTCUSDT", barOpen: minute(5), price: 103) == nil)
    // 同窗口里回落到阈值以内再冲上去：还是同一个窗口，不响。
    #expect(t.observe(symbol: "BTCUSDT", barOpen: minute(5), price: 100.5) == nil)
    #expect(t.observe(symbol: "BTCUSDT", barOpen: minute(5), price: 102) == nil)
    // 第 6 分钟（参照第 1 分钟 = 100）：还在同一个五分钟窗口里——不响。
    _ = t.observe(symbol: "BTCUSDT", barOpen: minute(6), price: 102, closed: true)
    // 换下一个窗口（第 10 分钟，参照第 5 分钟收盘 102）：先回落（退出阈值）……
    for n in Int64(7)...9 { _ = t.observe(symbol: "BTCUSDT", barOpen: minute(n), price: 102, closed: true) }
    #expect(t.observe(symbol: "BTCUSDT", barOpen: minute(10), price: 102.1) == nil)
    // ……再冲过去：新窗口、已经重新上膛，响。
    let fired = t.observe(symbol: "BTCUSDT", barOpen: minute(10), price: 104)
    let e = try #require(fired)
    #expect(e.window == minute(10))
  }

  @Test("一直停在阈值外、跨了窗口也不重复响")
  func stayingBeyondTheThresholdDoesNotRepeat() {
    var t = WatchMove.Tracker()
    // 一路涨：每分钟涨 1%，五分钟累计一直超过 1.5%。
    var fired = 0
    for n in Int64(0)..<20 {
      let price = 100 * pow(1.01, Double(n))
      if t.observe(symbol: "BTCUSDT", barOpen: minute(n), price: price, closed: true) != nil { fired += 1 }
    }
    #expect(fired == 1)
  }

  @Test("涨与跌各自一道闸：同一窗口里先涨后跌两个方向各响一次")
  func directionsAreIndependent() {
    var t = WatchMove.Tracker()
    warm(&t)
    #expect(t.observe(symbol: "BTCUSDT", barOpen: minute(5), price: 102)?.direction == .up)
    #expect(t.observe(symbol: "BTCUSDT", barOpen: minute(5), price: 98)?.direction == .down)
  }

  @Test("改自选：拿掉的品种忘掉，加回来从缺口重新开始")
  func changingFavoritesForgetsRemovedSymbols() {
    var t = WatchMove.Tracker()
    warm(&t, symbol: "BTCUSDT")
    warm(&t, symbol: "ETHUSDT")
    t.keep(["ETHUSDT"])
    #expect(t.symbols == ["binance/usd_m/ETHUSDT"])
    #expect(t.observe(symbol: "BTCUSDT", barOpen: minute(5), price: 110) == nil,
            "加回来的品种没有五分钟前的参照")
    #expect(t.observe(symbol: "ETHUSDT", barOpen: minute(5), price: 110) != nil)
  }

  @Test("自选没拿掉的品种闸照留：品种键里带「/」、别家的现货也一样")
  func keepPreservesGatesForFullKeys() {
    var t = WatchMove.Tracker()
    let key = "binance/usd_m/BTCUSDT"
    warm(&t, symbol: key)
    let e = t.observe(symbol: key, barOpen: minute(5), price: 102)
    #expect(e.map(WatchMove.title(for:)) == "BTC 五分钟涨 2.00%")
    t.keep([key, "binance/usd_m/ETHUSDT"])
    #expect(t.observe(symbol: key, barOpen: minute(5), price: 103) == nil,
            "自选改了但这只还在：同一个窗口里不许再响")
  }

  @Test("裸代号 / 规范键 / 大写规范键三种写法归到同一只：同一串价、同一道闸")
  func symbolSpellingsShareOneKey() {
    let spellings = ["BTCUSDT", "binance/usd_m/BTCUSDT", "BINANCE/USD_M/BTCUSDT", " btcusdt "]
    var t = WatchMove.Tracker()
    // 五根收盘价轮着用不同写法喂：只要归到同一格，第六口就能拿到五分钟前那一根。
    for n in Int64(0)..<5 {
      _ = t.observe(symbol: spellings[Int(n) % spellings.count], barOpen: minute(n), price: 100)
    }
    #expect(t.symbols == ["binance/usd_m/BTCUSDT"])
    let e = t.observe(symbol: "BINANCE/USD_M/BTCUSDT", barOpen: minute(5), price: 101.6)
    #expect(e?.symbol == "binance/usd_m/BTCUSDT", "事件带的是规范键，不是大写的规范键")
    #expect(e.map(WatchMove.title(for:)) == "BTC 五分钟涨 1.60%")
    for spelling in spellings {
      #expect(t.observe(symbol: spelling, barOpen: minute(5), price: 101.9) == nil,
              "换个写法也是同一道闸：同窗口不再响")
    }
  }

  @Test("改自选不丢留下那只的闸：同窗口里不会再响一次")
  func keepingASymbolKeepsItsGate() {
    var t = WatchMove.Tracker()
    warm(&t, symbol: "binance/usd_m/BTCUSDT")
    warm(&t, symbol: "binance/usd_m/ETHUSDT")
    #expect(t.observe(symbol: "binance/usd_m/BTCUSDT", barOpen: minute(5), price: 101.6) != nil)
    // 宿主交进来的是规范键；以前按第一个 `/` 拆出 "BINANCE" 去比，闸全被清掉。
    t.keep(["binance/usd_m/BTCUSDT"])
    #expect(t.symbols == ["binance/usd_m/BTCUSDT"])
    #expect(t.observe(symbol: "binance/usd_m/BTCUSDT", barOpen: minute(5), price: 101.8) == nil)
    // 裸代号去 keep 也是同一只。
    t.keep(["BTCUSDT"])
    #expect(t.symbols == ["binance/usd_m/BTCUSDT"])
    #expect(t.observe(symbol: "BTCUSDT", barOpen: minute(5), price: 101.9) == nil)
  }

  // ---------------------------------------------------------------- 自动幅度（收设置项 E 组）

  struct ThresholdFixture: Decodable {
    struct Constants: Decodable {
      var fallbackPercent: Double
      var floorPercent: Double
      var ceilingPercent: Double
      var minReturns: Int
      var maxReturns: Int
      var madScale: Double
    }
    struct Segment: Decodable { var count: Int; var stepPercent: Double }
    struct Case: Decodable {
      var name: String
      var why: String
      var start: Double
      var segments: [Segment]
      var expectPercent: Double
    }
    var version: Int
    var constants: Constants
    var cases: [Case]

    static func load() throws -> ThresholdFixture {
      let root = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent()
        .deletingLastPathComponent().deletingLastPathComponent()
      let url = root.appendingPathComponent("Backend/kanpan-api/contract/watch-move-threshold.json")
      return try JSONDecoder().decode(ThresholdFixture.self, from: Data(contentsOf: url))
    }
  }

  /// 夹具的收盘价：从 `start` 起，每段段内偶数步 ×(1+s)、奇数步 ÷(1+s)。
  static func closes(_ c: ThresholdFixture.Case) -> [Double] {
    var out = [c.start]
    for segment in c.segments {
      let step = 1 + segment.stepPercent / 100
      for i in 0..<segment.count { out.append(i % 2 == 0 ? out.last! * step : out.last! / step) }
    }
    return out
  }

  @Test("夹具 watch-move-threshold.json：常数两端一致，每条用例 autoThreshold 与逐根喂 Tracker 都算出同一个幅度")
  func sharedThresholdFixture() throws {
    let fixture = try ThresholdFixture.load()
    #expect(fixture.version == 1)
    let k = fixture.constants
    #expect(k.fallbackPercent == WatchMove.fallbackThreshold)
    #expect(k.floorPercent == WatchMove.thresholdRange.lowerBound)
    #expect(k.ceilingPercent == WatchMove.thresholdRange.upperBound)
    #expect(k.minReturns == WatchMove.minReturns)
    #expect(k.maxReturns == WatchMove.maxReturns)
    #expect(k.madScale == WatchMove.madScale)
    #expect(fixture.cases.count >= 8, "夹具被删薄了")
    for c in fixture.cases {
      let closes = Self.closes(c)
      let returns = zip(closes.dropFirst(), closes).map { Foundation.log($0 / $1) }
      #expect(abs(WatchMove.autoThreshold(returns: returns) - c.expectPercent) < 1e-6, "\(c.name)：\(c.why)")
      var t = WatchMove.Tracker()
      for (n, close) in closes.enumerated() {
        _ = t.observe(symbol: "BTCUSDT", barOpen: minute(Int64(n)), price: close, closed: true)
      }
      #expect(abs(t.threshold(for: "BTCUSDT") - c.expectPercent) < 1e-6, "Tracker · \(c.name)")
    }
  }

  @Test("缺口两边不连：断开的两根之间不算收益")
  func gapsDoNotMakeReturns() {
    var t = WatchMove.Tracker()
    // 30 根安静的（29 个收益），隔一分钟再来一根跳 20% 的：不连，收益还是 29 个 ⇒ 仍用 1.5%。
    for n in Int64(0)..<30 { _ = t.observe(symbol: "BTCUSDT", barOpen: minute(n), price: n % 2 == 0 ? 100 : 100.1, closed: true) }
    _ = t.observe(symbol: "BTCUSDT", barOpen: minute(31), price: 120, closed: true)
    #expect(t.threshold(for: "BTCUSDT") == WatchMove.fallbackThreshold)
    // 再连着来一根：这才是第 30 个收益，开始按波动算。
    _ = t.observe(symbol: "BTCUSDT", barOpen: minute(32), price: 120.12, closed: true)
    #expect(t.threshold(for: "BTCUSDT") != WatchMove.fallbackThreshold)
  }

  @Test("同一根收两次（k.x 之后又换根）只记一个收益")
  func aBarClosedTwiceCountsOnce() {
    var t = WatchMove.Tracker()
    for n in Int64(0)..<31 {
      _ = t.observe(symbol: "BTCUSDT", barOpen: minute(n), price: n % 2 == 0 ? 100 : 100.1, closed: true)
    }
    let once = t.threshold(for: "BTCUSDT")
    var u = WatchMove.Tracker()
    for n in Int64(0)..<31 {
      let price: Double = n % 2 == 0 ? 100 : 100.1
      _ = u.observe(symbol: "BTCUSDT", barOpen: minute(n), price: price)
      _ = u.observe(symbol: "BTCUSDT", barOpen: minute(n), price: price, closed: true)
    }
    #expect(u.threshold(for: "BTCUSDT") == once)
    #expect(u.series["binance/usd_m/BTCUSDT"]?.returns.count == 30)
  }

  @Test("切后台断过：收盘价作废、估出来的幅度留着")
  func forgettingPricesKeepsTheThreshold() {
    var t = WatchMove.Tracker()
    for n in Int64(0)..<60 { _ = t.observe(symbol: "BTCUSDT", barOpen: minute(n), price: n % 2 == 0 ? 100 : 100.02, closed: true) }
    #expect(t.threshold(for: "BTCUSDT") == 0.5)
    t.forgetPrices()
    #expect(t.threshold(for: "BTCUSDT") == 0.5)
    #expect(t.observe(symbol: "BTCUSDT", barOpen: minute(60), price: 110) == nil, "断过之后没有五分钟前的参照")
  }

  @Test("乱序的旧帧不要")
  func staleFramesAreIgnored() {
    var t = WatchMove.Tracker()
    warm(&t)
    _ = t.observe(symbol: "BTCUSDT", barOpen: minute(5), price: 100)
    #expect(t.observe(symbol: "BTCUSDT", barOpen: minute(3), price: 150) == nil)
  }
}
