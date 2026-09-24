import Foundation
import KanpanCore
import KanpanNetwork

/// `RoutedMarketFeed` 里主力订单流这一格的全部状态与起停。路由只在几个时刻调它（开关、首帧、
/// 换品种 / 换线路、前后台、停），其余都收在这里，不散在路由的字段里。
struct OrderFlowSlot {
  typealias Publish = @Sendable (_ token: UUID, _ frame: OrderFlowSnapshot) async -> Void

  /// 指标开关。
  var enabled = false
  /// 品种事实（base、资产类别、最小变动价、成交额），由 app 按品种给。还没有就先不订。
  var facts: @Sendable (String) -> OrderFlowFacts? = { _ in nil }
  /// 用户改过的门槛 / 步长，按去掉缩放前缀的 base 存。
  private(set) var overrides: [String: OrderFlowOverride] = [:]
  /// 哪只品种的 K 线已经交给界面（历史 ≥ 3 根）。簿订阅只在这之后才发，不跟首屏抢。
  var chartReady: String?
  /// 正在跑的那一条订阅；`token` 跟着换，迟到的旧帧因此进不来。
  private(set) var feed: OrderFlowFeed?
  private(set) var token = UUID()
  /// 正在跑的那条按哪个 base 取用户改过的项。
  private var overrideKey: String?
  /// 最后一帧：换周期（同一只品种）时直接补给新的 selection，不必重订。
  private(set) var last: OrderFlowSnapshot?

  /// 开着、在前台、首帧已画、品种事实已到、这只还没在跑，就起一条。起了返回 true。
  mutating func start(symbol: String, foreground: Bool, provider: (any MarketProvider)?,
                      paths: Paths, log: FeedLog, publish: @escaping Publish) -> Bool {
    guard enabled, foreground, feed == nil, !symbol.isEmpty, chartReady == symbol,
          let provider, let facts = facts(symbol) else { return false }
    let token = UUID()
    let directory = Self.directory(in: paths)
    guard let next = OrderFlowFeed(symbol: symbol, facts: facts, override: overrides[facts.overrideKey],
                                   provider: provider, directory: directory, log: log,
                                   sink: { frame in await publish(token, frame) }) else { return false }
    feed = next; self.token = token; last = nil; overrideKey = facts.overrideKey
    Task.detached(priority: .utility) {
      OrderFlowFeed.sweep(directory: directory, nowMs: Int64(Date().timeIntervalSince1970 * 1000))
    }
    Task { await next.start() }
    return true
  }

  /// 换一份用户改过的项；正在跑的那条的 base 变了就推给它。
  mutating func setOverrides(_ next: [String: OrderFlowOverride]) {
    let before = overrideKey.flatMap { overrides[$0] }
    overrides = next
    guard let feed, let key = overrideKey else { return }
    let after = next[key]
    if after != before { Task { await feed.setOverride(after) } }
  }

  /// 退订并清簿。`forgetChart` 为 true 时连「首帧已画」也清掉（换品种、换线路）。
  /// 原来有一条在跑就返回 true（调用方据此发一帧 nil 清图）。
  mutating func stop(forgetChart: Bool) -> Bool {
    if forgetChart { chartReady = nil }
    guard let dying = feed else { return false }
    feed = nil; token = UUID(); last = nil; overrideKey = nil
    Task { await dying.stop() }
    return true
  }

  /// 这一帧还算不算数：来自当前这条、品种对得上。算数就记成最后一帧。
  mutating func accept(_ frame: OrderFlowSnapshot, token: UUID, symbol: String) -> Bool {
    guard feed != nil, token == self.token, frame.symbol == symbol else { return false }
    last = frame
    return true
  }

  /// 日志落盘目录：缓存根下的 `orderflow/`。
  static func directory(in paths: Paths) -> URL {
    paths.root.appendingPathComponent("orderflow", isDirectory: true)
  }
}
