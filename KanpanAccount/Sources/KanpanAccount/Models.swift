import Foundation

public struct AccountUser: Codable, Sendable, Equatable, Identifiable {
  public var id: UUID
  public var email: String
  public init(id: UUID, email: String) { self.id = id; self.email = email }
}
/// 设备类别。一个账号每一类同时只准一台在线：手机一类、平板一类、电脑一类
/// （服务端 `Backend/kanpan-api/src/auth.rs` 的 `DeviceKind`）。
///
/// **同一台设备每一趟请求都得报同一个类别**：刷新时报的类别和会话记录对不上，
/// 服务端判 `invalid_device`。所以这个值一旦跟着凭据落了盘，就照着盘上那份走，
/// 不要每次开机重新推断一遍。
public enum DeviceKind: String, Codable, Sendable, Equatable, CaseIterable {
  case phone, tablet, desktop
  /// 界面上的叫法。
  public var label: String {
    switch self { case .phone: "手机"; case .tablet: "平板"; case .desktop: "电脑" }
  }
  /// 不认识的类别按手机算，和服务端 `DeviceKind::parse` 一致。
  /// 将来服务端多出一类（手表之类）时，老客户端解不开的应该只是那一个字段，
  /// 而不是整张设备列表、整条错误响应。
  public init(from decoder: any Decoder) throws {
    let raw = try decoder.singleValueContainer().decode(String.self)
    self = DeviceKind(rawValue: raw) ?? .phone
  }
}
public struct AccountDevice: Codable, Sendable, Equatable {
  public var id: UUID
  public var name: String
  public var secret: String
  /// 这台机器算哪一类。平台判断在 app 壳层做（`AccountFeature`），包里不碰 UIKit。
  public var kind: DeviceKind
  public init(id: UUID = UUID(), name: String, kind: DeviceKind = .phone,
              secret: String = UUID().uuidString + UUID().uuidString) {
    self.id = id; self.name = name; self.kind = kind; self.secret = secret
  }
  /// 老版本写下的钥匙串存档里没有 `kind`。它对应的那条服务端会话也是按「手机」记的
  /// （服务端那个枚举的 `#[default]`），所以缺省必须是手机——解成别的类别，
  /// 下一次刷新就会被判 `invalid_device`，人白白被登出。
  public init(from decoder: any Decoder) throws {
    let c = try decoder.container(keyedBy: CodingKeys.self)
    id = try c.decode(UUID.self, forKey: .id)
    name = try c.decode(String.self, forKey: .name)
    secret = try c.decode(String.self, forKey: .secret)
    kind = try c.decodeIfPresent(DeviceKind.self, forKey: .kind) ?? .phone
  }
}
public struct AccountTokens: Codable, Sendable {
  public var user: AccountUser
  public var sessionId: UUID
  public var accessToken: String
  public var refreshToken: String
  public var expiresAt: Int64
  public var serverTime: Int64
}
public struct SavedAccount: Codable, Sendable {
  public var user: AccountUser
  public var sessionId: UUID
  public var device: AccountDevice
  public var refreshToken: String
  public var refreshRequestId: UUID?
  /// 是谁签发的这份凭据（服务器主机名）。
  ///
  /// 令牌只对签它的那台服务器有意义，换一台就是把 A 家的钥匙往 B 家的锁上试
  /// ——最轻也是把自己的 refresh 令牌递给了别人。恢复会话时对不上就当作没有会话。
  /// 老版本写下的存档没有这个字段（`nil`），按当前地址算数：迁移不清人。
  public var origin: String?
  /// 这条会话被**同一类设备**顶掉了（服务端 401 `session_replaced`），是被哪一类顶的。
  ///
  /// 记在存档里，同时把 `refreshToken` 清空：那把令牌服务端已经作废，留着只会在
  /// 下一次刷新时再撞一次墙；**身份留着**是因为本机档案（自选、画线、复盘）是按
  /// 用户 id 存的，把整条存档删掉，下次开 app 装进来的就是访客那份了——
  /// 云端只是同步通道，不是可用性依赖。
  public var replacedBy: DeviceKind?
}
public struct AccountSessionDevice: Codable, Sendable, Identifiable {
  public var id: UUID
  public var name: String
  public var kind: DeviceKind
  public var createdAt: Int64
  public var lastSeen: Int64
  public var current: Bool
  public init(id: UUID, name: String, kind: DeviceKind = .phone, createdAt: Int64, lastSeen: Int64, current: Bool) {
    self.id = id; self.name = name; self.kind = kind
    self.createdAt = createdAt; self.lastSeen = lastSeen; self.current = current
  }
  /// 网关有两台，可能一台已经在发 `kind` 另一台还没有。缺了的那一条按手机算，
  /// 别让整张设备列表解不开。
  public init(from decoder: any Decoder) throws {
    let c = try decoder.container(keyedBy: CodingKeys.self)
    id = try c.decode(UUID.self, forKey: .id)
    name = try c.decode(String.self, forKey: .name)
    kind = try c.decodeIfPresent(DeviceKind.self, forKey: .kind) ?? .phone
    createdAt = try c.decode(Int64.self, forKey: .createdAt)
    lastSeen = try c.decode(Int64.self, forKey: .lastSeen)
    current = try c.decode(Bool.self, forKey: .current)
  }
}
public struct AccountDevices: Decodable, Sendable { public var devices: [AccountSessionDevice] }
public struct AccountOK: Decodable, Sendable { public var ok: Bool }
public enum AccountError: LocalizedError, Equatable {
  case unavailable, invalidURL, invalidResponse, keychain, storage, reauthenticationRequired, http(Int, String)
  /// 钥匙串**这一刻**读不动（锁屏状态下被后台拉起时的 `errSecInteractionNotAllowed`、
  /// 钥匙串守护进程抽风）。凭据很可能还在，只是现在拿不到——和「没有凭据」「凭据被
  /// 服务端拒了」都不是一回事：本机档案照常装着，同步停一停，读得到了再接上。
  case credentialsUnavailable
  /// 这条会话被**同一类设备**顶下去了（服务端 401 `session_replaced`）。
  ///
  /// 和 `reauthenticationRequired` 分开是因为它们在界面上是两句话：一句是「登录
  /// 失效了」，另一句是「这个账号刚在另一台手机上登录了」——后者用户看一眼就知道
  /// 发生了什么，前者只会让人以为出了毛病。重试一万次也是同一堵墙。
  case sessionReplaced(DeviceKind)
  public var errorDescription: String? {
    switch self {
    case .unavailable: "账号服务暂不可用"
    case .invalidURL: "账号服务地址无效"
    case .invalidResponse: "暂时无法读取，请重试"
    case .keychain: "暂时无法保存登录状态，请重试"
    case .credentialsUnavailable: "暂时读不到登录状态，稍后自动重试"
    case .storage: "未能保存，请检查设备空间"
    case .reauthenticationRequired: "登录已失效，请重新登录"
    case .sessionReplaced(let kind): "这个账号在另一台\(kind.label)上登录了"
    case .http(_, "invalid_username"): AccountCredentialRules.usernameRule
    case .http(_, "username_taken"): "用户名已被使用"
    case .http(_, "invalid_password"): AccountCredentialRules.passwordRule
    case .http(_, "wrong_password"): "密码不对"
    case .http(_, "search_range_too_short"): "找相似至少框选 16 根 K 线"
    case .http(_, "search_busy"): "正在处理上一次查找，请稍后再试"
    case .http(_, "export_too_large"): "数据太多，暂时导不出来"
    case .http(401, _): "登录已失效，请重新登录"
    case .http(429, _): "操作频繁，请稍后重试"
    case .http(409, _): "正在更新，本机内容已保留"
    case .http(_, _): "暂未成功，请稍后重试"
    }
  }
}
/// 用户名、密码的规则，和服务端 `auth.rs` 的 `email` / `password`、`share.rs` 的
/// `username` 一个口径。
///
/// 从前这两条只在服务端拒了之后才以错误的形式露面：人填完、点了、等一趟网络才知道
/// 用户名不能带点、密码要有数字。现在账号页和加朋友的输入框边输边拿它校验，不合格
/// 直接置灰，规则那一行小字只在不合格时出现。两边对同一份夹具
/// `Backend/kanpan-api/contract/account-credentials.json` 各跑一遍，谁改了规则另一边的
/// 测试就红。
public enum AccountCredentialRules {
  public static let usernameRule = "用户名需 3–32 位字母、数字或下划线"
  public static let passwordRule = "密码至少 8 位，需含字母和数字"
  /// 服务端会存下来的样子（去首尾空白、ASCII 小写）；不合规则时是 `nil`。
  public static func username(_ raw: String) -> String? {
    let v = raw.trimmingCharacters(in: .whitespacesAndNewlines)
    guard (3...32).contains(v.utf8.count), v.utf8.allSatisfy({ letter($0) || digit($0) || $0 == UInt8(ascii: "_") })
    else { return nil }
    return v.lowercased()
  }
  /// 注册、改新密码时收不收。下限按 Unicode 标量数（服务端 `chars().count()`，不是
  /// Swift 的字形数——一个全家福表情是 5 个标量），上限按 UTF-8 字节数。
  public static func acceptsPassword(_ v: String) -> Bool {
    v.unicodeScalars.count >= 8 && v.utf8.count <= 128
      && v.utf8.contains(where: letter) && v.utf8.contains(where: digit)
  }
  // 只认 ASCII：全角字母、带重音的字母服务端都不收（`is_ascii_alphanumeric`）。
  // UTF-8 里多字节字符的每个字节都 ≥ 0x80，按字节判不会把它们误认进来。
  private static func letter(_ b: UInt8) -> Bool { (0x41...0x5A).contains(b) || (0x61...0x7A).contains(b) }
  private static func digit(_ b: UInt8) -> Bool { (0x30...0x39).contains(b) }
}
/// A typed, Sendable JSON value used by the sync boundary, never raw Any dictionaries.
public enum JSONValue: Codable, Sendable, Equatable {
  case string(String), number(Double), bool(Bool), array([JSONValue]), object([String: JSONValue]), null
  public init(from decoder: any Decoder) throws {
    let c = try decoder.singleValueContainer()
    if c.decodeNil() { self = .null }
    else if let v = try? c.decode(Bool.self) { self = .bool(v) }
    else if let v = try? c.decode(String.self) { self = .string(v) }
    else if let v = try? c.decode(Double.self) { self = .number(v) }
    else if let v = try? c.decode([JSONValue].self) { self = .array(v) }
    else { self = .object(try c.decode([String: JSONValue].self)) }
  }
  public func encode(to encoder: any Encoder) throws {
    var c = encoder.singleValueContainer()
    switch self {
    case .string(let v): try c.encode(v)
    case .number(let v): try c.encode(v)
    case .bool(let v): try c.encode(v)
    case .array(let v): try c.encode(v)
    case .object(let v): try c.encode(v)
    case .null: try c.encodeNil()
    }
  }
  public static func encode<T: Encodable>(_ value: T) throws -> JSONValue { try JSONDecoder().decode(Self.self, from: JSONEncoder().encode(value)) }
  public func decode<T: Decodable>(_ type: T.Type = T.self) throws -> T { try JSONDecoder().decode(type, from: JSONEncoder().encode(self)) }
}
