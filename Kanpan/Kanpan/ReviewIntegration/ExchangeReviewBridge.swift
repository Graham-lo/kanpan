import BackgroundTasks
import Foundation
import Observation
import UIKit
import os
import KanpanAccount
import KanpanChart
import KanpanCore
import KanpanNetwork
import ReviewDomain
import ReviewUI

/// 交易所只读账户 ↔ 复盘本（自动复盘 3c）。
///
/// 发动机（`ExchangeAccountSync`）只管「拉成交、拼回合」；这一层把它接进 app：
/// - **什么时候拉**：回到前台拉一次、前台每 5 分钟一次、打开复盘本一次（节流在发动机里，
///   按「尝试」计，来回切不会反复打交易所）；后台交给系统的 `BGAppRefreshTask`，
///   有空就拉一轮、传一轮。断网安静放弃，不提示、不重试。
/// - **拉到的回合放哪**：本机一份（`exchange-rounds-<venue>-<market>.json`，按 id 覆盖），
///   整份灌给 `TradeReviewFeature.setLocalRounds`——没登录只在本机显示，登录后自动补传。
///   Key 与回合仍是这台手机的（不随账号同步、不进账号档案），但回合记着**属主**：
///   接入时（或访客接入后第一次登录时）是哪个看盘账号，就只给那个账号看、只往那个账号传。
///   换成别的账号登录，复盘本里不出这些回合、也不拉；要给新账号用，移除后重新接入
///   （见 `ExchangeRoundsOwnership`）。以前「登了哪个账号就传到哪个」，同一台手机换人登录，
///   前一个人的成交会被整份传进后一个人的账号。
/// - **回合档丢了**（卸载重装、文件坏了）：发动机的中间状态一并作废，下一轮从回溯起点重拼，
///   能补回的都补回来（交易所只留近 90 天的成交）。
/// - **图**：复盘图只画在复盘本自己的图上（缩略图、详情大图），用行情那张图的样式、
///   取本家历史 K 线，成交点画成箭头、开平均价画成虚线。主图一根线都不碰。
///
/// Key 从头到尾只在 Keychain 里（`ExchangeCredentialStore`），这一层只见得到尾号四位。
@MainActor @Observable final class ExchangeReviewBridge {
  nonisolated static let refreshTaskID = "com.yj27y32.hkline.exchange-refresh"
  static let shared = ExchangeReviewBridge()
  /// 前台定时拉的间隔。和发动机的节流同一个数。
  static let foregroundPeriod: Duration = .seconds(300)

  let venue = ExchangeAccountRegistry.binanceFutures
  private(set) var status: ExchangeCredentialStore.Status?
  private(set) var rounds: [TradeRound] = []
  private(set) var connecting = false
  private(set) var pulling = false
  /// 接入页上那一行红字（这一趟接入为什么没成）。
  var connectError: String?
  /// 上一轮同步为什么没成（断网不算，断网不出声）。
  private(set) var lastFailure: String?
  /// 第一次从 Keychain 读完状态之前，界面别先说「未接入」再跳成已接入。
  private(set) var loaded = false
  /// 这把 Key 记在另一个看盘账号下：此刻登录的人看不到这些回合，也不替他拉。
  private(set) var ownerMismatch = false

  var connected: Bool { status != nil }
  var lastSync: Int64? { status?.watermark }

  /// 画复盘图用的底：行情那张图此刻的样式（皮肤、涨跌色、时区）。宿主接上。
  @ObservationIgnored var baseState: @MainActor () -> ChartState? = { nil }
  /// 取历史 K 线走哪条线路（跟着用户选的行情线路）。宿主接上。
  @ObservationIgnored var resolver: @MainActor () -> RouteResolver = { RouteResolver() }

