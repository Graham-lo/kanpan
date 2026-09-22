import Foundation

// ============================================================ 落盘
//
// MetricKit 一天最多回调一次，而且**只在 app 下次启动时**把攒着的 payload 交过来。
// 也就是说：崩溃发生在周一，周二打开 app 才拿得到报告，拿到的那一刻如果不存盘，
// 这份报告就永远没了（`MXMetricManager` 不会再给第二次）。
//
// 所以这一层的唯一职责是「收到就立刻写进沙盒，一个字节都别丢」，判定逻辑都在别处。
//
// 存哪儿：`Library/Application Support/kanpan/Diagnostics/`（小写 kanpan，和别的存档同一棵树，见 `defaultDirectory`）。
//   - 不放 `Caches/`：系统随时会清，崩溃报告被清掉 = P9.7 没法验。
//   - 不放 `Documents/`：那要 Info.plist 开 `UIFileSharingEnabled` 才有意义，
//     而 Info.plist 这轮不许动。导出走 `exportBundle()` 生成一份合并 JSON，
//     模拟器上用 `xcrun simctl get_app_container booted com.mdd.kanpan data` 直接取，
//     真机上用 Xcode ▸ Devices ▸ Download Container。取法写在 docs/acceptance/M9.md。
//
// 容量：诊断文件不能变成 P9.4「沙盒 < 1MB」的累赘，所以**自带上限**
// （条数 + 总字节，超了删最旧的）。上限是 `Limits`，单测里调小了直接验淘汰。

/// 存盘的一条记录。`payload` 是 MetricKit 原样的 JSON，不做任何裁剪——
/// 摘要看走眼时要能回去翻原文。
struct DiagnosticsRecord: Codable, Sendable, Equatable {
  /// 存档格式版本。以后改结构靠它区分，别让新代码把旧文件解成空。
  var schema: Int = 1
  var id: String
  var kind: PayloadKind
  /// 收到的时刻（不是事件发生的时刻，事件时刻在 `digest.begin/end` 里）。
  var receivedAt: Date
  /// 解析出来的判定依据。JSON 坏掉时为 nil。
  var digest: PayloadDigest?
  /// 原始 payload。能解成对象就存对象，解不了就退到 base64（`payloadBase64`）。
  var payload: JSONValue?
  var payloadBase64: String?
}

/// 一次导出。给人看、也给 `Tools/diagnostics-report.sh` 读。
struct DiagnosticsBundle: Codable, Sendable {
  var schema: Int = 1
  var generatedAt: Date
  var recordCount: Int
  /// P9.7 的判定：崩溃总数必须为 0。
  var crashCount: Int
  var hangCount: Int
  /// 所有 metric payload 里启动到首帧 p50 的**最大值**（最坏的那天）。
  var worstLaunchP50Ms: Double?
  /// 最近一份 payload 报的当日累计逻辑写入。
  var latestLogicalWritesKB: Double?
  /// P9.7 verdict。没有任何 payload 时是 nil（「还没数据」≠「过了」）。
  var crashFree: Bool?
  var records: [DiagnosticsRecord]
}

final class DiagnosticsStore: @unchecked Sendable {

  struct Limits: Sendable {
    /// 最多留几份。MetricKit 一天一份，64 份 ≈ 两个月。
    var maxRecords: Int = 64
    /// 总字节上限。一份 payload 通常 20–60 KB，512 KB 大约放得下十几份大的；
    /// 条数和字节谁先到按谁淘汰。
    var maxBytes: Int = 512 * 1024
    init(maxRecords: Int = 64, maxBytes: Int = 512 * 1024) {
      self.maxRecords = maxRecords
      self.maxBytes = maxBytes
    }
  }

  private let directory: URL
  private let limits: Limits
  private let clock: @Sendable () -> Date
  private let lock = NSLock()

