import Foundation
import ImageIO
import Observation
import os
import UIKit
import KanpanAccount
import KanpanCore

/// 收件箱要走的那几趟网络。线上就是 `ShareClient`；用例换成计数的假服务（压测 H2）。
protocol ShareInboxService: Sendable {
  func inbox(after: String?) async throws -> ShareClient.Page
  func friends() async throws -> [ShareFriend]
  func mark(_ id: String, kept: Bool) async throws
  func shot(_ id: String) async throws -> Data
  func add(_ username: String) async throws
  func remove(_ username: String) async throws
}
extension ShareClient: ShareInboxService {}

/// 收件箱独立于个人同步。账号目录切换时，缓存、待回执和在途响应一起隔离。
@MainActor @Observable final class ShareInbox {
  struct Cache: Codable, Sendable {
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
  @ObservationIgnored private var client: (any ShareInboxService)?
  @ObservationIgnored private var epoch = UUID()
  @ObservationIgnored private var task: Task<Void, Never>?
  /// 解好、已经缩到屏上尺寸的缩略图，最多 `thumbMemoryLimit` 张，按最近用过的顺序淘汰。
  ///
  /// 以前内存里留的是 JPEG 原字节、只留 6 张，每次 body 都在主线程 `UIImage(data:)` 整张解码；
  /// 朋友页一屏就十来行，来回一滚全落到读盘 + 解码上（压测 H2）。缩到 `thumbnailPixels`
  /// 之后一张不到 100 KB，64 张几 MB。
  @ObservationIgnored private var thumbs: [String: UIImage] = [:]
  @ObservationIgnored private var thumbOrder: [String] = []
  /// 正在后台读盘 / 下载的那几张。同一张图卡片和行同时要，只跑一趟。
  @ObservationIgnored private var loading: [String: Task<ThumbLoad, Never>] = [:]
  /// 已经排了一次「盘上截图总量回到预算以内」的目录。一批下载只扫一次目录。
  @ObservationIgnored private var trimPending: Set<URL> = []
  /// 排过几次总量裁剪。给用例数：一批下载不该每张都扫一遍目录。
  @ObservationIgnored private(set) var trimsScheduled = 0
  static let thumbMemoryLimit = 64
  /// 缩略图短边的像素数。屏上最大那一格是 44×36 pt，三倍屏 132 px，留一点余量。
  nonisolated static let thumbnailPixels = 160
  /// 下载完一张之后等多久再裁剪总量，这段时间里接着下载的不再各排一次。
  static let trimDelay: Duration = .seconds(2)
  /// `share-shots/` 的总量上限。一张一两百 KB，32 MB 约两百张；删掉的哪天再打开那封信
  /// 会从服务端再拉一次（服务端不删分享）。
  nonisolated static let shotDiskBudget = 32 * 1024 * 1024

  /// `shares.json` 的落盘队列。整个进程一条，所有账号目录共用（按文件分开合批）。
  nonisolated static let writer = ShareCacheWriter()

