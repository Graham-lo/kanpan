import SwiftUI
import KanpanCore

/// 风格面板（A6.1 / A6.2 / A6.3）。
///
/// 十一款一屏能翻完，每一款给出名字、一句话、赌的是什么，外加一张**按这一版真画的**小图；
/// 底下一条「外观」分段（跟随系统 / 浅色 / 深色）。标题与脚注一字照原型。
struct StylePanel: View {
  var store: PrefsStore
  @Environment(\.panelTheme) private var t

  var body: some View {
    PanelSheet(title: "风格", subtitle: "配色统一靛 · 换的是 K 线本身") {
      StyleGrid(store: store)

      PanelRow(name: "外观", divider: false) {
        PanelSegment(options: ThemeChoice.options, selection: store.prefs.theme) { v in
          store.update { $0.theme = v }
        }
      }

      PanelNote(markdown:
        "每一套换的都是 **K 线本身**：实体占几成、影线多粗、端头平还是圆、"
        + "是否空心或只描边，连同价格上下留白、根与根的间距、右轴宽度、副图和时间轴高度一起换。"
        + "图表类型始终只有一种：K 线。")
    }
  }
}

/// 原型 `styleGrid`：窄屏一列、宽屏两列（原型 `@container (max-width: 379px)`）。
private struct StyleGrid: View {
  var store: PrefsStore
  @Environment(\.panelTheme) private var t
  @Environment(\.dismiss) private var dismiss
  /// 横屏侧栏没有系统 `dismiss`，走主界面递进来的这一条（见 `PanelCloser`）。
  @Environment(\.panelDismiss) private var sideDismiss
  @State private var width: CGFloat = 0

  private var columns: [GridItem] {
    let two = width >= 380
    return Array(repeating: GridItem(.flexible(), spacing: 8), count: two ? 2 : 1)
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 10) {
      Text("风格").font(PanelFont.name).foregroundStyle(t.ink)
      LazyVGrid(columns: columns, spacing: 8) {
        ForEach(CandleStyle.all) { st in
          StyleCard(style: st,
                    selected: st.id == store.prefs.styleID,
                    colors: store.prefs.chartColors(dark: t.dark)) {
            store.update { $0.styleID = st.id }
            // 选完就收起，直接看换过的图——和周期面板一个规矩（原型 `closeAll()`）。
            // 单选的面板都这样；指标和设置是一次调好几项的，不在此列。
            PanelCloser(side: sideDismiss, sheet: dismiss)()
          }
          .accessibilityIdentifier("style.card.\(st.id)")
        }
      }
    }
    .padding(.horizontal, PanelMetrics.hPad)
    .padding(.top, 12)
    .padding(.bottom, 14)
    .background {
      // 量的是这一格容器的宽，不是屏幕的宽——和原型的容器查询一个意思。
      GeometryReader { geo in
        Color.clear.onAppear { width = geo.size.width }
          .onChange(of: geo.size.width) { _, new in width = new }
      }
    }
    .overlay(alignment: .bottom) { Rectangle().fill(t.hair).frame(height: 1) }
  }
}

private struct StyleCard: View {
  var style: CandleStyle
  var selected: Bool
  var colors: ChartColors
  var pick: () -> Void

  @Environment(\.panelTheme) private var t

  var body: some View {
    Button(action: pick) {
      VStack(alignment: .leading, spacing: 5) {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
          Text(style.name)
            .font(PanelFont.cardName)
            .foregroundStyle(selected ? t.amber : t.ink)
          Text(style.one)
            .font(PanelFont.cardOne)
            .foregroundStyle(t.ink3)
            .lineLimit(2)
          Spacer(minLength: 0)
        }
        Text(style.bet)
          .font(PanelFont.cardBet)
          .lineSpacing(4.5)
          .foregroundStyle(t.ink2)
          .fixedSize(horizontal: false, vertical: true)
          .frame(maxWidth: .infinity, alignment: .leading)
        StyleThumbnail(style: style, colors: colors)
      }
      .padding(.horizontal, 10)
      .padding(.top, 9)
      .padding(.bottom, 8)
      .frame(maxWidth: .infinity, alignment: .leading)
      .background(RoundedRectangle(cornerRadius: 12, style: .continuous)
        .fill(selected ? t.amberSoft : t.raised2))
      .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous)
        .stroke(selected ? t.amberLine : t.line, lineWidth: 1))
    }
    .buttonStyle(.plain)
    .accessibilityLabel("\(style.name)，\(style.one)")
    .accessibilityAddTraits(selected ? [.isButton, .isSelected] : .isButton)
  }
}

#Preview("风格") {
  PanelPreviewHost { store in StylePanel(store: store) }
}
