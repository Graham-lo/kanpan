import Foundation
import Testing
@testable import KanpanAccount

/// 「用户刚做的那一次改动」要么整份落下去，要么整份不算。
///
/// 这一组盯的是同一个毛病的四个切面：落盘器把主线程压在队列后面（A2）、
/// 两个文件之间的崩溃窗口（B2）、把云端那批装进本机时的半截状态（B4）、
/// 以及合并之后那句「本地还脏就推回去」被自己的保护区挡掉（B6）。
@MainActor @Suite("一次编辑要么整份落盘，要么整份不算") struct AtomicCommitTests {
  private func temp() throws -> URL {
    let p = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: p, withIntermediateDirectories: true)
    return p
  }

  // MARK: - A2：落盘器合并写

  @Test func aBlockedQueueCollapsesIntoOneWriteAndTheDiskHoldsTheNewest() throws {
    let root = try temp(); defer { try? FileManager.default.removeItem(at: root) }
    let store = try SyncStore(directory: root); let device = UUID()
    // 先把后台队列堵死，让 50 次 capture 全堆在队列里——这就是「离线攒了 n 条
    // 操作」时的真实形状：第 k 次编辑要写的那份档里装着 k 条操作，总功耗 1+2+…+n。
    let gate = DispatchSemaphore(value: 0)
    ArchiveWriter.queue.async { gate.wait() }
    for index in 1...50 {
      var value = SyncObject(collection: "settings", id: "chart")
      value.body["tick"] = .number(Double(index))
      try store.capture(value, device: device)
    }
    gate.signal()
    store.flushNow()
    // 堆着的旧快照整份都被新快照包住了，写它们只是在让主线程多等。
    #expect(store.writeCount == 1)
    let reopened = try SyncStore(directory: root)
    #expect(reopened.archive.operations.count == 50)
    #expect(reopened.archive.operations.map(\.logical) == Array(1...50).map(UInt64.init))
    #expect(reopened.archive.local["settings:chart"]?.body["tick"] == .number(50))
  }

  @Test func flushNowStillMeansThisVersionIsAlreadyOnDisk() throws {
    // 合并写不许把 `flushNow()` 降成「尽力而为」：每一次返回之后，刚写的那一版
    // 都要能被另一个 `SyncStore` 重新打开读出来。缩放、拖分隔线这类连续手势
    // 「手指一抬就落盘」靠的就是这一条。
    let root = try temp(); defer { try? FileManager.default.removeItem(at: root) }
    let store = try SyncStore(directory: root); let device = UUID()
    for index in 1...20 {
      var value = SyncObject(collection: "settings", id: "chart")
      value.body["tick"] = .number(Double(index))
      try store.capture(value, device: device)
      store.flushNow()
      let reopened = try SyncStore(directory: root)
      #expect(reopened.archive.local["settings:chart"]?.body["tick"] == .number(Double(index)))
    }
    // 每一次都等到了自己那一版，谁也没被合并掉。
    #expect(store.writeCount == 20)
  }

  @Test func aFailedWriteIsStillReportedByTheNextTransaction() throws {
    let root = try temp(); defer { try? FileManager.default.removeItem(at: root) }
    let store = try SyncStore(directory: root); let device = UUID()
    var value = SyncObject(collection: "settings", id: "chart")
    value.body["tick"] = .number(1); try store.capture(value, device: device)
    store.flushNow()
    #expect(store.writeCount == 1)
    // 把账号目录换成一个普通文件，之后的写必然失败。合并写之后，失败依旧要能被看见。
    try FileManager.default.removeItem(at: root)
    try Data("not a directory".utf8).write(to: root)
    value.body["tick"] = .number(2); try store.capture(value, device: device)
    store.flushNow()
    value.body["tick"] = .number(3)
    #expect(throws: (any Error).self) { try store.capture(value, device: device) }
  }
}