  nonisolated static func read(directory: URL) throws -> Cache {
    // 后台还排着没写出去的那一份要先落地，不然刚切走又切回来的账号会读到旧的。
    writer.drain()
    let file = directory.appendingPathComponent("shares.json")
    guard FileManager.default.fileExists(atPath: file.path) else { return Cache() }
    return try JSONDecoder().decode(Cache.self, from: Data(contentsOf: file))
  }
  func activate(directory: URL, owner: UUID?, cache: Cache, api: AccountClient?) {
    activate(directory: directory, owner: owner, cache: cache,
             service: owner == nil ? nil : api.map { ShareClient(api: $0, owner: owner) })
  }
  /// 同上，网络那一层直接递进来（用例用假的）。
  func activate(directory: URL, owner: UUID?, cache: Cache, service: (any ShareInboxService)?) {
    task?.cancel(); task = nil; epoch = UUID(); busy = false; pullAgain = false; notice = nil
    self.directory = directory; self.owner = owner; self.cache = cache
    client = owner == nil ? nil : service
    items = owner == nil ? [] : cache.items; friends = owner == nil ? [] : cache.friends
    for job in loading.values { job.cancel() }
    loading = [:]; thumbs = [:]; thumbOrder = []
  }
  private var cacheFile: URL? { directory?.appendingPathComponent("shares.json") }
  /// 马上写、写不成就抛。「留下」要先确认新 id 落了盘才能把线交出去，走这条。
  private func save() throws {
    guard let cacheFile else { return }
    try Self.writer.writeNow(cache, to: cacheFile)
  }
  /// 交给后台写：整份 JSON 编码不压在主线程上，一连串改动只写最后那一份（压测 H2）。
  /// 写不成在这一页上说一句，和原来同步写失败时一样。
  private func persist() {
    guard let cacheFile else { return }
    let generation = epoch
    Self.writer.schedule(cache, to: cacheFile) { [weak self] in
      Task { @MainActor [weak self] in
        guard let self, epoch == generation else { return }
        notice = "收件箱未能保存，请重试"
      }
    }
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
        persist(); items = cache.items; revision += 1
        // 列表刷新完顺手扫一次截图缓存：过了留存期被滤掉的信，图也跟着删（审查 D4）。
        // 列目录、删文件都在后台做，不占主线程。
        if let directory {
          let keeping = Set(cache.items.map(\.id))
          Task.detached(priority: .utility) { Self.pruneShots(in: directory, keeping: keeping) }
        }
        let names = try await client.friends()
        try Task.checkCancellation(); guard epoch == generation else { return }
        cache.friends = names; persist(); friends = names; notice = nil
      } catch is CancellationError {} catch {
        if epoch == generation { notice = ShareClient.message(error) }
      }
    }
  }
  private func flush(client: any ShareInboxService, generation: UUID) async throws {
    for (id, keep) in cache.pending {
      do { try await client.mark(id, kept: keep) }
      catch AccountError.http(404, _) {} // 未留下且已过留存期的信，无需继续回执。
      try Task.checkCancellation(); guard epoch == generation else { throw CancellationError() }
      // 发「已读」期间又点了「留下」，新回执不能被旧完成盖掉。
      if cache.pending[id] == keep { cache.pending[id] = nil; persist() }
    }
  }
  func opened(_ item: ShareItem) { mark(item, keep: false) }
  func kept(_ item: ShareItem) { mark(item, keep: true) }
  private func mark(_ item: ShareItem, keep: Bool) {
    guard let index = cache.items.firstIndex(where: { $0.id == item.id }) else { return }
    let stamp = ShareDates.stamp()
    cache.items[index].openedAt = cache.items[index].openedAt ?? stamp
    if keep { cache.items[index].keptAt = cache.items[index].keptAt ?? stamp }
    cache.pending[item.id] = (cache.pending[item.id] ?? false) || keep
    persist(); items = cache.items; pull()
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
  @discardableResult nonisolated static func pruneShots(in directory: URL, keeping ids: Set<String>) -> Int {
    let folder = directory.appendingPathComponent("share-shots")
    let names = (try? FileManager.default.contentsOfDirectory(atPath: folder.path)) ?? []
    var removed = 0
    for name in names where name.hasSuffix(".jpg") && !ids.contains(String(name.dropLast(4))) {
      if (try? FileManager.default.removeItem(at: folder.appendingPathComponent(name))) != nil { removed += 1 }
    }
    return removed
  }
  /// 超过 `budget` 就按最久没看（修改时间，`shot(_:)` 读到时会拨到现在）删「id.jpg」，
  /// 删到回到预算以内。别的文件不碰。
  @discardableResult nonisolated static func trimShots(in directory: URL, budget: Int = shotDiskBudget) -> Int {
    let folder = directory.appendingPathComponent("share-shots")
    let keys: [URLResourceKey] = [.fileSizeKey, .contentModificationDateKey]
    let files = ((try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: keys)) ?? [])
      .filter { $0.pathExtension == "jpg" }
      .compactMap { url -> (url: URL, size: Int, used: Date)? in
        guard let values = try? url.resourceValues(forKeys: Set(keys)) else { return nil }
        return (url, values.fileSize ?? 0, values.contentModificationDate ?? .distantPast)
      }
    var total = files.reduce(0) { $0 + $1.size }
    var removed = 0
    for file in files.sorted(by: { $0.used < $1.used }) where total > budget {
      if (try? FileManager.default.removeItem(at: file.url)) != nil { total -= file.size; removed += 1 }
    }
    return removed
  }
  /// 一张缩略图从哪儿来的：`fetched` = 这次是从服务端拉下来的（盘上没有）。
  struct ThumbLoad: Sendable {
    var image: UIImage?
    var fetched: Bool
  }
  private func remember(_ image: UIImage, for id: String) {
    thumbs[id] = image
    thumbOrder.removeAll { $0 == id }; thumbOrder.append(id)
    while thumbOrder.count > Self.thumbMemoryLimit, let victim = thumbOrder.first {
      thumbOrder.removeFirst(); thumbs.removeValue(forKey: victim)
    }
  }
  /// 内存里现成的那张，不读盘、不下载、不改淘汰顺序。行重新滚进屏幕时拿它先顶上，
  /// 不闪一下占位图。
  func cachedThumbnail(_ id: String) -> UIImage? { thumbs[id] }
  /// 这封信的缩略图（已缩到屏上尺寸）。内存里有就直接给；没有就在后台读盘、解码，
  /// 盘上也没有才去服务端拉，拉下来落盘。读盘、写盘、解码都不在主线程上。
  func thumbnail(_ id: String) async -> UIImage? {
    if let image = thumbs[id] { remember(image, for: id); return image }
    let generation = epoch
    if let running = loading[id] {
      let result = await running.value
      return generation == epoch ? result.image : nil
    }
    guard let client, let directory else { return nil }
    let file = Self.shotFile(id, in: directory)
    let job = Task { await Self.loadThumbnail(id, file: file, client: client) }
    loading[id] = job
    let result = await job.value
    if loading[id] == job { loading[id] = nil }
    guard generation == epoch else { return nil }
    if result.fetched { scheduleTrim(in: directory) }
    if let image = result.image { remember(image, for: id) }
    return result.image
  }
  private nonisolated static func shotFile(_ id: String, in directory: URL) -> URL {
    directory.appendingPathComponent("share-shots").appendingPathComponent(id + ".jpg")
  }
  /// 先读盘（读到就把修改时间拨到现在，`trimShots` 按它判最久没看），读不到或坏了才下载。
  @concurrent nonisolated private static func loadThumbnail(_ id: String, file: URL,
                                                             client: any ShareInboxService) async -> ThumbLoad {
    if let data = try? Data(contentsOf: file) {
      if let image = decodeThumbnail(data) {
        try? FileManager.default.setAttributes([.modificationDate: Date()], ofItemAtPath: file.path)
        return ThumbLoad(image: image, fetched: false)
      }
      // 盘上那张坏了（写到一半断电之类），删掉重拉。
      try? FileManager.default.removeItem(at: file)
    }
    guard let data = try? await client.shot(id), !Task.isCancelled else {
      return ThumbLoad(image: nil, fetched: false)
    }
    try? FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
    try? data.write(to: file, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
    return ThumbLoad(image: decodeThumbnail(data), fetched: true)
  }
  /// 按屏上尺寸解码：短边缩到 `thumbnailPixels`（原图更小就不放大），方向照 EXIF 摆正。
  /// 图上 `scaledToFill` 进 44 pt 宽的格子，三倍屏上也不会被放大，看起来和整张解码一样。
  nonisolated static func decodeThumbnail(_ data: Data) -> UIImage? {
    guard let source = CGImageSourceCreateWithData(data as CFData, [kCGImageSourceShouldCache: false] as CFDictionary),
          CGImageSourceGetCount(source) > 0 else { return nil }
    let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any]
    let width = properties?[kCGImagePropertyPixelWidth] as? Int ?? 0
    let height = properties?[kCGImagePropertyPixelHeight] as? Int ?? 0
    guard width > 0, height > 0 else { return nil }
    let long = max(width, height), short = min(width, height)
    let edge = min(long, Int((Double(long) * Double(thumbnailPixels) / Double(short)).rounded(.up)))
    let options: [CFString: Any] = [
      kCGImageSourceCreateThumbnailFromImageAlways: true,
      kCGImageSourceCreateThumbnailWithTransform: true,
      kCGImageSourceShouldCacheImmediately: true,
      kCGImageSourceThumbnailMaxPixelSize: edge,
    ]
    guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else { return nil }
    return UIImage(cgImage: image)
  }
  /// 下载落盘之后把 `share-shots/` 裁回预算以内。一批下载只排一次：等 `trimDelay`，
  /// 再在后台扫一遍目录（以前每下载一张就在主线程上把整个目录扫一遍）。
  private func scheduleTrim(in directory: URL) {
    guard trimPending.insert(directory).inserted else { return }
    trimsScheduled += 1
    Task { [weak self] in
      try? await Task.sleep(for: Self.trimDelay)
      await Task.detached(priority: .utility) { Self.trimShots(in: directory) }.value
      self?.trimPending.remove(directory)
    }
  }
}

