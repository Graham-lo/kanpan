import Foundation

// 交易侧战绩（方案 3.4）：胜率、盈亏比、期望值、总净盈亏、费用占毛利、最大连亏、平均持仓时长，
// 按品种 / 方向 / 持仓时长档 / 开仓时段 / 周几分组，外加复盘本交易段顶部那张「上周」周报卡。
//
// 全是算术，客户端算、服务端不另存聚合：回合本身随复盘同步，算的口径改了只要改这里，
// 不用去迁移服务端存下来的旧聚合。只统计已平仓的回合——持仓中的盈亏还没定。
// 只给数字，不打分、不点评（不接 AI，`kanpan-chart-shows-data-not-quant-judgement`）。

/// 一组回合的汇总。所有金额都按回合自己的 `quoteAsset` 直接相加（第一期全是 U 本位，USDT / USDC 一比一看）。
public struct RoundSummary: Sendable, Hashable {
  public var count = 0
  /// 净盈亏 > 0 的笔数。
  public var wins = 0
  /// 净盈亏 < 0 的笔数（打平不算输也不算赢）。
  public var losses = 0
  /// 胜率 = 赢的笔数 ÷ 总笔数（比值）。
  public var winRate: Decimal?
  public var netPnl: Decimal = 0
  /// 毛利 = 已实现盈亏合计（费用之前）。
  public var grossPnl: Decimal = 0
  public var commission: Decimal = 0
  /// 资金费合计，正数 = 收入。
  public var funding: Decimal = 0
  /// 费用 = 手续费 − 资金费收入（资金费是支出时就是手续费加上它）。
  public var fees: Decimal = 0
  /// 费用占毛利的比例；毛利 ≤ 0 时没有意义，留空。
  public var feeShareOfGross: Decimal?
  public var averageWin: Decimal?
  public var averageLoss: Decimal?
  /// 盈亏比 = 平均每笔赢 ÷ 平均每笔亏的绝对值；没有赢或没有亏时留空。
  public var rewardRisk: Decimal?
  /// 期望值 = 平均每笔净盈亏。
  public var expectancy: Decimal?
  /// 最长连续亏损笔数（按平仓时间排）。
  public var longestLosingStreak = 0
  public var averageHoldingMs: Int64?
  public var best: TradeRound?
  public var worst: TradeRound?

  public init() {}
}

/// 持仓时长档。
public enum HoldingBucket: Int, CaseIterable, Sendable, Hashable, Comparable {
  case underHour, hourToDay, dayToWeek, overWeek

  public init(holdingMs: Int64) {
    switch holdingMs {
    case ..<3_600_000: self = .underHour
    case ..<86_400_000: self = .hourToDay
    case ..<(7 * 86_400_000): self = .dayToWeek
    default: self = .overWeek
    }
  }

  public var title: String {
    switch self {
    case .underHour: "1 小时内"
    case .hourToDay: "1 小时–1 天"
    case .dayToWeek: "1–7 天"
    case .overWeek: "7 天以上"
    }
  }

  public static func < (a: Self, b: Self) -> Bool { a.rawValue < b.rawValue }
}

/// 开仓时段（本地时间四段）。
public enum SessionSlot: Int, CaseIterable, Sendable, Hashable, Comparable {
  case night, morning, afternoon, evening

  public init(hour: Int) {
    switch hour {
    case ..<6: self = .night
    case ..<12: self = .morning
    case ..<18: self = .afternoon
    default: self = .evening
    }
  }

  public var title: String {
    switch self {
    case .night: "凌晨 0–6 点"
    case .morning: "上午 6–12 点"
    case .afternoon: "下午 12–18 点"
    case .evening: "晚上 18–24 点"
    }
  }

  public static func < (a: Self, b: Self) -> Bool { a.rawValue < b.rawValue }
}

/// 周几，周一 = 1 … 周日 = 7（周一开头，和周报的周界一致）。
public struct Weekday: Sendable, Hashable, Comparable {
  public let index: Int
  public init(index: Int) { self.index = index }

  public var title: String { ["周一", "周二", "周三", "周四", "周五", "周六", "周日"][index - 1] }

  public static func < (a: Self, b: Self) -> Bool { a.index < b.index }
}

public struct RoundGroup<Key: Hashable & Sendable>: Sendable {
  public let key: Key
  public let summary: RoundSummary
}

public enum RoundStats {
  // MARK: 汇总

