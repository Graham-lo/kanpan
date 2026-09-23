import Foundation
import KanpanCore
import KanpanNetwork

/// 一家交易所（一个提供者）的品种表（§4.1）。几十 KB，放 `Caches/` 24 小时；
/// 过期就重拉，拉不到就先用旧的（离线也能开品种页）。
///
/// **一家一个缓存文件**（`file(for:in:)`）：默认交易所的真身在根上（老用户盘上那份
/// 照旧能读），替身上游和别的交易所各在 `sources/<分区>/` 下一份，互不覆盖。
///
/// 三条规矩，都是审查里换来的：
/// * **非 `TRADING` 的行留在表里**，带着 `SymbolInfo.status`（B-06）。只留 `TRADING`
///   会把「已下架」和「根本不存在」压成同一件事：自选里那一行凭空消失，图表拿一张
///   占位表现出正常的样子。谁该灰、谁不该有实时价，由各页按这一档自己判。
/// * **一次刷新只跑一趟，而且校验和采纳都在那一趟里面**（B-05）。原来等在门口的调用方
///   拿的是「任务的原始结果」，校验（空表、全是下架的）只有发起那一个人做——于是
///   同一秒里进来的两个调用方，一个拿到验过的表，另一个拿到没验的。
/// * **用户明确点名一个表里没有的品种时，允许为他立刻重拉一次**（B-06），
///   两次之间至少隔 `onDemandDebounceMs`。新上市的合约就属于这种：表还没过期，
///   但它确实不在里面。
public actor SymbolCatalog {
  public static let ttlMs: Int64 = 24 * 3_600_000
  /// 「用户点名了一个表里没有的代号」这件事，最快隔多久才允许为它重拉一次整表。
  public static let onDemandDebounceMs: Int64 = 5 * 60_000
  /// 刚失败过就别接着打。手里已经有一份（哪怕旧）时，这段时间内的 `all()` 直接用它。
  /// 离线时 `all()` 会被每一次进页调用，没有这道闸就是一连串注定失败的请求。
  public static let retryAfterFailureMs: Int64 = 60_000

  private let provider: any MarketProvider
  private let paths: Paths
  private let log: FeedLog
  private var symbols: [SymbolInfo] = []
  private var loadedAtMs: Int64 = 0
  /// 6：非 TRADING 的行也留在表里，并带上 `status`（审查 B-06）。
  /// 必须跳一版——盘上那份 schema 5 的缓存里根本没有那些行，沿用它会让
  /// 「已下架」这一档在升级后的第一天里完全失效。
  /// 7：每行带上 `onboardDate`（P2.15「新」记号）。同理必须跳——schema 6 的缓存里
  /// 没有这一列，沿用它就是升级后一整天搜索和自选里一个「新」都不出。
  private static let schema = 7
  private var loadedSchema = 0
  private var failedAtMs: Int64 = 0
  private var lastOnDemandMs: Int64 = 0

  /// - Parameter paths: 缓存树的根。这一家的文件落在哪个分区由 `partition(for:in:)` 定。
  public init(provider: any MarketProvider, paths: Paths = .caches(), log: FeedLog = .silent) {
    self.provider = provider
    self.paths = Self.partition(for: provider.capabilities, in: paths)
    self.log = log
  }

  /// 这一家的品种表放哪棵树：默认交易所的真身放根上；替身上游按 `snapshotNamespace`、
  /// 别的交易所按 venue 各一棵（`Paths.source`，「清缓存」点得到名）。
  public static func partition(for caps: ProviderCapabilities, in root: Paths) -> Paths {
    if let ns = caps.snapshotNamespace { return root.source(ns) }
    if caps.venue == VenueRegistry.default.id { return root }
    return root.source(caps.venue)
  }

  /// 这一家的品种表缓存文件。
  public static func file(for caps: ProviderCapabilities, in root: Paths) -> URL {
    partition(for: caps, in: root).exchangeInfo
  }

  /// 这份表是哪家的。
  public nonisolated var capabilities: ProviderCapabilities { provider.capabilities }

  private var refreshTask: Task<[SymbolInfo], Never>?

  public func all(now: Int64 = Int64(Date().timeIntervalSince1970 * 1000)) async -> [SymbolInfo] {
    if let have = cached(now: now) { return have }
    // 刚失败过、手里又还有一份：先用手里那份，别接着打。
    if !symbols.isEmpty, now - failedAtMs < Self.retryAfterFailureMs, refreshTask == nil {
      return symbols
    }
    return await refresh(now: now)
  }

  /// 手里 / 盘上那份还能不能直接用。
  private func cached(now: Int64) -> [SymbolInfo]? {
    if !symbols.isEmpty, loadedSchema == Self.schema, now - loadedAtMs < Self.ttlMs { return symbols }
    if symbols.isEmpty, let disk = readDisk(), disk.schema == Self.schema, now - disk.at < Self.ttlMs,
       (try? Self.validate(disk.list)) != nil {
      adopt(disk.list, at: disk.at, schema: Self.schema)
      log("品种表走缓存 \(symbols.count) 个")
      return symbols
    }
    return nil
  }

  /// 单飞的一趟刷新。
  ///
  /// 关键在于**取数、校验、采纳、退回旧表全在同一个任务里面**：
  /// 所有等在门口的调用方 `await` 的是同一个任务的返回值，拿到的是同一份
  /// 已经验过、已经采纳的表。任务本身永不抛错（`Task<_, Never>`）——
  /// 「拉不到就用旧的」是这一层的职责，不该让每个调用方各自兜一遍。
  private func refresh(now: Int64) async -> [SymbolInfo] {
    if let refreshTask { return await refreshTask.value }
    let task = Task<[SymbolInfo], Never> { () -> [SymbolInfo] in
      do {
        let fresh = try await self.provider.instruments()
        try Self.validate(fresh)
        self.adopt(fresh, at: now, schema: Self.schema)
        self.failedAtMs = 0
        self.writeDisk(fresh, at: now)
        self.log("品种表刷新 \(fresh.count) 个")
        return fresh
      } catch {
        self.failedAtMs = now
        self.log("品种表拉取失败，用旧的：\(error)")
        return self.fallback()
      }
    }
    refreshTask = task
    let out = await task.value
    refreshTask = nil
    return out
  }

  /// 拉不到时退回盘上那份，**不看 TTL 也不看 schema**：离线状态下一张旧表远好过
  /// 一张空表（品种页空着等于这个 app 打不开）。但代次记成盘上那份的，
  /// 下一次 `all()` 仍然知道它该被刷新。
  private func fallback() -> [SymbolInfo] {
    guard symbols.isEmpty, let disk = readDisk(), (try? Self.validate(disk.list)) != nil else {
      return symbols
    }
    adopt(disk.list, at: disk.at, schema: disk.schema ?? 0)
    return symbols
  }

  private func adopt(_ list: [SymbolInfo], at ms: Int64, schema: Int) {
    symbols = list
    loadedAtMs = ms
    loadedSchema = schema
  }

  /// 一张表要能当品种表用，至少得有一行**能交易**。
  ///
  /// 只判「非空」不够：网关某一版的过滤条件写错时，回来的可能是一张几百行、
  /// 全是 `SETTLING` 的表。那张表解得开、条数也漂亮，可用户搜不到任何东西、
  /// 一张图也开不出来，还会被当成好表落盘、顶掉盘上原来那份可用的。
  static func validate(_ list: [SymbolInfo]) throws {
    guard !list.isEmpty else { throw FeedError.badResponse("品种表为空") }
    guard list.contains(where: { $0.status.hasLivePrice }) else {
      throw FeedError.badResponse("品种表里没有一个在交易的品种")
    }
  }

  public func find(_ symbol: String) async -> SymbolInfo? {
    let s = InstrumentID.canonical(symbol)
    return await all().first { $0.symbol == s }
  }

  /// 用户**明确点名**的查询：搜索框里敲了全名、从别处跳进一张图、点了一行自选。
  ///
  /// 和 `find` 的差别只有一条：表里没有这个代号时，允许为他立刻重拉一次整表
  /// （新上市的合约就是这种——表还没过期，但它确实不在里面）。这条路会被用户
  /// 连着按出来，所以两趟之间至少隔 `onDemandDebounceMs`；隔不够就老实回 `nil`，
  /// 不去打第二趟。
  public func lookup(_ symbol: String,
                     now: Int64 = Int64(Date().timeIntervalSince1970 * 1000)) async -> SymbolInfo? {
    let s = InstrumentID.canonical(symbol)
    if let hit = await all(now: now).first(where: { $0.symbol == s }) { return hit }
    guard now - lastOnDemandMs >= Self.onDemandDebounceMs else { return nil }
    lastOnDemandMs = now
    log("按需刷新品种表：表里没有 \(s)")
    return await refresh(now: now).first { $0.symbol == s }
  }

  /// 交易所拿这个代号答不出来：把它标成已下架，**不删**。
  ///
  /// 删掉的后果是自选里那一行凭空消失——用户会以为是自己手滑删了（审查 B-06）。
  /// 标记之后各页按 `status` 自己判：自选照旧列着但不装实时价，「全部合约」不再列它。
  ///
  /// 表里连这个代号都没有时**补一行占位**再标（审查复核项 4）。原来这儿直接 return，
  /// 于是一次明确的拒绝什么都没留下：那一行只能一直显示成「未知」，而「未知」
  /// （我们不知道）和「下架」（交易所明确说没有这个代号）是两件事，
  /// 这条唯一的写入口就是两者的分界线。占位行只有代号是真的，
  /// 精度留 0，界面按最后看到的价自己猜小数位。
  public func markDelisted(_ symbol: String) {
    let s = InstrumentID.canonical(symbol)
    // 手里根本还没有品种表（冷启动第一帧就开了一张图）：什么都不写。
    // 那会拿一张只有这一行的表顶掉盘上那份好表，下次冷启动连品种页都打不开。
    guard !symbols.isEmpty else { return }
    if let i = symbols.firstIndex(where: { $0.symbol == s }) {
      guard symbols[i].status != .delisted else { return }
      symbols[i].status = .delisted
    } else {
      symbols.append(.placeholder(symbol: s, status: .delisted))
    }
    log("品种表标记下架 \(s)")
    // 盘上那份也改掉，否则下次冷启动它又是「正常挂牌」。代次不动：这不是一次刷新。
    writeDisk(symbols, at: loadedAtMs)
  }

  /// 这个错误是不是「交易所不认这个代号」。
  ///
  /// 判据和 `RoutedMarketFeed.skippable` 同源，但更窄：那条要回答的是「要不要跳过
  /// 接着干」，这条要回答的是「能不能据此把一个品种标成下架」，判错的代价大得多，
  /// 所以只认三种确凿的答复——400 `-1121 Invalid symbol`、400 里带 `invalid symbol`
  /// 字样的、以及 404。限流（418/429）、地域拒绝（451）、超时（408）一个都不算：
  /// 它们拒的是整条线路，照那个判会把整张自选表一次标成下架。
  public static func rejectsSymbol(_ error: any Error) -> Bool {
    guard let e = error as? UpstreamError else { return false }
    guard !e.isRateLimited, !e.isGeoBlocked, e.status != 408 else { return false }
    if e.status == 404 { return true }
    guard e.status == 400 else { return false }
    if e.code == -1121 { return true }
    return (e.msg ?? "").lowercased().contains("invalid symbol")
  }

  // ------------------------------------------------------------------ 磁盘

  private struct Disk: Codable { var schema: Int?; var at: Int64; var list: [SymbolInfo] }

  private func readDisk() -> Disk? {
    guard let d = try? Data(contentsOf: paths.exchangeInfo) else { return nil }
    return try? JSONDecoder().decode(Disk.self, from: d)
  }

  private func writeDisk(_ list: [SymbolInfo], at: Int64) {
    try? paths.ensureRoot()
    guard let d = try? JSONEncoder().encode(Disk(schema: Self.schema, at: at, list: list)) else { return }
    try? d.write(to: paths.exchangeInfo, options: .atomic)
  }
}
