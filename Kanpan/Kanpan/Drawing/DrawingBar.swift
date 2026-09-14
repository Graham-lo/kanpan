import KanpanChart
import KanpanCore
import SwiftUI

/// 画线底栏：趋势线 / 水平线 / 删除 / 完成（A7.1，原型 `.drawbar`）。
///
/// 四颗按钮的排布照原型：两颗工具靠左，`删除` 用 `margin-left: auto` 顶到右边、
/// 用跌色，`完成` 收尾。选中的工具是 amber 描边 + `amberSoft` 底。
struct DrawingBar: View {
  @ObservedObject var controller: DrawingController
  @Environment(\.panelTheme) private var theme

  var body: some View {
    HStack(spacing: 4) {
      button("/ 趋势线", on: controller.tool == .trend) { controller.pick(.trend) }
        .accessibilityIdentifier("draw.trend")
      button("— 水平线", on: controller.tool == .hline) { controller.pick(.hline) }
        .accessibilityIdentifier("draw.hline")
      Spacer(minLength: 0)
      button("删除", on: false, danger: true, enabled: controller.canDelete) {
        controller.deleteSelected()
      }
      .accessibilityIdentifier("draw.delete")
      button("完成", on: false) { controller.finish() }
        .accessibilityIdentifier("draw.finish")
    }
    .padding(.horizontal, 8)
    .padding(.vertical, 7)
    .background(theme.raised)
    .overlay(alignment: .top) { theme.line.frame(height: 0.5) }
  }

  private func button(
    _ title: String, on: Bool, danger: Bool = false, enabled: Bool = true,
    action: @escaping () -> Void
  ) -> some View {
    Button(action: action) {
      Text(title)
        .font(PanelFont.seg)
        .foregroundStyle(on ? theme.amber : (danger ? theme.down : theme.ink2))
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(
          RoundedRectangle(cornerRadius: 8).fill(on ? theme.amberSoft : .clear)
        )
        .overlay(
          RoundedRectangle(cornerRadius: 8).stroke(on ? theme.amberLine : .clear, lineWidth: 1)
        )
    }
    .buttonStyle(.plain)
    .disabled(!enabled)
    .opacity(enabled ? 1 : 0.35)
  }
}

/// 图区顶上那一行提示：「点两下画一条趋势线」→ 落第一点后「再点一下」（§10.8）。
///
/// 撤销 / 重做放在这一行的右端，不进底栏——A7.1 把底栏钉死成四项了
/// （见 `docs/acceptance/M7.md` 的分歧记录）。
struct DrawingHintStrip: View {
  @ObservedObject var controller: DrawingController
  @Environment(\.panelTheme) private var theme

  var body: some View {
    if let hint = controller.hint {
      HStack(spacing: 10) {
        Text(hint)
          .font(PanelFont.note)
          .foregroundStyle(theme.ink2)
        Spacer(minLength: 0)
        step("arrow.uturn.backward", enabled: controller.canUndo) { controller.undo() }
        step("arrow.uturn.forward", enabled: controller.canRedo) { controller.redo() }
      }
      .padding(.horizontal, 12)
      .padding(.vertical, 5)
      .background(
        Capsule().fill(theme.raised).overlay(Capsule().stroke(theme.line, lineWidth: 0.5))
      )
      .padding(.horizontal, 12)
      .allowsHitTesting(true)
    }
  }

  private func step(_ symbol: String, enabled: Bool, action: @escaping () -> Void) -> some View {
    Button(action: action) {
      Image(systemName: symbol)
        .font(.system(size: 12, weight: .medium))
        .foregroundStyle(theme.ink2)
    }
    .buttonStyle(.plain)
    .disabled(!enabled)
    .opacity(enabled ? 1 : 0.35)
  }
}

/// 画线栏的横屏版：同样四项，竖着排在工具栏左边（§10.7）。
///
/// 横屏没有底栏，`DrawingBar` 那条「靠左两颗、删除顶到右边」的排布搬不过来；这里
/// 保持同样的**顺序**（趋势线 · 水平线 · 删除 · 完成），把「删除顶到另一端」换成
/// 一条分隔线——竖排里再用 `Spacer` 撑开会把四颗按钮拉到屏幕两头，够不着。
struct DrawingRail: View {
  @ObservedObject var controller: DrawingController
  @Environment(\.panelTheme) private var theme

  var body: some View {
    VStack(spacing: 4) {
      button("趋势线", glyph: "/", on: controller.tool == .trend) { controller.pick(.trend) }
      button("水平线", glyph: "—", on: controller.tool == .hline) { controller.pick(.hline) }
      theme.line.frame(height: 0.5).padding(.horizontal, 8)
      button("删除", glyph: nil, on: false, danger: true, enabled: controller.canDelete) {
        controller.deleteSelected()
      }
      button("完成", glyph: nil, on: false) { controller.finish() }
      Spacer(minLength: 0)
    }
    .padding(.vertical, 8)
    .frame(width: 52)
    .background(theme.raised)
    .overlay(alignment: .leading) { theme.line.frame(width: 0.5) }
  }

  private func button(
    _ title: String, glyph: String?, on: Bool, danger: Bool = false, enabled: Bool = true,
    action: @escaping () -> Void
  ) -> some View {
    Button(action: action) {
      VStack(spacing: 1) {
        if let glyph {
          Text(glyph).font(.system(size: 13, weight: .semibold))
        }
        Text(title).font(.system(size: 10, weight: .medium))
      }
      .foregroundStyle(on ? theme.amber : (danger ? theme.down : theme.ink2))
      .frame(maxWidth: .infinity)
      .padding(.vertical, 6)
      .background(RoundedRectangle(cornerRadius: 8).fill(on ? theme.amberSoft : .clear))
      .overlay(
        RoundedRectangle(cornerRadius: 8).stroke(on ? theme.amberLine : .clear, lineWidth: 1)
      )
      .padding(.horizontal, 4)
    }
    .buttonStyle(.plain)
    .disabled(!enabled)
    .opacity(enabled ? 1 : 0.35)
  }
}
