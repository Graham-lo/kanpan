import Foundation
import KanpanCore
import KanpanAccount

/// 把同步存档里的对象叠到本机正式档案上——**只此一处**。
///
/// ## 谁赢不在这儿判
///
/// 本地与云端谁说了算只有一条规则，住在 `SyncArchive.holdsLocal`（有待发操作或未了结的
/// 拒绝记录 → 本机的值说了算）。`SyncStore` 按它把赢家写进 `local`（`receive` /
/// `acknowledge`），启动时再按它挑出「盘上还没跟上的那几份」（`startupCorrections`）。
/// 这里只回答另一个问题：**一个同步对象落到本地模型上长什么样**。
///
/// 2026-09-24 以前（深度审查第 22 项「冲突解决散在六处」）这件事写了六遍：`prepare` 里
/// 画线墓碑、提醒墓碑、提醒 / 画线 / 自选三段前向对账，`applyPending` 里又把设置、画线、
/// 提醒、自选各合并一遍。同一种对象两处落法并不一样——画线工具偏好在 `prepare` 里解不开
/// 就跳过，在 `applyPending` 里却整批抛，于是一份坏的工具偏好能让这台设备从此什么都装不进来。
/// 现在两边都调这一份。
enum SyncOverlay {
  /// 对象 id 的最后一段就是本地的那个 id（画线 / 提醒的对象 id 是 `venue/market/symbol/<id>`）。
  static func localID(_ object: SyncObject) -> String { String(object.id.split(separator: "/").last ?? "") }

  /// 设置：按字段合并，本地脏的一律跳过，干净的跟着云端走。没有这个对象时返回 `nil`。
  static func settings(_ object: SyncObject?, onto local: Prefs, keeping dirty: Set<String>) throws -> Prefs? {
    guard let object, !object.deleted else { return nil }
    return Prefs.keeping(dirty, of: local, over: try PersonalSyncCodec.apply(object, to: local))
  }

  /// 画线与画线工具偏好。删 → 移除；活 → 就地替换或追加。
  ///
  /// **解不开的那条跳过，别整批抛。** 新版本加一把画线工具，老版本的机器就会读到一个它不认识的
  /// `kind`；整批抛出去的话 `pendingApply` 一直挂着，每次重试都在同一条上翻车，这台设备从此
  /// 再也收不到任何设置、自选、画线。跳过的那条：它要是本机说了算的，待发操作还在队列里；
  /// 要是云端的，下一次应用还会再来。
  static func drawings(_ objects: some Sequence<SyncObject>, onto archive: inout DrawArchive) {
    for object in objects {
      if object.collection == "drawingPreferences" {
        guard !object.deleted,
              let value = try? KanpanAccount.JSONValue.object(PersonalSyncCodec.expand(object.body)).decode(DrawingPreferences.self)
        else { continue }
        archive.preferences = value
        continue
      }
      guard object.collection == "drawings" else { continue }
      let name = PersonalSyncCodec.instrument(object); guard !name.isEmpty else { continue }
      let id = localID(object)
      if object.deleted { archive[name].removeAll { $0.id == id }; continue }
      guard let drawing = try? PersonalSyncCodec.drawing(object) else { continue }
      if let index = archive[name].firstIndex(where: { $0.id == id }) { archive[name][index] = drawing }
      else { archive[name].append(drawing) }
    }
  }

  /// 提醒。服务端判出触发之后会自己写一条 `patch`（`status` / `firedAt` / `firedPrice`），
  /// 就是从这儿落进本机的——所以它既管「别的设备加的提醒」，也管「它响了」。
  /// 解不开的那条跳过，理由同画线。
  static func alerts(_ objects: some Sequence<SyncObject>, onto archive: inout AlertArchive) {
    for object in objects where object.collection == "alerts" {
      let id = localID(object)
      if object.deleted { archive.alerts.removeAll { $0.id == id }; continue }
      guard let alert = try? PersonalSyncCodec.alert(object) else { continue }
      archive[id] = alert
    }
  }