/// 桥接层那两个文件的提交顺序，照 `DrawingController.write()` / `AppAccountBridge.prepare()`
/// 复刻一遍，好在这儿把「两次写之间进程没了」表达出来——不去真的 kill 进程，
/// 而是把第二次写换成「不写」。
///
/// 真实对应关系：
/// - `formal` = `draws.json`（`DrawStore`）——画线的正式文件；
/// - `store`  = `sync-v1.json`（`SyncStore`）——同步存档，里面同时装着
///   「本机说了算的那份值」和「那条待发操作」。
@MainActor private final class DrawingCommit {
  let root: URL
  let device = UUID()
  /// 正式文件。用内存里的一份字典代替 `draws.json`，语义一样：整份原子替换。
  private(set) var formal: [String: JSONValue] = [:]
  private(set) var store: SyncStore
  /// 旧写法 = 先写正式文件，再写同步存档。
  let archiveFirst: Bool
  init(root: URL, archiveFirst: Bool) throws {
    self.root = root
    self.archiveFirst = archiveFirst
    store = try SyncStore(directory: root)
  }
  private func object(_ id: String, _ value: JSONValue) -> SyncObject {
    var o = SyncObject(collection: "drawings", id: id)
    o.body["geometry"] = value
    return o
  }
  /// 用户画完一根线。`crashAfterFirstWrite` = 两次写之间进程没了。
  func draw(_ id: String, _ value: JSONValue, crashAfterFirstWrite: Bool = false) throws {
    if archiveFirst {
      try store.capture(object(id, value), device: device)
      store.flushNow()
      if crashAfterFirstWrite { return }
      formal[id] = value
    } else {
      formal[id] = value
      if crashAfterFirstWrite { return }
      try store.capture(object(id, value), device: device)
      store.flushNow()
    }
  }
  /// 重开进程：存档从盘上重读，正式文件保持上一次真正写下去的样子。
  func restart(forwardFill: Bool) throws {
    store = try SyncStore(directory: root)
    guard forwardFill else { return }
    // B2 的启动前向对账：存档里「本机说了算」的那份比正式文件新，就往前补进正式文件。
    // 只向前——盘上已经落下的值永远不往回滚。
    let onDisk = formal.map { object($0.key, $0.value) }
    for object in store.unpersistedLocalChanges(in: ["drawings"], onDisk: onDisk) {
      let id = object.id
      if object.deleted { formal[id] = nil } else { formal[id] = object.body["geometry"] }
    }
  }
  /// 云端把它那份（旧的）发下来，然后照 `applyPending()` 把 `local` 装回正式文件。
  func receiveFromCloud(_ id: String, _ value: JSONValue, revision: Int64) throws {
    var o = object(id, value); o.revision = revision
    try store.receive(SyncPage(objects: [o], next: nil, cursor: revision, serverTime: 0))
    for object in store.archive.local.values where object.collection == "drawings" {
      if object.deleted { formal[object.id] = nil } else { formal[object.id] = object.body["geometry"] }
    }
  }
}

