import UIKit
import UserNotifications

// ---------------------------------------------------------------- 远程推送

/// APNs 那一半：**现在整条是哑的，而且必须哑得不碍事**。
///
/// 这个账号还没开 Apple 开发者会员，工程里既没有 Push Notifications capability，
/// 也没有 `aps-environment` 这条 entitlement——加了真机根本装不上。
/// 所以 `registerForRemoteNotifications()` 注册必然失败，系统会回
/// `didFailToRegisterForRemoteNotificationsWithError`，这儿静静收下就完了。
///
/// 会员开通、capability 打开之后，这条路自己就通了：系统改回调
/// `didRegisterForRemoteNotificationsWithDeviceToken`，token 经 `arrived(_:)`
/// 交给账号桥 `POST /v1/devices/push-token`，一行都不用改。
@MainActor
enum PushRegistration {
  /// 拿到的那串 token（十六进制）。没拿到就是 nil，**nil 不是错误**。
  private(set) static var token: String?
  /// 有人等着它。账号桥登记在这儿：token 来了就上传。
  static var onToken: ((String) -> Void)?

  /// 沙盒还是生产。Debug 包连沙盒 APNs，Release 连生产。
  static var environment: String {
    #if DEBUG
    return "sandbox"
    #else
    return "production"
    #endif
  }

  /// 跟系统要一次 token。没权限时不叫——那一下必然失败，白费一次。
  static func start() {
    UIApplication.shared.registerForRemoteNotifications()
  }

  /// 有权限就要一次 token。启动时叫，幂等。
  ///
  /// 权限自己问（而不是借 `AlertNotifications.isAuthorized()`）：这一整块要能脱开提醒
  /// 模块单独编——`Main/OrientationBridge.swift` 的两条 delegate 回调引用它，
  /// 主界面那个测试壳（`Kanpan/KanpanTests`）里只软链得到这一个文件。
  static func startIfAuthorized() {
    Task {
      let settings = await UNUserNotificationCenter.current().notificationSettings()
      switch settings.authorizationStatus {
      case .authorized, .provisional: await MainActor.run { start() }
      default: return
      }
    }
  }

  static func arrived(_ data: Data) {
    let hex = data.map { String(format: "%02x", $0) }.joined()
    guard !hex.isEmpty, hex != token else { return }
    token = hex
    onToken?(hex)
  }

  static func failed(_ error: any Error) {
    token = nil
  }
}

/// 推送 token「报给谁了」的账本（审查 17）。
///
/// token 是**设备**的，服务端却按**账号**收（`POST /v1/devices/push-token` 要登录）。
/// 从前 token 一来就报一次，没登录就 `return`、网络失败就 `try?` 吞掉——而 `arrived`
/// 对同一串 token 只响一次，于是「先开 app、后登录」的人、以及报的那一下正好断网的人，
/// 这台设备的 token 永远到不了服务端。账本记下「哪个 token 已经报给了哪个账号」，
/// 每次同步（登录、恢复会话、回前台都会走到）问它一句还欠不欠。
///
/// 没有 APNs 密钥时这条路照样跑：token 根本不会来（`PushRegistration.token == nil`），
/// `due` 永远答 nil，一个请求都不发；服务端收 token 也不依赖密钥（密钥只管往外推）。
struct PushTokenLedger: Equatable {
  private struct Entry: Equatable { var token: String; var owner: UUID }
  private var sent: Entry?
  private var inFlight: Entry?

  /// 现在该报哪一串。没 token、没登录、已报过、正在报，都答 nil。
  func due(token: String?, owner: UUID?) -> String? {
    guard let token, let owner else { return nil }
    let entry = Entry(token: token, owner: owner)
    return entry == sent || entry == inFlight ? nil : token
  }
  mutating func begin(token: String, owner: UUID) { inFlight = Entry(token: token, owner: owner) }
  /// 那一趟回来了。`ok == false`（断网、5xx）就当没报过，下次同步再报。
  mutating func finish(token: String, owner: UUID, ok: Bool) {
    let entry = Entry(token: token, owner: owner)
    guard inFlight == entry else { return }
    inFlight = nil
    if ok { sent = entry }
  }
}
