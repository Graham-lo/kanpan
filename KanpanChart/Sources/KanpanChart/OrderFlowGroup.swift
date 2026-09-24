import Foundation
import KanpanCore

// 主力订单流 · 手机布局的「一段一条带」（2026-09-24 晚，用户：「都挤在一起，有没有适合手机的布局设计展示」）。
//
// BTC 默认门槛下十三本簿同时出单，一单一条带在手机的矮图区里右缘叠成一堵墙。所以画的时候按
// 「价位桶 × 买卖侧 × 类（现货 / 合约）× 时间段」合成一条：币安 U 本位、币本位、交割与 OKX 永续在同一桶同一侧、
// 时间上连着的单画成一条「合约」带，三家现货画成一条「现货」带。只是画法合并——`OrderFlowModel` 交出来的逐单不动，
// 图例「主力 买 X · 卖 Y」仍按逐单求和。
//
// **按时间切段**（2026-09-24 夜修）：起初同一「桶 × 侧 × 类」不分时间合成一条，同一价位 21:30 挂过 1 分钟、
// 23:00 又挂一单，就画成 21:30 连到右缘的一整条。真机 BTC 实测 191 条带画出来共 572 小时，真有单挂着的只有
// 213 小时；最坏的合约卖 834 桶 22 单实挂 10 分钟，画成近 5 小时——图上画了没发生过的墙。所以同一桶侧类里的单
// 按首见排好，逐单往前一段上并：和这一段的区间重叠、或者空档不超过容差（`mergeGapMs`）就并进去，否则另起一段。
// 容差 = max(60 秒, 一根 K 线的时长)：
//   - 60 秒兜底：撤了马上挂回来（簿抖、改价）仍算同一堵墙，不在 1 分钟图上碎成几截；
//   - 一根 K 线：空档不超过一根时，两单在图上落在同一根或相邻两根，画出来本来就是连着的，拆成两条只多一个缝、
//     多一枚签、多一次命中歧义；超过一根才会在图上真的空出一根以上——那才是看得见的「中间没有墙」。
//   - 只随周期变，不随缩放、平移变：段的身份（选中）跨缩放稳定；换周期时选中本来就会清掉。
//
// 一段里同一本簿可能先后有好几单（撤了又挂回来）。它们是同一堵墙的前后两截，名义不该累加：
//   - 每本簿取「最近的那一单」（首见最晚的）当它此刻的名义与状态；
//   - 合并带的名义 = 各本簿最近那一单的名义之和；粗细按各本簿最近那一单的「门槛四分之一格」之和算档；
//   - 深浅：段里任何一单有过成交就深；
//   - 起点取段里最早的首见，终点取段里最晚的结束，有一单还挂着就画到右缘；
//   - 成交金额按段里全部单求和（成交是真实发生过的，不会重复）。
// 以上都只在段内算，别的段的单不掺进来。
//
// **相邻桶并成一堵墙**（2026-09-25）：ETH / SOL 的步长小（1 / 0.1），一堵 3100 万的墙在簿上摊在 2682、2683、2684
// 三个桶里，画成三条细带、各写各的金额，一屏几百条 2 pt 带没有主次。所以切好段、去掉活不过一根 K 线的
// 已结束段之后，再把「同侧、同类、桶号相邻（差 1，可以连成串）、时间上重叠或空档 ≤ 切段容差」的段并成一堵墙。
// 墙必须成块：墙里所有段有一个共同在场的时刻、最多跨 `maxWallBuckets`（5）个桶——否则价格走几天，
// 相邻桶里前后接力的段会链成一整片（首版真机 BTC 一堵墙 34 个桶、高 1396 pt）。
//   - 价位范围 = 最低桶的桶价 … 最高桶的桶价 + 步长；名义 = 各段画法名义之和；粗细档按合计算；
//   - 标签写合计；详情卡标题写价位范围，一本簿一行，同一本簿跨几个桶就每桶一行、各带自己的价；
//   - 墙的键 = 墙里最早起的那一段的键（起点一样取桶小的）：挂着的墙续长、后来的段并进来都不变；
//     更早的段并进来（服务端回填）键会前移，按 `covers` 认回来（见那里）。
//   - 单桶的墙和原来的一段一条完全一样；BTC 步长 100，墙最多 500 美元宽，看起来和原来差不多。

