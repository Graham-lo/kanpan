import KanpanCore
import SwiftUI

/// 周期条：常用几档横排 + 右端「更多」（§9.1）。
///
/// 常用档由设置里的 `quickIntervals` 决定（A6.5）；当前这档不在常用里也要出现，
/// 否则从面板里选了个冷门周期，条上会一个都不高亮——原型 `renderPeriods()` 同样处理。
struct IntervalBar: View {
  var theme: PanelTheme
  var quick: [Interval]
  var current: Interval
  var onPick: (Interval) -> Void
  var onMore: () -> Void
  /// 右端「图表」：开 K 线设置那一页（`Panel.chart`）。
  ///
  /// 画线与图表设置放在周期条，底栏保留自选入口。
  var onChart: () -> Void
  var drawing: Bool = false
  var onDraw: () -> Void = {}

  private var list: [Interval] {
    quick.contains(current) ? quick : [current] + quick
  }

  var body: some View {
    HStack(spacing: 0) {
      ScrollView(.horizontal, showsIndicators: false) {
        HStack(spacing: 2) {
          ForEach(list, id: \.self) { iv in
            chip(iv)
              .accessibilityIdentifier("interval.chip.\(iv.rawValue)")
          }
        }
        .padding(.horizontal, 4)
      }
      .accessibilityIdentifier("interval.quick")
      tail("画线", chevron: false, action: onDraw)
        .accessibilityIdentifier("interval.draw")
        .accessibilityAddTraits(drawing ? [.isSelected] : [])
      tail("更多", chevron: true, action: onMore)
        .accessibilityIdentifier("interval.more")
      tail("图表", chevron: false, action: onChart)
        .accessibilityIdentifier("interval.chart")
    }
    .fixedSize(horizontal: false, vertical: true)
  }

  /// 条右端那种按钮：左边一条分隔线、顶天立地、13pt 次级字。
  ///
  /// 「更多」带下箭头（那是从条上往下拉出一屏周期），「图表」不带（它开的是另一页设置，
  /// 不是这根条的延伸）。
  private func tail(_ title: String, chevron: Bool, action: @escaping () -> Void) -> some View {
    Button(action: action) {
      HStack(spacing: 3) {
        Text(title).font(.system(size: 13, weight: .medium))
        if chevron { VectorIcon.chevron(10) }
      }
      .foregroundStyle(theme.ink2)
      .padding(.horizontal, 11)
      .frame(maxHeight: .infinity)
      .overlay(alignment: .leading) {
        Rectangle().fill(theme.line).frame(width: 1)
      }
      .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
  }

  private func chip(_ iv: Interval) -> some View {
    let on = iv == current
    return Button { onPick(iv) } label: {
      Text(iv.rawValue)
        .font(.system(size: 13, weight: .medium))
        .foregroundStyle(on ? theme.amber : theme.ink2)
        .padding(.horizontal, 10)
        .frame(minHeight: 44)
        .overlay(alignment: .bottom) {
          // 选中那一档底下的琥珀小横杠：左右各缩 10pt、离底 4pt（原型 `.pchip.on::after`）。
          if on {
            RoundedRectangle(cornerRadius: 2)
              .fill(theme.amber)
              .frame(height: 2)
              .padding(.horizontal, 10)
              .padding(.bottom, 4)
          }
        }
        .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
    .accessibilityLabel(iv.display)
    .accessibilityAddTraits(on ? [.isSelected] : [])
  }
}
