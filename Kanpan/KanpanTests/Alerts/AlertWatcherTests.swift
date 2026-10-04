import Foundation
import KanpanCore
import Testing
import UIKit
@testable import Kanpan

/// 「响了」从存档到用户眼前那一段（`AlertWatcher`），接上真的 `AlertEngine` 一起量：
/// 价撞线 → 通知中心放一条、宿主说一句 → 从存档里删掉 → 同一条再也不说第二遍；
/// 换档案（登录 / 切账号）之后，上一个人的提醒既不再被判，也不被当成新触发念出来。
/// 深度审查 E 线补的用例（之前 `AlertWatcher` 没有任何用例）。
@Suite("提醒 · 响了之后")
@MainActor
struct AlertWatcherTests {
  private let m0: Int64 = 1_758_000_000_000
  private func minute(_ n: Int64) -> Int64 { m0 + n * 60_000 }

  private func fileStore() -> AlertFileStore {
    AlertFileStore(url: FileManager.default.temporaryDirectory
      .appendingPathComponent("alerts-\(UUID().uuidString).json"))
  }

  private func hline(_ id: String, p: Double) -> Drawing {
    Drawing(id: id, kind: .hline, points: [DrawPoint(t: Double(m0), p: p)])
  }

  /// `AlertWatcher` 收存档走主队列（`receive(on: DispatchQueue.main)`），让主线程转几圈等它收完。
  private func drain(until done: () -> Bool) async {
    for _ in 0..<200 where !done() { try? await Task.sleep(for: .milliseconds(5)) }
    try? await Task.sleep(for: .milliseconds(20))
  }

  private struct Rig {
    let store: AlertStore
    let engine: AlertEngine
    let watcher: AlertWatcher
  }

  private final class Log {
    var notified: [String] = []
    var said: [String] = []
  }

  private func rig(_ log: Log) -> Rig {
    let store = AlertStore(store: fileStore())
    let engine = AlertEngine()
    let watcher = AlertWatcher()
    watcher.serverSendsWebhooks = { true }
    watcher.present = { alert, _, _, _ in log.notified.append(alert.id) }
    watcher.onFired = { log.said.append($0.id) }
    engine.attach(store)
    watcher.attach(store)
    return Rig(store: store, engine: engine, watcher: watcher)
  }

  @Test("手指按着列表滚动（主 runloop 只转 tracking 模式）时提醒照样说出来、照样收尾，不等松手")
  func firesWhileListIsTracking() async {
    let log = Log()
    let r = rig(log)
    let alert = r.store.add(drawing: hline("d1", p: 100), symbol: "BTCUSDT", now: Double(m0))!
    // 引擎按存档重算要盯的品种排在下一拍（`receive(on:)`），盯上了再喂价。
    await drain { r.engine.watched.contains(InstrumentID.canonical("BTCUSDT")) }
    let main = CFRunLoopGetMain()!
    let tracking = CFRunLoopMode(RunLoop.Mode.tracking.rawValue as CFString)
    // 在 runloop 的 perform 回调里（不在主队列的块里）只转 tracking 模式：主队列在 common 模式里，
    // 照样被服务；Combine 的 `RunLoop.main` 调度只排在 default 模式，这期间一个字都收不到。
    let heard: Bool = await withCheckedContinuation { done in
      CFRunLoopPerformBlock(main, CFRunLoopMode.commonModes.rawValue) {
        MainActor.assumeIsolated {
          r.engine.observe(symbol: "BTCUSDT", price: 100, timeMs: self.minute(1) + 1_000)
          for _ in 0..<60 where log.said.isEmpty || r.store.alert(id: alert.id) != nil {
            _ = CFRunLoopRunInMode(tracking, 0.05, false)
          }
          done.resume(returning: log.said == [alert.id] && r.store.alert(id: alert.id) == nil)
        }
      }
      CFRunLoopWakeUp(main)
    }
    #expect(heard, "滚动期间就该说出来并从存档删掉")
    #expect(log.notified == [alert.id])
  }