  @ObservationIgnored private weak var review: ReviewFeature?
  @ObservationIgnored private var engine: ExchangeAccountSync?
  @ObservationIgnored private let roundsURL: URL
  /// 本机那份回合记在哪个看盘档案下（`AccountFiles.currentProfile` 的值）；老文件没有，是 nil。
  @ObservationIgnored private var owner: String?
  @ObservationIgnored private var watchingProfile = false
  /// 后台刷新把 app 拉起、没有界面时（审查 E·待核实五），复盘本与账号桥都还没建
  /// （它们是 `MainScreen` 的状态，场景没连上就没有 `MainScreen`），`AccountFiles.currentProfile`
  /// 也还是空串。这一轮「此刻是谁、新回合往哪儿传」由桥自己去问。
  @ObservationIgnored private let headlessUplink: @MainActor () async -> ExchangeReviewUplink?
  /// 没界面那一轮问到的档案 id。只在 `AccountFiles.currentProfile` 还是空串时顶上。
  @ObservationIgnored private var headlessProfile: String?
  /// 账号桥装着的档案 id（`AccountFiles.currentProfile`）。单测换成固定值，不跟同进程别的用例抢那个全局。
  @ObservationIgnored private let currentProfile: @MainActor () -> String

  private static let log = Logger(subsystem: "com.kanpan.app", category: "exchange")
  @ObservationIgnored private var foregroundLoop: Task<Void, Never>?
  @ObservationIgnored private var pulls = 0
  @ObservationIgnored private var barCache: [String: BarSeries] = [:]
  @ObservationIgnored private var barOrder: [String] = []

  convenience init() {
    let venue = ExchangeAccountRegistry.binanceFutures
    var store = ExchangeCredentialStore(venue: venue.venue, market: venue.market)
    var stateURL = ExchangeAccountSync.defaultStateURL(venue: venue.venue, market: venue.market)
    var roundsURL = stateURL.deletingLastPathComponent()
      .appendingPathComponent("exchange-rounds-\(venue.venue)-\(venue.market).json")
    var makeProvider: ExchangeAccountSync.ProviderFactory = {
      ExchangeAccountRegistry.provider(for: venue, credentials: $0)
    }
    var autoKey: String?
    #if DEBUG
    if let demo = ExchangeDemoAccount.setup(venue: venue) {
      store = demo.store; stateURL = demo.stateURL; roundsURL = demo.roundsURL
      if demo.fixture {
        let prices = Self.priceLookup(venue: venue)
        makeProvider = { ExchangeDemoProvider(venue: venue, credentials: $0, priceAt: prices) }
      }
      autoKey = demo.autoKey
    }
    #endif
    self.init(store: store, stateURL: stateURL, roundsURL: roundsURL, makeProvider: makeProvider,
              autoKey: autoKey, headlessUplink: { await ExchangeReviewUplink.resolve() })
  }

  /// 装配口：Keychain、两份本机档、取数的 provider、没界面时的上传通道都从外面给。
  /// 正式走上面那个无参的；单测给内存 Keychain、临时目录、假 provider、假上传通道。
  init(store: ExchangeCredentialStore, stateURL: URL, roundsURL: URL,
       makeProvider: @escaping ExchangeAccountSync.ProviderFactory, autoKey: String? = nil,
       currentProfile: @escaping @MainActor () -> String = { AccountFiles.currentProfile },
       headlessUplink: @escaping @MainActor () async -> ExchangeReviewUplink?) {
    let venue = ExchangeAccountRegistry.binanceFutures
    self.roundsURL = roundsURL
    self.currentProfile = currentProfile
    self.headlessUplink = headlessUplink
    let file = Self.loadRounds(roundsURL)
    rounds = file?.rounds ?? []
    owner = file?.owner
    // 回合档没了或解不开：发动机手上的账本也不能再接着用（它以为那些回合已经交过了），
    // 一起作废，下一轮从回溯起点重拼，把回合补回来。
    engine = ExchangeAccountSync(venue: venue.venue, market: venue.market, store: store,
                                 stateURL: stateURL, discardState: file == nil, makeProvider: makeProvider,
                                 onRounds: { [weak self] in await self?.absorb($0) })
    Task {
      await refreshStatus()
      loaded = true
      if status == nil, let autoKey { await connect(apiKey: autoKey, secret: "fixture-secret") }
    }
  }

  // MARK: - 接入复盘本

  func attach(review: ReviewFeature) {
    self.review = review
    review.trades.onPull = { [weak self] in self?.pull() }
    review.trades.chartImage = { [weak self] round, spec, size in
      await self?.chartImage(round, spec: spec, size: size)
    }
    publish()
    showRounds()
    watchProfile()
  }

  private func publish() {
    review?.trades.exchange = .init(connected: status != nil, title: venue.displayName, lastSync: status?.watermark)
  }

