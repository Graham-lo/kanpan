import Foundation

/// 一次拉取的范围：一个集合，可选再按对象 id 前缀收窄（画线按品种：`venue/market/symbol/`）。
public struct SyncScope: Hashable, Sendable, CustomStringConvertible {
  public var collection: String
  public var prefix: String?
  public init(_ collection: String, prefix: String? = nil) { self.collection = collection; self.prefix = prefix }
  public var description: String { prefix.map { collection + "?" + $0 } ?? collection }
}

/// 个人同步的一轮：**先推、后拉**。
///
/// 这是从 `AppAccountBridge.run` 原样搬出来的那个循环（2026-09-24，深度审查第 22 项），
/// 桥上只剩接线：什么时候起一轮、这一轮算不算数（`stillCurrent`）、推完之后清哪些脏标记
/// （`onPushed`）、拉完之后要不要把云端那批装进本机。循环本身不认识 app 里任何一个
/// 业务类型——它只认 `SyncStore` 和 `SyncTransport`，所以 `swift test` 能直接驱动它，
/// 测试不再维护一份手抄的替身（`SyncLoop`，已删）。
///
/// ## 推送循环的分支（每一条都有一个用例钉着，见 `SyncEngineTests`）
///
/// - 一批 = 队首**能安全同批**的那几条（`SyncStore.batch`），再受条数（服务端上限 100）
///   与**编码之后的字节数**两道闸（`SyncStore.nextBatch(limit:maxBytes:)`）。
/// - 单独一条就超字节预算：隔离掉（`payload_too_large`），不让它堵住后面所有人。
/// - 413：服务端连读都没读完，这一批一条都没落库 → 退回未发送、预算对半砍（不低于 16 KiB）。
/// - 409 `resync_required`：整个事务回滚了 → 退回未发送、**这一轮里就**把碰过的对象
///   重拉一遍、按新版本重整（`realign`），接着推。一轮最多三次。
/// - 400 / 422 / `invalid_operation` / `idempotency_mismatch`：再发一万次也不会成功 →
///   先改成一条一条发把坏的那条揪出来，再单独隔离。
/// - 服务端没认掉任何一条：不空转，收工。
/// - 其它错误（断网、5xx、401、429、410…）原样抛给调用方；`demandsBootstrap` 告诉它
///   下一轮要不要整份重拉。
///
/// ## 谁赢
///
/// 对象级的胜负只有一条规则，住在 `SyncArchive.holdsLocal`：这个对象上有待发操作或
/// 未了结的拒绝记录，本机的值说了算，云端那份（拉取 / 回执）写不进 `local`；否则云端
/// 那份就是 `local`。同一个字段上两台设备的先后由服务端按时间戳判（`merge()`），
/// 客户端不替它猜——所以回执里的 `baseRevision` 绝不往上抬（B5，见 `acknowledge`）。
@MainActor public final class SyncEngine {
  /// 这一轮做到哪一步。
  public enum Plan: Equatable, Sendable {
    /// 只把待发操作推上去。
    case push
    /// 推完再拉一个品种的画线。参数是画线 id 的品种前缀（`venue/market/symbol/`）。
    case drawings(prefix: String)
    /// 推完拉四档全量（设置、画线工具偏好、自选、分组、提醒），有品种时再带它的画线；
    /// 最后把被服务端顶回来过的那几项用新 id 补推一次。
    case full(drawingsPrefix: String?)
  }

  /// 一轮下来的结果。
  public struct Outcome: Sendable, Equatable {
    /// 被跟踪的那个对象（`trackedKey`，默认设置那一份）里，服务端**认下**的线上字段路径。
    public var acked: Set<String> = []
    /// 同一个对象里**没落地**的：回执里 `droppedFields` 顶回来的、整条没回执的、被隔离的、
    /// 这一轮结束时还躺在队列里的。它得和 `acked` 一起交给脏标记那一层：一个本地字段
    /// 在线上可能是好几条路径，只认下一条就清整个字段，等于把没推上去的那条当成推过了。
    public var dropped: Set<String> = []
    /// 真的拉过的范围，按拉的顺序。
    public var pulled: [SyncScope] = []
    /// 实际发出去的每一批的条数（观测用：确认没退化成一条一个请求）。
    public var batches: [Int] = []
    /// 全量那一档补推拒绝记录之后，队列里又有了东西（调用方该再排一轮推送）。
    public var leftovers = false
    public init() {}
  }

