import SwiftUI

/// 设置 › 通用「自选走势线」：自选行上那条 24 小时迷你走势线开不开（`Prefs.favoritesTrend`，出厂开）。
///
/// 只此一颗全局开关，跟账号同步（2026-10-08）。手指拨到的那一下给一次 selection 触觉
/// （`updateByHand`），云端落地改了它不震。
///
/// 摆在 `SettingsPanel` 的「通用」组里（`HabitSettingsRows` 之前）：
/// `FavoritesTrendSettingRow(store: store)`。
struct FavoritesTrendSettingRow: View {
  var store: PrefsStore

  var body: some View {
    PanelRow(name: "自选走势线") {
      PanelSwitch(isOn: store.prefs.favoritesTrend) {
        store.updateByHand { $0.favoritesTrend.toggle() }
      }
      .accessibilityIdentifier("settings.favoritesTrend")
    }
  }
}
