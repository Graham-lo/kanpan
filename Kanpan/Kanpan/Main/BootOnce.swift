import SwiftUI

/// 启动那一下「只跑一次」的闸。
///
/// `MainScreen` 的 `boot()` 挂在两个入口上：`.onAppear` 和 `.task`。两个都要——
/// `.onAppear` 是同步的，首帧之前就能把线接好；`.task` 兜底那些 `onAppear` 没按时来的
/// 场面（审查 B.9）。代价是两个入口都会进来一次，所以真正干活的只能是先到的那一个。
///
/// 从前这道闸是 `MainScreen` 里一个 `@State var didBoot` 加一句 `guard`，写在 app
/// 工程那几千行里，没有任何用例量得到（审查 B.10 BT-20）。收成这一个小件之后，
/// 「两个入口真的都进来了、boot 只跑了一次」可以在模拟器上直接挂一张 SwiftUI 视图量。
///
/// 先置位、后干活：`work` 里面哪怕同步地又触发了一次入口（重入），也是空转。
@MainActor final class BootLatch {
  private(set) var fired = false
  /// 两个入口一共进来了几次（含空转的）。观测与测试用。
  private(set) var attempts = 0
  /// 每进来一次就报一声。只给用例用来「等到第二个入口也到了」，不靠 sleep 去猜。
  var onAttempt: (@MainActor () -> Void)?

  init() {}

  /// 第一次调用执行 `work` 并返回 `true`；之后一律空转、返回 `false`。
  @discardableResult
  func run(_ work: @MainActor () -> Void) -> Bool {
    attempts += 1
    defer { onAttempt?() }
    guard !fired else { return false }
    fired = true
    work()
    return true
  }
}

/// 把 `.onAppear` 和 `.task` 两个启动入口接到同一道 `BootLatch` 上。
///
/// 一个修饰符顶原来两个：`MainScreen` 那条链上少套一层 `ModifiedContent`
/// （iOS 27 启动栈溢出那件事，见 `MainScreenParts.swift`）。
struct BootOnce: ViewModifier {
  let boot: @MainActor () -> Void
  @State private var latch: BootLatch

  init(latch: BootLatch = BootLatch(), boot: @escaping @MainActor () -> Void) {
    self.boot = boot
    _latch = State(initialValue: latch)
  }

  func body(content: Content) -> some View {
    content
      .onAppear { latch.run(boot) }
      .task { latch.run(boot) }
  }
}