  /// `directory` 传 nil 用默认沙盒位置；单测传临时目录。
  /// `clock` 是为了让淘汰顺序在测试里可控——真机上就是 `Date.init`。
  init(
    directory: URL? = nil,
    limits: Limits = Limits(),
    clock: @escaping @Sendable () -> Date = { Date() }
  ) {
    self.directory = directory ?? DiagnosticsStore.defaultDirectory()
    self.limits = limits
    self.clock = clock
  }

  /// 诊断目录：`Application Support/kanpan/Diagnostics`。
  ///
  /// 以前是大写的 `Kanpan/Diagnostics`，而账号、行情缓存、提醒存档都住在小写的 `kanpan/` 下。
  /// 真机的 APFS 分大小写，两棵树并排相安无事；模拟器却不行——宿主盘不分大小写，
  /// 小写 `kanpan` 一旦先建出来，模拟器里 `mkdir Kanpan` 被宿主判「已存在」、按分大小写
  /// 去找又找不到，报 ENOTDIR，于是帧报告和 MetricKit payload **一份都存不下来**（P2.2 实测）。
  /// 所以统一到小写这棵树。老目录里若还有东西（真机上攒下的 payload），第一次用时整个搬过来。
  static func defaultDirectory() -> URL {
    let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)
      .first ?? URL(fileURLWithPath: NSTemporaryDirectory())
    let current = base.appendingPathComponent("kanpan/Diagnostics", isDirectory: true)
    let legacy = base.appendingPathComponent("Kanpan/Diagnostics", isDirectory: true)
    let fm = FileManager.default
    // 在不分大小写的盘上这两条路径是同一个目录，`fileExists` 两边都真，什么也不搬。
    if fm.fileExists(atPath: legacy.path), !fm.fileExists(atPath: current.path) {
      try? fm.createDirectory(at: current.deletingLastPathComponent(), withIntermediateDirectories: true)
      try? fm.moveItem(at: legacy, to: current)
    }
    return current
  }

  var directoryURL: URL { directory }

  // ---------------------------------------------------------------- 写

  /// 收下一份 payload。返回写成功的那条记录（写失败返回 nil，不抛——
  /// 诊断收集自己把 app 弄崩了是本末倒置）。
  @discardableResult
  func ingest(_ data: Data, kind: PayloadKind) -> DiagnosticsRecord? {
    let now = clock()
    let digest = PayloadParser.digest(from: data, kind: kind)
    let value = try? JSONDecoder().decode(JSONValue.self, from: data)

    let record = DiagnosticsRecord(
      id: UUID().uuidString,
      kind: kind,
      receivedAt: now,
      digest: digest,
      payload: value,
      // 解不成 JSON 才退 base64。这种情况理论上不该发生（MetricKit 给的就是 JSON），
      // 但真发生了也要把字节留住，否则证据就是假的。
      payloadBase64: value == nil ? data.base64EncodedString() : nil)

    lock.lock()
    defer { lock.unlock() }
    guard ensureDirectory() else { return nil }

    let name = Self.fileName(kind: kind, at: now, id: record.id)
    guard let encoded = try? Self.encoder.encode(record) else { return nil }
    let url = directory.appendingPathComponent(name)
    do {
      try encoded.write(to: url, options: .atomic)
    } catch {
      return nil
    }
    // 索引是增量维护的：刚写的这一份直接加进去，不必为了淘汰再扫一遍目录。
    var entries = indexLocked()
    entries.append(Slot(url: url, name: name, size: encoded.count))
    entries.sort(by: Self.older)
    slots = entries
    pruneLocked()
    return record
  }

  // ---------------------------------------------------------------- 读

  /// 按收到时间从旧到新。解不动的文件跳过但**不删**——留着人工看。
  func records() -> [DiagnosticsRecord] {
    lock.lock()
    defer { lock.unlock() }
    return recordsLocked().map(\.record)
  }

  /// 合并成一份可导出的 JSON。
  func exportBundle() -> DiagnosticsBundle {
    let all = records()
    let crashes = all.reduce(0) { $0 + ($1.digest?.crashCount ?? 0) }
    let hangs = all.reduce(0) { $0 + ($1.digest?.hangCount ?? 0) }
    let launches = all.compactMap { $0.digest?.launchTimeToFirstDrawMs?.p50 }
    // 「最近一份有报磁盘数的 payload」而不是「最后一份 payload」：
    // diagnostic payload 里没有这项，取最后一份会永远是 nil。
    let writes = all.compactMap { $0.digest?.cumulativeLogicalWritesKB }.last

    return DiagnosticsBundle(
      generatedAt: clock(),
      recordCount: all.count,
      crashCount: crashes,
      hangCount: hangs,
      worstLaunchP50Ms: launches.max(),
      latestLogicalWritesKB: writes,
      crashFree: all.isEmpty ? nil : crashes == 0,
      records: all)
  }

  /// 导出到文件，返回写到哪儿了。
  @discardableResult
  func writeExport(to url: URL) throws -> URL {
    let data = try Self.encoder.encode(exportBundle())
    try FileManager.default.createDirectory(
      at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
    try data.write(to: url, options: .atomic)
    return url
  }

  /// 清空。设置页「清诊断数据」用；单测也用它做 teardown。
  func removeAll() {
    lock.lock()
    defer { lock.unlock() }
    for f in (try? FileManager.default.contentsOfDirectory(
      at: directory, includingPropertiesForKeys: nil)) ?? []
    where f.pathExtension == "json" {
      try? FileManager.default.removeItem(at: f)
    }
    slots = []
  }

  /// 当前占用字节数。P9.4 取证时报这个数。
  func diskUsageBytes() -> Int {
    lock.lock()
    defer { lock.unlock() }
    // 走索引：只问文件大小，不用把每份 payload 都解出来。
    return indexLocked().reduce(0) { $0 + $1.size }
  }

  // ---------------------------------------------------------------- 内部

  private struct Entry {
    var url: URL
    var record: DiagnosticsRecord
    var size: Int
  }

  /// 目录的轻量索引：淘汰只需要「谁最旧、各自多大」，这两样文件名和
  /// `.fileSizeKey` 里都有（文件名带毫秒时间戳，见 `fileName(kind:at:id:)`），
  /// 一个字节的 JSON 都不用解。
  ///
  /// 以前 `pruneLocked` 每收一份就把整个目录读一遍、每份都 `JSONDecoder` 解一遍，
  /// 冷启动补收 24 份历史 payload 时这一步是 24 × 全目录。现在启动扫一次，
  /// 之后收一份加一条、淘汰一份减一条。
  private struct Slot {
    var url: URL
    var name: String
    var size: Int
  }

  /// nil = 还没扫过。
  private var slots: [Slot]?

  /// 文件名里的毫秒时间戳：`<kind>-<015d 毫秒>-<id 前 8 位>.json`。
  private static func stamp(_ name: String) -> Int64 {
    let parts = name.split(separator: "-")
    guard parts.count > 1, let value = Int64(parts[1]) else { return 0 }
    return value
  }

  /// 同一毫秒时按文件名兜底，保证顺序是确定的。
  private static func older(_ a: Slot, _ b: Slot) -> Bool {
    let x = stamp(a.name), y = stamp(b.name)
    return x == y ? a.name < b.name : x < y
  }

  private func indexLocked() -> [Slot] {
    if let slots { return slots }
    let fm = FileManager.default
    let files = (try? fm.contentsOfDirectory(
      at: directory, includingPropertiesForKeys: [.fileSizeKey])) ?? []
    var out: [Slot] = []
    for f in files where f.pathExtension == "json" {
      let size = (try? f.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
      out.append(Slot(url: f, name: f.lastPathComponent, size: size))
    }
    out.sort(by: Self.older)
    slots = out
    return out
  }

  private func recordsLocked() -> [Entry] {
    let fm = FileManager.default
    let files = (try? fm.contentsOfDirectory(
      at: directory, includingPropertiesForKeys: [.fileSizeKey])) ?? []
    var out: [Entry] = []
    for f in files where f.pathExtension == "json" {
      guard let data = try? Data(contentsOf: f),
        let r = try? Self.decoder.decode(DiagnosticsRecord.self, from: data)
      else { continue }
      out.append(Entry(url: f, record: r, size: data.count))
    }
    out.sort { $0.record.receivedAt < $1.record.receivedAt }
    return out
  }

  /// 超限就从最旧的开始删。**先删到条数达标，再删到字节达标**，
  /// 顺序无所谓（都是删最旧），分两步只是读起来清楚。
  private func pruneLocked() {
    var entries = indexLocked()

    while entries.count > limits.maxRecords, let oldest = entries.first {
      try? FileManager.default.removeItem(at: oldest.url)
      entries.removeFirst()
    }
    var total = entries.reduce(0) { $0 + $1.size }
    // 留一条底线：哪怕单份 payload 就超了 maxBytes，也得留住最新那一条，
    // 否则刚收到的崩溃报告会被自己的清理逻辑删掉。
    while total > limits.maxBytes, entries.count > 1, let oldest = entries.first {
      try? FileManager.default.removeItem(at: oldest.url)
      total -= oldest.size
      entries.removeFirst()
    }
    slots = entries
  }

  private func ensureDirectory() -> Bool {
    (try? FileManager.default.createDirectory(
      at: directory, withIntermediateDirectories: true)) != nil
      || FileManager.default.fileExists(atPath: directory.path)
  }

  /// 文件名带**毫秒时间戳零填充**，好让 `ls` 出来就是时间序，人翻沙盒时顺眼。
  static func fileName(kind: PayloadKind, at date: Date, id: String) -> String {
    let ms = Int64((date.timeIntervalSince1970 * 1000).rounded())
    let stamp = String(format: "%015lld", ms)
    return "\(kind.rawValue)-\(stamp)-\(id.prefix(8)).json"
  }

  static let encoder: JSONEncoder = {
    let e = JSONEncoder()
    e.dateEncodingStrategy = .iso8601
    e.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
    return e
  }()

  static let decoder: JSONDecoder = {
    let d = JSONDecoder()
    d.dateDecodingStrategy = .iso8601
    return d
  }()
}

// ============================================================ 任意 JSON
//
// `Codable` 没法直接存「任意 JSON」，而我们要把 MetricKit 的原始 payload
// 原样嵌进记录里（字段随系统版本变，写死结构必然漏）。这是最小实现：
// 只管 encode/decode 往返一致，不做便利访问器。

indirect enum JSONValue: Codable, Sendable, Equatable {
  case null
  case bool(Bool)
  case number(Double)
  case string(String)
  case array([JSONValue])
  case object([String: JSONValue])

  init(from decoder: Decoder) throws {
    let c = try decoder.singleValueContainer()
    if c.decodeNil() { self = .null; return }
    if let v = try? c.decode(Bool.self) { self = .bool(v); return }
    if let v = try? c.decode(Double.self) { self = .number(v); return }
    if let v = try? c.decode(String.self) { self = .string(v); return }
    if let v = try? c.decode([JSONValue].self) { self = .array(v); return }
    if let v = try? c.decode([String: JSONValue].self) { self = .object(v); return }
    throw DecodingError.dataCorruptedError(in: c, debugDescription: "不认识的 JSON 结点")
  }

  func encode(to encoder: Encoder) throws {
    var c = encoder.singleValueContainer()
    switch self {
    case .null: try c.encodeNil()
    case .bool(let v): try c.encode(v)
    case .number(let v): try c.encode(v)
    case .string(let v): try c.encode(v)
    case .array(let v): try c.encode(v)
    case .object(let v): try c.encode(v)
    }
  }
}