  public static func summarize(_ rounds: [TradeRound]) -> RoundSummary {
    let done = rounds.filter { $0.status == .closed }
      .sorted { ($0.closedAt ?? 0, $0.id) < ($1.closedAt ?? 0, $1.id) }
    var s = RoundSummary()
    guard !done.isEmpty else { return s }
    s.count = done.count
    var winSum: Decimal = 0, lossSum: Decimal = 0, holding: Int64 = 0, streak = 0
    for r in done {
      s.netPnl += r.netPnl
      s.grossPnl += r.realizedPnl
      s.commission += r.commission
      s.funding += r.funding
      holding += r.holdingMs ?? 0
      if r.netPnl > 0 { s.wins += 1; winSum += r.netPnl; streak = 0 }
      if r.netPnl < 0 {
        s.losses += 1; lossSum += r.netPnl; streak += 1
        s.longestLosingStreak = max(s.longestLosingStreak, streak)
      }
      if r.netPnl == 0 { streak = 0 }
      if s.best.map({ r.netPnl > $0.netPnl }) ?? true { s.best = r }
      if s.worst.map({ r.netPnl < $0.netPnl }) ?? true { s.worst = r }
    }
    let n = Decimal(s.count)
    s.fees = s.commission - s.funding
    s.winRate = ratio(Decimal(s.wins) / n)
    s.expectancy = (s.netPnl / n).amountRounded
    s.feeShareOfGross = s.grossPnl > 0 ? ratio(s.fees / s.grossPnl) : nil
    s.averageWin = s.wins > 0 ? (winSum / Decimal(s.wins)).amountRounded : nil
    s.averageLoss = s.losses > 0 ? (lossSum / Decimal(s.losses)).amountRounded : nil
    if let w = s.averageWin, let l = s.averageLoss, l != 0 {
      s.rewardRisk = TradeDecimal.round(w / l.magnitudeValue, scale: TradeDecimal.rewardRiskScale)
    }
    s.averageHoldingMs = holding / Int64(s.count)
    return s
  }

  // MARK: 分组

  public static func bySymbol(_ rounds: [TradeRound]) -> [RoundGroup<String>] {
    // 按净盈亏从高到低排：一眼看出钱在哪只上赚、在哪只上亏。
    group(rounds) { $0.symbol }.sorted { $0.summary.netPnl != $1.summary.netPnl
      ? $0.summary.netPnl > $1.summary.netPnl : $0.key < $1.key }
  }

  public static func byDirection(_ rounds: [TradeRound]) -> [RoundGroup<TradeDirection>] {
    group(rounds) { $0.direction }.sorted { $0.key == .long && $1.key == .short }
  }

  public static func byHolding(_ rounds: [TradeRound]) -> [RoundGroup<HoldingBucket>] {
    group(rounds) { HoldingBucket(holdingMs: $0.holdingMs ?? 0) }.sorted { $0.key < $1.key }
  }

  /// 按开仓时刻落在本地时间哪一段。
  public static func bySession(_ rounds: [TradeRound], calendar: Calendar = .current) -> [RoundGroup<SessionSlot>] {
    group(rounds) { SessionSlot(hour: calendar.component(.hour, from: date($0.openedAt))) }
      .sorted { $0.key < $1.key }
  }

  /// 按开仓那天是周几。
  public static func byWeekday(_ rounds: [TradeRound], calendar: Calendar = .current) -> [RoundGroup<Weekday>] {
    group(rounds) { weekday($0.openedAt, calendar) }.sorted { $0.key < $1.key }
  }

  static func group<K: Hashable & Sendable>(_ rounds: [TradeRound], by key: (TradeRound) -> K) -> [RoundGroup<K>] {
    Dictionary(grouping: rounds.filter { $0.status == .closed }, by: key)
      .map { RoundGroup(key: $0.key, summary: summarize($0.value)) }
  }

  // MARK: 工具

  static func ratio(_ v: Decimal) -> Decimal { TradeDecimal.round(v, scale: TradeDecimal.ratioScale) }
  static func date(_ ms: Int64) -> Date { Date(timeIntervalSince1970: TimeInterval(ms) / 1000) }
  static func ms(_ d: Date) -> Int64 { Int64((d.timeIntervalSince1970 * 1000).rounded()) }

  static func weekday(_ ms: Int64, _ calendar: Calendar) -> Weekday {
    // Calendar 的 weekday：1 = 周日 … 7 = 周六；换成周一开头。
    let w = calendar.component(.weekday, from: date(ms))
    return Weekday(index: (w + 5) % 7 + 1)
  }
}

/// 复盘本交易段顶部的「上周」周报卡：笔数、净盈亏、胜率、最赚 / 最亏一笔、费用。
/// 周界是本地时区的周一 00:00；周一一过零点就滚到新的一周，不推通知。
public struct WeeklyReport: Sendable {
  /// 上周一 00:00（含）。
  public let start: Int64
  /// 本周一 00:00（不含）。
  public let end: Int64
  /// 平仓时间落在 `[start, end)` 的回合的汇总。
  public let summary: RoundSummary

  public static func lastWeek(_ rounds: [TradeRound], now: Int64, calendar: Calendar = .current) -> WeeklyReport {
    let (start, end) = lastWeekBounds(now: now, calendar: calendar)
    let inWeek = rounds.filter { r in
      guard r.status == .closed, let c = r.closedAt else { return false }
      return c >= start && c < end
    }
    return WeeklyReport(start: start, end: end, summary: RoundStats.summarize(inWeek))
  }

  /// 上周一 00:00 到本周一 00:00（本地时区；按日历加减，夏令时那一周也是整七天日历日）。
  public static func lastWeekBounds(now: Int64, calendar: Calendar = .current) -> (Int64, Int64) {
    let today = calendar.startOfDay(for: RoundStats.date(now))
    let sinceMonday = RoundStats.weekday(now, calendar).index - 1
    let thisMonday = calendar.date(byAdding: .day, value: -sinceMonday, to: today) ?? today
    let lastMonday = calendar.date(byAdding: .day, value: -7, to: thisMonday) ?? thisMonday
    return (RoundStats.ms(lastMonday), RoundStats.ms(thisMonday))
  }
}
