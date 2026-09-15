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
  /// 右端「记」：把当前这张图记进复盘本。
  ///
  /// 以前它是浮在主图上的一颗可拖动圆钮。浮在图上就一定挡图——K 线、均线、
  /// 最新价标签，它停在哪儿就糊掉哪一块，还在画布上挖了一块点不动的死区。
  /// 挪到这根条上跟「画线」「图表」作伴：一个像素都不占图，横屏工具栏本来也是
  /// 这么摆的（`ToolRail` 的「记」），两个方向终于是同一套。
  var onRecord: (() -> Void)?

  /// 条上永远只排常用那几档，**顺序固定**。
  ///
  /// 原来是 `[current] + quick`：从「更多」里选了个不在常用里的周期（比如 2h），
  /// 它会被插到最前面，后面六个 chip 整体右移一格。用户照着肌肉记忆点「第二个是 5m」，
  /// 点到的是 1m。冷门周期改成显示在「更多」按钮上（`更多 · 2h`），位置一个都不动。
  private var list: [Interval] { quick }
  /// 当前这档不在常用里时，把它挂到「更多」上，否则条上一个高亮都没有。
  private var offQuick: Interval? { quick.contains(current) ? nil : current }

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
      tail(offQuick.map { "更多 · " + $0.rawValue } ?? "更多", chevron: true,
           on: offQuick != nil, action: onMore)
        .accessibilityIdentifier("interval.more")
      tail("画线", chevron: false, on: drawing, action: onDraw)
        .accessibilityIdentifier("interval.draw")
        .accessibilityAddTraits(drawing ? [.isSelected] : [])
      if let onRecord {
        tail("记", chevron: false, action: onRecord)
          .accessibilityIdentifier("interval.record")
          .accessibilityLabel("记一笔")
      }
      tail("图表", chevron: false, action: onChart)
        .accessibilityIdentifier("interval.chart")
    }
    .fixedSize(horizontal: false, vertical: true)
  }

  /// 条右端那种按钮：左边一条分隔线、顶天立地、13pt 次级字。
  ///
  /// 「更多」带下箭头（那是从条上往下拉出一屏周期），「图表」不带（它开的是另一页设置，
  /// 不是这根条的延伸）。`on` 是「这个按钮代表的状态正生效」——当前周期不在常用里的
  /// 「更多 · 2h」、以及正处在画线态的「画线」，都用琥珀色，跟 chip 的选中色一致。
  private func tail(
    _ title: String, chevron: Bool, on: Bool = false, action: @escaping () -> Void
  ) -> some View {
    Button(action: action) {
      HStack(spacing: 3) {
        Text(title).font(.system(size: 13, weight: .medium))
        if chevron { VectorIcon.chevron(10) }
      }
      .foregroundStyle(on ? theme.amber : theme.ink2)
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
