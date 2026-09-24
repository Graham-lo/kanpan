import Foundation

// 主力订单流 · 门槛、步长与显示开关。
//
// 照 CoinAnk「主力大额挂单」：门槛（过滤单位，美元）按产品各一个、步长（价格）一个，都是用户可改、
// 随账号同步的指标设置；代码里只给**初始默认值**（`OrderFlowDefaults`）。用户改过的项按 base 资产
// 存（`[base: OrderFlowOverride]`），没改过的 base 一律走默认表——默认表以后调了，没改过的人跟着变。
// 显示开关（现货 / 合约 / 已成交买卖 / 已撤销买卖）跟人走、全品种共用一份。
//
// ## 默认表的来源
// 原项目 send-tradfi「站立墙之前」的主力墙版本（提交 68e5836 add principal wall monitoring 起、
// 到 e14c93c 切到站立墙之前的最后一版，`crates/bit-orderbook-aggregate` 与
// `crates/bit-orderbook-contract` 的 OrderbookAggregationPolicy）：
//   - BTC / ETH：现货 100 万、永续 500 万；SOL：现货 75 万、永续 250 万（迁移 0043）。
//   - 美股、金银等（非币）：永续 200 万。原项目是 350 万（迁移 0129 / 0131），用户 2026-09-24 按流动性改成 200 万。
//   - 步长 BTC 100、ETH 1、SOL 0.1；MU / SNDK / SPCX / SKHYNIX 1，SKHY 0.1；XAU 1，XAG 0.1（迁移 0048 / 0050 / 0067 / 0070）。
//   - 币本位永续、交割没有单独的原始值，用户 2026-09-24 定为跟永续同一个数。
// 表里没有的币按币安 U 本位永续 24h 成交额分六档（用户 2026-09-24 定，打开品种时定一次）；
// 表里没有步长的品种取前一 UTC 日收盘 × 0.1% 最接近的 1 / 2 / 5 × 10ⁿ，且不小于最小价格步长
// （`BucketScheme.derivedStep`）。

/// 一只 base 此刻生效的门槛与步长。某种产品为 nil = 这只不订这种产品（非币只订 U 本位永续）。
public struct OrderFlowThresholds: Sendable, Equatable, Codable {
  public var spot: Double?
  public var usdtPerp: Double?
  public var coinPerp: Double?
  public var delivery: Double?
  /// 价格步长；nil = 表里没有，等前一日收盘算出来（`BucketScheme.derivedStep`）。
  public var step: Double?

  public init(spot: Double? = nil, usdtPerp: Double? = nil, coinPerp: Double? = nil, delivery: Double? = nil,
              step: Double? = nil) {
    self.spot = spot; self.usdtPerp = usdtPerp; self.coinPerp = coinPerp; self.delivery = delivery; self.step = step
  }

  public subscript(product: OrderFlowProduct) -> Double? {
    get {
      switch product {
      case .spot: spot
      case .usdtPerp: usdtPerp
      case .coinPerp: coinPerp
      case .delivery: delivery
      }
    }
    set {
      switch product {
      case .spot: spot = newValue
      case .usdtPerp: usdtPerp = newValue
      case .coinPerp: coinPerp = newValue
      case .delivery: delivery = newValue
      }
    }
  }

  /// 这只要订的产品。
  public var products: [OrderFlowProduct] { OrderFlowProduct.allCases.filter { self[$0] != nil } }

  /// 叠上用户改过的项。用户不能给这只没有的产品凭空加一个门槛（非币仍只订 U 本位永续）。
  public func applying(_ override: OrderFlowOverride?) -> OrderFlowThresholds {
    guard let override = override?.normalized else { return self }
    var out = self
    for product in OrderFlowProduct.allCases where out[product] != nil {
      if let value = override[product] { out[product] = value }
    }
    if let step = override.step { out.step = step }
    return out
  }
}

/// 用户在指标面板里改过的那几项（一只 base 一份）。nil 的项用默认表。
public struct OrderFlowOverride: Sendable, Equatable, Codable {
  public var spot: Double?
  public var usdtPerp: Double?
  public var coinPerp: Double?
  public var delivery: Double?
  public var step: Double?

