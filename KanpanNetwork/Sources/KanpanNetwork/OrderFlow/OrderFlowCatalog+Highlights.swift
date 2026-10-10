import Foundation
import KanpanCore

/// 要点引擎三个只读接口（PROJECT.md §79）：行情页上滑「盘口要点」、首页「异动」一列、首页「榜单」三张卡。
/// 和 `insights(base:)` 一样逐个 API 主机试；全失败给 `nil`（界面按「取不到」处理，不当成平静）。
extension OrderFlowCatalog {
  public static let highlightsPath = "/v1/market/orderflow/highlights"
  public static let highlightsBoardPath = "/v1/market/orderflow/highlights/board"
  public static let marketBoardPath = "/v1/market/board"
  /// 首页带上的自选最多多少只（和 kanpan-api `board::MAX_BASES` 同数）。
  public static let highlightsMaxBases = 60

  /// 一只的「盘口要点」。`base` 是去掉缩放前缀后的币名（`OrderFlowBase.normalize`）。
  public func highlights(base: String) async -> HighlightsPage? {
    guard OrderFlowBase.isValid(base) else { return nil }
    return await fetchJSON(Self.highlightsPath, [URLQueryItem(name: "base", value: base)]) { data in
      Self.parseHighlights(data, base: base)
    }
  }

  /// 首页「异动」：自选（最多 60 只，按给的顺序去重）∪ 服务端热点层。
  public func highlightsBoard(bases: [String]) async -> HighlightsBoard? {
    var seen = Set<String>()
    let list = bases.filter { OrderFlowBase.isValid($0) && seen.insert($0).inserted }.prefix(Self.highlightsMaxBases)
    return await fetchJSON(Self.highlightsBoardPath, [URLQueryItem(name: "bases", value: list.joined(separator: ","))]) { data in
      try? JSONDecoder().decode(HighlightsBoard.self, from: data)
    }
  }

  /// 首页「榜单」的一张卡。
  public func marketBoard(kind: MarketBoard.Kind, window: MarketBoard.Window) async -> MarketBoard? {
    await fetchJSON(Self.marketBoardPath, [URLQueryItem(name: "kind", value: kind.rawValue),
                                           URLQueryItem(name: "window", value: window.rawValue)]) { data in
      try? JSONDecoder().decode(MarketBoard.self, from: data)
    }
  }

  static func parseHighlights(_ data: Data, base: String) -> HighlightsPage? {
    guard let page = try? JSONDecoder().decode(HighlightsPage.self, from: data), page.base == base,
          page.generatedAtMs > 0, page.generatedAtMs <= Int64(Date().timeIntervalSince1970 * 1000) + 60_000 else { return nil }
    return page
  }

  private func fetchJSON<T>(_ path: String, _ query: [URLQueryItem], parse: (Data) -> T?) async -> T? {
    for host in route.apiHosts {
      guard !Task.isCancelled, var c = URLComponents(string: "https://\(host)"), c.host != nil, c.user == nil else { return nil }
      c.path = path
      c.queryItems = query
      guard let url = c.url else { continue }
      do {
        let reply = try await http.get(url, timeout: 12)
        guard !Task.isCancelled, (200..<300).contains(reply.status), let value = parse(reply.body) else { continue }
        return value
      } catch is CancellationError { return nil }
      catch { continue }
    }
    return nil
  }
}
