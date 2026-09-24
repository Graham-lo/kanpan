import Foundation
import KanpanCore

/// 回放那一卷 K 线，以及「推进一根」时喂给图的那一段（第 25 项：回放增量追加）。
///
/// 原来每推进一根，桥都把 `bars.prefix(cursor + 1)` 整段重新摊成一条新的 `BarSeries`，
/// 再把记录当时的画线快照整份 JSON 解一遍。新序列的修订戳和上一拍毫无关系，图表认不出
/// 「只是后面长了一根」，于是十几条指标每一拍都从头算——4× 播放时一秒四次。
///
/// 现在：
/// - 往后推一根：在上一段后面 `append` 那一根，`BarSeries.isOneBarAfter` 成立，
///   图表走 `IndicatorEngine.updateTail` 只算最后一根；
/// - 原地不动（翻页补数后重画一次）：原样返回同一条，修订戳不变，图表整帧跳过；
/// - 往回退、或者整卷换过（往前补历史、超长裁掉一头）：才整段重建。
/// - 画线快照只解一次，之后每一拍拿同一份。
public struct ReviewReplayTape: Sendable {
  public let symbol: String
  public let interval: Interval
  public private(set) var bars: [Bar]
  /// 上一次喂给图的那一段：永远是 `bars` 的一个前缀（`replace` 守着这条）。
  private var shown: BarSeries?
  private let snapshot: Data?
  private var decoded: [Drawing]?
  /// 整段重建过几次（测试与量数用）。
  public private(set) var rebuilds = 0
  /// 画线快照解过几次（测试与量数用）。
  public private(set) var decodes = 0

  public init(symbol: String, interval: Interval, bars: [Bar], drawingSnapshot: Data?) {
    self.symbol = symbol; self.interval = interval; self.bars = bars; self.snapshot = drawingSnapshot
  }

  /// 换一批 K 线（往后翻页接上、往前补历史、超长裁掉一头）。
  ///
  /// 开头那根没变时，已经喂过的那一段仍是新卷的前缀——K 线严格等距、接上来的只会
  /// 落在尾巴后面（调用方验过缺口），留着接着 `append`。开头变了就作废，下一拍整段重建。
  public mutating func replace(bars new: [Bar]) {
    if new.first?.openTime != bars.first?.openTime || (shown?.count ?? 0) > new.count { shown = nil }
    bars = new
  }

  /// 前 `cursor + 1` 根。
  public mutating func series(through cursor: Int) -> BarSeries {
    let count = min(max(0, cursor + 1), bars.count)
    if var series = shown, series.count <= count {
      if series.count < count {
        // 先松开自己手里那一份，列数组少一个持有者，`append` 少拷一次。
        shown = nil
        for i in series.count..<count { series.append(bars[i]) }
        shown = series
      }
      return series
    }
    rebuilds += 1
    let series = BarSeries(symbol: symbol, interval: interval, bars: Array(bars.prefix(count)))
    shown = series
    return series
  }

  /// 记录当时的画线快照。解一次、存下来；坏的快照当作没有线，也只试一次。
  public mutating func drawings() -> [Drawing] {
    if let decoded { return decoded }
    decodes += 1
    let value = snapshot.flatMap { try? JSONDecoder().decode([Drawing].self, from: $0) } ?? []
    decoded = value
    return value
  }
}

/// 图上要画哪几条复盘记号（落图那一层每一帧都要问一遍）。
///
/// 原来 `RangeOverlayView.draw(_:)` 每一帧都把全部记录过一遍 `paints`（每条现拼一个
/// `InstrumentID` 比品种），拖图、捏合时一秒一百多帧。记录和图上的品种、周期都没变时
/// 答案不会变，所以存一份：记录那个数组还是同一块（`records` 没被改过，数组是写时复制，
/// 同一块内存就是同一份内容），品种 / 周期 / 行情源也一样，就直接给上一次的答案。
public struct ReviewMarkFilter {
  /// 一张图上最多画几条。
  public static let limit = 50
  private struct Key: Equatable { var venue: String; var symbol: String; var interval: String }
  private var key: Key?
  private var source: [ReviewRecord] = []
  private var result: [ReviewRecord] = []
  /// 真的重新筛过几次（测试与量数用）。
  public private(set) var misses = 0

  public init() {}

  public mutating func marks(_ records: [ReviewRecord], venue: String, symbol: String, interval: String) -> [ReviewRecord] {
    let key = Key(venue: venue, symbol: symbol, interval: interval)
    if key == self.key, Self.same(records, source) { return result }
    misses += 1
    self.key = key; source = records
    result = Array(records.lazy.filter { $0.paints(venue: venue, symbol: symbol, interval: interval) }.prefix(Self.limit))
    return result
  }

  /// 同一块数组存储就一定是同一份内容（我们手里攥着 `source`，那块内存不会被别人复用）；
  /// 不是同一块时退回逐条比——SwiftUI 重新下发的常常是内容一样的另一份拷贝。
  private static func same(_ a: [ReviewRecord], _ b: [ReviewRecord]) -> Bool {
    guard a.count == b.count else { return false }
    let shared = a.withUnsafeBufferPointer { pa in b.withUnsafeBufferPointer { pb in pa.baseAddress == pb.baseAddress } }
    return shared || a == b
  }
}
