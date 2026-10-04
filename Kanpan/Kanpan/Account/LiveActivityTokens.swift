import Foundation
import KanpanAccount

/// 「盯一个」那条实时活动在服务端的登记与收起，钉在档案的主人身上（审查 D-06）。
///
/// 以前这两趟请求不带 `owner:`：这一秒还是 A 的档案、下一秒客户端已经换成 B（换号、
/// 被顶下去重新登录），A 那条活动的令牌就带着 B 的令牌登记到了 B 的账号下——B 的锁屏开始
/// 收 A 盯的那只品种的推送；收起那一趟也会去关 B 名下同 id 的活动。和推送令牌、同步、
/// 收件箱一个规矩：客户端这一刻替的不是这个人就不出门（`AccountClient` 当场取消）。
struct LiveActivityTokens: Sendable {
  let api: AccountClient
  let owner: UUID

  /// 登记活动的推送令牌：服务端拿它按行情推锁屏更新（有 APNs 密钥时）。
  func submit(token: String, activityID: String, alertID: String, environment: String) async throws {
    let body: [String: String] = ["token": token, "kind": "liveActivity", "environment": environment,
                                  "activityId": activityID, "alertId": alertID]
    let data = try JSONSerialization.data(withJSONObject: body)
    _ = try await api.data("v1/devices/push-token", method: "POST", body: data, owner: owner)
  }
  /// 活动收起：服务端停止给它推更新、丢掉令牌。
  func end(activityID: String) async throws {
    let data = try JSONSerialization.data(withJSONObject: ["activityId": activityID])
    _ = try await api.data("v1/devices/live-activity/end", method: "POST", body: data, owner: owner)
  }
}
