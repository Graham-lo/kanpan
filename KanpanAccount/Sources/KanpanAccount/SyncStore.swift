import Foundation

public struct SyncObject: Codable, Sendable, Equatable {
  public var collection: String
  public var id: String
  public var body: [String: JSONValue]
  public var fields: [String: JSONValue]
  public var revision: Int64
  public var deleted: Bool
  public var generation: Int64
  public var key: String { collection + ":" + id }
  public init(collection: String, id: String) {
    self.collection = collection; self.id = id; body = [:]; fields = [:]; revision = 0; deleted = false; generation = 0
  }
}
public struct SyncOperation: Codable, Sendable, Identifiable {
  public var id = UUID()
  public var collection: String
  public var objectId: String
  public var deviceId: UUID
  public var baseRevision: Int64
  public var generation: Int64
  public var timestamp: Int64
  public var logical: UInt64
  public var action: String
  public var fields: [String: JSONValue]
  public var importBatch: UUID?
}
/// 服务端对一条操作的回执。
///
/// `droppedFields`：服务端认下了这条操作，但其中这几个字段它**不认识、没有收下**
/// （新服务端把「未知字段」从「整条拒绝」降级成了「丢掉该字段并回报」）。
/// 这几项的脏标记**不许清**——它其实没推上去。老服务端不回这个字段，
/// 可选类型的合成解码会当它不存在，不会解码失败。
public struct SyncResult: Codable, Sendable {
  public var operationId: UUID
  public var object: SyncObject
  public var cursor: Int64
  public var droppedFields: [String]?
}
public struct SyncPushResponse: Codable, Sendable { public var results: [SyncResult]; public var serverTime: Int64 }
public struct SyncPage: Codable, Sendable { public var objects: [SyncObject]; public var next: String?; public var cursor: Int64; public var serverTime: Int64 }
public struct SyncArchive: Codable, Sendable {
  public var version = 1
  public var operations: [SyncOperation] = []
  public var sent: Set<UUID> = []
  public var objects: [String: SyncObject] = [:]
  public var local: [String: SyncObject] = [:]
  public var autoSync = true
  public var lastSync: Int64?
  public var logical: UInt64 = 0
  public var offset: Int64 = 0
}

/// 存档落盘器：一条串行队列，把「编码 + 原子写」整段挪出主线程。
///
/// 为什么是 `DispatchQueue` 而不是 actor：串行队列是 FIFO 的，第 N 次
/// `schedule` 一定排在第 N+1 次前面，所以盘上的内容永远是某一次 transaction
/// 的完整快照，不会出现新档被旧档盖回去。往 actor 里塞 `Task` 没有这个保证。
///
/// 整个进程共用一条队列：切换用户时旧档还可能有没写完的活儿，共用一条队列
/// 就不会出现两个 `SyncStore` 对同一个文件交错写。量级很小（一次几十 KB），
/// 串起来也不会堵。
final class ArchiveWriter: @unchecked Sendable {
  private static let queue = DispatchQueue(label: "kanpan.account.archive", qos: .utility)
  private let url: URL
  private let lock = NSLock()
  private var failure: Error?
  private var writes = 0
  init(url: URL) { self.url = url }

  /// `SyncArchive` 是值类型，拷出来之后主线程就可以接着改自己的那份。
  func schedule(_ value: SyncArchive) {
    let url = self.url
    Self.queue.async { [weak self] in
      var caught: Error?
      do { try AccountFiles.writeData(try JSONEncoder().encode(value), to: url) } catch { caught = error }
      guard let self else { return }
      lock.lock()
      writes += 1
      if failure == nil { failure = caught }
      lock.unlock()
    }
  }
  /// 等队列排空（阻塞当前线程）。退到后台、以及「写完必须立刻能被重新打开」的场合用。
  func drain() { Self.queue.sync {} }
  /// 不阻塞的排空。
  func drain(_ done: @escaping @Sendable () -> Void) { Self.queue.async { done() } }
  /// 取走并清掉攒下的写盘错误。落盘是异步的，错误只能由下一次 transaction 抛出来。
  func takeFailure() -> Error? {
    lock.lock(); defer { lock.unlock() }
    let value = failure; failure = nil; return value
  }
  /// 真正落盘的次数。只用于观测与测试（「一次批量只写一次」）。
  var writeCount: Int { lock.lock(); defer { lock.unlock() }; return writes }
}