  /// 服务端一次最多收 100 条操作（`Backend/kanpan-api/src/sync.rs` 的 `push`）。
  public static let batchLimit = 100
  /// 一批**编码之后**最多多少字节。服务端整个请求体只收 512 KiB
  /// （`kanpan-api/src/lib.rs` 的 `DefaultBodyLimit`），留 128 KiB 给 HTTP 头、令牌与余量。
  public static let batchBytes = 384 * 1024
  /// 413 之后预算砍到这儿就不再往下砍：再小也只能说明是那一条本身发不上去，
  /// 下一圈开头那道字节闸会把它认出来并隔离掉，循环一定收敛。
  public static let minimumBatchBytes = 16 * 1024
  /// 一轮里最多做几次「回滚 → 重拉 → 重整 → 接着推」。正常最多用一次；给三次是为了容下
  /// 「重拉的同时别的设备又改了一次」，再多就不是冲突而是打转了，剩下的留给下一轮。
  public static let resyncBudget = 3

  public let store: SyncStore
  public let transport: any SyncTransport
  public let device: UUID
  /// 这个客户端替哪些键说话（`SyncStore.capture` 用的同一张表），补推拒绝记录时要用。
  public let owning: [String: Set<String>]
  /// 要回报 `acked` / `dropped` 的那个对象（`collection:id`）。
  public var trackedKey = "settings:chart"
  public var batchLimit = SyncEngine.batchLimit
  public var batchBytes = SyncEngine.batchBytes
  /// 这一轮还算不算数（换了账号、又起了一轮）。每次网络往返回来都问一次，不算数就
  /// 抛 `CancellationError`，存档一个字节都不再动。
  public var stillCurrent: @MainActor () -> Bool = { true }
  /// 队列有了变化（隔离、回滚、重整），状态栏可以刷新了。
  public var onProgress: @MainActor () -> Void = {}
  /// 推送阶段结束、拉取开始之前响一次，带着这一轮的 `acked` / `dropped`。
  ///
  /// 放在拉取**之前**是有意的：拉取抛错（断网）时，已经推上去的那几个字段的脏标记
  /// 照样要清——它们确实已经在云端了。
  public var onPushed: @MainActor (_ acked: Set<String>, _ dropped: Set<String>) -> Void = { _, _ in }

  public init(store: SyncStore, transport: any SyncTransport, device: UUID, owning: [String: Set<String>] = [:]) {
    self.store = store; self.transport = transport; self.device = device; self.owning = owning
  }

  /// 这一档要拉的范围，按顺序。
  public static func scopes(for plan: Plan) -> [SyncScope] {
    switch plan {
    case .push: return []
    case .drawings(let prefix): return [SyncScope("drawings", prefix: prefix)]
    case .full(let prefix):
      return ["settings", "drawingPreferences", "favorites", "groups", "alerts"].map { SyncScope($0) }
        + (prefix.map { [SyncScope("drawings", prefix: $0)] } ?? [])
    }
  }

  /// 跑一轮。
  @discardableResult public func run(_ plan: Plan) async throws -> Outcome {
    var outcome = Outcome()
    do {
      try await push(into: &outcome)
    } catch {
      // 多批推送推到一半断了：前面几批的回执已经入账，那几个字段确实在云端了，
      // 这一轮不报就再也没人报——它们的脏标记会一直挂着，这个字段从此不再跟着云端走。
      // 所以照样报一次（队列里剩下的记成 dropped，挡住同名字段被误清），再把错误抛出去。
      // 这一轮不算数了（换了账号、又起了一轮）就不报：那是别人的档案。
      if stillCurrent() {
        for op in store.archive.operations { track(op, into: &outcome.dropped) }
        onPushed(outcome.acked, outcome.dropped)
      }
      throw error
    }
    onPushed(outcome.acked, outcome.dropped)
    for scope in Self.scopes(for: plan) {
      try await pull(scope)
      outcome.pulled.append(scope)
    }
    if case .full = plan {
      // 服务端修好之后，被它顶回来过的那几项自己补上去，不用用户再改一次。
      // **只在全量这一档。** 每次推送后都重试就是个忙循环：服务端要是真的永远不认
      // 这个字段，那就是每 500 毫秒一次跨洋往返换一次 400。这儿刚把云端那份拉回来，
      // 正好拿它和当前本地值现做差分。
      try store.retryRejected(device: device, owning: owning)
      outcome.leftovers = !store.archive.operations.isEmpty
    }
    return outcome
  }

