import Foundation
import Observation
import KanpanAccount
import KanpanCore

/// 收件箱独立于个人同步。账号目录切换时，缓存、待回执和在途响应一起隔离。
@MainActor @Observable final class ShareInbox {
  struct Cache: Codable {
    var items: [ShareItem] = []
    var friends: [ShareFriend] = []
    var cursor: String?
    var pending: [String: Bool] = [:]
    var copies: [String: [String]] = [:]
  }
  private(set) var items: [ShareItem] = []
  private(set) var friends: [ShareFriend] = []
  private(set) var busy = false
  private(set) var revision = 0
  @ObservationIgnored private var pullAgain = false
  var notice: String?
  var unseen: [ShareItem] { items.filter { $0.openedAt == nil } }
  @ObservationIgnored private var cache = Cache()
  @ObservationIgnored private var directory: URL?
  @ObservationIgnored private var owner: UUID?
  @ObservationIgnored private var client: ShareClient?
  @ObservationIgnored private var epoch = UUID()
  @ObservationIgnored private var task: Task<Void, Never>?
  @ObservationIgnored private var shots: [String: Data] = [:]

  static func read(directory: URL) throws -> Cache {
    let file = directory.appendingPathComponent("shares.json")
    guard FileManager.default.fileExists(atPath: file.path) else { return Cache() }
    return try JSONDecoder().decode(Cache.self, from: Data(contentsOf: file))
  }
  func activate(directory: URL, owner: UUID?, cache: Cache, api: AccountClient?) {
    task?.cancel(); task = nil; epoch = UUID(); busy = false; pullAgain = false; notice = nil
    self.directory = directory; self.owner = owner; self.cache = cache
    client = owner == nil ? nil : api.map { ShareClient(api: $0) }
    items = owner == nil ? [] : cache.items; friends = owner == nil ? [] : cache.friends
    shots = [:]
  }
  private func save() throws {
    guard let directory else { return }
    try JSONEncoder().encode(cache).write(to: directory.appendingPathComponent("shares.json"), options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
  }
  func pull() {
    guard let client else { return }
    if busy { pullAgain = true; return }
    let generation = epoch; busy = true
    task = Task { [weak self] in
      guard let self else { return }
      defer {
        if epoch == generation {
          busy = false; task = nil
          if pullAgain { pullAgain = false; pull() }
        }
      }
      do {
        try await flush(client: client, generation: generation)
        let page = try await client.inbox(after: cache.cursor)
        try Task.checkCancellation(); guard epoch == generation else { return }
        var merged = Dictionary(uniqueKeysWithValues: cache.items.map { ($0.id, $0) })
        for var item in page.items {
          if cache.pending[item.id] != nil {
            item.openedAt = item.openedAt ?? merged[item.id]?.openedAt
            item.keptAt = item.keptAt ?? merged[item.id]?.keptAt
          }
          merged[item.id] = item
        }
        // 服务端 90 天清理没有墓碑；本地遵守同一留存规则。
        let cutoff = Date().addingTimeInterval(-90 * 86400)
        cache.items = merged.values.filter { $0.keptAt != nil || ($0.createdDate ?? .distantFuture) >= cutoff }
          .sorted { $0.createdAt == $1.createdAt ? $0.id > $1.id : $0.createdAt > $1.createdAt }
        cache.cursor = page.cursor
        try save(); items = cache.items; revision += 1
        // 列表刷新完顺手扫一次截图缓存：过了留存期被滤掉的信，图也跟着删（审查 D4）。
        if let directory { Self.pruneShots(in: directory, keeping: Set(cache.items.map(\.id))) }
        let names = try await client.friends()
        try Task.checkCancellation(); guard epoch == generation else { return }
        cache.friends = names; try save(); friends = names; notice = nil
      } catch is CancellationError {} catch {
        if epoch == generation { notice = ShareClient.message(error) }
      }
    }
  }
  private func flush(client: ShareClient, generation: UUID) async throws {
    for (id, keep) in cache.pending {
      do { try await client.mark(id, kept: keep) }
      catch AccountError.http(404, _) {} // 未留下且已过留存期的信，无需继续回执。
      try Task.checkCancellation(); guard epoch == generation else { throw CancellationError() }
      // 发「已读」期间又点了「留下」，新回执不能被旧完成盖掉。
      if cache.pending[id] == keep { cache.pending[id] = nil; try save() }
    }
  }
  func opened(_ item: ShareItem) { mark(item, keep: false) }
  func kept(_ item: ShareItem) { mark(item, keep: true) }
  private func mark(_ item: ShareItem, keep: Bool) {
    guard let index = cache.items.firstIndex(where: { $0.id == item.id }) else { return }
    let stamp = ISO8601DateFormatter().string(from: Date())
    cache.items[index].openedAt = cache.items[index].openedAt ?? stamp
    if keep { cache.items[index].keptAt = cache.items[index].keptAt ?? stamp }
    cache.pending[item.id] = (cache.pending[item.id] ?? false) || keep
    do { try save(); items = cache.items; pull() }
    catch { notice = "收件箱未能保存，请重试" }
  }
  /// 先记新 id 再落画线；重试或进程中断都不会重复复制同一封信。
  func prepareKeep(_ item: ShareItem) throws -> [Drawing] {
    if cache.copies[item.id] == nil {
      cache.copies[item.id] = item.drawings.map { _ in Drawing.newID() }
    }
    // 上一次落盘失败也必须再写成功，之后才能把线交给 DrawingController。
    try save()
    return item.copies(ids: cache.copies[item.id])
  }
  /// 朋友页上「加朋友」。成功就记进本机那份名单；失败把错抛给输入框那一行去说。
  func addFriend(_ name: String) async throws {
    guard let client else { throw AccountError.unavailable }
    let generation = epoch
    try await client.add(name)
    guard generation == epoch else { throw CancellationError() }
    if !cache.friends.contains(where: { $0.username == name }) {
      cache.friends.append(ShareFriend(username: name))
      cache.friends.sort { $0.username < $1.username }
    }
    try save(); friends = cache.friends
  }
  func removeFriend(_ name: String) async {
    guard let client else { return }; let generation = epoch
    do {
      try await client.remove(name); guard generation == epoch else { return }
      cache.friends.removeAll { $0.username == name }; try save(); friends = cache.friends
    } catch { if generation == epoch { notice = ShareClient.message(error) } }
  }
  /// `share-shots/` 里只留还在收件箱里的那几封信的图，别的删掉。
  ///
  /// 图是 `shot(_:)` 按需拉下来落盘的，信过了 90 天留存期从列表里滤掉之后没人再删它，
  /// 一张一两百 KB 一直攒。只动「id.jpg」，别的文件不碰。
  @discardableResult static func pruneShots(in directory: URL, keeping ids: Set<String>) -> Int {
    let folder = directory.appendingPathComponent("share-shots")
    let names = (try? FileManager.default.contentsOfDirectory(atPath: folder.path)) ?? []
    var removed = 0
    for name in names where name.hasSuffix(".jpg") && !ids.contains(String(name.dropLast(4))) {
      if (try? FileManager.default.removeItem(at: folder.appendingPathComponent(name))) != nil { removed += 1 }
    }
    return removed
  }
  func shot(_ id: String) async -> Data? {
    if let image = shots[id] { return image }
    guard let client, let directory else { return nil }
    let generation = epoch
    let file = directory.appendingPathComponent("share-shots").appendingPathComponent(id + ".jpg")
    if let data = try? Data(contentsOf: file) { shots[id] = data; return data }
    guard let data = try? await client.shot(id), generation == epoch else { return nil }
    shots[id] = data
    try? FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
    try? data.write(to: file, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
    return data
  }
}
