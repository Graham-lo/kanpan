import Foundation
import Security

/// 一个交易所账户在本机的全部状态：Key / Secret 与接入元数据。
///
/// **只存本机 Keychain，`kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly`**：
/// - 不进 iCloud 钥匙串、不跟备份迁到新手机（换机重新贴一次 Key，比 Key 跟着备份到处走安全）；
/// - 不进任何偏好同步字段（`Prefs.syncedFieldNames` 里没有它，也不许加）、不进「导出我的数据」
///   （导出的是服务端上的数据，这里的东西服务端从头到尾没见过）；
/// - 服务端不经手：Key 只在手机上签名用，见各家交易所账户实现的头注释为什么（VPS 在美国，调账户端点会 451）。
///
/// 元数据（Key 尾号四位、接入时间、回溯起点、上次同步到哪）也放 Keychain 而不是偏好：
/// 它和 Key 同生同灭，删 Key 时一并清掉，不会留下「显示接着、其实没 Key」的半截状态。
struct ExchangeCredentialStore: Sendable {
  /// 接入元数据。界面只显示尾号，不显示 Key 本身。
  struct Status: Codable, Sendable, Equatable {
    /// Key 的后 4 位。
    var keySuffix: String
    /// 接入时间（毫秒）。
    var connectedAt: Int64
    /// 第一次回溯的起点（毫秒）：接入时往前 90 天。
    var backfillFrom: Int64
    /// 已经完整拉到的时间点（毫秒）；nil 表示还没拉成过一次。
    var watermark: Int64?
    /// 上一次尝试同步的时间（毫秒），前台节流用。
    var lastAttemptAt: Int64?
  }

  let service: String
  private let io: ExchangeKeychainIO

  /// 正式用的 service 名按交易所分；测试传一个自己的，互不干扰。
  init(venue: String, market: String) {
    self.init(service: "kanpan.exchange.\(venue).\(market)")
  }

  /// `io` 只给测试换成内存版（模拟某一项写不进去）；正式一律走系统 Keychain。
  init(service: String, io: ExchangeKeychainIO = .system) {
    self.service = service
    self.io = io
  }

  private static let credentialsAccount = "credentials"
  private static let statusAccount = "status"

  // MARK: - 凭据

  func loadCredentials() throws -> ExchangeCredentials? {
    try io.read(service, Self.credentialsAccount).map { try Self.decode(ExchangeCredentials.self, $0) }
  }

  func loadStatus() throws -> Status? {
    try io.read(service, Self.statusAccount).map { try Self.decode(Status.self, $0) }
  }

  /// 接入：Key 与元数据一起写。调用方必须先过只读校验再调这里。
  ///
  /// 两项要么都在、要么都不在：元数据写不进去时把刚写的 Key 删回去再抛错。
  /// 否则界面按元数据判「没接入」，Key 却悄悄留在 Keychain 里，用户以为没存、其实存着。
  func save(credentials: ExchangeCredentials, status: Status) throws {
    let credentialsData = try Self.encode(credentials)
    let statusData = try Self.encode(status)
    try io.write(credentialsData, service, Self.credentialsAccount)
    do {
      try io.write(statusData, service, Self.statusAccount)
    } catch {
      try? io.delete(service, Self.credentialsAccount)
      try? io.delete(service, Self.statusAccount)
      throw error
    }
  }

  func saveStatus(_ status: Status) throws {
    try io.write(Self.encode(status), service, Self.statusAccount)
  }

  /// 断开：Key 与元数据全删。先删 Key（最要紧的那一项），删元数据失败也不影响 Key 已经删掉；
  /// 两项都试一遍，任何一项没删成都抛错，让界面照实说「没断开」。
  func removeAll() throws {
    var failure: (any Error)?
    do { try io.delete(service, Self.credentialsAccount) } catch { failure = error }
    do { try io.delete(service, Self.statusAccount) } catch { failure = failure ?? error }
    if let failure { throw failure }
  }

  private static func encode<T: Encodable>(_ value: T) throws -> Data {
    do { return try JSONEncoder().encode(value) } catch { throw ExchangeAccountError.keychain }
  }

  private static func decode<T: Decodable>(_ type: T.Type, _ data: Data) throws -> T {
    do { return try JSONDecoder().decode(type, from: data) } catch { throw ExchangeAccountError.keychain }
  }
}

/// Keychain 的读、写、删三个动作。正式用 `.system`（本机 Keychain、`AfterFirstUnlockThisDeviceOnly`）；
/// 测试换成内存版，才能模拟「第二项写不进去」这种系统 Keychain 造不出来的情况。
struct ExchangeKeychainIO: Sendable {
  var read: @Sendable (_ service: String, _ account: String) throws -> Data?
  var write: @Sendable (_ data: Data, _ service: String, _ account: String) throws -> Void
  var delete: @Sendable (_ service: String, _ account: String) throws -> Void

  static let system = ExchangeKeychainIO(read: { try ExchangeKeychainIO.systemRead($0, $1) },
                                         write: { try ExchangeKeychainIO.systemWrite($0, $1, $2) },
                                         delete: { try ExchangeKeychainIO.systemDelete($0, $1) })

  private static func baseQuery(_ service: String, _ account: String) -> [String: Any] {
    [kSecClass as String: kSecClassGenericPassword,
     kSecAttrService as String: service,
     kSecAttrAccount as String: account]
  }

  private static func systemRead(_ service: String, _ account: String) throws -> Data? {
    var query = baseQuery(service, account)
    query[kSecReturnData as String] = true
    query[kSecMatchLimit as String] = kSecMatchLimitOne
    var result: CFTypeRef?
    let status = SecItemCopyMatching(query as CFDictionary, &result)
    switch status {
    case errSecSuccess: return result as? Data
    case errSecItemNotFound: return nil
    default: throw ExchangeAccountError.keychain
    }
  }

  private static func systemWrite(_ data: Data, _ service: String, _ account: String) throws {
    let attributes: [String: Any] = [
      kSecValueData as String: data,
      kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
    ]
    let query = baseQuery(service, account)
    let updated = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
    if updated == errSecSuccess { return }
    guard updated == errSecItemNotFound else { throw ExchangeAccountError.keychain }
    var add = query
    add.merge(attributes) { $1 }
    guard SecItemAdd(add as CFDictionary, nil) == errSecSuccess else { throw ExchangeAccountError.keychain }
  }

  private static func systemDelete(_ service: String, _ account: String) throws {
    let status = SecItemDelete(baseQuery(service, account) as CFDictionary)
    guard status == errSecSuccess || status == errSecItemNotFound else { throw ExchangeAccountError.keychain }
  }
}
