import Foundation

public struct AccountUser: Codable, Sendable, Equatable, Identifiable {
  public var id: UUID
  public var email: String
  public init(id: UUID, email: String) { self.id = id; self.email = email }
}
public struct AccountDevice: Codable, Sendable, Equatable {
  public var id: UUID
  public var name: String
  public var secret: String
  public init(id: UUID = UUID(), name: String, secret: String = UUID().uuidString + UUID().uuidString) {
    self.id = id; self.name = name; self.secret = secret
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
}
public struct AccountChallenge: Codable, Sendable {
  public var challengeId: UUID
  public var resendAfter: Int
}
public struct AccountSessionDevice: Codable, Sendable, Identifiable {
  public var id: UUID
  public var name: String
  public var createdAt: Int64
  public var lastSeen: Int64
  public var current: Bool
}
public struct AccountDevices: Decodable, Sendable { public var devices: [AccountSessionDevice] }
public struct AccountOK: Decodable, Sendable { public var ok: Bool }
public enum AccountError: LocalizedError, Equatable {
  case unavailable, invalidURL, invalidResponse, keychain, storage, cancelled, http(Int, String)
  public var errorDescription: String? {
    switch self {
    case .unavailable: "账号服务暂不可用"
    case .invalidURL: "账号服务地址无效"
    case .invalidResponse: "暂时无法读取，请重试"
    case .keychain: "暂时无法保存登录状态，请重试"
    case .storage: "未能保存，请检查设备空间"
    case .cancelled: "操作已取消"
    case .http(_, "invalid_username"): "用户名需 3–32 位字母、数字或下划线"
    case .http(_, "username_taken"): "用户名已被使用"
    case .http(_, "invalid_password"): "密码至少 8 位，需含字母和数字"
    case .http(_, "invalid_code"): "验证码不对"
    case .http(_, "code_expired"): "验证码已失效，请重新发送"
    case .http(_, "email_unavailable"): "邮件暂时发不出，请稍后重试"
    case .http(_, "search_range_too_short"): "找相似至少框选 16 根 K 线"
    case .http(_, "search_busy"): "正在处理上一次查找，请稍后再试"
    case .http(401, _): "登录已失效，请重新登录"
    case .http(429, _): "操作频繁，请稍后重试"
    case .http(409, _): "正在更新，本机内容已保留"
    case .http(_, _): "暂未成功，请稍后重试"
    }
  }
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