  @Test("撞线：通知一条、说一句、随即从存档删掉；后面再撞也不再说")
  func firesOnceThenDeletes() async {
    let log = Log()
    let r = rig(log)
    let alert = r.store.add(drawing: hline("d1", p: 100), symbol: "BTCUSDT", now: Double(m0))!
    // 引擎按存档重算要盯的品种排在下一拍（`receive(on:)`），盯上了再喂价。
    await drain { r.engine.watched.contains(InstrumentID.canonical("BTCUSDT")) }
    r.engine.observe(symbol: "BTCUSDT", price: 100, timeMs: minute(1) + 1_000)
    await drain { r.store.alert(id: alert.id) == nil }
    #expect(log.notified == [alert.id])
    #expect(log.said == [alert.id])
    #expect(r.store.alert(id: alert.id) == nil, "触发即删")
    #expect(r.engine.watched.isEmpty, "删掉之后这只品种不再盯")

    // 再来几口撞同一个价：存档里已经没有它，一个字都不该再说。
    r.engine.observe(symbol: "BTCUSDT", price: 100, timeMs: minute(1) + 2_000)
    r.engine.observe(symbol: "BTCUSDT", price: 100, timeMs: minute(2) + 1_000)
    await drain { false }
    #expect(log.notified == [alert.id])
    #expect(log.said == [alert.id])
  }

  @Test("在后台响的只留通知，不动界面")
  func backgroundFiresOnlyNotify() async {
    let log = Log()
    let r = rig(log)
    let alert = r.store.add(drawing: hline("d1", p: 100), symbol: "BTCUSDT", now: Double(m0))!
    r.watcher.setForeground(false)
    // 后台那一段由服务端判，回前台拉同步换下来一条已触发。
    var synced = r.store.archive
    synced.alerts[0].status = .fired
    synced.alerts[0].firedAt = Double(minute(3))
    synced.alerts[0].firedPrice = 100.2
    r.store.publishSynced(synced)
    await drain { r.store.alert(id: alert.id) == nil }
    #expect(log.notified == [alert.id])
    #expect(log.said.isEmpty)
  }

  @Test("换档案：新档案里躺着的旧已触发不念、照样清掉；上一个人的提醒不再被判")
  func switchingProfilesNeitherReplaysNorJudgesTheOldOne() async {
    let log = Log()
    let r = rig(log)
    let old = r.store.add(drawing: hline("d1", p: 100), symbol: "BTCUSDT", now: Double(m0))!
    await drain { !r.engine.watched.isEmpty }
    #expect(r.engine.watched == [InstrumentID.canonical("BTCUSDT")])

    // 另一个人的档案：一条早就响过、还没来得及删的，一条在等的 ETH。
    var stale = Alert(symbol: "SOLUSDT", drawingID: "s1",
                      lines: [AlertLine(points: [DrawPoint(t: Double(m0), p: 50)], extendLeft: true, extendRight: true)],
                      armedAt: Double(m0), title: "旧的", created: Double(m0))
    stale.status = .fired; stale.firedAt = Double(m0); stale.firedPrice = 50
    let eth = Alert(symbol: "ETHUSDT", drawingID: "e1",
                    lines: [AlertLine(points: [DrawPoint(t: Double(m0), p: 200)], extendLeft: true, extendRight: true)],
                    armedAt: Double(m0), title: "ETH", created: Double(m0))
    r.store.useStorage(fileStore(), archive: AlertArchive(alerts: [stale, eth]))
    await drain { r.store.alert(id: stale.id) == nil }
    #expect(log.notified.isEmpty, "换档案带进来的旧已触发不念")
    #expect(r.store.alert(id: stale.id) == nil, "但照样清掉")
    #expect(r.engine.watched == [InstrumentID.canonical("ETHUSDT")])

    // 上一个人的 BTC 那条：价撞上来也不判，新档案里一个字都不多。
    r.engine.observe(symbol: "BTCUSDT", price: 100, timeMs: minute(1) + 1_000)
    await drain { false }
    #expect(r.store.alert(id: old.id) == nil)
    #expect(r.store.all.map(\.id) == [eth.id])
    #expect(log.notified.isEmpty)

    // 新档案自己的照常响。
    r.engine.observe(symbol: "ETHUSDT", price: 200, timeMs: minute(1) + 1_000)
    await drain { r.store.alert(id: eth.id) == nil }
    #expect(log.notified == [eth.id])
  }
}
