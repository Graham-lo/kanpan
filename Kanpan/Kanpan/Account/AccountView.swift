import SwiftUI
import KanpanAccount

struct AccountView: View {
  @Bindable var feature: AccountFeature
  /// 推在设置整页的导航栈里（设置 → 账号，UI 整改 P2）：不自带导航栈；顶层（账号 / 登录）
  /// 用系统返回，退回设置；子页（同步、设备、改密码……）仍是左上那颗 `account.back` 退回上一层。
  var pushed = false
  @Environment(\.panelTheme) private var theme
  @FocusState private var focused: Field?
  private enum Field { case email, password, newPassword }
  /// 账号页的顶层：再往外退就是离开账号页。
  private var atTop: Bool { feature.page == .account || feature.page == .login }
  var body: some View {
    if pushed {
      // 外面这层是「账号页在不在」的记号（`account.view`；SwiftUI 会把它并到唯一的
      // 滚动视图上，用例按任意类型找，见 `XCUIApplication.accountView`），
      // `children: .contain` 让里头的输入框、按钮各留各的名字。
      VStack(spacing: 0) { page }
        .tint(theme.amber)
        .background(theme.app.ignoresSafeArea())
        // 提交中不许退（和表那条路的 `interactiveDismissDisabled(busy)` 同一个意思）；
        // 子页的「‹」是自己的，系统那颗藏起来。
        .navigationBarBackButtonHidden(!atTop || feature.busy)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("account.view")
    } else {
      sheet
    }
  }
  private var page: some View {
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
      // 推在设置里时顶层这颗交给系统返回。
      if !pushed || !atTop {
        ToolbarItem(placement: .cancellationAction) {
          Button {
            focused = nil
            if atTop { feature.presented = false }
            else { feature.move(feature.user == nil ? .login : .account) }
          } label: {
            Label(atTop ? "关闭" : "返回", systemImage: "chevron.left")
          }.disabled(feature.busy).accessibilityIdentifier("account.back")
        }
      }
    }
  }
  private var sheet: some View {
    NavigationStack { page }.tint(theme.amber)
      // 审查 U14 在模拟器上见过一次「下半截白底硬边」，2026-09-24 按键盘交互收起、整张下拉
      // 复现过一轮没再出现。表单底色只铺在内容那一层，sheet 本身仍是系统默认底；
      // 把 sheet 的底也钉成页面底色，哪一帧露出来都是同一块料。
      .presentationBackground(theme.app)
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
      VStack(spacing: Space.l) {
        if [.login, .register].contains(feature.page) {
          input("用户名", field: .email, hint: feature.usernameHint, hintID: "account.email.rule") {
            TextField("用户名", text: $feature.email).keyboardType(.asciiCapable)
              .textContentType(.username).textInputAutocapitalization(.never).autocorrectionDisabled()
              .focused($focused, equals: .email).submitLabel(.next).onSubmit { focused = .password }
              .accessibilityIdentifier("account.email")
          }
        }
        if [.login, .register, .changePassword, .close].contains(feature.page) {
          input(feature.page == .changePassword ? "当前密码" : "密码", field: .password,
                hint: feature.page == .register ? feature.passwordHint : nil, hintID: "account.password.rule") {
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
          input("新密码", field: .newPassword, hint: feature.passwordHint, hintID: "account.password.rule") {
            SecureField("新密码", text: $feature.newPassword).textContentType(.password)
              .focused($focused, equals: .newPassword).submitLabel(.go).onSubmit { feature.submit() }
              .accessibilityIdentifier("account.newPassword")
          }
        }
        if feature.page == .close { Text("注销后云端数据将删除").font(TypeScale.footnote).foregroundStyle(theme.ink3).frame(maxWidth: .infinity, alignment: .leading) }
        // 出错的字走跌色。原来写死了橙，那是上一版的品牌色，换了配色以后它是全页唯一
        // 一处跟谁都不像的颜色；错误本来就该跟「跌」同一支红。
        // 登录页上那一行字：这一趟出的错优先，没出错时摆「被顶下去」那一句
        // ——人是被顶回登录页来的，得让他看见为什么。
        if let message = feature.error ?? (feature.page == .login ? feature.replacedNotice : nil) {
          Text(message).font(TypeScale.footnote).foregroundStyle(theme.danger).frame(maxWidth: .infinity, alignment: .leading).accessibilityIdentifier("account.error")
        }
        // 禁用态（没填全）不再交给系统 `.borderedProminent`：它在灰底上叠灰字，实测只有 1.44:1，
        // 看不出按钮上写的是什么。和面板里的主按钮同一套（`PanelDisabled`）：底换中性的
        // `raised2`、字换 `ink3`（≥3:1）；提交中（`busy`）仍是可用的样子，只是转圈。
        let ready = feature.busy || feature.canSubmit
        Button { focused = nil; feature.submit() } label: {
          Group { if feature.busy { ProgressView().tint(theme.badgeInk) } else { Text(primary) } }
            .font(TypeScale.title)
            .foregroundStyle(ready ? theme.badgeInk : PanelDisabled.ink(theme))
            .frame(maxWidth: .infinity, minHeight: Hit.min + Space.xs)  // 主按钮 48
            .background(Capsule().fill(ready ? (feature.page == .close ? theme.danger : theme.amber)
                                             : PanelDisabled.fill(theme)))
            .contentShape(Capsule())
        }.buttonStyle(.plain)
          .disabled(feature.busy || !feature.canSubmit).accessibilityIdentifier("account.submit")
        // 登录、注册两页互相切换的那一颗：同一个位置、同一种样式，只是字对调。
        if [.login, .register].contains(feature.page) {
          let other: AccountFeature.Page = feature.page == .login ? .register : .login
          Button { focused = nil; feature.move(other) } label: {
            // 点按区放进 label 里撑满整宽 44，否则只有那两个字点得中。
            Text(other == .register ? "注册" : "登录")
              .font(TypeScale.bodyEmph)
              .frame(maxWidth: .infinity, minHeight: Hit.min)
              .contentShape(Rectangle())
          }
          .accessibilityIdentifier("account.switch")
        }
      }
      .pageHorizontalInset()
      .padding(.vertical, Space.xl)
    }.scrollDismissesKeyboard(.interactively)
      .scrollContentBackground(.hidden)
      .background(theme.app)
  }
  private var primary: String {
    switch feature.page { case .changePassword: "保存"; default: title }
  }
  /// `hint` 是框下那一行规则字：只在不合格时占一行，合格了整行收起，不留空位。
  private func input<Content: View>(_ title: String, field: Field, hint: String? = nil, hintID: String = "",
                                    @ViewBuilder content: () -> Content) -> some View {
    // 2026-09-24 UI 整改 P1b：框里的字 15、框高 44、圆角 8（`Radius.s`），标签 13、规则字 12。
    VStack(alignment: .leading, spacing: Space.s) {
      Text(title).font(TypeScale.footnote).foregroundStyle(theme.ink3)
      content().font(TypeScale.body).padding(.horizontal, Space.m).frame(minHeight: Hit.min)
        .foregroundStyle(theme.ink)
        .background(theme.raised2, in: RoundedRectangle(cornerRadius: Radius.s, style: .continuous))
      if let hint {
        Text(hint).font(TypeScale.caption).foregroundStyle(theme.ink3).accessibilityIdentifier(hintID)
      }
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
        VStack(alignment: .leading, spacing: Space.s) {
          // 被同类设备顶下去时说得出是什么顶的（「这个账号在另一台手机上登录了」）；
          // 其余的失效仍旧是笼统那一句。
          Text(feature.replacedNotice ?? "登录已失效").foregroundStyle(theme.danger)
          Text("已退出登录，本机数据都在")
            .font(TypeScale.caption).foregroundStyle(theme.ink3)
          Button("重新登录") { feature.reauthenticate() }
            .frame(minHeight: Hit.min).accessibilityIdentifier("account.reauthenticate")
        }.padding(.vertical, Space.xs)
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
            else { VectorIcon.chevronRight(ControlMetrics.chevron).foregroundStyle(theme.ink3) }
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
              .font(TypeScale.caption).foregroundStyle(theme.ink3)
          }
          Spacer()
          Button { Haptics.warning(); feature.revoke(item) } label: { Text("退出").hitTarget() }
            .buttonStyle(.borderless).foregroundStyle(theme.danger)
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
    Button(action: action) { HStack { Text(title); Spacer(); VectorIcon.chevronRight(ControlMetrics.chevron).foregroundStyle(theme.ink3) } }.foregroundStyle(theme.ink)
  }
}

private extension View {
  /// 账号里那几张 `List` 共用的底：系统那抹灰换成皮肤的 `app`。
  /// 不换的话它们是全 app 仅存的系统配色，和左右两页对不上。
  /// 行的底得逐个 `Section` 自己写 `.listRowBackground(theme.raised)`，
  /// 那是行的属性，挂在 `List` 上不生效。
  ///
  /// 2026-09-24 UI 整改 P1b：行名 15（`TypeScale.body`，系统 List 默认是 17），行高至少 44。
  /// 左右边距用 inset grouped 自己的版心（本机 20 / 小屏 16），和 `Inset.page` 同一档。
  func listed(_ theme: PanelTheme) -> some View {
    font(TypeScale.body)
      .environment(\.defaultMinListRowHeight, Inset.rowMin)
      .scrollContentBackground(.hidden).background(theme.app).foregroundStyle(theme.ink)
  }
}
