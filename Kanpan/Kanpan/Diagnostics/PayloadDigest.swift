import Foundation

// ============================================================ payload → 摘要
//
// 任务书 §13 M9 只关心四件事（P9.1 启动、P9.5/P9.7 稳定、P9.4 磁盘）：
//   崩溃、挂起、磁盘写入、启动耗时。
//
// MetricKit 一份 payload 是几十 KB 的 JSON，里面九成是我们不看的（蜂窝信号、
// 定位、GPU 时间、显示亮度…）。原始 JSON 照样整份存盘（出事要能回溯），
// 但**判定只看这里抽出来的摘要**——摘要是 Codable 的小结构，能直接写进
// docs/acceptance/M9.md 的表格。
//
// 这一层是**纯函数**：入参是 `Data`（`MXMetricPayload.jsonRepresentation()` 的
// 原样输出），出参是 `PayloadDigest`。所以没有真机、没有 MetricKit、在
// KanpanTests 里喂一段手写 JSON 就能把它全测了——这正是任务书要的
// 「注入的假 payload」。

/// payload 的种类。MetricKit 有两条回调，两种 JSON 结构完全不同。
enum PayloadKind: String, Codable, Sendable {
  /// `didReceive [MXMetricPayload]`：每天一份的聚合指标（直方图为主）。
  case metric
  /// `didReceive [MXDiagnosticPayload]`：崩溃 / 挂起 / 磁盘写入 / 启动超时的**逐次**诊断。
  case diagnostic
}

/// 一次崩溃或异常的可读摘要。`callStackTree` 不进摘要（太大），留在原始 JSON 里。
struct IncidentDigest: Codable, Sendable, Equatable {
  /// 归到哪一类：crash / hang / diskWrite / cpu / launch。
  var category: String
  /// 出事的 app 版本，形如 `1.0.0 (1)`。崩溃报告不写版本就没法判断「这是旧包的锅」。
  var version: String?
  /// 崩溃：`terminationReason`；挂起：挂了多久；磁盘：写了多少。人能读的一句话。
  var detail: String?
  /// 挂起时长 ms / 启动超时时长 ms。其它类别为 nil。
  var durationMs: Double?
  /// 磁盘写入异常写了多少 KB。其它类别为 nil。
  var writtenKB: Double?
}

/// 一份 payload 抽出来的全部判定依据。
struct PayloadDigest: Codable, Sendable, Equatable {
  var kind: PayloadKind

  /// payload 自带的采集区间（`timeStampBegin` / `timeStampEnd`），原样留字符串——
  /// MetricKit 给的是 `"2026-09-13 00:00:00 -0000"` 这种非 ISO8601 的格式，
  /// 硬解析容易在时区上出错，而我们只是拿它对账，不做运算。
  var begin: String?
  var end: String?

  /// `metaData.appBuildVersion` / 顶层 `appVersion`。
  var appVersion: String?
  var appBuildVersion: String?
  var osVersion: String?
  var deviceType: String?

  // ---- P9.1 启动耗时（metric payload）----
  /// 冷启动到第一帧。桶粒度近似，见 `ParsedHistogram.percentile`。
  var launchTimeToFirstDrawMs: Percentiles?
  /// 后台恢复耗时。
  var launchResumeMs: Percentiles?

  // ---- P9.7 挂起（metric payload）----
  /// 主线程挂起时长分布。
  var hangTimeMs: Percentiles?

  // ---- P9.4 磁盘（metric payload）----
  /// 当天累计逻辑写入，KB。任务书要「沙盒行情文件 < 1MB」，这一项是**进程写入量**，
  /// 不是沙盒占用量，两者别混——沙盒占用要靠 `du`（P9.4 明写了 `du`）。
  var cumulativeLogicalWritesKB: Double?

  // ---- P9.7 崩溃（diagnostic payload）----
  var incidents: [IncidentDigest]

  /// P9.7 的判定就是这一个数：崩溃条数必须为 0。
  var crashCount: Int { incidents.filter { $0.category == "crash" }.count }
  var hangCount: Int { incidents.filter { $0.category == "hang" }.count }

  /// 直方图抽出来的三个数。全 nil 表示这份 payload 里没这项。
  struct Percentiles: Codable, Sendable, Equatable {
    var count: Int
    var p50: Double?
    var p90: Double?
    var mean: Double?
    var max: Double?

    init?(_ h: ParsedHistogram) {
      guard !h.isEmpty else { return nil }
      count = h.totalCount
      p50 = h.percentile(0.5)
      p90 = h.percentile(0.9)
      mean = h.mean
      max = h.maximum
    }
  }
}

// ---------------------------------------------------------------- 解析

enum PayloadParser {

  /// 解析一份 payload。JSON 坏了返回 nil——上层照样把原始字节存盘，
  /// 只是摘要标成缺失，绝不吞掉证据。
  static func digest(from data: Data, kind: PayloadKind) -> PayloadDigest? {
    guard let root = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else {
      return nil
    }
    return digest(from: root, kind: kind)
  }