  // MARK: - 推

  private func push(into outcome: inout Outcome) async throws {
    // 撞过一次「这条永远不会成功」之后，在**那一批里**对半切着发，把坏的那条揪出来单独隔离。
    //
    // `suspects` 是队首这几条：一起发会被服务端按语义整批顶回来，坏的那条就在里头。
    // 每次只发它的前一半——前一半过了，坏的在剩下那段里；前一半也被顶，就把嫌疑缩到这一半。
    // 缩到一条还被顶就是它，隔离掉，嫌疑清零，**回到整批发**。
    //
    // 从前是一个撞过就再也不复位的 `oneByOne`：一条坏操作之后，这一轮里队列剩下的每一条
    // 都单独一个跨洋请求。离线攒了 5000 条、第 50 条是坏的，就是 4950 次往返
    // （压测 2026-09-26：5000 条、第 50 条坏，修前 5001 个请求，修后 57 个）。
    var suspects = 0
    var resyncs = Self.resyncBudget
    // 这一轮的字节上限。撞过 413 就对半砍，砍到单条也过不去时把那条隔离掉。
    var budget = batchBytes
    while !store.archive.operations.isEmpty {
      try checkpoint()
      let batch = store.nextBatch(limit: suspects > 0 ? max(1, suspects / 2) : batchLimit, maxBytes: budget)
      let ids = batch.map(\.id)
      let payload = try JSONEncoder().encode(SyncPushRequest(batch))
      if payload.count > budget {
        // 单独一条就超限：它再发一万次也只会换回 413。和语义错误那一档同一个处置——
        // 隔离掉，本地值与脏标记一个不动。
        track(batch[0], into: &outcome.dropped)
        try store.quarantine(batch[0].id, reason: "payload_too_large")
        suspects = max(0, suspects - 1)
        onProgress()
        continue
      }
      let before = store.archive.operations.count
      try store.markSent(ids)
      outcome.batches.append(batch.count)
      let result: SyncPushResponse
      do {
        result = try await transport.push(payload, key: batch[0].id)
      } catch let error as AccountError where Self.isTooLarge(error) {
        // 413：这一批一条都没落库 → 先清 `sent`，再把上限对半砍了重来。
        try checkpoint()
        try store.rollback(ids)
        budget = max(Self.minimumBatchBytes, min(budget, payload.count) / 2)
        onProgress()
        continue
      } catch let error as AccountError where Self.isRollback(error) && resyncs > 0 {
        // 服务端那一整个事务已经回滚：清 `sent`，**在同一轮里**把受影响的对象拉回来、
        // 按新版本重整本地意图，接着推。等下一轮就是回到同一个 409 里打转（B1）。
        try checkpoint()
        resyncs -= 1
        try store.rollback(ids)
        for scope in Self.refetchScopes(batch) { try await pull(scope) }
        try store.realign()
        onProgress()
        continue
      } catch let error as AccountError where Self.isPermanent(error) {
        // 语义错误：重试只会把整条队列堵死。先揪出是哪一条，再单独隔离——
        // **本地值和脏标记一个都不动**，下次启动本地照样赢（B3）。
        try checkpoint()
        guard batch.count == 1 else { suspects = batch.count; continue }
        let reason: String = { if case .http(_, let code) = error { return code }; return "request_failed" }()
        try store.quarantine(batch[0].id, reason: reason)
        track(batch[0], into: &outcome.dropped)
        // 揪出来了。嫌疑段里剩下的要是还有坏的，整批发时会再被顶一次、再切一次。
        suspects = 0
        onProgress()
        continue
      }
      try checkpoint()
      let receipts = Dictionary(result.results.map { ($0.operationId, Set($0.droppedFields ?? [])) },
                                uniquingKeysWith: { a, _ in a })
      var acked = Set<String>(), dropped = Set<String>()
      for op in batch where op.key == trackedKey {
        guard let missed = receipts[op.id] else { dropped.formUnion(op.fields.keys); continue }  // 没回执 = 没认掉
        acked.formUnion(op.fields.keys.filter { !missed.contains($0) })
        dropped.formUnion(missed)
      }
      // 回执入账成功之后才算进这一轮：入账抛错时这一批还留在队列里，由收尾那句记成 dropped。
      try store.acknowledge(result)
      outcome.acked.formUnion(acked); outcome.dropped.formUnion(dropped)
      // 这一段过了：坏的那条在嫌疑段剩下的部分里。
      if suspects > 0 { suspects = max(0, suspects - batch.count) }
      // 服务端没认掉任何一条就别空转。
      guard store.archive.operations.count < before else { break }
    }
    // 跳出循环时队列里还剩下的：也算没落地。
    for op in store.archive.operations { track(op, into: &outcome.dropped) }
  }

