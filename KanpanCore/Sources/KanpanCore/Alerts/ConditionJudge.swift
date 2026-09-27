import Foundation

/// 条件提醒触发时观测到的东西：推送正文、Webhook 的 `detail` / `value`、回写的 `firedPrice`。
/// 字段与服务端 `conditions.rs` 的 `Observation` 一一对应。
public struct ConditionObservation: Sendable, Equatable {
  /// 判到的时刻（毫秒）。
  public var at: Double
  /// `firedPrice`：费率是标记价格、持仓量是现价、均线是收盘价、大单是墙的价位。
  public var price: Double
  /// 推送正文（不含备注）：「预测费率 0.0612% · 14 分钟后结算」。
  public var detail: String
  /// Webhook 的 `value`（协议第 4 节）。
  public var value: RuleJSON

  public init(at: Double, price: Double, detail: String, value: RuleJSON) {
    self.at = at; self.price = price; self.detail = detail; self.value = value
  }
}

/// 条件提醒的四种判法（纯函数，不碰网络、不读时钟）。
///
/// 口径和服务端 `conditions.rs` / `conditions/walls.rs` 一字不差（协议第 2 节），所以前台判到的
/// 和服务端判到的是同一件事，谁先判到谁响；「只响一次」靠 `status`，不靠这里。
public enum ConditionJudge {
  /// 费率在结算前多久判。
  public static let fundingWindowMs: Double = 15 * 60_000
  /// 持仓量比的是多久以前、点距多少。
  public static let oiSpanMs: Double = 60 * 60_000
  public static let oiPeriodMs: Double = 5 * 60_000

  // ---------------------------------------------------------------- 费率

  /// `now` 在不在这一次结算的判定窗口里（结算前 15 分钟到结算），且已经武装。
  /// 窗口里每一次结算只判一次——「判过哪一次」由调用方按 `nextFunding` 记。
  public static func inFundingWindow(now: Double, nextFunding: Double, armedAt: Double) -> Bool {
    nextFunding > 0 && now >= nextFunding - fundingWindowMs && now < nextFunding && now >= armedAt
  }

  /// 预测费率过没过线；过了给观测。`predicted` 是比值。
  public static func funding(side: AlertRule.Side, rate: String, predicted: Decimal, mark: Double,
                             nextFunding: Double, now: Double) -> ConditionObservation? {
    guard let rate = AlertRule.decimal(rate) else { return nil }
    let met = side == .above ? predicted >= rate : predicted <= rate
    guard met else { return nil }
    let minutes = Int(((nextFunding - now) + 59_999) / 60_000)
    return ConditionObservation(
      at: now, price: mark,
      detail: "预测费率 \(AlertRule.percent(predicted, dp: 4))% · \(minutes) 分钟后结算",
      value: .object(["rate": .string(AlertRule.text(predicted)), "markPrice": .string(plain(mark)),
                      "nextFundingTime": .int(Int(nextFunding))]))
  }

  // ---------------------------------------------------------------- 持仓量

  /// 一个持仓量点：时刻（毫秒）与币数量（`sumOpenInterest`）。
  public struct OIPoint: Sendable, Equatable {
    public var at: Double
    public var amount: Double
    public init(at: Double, amount: Double) { self.at = at; self.amount = amount }
  }

  /// 最新一个点 `L` 与恰好 1 小时前的点 `P` 比，`|变化| ≥ threshold` 就响；只看 `L.at ≥ armedAt`，缺 `P` 不判。
  /// 同一个 `L` 只判一次由调用方记。`price` 是现价（写进正文与 `firedPrice`）。
  public static func openInterest(threshold: String, points: [OIPoint], armedAt: Double, price: Double,
                                  now: Double) -> ConditionObservation? {
    guard let threshold = AlertRule.decimal(threshold), let last = points.max(by: { $0.at < $1.at }),
          last.at >= armedAt,
          let before = points.first(where: { $0.at == last.at - oiSpanMs }),
          before.amount > 0, last.amount > 0, before.amount.isFinite, last.amount.isFinite else { return nil }
    let change = Decimal(last.amount - before.amount) / Decimal(before.amount)
    guard abs(change) >= threshold else { return nil }
    var rounded = Decimal(); var raw = change
    NSDecimalRound(&rounded, &raw, 8, .plain)
    return ConditionObservation(
      at: now, price: price,
      detail: "1 小时持仓量 \(AlertRule.signedPercent(change, dp: 2)) · 现价 \(AlertRule.money(price))",
      value: .object(["change": .string(AlertRule.text(rounded)), "from": .string(plain(before.amount)),
                      "to": .string(plain(last.amount)), "at": .int(Int(last.at))]))
  }

  // ---------------------------------------------------------------- 均线

  /// 一根**已收盘**的 K 线。
  public struct ClosedBar: Sendable, Equatable {
    public var openTime: Double
    public var close: Double
    /// 收盘时刻（毫秒，= 开盘 + 周期）。
    public var closeTime: Double
    public init(openTime: Double, close: Double, closeTime: Double) {
      self.openTime = openTime; self.close = close; self.closeTime = closeTime
    }
  }

