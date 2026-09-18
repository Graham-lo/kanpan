import SwiftUI
import UIKit

/// **全 app 唯一一处读前后台的地方。**
///
/// 为什么要有这么个东西：在这之前，「app 要走了」这件事同时有三个互不知情的听众——
/// `MainScreen` 的 `scenePhase`（两个 `onChange`，而且两处对「离开前台」的定义还不一样：
/// 一处 `switch` 把 `.inactive` 落进了 `default`，另一处写的是 `!= .active`）、
/// `AppAccountBridge` 自己挂的 `didEnterBackgroundNotification`。它们都要在那一刻写点
/// 东西下去，谁先谁后没人定义过，而顺序恰恰是要命的：
///
/// **先让所有产数据的落盘，最后才排空同步存档的写盘队列。**
/// 反过来的话，存档队列先排空、`ChartViewport` 后脚才把根宽交给 `PrefsStore`，那次
/// 同步操作就只留在内存里，app 一被杀就没了——正是用户看到的「缩小后立刻杀掉，
/// 回来不是缩小后的样子」。
///
/// 所以这里定死两件事：
/// 1. **登记制**。谁要在离开前台时落点什么，来 `register(id:priority:flush:)` 报个到。
///    不许再自己去挂 `UIApplication` 的通知，也不许再多读一处 `scenePhase`。
/// 2. **顺序显式**。`priority` 小的先跑；`.data`（产数据的）在前，`.sync`（排空存档
///    写盘队列的）在最后。这不是「碰巧现在是这个顺序」，是**规定**。
///
/// 另外补了一刀 `willTerminate`：这仓库以前一处都没有。系统在杀之前给的那一下，
/// 是最后一次落盘机会，白扔可惜。
@MainActor
final class AppLifecycle {
  static let shared = AppLifecycle()

  /// 落盘顺序。数字小的先跑。
  enum Priority: Int {
    /// 产数据的：偏好、根宽、复盘草稿……凡是「用户做过的事还没落到盘上」的都属这一档。
    case data = 0
    /// 收尾的：把同步存档的写盘队列排空。**必须排在所有 `.data` 后面**，
    /// 否则上面那些人刚生出来的操作赶不上这趟车。
    case sync = 100
  }

  private struct Hook { let priority: Int; let seq: Int; let flush: () -> Void }
  private var hooks: [String: Hook] = [:]
  private var seq = 0

  private struct Resources { let leave: () -> Void; let enter: () -> Void }
  private var resources: [String: Resources] = [:]

  private var observers: [NSObjectProtocol] = []
  /// 这一轮「离开前台」是不是已经落过盘了。`.inactive` 紧接着 `.background`，
  /// 不拦一下会白跑两遍。回到 `.active` 时放开。
  private var flushedSinceActive = false

  private init() {}

  // ---------------------------------------------------------------- 登记

  /// 登记一件「离开前台前必须落下去」的事。同一个 `id` 再登记会替换上一个
  /// （`MainScreen` 重建时不会叠加），传 `nil` 注销。
  func register(id: String, priority: Priority, flush: (() -> Void)?) {
    guard let flush else { hooks.removeValue(forKey: id); return }
    seq += 1
    hooks[id] = Hook(priority: priority.rawValue, seq: seq, flush: flush)
  }

  /// 登记一件「进后台要停、回前台要续」的事（行情连接、后台运行额度这类）。
  ///
  /// 和上面那条分开，是因为两者的时机口径**故意不一样**：
  /// - 落盘看的是 `.inactive`（切出去的那一下就写，别赌还能等到 `.background`）。
  /// - 资源看的是 `.background`。`.inactive` 只是弹了个控制中心或系统弹窗，
  ///   这时候掐连接，用户回来还得重连一次，纯亏。
  func registerResources(id: String, leave: @escaping () -> Void, enter: @escaping () -> Void) {
    resources[id] = Resources(leave: leave, enter: enter)
  }

  // ---------------------------------------------------------------- 入口

  /// 挂上系统通知。幂等，`KanpanApp.init()` 调一次就够。
  ///
  /// 为什么 `scenePhase` 之外还要听通知：`willTerminate` 在 `scenePhase` 里没有对应
  /// 的一档；而 `didEnterBackground` 比 SwiftUI 那条路更早、也更可靠。两条路进来
  /// 都会被 `flushedSinceActive` 收敛成一次。
  func start() {
    guard observers.isEmpty else { return }
    let center = NotificationCenter.default
    for name in [UIApplication.didEnterBackgroundNotification, UIApplication.willTerminateNotification] {
      observers.append(center.addObserver(forName: name, object: nil, queue: .main) { _ in
        MainActor.assumeIsolated { AppLifecycle.shared.leaveForeground(final: name == UIApplication.willTerminateNotification) }
      })
    }
  }

  /// `MainScreen` 里那唯一一处 `scenePhase` 把话递到这儿来。别再加第二处。
  func phaseChanged(to phase: ScenePhase) {
    switch phase {
    case .active:
      flushedSinceActive = false
      for r in resources.values { r.enter() }
    case .background:
      leaveForeground(final: false)
      for r in resources.values { r.leave() }
    default:
      // `.inactive`：人已经把手指放上了 app 切换器，或者正要被弹窗盖住。
      // 这一刻就得把欠的落下去——等 `.background` 可能已经太晚了。
      // 资源不动，理由见 `registerResources`。
      leaveForeground(final: false)
    }
  }

  /// 把所有欠的落下去。`final` 表示这是被杀之前最后一下，不吃去重那一层。
  func leaveForeground(final: Bool) {
    if flushedSinceActive && !final { return }
    flushedSinceActive = true
    for hook in hooks.values.sorted(by: { ($0.priority, $0.seq) < ($1.priority, $1.seq) }) { hook.flush() }
  }
}
