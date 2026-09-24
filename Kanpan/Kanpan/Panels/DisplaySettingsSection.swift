import SwiftUI
import KanpanCore

/// 配色分两根轴：选哪一套（青苔 / 陶土），和跟不跟系统深浅。
/// 亮度阈值与滞回留在 `BrightnessThemePolicy` 里，界面上不解释。
struct DisplaySettingsSection: View {
  var store: PrefsStore
  @Environment(\.panelTheme) private var theme
  @Environment(\.colorScheme) private var scheme
  /// 皮肤卡这一排和上下的行站在同一条竖线上：整页里跟页面外边距走（`panelPageInset()`）。
  @Environment(\.panelHPad) private var hPad

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
    HStack(spacing: Space.m) {
      ForEach(ThemeSkin.allCases, id: \.self) { skin in
        card(skin)
      }
    }.padding(.horizontal, hPad).padding(.vertical, Space.s)
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
    // 原来叫「自动护眼配色 · 随屏幕明暗切换」，和上面「外观」里的「跟随系统」读起来像
    // 同一件事（审查 U13）。两者不合并：「跟随系统」跟的是系统深色模式，这颗跟的是屏幕
    // 亮度（`BrightnessThemePolicy`）。只改字面，写清它按什么切，不要副标题。
    PanelRow(name: "按屏幕亮度切换深浅") {
      PanelSwitch(isOn: store.prefs.ambientTheme) { store.update { $0.ambientTheme.toggle() } }
        .accessibilityIdentifier("display.ambient")
    }
  }

  /// 一张配色卡：拿这套配色当前深浅下的真实颜色画几根蜡烛，所见即所得。
  private func card(_ skin: ThemeSkin) -> some View {
    let color = PanelTheme(seed: skin.seed(dark: dark), redUp: store.prefs.redUp)
    let picked = store.prefs.skin == skin
    let shape = RoundedRectangle(cornerRadius: Radius.m, style: .continuous)
    return Button {
      store.update { $0.skin = skin }
    } label: {
      VStack(alignment: .leading, spacing: Space.s) {
        HStack(alignment: .bottom, spacing: Space.xs) {
          ForEach(0..<6) { index in
            // 这是蜡烛预览，取图上那支色（`chart`），不是文字上的涨跌色。
            Rectangle().fill(Color(hex: index.isMultiple(of: 3) ? color.chart.down : color.chart.up))
              .frame(width: 6, height: CGFloat(10 + (index * 7) % 27))
          }
          Spacer(minLength: 0)
          Circle().fill(color.amber).frame(width: 10, height: 10)
        }.frame(height: 40).accessibilityHidden(true)
        // 名字和注脚默认并排；系统字调大、三张卡并排放不下时，注脚整行落到名字下面，
        // 不把「冷 · 墨绿」拆成两半（P2.13）。
        ViewThatFits(in: .horizontal) {
          HStack(spacing: Space.xs) { skinName(skin, color); skinNote(skin, color) }
          VStack(alignment: .leading, spacing: Space.xxs) { skinName(skin, color); skinNote(skin, color) }
        }
      }.padding(Inset.cardCompact).frame(maxWidth: .infinity, minHeight: Hit.min, alignment: .leading)
        .background(color.app, in: shape)
        // 没选中的描边取 `controlLine`（对页面底 ≥ 3:1，UI 整改 P2）；原来的 `line` 只有 1.2:1 左右，
        // 浅色皮肤下白卡压在近白的页面上几乎看不出边。描边画在卡里（`strokeBorder`），和卡同心。
        .overlay(shape.strokeBorder(picked ? theme.amber : theme.controlLine, lineWidth: picked ? 2 : 1))
        // 整张卡都是点按区。
        .contentShape(shape)
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
