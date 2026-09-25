import Foundation
import KanpanCore
import Observation
import WidgetKit

/// 桌面小组件的数据源（P3.2）：把自选、报价、皮肤折成一份 `WidgetSnapshot`，
/// 写进 App Group 容器，再叫系统重载小组件。小组件扩展只读这份文件。
///
/// 什么时候写：
/// - **形状变了立刻写**：自选增删改序、分类、皮肤 / 深浅 / 涨跌色——跟着
///   `shape` 读到的那几项走（`withObservationTracking`），一变就写、立刻重载。
/// - **只是价动了**：最多 30 秒写一次，60 秒重载一次。app 在前台时系统不对
///   `reloadAllTimelines` 记额度，但也没必要逐帧重画桌面。
/// - **离开前台**：写最后一份（不再重载，桌面那份由系统 15 分钟刷一次、扩展自己补价）。
///
/// 中号的折线要一段收盘价：自选每只 15 分钟取一次 1 小时 × 24 根，只在前台取。
@MainActor
final class WidgetFeed {
  typealias Collect = @MainActor (_ closes: [String: [Double]]) -> WidgetSnapshot?

  static let writeEvery: TimeInterval = 30
  static let reloadEvery: TimeInterval = 60
  static let closesEvery: TimeInterval = 15 * 60
  static let closesConcurrency = 2

  private var collect: Collect?
  private var shape: (@MainActor () -> [String])?
  private var fetchCloses: (@Sendable (String) async -> [Double]?)?
  private let directory: URL?

  private var foreground = true
  private var lastWrite = Date.distantPast
  private var lastReload = Date.distantPast
  private var pending: Task<Void, Never>?
  private var closes: [String: [Double]] = [:]
  private var ledger = WidgetClosesLedger(every: WidgetFeed.closesEvery, retry: 60, concurrency: WidgetFeed.closesConcurrency)
  private var closesJobs: [String: Task<Void, Never>] = [:]
  private var lastSymbols: [String] = []

  init(directory: URL? = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: WidgetSnapshot.appGroup)) {
    self.directory = directory
  }

  /// 宿主交进来三样：怎么折快照、哪几项算「形状」、怎么取一段收盘价。
  func bind(collect: @escaping Collect, shape: @escaping @MainActor () -> [String],
            fetchCloses: @escaping @Sendable (String) async -> [Double]?) {
    self.collect = collect
    self.shape = shape
    self.fetchCloses = fetchCloses
    track()
  }

  private func track() {
    guard let shape else { return }
    _ = withObservationTracking { shape() } onChange: { [weak self] in
      Task { @MainActor [weak self] in
        self?.track()
        self?.flush(reload: true)
      }
    }
  }

  /// 报价簿又出了一批。
  func quotesChanged() {
    guard foreground, pending == nil else { return }
    let wait = max(0, Self.writeEvery - Date().timeIntervalSince(lastWrite))
    pending = Task { @MainActor [weak self] in
      try? await Task.sleep(for: .seconds(wait))
      guard let self, !Task.isCancelled else { return }
      self.pending = nil
      self.flush(reload: Date().timeIntervalSince(self.lastReload) >= Self.reloadEvery)
    }
  }

  func setForeground(_ on: Bool) {
    guard on != foreground else { return }
    foreground = on
    if on {
      flush(reload: true)
    } else {
      pending?.cancel(); pending = nil
      closesJobs.values.forEach { $0.cancel() }; closesJobs.removeAll()
      // 被掐掉的那几只一口数都没拿到：回前台就该重取，不能按「刚取过」再等一刻钟。
      ledger.cancelAll()
      flush(reload: false)
    }
  }

  /// 立刻折一份写下去。
  func flush(reload: Bool) {
    pending?.cancel(); pending = nil
    guard let collect, let snapshot = collect(closes) else { return }
    lastSymbols = snapshot.favorites
    if let directory {
      try? snapshot.write(to: WidgetSnapshot.url(in: directory))
    }
    lastWrite = Date()
    if reload && foreground {
      lastReload = Date()
      WidgetCenter.shared.reloadAllTimelines()
    }
    loadCloses()
  }

  private func loadCloses() {
    guard foreground, let fetchCloses else { return }
    for symbol in lastSymbols {
      guard let ticket = ledger.begin(symbol, now: Date()) else { continue }
      closesJobs[symbol] = Task { @MainActor [weak self] in
        let values = await fetchCloses(symbol)
        guard let self, !Task.isCancelled else { return }
        let usable = values.flatMap { $0.count >= 2 ? $0 : nil }
        // 只认这只当前在路上的那一笔、而且比已收下的那份新（审查 P2-5）；取不到的一分钟后再来。
        if self.ledger.finish(ticket, success: usable != nil, now: Date()), let usable {
          self.closes[symbol] = usable
          self.quotesChanged()
        }
        if self.ledger.inFlight[symbol] == nil { self.closesJobs[symbol] = nil }
        self.loadCloses()
      }
    }
  }

  // MARK: 折快照

  /// 把 app 手上的东西折成一份快照。纯函数，单独拎出来好测。
  static func snapshot(symbols: SymbolPrefs, quotes: [String: Ticker], decimals: (String) -> Int?,
                       closes: [String: [Double]], skin: ThemeSkin, appearance: ThemeChoice, redUp: Bool,
                       refresh: WidgetSnapshot.Refresh?, basis: ChangeBasis,
                       now: Date = Date()) -> WidgetSnapshot {
    let order = symbols.favorites
    let groups = symbols.groups.map { group in
      WidgetSnapshot.Group(id: group.id, name: group.name,
                           symbols: order.filter { symbols.groupForSymbol[$0] == group.id })
    }
    var table: [String: WidgetSnapshot.Quote] = [:]
    for symbol in order {
      guard let ticker = quotes[symbol], ticker.last.isFinite, ticker.last > 0 else { continue }
      let change = ticker.changePercent
      let open = change.isFinite && change > -100 ? ticker.last / (1 + change / 100) : nil
      table[symbol] = WidgetSnapshot.Quote(symbol: symbol, price: ticker.last, change: change, decimals: decimals(symbol),
                                           closes: Array((closes[symbol] ?? []).suffix(WidgetSnapshot.sparkLimit)),
                                           timeMs: ticker.timeMs ?? Int64(now.timeIntervalSince1970 * 1000), open: open)
    }
    return WidgetSnapshot(updatedAt: Int64(now.timeIntervalSince1970 * 1000), favorites: order, groups: groups,
                          quotes: table,
                          light: WidgetSnapshot.Colors(seed: skin.seed(dark: false), redUp: redUp),
                          dark: WidgetSnapshot.Colors(seed: skin.seed(dark: true), redUp: redUp),
                          appearance: WidgetSnapshot.Appearance(rawValue: appearance.rawValue) ?? .auto,
                          refresh: refresh, rolling: basis == .rolling24h)
  }
}

