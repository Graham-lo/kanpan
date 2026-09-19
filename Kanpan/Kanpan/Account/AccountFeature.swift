import SwiftUI
import Observation
import KanpanAccount

@MainActor @Observable final class AccountFeature {
  enum Page: String { case account, login, register, sync, devices, changePassword, close }
  var page: Page = .login
  var presented = false
  var email = ""
  var password = ""
  var newPassword = ""
  var code = ""
  var error: String?
  var notice: String?
  var busy = false
  var resendAt = Date.distantPast
  var devices: [AccountSessionDevice] = []
  private(set) var user: AccountUser?
  private(set) var device = AccountDevice(name: UIDevice.current.model)
  private(set) var client: AccountClient?
  private var challenge: AccountChallenge?
  private var attempt = UUID()
  @ObservationIgnored var onPrepareAccount: ((AccountUser?) throws -> (@MainActor () -> Void))?
  @ObservationIgnored var onSynchronize: (() -> Void)?
  @ObservationIgnored var onAutoSync: ((Bool) -> Void)?
  var autoSync = true
  var syncStatus = ""
  var lastSync: Date?
  var pending = 0
  /// 服务端**明确拒过**这条会话（刷新令牌换回 401，见 `AccountClient.accessToken`）。
  ///
  /// 和「同步失败」不是一回事：断网、超时、服务端 502 都只是这一趟没成，下一趟照常
  /// 重试；只有这一种是「再试一万次也是同一堵墙」，界面上必须摆一条重新登录的路，
  /// 否则用户看到的就是一个永远停在「同步失败」、点什么都没用的账号页。
  /// 本机档案一个字都不动——云端只是同步通道，掉线不等于退登。
  private(set) var needsReauthentication = false

