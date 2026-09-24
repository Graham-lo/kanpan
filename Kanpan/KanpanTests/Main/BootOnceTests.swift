import SwiftUI
import Testing
import UIKit
@testable import Kanpan

// §B.10 回归规格 BT-20：`MainScreen` 的 `boot()` 挂在 `.onAppear` 和 `.task` 两个入口上，
// 两个入口都会进来，真正干活的只能有一次。量的是 `MainScreen` 实际用的那只修饰符
// （`BootOnce`），假模型 + 计数器代替真的行情 / 报价簿 / 账号接线。

/// 假的「启动要接的那几摊」。每一摊都数自己被接了几次。
@MainActor private final class FakeMarket { var starts = 0; func start() { starts += 1 } }
@MainActor private final class FakeQuotes { var configures = 0; func configure() { configures += 1 } }
@MainActor private final class FakeAccount { var wires = 0; func wire() { wires += 1 } }
@MainActor private final class Counter { var boots = 0 }
@MainActor private final class Once { var done = false }

@MainActor private struct Rig {
  let counter = Counter(), market = FakeMarket(), quotes = FakeQuotes(), account = FakeAccount()
  var boot: @MainActor () -> Void {
    { [counter, market, quotes, account] in
      counter.boots += 1
      account.wire(); market.start(); quotes.configure()
    }
  }
}

private struct Probe: View {
  let latch: BootLatch
  let boot: @MainActor () -> Void
  var body: some View {
    Color.clear.frame(width: 10, height: 10).modifier(BootOnce(latch: latch, boot: boot))
  }
}

@MainActor
@Suite("BT-20 两个启动入口只实际执行一次 boot", .serialized, .timeLimit(.minutes(1)))
struct BootOnceTests {

  @Test("闸本身：两个入口按两种先后各进一次，boot 都只跑一次")
  func latchRunsOnceInEitherOrder() {
    for _ in 0..<2 {
      let rig = Rig(); let latch = BootLatch()
      #expect(latch.run(rig.boot) == true)
      #expect(latch.run(rig.boot) == false)
      #expect(latch.attempts == 2)
      #expect(rig.counter.boots == 1)
      #expect(rig.market.starts == 1 && rig.quotes.configures == 1 && rig.account.wires == 1)
    }
  }

  @Test("boot 里同步地又撞进一次入口（重入）：空转，不会二次接线")
  func reentrantAttemptIsANoOp() {
    let rig = Rig(); let latch = BootLatch()
    latch.run { rig.boot(); latch.run(rig.boot) }
    #expect(latch.attempts == 2)
    #expect(rig.counter.boots == 1)
  }

  @Test("真挂进窗口：.onAppear 和 .task 两个入口都到了，boot 只跑一次")
  func bothSwiftUIEntriesFireButBootRunsOnce() async throws {
    let rig = Rig(); let latch = BootLatch()
    var window: UIWindow?
    // 等的是「第二个入口也到了」这件事本身（`onAttempt`），不是一段时间。
    // 十秒的兜底只在入口根本不来时才会走到，那本身就是失败。
    let arrived: Bool = await withCheckedContinuation { continuation in
      let once = Once()
      let finish: @MainActor (Bool) -> Void = { ok in
        guard !once.done else { return }
        once.done = true; continuation.resume(returning: ok)
      }
      latch.onAttempt = { if latch.attempts >= 2 { finish(true) } }
      Task { @MainActor in
        try? await Task.sleep(for: .seconds(10))
        finish(false)
      }
      let host = UIWindow(frame: CGRect(x: 0, y: 0, width: 100, height: 100))
      host.rootViewController = UIHostingController(rootView: Probe(latch: latch, boot: rig.boot))
      host.makeKeyAndVisible()
      host.layoutIfNeeded()
      window = host
    }
    latch.onAttempt = nil
    #expect(arrived, "两个启动入口没有都进来（attempts = \(latch.attempts)），这条量不到双入口")
    #expect(latch.attempts == 2)
    #expect(rig.counter.boots == 1, "boot 跑了 \(rig.counter.boots) 次")
    #expect(rig.market.starts == 1 && rig.quotes.configures == 1 && rig.account.wires == 1)

    // 视图重新求值（父视图刷新）不会换掉那道闸：再布局一遍，boot 仍然只有一次。
    window?.rootViewController?.view.setNeedsLayout()
    window?.layoutIfNeeded()
    #expect(rig.counter.boots == 1)
    window?.isHidden = true
    window = nil
  }
}
