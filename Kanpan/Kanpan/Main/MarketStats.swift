import Foundation
import KanpanCore
import KanpanNetwork

/// 顶栏右侧那两格要的后端数据：供应量（算总市值）和持仓量。
///
/// 两条都是网关上的免鉴权只读接口（2026-09-18 规格）：
/// ```
/// GET /v1/market/meta?symbols=BTCUSDT,ETHUSDT
/// GET /v1/market/open-interest?symbol=BTCUSDT&source=binance
/// ```
/// 失败一律当「没有」——那一格显示 `--`，不弹提示、不在界面上报线路状态。

struct SymbolMeta: Sendable, Equatable {
  var totalSupply: Double?
  var circulatingSupply: Double?
  var maxSupply: Double?
  var rank: Int?
}

struct OpenInterestStat: Sendable, Equatable {
  var symbol: String
  /// 币本位数量。
  var openInterest: Double?
  /// 美元名义。币安不回这个，服务端用现价乘出来。
  var openInterestValue: Double?
  var timeMs: Int64?
}

actor MarketStatsClient {
  static let shared = MarketStatsClient()

  /// 供应量跟交易所无关，也基本不动——按品种取一次记半天，换线路不再请求。
  private static let metaTTL: TimeInterval = 12 * 3600

  private var metaCache: [String: (row: SymbolMeta, at: Date)] = [:]
  private var metaTasks: [String: Task<SymbolMeta?, Never>] = [:]

  private let session: URLSession = {
    let c = URLSessionConfiguration.ephemeral
    c.timeoutIntervalForRequest = 8
    c.timeoutIntervalForResource = 12
    c.waitsForConnectivity = false
    return URLSession(configuration: c)
  }()

  // ---------------------------------------------------------------- 供应量

  func meta(symbol: String, base: String, hosts: [String]) async -> SymbolMeta? {
    let sym = symbol.uppercased()
    if let hit = metaCache[sym], Date().timeIntervalSince(hit.at) < Self.metaTTL { return hit.row }
    if let running = metaTasks[sym] { return await running.value }
    let task = Task<SymbolMeta?, Never> { [session] in
      for host in hosts {
        guard var parts = URLComponents(string: "https://\(host)/v1/market/meta") else { continue }
        // 一次只问这一个品种，不要整表：整表那条路不会把 `1000PEPE` 这种
        // 乘数合约换算回币本身，也认不出 USDC 计价的对，那两类会白白空着。
        parts.queryItems = [URLQueryItem(name: "symbols", value: sym)]
        guard let url = parts.url else { continue }
        guard let body = try? await Self.get(url, session: session) else { continue }
        guard let table = Self.decodeMeta(body) else { continue }
        // 后端答了就以它为准：它说不认识这个币（股指、贵金属都没有市值），
        // 那就是没有，不必再问备用那台。
        return table[sym] ?? table[base.uppercased()]
      }
      return nil
    }
    metaTasks[sym] = task
    let row = await task.value
    metaTasks[sym] = nil
    if let row { metaCache[sym] = (row, Date()) }
    return row
  }

  private static func decodeMeta(_ body: Data) -> [String: SymbolMeta]? {
    guard let root = try? JSONSerialization.jsonObject(with: body) as? [String: Any],
          let data = root["data"] as? [String: Any] else { return nil }
    var out: [String: SymbolMeta] = [:]
    out.reserveCapacity(data.count)
    for (key, value) in data {
      guard let row = value as? [String: Any] else { continue }
      out[key.uppercased()] = SymbolMeta(
        totalSupply: num(row["totalSupply"]),
        circulatingSupply: num(row["circulatingSupply"]),
        maxSupply: num(row["maxSupply"]),
        rank: (row["rank"] as? NSNumber)?.intValue)
    }
    return out
  }

  // ---------------------------------------------------------------- 持仓量

  func openInterest(symbol: String, source: MarketSource, hosts: [String]) async -> OpenInterestStat? {
    for host in hosts {
      guard var parts = URLComponents(string: "https://\(host)/v1/market/open-interest") else { continue }
      parts.queryItems = [URLQueryItem(name: "symbol", value: symbol.uppercased()),
                          URLQueryItem(name: "source", value: source.rawValue)]
      guard let url = parts.url else { continue }
      guard let body = try? await Self.get(url, session: session) else { continue }
      guard let root = try? JSONSerialization.jsonObject(with: body) as? [String: Any],
            let row = root["data"] as? [String: Any] else { continue }
      return OpenInterestStat(symbol: (row["symbol"] as? String) ?? symbol.uppercased(),
                              openInterest: Self.num(row["openInterest"]),
                              openInterestValue: Self.num(row["openInterestValue"]),
                              timeMs: (row["time"] as? NSNumber)?.int64Value)
    }
    return nil
  }

  // ---------------------------------------------------------------- 杂务

  /// 非 200 当失败：契约里失败一律是非 200 + `{"error":"…"}`。
  private static func get(_ url: URL, session: URLSession) async throws -> Data {
    let (body, response) = try await session.data(from: url)
    guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
      throw URLError(.badServerResponse)
    }
    return body
  }

  /// 数字字段可能是数也可能是字符串，两种都收；`null` / 非数一律当缺失。
  ///
  /// 不用再单独挡 `NSNull`：它不是 `NSNumber`，`as? NSNumber` 这一步就已经把它
  /// 判掉了，多写一句反而是编译器认定「永远不成立」的死代码。
  private static func num(_ any: Any?) -> Double? {
    if let n = any as? NSNumber {
      let v = n.doubleValue
      return v.isFinite ? v : nil
    }
    if let s = any as? String, let v = Double(s), v.isFinite { return v }
    return nil
  }
}
