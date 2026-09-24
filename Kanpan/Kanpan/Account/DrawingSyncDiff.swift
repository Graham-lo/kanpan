import Foundation
import KanpanCore
import KanpanAccount

/// 一次本机改动要交给同步存档记账的那一批对象，以及「这一批替哪些键说话」。
///
/// 记账（`SyncStore.capture`）之前要推出删除：本机档案里已经没有、存档 `local` 里还活着的键，
/// 就是这次删掉的。可「没有」只在**这一批覆盖到的范围里**才算数——范围之外的键这次压根没编码，
/// 不在 `objects` 里不代表被删了。`owns` 就是这个范围。
struct SyncCaptureBatch {
  var objects: [SyncObject]
  var owns: (SyncObject) -> Bool

  /// 加上推出来的删除之后，真正交给 `SyncStore.capture` 的那一批。
  func withDeletions(against local: some Sequence<SyncObject>) -> [SyncObject] {
    let keys = Set(objects.map(\.key))
    let deleted = local.filter { owns($0) && !$0.deleted && !keys.contains($0.key) }
    return objects + deleted.map { var value = $0; value.deleted = true; return value }
  }
}

/// 画线这一档的**按脏品种增量**记账（审查 22 的性能那一行）。
///
/// ## 为什么要增量
///
/// 从前每抬一次手，`captureDrawings` 就把**全部品种的全部画线**逐条编成同步对象
/// （`PersonalSyncCodec.drawings`：每条一次 JSON 编码 + 一次解码成 `JSONValue`），
/// 再逐条跟存档里的 `local` 比一遍。用户只动了 BTC 上的一条线，ETH、SOL……上那几百条
/// 也陪着编一遍、比一遍，结果全是「没变」。画线越多，抬手越贵。
///
/// ## 怎么增量
///
/// 记住**上一次成功记完账的那一份档案**（`baseline`），这一次只编「那一桶和上次不一样」的品种，
/// 删除也只在这几个品种里推；画线工具偏好只有自己变了才带上。桶是按品种分的（`DrawArchive.bySymbol`），
/// 一次手势只会动一个品种的桶，所以通常只编几条。比较用的是 `Array ==`：没动过的桶和上一份共享
/// 同一块存储，比一次就是比一个指针。
///
/// ## 什么时候退回全量
///
/// `baseline` 为空就整份编（和从前逐字一样）。它在这几处被清空或挪动，任何一处想不清楚就清空——
/// 清空的代价只是下一次抬手多编一遍，不会少记一笔账：
///
/// - **换档案（`prepare`）**：新档案盘上的画线和存档 `local` 之间可能差着「上次猝死时没记上的那一笔」
///   （见 `AppAccountBridge.capture` 那段注释），第一次抬手必须整份对一遍才能补上。
/// - **记账没成功**（没登录、档案出错、写存档抛错）：`baseline` 不动，还停在更早那份上；
///   下一次比出来的差只会更大，不会漏掉这次没记上的品种。
/// - **云端那批装进来（`applyPending`）**：装之前的档案如果正是 `baseline`，就挪到装之后那份上——
///   装进来的每一桶本来就是从 `local` 里叠出来的，它和存档没有差；否则清空。
struct DrawingSyncDiff {
  private(set) var baseline: DrawArchive?

  /// 这一次要记账的那一批。
  func batch(_ archive: DrawArchive) throws -> SyncCaptureBatch {
    guard let baseline else {
      return SyncCaptureBatch(objects: try PersonalSyncCodec.drawings(archive),
                              owns: { $0.collection == "drawings" || $0.collection == "drawingPreferences" })
    }
    var symbols = Set<String>()
    for key in Set(archive.bySymbol.keys).union(baseline.bySymbol.keys) where archive.bySymbol[key] != baseline.bySymbol[key] {
      symbols.insert(InstrumentID.canonical(key))
    }
    let preferences = archive.preferences != baseline.preferences
    if symbols.isEmpty && !preferences { return SyncCaptureBatch(objects: [], owns: { _ in false }) }
    var dirty = DrawArchive(version: archive.version)
    dirty.preferences = archive.preferences
    dirty.bySymbol = archive.bySymbol.filter { symbols.contains(InstrumentID.canonical($0.key)) }
    let objects = try PersonalSyncCodec.drawings(dirty).filter { preferences || $0.collection != "drawingPreferences" }
    return SyncCaptureBatch(objects: objects, owns: { object in
      switch object.collection {
      case "drawings": symbols.contains(PersonalSyncCodec.instrument(object))
      case "drawingPreferences": preferences
      default: false
      }
    })
  }
  /// 这一份已经记完账了。
  mutating func captured(_ archive: DrawArchive) { baseline = archive }
  /// 下一次整份对一遍。
  mutating func forget() { baseline = nil }
  /// 档案不经记账被换了一份（云端装进来）：从 `old` 换成 `new`。
  mutating func rebase(from old: DrawArchive, to new: DrawArchive) {
    guard old != new else { return }
    baseline = baseline == old ? new : nil
  }
}