/// 一条合并带（一堵墙）的身份：墙里最早起的那一段是哪一桶、哪一侧、哪一类、从哪一刻起。
///
/// `start` = 那一段里最早的首见。挂着的单续长、新单并到段尾、后起的段并进墙，键都不变，所以选中的那堵不会跳走；
/// 只有更早的单或段并进来（服务端历史回填把两段接上）键才会变——那时按 `OrderFlowGroup.covers` 认回来。
public struct OrderFlowGroupKey: Sendable, Hashable {
  public var bucket: Int64
  public var side: BookSide
  /// true = 合约（U 本位永续、币本位永续、交割），false = 现货。
  public var contract: Bool
  /// 这一段的起点：段里最早的首见（ms）。
  public var start: Int64

  public init(bucket: Int64, side: BookSide, contract: Bool, start: Int64) {
    self.bucket = bucket; self.side = side; self.contract = contract; self.start = start
  }

  /// 以这一单为起点的那一段（这一单是段里最早的那一单时，就是它所在那条带的键）。
  public init(_ order: BigOrder) {
    self.init(bucket: order.bucket, side: order.side, contract: order.product.isContract, start: order.firstSeenMs)
  }

  /// 同一桶、同一侧、同一类（不管哪一段）。
  public func sameLane(_ other: OrderFlowGroupKey) -> Bool {
    bucket == other.bucket && side == other.side && contract == other.contract
  }

  /// 同一侧、同一类（不管哪一桶、哪一段）：能并成同一堵墙的前提。
  public func sameKind(_ other: OrderFlowGroupKey) -> Bool {
    side == other.side && contract == other.contract
  }

  /// 诊断与 UI 用例用的字符串：「contract|ask|836|1790000000000」（最后一段是起点 ms）。
  public var id: String {
    (contract ? "contract" : "spot") + "|" + side.rawValue + "|" + String(bucket) + "|" + String(start)
  }
}

/// 一条合并带（一堵墙）：同侧、同类、相邻桶、时间上连着的几段。单桶单段就是原来的「一段一条」。
public struct OrderFlowGroup: Sendable, Equatable {
  /// 一本簿在这堵墙的某一桶里的那一行（详情卡上一行一本；同一本簿跨几个桶就每桶一行）。
  public struct Book: Sendable, Equatable {
    public var venueID: String
    public var exchange: String
    public var product: OrderFlowProduct
    /// 哪一桶。
    public var bucket: Int64
    /// 这本簿在这一桶最近的那一单（首见最晚的）：此刻的名义、状态、价位以它为准。
    public var latest: BigOrder
    /// 这本簿在这一桶一共几单（撤了又挂回来算两单）。
    public var orders: Int
    /// 全部单的成交名义之和。
    public var filledNotional: Double
    /// 成交比例的分母之和（挂着的按此刻名义，结束的按消失掉的名义，和 `BigOrder.fillRatio` 同一口径）。
    public var fillBase: Double
    /// 任何一单被吃过。
    public var hasFill: Bool

    public var notional: Double { latest.notional }
    /// 这一行的价位（这本簿这一桶最近那一单的价）。
    public var price: Double { latest.price }
    public var fillRatio: Double { fillBase > 0 ? min(1, max(0, filledNotional / fillBase)) : 0 }
  }

  /// 墙里的一段占的那一格：哪一桶、从哪到哪（挂着的 `end` 是 nil）。选中认回来靠它。
  public struct Span: Sendable, Equatable, Hashable {
    public var bucket: Int64
    public var start: Int64
    public var end: Int64?

