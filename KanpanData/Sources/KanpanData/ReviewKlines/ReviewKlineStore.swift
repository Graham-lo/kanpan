import Foundation
import KanpanCore

/// 复盘回放（笔记「在图上重温」、交易回放、复盘本缩略图）用的已收盘 K 线盘上缓存。
///
/// 为什么单独一份、不复用启动快照（`SeriesStore`）：启动快照存的是「每对最新的那一截」，
/// 复盘要的是**过去任意一段**——三个月前那一单前后几百根。两者的淘汰口径完全不同，
/// 硬塞进一份只会互相挤掉。
///
/// 布局：一个「品种 + 源周期（+ 行情源分区）」一个文件，文件里是若干段**已经问过交易所**
/// 的时间区间 `[from, to)` 和这段里的全部已收盘 K 线。判据只有一句：**段内交易所给过什么
/// 就是什么**，没有的那一根就是真的没有（停牌、上市前），不会再去问。正在走的那一根和
/// 「现在」之后的时间一律不进段，下次照样去取。
///
/// 封顶两层：
/// - 每个文件最多 `maxBarsPerSlot` 根（4 万根 × 56 字节 ≈ 2.2 MB），超了先丢离这次写入最远的段，
///   一段也装不下就从远离写入的那一头截；
/// - 整棵目录 `maxBytes`（默认 48 MB），超了按最近使用时间（读写都会刷新）从最久没用的删起，
///   删到 3/4 为止。
///
/// 放在 `Library/Caches` 下（`Paths.reviewKlines`），没了重新取回来就有，「清缓存」一并清。
public actor ReviewKlineStore {
  public static let defaultMaxBytes = 48 * 1024 * 1024
  public static let defaultMaxBarsPerSlot = 40_000

  public let directory: URL
  public let maxBytes: Int
  public let maxBarsPerSlot: Int

  /// 一段已经问过交易所的区间。`bars` 按 openTime 升序，全落在 `[from, to)` 里。
  struct Segment: Equatable {
    var from: Int64
    var to: Int64
    var bars: [Bar]
  }

  /// 最近读写过的几个文件留在内存里，翻来覆去开同一条记录不用每次读盘解码。
  private var memory: [URL: [Segment]] = [:]
  private var memoryOrder: [URL] = []
  private let memorySlots = 6
  /// 盘上每个文件的大小与最近使用时间。第一次用到时扫一遍目录建起来，之后增量维护。
  private var index: [String: IndexEntry]?
  private struct IndexEntry { var url: URL; var bytes: Int; var used: Date }
  /// 盘上索引的键：把软链接解开（`/tmp` 与 `/private/tmp`）之后的路径，目录扫出来的和拼出来的才对得上。
  private static func key(_ url: URL) -> String { url.resolvingSymlinksInPath().path }

  public init(directory: URL, maxBytes: Int = ReviewKlineStore.defaultMaxBytes,
              maxBarsPerSlot: Int = ReviewKlineStore.defaultMaxBarsPerSlot) {
    self.directory = directory
    self.maxBytes = maxBytes
    self.maxBarsPerSlot = max(1, maxBarsPerSlot)
  }

  // MARK: 查

  /// 一次查询的结果：盘上已有的那几根，以及还得去交易所问的那几段（升序、互不重叠）。
  public struct Lookup: Sendable, Equatable {
    public var bars: [Bar]
    public var missing: [Range<Int64>]
    public var isComplete: Bool { missing.isEmpty }
  }

  /// `[from, to)` 这一段里盘上已有的已收盘 K 线，以及缺的那几段。
  public func lookup(symbol: String, interval: Interval, namespace: String? = nil,
                     from: Int64, to: Int64) -> Lookup {
    guard to > from else { return Lookup(bars: [], missing: []) }
    guard let url = Self.url(symbol: symbol, interval: interval, namespace: namespace, in: directory) else {
      return Lookup(bars: [], missing: [from..<to])
    }
    let segments = load(url)
    var bars: [Bar] = []
    var missing: [Range<Int64>] = []
    var cursor = from
    for seg in segments where seg.to > from && seg.from < to {
      if seg.from > cursor { missing.append(cursor..<min(seg.from, to)) }
      bars.append(contentsOf: seg.bars.lazy.filter { $0.openTime >= from && $0.openTime < to })
      cursor = max(cursor, seg.to)
      if cursor >= to { break }
    }
    if cursor < to { missing.append(cursor..<to) }
    if missing != [from..<to] { touch(url) }
    return Lookup(bars: bars, missing: missing)
  }

  // MARK: 写

  /// 记下「`[from, to)` 问过交易所了，给的是 `bars`」。
  ///
  /// 只记已收盘的部分：遇到还在走的那一根（收线时间晚于 `now`），覆盖区间就截到它的开盘；
  /// 区间末端离 `now` 不到一根时，也只算到最后一根已收盘的收线为止——那后面可能马上还会
  /// 长出新的一根。交易所什么都没给的一次（上市前、线路不认这只）不记，下次再问。
  public func record(symbol: String, interval: Interval, namespace: String? = nil,
                     from: Int64, to: Int64, bars: [Bar], now: Int64) {
    guard to > from,
          let url = Self.url(symbol: symbol, interval: interval, namespace: namespace, in: directory) else { return }
    let sorted = bars.filter { $0.openTime >= from && $0.openTime < to }.sorted { $0.openTime < $1.openTime }
    var limit = to
    if let forming = sorted.first(where: { interval.advancing($0.openTime, by: 1) > now }) {
      limit = min(limit, forming.openTime)
    }
    let closed = sorted.filter { $0.openTime < limit }
    if to > now - interval.stepMs {
      limit = min(limit, closed.last.map { interval.advancing($0.openTime, by: 1) } ?? from)
    }
    guard limit > from, !closed.isEmpty else { return }
    let fresh = Segment(from: from, to: limit, bars: closed)
    var segments = Self.merge(load(url), with: fresh)
    segments = Self.capped(segments, around: from..<limit, maxBars: maxBarsPerSlot, interval: interval)
    write(segments, to: url)
  }

  // MARK: 管理

  /// 整棵目录现在占多少字节（按文件大小）。
  public func totalBytes() -> Int {
    buildIndex().values.reduce(0) { $0 + $1.bytes }
  }

  /// 全部删掉（测试与「清缓存」以外的兜底）。
  public func removeAll() {
    try? FileManager.default.removeItem(at: directory)
    memory = [:]; memoryOrder = []; index = [:]
  }

  // MARK: 合并与封顶（纯函数，单测直接打）

  static func merge(_ segments: [Segment], with fresh: Segment) -> [Segment] {
    var result: [Segment] = []
    var merged = fresh
    for seg in segments {
      if seg.to >= merged.from && seg.from <= merged.to {
        // 相交或首尾相接：并成一段，同一根以这次取回来的为准。
        var byTime: [Int64: Bar] = [:]
        for bar in seg.bars { byTime[bar.openTime] = bar }
        for bar in merged.bars { byTime[bar.openTime] = bar }
        merged = Segment(from: min(seg.from, merged.from), to: max(seg.to, merged.to),
                         bars: byTime.values.sorted { $0.openTime < $1.openTime })
      } else {
        result.append(seg)
      }
    }
    result.append(merged)
    return result.sorted { $0.from < $1.from }
  }

  static func capped(_ segments: [Segment], around focus: Range<Int64>, maxBars: Int,
                     interval: Interval) -> [Segment] {
    var segs = segments
    func total() -> Int { segs.reduce(0) { $0 + $1.bars.count } }
    func distance(_ s: Segment) -> Int64 {
      if s.to <= focus.lowerBound { return focus.lowerBound - s.to }
      if s.from >= focus.upperBound { return s.from - focus.upperBound }
      return 0
    }
    while total() > maxBars, segs.count > 1 {
      // 丢离这次写入最远的一段。
      guard let far = segs.indices.max(by: { distance(segs[$0]) < distance(segs[$1]) }) else { break }
      segs.remove(at: far)
    }
    if total() > maxBars, var only = segs.first {
      // 一段就装不下：从离写入远的那一头截。
      let excess = only.bars.count - maxBars
      let headGap = focus.lowerBound - only.from
      let tailGap = only.to - focus.upperBound
      if tailGap > headGap {
        only.bars.removeLast(excess)
        only.to = only.bars.last.map { interval.advancing($0.openTime, by: 1) } ?? only.from
      } else {
        only.bars.removeFirst(excess)
        only.from = only.bars.first?.openTime ?? only.to
      }
      segs = only.to > only.from ? [only] : []
    }
    return segs
  }

  // MARK: 盘

  /// 文件位置：`<目录>/[<分区>/]<交易所>/<市场>/<品种>@<周期>.rkl`。周期片段沿用启动快照那份
  /// （`1m` 与 `1M` 只差大小写，iOS 文件系统不分大小写）。
  static func url(symbol: String, interval: Interval, namespace: String?, in dir: URL) -> URL? {
    let id = InstrumentID(symbol)
    guard id.isValid else { return nil }
    var base = dir
    if let namespace, !namespace.isEmpty {
      let safe = namespace.filter { $0.isLetter || $0.isNumber || $0 == "-" || $0 == "_" }
      guard !safe.isEmpty else { return nil }
      base = base.appendingPathComponent("ns-" + safe, isDirectory: true)
    }
    return base.appendingPathComponent(id.venue, isDirectory: true)
      .appendingPathComponent(id.market, isDirectory: true)
      .appendingPathComponent("\(id.symbol)@\(SeriesStore.slug(interval)).rkl")
  }

  private func load(_ url: URL) -> [Segment] {
    if let hit = memory[url] {
      // 「清缓存」可能刚把整棵目录删了：内存里那份跟着作废，别让用量和淘汰对着一份不存在的文件算。
      if hit.isEmpty || FileManager.default.fileExists(atPath: url.path) { remember(url, hit); return hit }
      memory[url] = nil; memoryOrder.removeAll { $0 == url }; index = nil
    }
    let segments = (try? Data(contentsOf: url)).flatMap(Self.decode) ?? []
    remember(url, segments)
    return segments
  }

  private func remember(_ url: URL, _ segments: [Segment]) {
    memory[url] = segments
    memoryOrder.removeAll { $0 == url }
    memoryOrder.append(url)
    while memoryOrder.count > memorySlots { memory[memoryOrder.removeFirst()] = nil }
  }

  private func touch(_ url: URL) {
    let now = Date()
    try? FileManager.default.setAttributes([.modificationDate: now], ofItemAtPath: url.path)
    if var entry = index?[Self.key(url)] { entry.used = now; index?[Self.key(url)] = entry }
  }

  private func write(_ segments: [Segment], to url: URL) {
    let fm = FileManager.default
    buildIndex()
    if segments.isEmpty {
      try? fm.removeItem(at: url)
      index?[Self.key(url)] = nil
      remember(url, [])
      return
    }
    let data = Self.encode(segments)
    do {
      try fm.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
      try data.write(to: url, options: .atomic)
      var values = URLResourceValues(); values.isExcludedFromBackup = true
      var mutable = url; try? mutable.setResourceValues(values)
    } catch { return }
    remember(url, segments)
    index?[Self.key(url)] = IndexEntry(url: url, bytes: data.count, used: Date())
    evict(keeping: url)
  }

  @discardableResult
  private func buildIndex() -> [String: IndexEntry] {
    if let index { return index }
    var built: [String: IndexEntry] = [:]
    let keys: [URLResourceKey] = [.isRegularFileKey, .fileSizeKey, .contentModificationDateKey]
    if let walker = FileManager.default.enumerator(at: directory, includingPropertiesForKeys: keys) {
      for case let file as URL in walker where file.pathExtension == "rkl" {
        let v = try? file.resourceValues(forKeys: Set(keys))
        guard v?.isRegularFile == true else { continue }
        built[Self.key(file)] = IndexEntry(url: file, bytes: v?.fileSize ?? 0,
                                           used: v?.contentModificationDate ?? .distantPast)
      }
    }
    index = built
    return built
  }

  private func evict(keeping keep: URL) {
    guard var idx = index else { return }
    var total = idx.values.reduce(0) { $0 + $1.bytes }
    guard total > maxBytes else { return }
    let target = maxBytes * 3 / 4
    let kept = Self.key(keep)
    for (k, entry) in idx.sorted(by: { $0.value.used < $1.value.used }) where total > target && k != kept {
      try? FileManager.default.removeItem(at: entry.url)
      idx[k] = nil
      for (m, _) in memory where Self.key(m) == k { memory[m] = nil; memoryOrder.removeAll { $0 == m } }
      total -= entry.bytes
    }
    index = idx
  }

  // MARK: 编码
  //
  // 二进制而不是 JSON：主动买量拿不到时是 NaN（见 `Bar.takerBuy`），JSON 存不了；
  // 一根 56 字节，几万根也就两三 MB，解码是一次内存拷贝。

  static let magic: UInt32 = 0x524B_4C31 // "RKL1"

  static func encode(_ segments: [Segment]) -> Data {
    var data = Data()
    data.reserveCapacity(8 + segments.reduce(0) { $0 + 20 + $1.bars.count * 56 })
    append(&data, magic)
    append(&data, UInt32(segments.count))
    for seg in segments {
      append(&data, UInt64(bitPattern: seg.from))
      append(&data, UInt64(bitPattern: seg.to))
      append(&data, UInt32(seg.bars.count))
      for bar in seg.bars {
        append(&data, UInt64(bitPattern: bar.openTime))
        for v in [bar.open, bar.high, bar.low, bar.close, bar.volume, bar.takerBuy] {
          append(&data, v.bitPattern)
        }
      }
    }
    return data
  }

  static func decode(_ data: Data) -> [Segment]? {
    var reader = Reader(data: data)
    guard reader.u32() == magic, let count = reader.u32(), count < 10_000 else { return nil }
    var segments: [Segment] = []
    for _ in 0..<count {
      guard let from = reader.u64(), let to = reader.u64(), let n = reader.u32(),
            reader.remaining >= Int(n) * 56 else { return nil }
      var bars: [Bar] = []
      bars.reserveCapacity(Int(n))
      for _ in 0..<n {
        guard let t = reader.u64() else { return nil }
        var values: [Double] = []
        for _ in 0..<6 { guard let raw = reader.u64() else { return nil }; values.append(Double(bitPattern: raw)) }
        bars.append(Bar(openTime: Int64(bitPattern: t), open: values[0], high: values[1], low: values[2],
                        close: values[3], volume: values[4], takerBuy: values[5]))
      }
      let f = Int64(bitPattern: from), e = Int64(bitPattern: to)
      guard e > f else { return nil }
      segments.append(Segment(from: f, to: e, bars: bars))
    }
    return segments.sorted { $0.from < $1.from }
  }

  private static func append<T: FixedWidthInteger>(_ data: inout Data, _ value: T) {
    withUnsafeBytes(of: value.littleEndian) { data.append(contentsOf: $0) }
  }

  private struct Reader {
    let data: Data
    var offset = 0
    init(data: Data) { self.data = data }
    var remaining: Int { data.count - offset }
    mutating func u32() -> UInt32? { read(UInt32.self) }
    mutating func u64() -> UInt64? { read(UInt64.self) }
    private mutating func read<T: FixedWidthInteger>(_: T.Type) -> T? {
      let size = MemoryLayout<T>.size
      guard remaining >= size else { return nil }
      var value: T = 0
      _ = withUnsafeMutableBytes(of: &value) { buf in
        data.copyBytes(to: buf, from: (data.startIndex + offset)..<(data.startIndex + offset + size))
      }
      offset += size
      return T(littleEndian: value)
    }
  }
}
