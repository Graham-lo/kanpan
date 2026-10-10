import Foundation
import KanpanCore
import KanpanAccount

/// 记账：本机改动（设置 / 自选 / 画线 / 提醒）→ 同步存档里的待发操作。
///
/// 从 `AppAccountBridge` 原样搬出来（2026-10-10 拆分）。四个 store 的 `onChange` 由
/// `AppAccountBridge.init` 接到这里的 `captureSettings()` / `captureSymbols()` /
/// `captureDrawings()` / `captureAlerts()`；记上一笔之后由注入的 `onRecorded` 刷新状态、
/// 起 500ms 去抖推送（`SyncLifecycle`）。
///
/// 画线的增量基线（`DrawingSyncDiff`）也归这里：换档案时 `forgetDrawingBaseline()`，
/// 云端那批装进来时 `rebaseDrawingBaseline(from:to:)`。
@MainActor final class SyncRecorder {
  private let profile: ActiveProfile
  private let account: AccountFeature
  private let prefs: PrefsStore
  private let symbols: SymbolPickerModel
  private let drawings: DrawingController
  private let alerts: AlertStore

  /// 真的记上了一笔之后响：刷新账号页状态、起去抖推送。顺序同搬家之前（先刷状态再去抖）。
  var onRecorded: () -> Void = {}

  /// 画线增量记账的基线（上一次记完账的那份档案）。换档案、云端装进来时跟着挪或清空。
  private var drawingDiff = DrawingSyncDiff()

  init(profile: ActiveProfile, account: AccountFeature, prefs: PrefsStore, symbols: SymbolPickerModel,
       drawings: DrawingController, alerts: AlertStore) {
    self.profile = profile; self.account = account; self.prefs = prefs
    self.symbols = symbols; self.drawings = drawings; self.alerts = alerts
  }

  /// 新档案盘上的画线和存档之间可能差着没记上的一笔：第一次抬手整份对一遍。
  func forgetDrawingBaseline() { drawingDiff.forget() }
  /// 云端那批画线装进来：装之前的档案正是基线就挪到装之后那份上，否则清空（规则见 `DrawingSyncDiff`）。
  func rebaseDrawingBaseline(from old: DrawArchive, to new: DrawArchive) { drawingDiff.rebase(from: old, to: new) }

