import Foundation
import KanpanCore
import KanpanNetwork

/// `RoutedMarketFeed` 里主力订单流这一格的全部状态与起停。路由只在几个时刻调它（开关、首帧、
/// 换品种 / 换线路、前后台、停），其余都收在这里，不散在路由的字段里。
struct OrderFlowSlot {
  typealias Publish = @Sendable (_ token: UUID, _ frame: OrderFlowSnapshot) async -> Void

  /// 指标开关。
  var enabled = false
  /// 合约表里的最小变动价，由 app 按品种给。
  var tick: @Sendable (String) -> Double? = { _ in nil }
  /// 哪只品种的 K 线已经交给界面（历史 ≥ 3 根）。簿订阅只在这之后才发，不跟首屏抢。
  var chartReady: String?
  /// 正在跑的那一条订阅；`token` 跟着换，迟到的旧帧因此进不来。
  private(set) var feed: OrderFlowFeed?
  private(set) var token = UUID()
  /// 最后一帧：换周期（同一只品种）时直接补给新的 selection，不必重订。
  private(set) var last: OrderFlowSnapshot?

  /// 开着、在前台、首帧已画、这只还没在跑，就起一条。起了返回 true。
  mutating func start(symbol: String, foreground: Bool, provider: (any MarketProvider)?,
                      paths: Paths, log: FeedLog, publish: @escaping Publish) -> Bool {
    guard enabled, foreground, feed == nil, !symbol.isEmpty, chartReady == symbol,
          let provider else { return false }
    let token = UUID()
    guard let next = OrderFlowFeed(symbol: symbol, provider: provider, tick: tick(symbol),
                                   directory: Self.directory(in: paths), log: log,
                                   sink: { frame in await publish(token, frame) }) else { return false }
    feed = next; self.token = token; last = nil
    Task { await next.start() }
    return true
  }

  /// 退订并清簿。`forgetChart` 为 true 时连「首帧已画」也清掉（换品种、换线路）。
  /// 原来有一条在跑就返回 true（调用方据此发一帧 nil 清图）。
  mutating func stop(forgetChart: Bool) -> Bool {
    if forgetChart { chartReady = nil }
    guard let dying = feed else { return false }
    feed = nil; token = UUID(); last = nil
    Task { await dying.stop() }
    return true
  }

  /// 这一帧还算不算数：来自当前这条、品种对得上。算数就记成最后一帧。
  mutating func accept(_ frame: OrderFlowSnapshot, token: UUID, symbol: String) -> Bool {
    guard feed != nil, token == self.token, frame.symbol == symbol else { return false }
    last = frame
    return true
  }

  /// 标定落盘目录：缓存根下的 `orderflow/`。
  static func directory(in paths: Paths) -> URL {
    paths.root.appendingPathComponent("orderflow", isDirectory: true)
  }
}
