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
  /// 同一个对象上，这条操作的**本地前驱**（记账时队列里该对象的最后一条）。
  ///
  /// 为什么要它：`acknowledge` 得分清两件长得很像的事——
  /// 「这条操作依赖我自己前一条本地操作」（删除→恢复：恢复的 base 必须对齐删除
  /// 之后的 revision，否则服务端第一句就顶回来），和「用户实际基于哪个云端版本
  /// 做的决定」（普通 patch：base 是他当初看到的那一版）。把后者也一并抬上去，
  /// 等于骗服务端说「我看过新版本之后又改了一次」，于是**积压 100 条和 101 条的
  /// 最终赢家不一样**——用户没做任何不同的事，结果却由分批边界决定（B5）。
  ///
  /// **这个字段只活在本机存档里，绝不发给服务端。** 服务端的 `Operation`
  /// （`Backend/kanpan-api/src/sync.rs`）带 `deny_unknown_fields`，多一个键
  /// 整批 400。推送体一律走 `SyncPushRequest`，`SyncOperation` 自己的 `Codable`
  /// 只给存档用。
  public var dependsOn: UUID?
  public var key: String { collection + ":" + objectId }
}
/// 推送到服务端的那一份操作。
///
/// 和 `SyncOperation` 分开写，是因为服务端 `Operation` 带 `deny_unknown_fields`：
/// 本机多出来的任何一个字段（`dependsOn`）都会让**整批 100 条**一起 400，
/// 而那一批里九十九条本来是好的。字段在这儿逐个抄一遍，本机以后再加字段
/// 也不可能溜到线上去。
public struct WireOperation: Encodable, Sendable {
  public var id: UUID
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
  public init(_ op: SyncOperation) {
    id = op.id; collection = op.collection; objectId = op.objectId; deviceId = op.deviceId
    baseRevision = op.baseRevision; generation = op.generation; timestamp = op.timestamp
    logical = op.logical; action = op.action; fields = op.fields; importBatch = op.importBatch
  }
}
/// `POST v1/sync/operations` 的请求体。推送体只有这一个入口。
public struct SyncPushRequest: Encodable, Sendable {
  public var operations: [WireOperation]
  public init(_ operations: [SyncOperation]) { self.operations = operations.map(WireOperation.init) }
}
/// 一条**被服务端按语义顶回来**的操作，连同用户当时的意图一起留在本机。
///
/// 为什么要写进存档而不是只放在内存里：用户那一改（清空标注文字、某个这台服务器
/// 还不认的字段）已经生效在他眼前的图上了。只把操作从待发队列里拿走的话，重启之后
/// 本机就再也没人知道「这份本地值还没推上去」，下一次拉取会拿云端那份旧的把它盖
/// 回去——用户看到自己的修改自己变回去了（B3）。
public struct RejectedOperation: Codable, Sendable, Identifiable {
  public var id: UUID { operation.id }
  /// 被拒的那条操作原样留着：不改载荷、不改 id。要重建载荷时另起一条新 id 的操作。
  public var operation: SyncOperation
  /// 服务端给的理由（`AccountError.http` 的 reason）。
  public var reason: String
  /// 被拒的时刻（毫秒）。
  public var at: Int64
  /// 用户当时的值。服务端修好之后拿它和当前云端对象重新组一条**新 id** 的操作补推。
  public var intent: SyncObject
  public init(operation: SyncOperation, reason: String, at: Int64, intent: SyncObject) {
    self.operation = operation; self.reason = reason; self.at = at; self.intent = intent
  }
  public var collection: String { operation.collection }
  public var objectId: String { operation.objectId }
  public var key: String { operation.key }
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
  /// **真正把拉下来那批装进本机**的时刻，和 `lastSync`（拉到哪儿了）分开记。
  ///
  /// 从前只有 `lastSync`：拉取一结束就写上，紧接着才去 `applyPending()`。
  /// 装到一半出错（画线解码失败、文件写不进去）时，盘上留着的是「这批已经digest过了」，
  /// 下一轮不会重来，这批的内容就永远不会落到本机。判断「这批要不要重来」看的是这一个。
  public var lastApplied: Int64?
  public var logical: UInt64 = 0
  public var offset: Int64 = 0
  /// 被服务端顶回来、已经从待发队列里拿走，但**用户的值还留在本机**的那些操作。
  /// 一个对象最多留最近的一条。它们不在 `operations` 里，所以不堵队列、不算 `pending`。
  public var rejected: [RejectedOperation] = []
  public init() {}
  /// 手写解码，**因为 Swift 合成出来的那份不认属性默认值**：老存档里没有
  /// `rejected` 这个键，合成解码会直接 `keyNotFound` 抛出去，`SyncStore.init`
  /// 跟着抛，用户的整份账号档案就打不开了。往这个档里加字段必须走 `decodeIfPresent`。
  /// 反过来老版本读新档没问题——合成解码忽略不认识的键。
  public init(from decoder: any Decoder) throws {
    let c = try decoder.container(keyedBy: CodingKeys.self)
    version = try c.decodeIfPresent(Int.self, forKey: .version) ?? 1
    operations = try c.decodeIfPresent([SyncOperation].self, forKey: .operations) ?? []
    sent = try c.decodeIfPresent(Set<UUID>.self, forKey: .sent) ?? []
    objects = try c.decodeIfPresent([String: SyncObject].self, forKey: .objects) ?? [:]
    local = try c.decodeIfPresent([String: SyncObject].self, forKey: .local) ?? [:]
    autoSync = try c.decodeIfPresent(Bool.self, forKey: .autoSync) ?? true
    lastSync = try c.decodeIfPresent(Int64.self, forKey: .lastSync)
    lastApplied = try c.decodeIfPresent(Int64.self, forKey: .lastApplied)
    logical = try c.decodeIfPresent(UInt64.self, forKey: .logical) ?? 0
    offset = try c.decodeIfPresent(Int64.self, forKey: .offset) ?? 0
    rejected = try c.decodeIfPresent([RejectedOperation].self, forKey: .rejected) ?? []
  }
  /// 这个对象上有没有「本机说了算」的理由：待发操作，**或者**一条还没了结的拒绝记录。
  ///
  /// 两者都表示「用户的值还没推上去」，所以两者都得挡住云端那份往 `local` 里写。
  /// 只认前一半就是 B3 那条路：操作被隔离之后没人再护着本地值。
  func holdsLocal(_ collection: String, _ id: String) -> Bool {
    operations.contains { $0.collection == collection && $0.objectId == id }
      || rejected.contains { $0.collection == collection && $0.objectId == id }
  }
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
  /// 进程共用的那条串行队列。测试要能把它堵住，才量得出「堆在队列里的旧快照有没有被合并掉」。
  static let queue = DispatchQueue(label: "kanpan.account.archive", qos: .utility)
  private let url: URL
  private let lock = NSLock()
  private var failure: Error?
  private var writes = 0
  /// 还没开写的最新一版。每次 `schedule` 覆盖它，队列上的第一格取走它。
  private var pending: SyncArchive?
  init(url: URL) { self.url = url }