    public init(bucket: Int64, start: Int64, end: Int64?) {
      self.bucket = bucket; self.start = start; self.end = end
    }

    /// 这一格的时间跨度里有没有这一刻。
    public func contains(_ ms: Int64) -> Bool { start <= ms && ms <= (end ?? .max) }
  }

  public var key: OrderFlowGroupKey
  /// 按首见先后排的全部单。
  public var members: [BigOrder]
  /// 一本簿一桶一行，按此刻名义从大到小（名义一样按簿名、再按桶）。
  public var books: [Book]
  /// 墙里的各段（一桶可以有几段），按起点排。
  public var spans: [Span]
  /// 步长（`OrderFlowSnapshot.thresholds.step`）：算价位范围用；不知道时按各行的价。
  public var step: Double?

  /// 把几单合成一条带；空的给 nil。不检查它们是不是同侧同类、桶与时间连着，调用方按 `segments` / `walls` 分好组。
  /// `spans` 不给就按成员一桶一格（每桶最早首见到最晚结束）。
  public init?(key: OrderFlowGroupKey, members: [BigOrder], spans: [Span]? = nil, step: Double? = nil) {
    guard !members.isEmpty else { return nil }
    self.key = key
    self.step = step.flatMap { $0.isFinite && $0 > 0 ? $0 : nil }
    self.members = members.sorted { $0.firstSeenMs != $1.firstSeenMs ? $0.firstSeenMs < $1.firstSeenMs : $0.id < $1.id }
    struct RowKey: Hashable { var venue: String; var bucket: Int64 }
    var rows: [RowKey: Book] = [:]
    var perBucket: [Int64: Span] = [:]
    for o in self.members {
      let base = o.status == .live ? o.notional : (o.vanishedNotional ?? o.notional)
      let rk = RowKey(venue: o.venueID, bucket: o.bucket)
      if var b = rows[rk] {
        if o.firstSeenMs >= b.latest.firstSeenMs { b.latest = o }
        b.orders += 1
        b.filledNotional += o.filledNotional
        b.fillBase += base
        b.hasFill = b.hasFill || o.hasFill
        rows[rk] = b
      } else {
        rows[rk] = Book(venueID: o.venueID, exchange: o.exchange, product: o.product, bucket: o.bucket, latest: o,
                        orders: 1, filledNotional: o.filledNotional, fillBase: base, hasFill: o.hasFill)
      }
      if spans == nil {
        let end: Int64? = o.isLive ? nil : max(o.firstSeenMs, o.endMs ?? o.firstSeenMs)
        if var span = perBucket[o.bucket] {
          span.start = min(span.start, o.firstSeenMs)
          span.end = (span.end == nil || end == nil) ? nil : max(span.end!, end!)
          perBucket[o.bucket] = span
        } else {
          perBucket[o.bucket] = Span(bucket: o.bucket, start: o.firstSeenMs, end: end)
        }
      }
    }
    books = rows.values.sorted {
      if $0.notional != $1.notional { return $0.notional > $1.notional }
      if $0.venueID != $1.venueID { return $0.venueID < $1.venueID }
      return $0.bucket < $1.bucket
    }
    self.spans = (spans ?? Array(perBucket.values)).sorted {
      $0.start != $1.start ? $0.start < $1.start : $0.bucket < $1.bucket
    }
  }

  /// 两段之间的空档不超过这么久就并成一段的下限：撤了马上挂回来仍算同一堵墙。
  public static let minMergeGapMs: Int64 = 60_000

  /// 切段容差：max(60 秒, 一根 K 线的时长)。理由见文件头。并墙的时间容差用同一个数。
  public static func mergeGapMs(barMs: Int64) -> Int64 { max(minMergeGapMs, barMs) }

  /// 一段：键、按首见排好的成员、段的结束（有一单还挂着就是 nil）。只切段、不建 `OrderFlowGroup`（便宜），
  /// 图表先按墙的时间跨度筛掉这一屏外面的，再对剩下的建组。
  public struct Segment: Sendable, Equatable {
    public var key: OrderFlowGroupKey
    public var members: [BigOrder]
    public var endMs: Int64?