  /// 按此刻登录的是谁，把该给他看的回合灌给复盘本（属主不对就灌空的）；访客时接入的回合，
  /// 第一次登录就记到这个账号名下。
  private func showRounds() {
    let view = ExchangeRoundsOwnership.view(rounds, owner: owner, profile: profile)
    if let claim = view.claim, claim != owner {
      owner = claim
      saveRounds()
    }
    ownerMismatch = view.hidden
    review?.trades.setLocalRounds(view.rounds)
  }

  /// 此刻装着谁的档案。账号桥装过档案就认它；还没装（后台刷新拉起、没有界面）就认这一轮
  /// 桥自己问到的那个人。两边都没有是空串——属于某个账号的回合对空串一律不可见，
  /// 从前后台那一轮就是因此判成「属主不对」，连拉都不拉。
  private var profile: String {
    let current = currentProfile()
    return current.isEmpty ? (headlessProfile ?? current) : current
  }

  /// 换账号（登录、退登、换号）时复盘本会换一个上传通道：在它换的**那一刻**（`client` 赋值前）
  /// 先把本机回合按新的属主重新筛一遍——`TradeReviewFeature.activate` 紧接着就会把手上的回合补传，
  /// 晚一拍就把前一个人的成交传进了后一个人的账号。
  private func watchProfile() {
    guard let review, !watchingProfile else { return }
    watchingProfile = true
    withObservationTracking {
      _ = review.trades.isConnected
    } onChange: { [weak self] in
      MainActor.assumeIsolated {
        guard let self else { return }
        self.watchingProfile = false
        self.showRounds()
        // 这一次通知已经用掉了；等这一轮赋值走完再接着盯下一次。
        Task { @MainActor [weak self] in self?.watchProfile() }
      }
    }
  }

  // MARK: - 接入 / 移除

  func connect(apiKey: String, secret: String) async {
    guard let engine, !connecting else { return }
    connecting = true; connectError = nil
    do {
      status = try await engine.connect(apiKey: apiKey, secret: secret)
      lastFailure = nil
      connecting = false
      // 这把 Key 记到此刻登录的人名下。本机还留着别的账号的回合（换人后先移除、再接入）：
      // 那一份不属于他，清掉，不给他看、不替他传。
      let profile = AccountFiles.currentProfile
      if ExchangeRoundsOwnership.view(rounds, owner: owner, profile: profile).hidden { rounds = [] }
      owner = profile.isEmpty ? nil : profile
      saveRounds()
      showRounds()
      publish()
      await pullNow(force: true)
    } catch {
      connecting = false
      connectError = ExchangeAccountError.message(error)
    }
  }

  /// 移除：Key 与同步状态全删。已经拼好的回合留着（复盘本里照样看得到，服务端那份也不动）。
  /// 钥匙串删不掉（设备锁着、钥匙串抽风）就不装作已移除：留在已接入，给一行红字，
  /// 否则下次启动 Key 还在、又显示已接入。
  func disconnect() async {
    guard let engine else { return }
    do {
      try await engine.disconnect()
      status = nil; lastFailure = nil; connectError = nil
      publish()
    } catch {
      Self.log.error("移除交易所密钥失败：\(error.localizedDescription, privacy: .public)")
      lastFailure = ExchangeAccountError.message(error) ?? ExchangeAccountError.genericFailure
      await refreshStatus()
    }
  }

  // MARK: - 拉

  /// 到点了就拉（节流在发动机里）。`force` 只给「立即同步」与「刚接入」。
  @discardableResult func pull(force: Bool = false) -> Task<Void, Never> {
    Task { await pullNow(force: force) }
  }

  func pullNow(force: Bool) async {
    guard let engine, status != nil else { return }
    // 登录的不是这把 Key 的属主：不替他拉（拉回来也不给他看）。
    showRounds()
    guard !ownerMismatch else { return }
    pulls += 1; pulling = true
    let outcome = await engine.pullIfDue(force: force)
    pulls -= 1; pulling = pulls > 0
    switch outcome {
    case .pulled:
      lastFailure = nil
      // 没有成交也要留下这份（空的）回合档：下次启动看到档在，才知道发动机的账本还能接着用。
      if !FileManager.default.fileExists(atPath: roundsURL.path) { saveRounds() }
      // 「立即同步」是人点的：交易所那头没变化也把服务端的结果拉一次。
      if force { review?.trades.sync() }
    case .failed(let message): lastFailure = message
    case .notConnected, .offline, .skipped: break
    }
    await refreshStatus()
  }

