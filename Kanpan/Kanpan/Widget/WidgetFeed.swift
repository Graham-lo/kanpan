import Foundation
import KanpanCore
import Observation
import WidgetKit

/// 桌面小组件的数据源（P3.2）：把自选、报价、皮肤折成一份 `WidgetSnapshot`，
/// 写进 App Group 容器，再叫系统重载小组件。小组件扩展只读这份文件。
///
/// 什么时候写：
/// - **形状变了立刻写**：自选增删改序、分类、置顶、皮肤 / 深浅 / 涨跌色——跟着
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
  private var closesAt: [String: Date] = [:]
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
    for symbol in lastSymbols where closesJobs.count < Self.closesConcurrency && closesJobs[symbol] == nil {
      guard Date().timeIntervalSince(closesAt[symbol] ?? .distantPast) >= Self.closesEvery else { continue }
      closesAt[symbol] = Date()
      closesJobs[symbol] = Task { @MainActor [weak self] in
        let values = await fetchCloses(symbol)
        guard let self, !Task.isCancelled else { return }
        self.closesJobs[symbol] = nil
        if let values, values.count >= 2 {
          self.closes[symbol] = values
          self.quotesChanged()
        } else {
          // 取不到：一分钟后可以再来，不用干等一刻钟。
          self.closesAt[symbol] = Date().addingTimeInterval(60 - Self.closesEvery)
        }
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
    let pinned = symbols.pinned.filter { symbols.favorites.contains($0) }
    let order = pinned + symbols.favorites.filter { !pinned.contains($0) }
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