  /// 门槛允许的范围（美元）。服务端 `sync_validation.rs` 的值规则是同一组数。
  public static let thresholdRange: ClosedRange<Double> = 1_000...1_000_000_000
  /// 步长允许的范围（价格）。
  public static let stepRange: ClosedRange<Double> = 0.000_000_01...1_000_000

  public init(spot: Double? = nil, usdtPerp: Double? = nil, coinPerp: Double? = nil, delivery: Double? = nil,
              step: Double? = nil) {
    self.spot = spot; self.usdtPerp = usdtPerp; self.coinPerp = coinPerp; self.delivery = delivery; self.step = step
  }

  public subscript(product: OrderFlowProduct) -> Double? {
    get {
      switch product {
      case .spot: spot
      case .usdtPerp: usdtPerp
      case .coinPerp: coinPerp
      case .delivery: delivery
      }
    }
    set {
      switch product {
      case .spot: spot = newValue
      case .usdtPerp: usdtPerp = newValue
      case .coinPerp: coinPerp = newValue
      case .delivery: delivery = newValue
      }
    }
  }

  public var isEmpty: Bool { normalized == nil }

  /// 越界、非数的项丢掉（不夹到边上：用户没输过那个数）；一项都不剩就是 nil。
  public var normalized: OrderFlowOverride? {
    var out = OrderFlowOverride()
    for product in OrderFlowProduct.allCases {
      if let v = self[product], v.isFinite, Self.thresholdRange.contains(v) { out[product] = v }
    }
    if let s = step, s.isFinite, Self.stepRange.contains(s) { out.step = s }
    let empty = OrderFlowProduct.allCases.allSatisfy { out[$0] == nil } && out.step == nil
    return empty ? nil : out
  }
}

/// 显示开关：跟人走、全品种共用。只管画不画，不影响跟踪（关掉再开，历史还在）。
public struct OrderFlowDisplay: Sendable, Equatable, Codable {
  /// 显示现货的大单。
  public var spot = true
  /// 显示合约（U 本位永续、币本位永续、交割）的大单。
  public var contract = true
  /// 显示已成交的大单（买卖两侧一起）。
  public var filled = true
  /// 显示已撤销的大单（买卖两侧一起）。
  public var cancelled = true
  // 原来已成交 / 已撤销各按买卖拆成两个开关（六个），审查第 41 项合成四个：买卖两侧分开藏
  // 没有实际用处（看的是「这一侧有没有人撤」，不是「只看撤掉的卖单」），六个开关只是多占一屏。

  public init(spot: Bool = true, contract: Bool = true, filled: Bool = true, cancelled: Bool = true) {
    self.spot = spot; self.contract = contract; self.filled = filled; self.cancelled = cancelled
  }

  public static let all = OrderFlowDisplay()

  /// 这一单画不画。还挂着的、失联结束的只看产品开关。
  public func shows(_ order: BigOrder) -> Bool {
    guard order.product.isContract ? contract : spot else { return false }
    switch order.status {
    case .live, .lost: return true  // 失联结束的不归成交 / 撤销开关管
    case .filled: return filled
    case .cancelled: return cancelled
    }
  }
}

/// 默认表与判定常数。
public enum OrderFlowDefaults {
  /// 有固定表的币：（现货，永续，步长）。币本位永续、交割取永续那个数。
  static let majors: [String: (spot: Double, perpetual: Double, step: Double)] = [
    "BTC": (1_000_000, 5_000_000, 100),
    "ETH": (1_000_000, 5_000_000, 1),
    "SOL": (750_000, 2_500_000, 0.1),
  ]