  private func track(_ op: SyncOperation, into set: inout Set<String>) {
    if op.key == trackedKey { set.formUnion(op.fields.keys) }
  }

  // MARK: - 拉

  private func pull(_ scope: SyncScope) async throws {
    var after: String?
    repeat {
      let page = try await transport.bootstrap(collection: scope.collection, prefix: scope.prefix, after: after)
      try checkpoint()
      try store.receive(page)
      after = page.next
    } while after != nil
  }

  /// 被 409 顶回来之后要重拉的范围：按集合归并，画线再按品种那一层的前缀收窄
  /// （画线 id 是 `venue/market/symbol/<线 id>`）。既不会退化成一条一个请求，
  /// 也不会为了一条线把这个人所有品种的画线都拖回来。
  public static func refetchScopes(_ batch: [SyncOperation]) -> [SyncScope] {
    var scopes: Set<SyncScope> = []
    for op in batch {
      guard op.collection == "drawings" else { scopes.insert(SyncScope(op.collection)); continue }
      let folder = op.objectId.split(separator: "/").dropLast().joined(separator: "/")
      scopes.insert(folder.isEmpty ? SyncScope(op.collection) : SyncScope(op.collection, prefix: folder + "/"))
    }
    return scopes.sorted { $0.description < $1.description }
  }

  private func checkpoint() throws {
    try Task.checkCancellation()
    guard stillCurrent() else { throw CancellationError() }
  }

  // MARK: - 错误分类

  /// 这个错误是不是「再发一万次也不会成功」。
  ///
  /// 400 / 422 是服务端对内容本身的判决；401 要重新登录、429 是限流、5xx 与网络错误都是
  /// 「这次不行」，留在队列里等下一轮。409 分两种：`resync_required` 见 `isRollback`；
  /// `idempotency_mismatch` 是「同 id 的操作已经落过库、载荷却对不上」，只能隔离。
  public static func isPermanent(_ error: AccountError) -> Bool {
    guard case .http(let code, let reason) = error else { return false }
    if reason == "idempotency_mismatch" { return true }
    if code == 401 || code == 409 || code == 429 { return false }
    return code == 400 || code == 422 || reason == "invalid_operation"
  }
  /// 请求体太大被挡在门外（413）：`DefaultBodyLimit` 在进 handler 之前就拒了，没到数据库。
  public static func isTooLarge(_ error: AccountError) -> Bool {
    guard case .http(413, _) = error else { return false }
    return true
  }
  /// 这个错误能不能证明**这一批服务端一条都没落库**：只有 `resync_required`
  /// （`merge()` 在事务里抛的，`tx.commit()` 没跑到）。
  public static func isRollback(_ error: AccountError) -> Bool {
    guard case .http(409, let reason) = error else { return false }
    return reason == "resync_required"
  }
  /// 这一轮抛出来的错误之后，下一轮要不要整份重拉：服务端按版本 / 游标把我们顶回来了
  /// （409 用完了重整次数、410 `cursor_expired`、400 之类），本机这份不再可信。
  /// 401（要重新登录）和 429（限流）不算——那跟本机这份对不对无关。
  public static func demandsBootstrap(_ error: any Error) -> Bool {
    guard case AccountError.http(let code, _) = error else { return false }
    return (400..<500).contains(code) && code != 401 && code != 429
  }
}
