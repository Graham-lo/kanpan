import Foundation
import KanpanCore
import Testing
@testable import Kanpan

private let day: Double = 86_400
private let now: Double = 1_790_000_000
private let btc = "binance/usd_m/BTCUSDT"
private let eth = "binance/usd_m/ETHUSDT"

private func dwell(_ key: String, _ iv: Interval, _ seconds: Double, ago: Double) -> HabitEvent {
  HabitEvent(t: now - ago, kind: .interval, key: key, value: iv.rawValue, w: seconds)
}

@Suite("按习惯学 · 推断")
struct HabitInferenceTests {
  // ---------------------------------------------------------------- 权重衰减

  @Test("新近加权：半衰期 7 天，30 天窗口之外不算")
  func decay() {
    #expect(HabitInference.decay(age: 0) == 1)
    #expect(abs(HabitInference.decay(age: 7 * day) - 0.5) < 1e-9)
    #expect(abs(HabitInference.decay(age: 14 * day) - 0.25) < 1e-9)
    // 未来的时刻（时钟回拨）不放大。
    #expect(HabitInference.decay(age: -day) == 1)
    let log = HabitLog(events: [dwell(btc, .h4, 3_000, ago: 31 * day)])
    #expect(HabitInference.learn(from: log, now: now).intervals.isEmpty)
  }

  // ---------------------------------------------------------------- 1. 周期

  @Test("周期：取加权停留最多的那个；近的压过更多但更旧的")
  func intervalWinner() {
    // 20 天前在 1 时看了 1000 秒（衰减到约 138），昨天在 4 时看了 300 秒（约 270）。
    let events = [dwell(btc, .h1, 1_000, ago: 20 * day), dwell(btc, .h4, 300, ago: day)]
    let learned = HabitInference.intervals(events, now: now)
    #expect(learned[btc]?.v == Interval.h4.rawValue)
    #expect(learned[btc]?.n == 1)
    #expect(learned[btc]?.at == now - day)
    // 同样的停留全放在今天：更多的那个赢。
    let today = [dwell(btc, .h1, 1_000, ago: 60), dwell(btc, .h4, 300, ago: 0)]
    #expect(HabitInference.intervals(today, now: now)[btc]?.v == Interval.h1.rawValue)
  }

  @Test("周期：加权后不到两分钟不算学到；各只品种各算各的")
  func intervalMinimum() {
    let events = [dwell(btc, .h4, 100, ago: 0), dwell(eth, .m15, 200, ago: 0), dwell(eth, .m15, 100, ago: 10)]
    let learned = HabitInference.intervals(events, now: now)
    #expect(learned[btc] == nil)
    #expect(learned[eth]?.v == Interval.m15.rawValue)
    #expect(learned[eth]?.n == 2)
  }

  // ---------------------------------------------------------------- 2. 价格轴

  @Test("价格轴：按类别看线性 / 对数谁停留多；百分比不参与")
  func axisDwell() {
    let events = [
      HabitEvent(t: now - 100, kind: .axisDwell, key: "crypto", value: "log", w: 600),
      HabitEvent(t: now - 50, kind: .axisDwell, key: "crypto", value: "linear", w: 200),
      HabitEvent(t: now - 50, kind: .axisDwell, key: "equity", value: "linear", w: 300),
      HabitEvent(t: now - 50, kind: .axisDwell, key: "metal", value: "percent", w: 900),
    ]
    let learned = HabitInference.priceAxis(events, now: now)
    #expect(learned["crypto"]?.v == "log")
    #expect(learned["crypto"]?.n == 1)
    #expect(learned["equity"]?.v == "linear")
    #expect(learned["metal"] == nil)
  }

  @Test("价格轴：亲手切一次立刻压过此前全部停留，之后停留还能再改回来")
  func axisPick() {
    var events = [
      HabitEvent(t: now - 3_000, kind: .axisDwell, key: "crypto", value: "log", w: 5_000),
      HabitEvent(t: now - 2_000, kind: .axisPick, key: "crypto", value: "linear"),
    ]
    #expect(HabitInference.priceAxis(events, now: now)["crypto"]?.v == "linear")
    // 亲手切过的，停留不够两分钟也算学到。
    let picked = [HabitEvent(t: now, kind: .axisPick, key: "index", value: "log")]
    #expect(HabitInference.priceAxis(picked, now: now)["index"]?.v == "log")
    // 之后又在对数上看了很久：回到对数。
    events.append(HabitEvent(t: now - 10, kind: .axisDwell, key: "crypto", value: "log", w: 20_000))
    #expect(HabitInference.priceAxis(events, now: now)["crypto"]?.v == "log")
  }

