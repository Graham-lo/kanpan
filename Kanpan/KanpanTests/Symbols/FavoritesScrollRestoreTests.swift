import Testing
@testable import Kanpan

/// 回到自选页那一段「滚回原来那一行」要停得下来：手指落下、换分类、整页消失时，
/// 正在跑的那一段下一次醒来就停在原地，不再滚、不再记落脚点（深度审查 D 线 2026-10-04）。
@Suite(.serialized) @MainActor struct FavoritesScrollRestoreTests {
  /// 一段假的还原：四轮，每轮先睡一小会儿、醒来先问 `live()`，跑完才算「落地」。
  final class Probe { var rounds = 0; var landed = false }
  private func run(_ restore: FavoritesScrollRestore, _ probe: Probe) {
    restore.start { live in
      for _ in 0..<4 {
        try? await Task.sleep(for: .milliseconds(30))
        guard live() else { return }
        probe.rounds += 1
      }
      probe.landed = true
    }
  }
  private func until(_ done: () -> Bool) async {
    for _ in 0..<200 where !done() { try? await Task.sleep(for: .milliseconds(5)) }
  }

  @Test func stoppingMidwayHaltsAtTheNextWakeUp() async {
    let restore = FavoritesScrollRestore(), probe = Probe()
    run(restore, probe)
    await until { probe.rounds >= 1 }
    #expect(probe.rounds == 1)
    // 人按住了表。
    restore.stop()
    try? await Task.sleep(for: .milliseconds(200))
    #expect(probe.rounds == 1)
    #expect(!probe.landed)
  }

  @Test func startingAgainRetiresThePreviousRun() async {
    let restore = FavoritesScrollRestore(), first = Probe(), second = Probe()
    run(restore, first)
    await until { first.rounds >= 1 }
    // 又回到这一页一次：旧那一段不许接着拽表。
    run(restore, second)
    await until { second.landed }
    #expect(second.landed)
    #expect(second.rounds == 4)
    #expect(!first.landed)
    #expect(first.rounds <= 2)
  }

  @Test func anUninterruptedRunStillLands() async {
    let restore = FavoritesScrollRestore(), probe = Probe()
    run(restore, probe)
    await until { probe.landed }
    #expect(probe.landed)
    #expect(probe.rounds == 4)
  }

  @Test func stoppingWithNothingRunningIsHarmless() {
    let restore = FavoritesScrollRestore()
    restore.stop(); restore.stop()
  }
}
