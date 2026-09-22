import SwiftUI
import KanpanCore

/// 配色分两根轴：选哪一套（青苔 / 陶土），和跟不跟系统深浅。
/// 亮度阈值与滞回留在 `BrightnessThemePolicy` 里，界面上不解释。
struct DisplaySettingsSection: View {
  var store: PrefsStore
  @Environment(\.panelTheme) private var theme
  @Environment(\.colorScheme) private var scheme

  private var dark: Bool {
    switch store.prefs.theme {
    case .system: scheme == .dark
    case .light: false
    case .dark: true
    }
  }

  var body: some View {
    // 「显示」这个词让给「图表」面板里那一组（那边管的是画在图上的东西）：
    // 这儿从头到尾只有配色，叫「配色」不会再和那边撞（第三批 16）。
    PanelGroupTitle(text: "配色")
    HStack(spacing: 10) {
      ForEach(ThemeSkin.allCases, id: \.self) { skin in
        card(skin)
      }
    }.padding(.horizontal, 16).padding(.vertical, 8)
    // 这一排原来还挂着 `.accessibilityIdentifier("display.themes")`。加在 HStack 上的
    // 标识符会往下盖住几张卡自己的 `display.theme.sage` / `display.theme.terra` / `display.theme.classic`，
    // 于是无障碍树里并排躺着两个都叫 `display.themes` 的按钮，UI 用例按名字一张也找不着。
    // 外面这层没人按名字找，删掉就是了。

    PanelGroupTitle(text: "深浅")
    PanelRow(name: "外观") {
      PanelSegment(options: ThemeChoice.allCases.map { ($0.display, $0) },
                   selection: store.prefs.theme, id: "display.mode") { choice in
        store.update { $0.theme = choice; $0.ambientTheme = false }
      }
    }
    PanelRow(name: "自动护眼配色", meta: "随屏幕明暗切换") {
      PanelSwitch(isOn: store.prefs.ambientTheme) { store.update { $0.ambientTheme.toggle() } }
        .accessibilityIdentifier("display.ambient")
    }
  }

  /// 一张配色卡：拿这套配色当前深浅下的真实颜色画几根蜡烛，所见即所得。
  private func card(_ skin: ThemeSkin) -> some View {
    let color = PanelTheme(seed: skin.seed(dark: dark), redUp: store.prefs.redUp)
    let picked = store.prefs.skin == skin
    return Button {
      store.update { $0.skin = skin }
    } label: {
      VStack(alignment: .leading, spacing: 10) {
        HStack(alignment: .bottom, spacing: 5) {
          ForEach(0..<6) { index in
            Rectangle().fill(index.isMultiple(of: 3) ? color.down : color.up)
              .frame(width: 6, height: CGFloat(10 + (index * 7) % 27))
          }
          Spacer(minLength: 0)
          Circle().fill(color.amber).frame(width: 10, height: 10)
        }.frame(height: 40).accessibilityHidden(true)
        // 名字和注脚默认并排；系统字调大、三张卡并排放不下时，注脚整行落到名字下面，
        // 不把「冷 · 墨绿」拆成两半（P2.13）。
        ViewThatFits(in: .horizontal) {
          HStack(spacing: 6) { skinName(skin, color); skinNote(skin, color) }
          VStack(alignment: .leading, spacing: 2) { skinName(skin, color); skinNote(skin, color) }
        }
      }.padding(12).frame(maxWidth: .infinity, alignment: .leading)
        .background(color.app, in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12)
          .stroke(picked ? theme.amber : theme.line, lineWidth: picked ? 2 : 1))
    }.buttonStyle(.plain).accessibilityIdentifier("display.theme." + skin.rawValue)
      .accessibilityValue(picked ? "已选" : "未选")
  }

  private func skinName(_ skin: ThemeSkin, _ color: PanelTheme) -> some View {
    Text(skin.display).font(PanelFont.name).foregroundStyle(color.ink).lineLimit(1)
  }

  private func skinNote(_ skin: ThemeSkin, _ color: PanelTheme) -> some View {
    Text(skin.note).font(PanelFont.meta).foregroundStyle(color.ink3).lineLimit(1)
  }
}