  @Test("类别：大宗、盘前并进其它")
  func categories() {
    #expect(HabitCategory(.crypto) == .crypto)
    #expect(HabitCategory(.equity) == .equity)
    #expect(HabitCategory(.preciousMetal) == .metal)
    #expect(HabitCategory(.index) == .index)
    #expect(HabitCategory(.commodity) == .other)
    #expect(HabitCategory(.preMarket) == .other)
  }

  // ---------------------------------------------------------------- 3. 板块

  private func picks(_ values: [SectorWindow], market: SectorMarket = .crypto) -> [HabitEvent] {
    values.enumerated().map { i, w in
      HabitEvent(t: now - Double(values.count - i) * 60, kind: .sectorWindow, key: market.rawValue, value: w.rawValue)
    }
  }

  @Test("板块：最近十次里多的那个；只看最近十次")
  func sectorMajority() {
    let recent = picks([.d5, .d5, .d5, .d5, .d5, .d5] + [.today, .d5, .today, .today, .today, .d5, .today, .today, .d5, .today])
    // 最近十次：7 今日 / 3 五日。更早的六次五日不算（算上就是 9 比 7 五日赢）。
    let learned = HabitInference.sectorWindow(recent)
    #expect(learned["crypto"]?.v == "today")
    #expect(learned["crypto"]?.n == 7)
  }

  @Test("板块：不到三次、或者打平，不算学到；两个市场各算各的")
  func sectorTieAndMinimum() {
    #expect(HabitInference.sectorWindow(picks([.d5, .d5])).isEmpty)
    #expect(HabitInference.sectorWindow(picks([.d5, .today, .d5, .today])).isEmpty)
    let both = picks([.d5, .d5, .d5], market: .crypto) + picks([.today, .today, .today], market: .us)
    let learned = HabitInference.sectorWindow(both)
    #expect(learned["crypto"]?.v == "d5")
    #expect(learned["us"]?.v == "today")
  }

  // ---------------------------------------------------------------- 4. 波动提醒倍数

  @Test("倍数：连续两次没点开升一档，点开降一档")
  func factorSteps() {
    let ladder = HabitInference.factorLadder
    #expect(ladder[HabitInference.step([])] == 1)
    #expect(ladder[HabitInference.step([.ignored])] == 1)
    #expect(ladder[HabitInference.step([.ignored, .ignored])] == 1.25)
    #expect(ladder[HabitInference.step([.ignored, .opened, .ignored])] == 0.8)
    #expect(ladder[HabitInference.step([.opened])] == 0.8)
    #expect(ladder[HabitInference.step([.opened, .ignored, .ignored])] == 1)
  }

  @Test("倍数：夹在 0.5 与 2 之间")
  func factorClamp() {
    let ladder = HabitInference.factorLadder
    #expect(ladder[HabitInference.step(Array(repeating: .ignored, count: 40))] == 2)
    #expect(ladder[HabitInference.step(Array(repeating: .opened, count: 40))] == 0.5)
    #expect(ladder.first == LearnedDefaults.factorRange.lowerBound)
    #expect(ladder.last == LearnedDefaults.factorRange.upperBound)
  }

  @Test("倍数：15 分钟内点开算点开，过了没点开算忽略，没满 15 分钟的先不算")
  func factorOutcomes() {
    let w = HabitInference.moveOpenWindow
    let fires = [now - 5 * w, now - 3 * w, now - 2 * w, now - 60]
    let opens = [now - 5 * w + 30]
    let outcomes = HabitInference.outcomes(fires: fires, opens: opens, now: now).map(\.outcome)
    #expect(outcomes == [.opened, .ignored, .ignored])
    let events = fires.map { HabitEvent(t: $0, kind: .moveFired, key: btc) }
      + opens.map { HabitEvent(t: $0, kind: .moveOpened, key: btc) }
    let learned = HabitInference.watchMove(events, now: now)
    // 点开一次降到 0.8，再连续两次忽略升回 1。
    #expect(learned[btc]?.v == 1)
    #expect(learned[btc]?.n == 3)
    #expect(learned[btc]?.at == now - 2 * w)
  }

  // ---------------------------------------------------------------- 日志

