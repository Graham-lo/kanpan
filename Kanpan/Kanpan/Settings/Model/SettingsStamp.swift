import Foundation
import KanpanCore

// MARK: - 一份体验类缓存的最小状态

/// 「值 + 属主 + 脏字段集 + 修改时间」里除了值以外的那三样。
///
/// 2026-09-19 用户定的机制级规矩，原话：
///
/// > 体验类当然是**本地优先**，然后云端自动记录，下一次使用**假如本地缓存的记录被破坏
/// > 或者不完整才同步**，但这里一定要注意**标识状态**……避免**云端没同步，下次进来
/// > 对不上又覆盖回去，相当于没改**。
///
/// 三样各自回答一个问题，缺一不可：
///
/// - `owner`：**这份缓存是不是这个账号的。** 不是就当它不存在（防「B 登进来看到 A 的东西」）。
/// - `dirty`：**哪几个字段还没推上去。** 键是字段名，值是那一下改动的时刻。
///   **粒度按字段，不按整份档案**——两台设备一台改皮肤一台改缩放，两边都在
///   `settings:chart` 这**一个**同步对象里；按对象打标识必然丢掉一边。
/// - `updatedAt` / `pushedAt`：**两份都干净但不一样时谁新**，以及「本地改过却没推成功」。
///
/// 落盘规矩（这一条是硬的）：**落本地 + 记脏 + 记时间是同一步、同步完成**，
/// 推云端才是异步的，而且**推成功才清对应的脏字段**。推失败、断网、app 被杀，
/// 脏标识都留着，下次启动照样本地赢。
///
/// ## 别造第二套标识
///
/// 同步层（`KanpanAccount.SyncStore`）已经有一整套业界标配，这一份**不重复、不平行**：
///
/// | 业界（CloudKit / Firestore / offline-first） | 看盘已有的 | 这一份补的 |
/// | --- | --- | --- |
/// | change tag / ETag | `SyncObject.revision` | —— |
/// | expectedRev（检冲突） | `SyncOperation.baseRevision` | —— |
/// | tombstone | `SyncObject.deleted` | —— |
/// | Lamport 逻辑时钟 | `SyncOperation.logical` + `deviceId` | —— |
/// | change token（增量拉） | `SyncArchive.cursor` / `offset` | —— |
/// | outbox（待发队列） | `archive.operations` + `sent`，已经是按字段发 patch | **本机这一侧的影子** |
///
/// 真正缺的从来不是「同步没有标识」，而是**体验类偏好没有走这套标识**：整份 `Prefs`
/// 被压成 `settings:chart` 一个对象，`revision` 是对象级的，字段级冲突在它眼里不存在。
/// 所以这一份只活在本机，是 outbox 的本地影子：**不新增服务端字段、不改协议**，
/// 线上那一侧继续用 `revision` / `baseRevision`。
///
/// 还有一条通行结论写在这儿并且被用例钉着：**不要只靠墙上时钟的 last-write-wins**。
/// 合并规则是显式的、按字段的——本地脏的一律跳过，干净的跟着云端走
/// （见 `PrefsStore.applySynced` 与 `AppAccountBridge.applyPending`）。
struct SettingsStamp: Codable, Equatable, Sendable {
  /// 和 `Prefs` 分开存：`Prefs` 是要随账号同步的那一份，这一份**只属于这台机器**，
  /// 而且它一直在变（每改一次就换一个时间戳），塞进 `Prefs` 会让
  /// `PrefsStore.update` 那句「没真改动就不落盘」永远判为「改了」。
  static let storageKey = "kanpan.settings.stamp.v1"

  /// 属主：账号 id，或访客档案的那个 id。空串表示「还没认过主」。
  var owner: String = ""
  /// 字段名 → 那一下改动的时刻（毫秒）。推成功之后按「时刻没变」逐个清。
  var dirty: [String: Double] = [:]
  /// 最近一次本地改动的时刻。
  var updatedAt: Double = 0
  /// 最近一次推云成功的时刻。
  var pushedAt: Double = 0