@MainActor @Suite("两次写之间崩掉，用户刚画的那根线还在") struct DrawingCrashWindowTests {
  private func temp() throws -> URL {
    let p = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: p, withIntermediateDirectories: true)
    return p
  }

  @Test func theOldOrderLetsTheCloudOverwriteWhatTheUserJustSaved() throws {
    let root = try temp(); defer { try? FileManager.default.removeItem(at: root) }
    let commit = try DrawingCommit(root: root, archiveFirst: false)
    // 先有一根线，两边都落干净了，也推上去了。
    try commit.draw("BTCUSDT/line", .number(1))
    let first = try #require(commit.store.archive.operations.first)
    var pushed = SyncObject(collection: "drawings", id: "BTCUSDT/line")
    pushed.body["geometry"] = .number(1); pushed.revision = 1
    try commit.store.acknowledge(SyncPushResponse(results: [SyncResult(operationId: first.id, object: pushed, cursor: 1)], serverTime: 0))
    commit.store.flushNow()
    // 用户把它拖到新位置。旧写法：正式文件先写成功，同步存档还没写，进程没了。
    try commit.draw("BTCUSDT/line", .number(2), crashAfterFirstWrite: true)
    #expect(commit.formal["BTCUSDT/line"] == .number(2))
    // 重开：盘上是「新几何 + 旧存档」，存档里既没有新值也没有那条待发操作。
    try commit.restart(forwardFill: false)
    #expect(commit.store.archive.operations.isEmpty)
    #expect(commit.store.archive.local["drawings:BTCUSDT/line"]?.body["geometry"] == .number(1))
    // 下一次拉取，云端那份旧的直接盖回正式文件——用户刚存下的那一版没了。
    // 这一条钉住的是**旧写法的症状**（所以断言的是 1 而不是 2）：它说明为什么
    // 提交顺序必须掉个个儿。下一条是同一段剧情在新写法下的样子。
    try commit.receiveFromCloud("BTCUSDT/line", .number(1), revision: 1)
    #expect(commit.formal["BTCUSDT/line"] == .number(1))
  }

  @Test func archiveFirstPlusForwardFillKeepsIt() throws {
    let root = try temp(); defer { try? FileManager.default.removeItem(at: root) }
    let commit = try DrawingCommit(root: root, archiveFirst: true)
    try commit.draw("BTCUSDT/line", .number(1))
    let first = try #require(commit.store.archive.operations.first)
    var pushed = SyncObject(collection: "drawings", id: "BTCUSDT/line")
    pushed.body["geometry"] = .number(1); pushed.revision = 1
    try commit.store.acknowledge(SyncPushResponse(results: [SyncResult(operationId: first.id, object: pushed, cursor: 1)], serverTime: 0))
    commit.store.flushNow()
    // 新写法：同步存档先落——它一份就同时装着新的本地值和那条待发操作。
    // 崩在这之后，正式文件还是旧的。
    try commit.draw("BTCUSDT/line", .number(2), crashAfterFirstWrite: true)
    #expect(commit.formal["BTCUSDT/line"] == .number(1))
    try commit.restart(forwardFill: true)
    // 启动前向对账把新几何补进正式文件。
    #expect(commit.formal["BTCUSDT/line"] == .number(2))
    #expect(commit.store.archive.operations.count == 1)
    // 而且那条待发操作还在，所以云端那份旧的根本进不了 `local`。
    try commit.receiveFromCloud("BTCUSDT/line", .number(1), revision: 1)
    #expect(commit.formal["BTCUSDT/line"] == .number(2))
  }

  @Test func forwardFillNeverRollsAPersistedValueBackwards() throws {
    let root = try temp(); defer { try? FileManager.default.removeItem(at: root) }
    let commit = try DrawingCommit(root: root, archiveFirst: true)
    // 两次写都成功了：存档和正式文件是同一版。
    try commit.draw("BTCUSDT/line", .number(7))
    try commit.restart(forwardFill: true)
    #expect(commit.formal["BTCUSDT/line"] == .number(7))
    // 存档里没有待发操作的那些对象（云端来的），对账一步都不许动正式文件。
    try commit.receiveFromCloud("ETHUSDT/line", .number(3), revision: 2)
    let before = commit.formal
    try commit.restart(forwardFill: true)
    #expect(commit.formal == before)
  }
}