  static func digest(from root: [String: Any], kind: PayloadKind) -> PayloadDigest {
    let meta = root["metaData"] as? [String: Any] ?? [:]

    var d = PayloadDigest(
      kind: kind,
      begin: root["timeStampBegin"] as? String,
      end: root["timeStampEnd"] as? String,
      appVersion: root["appVersion"] as? String ?? meta["appVersion"] as? String,
      appBuildVersion: meta["appBuildVersion"] as? String,
      osVersion: meta["osVersion"] as? String,
      deviceType: meta["deviceType"] as? String,
      incidents: [])

    switch kind {
    case .metric: fillMetric(&d, root: root)
    case .diagnostic: fillDiagnostic(&d, root: root)
    }
    return d
  }

  // ---- metric payload ----

  private static func fillMetric(_ d: inout PayloadDigest, root: [String: Any]) {
    if let launch = root["applicationLaunchMetrics"] as? [String: Any] {
      // 键名在系统版本之间变过：早期带 `Key` 后缀。两个都试。
      let first = launch["histogrammedTimeToFirstDrawKey"] ?? launch["histogrammedTimeToFirstDraw"]
      d.launchTimeToFirstDrawMs = .init(ParsedHistogram.parse(first, unit: .milliseconds))

      let resume = launch["histogrammedApplicationResumeTime"]
        ?? launch["histogrammedResumeTimeKey"]
      d.launchResumeMs = .init(ParsedHistogram.parse(resume, unit: .milliseconds))
    }

    if let resp = root["applicationResponsivenessMetrics"] as? [String: Any] {
      let hang = resp["histogrammedApplicationHangTime"] ?? resp["histogrammedAppHangTime"]
      d.hangTimeMs = .init(ParsedHistogram.parse(hang, unit: .milliseconds))
    }

    if let disk = root["diskIOMetrics"] as? [String: Any] {
      d.cumulativeLogicalWritesKB = MeasurementText.kilobytes(any: disk["cumulativeLogicalWrites"])
    }
  }

  // ---- diagnostic payload ----

  /// 五种诊断数组 → 统一的 `IncidentDigest` 列表。
  ///
  /// 每一类的 `diagnosticMetaData` 字段集不一样，逐类挑：
  ///   crash      → terminationReason / signal / exceptionType
  ///   hang       → hangDuration
  ///   diskWrite  → writesCaused
  ///   cpu        → totalCPUTime / totalSampledTime
  ///   launch     → launchDuration
  private static func fillDiagnostic(_ d: inout PayloadDigest, root: [String: Any]) {
    var out: [IncidentDigest] = []

    func meta(_ item: Any) -> [String: Any] {
      (item as? [String: Any])?["diagnosticMetaData"] as? [String: Any] ?? [:]
    }
    func version(_ m: [String: Any], _ item: Any) -> String? {
      let v = m["appVersion"] as? String ?? (item as? [String: Any])?["version"] as? String
      guard let v else { return nil }
      if let b = m["appBuildVersion"] as? String { return "\(v) (\(b))" }
      return v
    }

    for item in root["crashDiagnostics"] as? [Any] ?? [] {
      let m = meta(item)
      // 崩溃的「一句话」优先用 terminationReason（人能看懂），退回到信号 / 异常号。
      var detail = m["terminationReason"] as? String
      if detail == nil {
        let sig = (m["signal"] as? NSNumber)?.intValue
        let exc = (m["exceptionType"] as? NSNumber)?.intValue
        if sig != nil || exc != nil {
          detail = "signal=\(sig.map(String.init) ?? "?") exceptionType=\(exc.map(String.init) ?? "?")"
        }
      }
      out.append(IncidentDigest(
        category: "crash", version: version(m, item), detail: detail,
        durationMs: nil, writtenKB: nil))
    }

    for item in root["hangDiagnostics"] as? [Any] ?? [] {
      let m = meta(item)
      let ms = MeasurementText.milliseconds(any: m["hangDuration"])
      out.append(IncidentDigest(
        category: "hang", version: version(m, item),
        detail: ms.map { "挂起 \(Int($0)) ms" },
        durationMs: ms, writtenKB: nil))
    }

    for item in root["diskWriteExceptionDiagnostics"] as? [Any] ?? [] {
      let m = meta(item)
      let kb = MeasurementText.kilobytes(any: m["writesCaused"])
      out.append(IncidentDigest(
        category: "diskWrite", version: version(m, item),
        detail: kb.map { "写入 \(Int($0)) KB" },
        durationMs: nil, writtenKB: kb))
    }

    for item in root["cpuExceptionDiagnostics"] as? [Any] ?? [] {
      let m = meta(item)
      let cpu = MeasurementText.milliseconds(any: m["totalCPUTime"])
      out.append(IncidentDigest(
        category: "cpu", version: version(m, item),
        detail: cpu.map { "CPU \(Int($0)) ms" },
        durationMs: cpu, writtenKB: nil))
    }

    for item in root["appLaunchDiagnostics"] as? [Any] ?? [] {
      let m = meta(item)
      let ms = MeasurementText.milliseconds(any: m["launchDuration"])
      out.append(IncidentDigest(
        category: "launch", version: version(m, item),
        detail: ms.map { "启动耗时 \(Int($0)) ms" },
        durationMs: ms, writtenKB: nil))
    }

    d.incidents = out
  }
}
