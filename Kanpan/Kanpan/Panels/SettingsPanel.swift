import SwiftUI
import KanpanCore

/// 设置面板（A6.3 / A6.7 / A6.8 / A6.9 / A6.10 / A6.11）。
///
/// 条目顺序：先照原型（外观 · 涨跌配色 · 价格轴 · 时区 · 十字线磁吸），
/// 再按任务书 §10.6 追加原型里没有的那几项（本根倒计时 · 盯盘时不锁屏 · 启动快照 ·
/// API 域名 · 清缓存 · 关于）。原型里的「演示实时跳动」是原型自己的假数据开关，不进 app。
///
/// 没有「确定」也没有「取消」：改一下立刻生效、立刻落盘，并给一次 selection 触觉。
struct SettingsPanel: View {
  var store: PrefsStore

  @Environment(\.panelTheme) private var t
  @State private var hostDraft: String = ""
  @State private var streamDraft: String = ""
  @State private var clearing = false

  private var prefs: Prefs { store.prefs }

  var body: some View {
    PanelSheet(title: "设置", subtitle: nil) {
      DisplaySettingsSection(store: store)
      PanelRow(name: "涨跌配色") {
        PanelSegment(options: [("绿涨红跌", false), ("红涨绿跌", true)], selection: prefs.redUp) { v in
          store.update { $0.redUp = v }
        }
      }
      PanelRow(name: "价格轴") {
        PanelSegment(options: SettingsPanel.priceModes, selection: prefs.priceMode) { v in
          store.update { $0.priceMode = v }
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
      switchRow("十字线磁吸", "吸到最近一根 K 线上", prefs.magnet) { $0.magnet = $1 }
        .accessibilityIdentifier("settings.magnet")

      // ---- 任务书 §10.6 里有、原型里没有的
      switchRow("本根倒计时", "右轴上显示这根还有多久收", prefs.countdown) { $0.countdown = $1 }
        .accessibilityIdentifier("settings.countdown")
      switchRow("盯盘时不锁屏", "在图上就不自动息屏", prefs.keepAwake) { $0.keepAwake = $1 }
        .accessibilityIdentifier("settings.keepAwake")
      switchRow("启动快照", "冷启动先画上次那 600 根，再等网", prefs.launchSnapshot) { $0.launchSnapshot = $1 }
        .accessibilityIdentifier("settings.launchSnapshot")

      hostRow
      streamRow
      switchRow("智能行情线路", "自动选用较快的可用线路，断线自动切换", prefs.smartMarketRoute) { $0.smartMarketRoute = $1 }
        .accessibilityIdentifier("settings.smartMarketRoute")
      cacheRow

      PanelRow(name: "恢复默认", meta: "风格、指标、周期、各项开关回到全新安装的样子",
               divider: false, onTap: { store.resetToDefaults() }) {
        Text("恢复").font(PanelFont.seg).foregroundStyle(t.amber)
      }

      PanelNote(markdown:
        "行情走 WebSocket，最新价和右轴胶囊一直跳。**这里的任何一项改完立刻生效、立刻存**，"
        + "杀掉 app 再开还是这样。")
    }
    .panelToast(store)
    .task { await store.refreshCacheUsage() }
    .onAppear { hostDraft = prefs.apiHost; streamDraft = prefs.streamHost }
    .sensoryFeedback(.selection, trigger: prefs)
  }

  // MARK: - 行

  private func switchRow(_ name: String, _ meta: String, _ on: Bool,
                         _ set: @escaping (inout Prefs, Bool) -> Void) -> some View {
    PanelRow(name: name, meta: meta) {
      PanelSwitch(isOn: on) { store.update { set(&$0, !on) } }
    }
  }

  /// A6.10：填一个域名，立刻落盘；形状不对就弹一句、不写。
  private var hostRow: some View {
    PanelRow(name: "API 域名", meta: "默认 \(APIHost.default)") {
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
    PanelRow(name: "行情推送域名", meta: "默认 \(APIHost.defaultStream)") {
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
    guard u.available else { return "数据层未接入" }
    return "启动快照与品种表 \(MarketCacheUsage.display(u.marketBytes))"
      + " · 持仓量归档 \(MarketCacheUsage.display(u.oiBytes))"
  }

  // MARK: - 分段选项

  /// A6.8。`PriceMode` 的三档，字面照原型。
  static let priceModes: [(String, PriceMode)] = [("常规", .linear), ("对数", .log), ("百分比", .percent)]
  /// A6.9。原型写的是 本地 / UTC / 交易所——任务书写的是 设备 / UTC+8 / UTC，以原型为准。
  static let zones: [(String, TZChoice)] = [("本地", .local), ("UTC", .utc), ("交易所", .exchange)]
}

#Preview("设置") {
  PanelPreviewHost { store in SettingsPanel(store: store) }
}
