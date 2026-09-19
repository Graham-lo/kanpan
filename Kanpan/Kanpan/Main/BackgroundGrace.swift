import UIKit

/// 进后台后的那一小段运行时间。
///
/// iOS 在 app 进后台时并不会立刻冻住进程，但要主动把这段时间要下来，否则
/// 随时可能被挂起。要下来之后，`MarketFeed` 与 `QuoteBook` 的宽限窗口才真的
/// 有 CPU 去跑——短暂切走再切回来时连接还活着，回来就是现价，不用重连。
///
/// 系统给的额度有限（约 30 秒），到点必须自己结束，否则会被强杀。这里比
/// 两处宽限窗口多留一点（27 秒 > 25 秒），等它们先收工。
@MainActor
final class BackgroundGrace {
  /// 要额度 / 还额度这两下的实际动作。
  ///
  /// 默认走 `UIApplication`。做成可注入是为了能测「`deinit` 到底有没有还」——
  /// 单元测试进程里 `beginBackgroundTask` 要不到真额度，而那恰恰是要测的一条。
  /// 两个都是 `@Sendable`：`deinit` 不在主 actor 上，得能从那儿把 `end` 拿出来用。
  typealias Begin = @Sendable (@escaping @Sendable () -> Void) -> UIBackgroundTaskIdentifier
  typealias End = @Sendable (UIBackgroundTaskIdentifier) -> Void

  /// `id` / `begin` / `end` 都要从 `deinit` 里读到，所以不进 actor 的隔离存储。
  /// 写只发生在主 actor，读只发生在主 actor 或 `deinit`（那时已经没有别的引用）。
  nonisolated(unsafe) private var id: UIBackgroundTaskIdentifier = .invalid
  private var expiry: Task<Void, Never>?
  private let seconds: Double
  nonisolated private let beginTask: Begin
  nonisolated private let endTask: End

  init(seconds: Double = 27,
       begin: @escaping Begin = { expired in
         MainActor.assumeIsolated {
           UIApplication.shared.beginBackgroundTask(withName: "kanpan.keepFeed", expirationHandler: expired)
         }
       },
       end: @escaping End = { id in
         MainActor.assumeIsolated { UIApplication.shared.endBackgroundTask(id) }
       }) {
    self.seconds = seconds
    self.beginTask = begin
    self.endTask = end
  }

  func begin() {
    guard id == .invalid else { return }
    id = beginTask { [weak self] in
      // 系统提前收回额度：立刻结束，别等自己的定时器。
      MainActor.assumeIsolated { self?.end() }
    }
    guard id != .invalid else { return }
    let seconds = self.seconds
    expiry = Task { [weak self] in
      try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
      guard let self, !Task.isCancelled else { return }
      self.end()
    }
  }

  func end() {
    expiry?.cancel(); expiry = nil
    guard id != .invalid else { return }
    endTask(id)
    id = .invalid
  }

  deinit {
    expiry?.cancel()
    // 额度必须真的还回去。这儿原来只 cancel 了自己的定时器：那只是让「27 秒后自己还」
    // 这条路断掉，系统那边的后台任务照样开着——轻则 app 一直被算成「正在后台干活」，
    // 重则额度耗尽时被系统直接杀掉（而且日志里看不出是谁欠的）。
    guard id != .invalid else { return }
    let leaked = id
    id = .invalid
    if Thread.isMainThread { endTask(leaked) }
    else {
      // 兜底：不在主线程上释放时排一次主队列，别在 deinit 里断言。
      let end = endTask
      DispatchQueue.main.async { end(leaked) }
    }
  }
}
