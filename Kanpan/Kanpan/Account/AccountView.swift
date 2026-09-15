import SwiftUI
import KanpanAccount

struct AccountView: View {
  @Bindable var feature: AccountFeature
  @Environment(\.panelTheme) private var theme
  @FocusState private var focused: Field?
  private enum Field { case email, password, newPassword, code }
  var body: some View {
    NavigationStack {
      Group {
        switch feature.page {
        case .account: account
        case .sync: sync
        case .devices: deviceList
        default: form
        }
      }
      .navigationTitle(title).navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .cancellationAction) {
          Button(feature.page == .account || feature.page == .login ? "完成" : "返回") {
            focused = nil
            if feature.page == .account || feature.page == .login { feature.presented = false }
            else { feature.move(feature.user == nil ? .login : .account) }
          }.disabled(feature.busy)
        }
      }
    }.tint(theme.amber)
      .interactiveDismissDisabled(feature.busy)
      .accessibilityIdentifier("account.view")
  }
  private var title: String {
    switch feature.page {
    case .account: "账号"; case .login: "登录"; case .register: "注册"
    case .sync: "同步"; case .devices: "登录设备"
    case .changePassword: "修改密码"; case .close: "注销账号"
    }
  }
  private var form: some View {
    ScrollView {
      VStack(spacing: 18) {
        if [.login, .register].contains(feature.page) {
          input("用户名", field: .email) {
            TextField("用户名", text: $feature.email).keyboardType(.asciiCapable)
              .textContentType(.username).textInputAutocapitalization(.never).autocorrectionDisabled()
              .focused($focused, equals: .email).submitLabel(.next).onSubmit { focused = .password }
              .accessibilityIdentifier("account.email")
          }
        }
        if [.login, .register, .changePassword, .close].contains(feature.page) {
          input(feature.page == .changePassword ? "当前密码" : "密码", field: .password) {
            SecureField("密码", text: $feature.password)
              .textContentType(feature.page == .register ? .newPassword : .password)
              .focused($focused, equals: .password).submitLabel(.go)
              .onSubmit { feature.submit() }.accessibilityIdentifier("account.password")
          }
        }
        if [.changePassword].contains(feature.page) {
          input("新密码", field: .newPassword) {
            SecureField("新密码", text: $feature.newPassword).textContentType(.newPassword)
              .focused($focused, equals: .newPassword).submitLabel(.go).onSubmit { feature.submit() }
              .accessibilityIdentifier("account.newPassword")
          }
        }
        if feature.page == .close { Text("注销后云端数据将删除").font(.footnote).foregroundStyle(.secondary).frame(maxWidth: .infinity, alignment: .leading) }
        if let error = feature.error { Text(error).font(.footnote).foregroundStyle(.orange).frame(maxWidth: .infinity, alignment: .leading).accessibilityIdentifier("account.error") }
        Button { focused = nil; feature.submit() } label: {
          Group { if feature.busy { ProgressView().tint(.white) } else { Text(primary) } }.frame(maxWidth: .infinity, minHeight: 48)
        }.buttonStyle(.borderedProminent).tint(feature.page == .close ? .red : theme.amber)
          .disabled(feature.busy).accessibilityIdentifier("account.submit")
        if feature.page == .login {
          HStack {
            Spacer(); Button("注册") { feature.move(.register) }.frame(minHeight: 44)
          }.font(.subheadline)
        } else if feature.page == .register {
          Button("已有账号，登录") { feature.move(.login) }.frame(minHeight: 44)
        }
      }.padding(20)
    }.scrollDismissesKeyboard(.interactively)
  }
  private var primary: String {
    switch feature.page { case .changePassword: "保存"; default: title }
  }
  private func input<Content: View>(_ title: String, field: Field, @ViewBuilder content: () -> Content) -> some View {
    VStack(alignment: .leading, spacing: 8) {
      Text(title).font(.subheadline).foregroundStyle(.secondary)
      content().padding(.horizontal, 12).frame(minHeight: 48)
        .background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 10))
    }
  }
  private var account: some View {
    List {
      Section { LabeledContent("用户名", value: feature.user?.email ?? "") }
      Section {
        row("同步") { feature.move(.sync) }
        row("登录设备") { feature.move(.devices) }
        row("修改密码") { feature.move(.changePassword) }
      }
      Section { Button("退出登录", role: .destructive) { Task { await feature.logout() } } }
      Section { Button("注销账号", role: .destructive) { feature.move(.close) } }
    }
  }
  private var sync: some View {
    List {
      Section {
        Toggle("自动同步", isOn: Binding(get: { feature.autoSync }, set: { feature.onAutoSync?($0) }))
        LabeledContent("上次同步") { if let last = feature.lastSync { Text(last, style: .relative) } else { Text("尚未同步") } }
        if !feature.syncStatus.isEmpty { Text(feature.syncStatus).foregroundStyle(.secondary) }
        if feature.pending > 0 { LabeledContent("待同步", value: "\(feature.pending) 项") }
      }
      Section { Button("立即同步") { feature.onSynchronize?() } }
    }
  }
  private var deviceList: some View {
    List {
      ForEach(feature.devices) { item in
        HStack {
          VStack(alignment: .leading) { Text(item.name); Text(item.current ? "本机" : Date(timeIntervalSince1970: Double(item.lastSeen) / 1000).formatted(date: .abbreviated, time: .shortened)).font(.caption).foregroundStyle(.secondary) }
          Spacer(); Button("退出", role: .destructive) { feature.revoke(item) }.frame(minHeight: 44)
        }
      }
      if let error = feature.error { Text(error).foregroundStyle(.orange) }
    }.task { await feature.loadDevices() }.refreshable { await feature.loadDevices() }
  }
  private func row(_ title: String, action: @escaping () -> Void) -> some View {
    Button(action: action) { HStack { Text(title); Spacer(); Image(systemName: "chevron.right").foregroundStyle(.tertiary) } }.foregroundStyle(.primary)
  }
}
