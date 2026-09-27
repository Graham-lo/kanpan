import BackgroundTasks
import Foundation
import Observation
import UIKit
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
///   这一份不跟账号走：Key 是这台手机的，回合也是这台手机拉的；登了哪个看盘账号就传到哪个。
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

  var connected: Bool { status != nil }
  var lastSync: Int64? { status?.watermark }

  /// 画复盘图用的底：行情那张图此刻的样式（皮肤、涨跌色、时区）。宿主接上。
  @ObservationIgnored var baseState: @MainActor () -> ChartState? = { nil }
  /// 取历史 K 线走哪条线路（跟着用户选的行情线路）。宿主接上。
  @ObservationIgnored var resolver: @MainActor () -> RouteResolver = { RouteResolver() }

  @ObservationIgnored private weak var review: ReviewFeature?
  @ObservationIgnored private var engine: ExchangeAccountSync?
  @ObservationIgnored private let roundsURL: URL
  @ObservationIgnored private var foregroundLoop: Task<Void, Never>?
  @ObservationIgnored private var pulls = 0
  @ObservationIgnored private var barCache: [String: BarSeries] = [:]
  @ObservationIgnored private var barOrder: [String] = []

  init() {
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
    self.roundsURL = roundsURL
    rounds = Self.loadRounds(roundsURL)
    engine = ExchangeAccountSync(venue: venue.venue, market: venue.market, store: store,
                                 stateURL: stateURL, makeProvider: makeProvider,
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
    review.trades.setLocalRounds(rounds)
  }

  private func publish() {
    review?.trades.exchange = .init(connected: status != nil, title: venue.displayName, lastSync: status?.watermark)
  }

  // MARK: - 接入 / 移除

  func connect(apiKey: String, secret: String) async {
    guard let engine, !connecting else { return }
    connecting = true; connectError = nil
    do {
      status = try await engine.connect(apiKey: apiKey, secret: secret)
      lastFailure = nil
      connecting = false
      publish()
      await pullNow(force: true)
    } catch {
      connecting = false
      connectError = ExchangeAccountError.message(error)
    }
  }

  /// 移除：Key 与同步状态全删。已经拼好的回合留着（复盘本里照样看得到，服务端那份也不动）。
  func disconnect() async {
    try? await engine?.disconnect()
    status = nil; lastFailure = nil; connectError = nil
    publish()
  }

  // MARK: - 拉

  /// 到点了就拉（节流在发动机里）。`force` 只给「立即同步」与「刚接入」。
  @discardableResult func pull(force: Bool = false) -> Task<Void, Never> {
    Task { await pullNow(force: force) }
  }

  func pullNow(force: Bool) async {
    guard let engine, status != nil else { return }
    pulls += 1; pulling = true
    let outcome = await engine.pullIfDue(force: force)
    pulls -= 1; pulling = pulls > 0
    switch outcome {
    case .pulled:
      lastFailure = nil
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
    Self.saveRounds(rounds, to: roundsURL)
    review?.trades.setLocalRounds(rounds)
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
    guard status != nil else { return }
    let request = BGAppRefreshTaskRequest(identifier: Self.refreshTaskID)
    request.earliestBeginDate = Date(timeIntervalSinceNow: 30 * 60)
    try? BGTaskScheduler.shared.submit(request)
  }

  private func backgroundPull() async {
    if status == nil { await refreshStatus() }
    await pullNow(force: false)
    await review?.trades.synchronize()
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

  private static func loadRounds(_ url: URL) -> [TradeRound] {
    guard let data = try? Data(contentsOf: url) else { return [] }
    return (try? JSONDecoder().decode([TradeRound].self, from: data)) ?? []
  }

  private static func saveRounds(_ rounds: [TradeRound], to url: URL) {
    try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
    guard let data = try? JSONEncoder().encode(rounds), (try? data.write(to: url, options: [.atomic])) != nil
    else { return }
    // 丢了能从交易所重拼，不跟备份走。
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