  @Test("日志：30 天前的丢、超上限从最旧的丢、停留同一小时内并成一条")
  func logPruneAndCoalesce() {
    var log = HabitLog()
    log.append(dwell(btc, .h4, 60, ago: 31 * day), now: now)
    #expect(log.isEmpty)
    log.append(dwell(btc, .h4, 60, ago: 600), now: now)
    log.append(dwell(btc, .h4, 30, ago: 0), now: now)
    #expect(log.events.count == 1)
    #expect(log.events[0].w == 90)
    #expect(log.events[0].t == now)
    log.append(dwell(btc, .h1, 30, ago: 0), now: now)
    #expect(log.events.count == 2)
    for i in 0..<(HabitLog.capacity + 50) {
      log.append(HabitEvent(t: now + Double(i), kind: .moveFired, key: btc), now: now + Double(i))
    }
    #expect(log.events.count == HabitLog.capacity)
    #expect(log.events.first?.kind == .moveFired)
    let size = (try? JSONEncoder().encode(log).count) ?? 0
    #expect(size < 200_000)
  }

  // ---------------------------------------------------------------- 结论的形状

  @Test("结论：合并时同一个键谁新用谁，过期的丢，编码不超过 16 KB")
  func mergeAndLimits() throws {
    var synced = LearnedDefaults()
    synced.intervals[btc] = .init(v: "1d", n: 3, at: now - 100)
    synced.intervals[eth] = .init(v: "1h", n: 3, at: now - 31 * day)
    synced.sectorWindow["crypto"] = .init(v: "d5", n: 5, at: now - 10)
    var local = LearnedDefaults()
    local.intervals[btc] = .init(v: "4h", n: 1, at: now - 50)
    local.sectorWindow["crypto"] = .init(v: "today", n: 3, at: now - 20)
    let merged = LearnedDefaults.merged(synced: synced, local: local, now: now)
    #expect(merged.intervals[btc]?.v == "4h")
    #expect(merged.intervals[eth] == nil)
    #expect(merged.sectorWindow["crypto"]?.v == "d5")

    var big = LearnedDefaults()
    for i in 0..<300 {
      big.intervals["binance/usd_m/SYMBOL\(i)LONGNAMEUSDT"] = .init(v: "15m", n: 99, at: now - Double(i))
      big.watchMove["binance/usd_m/SYMBOL\(i)LONGNAMEUSDT"] = .init(v: 1.25, n: 9, at: now - Double(i))
    }
    let pruned = big.pruned(now: now)
    #expect(pruned.intervals.count <= LearnedDefaults.maxSymbols)
    #expect(pruned.encodedSize <= LearnedDefaults.maxBytes)
    // 留下的是最新的。
    #expect(pruned.intervals["binance/usd_m/SYMBOL0LONGNAMEUSDT"] != nil)
  }

  @Test("结论：读不懂的条目只丢那一条；空表不写出去")
  func tolerantCodec() throws {
    let json = #"""
    {"intervals":{"binance/usd_m/BTCUSDT":{"v":"4h","n":2,"at":1},"x":{"v":"7h","n":1,"at":1}},
     "priceAxis":{"crypto":{"v":"percent","n":1,"at":1},"equity":{"v":"linear","n":1,"at":1}},
     "watchMove":{"binance/usd_m/BTCUSDT":{"v":9,"n":1,"at":1}},
     "sectorWindow":"garbage"}
    """#
    let decoded = try JSONDecoder().decode(LearnedDefaults.self, from: Data(json.utf8))
    #expect(decoded.intervals.keys.sorted() == [btc])
    #expect(decoded.priceAxis.keys.sorted() == ["equity"])
    #expect(decoded.watchMove.isEmpty)
    #expect(decoded.sectorWindow.isEmpty)
    #expect(String(decoding: try JSONEncoder().encode(LearnedDefaults.empty), as: UTF8.self) == "{}")
  }

  @Test("「已学到的」：四组、倍数回到 1 的不列、空的整页为空")
  func learnedItems() {
    #expect(LearnedItems(.empty).isEmpty)
    var learned = LearnedDefaults()
    learned.intervals[btc] = .init(v: "4h", n: 7, at: now)
    learned.priceAxis["equity"] = .init(v: "linear", n: 2, at: now)
    learned.sectorWindow["crypto"] = .init(v: "d5", n: 6, at: now)
    learned.watchMove[btc] = .init(v: 1.25, n: 4, at: now)
    learned.watchMove[eth] = .init(v: 1, n: 4, at: now)
    let items = LearnedItems(learned)
    #expect(items.groups.map(\.title) == ["周期", "价格轴", "板块", "波动提醒"])
    #expect(items.groups[0].rows == [.init(id: "interval." + btc, name: "BTC", value: Interval.h4.shortLabel, count: 7)])
    #expect(items.groups[1].rows.first?.value == "线性")
    #expect(items.groups[2].rows.first?.value == "5 日")
    #expect(items.groups[3].rows.map(\.name) == ["BTC"])
    #expect(items.count == 4)
  }
}
