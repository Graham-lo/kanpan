import KanpanChart
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
        // 不论是收起整张账号页还是退回上一层，出口都在左上角同一颗「‹」上（2026-09-15）。
        ToolbarItem(placement: .cancellationAction) {
          Button {
            focused = nil
            if feature.page == .account || feature.page == .login { feature.presented = false }
            else { feature.move(feature.user == nil ? .login : .account) }
          } label: {
            Label(feature.page == .account || feature.page == .login ? "关闭" : "返回",
                  systemImage: "chevron.left")
          }.disabled(feature.busy).accessibilityIdentifier("account.back")
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
              // 注册页不要报 `.newPassword`：那会拉起系统的「强密码」自动填充流程，
              // 这套账号是用户名 + 自定义口令，弹出来的密码面板不但用不上，还会把 app
              // 顶到后台、键入的字符只剩最后一个。统一按普通密码框处理。
              .textContentType(.password)
              .focused($focused, equals: .password).submitLabel(.go)
              .onSubmit { feature.submit() }.accessibilityIdentifier("account.password")
          }
        }
        if [.changePassword].contains(feature.page) {
          input("新密码", field: .newPassword) {
            SecureField("新密码", text: $feature.newPassword).textContentType(.password)
              .focused($focused, equals: .newPassword).submitLabel(.go).onSubmit { feature.submit() }
              .accessibilityIdentifier("account.newPassword")
          }
        }
        if feature.page == .close { Text("注销后云端数据将删除").font(.footnote).foregroundStyle(theme.ink3).frame(maxWidth: .infinity, alignment: .leading) }
        // 出错的字走跌色。原来写死了橙，那是上一版的品牌色，换了配色以后它是全页唯一
        // 一处跟谁都不像的颜色；错误本来就该跟「跌」同一支红。
        // 登录页上那一行字：这一趟出的错优先，没出错时摆「被顶下去」那一句
        // ——人是被顶回登录页来的，得让他看见为什么。
        if let message = feature.error ?? (feature.page == .login ? feature.replacedNotice : nil) {
          Text(message).font(.footnote).foregroundStyle(theme.danger).frame(maxWidth: .infinity, alignment: .leading).accessibilityIdentifier("account.error")
        }
        Button { focused = nil; feature.submit() } label: {
          Group { if feature.busy { ProgressView().tint(theme.badgeInk) } else { Text(primary) } }.frame(maxWidth: .infinity, minHeight: 48)
        }.buttonStyle(.borderedProminent).tint(feature.page == .close ? theme.danger : theme.amber)
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
      .scrollContentBackground(.hidden)
      .background(theme.app)
  }
  private var primary: String {
    switch feature.page { case .changePassword: "保存"; default: title }
  }
  private func input<Content: View>(_ title: String, field: Field, @ViewBuilder content: () -> Content) -> some View {
    VStack(alignment: .leading, spacing: 8) {
      Text(title).font(.subheadline).foregroundStyle(theme.ink3)
      content().padding(.horizontal, 12).frame(minHeight: 48)
        .foregroundStyle(theme.ink)
        .background(theme.raised2, in: RoundedRectangle(cornerRadius: 10))
    }
  }
  /// 「登录已失效」那一条。
  ///
  /// 服务端明确拒过这条会话之后，客户端就不再重试了（再试也是同一堵墙），同步会一直
  /// 停着。不摆这条的话用户在账号页上看到的是一个永远「同步失败」、点什么都没用的页面。
  /// 文案要说清楚**本机数据没丢**：云端只是同步通道，掉线不等于退登。
  @ViewBuilder private var expired: some View {
    if feature.needsReauthentication {
      Section {
        VStack(alignment: .leading, spacing: 8) {
          // 被同类设备顶下去时说得出是什么顶的（「这个账号在另一台手机上登录了」）；
          // 其余的失效仍旧是笼统那一句。
          Text(feature.replacedNotice ?? "登录已失效").foregroundStyle(theme.danger)
          Text("同步暂停了，本机的自选、画线、复盘都还在。重新登录就接着同步。")
            .font(.footnote).foregroundStyle(theme.ink3)
          Button("重新登录") { feature.reauthenticate() }
            .frame(minHeight: 44).accessibilityIdentifier("account.reauthenticate")
        }.padding(.vertical, 4)
      }
      .listRowBackground(theme.raised)
    }
  }
  private var account: some View {
    List {
      expired
      Section { LabeledContent("用户名", value: feature.user?.email ?? "") }
        .listRowBackground(theme.raised)
      Section {
        row("同步") { feature.move(.sync) }
        row("登录设备") { feature.move(.devices) }
        row("修改密码") { feature.move(.changePassword) }
        Button { feature.exportData() } label: {
          HStack {
            Text("导出我的数据"); Spacer()
            if feature.exporting { ProgressView().controlSize(.small) }
            else { VectorIcon.chevron(10, w: 1.7).rotationEffect(.degrees(-90)).foregroundStyle(theme.ink3) }
          }
        }
        .foregroundStyle(theme.ink).disabled(feature.exporting)
        .accessibilityIdentifier("account.export")
      }
      .listRowBackground(theme.raised)
      if let error = feature.error {
        Section { Text(error).foregroundStyle(theme.danger).accessibilityIdentifier("account.error") }
          .listRowBackground(theme.raised)
      }
      Section { Button("退出登录") { Haptics.warning(); Task { await feature.logout() } }.foregroundStyle(theme.danger) }
        .listRowBackground(theme.raised)
      Section { Button("注销账号") { feature.move(.close) }.foregroundStyle(theme.danger) }
        .listRowBackground(theme.raised)
    }
    .listed(theme)
  }
  private var sync: some View {
    List {
      expired
      Section {
        Toggle("自动同步", isOn: Binding(get: { feature.autoSync }, set: { feature.onAutoSync?($0) }))
        LabeledContent("上次同步") { if let last = feature.lastSync { Text(last, style: .relative) } else { Text("尚未同步") } }
        if !feature.syncStatus.isEmpty { Text(feature.syncStatus).foregroundStyle(theme.ink3) }
        if feature.pending > 0 { LabeledContent("待同步", value: "\(feature.pending) 项") }
      }
      .listRowBackground(theme.raised)
      Section { Button("立即同步") { feature.onSynchronize?() } }
        .listRowBackground(theme.raised)
    }
    .listed(theme)
  }
  private var deviceList: some View {
    List {
      ForEach(feature.devices) { item in
        HStack {
          VStack(alignment: .leading) {
            Text(item.name)
            // 「每类设备只许一台在线」这条规则要在这张表上看得见：手机 / 平板 / 电脑
            // 各占一行，同一类里再登一台就会把这一行顶掉。
            Text([item.kind.label, item.current ? "本机" : Date(timeIntervalSince1970: Double(item.lastSeen) / 1000).formatted(date: .abbreviated, time: .shortened)].joined(separator: " · "))
              .font(.caption).foregroundStyle(theme.ink3)
          }
          Spacer(); Button("退出") { Haptics.warning(); feature.revoke(item) }.foregroundStyle(theme.danger).frame(minHeight: 44)
        }
        .listRowBackground(theme.raised)
      }
      // 这一条也挂 `account.error`：设备列表是「被顶下去」唯一必然带令牌出门的入口，
      // 它报的错不打标识的话，用例红了只会说「页面上没有报错」，查不出到底是撞了
      // 401 还是这一趟请求超时了（09-21 矩阵上就吃过这个哑巴亏）。
      if let error = feature.error {
        Text(error).foregroundStyle(theme.danger).listRowBackground(theme.raised)
          .accessibilityIdentifier("account.error")
      }
    }
    .listed(theme)
    .task { await feature.loadDevices() }.refreshable { await feature.loadDevices() }
  }
  private func row(_ title: String, action: @escaping () -> Void) -> some View {
    Button(action: action) { HStack { Text(title); Spacer(); VectorIcon.chevron(10, w: 1.7).rotationEffect(.degrees(-90)).foregroundStyle(theme.ink3) } }.foregroundStyle(theme.ink)
  }
}

private extension View {
  /// 账号里那几张 `List` 共用的底：系统那抹灰换成皮肤的 `app`。
  /// 不换的话它们是全 app 仅存的系统配色，和左右两页对不上。
  /// 行的底得逐个 `Section` 自己写 `.listRowBackground(theme.raised)`，
  /// 那是行的属性，挂在 `List` 上不生效。
  func listed(_ theme: PanelTheme) -> some View {
    scrollContentBackground(.hidden).background(theme.app).foregroundStyle(theme.ink)
  }
}
