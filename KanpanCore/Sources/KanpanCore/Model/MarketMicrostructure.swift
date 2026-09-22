import Foundation

/// 一帧五档盘口。图表只消费价量，不接触网络协议或增量订单簿。
public struct OrderBook: Sendable, Equatable {
  public struct Level: Sendable, Equatable {
    public var price: Double
    public var quantity: Double
    public init(price: Double, quantity: Double) { self.price = price; self.quantity = quantity }
  }
  public var symbol: String
  public var time: Int64
  public var bids: [Level]
  public var asks: [Level]
  public init(symbol: String, time: Int64, bids: [Level], asks: [Level]) {
    self.symbol = InstrumentID.canonical(symbol); self.time = time
    let valid: (Level) -> Bool = { $0.price.isFinite && $0.price > 0 && $0.quantity.isFinite && $0.quantity > 0 }
    self.bids = Array(bids.filter(valid).sorted { $0.price > $1.price }.prefix(5))
    self.asks = Array(asks.filter(valid).sorted { $0.price < $1.price }.prefix(5))
  }
}

/// 仅保留正在接收的当前桶，断线即清空。历史比率始终来自已完成的统计桶。
public struct TakerBucket: Sendable {
  public private(set) var time: Int64?
  public private(set) var buy = 0.0
  public private(set) var sell = 0.0
  private var lastID: Int64?
  private var lastTime: Int64 = 0
  private let startedAt: Int64
  /// 中途接入的半桶不能冒充完整桶；从连接后第一个自然桶开始发布。
  public init(startedAt: Int64 = 0) { self.startedAt = startedAt }
  public mutating func add(time: Int64, quantity: Double, buyer: Bool, id: Int64?, interval: Interval) {
    guard time > 0, time >= lastTime, quantity.isFinite, quantity > 0 else { return }
    if let id, let lastID, id <= lastID { return }
    let sampleInterval: Interval = interval.stepMs < 300_000 ? .m5 : interval.stepMs > 86_400_000 ? .d1 : interval
    let bucket = Aggregator.bucketStart(ms: time, interval: sampleInterval)
    if self.time != bucket { self.time = bucket; buy = 0; sell = 0 }
    if buyer { buy += quantity } else { sell += quantity }
    lastID = id; lastTime = time
  }
  public var point: OIPoint? {
    guard let time, time >= startedAt, sell > 0, (buy / sell).isFinite else { return nil }
    return OIPoint(time: time, value: buy / sell)
  }
}
