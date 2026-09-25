import Foundation

/// 行情失败的现场记录，正式包也开着。
///
/// 2026-09-25 用户报「BTC 5m 跳空、ONDO 只剩一根，跑一会又好了」，手机上一行日志都没有
/// （正式包的 `MarketModel.log` 是静音的），只能在模拟器上猜。这里只留「出事」那几类行——
/// 首屏 / 补缺失败、上游封禁限流、自愈、线路巡检——最近 200 行，落在 Caches 里一个小文件，
/// 下次再出现就有时间线可看。取法：Xcode「Devices and Simulators」→ 下载 app 容器，
/// 或 `xcrun devicectl device copy from --domain-type appDataContainer
/// --domain-identifier <bundle id> --source Library/Caches/feed-failures.log`。
///
/// 只按关键词过滤，不读启动环境（审查 C-02）；一分钟也就零星几行，整文件重写足够。
final class FeedFailureTrail: @unchecked Sendable {
  static let shared = FeedFailureTrail()

  private static let keywords = ["失败", "封禁", "限流", "自愈", "巡检", "补缺", "断线"]
  private static let capacity = 200
  private static let stampStyle = Date.ISO8601FormatStyle(includingFractionalSeconds: true, timeZone: .current)

  let url = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
    .appendingPathComponent("feed-failures.log")
  private let queue = DispatchQueue(label: "kanpan.feed-failure-trail", qos: .utility)
  /// 只在 `queue` 上读写。第一次写的时候从文件接上，跨启动连续。
  private var lines: [String]?

  func note(_ line: String) {
    guard Self.keywords.contains(where: { line.contains($0) }) else { return }
    let entry = "\(Date().formatted(Self.stampStyle)) \(line)"
    queue.async { [self] in
      var all = lines ?? ((try? String(contentsOf: url, encoding: .utf8))?
        .split(separator: "\n").map(String.init) ?? [])
      all.append(entry)
      if all.count > Self.capacity { all.removeFirst(all.count - Self.capacity) }
      lines = all
      try? (all.joined(separator: "\n") + "\n").write(to: url, atomically: true, encoding: .utf8)
    }
  }
}
