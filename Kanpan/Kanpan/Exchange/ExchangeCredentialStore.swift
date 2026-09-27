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

  /// 正式用的 service 名按交易所分；测试传一个自己的，互不干扰。
  init(venue: String, market: String) {
    self.service = "kanpan.exchange.\(venue).\(market)"
  }

  init(service: String) {
    self.service = service
  }

  private static let credentialsAccount = "credentials"
  private static let statusAccount = "status"

  // MARK: - 凭据

  func loadCredentials() throws -> ExchangeCredentials? {
    try read(Self.credentialsAccount).map { try Self.decode(ExchangeCredentials.self, $0) }
  }

  func loadStatus() throws -> Status? {
    try read(Self.statusAccount).map { try Self.decode(Status.self, $0) }
  }

  /// 接入：Key 与元数据一起写。调用方必须先过只读校验再调这里。
  func save(credentials: ExchangeCredentials, status: Status) throws {
    try write(Self.encode(credentials), account: Self.credentialsAccount)
    try write(Self.encode(status), account: Self.statusAccount)
  }

  func saveStatus(_ status: Status) throws {
    try write(Self.encode(status), account: Self.statusAccount)
  }

  /// 断开：Key 与元数据全删。
  func removeAll() throws {
    try delete(Self.credentialsAccount)
    try delete(Self.statusAccount)
  }

  // MARK: - Keychain

  private func baseQuery(_ account: String) -> [String: Any] {
    [kSecClass as String: kSecClassGenericPassword,
     kSecAttrService as String: service,
     kSecAttrAccount as String: account]
  }

  private func read(_ account: String) throws -> Data? {
    var query = baseQuery(account)
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

  private func write(_ data: Data, account: String) throws {
    let attributes: [String: Any] = [
      kSecValueData as String: data,
      kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
    ]
    let updated = SecItemUpdate(baseQuery(account) as CFDictionary, attributes as CFDictionary)
    if updated == errSecSuccess { return }
    guard updated == errSecItemNotFound else { throw ExchangeAccountError.keychain }
    var add = baseQuery(account)
    add.merge(attributes) { $1 }
    guard SecItemAdd(add as CFDictionary, nil) == errSecSuccess else { throw ExchangeAccountError.keychain }
  }

  private func delete(_ account: String) throws {
    let status = SecItemDelete(baseQuery(account) as CFDictionary)
    guard status == errSecSuccess || status == errSecItemNotFound else { throw ExchangeAccountError.keychain }
  }

  private static func encode<T: Encodable>(_ value: T) throws -> Data {
    do { return try JSONEncoder().encode(value) } catch { throw ExchangeAccountError.keychain }
  }

  private static func decode<T: Decodable>(_ type: T.Type, _ data: Data) throws -> T {
    do { return try JSONDecoder().decode(type, from: data) } catch { throw ExchangeAccountError.keychain }
  }
}
