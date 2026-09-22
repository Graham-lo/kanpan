import Foundation
import Testing
import KanpanAccount
@testable import KanpanMain

// §B.10 回归规格 BT-13 / BT-14：离开前台那一下的落盘钩子。
//
// 两条都用 `AppLifecycle.shared`（全 app 唯一一份），所以套件都是 `.serialized`，
// 而且 BT-13 的用例全是**同步**的：中途没有一个 `await`，别的用例插不进来。
// 进门先 `phaseChanged(.active)` 把「这一轮已经落过盘」清掉，出门把自己登记的钩子摘干净。

/// 用例里攒记录用。
@MainActor private final class Trail {
  var log: [String] = []
}

/// 写盘队列那一侧（不在主线程上）往回报东西用。
private final class LockedLog: @unchecked Sendable {
  private let lock = NSLock()
  private var items: [String] = []
  func add(_ s: String) { lock.lock(); items.append(s); lock.unlock() }
  var all: [String] { lock.lock(); defer { lock.unlock() }; return items }
}

// ---------------------------------------------------------------- BT-13

@MainActor
@Suite("BT-13 离开前台的落盘钩子：次数与先后", .serialized)
struct LifecycleHookOrderTests {

  /// 故意**先登记 `.sync`、后登记 `.data`**：先后只能由档位定，不能由登记顺序定。
  /// 每一档登记两个，看得出同档之内按登记先后、跨档严格 data 在前。
  private func install(_ trail: Trail) -> [AppLifecycle.HookToken] {
    let life = AppLifecycle.shared
    return [
      life.register(id: "bt13.sync.1", priority: .sync) { [trail] in trail.log.append("sync1") },
      life.register(id: "bt13.sync.2", priority: .sync) { [trail] in trail.log.append("sync2") },
      life.register(id: "bt13.data.1", priority: .data) { [trail] in trail.log.append("data1") },
      life.register(id: "bt13.data.2", priority: .data) { [trail] in trail.log.append("data2") },
    ]
  }
  private func uninstall(_ tokens: [AppLifecycle.HookToken]) {
    for token in tokens { AppLifecycle.shared.unregister(hook: token) }
  }

  @Test("inactive → background：同一轮离场只落一次")
  func inactiveThenBackgroundFlushesOnce() {
    let life = AppLifecycle.shared
    life.phaseChanged(to: .active)
    let trail = Trail()
    let tokens = install(trail)
    defer { uninstall(tokens); life.phaseChanged(to: .active) }

    life.phaseChanged(to: .inactive)
    #expect(trail.log == ["data1", "data2", "sync1", "sync2"])
    life.phaseChanged(to: .background)
    #expect(trail.log == ["data1", "data2", "sync1", "sync2"], ".background 紧跟 .inactive，不许再白跑一遍")
  }

  @Test("inactive → active → inactive：回过一次前台，就是两轮离场、各落一次")
  func inactiveActiveInactiveFlushesTwice() {
    let life = AppLifecycle.shared
    life.phaseChanged(to: .active)
    let trail = Trail()
    let tokens = install(trail)
    defer { uninstall(tokens); life.phaseChanged(to: .active) }

    life.phaseChanged(to: .inactive)
    life.phaseChanged(to: .active)
    life.phaseChanged(to: .inactive)
    let round = ["data1", "data2", "sync1", "sync2"]
    #expect(trail.log == round + round)
  }

  @Test("data 严格早于 sync：sync 跑的时候每一个 data 都已经跑完")
  func dataStrictlyPrecedesSync() {
    let life = AppLifecycle.shared
    life.phaseChanged(to: .active)
    let trail = Trail()
    // sync 那一档在跑的那一刻，把「data 已经跑了几个」记下来。它必须是全部。
    var dataDone = 0
    let tokens = [
      life.register(id: "bt13.sync.only", priority: .sync) { [trail] in trail.log.append("sync@\(dataDone)") },
      life.register(id: "bt13.data.a", priority: .data) { dataDone += 1 },
      life.register(id: "bt13.data.b", priority: .data) { dataDone += 1 },
      life.register(id: "bt13.data.c", priority: .data) { dataDone += 1 },
    ]
    defer { uninstall(tokens); life.phaseChanged(to: .active) }

    life.phaseChanged(to: .background)
    #expect(trail.log == ["sync@3"])
    // 被杀前那一下（`willTerminate`）不吃去重，也还是同一个顺序。
    dataDone = 0
    life.leaveForeground(final: true)
    #expect(trail.log == ["sync@3", "sync@3"])
  }
}