/// 小组件折线的取数账本（审查 P2-5）：每只什么时候可以再取、谁在路上、收下的那份是哪一笔发的。
///
/// 原来只有一张「上次开始取的时刻」表，有两个洞：切后台掐掉的那笔一口数没拿到，表上却记着
/// 「刚取过」，回前台要白等一刻钟才重取；而且收下结果不看是哪一笔发的，只要有一笔旧的后到
/// 就会把新的盖回去。现在：
/// - `begin`：到点了、这只没有在路上、在路上的不超过并发数，才发一张票；
/// - `finish`：只认这只**当前**那张票，并且票的时刻要比已收下的那份**严格更新**（单调递增）；
///   成功一刻钟后再取，失败一分钟后再来；
/// - `cancelAll`：在路上的全作废，并且这几只立刻算「到点」。
struct WidgetClosesLedger {
  struct Ticket: Equatable, Sendable {
    let symbol: String
    let at: Date
  }
  let every: TimeInterval
  let retry: TimeInterval
  let concurrency: Int
  /// 每只最早什么时候可以再取。
  private(set) var dueAt: [String: Date] = [:]
  /// 在路上的那一笔。
  private(set) var inFlight: [String: Ticket] = [:]
  /// 已经收下的那份是哪个时刻发的。
  private(set) var acceptedAt: [String: Date] = [:]

  init(every: TimeInterval, retry: TimeInterval, concurrency: Int) {
    self.every = every; self.retry = retry; self.concurrency = max(1, concurrency)
  }

  mutating func begin(_ symbol: String, now: Date) -> Ticket? {
    guard inFlight[symbol] == nil, inFlight.count < concurrency, now >= dueAt[symbol] ?? .distantPast else { return nil }
    // 票的时刻严格递增：同一时刻（测试里、或者时钟被往回拨）连发两张，后一张也要比前一张新。
    var at = now
    if let last = acceptedAt[symbol], at <= last { at = last.addingTimeInterval(0.001) }
    let ticket = Ticket(symbol: symbol, at: at)
    inFlight[symbol] = ticket
    dueAt[symbol] = now.addingTimeInterval(every)
    return ticket
  }

  /// 一笔回来了。返回 false：这笔已经作废（被掐掉 / 不是当前那张票 / 比收下的旧），结果不要。
  mutating func finish(_ ticket: Ticket, success: Bool, now: Date) -> Bool {
    guard inFlight[ticket.symbol] == ticket else { return false }
    inFlight[ticket.symbol] = nil
    guard success else {
      dueAt[ticket.symbol] = now.addingTimeInterval(retry)
      return true
    }
    if let accepted = acceptedAt[ticket.symbol], ticket.at <= accepted { return false }
    acceptedAt[ticket.symbol] = ticket.at
    return true
  }

  mutating func cancelAll() {
    for symbol in inFlight.keys { dueAt[symbol] = nil }
    inFlight.removeAll()
  }
}
