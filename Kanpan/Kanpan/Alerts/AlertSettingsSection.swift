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
      listingRow
    }
    .navigationDestination(isPresented: $showSound) { AlertSoundPage(store: preferences) }
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

  /// 自选波动提醒：只有一个开关。幅度不让人填（收设置项 E 组，2026-09-28）——按每只自己
  /// 最近一天的 1 分钟波动自动定（`WatchMove.autoThreshold`），BTC 落在 0.5% 附近、山寨自动放宽。
  private var watchMoveRows: some View {
    PanelRow(name: "自选波动提醒") {
      PanelSwitch(isOn: preferences.prefs.watchMoveAlert) {
        preferences.update { $0.watchMoveAlert.toggle() }
      }
      .accessibilityIdentifier("alerts.watchMove")
    }
  }

  /// 品种上新与停牌下架：开着时前台与每次同步去服务端拉一遍（`ListingNotices`），新的各出一条本地通知。
  private var listingRow: some View {
    PanelRow(name: "品种上新与停牌下架", divider: false) {
      PanelSwitch(isOn: preferences.prefs.notifyListingChanges) {
        preferences.update { $0.notifyListingChanges.toggle() }
      }
      .accessibilityIdentifier("alerts.listing")
    }
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
