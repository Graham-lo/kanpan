import Foundation
import KanpanCore
import KanpanData
import KanpanNetwork

/// 板块页「5 日」那一档要的日线收盘。
///
/// 服务端每天收盘后采一次，这一边只管取回来：
/// ```
/// GET https://<网关>/v1/market/sector-history
/// → {"data":{"asof":"2026-09-18","symbols":{"BTCUSDT":{"c5":…,"c20":…}}}}
/// ```
/// 走共享的后端取数口（`RouteResolver.backend`，主、备两台按顺序试，失败按类记日志），
/// 不再自己建 `URLSession`、自己拼名单。解不开或全都不成就**什么也不做**——
/// 界面上不出现取数状态、不出现更新时间、不出现数据来源
/// （`kanpan-no-engineering-status-fields`）。没历史时页面自己会退回只有「今日」的样子。
///
/// 节奏：进页取一趟，之后每小时一趟（日线一天才换一次，秒级刷新毫无意义）。
/// 回来的 `asof` 和手上这份一样就原地不动，连 `history` 都不赋值——否则整页会为一份
/// 一模一样的数据重算一遍聚合。**取回来的那份和磁盘上那份一样要过 `apply` 那道闸**：
/// 服务端算不出今天那份时会拿上一份垫着（`sector_history.rs` 的 `stale()`），
/// 旧收盘配现价算出来的收益挂着「5 日」的名字却不是 5 日；拦下来之后页面就是
/// 「没有历史」那一套——那颗药丸整行不出现，停在 5 日的人就地退回今日。
/// 取回来的原样存进 Caches，下次进页先拿它顶上，
/// 不让「5 日」那颗药丸在每次冷启动时先消失一秒再出现。
///
/// 缺字段就是**没有**，不是 0：`last / 0` 是 +∞，一个 +∞ 能把整段中位数带走。
@MainActor @Observable final class SectorHistoryFeed {
  /// 当前这份日线收盘。取不到就是 `.empty`。
  private(set) var history: SectorHistory = .empty

  @ObservationIgnored private var backend: BackendClient?
  @ObservationIgnored private var visible = false
  @ObservationIgnored private var job: Task<Void, Never>?
  @ObservationIgnored private var lastPull: Date?
  @ObservationIgnored private var loadedCache = false

  /// 两趟之间隔多久。日线一天换一次，一小时问一趟已经比需要的勤快。
  private static let refreshSeconds: TimeInterval = 3600
  /// 循环的步长。取失败了下一步就再试一次，不必等满一小时。
  private static let tickSeconds: TimeInterval = 600

  // MARK: 外部接线

  /// 后端取数口（`RouteResolver.backend`）。
  func configure(backend: BackendClient) {
    guard backend != self.backend else { return }
    self.backend = backend
    // 换了线路就当手上这份过期，下一拍立刻重取。
    lastPull = nil
    restart()
  }

  /// 板块页在不在屏幕上。
  func setVisible(_ on: Bool) {
    guard on != visible else { return }
    visible = on
    restart()
  }

  // MARK: 取数

  private func restart() {
    job?.cancel()
    job = nil
    guard visible, let backend, !backend.hosts.isEmpty else { return }
    job = Task { [weak self] in await self?.run() }
  }

  private func run() async {
    loadCache()
    while !Task.isCancelled {
      if stale { await pull() }
      try? await Task.sleep(for: .seconds(Self.tickSeconds))
    }
  }

  private var stale: Bool {
    guard let last = lastPull else { return true }
    return Date().timeIntervalSince(last) >= Self.refreshSeconds
  }

  private func pull() async {
    guard let backend, let body = try? await backend.get(Self.path, timeout: 8) else { return }
    guard let parsed = Self.decode(body) else { return }
    lastPull = Date()
    apply(parsed)
    Self.writeCache(body)
  }

  /// 网络和磁盘两条路都从这儿进，一道闸：过期的不要（服务端算不出今天那份时会拿
  /// 上一份垫着，老基线配现价算出来的不是「5 日」），同一天的原样那份也不要
  /// （`history` 是被观察的，赋一次整页就重算一次聚合、重排一遍列表）。
  /// 口径在 Core 的 `SectorHistory.accepts`，那儿有用例钉着。
  private func apply(_ next: SectorHistory) {
    guard history.accepts(next) else { return }
    history = next
  }