    public var span: Span { Span(bucket: key.bucket, start: key.start, end: endMs) }
  }

  /// 一堵墙：并在一起的几段（还没建 `OrderFlowGroup`）。
  public struct Wall: Sendable, Equatable {
    public var key: OrderFlowGroupKey
    public var segments: [Segment]
    /// 最早的起点。
    public var startMs: Int64
    /// 最晚的结束；有一段还挂着就是 nil。
    public var endMs: Int64?

    public var members: [BigOrder] { segments.flatMap(\.members) }
    public var spans: [Span] { segments.map(\.span) }

    /// 建成画得出来的一条带。
    public func group(step: Double?) -> OrderFlowGroup? {
      OrderFlowGroup(key: key, members: members, spans: spans, step: step)
    }
  }

  private struct Lane: Hashable {
    var bucket: Int64
    var side: BookSide
    var contract: Bool
  }

  /// 按「桶 × 侧 × 类 × 时间段」切段。同一桶侧类里的单按首见排好，逐单往当前段上并：它的首见不晚于
  /// 「段里最晚的结束 + gapMs」（区间重叠或空档不超过容差）就并进去，否则另起一段。挂着的单结束算无穷远，
  /// 之后的单都并进来。同首见的单谁先谁后不影响结果。顺序：桶侧类的字典序无意义，调用方自己排。
  public static func segments(_ orders: [BigOrder], gapMs: Int64) -> [Segment] {
    var lanes: [Lane: [BigOrder]] = [:]
    for o in orders {
      lanes[Lane(bucket: o.bucket, side: o.side, contract: o.product.isContract), default: []].append(o)
    }
    var out: [Segment] = []
    out.reserveCapacity(lanes.count)
    for (lane, list) in lanes {
      let sorted = list.sorted { $0.firstSeenMs < $1.firstSeenMs }
      var members: [BigOrder] = []
      var runEnd = Int64.min
      func flush() {
        guard let first = members.first else { return }
        let key = OrderFlowGroupKey(bucket: lane.bucket, side: lane.side, contract: lane.contract, start: first.firstSeenMs)
        out.append(Segment(key: key, members: members, endMs: runEnd == .max ? nil : runEnd))
      }
      for o in sorted {
        let end = o.isLive ? Int64.max : max(o.firstSeenMs, o.endMs ?? o.firstSeenMs)
        if !members.isEmpty, runEnd == .max || o.firstSeenMs - runEnd <= gapMs {
          members.append(o)
          runEnd = max(runEnd, end)
        } else {
          flush()
          members = [o]
          runEnd = end
        }
      }
      flush()
    }
    return out
  }

  /// 去掉活不过一根 K 线的已结束段：（结束 − 首见）< `minLifeMs`。挂着的一律留。
  /// 这类段在图上最多占一根 K 线宽，一屏几百条只是碎屑；图例（逐单还挂着的合计）不受影响。
  public static func dropShortLived(_ segments: [Segment], minLifeMs: Int64) -> [Segment] {
    guard minLifeMs > 0 else { return segments }
    return segments.filter { s in s.endMs.map { $0 - s.key.start >= minLifeMs } ?? true }
  }

  /// 一堵墙最多跨几个桶。BTC 默认步长 100 时是 500 美元，ETH（步长 1）是 5 美元。
  public static let maxWallBuckets = 5

