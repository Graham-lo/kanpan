import Testing
import UserNotifications
@testable import Kanpan

/// 「通知关着」那一行什么时候出来（方案 2.3 的权限时机后半句）。
///
/// 判据一句话：**只有系统那边真的写着「拒」才出**。别的档各有各的不出的理由，
/// 一条一条钉在这儿，免得哪天顺手放宽成「不是 authorized 就提示」。
@Suite("提醒权限横幅")
struct AlertPermissionTests {
  @Test("拒过了：系统不会再问第二次，只能去设置里开——出")
  func deniedShowsTheRow() {
    #expect(AlertPermission.needsSystemSettings(.denied))
  }

  @Test("还没问过：下次点「加入提醒」系统自己会弹，这时候提设置是无中生有——不出")
  func notDeterminedStaysQuiet() {
    #expect(!AlertPermission.needsSystemSettings(.notDetermined))
  }

  @Test("给了权限：响得了——不出")
  func authorizedStaysQuiet() {
    #expect(!AlertPermission.needsSystemSettings(.authorized))
  }

  @Test("安静授权也是授权——不出")
  func provisionalStaysQuiet() {
    #expect(!AlertPermission.needsSystemSettings(.provisional))
  }

  @Test("临时授权（App Clip 那档）也能响——不出")
  func ephemeralStaysQuiet() {
    #expect(!AlertPermission.needsSystemSettings(.ephemeral))
  }

  @Test("没查之前不闪一行出来")
  @MainActor
  func startsHidden() {
    #expect(AlertPermission().needsSystemSettings == false)
  }
}