// ---------------------------------------------------------------- BT-14

@MainActor
@Suite("BT-14 写盘队列堵着时离场：不自锁、最新一版落盘、正式文件在存档之后", .serialized)
struct ArchiveQueueLeaveTests {

  @Test("写盘队列被堵住、还排着存档写和正式文件写的时候离开前台：主线程等得到、不死锁")
  func leavingWithQueuedWritesDoesNotSelfDeadlock() throws {
    let root = URL(fileURLWithPath: NSTemporaryDirectory())
      .appendingPathComponent("bt14-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: root) }
    let archiveURL = root.appendingPathComponent("sync-v1.json")
    let store = try SyncStore(directory: root)
    let device = UUID()
    let events = LockedLog()

    // ① 把进程共用的那条写盘队列堵住，并确认它此刻真的堵在这一格上。
    let blocked = DispatchSemaphore(value: 0), release = DispatchSemaphore(value: 0)
    store.afterArchiveWritten { blocked.signal(); release.wait() }
    blocked.wait()

    // ② 堵着的时候排进去：一版存档写（v1）+ 一次正式文件写（`draws.json` 那种伴随写）。
    var line = SyncObject(collection: "drawings", id: "BTCUSDT/bt14")
    line.body["v"] = .number(1)
    try store.capture(line, device: device)
    let key = line.key
    store.afterArchiveWritten {
      // 正式文件这一笔跑的时候，盘上的存档必须已经不比它旧（B2：存档先落）。
      let onDisk = (try? JSONDecoder().decode(SyncArchive.self, from: Data(contentsOf: archiveURL)))?
        .local[key]?.body["v"]
      switch onDisk {
      case .some(.number(2)): events.add("companion:v2")
      case .some(.number(1)): events.add("companion:v1")
      default: events.add("companion:missing")
      }
    }

    // ③ 离场钩子：`.data` 再产一版（v2），`.sync` 排空队列——和 `AppAccountBridge`
    //    登记的那一条一模一样（`flushNow()`）。放行队列的是另一条线程，它等的是
    //    「主线程已经走到排空那一步」这个信号，不是一段时间。
    let leaving = DispatchSemaphore(value: 0)
    let releaser = Thread { leaving.wait(); events.add("released"); release.signal() }
    releaser.start()
    let life = AppLifecycle.shared
    life.phaseChanged(to: .active)
    let latest: SyncObject = { var l = line; l.body["v"] = .number(2); return l }()
    let tokens = [
      life.register(id: "bt14.sync", priority: .sync) { [store] in
        events.add("flush-begin"); leaving.signal(); store.flushNow(); events.add("flush-end")
      },
      life.register(id: "bt14.data", priority: .data) { [store] in
        events.add("data"); try? store.capture(latest, device: device)
      },
    ]
    defer { for t in tokens { life.unregister(hook: t) }; life.phaseChanged(to: .active) }

    life.phaseChanged(to: .background)   // 自锁的话就永远回不到下一行

    let log = events.all
    #expect(log.first == "data")
    #expect(log.firstIndex(of: "flush-begin").map { $0 < (log.firstIndex(of: "released") ?? -1) } == true,
            "放行必须发生在主线程已经挂到排空上之后，不然这条用例量的不是「堵着时离场」：\(log)")
    #expect(log.last == "flush-end", "排空返回时，排在它前面的正式文件写必须已经跑完：\(log)")
    #expect(log.contains("companion:v2"),
            "两版存档写被合并成一次、而且赶在正式文件写之前落盘：\(log)")
    #expect(store.writeCount == 1, "堵着时排进去的两版存档只该真写一次（合并写）")

    let reopened = try SyncStore(directory: root)
    #expect(reopened.archive.local[key]?.body["v"] == .number(2), "离场时最新那一版必须在盘上")
    #expect(reopened.archive.operations.count == store.archive.operations.count)
  }
}