  /// 非币（美股、ETF、金银、大宗、指数、盘前……）的兜底门槛 200 万：只在标定不出来（一本簿都没拿到首张快照）
  /// 时用。正常情况下非币的默认门槛按簿深标定，见 `calibratedThreshold(depth:)`。
  public static let tradfiPerpetual = 2_000_000.0
  /// 非币默认门槛的标定（2026-09-25）：固定 200 万对 SNDK 这类盘口只有两千来万深的票永远出不了一单。
  /// D = 各本簿首张快照里中间价 ±1% 以内买卖两侧的美元名义之和，门槛 = round125(0.03 × D)，夹在 [5 万, 200 万]。
  /// 服务端（kanpan-api）用同一条公式，`thresholds` 里回的是同一个数。
  public static let calibrationBandBps = 100.0
  public static let calibrationFraction = 0.03
  public static let calibrationFloor = 50_000.0
  public static let calibrationCeiling = 2_000_000.0
  /// 订阅起来后最多等这么久：所有簿都拿到首张快照就立刻标定；到点时有一本就按已有的算，一本都没有用兜底。
  public static let calibrationTimeoutMs: Int64 = 8_000
  /// 非币里有表的步长；没表的按前一日收盘推。
  public static let tradfiSteps: [String: Double] = [
    "MU": 1, "SNDK": 1, "SPCX": 1, "SKHYNIX": 1, "SKHY": 0.1, "XAU": 1, "XAG": 0.1,
  ]

  /// 表里没有的币：（币安 U 本位永续 24h 成交额下限，永续门槛，现货门槛），从高到低。
  public static let coinTiers: [(turnover: Double, perpetual: Double, spot: Double)] = [
    (10_000_000_000, 5_000_000, 1_000_000),
    (2_000_000_000, 2_500_000, 750_000),
    (500_000_000, 1_000_000, 300_000),
    (100_000_000, 500_000, 150_000),
    (20_000_000, 200_000, 60_000),
    (0, 100_000, 30_000),
  ]
  /// 成交额不知道时用第三档（5 亿–20 亿）。
  public static let unknownTurnoverTier = 2

  /// 出现、消失都要连续这么多次评估……
  public static let confirmationSamples = 2
  /// ……且首尾相隔至少这么久。
  public static let confirmationMs: Int64 = 300
  /// 出现要 ≥ 门槛；出现之后跌到门槛 × 这个比例以下才算结束（退出滞回）。
  ///
  /// 实测 BTC 默认门槛下，现价附近总有一批档位在门槛上下来回抖（一拍 1.02M、下一拍 0.97M），
  /// 不加滞回就每分钟出几十条只活几秒的「已撤销」，把图刷成碎屑、也把留存额度冲光。
  /// 一张 5M 的墙缩到 4M 在交易员眼里仍是同一张墙；缩掉一半以上才是「被撤了 / 被吃了」。
  public static let exitRatio = 0.5
  /// 结束时，累计成交 ≥ 消失掉的那部分名义（跌破退出线前最后一拍的名义 − 结束时剩下的）× 这个比例算「已成交」，
  /// 否则「已撤销」。
  ///
  /// 取 0.8 而不是 1：簿上的量是 100 ms 一拍的快照，成交是逐笔，两路之间总有对不齐的零头；
  /// 被吃掉大半、剩下一点被顺手撤掉，交易员眼里仍然是「这单被打穿了」。低于八成就是主动撤单为主。
  /// 比的是消失的部分而不是首次名义：有了退出滞回，结束时桶里可能还剩门槛的一半没走，那一半既没成交也没撤。
  public static let filledRatio = 0.8
  /// 已结束的大单在内存里保留多久、最多几条。还挂着的永远不删——挂着的墙就是这个功能要看的东西。
  ///
  /// 服务端（kanpan-api `orderflow_history`）常驻跟踪、存 3 天，手机打开时取回来并进模型，
  /// 往左拖还能往前补（见 `OrderFlowModel.mergeHistory`）；所以内存里要装得下 3 天。
  /// 2026-09-25 从 30 天收到 3 天：更早的墙对盯盘没有用，一个月的碎单只会把图刷成底噪、把条数额度冲光。
  /// 条数封顶 2 万：线上实测 BTC 默认门槛一天约三万多条结束的单（一半活不过 1 分钟），3 天也装不下全部，
  /// 超了按「活得短的先走」挤（`recentKeepMs` 以内结束的、落在可视区间里的优先留），
  /// 拉远看几天时留下的正是活得久、看得见的那些墙。
  public static let retentionMs: Int64 = 3 * 86_400_000
  public static let maxEndedOrders = 20_000
  /// 这么久以内结束的，不因为超额被挤掉（刚发生的细节最要紧，1 分钟图上一屏就是这么长）。
  public static let recentKeepMs: Int64 = 2 * 3_600_000
  /// 超额时一次删到上限的这个比例，免得每一拍都排一次序。
  public static let trimRatio = 0.9
  /// 本机日志只存最近 24 小时、最多这么多条：更早的每次向服务端取，不落盘。
  /// 5000 条短键 JSON 约 1 MB（单测钉着上限）；超了按留存同一个次序挑（挂着的全留）。
  public static let journalRetentionMs: Int64 = 86_400_000
  public static let journalMaxOrders = 5_000
  /// 只看每本簿中间价两侧这么远以内的价位（10%）。更远的挂单离现价太远，不是「主力」要看的东西，
  /// 也免得几张远处的死单占着留存额度。
  public static let scanRadiusBps = 1_000.0