  private func refreshStatus() async {
    guard let engine else { return }
    status = try? await engine.status()
    publish()
  }

  /// 发动机交出来的回合（只有变了的）：按 id 覆盖进本机那份，整份灌给复盘本。
  private func absorb(_ changed: [TradeRound]) {
    var byID = Dictionary(rounds.map { ($0.id, $0) }, uniquingKeysWith: { $1 })
    for round in changed { byID[round.id] = round }
    rounds = byID.values.sorted { ($0.openedAt, $0.id) > ($1.openedAt, $1.id) }
    saveRounds()
    showRounds()
  }

  // MARK: - 前后台

  func setForeground(_ foreground: Bool) {
    if foreground {
      guard foregroundLoop == nil else { return }
      foregroundLoop = Task { [weak self] in
        while !Task.isCancelled {
          await self?.pullNow(force: false)
          do { try await Task.sleep(for: Self.foregroundPeriod) } catch { return }
        }
      }
    } else {
      foregroundLoop?.cancel(); foregroundLoop = nil
      scheduleBackgroundRefresh()
    }
  }

  /// 系统给的后台刷新：在 `KanpanApp.init` 里登记（必须在启动结束前）。
  nonisolated static func registerBackgroundRefresh() {
    BGTaskScheduler.shared.register(forTaskWithIdentifier: refreshTaskID, using: nil) { task in
      nonisolated(unsafe) let task = task
      let work = Task { @MainActor in
        await ExchangeReviewBridge.shared.backgroundPull()
        ExchangeReviewBridge.shared.scheduleBackgroundRefresh()
        task.setTaskCompleted(success: !Task.isCancelled)
      }
      task.expirationHandler = { work.cancel() }
    }
  }

  /// 接着的时候才约下一次（没接就不打扰系统）。
  func scheduleBackgroundRefresh() {
    guard status != nil, !ownerMismatch else { return }
    let request = BGAppRefreshTaskRequest(identifier: Self.refreshTaskID)
    request.earliestBeginDate = Date(timeIntervalSinceNow: 30 * 60)
    try? BGTaskScheduler.shared.submit(request)
  }

  /// 系统给的那一轮后台刷新：拉一次交易所，新拼好的回合**这一轮就传上去**。
  ///
  /// 有界面（复盘本挂在桥上）时交给复盘本那一套传、再拉。没有界面时复盘本根本不存在——
  /// 原来这里是 `review?.trades.synchronize()`，`review` 是 nil，新回合就只落在本机，
  /// 等人哪天回前台才补传（审查 E·待核实五）。现在桥自己问到「此刻是谁」与上传通道，
  /// 按那个人能看见的那一份直接走 `TradeSync.upload`；没登录、钥匙串读不动就只拉不传。
  func backgroundPull() async {
    if status == nil { await refreshStatus() }
    guard status != nil else { return }
    if let review {
      await pullNow(force: false)
      await review.trades.synchronize()
      return
    }
    let uplink = await headlessUplink()
    headlessProfile = uplink?.profile
    await pullNow(force: false)
    // 拉的这一会儿界面起来了（人点开了 app）：复盘本接上桥时已经拿到这批回合、会自己去传。
    guard review == nil, let upload = uplink?.upload, !ownerMismatch else { return }
    let visible = ExchangeRoundsOwnership.view(rounds, owner: owner, profile: profile)
    guard !visible.hidden, !visible.rounds.isEmpty else { return }
    await upload(visible.rounds)
  }

  // MARK: - 复盘图

