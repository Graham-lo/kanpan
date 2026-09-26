import Foundation

/// 桌面上的中号小组件此刻在画哪几只的走势。
///
/// 折线只有中号（`kanpan.symbol`）画，而且只画用户在小组件上选的那一只；小组件选了谁只有
/// 扩展知道（意图类型只在扩展里）。所以由扩展在每次排时间线时把「这一格画的是谁」记进
/// App Group 里的这个小文件，app 只给这几只取收盘价（整机压测 2026-09-26：原来前台每 15 分钟
/// 给**全部**自选各取一段，几百只自选就是几百发请求，弱网下和首屏抢带宽，快照也跟着变胖）。
///
/// 一只一个「最后一次被画」的时刻；两天没再被画的（小组件删了、换了品种）自然过期。
/// 同一个文件同步进 app 与扩展两个 target。
enum WidgetSparklineWants {
  static let fileName = "widget-sparklines.json"
  static let lifetime: TimeInterval = 2 * 24 * 3600

  static func url(in container: URL) -> URL { container.appendingPathComponent(fileName) }

  /// 扩展：这一格正在画 `symbol` 的走势。
  static func note(_ symbol: String, in container: URL, now: Date = Date()) {
    var table = read(in: container)
    let nowMs = Int64(now.timeIntervalSince1970 * 1000)
    table = prune(table, now: now)
    // 同一只一分钟内反复记没有意义，少写一次盘。
    if let last = table[symbol], nowMs - last < 60_000 { return }
    table[symbol] = nowMs
    guard let data = try? JSONEncoder().encode(table) else { return }
    try? data.write(to: url(in: container), options: .atomic)
  }

  /// app：眼下有哪几只要折线。
  static func symbols(in container: URL, now: Date = Date()) -> Set<String> {
    Set(prune(read(in: container), now: now).keys)
  }

  private static func read(in container: URL) -> [String: Int64] {
    guard let data = try? Data(contentsOf: url(in: container)),
          let table = try? JSONDecoder().decode([String: Int64].self, from: data) else { return [:] }
    return table
  }

  private static func prune(_ table: [String: Int64], now: Date) -> [String: Int64] {
    let floor = Int64((now.timeIntervalSince1970 - lifetime) * 1000)
    return table.filter { $0.value >= floor }
  }
}