  var isDirty: Bool { !dirty.isEmpty }
  var dirtyFields: Set<String> { Set(dirty.keys) }

  /// 记脏。和落盘同一步调用。
  mutating func mark(_ fields: Set<String>, at now: Double) {
    guard !fields.isEmpty else { return }
    for field in fields { dirty[field] = now }
    updatedAt = max(updatedAt, now)
  }

  /// 推成功了，把这一批清掉。
  ///
  /// **只清「时刻没变的」那些**：推的过程中用户又改了同一个字段的话，`dirty` 里那个
  /// 时刻已经换成新的了，清掉就等于把这一次新改动当成推过了——下次云端回拉照样盖回去。
  mutating func clear(_ pushed: [String: Double], at now: Double) {
    for (field, when) in pushed where dirty[field] == when { dirty.removeValue(forKey: field) }
    pushedAt = max(pushedAt, now)
  }

  /// 交给对账用的**线上键名**。`rsiLower` / `rsiUpper` 在这里并成 `rsiRange` 一个键。
  var dirtyWireKeys: Set<String> { Set(dirty.keys.map(SettingsWire.key(for:))) }

  /// 服务端认掉（ACK）了哪几个线上键，就清哪几个本地字段。
  ///
  /// **「发出去了」不算数**——`SyncStore` 那边 `markSent` 只是把操作记成已发，
  /// 真正的成功是 `SyncPushResponse` 里按 `operationId` 对上的那几条
  /// （`SyncStore.acknowledge`）。断网重发、服务端拒绝、app 半路被杀，
  /// 脏标识都必须原样留着。
  ///
  /// ## 一个本地字段，线上好几条路径
  ///
  /// 脏标识按**顶层字段名**记（`params`），发上去的却是 `PersonalSyncCodec.flatten`
  /// 拍平后的一串路径（`params/MA`、`params/EMA`、`params/VOL`…，见 `SettingsWire`）。
  /// 服务端是**按项**收的：同一条操作里，它可能认下 `params/MA` 却把 `params/EMA`
  /// 放进 `droppedFields` 顶回来。
  ///
  /// 所以清的判据是「**这个字段这一轮报上来的路径里，一条都没被丢**」：只要有一条
  /// 落在 `dropped` 里，那个顶层脏标识就必须留着。少了这一道，清掉的等于把没推上去的
  /// 那一改当成推过了——下次云端回拉照样把它盖回去，就是用户说的「相当于没改」。
  ///
  /// 既没被认下、也没被丢（整条操作没回执、被隔离、还躺在队列里）的路径，
  /// 由调用方一并塞进 `dropped`：在这儿它和「被丢掉」是同一件事——没落地。
  ///
  /// - Parameters:
  ///   - keys: 被 ACK 的那些操作里**真收下了**的线上字段名 / 路径。
  ///   - dropped: 同一批里**没收下**的线上字段名 / 路径（`droppedFields` + 没回执的）。
  ///   - pushed: 推上去那一刻的脏字段快照（本地字段名 → 时刻）。
  mutating func clear(acked keys: Set<String>, dropped: Set<String> = [],
                      from pushed: [String: Double], at now: Double) {
    // 有一条路径没落地，这个顶层字段这一轮就整个不清。
    var blocked: Set<String> = []
    for key in dropped { blocked.formUnion(SettingsWire.fields(for: key)) }
    var batch: [String: Double] = [:]
    for key in keys {
      for field in SettingsWire.fields(for: key) where !blocked.contains(field) {
        if let when = pushed[field] { batch[field] = when }
      }
    }
    guard !batch.isEmpty else { return }
    clear(batch, at: now)
  }