  /// 自选 / 分组：**整张重建**。云端那几张表（`favorites` / `groups`，一条自选一个对象）
  /// 能把同步的那一半整份还原；「最近」「常看」一直是本机的事，按 `SymbolFieldPlan` 的
  /// localOnly 表原样抄回去——清单只有那一张表，加字段的人不必记得回这儿补参数。
  ///
  /// `objects` 要给**这两张表的全部对象**（`SyncArchive.local` 里的那一整份）：给一部分就是
  /// 把没给的那几条删掉。
  static func symbols(rebuiltFrom objects: some Sequence<SyncObject>, keeping local: SymbolPrefs) -> SymbolPrefs {
    let live = objects.filter { !$0.deleted }
    let groups = live.filter { $0.collection == "groups" }.sorted(by: order).compactMap { v -> FavoriteGroup? in
      guard case .string(let name) = v.body["name"] else { return nil }; return FavoriteGroup(id: v.id, name: name)
    }
    var names: [String] = [], membership: [String: String] = [:]
    for value in live.filter({ $0.collection == "favorites" }).sorted(by: order) {
      let name = PersonalSyncCodec.instrument(value); guard !name.isEmpty else { continue }; names.append(name)
      if case .string(let group) = value.body["groupId"] { membership[name] = group }
    }
    let rebuilt = SymbolPrefs(favorites: names, groups: groups, groupForSymbol: membership)
    return SymbolPrefs.keeping(SymbolPrefs.localOnlyFieldNames, of: local, over: rebuilt)
  }

  /// 这一整份分组对象里，哪些是同名的多余那个：「被并掉的 id → 留下的 id」。
  ///
  /// 整张重建（上面那个）已经按名字并好了；这里是给 `applyPending` 看的——不空就说明
  /// 云端还躺着多余的分组对象，要再记一次账，把它们推删除、把挂在上面的自选改挂过去。
  static func mergedGroups(in objects: some Sequence<SyncObject>) -> [String: String] {
    let groups = objects.filter { $0.collection == "groups" && !$0.deleted }.sorted(by: order).compactMap { v -> FavoriteGroup? in
      guard case .string(let name) = v.body["name"], !v.id.isEmpty, !name.isEmpty else { return nil }
      return FavoriteGroup(id: v.id, name: name)
    }
    return SymbolPrefs.mergeSameNamed(groups).merged
  }

  /// 按对象里记的 `order` 排，同序按 id。
  private static func order(_ a: SyncObject, _ b: SyncObject) -> Bool {
    let x: Double = { if case .number(let n) = a.body["order"] { return n }; return 0 }()
    let y: Double = { if case .number(let n) = b.body["order"] { return n }; return 0 }()
    return x == y ? a.id < b.id : x < y
  }

  /// 自选 / 分组：**逐条补**（启动前向对账用）。只动给了的那几条，位置按对象里记的 `order`
  /// 插回去，插不进就落到末尾——真身顺序仍以那条待发操作为准，下一次整张重建会把它摆正。
  static func symbols(_ objects: some Sequence<SyncObject>, patching prefs: inout SymbolPrefs) {
    for object in objects {
      var slot = Int.max
      if case .number(let order) = object.body["order"] { slot = Int(order) }
      if object.collection == "groups" {
        prefs.groups.removeAll { $0.id == object.id }
        guard !object.deleted, case .string(let name) = object.body["name"] else { continue }
        prefs.groups.insert(FavoriteGroup(id: object.id, name: name), at: min(max(slot, 0), prefs.groups.count))
        continue
      }
      guard object.collection == "favorites" else { continue }
      let symbol = PersonalSyncCodec.instrument(object); guard !symbol.isEmpty else { continue }
      prefs.favorites.removeAll { $0 == symbol }
      prefs.groupForSymbol[symbol] = nil
      guard !object.deleted else { continue }
      prefs.favorites.insert(symbol, at: min(max(slot, 0), prefs.favorites.count))
      if case .string(let group) = object.body["groupId"] { prefs.groupForSymbol[symbol] = group }
    }
    // 补回来的分组可能和手上的同名（另一台设备推上来的「加密」）：同样并成一格。
    prefs.mergeSameNamedGroups()
  }
}
