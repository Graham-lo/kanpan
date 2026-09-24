import Foundation
import KanpanCore

// 主力订单流 · 手机布局的「一桶一条带」（2026-09-24 晚，用户：「都挤在一起，有没有适合手机的布局设计展示」）。
//
// BTC 默认门槛下十三本簿同时出单，一单一条带在手机的矮图区里右缘叠成一堵墙。所以画的时候按
// 「价位桶 × 买卖侧 × 类（现货 / 合约）」合成一条：币安 U 本位、币本位、交割与 OKX 永续在同一桶同一侧的
// 单画成一条「合约」带，三家现货画成一条「现货」带。只是画法合并——`OrderFlowModel` 交出来的逐单不动，
// 图例「主力 买 X · 卖 Y」仍按逐单求和。
//
// 一条带里同一本簿可能先后有好几单（撤了又挂回来）。它们是同一堵墙的前后两段，名义不该累加：
//   - 每本簿取「最近的那一单」（首见最晚的）当它此刻的名义与状态；
//   - 合并带的名义 = 各本簿最近那一单的名义之和；粗细按各本簿最近那一单的「门槛四分之一格」之和算档；
//   - 深浅：任何一单（含早先那几段）有过成交就深；
//   - 起点取最早的首见，终点取最晚的结束，有一单还挂着就画到右缘；
//   - 成交金额按全部单求和（成交是真实发生过的，不会重复）。

/// 一条合并带是哪一桶、哪一侧、哪一类。
public struct OrderFlowGroupKey: Sendable, Hashable {
  public var bucket: Int64
  public var side: BookSide
  /// true = 合约（U 本位永续、币本位永续、交割），false = 现货。
  public var contract: Bool

  public init(bucket: Int64, side: BookSide, contract: Bool) {
    self.bucket = bucket; self.side = side; self.contract = contract
  }

  public init(_ order: BigOrder) {
    self.init(bucket: order.bucket, side: order.side, contract: order.product.isContract)
  }

  /// 诊断与 UI 用例用的字符串：「contract|ask|836」。
  public var id: String { (contract ? "contract" : "spot") + "|" + side.rawValue + "|" + String(bucket) }
}

/// 一条合并带：同一桶、同一侧、同一类的几单。
public struct OrderFlowGroup: Sendable, Equatable {
  /// 一本簿在这条带里的那一行（详情卡上一行一本）。
  public struct Book: Sendable, Equatable {
    public var venueID: String
    public var exchange: String
    public var product: OrderFlowProduct
    /// 这本簿最近的那一单（首见最晚的）：此刻的名义、状态以它为准。
    public var latest: BigOrder
    /// 这本簿在这条带里一共几单（撤了又挂回来算两单）。
    public var orders: Int
    /// 全部单的成交名义之和。
    public var filledNotional: Double
    /// 成交比例的分母之和（挂着的按此刻名义，结束的按消失掉的名义，和 `BigOrder.fillRatio` 同一口径）。
    public var fillBase: Double
    /// 任何一单被吃过。
    public var hasFill: Bool

    public var notional: Double { latest.notional }
    public var fillRatio: Double { fillBase > 0 ? min(1, max(0, filledNotional / fillBase)) : 0 }
  }

  public var key: OrderFlowGroupKey
  /// 按首见先后排的全部单。
  public var members: [BigOrder]
  /// 一本簿一行，按此刻名义从大到小（名义一样按簿名）。
  public var books: [Book]

  /// 把几单合成一条带；空的给 nil。不检查它们是不是同一桶同一侧同一类，调用方按 `key` 分好组。
  public init?(key: OrderFlowGroupKey, members: [BigOrder]) {
    guard !members.isEmpty else { return nil }
    self.key = key
    self.members = members.sorted { $0.firstSeenMs != $1.firstSeenMs ? $0.firstSeenMs < $1.firstSeenMs : $0.id < $1.id }
    var byVenue: [String: Book] = [:]
    for o in self.members {
      let base = o.status == .live ? o.notional : (o.vanishedNotional ?? o.notional)
      if var b = byVenue[o.venueID] {
        if o.firstSeenMs >= b.latest.firstSeenMs { b.latest = o }
        b.orders += 1
        b.filledNotional += o.filledNotional
        b.fillBase += base
        b.hasFill = b.hasFill || o.hasFill
        byVenue[o.venueID] = b
      } else {
        byVenue[o.venueID] = Book(venueID: o.venueID, exchange: o.exchange, product: o.product, latest: o, orders: 1,
                                  filledNotional: o.filledNotional, fillBase: base, hasFill: o.hasFill)
      }
    }
    books = byVenue.values.sorted { $0.notional != $1.notional ? $0.notional > $1.notional : $0.venueID < $1.venueID }
  }