  /// 换了个人：脏标识跟着上一个人走，一个字都不留。
  ///
  /// 注意反过来那半条同样是硬要求：**同一个人的档案晚到不许作废**
  /// （见 `ChartViewport.adopt(barSpacing:reason:)`），因为脏标识恰恰说明
  /// 「用户刚改的，还没推上去」。
  static func fresh(owner: String) -> SettingsStamp { SettingsStamp(owner: owner) }
}

// MARK: - 哨兵：本地这份为什么读不到

/// 放在**比真身更顽固的那一层**（`UserDefaults`，Library/Preferences），
/// 专门回答「本地档案读不到，是第一次装、是换了人、是坏了、还是被清了」。
///
/// 2026-09-19 用户原话：「用来判断是清空了缓存还是什么情况，一般来说这种缓存清空
/// 不应该出现在可清空范围内。」
///
/// **哨兵和真身不能在同一层**——同一层就会一起消失，「首次」和「被清空」就分辨不出来了。
/// 真身在 `Application Support/kanpan/accounts/…/prefs.json`（见 `AccountFiles`），
/// 哨兵在 `UserDefaults.standard`；行情缓存在 `Library/Caches`，那一层被系统清掉是正常的，
/// 体验类一个字节都不许放在那儿。
struct SettingsSentinel: Codable, Equatable, Sendable {
  static let storageKey = "kanpan.settings.sentinel.v1"

  /// 装机 id：这台机器上这次安装的批次。整份哨兵没了才会换一个。
  var install: String = ""
  /// 最后一次成功写盘的属主。
  var owner: String = ""
  /// 最后一次成功写盘的时刻。
  var wroteAt: Double = 0
  /// 最后一次成功推上云端的时刻。
  var pushedAt: Double = 0

  /// 本地曾经有过没推上去的改动。`wiped` 那一路靠它区分「丢的是白纸还是用户的改动」。
  var hadUnpushedWork: Bool { wroteAt > pushedAt }
}

/// 启动时那份本地档案的体检结论。四种，处理各不相同，**不许混成一条路**。
enum SettingsCacheVerdict: Equatable, Sendable {
  /// 档案在、属主对：本地优先，云端只做「按字段合并」。
  case intact
  /// 首次：哨兵也没有。正常从云端拉。
  case firstRun
  /// 属主不符：档案在，但里面记的不是当前这个人。当它不存在，**绝不能用**。
  case ownerMismatch(expected: String, found: String)
  /// 损坏 / 不完整：解不开或缺字段。回落云端，但**不许顺手清掉脏标记**，
  /// 否则会把还没推上去的改动一起抹掉。
  case damaged
  /// 被清空：档案没了，哨兵还在。`unpushed` 为真时，本地曾有过没推上去的改动——
  /// 这时候直接拉云端就是用户最痛的那个现象「我明明改了，等于没改」。
  case wiped(unpushed: Bool)

  /// 这一路还能不能把本地那份当权威。
  var trustsLocal: Bool { self == .intact }
}

enum SettingsCacheDoctor {
  /// - Parameters:
  ///   - archive: 本地档案的字节。nil = 没有这份文件。
  ///   - readable: 这份字节解得开、字段齐不齐（由 `PrefsCodec` 那一层判）。
  ///   - stamp: 档案旁边那份状态（属主 / 脏字段 / 时间）。nil = 没有。
  ///   - sentinel: 另一层里的哨兵。nil = 没有。
  ///   - owner: 现在该是谁的。
  static func diagnose(archive: Data?, readable: Bool, stamp: SettingsStamp?,
                       sentinel: SettingsSentinel?, owner: String) -> SettingsCacheVerdict {
    guard let archive, !archive.isEmpty else {
      // 档案没了。哨兵在不在决定了这是「第一次」还是「被清了」。
      guard let sentinel, !sentinel.install.isEmpty else { return .firstRun }
      // 哨兵记的是上一个人、这次换了个人登进来：对这个人来说这确实是第一次。
      guard sentinel.owner.isEmpty || sentinel.owner == owner else { return .firstRun }
      return .wiped(unpushed: sentinel.hadUnpushedWork)
    }
    if let stamp, !stamp.owner.isEmpty, stamp.owner != owner {
      return .ownerMismatch(expected: owner, found: stamp.owner)
    }
    return readable ? .intact : .damaged
  }
}

