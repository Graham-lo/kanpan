import Foundation
import KanpanAccount

/// 账号桥各块共用的「此刻装着的这份档案」：谁的、哪个档案柜、哪份同步存档、第几代。
///
/// 以前这几样是 `AppAccountBridge` 一个类里的私有变量，换人、记账、应用远端、起停同步
/// 全在同一个类里读写它们。拆开之后各块（`AccountProfileSwitcher` / `SyncRecorder` /
/// `SyncApplier` / `SyncLifecycle` / `AccountChores`）拿的是**同一个**这份引用，
/// 读到的永远是当下这一刻的值——和从前读 `self.sync` / `self.owner` 逐字一样。
///
/// **只有 `AccountProfileSwitcher` 的提交那一段写它**（换属主那一刻），别的块只读；
/// 代次（`epoch`）与保护区（`gate`）也一样在那一刻换代。
@MainActor final class ActiveProfile {
  /// 档案主人；访客（没登录）是 `nil`。
  var owner: UUID?
  /// 这份档案的柜子（prefs.json / symbols.json / search.json）；还没 prepare 过是 `nil`。
  var personal: PersonalFileStorage?
  /// 这份档案的同步存档；没登录是 `nil`。
  var sync: SyncStore?
  /// 档案代次：换一次档案换一个。在途的同步、默认自选那一趟、同步完再拉收件箱那一下，
  /// 都拿它判自己还算不算数。
  var epoch = UUID()
  /// 「正在把云端那批装进本机」这段保护区，外加出了保护区才做的那些事（B6）。
  let gate = ApplyGate()

  init() {}
}
