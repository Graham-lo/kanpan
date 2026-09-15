import SwiftUI
import KanpanCore

/// 图表内的四种精选外观。旧存档仍按原来的造型显示，主动选择时才替换。
struct CandleStylePicker: View {
  var store: PrefsStore
  @Environment(\.panelTheme) private var t

  private let styles: [(id: String, title: String)] = [
    ("aicoin", "经典"), ("pill", "圆角"), ("paper", "空心"), ("outline", "轮廓")
  ]

  var body: some View {
    VStack(alignment: .leading, spacing: 8) {
      HStack {
        Text("K 线风格").font(PanelFont.name)
        Spacer()
        if !styles.contains(where: { $0.id == store.prefs.styleID }) {
          Text("当前：\(store.prefs.style.name)").font(PanelFont.meta).foregroundStyle(t.ink3)
        }
      }
      LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
        ForEach(styles, id: \.id) { option in
          let selected = store.prefs.styleID == option.id
          Button {
            store.update { $0.styleID = option.id; $0.bodyChoice = .style }
          } label: {
            VStack(alignment: .leading, spacing: 6) {
              HStack {
                Text(option.title).font(PanelFont.name)
                Spacer()
                Image(systemName: "checkmark").opacity(selected ? 1 : 0)
              }
              .foregroundStyle(selected ? t.amber : t.ink)
              StyleThumbnail(style: CandleStyle.style(id: option.id), colors: store.prefs.chartColors(dark: t.dark))
            }
            .padding(10)
            .background(RoundedRectangle(cornerRadius: 10).fill(selected ? t.amberSoft : t.raised2))
            .overlay(RoundedRectangle(cornerRadius: 10).stroke(selected ? t.amberLine : t.line))
            .contentShape(Rectangle())
          }
          .buttonStyle(.plain)
          .accessibilityLabel(option.title)
          .accessibilityIdentifier("style.card.\(option.id)")
          .accessibilityAddTraits(selected ? [.isSelected] : [])
        }
      }
    }
    .padding(PanelMetrics.hPad)
  }
}
