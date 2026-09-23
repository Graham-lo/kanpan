import Foundation
import KanpanCore

/// 小组件刷新那一拍自己补的价。
///
/// app 在前台时每刷到行情就写快照、并叫系统重载小组件，那时快照是新的，这儿什么都不取；
/// app 不在前台，系统按 15 分钟来刷，这时快照是旧的，就照快照里写的取数方式
/// （`WidgetSnapshot.Refresh`，app 按用户选的线路定：直连打币安、网关打网关）取一口：
/// 小号四只各一口 24 小时行情，中号那一只再带一段 1 小时收盘价。
/// 每一口都有超时，取不到就沿用快照——宁可旧，不画空。
enum LiveQuotes {
  /// 快照比这更新就不取：app 刚写过。
  static let freshSeconds: Double = 120
  static let timeout: Double = 6

  static func refresh(_ snapshot: WidgetSnapshot, symbols: [String], sparkline: String? = nil,
                      now: Date = Date()) async -> WidgetSnapshot {
    let age = now.timeIntervalSince1970 - Double(snapshot.updatedAt) / 1000
    guard age > freshSeconds, let plan = snapshot.refresh, !plan.hosts.isEmpty else { return snapshot }
    var next = snapshot
    await withTaskGroup(of: (String, Ticker24h?, [Double]?).self) { group in
      for symbol in symbols where snapshot.quotes[symbol] != nil && InstrumentID(symbol).marketKey == plan.market {
        group.addTask {
          async let ticker = fetchTicker(plan, symbol: symbol)
          async let closes: [Double]? = symbol == sparkline ? fetchCloses(plan, symbol: symbol) : nil
          return (symbol, await ticker, await closes)
        }
      }
      for await (symbol, ticker, closes) in group {
        guard let ticker else { continue }
        next.apply(symbol: symbol, price: ticker.price, rollingChange: ticker.change, timeMs: ticker.timeMs, closes: closes)
      }
    }
    return next
  }

  struct Ticker24h: Sendable { var price: Double; var change: Double?; var timeMs: Int64 }

  private static func session() -> URLSession {
    let config = URLSessionConfiguration.ephemeral
    config.timeoutIntervalForRequest = timeout
    config.timeoutIntervalForResource = timeout
    return URLSession(configuration: config)
  }

  /// 按顺序试候选主机，第一台回 200 的就用。
  private static func get(_ urls: [URL]) async -> Data? {
    let session = session()
    defer { session.finishTasksAndInvalidate() }
    for url in urls {
      guard let (data, response) = try? await session.data(from: url),
            (response as? HTTPURLResponse)?.statusCode == 200 else { continue }
      return data
    }
    return nil
  }

  static func fetchTicker(_ plan: WidgetSnapshot.Refresh, symbol: String) async -> Ticker24h? {
    let raw = InstrumentID(symbol).symbol
    guard let data = await get(plan.hosts.compactMap { plan.tickerURL(host: $0, symbol: raw) }),
          let parsed = plan.parseTicker(data) else { return nil }
    return Ticker24h(price: parsed.price, change: parsed.change,
                     timeMs: parsed.timeMs ?? Int64(Date().timeIntervalSince1970 * 1000))
  }

  static func fetchCloses(_ plan: WidgetSnapshot.Refresh, symbol: String) async -> [Double]? {
    let raw = InstrumentID(symbol).symbol
    guard let data = await get(plan.hosts.compactMap { plan.closesURL(host: $0, symbol: raw) }) else { return nil }
    return plan.parseCloses(data)
  }
}