  /// `bars` 里最后一根 `k`（已收盘）与前一根比，边沿穿过才响：
  /// above：`C[k-1] < MA[k-1]` 且 `C[k] ≥ MA[k]`；below 反之。需要 N + 1 根，只判收盘晚于 armedAt 的。
  public static func maCross(length: Int, side: AlertRule.Side, bars: [ClosedBar], armedAt: Double,
                             now: Double) -> ConditionObservation? {
    guard length >= 1, bars.count >= length + 1, let bar = bars.last, bar.closeTime > armedAt else { return nil }
    let closes = bars.map(\.close)
    let k = closes.count - 1
    guard let ma = sma(closes, k, length), let prevMA = sma(closes, k - 1, length) else { return nil }
    let (c, p) = (closes[k], closes[k - 1])
    let crossed = side == .above ? (p < prevMA && c >= ma) : (p > prevMA && c <= ma)
    guard crossed else { return nil }
    return ConditionObservation(
      at: now, price: c,
      detail: "收盘 \(AlertRule.money(c)) · MA\(length) \(AlertRule.money(ma))",
      value: .object(["close": .string(plain(c)), "ma": .string(plain(ma)),
                      "openTime": .int(Int(bar.openTime)), "closeTime": .int(Int(bar.closeTime))]))
  }

  /// 收盘价的简单移动平均，含第 `k` 根（`Indicator/Math.swift` 的 `sma` 同一口径）。
  static func sma(_ closes: [Double], _ k: Int, _ n: Int) -> Double? {
    guard n >= 1, k + 1 >= n, k < closes.count, k >= 0 else { return nil }
    return closes[(k + 1 - n)...k].reduce(0, +) / Double(n)
  }

  // ---------------------------------------------------------------- 大单

  /// 一面还挂着的墙。
  public struct Wall: Sendable, Equatable {
    /// 同一面墙的稳定键（`BigOrder.id`）。
    public var key: String
    /// 交易所显示名（「币安」）。
    public var exchange: String
    /// `spot` / `usdtPerp` / `coinPerp` / `delivery`。
    public var product: String
    /// `bid` / `ask`。
    public var side: String
    public var price: Double
    public var notional: Double
    public var firstSeen: Double
    public init(key: String, exchange: String, product: String, side: String, price: Double,
                notional: Double, firstSeen: Double) {
      self.key = key; self.exchange = exchange; self.product = product; self.side = side
      self.price = price; self.notional = notional; self.firstSeen = firstSeen
    }
  }

  /// 武装后第一次看到这只品种的簿时的基线：那一刻已经 ≥ 门槛、且首次出现早于武装的老墙。
  public static func wallBaseline(walls: [Wall], threshold: Double, armedAt: Double) -> Set<String> {
    Set(walls.filter { $0.firstSeen < armedAt && $0.notional >= threshold }.map(\.key))
  }

  /// 只认新的墙：首次出现在武装之后的，或不在基线里（武装后第一次看到时还没到门槛、后来长过去）的。
  /// 有多面就挑名义最大的那面。
  public static func wall(threshold: Double, walls: [Wall], baseline: Set<String>, armedAt: Double,
                          now: Double) -> ConditionObservation? {
    guard let w = walls.filter({ $0.notional >= threshold && ($0.firstSeen >= armedAt || !baseline.contains($0.key)) })
      .max(by: { $0.notional < $1.notional }) else { return nil }
    return ConditionObservation(
      at: now, price: w.price,
      detail: "\(w.exchange) \(productLabel(w.product)) \(w.side == "bid" ? "买墙" : "卖墙") \(AlertRule.units(w.notional)) @ \(AlertRule.money(w.price))",
      value: .object(["exchange": .string(w.exchange), "product": .string(w.product), "side": .string(w.side),
                      "price": .string(plain(w.price)), "notional": .string(plain(w.notional.rounded())),
                      "firstSeen": .int(Int(w.firstSeen))]))
  }

  public static func productLabel(_ product: String) -> String {
    switch product {
    case "spot": "现货"
    case "usdtPerp": "U 本位"
    case "coinPerp": "币本位"
    case "delivery": "交割"
    default: product
    }
  }

  // ---------------------------------------------------------------- 服务端判到的

  /// 服务端判到的那条同步下来只有 `firedAt` / `firedPrice`，没有正文——按种类补一句。
  public static func fallbackDetail(rule: AlertRule?, price: Double?) -> String {
    guard let price, price.isFinite, price > 0 else { return rule?.phrase ?? "条件提醒" }
    let money = AlertRule.money(price)
    switch rule {
    case .funding: return "标记价格 \(money)"
    case .openInterestChange: return "现价 \(money)"
    case .maCross: return "收盘 \(money)"
    case .orderflowWall: return "挂单价 \(money)"
    default: return "现价 \(money)"
    }
  }

  /// 数 → 十进制字符串（不用科学计数法；Webhook 的 `value` 用）。
  static func plain(_ v: Double) -> String {
    guard v.isFinite else { return "0" }
    // 最短往返写法（和服务端 `f64::to_string` 一样短）；带指数的再走 Decimal 展开。
    var text = v.description
    if text.hasSuffix(".0") { text.removeLast(2) }
    if text.contains("e") || text.contains("E") { return AlertRule.text(Decimal(string: text) ?? Decimal(v)) }
    return text
  }
}
