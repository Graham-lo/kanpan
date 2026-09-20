import Testing
import Foundation
import KanpanCore
@testable import KanpanSettings

/// 第五轮审查 A.5 用例 7：`pending / adopt / settle` 的一整条序列。
///
/// 报告要的序列是「档案 A，缩放留着没落盘 → 收到同一份档案的旧值 → 抬手 → 切周期 → 返回」，
/// 要断言的是「采用最终本地根宽；pending 清干净；提交次数与 adoptToken 都有明确定义」。
/// `PrefsPersistenceTests` 已经分别盖过「手一松就落盘」「晚到的同档案不许赢」「每到一次货
/// token 跳一格」，缺的正是把它们串成一条的那个次序——以及**提交次数**：这一层对外只有
/// 三个动作（记操作 / 排空存档 / 推服务端），一次 settle 恰好各一次，重复的抬手一次都不许多。
@Suite("A.5 · 视野的落盘时机")
struct ChartViewportA5Tests {

  /// 把 `ChartViewport.Sync` 那三个动作数出来。这层不暴露任何状态，能观察的只有次数与顺序。
  @MainActor
  private final class CountingSync: ChartViewport.Sync {
    var records = 0, flushes = 0, pushes = 0
    /// 调用顺序也记一份：`settle()` 的次序是「记操作 → 排空存档 → 推」，反了就等于
    /// 把用户刚做的动作暴露给一次可能拉回旧值的同步。
    var trace: [String] = []
    func recordLayout() { records += 1; trace.append("record") }
    func flushLayoutArchive() { flushes += 1; trace.append("flush") }
    func pushLayout() { pushes += 1; trace.append("push") }
  }

  @MainActor
  private func make() -> (ChartViewport, PrefsStore, InMemoryPrefsStorage, CountingSync) {
    let box = InMemoryPrefsStorage()
    let store = PrefsStore(storage: box, cache: UnavailableMarketCache())
    let viewport = ChartViewport(owner: store)
    let sync = CountingSync()
    viewport.sync = sync
    return (viewport, store, box, sync)
  }

  @Test("7 缩放没落盘时收到同一份档案的旧值：本地这一捏赢，且只提交一次")
  @MainActor
  func case7_pendingAdoptSettle() {
    let (viewport, store, box, sync) = make()
    let token0 = viewport.adoptToken

    // ① 用户捏到 9.5，手还按着：内存当场认，盘上一个字节都没有，同步也一声不吭。
    viewport.userIsZooming(to: 9.5)
    #expect(viewport.barSpacing == 9.5)
    #expect(box.keys.isEmpty)
    #expect(store.prefs.barSpacing == AICoinBehavior.initialSpacing)
    #expect((sync.records, sync.flushes, sync.pushes) == (0, 0, 0))

    // ② 同一份档案晚到，带着旧值 4：这是「他自己的档案晚到了」，不是换了个人，
    //    所以旧值不许赢；而且这一下要顺手把欠着的 9.5 落掉。
    viewport.adopt(barSpacing: AICoinBehavior.initialSpacing, reason: .sameProfile)
    #expect(viewport.barSpacing == 9.5, "采用的是最终本地根宽")
    #expect(store.prefs.barSpacing == 9.5)
    #expect((sync.records, sync.flushes, sync.pushes) == (1, 1, 1), "落盘 + 同步恰好一轮")
    #expect(sync.trace == ["record", "flush", "push"], "记操作必须排在推之前")
    #expect(viewport.adoptToken == token0, "这一路走的是「保住用户那一捏」，图不用重起点")

    // ③ 抬手：欠账已经在 ② 清掉了，这一下必须是一次纯比较——不写盘，也不再提交。
    let keysAfterSettle = box.keys
    viewport.interactionEnded()
    #expect(box.keys == keysAfterSettle)
    #expect((sync.records, sync.flushes, sync.pushes) == (1, 1, 1), "pending 已清，抬手不该再提交一轮")
    viewport.interactionEnded()
    #expect((sync.records, sync.flushes, sync.pushes) == (1, 1, 1), "抬几次手都一样")

    // ④ 切周期：新图问的是内存那一份，它不等任何定时器，也不受 ② 那份旧档案影响。
    #expect(viewport.barSpacing == 9.5)

    // ⑤ 返回（云端那份终于追上了本地）：这时没有欠账，走的是「让图重新起点」那一支。
    viewport.adopt(barSpacing: 9.5, reason: .sameProfile)
    #expect(viewport.barSpacing == 9.5)
    #expect(viewport.adoptToken == token0 + 1, "到一次货，token 就跳一格——哪怕值没变")
    #expect((sync.records, sync.flushes, sync.pushes) == (1, 1, 1), "到货不是用户动作，不提交")
  }

  @Test("7 手势中途换了属主：欠着的那一捏作废，之后的抬手一次都不许提交")
  @MainActor
  func case7_ownerSwitchDropsPending() {
    let (viewport, store, box, sync) = make()
    let token0 = viewport.adoptToken
    viewport.userIsZooming(to: 9.5)
    viewport.adopt(barSpacing: 2.0, reason: .ownerSwitched)
    #expect(viewport.barSpacing == 2.0, "换了人就以新档案为准")
    #expect(box.keys.isEmpty, "上一个人欠的那一捏不许写到新属主头上")
    #expect(store.prefs.barSpacing == AICoinBehavior.initialSpacing)
    #expect(viewport.adoptToken == token0 + 1, "换属主也是一次到货")
    viewport.interactionEnded()
    #expect(box.keys.isEmpty, "pending 是真的清了，不是压在那儿等下一次抬手")
    #expect((sync.records, sync.flushes, sync.pushes) == (0, 0, 0))
  }

  @Test("7 没捏过就抬手：不写盘、不提交；真捏过才提交，且一次手势只提交一轮")
  @MainActor
  func case7_settleIsIdempotent() {
    let (viewport, _, box, sync) = make()
    viewport.interactionEnded()
    #expect(box.keys.isEmpty)
    #expect((sync.records, sync.flushes, sync.pushes) == (0, 0, 0))

    // 一次手势里每帧都在报，落盘只该发生在手抬起来那一下。
    for w in stride(from: 4.0, to: 8.0, by: 0.25) { viewport.userIsZooming(to: w) }
    #expect(box.keys.isEmpty)
    viewport.interactionEnded()
    #expect((sync.records, sync.flushes, sync.pushes) == (1, 1, 1))
    #expect(viewport.barSpacing == 7.75)

    // 报同一个值不算改动：连 pending 都不该产生。
    viewport.userIsZooming(to: 7.75)
    viewport.interactionEnded()
    #expect((sync.records, sync.flushes, sync.pushes) == (1, 1, 1), "没真变过就不提交")
  }

  @Test("7 退后台是兜底不是时机：正常抬过手之后它一次都不提交")
  @MainActor
  func case7_backgroundIsOnlyABackstop() {
    let (viewport, _, _, sync) = make()
    viewport.userIsZooming(to: 6.0)
    viewport.interactionEnded()
    #expect((sync.records, sync.flushes, sync.pushes) == (1, 1, 1))
    viewport.willLeaveForeground()
    #expect((sync.records, sync.flushes, sync.pushes) == (1, 1, 1))

    // 反过来：手势中途直接被切后台（抬手事件根本没来），兜底要把它接住。
    viewport.userIsZooming(to: 6.5)
    viewport.willLeaveForeground()
    #expect((sync.records, sync.flushes, sync.pushes) == (2, 2, 2))
  }
}
