import Foundation
import KanpanCore
import Observation

/// 自选五分钟波动提醒的前台一半（P3.1）。
///
/// 判定规则只有一份，写在 `KanpanCore/Alerts/WatchMove.swift`；服务端
/// `Backend/kanpan-api/src/watch_move.rs` 按同一段文字实现另一半，app 不在前台时由它判。
/// 这个类只做接线：
///
/// - **盯谁**：当前账号的自选（宿主在 `settleFavorites` 那一拍交进来）。自选改了，
///   拿掉的品种连同它的闸一起忘掉。
/// - **开关与幅度**：设置里的 `watchMoveAlert` / `watchMoveThreshold`（随账号同步，
///   服务端读同一份）。关掉就把状态全清——再打开从缺口重新开始，不拿关着那段时间的
///   陈价去比。
/// - **喂价**：和 `AlertEngine` 同两条流（图上那只走逐笔，别的走报价簿的列表流），
///   按交易所时刻切成 1 分钟桶。服务端订的是同一个交易所的 1 分钟 K 线，两边参照
///   的是同一根的收盘价。
/// - **前后台**：切后台就把收盘价扔掉（断过的流不算连续），闸留着——同一个窗口里
///   回来不许再响一次。
///
/// 响了交给 `onEvent`，宿主负责发本地通知 + 浮条（`MainScreen.wireWatchMove`）。
@MainActor
final class WatchMoveMonitor {
  var onEvent: ((WatchMove.Event) -> Void)?

  private(set) var enabled = false
  private(set) var threshold = WatchMove.defaultThreshold
  private(set) var favorites: Set<String> = []
  private var tracker = WatchMove.Tracker()
  private var foreground = true

  private var read: (@MainActor () -> (enabled: Bool, threshold: Double))?

  /// 跟着设置走：`read` 读出开关与幅度，读到的任何一项一变就重读一次
  /// （`withObservationTracking`，`PrefsStore` 是 `@Observable`）。
  func follow(_ read: @escaping @MainActor () -> (enabled: Bool, threshold: Double)) {
    self.read = read
    track()
  }

  private func track() {
    guard let read else { return }
    let value = withObservationTracking { read() } onChange: { [weak self] in
      Task { @MainActor [weak self] in self?.track() }
    }
    configure(enabled: value.enabled, threshold: value.threshold)
  }

  /// 设置变了。关掉就全清。
  func configure(enabled: Bool, threshold: Double) {
    self.threshold = WatchMove.clampThreshold(threshold)
    guard enabled != self.enabled else { return }
    self.enabled = enabled
    if !enabled { tracker = WatchMove.Tracker() }
    #if DEBUG
    injectIfTesting()
    #endif
  }

  /// 自选里存的是完整品种 key（`binance/usd_m/BTCUSDT`），报价簿与主图喂进来的可能是裸代号；
  /// 两边都折成同一个完整 key 再比，不然谁也对不上、永远不响。规范键是小写前缀 + 大写代号
  /// （`WatchMove.Tracker` 也按它记）；不能再 `uppercased()`——那会写成 `BINANCE/USD_M/BTCUSDT`，
  /// 事件带着它出去，`picker.info(for:)` 查不到小数位，点「查看」开的也不是规范键。
  static func key(_ symbol: String) -> String { InstrumentID.canonical(symbol) }

  /// 自选变了。进来的是什么写法都先归成规范键（宿主交的是规范键，UI 用例的注入是裸代号）。
  func setFavorites(_ symbols: [String]) {
    let next = Set(symbols.map(Self.key).filter { !$0.isEmpty })
    guard next != favorites else { return }
    favorites = next
    tracker.keep(next)
    #if DEBUG
    injectIfTesting()
    #endif
  }

  func setForeground(_ value: Bool) {
    guard value != foreground else { return }
    foreground = value
    if !value { tracker.forgetPrices() }
  }

  /// 报价簿那一批。
  func observe(_ tickers: [Ticker]) {
    guard enabled, foreground, !favorites.isEmpty else { return }
    for ticker in tickers { observe(symbol: ticker.symbol, price: ticker.last, timeMs: ticker.timeMs ?? 0) }
  }

  /// 一口价。`timeMs` 是交易所时刻，取不到传 0 用本机的顶上。
  func observe(symbol: String, price: Double, timeMs: Int64, closed: Bool = false) {
    guard enabled, foreground else { return }
    let key = Self.key(symbol)
    guard favorites.contains(key) else { return }
    let stamp = timeMs > 0 ? timeMs : Int64(Date().timeIntervalSince1970 * 1000)
    let open = stamp - stamp % WatchMove.barMs
    if let event = tracker.observe(symbol: key, barOpen: open, price: price, closed: closed, threshold: threshold) {
      onEvent?(event)
    }
  }

  #if DEBUG
  private var injected = false
  private func injectIfTesting(environment: [String: String] = ProcessInfo.processInfo.environment) {
    guard !injected, enabled, environment["KANPAN_TEST_PROFILE"] == "1",
          let symbol = environment["KANPAN_TEST_WATCHMOVE"].map(Self.key), favorites.contains(symbol) else { return }
    injected = true
    // 隔两秒再喂：让用例先把开关与幅度那一格截完图。
    Task { @MainActor [weak self] in
      try? await Task.sleep(for: .seconds(Self.testInjectDelay))
      self?.injectTestMove(symbol: symbol)
    }
  }

  static let testInjectDelay: Double = 2

  /// UI 用例在模拟器上走一遍「响一次」的完整链路：真行情五分钟里未必动 1.5%，
  /// 所以从启动环境 `KANPAN_TEST_WATCHMOVE=<代号>`（配 `KANPAN_TEST_PROFILE=1`）认一只，
  /// 开关一打开（且这只在自选里）就往这只品种上喂六根合成的 1 分钟价——前五根收在 100、第六根 102（+2%）。时间戳放在
  /// 一天以后，真行情的帧全比它早，会被当成乱序的旧帧挡掉，不会搅进来。
  /// 走的是和真行情完全一样的 `observe`：开关、自选、阈值、去重一道都不绕。
  func injectTestMove(symbol: String, now: Double = Date().timeIntervalSince1970 * 1000) {
    let base = Int64(now) + 86_400_000
    let start = base - base % WatchMove.windowMs
    for n in 0..<5 {
      observe(symbol: symbol, price: 100, timeMs: start + Int64(n) * WatchMove.barMs, closed: true)
    }
    observe(symbol: symbol, price: 102, timeMs: start + 5 * WatchMove.barMs)
  }
  #endif
}
