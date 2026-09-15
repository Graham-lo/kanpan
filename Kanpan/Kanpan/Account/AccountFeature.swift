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
      catch AccountError.http(401, _) where current == .changePassword || current == .close { error = "密码不对" }
      catch { self.error = error.localizedDescription }
    }
  }
  private func accept(_ value: AccountTokens) async throws {
    guard let client else { throw AccountError.unavailable }
    let apply = try onPrepareAccount?(value.user)
    try await client.accept(value, device: device)
    apply?()
    user = value.user; email = value.user.email; password = ""; newPassword = ""; code = ""
    page = .account; presented = false; notice = "已登录"; onSynchronize?()
  }
  func logout() async {
    guard !busy || page == .close else { return }
    do {
      let apply = try onPrepareAccount?(nil)
      try await client?.signOut()
      apply?()
      // Personal views are removed immediately; network revocation may finish later.
      user = nil; presented = false; password = ""; newPassword = ""; devices = []
    } catch { self.error = error.localizedDescription }
  }
  func loadDevices() async {
    guard let client else { return }
    do { devices = try await client.request("v1/auth/devices", as: AccountDevices.self).devices }
    catch { self.error = error.localizedDescription }
  }
  func revoke(_ item: AccountSessionDevice) {
    guard let client else { return }
    Task {
      do {
        let _: AccountOK = try await client.request("v1/auth/devices/" + item.id.uuidString, method: "DELETE")
        if item.current { await logout() } else { await loadDevices() }
      } catch { self.error = error.localizedDescription }
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
