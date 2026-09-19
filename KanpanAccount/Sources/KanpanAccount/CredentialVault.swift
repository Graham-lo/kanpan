import Foundation
import Security

public protocol CredentialVault: Sendable {
  func read() throws -> SavedAccount?
  func write(_ value: SavedAccount?) throws
}
public struct KeychainCredentialVault: CredentialVault {
  public let service: String
  public init(service: String = "kanpan.account") { self.service = service }
  private var query: [String: Any] { [kSecClass as String: kSecClassGenericPassword,
    kSecAttrService as String: service, kSecAttrAccount as String: "active-session"] }
  public func read() throws -> SavedAccount? {
    var q = query; q[kSecReturnData as String] = true; q[kSecMatchLimit as String] = kSecMatchLimitOne
    var result: CFTypeRef?
    let status = SecItemCopyMatching(q as CFDictionary, &result)
    if status == errSecItemNotFound { return nil }
    guard status == errSecSuccess, let data = result as? Data else { throw AccountError.keychain }
    return try JSONDecoder().decode(SavedAccount.self, from: data)
  }
  public func write(_ value: SavedAccount?) throws {
    guard let value else {
      let status = SecItemDelete(query as CFDictionary)
      guard status == errSecSuccess || status == errSecItemNotFound else { throw AccountError.keychain }; return
    }
    let data = try JSONEncoder().encode(value)
    let attributes: [String: Any] = [kSecValueData as String: data,
      kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly]
    let status = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
    if status == errSecItemNotFound {
      var q = query; attributes.forEach { q[$0.key] = $0.value }
      guard SecItemAdd(q as CFDictionary, nil) == errSecSuccess else { throw AccountError.keychain }
    } else if status != errSecSuccess { throw AccountError.keychain }
  }
}

/// 老版本在钥匙串里留下的条目。
///
/// 复盘从网页版并进来时带过一套自己的凭据（service = `kanpan.scorebook`，由
/// `ReviewData.ReviewCredentials` 读写）。这一版复盘的鉴权全部走账号那条链
/// （`AccountClient` 的访问令牌），那套凭据**再没有任何读路径**——但老机器上那条
/// 钥匙串条目还躺着，而钥匙串是唯一一处「退登之后还留在本机的用户凭据」。
/// 所以退登时连它一起抹掉：没有读路径不等于它不该走。
public enum LegacyKeychain {
  /// 把这个 service 下的所有通用密码条目删掉。没有就当已经删过（幂等）。
  @discardableResult public static func purge(service: String) -> Bool {
    let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
                                kSecAttrService as String: service]
    let status = SecItemDelete(query as CFDictionary)
    return status == errSecSuccess || status == errSecItemNotFound
  }
  /// 复盘那套老凭据的 service 名。
  public static let reviewService = "kanpan.scorebook"
}
