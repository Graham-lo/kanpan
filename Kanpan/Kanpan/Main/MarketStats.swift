import Foundation
import KanpanCore
import KanpanNetwork
import Synchronization

/// 顶栏右侧那两格要的后端数据：供应量（算总市值）和持仓量。
///
/// 两条都是网关上的免鉴权只读接口（2026-09-18 规格）：
/// ```
/// GET /v1/market/meta?symbols=BTCUSDT,ETHUSDT
/// GET /v1/market/open-interest?symbol=BTCUSDT&source=binance
/// ```
/// 失败一律当「没有」——那一格显示 `--`，不弹提示、不在界面上报线路状态。
/// 这两条只在主机的 kanpan-api 上（备用机跑 metrics 模式，回 404），调用方传 `route.apiHosts`。

struct SymbolMeta: Sendable, Equatable {
  var totalSupply: Double?
  var circulatingSupply: Double?
  var maxSupply: Double?
  var rank: Int?
  /// 股票才有（后端从同一张上市页读出来、折成美元）：一致预期的未来十二个月净利润、
  /// 过去十二个月营收。顶栏「Fwd PE / P/S」那一格拿现乘的市值去除它们。
  var forwardEarnings: Double? = nil
  var revenue: Double? = nil
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

  /// 持仓量在「一换品种就有数」这件事上的保鲜期。持仓量本来就是分钟级统计，
  /// 一分钟内的那口足够代表「现在」；过了就当没有，换过去先空着等新的一口。
  static let openInterestFresh: TimeInterval = 60

  /// 换品种那一刻要**同步**读的那份：主线程上的 `switchTo` 不能等一次 actor 跳转，
  /// 否则顶栏还是会先画一帧「—」。所以供应量和持仓量各在锁里镜像一份，
  /// actor 里的写入顺手更新它；读的人不用 `await`。
  private struct Memo {
    var meta: [String: SymbolMeta] = [:]
    var openInterest: [String: (stat: OpenInterestStat, at: Date)] = [:]
  }
  private nonisolated let memo = Mutex(Memo())
  private var oiTasks: [String: Task<OpenInterestStat?, Never>] = [:]

  private static func oiKey(_ symbol: String, _ source: String) -> String {
    source + "|" + InstrumentID.canonical(symbol)
  }

  /// 已经问到过的供应量（没过 12 小时）。空行也算答案：股指、贵金属没有市值。
  nonisolated func cachedMeta(symbol: String) -> SymbolMeta? {
    let sym = InstrumentID.canonical(symbol)
    return memo.withLock { $0.meta[sym] }
  }

  /// 一分钟内问到过的持仓量。按交易所分开记：币安和 OKX 的口径不是一回事。
  nonisolated func cachedOpenInterest(symbol: String, source: String?,
                                      maxAge: TimeInterval = openInterestFresh) -> OpenInterestStat? {
    guard let source else { return nil }
    let key = Self.oiKey(symbol, source)
    return memo.withLock { box in
      guard let hit = box.openInterest[key], Date().timeIntervalSince(hit.at) < maxAge else { return nil }
      return hit.stat
    }
  }

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
      memo.withLock { $0.meta[sym] = row }
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

  /// 一次问一批（扫图时的前后邻居）：`symbols=A,B` 一个往返。已经有的、刚失败还在
  /// 冷却里的、正在问的都不再问。后端没回的那只就是「没有」，照样记一行空的。
  func prefetchMeta(symbols: [String], hosts: [String]) async {
    let now = Date()
    let want = Array(Set(symbols.map { InstrumentID.canonical($0) }.filter { sym in
      if let hit = metaCache[sym], now.timeIntervalSince(hit.at) < Self.metaTTL { return false }
      if let failed = metaFailedAt[sym], now.timeIntervalSince(failed) < Self.metaRetryDelay { return false }
      return metaTasks[sym] == nil
    })).sorted()
    guard !want.isEmpty else { return }
    let names = want.map { InstrumentID($0).symbol }.joined(separator: ",")
    for host in hosts {
      guard var parts = URLComponents(string: "https://\(host)/v1/market/meta") else { continue }
      parts.queryItems = [URLQueryItem(name: "symbols", value: names)]
      guard let url = parts.url, let body = try? await Self.get(url, session: session),
            let table = Self.decodeMeta(body) else { continue }
      let at = Date()
      for sym in want {
        let row = table[InstrumentID(sym).symbol] ?? SymbolMeta()
        metaCache[sym] = (row, at)
        metaFailedAt[sym] = nil
        memo.withLock { $0.meta[sym] = row }
      }
      return
    }
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
        rank: (row["rank"] as? NSNumber)?.intValue,
        forwardEarnings: num(row["forwardEarnings"]),
        revenue: num(row["revenue"]))
    }
    return out
  }

  // ---------------------------------------------------------------- 持仓量

  /// - Parameter source: 服务端按哪家的口径取（`ProviderCapabilities.openInterestSource`）。
  ///   nil = 这家没有持仓量，直接不问。
  /// - Parameter maxAge: 缓存里这么新的就直接用，不再问（0 = 一定去问）。
  ///   同一只同一家正在问的，后到的人等同一个结果，不再多发一次。
  func openInterest(symbol: String, source: String?, hosts: [String],
                    maxAge: TimeInterval = 0) async -> OpenInterestStat? {
    guard let source else { return nil }
    let key = Self.oiKey(symbol, source)
    if maxAge > 0, let hit = cachedOpenInterest(symbol: symbol, source: source, maxAge: maxAge) { return hit }
    if let running = oiTasks[key] { return await running.value }
    let task = Task<OpenInterestStat?, Never> { [session] in
      await Self.fetchOpenInterest(symbol: symbol, source: source, hosts: hosts, session: session)
    }
    oiTasks[key] = task
    let stat = await task.value
    oiTasks[key] = nil
    if let stat { memo.withLock { $0.openInterest[key] = (stat, Date()) } }
    return stat
  }

  /// 扫图时的前后邻居：没有一分钟内那口的才去问，几只并发出去。
  func prefetchOpenInterest(symbols: [String], source: String?, hosts: [String]) async {
    guard let source else { return }
    await withTaskGroup(of: Void.self) { group in
      for sym in Set(symbols.map { InstrumentID.canonical($0) })
      where cachedOpenInterest(symbol: sym, source: source) == nil {
        group.addTask { _ = await self.openInterest(symbol: sym, source: source, hosts: hosts,
                                                    maxAge: Self.openInterestFresh) }
      }
    }
  }

  private static func fetchOpenInterest(symbol: String, source: String, hosts: [String],
                                        session: URLSession) async -> OpenInterestStat? {
    for host in hosts {
      guard var parts = URLComponents(string: "https://\(host)/v1/market/open-interest") else { continue }
      parts.queryItems = [URLQueryItem(name: "symbol", value: InstrumentID(symbol).symbol),
                          URLQueryItem(name: "source", value: source)]
      guard let url = parts.url else { continue }
      guard let body = try? await get(url, session: session) else { continue }
      guard let root = try? JSONSerialization.jsonObject(with: body) as? [String: Any],
            let row = root["data"] as? [String: Any] else { continue }
      return OpenInterestStat(symbol: InstrumentID.canonical((row["symbol"] as? String) ?? symbol),
                              openInterest: num(row["openInterest"]),
                              openInterestValue: num(row["openInterestValue"]),
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
