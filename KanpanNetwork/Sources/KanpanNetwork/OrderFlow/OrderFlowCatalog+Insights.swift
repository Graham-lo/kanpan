import Foundation
import KanpanCore

extension OrderFlowCatalog {
  public static let insightsPath = "/v1/market/orderflow/insights"

  /// Actual execution-price aggregates. A missing endpoint is unavailable, never a zero day.
  public func insights(base: String) async -> OrderFlowInsightsPage? {
    guard OrderFlowBase.isValid(base) else { return nil }
    for host in route.apiHosts {
      guard !Task.isCancelled, var c = URLComponents(string: "https://\(host)"), c.host != nil, c.user == nil else { return nil }
      c.path = Self.insightsPath
      c.queryItems = [URLQueryItem(name: "base", value: base)]
      guard let url = c.url else { continue }
      do {
        let reply = try await http.get(url, timeout: 12)
        guard !Task.isCancelled, (200..<300).contains(reply.status),
              let page = Self.parseInsights(reply.body, base: base) else { continue }
        return page
      } catch is CancellationError { return nil }
      catch { continue }
    }
    return nil
  }

  static func parseInsights(_ data: Data, base: String) -> OrderFlowInsightsPage? {
    guard let page = try? JSONDecoder().decode(OrderFlowInsightsPage.self, from: data),
          page.base == base, page.isValid, page.generatedAtMs <= Int64(Date().timeIntervalSince1970 * 1000) + 60_000 else { return nil }
    return page
  }
}
