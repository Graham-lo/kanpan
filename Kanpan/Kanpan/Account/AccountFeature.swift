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
  var error: String?
  var busy = false
  /// 「导出我的数据」正在路上（`AccountExport.swift`）。
  var exporting = false
  var devices: [AccountSessionDevice] = []
  private(set) var user: AccountUser?
  private(set) var device = AccountDevice(name: UIDevice.current.model, kind: .current)
  private(set) var client: AccountClient?
  private var attempt = UUID()
  /// 「这台机器上现在是谁」的版本号。主动登录、退出登录各抬一次。
  ///
  /// 冷启动那一下的 `restore()` 要跨两次 actor 往返（读凭据里的用户、设备）。这中间
  /// 用户要是已经点了退出、或者登上了另一个号，restore 回来时拿着的还是旧的那个人，
  /// 从前它照样 `onPrepareAccount(旧人)` 把旧档案装回去——刚退出的人又被登回来，
  /// 刚登上的 B 被 A 的档案盖掉（审查 B.10 BT-22）。号对不上就说明这次 restore 已经
  /// 过时，什么都不装。
  @ObservationIgnored private var generation = 0
  @ObservationIgnored var onPrepareAccount: ((AccountUser?) throws -> (@MainActor () -> Void))?
  @ObservationIgnored var onSynchronize: (() -> Void)?
  @ObservationIgnored var onAutoSync: ((Bool) -> Void)?
  /// 上一次装进来的是哪个登录的人（`AccountFiles.lastOwner`，只有身份没有令牌）。
  /// 钥匙串读不动时靠它把那个人的本地档案照常装上。
  @ObservationIgnored var lastOwner: (() -> AccountUser?)?
  /// 钥匙串读不动、凭据还欠着（见 `AccountClient.credentialsUnavailable`）。
  ///
  /// 这时手上装的是上次那个人的本地档案——自选、画线、提醒都在——只是同步先停着，
  /// 钥匙串读得到了就自己接上。它**不是**「登录失效」：不摆重新登录那条路，
  /// 本机档案一个字都不动。
  private(set) var credentialsPending = false
  /// 凭据欠着时那条「稍后再读一次」的任务。退避 2s → 60s 封顶；设备解锁
  /// （`protectedDataDidBecomeAvailable`）时当场再读一次。
  @ObservationIgnored private var credentialRetry: Task<Void, Never>?
  @ObservationIgnored private var unlockObserver: (any NSObjectProtocol)?
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
  /// 被顶下去时那一句话：「这个账号在另一台手机／平板／电脑上登录了」。
  ///
  /// 一个账号每一类设备只许一台在线（服务端 `auth.rs`）。这和「登录失效」是两回事：
  /// 失效只说得出「再签一次名」，被顶下去说得出**是什么把你顶掉的**——用户看一眼
  /// 就知道发生了什么，不会以为 app 坏了。本机档案一个字都不动。
  private(set) var replacedNotice: String?

  /// 测试用：直接给一个客户端（假服务器、假钥匙串）。产品走下面那个无参的。
  init(client: AccountClient?) { self.client = client }
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
    let started = generation
    let saved = await client.savedUser()
    guard generation == started else { return }
    guard let saved else {
      // 钥匙串读不动（锁屏被后台拉起之类）：不当成「没登录」。按上次那个人把本地档案
      // 装上，同步停着，稍后再读（审查 17）。真的没登录过的人 `credentialsUnavailable`
      // 是 false，照旧直接返回。
      if await client.credentialsUnavailable, generation == started { holdLastOwner(started: started) }
      return
    }
    await adopt(saved, started: started)
  }
  /// 把钥匙串里读到的那个人装上。`restore()` 与「凭据欠着之后终于读到了」共用。
  private func adopt(_ saved: AccountUser, started: Int) async {
    guard let client else { return }
    let savedDevice = await client.savedDevice()
    // 两次 `await` 之间用户可能已经退出或换了号：这次 restore 作废，一样都不装。
    guard generation == started else { return }
    do {
      if let d = savedDevice { device = d }
      let apply = try onPrepareAccount?(saved); apply?()
      user = saved; email = saved.email
      onSynchronize?()
    } catch { self.error = error.localizedDescription }
  }
  /// 凭据欠着：先按上次那个人装档案，再排一次「稍后再读」。
  private func holdLastOwner(started: Int) {
    credentialsPending = true
    if user == nil, let owner = lastOwner?() {
      do {
        let apply = try onPrepareAccount?(owner); apply?()
        user = owner; email = owner.email
      } catch { self.error = error.localizedDescription }
    }
    scheduleCredentialRetry(started: started)
  }
  private func scheduleCredentialRetry(started: Int) {
    guard credentialRetry == nil else { return }
    if unlockObserver == nil {
      unlockObserver = NotificationCenter.default.addObserver(
        forName: UIApplication.protectedDataDidBecomeAvailableNotification, object: nil, queue: .main
      ) { [weak self] _ in MainActor.assumeIsolated { self?.retryCredentialsNow() } }
    }
    credentialRetry = Task { [weak self] in
      var delay = 2.0
      while !Task.isCancelled {
        try? await Task.sleep(for: .seconds(delay))
        guard !Task.isCancelled, let self else { return }
        if await self.retryCredentials(started: started) { return }
        delay = min(delay * 2, 60)
      }
    }
  }
  /// 设备解锁那一下：不等退避，当场再读一次。
  func retryCredentialsNow() {
    guard credentialsPending else { return }
    Task { await resumeCredentials() }
  }
  /// 按当前这一代再读一次钥匙串（解锁通知、单测走这儿）。
  func resumeCredentials() async { await retryCredentials(started: generation) }
  /// 再读一次钥匙串。读到了返回 `true`（任务收工），还读不动返回 `false`。
  @discardableResult private func retryCredentials(started: Int) async -> Bool {
    guard let client, credentialsPending, generation == started else { return true }
    guard await client.retryCredentials() else { return false }
    guard generation == started, credentialsPending else { return true }
    endCredentialWait()
    if let saved = await client.savedUser() {
      guard generation == started else { return true }
      if saved.id == user?.id {
        // 档案早就是这个人的，只差凭据：补上设备信息，同步接上。
        if let d = await client.savedDevice() { device = d }
        onSynchronize?()
      } else {
        await adopt(saved, started: started)
      }
    } else if user != nil {
      // 钥匙串这回答的是「里面没有」：凭据真的没了。档案照旧摆着，摆一条重新登录的路。
      needsReauthentication = true
    }
    return true
  }
  private func endCredentialWait() {
    credentialsPending = false
    credentialRetry?.cancel(); credentialRetry = nil
    if let unlockObserver { NotificationCenter.default.removeObserver(unlockObserver) }
    unlockObserver = nil
  }
  func open() { error = nil; password = ""; newPassword = ""; page = user == nil ? .login : .account; presented = true }
  func move(_ page: Page) { self.page = page; error = nil; password = ""; newPassword = "" }
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
          password = ""; newPassword = ""; page = .account
        case .close:
          struct Input: Encodable { var password: String }
          let _: AccountOK = try await client.request("v1/auth/account", method: "DELETE", body: JSONEncoder().encode(Input(password: password)))
          await logout()
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
  /// 登录 / 注册拿到令牌之后的那一步。不是 `private`：BT-22 的用例要从这儿摆
  /// 「restore 还挂着、登录先完成」的时序（`submit` 只是在它前面多一趟 HTTP）。
  func accept(_ value: AccountTokens) async throws {
    guard let client else { throw AccountError.unavailable }
    generation &+= 1
    let apply = try onPrepareAccount?(value.user)
    try await client.accept(value, device: device)
    apply?()
    user = value.user; email = value.user.email; password = ""; newPassword = ""
    needsReauthentication = false; replacedNotice = nil; endCredentialWait()
    page = .account; presented = false; onSynchronize?()
    Haptics.success()
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
    generation &+= 1
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
    needsReauthentication = false; replacedNotice = nil; endCredentialWait()
    do { let apply = try onPrepareAccount?(nil); apply?() }
    catch { failure = failure ?? error }
    if let failure { error = failure.localizedDescription }
  }
  /// 同步那边报上来的错误统一从这儿进：把「该重新登录了」这一种单独挑出来。
  func report(sync error: any Error) {
    lost(error)
    syncStatus = error.localizedDescription
  }
  /// 「这条会话还算不算数」这一问，两个入口（同步、账号页）给的是同一个答案。
  private func lost(_ error: any Error) {
    switch error {
    case AccountError.reauthenticationRequired: needsReauthentication = true
    case AccountError.sessionReplaced: needsReauthentication = true; replacedNotice = error.localizedDescription
    default: break
    }
  }
  /// 把登录页摆到用户面前（会话失效之后那条路）。账号还在、档案还在，只是要再签一次名。
  func reauthenticate() {
    error = nil; password = ""; newPassword = ""
    email = user?.email ?? email
    page = .login; presented = true
  }
  /// 账号页上的错误统一从这儿进（同 `report(sync:)`，只是摆在另一处）。
  private func note(_ error: any Error) {
    lost(error)
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
extension DeviceKind {
  /// 这台机器算哪一类。判断留在 app 壳层：`KanpanAccount` 是个不碰 UIKit 的包，
  /// 把 `UIDevice` 搬进去就把它钉死在 iOS 上了。
  ///
  /// 「iPad 上跑的 iPhone 版」（兼容模式）报的 idiom 就是 `.phone`，那也正是它该占的
  /// 名额——服务端按报上来的类别算，界面上也确实是一部手机的样子。
  /// `UIDevice.current` 是主线程隔离的，这儿不标 `@MainActor` 就是两条并发警告
  /// （审查 C：零警告）。唯一的调用方是 `AccountFeature.device` 的初值，那个类本来
  /// 就整个挂在主线程上，标上去不影响任何人。
  @MainActor static var current: DeviceKind {
    #if DEBUG
      // 测试后门（P4.5）：同一账号每类设备只准一台在线，两台 iPhone 模拟器同时登录
      // 必然顶掉一台。跨设备并发用例让第二台自报「平板」，规则本身不动。正式包没有这一行。
      if let raw = ProcessInfo.processInfo.environment["KANPAN_TEST_DEVICE_KIND"],
         let kind = DeviceKind(rawValue: raw) { return kind }
    #endif
    if ProcessInfo.processInfo.isiOSAppOnMac { return .desktop }
    switch UIDevice.current.userInterfaceIdiom {
    case .pad: return .tablet
    case .mac: return .desktop
    default: return .phone
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