  /// 成交额 → 档位（0 起）。
  public static func tier(turnover24h: Double?) -> Int {
    guard let t = turnover24h, t.isFinite, t >= 0 else { return unknownTurnoverTier }
    return coinTiers.firstIndex { t >= $0.turnover } ?? coinTiers.count - 1
  }

  /// 这只品种的默认门槛要不要按簿深标定：非币、且不在固定表里。
  public static func needsCalibration(base: String, asset: SymbolClassification.Asset) -> Bool {
    asset != .crypto && majors[base.uppercased()] == nil
  }

  /// 就近取 1 / 2 / 5 × 10ⁿ（按线性距离；两边一样近取小的）。非正数、非有限数原样返回。
  public static func round125(_ x: Double) -> Double {
    guard x.isFinite, x > 0 else { return x }
    let exponent = floor(log10(x))
    var candidates: [Double] = []
    for e in [exponent - 1, exponent, exponent + 1] {
      let p = pow(10, e)
      candidates += [p, 2 * p, 5 * p]
    }
    var best = candidates[0]
    var bestDistance = abs(x - best)
    for c in candidates.dropFirst() {
      let d = abs(x - c)
      // 候选从小到大排，严格小于才换：一样近时留住小的那个。相对容差吸收 pow/log 的浮点零头。
      if d < bestDistance - 1e-9 * max(1, c) { best = c; bestDistance = d }
    }
    return best
  }

  /// 簿深 D（中间价 ±1% 以内两侧美元名义之和）→ 标定门槛。D 不可用时给兜底 200 万。
  public static func calibratedThreshold(depth: Double) -> Double {
    guard depth.isFinite else { return tradfiPerpetual }
    guard depth > 0 else { return calibrationFloor }
    let raw = round125(calibrationFraction * depth)
    return min(calibrationCeiling, max(calibrationFloor, raw))
  }

  /// 一只 base 的默认门槛与步长（步长可能是 nil，等前一日收盘）。
  /// `turnover24h` 是币安 U 本位永续的 24h 成交额（美元），不知道给 nil。
  /// `calibrated` 是按簿深标定出的非币门槛（`calibratedThreshold(depth:)`）；还没标定或标定不出给 nil，用兜底 200 万。
  /// 只对 `needsCalibration` 的品种起作用，币一律忽略它。
  public static func thresholds(base: String, asset: SymbolClassification.Asset,
                                turnover24h: Double?, calibrated: Double? = nil) -> OrderFlowThresholds {
    let base = base.uppercased()
    guard asset == .crypto || majors[base] != nil else {
      let threshold = calibrated.flatMap { $0.isFinite && $0 > 0 ? $0 : nil } ?? tradfiPerpetual
      return OrderFlowThresholds(usdtPerp: threshold, step: tradfiSteps[base])
    }
    if let m = majors[base] {
      return OrderFlowThresholds(spot: m.spot, usdtPerp: m.perpetual, coinPerp: m.perpetual,
                                 delivery: m.perpetual, step: m.step)
    }
    let t = coinTiers[tier(turnover24h: turnover24h)]
    return OrderFlowThresholds(spot: t.spot, usdtPerp: t.perpetual, coinPerp: t.perpetual, delivery: t.perpetual)
  }
}
