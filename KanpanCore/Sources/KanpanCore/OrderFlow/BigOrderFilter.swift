import Foundation

// 主力订单流 · 大单门槛。
//
// 移植 send-tradfi `crates/bit-orderbook-signal-policy/src/candidate.rs` 的 evaluate_bucket（:91）、
// median（:226）、within_bps（:210），顺序与判据一致：
//   1. 名义 < 绝对下限或 ≤ 0 → 拒；
//   2. 邻居 = 同侧、不是自己、中点距参考价 ≤ 150 bps 的桶；少于 4 个 → 拒；
//   3. 局部基准 = 邻居名义的下中位数；≤ 0 → 拒；名义 / 基准 < 5 → 拒；
//   4. 深度占比 = 名义 / 同侧中点距参考价 ≤ 100 bps 各桶名义之和；< 0.20 → 拒。
// 不搬：单交易所 8× 那一支（看盘一本簿只来自一家）、≥ 0.97 百分位那一条、质量分与生命周期。
// 看盘加的只有显示滞回：已在图上的桶维持门槛放宽到 3.5×，防门槛边缘闪；这是显示层抖动控制，不是判定。

public struct BucketNotional: Sendable, Equatable {
  public var side: BookSide
  public var index: Int64
  public var low: Double
  public var width: Double
  public var notional: Double
  public init(side: BookSide, index: Int64, low: Double, width: Double, notional: Double) {
    self.side = side; self.index = index; self.low = low; self.width = width; self.notional = notional
  }
  public var midpoint: Double { low + width / 2 }
}

public enum BigOrderRejection: Sendable, Equatable {
  case noFloor, belowFloor, insufficientNeighbourhood, belowLocalMultiple, belowDepthShare
}

public struct BigOrderEvidence: Sendable, Equatable {
  public var localMedian: Double
  public var localMultiple: Double
  public var depthShare: Double
  public var floor: Double
  public var neighbours: Int
}

public enum BigOrderVerdict: Sendable, Equatable {
  case admitted(BigOrderEvidence)
  case rejected(BigOrderRejection)
  public var isAdmitted: Bool { if case .admitted = self { true } else { false } }
}

public struct BigOrderFilter: Sendable {
  public static let localRadiusBps = 150.0
  public static let enterMultiple = 5.0
  public static let holdMultiple = 3.5
  public static let depthShareRadiusBps = 100.0
  public static let minimumDepthShare = 0.20
  public static let minimumNeighbours = 4
  /// 只评估参考价两侧 300 bps 以内的桶。
  public static let scanRadiusBps = 300.0

  struct Key: Hashable { var side: BookSide; var index: Int64 }
  struct Tracked: Equatable { var firstSeenMs: Int64; var initialNotional: Double; var filledNotional: Double }

  private(set) var tracked: [Key: Tracked] = [:]

  public init() {}

  // MARK: 单桶判定（纯函数，对拍原项目）

  public static func evaluate(_ bucket: BucketNotional, sameSide: [BucketNotional], reference: Double,
                              floor: Double?, requiredMultiple: Double = enterMultiple) -> BigOrderVerdict {
    guard let floor else { return .rejected(.noFloor) }
    let notional = bucket.notional
    if notional < floor || notional <= 0 { return .rejected(.belowFloor) }

    let neighbours = sameSide.filter {
      $0.side == bucket.side && $0.index != bucket.index && within(reference, $0.midpoint, localRadiusBps)
    }.map(\.notional)
    if neighbours.count < minimumNeighbours { return .rejected(.insufficientNeighbourhood) }
    let localMedian = median(neighbours)
    if localMedian <= 0 { return .rejected(.insufficientNeighbourhood) }
    let localMultiple = notional / localMedian
    if localMultiple < requiredMultiple { return .rejected(.belowLocalMultiple) }

    let depthTotal = sameSide.filter {
      $0.side == bucket.side && within(reference, $0.midpoint, depthShareRadiusBps)
    }.reduce(0) { $0 + $1.notional }
    let depthShare = depthTotal > 0 ? notional / depthTotal : 0
    if depthShare < minimumDepthShare { return .rejected(.belowDepthShare) }

    return .admitted(BigOrderEvidence(localMedian: localMedian, localMultiple: localMultiple,
                                      depthShare: depthShare, floor: floor, neighbours: neighbours.count))
  }

  /// 偶数个取两个中间值里较小的那个——取表里真有的样本，不取平均。
  static func median(_ values: [Double]) -> Double {
    guard !values.isEmpty else { return 0 }
    let sorted = values.sorted()
    return sorted[(sorted.count - 1) / 2]
  }

  static func within(_ reference: Double, _ price: Double, _ radiusBps: Double) -> Bool {
    guard reference > 0 else { return false }
    return abs(price - reference) / reference * 10_000 <= radiusBps
  }

  // MARK: 逐帧跟踪（滞回、首次出现、成交累计）

  /// 用这一帧的全部桶重算大单集合。没过门槛的立刻丢掉——撤了或吃完就消失，不淡出。
  public mutating func update(buckets: [BucketNotional], reference: Double,
                              bidFloor: Double?, askFloor: Double?, nowMs: Int64) -> [BigOrder] {
    var next: [Key: Tracked] = [:]
    var out: [BigOrder] = []
    for side in [BookSide.bid, .ask] {
      let same = buckets.filter { $0.side == side }
      let floor = side == .bid ? bidFloor : askFloor
      for bucket in same where Self.within(reference, bucket.midpoint, Self.scanRadiusBps) {
        let key = Key(side: side, index: bucket.index)
        let prior = tracked[key]
        let required = prior == nil ? Self.enterMultiple : Self.holdMultiple
        guard Self.evaluate(bucket, sameSide: same, reference: reference, floor: floor,
                            requiredMultiple: required).isAdmitted else { continue }
        let t = prior ?? Tracked(firstSeenMs: nowMs, initialNotional: bucket.notional, filledNotional: 0)
        next[key] = t
        out.append(BigOrder(side: side, bucketIndex: bucket.index, low: bucket.low, width: bucket.width,
                            notional: bucket.notional, initialNotional: t.initialNotional,
                            filledNotional: t.filledNotional, firstSeenMs: t.firstSeenMs))
      }
    }
    tracked = next
    return out.sorted { a, b in
      if a.side != b.side { return a.side == .bid }
      if a.notional != b.notional { return a.notional > b.notional }
      return a.bucketIndex < b.bucketIndex
    }
  }

  /// 吃到某条大单所在桶的主动成交，累计到它的「已成交」。不做撤单会计。
  public mutating func recordTrade(_ trade: OrderFlowTrade, scheme: BucketScheme) {
    guard trade.price.isFinite, trade.quantity.isFinite, trade.price > 0, trade.quantity > 0 else { return }
    let key = Key(side: trade.hitSide, index: scheme.index(of: trade.price))
    tracked[key]?.filledNotional += trade.price * trade.quantity
  }

  public mutating func reset() { tracked.removeAll() }
}