  static let path = "/v1/market/sector-history"

  // MARK: 解包

  /// `{"data":{"asof":…,"symbols":{…}}}` → 以**大写 base** 为键的收盘表。
  ///
  /// 服务端给的是合约名（`BTCUSDT`），板块这一路只认 base。同一个币可能有好几张
  /// 合约（`1000BONKUSDT` 和 `1000BONKUSDC` 都在表里），按 `SectorQuotePreference`
  /// 的计价币档次留一张——和 `SectorFeed` 挑行情用的是同一把尺子，不然「5 日」用的
  /// 收盘和「现价」来自两张不同的合约。
  static func decode(_ body: Data) -> SectorHistory? {
    guard let root = try? JSONSerialization.jsonObject(with: body) as? [String: Any],
          let data = root["data"] as? [String: Any],
          let asof = data["asof"] as? String, SectorHistory.day(asof) != nil,
          let symbols = data["symbols"] as? [String: Any] else { return nil }
    var closes: [String: SectorCloses] = [:]
    var rank: [String: Int] = [:]
    closes.reserveCapacity(symbols.count)
    for (raw, any) in symbols {
      guard let row = any as? [String: Any] else { continue }
      let symbol = raw.uppercased()
      let split = Self.split(symbol)
      if let old = rank[split.base], old <= split.rank { continue }
      let c5 = num(row["c5"])
      let c20 = num(row["c20"])
      guard c5 != nil || c20 != nil else { continue }
      rank[split.base] = split.rank
      closes[split.base] = SectorCloses(c5: c5, c20: c20)
    }
    guard !closes.isEmpty else { return nil }
    return SectorHistory(asof: asof, closes: closes)
  }

  /// `BTCUSDT` → （`BTC`，计价币档次）。认不出计价币就整条当 base，档次垫底。
  private static func split(_ symbol: String) -> (base: String, rank: Int) {
    QuoteAssets.tradableSplit(symbol)
  }

  /// 数可能是数也可能是字符串。`null`、非数、非正数一律当**缺失**
  /// ——缺一档只是这个币的这段窗口没有，不是 0。
  private static func num(_ any: Any?) -> Double? {
    let value: Double? = if let n = any as? NSNumber { n.doubleValue }
      else if let s = any as? String { Double(s) } else { nil }
    guard let value, value.isFinite, value > 0 else { return nil }
    return value
  }

  // MARK: 磁盘

  /// Caches 里那一份。取回来的原样存，下次进页先顶上。
  ///
  /// 路径问 `Paths` 要，不自己拼 `Library/Caches`：自己拼出来的那一份直接挂在
  /// Caches 根上，既躲开了「清缓存」（清的是 `Paths` 指的那几处），也躲开了测试档
  /// 隔离（`KANPAN_TEST_PROFILE` 那棵子树）。板块历史是**取得回来**的数据，
  /// 它本来就该跟别的行情缓存一起被清。
  private nonisolated static var cacheURL: URL { Paths.caches().sectorHistory }

  /// 老位置（`Library/Caches/sector-history.json`）上那一份，谁也管不着它。
  /// 搬家不必留情：丢的只是一次板块历史，进页重新取一趟就回来了。
  private nonisolated static func dropLegacyCache() {
    guard let base = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first else { return }
    try? FileManager.default.removeItem(at: base.appendingPathComponent("sector-history.json"))
  }

  private func loadCache() {
    guard !loadedCache, history.isEmpty else { return }
    loadedCache = true
    Self.dropLegacyCache()
    guard let body = try? Data(contentsOf: Self.cacheURL),
          let parsed = Self.decode(body) else { return }
    apply(parsed)
  }

  private nonisolated static func writeCache(_ body: Data) {
    let paths = Paths.caches()
    try? paths.ensureRoot()
    try? body.write(to: paths.sectorHistory, options: .atomic)
  }
}
