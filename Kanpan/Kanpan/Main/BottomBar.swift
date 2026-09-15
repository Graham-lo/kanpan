import SwiftUI

/// 底栏保留常用去处；外观与横屏统一在周期行。
struct BottomBar: View {
  var theme: PanelTheme
  /// 哪个亮着。面板开着时对应那个是琥珀色（原型 `syncTools()`）。
  var active: Panel?
  var onPanel: (Panel) -> Void
  var onReview: () -> Void
  var reviewCount: Int
  var onFavorites: () -> Void

  var body: some View {
    HStack(spacing: 0) {
      tool(.indicator, VectorIcon.indicator, "指标") { onPanel(.indicator) }
        .accessibilityIdentifier("bottom.indicator")
      item(VectorIcon.star(), "自选", on: false, action: onFavorites)
        .accessibilityIdentifier("bottom.favorites")
      item(VectorIcon.chart, "复盘", on: false, action: onReview)
        .accessibilityIdentifier("bottom.review")
        .overlay(alignment: .topTrailing) {
          if reviewCount > 0 { Text("\(min(reviewCount, 99))").font(.system(size: 9)).padding(3).background(theme.amber, in: Capsule()).foregroundStyle(.white).padding(.trailing, 14) }
        }
      tool(.settings, VectorIcon.settings, "设置") { onPanel(.settings) }
        .accessibilityIdentifier("bottom.settings")
    }
  }

  private func tool(
    _ which: Panel, _ icon: VectorIcon, _ title: String, action: @escaping () -> Void
  ) -> some View {
    item(icon, title, on: active == which, action: action)
  }

  private func item(
    _ icon: VectorIcon, _ title: String, on: Bool, action: @escaping () -> Void
  ) -> some View {
    Button(action: action) {
      VStack(spacing: 3) {
        icon
        Text(title).font(.system(size: 10, weight: .medium))
      }
      .foregroundStyle(on ? theme.amber : theme.ink3)
      .padding(.top, 7)
      .padding(.bottom, 6)
      .frame(maxWidth: .infinity)
      .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
    .accessibilityAddTraits(on ? [.isSelected] : [])
  }
}

/// 图区右下角的「回到最新」（G14）。
///
/// 视野离开最新一根就淡入，回到最新就淡出。位置按原型：离右 60pt——刚好让开价格轴，
/// 离底 28pt。
/// 一句话提示，1.6 秒后自己消失（原型 `.toast`）。
struct Toast: View {
  var theme: PanelTheme
  var text: String

  var body: some View {
    Text(text)
      .font(.system(size: 12.5))
      .foregroundStyle(theme.ink)
      .padding(.horizontal, 14)
      .padding(.vertical, 8)
      .background(
        RoundedRectangle(cornerRadius: 20).fill(theme.raised)
          .overlay(RoundedRectangle(cornerRadius: 20).stroke(theme.line, lineWidth: 1)))
      .shadow(color: .black.opacity(theme.dark ? 0.5 : 0.12), radius: 12, y: 4)
      .transition(.opacity)
  }
}
