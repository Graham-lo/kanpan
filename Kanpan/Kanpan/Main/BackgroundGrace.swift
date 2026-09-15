import UIKit

/// 进后台后的那一小段运行时间。
///
/// iOS 在 app 进后台时并不会立刻冻住进程，但要主动把这段时间要下来，否则
/// 随时可能被挂起。要下来之后，`MarketFeed` 与 `QuoteBook` 的宽限窗口才真的
/// 有 CPU 去跑——短暂切走再切回来时连接还活着，回来就是现价，不用重连。
///
/// 系统给的额度有限（约 30 秒），到点必须自己结束，否则会被强杀。这里比
/// 两处宽限窗口多留一点，等它们先收工。
@MainActor
final class BackgroundGrace {
  private var id: UIBackgroundTaskIdentifier = .invalid
  private var expiry: Task<Void, Never>?
  private let seconds: Double

  init(seconds: Double = 27) { self.seconds = seconds }

  func begin() {
    guard id == .invalid else { return }
    id = UIApplication.shared.beginBackgroundTask(withName: "kanpan.keepFeed") { [weak self] in
      // 系统提前收回额度：立刻结束，别等自己的定时器。
      MainActor.assumeIsolated { self?.end() }
    }
    guard id != .invalid else { return }
    expiry = Task { [weak self] in
      try? await Task.sleep(nanoseconds: UInt64((self?.seconds ?? 27) * 1_000_000_000))
      guard let self, !Task.isCancelled else { return }
      self.end()
    }
  }

  func end() {
    expiry?.cancel(); expiry = nil
    guard id != .invalid else { return }
    UIApplication.shared.endBackgroundTask(id)
    id = .invalid
  }

  deinit { expiry?.cancel() }
}
