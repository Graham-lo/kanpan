import Foundation
import KanpanCore

// ============================================================ 重温这件事的两条规矩
//
// 桥（`ReviewChartBridge`）住在 app 里，跑不进这个包的测试；而它身上最容易出错的
// 两件事恰恰是**纯算术**：这段行情该用几位小数（审查 B-04），推进一根之后视野该
// 落在哪（审查 B-05）。所以把这两条搬到这儿，桥只剩「取数、喂给图」这点接线。

/// 这段行情自己的价格小数位。
///
/// 回放的是**另一个品种**，精度不能跟着当前这张实时图走：一位小数的图上打开
/// 0.00001234 的记录，轴、十字线、画线标签会把它写成 `0.0`（审查 B-04）。
/// 宿主优先取品种目录的 `priceDecimals`；目录缺失时才用这里从报价推导的位数兜底。
/// 一批整数报价不能证明品种没有小数位，故返回未知交给宿主处理。
public enum ReviewPricePrecision {
  /// 最多认到第几位。币安 USDⓈ-M 的 `pricePrecision` 不超过 8。
  public static let maxDecimals = 8

  /// 这批价格需要几位小数；全是整数时返回 `nil`（该由调用方按一口价兜底）。
  public static func decimals(of prices: [Double]) -> Int? {
    var need = 0
    for price in prices where price.isFinite && price != 0 {
      need = max(need, digits(price))
      if need >= maxDecimals { return maxDecimals }
    }
    return need > 0 ? need : nil
  }

  /// 小数位 → `tickSize`。
  public static func tickSize(decimals: Int) -> Double {
    pow(10, -Double(max(0, min(maxDecimals, decimals))))
  }

  private static func digits(_ price: Double) -> Int {
    let magnitude = abs(price)
    for d in 0...maxDecimals {
      let scaled = magnitude * pow(10, Double(d))
      // 浮点数还原出来的报价会差几个 ulp，容差按量级给，不能写死绝对值：
      // 76800.5 和 0.00001234 差着八个数量级。
      if abs(scaled - scaled.rounded()) <= max(1, scaled) * 1e-9 { return d }
    }
    return maxDecimals
  }
}

/// 重温时的视野（毫秒）。和 `KanpanCore.ViewWindow` 同一口径：存右缘 + 窗宽。
public struct ReviewReplayWindow: Sendable, Equatable {
  public var to: Double
  public var span: Double
  public init(to: Double, span: Double) { self.to = to; self.span = span }
}

/// 推进一根之后，视野该落在哪。
///
/// 原来每一拍都写死 `span = 80 根`、右缘贴着最新一根（审查 B-05）：人在回放里放大
/// 看细节，按一下「下一根」就被缩回 80 根——那颗按钮把人的手一次次拨开。
///
/// 现在 80 根只是**第一次进来**（和明确「跳到判断处」重新取数）时的兜底；之后：
/// * 根宽（`span`）一律保留，人捏成什么样就是什么样；
/// * 右缘只在**人还跟着播放头**时才跟着走——最新那根还在屏幕里就算跟着；
///   人已经拖去看历史了，就一动不动，让新根在视野外长出来。
public enum ReviewReplayViewport {
  /// 没有个人视野时的兜底窗宽（根）。
  public static let defaultBars: Double = 80
  /// 右边留白（根）。
  public static let rightPadBars: Double = 6

  public static func next(current: ReviewReplayWindow?, previousLastTime: Int64?,
                          lastTime: Int64, step: Int64, reset: Bool) -> ReviewReplayWindow {
    let fallback = ReviewReplayWindow(to: Double(lastTime + step * Int64(rightPadBars)),
                                      span: Double(step) * defaultBars)
    guard !reset, let current, current.span > 0, current.to.isFinite, current.span.isFinite else { return fallback }
    guard let previousLastTime else { return ReviewReplayWindow(to: fallback.to, span: current.span) }
    // 最新那根的开盘时刻还在视野里 = 人还跟着播放头。
    guard current.to >= Double(previousLastTime) else { return current }
    return ReviewReplayWindow(to: fallback.to, span: current.span)
  }
}