@MainActor @Suite("拉下来的那批，什么时候才算真的装进本机") struct ApplyBookkeepingTests {
  private func temp() throws -> URL {
    let p = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: p, withIntermediateDirectories: true)
    return p
  }

  @Test func aBatchFetchedButNotAppliedIsRedoneAfterARestart() throws {
    let root = try temp(); defer { try? FileManager.default.removeItem(at: root) }
    do {
      let store = try SyncStore(directory: root)
      // 拉取完成。从前这里写的是 `lastSync`，紧接着才去 `applyPending()`——
      // 于是「拉到哪儿了」和「装进本机没有」共用一个时刻，装到一半没了也没人知道。
      try store.markFetched(at: 1_000)
      store.flushNow()
    }
    let reopened = try SyncStore(directory: root)
    #expect(reopened.needsApply)
    try reopened.markApplied(at: 1_000)
    #expect(!reopened.needsApply)
    reopened.flushNow()
    let again = try SyncStore(directory: root)
    #expect(!again.needsApply)
  }

  @Test func aNewerFetchAfterAnApplyIsPendingAgain() throws {
    let root = try temp(); defer { try? FileManager.default.removeItem(at: root) }
    let store = try SyncStore(directory: root)
    try store.markFetched(at: 1_000)
    try store.markApplied(at: 1_000)
    #expect(!store.needsApply)
    try store.markFetched(at: 2_000)
    #expect(store.needsApply)
  }

  @Test func anArchiveWrittenBeforeLastAppliedExistsStillOpens() throws {
    let root = try temp(); defer { try? FileManager.default.removeItem(at: root) }
    // 老档里没有 `lastApplied` 这个键。手写解码必须走 `decodeIfPresent`，
    // 否则整份账号档案打不开。
    let old = #"{"version":1,"operations":[],"sent":[],"objects":{},"local":{},"autoSync":true,"logical":0,"offset":0,"lastSync":900}"#
    try Data(old.utf8).write(to: root.appendingPathComponent("sync-v1.json"))
    let store = try SyncStore(directory: root)
    #expect(store.archive.lastSync == 900)
    // 没记过「装进去了」，所以启动时这批要重来一次——这正是想要的保守方向。
    #expect(store.needsApply)
  }
}

@MainActor @Suite("保护区里登记的回推，出来之后才做") struct ApplyGateTests {
  @Test func aCaptureInsideTheGuardProducesNothing() throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: root) }
    let store = try SyncStore(directory: root); let device = UUID()
    let gate = ApplyGate()
    // 复刻桥接层：`capture()` 的第一道 guard 就是 `!applying`。
    func capture(_ value: SyncObject) throws {
      guard !gate.isApplying else { return }
      try store.capture(value, device: device)
    }
    var dirty = SyncObject(collection: "settings", id: "chart")
    dirty.body["tick"] = .number(9)
    gate.enter()
    // 旧写法：合并完发现本地还脏，就地回推。保护区还没出，一条操作都产生不了。
    try capture(dirty)
    #expect(store.archive.operations.isEmpty)
    gate.leave()
    #expect(store.archive.operations.isEmpty)
  }

  @Test func workDeferredInsideTheGuardRunsAfterItCloses() throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: root) }
    let store = try SyncStore(directory: root); let device = UUID()
    let gate = ApplyGate()
    func capture(_ value: SyncObject) throws {
      guard !gate.isApplying else { return }
      try store.capture(value, device: device)
    }
    var dirty = SyncObject(collection: "settings", id: "chart")
    dirty.body["tick"] = .number(9)
    var ranWhileApplying: Bool?
    gate.enter()
    gate.afterApplying { ranWhileApplying = gate.isApplying; try? capture(dirty) }
    #expect(store.archive.operations.isEmpty)
    gate.leave()
    #expect(ranWhileApplying == false)
    #expect(store.archive.operations.count == 1)
    #expect(store.archive.local["settings:chart"]?.body["tick"] == .number(9))
  }

  @Test func aStaleSnapshotFromAnEarlierRoundIsDropped() {
    let gate = ApplyGate()
    var ran = 0
    gate.enter()
    gate.afterApplying { ran += 1 }
    // 中途换了账号 / 又起了一轮应用：上一轮登记的补做动作作废。
    gate.rotate()
    gate.leave()
    #expect(ran == 0)
  }

  @Test func outsideTheGuardItJustRunsNow() {
    let gate = ApplyGate()
    var ran = 0
    gate.afterApplying { ran += 1 }
    #expect(ran == 1)
  }
}

