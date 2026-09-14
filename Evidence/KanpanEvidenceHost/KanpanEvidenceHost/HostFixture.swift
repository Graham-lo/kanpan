import Foundation
import KanpanCore

/// 定版快照。和 `KanpanChart/Tests/KanpanChartTests/EvidenceSupport.swift` 里的
/// `Fixture` 读的是**同一个文件**（`Tools/export-chart-fixtures.mjs` 从原型导出的
/// `snapshot.json`），字段一一对应，只是那份跟着测试 bundle 走、这份跟着宿主 app 走。
///
/// 取证一律用它，**不碰网络**：A3.12 量的是「静止」，多一条 socket 就不是静止了。
enum HostFixture {
  struct Snapshot: Decodable {
    struct Meta: Decodable {
      let base: String, quote: String
      let pricePrecision: Int, tickSize: Double
    }
    struct OI: Decodable { let t0: Int64, step: Int64, values: [Double] }
    let symbol: String, interval: String
    let t0: Int64, step: Int64, p: Int
    let open: [Double], high: [Double], low: [Double], close: [Double], volume: [Double]
    let oi: OI
    let meta: Meta
  }

  /// 仓库根。`#filePath` 是编译期写死的绝对路径：
  /// `<仓库>/Evidence/KanpanEvidenceHost/KanpanEvidenceHost/HostFixture.swift`，往上数三层。
  /// 模拟器不强制 app 沙箱，进程能直接读宿主机路径——`EvidenceSupport` 落盘用的也是这条。
  /// fixture 不进 app bundle，就是为了不在仓库里留第二份快照（会漂）。
  static let repoRoot: URL = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent()  // KanpanEvidenceHost（源码目录）
    .deletingLastPathComponent()  // KanpanEvidenceHost（工程目录）
    .deletingLastPathComponent()  // Evidence
    .deletingLastPathComponent()  // 仓库根

  private static let fixtureURL = repoRoot
    .appendingPathComponent("KanpanChart/Tests/KanpanChartTests/Fixtures/snapshot.json")

  /// 读不到就返回 nil，由 `HostViewController` 在屏幕上写明原因——
  /// 空白一屏也「静止」，但那是假证据，必须能一眼看出来。
  static func load() -> Snapshot? {
    guard let d = try? Data(contentsOf: fixtureURL) else { return nil }
    return try? JSONDecoder().decode(Snapshot.self, from: d)
  }

  static var fixturePath: String { fixtureURL.path }
}

extension HostFixture.Snapshot {
  var series: BarSeries {
    BarSeries(
      symbol: symbol, interval: Interval(rawValue: interval) ?? .h1,
      t0: t0, step: step,
      open: open, high: high, low: low, close: close, volume: volume)
  }

  var oiSeries: OISeries { OISeries(t0: oi.t0, step: oi.step, values: oi.values) }

  var symbolInfo: SymbolInfo {
    SymbolInfo(
      symbol: symbol, base: meta.base, quote: meta.quote,
      pricePrecision: meta.pricePrecision, tickSize: meta.tickSize)
  }
}
