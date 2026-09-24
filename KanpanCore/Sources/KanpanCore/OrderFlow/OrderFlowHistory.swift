import Foundation

// 主力订单流 · 服务端历史的一页。
//
// kanpan-api 常驻跟踪 BTC / ETH / SOL（别的币有人问过就跟，24 小时没人问就停），大单的生命周期
// 存 3 天（2026-09-25 从 30 天收到 3 天）。手机打开一只品种时取最近 24 小时并进本机模型，每分钟取一次增量，往左拖还能 24 小时一段
// 往前补，最多到 3 天：
// ```
// GET /v1/market/orderflow/history?base=BTC&from=<ms>&to=<ms>
// → {"base":"BTC","thresholds":{"spot":1e6,"usdtPerp":5e6,…,"step":100},"trackedSinceMs":…,"orders":[…]}
// ```
// 每条大单的字段名和 `BigOrder` 的属性名一样（服务端 `orderflow_history/model.rs`），但**价格与步长是
// 每个币的价**，本机模型用的是图上的价（`1000PEPE` 一格是 1000 个币）；换算与重新分桶在
// `OrderFlowModel.mergeHistory` 里做。落盘日志用的是短键（`BigOrder.CodingKeys`），所以这里另解一遍。

/// 服务端历史的一页。
public struct OrderFlowHistoryPage: Sendable, Equatable {
  /// 去掉缩放前缀的币名。
  public var base: String
  /// 服务端此刻用的默认门槛与步长（步长是每个币的价；还没算出来是 nil）。
  public var thresholds: OrderFlowThresholds
  /// 服务端从什么时候开始跟这只（封顶 3 天前）。比它早的去取也是空的。
  public var trackedSinceMs: Int64
  /// 这一页问的区间。
  public var fromMs: Int64
  public var toMs: Int64
  /// 区间内出现过的大单：出现 ≤ `toMs`，且还挂着或结束 ≥ `fromMs`；按出现时刻升序。
  public var orders: [BigOrder]

  public init(base: String, thresholds: OrderFlowThresholds, trackedSinceMs: Int64, fromMs: Int64, toMs: Int64,
              orders: [BigOrder]) {
    self.base = base; self.thresholds = thresholds; self.trackedSinceMs = trackedSinceMs
    self.fromMs = fromMs; self.toMs = toMs; self.orders = orders
  }

  /// 这一页里最晚的那个时刻（出现或结束）。增量从它往前退一点接着取。
  public var latestMs: Int64? {
    orders.map { max($0.firstSeenMs, $0.endMs ?? $0.firstSeenMs) }.max()
  }

  /// 解服务端回的 JSON。整体不是那个形状就是 nil；单条坏了（未知产品、状态、非数）只丢那一条。
  /// `fromMs` / `toMs` 是调用方问的区间（服务端不回显）。
  public static func parse(_ data: Data, fromMs: Int64, toMs: Int64) -> OrderFlowHistoryPage? {
    guard let root = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
          let base = root["base"] as? String,
          let rows = root["orders"] as? [[String: Any]] else { return nil }
    let t = root["thresholds"] as? [String: Any] ?? [:]
    let thresholds = OrderFlowThresholds(spot: positive(t["spot"]), usdtPerp: positive(t["usdtPerp"]),
                                         coinPerp: positive(t["coinPerp"]), delivery: positive(t["delivery"]),
                                         step: positive(t["step"]))
    let since = integer(root["trackedSinceMs"]) ?? fromMs
    var orders: [BigOrder] = []
    orders.reserveCapacity(rows.count)
    for row in rows {
      guard let venueID = row["venueID"] as? String, !venueID.isEmpty,
            let exchange = row["exchange"] as? String,
            let product = (row["product"] as? String).flatMap(OrderFlowProduct.init(rawValue:)),
            let side = (row["side"] as? String).flatMap(BookSide.init(rawValue:)),
            let status = (row["status"] as? String).flatMap(BigOrder.Status.init(rawValue:)),
            let bucket = integer(row["bucket"]),
            let price = positive(row["price"]),
            let first = integer(row["firstSeenMs"]),
            let initial = positive(row["initialNotional"]),
            let threshold = positive(row["threshold"]) else { continue }
      let end = integer(row["endMs"])
      // 挂着的没有结束时刻，结束的必须有；对不上的整条不认。
      guard (status == .live) == (end == nil) else { continue }
      orders.append(BigOrder(venueID: venueID, exchange: exchange, product: product, side: side, bucket: bucket,
                             price: price, firstSeenMs: first, endMs: end.map { max($0, first) }, status: status,
                             initialNotional: initial, notional: nonNegative(row["notional"]) ?? initial,
                             filledNotional: nonNegative(row["filledNotional"]) ?? 0, threshold: threshold,
                             vanishedNotional: nonNegative(row["vanishedNotional"])))
    }
    return OrderFlowHistoryPage(base: base, thresholds: thresholds, trackedSinceMs: since, fromMs: fromMs,
                                toMs: toMs, orders: orders)
  }

  private static func number(_ any: Any?) -> Double? {
    guard let n = any as? NSNumber, CFGetTypeID(n) != CFBooleanGetTypeID() else { return nil }
    let v = n.doubleValue
    return v.isFinite ? v : nil
  }
  private static func positive(_ any: Any?) -> Double? { number(any).flatMap { $0 > 0 ? $0 : nil } }
  private static func nonNegative(_ any: Any?) -> Double? { number(any).flatMap { $0 >= 0 ? $0 : nil } }
  private static func integer(_ any: Any?) -> Int64? {
    guard let v = number(any), abs(v) < 9e15 else { return nil }
    return Int64(v)
  }
}
