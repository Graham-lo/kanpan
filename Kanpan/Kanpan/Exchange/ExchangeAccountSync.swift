import Foundation
import KanpanCore

/// 把一个交易所账户的成交拉回来、拼成回合、把有变化的回合交出去。自动复盘的发动机。
///
/// 用户 2026-09-27 定的：只读 API「不是显示在上面，而是做成自动复盘，直接帮用户处理」——
/// 用户不需要按「同步」，接入之后 app 在前台时顺手拉（`pullIfDue()`），拼好的回合经 `onRounds`
/// 交给复盘那一层（下一阶段接：写成 `kind:"trade"` 的复盘记录，见 `docs/交易复盘-协议-2026-09-27.md` §3）。
///
/// 节奏：
/// - 第一次接入往前回溯 90 天；之后从上次的水位往前留 1 小时重叠增量拉（重叠部分靠去重吃掉）。
/// - 前台 5 分钟最多拉一次（按「尝试」计，失败也算），切前后台、来回点页面不会反复打交易所。
/// - 断网就安静地放弃这一轮，不提示、不重试，等下一次 `pullIfDue()`。
/// - 交出去是「至少一次」：先回调、再落盘水位。回调之后 app 被杀，下次会把同一批回合再交一遍，
///   回合 id 稳定（协议 §2.2），下游按 id 覆盖即可。
///
/// 这一阶段**不接** `AppLifecycle`、不接任何界面；接线在后续阶段。
actor ExchangeAccountSync {
  enum Outcome: Equatable, Sendable {
    /// 还没接入。
    case notConnected
    /// 5 分钟内拉过，或者上一轮还没完。
    case skipped
    /// 断网，这一轮安静放弃。
    case offline
    /// 拉成了；带着这一轮交出去的回合数。
    case pulled(rounds: Int)
    /// 其它失败，带着界面上那一句。
    case failed(message: String)
  }

  /// 同一个 id 规则里的「账户标签」：一台手机一个交易所只接一把 Key（协议 §2.2）。
  static let accountTag = "primary"
  static let throttleMs: Int64 = 5 * 60_000
  static let backfillMs: Int64 = 90 * 86_400_000
  static let overlapMs: Int64 = 3_600_000

  typealias ProviderFactory = @Sendable (ExchangeCredentials) -> (any ExchangeAccountProvider)?
  typealias RoundsSink = @Sendable ([TradeRound]) async -> Void

  let venue: String
  let market: String
  private let store: ExchangeCredentialStore
  private let stateURL: URL
  private let clock: @Sendable () -> Int64
  private let makeProvider: ProviderFactory
  private let onRounds: RoundsSink
  private var inFlight = false

  init(venue: String, market: String,
       store: ExchangeCredentialStore,
       stateURL: URL,
       clock: @escaping @Sendable () -> Int64 = { Int64(Date().timeIntervalSince1970 * 1000) },
       makeProvider: @escaping ProviderFactory,
       onRounds: @escaping RoundsSink) {
    self.venue = venue; self.market = market
    self.store = store; self.stateURL = stateURL; self.clock = clock
    self.makeProvider = makeProvider; self.onRounds = onRounds
  }

  /// 正式装配：按登记表造 provider，状态放 Application Support。
  init(venue: ExchangeAccountRegistry.Venue, onRounds: @escaping RoundsSink) {
    self.init(venue: venue.venue, market: venue.market,
              store: ExchangeCredentialStore(venue: venue.venue, market: venue.market),
              stateURL: Self.defaultStateURL(venue: venue.venue, market: venue.market),
              makeProvider: { ExchangeAccountRegistry.provider(for: venue, credentials: $0) },
              onRounds: onRounds)
  }

  /// 拼回合的中间状态（开着的账、最近结束的回合、见过的成交）。只在本机，不同步、不导出；
  /// 丢了也不要紧，下次从回溯起点重拼，回合 id 不变。
  static func defaultStateURL(venue: String, market: String) -> URL {
    let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
      ?? URL(fileURLWithPath: NSTemporaryDirectory())
    return base.appendingPathComponent("kanpan", isDirectory: true)
      .appendingPathComponent("exchange-\(venue)-\(market).json")
  }

  // MARK: - 接入 / 断开

  /// 接入一把 Key：先过只读校验，过了才写 Keychain。校验不过（有交易 / 提现权限、Key 不对、网络不通）
  /// 什么都不写，原样抛出 `ExchangeAccountError`。
  @discardableResult
  func connect(apiKey: String, secret: String) async throws -> ExchangeCredentialStore.Status {
    let credentials = ExchangeCredentials(apiKey: apiKey, secret: secret).trimmed
    guard !credentials.apiKey.isEmpty, !credentials.secret.isEmpty else {
      throw ExchangeAccountError.missingCredentials
    }
    guard let provider = makeProvider(credentials) else { throw ExchangeAccountError.notConnected }
    try await provider.verifyReadOnly()
    let now = clock()
    let status = ExchangeCredentialStore.Status(keySuffix: credentials.keySuffix, connectedAt: now,
                                                backfillFrom: now - Self.backfillMs, watermark: nil,
                                                lastAttemptAt: nil)
    removeState()
    try store.save(credentials: credentials, status: status)
    return status
  }

  /// 断开：Key、元数据、拼回合的中间状态全删。已经写成复盘记录的回合不动。
  func disconnect() throws {
    try store.removeAll()
    removeState()
  }

  func status() throws -> ExchangeCredentialStore.Status? {
    try store.loadStatus()
  }

  // MARK: - 拉取

  /// 到点了就拉一轮。`force` 只给「接入成功后立刻拉第一轮」这种场合用，跳过 5 分钟节流。
  @discardableResult
  func pullIfDue(force: Bool = false) async -> Outcome {
    guard !inFlight else { return .skipped }
    inFlight = true
    defer { inFlight = false }

    let credentials: ExchangeCredentials
    var status: ExchangeCredentialStore.Status
    do {
      guard let c = try store.loadCredentials(), let s = try store.loadStatus() else { return .notConnected }
      credentials = c; status = s
    } catch {
      return .failed(message: ExchangeAccountError.keychain.message)
    }

    let now = clock()
    if !force, let last = status.lastAttemptAt, now - last < Self.throttleMs, now >= last {
      return .skipped
    }
    status.lastAttemptAt = now
    try? store.saveStatus(status)

    guard let provider = makeProvider(credentials) else { return .notConnected }
    let from = status.watermark.map { max(status.backfillFrom, $0 - Self.overlapMs) } ?? status.backfillFrom
    do {
      let batch = try await provider.fetch(from: from, to: now)
      var builder = loadBuilder() ?? RoundBuilder(venue: venue, market: market, accountTag: Self.accountTag)
      let context = RoundBuilder.Context(leverage: batch.leverage, markPrices: batch.markPrices,
                                         currentPositions: builder.initialized ? nil : batch.positions)
      let rounds = builder.ingest(fills: batch.fills, funding: batch.funding, context: context)
      if !rounds.isEmpty { await onRounds(rounds) }
      try saveBuilder(builder)
      // 回调期间可能被断开了：Keychain 里已经没有 Key 就不要把状态写回去。
      guard var latest = try store.loadStatus(), latest.connectedAt == status.connectedAt else {
        removeState()
        return .notConnected
      }
      latest.watermark = now
      try store.saveStatus(latest)
      return .pulled(rounds: rounds.count)
    } catch is CancellationError {
      return .skipped
    } catch let error as ExchangeAccountError where error.isSilent {
      return .offline
    } catch {
      return .failed(message: ExchangeAccountError.message(error) ?? ExchangeAccountError.genericFailure)
    }
  }

  // MARK: - 中间状态

  private func loadBuilder() -> RoundBuilder? {
    guard let data = try? Data(contentsOf: stateURL) else { return nil }
    guard let builder = try? JSONDecoder().decode(RoundBuilder.self, from: data),
          builder.venue == venue, builder.market == market else { return nil }
    return builder
  }

  private func saveBuilder(_ builder: RoundBuilder) throws {
    try FileManager.default.createDirectory(at: stateURL.deletingLastPathComponent(),
                                            withIntermediateDirectories: true)
    let data = try JSONEncoder().encode(builder)
    try data.write(to: stateURL, options: [.atomic])
    // 只排除这一个文件（同一个目录里还有提醒档案，要跟备份走）；丢了能从交易所重拼。
    var values = URLResourceValues()
    values.isExcludedFromBackup = true
    var fileURL = stateURL
    try? fileURL.setResourceValues(values)
  }

  private func removeState() {
    try? FileManager.default.removeItem(at: stateURL)
  }
}