/// `AppAccountBridge.applyPending()` 的三段式，照着复刻一遍，好在这儿把
/// 「装到一半出错」表达出来。会抛错的那一步是画线解码（`PersonalSyncCodec.drawing`），
/// 这里用一个开关代替。
@MainActor private final class ApplyTransaction {
  let root: URL
  private(set) var store: SyncStore
  /// 站位 `prefs.json` 与 `draws.json`。
  private(set) var settingsFile = 0
  private(set) var drawingsFile = 0
  private(set) var pendingApply = false
  /// 新写法 = 准备 → 落盘 → 发布。旧写法 = 边算边装。
  let threePhase: Bool
  /// 画线解不开。
  var drawingIsBroken = false
  init(root: URL, threePhase: Bool) throws {
    self.root = root
    self.threePhase = threePhase
    store = try SyncStore(directory: root)
  }
  struct Broken: Error {}
  private func decodeDrawing(_ value: Int) throws -> Int {
    if drawingIsBroken { throw Broken() }
    return value
  }
  /// 一轮同步：拉取 → 装进本机。
  func round(settings: Int, drawing: Int, at time: Int64) throws {
    // 中途抛错也要把存档落下去——「拉到哪儿了」这一笔本来就已经记上了。
    defer { store.flushNow() }
    try store.markFetched(at: time)
    pendingApply = true
    if threePhase {
      // 一、准备：会抛错的全在这儿，而且一个字节都不写。
      let nextDrawing = try decodeDrawing(drawing)
      // 二、落盘：一次性提交，成功之后才清 `pendingApply`。
      settingsFile = settings
      drawingsFile = nextDrawing
      try store.markApplied(at: time)
      pendingApply = false
    } else {
      // 旧写法：进门先把待办清掉，先把设置装进去，再去做会抛错的画线。
      pendingApply = false
      settingsFile = settings
      drawingsFile = try decodeDrawing(drawing)
    }
    store.flushNow()
  }
  func restart() throws { store = try SyncStore(directory: root) }
}

@MainActor @Suite("装到一半出错，这一批要么全算要么全不算") struct ApplyTransactionTests {
  private func temp() throws -> URL {
    let p = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: p, withIntermediateDirectories: true)
    return p
  }

  @Test func theOldOneStageApplyLeavesHalfOfItApplied() throws {
    let root = try temp(); defer { try? FileManager.default.removeItem(at: root) }
    let apply = try ApplyTransaction(root: root, threePhase: false)
    try apply.round(settings: 1, drawing: 1, at: 1_000)
    apply.drawingIsBroken = true
    #expect(throws: (any Error).self) { try apply.round(settings: 2, drawing: 2, at: 2_000) }
    // 钉住旧写法的症状：设置换成了新的，画线还停在旧的，补跑的钩子也被清掉了。
    #expect(apply.settingsFile == 2)
    #expect(apply.drawingsFile == 1)
    #expect(!apply.pendingApply)
  }

  @Test func theThreePhaseApplyIsAllOrNothing() throws {
    let root = try temp(); defer { try? FileManager.default.removeItem(at: root) }
    let apply = try ApplyTransaction(root: root, threePhase: true)
    try apply.round(settings: 1, drawing: 1, at: 1_000)
    apply.drawingIsBroken = true
    #expect(throws: (any Error).self) { try apply.round(settings: 2, drawing: 2, at: 2_000) }
    // 准备那一段就抛了，两个文件一个都没动。
    #expect(apply.settingsFile == 1)
    #expect(apply.drawingsFile == 1)
    // 补跑的钩子还在，面板一关就重来。
    #expect(apply.pendingApply)
    // 断电重开也一样看得出来：拉到 2000，只装到 1000。
    try apply.restart()
    #expect(apply.store.needsApply)
    // 画线修好之后这一批整份补上。
    apply.drawingIsBroken = false
    try apply.round(settings: 2, drawing: 2, at: 2_000)
    #expect(apply.settingsFile == 2)
    #expect(apply.drawingsFile == 2)
    #expect(!apply.pendingApply)
    try apply.restart()
    #expect(!apply.store.needsApply)
  }
}
