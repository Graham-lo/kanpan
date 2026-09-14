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

  private var list: [Interval] {
    quick.contains(current) ? quick : [current] + quick
  }

  var body: some View {
    HStack(spacing: 0) {
      ScrollView(.horizontal, showsIndicators: false) {
        HStack(spacing: 2) {
          ForEach(list, id: \.self) { iv in
            chip(iv)
          }
        }
        .padding(.horizontal, 4)
      }
      Button(action: onMore) {
        HStack(spacing: 3) {
          Text("更多").font(.system(size: 13, weight: .medium))
          VectorIcon.chevron(10)
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
    .fixedSize(horizontal: false, vertical: true)
  }

  private func chip(_ iv: Interval) -> some View {
    let on = iv == current
    return Button { onPick(iv) } label: {
      Text(iv.rawValue)
        .font(.system(size: 13, weight: .medium))
        .foregroundStyle(on ? theme.amber : theme.ink2)
        .padding(.horizontal, 10)
        .padding(.vertical, 9)
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
