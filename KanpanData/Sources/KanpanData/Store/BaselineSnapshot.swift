import Foundation

/// 上次算涨跌幅用的那批「当日开盘价」。
///
/// 非 24 小时口径（上海 0 点 / UTC 0 点）的涨跌幅不是交易所直接给的数，得自己
/// 拿那一刻的 1 小时 K 线开盘价来算。一个品种一发请求，几十个自选就是几十次往返：
/// 冷启动时价格早就从 `QuoteSnapshot` 摆上了，涨跌幅那一列还在一格格地填——
/// 用户看到的「涨跌幅每次都是最慢出来的」就是这个。
///
/// 开盘价在同一档边界里是定值，所以存下来就能直接用。读回来要对边界：只要
/// 还是当前这一档，它仍然是交易所当时真给过的开盘价，不是编的；跨到下一天
/// 整份作废，老老实实重新取。
public enum BaselineSnapshot {
  /// 和 `QuoteSnapshot` 一个量级：自选几十个，留够余量即可。
  public static let maxEntries = 256

  private struct File: Codable {
    var boundary: Int64
    var opens: [String: Double]
  }

  public static func write(boundary: Int64, opens: [String: Double], to url: URL) {
    let kept = opens.filter { !$0.key.isEmpty && $0.value.isFinite && $0.value > 0 }
    let rows = Dictionary(uniqueKeysWithValues: kept.sorted { $0.key < $1.key }.prefix(maxEntries).map { ($0.key, $0.value) })
    guard !rows.isEmpty else { remove(url); return }
    do {
      try FileManager.default.createDirectory(at: url.deletingLastPathComponent(),
                                              withIntermediateDirectories: true)
      let file = File(boundary: boundary, opens: rows)
      try JSONEncoder().encode(file).write(to: url, options: .atomic)
    } catch {
      // 缓存写失败不影响使用，下次再写。
    }
  }

  /// 边界对不上就当没有——宁可重新取，也不能拿昨天的开盘价算今天的涨跌幅。
  public static func read(_ url: URL, boundary: Int64) -> [String: Double] {
    guard let data = try? Data(contentsOf: url),
          let file = try? JSONDecoder().decode(File.self, from: data),
          file.boundary == boundary else { return [:] }
    return file.opens.filter { !$0.key.isEmpty && $0.value.isFinite && $0.value > 0 }
  }

  public static func remove(_ url: URL) { try? FileManager.default.removeItem(at: url) }
}
