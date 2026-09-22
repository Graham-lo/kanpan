import Foundation

// ============================================================ 帧报告落盘
//
// `FrameProbe` 采完一段就往这儿扔一份 `FrameReport`。落盘位置和 MetricKit 的
// 诊断放一块（`Application Support/kanpan/Diagnostics/frames/`），取法也一样：
//
//   模拟器：xcrun simctl get_app_container booted com.mdd.kanpan data
//   真机：  Xcode ▸ Window ▸ Devices and Simulators ▸ Download Container
//
// 也可以直接调 `Tools/frame-report.sh`，它把上面这两步和判定表一起干了。
//
// 为什么不复用 `DiagnosticsStore`：那个是给 MetricKit 用的，一条记录 = 一份系统
// payload，淘汰策略按「攒两个月」设计；帧报告是我们主动采的，一次取证能出十几份，
// 混在一起会把崩溃报告挤掉。两套目录、两套上限，互不影响。

/// 一次取证的全部帧报告。
struct FrameReportBundle: Codable, Sendable {
  var schema: Int = 1
  var generatedAt: Date
  var reports: [FrameReport]

  /// 全部报告都判过且都过，才是 true；有一份没数据就是 nil。
  var allPassed: Bool? {
    let flags = reports.map(\.verdict.allPassed)
    if flags.isEmpty || flags.contains(where: { $0 == nil }) { return nil }
    return flags.allSatisfy { $0 == true }
  }
}

final class FrameReportStore: @unchecked Sendable {

  private let directory: URL
  private let maxReports: Int
  private let clock: @Sendable () -> Date
  private let lock = NSLock()

  init(
    directory: URL? = nil,
    maxReports: Int = 64,
    clock: @escaping @Sendable () -> Date = { Date() }
  ) {
    self.directory = directory
      ?? DiagnosticsStore.defaultDirectory().appendingPathComponent("frames", isDirectory: true)
    self.maxReports = maxReports
    self.clock = clock
  }

  var directoryURL: URL { directory }

  /// 存一份。文件名带毫秒时间戳，`ls` 出来就是时间序。
  /// 标签里的斜杠和空格换成 `-`，否则 `label = "拖动 / 60s"` 会当成路径。
  @discardableResult
  func save(_ report: FrameReport) -> URL? {
    lock.lock()
    defer { lock.unlock() }
    guard (try? FileManager.default.createDirectory(
      at: directory, withIntermediateDirectories: true)) != nil
      || FileManager.default.fileExists(atPath: directory.path)
    else { return nil }

    let ms = Int64((clock().timeIntervalSince1970 * 1000).rounded())
    let safe = report.label.map { c -> Character in
      "/\\: ".contains(c) ? "-" : c
    }
    let url = directory.appendingPathComponent(
      "frame-\(String(format: "%015lld", ms))-\(String(safe)).json")
    guard let data = try? DiagnosticsStore.encoder.encode(report),
      (try? data.write(to: url, options: .atomic)) != nil
    else { return nil }
    pruneLocked()
    return url
  }

  /// 按文件名（= 时间序）读回来。
  func reports() -> [FrameReport] {
    lock.lock()
    defer { lock.unlock() }
    return reportsLocked().map(\.1)
  }

  func bundle() -> FrameReportBundle {
    FrameReportBundle(generatedAt: clock(), reports: reports())
  }

  @discardableResult
  func writeExport(to url: URL) throws -> URL {
    let data = try DiagnosticsStore.encoder.encode(bundle())
    try FileManager.default.createDirectory(
      at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
    try data.write(to: url, options: .atomic)
    return url
  }

  func removeAll() {
    lock.lock()
    defer { lock.unlock() }
    for (url, _) in reportsLocked() { try? FileManager.default.removeItem(at: url) }
  }

  private func reportsLocked() -> [(URL, FrameReport)] {
    let files = (try? FileManager.default.contentsOfDirectory(
      at: directory, includingPropertiesForKeys: nil)) ?? []
    return files
      .filter { $0.pathExtension == "json" }
      .sorted { $0.lastPathComponent < $1.lastPathComponent }
      .compactMap { url in
        guard let d = try? Data(contentsOf: url),
          let r = try? DiagnosticsStore.decoder.decode(FrameReport.self, from: d)
        else { return nil }
        return (url, r)
      }
  }

  private func pruneLocked() {
    var all = reportsLocked()
    while all.count > maxReports, let oldest = all.first {
      try? FileManager.default.removeItem(at: oldest.0)
      all.removeFirst()
    }
  }
}