// ============================================================ 回放条上那根进度线

/// 回放条上那根可拖的进度线。
///
/// 按「卷里第几根」算，不按时间算：月线这类不等长的周期照样一格一根。两种回放都有它——
/// 交易回放从开仓前 20 根到平仓后 5 根、刻度打在开仓与平仓两根上；笔记回放从这卷的首根
/// 到末根、刻度打在判断那根上（往前补了历史，卷长了它就跟着长）。
public struct ReviewReplayTrack: Sendable, Equatable {
  public var lower: Int
  public var upper: Int
  public var marks: [Int]
  public init(lower: Int, upper: Int, marks: [Int] = []) {
    self.lower = lower; self.upper = max(lower, upper); self.marks = marks
  }

  /// 第 `index` 根在线上的位置（0…1）。
  public func fraction(of index: Int) -> Double {
    guard upper > lower else { return 1 }
    return min(1, max(0, Double(index - lower) / Double(upper - lower)))
  }

  /// 手指落在线上 `fraction` 处，对应第几根（就近取整）。
  public func index(at fraction: Double) -> Int {
    guard upper > lower, fraction.isFinite else { return upper }
    let clamped = min(1, max(0, fraction))
    return lower + Int((clamped * Double(upper - lower)).rounded())
  }

  /// 刻度的位置，只留落在线上的。
  public var markFractions: [Double] {
    marks.filter { $0 >= lower && $0 <= upper }.map(fraction(of:))
  }

  /// 从第 `from` 根拖到第 `to` 根，有没有越过（或踩上）一个刻度——拖动时震一下用。
  /// 出发的那一根不算：停在刻度上起手不该先震一下。
  public func crossesMark(from: Int, to: Int) -> Bool {
    guard from != to else { return false }
    return marks.contains { mark in
      from < to ? (mark > from && mark <= to) : (mark < from && mark >= to)
    }
  }
}

// ============================================================ 交易回放（自动复盘 3d）

/// 已平仓的一笔，在行情图上从开仓前一段一路播到平仓后几根：这一段要的全部纯算术。
///
/// 目标是把这笔单子还原成当时的场景——当时 K 线怎么走、在哪一根进、在哪一根出。
/// 桥（`ReviewChartBridge.openTrade`）只管取数、喂图、按这里的答案停顿与收尾。
public struct TradeReplayPlan: Sendable, Equatable {
  /// 图上的一笔成交：落在哪根、什么价、买还是卖、是进场（开 / 加）还是离场（减 / 平）。
  public struct Mark: Sendable, Equatable {
    public var time: Int64
    public var bar: Int64
    public var price: Double
    public var qty: Double
    public var buy: Bool
    public var entry: Bool
  }
  /// 开仓均价那条虚线的一段：加仓之后均价会变，所以是一段一段的。
  public struct Segment: Sendable, Equatable {
    public var from: Int64
    public var to: Int64
    public var price: Double
    public init(from: Int64, to: Int64, price: Double) { self.from = from; self.to = to; self.price = price }
  }

  /// 开仓前静止起点留几根。
  public static let leadBars = 20
  /// 平仓后再播几根就停。
  public static let tailBars = 5
  /// 指标要热身：起点再往前多取几根。
  public static let historyBars = 300
  /// 进来先静止多久再自动播（毫秒）。
  public static let holdMs = 800
  /// 走到开仓 / 平仓那根停多久（毫秒）。
  public static let pauseMs = 1200
  /// 人自己的周期：开仓→平仓落在这么多根里才用它。
  public static let preferredBars = 10...200
  /// 自己挑周期时，让这笔落在这么多根里。
  public static let targetBars = 30...60
  /// 自己挑周期时的候选。
  public static let candidates: [Interval] = [.m1, .m5, .m15, .h1, .h4, .d1]

