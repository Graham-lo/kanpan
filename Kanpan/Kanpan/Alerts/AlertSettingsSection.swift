import KanpanCore
import SwiftUI

/// 设置整页上的「通知」一组：提醒铃声、自选波动提醒、通知权限。
///
/// 2026-09-25 以前这三样住在提醒总表顶上、总表又挂在设置的「提醒」一行下面。用户说
/// 「设置里的提醒就顺便删了吧，现在入口改到了外面了就不需要了」——建提醒只从图上那颗药丸进，
/// 管提醒从新建页右上「全部预警」进；剩下这三样是**设置**，就回到设置页上，自己成一组。
/// 分组标题由这里自己画，`SettingsPanel` 只管把它排在「行情」之后。
///
/// 铃声那一行推 `AlertSoundPage`，要一个外层 `NavigationStack`（设置整页有）。
struct AlertSettingsSection: View {
  var preferences: PrefsStore

  @State private var showSound = false
  /// 自选波动的幅度，编辑时的那一格字。离开输入框才落盘（`kanpan-persist-on-gesture-end`）。
  @State private var thresholdText = ""
  @FocusState private var thresholdFocused: Bool
  /// 通知权限那一行的开关（见 `AlertPermission`）。这一组自己养一个，别处不看它。
  @StateObject private var permission = AlertPermission()
  /// 「回前台再查一遍」那份登记。用户点了权限那一行就去了系统设置，回来时这一页还开着、
  /// `task` 不会再跑一次；而他很可能刚把开关拨上来，这一行就得自己消失。
  /// 走 `AppLifecycle` 是**规定**：全 app 只有那一处读前后台，谁要听就去报到，
  /// 不许自己挂 `UIApplication` 的通知（见 `AppLifecycle` 开头第 1 条）。
  @State private var lifecycle: AppLifecycle.ResourceToken?

  @Environment(\.panelTheme) private var t

  var body: some View {
    VStack(spacing: 0) {
      PanelGroupTitle(text: "通知")
      if permission.needsSystemSettings { AlertPermissionRow { permission.openSystemSettings() } }
      PanelRow(name: "提醒铃声", onTap: { showSound = true }) {
        HStack(spacing: Space.xs) {
          Text(preferences.prefs.alertSound.title).font(PanelFont.name)
          VectorIcon.chevronRight(ControlMetrics.chevron)
        }.foregroundStyle(t.ink3)
      }
      .accessibilityIdentifier("alerts.sound.open")
      .accessibilityValue(preferences.prefs.alertSound.title)
      watchMoveRows
    }
    .navigationDestination(isPresented: $showSound) { AlertSoundPage(store: preferences) }
    .toolbar {
      // 数字键盘没有回车键，收不起来（视觉审查 2.9 #5）。
      ToolbarItemGroup(placement: .keyboard) {
        Spacer()
        Button("完成") { thresholdFocused = false }
      }
    }
    .task { await permission.refresh() }
    .onAppear {
      guard lifecycle == nil else { return }
      lifecycle = AppLifecycle.shared.registerResources(
        id: "alerts.permission",
        leave: {},
        enter: { Task { await permission.refresh() } })
    }
    .onDisappear {
      guard let token = lifecycle else { return }
      AppLifecycle.shared.unregisterResources(token: token)
      lifecycle = nil
    }
  }

  /// 自选波动提醒：一个开关，开着时下面一格幅度（手动输入，没有口径可选）。
  @ViewBuilder private var watchMoveRows: some View {
    let on = preferences.prefs.watchMoveAlert
    PanelRow(name: "自选波动提醒", divider: on) {
      PanelSwitch(isOn: on) {
        commitThreshold()
        preferences.update { $0.watchMoveAlert.toggle() }
      }
      .accessibilityIdentifier("alerts.watchMove")
    }
    if on {
      PanelRow(name: "五分钟涨跌超过", divider: false) {
        HStack(spacing: Space.xs) {
          TextField("", text: $thresholdText)
            .keyboardType(.decimalPad)
            .multilineTextAlignment(.trailing)
            .font(TypeScale.body).monospacedDigit()
            .foregroundStyle(t.ink)
            .frame(width: Hit.min)
            .padding(.horizontal, Space.s)
            .padding(.vertical, Space.s)
            .background(t.raised2, in: RoundedRectangle(cornerRadius: Radius.s, style: .continuous))
            .focused($thresholdFocused)
            .onSubmit(commitThreshold)
            .accessibilityIdentifier("alerts.watchMove.threshold")
            .accessibilityLabel("五分钟涨跌超过")
          Text("%").font(TypeScale.body).foregroundStyle(t.ink3)
        }
      }
      .onAppear { thresholdText = Self.format(preferences.prefs.watchMoveThreshold) }
      .onChange(of: thresholdFocused) { _, focused in if !focused { commitThreshold() } }
      .onDisappear(perform: commitThreshold)
    }
  }

  private func commitThreshold() {
    let text = thresholdText.replacingOccurrences(of: ",", with: ".").trimmingCharacters(in: .whitespaces)
    guard !text.isEmpty else { return }
    let value = Double(text).map(WatchMove.clampThreshold) ?? preferences.prefs.watchMoveThreshold
    thresholdText = Self.format(value)
    guard value != preferences.prefs.watchMoveThreshold else { return }
    preferences.update { $0.watchMoveThreshold = value }
  }

  static func format(_ value: Double) -> String {
    var text = String(format: "%.2f", value)
    while text.hasSuffix("0") { text.removeLast() }
    if text.hasSuffix(".") { text.removeLast() }
    return text
  }
}

/// 通知被拒之后「通知」组最上面那一行。**提示，不是拦路**：下面几行照常能改。
///
/// 色走 `amberSoft` + `amberLine`（皮肤自己的强调色兑得极淡的一层），和「要不要提醒」
/// 那条问句（`AlertPromptBar`）是同一个功能的两句话，读成同一个东西；不用 `t.danger`——
/// 那一支留给「删除 / 注销」这种不可逆动作。
///
/// 2026-09-24 UI 整改 P1b：高 36 → 44（整行就是按钮）、圆角取 `Radius.m`、左右跟正文同一条
/// 边（`hPad`，整页里随屏宽 16 / 20），去掉 SF 的铃铛线框，字 13 走 `TypeScale.footnote`。
private struct AlertPermissionRow: View {
  var open: () -> Void
  @Environment(\.panelTheme) private var t
  @Environment(\.panelHPad) private var hPad

  var body: some View {
    Button(action: open) {
      HStack(spacing: Space.s) {
        Text("通知关着，提醒到了不会响")
          .font(TypeScale.footnote)
          .foregroundStyle(t.ink)
          .lineLimit(1)
          .minimumScaleFactor(0.85)
        Spacer(minLength: Space.s)
        HStack(spacing: Space.xxs) {
          Text("去打开").font(TypeScale.footnoteEmph)
          VectorIcon.chevronRight(ControlMetrics.chevron)
        }
        .foregroundStyle(t.amber)
      }
      .padding(.horizontal, Space.m)
      .frame(maxWidth: .infinity)
      .frame(minHeight: Hit.min)
      .contentShape(Rectangle())
      .background(
        RoundedRectangle(cornerRadius: Radius.m, style: .continuous)
          .fill(t.amberSoft)
          .overlay(RoundedRectangle(cornerRadius: Radius.m, style: .continuous)
            .strokeBorder(t.amberLine, lineWidth: 0.5))
      )
    }
    .buttonStyle(.plain)
    .padding(.horizontal, hPad)
    .padding(.vertical, Space.s)
    .accessibilityIdentifier("alerts.permission")
  }
}
