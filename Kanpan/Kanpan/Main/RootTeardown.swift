import Foundation

/// 「这棵根真的没了」——SwiftUI 里唯一可靠的那个信号。
///
/// 为什么需要它：`MainScreen` 把行情模型、报价簿、板块流、后台运行额度都挂在自己的
/// `@State` 上，可 SwiftUI 从不告诉你「这个 View 被销毁了」。`onDisappear` 说的是
/// 「这一帧不画了」——盖一层全屏 cover、切一格标签、转个屏都会叫它，那些时候根还
/// 活着，照着它停流等于把用户自己的行情掐掉。
///
/// 分得清这两件事的只有 `@State` 的**存储寿命**：`@State` 跟着视图身份走，这份存储
/// 被释放，就说明这棵根的身份真的没了（场景断开、根被顶掉、进程收尾），这时候
/// `deinit` 才响。所以把「根没了要做什么」装进一个 `@State` 持有的对象里。
///
/// 用法（`MainScreen.wireLifecycle()`）：
/// ```swift
/// teardown.onTeardown { [market, quotes] in market.stop(); quotes.shutdown() }
/// ```
/// **闭包一定要写显式捕获列表**：直接写 `market.stop()` 捕获的是 View 结构体自己，
/// 而 `@State` 的包装器里握着这份存储的强引用——那就成了环，`deinit` 永远不来。
final class RootTeardown {
  /// 根没了要跑的那件事。
  ///
  /// `nonisolated(unsafe)`：`deinit` 不在主 actor 上，得能从那儿读到它。写只发生在
  /// 主 actor（`onTeardown`），读只发生在 `deinit`（那时已经没有别的引用），没有并发。
  nonisolated(unsafe) private var stop: (@Sendable () -> Void)?

  /// 装上「根没了要做的事」。重复装以最后一次为准。
  @MainActor
  func onTeardown(_ body: @escaping @Sendable @MainActor () -> Void) {
    stop = { MainActor.assumeIsolated(body) }
  }

  deinit {
    guard let stop else { return }
    self.stop = nil
    // SwiftUI 在主线程上释放 `@State` 的存储，这是常态，直接跑。真落到别的线程上时
    // 排一次主队列——绝不在这儿断言：为了收摊把 app 崩掉是本末倒置。
    if Thread.isMainThread { stop() } else { DispatchQueue.main.async { stop() } }
  }
}
