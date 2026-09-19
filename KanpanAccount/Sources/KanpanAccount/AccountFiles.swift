import Foundation

/// Durable account boundaries. Evictable history belongs in Library/Caches, never this directory.
@MainActor public final class AccountFiles {
  public let root: URL
  private struct Registry: Codable { var version = 1; var guest = UUID(); var claims: [String: UUID] = [:]; var completed: Set<String> = [] }
  private var registry: Registry
  private var registryURL: URL { root.appendingPathComponent("registry.json") }
  public init(root: URL) throws {
    self.root = root
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    let url = root.appendingPathComponent("registry.json")
    if FileManager.default.fileExists(atPath: url.path) {
      registry = try JSONDecoder().decode(Registry.self, from: Data(contentsOf: url))
      guard registry.version == 1 else { throw AccountError.storage }
    } else { registry = Registry(); try Self.write(registry, to: url) }
  }
  public var guestBatch: UUID { registry.guest }

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
