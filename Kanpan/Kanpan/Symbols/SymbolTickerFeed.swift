import Foundation
import KanpanCore

// ============================================================ 全市场行情流
//
// A5.7：「每行价格实时跳动（`!ticker@arr`）；出页面后退订（日志确认）」。
//
// 数据层（KanpanData）目前只有单品种的 `ticker24h` REST，没有 `!ticker@arr`
// 这条全市场组合流；补它属于数据层的活，不在品种页这一半里。
// 所以这里只定一个最小切面：品种页负责在**进页 start / 出页 stop**，
// 谁来喂由宿主决定。真流接上时写一个 `BinanceAllTickerFeed` 实现它即可，
// 品种页一行都不用改。

/// 品种页的行情来源。进页订阅、出页退订。
@MainActor
protocol SymbolTickerFeed: AnyObject {
  /// 开始推送。`onUpdate` 会被多次调用，每次给一批变动的 24h 行情。
  func start(onUpdate: @escaping @MainActor ([Ticker]) -> Void)
  /// 停止推送，并保证 `onUpdate` 之后不再被调用。
  func stop()
}

/// 固定快照，推一次就完事。预览、单测、离线时用。
@MainActor
final class StaticTickerFeed: SymbolTickerFeed {
  private let snapshot: [Ticker]
  /// start / stop 各被调用了几次——A5.7 的「退订」在单测里就靠这个断言。
  private(set) var startCount = 0
  private(set) var stopCount = 0
  private(set) var isRunning = false
  private var sink: (@MainActor ([Ticker]) -> Void)?

  init(_ snapshot: [Ticker]) { self.snapshot = snapshot }

  func start(onUpdate: @escaping @MainActor ([Ticker]) -> Void) {
    startCount += 1
    isRunning = true
    sink = onUpdate
    onUpdate(snapshot)
  }

  func stop() {
    guard isRunning else { return }
    stopCount += 1
    isRunning = false
    sink = nil
  }

  /// 测试里手动推一批，模拟价格跳动。停掉之后推不进去。
  func push(_ batch: [Ticker]) { sink?(batch) }
}