  /// 一个回合的图：本家历史 K 线 + 成交箭头 + 开平均价虚线。取不到就没有图（行上留白）。
  func chartImage(_ round: TradeRound, spec: TradeChartSpec?, size: CGSize) async -> Data? {
    guard size.width > 1, size.height > 1, var base = baseState() else { return nil }
    let interval: Interval, start: Int64, end: Int64
    if let spec, let value = Interval(rawValue: spec.interval), spec.end > spec.start {
      interval = value; start = spec.start; end = spec.end
    } else {
      let window = ReviewChartInterval.window(openedAt: round.openedAt, closedAt: round.closedAt, now: ReviewClock.now)
      interval = window.interval; start = window.start; end = window.end
    }
    let key = round.instrument.key
    guard let series = await bars(key: key, venue: round.venue, market: round.market,
                                  interval: interval, start: start, end: end), series.count >= 2 else { return nil }
    let closes = (0..<series.count).map { series.close[$0] }
    let decimals = review?.priceDecimals(key) ?? ReviewPricePrecision.decimals(of: closes)
      ?? priceDecimalsFallback(closes.last ?? 1)
    let placeholder = SymbolInfo.placeholder(symbol: key)
    base.series = series
    base.symbol = SymbolInfo(symbol: key, base: placeholder.base, quote: placeholder.quote,
                             pricePrecision: decimals, tickSize: pow(10, -Double(decimals)))
    base.decimals = base.symbol.priceDecimals
    base.oi = nil; base.subs = []; base.overlays = []; base.compare = []; base.percentAxis = false
    base.external = [:]; base.crosshair = nil; base.nowMs = nil; base.depth = nil; base.orderFlow = nil
    base.options.drawings = true; base.options.countdown = false; base.options.sinceChange = false
    base.drawings = Self.markers(round)
    let step = Double(interval.stepMs)
    base.view = ViewWindow(from: Double(series.time(at: 0)) - step, to: Double(series.lastTime) + step * 2)
    if size.width < 160 {
      // 缩略图：按三倍大小画、1× 出，再由行里缩下去——K 线的形状看得清，刻度字缩成纹理。
      base.options.lastLine = false
      let big = CGSize(width: size.width * 3, height: size.height * 3)
      return ChartSnapshotRenderer.chartImage(state: base, size: big, scale: 1)?.jpegData(compressionQuality: 0.8)
    }
    return ChartSnapshotRenderer.chartImage(state: base, size: size)?.pngData()
  }

  /// 成交点：买是向上箭头（画在点下方）、卖是向下箭头；开仓均价、平仓均价两条虚线。
  static func markers(_ round: TradeRound) -> [Drawing] {
    var drawings = round.fills.map { fill in
      Drawing(id: "fill-\(fill.id)", kind: fill.side == .buy ? .markerUp : .markerDown,
              a: DrawPoint(t: Double(fill.time), p: NSDecimalNumber(decimal: fill.price).doubleValue))
    }
    var levels: [(String, Decimal, Int64)] = [("open", round.openAvgPrice, round.openedAt)]
    if let close = round.closeAvgPrice { levels.append(("close", close, round.closedAt ?? round.openedAt)) }
    for (name, price, _) in levels {
      var line = Drawing(id: "avg-\(name)", kind: .hline,
                         a: DrawPoint(t: Double(round.openedAt), p: NSDecimalNumber(decimal: price).doubleValue))
      line.dash = .dashed
      drawings.append(line)
    }
    return drawings
  }

  /// 取一段历史 K 线（本页记住最近几十段：缩略图和详情大图常常是同一段）。
  private func bars(key: String, venue: String, market: String, interval: Interval,
                    start: Int64, end: Int64) async -> BarSeries? {
    let cacheKey = "\(key)|\(interval.rawValue)|\(start)|\(end)"
    if let hit = barCache[cacheKey] { return hit }
    guard VenueRegistry.descriptor(venue)?.market == market,
          let provider = resolver().ownDataProvider(venue: venue) else { return nil }
    let caps = provider.capabilities
    var cursor = start
    var fetched: [Bar] = []
    do {
      while cursor <= end {
        let page = try await provider.klines(symbol: key, interval: interval, limit: caps.maxKlines,
                                             startTime: cursor, endTime: end)
        guard let last = page.last else { break }
        fetched.append(contentsOf: page)
        let next = interval.advancing(last.openTime, by: 1)
        guard next > cursor, fetched.count < 1500 else { break }
        cursor = next
      }
    } catch { return nil }
    guard !fetched.isEmpty else { return nil }
    let series = MarketSeries.series(symbol: key, interval: interval, bars: fetched, capabilities: caps)
    barCache[cacheKey] = series; barOrder.append(cacheKey)
    if barOrder.count > 40 { barCache[barOrder.removeFirst()] = nil }
    return series
  }

  // MARK: - 本机那份回合

