import Foundation
import KanpanCore

/// 从行为日志推结论。全是纯函数：同一份日志、同一个「现在」，推出来的永远一样。
///
/// 四条规则（数字都在下面的常量里，单测钉着）：
///
/// 1. **品种的打开周期**：这只品种上各周期的停留秒数按新近加权（半衰期 7 天）累计，
///    取最多的那个；最多的那个加权后不到 `intervalMinSeconds` 就算还没学到。
/// 2. **类别的价格轴**：同一类品种上线性 / 对数的停留秒数同样加权累计；在图表设置里亲手
///    切一次，切到的那一档就抬到「此刻领先的另一档 + `axisPickFloor`」——
///    亲手选的立刻压过之前的一切，之后再按停留慢慢变。百分比不参与。
/// 3. **板块页今日 / 5 日**：每个市场最近 10 次选择里多的那个；不到 3 次、或者打平，不算学到。
/// 4. **自选波动提醒的灵敏度**：每只品种一个倍数，从 1 起，在 `factorLadder` 上走。
///    响了之后 15 分钟内点开了那只 → 降一档（更灵敏）；连续两次没点开 → 升一档（更迟钝）。
///    两头夹在 0.5 与 2 之间。还没到 15 分钟的那一响先不算。
enum HabitInference {
  /// 新近加权的半衰期。
  static let halfLife: Double = 7 * 86_400
  /// 一段停留短于这个（秒）不记——点进去扫一眼就走不算「看」。
  static let minDwell: Double = 5
  /// 一段停留最多记这么久：图表页在前台常亮，人走开了屏幕也亮着。
  static let maxDwell: Double = 30 * 60
  static let intervalMinSeconds: Double = 120
  static let axisMinSeconds: Double = 120
  static let axisPickFloor: Double = 120
  static let sectorRecent = 10
  static let sectorMinPicks = 3
  static let moveOpenWindow: Double = 15 * 60
  static let moveIgnoredStreak = 2
  static let factorLadder: [Double] = [0.5, 0.63, 0.8, 1.0, 1.25, 1.6, 2.0]
  static let factorStart = 3

  static func decay(age: Double) -> Double { pow(0.5, max(0, age) / halfLife) }

  /// 整份结论。只含日志里有依据的键。
  static func learn(from log: HabitLog, now: Double) -> LearnedDefaults {
    let events = log.events.filter { $0.t >= now - HabitLog.retention }
    var out = LearnedDefaults()
    out.intervals = intervals(events, now: now)
    out.priceAxis = priceAxis(events, now: now)
    out.sectorWindow = sectorWindow(events)
    out.watchMove = watchMove(events, now: now)
    return out
  }

  // ---------------------------------------------------------------- 1. 周期

  static func intervals(_ events: [HabitEvent], now: Double) -> [String: LearnedDefaults.Choice] {
    var tallies: [String: Tally] = [:]
    for e in events where e.kind == .interval && Interval(rawValue: e.value) != nil {
      tallies[e.key, default: Tally()].add(e.value, weight: e.w * decay(age: now - e.t), at: e.t)
    }
    return tallies.compactMapValues { $0.winner(minimum: intervalMinSeconds) }
  }

  // ---------------------------------------------------------------- 2. 价格轴

  static func priceAxis(_ events: [HabitEvent], now: Double) -> [String: LearnedDefaults.Choice] {
    var tallies: [String: Tally] = [:]
    for e in events where LearnedDefaults.axisValues.contains(e.value) {
      switch e.kind {
      case .axisDwell:
        tallies[e.key, default: Tally()].add(e.value, weight: e.w * decay(age: now - e.t), at: e.t)
      case .axisPick:
        // 从前记的是「此前这一类全部依据之和 + 底分」：每切一次总量翻一倍，来回切上
        // 一千来次就溢出成 inf，两档都是 inf 时谁赢全凭字面序（深度审查 D 线 2026-10-04）。
        // 压过之前的一切只需要压过此刻领先的那一档：抬到它之上一个底分，来回切只线性涨。
        tallies[e.key, default: Tally()].outbid(e.value, margin: axisPickFloor * decay(age: now - e.t), at: e.t)
        tallies[e.key]?.picked = true
      default: continue
      }
    }
    // 光靠停留要够久；亲手切过的（带着底分）一定算学到。
    return tallies.compactMapValues { $0.winner(minimum: axisMinSeconds) }
  }