  /// 把段并成墙：同侧、同类、桶号相邻、时间上重叠或空档 ≤ `gapMs` 的段并在一起，但墙要**成块**：
  ///   - **有一个共同的时刻**：墙里每一段（结束 + `gapMs` 之前）都还在的那一刻得存在——
  ///     最晚的起点 ≤ 最早的「结束 + 容差」（挂着的算无穷远）。不然价格走了三天，一路上相邻桶里前后接力的段会
  ///     链成一整片（真机 BTC 首版：34 个桶、1600 段并成一堵、高 1396 pt）；
  ///   - **最多 `maxWallBuckets` 个桶**。
  /// 做法：按（起点，桶）升序逐段看，能挂到相邻桶（±1）所在的、还「开着」（最早的结束 + 容差 ≥ 这段起点）的墙上
  /// 就挂上去（两边都能挂取键早的那堵），否则另起一堵。不做两堵之间的桥接。同一桶的段在时间上相隔 > 容差，
  /// 所以一堵墙每个桶最多一段。结果只取决于段的集合（排序全序），与输入顺序无关；墙的顺序无意义，调用方自己排。
  public static func walls(_ segments: [Segment], gapMs: Int64) -> [Wall] {
    guard !segments.isEmpty else { return [] }
    let order = segments.indices.sorted {
      let a = segments[$0].key, b = segments[$1].key
      if a.start != b.start { return a.start < b.start }
      if a.bucket != b.bucket { return a.bucket < b.bucket }
      if a.side != b.side { return a.side == .bid }
      return !a.contract && b.contract
    }
    let reach = { (i: Int) -> Int64 in
      guard let end = segments[i].endMs else { return .max }
      return end > Int64.max - gapMs ? .max : end + gapMs
    }
    struct Building { var parts: [Int]; var low: Int64; var high: Int64; var minReach: Int64 }
    var building: [Building] = []
    // 每条道（桶 × 侧 × 类）最后挂到的那堵墙。
    var laneWall: [Lane: Int] = [:]
    for i in order {
      let s = segments[i]
      let b = s.key.bucket
      var best: Int?
      for nb in [b - 1, b + 1] {
        guard let w = laneWall[Lane(bucket: nb, side: s.key.side, contract: s.key.contract)] else { continue }
        let wall = building[w]
        guard wall.minReach >= s.key.start,
              max(wall.high, b) - min(wall.low, b) + 1 <= Int64(maxWallBuckets),
              laneWall[Lane(bucket: b, side: s.key.side, contract: s.key.contract)] != w
        else { continue }
        if let cur = best {
          let ck = segments[building[cur].parts[0]].key, wk = segments[wall.parts[0]].key
          if (wk.start, wk.bucket) < (ck.start, ck.bucket) { best = w }
        } else {
          best = w
        }
      }
      let lane = Lane(bucket: b, side: s.key.side, contract: s.key.contract)
      if let w = best {
        building[w].parts.append(i)
        building[w].low = min(building[w].low, b)
        building[w].high = max(building[w].high, b)
        building[w].minReach = min(building[w].minReach, reach(i))
        laneWall[lane] = w
      } else {
        building.append(Building(parts: [i], low: b, high: b, minReach: reach(i)))
        laneWall[lane] = building.count - 1
      }
    }
    return building.map { w in
      let parts = w.parts.map { segments[$0] }
      let end: Int64? = parts.contains { $0.endMs == nil } ? nil : parts.compactMap(\.endMs).max()
      return Wall(key: parts[0].key, segments: parts, startMs: parts[0].key.start, endMs: end)
    }
  }

  /// 画的先后（也是这一屏排主次的次序）：画法上的名义（`drawNotional`）从大到小，一样的先起的在前，
  /// 再按 `key.id`（结果稳定）。
  public static func drawOrder(_ a: OrderFlowGroup, _ b: OrderFlowGroup) -> Bool {
    if a.drawNotional != b.drawNotional { return a.drawNotional > b.drawNotional }
    if a.firstSeenMs != b.firstSeenMs { return a.firstSeenMs < b.firstSeenMs }
    return a.key.id < b.key.id
  }

