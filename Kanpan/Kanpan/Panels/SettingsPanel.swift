import SwiftUI
import KanpanCore

/// 设置面板（A6.3 / A6.7 / A6.8 / A6.9 / A6.10 / A6.11）。
///
/// 条目顺序：先照原型（外观 · 涨跌配色 · 时区 · 十字线磁吸），再按任务书 §10.6 追加
/// 原型里没有的那几项（盯盘时不锁屏 · 启动快照 · 域名 · 清缓存）。原型里的
/// 「演示实时跳动」是原型自己的假数据开关，不进 app。
///
/// 和「图表」的分界：**画在图上的东西归图表面板**。原型那份「价格轴」和「本根倒计时」
/// 在两边各有一份，改的却是同一个字段，现在只留图表那边（见 `ChartPanel`）。
///
/// 域名、线路、缓存这几件收进最底下的「高级与诊断」，默认折着。它们不是日常会动的
/// 东西——真要动的时候多半是照着一句排查说明填，找得到就行；平时摊在设置里，
/// 每次找「不锁屏」都要从一堆域名输入框里翻过去。
///
/// 没有「确定」也没有「取消」：改一下立刻生效、立刻落盘，并给一次 selection 触觉。
struct SettingsPanel: View {
  var store: PrefsStore

  @Environment(\.panelTheme) private var t
  @Environment(\.accountFeature) private var account
  @State private var hostDraft: String = ""
  @State private var streamDraft: String = ""
  @State private var clearing = false
  @State private var advanced = false

  private var prefs: Prefs { store.prefs }

  var body: some View {
    PanelSheet(title: "设置", subtitle: nil) {
      if let account {
        PanelRow(name: account.user?.email ?? "登录", meta: account.user == nil ? nil : account.syncStatus,
                 onTap: { account.open() }) {
          Image(systemName: "person.crop.circle").font(.title3).foregroundStyle(t.amber)
        }.accessibilityIdentifier("settings.account")
      }
      DisplaySettingsSection(store: store)
      PanelRow(name: "涨跌配色") {
        PanelSegment(options: [("绿涨红跌", false), ("红涨绿跌", true)], selection: prefs.redUp) { v in
          store.update { $0.redUp = v }
        }
      }
      PanelRow(name: "开盘时间") {
        Menu(prefs.changeBasis.title) {
          ForEach(ChangeBasis.allCases, id: \.self) { basis in
            Button(basis.title) { store.update { $0.changeBasis = basis } }
          }
        }.accessibilityIdentifier("settings.changeBasis")
      }
      PanelRow(name: "时区") {
        PanelSegment(options: SettingsPanel.zones, selection: prefs.timeZone) { v in
          store.update { $0.timeZone = v }
        }
      }
      switchRow("十字线磁吸", nil, prefs.magnet) { $0.magnet = $1 }
        .accessibilityIdentifier("settings.magnet")

      // ---- 任务书 §10.6 里有、原型里没有的
      switchRow("盯盘时不锁屏", nil, prefs.keepAwake) { $0.keepAwake = $1 }
        .accessibilityIdentifier("settings.keepAwake")
      switchRow("启动快照", "先显示上次图表", prefs.launchSnapshot) { $0.launchSnapshot = $1 }
        .accessibilityIdentifier("settings.launchSnapshot")

      PanelGroupTitle(text: "高级与诊断")
      PanelRow(name: advanced ? "收起" : "展开", meta: "行情域名、线路与缓存 · 平时不用动",
               divider: advanced, onTap: { advanced.toggle() }) {
        Image(systemName: advanced ? "chevron.up" : "chevron.down")
          .font(PanelFont.seg).foregroundStyle(t.ink3)
      }
      .accessibilityIdentifier("settings.advanced")
      if advanced {
        switchRow("智能行情线路", "自动选择可用线路", prefs.smartMarketRoute) { $0.smartMarketRoute = $1 }
          .accessibilityIdentifier("settings.smartMarketRoute")
        hostRow
        streamRow
        cacheRow
      }

      PanelRow(name: "恢复默认", meta: "重置所有偏好设置",
               divider: false, onTap: { store.resetToDefaults() }) {
        Text("恢复").font(PanelFont.seg).foregroundStyle(t.amber)
      }

    }
    .sheet(isPresented: Binding(get: { account?.presented == true }, set: { account?.presented = $0 })) {
      if let account { AccountView(feature: account) }
    }
    .panelToast(store)
    .task { await store.refreshCacheUsage() }
    .onAppear { hostDraft = prefs.apiHost; streamDraft = prefs.streamHost }
    .sensoryFeedback(.selection, trigger: prefs)
  }

