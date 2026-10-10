import Foundation
import KanpanCore
import KanpanAccount
import ReviewUI

/// 同步引擎的起停与调度：什么时候起一轮、这一轮做到哪一步（推 / 拉画线 / 全量）、
/// 这一轮还算不算数（`epoch` + `taskID`）、被挡下来的推送跑完补上、本地改动去抖之后推，
/// 以及账号页上那几个状态数（`updateStatus`）。
///
/// 从 `AppAccountBridge` 原样搬出来（2026-10-10 拆分）。推、拉、谁赢、出错怎么退都在
/// `SyncEngine`（`KanpanAccount`）；这里只管这一轮算不算数、推完清哪些脏标记、拉完要不要装进本机。
/// 「装进本机」那一步不在这儿做，交给注入进来的 `applyIfDue`（`SyncApplier`）。
@MainActor final class SyncLifecycle {
  private let profile: ActiveProfile
  private let account: AccountFeature
  private let prefs: PrefsStore
  private let review: ReviewFeature

  /// 一轮推 / 拉成了之后，要不要把云端那批装进本机、装就装。参数是这一轮**起跑时**的那份存档
  /// （判「欠着没装」看它），真正装的是 `ActiveProfile` 上此刻那份——和搬家之前逐字一样。
  /// 由 `AppAccountBridge` 接到 `SyncApplier.applyIfDue(_:)`。
  var applyIfDue: (SyncStore) throws -> Void = { _ in }
  /// 每一轮同步跑完都拉一次「品种上新与停牌下架」通知（`AccountChores.pullListingNotices`）。
  var pullListingNotices: () -> Void = {}

  private var task: Task<Void, Never>?
  private var taskID = UUID()
  private var debounce: Task<Void, Never>?
  private var symbol = ""
  /// 上一次真的做过全量 bootstrap 的时刻。
  private var lastBootstrap = Date.distantPast
  /// 下一次同步必须做全量：登录 / 恢复会话 / 刚被服务端顶回来（版本冲突）之后置上。
  private var needsBootstrap = true
  /// 这个会话里已经按品种拉过画线的品种。切回老品种不再重复拉。
  private var bootstrappedDrawings: Set<String> = []
  /// 两次全量 bootstrap 之间的最小间隔。
  private static let bootstrapInterval: TimeInterval = 300
  /// 上一轮还在跑时被挡下来的那次推送（值是它的 `manual`）。跑完补上。
  ///
  /// 以前 `run` 开头那句 `guard task == nil` 是**直接吞掉**的：用户手一松要求推一次，
  /// 正赶上前一轮同步没跑完，这一次就当没发生过。存档里那条操作只能等下一次触发，
  /// app 要是这会儿被杀，云端就永远停在旧值上。
  private var queuedPush: Bool?

  init(profile: ActiveProfile, account: AccountFeature, prefs: PrefsStore, review: ReviewFeature) {
    self.profile = profile; self.account = account; self.prefs = prefs; self.review = review
  }

  /// 自动同步开没开。登录了就一直同步：原来同步页上有一颗「自动同步」开关（存在
  /// `SyncArchive.autoSync` 里，关掉时状态写「已暂停」），2026-09-28 收掉（收设置项 H）——
  /// 登录就是为了跨设备同步，关掉它只会让两台设备悄悄分叉。老存档里存着 `false` 的也不再认，
  /// 升级上来的那台当场恢复同步。
  ///
  /// DEBUG 包留一个测试后门 `KANPAN_TEST_HOLD_SYNC=1`：这一次启动只在点「立即同步」时推拉，
  /// 跨设备并发用例（P4.5）靠它让两台各自攒着改动不推。正式包没有这一行。
  private static var automaticSync: Bool {
    #if DEBUG
      if ProcessInfo.processInfo.environment["KANPAN_TEST_HOLD_SYNC"] == "1" { return false }
    #endif
    return true
  }
  /// 账号页「还有 N 条没上云」的那个数：同步队列里的操作 + 复盘待传的那几笔。
  ///
  /// 只算这一处（审查 D-10）：以前同步失败的那条路自己写了一份只数同步操作的，一失败
  /// 复盘那几笔就从角标上没了，下一次 `updateStatus()` 又冒回来，数字来回跳。
  static func pendingCount(operations: Int, reviewUploads: Int) -> Int { operations + reviewUploads }
  func updateStatus() {
    review.autoSync = Self.automaticSync
    account.pending = Self.pendingCount(operations: profile.sync?.archive.operations.count ?? 0, reviewUploads: review.pendingUploads)
    account.lastSync = profile.sync?.archive.lastSync.map { Date(timeIntervalSince1970: Double($0) / 1000) }
    // 被隔离的那几条要说出来：它们不在 `pending` 里（不会永远挂着归不了零），
    // 但用户的改动确实还没上云——这句就是那件事的唯一交代。
    //
    // 数是从**存档**里读的，不是内存里的一个数组：那些改动重启之后还在本机、
    // 还没推上去，这句话重启之后也就还得成立（B3）。
    let stuck = profile.sync?.archive.rejected.count ?? 0
    account.syncStatus = profile.owner == nil ? "" : account.pending > 0 ? "待同步"
      : stuck > 0 ? "\(stuck) 项暂未同步"
      : account.lastSync == nil ? "尚未同步" : "已同步"
  }