  init() {
    // Shipping endpoint is supplied by the app build, never typed into the product UI.
    let configured = Bundle.main.object(forInfoDictionaryKey: "KanpanAccountAPIURL") as? String
    #if DEBUG
    let address = ProcessInfo.processInfo.environment["KANPAN_ACCOUNT_API_URL"] ?? configured
    #else
    let address = configured
    #endif
    if let address, let url = URL(string: address), !address.isEmpty {
      do {
        var service = "kanpan.account"
        #if DEBUG
        if ProcessInfo.processInfo.environment["KANPAN_TEST_PROFILE"] == "1" {
          service += ".test." + (ProcessInfo.processInfo.environment["KANPAN_PERSISTENCE_PROFILE"] ?? "normal")
        }
        #endif
        client = try AccountClient(baseURL: url, vault: KeychainCredentialVault(service: service))
      } catch { self.error = error.localizedDescription }
    }
  }
  func restore() async {
    guard let client else { return }
    if let saved = await client.savedUser() {
      do {
        if let d = await client.savedDevice() { device = d }
        let apply = try onPrepareAccount?(saved); apply?()
        user = saved; email = saved.email
        onSynchronize?()
      } catch { self.error = error.localizedDescription }
    }
  }
  func open() { error = nil; password = ""; newPassword = ""; code = ""; page = user == nil ? .login : .account; presented = true }
  func move(_ page: Page) { self.page = page; error = nil; password = ""; newPassword = ""; code = "" }
  func submit() {
    guard !busy else { return }
    guard let client else { error = AccountError.unavailable.localizedDescription; return }
    busy = true; error = nil; let id = UUID(); attempt = id
    let current = page
    Task {
      defer { if attempt == id { busy = false } }
      do {
        switch current {
        case .login, .register:
          struct Input: Encodable { var username: String; var password: String; var device: AccountDevice }
          let data = try JSONEncoder().encode(Input(username: email, password: password, device: device))
          let value: AccountTokens = try await client.request(current == .login ? "v1/auth/login" : "v1/auth/register", method: "POST", body: data, authenticated: false)
          try await accept(value)
        case .changePassword:
          struct Input: Encodable { var currentPassword: String; var newPassword: String }
          let _: AccountOK = try await client.request("v1/auth/password/change", method: "POST", body: JSONEncoder().encode(Input(currentPassword: password, newPassword: newPassword)))
          password = ""; newPassword = ""; page = .account; notice = "密码已修改"
        case .close:
          struct Input: Encodable { var password: String }
          let _: AccountOK = try await client.request("v1/auth/account", method: "DELETE", body: JSONEncoder().encode(Input(password: password)))
          await logout(); notice = "账号已注销"
        default: break
        }
      } catch AccountError.http(401, _) where current == .login { error = "用户名或密码不对" }
      // 改密码 / 注销那两页**不再**把 401 一律念成「密码不对」。服务端现在分得清：
      // 密码错是 `wrong_password`（`auth.rs`），会话过期 / 令牌失效才是
      // `authentication_failed`。一律念成密码不对的后果是用户对着正确的密码反复重输，
      // 而真正该做的是重新登录——那条路由 `needsReauthentication` 摆出来。
      catch { note(error) }
    }
  }
  private func accept(_ value: AccountTokens) async throws {
    guard let client else { throw AccountError.unavailable }
    let apply = try onPrepareAccount?(value.user)
    try await client.accept(value, device: device)
    apply?()
    user = value.user; email = value.user.email; password = ""; newPassword = ""; code = ""
    needsReauthentication = false
    page = .account; presented = false; notice = "已登录"; onSynchronize?()
  }
  /// 退出登录。
  ///
  /// 顺序是**先退干净、再装访客档案**，不能反过来。原来是 `onPrepareAccount(nil)`
  /// 打头：它要读访客目录里的 prefs / 自选 / 画线 / 复盘，任何一份解不开就整段抛出，
  /// 于是用户点了退出却还登着——钥匙串里那份凭据还在、服务端那条会话也还在，
  /// 而他以为自己已经走了。退登是个**只能前进**的动作：本机这一半（内存里的用户、
  /// 钥匙串、服务端会话）一定要走掉，装档案失败最多在账号页上留一句提示。
  func logout() async {
    guard !busy || page == .close else { return }
    var failure: (any Error)?
    // 钥匙串写失败也不把人留在登录态：`signOut` 里内存那一半已经先清了（A-02）。
    do { try await client?.signOut() } catch { failure = error }
    // 复盘从网页版带过来的那套老凭据（`kanpan.scorebook`）也在这儿走：它在这一版里
    // 已经没有读路径了，但钥匙串里那条还躺在老机器上——退登之后本机不该留着任何
    // 还能证明「这台机器上住过谁」的凭据。见 `LegacyKeychain`。
    LegacyKeychain.purge(service: LegacyKeychain.reviewService)
    // Personal views are removed immediately; network revocation may finish later.
    // `email`（登录页那个用户名输入框）也要清：不清的话下次打开登录页预填着上一个人的
    // 账号名，同一台设备换人用一眼就看见别人用的是什么号。
    user = nil; presented = false; email = ""; password = ""; newPassword = ""; devices = []
    needsReauthentication = false
    do { let apply = try onPrepareAccount?(nil); apply?() }
    catch { failure = failure ?? error }
    if let failure { error = failure.localizedDescription }
  }
  /// 同步那边报上来的错误统一从这儿进：把「该重新登录了」这一种单独挑出来。
  func report(sync error: any Error) {
    if case AccountError.reauthenticationRequired = error { needsReauthentication = true }
    syncStatus = error.localizedDescription
  }
  /// 把登录页摆到用户面前（会话失效之后那条路）。账号还在、档案还在，只是要再签一次名。
  func reauthenticate() {
    error = nil; password = ""; newPassword = ""; code = ""
    email = user?.email ?? email
    page = .login; presented = true
  }
  /// 账号页上的错误统一从这儿进（同 `report(sync:)`，只是摆在另一处）。
  private func note(_ error: any Error) {
    if case AccountError.reauthenticationRequired = error { needsReauthentication = true }
    self.error = error.localizedDescription
  }
  func loadDevices() async {
    guard let client else { return }
    do { devices = try await client.request("v1/auth/devices", as: AccountDevices.self).devices }
    catch { note(error) }
  }
  func revoke(_ item: AccountSessionDevice) {
    guard let client else { return }
    Task {
      do {
        let _: AccountOK = try await client.request("v1/auth/devices/" + item.id.uuidString, method: "DELETE")
        if item.current { await logout() } else { await loadDevices() }
      } catch { note(error) }
    }
  }
}
private struct AccountFeatureKey: EnvironmentKey { static let defaultValue: AccountFeature? = nil }
extension EnvironmentValues {
  var accountFeature: AccountFeature? {
    get { self[AccountFeatureKey.self] }
    set { self[AccountFeatureKey.self] = newValue }
  }
}
