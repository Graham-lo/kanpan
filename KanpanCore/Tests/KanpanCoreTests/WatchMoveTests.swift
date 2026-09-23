import Foundation
import Testing
@testable import KanpanCore

/// 自选五分钟波动提醒的判定（P3.1）。服务端 `watch_move.rs` 的单测按同一组场景写。
@Suite struct WatchMoveTests {
  static let m0: Int64 = 1_800_000_000_000 - 1_800_000_000_000 % 300_000
  func minute(_ n: Int64) -> Int64 { Self.m0 + n * 60_000 }

  /// 连着喂五根已收的：第 0～4 分钟都收在 `base`，第 5 分钟那一口就有参照了。
  private func warm(_ t: inout WatchMove.Tracker, base: Double = 100, symbol: String = "BTCUSDT") {
    for n in Int64(0)..<5 { _ = t.observe(symbol: symbol, barOpen: minute(n), price: base, closed: true, threshold: 1.5) }
  }

  @Test("涨过幅度响一次，方向是涨")
  func upwardMoveFires() throws {
    var t = WatchMove.Tracker()
    warm(&t)
    let fired = t.observe(symbol: "BTCUSDT", barOpen: minute(5), price: 101.6, threshold: 1.5)
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
    let fired = t.observe(symbol: "BTCUSDT", barOpen: minute(5), price: 98.4, threshold: 1.5)
    let e = try #require(fired)
    #expect(e.direction == .down)
    #expect(e.change < 0)
    #expect(WatchMove.title(for: e) == "BTC 五分钟跌 1.60%")
  }

  @Test("没过幅度不响")
  func smallMoveIsQuiet() {
    var t = WatchMove.Tracker()
    warm(&t)
    #expect(t.observe(symbol: "BTCUSDT", barOpen: minute(5), price: 101.4, threshold: 1.5) == nil)
    #expect(t.observe(symbol: "BTCUSDT", barOpen: minute(5), price: 98.6, threshold: 1.5) == nil)
  }

  @Test("五分钟前那一根缺着就不判：缺口不当零波动，也不当大波动")
  func aGapIsNotJudged() {
    var t = WatchMove.Tracker()
    // 刚开始盯：第一口就是大涨，但没有五分钟前的参照。
    #expect(t.observe(symbol: "BTCUSDT", barOpen: minute(5), price: 150, threshold: 1.5) == nil)
    // 中间断了三分钟：第 1、2、3 分钟一口价都没有，第 6 分钟的参照（第 1 分钟）缺着。
    var g = WatchMove.Tracker()
    _ = g.observe(symbol: "BTCUSDT", barOpen: minute(0), price: 100, closed: true, threshold: 1.5)
    _ = g.observe(symbol: "BTCUSDT", barOpen: minute(4), price: 100, closed: true, threshold: 1.5)
    #expect(g.observe(symbol: "BTCUSDT", barOpen: minute(6), price: 120, threshold: 1.5) == nil)
    #expect(g.observe(symbol: "BTCUSDT", barOpen: minute(7), price: 120, threshold: 1.5) == nil,
            "第 7 分钟的参照是第 2 分钟，也缺")
  }

  @Test("同品种同方向同窗口只响一次；回到阈值以内再冲过去、换了窗口才再响")
  func dedupeWithinWindowAndRearmAfterExit() throws {
    var t = WatchMove.Tracker()
    warm(&t)
    #expect(t.observe(symbol: "BTCUSDT", barOpen: minute(5), price: 102, threshold: 1.5) != nil)
    // 同一根里继续涨：不再响。
    #expect(t.observe(symbol: "BTCUSDT", barOpen: minute(5), price: 103, threshold: 1.5) == nil)
    // 同窗口里回落到阈值以内再冲上去：还是同一个窗口，不响。
    #expect(t.observe(symbol: "BTCUSDT", barOpen: minute(5), price: 100.5, threshold: 1.5) == nil)
    #expect(t.observe(symbol: "BTCUSDT", barOpen: minute(5), price: 102, threshold: 1.5) == nil)
    // 第 6 分钟（参照第 1 分钟 = 100）：还在同一个五分钟窗口里——不响。
    _ = t.observe(symbol: "BTCUSDT", barOpen: minute(6), price: 102, closed: true, threshold: 1.5)
    // 换下一个窗口（第 10 分钟，参照第 5 分钟收盘 102）：先回落（退出阈值）……
    for n in Int64(7)...9 { _ = t.observe(symbol: "BTCUSDT", barOpen: minute(n), price: 102, closed: true, threshold: 1.5) }
    #expect(t.observe(symbol: "BTCUSDT", barOpen: minute(10), price: 102.1, threshold: 1.5) == nil)
    // ……再冲过去：新窗口、已经重新上膛，响。
    let fired = t.observe(symbol: "BTCUSDT", barOpen: minute(10), price: 104, threshold: 1.5)
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
      if t.observe(symbol: "BTCUSDT", barOpen: minute(n), price: price, closed: true, threshold: 1.5) != nil { fired += 1 }
    }
    #expect(fired == 1)
  }

  @Test("涨与跌各自一道闸：同一窗口里先涨后跌两个方向各响一次")
  func directionsAreIndependent() {
    var t = WatchMove.Tracker()
    warm(&t)
    #expect(t.observe(symbol: "BTCUSDT", barOpen: minute(5), price: 102, threshold: 1.5)?.direction == .up)
    #expect(t.observe(symbol: "BTCUSDT", barOpen: minute(5), price: 98, threshold: 1.5)?.direction == .down)
  }

  @Test("改自选：拿掉的品种忘掉，加回来从缺口重新开始")
  func changingFavoritesForgetsRemovedSymbols() {
    var t = WatchMove.Tracker()
    warm(&t, symbol: "BTCUSDT")
    warm(&t, symbol: "ETHUSDT")
    t.keep(["ETHUSDT"])
    #expect(t.symbols == ["ETHUSDT"])
    #expect(t.observe(symbol: "BTCUSDT", barOpen: minute(5), price: 110, threshold: 1.5) == nil,
            "加回来的品种没有五分钟前的参照")
    #expect(t.observe(symbol: "ETHUSDT", barOpen: minute(5), price: 110, threshold: 1.5) != nil)
  }

  @Test("幅度夹在 0.1%～50% 之间，读不出来退回 1.5%")
  func thresholdIsClamped() {
    #expect(WatchMove.clampThreshold(0) == 0.1)
    #expect(WatchMove.clampThreshold(80) == 50)
    #expect(WatchMove.clampThreshold(.nan) == 1.5)
    #expect(WatchMove.clampThreshold(2.5) == 2.5)
  }

  @Test("乱序的旧帧不要")
  func staleFramesAreIgnored() {
    var t = WatchMove.Tracker()
    warm(&t)
    _ = t.observe(symbol: "BTCUSDT", barOpen: minute(5), price: 100, threshold: 1.5)
    #expect(t.observe(symbol: "BTCUSDT", barOpen: minute(3), price: 150, threshold: 1.5) == nil)
  }
}
