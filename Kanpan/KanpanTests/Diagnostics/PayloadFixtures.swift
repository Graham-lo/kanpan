import Foundation

@testable import Kanpan

// ============================================================ 假 payload
//
// `MXMetricPayload` / `MXDiagnosticPayload` 都**没有公开构造器**，也不能子类化，
// 模拟器上又永远不回调——所以想在没有真机的情况下测这条链，唯一的路是
// 沿着 `jsonRepresentation()` 这个缝切进去：真机上系统给的是这个形状的 JSON，
// 测试里我们自己造同一个形状的 JSON，喂进**同一个** `store.ingest(_:kind:)`。
//
// 下面的字段名和嵌套结构照着真 payload 抄（Apple 文档 + 真机 dump 的形状），
// 值换成好判定的整数。任何一处字段名写错，`PayloadDigest` 就抽不出数——
// 这正是这套件要防的事。

enum PayloadFixtures {

  static func json(_ object: [String: Any]) -> Data {
    try! JSONSerialization.data(withJSONObject: object)
  }

  /// MXHistogram 的形状。
  static func histogram(_ buckets: [(String, String, Int)]) -> [String: Any] {
    var values: [String: Any] = [:]
    for (i, b) in buckets.enumerated() {
      values["\(i)"] = ["bucketStart": b.0, "bucketEnd": b.1, "bucketCount": b.2]
    }
    return ["histogramNumBuckets": buckets.count, "histogramValue": values]
  }

  /// 一份典型的每日指标 payload。
  ///
  /// - 启动到首帧：380ms 一档 6 次、480ms 一档 2 次 —— P9.1 要「< 400ms 中位数」，
  ///   这份数据的 p50 落在第一桶（350ms），是**过**的样子。
  /// - 挂起：0–100ms 三次，没有长挂起。
  /// - 磁盘：当日累计写入 240 kB。
  static func metricPayload(
    appVersion: String = "1.0.0",
    build: String = "1",
    launchBuckets: [(String, String, Int)] = [("300 ms", "400 ms", 6), ("400 ms", "500 ms", 2)],
    hangBuckets: [(String, String, Int)] = [("0 ms", "100 ms", 3)],
    writes: String = "240 kB"
  ) -> Data {
    json([
      "appVersion": appVersion,
      "timeStampBegin": "2026-09-13 00:00:00 -0000",
      "timeStampEnd": "2026-09-13 23:59:59 -0000",
      "metaData": [
        "appBuildVersion": build,
        "osVersion": "iPhone OS 26.5 (23A123)",
        "deviceType": "iPhone17,1",
        "regionFormat": "CN",
        "platformArchitecture": "arm64e",
      ],
      "applicationLaunchMetrics": [
        "histogrammedTimeToFirstDrawKey": histogram(launchBuckets),
        "histogrammedApplicationResumeTime": histogram([("0 ms", "50 ms", 12)]),
      ],
      "applicationResponsivenessMetrics": [
        "histogrammedApplicationHangTime": histogram(hangBuckets)
      ],
      "diskIOMetrics": ["cumulativeLogicalWrites": writes],
      // 我们不看但真 payload 里一定有的东西，留着验「多余字段不会把解析带沟里」。
      "cellularConditionMetrics": ["cellConditionTime": histogram([("0 bars", "1 bars", 1)])],
      "gpuMetrics": ["cumulativeGPUTime": "30 sec"],
    ])
  }

  /// 一份带崩溃的诊断 payload。
  static func crashPayload(
    terminationReason: String? = "Namespace SIGNAL, Code 0xb",
    signal: Int = 11,
    version: String = "1.0.0",
    build: String = "1"
  ) -> Data {
    var meta: [String: Any] = [
      "appVersion": version,
      "appBuildVersion": build,
      "deviceType": "iPhone17,1",
      "osVersion": "iPhone OS 26.5 (23A123)",
      "platformArchitecture": "arm64e",
      "signal": signal,
      "exceptionType": 1,
      "exceptionCode": 0,
      "virtualMemoryRegionInfo": "0x0 is not in any region",
    ]
    if let terminationReason { meta["terminationReason"] = terminationReason }
    return json([
      "timeStampBegin": "2026-09-13 09:00:00 -0000",
      "timeStampEnd": "2026-09-13 09:00:01 -0000",
      "crashDiagnostics": [
        [
          "version": version,
          "diagnosticMetaData": meta,
          "callStackTree": ["callStackPerThread": true, "callStacks": []],
        ]
      ],
    ])
  }

  /// 四类非崩溃诊断各一条：挂起 3s、磁盘写 1MB、CPU 20s、启动超时 5s。
  static func mixedDiagnosticPayload() -> Data {
    func entry(_ meta: [String: Any]) -> [String: Any] {
      ["version": "1.0.0", "diagnosticMetaData": meta,
       "callStackTree": ["callStackPerThread": true, "callStacks": []]]
    }
    return json([
      "timeStampBegin": "2026-09-13 09:00:00 -0000",
      "timeStampEnd": "2026-09-13 10:00:00 -0000",
      "hangDiagnostics": [
        entry(["appVersion": "1.0.0", "appBuildVersion": "1", "hangDuration": "3000 ms"])
      ],
      "diskWriteExceptionDiagnostics": [
        entry(["appVersion": "1.0.0", "appBuildVersion": "1", "writesCaused": "1024 mB"])
      ],
      "cpuExceptionDiagnostics": [
        entry([
          "appVersion": "1.0.0", "appBuildVersion": "1",
          "totalCPUTime": "20 sec", "totalSampledTime": "30 sec",
        ])
      ],
      "appLaunchDiagnostics": [
        entry(["appVersion": "1.0.0", "appBuildVersion": "1", "launchDuration": "5 s"])
      ],
    ])
  }

  /// 什么事都没发生的一天：诊断 payload 存在但四个数组全空。
  static func cleanDiagnosticPayload() -> Data {
    json([
      "timeStampBegin": "2026-09-13 00:00:00 -0000",
      "timeStampEnd": "2026-09-13 23:59:59 -0000",
    ])
  }
}

/// 可控时钟。淘汰策略按时间排序，真时钟下同一毫秒写进去的几份分不出先后，
/// 用例会随机翻绿翻红。
final class TestClock: @unchecked Sendable {
  private let lock = NSLock()
  private var t: Date

  init(_ start: Date = Date(timeIntervalSince1970: 1_760_000_000)) { t = start }

  func advance(_ seconds: TimeInterval) {
    lock.lock()
    t += seconds
    lock.unlock()
  }

  var now: @Sendable () -> Date {
    { [self] in
      lock.lock()
      defer { lock.unlock() }
      return t
    }
  }
}
