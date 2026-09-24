import Foundation

// 主力订单流 · 画法要用的只读派生量（2026-09-24 CoinAnk 式粗横带；同日晚改手机布局）。
//
// 图上不再一单一条：同一价位桶、同一侧、同一类（现货 / 合约）的几单合成一条带（合并在 KanpanChart，
// `OrderFlowGroup`），粗细按合并后的「名义 ÷ 门槛」之和分五档。所以每一单交给图表的是「门槛的几个四分之一」
// （`thicknessQuarters`，向下取整）：五档的分界 1× / 2× / 4× / 8× / 16× 都是 ¼ 的整数倍，单独一单的档
// 不因取整而偏；几单相加时按取整后的数算，名义在一格（¼ 门槛）里抖不改变画法。
//
// `renderKey` 就是「画出来一样」的判据：四分之一格、深浅、位置与状态都一样，底图不重画。
// `pixelKey`（行情流用来决定要不要发帧）比它细，这里不动它。
extension BigOrder {
  /// 粗细档数：0…4。2026-09-25 起图上一律「细线 + 签」，线粗按屏内排名定（见 `ChartRenderer+OrderFlow`），
  /// 这里的档只剩「画出来一样」的判据（`renderKey`）这一个用处。
  public static let thicknessTiers = 5
  /// 四分之一格封顶：16 倍门槛以上一律按 16 倍算（已经是最粗一档）。
  public static let maxThicknessQuarters = 64

  /// 这一单占门槛的几个四分之一（向下取整，封顶 64 = 16 倍）。
  public var thicknessQuarters: Int { Self.thicknessQuarters(notional: notional, threshold: threshold) }

  public static func thicknessQuarters(notional: Double, threshold: Double) -> Int {
    guard threshold > 0, notional.isFinite, notional > 0 else { return 0 }
    let q = (4 * notional / threshold).rounded(.down)
    return q.isFinite ? Int(min(Double(maxThicknessQuarters), max(0, q))) : 0
  }

  /// 单独画这一单时的粗细档。
  public var thicknessTier: Int { Self.thicknessTier(quarters: thicknessQuarters) }

  public static func thicknessTier(notional: Double, threshold: Double) -> Int {
    thicknessTier(quarters: thicknessQuarters(notional: notional, threshold: threshold))
  }

  /// 粗细档：r = 四分之一格数 ÷ 4（名义 ÷ 门槛），档 = ⌊log₂ r⌋ 夹到 0…4——
  /// 不到 2 倍（含撤单滞回留下的 0.5–1 倍）0 档，2 倍 1 档，4 倍 2 档，8 倍 3 档，16 倍及以上 4 档。
  public static func thicknessTier(quarters: Int) -> Int {
    guard quarters >= 8 else { return 0 }
    return min(thicknessTiers - 1, max(0, Int(log2(Double(quarters) / 4).rounded(.down))))
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
    public var quarters: Int
    public var hasFill: Bool
    public var tier: Int { BigOrder.thicknessTier(quarters: quarters) }
  }

  public var renderKey: RenderKey {
    RenderKey(id: id, status: status, endMs: endMs, bucket: bucket, price: price, threshold: threshold,
              quarters: thicknessQuarters, hasFill: hasFill)
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