  public let direction: TradeDirection
  public let interval: Interval
  public let step: Int64
  /// 第一笔进场成交所在那根的开盘时刻。
  public let openBar: Int64
  /// 最后一笔离场成交所在那根的开盘时刻。
  public let closeBar: Int64
  /// 进来时游标停的那根（开仓前 20 根）。
  public let startBar: Int64
  /// 自动停下的那根（平仓后 5 根）。
  public let stopBar: Int64
  public let marks: [Mark]
  public let closeAverage: Double?

  /// 这笔用哪个周期回放。顺序（用户 2026-09-28 定）：
  /// 1. 人自己的周期（`preferred`）——他复盘时该看的是他当时会看的那张图——只要这笔在它上面
  ///    落在 10–200 根里；
  /// 2. 服务端那份复盘图的周期（`spec`，协议 4.3）；
  /// 3. 按持仓时长从 1分 / 5分 / 15分 / 1时 / 4时 / 1天 里挑，让这笔落在 30–60 根里
  ///    （够不着就挑离这一段最近的，一样近取小的）。
  /// 周线、月线、年线不参与：一笔单子在那上面只剩一两根，也对不齐交易所的开盘时刻。
  public static func interval(preferred: Interval?, spec: String?, openedAt: Int64, closedAt: Int64) -> Interval {
    if let preferred, eligible(preferred), preferredBars.contains(bars(preferred, from: openedAt, to: closedAt)) {
      return preferred
    }
    if let spec, let value = Interval(rawValue: spec), eligible(value) { return value }
    var best = candidates[0], bestDistance = Int.max
    for candidate in candidates {
      let count = bars(candidate, from: openedAt, to: closedAt)
      let distance = count < targetBars.lowerBound ? targetBars.lowerBound - count
        : count > targetBars.upperBound ? count - targetBars.upperBound : 0
      if distance < bestDistance { best = candidate; bestDistance = distance }
    }
    return best
  }

  /// 从 `from` 所在那根到 `to` 所在那根，一共几根（两头都算）。
  public static func bars(_ interval: Interval, from: Int64, to: Int64) -> Int {
    let step = interval.stepMs
    return Int((floorTo(max(from, to), step) - floorTo(min(from, to), step)) / step) + 1
  }

  static func eligible(_ interval: Interval) -> Bool {
    !interval.isIrregular && interval.stepMs <= Interval.d1.stepMs
  }

  static func floorTo(_ t: Int64, _ step: Int64) -> Int64 {
    let r = t % step
    return r >= 0 ? t - r : t - r - step
  }

  /// 持仓中的回合没有「平仓后」，不回放。
  public init?(round: TradeRound, spec: TradeChartSpec?, preferred: Interval?) {
    guard !round.isOpen, let closedAt = round.closedAt else { return nil }
    let interval = Self.interval(preferred: preferred, spec: spec?.interval, openedAt: round.openedAt, closedAt: closedAt)
    let step = interval.stepMs
    var marks = round.fills.map { fill in
      Mark(time: fill.time, bar: Self.floorTo(fill.time, step),
           price: NSDecimalNumber(decimal: fill.price).doubleValue,
           qty: NSDecimalNumber(decimal: fill.qty).doubleValue,
           buy: fill.side == .buy, entry: fill.role == .open || fill.role == .add)
    }.sorted { $0.time < $1.time }
    // 没有成交明细（老数据）：拿回合自己的开 / 平均价补两笔，图上照样有进出。
    let long = round.direction == .long
    if !marks.contains(where: \.entry) {
      marks.insert(Mark(time: round.openedAt, bar: Self.floorTo(round.openedAt, step),
                        price: NSDecimalNumber(decimal: round.openAvgPrice).doubleValue, qty: 1,
                        buy: long, entry: true), at: 0)
    }
    if !marks.contains(where: { !$0.entry }), let close = round.closeAvgPrice {
      marks.append(Mark(time: closedAt, bar: Self.floorTo(closedAt, step),
                        price: NSDecimalNumber(decimal: close).doubleValue, qty: 1, buy: !long, entry: false))
    }
    let openBar = marks.first(where: \.entry)?.bar ?? Self.floorTo(round.openedAt, step)
    let closeBar = max(openBar, marks.last(where: { !$0.entry })?.bar ?? Self.floorTo(closedAt, step))
    self.direction = round.direction
    self.interval = interval
    self.step = step
    self.openBar = openBar
    self.closeBar = closeBar
    self.startBar = openBar - Int64(Self.leadBars) * step
    self.stopBar = closeBar + Int64(Self.tailBars) * step
    self.marks = marks
    self.closeAverage = round.closeAvgPrice.map { NSDecimalNumber(decimal: $0).doubleValue }
  }

