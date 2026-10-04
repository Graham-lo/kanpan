import Foundation

/// Durable account boundaries. Evictable history belongs in Library/Caches, never this directory.
@MainActor public final class AccountFiles {
  public let root: URL
  /// `owner` 是后加的可选字段：老的 registry.json 没有这个键，解出来就是 `nil`。
  private struct Registry: Codable {
    var version = 1; var guest = UUID(); var claims: [String: UUID] = [:]; var completed: Set<String> = []
    var owner: AccountUser?
  }
  private var registry: Registry
  private var registryURL: URL { root.appendingPathComponent("registry.json") }
  /// 打开账号根目录。
  ///
  /// `registry.json` 三种读不动要分开对待：
  /// - **读不出字节**（首次解锁前的数据保护、IO 抽风）：照抛。这是「这会儿读不动」，下次启动就好。
  /// - **比自己新的版本**：照抛、原地不动，等升级回去还能读。
  /// - **字节在、但解不开**（半截、乱码）：从前也是照抛，而 `AppAccountBridge` 建不起来，
  ///   `MainScreen` 那边只能报个错——此后**每一次**启动都一样，账号同步、换档案全都死掉，
  ///   没有任何自救的路（V-3）。现在把坏档原样挪到旁边（`registry.json.unreadable-<毫秒时间戳>`），
  ///   重建一份：访客批次能确定就沿用（见 `recoveredGuest`），确定不了就开新的；
  ///   认领日志没法重建，丢掉的最坏结果是某次没走完的访客搬家要重新认领，原目录都还在盘上。
  public init(root: URL, now: Date = Date()) throws {
    self.root = root
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    let url = root.appendingPathComponent("registry.json")
    if FileManager.default.fileExists(atPath: url.path) {
      let data = try Data(contentsOf: url)
      if let decoded = try? JSONDecoder().decode(Registry.self, from: data) {
        guard decoded.version == 1 else { throw AccountError.storage }
        registry = decoded
      } else {
        struct Probe: Decodable { var version: Int? }
        if let version = (try? JSONDecoder().decode(Probe.self, from: data))?.version, version != 1 {
          throw AccountError.storage
        }
        let stamp = Int((now.timeIntervalSince1970 * 1000).rounded())
        try FileManager.default.moveItem(at: url, to: root.appendingPathComponent("registry.json.unreadable-\(stamp)"))
        var fresh = Registry()
        if let guest = Self.recoveredGuest(root: root) { fresh.guest = guest }
        registry = fresh; try Self.write(registry, to: url)
      }
    } else { registry = Registry(); try Self.write(registry, to: url) }
  }

  /// 登记簿坏了之后，哪个访客批次能**确定**是现在这位访客的。
  ///
  /// 只有一种情况能确定：这台机器上从没登录过（根目录下没有任何 `u-` 档案），
  /// 而 `local/` 下恰好只有一个有内容的批次——那就是一直在用的那一份，接着用，
  /// 访客的自选、画线不会因为登记簿坏了就「没了」。
  /// 登录过就不猜：那时 `local/` 下的旧批次可能是已经搬进某个账号的备份，
  /// 拿它当访客，下次登录会被再认领一遍，把用户早删掉的东西又并回去。
  private static func recoveredGuest(root: URL) -> UUID? {
    let fm = FileManager.default
    let top = (try? fm.contentsOfDirectory(atPath: root.path)) ?? []
    guard !top.contains(where: { $0.hasPrefix("u-") }) else { return nil }
    let local = root.appendingPathComponent("local", isDirectory: true)
    let batches = ((try? fm.contentsOfDirectory(atPath: local.path)) ?? []).compactMap { name -> UUID? in
      guard let id = UUID(uuidString: name),
        let items = try? fm.contentsOfDirectory(atPath: local.appendingPathComponent(name).path), !items.isEmpty
      else { return nil }
      return id
    }
    return batches.count == 1 ? batches[0] : nil
  }
  public var guestBatch: UUID { registry.guest }
  /// 上一次装进来的是哪个**登录的**人（访客、已退登 = `nil`）。
  ///
  /// 只有身份（id + 用户名），没有任何令牌——凭据只在钥匙串里。它存在的唯一理由是
  /// 钥匙串**读不动**的那几次（锁屏被后台拉起、钥匙串守护进程抽风）：那时不知道
  /// 这台机器上是谁，就按它把那个人的本地档案照常装上，而不是退成访客让人以为
  /// 「自选没了」。见 `AccountFeature.restore()`。
  public var lastOwner: AccountUser? { registry.owner }
  /// 记下现在装着的是谁（和 `activate` 同在提交点调用）。没变就不写盘；写失败也不抛——
  /// 它只是钥匙串读不动时的后备，丢一次最坏就是那一次退成访客（和从前一样）。
  public func remember(owner: AccountUser?) {
    guard registry.owner != owner else { return }
    var next = registry; next.owner = owner
    guard (try? Self.write(next, to: registryURL)) != nil else { return }
    registry = next
  }

