import Foundation

// 主力订单流 · 画法要用的只读派生量（2026-09-24 改 CoinAnk 式粗横带）。
//
// 图表那一层只按两样东西画一单：粗细档（名义 ÷ 门槛，半个倍频一档，共七档）与深浅（有没有成交过）。
// `renderKey` 就是「画出来一样」的判据：名义在同一档里抖、成交比例在「有成交」里涨跌都不算变化，
// 底图不因此重画。`pixelKey`（行情流用来决定要不要发帧）比它细，这里不动它。
extension BigOrder {
  /// 粗细档数：0…6。
  public static let thicknessTiers = 7

  /// 粗细档：r = 名义 ÷ 门槛，档 = ⌊2·log₂ r⌋ 夹到 0…6——刚过门槛（r < √2）0 档，
  /// 每大 √2 倍升一档，门槛 8 倍及以上封顶 6 档。撤单滞回留下的 0.5–1 倍也落 0 档。
  public var thicknessTier: Int { Self.thicknessTier(notional: notional, threshold: threshold) }

  public static func thicknessTier(notional: Double, threshold: Double) -> Int {
    guard threshold > 0, notional.isFinite, notional > threshold else { return 0 }
    return min(thicknessTiers - 1, max(0, Int((2 * log2(notional / threshold)).rounded(.down))))
  }

  /// 有没有被吃过（深色）：成交名义 > 0。
  public var hasFill: Bool { filledNotional > 0 }

  /// 画出来一样的判据（见上）。
  public struct RenderKey: Sendable, Equatable {
    public var id: String
    public var status: Status
    public var endMs: Int64?
    public var bucket: Int64
    public var price: Double
    public var threshold: Double
    public var tier: Int
    public var hasFill: Bool
  }

  public var renderKey: RenderKey {
    RenderKey(id: id, status: status, endMs: endMs, bucket: bucket, price: price, threshold: threshold,
              tier: thicknessTier, hasFill: hasFill)
  }
}

extension OrderFlowSnapshot {
  /// 图上画出来一样：每一单只比 `BigOrder.renderKey`（比 `sameContent` 粗，图表决定要不要重画底图用）。
  public func sameRender(as other: OrderFlowSnapshot) -> Bool {
    guard symbol == other.symbol, phase == other.phase, thresholds == other.thresholds, defaults == other.defaults,
          venues == other.venues, orders.count == other.orders.count else { return false }
    return zip(orders, other.orders).allSatisfy { $0.renderKey == $1.renderKey }
  }
}