// MARK: - 本地字段名 ↔ 线上键名

/// 脏标识认的是**本地字段名**（也就是 `Prefs.syncedFieldNames` 那张白名单里的键，
/// flatten 之前的那一层），而推上去的操作认的是**线上键名**。两边有两处对不齐：
///
/// 1. `rsiLower` / `rsiUpper` 在 `PersonalSyncCodec.settings` 里被合成 `rsiRange`
///    一个数组键发出去，`apply` 再把它拆回两个。所以任一变脏，线上认的都是 `rsiRange`；
///    反过来 ACK 回来一个 `rsiRange`，要清的是**两个**本地字段。
/// 2. **嵌套字段被 `PersonalSyncCodec.flatten` 拍成了带斜杠的路径。** 本地一个
///    `params` 字段，上线之后是 `params/MA`、`params/EMA`、`params/VOL`… 一串；
///    `indicatorColors` 更深一层，是 `indicatorColors/MACD/0`。
///    `subHeightOverrides`、`hiddenOutputs` 同理。服务端 ACK 回来的、
///    `droppedFields` 里报回来的，全是这些**路径**，不是顶层字段名。
///
/// 第 2 条曾经漏掉过，代价是**所有嵌套字段的脏标识永远清不掉**（2026-09-19 实测：
/// 某个账号的 `settings-stamp.json` 里 `dirty` 一直挂着 `subHeightOverrides`，
/// 而云端那份 `body` 明明已经收下了 `subHeightOverrides/MACD`）。后果有两层：
/// 一是 `PrefsStore.applySynced` 里 `Prefs.keeping(dirtyFields, …)` 会让云端的
/// `params` / `indicatorColors` / `subHeightOverrides` / `hiddenOutputs`（当时还有 `subHeights`）
/// **永远打不赢本地**——换台设备改的指标参数、指标颜色、副图高度，另一台再也收不到，
/// 这几类设置事实上变成单向同步；二是 `AppAccountBridge.applyPending` 里
/// `if prefs.stamp.isDirty { captureSettings() }` 永远为真，每轮同步都白推一整份 settings。
///
/// 所以这一处显式写在这儿、并且有用例钉着，免得它再一次默默对不上——对不上的后果
/// 要么是脏标识永远清不掉（一直以为没推成功），要么是清错了（把没推上去的改动当成
/// 推过了，下次回拉照样盖回去）。
enum SettingsWire {
  static let rsiRange = "rsiRange"
  static let rsiFields: Set<String> = ["rsiLower", "rsiUpper"]

  /// 本地字段名 → 线上键名。
  ///
  /// 这一头不用管拍平：脏标识本来就只记顶层字段名，`params` 映出去还是 `params`。
  static func key(for field: String) -> String { rsiFields.contains(field) ? rsiRange : field }

  /// 线上键名（含拍平后的路径）→ 本地字段名。
  ///
  /// `rsiRange` 映回上下轨两个；带斜杠的路径取**第一段**（`params/MA` → `params`，
  /// `indicatorColors/MACD/0` → `indicatorColors`），因为拍平只在顶层字段的值里往下拆，
  /// 顶层字段名自己不含斜杠（见 `PersonalSyncCodec.flatten` / `expand`）。
  static func fields(for key: String) -> Set<String> {
    if key == rsiRange { return rsiFields }
    guard let slash = key.firstIndex(of: "/") else { return [key] }
    return [String(key[key.startIndex..<slash])]
  }
}

// MARK: - 按字段比对