  private func capture(_ objects: [SyncObject], collections: Set<String>) {
    capture(SyncCaptureBatch(objects: objects, owns: { collections.contains($0.collection) }))
  }
  /// 记一批账；返回「真的记上了没有」——画线的增量基线只在记上之后才准往前挪。
  @discardableResult private func capture(_ batch: SyncCaptureBatch) -> Bool {
    guard !profile.gate.isApplying, profile.owner != nil, let sync = profile.sync else { return false }
    do {
      if let error = profile.personal?.error { account.syncStatus = error; return false }
      // 一次事务记完：自选每条都带 `order`，往头部插一个品种会让后面每一条都变，
      // 逐条 capture 等于整档重写 N 次。删除只在这一批覆盖到的范围里推（`SyncCaptureBatch.owns`）。
      // 删除拿「本机装进正式文件的那一版」比（`appliedLocal`），不拿 `local`：云端新带来、
      // 还没装进本机的对象不在正式文件里，拿 `local` 比会把它当成「用户删了」推一条删除。
      try sync.capture(batch.withDeletions(against: sync.archive.appliedLocal.values),
                       device: account.device.id, owning: PersonalSyncCodec.ownedKeys)
      // **落盘立刻发起，但不在主线程上等它写完。**
      //
      // `sync.capture` 里那一句 `ArchiveWriter.schedule` 就是「现在开始写」：字节已经
      // 交给写盘队列，队列是 `.userInitiated`，手一抬到落盘通常几毫秒。手势结束那一刻
      // 要的「立刻落盘」到这里就兑现了。
      //
      // 这儿原来还跟着一句 `sync.flushNow()`（`queue.sync {}`），理由写的是「app 这一刻
      // 被杀，下次冷启动 `applyPending()` 会拿存档里那份旧的把偏好盖回去」，代价估成
      // 「几百字节的小 JSON」。两头都不成立，去掉了：
      //
      // - **代价不是几百字节。** 每条画线的完整几何在存档的 `objects` 和 `local` 里
      //   各存一份，`settings:chart` 一项就有 10.6 KB × 2；实测一份只有四条线的真实
      //   存档是 46 KB，画线多起来就是几百 KB。等的是这一整份的 JSON 编码 + 原子写，
      //   而这条路每次抬手、每次改设置都要走一遍。
      // - **它防的那个窗口已经被别人关死了。** 其一，「app 被杀」这件事在本仓里有
      //   唯一入口 `AppLifecycle`：`AppAccountBridge.init` 里那个 `.sync` 档的钩子在离开前台 /
      //   进后台 / `willTerminate` 时调 `flushNow()`，而且**排在所有产数据的钩子后面**，
      //   用户划掉 app 走的正是这条路。其二，被举例的那个「偏好被盖回去」在设置这一档
      //   根本轮不到存档来兜：`PrefsStore.persist()` 是**同步**写 prefs.json + 脏标识，
      //   而且发生在 `onChange`（也就是这条 capture）**之前**；冷启动时 `prepare()`
      //   看见脏标识就会重新 `capture` 一条操作（`AccountProfileSwitcher.prepare` 里的脏标识对账），
      //   `applyPending()` 也按 `Prefs.keeping(dirtyFields:)` 护着脏字段不被云端覆盖。存档丢掉那一版，
      //   用户的值一个字都不少。
      //
      // 剩下的窗口写在这儿，别再让下一个人去猜：**没有任何通知的猝死**（jetsam / 崩溃）
      // 恰好落在这几毫秒里时，画线与自选那两档会丢掉「这一改还没推上去」的记账——
      // 盘上的 draws.json / symbols.json 仍然是新的，用户看得见自己的东西，
      // 但下一次拉取会拿云端那份旧的把它盖回去。这是**几毫秒**换掉每次抬手的卡顿。
      // 至于网络推送，仍旧留给 `onRecorded` 那 500ms 去抖（`SyncLifecycle.schedulePush`）：
      // 那是省流量，不是省命。
      onRecorded()
      return true
    } catch { account.report(sync: error); return false }
  }
  func captureSettings() {
    do {
      let object = try PersonalSyncCodec.settings(prefs.prefs)
      capture([object], collections: ["settings"])
      settleAgreedSettings(object)
    } catch { account.report(sync: error) }
  }
  /// 记完账再对一遍账：**脏着、却和存档一致、队列里也没它的**字段，清掉脏标识。
  ///
  /// `SyncStore.capture` 比出手上这份和存档 `local` 一样就不记操作，这本身没错——
  /// 没变化不该占队列。但 `PrefsStore` 的脏标识是在**改动那一刻**打的，它不知道
  /// 这一改在同步层看来是不是「没变化」（用户把周期从 4h 换到 1h 又换回 4h；
  /// 或者改动发生时正在应用云端那批，`gate` 把记账挡了，事后云端那份已经等于本地）。
  /// 于是脏标识永远等不到 `syncPushed` 来清它，这个字段就永远「本地更新、云端别碰」。
  ///
  /// 判「有东西可推」的三处：手上这份和存档 `local` 的差异、队列里对这个对象还没被
  /// 认下的操作、被服务端顶回来等着补推的那条。三处都不沾的脏字段才清。
  ///
  /// 第四处（审查 2026-10-10 第 3 项）：存档 `local` 和云端 `objects` 不一样的那几项。服务端还不认识的
  /// 字段被丢掉之后，`local` 叠回了用户的值（`SyncStore.keepingUnknown`，免得每记一次账就生出一条
  /// 新操作），可云端其实没有它——这时清脏标记，下一次全量拉回云端那份就把用户的值盖掉了。
  private func settleAgreedSettings(_ object: SyncObject) {
    guard !profile.gate.isApplying, profile.owner != nil, let sync = profile.sync, prefs.stamp.isDirty,
          let blocked = Self.unsettledSettingsFields(object, in: sync.archive) else { return }
    let agreed = prefs.dirtyFields.subtracting(blocked)
    guard !agreed.isEmpty else { return }
    prefs.syncAgreed(agreed)
  }
  /// `settleAgreedSettings` 那张「还有东西可推、脏标记不许清」的本地字段表。`nil` = 存档里还没有这个对象，一个都不清。
  static func unsettledSettingsFields(_ object: SyncObject, in archive: SyncArchive) -> Set<String>? {
    guard let baseline = archive.local[object.key], !baseline.deleted else { return nil }
    var blocked = Set<String>()
    for key in Set(object.body.keys).union(baseline.body.keys) where object.body[key] != baseline.body[key] {
      blocked.formUnion(SettingsWire.fields(for: key))
    }
    let cloud = archive.objects[object.key]
    for key in baseline.body.keys where cloud?.body[key] != baseline.body[key] {
      blocked.formUnion(SettingsWire.fields(for: key))
    }
    let queued = archive.operations.filter { $0.collection == object.collection && $0.objectId == object.id }.map(\.fields)
      + archive.rejected.filter { $0.intent.key == object.key }.map(\.operation.fields)
    for fields in queued { for key in fields.keys { blocked.formUnion(SettingsWire.fields(for: key)) } }
    return blocked
  }
  func captureSymbols() { capture(PersonalSyncCodec.symbols(symbols.prefs), collections: ["favorites", "groups"]) }
  /// 只编「和上次记完账那份不一样」的品种（`DrawingSyncDiff`）；记上了才把基线挪过来。
  func captureDrawings() {
    let archive = drawings.storedArchive
    do { if capture(try drawingDiff.batch(archive)) { drawingDiff.captured(archive) } } catch { account.report(sync: error) }
  }
  func captureAlerts() { do { capture(try PersonalSyncCodec.alerts(alerts.all), collections: ["alerts"]) } catch { account.report(sync: error) } }
}
