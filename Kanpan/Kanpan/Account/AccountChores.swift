import Foundation
import KanpanCore
import KanpanAccount
import ReviewData
import ReviewUI

/// 账号桥上那几件和「同步存档」本身无关、但都钉在档案主人身上的杂务：
/// 推送令牌、实时活动令牌、品种上新 / 下架通知、分享收件箱、访客认领收尾、默认自选播种。
///
/// 从 `AppAccountBridge` 原样搬出来（2026-10-10 拆分）。每一件都只读 `ActiveProfile`
/// 此刻的主人 / 代次，不碰同步存档的记账与应用。
@MainActor final class AccountChores {
  private let profile: ActiveProfile
  private let files: AccountFiles
  private let account: AccountFeature
  private let prefs: PrefsStore
  private let symbols: SymbolPickerModel
  private let inbox: ShareInbox
  private let review: ReviewFeature

  /// 访客认领收尾之后刷新账号页状态（`SyncLifecycle.updateStatus`）。
  var updateStatus: () -> Void = {}
  /// 默认自选真的加进去了：宿主重新兑现落地页（`AppAccountBridge.onProfileReady`）。
  var onProfileReady: () -> Void = {}

  /// 推送 token 报给过谁（见 `PushTokenLedger`）。
  private var pushLedger = PushTokenLedger()

  init(profile: ActiveProfile, files: AccountFiles, account: AccountFeature, prefs: PrefsStore,
       symbols: SymbolPickerModel, inbox: ShareInbox, review: ReviewFeature) {
    self.profile = profile; self.files = files; self.account = account; self.prefs = prefs
    self.symbols = symbols; self.inbox = inbox; self.review = review
  }

  /// 复盘同步跑完一轮：访客那批认领的东西都推上去了（同步队列空、复盘没有待传），
  /// 就把访客批次了结掉，再刷新状态。接在 `review.onSyncComplete` 上。
  func reviewSyncCompleted() {
    do {
      if let owner = profile.owner, let batch = try files.pendingGuest(user: owner), profile.sync?.archive.operations.isEmpty == true, review.pendingUploads == 0 {
        try files.completeGuestClaim(user: owner, batch: batch.id)
      }
      updateStatus()
    } catch { account.report(sync: error) }
  }

  /// 访客和账号都给同一份默认自选（只补缺的），什么时候给、给过没有都在
  /// `DefaultFavoritesSeeder` 里（方案第 3 节第四件，2026-10-07 改口径）。
  /// 代次拿来防「取榜那几秒里账号档案回来了」——那时这一趟当场作废。
  ///
  /// 由 `AccountProfileSwitcher` 的提交那一段在 `onProfileReady()` 之后调，代次就在那一刻取。
  func seedDefaultFavorites(for user: UUID?) {
    let seedEpoch = profile.epoch
    DefaultFavoritesSeeder.consider(symbols: symbols,
                                    profileKey: user?.uuidString ?? DefaultFavoritesSeeder.guestProfile,
                                    stillCurrent: { [weak self] in self?.profile.epoch == seedEpoch },
                                    done: { [weak self] in self?.onProfileReady() })
  }

  /// 分享不是个人同步：只在登录 / 前台拉取入口挂一次（`AppAccountBridge.synchronize`）。
  func pullInbox() { inbox.pull() }

  /// 设置里开着「品种上新与停牌下架」就去拉一次服务端记下的品种状态通知（`ListingNotices`）。
  /// 回前台（`synchronize`）和每一轮同步跑完都叫；两次太近的那次由 `ListingNotices` 自己挡掉。
  func pullListingNotices() {
    guard prefs.prefs.notifyListingChanges, let api = account.client, let owner = profile.owner else { return }
    ListingNotices.pull(api: api, owner: owner, sound: prefs.prefs.alertSound)
  }

  /// 把这台设备的推送 token 交给服务端。
  ///
  /// 失败**不报给用户**：没有推送只是「提醒要等下一次打开 app 才看得见」，
  /// 不是故障（`kanpan-no-engineering-status-fields`）。没登录时连发都不发——
  /// 这个接口按人存 token。
  /// 这台设备的推送 token 还欠不欠某个账号一次上报（见 `PushTokenLedger`）。
  /// token 来的时候、以及每次同步都问一遍：没登录时来的 token，登录后补报；
  /// 报的那一下失败了，下一次同步再报。
  func submitPushToken() {
    guard let api = account.client, let owner = profile.owner,
          let token = pushLedger.due(token: PushRegistration.token, owner: owner) else { return }
    // 复盘到点走推送时（`ReviewDueReminders.channel == .remote`）另登记一条 `reviewDue` 类：
    // 服务端只把复盘到点推给这一类（迁移 0023），走本机日历通知的设备不登记，就收不到第二条。
    let kinds = ReviewDueReminders.channel == .remote ? ["alerts", "reviewDue"] : ["alerts"]
    let bodies = kinds.compactMap { kind in
      try? JSONSerialization.data(withJSONObject: ["token": token, "kind": kind, "environment": PushRegistration.environment])
    }
    guard bodies.count == kinds.count else { return }
    pushLedger.begin(token: token, owner: owner)
    Task { [weak self] in
      var ok = true
      for data in bodies where ok {
        ok = (try? await api.data("v1/devices/push-token", method: "POST", body: data, owner: owner)) != nil
      }
      self?.pushLedger.finish(token: token, owner: owner, ok: ok)
    }
  }
  /// 「盯一个」那条实时活动的推送令牌：服务端拿它按行情推锁屏更新（有 APNs 密钥时）。
  /// 钉在档案主人身上（`LiveActivityTokens`，审查 D-06）：换了人就不出门。
  func submitActivityToken(_ token: String, activityID: String, alertID: String) {
    guard let api = account.client, let owner = profile.owner else { return }
    let tokens = LiveActivityTokens(api: api, owner: owner), environment = PushRegistration.environment
    Task { try? await tokens.submit(token: token, activityID: activityID, alertID: alertID, environment: environment) }
  }
  /// 活动收起：服务端停止给它推更新、丢掉令牌。
  func endActivity(_ activityID: String) {
    guard let api = account.client, let owner = profile.owner else { return }
    let tokens = LiveActivityTokens(api: api, owner: owner)
    Task { try? await tokens.end(activityID: activityID) }
  }
}