  // MARK: - 行

  private func switchRow(_ name: String, _ meta: String?, _ on: Bool,
                         _ set: @escaping (inout Prefs, Bool) -> Void) -> some View {
    PanelRow(name: name, meta: meta) {
      PanelSwitch(isOn: on) { store.update { set(&$0, !on) } }
    }
  }

  /// A6.10：填一个域名，立刻落盘；形状不对就弹一句、不写。
  private var hostRow: some View {
    PanelRow(name: "API 域名") {
      TextField(APIHost.default, text: $hostDraft)
        .textFieldStyle(.plain)
        .font(PanelFont.number)
        .foregroundStyle(t.ink)
        .multilineTextAlignment(.trailing)
        .textInputAutocapitalization(.never)
        .autocorrectionDisabled()
        .keyboardType(.URL)
        .submitLabel(.done)
        .frame(minWidth: 150)
        .onSubmit { commitHost() }
    }
  }

  /// 行情推送域名。和上一行分开填：走镜像或代理时常常只有一边通，
  /// 推送这条不通的表现就是「图有数据但一动不动」——那时候改的是这一行。
  private var streamRow: some View {
    PanelRow(name: "行情推送域名") {
      TextField(APIHost.defaultStream, text: $streamDraft)
        .textFieldStyle(.plain)
        .font(PanelFont.number)
        .foregroundStyle(t.ink)
        .multilineTextAlignment(.trailing)
        .textInputAutocapitalization(.never)
        .autocorrectionDisabled()
        .keyboardType(.URL)
        .submitLabel(.done)
        .frame(minWidth: 150)
        .onSubmit { commitStream() }
    }
  }

  private func commitStream() {
    let draft = streamDraft
    store.attempt { $0.setStreamHost(draft) }
    streamDraft = store.prefs.streamHost
  }

  private func commitHost() {
    let draft = hostDraft
    store.attempt { $0.setAPIHost(draft) }
    hostDraft = store.prefs.apiHost      // 没写进去就退回上一版，输入框不留一个假值
  }

  /// A6.11：清的是 `KanpanData.Paths` 指的那几处，不是另拼一套目录。
  private var cacheRow: some View {
    PanelRow(name: "清缓存", meta: cacheMeta) {
      Button {
        clearing = true
        Task { await store.clearCache(); clearing = false }
      } label: {
        if clearing {
          ProgressView().controlSize(.small)
        } else {
          Text("清除").font(PanelFont.seg).foregroundStyle(t.amber)
        }
      }
      .buttonStyle(.plain)
      .disabled(clearing)
    }
  }

  private var cacheMeta: String {
    guard let u = store.cacheUsage else { return "正在统计…" }
    guard u.available else { return "暂时无法读取" }
    return MarketCacheUsage.display(u.totalBytes)
  }

  // MARK: - 分段选项

  /// A6.9。原型写的是 本地 / UTC / 交易所——任务书写的是 设备 / UTC+8 / UTC，以原型为准。
  static let zones: [(String, TZChoice)] = [("本地", .local), ("UTC", .utc), ("交易所", .exchange)]
}

#Preview("设置") {
  PanelPreviewHost { store in SettingsPanel(store: store) }
}