@MainActor public final class SyncStore {
  public private(set) var archive: SyncArchive
  private let url: URL
  private let writer: ArchiveWriter
  public init(directory: URL) throws {
    url = directory.appendingPathComponent("sync-v1.json")
    archive = try AccountFiles.read(SyncArchive.self, at: url) ?? SyncArchive()
    guard archive.version == 1 else { throw AccountError.storage }
    writer = ArchiveWriter(url: url)
  }
  /// 一次事务 = 一次编码 + 一次写盘。
  ///
  /// 以前每次都先把整档从盘上重读一遍只为校验 version：这个档只有本进程在写，
  /// version 在 `init` 里已经验过，重读纯属白花主线程时间。改成进程内持有已加载的
  /// 那一份，启动 / 切用户时读一次。落盘排到后台队列，上一次写盘的错误由这一次抛出。
  public func transaction(_ edit: (inout SyncArchive) throws -> Void) throws {
    if let failure = writer.takeFailure() { throw failure }
    var next = archive; try edit(&next)
    guard next.version == 1 else { throw AccountError.storage }
    archive = next
    writer.schedule(next)
  }
  /// Record only actual field changes. Uncertain requests are immutable; retry them with their original ID.
  public func capture(_ value: SyncObject, device: UUID, importing batch: UUID? = nil) throws {
    try capture([value], device: device, importing: batch)
  }
  /// 批量记账：N 个对象一次事务、一次写盘。
  ///
  /// 自选列表每条都带 `order`，往头部插一个品种会让后面每一条的 `order` 都变；
  /// 逐条 `capture` 等于整档重写 N 次。批量之后是 1 次。
  public func capture(_ values: [SyncObject], device: UUID, importing batch: UUID? = nil) throws {
    guard !values.isEmpty else { return }
    var staged = archive
    var changed = false
    for value in values where stage(value, device: device, importing: batch, into: &staged) { changed = true }
    guard changed else { return }
    try transaction { $0 = staged }
  }
  /// 把一个对象记进给定的存档副本，返回「有没有真的产生一条操作」。
  private func stage(_ value: SyncObject, device: UUID, importing batch: UUID?, into a: inout SyncArchive) -> Bool {
    let previous = a.local[value.key]
    guard previous?.body != value.body || previous?.deleted != value.deleted else { return false }
    let base = a.objects[value.key] ?? SyncObject(collection: value.collection, id: value.id)
    if batch != nil && base.deleted { return false }
    var changed = value.body.filter { previous?.body[$0.key] != $0.value }
    for key in previous?.body.keys ?? Dictionary<String, JSONValue>().keys where value.body[key] == nil { changed[key] = .null }
    let action = value.deleted ? "delete" : (previous?.deleted == true || base.deleted) ? "restore" : "patch"
    let op = SyncOperation(collection: value.collection, objectId: value.id, deviceId: device,
      baseRevision: base.revision, generation: base.generation, timestamp: Int64(Date().timeIntervalSince1970 * 1000) + a.offset,
      logical: a.logical + 1, action: action, fields: changed, importBatch: batch)
    a.logical += 1; a.operations.append(op); a.local[value.key] = value
    return true
  }
  public func markSent(_ id: UUID) throws { try transaction { $0.sent.insert(id) } }
  /// 隔离一条**永远不会成功**的操作：把它从待发队列里拿走，并把这个对象的本地记账
  /// 退回服务端那一份。
  ///
  /// 用在服务端按语义顶回来（400 / 422）的时候。不这么做的话这条操作会被无限重发，
  /// 而 `run` 那句「没进展就 break」会让它**把后面所有人的操作一起堵死**——
  /// 一次缩放就能让这个账号从此再也同步不上任何东西。
  ///
  /// 退回 `local` 这一步是关键：`stage` 是拿 `local` 做差分的，只拿走操作而不退回
  /// 记账的话，下次同样的值再 `capture` 会被判成「没变」，用户这一改就**真的丢了**。
  /// 退回之后，下一次 `capture` 会拿当前的值重新和服务端那份比，重新组一条新操作。
  /// 本地值和脏标记一个都不动。
  public func quarantine(_ id: UUID) throws {
    try transaction { a in
      guard let index = a.operations.firstIndex(where: { $0.id == id }) else { return }
      let op = a.operations.remove(at: index)
      a.sent.remove(id)
      let key = op.collection + ":" + op.objectId
      if !a.operations.contains(where: { $0.collection == op.collection && $0.objectId == op.objectId }) {
        a.local[key] = a.objects[key]
      }
    }
  }
  /// 一批已发操作一次记完，别一条一条来。
  public func markSent(_ ids: [UUID]) throws {
    guard !ids.isEmpty else { return }
    try transaction { a in for id in ids { a.sent.insert(id) } }
  }
  public func acknowledge(_ response: SyncPushResponse) throws {
    try transaction { a in
      a.offset = response.serverTime - Int64(Date().timeIntervalSince1970 * 1000)
      for result in response.results {
        a.objects[result.object.key] = result.object
        a.operations.removeAll { $0.id == result.operationId }; a.sent.remove(result.operationId)
        // Operations behind this ACK have not been sent; advance causal base without changing uncertain requests.
        for index in a.operations.indices where !a.sent.contains(a.operations[index].id) && a.operations[index].collection == result.object.collection && a.operations[index].objectId == result.object.id {
          a.operations[index].baseRevision = result.object.revision
          a.operations[index].generation = result.object.generation
        }
        if !a.operations.contains(where: { $0.collection == result.object.collection && $0.objectId == result.object.id }) { a.local[result.object.key] = result.object }
      }
    }
  }
  public func receive(_ page: SyncPage) throws {
    try transaction { a in
      a.offset = page.serverTime - Int64(Date().timeIntervalSince1970 * 1000)
      for object in page.objects {
        a.objects[object.key] = object
        if !a.operations.contains(where: { $0.collection == object.collection && $0.objectId == object.id }) { a.local[object.key] = object }
      }
    }
  }
  /// 等排队的写盘全部落地。
  public func flush() async {
    await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
      writer.drain { continuation.resume() }
    }
  }
  /// 阻塞版排空：退到后台这种「必须现在就保证在盘上」的路径用。
  public func flushNow() { writer.drain() }
  /// 真正落盘的次数。观测与测试用。
  public var writeCount: Int { writer.writeCount }
}