  // ---------------------------------------------------------------- 3. 板块窗口

  static func sectorWindow(_ events: [HabitEvent]) -> [String: LearnedDefaults.Choice] {
    var picks: [String: [HabitEvent]] = [:]
    for e in events where e.kind == .sectorWindow && LearnedDefaults.sectorValues.contains(e.value) {
      picks[e.key, default: []].append(e)
    }
    return picks.compactMapValues { all in
      let recent = all.sorted { $0.t < $1.t }.suffix(sectorRecent)
      guard recent.count >= sectorMinPicks else { return nil }
      var counts: [String: Int] = [:]
      for e in recent { counts[e.value, default: 0] += 1 }
      let ranked = counts.sorted { $0.value > $1.value }
      guard let top = ranked.first, ranked.count == 1 || ranked[1].value < top.value else { return nil }
      return .init(v: top.key, n: top.value, at: recent.last?.t ?? 0)
    }
  }

  // ---------------------------------------------------------------- 4. 波动提醒倍数

  enum MoveOutcome: Equatable { case opened, ignored }

  /// 每一响的结局，按时间先后。还没满 15 分钟又没点开的那一响不在里面。
  static func outcomes(fires: [Double], opens: [Double], now: Double) -> [(t: Double, outcome: MoveOutcome)] {
    fires.sorted().compactMap { f in
      if opens.contains(where: { $0 >= f && $0 - f <= moveOpenWindow }) { return (f, .opened) }
      return now - f >= moveOpenWindow ? (f, .ignored) : nil
    }
  }

  /// 在阶梯上走一遍，返回落在第几档。
  static func step(_ outcomes: [MoveOutcome]) -> Int {
    var index = factorStart
    var streak = 0
    for outcome in outcomes {
      switch outcome {
      case .opened:
        index = max(0, index - 1); streak = 0
      case .ignored:
        streak += 1
        if streak >= moveIgnoredStreak { index = min(factorLadder.count - 1, index + 1); streak = 0 }
      }
    }
    return index
  }

  static func watchMove(_ events: [HabitEvent], now: Double) -> [String: LearnedDefaults.Factor] {
    var fires: [String: [Double]] = [:]
    var opens: [String: [Double]] = [:]
    for e in events {
      switch e.kind {
      case .moveFired: fires[e.key, default: []].append(e.t)
      case .moveOpened: opens[e.key, default: []].append(e.t)
      default: continue
      }
    }
    var out: [String: LearnedDefaults.Factor] = [:]
    for (key, times) in fires {
      let resolved = outcomes(fires: times, opens: opens[key] ?? [], now: now)
      guard let last = resolved.last else { continue }
      out[key] = .init(v: factorLadder[step(resolved.map(\.outcome))], n: resolved.count, at: last.t)
    }
    return out
  }

  // ---------------------------------------------------------------- 累计

  /// 一张「值 → 加权秒数」的表，外加每个值被记了几段、最近一段在什么时候。
  struct Tally {
    var weights: [String: Double] = [:]
    var counts: [String: Int] = [:]
    var latest: Double = 0
    /// 这一类里有没有亲手切过（价格轴）。切过就不看停留够不够久。
    var picked = false

    var total: Double { weights.values.reduce(0, +) }

    mutating func add(_ value: String, weight: Double, at t: Double) {
      weights[value, default: 0] += weight
      counts[value, default: 0] += 1
      latest = max(latest, t)
    }

    /// 亲手选：把 `value` 抬到「其余各档里最多的那个 + `margin`」，已经更高就加一个 `margin`
    /// （再切一次同一档也算一次依据，不白切）。
    mutating func outbid(_ value: String, margin: Double, at t: Double) {
      let own = weights[value] ?? 0
      let rival = weights.lazy.filter { $0.key != value }.map(\.value).max() ?? 0
      add(value, weight: max(rival + margin - own, margin), at: t)
    }

    /// 最多的那个；打平时按值的字面序定，保证结果稳定。
    func winner(minimum: Double) -> LearnedDefaults.Choice? {
      guard let top = weights.max(by: { $0.value != $1.value ? $0.value < $1.value : $0.key > $1.key }),
            top.value > 0, top.value >= minimum || picked else { return nil }
      return .init(v: top.key, n: counts[top.key] ?? 0, at: latest)
    }
  }
}