  /// 换档案那一刻收掉上一份档案的这一轮：在途的同步、还没到点的去抖推送一并作废，
  /// `taskID` 换掉，还在途那一轮跑完时认出自己不算数。
  ///
  /// 只由 `AccountProfileSwitcher` 的提交那一段调，排在换代次（`epoch`）之前，顺序同搬家之前。
  func endRound() {
    task?.cancel(); debounce?.cancel(); task = nil; taskID = UUID()
  }
  /// 换属主之后本机拿到的是空档，下一次同步必须把服务端那份整份拉回来。
  func forgetBootstrap() {
    needsBootstrap = true; lastBootstrap = .distantPast; bootstrappedDrawings = []
  }
  /// 本机刚记完一笔账：网络推送留给 500ms 去抖——那是省流量，不是省命
  /// （为什么不在手指上等落盘，见 `SyncRecorder.capture` 那段注释）。
  func schedulePush() {
    debounce?.cancel()
    debounce = Task { [weak self] in
      try? await Task.sleep(for: .milliseconds(500)); guard !Task.isCancelled else { return }; self?.run(.push, manual: false)
    }
  }

  /// 图上换了品种。
  ///
  /// 以前这里直接 `synchronize()`：推完待发操作还要无条件走一遍四个 collection 的
  /// 全量 bootstrap 再加一次复盘同步，已登录用户每换一个品种就是五六次跨洋往返
  /// 加好几次整档重写。现在只做两件事——有待发就推，以及**这个会话里第一次**
  /// 看到这个品种时把它的画线拉一次（别的设备上画的线还是会出现，只是不再每次重拉）。
  func focus(_ symbol: String) {
    guard self.symbol != symbol else { return }
    self.symbol = symbol
    guard let sync = profile.sync, profile.owner != nil else { return }
    let fresh = !symbol.isEmpty && !bootstrappedDrawings.contains(symbol)
    guard fresh || !sync.archive.operations.isEmpty else { return }
    run(fresh ? .drawings : .push, manual: false)
  }
  /// 外部（回前台、设置页、登录回调）唯一的入口。到点了才做全量。
  ///
  /// 推送令牌、收件箱、品种通知这几件同步之外的事由 `AppAccountBridge.synchronize` 接在后面。
  func synchronize(manual: Bool) {
    let due = needsBootstrap || Date().timeIntervalSince(lastBootstrap) >= Self.bootstrapInterval
    run(manual || due ? .full : .push, manual: manual)
  }
  /// 等此刻在跑的这一轮跑完，档案没换过就做 `work`；换过就作废。
  func afterCurrentRound(_ work: @escaping @MainActor () -> Void) {
    let current = profile.epoch; let running = task
    Task { [weak self] in
      await running?.value
      guard let self, profile.epoch == current else { return }
      work()
    }
  }

  /// 这一轮同步做到哪一步。
  enum SyncPlan {
    /// 只把待发操作推上去。切品种、本地改动去抖之后走这条。
    case push
    /// 推完再拉一次当前品种的画线（每个品种每个会话一次）。
    case drawings
    /// 推完拉四档全量，再带一次复盘同步。只在登录 / 恢复会话 / 手动同步 /
    /// 距上次全量 ≥5 分钟的回前台 / 被服务端顶回来之后发生。
    case full
  }

