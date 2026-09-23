import Foundation
import KanpanAccount

struct ShareClient: Sendable {
  let api: AccountClient
  struct Page: Decodable, Sendable { var items: [ShareItem]; var cursor: String }
  private struct Sent: Decodable, Sendable { var id: String }
  private struct OK: Decodable, Sendable { var ok: Bool }
  func friends() async throws -> [ShareFriend] { try await api.request("v1/friends") }
  func remove(_ username: String) async throws {
    let _: OK = try await api.request("v1/friends/" + username, method: "DELETE")
  }
  func send(_ body: ShareOutbound) async throws -> String {
    let sent: Sent = try await api.request("v1/shares", method: "POST", body: JSONEncoder().encode(body))
    return sent.id
  }
  func upload(_ image: Data, id: String) async throws {
    _ = try await api.data("v1/shares/\(id)/shot", method: "PUT", body: image, contentType: "image/jpeg")
  }
  func shot(_ id: String) async throws -> Data { try await api.data("v1/shares/\(id)/shot") }
  func inbox(after: String?) async throws -> Page {
    let query = after.map { "?after=" + ($0.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? "") } ?? ""
    return try await api.request("v1/shares/inbox" + query)
  }
  func mark(_ id: String, kept: Bool) async throws {
    let _: OK = try await api.request("v1/shares/\(id)/" + (kept ? "kept" : "opened"), method: "POST")
  }
  static func message(_ error: Error) -> String {
    if let value = error as? AccountError {
      switch value {
      case .http(404, "no_such_user"): return "没有这个用户名"
      case .http(400, "cannot_send_self"): return "不能发给自己"
      case .http(400, "invalid_username"): return "请填写朋友的用户名"
      case .http(400, "invalid_reply_to"): return "这封已经回不了了"
      case .http(429, _): return "发得有点快，稍后再试"
      default: return value.localizedDescription
      }
    }
    return "暂时连不上，请重试"
  }
}
