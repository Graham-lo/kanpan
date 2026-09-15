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