  /// 要取的那一段（毫秒，左闭右开，右端由调用方再按「现在」截）：起点再往前 300 根给指标热身，
  /// 右端到停下那根收盘。服务端给的窗口周期对得上时一并包进来。
  public func fetchWindow(spec: TradeChartSpec?) -> (start: Int64, end: Int64) {
    var start = startBar, end = stopBar + step
    if let spec, spec.interval == interval.rawValue, spec.end > spec.start {
      start = min(start, Self.floorTo(spec.start, step)); end = max(end, spec.end)
    }
    return (start - Int64(Self.historyBars) * step, end)
  }

  /// 走到这一根要不要停一下（开仓那根、平仓那根）。
  public func pauses(at bar: Int64) -> Bool { bar == openBar || bar == closeBar }
  /// 这一根是不是开仓那根：停顿时带出「当时怎么想」。
  public func isOpenBar(_ bar: Int64) -> Bool { bar == openBar }
  /// 播到这一根该收尾了。
  public func finished(at bar: Int64) -> Bool { bar >= stopBar }
  /// 这一根上仓位还拿着：浮动盈亏那颗胶囊只在这一段出现。
  public func holding(at bar: Int64) -> Bool { bar >= openBar && bar < closeBar }

  /// 最新一根是 `bar` 时，图上能画的成交：只画已经发生的，不漏未来。
  public func visibleMarks(through bar: Int64) -> [Mark] { marks.filter { $0.bar <= bar } }

  /// 到这一根为止的开仓均价（进场成交按数量加权）。还没开仓是 `nil`。
  public func entryAverage(through bar: Int64) -> Double? {
    var cost = 0.0, qty = 0.0
    for mark in marks where mark.entry && mark.bar <= bar { cost += mark.price * mark.qty; qty += mark.qty }
    return qty > 0 ? cost / qty : nil
  }

  /// 开仓均价那条虚线：从开仓那根画到「此刻」与平仓那根里早的一个，加仓处换一段。
  public func entrySegments(through bar: Int64) -> [Segment] {
    let end = min(bar, closeBar)
    guard end >= openBar else { return [] }
    let changes = Array(Set(marks.filter { $0.entry && $0.bar <= end }.map(\.bar))).sorted()
    var result: [Segment] = []
    for (i, from) in changes.enumerated() {
      guard let price = entryAverage(through: from) else { continue }
      let to = i + 1 < changes.count ? changes[i + 1] : end
      result.append(Segment(from: from, to: to, price: price))
    }
    return result
  }

  /// 此刻的浮动盈亏（比值）：这一根收盘价对开仓均价，按方向取正负。只在持仓那一段给。
  public func floatingReturn(close: Double, at bar: Int64) -> Double? {
    guard holding(at: bar), let average = entryAverage(through: bar), average > 0, close.isFinite else { return nil }
    let change = (close - average) / average
    return direction == .long ? change : -change
  }
}
