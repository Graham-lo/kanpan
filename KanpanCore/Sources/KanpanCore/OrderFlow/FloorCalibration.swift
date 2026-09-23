import Foundation

// 主力订单流 · 绝对下限标定。
//
// 原项目 `crates/bit-orderbook-signal-policy/src/calibration.rs`：每侧一条分布、floor 取 q0.90、
// 样本少于 CALIBRATION_MINIMUM_SAMPLES（2000）不作数。看盘去掉时段维度与冻结流程，改成在手机上
// 自己攒：图开着时每秒每侧记一个样本（当帧该侧 300 bps 内各桶名义的 q0.90），留最近 2000 个、
// 7 天滚动，本机落盘；不够 2000 时由调用方用当帧的同一统计量顶着（`frameFloor`）。
// 样本与兜底是同一个量，攒够后换过去不会让门槛突然跳一截。

public struct FloorCalibration: Sendable, Equatable {
  public static let minimumSamples = 2000
  public static let capacity = 2000
  public static let windowMs: Int64 = 7 * 86_400_000
  public static let quantile = 0.90

  public struct Sample: Sendable, Equatable {
    public var timeMs: Int64
    public var value: Double
    public init(timeMs: Int64, value: Double) { self.timeMs = timeMs; self.value = value }
  }

  public private(set) var bids: [Sample] = []
  public private(set) var asks: [Sample] = []

  public init() {}

  public func samples(_ side: BookSide) -> [Sample] { side == .bid ? bids : asks }

  public mutating func record(_ value: Double, side: BookSide, atMs: Int64) {
    guard value.isFinite, value > 0 else { return }
    var list = samples(side)
    list.append(Sample(timeMs: atMs, value: value))
    Self.prune(&list, nowMs: atMs)
    if side == .bid { bids = list } else { asks = list }
  }

  /// 攒够 2000 个 7 天内样本时的 q0.90；不够返回 nil，由调用方用当帧兜底。
  public func floor(_ side: BookSide, nowMs: Int64) -> Double? {
    let cutoff = nowMs - Self.windowMs
    let values = samples(side).lazy.filter { $0.timeMs >= cutoff }.map(\.value)
    let array = Array(values)
    guard array.count >= Self.minimumSamples else { return nil }
    return Self.value(atQuantile: Self.quantile, of: array)
  }

  /// 当帧兜底：该侧 300 bps 内各桶名义的 q0.90。每秒的标定样本也是这个量。
  public static func frameFloor(_ notionals: [Double]) -> Double? {
    value(atQuantile: quantile, of: notionals.filter { $0.isFinite && $0 > 0 })
  }

  /// 最近秩分位：排序后取第 ceil(q·n) 个；空集返回 nil。
  public static func value(atQuantile q: Double, of values: [Double]) -> Double? {
    guard !values.isEmpty else { return nil }
    let sorted = values.sorted()
    let rank = Int((q * Double(sorted.count)).rounded(.up))
    return sorted[min(max(rank - 1, 0), sorted.count - 1)]
  }

  private static func prune(_ list: inout [Sample], nowMs: Int64) {
    let cutoff = nowMs - windowMs
    if let first = list.firstIndex(where: { $0.timeMs >= cutoff }), first > 0 { list.removeFirst(first) }
    else if list.last.map({ $0.timeMs < cutoff }) == true { list.removeAll() }
    if list.count > capacity { list.removeFirst(list.count - capacity) }
  }

  // MARK: 落盘（每个样本 8 字节：相对秒 Int32 + 名义 Float32；每侧 2000 个 ≈ 16 KB）

  private static let magic: UInt32 = 0x4F46_4331  // "OFC1"

  public func encoded() -> Data {
    let base = min(bids.first?.timeMs ?? .max, asks.first?.timeMs ?? .max)
    let baseMs = base == .max ? 0 : base
    var data = Data(capacity: 20 + (bids.count + asks.count) * 8)
    func put<T: FixedWidthInteger>(_ v: T) { withUnsafeBytes(of: v.littleEndian) { data.append(contentsOf: $0) } }
    put(Self.magic); put(baseMs); put(UInt32(bids.count)); put(UInt32(asks.count))
    for s in bids + asks {
      put(Int32(clamping: (s.timeMs - baseMs) / 1000))
      put(Float32(s.value).bitPattern)
    }
    return data
  }

  public init?(encoded data: Data) {
    let bytes = [UInt8](data)
    var offset = 0
    func take<T: FixedWidthInteger>(_: T.Type) -> T? {
      let size = MemoryLayout<T>.size
      guard offset + size <= bytes.count else { return nil }
      var v: T = 0
      for i in 0..<size { v |= T(truncatingIfNeeded: bytes[offset + i]) << (8 * i) }
      offset += size
      return v
    }
    guard take(UInt32.self) == Self.magic, let baseMs = take(Int64.self),
          let nb = take(UInt32.self), let na = take(UInt32.self),
          Int(nb) <= Self.capacity, Int(na) <= Self.capacity,
          bytes.count == 20 + (Int(nb) + Int(na)) * 8 else { return nil }
    func read(_ n: UInt32) -> [Sample]? {
      var out: [Sample] = []
      out.reserveCapacity(Int(n))
      for _ in 0..<n {
        guard let dt = take(Int32.self), let bits = take(UInt32.self) else { return nil }
        let v = Double(Float32(bitPattern: bits))
        guard v.isFinite, v > 0 else { continue }
        out.append(Sample(timeMs: baseMs + Int64(dt) * 1000, value: v))
      }
      return out
    }
    guard let b = read(nb), let a = read(na) else { return nil }
    bids = b; asks = a
  }
}
