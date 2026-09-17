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
  public func directory(user: UUID?) throws -> URL {
    let path = user.map { "u-" + $0.uuidString.lowercased() } ?? "local/" + registry.guest.uuidString.lowercased()
    let url = root.appendingPathComponent(path, isDirectory: true)
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
    let source = try directory(user: nil)
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
