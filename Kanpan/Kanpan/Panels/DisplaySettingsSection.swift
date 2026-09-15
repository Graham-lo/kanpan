import SwiftUI
import KanpanCore

/// Native palette controls. Brightness thresholds and hysteresis stay internal.
struct DisplaySettingsSection: View {
  var store: PrefsStore
  @Environment(\.panelTheme) private var theme
  @Environment(\.colorScheme) private var scheme

  var body: some View {
    PanelGroupTitle(text: "显示与护眼")
    ScrollView(.horizontal) {
      HStack(spacing: 10) {
        ForEach(ThemeChoice.allCases, id: \.self) { choice in
          let color = PanelTheme(seed: choice.seed(systemDark: scheme == .dark), redUp: store.prefs.redUp)
          Button {
            store.update { $0.theme = choice; $0.ambientTheme = false }
          } label: {
            VStack(alignment: .leading, spacing: 10) {
              HStack(alignment: .bottom, spacing: 5) {
                ForEach(0..<6) { index in
                  Rectangle().fill(index.isMultiple(of: 3) ? color.down : color.up)
                    .frame(width: 6, height: CGFloat(10 + (index * 7) % 27))
                }
              }.frame(maxWidth: .infinity, alignment: .leading).frame(height: 40)
                .accessibilityHidden(true)
              Text(choice.display).font(PanelFont.name).foregroundStyle(color.ink)
                .fixedSize(horizontal: false, vertical: true)
            }.padding(12).frame(width: 112, alignment: .leading)
              .background(color.app, in: RoundedRectangle(cornerRadius: 12))
              .overlay(RoundedRectangle(cornerRadius: 12).stroke(store.prefs.theme == choice ? theme.amber : theme.line,
                lineWidth: store.prefs.theme == choice ? 2 : 1))
          }.buttonStyle(.plain).accessibilityIdentifier("display.theme." + choice.rawValue)
            .accessibilityValue(store.prefs.theme == choice ? "已选" : "未选")
        }
      }.padding(.horizontal, 16).padding(.vertical, 8)
    }.accessibilityIdentifier("display.themes")
    PanelRow(name: "自动护眼配色", meta: "随屏幕明暗切换") {
      PanelSwitch(isOn: store.prefs.ambientTheme) { store.update { $0.ambientTheme.toggle() } }
        .accessibilityIdentifier("display.ambient")
    }
  }
}
