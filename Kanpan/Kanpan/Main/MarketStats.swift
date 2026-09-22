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
  ///
  /// 但「半天」是有上限的意思，不是「这一程只取一次」：审查 B-03 指出原来那条
  /// 一次性任务只在开图那一下跑，挂着不动的会话过了 12 小时之后市值还是半天前
  /// 那个供应量算的。现在由 `metaIfStale` 在持仓轮询里顺手续期。
  private static let metaTTL: TimeInterval = 12 * 3600

  /// 一次都问不通之后的冷却。供应量不是行情，没必要每 45 秒重试一轮；
  /// 但也不能一次失败就这一程都不再问（那又回到 B-03 的老样子）。
  private static let metaRetryDelay: TimeInterval = 300

  private var metaCache: [String: (row: SymbolMeta, at: Date)] = [:]
  private var metaFailedAt: [String: Date] = [:]
  private var metaTasks: [String: Task<SymbolMeta?, Never>] = [:]

  private let session: URLSession = {
    let c = URLSessionConfiguration.ephemeral
    c.timeoutIntervalForRequest = 8
    c.timeoutIntervalForResource = 12
    c.waitsForConnectivity = false
    return URLSession(configuration: c)
  }()

  // ---------------------------------------------------------------- 供应量

  /// 拿供应量。返回 `nil` **只**表示「一台都没问通」——调用方这时什么都不该动，
  /// 屏上那格保持原样。后端答了但说不认识这个品种（股指、贵金属都没有市值），
  /// 返回的是一行空的 `SymbolMeta`：那是权威的「没有」，调用方要据此把市值清掉
  /// （审查 B.8：`meta` 为空就清 `totalSupply`，不能留着上一个品种或半天前那个数）。
  func meta(symbol: String, base: String, hosts: [String]) async -> SymbolMeta? {
    let sym = InstrumentID.canonical(symbol)
    if let hit = metaCache[sym], Date().timeIntervalSince(hit.at) < Self.metaTTL { return hit.row }
    if let running = metaTasks[sym] { return await running.value }
    let task = Task<SymbolMeta?, Never> { [session] in
      for host in hosts {
        guard var parts = URLComponents(string: "https://\(host)/v1/market/meta") else { continue }
        // 一次只问这一个品种，不要整表：整表那条路不会把 `1000PEPE` 这种
        // 乘数合约换算回币本身，也认不出 USDC 计价的对，那两类会白白空着。
        parts.queryItems = [URLQueryItem(name: "symbols", value: InstrumentID(sym).symbol)]
        guard let url = parts.url else { continue }
        guard let body = try? await Self.get(url, session: session) else { continue }
        guard let table = Self.decodeMeta(body) else { continue }
        // 后端答了就以它为准：它说不认识这个币（股指、贵金属都没有市值），
        // 那就是没有，不必再问备用那台——空行也是答案，照样记进缓存。
        return table[InstrumentID(sym).symbol] ?? table[base.uppercased()] ?? SymbolMeta()
      }
      return nil
    }
    metaTasks[sym] = task
    let row = await task.value
    metaTasks[sym] = nil
    if let row {
      metaCache[sym] = (row, Date())
      metaFailedAt[sym] = nil
    } else {
      metaFailedAt[sym] = Date()
    }
    return row
  }

  /// 缓存过期了（或者上一轮失败且冷却也过了）才真去问一次；还新鲜就返回 `nil`，
  /// 调用方什么都不用做。持仓轮询每 45 秒叫一次这条，命中缓存时只是一次字典查找。
  func metaIfStale(symbol: String, base: String, hosts: [String]) async -> SymbolMeta? {
    let sym = InstrumentID.canonical(symbol)
    let now = Date()
    if let hit = metaCache[sym], now.timeIntervalSince(hit.at) < Self.metaTTL { return nil }
    if let failed = metaFailedAt[sym], now.timeIntervalSince(failed) < Self.metaRetryDelay { return nil }
    return await meta(symbol: sym, base: base, hosts: hosts)
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

  /// - Parameter source: 服务端按哪家的口径取（`ProviderCapabilities.openInterestSource`）。
  ///   nil = 这家没有持仓量，直接不问。
  func openInterest(symbol: String, source: String?, hosts: [String]) async -> OpenInterestStat? {
    guard let source else { return nil }
    for host in hosts {
      guard var parts = URLComponents(string: "https://\(host)/v1/market/open-interest") else { continue }
      parts.queryItems = [URLQueryItem(name: "symbol", value: InstrumentID(symbol).symbol),
                          URLQueryItem(name: "source", value: source)]
      guard let url = parts.url else { continue }
      guard let body = try? await Self.get(url, session: session) else { continue }
      guard let root = try? JSONSerialization.jsonObject(with: body) as? [String: Any],
            let row = root["data"] as? [String: Any] else { continue }
      return OpenInterestStat(symbol: InstrumentID.canonical((row["symbol"] as? String) ?? symbol),
                              openInterest: Self.num(row["openInterest"]),
                              openInterestValue: Self.num(row["openInterestValue"]),
                              timeMs: (row["time"] as? NSNumber)?.int64Value)
    }
    return nil
  }

  // ---------------------------------------------------------------- 顶栏「仓」那一格

  /// 「仓」这一格该显示哪个数。**只认美元名义**（审查 A-02）。
  ///
  /// 三种情形分得很清楚：
  /// * 整个请求没回来（`stat == nil`）→ 沿用上一口值。一次超时就把屏上的数字抹成
  ///   `--` 比留着上一口更像出错，而 45 秒后就会有下一轮。
  /// * 回来了、带着有效名义 → 用它。
  /// * 回来了、但没有名义（只有币本位数量，或者数是 0 / 非数）→ **清空**。
  ///   后端明确说「这个品种我给不出名义」，那就该是 `--`；退回币本位数量会让
  ///   同一格一会儿是钱一会儿是币，用户无从分辨。数量字段服务端仍然会发，
  ///   但顶栏永远不显示它。
  static func notionalOpenInterest(_ stat: OpenInterestStat?, previous: Double?) -> Double? {
    guard let stat else { return previous }
    guard let value = stat.openInterestValue, value.isFinite, value > 0 else { return nil }
    return value
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