  /// `SyncArchive` 是值类型，拷出来之后主线程就可以接着改自己的那份。
  ///
  /// 待写的那一版只留最新的一份（合并写）。存档是**整份快照**，不是增量：
  /// 第 k 版整个被第 k+1 版包住，所以把还没开写的旧版丢掉，盘上的内容一个字节
  /// 都不会少。从前每次 `schedule` 都独立编码 + 写一遍，离线攒 n 条操作时
  /// 第 k 次编辑要编码一份装着 k 条操作的档，总功耗 1+2+…+n；而每一次
  /// `capture()` 后面都跟着一次主线程 `flushNow()`，这些活儿全压在手指上。
  func schedule(_ value: SyncArchive) {
    lock.lock()
    pending = value
    lock.unlock()
    // 强引用：`flushNow()` 之前 store 被释放掉的话，这一版还是得落下去。
    Self.queue.async { self.writeLatest() }
  }
  /// 取走当前最新的待写版本写掉。没有待写版本说明已经被前一格合并走了。
  private func writeLatest() {
    lock.lock()
    guard let value = pending else { lock.unlock(); return }
    pending = nil
    lock.unlock()
    var caught: Error?
    do { try AccountFiles.writeData(try JSONEncoder().encode(value), to: url) } catch { caught = error }
    lock.lock()
    writes += 1
    if failure == nil { failure = caught }
    lock.unlock()
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
  /// 拉取这一批完成了（还没装进本机）。
  public func markFetched(at time: Int64) throws {
    try transaction { $0.lastSync = time }
  }
  /// 这一批**真的装进本机了**。落盘成功之后才准调它。
  public func markApplied(at time: Int64) throws {
    try transaction { $0.lastApplied = time }
  }
  /// 拉下来的这批还没装进本机。重启之后照样看得出来，因为两个时刻都在存档里。
  public var needsApply: Bool {
    guard let fetched = archive.lastSync else { return false }
    return (archive.lastApplied ?? .min) < fetched
  }
  /// 存档里「本机说了算」、但正式文件上还没有这一版的那些对象。
  ///
  /// 用在启动时的前向对账：画线是先落同步存档（新的本地值和那条待发操作在同一份档里），
  /// 再落 `draws.json`；两次写之间进程没了，盘上就是「新存档 + 旧正式文件」。
  /// 这个方法把差额挑出来，让调用方**只向前**补进正式文件。
  ///
  /// 只认 `holdsLocal` 的对象——有待发操作或未了结的拒绝记录，才说明这一版是
  /// 用户刚改的、还没推上去的。云端下发的那些不在此列，否则就成了拿存档去
  /// 回滚正式文件。
  public func unpersistedLocalChanges(in collections: Set<String>, onDisk: [SyncObject]) -> [SyncObject] {
    var disk: [String: SyncObject] = [:]
    for object in onDisk where collections.contains(object.collection) { disk[object.key] = object }
    var out: [SyncObject] = []
    for (key, object) in archive.local where collections.contains(object.collection) {
      guard archive.holdsLocal(object.collection, object.id) else { continue }
      let current = disk[key]
      if object.deleted {
        // 已经不在正式文件里了就没什么可补的。
        if current != nil { out.append(object) }
      } else if current?.body != object.body {
        out.append(object)
      }
    }
    return out.sorted { $0.key < $1.key }
  }
  /// Record only actual field changes. Uncertain requests are immutable; retry them with their original ID.
  public func capture(_ value: SyncObject, device: UUID, importing batch: UUID? = nil,
                      owning ownedKeys: [String: Set<String>] = [:]) throws {
    try capture([value], device: device, importing: batch, owning: ownedKeys)
  }
  /// 批量记账：N 个对象一次事务、一次写盘。
  ///
  /// 自选列表每条都带 `order`，往头部插一个品种会让后面每一条的 `order` 都变；
  /// 逐条 `capture` 等于整档重写 N 次。批量之后是 1 次。
  ///
  /// `ownedKeys` 是**这个客户端替哪些键说话**：collection → 它自己会发出去的键。
  /// 见 `stage` 里那一段。给空表就是从前的行为（每个键都当自己的），
  /// 老调用点不传照旧编译、照旧跑。
  public func capture(_ values: [SyncObject], device: UUID, importing batch: UUID? = nil,
                      owning ownedKeys: [String: Set<String>] = [:]) throws {
    guard !values.isEmpty else { return }
    var staged = archive
    var changed = false
    for value in values where stage(value, device: device, importing: batch, owning: ownedKeys, into: &staged) { changed = true }
    guard changed else { return }
    try transaction { $0 = staged }
  }
  /// 把一个对象记进给定的存档副本，返回「有没有真的产生一条操作」。
  ///
  /// ## 「先前有、这次没有」的键，只有是自己的才翻译成删除
  ///
  /// 差分是拿 `previous`（`archive.local`）和这次这份逐键比出来的，其中「先前有、
  /// 这次没有」历来被翻译成 `.null`（字段墓碑，「删掉这个字段」）。问题出在
  /// `previous` **不一定是本机自己写进去的**：全量同步和增量拉取都会把**云端那份**
  /// 写进 `local`（见 `receive`）。于是只要云端那个对象上带着一个**本机这个版本
  /// 的模型根本不产出的字段**，用户下一次碰这个对象，客户端就会自作主张提议
  /// 「把这个字段删掉」。
  ///
  /// 这件事两头都不对，2026-09-19 在模拟器上两条都真的见到了：
  ///
  /// - 服务端 `sync_validation.rs` 只在 `color` / `groupId` / `text` 和 settings、
  ///   drawingPreferences 的嵌套路径上收 null，别的一律 `invalid_operation`，而且是
  ///   **整条操作拒掉**。线上那两条标注的 body 里带着一个 `created`（`Drawing` 里
  ///   根本没有这个属性，服务端却留着它的值规则——和 `PrefsFieldPlan.wireOnlyKeys`
  ///   里的 `styleID` 是同一类只活在线上的遗留字段），于是改一次标注样式发出去的
  ///   fields 是 `{"created": null, ...}`，400 → `quarantine` → `retryRejected`
  ///   拿同样两份重新差分又差出同一个 null，每轮全量换一次跨洋 400，永远好不了。
  /// - 反过来说，服务端**要是收了**这些 null，客户端就会静悄悄删掉一个它只是不认识的
  ///   字段：老版本 app 改一条新版本写出来的画线，会把新版本的字段抹掉。今天没丢数据，
  ///   只是因为服务端整条拒了——「拒绝」正在替「数据丢失」挡枪。
  ///
  /// 所以规矩是：**一个客户端只替它认识的字段说话。** 没听说过的字段既不改也不删，
  /// 原样留在对象上（`value.body[key] = previous.body[key]`）。带回这一步不能省：
  /// 记账里的 `local` 要是少了这个键，下一次差分会差出同一个 null，兜了一圈回到原地。
  ///
  /// 用户真的把一个**自己的**字段清掉了（画线的 `color`、自选的 `groupId`），那条路
  /// 原样保留——它在 `ownedKeys` 里，照旧产出 `.null`。
  ///
  /// 表由调用方给（app 侧是 `PersonalSyncCodec.ownedKeys`，从编码器本身派生，不是手抄的
  /// 清单）；不给表就是从前的行为，`KanpanAccount` 自己不认识任何一个业务字段。
  private func stage(_ value: SyncObject, device: UUID, importing batch: UUID?,
                     owning ownedKeys: [String: Set<String>], into a: inout SyncArchive) -> Bool {
    var value = value
    let previous = a.local[value.key]
    let base = a.objects[value.key] ?? SyncObject(collection: value.collection, id: value.id)
    if batch != nil && base.deleted { return false }
    var changed = value.body.filter { previous?.body[$0.key] != $0.value }
    let owned = ownedKeys[value.collection]
    for key in previous?.body.keys ?? Dictionary<String, JSONValue>().keys where value.body[key] == nil {
      if let owned, !owned.contains(key) { value.body[key] = previous?.body[key] } else { changed[key] = .null }
    }
    // 带回外来键之后才判「到底有没有变」：只差一个外来键的两份 body 带回来就一模一样，
    // 这时候再往队列里塞一条 fields 空空如也的操作，是白白跑一趟跨洋请求。
    guard previous?.body != value.body || previous?.deleted != value.deleted else { return false }
    let action = value.deleted ? "delete" : (previous?.deleted == true || base.deleted) ? "restore" : "patch"
    let op = SyncOperation(collection: value.collection, objectId: value.id, deviceId: device,
      baseRevision: base.revision, generation: base.generation, timestamp: Int64(Date().timeIntervalSince1970 * 1000) + a.offset,
      logical: a.logical + 1, action: action, fields: changed, importBatch: batch,
      // 本地依赖链：这个对象上队列里的最后一条就是我的前驱。
      dependsOn: a.operations.last { $0.collection == value.collection && $0.objectId == value.id }?.id)
    a.logical += 1; a.operations.append(op); a.local[value.key] = value
    return true
  }

  // MARK: - 批次编排

  /// 从队首取出「可以放进同一批」的操作。**队列顺序不动、不跳过、不重排**，
  /// 碰到一条会把整批拖垮的操作就在它前面截断，剩下的下一轮再发。
  ///
  /// 依据是服务端 `merge()`（`Backend/kanpan-api/src/sync.rs`）在**同一个事务里
  /// 逐条合并**这件事：同批里前面那条改出来的 revision / generation，后面那条
  /// 立刻就要对上，对不上整批回滚。逐条推出来的边只有三种：
  ///
  /// - 同一对象上多条 `patch` 可以同批：`base <= revision` 就放行，字段再按时间戳
  ///   逐个比大小，本机的 `logical` 递增，后一条自然赢。
  /// - `delete` 跟在 `patch` 后面也可以：`delete` 只看 `base <= revision`。
  /// - **断的是这两种**：
  ///   1. `restore` 前面在同批里已经有该对象的任何操作——`restore` 要求
  ///      `base_revision == object.revision`（精确相等），前面那条把 revision
  ///      推走了，它就必败，而且拖着整批一起回滚；
  ///   2. 任何操作前面在同批里已经有该对象的 `delete` 或 `restore`——`delete`
  ///      之后的 `patch` 会被服务端**默默吞掉**（`else if object.deleted { return Ok }`，
  ///      用户那一改无声无息地没了），`delete` 之后的 `restore` 必败；
  ///      `restore` 会把 generation +1，而 generation 是**相等约束**，同批后面
  ///      带旧 generation 的操作一律 409。
  ///
  /// 互不依赖的对象照旧一批一百条走，不会退化成逐条跨洋请求。
  public static func batch(_ queue: [SyncOperation], limit: Int) -> [SyncOperation] {
    var picked: [SyncOperation] = []
    var sealed: Set<String> = []    // 这批里已经出现过 delete / restore 的对象
    var touched: Set<String> = []   // 这批里出现过任何操作的对象
    for op in queue {
      guard picked.count < limit else { break }
      if sealed.contains(op.key) { break }
      if op.action == "restore" && touched.contains(op.key) { break }
      picked.append(op)
      touched.insert(op.key)
      if op.action == "delete" || op.action == "restore" { sealed.insert(op.key) }
    }
    return picked
  }
  /// 待发队首的下一批。
  public func nextBatch(limit: Int) -> [SyncOperation] { Self.batch(archive.operations, limit: limit) }

  /// 待发队首的下一批，**同时受条数和字节数两道闸**。
  ///
  /// 条数从来不是唯一的上限：服务端整个请求体只收 512 KiB
  /// （`Backend/kanpan-api/src/lib.rs` 的 `DefaultBodyLimit`），而一条画线操作有多大
  /// 完全由用户画了多少个点决定——一百条大操作轻轻松松越线。越线的下场是 413：
  /// 请求在进 handler **之前**就被拒了，这一批一条都没落库，而客户端会把同一批原样
  /// 再发一次，于是这个账号的同步队列从此再也前进不了。
  ///
  /// 削的办法是砍尾巴：`batch()` 给的是一段**有序且能同批**的操作，取它的前缀仍然
  /// 安全（谁的前驱都不会被留在后面）。对半砍到只剩一条为止——一条还超，那就是
  /// 这条本身发不上去，由调用方隔离它（`quarantine`），本函数不做这个决定。
  public func nextBatch(limit: Int, maxBytes: Int) -> [SyncOperation] {
    var picked = Self.batch(archive.operations, limit: limit)
    while picked.count > 1, Self.encodedSize(picked) > maxBytes {
      picked = Array(picked.prefix(max(1, picked.count / 2)))
    }
    return picked
  }

  /// 这一批按**线上那份格式**编码之后有多大。编不出来就当无穷大（宁可切小）。
  public static func encodedSize(_ operations: [SyncOperation]) -> Int {
    guard let data = try? JSONEncoder().encode(SyncPushRequest(operations)) else { return .max }
    return data.count
  }

  // MARK: - 409 之后的恢复

  /// 把一批**确认整体回滚**的操作退回「未发送」。
  ///
  /// 只有能确认服务端一条都没落库的理由才准调：`resync_required` 可以——那个 409
  /// 是在事务里抛的，`tx.commit()` 根本没跑到。`idempotency_mismatch` **不可以**：
  /// 那说明同 id 的操作确实已经落过库，把它退回未发送等于允许改它的载荷再发一次，
  /// 服务端会拿 digest 再顶一次，这条从此谁也推不上去。
  public func rollback(_ ids: [UUID]) throws {
    guard !ids.isEmpty else { return }
    try transaction { a in for id in ids { a.sent.remove(id) } }
  }

  /// 按**刚拉回来的云端对象**重整所有未发送操作的版本元信息。
  ///
  /// 三条规则，一条都不能松：
  /// - `generation` 是相等约束，拉回来是多少就对齐多少；对不上服务端第一句就 409。
  /// - `restore` 的 `baseRevision` 必须精确等于云端 revision。
  /// - `patch` / `delete` 的 `baseRevision` **保持用户当初观察到的那一版**，只有
  ///   大于云端 revision 时才夹回去（那是服务端的硬门槛）。抬上去就是 B5：
  ///   「传输上晚发」被当成「用户看过新版本之后又改了一次」，凭空赢下别人的改动。
  ///
  /// 载荷一个字段都不动。真要换动作（`restore` 却发现对象根本没被删、`patch`
  /// 却发现对象是个墓碑）时另起一条**新 id** 的操作顶上，原来那条的意图由新操作
  /// 原样带走——已发出去过的 id 绝不能改载荷再发，服务端按 digest 认人。
  ///
  /// 走队列时同时按服务端规则**推演**每个对象的状态：队列里排在前面的 `delete`
  /// 还没发出去，也得算进来，否则紧跟着的 `restore` 会被误判成「对象没被删、
  /// 降级成 patch」，用户的撤销就丢了。
  public func realign() throws {
    try transaction { a in
      var projected: [String: (revision: Int64, generation: Int64, deleted: Bool)] = [:]
      var replaced: [UUID: UUID] = [:]
      for index in a.operations.indices {
        var op = a.operations[index]
        if let previous = op.dependsOn, let fresh = replaced[previous] { op.dependsOn = fresh }
        let remote = a.objects[op.key]
        var state = projected[op.key] ?? (remote?.revision ?? 0, remote?.generation ?? 0, remote?.deleted ?? false)
        if !a.sent.contains(op.id) {
          var action = op.action
          if action == "restore" && !state.deleted {
            // 对象在云端根本没被删（别的设备先恢复了 / 我们的删除整批回滚了）。
            // `restore` 这条路永远走不通，但用户的值还在载荷里，降级成 patch 送上去。
            action = "patch"
          } else if action == "patch" && state.deleted && a.local[op.key]?.deleted == false {
            // 云端是个墓碑，本机这份还活着：服务端会把 patch 默默吞掉，得用 restore。
            action = "restore"
          }
          if action != op.action {
            let fresh = UUID(); replaced[op.id] = fresh
            op.id = fresh; op.action = action
          }
          op.generation = state.generation
          op.baseRevision = action == "restore" ? state.revision : min(op.baseRevision, state.revision)
        }
        // 发没发出去，都要按服务端规则把这个对象的状态往前推，后面那条才对得上。
        if op.action == "restore" {
          if state.deleted { state.deleted = false; state.generation += 1; state.revision += 1 }
        } else if op.action == "delete" {
          state.deleted = true; state.revision += 1
        } else if !state.deleted {
          state.revision += 1
        }
        projected[op.key] = state
        a.operations[index] = op
      }
    }
  }
  public func markSent(_ id: UUID) throws { try transaction { $0.sent.insert(id) } }
  /// 隔离一条**永远不会成功**的操作：把它从待发队列里拿走，连同用户当时的意图
  /// 一起记进存档的 `rejected`。
  ///
  /// 用在服务端按语义顶回来（400 / 422）的时候。不这么做的话这条操作会被无限重发，
  /// 而 `run` 那句「没进展就 break」会让它**把后面所有人的操作一起堵死**——
  /// 一次缩放就能让这个账号从此再也同步不上任何东西。
  ///
  /// **不再把 `local` 退回服务端那一份。** 那一步原本是为了让下一次 `capture` 还能
  /// 差分出改动，代价却是 `applyPending()` 会拿云端那份旧的写回用户的图：他刚删掉的
  /// 标注文字自己长回来（B3）。设置那一档还有 `SettingsStamp` 的脏标记顶着，画线
  /// 什么都没有。现在本地值保持用户的值不动，改由 `rejected` 这条记录来承担两件事：
  /// 一是 `holdsLocal` 认它，云端那份就写不进 `local`；二是服务端修好之后
  /// `retryRejected` 拿当前本地值和当前云端对象重新组一条**新 id** 的操作补推。
  ///
  /// 一个对象只留最近的一条，队列和状态栏都不会越积越长。
  public func quarantine(_ id: UUID, reason: String) throws {
    try transaction { a in
      guard let index = a.operations.firstIndex(where: { $0.id == id }) else { return }
      let op = a.operations.remove(at: index)
      a.sent.remove(id)
      // 依赖这条的后续操作直接接到它的前驱上，链不断。
      for i in a.operations.indices where a.operations[i].dependsOn == id { a.operations[i].dependsOn = op.dependsOn }
      let intent = a.local[op.key] ?? a.objects[op.key] ?? SyncObject(collection: op.collection, id: op.objectId)
      a.rejected.removeAll { $0.key == op.key }
      a.rejected.append(RejectedOperation(operation: op, reason: reason,
        at: Int64(Date().timeIntervalSince1970 * 1000) + a.offset, intent: intent))
    }
  }
  /// 服务端修好之后，把还没了结的拒绝记录**用一条新 id 的操作**补推上去。
  ///
  /// 只在全量同步那一档调。每次推送后都重试就是个忙循环：服务端要是真的永远不认
  /// 这个字段，那就是每 500 毫秒一次跨洋往返换一次 400。全量之间至少隔五分钟。
  ///
  /// 三种情况直接把记录了结掉，不再补推：本机已经没有这个对象了；本地值和云端
  /// 那份已经一样了（别的路补上了 / 服务端那边被别人改成了同一个值）；这个对象
  /// 上又有了新的待发操作（那条会带着当前值上去，不必再来一条）。
  ///
  /// 新操作是拿**当前本地值**和**当前云端对象**现做的差分，不是把老载荷重发一遍：
  /// 老载荷是当初那一刻的，服务端的对象早就往前走了。
  ///
  /// **`ownedKeys` 必须和 `capture` 传的是同一张表。** 这儿是差分的另一个入口，
  /// 而且是**最容易踩到外来字段的那个**：它明摆着拿云端那份当 `previous`
  /// （下面那句 `staged.local[record.key] = remote`），云端带着的遗留字段一个不少。
  /// 少传这张表，被拒的那条操作就会原样再差出同一个 null、再被拒一次，
  /// 每轮全量同步换一次跨洋 400。
  public func retryRejected(device: UUID, owning ownedKeys: [String: Set<String>] = [:]) throws {
    guard !archive.rejected.isEmpty else { return }
    var staged = archive
    var changed = false
    var keep: [RejectedOperation] = []
    for record in staged.rejected {
      guard let local = staged.local[record.key] else { continue }
      let remote = staged.objects[record.key] ?? SyncObject(collection: record.collection, id: record.objectId)
      guard local.body != remote.body || local.deleted != remote.deleted else { continue }
      guard !staged.operations.contains(where: { $0.key == record.key }) else { keep.append(record); continue }
      // `stage` 是拿 `local` 做差分的，而这儿 `local` 就是用户的值本身——先把记账
      // 退回云端那份，`stage` 才能重新差出「本地和云端不一样的那几项」。这一下只动
      // 存档里的记账，用户眼前的值（prefs / draws.json）一个字都没碰。
      staged.local[record.key] = remote
      if stage(local, device: device, importing: nil, owning: ownedKeys, into: &staged) { changed = true }
      keep.append(record)
    }
    guard changed || keep.count != staged.rejected.count else { return }
    staged.rejected = keep
    try transaction { $0 = staged }
  }
  /// 一批已发操作一次记完，别一条一条来。
  public func markSent(_ ids: [UUID]) throws {
    guard !ids.isEmpty else { return }
    try transaction { a in for id in ids { a.sent.insert(id) } }
  }
  /// 回执入账。
  ///
  /// 后面那些**还没发出去**的同对象操作要不要跟着这次回执往前挪，分得很细——
  /// 这一段就是 B5 的正解：
  ///
  /// - `restore`：`baseRevision` 和 `generation` 都对齐回执里的对象。它要求
  ///   `base == revision` 精确相等、`generation` 相等，而**它依赖的正是我自己
  ///   前一条**（删除）——这是我这条链的正确性要求，不是在替用户重新观察云端。
  /// - `patch` / `delete`：**`baseRevision` 一个字都不动。** 那是用户当初看到的
  ///   那一版。回执里的对象可能带着设备 B 的并发修改，而我创建这些离线操作时
  ///   根本没见过它；抬上去之后服务端的 `op.base_revision >= old.revision` 短路
  ///   会把「传输上晚发」当成「用户看过新版本之后又改了一次」，于是积压 100 条
  ///   时 B 赢、101 条时 A 那条更旧的值反而赢。用户没做任何不同的事。
  ///   base 不动，服务端就按时间戳正常比大小，分批边界再也决定不了赢家。
  /// - `generation` 只有在**这次 ACK 的是我自己这条链上的 `restore`** 时才对齐：
  ///   那是我自己把 generation 推上去的。generation 要是被别人推的（设备 B 删了
  ///   又恢复），就让它按 409 走 `rollback` + 重拉 + `realign` 那条恢复路径，
  ///   不在这儿偷偷抬——偷偷抬等于假装本机见过 B 的那一轮删除恢复。
  public func acknowledge(_ response: SyncPushResponse) throws {
    try transaction { a in
      a.offset = response.serverTime - Int64(Date().timeIntervalSince1970 * 1000)
      for result in response.results {
        let acked = a.operations.first { $0.id == result.operationId }
        a.objects[result.object.key] = result.object
        a.operations.removeAll { $0.id == result.operationId }; a.sent.remove(result.operationId)
        // 断链：依赖这条的后续操作接到它的前驱上。
        for index in a.operations.indices where a.operations[index].dependsOn == result.operationId {
          a.operations[index].dependsOn = acked?.dependsOn
        }
        let generationIsMine = acked?.action == "restore"
        for index in a.operations.indices where !a.sent.contains(a.operations[index].id) && a.operations[index].key == result.object.key {
          if a.operations[index].action == "restore" {
            a.operations[index].baseRevision = result.object.revision
            a.operations[index].generation = result.object.generation
          } else if generationIsMine {
            a.operations[index].generation = result.object.generation
          }
        }
        // 这一条终于推上去了，而且云端那份已经和本机一样：那条拒绝记录可以了结。
        if let local = a.local[result.object.key], local.body == result.object.body, local.deleted == result.object.deleted {
          a.rejected.removeAll { $0.key == result.object.key }
        }
        if !a.holdsLocal(result.object.collection, result.object.id) { a.local[result.object.key] = result.object }
      }
    }
  }
  public func receive(_ page: SyncPage) throws {
    try transaction { a in
      a.offset = page.serverTime - Int64(Date().timeIntervalSince1970 * 1000)
      for object in page.objects {
        a.objects[object.key] = object
        // 有待发操作**或者**有未了结的拒绝记录，就都别让云端那份盖掉本机的值。
        if !a.holdsLocal(object.collection, object.id) { a.local[object.key] = object }
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
