import KanpanCore
import SwiftUI

/// 周期条：常用几档横排 + 右端「更多」（§9.1）。
///
/// 常用档由设置里的 `quickIntervals` 决定（A6.5）；当前这档不在常用里也要出现，
/// 否则从面板里选了个冷门周期，条上会一个都不高亮——原型 `renderPeriods()` 同样处理。
///
/// 右端只留「更多」和「图表」两颗。「画线」和「记一笔」原来也常驻在这儿，用户的话是
/// 「这个功能不是经常用到啊」「记和画线都放到图表栏目里」——一天点不了一次的东西
/// 不该跟周期抢常驻位置，两个都收进「图表」那一页（见 `ChartPanel`）。
struct IntervalBar: View {
  var theme: PanelTheme
  var quick: [Interval]
  var current: Interval
  var onPick: (Interval) -> Void
  var onMore: () -> Void
  /// 右端「图表」：开 K 线那一页（`Panel.chart`）。画线、记一笔也在那一页上。
  var onChart: () -> Void
  /// 条上永远只排常用那几档，**顺序固定**。
  ///
  /// 原来是 `[current] + quick`：从「更多」里选了个不在常用里的周期（比如 2h），
  /// 它会被插到最前面，后面六个 chip 整体右移一格。用户照着肌肉记忆点「第二个是 5m」，
  /// 点到的是 1m。冷门周期改成显示在「更多」按钮上（`更多 · 2h`），位置一个都不动。
  private var list: [Interval] { quick }
  /// 当前这档不在常用里时，把它挂到「更多」上，否则条上一个高亮都没有。
  private var offQuick: Interval? { quick.contains(current) ? nil : current }

  /// 常用档那一排实际有多宽 / 横条能露出多宽。只为了判断「到底排得下排不下」。
  @State private var contentWidth: CGFloat = 0
  @State private var viewportWidth: CGFloat = 0
  /// 排不下才需要那道淡出。默认七档在 iPhone 16 Pro 上正好是临界，差一两个点就翻面，
  /// 留半点余量免得来回抖。
  private var overflows: Bool { contentWidth > viewportWidth + 1 }

  var body: some View {
    HStack(spacing: 6) {
      ScrollView(.horizontal, showsIndicators: false) {
        // 间距和药丸内边距都比原来紧一点点：常用行从六档加到七档（用户：「现在周期
        // 这一行就只剩下更多和图表，可以展示更多的周期了」），差的就是这十几个点。
        HStack(spacing: 4) {
          ForEach(list, id: \.self) { iv in
            chip(iv)
              .accessibilityIdentifier("interval.chip.\(iv.rawValue)")
          }
        }
        .padding(.horizontal, 2)
        .background(GeometryReader { g in
          Color.clear.preference(key: IntervalRowWidth.self, value: g.size.width)
        })
      }
      .accessibilityIdentifier("interval.quick")
      .onPreferenceChange(IntervalRowWidth.self) { contentWidth = $0 }
      .background(GeometryReader { g in
        Color.clear.preference(key: IntervalViewportWidth.self, value: g.size.width)
      })
      .onPreferenceChange(IntervalViewportWidth.self) { viewportWidth = $0 }
      // 常用档排不下时右边会切出半颗药丸，硬切看着像画错了。
      // 让它在最后那几个点里淡出去，一眼就知道「右边还有，滑一下」。
      //
      // 排得下就一点都不淡：七档刚好占满，那道淡出会正压在最后一颗「1d」的右半边上，
      // 好端端一颗药丸看着像被啃掉一口，反而像画错了。
      .mask(LinearGradient(
        stops: overflows
          ? [.init(color: .black, location: 0),
             .init(color: .black, location: 0.93),
             .init(color: .black.opacity(0), location: 1)]
          : [.init(color: .black, location: 0), .init(color: .black, location: 1)],
        startPoint: .leading, endPoint: .trailing))
      tail(offQuick.map { "更多 · " + $0.rawValue } ?? "更多", chevron: true,
           on: offQuick != nil, action: onMore)
        .accessibilityIdentifier("interval.more")
      tail("图表", chevron: false, action: onChart)
        .accessibilityIdentifier("interval.chart")
    }
    .padding(.horizontal, 10)
    .frame(height: 44)
  }

  /// 条右端那几颗：和周期一样是药丸，只是底色深一档（原型 `.draw` 用的是 `surf2`），
  /// 好让「选哪一档周期」和「开哪个工具」在一条线上仍然分得开。
  ///
  /// 「更多」带下箭头（那是从条上往下拉出一屏周期），「图表」不带（它开的是另一页，
  /// 不是这根条的延伸）。`on` 是「这个按钮代表的状态正生效」——当前周期不在常用里时
  /// 「更多 · 2h」按选中那一档的样子填色。
  private func tail(
    _ title: String, chevron: Bool, on: Bool = false, action: @escaping () -> Void
  ) -> some View {
    Button(action: action) {
      HStack(spacing: 3) {
        Text(title).font(.system(size: 12.5, weight: .semibold))
        if chevron { VectorIcon.chevron(9, w: 1.7) }
      }
      .foregroundStyle(on ? theme.badgeInk : theme.ink2)
      .padding(.horizontal, 9)
      .frame(height: 28)
      .background(on ? AnyShapeStyle(theme.amber) : AnyShapeStyle(theme.raised2),
                  in: Capsule())
      .contentShape(Capsule())
    }
    .buttonStyle(.plain)
  }

  /// 一档周期：没选中是一颗浅底药丸，选中了整颗填强调色。
  /// 原来是「字变色 + 底下一条小横杠」，横杠只有 2pt 高，滑动时几乎看不出来哪档亮着。
  private func chip(_ iv: Interval) -> some View {
    let on = iv == current
    return Button { onPick(iv) } label: {
      Text(iv.rawValue)
        .font(.system(size: 12.5, weight: on ? .semibold : .medium))
        .foregroundStyle(on ? theme.badgeInk : theme.ink2)
        .padding(.horizontal, 8)
        .frame(height: 28)
        .background(on ? AnyShapeStyle(theme.amber) : AnyShapeStyle(theme.raised),
                    in: Capsule())
        .contentShape(Capsule())
    }
    .buttonStyle(.plain)
    .accessibilityLabel(iv.display)
    .accessibilityAddTraits(on ? [.isSelected] : [])
  }
}

/// 常用档那一排排出来有多宽（含两头 2pt 内边距）。
private struct IntervalRowWidth: PreferenceKey {
  static let defaultValue: CGFloat = 0
  static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = nextValue() }
}

/// 横条自己能露出多宽。和上面那个一比就知道排不排得下。
private struct IntervalViewportWidth: PreferenceKey {
  static let defaultValue: CGFloat = 0
  static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = nextValue() }
}
