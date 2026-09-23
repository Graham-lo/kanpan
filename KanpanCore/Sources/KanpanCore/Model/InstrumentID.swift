import Foundation

/// Stable identity, independent of the route used to retrieve a market.
/// Bare identifiers are accepted only for backwards compatibility with pre-v2 archives.
public struct InstrumentID: Hashable, Codable, Sendable, CustomStringConvertible {
  public let venue: String
  public let market: String
  public let symbol: String
  public var key: String { "\(venue)/\(market)/\(symbol)" }
  public var description: String { key }
  public var marketKey: String { "\(venue)/\(market)" }
  /// 给人看的代号：交易所代号里的 `-` 分隔（`BTC-USD`）显示成 `BTC/USD`，
  /// 没有分隔的（`BTCUSDT`）原样。存储、请求、文件名一律用 `symbol`，不用它。
  public var display: String { symbol.replacingOccurrences(of: "-", with: "/") }

  public init(venue: String, market: String, symbol: String) {
    self.venue = venue.lowercased()
    self.market = market.lowercased()
    self.symbol = symbol.uppercased()
  }

  public init(_ legacyOrKey: String) {
    let parts = legacyOrKey.trimmingCharacters(in: .whitespacesAndNewlines).split(separator: "/", omittingEmptySubsequences: false)
    if parts.count == 3 {
      self.init(venue: String(parts[0]), market: String(parts[1]), symbol: String(parts[2]))
    } else {
      self.init(venue: "binance", market: "usd_m", symbol: legacyOrKey.trimmingCharacters(in: .whitespacesAndNewlines))
    }
  }

  public var isValid: Bool {
    func component(_ s: String, extra: String) -> Bool {
      !s.isEmpty && s.count <= 64 && s.utf8.allSatisfy {
        (48...57).contains($0) || (65...90).contains($0) || (97...122).contains($0) || extra.utf8.contains($0)
      }
    }
    return component(venue, extra: "_") && component(market, extra: "_") && component(symbol, extra: "-_")
  }

  public static func canonical(_ value: String) -> String {
    value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "" : InstrumentID(value).key
  }

  /// Canonical keys win over an equivalent legacy alias; unrelated markets never collide.
  public static func migrate<Value>(_ values: [String: Value]) -> [String: Value] {
    var output: [String: Value] = [:]
    for key in values.keys.sorted(by: { ($0.contains("/") ? 1 : 0, $0) < ($1.contains("/") ? 1 : 0, $1) }) {
      output[canonical(key)] = values[key]
    }
    return output
  }
}