  /// 现在装着的是谁的档案：`u-<账号 uuid>`，或没登录时的 `local/<访客批次 uuid>`。
  ///
  /// 谁要它：`Library/Caches` 下那几份**内容随当前账号派生**的行情缓存（报价、
  /// 当日开盘价）得按身份分目录，否则 A 退出、B 登录，第一帧闪的是 A 的自选报价。
  /// `KanpanData.Paths` 是数据层，不认识账号包，身份只能由 app 那一层注入给它
  /// （`Paths.caches(profile:)`）。所以这个值就留在**算这条路径的地方**——
  /// 一处计算、两处用，绝不另发明一套 id。
  ///
  /// 它标的是「档案」，不是「登录状态」：没登录时也有一份（访客批次）。
  public private(set) static var currentProfile: String = ""

  /// 这个属主的档案 id。路径与 id 是同一个字符串，见 `currentProfile`。
  public func profileID(user: UUID?) -> String {
    user.map { "u-" + $0.uuidString.lowercased() } ?? "local/" + registry.guest.uuidString.lowercased()
  }

  /// 现在起装的是这个人的档案。
  ///
  /// 装档案是「先把所有会失败的活干完，再一次性提交」（`AppAccountBridge.prepare`
  /// 返回的那个闭包就是提交点），身份必须跟着**提交**走：取目录只是把地方准备好，
  /// 那之后还有读盘、解码、`ReviewStore` 初始化，任何一步抛出来，人都还留在原来
  /// 那个档案里——而身份要是已经改了，行情缓存就会写进另一个人的目录。
  ///
  /// `claimGuest` 里那次取访客目录也因此不需要特殊对待：它只是搬家的*来源*，
  /// 根本碰不到身份。
  public func activate(user: UUID?) { Self.currentProfile = profileID(user: user) }

  /// 取（并建好）某个属主的档案目录。**只建目录，不换身份**（见 `activate`）。
  public func directory(user: UUID?) throws -> URL { try makeDirectory(profileID(user: user)) }

  private func makeDirectory(_ id: String) throws -> URL {
    let url = root.appendingPathComponent(id, isDirectory: true)
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true); return url
  }
  /// Existing files survive corrupt/newer data; callers must handle failure explicitly.
  public static func write<T: Encodable>(_ value: T, to url: URL) throws {
    try writeData(try JSONEncoder().encode(value), to: url)
  }
  /// 已经编码好的字节直接落盘。
  ///
  /// 编码在调用方做完，这里只剩建目录 + 原子写，因此不需要主线程——`SyncStore`
  /// 的落盘队列就是用这个口子把「编码 + 写盘」整段挪出主线程的。
  public nonisolated static func writeData(_ data: Data, to url: URL) throws {
    try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
    try data.write(to: url, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
  }
  public static func read<T: Decodable>(_ type: T.Type, at url: URL) throws -> T? {
    guard FileManager.default.fileExists(atPath: url.path) else { return nil }
    return try JSONDecoder().decode(type, from: Data(contentsOf: url))
  }
  public func pendingGuest(user: UUID) throws -> (id: UUID, directory: URL)? {
    guard let key = registry.claims.keys.sorted().first(where: { registry.claims[$0] == user && !registry.completed.contains($0) }),
      let batch = UUID(uuidString: key) else { return nil }
    return (batch, root.appendingPathComponent("local/" + batch.uuidString.lowercased()))
  }
  /// Assignment and guest rotation share one atomic journal. A crash cannot assign a batch twice.
  public func claimGuest(user: UUID) throws -> (id: UUID, directory: URL)? {
    if let pending = try pendingGuest(user: user) { return pending }
    let batch = registry.guest
    // 搬家的**来源**目录，不是「当前档案」——所以不走 `directory(user:)`（见那儿的注释）。
    let source = try makeDirectory(profileID(user: nil))
    let files = try FileManager.default.contentsOfDirectory(at: source, includingPropertiesForKeys: nil)
    guard !files.isEmpty else { return nil }
    var next = registry; next.claims[batch.uuidString] = user; next.guest = UUID()
    try Self.write(next, to: registryURL); registry = next
    return (batch, source)
  }
  /// Call only after copied drafts and server-acknowledged operations are durable in the owner's slot.
  public func completeGuestClaim(user: UUID, batch: UUID) throws {
    guard registry.claims[batch.uuidString] == user else { throw AccountError.storage }
    var next = registry; next.completed.insert(batch.uuidString)
    try Self.write(next, to: registryURL); registry = next
    // Source remains a migration backup until a verified retention pass; never auto-import again.
  }
}
