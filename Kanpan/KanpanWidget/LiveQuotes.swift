import Foundation
import KanpanCore

/// 小组件刷新那一拍自己补的价。
///
/// app 在前台时每刷到行情就写快照、并叫系统重载小组件，那时快照是新的，这儿什么都不取；
/// app 不在前台，系统按 15 分钟来刷，这时快照是旧的，就照 app 当前那台 REST 主机取一口：
/// 小号四只各一口 24 小时行情，中号那一只再带一段 1 小时收盘价。
/// 每一口都有超时，取不到就沿用快照——宁可旧，不画空。
enum LiveQuotes {
  /// 快照比这更新就不取：app 刚写过。
  static let freshSeconds: Double = 120
  static let timeout: Double = 6

  static func refresh(_ snapshot: WidgetSnapshot, symbols: [String], sparkline: String? = nil,
                      now: Date = Date()) async -> WidgetSnapshot {
    let age = now.timeIntervalSince1970 - Double(snapshot.updatedAt) / 1000
    guard age > freshSeconds, !snapshot.fapiHost.isEmpty else { return snapshot }
    var next = snapshot
    await withTaskGroup(of: (String, Ticker24h?, [Double]?).self) { group in
      for symbol in symbols where snapshot.quotes[symbol] != nil
        && snapshot.hostMarket.map({ InstrumentID(symbol).marketKey == $0 }) ?? true {
        group.addTask {
          async let ticker = fetchTicker(host: snapshot.fapiHost, symbol: symbol)
          async let closes: [Double]? = symbol == sparkline ? fetchCloses(host: snapshot.fapiHost, symbol: symbol) : nil
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

  static func fetchTicker(host: String, symbol: String) async -> Ticker24h? {
    guard let url = URL(string: "https://\(host)/fapi/v1/ticker/24hr?symbol=\(InstrumentID(symbol).symbol)"),
          let (data, response) = try? await session().data(from: url),
          (response as? HTTPURLResponse)?.statusCode == 200,
          let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
          let price = (object["lastPrice"] as? String).flatMap(Double.init) else { return nil }
    let change = (object["priceChangePercent"] as? String).flatMap(Double.init)
    let time = (object["closeTime"] as? NSNumber)?.int64Value ?? Int64(Date().timeIntervalSince1970 * 1000)
    return Ticker24h(price: price, change: change, timeMs: time)
  }

  static func fetchCloses(host: String, symbol: String) async -> [Double]? {
    guard let url = URL(string: "https://\(host)/fapi/v1/klines?symbol=\(InstrumentID(symbol).symbol)&interval=1h&limit=\(WidgetSnapshot.sparkBars)"),
          let (data, response) = try? await session().data(from: url),
          (response as? HTTPURLResponse)?.statusCode == 200,
          let rows = try? JSONSerialization.jsonObject(with: data) as? [[Any]] else { return nil }
    let closes = rows.compactMap { row in row.count > 4 ? (row[4] as? String).flatMap(Double.init) : nil }
    return closes.count >= 2 ? closes : nil
  }
}