  /// 读回本机那份回合。没有、读不出、解不开都是 nil（调用方据此让发动机从回溯起点重拼）。
  private static func loadRounds(_ url: URL) -> ExchangeRoundsOwnership.File? {
    let data: Data
    do {
      data = try Data(contentsOf: url)
    } catch {
      let missing = (error as NSError).domain == NSCocoaErrorDomain
        && (error as NSError).code == NSFileReadNoSuchFileError
      if !missing { log.error("交易所回合档读不出：\(error.localizedDescription, privacy: .public)") }
      return nil
    }
    guard let file = ExchangeRoundsOwnership.decode(data) else {
      log.error("交易所回合档解不开（\(data.count, privacy: .public) 字节），从回溯起点重拼")
      return nil
    }
    return file
  }

  private func saveRounds() {
    let url = roundsURL
    do {
      try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
      let data = try JSONEncoder().encode(ExchangeRoundsOwnership.File(owner: owner, rounds: rounds))
      try data.write(to: url, options: [.atomic])
    } catch {
      // 写不进去：下次启动读到的是旧档或没有档，发动机会作废账本重拼，回合不会丢，只是多拉一轮。
      Self.log.error("交易所回合档写不进去：\(error.localizedDescription, privacy: .public)")
      return
    }
    // 不跟备份走：Key 只在这台手机上，换机恢复出来的回合档没有对应的 Key 与账本。
    var values = URLResourceValues(); values.isExcludedFromBackup = true
    var fileURL = url
    try? fileURL.setResourceValues(values)
  }

  /// 某只合约某一刻的价（取那一小时的开盘价）。只给演示账户用，让演示成交落在真实行情上。
  nonisolated static func priceLookup(venue: ExchangeAccountRegistry.Venue) -> @Sendable (String, Int64) async -> Double? {
    let provider = RouteResolver().ownDataProvider(venue: venue.venue)
    return { symbol, time in
      guard let provider, let hour = Interval(rawValue: "1h") else { return nil }
      let key = InstrumentID(venue: venue.venue, market: venue.market, symbol: symbol).key
      let start = time - time % hour.stepMs
      let bars = try? await provider.klines(symbol: key, interval: hour, limit: 1, startTime: start, endTime: nil)
      return bars?.first?.open
    }
  }
}

/// 本机那份交易所回合记在哪个看盘账号下、此刻该给谁看（审查 R9）。
///
/// 档案 id 就是 `AccountFiles.currentProfile`：登录的人是 `u-<uuid>`，没登录是 `local/<访客批次>`，
/// 档案还没装好时是空串。
/// - 属主就是此刻这份档案：照常给看、照常传。
/// - 属主是访客（`local/…`）或老文件没记属主：照常给看；此刻是登录的人，就记到他名下
///   （「没登录只在本机显示，登录后自动补传」，补传给的是第一个登录的人）。
/// - 属主是另一个登录账号：一个也不给看（复盘本拿到空的，自然也不会补传）。
enum ExchangeRoundsOwnership {
  /// 回合档的样子。老版本只存了一个回合数组，读进来属主是 nil。
  struct File: Codable, Equatable, Sendable {
    var owner: String?
    var rounds: [TradeRound]
  }

  struct Visible: Equatable, Sendable {
    var rounds: [TradeRound]
    /// 要把属主改记成谁（访客 / 老文件被第一个登录的人认领）；nil 是不用改。
    var claim: String?
    /// 属主是另一个账号，这一份对此刻的人不可见。
    var hidden: Bool
  }

  static func view(_ rounds: [TradeRound], owner: String?, profile: String) -> Visible {
    if let owner, owner == profile { return Visible(rounds: rounds, claim: nil, hidden: false) }
    if owner == nil || owner?.hasPrefix("local/") == true {
      let claim = profile.hasPrefix("u-") ? profile : nil
      return Visible(rounds: rounds, claim: claim, hidden: false)
    }
    return Visible(rounds: [], claim: nil, hidden: true)
  }

  static func decode(_ data: Data) -> File? {
    let decoder = JSONDecoder()
    if let file = try? decoder.decode(File.self, from: data) { return file }
    if let legacy = try? decoder.decode([TradeRound].self, from: data) { return File(owner: nil, rounds: legacy) }
    return nil
  }
}