  func run(_ plan: SyncPlan, manual: Bool) {
    guard task == nil else {
      // 全量 / 画线那两档自己有别的触发点（回前台、换品种），不必排队；
      // 会丢东西的只有「把待发操作推上去」这一档。
      if case .push = plan { queuedPush = (queuedPush ?? false) || manual }
      return
    }
    guard let sync = profile.sync, let api = account.client, let owner = profile.owner, manual || Self.automaticSync else { return }
    let requestEpoch = profile.epoch; let requestedSymbol = symbol
    let runID = UUID(); taskID = runID
    account.syncStatus = "同步中"
    task = Task { [weak self] in
      guard let self else { return }
      defer {
        if requestEpoch == profile.epoch && taskID == runID {
          task = nil
          // 这一轮跑的时候用户又换了品种：补一次，但只补新品种要的那点。
          if requestedSymbol != symbol {
            let fresh = !symbol.isEmpty && !bootstrappedDrawings.contains(symbol)
            if fresh || !sync.archive.operations.isEmpty { run(fresh ? .drawings : .push, manual: false) }
          }
          // 这一轮跑的时候有人要过推送、被上面那道 guard 挡了：现在补上。
          if let queued = queuedPush, task == nil {
            queuedPush = nil
            if !sync.archive.operations.isEmpty { run(.push, manual: queued) }
          }
        }
      }
      do {
        // 推上去那一刻的脏字段快照。推成功之后按「时刻没变」逐个清——
        // **推成功才清**，失败 / 断网 / 被杀都留着，下次启动本地照样赢。
        let marks = prefs.dirtyMarks
        // 推、拉、谁赢、出错怎么退都在 `SyncEngine` 里（`KanpanAccount`，swift test 直接测）；
        // 桥上只管这一轮算不算数、推完清哪些脏标记、拉完要不要装进本机。
        // 传输钉在这份同步存档的主人上：换号之后这一轮还在途的推 / 拉当场取消，
        // A 的待发操作不会带着 B 的令牌进 B 的云端，B 的对象也不会写进 A 的存档。
        let engine = SyncEngine(store: sync, transport: HTTPSyncTransport(client: api, owner: owner),
                                device: account.device.id, owning: PersonalSyncCodec.ownedKeys)
        engine.stillCurrent = { [weak self] in self.map { $0.profile.epoch == requestEpoch && $0.taskID == runID } ?? false }
        engine.onProgress = { [weak self] in self?.updateStatus() }
        // **只清服务端认下的那几个字段。** 被隔离的、被 `droppedFields` 丢掉的、
        // 还在队列里没发的，脏标记全都留着——下次启动本地照样赢。放在拉取之前：
        // 拉取断了，已经推上去的那几个字段也确实在云端了。
        // 回调时再确认一次这一轮还算数：换了账号，`prefs` 已经是另一份档案，不许替它清脏标记。
        engine.onPushed = { [weak self] acked, dropped in
          guard let self, profile.epoch == requestEpoch, taskID == runID else { return }
          prefs.syncPushed(marks, acked: acked, dropped: dropped)
        }
        let drawingsPrefix = requestedSymbol.isEmpty ? nil : InstrumentID.canonical(requestedSymbol) + "/"
        let outcome: SyncEngine.Outcome
        switch plan {
        case .push: outcome = try await engine.run(.push)
        case .drawings: outcome = try await engine.run(drawingsPrefix.map { .drawings(prefix: $0) } ?? .push)
        case .full: outcome = try await engine.run(.full(drawingsPrefix: drawingsPrefix))
        }
        if outcome.pulled.contains(where: { $0.collection == "drawings" }) { bootstrappedDrawings.insert(requestedSymbol) }
        if case .full = plan {
          needsBootstrap = false; lastBootstrap = Date()
          // 全量补推拒绝记录之后队列里又有了东西：跑完这一轮接着推。
          if outcome.leftovers { queuedPush = queuedPush ?? false }
        }
        // 装进本机只装**云端真的改过的那几张表**（`SyncStore.unapplied`，和写 `local` 的那笔
        // 同一个事务里记下）。一轮纯推送、回执又没带回别的设备的改动时它是空的，
        // `applyPending()` 那一整套（合并、两次主线程 `flushNow()`、`onProfileReady()`）整个跳过；
        // 换品种拉画线时只动画线那一份。全量同步例外：它把整份都记成欠着，顺手把正式文件与
        // `local` 之间任何说不清的差异扳回来——那一档五分钟最多一次，不在手指上。
        //
        // 深度审查 §9 的疑问「纯推送之后 `applyPending` 是否还承担把 realign 出的本地值落盘」：
        // 不承担。`realign` 只改操作的版本元信息、不碰 `local`；回执只在 `!holdsLocal` 时写
        // `local`，内容一变就记进 `unapplied`。`PushOnlyRoundTests` 逐条钉住。
        if case .full = plan { try sync.markUnapplied(nil) }
        // 「上次同步」：这一轮推 / 拉都成了。它不再兼任「有没有要装的」，那是 `unapplied` 的事。
        try sync.markFetched(at: Int64(Date().timeIntervalSince1970 * 1000))
        try applyIfDue(sync)
        updateStatus()
        pullListingNotices()
        // 复盘同步只跟着全量走：登录 / 恢复会话 / 手动 / 到点的回前台。
        if case .full = plan { review.synchronize(manual: manual) }
      } catch is CancellationError { if requestEpoch == profile.epoch && taskID == runID { updateStatus() } }
      catch {
        // 被服务端按版本顶回来了：本机这份不再可信，下一轮必须整份重拉。
        if SyncEngine.demandsBootstrap(error) { needsBootstrap = true }
        if requestEpoch == profile.epoch && taskID == runID { account.pending = Self.pendingCount(operations: sync.archive.operations.count, reviewUploads: review.pendingUploads); account.report(sync: error) }
      }
    }
  }
}
