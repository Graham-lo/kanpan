import Foundation
import KanpanAccount

struct ShareClient: Sendable {
  let api: AccountClient
  /// 这个客户端替谁发（收件箱按人落盘）。给了就钉住：换号之后在途的那一趟不会带着
  /// 新人的令牌出门、把 B 的收件箱写进 A 的缓存（`AccountClient.data(owner:)` 当场取消）。
  /// `nil` = 不钉，发给朋友这类「现在是谁就替谁发」的一次性动作用。
  var owner: UUID? = nil
  struct Page: Decodable, Sendable { var items: [ShareItem]; var cursor: String }
  private struct Sent: Decodable, Sendable { var id: String }
  private struct OK: Decodable, Sendable { var ok: Bool }
  func friends() async throws -> [ShareFriend] { try await api.request("v1/friends", owner: owner) }
  /// 朋友页的「加朋友」：只记进自己的朋友表（服务端 `share.rs` `add_friend`）。
  func add(_ username: String) async throws {
    struct Body: Encodable { var username: String }
    let _: ShareFriend = try await api.request("v1/friends", method: "POST", body: JSONEncoder().encode(Body(username: username)), owner: owner)
  }
  func remove(_ username: String) async throws {
    let _: OK = try await api.request("v1/friends/" + username, method: "DELETE", owner: owner)
  }
  func send(_ body: ShareOutbound) async throws -> String {
    let sent: Sent = try await api.request("v1/shares", method: "POST", body: JSONEncoder().encode(body), owner: owner)
    return sent.id
  }
  func upload(_ image: Data, id: String) async throws {
    _ = try await api.data("v1/shares/\(id)/shot", method: "PUT", body: image, contentType: "image/jpeg", owner: owner)
  }
  func shot(_ id: String) async throws -> Data { try await api.data("v1/shares/\(id)/shot", owner: owner) }
  func inbox(after: String?) async throws -> Page {
    let query = after.map { "?after=" + ($0.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? "") } ?? ""
    return try await api.request("v1/shares/inbox" + query, owner: owner)
  }
  func mark(_ id: String, kept: Bool) async throws {
    let _: OK = try await api.request("v1/shares/\(id)/" + (kept ? "kept" : "opened"), method: "POST", owner: owner)
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
