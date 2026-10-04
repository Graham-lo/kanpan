import Foundation
import Security

public protocol CredentialVault: Sendable {
  /// 这份凭据住在哪个「槽」里。**同一个槽就是同一套凭据**，哪怕分属两个
  /// `AccountClient` 实例。刷新的单飞与代际按它共享（见 `RefreshCoordinator`）：
  /// 两个客户端同时去刷同一把 refresh 令牌，服务端会当成令牌重用，把整条会话家族吊销。
  /// 所以这不是个可有可无的标识——认错槽就等于没有保护。
  var slotIdentifier: String { get }
  /// 读凭据。`nil` = 这里确实没有凭据；**抛出** = 这一刻读不动（凭据可能还在）。
  /// 两者不能混：把「读不动」当成「没有」，锁屏被拉起的那一次就会把登录的人装成访客。
  func read() throws -> SavedAccount?
  func write(_ value: SavedAccount?) throws
}
public struct KeychainCredentialVault: CredentialVault {
  public let service: String
  public init(service: String = "kanpan.account") { self.service = service }
  /// 钥匙串这一侧，一个 service 名就是一份凭据（account 固定是 `active-session`）。
  public var slotIdentifier: String { "keychain:" + service }
  private var query: [String: Any] { [kSecClass as String: kSecClassGenericPassword,
    kSecAttrService as String: service, kSecAttrAccount as String: "active-session"] }
  public func read() throws -> SavedAccount? {
    var q = query; q[kSecReturnData as String] = true; q[kSecMatchLimit as String] = kSecMatchLimitOne
    var result: CFTypeRef?
    let status = SecItemCopyMatching(q as CFDictionary, &result)
    if status == errSecItemNotFound { return nil }
    // 条目在、但这一刻不让读：设备重启后还没解过锁，app 被后台拉起（推送、后台刷新）。
    // 这不是「没登录」——调用方要按上次的身份照常装档案、稍后再读（见 `AccountClient`）。
    if status == errSecInteractionNotAllowed { throw AccountError.credentialsUnavailable }
    guard status == errSecSuccess, let data = result as? Data else { throw AccountError.keychain }
    // 读到了、但内容解不开（老版本写坏的、格式改过的）：这不是「这一刻读不动」——
    // 再读多少次也还是这串字节。以前直接把解码错误抛出去，客户端当成「凭据欠着」，
    // 人就永远卡在「暂时读不到登录状态」、既不算登录也退不了（审查 D-11）。
    // 当成没有凭据并把坏条目删掉，人看到的是「没登录」，重新登录一次就好。
    guard let saved = Self.decode(data) else { _ = SecItemDelete(query as CFDictionary); return nil }
    return saved
  }
  /// 钥匙串里那串字节解成凭据；解不开就是 `nil`（见 `read()`）。
  static func decode(_ data: Data) -> SavedAccount? { try? JSONDecoder().decode(SavedAccount.self, from: data) }
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
