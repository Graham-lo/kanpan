import SwiftUI

/// 底部工具条五个：风格 · 指标 · 画线 · 设置 · 横屏（§9.1）。
struct BottomBar: View {
  var theme: PanelTheme
  /// 哪个亮着。面板开着时对应那个是琥珀色（原型 `syncTools()`）。
  var active: Panel?
  var drawing: Bool
  var onPanel: (Panel) -> Void
  var onDraw: () -> Void
  var onLandscape: () -> Void

  var body: some View {
    HStack(spacing: 0) {
      tool(.style, VectorIcon.style, "风格") { onPanel(.style) }
      tool(.indicator, VectorIcon.indicator, "指标") { onPanel(.indicator) }
      item(VectorIcon.draw, "画线", on: drawing, action: onDraw)
      tool(.settings, VectorIcon.settings, "设置") { onPanel(.settings) }
      item(VectorIcon.landscape, "横屏", on: false, action: onLandscape)
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
struct LatestButton: View {
  var theme: PanelTheme
  var shown: Bool
  var action: () -> Void

  var body: some View {
    Button(action: action) {
      VectorIcon.chevronRight()
        .foregroundStyle(theme.ink2)
        .frame(width: 30, height: 30)
        .background(Circle().fill(theme.app.opacity(0.92)))
        .overlay(Circle().stroke(theme.line, lineWidth: 1))
    }
    .buttonStyle(.plain)
    .accessibilityLabel("回到最新")
    .padding(.trailing, 60)
    .padding(.bottom, 28)
    .opacity(shown ? 1 : 0)
    .allowsHitTesting(shown)
    .animation(.easeOut(duration: 0.15), value: shown)
  }
}

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