extension Prefs {
  /// 随账号同步的那些字段名。**和 `PrefsCodec` 的编码键名逐字相同**，所以拿它去
  /// JSON 上按键比对是成立的。
  ///
  /// 这张表以前长在 `PersonalSyncCodec.fields`（app 靶子里），而脏标识要做在
  /// `PrefsStore` 这一层（包里，M1 抽 `PersonalStore` 时要整块搬走），包看不见 app 靶子。
  /// 所以真身搬到这儿，`PersonalSyncCodec.fields` 改成引用它——**一份清单，两处用**。
  ///
  /// 2026-09-19 再往前一步：字面量那一份也撤了，改成从 `PrefsFieldPlan.table` 派生。
  /// 那张表是**唯一**一处说「哪个字段跟着人走 / 留在本机」的地方，穷举守卫
  /// （`PrefsFieldPlanTests`）钉着它必须盖住 `Prefs` 的每一个存储字段。
  static let syncedFieldNames: Set<String> = PrefsFieldPlan.names(.synced)

  /// 换档案时**留在本机**、不被新档案覆盖的那些字段（`PersonalSyncCodec.keepDeviceFields`）。
  static let deviceOnlyFieldNames: Set<String> = PrefsFieldPlan.names(.deviceOnly)

  /// 打脏标识时认的字段。
  ///
  /// 就是上面那张白名单，外加 RSI 的上下轨：它俩在同步对象里被合成 `rsiRange`
  /// 一个键发出去（见 `SettingsWire`），键名和本地字段名对不上，但它们照样是
  /// 「用户改过的体验类设置」，一样要能挡住云端回拉——也就是 `.syncedMerged` 那一档。
  static let stampedFieldNames: Set<String> = PrefsFieldPlan.names([.synced, .syncedMerged])

  /// 两份档案之间，**哪些体验类字段真的变了**。
  ///
  /// 走 JSON 比而不是逐字段写 `if`：字段有四十多个，逐个写必漏，而且下一个加字段的人
  /// 不会想起来回这儿补一行。`PrefsCodec` 的编码键名就是字段名，JSON 对象比一次就够。
  static func changedStampedFields(from old: Prefs, to new: Prefs) -> Set<String> {
    guard old != new else { return [] }
    let a = fieldMap(old), b = fieldMap(new)
    var changed: Set<String> = []
    for name in stampedFieldNames {
      let x = a[name] as? NSObject, y = b[name] as? NSObject
      if x != y { changed.insert(name) }
    }
    return changed
  }

  /// 把 `fields` 这几个字段从 `local` 抄回 `incoming` 那一份上。
  ///
  /// 「云端回拉的字段，凡是本地脏的**一律跳过**」就是这么实现的：先拿云端那份整体当底，
  /// 再把本地脏的那几个字段原样盖回去。
  static func keeping(_ fields: Set<String>, of local: Prefs, over incoming: Prefs) -> Prefs {
    guard !fields.isEmpty else { return incoming }
    var target = fieldMap(incoming)
    let source = fieldMap(local)
    guard !target.isEmpty, !source.isEmpty else { return incoming }
    for name in fields { target[name] = source[name] }
    guard let data = try? JSONSerialization.data(withJSONObject: target) else { return incoming }
    return PrefsCodec.decode(data)
  }

  private static func fieldMap(_ prefs: Prefs) -> [String: Any] {
    (try? JSONSerialization.jsonObject(with: PrefsCodec.encode(prefs))) as? [String: Any] ?? [:]
  }
}

/// 毫秒墙上钟。单测里把它换掉，免得靠 `sleep` 制造时间差。
///
/// 读它的只有 `@MainActor` 的 `PrefsStore`，换它的只有 `@MainActor` 的单测，
/// 所以直接钉在主 actor 上，让编译器替我们查，而不是 `nonisolated(unsafe)` 口头担保。
@MainActor
enum SettingsClock {
  static var now: () -> Double = { Date().timeIntervalSince1970 * 1000 }
}