/// `shares.json` 的落盘。一条串行队列：后台写按文件合批（还没写出去的旧份被最新那份顶掉），
/// 同步写也排在同一条队列上，所以排在前面的旧份永远不会晚于后来的同步写落地。
final class ShareCacheWriter: @unchecked Sendable {
  private let queue = DispatchQueue(label: "kanpan.share-cache", qos: .utility)
  private let pending = OSAllocatedUnfairLock<[URL: ShareInbox.Cache]>(uncheckedState: [:])
  private let counter = OSAllocatedUnfairLock(initialState: 0)
  /// 真写了几次盘。给用例数合批。
  var writes: Int { counter.withLock { $0 } }

  func schedule(_ cache: ShareInbox.Cache, to file: URL, failed: @escaping @Sendable () -> Void) {
    let first = pending.withLockUnchecked { slots in
      defer { slots[file] = cache }
      return slots[file] == nil
    }
    guard first else { return }
    queue.async { [self] in
      guard let latest = pending.withLockUnchecked({ $0.removeValue(forKey: file) }) else { return }
      do { try write(latest, to: file) } catch { failed() }
    }
  }
  func writeNow(_ cache: ShareInbox.Cache, to file: URL) throws {
    try queue.sync {
      // 这一份比排着的那份新，排着的不必再写。
      _ = pending.withLockUnchecked { $0.removeValue(forKey: file) }
      try write(cache, to: file)
    }
  }
  /// 等排着的都写完。
  func drain() { queue.sync {} }
  /// 占着写盘队列跑一段（给用例排一串「队列正忙时」进来的保存）。
  func whileBusy(_ body: () -> Void) { queue.sync(execute: body) }
  private func write(_ cache: ShareInbox.Cache, to file: URL) throws {
    try JSONEncoder().encode(cache).write(to: file, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
    counter.withLock { $0 += 1 }
  }
}