  /// 按「桶 × 侧 × 类」把一批单分组。顺序：画法上的名义（`drawNotional`）从大到小，一样按 `key.id`。
  public static func groups(_ orders: [BigOrder]) -> [OrderFlowGroup] {
    var buckets: [OrderFlowGroupKey: [BigOrder]] = [:]
    for o in orders { buckets[OrderFlowGroupKey(o), default: []].append(o) }
    return buckets.compactMap { OrderFlowGroup(key: $0.key, members: $0.value) }
      .sorted { $0.drawNotional != $1.drawNotional ? $0.drawNotional > $1.drawNotional : $0.key.id < $1.key.id }
  }

  public var side: BookSide { key.side }
  public var contract: Bool { key.contract }

  /// 此刻的名义：各本簿最近那一单的名义之和（图上标签、详情卡的合计）。
  public var notional: Double { books.reduce(0) { $0 + $1.notional } }
  /// 全部单的成交名义之和。
  public var filledNotional: Double { books.reduce(0) { $0 + $1.filledNotional } }
  /// 成交比例：成交之和 ÷ 各单分母之和（封顶 1）。
  public var fillRatio: Double {
    let base = books.reduce(0) { $0 + $1.fillBase }
    return base > 0 ? min(1, max(0, filledNotional / base)) : 0
  }
  /// 任何一单被吃过就画深色。
  public var hasFill: Bool { books.contains { $0.hasFill } }
  /// 有一单还挂着。
  public var isLive: Bool { members.contains(where: \.isLive) }
  /// 最早的首见。
  public var firstSeenMs: Int64 { members.map(\.firstSeenMs).min() ?? 0 }
  /// 最晚的结束；有一单还挂着就是 nil（画到右缘）。
  public var endMs: Int64? {
    if members.contains(where: \.isLive) { return nil }
    return members.compactMap(\.endMs).max()
  }

  /// 画粗细用的「门槛四分之一格」之和：各本簿最近那一单的 `thicknessQuarters` 相加。
  /// 只由逐单的 `renderKey` 决定——名义在一格里抖，粗细和挤压都不变，底图不用重画。
  public var quarters: Int { books.reduce(0) { $0 + $1.latest.thicknessQuarters } }
  /// 粗细档（0…4）。
  public var tier: Int { BigOrder.thicknessTier(quarters: quarters) }
  /// 排先后（谁先落、谁被压成细线、谁留标签）用的名义：按四分之一格折回美元，同样只由 `renderKey` 决定。
  public var drawNotional: Double { books.reduce(0) { $0 + Double($1.latest.thicknessQuarters) * $1.latest.threshold / 4 } }

  /// 画在哪口价上：四分之一格最多的那本簿最近那一单的价（一样多取 id 小的，结果稳定）。
  public var price: Double {
    books.map(\.latest).max { a, b in
      a.thicknessQuarters != b.thicknessQuarters ? a.thicknessQuarters < b.thicknessQuarters : a.id > b.id
    }?.price ?? 0
  }
}

/// 详情卡的尺寸上限与行数（app 那边按这个排，放在图表包里好单测）。
public enum OrderFlowCardBudget {
  /// 最多列几本簿，再多折成「还有 N 本」。
  public static let maxRows = 6
  /// 卡宽不超过图区（绘图区宽）的这个比例。
  public static let widthFraction = 0.85
  /// 卡高不超过主图的这个比例。
  public static let heightFraction = 0.55
  /// 卡与焦点带之间留的空。
  public static let bandGap = 6.0

  /// 卡能占的最大宽度。
  public static func maxWidth(plotW: Double) -> Double { max(0, plotW * widthFraction) }

  /// 卡摆在焦点带的上面还是下面、最多能多高：主图 55% 封顶，并且不越过焦点带（带上、带下取宽的一边）。
  public static func placement(bandY: Double, bandHalf: Double, top: Double, bottom: Double,
                               mainHeight: Double) -> (below: Bool, maxHeight: Double) {
    let above = bandY - bandHalf - bandGap - top
    let below = bottom - (bandY + bandHalf + bandGap)
    let room = max(above, below)
    return (below >= above, max(0, min(mainHeight * heightFraction, room)))
  }

  /// 高度放得下几行、折几本。`lines` = 这么高能排下的簿行数（含折叠那一行）。
  /// 簿不多于 `min(6, lines)` 全列；否则列 `min(6, lines − 1)` 行，其余折成一行「还有 N 本」。
  public static func rows(books: Int, lines: Int) -> (shown: Int, folded: Int) {
    let books = max(0, books), lines = max(0, lines)
    if books <= min(maxRows, lines) { return (books, 0) }
    let shown = max(0, min(maxRows, lines - 1))
    return (shown, books - shown)
  }

  /// 按像素高度算能排几行：`(可用高 − 固定部分) ÷ 行高`，向下取整。
  public static func lines(maxHeight: Double, fixedHeight: Double, rowHeight: Double) -> Int {
    guard rowHeight > 0, maxHeight > fixedHeight else { return 0 }
    return Int(((maxHeight - fixedHeight) / rowHeight).rounded(.down))
  }
}