  /// 把一批单切段、去掉活不过 `minLifeMs` 的已结束段、并墙，按 `drawOrder` 排好。
  /// `gapMs` 缺省只用 60 秒下限；图表按周期传 `mergeGapMs(barMs:)`，`minLifeMs` 传一根 K 线。
  public static func groups(_ orders: [BigOrder], gapMs: Int64 = minMergeGapMs, minLifeMs: Int64 = 0,
                            step: Double? = nil) -> [OrderFlowGroup] {
    let parts = dropShortLived(segments(orders, gapMs: gapMs), minLifeMs: minLifeMs)
    return walls(parts, gapMs: gapMs).compactMap { $0.group(step: step) }.sorted(by: drawOrder)
  }

  /// 选中存的那个键还认不认这堵墙：键一样；或者同侧同类、墙里有一段在键的那一桶、键的起点落在那一段的时间跨度里
  /// （那一段的起点前移了、两段被回填的历史接成了一段、或者更早的段并进来键换了）。同一桶里的段在时间上不相交，
  /// 一段只属于一堵墙，所以最多认一堵。
  public func covers(_ other: OrderFlowGroupKey) -> Bool {
    if other == key { return true }
    guard key.sameKind(other) else { return false }
    return spans.contains { $0.bucket == other.bucket && $0.contains(other.start) }
  }

  /// 宽松地认：键那一段已经不在了（活不过一根 K 线被去掉），但键的桶在墙的桶范围里、起点在墙的时间跨度里。
  /// 只在 `covers` 谁都不认时兜底用。
  public func looselyCovers(_ other: OrderFlowGroupKey) -> Bool {
    guard key.sameKind(other), other.bucket >= bucketLow, other.bucket <= bucketHigh else { return false }
    return firstSeenMs <= other.start && other.start <= (endMs ?? .max)
  }

  public var side: BookSide { key.side }
  public var contract: Bool { key.contract }

  /// 最低、最高的桶。
  public var bucketLow: Int64 { spans.map(\.bucket).min() ?? key.bucket }
  public var bucketHigh: Int64 { spans.map(\.bucket).max() ?? key.bucket }
  /// 并了几个桶。
  public var bucketCount: Int { Set(spans.map(\.bucket)).count }
  /// 跨了不止一个桶（详情卡标题写价位范围、每行带价）。
  public var isRange: Bool { bucketCount > 1 }
  /// 价位范围：最低桶的桶价 … 最高桶的桶价 + 步长。不知道步长时按各行的价。
  public var priceLow: Double {
    if let step { return Double(bucketLow) * step }
    return books.map(\.price).min() ?? price
  }
  public var priceHigh: Double {
    if let step { return Double(bucketHigh + 1) * step }
    return books.map(\.price).max() ?? price
  }

  /// 此刻的名义：各行（一本簿一桶）最近那一单的名义之和（图上标签、详情卡的合计）。
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

  /// 画粗细用的「门槛四分之一格」之和：各行最近那一单的 `thicknessQuarters` 相加。
  /// 只由逐单的 `renderKey` 决定——名义在一格里抖，粗细和挤压都不变，底图不用重画。
  public var quarters: Int { books.reduce(0) { $0 + $1.latest.thicknessQuarters } }
  /// 粗细档（0…4）。
  public var tier: Int { BigOrder.thicknessTier(quarters: quarters) }
  /// 排先后（主次、谁被压成细线、谁留标签）用的名义：按四分之一格折回美元，同样只由 `renderKey` 决定。
  public var drawNotional: Double { books.reduce(0) { $0 + Double($1.latest.thicknessQuarters) * $1.latest.threshold / 4 } }

  /// 代表价（次墙、底噪的细线画在这里；被压成细线的也画在这里）：四分之一格最多的那一行最近那一单的价
  /// （一样多取 id 小的，结果稳定）。
  public var price: Double {
    books.map(\.latest).max { a, b in
      a.thicknessQuarters != b.thicknessQuarters ? a.thicknessQuarters < b.thicknessQuarters : a.id > b.id
    }?.price ?? 0
  }
}

/// 详情卡的尺寸上限与摆位（app 那边按这个排，放在图表包里好单测）。卡只有三行，不再按高度算列几本簿。
public enum OrderFlowCardBudget {
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
}
