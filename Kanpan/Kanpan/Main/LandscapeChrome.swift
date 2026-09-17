import KanpanCore
import SwiftUI

/// 横屏的三件外壳（§10.7）：左边竖排周期、右边竖排工具、图区左上角那一行小字。
///
/// 竖屏那套控件在横屏下一个都不复用：横排的 chip 竖过来会太宽，底栏五项摊平在
/// 874pt 上每项 175pt 宽、图却只剩 300pt 高——横屏的全部意义就是把高度让给图。

/// 顶栏在横屏下缩成一行小字，叠在图例位上，不占高度。
struct LandscapeHeadline: View {
  var theme: PanelTheme
  var symbol: String
  var price: Double?
  var changePercent: Double?
  var decimals: Int
  var onSymbol: () -> Void

  private var up: Bool { (changePercent ?? 0) >= 0 }

  var body: some View {
    Button(action: onSymbol) {
      HStack(spacing: 8) {
        Text(symbol)
          .font(.system(size: 13, weight: .semibold))
          .foregroundStyle(theme.ink)
        if let price {
          Text(fmtNum(price, decimals))
            .font(.system(size: 13, weight: .semibold).monospacedDigit())
            .foregroundStyle(up ? theme.up : theme.down)
        }
        if let changePercent, changePercent.isFinite {
          Text((changePercent >= 0 ? "+" : "") + toFixed(changePercent, 2) + "%")
            .font(.system(size: 11, weight: .medium).monospacedDigit())
            .foregroundStyle(up ? theme.up : theme.down)
        }
        VectorIcon.chevron(9).foregroundStyle(theme.ink3)
      }
      .padding(.horizontal, 9)
      .padding(.vertical, 5)
      .background(Capsule().fill(theme.raised2.opacity(0.82)))
      .contentShape(Capsule())
    }
    .buttonStyle(.plain)
    .accessibilityIdentifier("land.symbol")
  }
}

/// 周期竖排贴左，宽 52pt（原型 `.screen.land .periods`）。可上下滚。
struct IntervalRail: View {
  var theme: PanelTheme
  var quick: [Interval]
  var current: Interval
  var onPick: (Interval) -> Void
  var onMore: () -> Void

  private var list: [Interval] {
    quick.contains(current) ? quick : [current] + quick
  }

  var body: some View {
    VStack(spacing: 0) {
      ScrollView(.vertical, showsIndicators: false) {
        VStack(spacing: 2) {
          ForEach(list, id: \.self) { chip($0) }
        }
        .padding(.vertical, 4)
      }
      Button(action: onMore) {
        VectorIcon.chevron(11)
          .foregroundStyle(theme.ink2)
          .frame(maxWidth: .infinity)
          .padding(.vertical, 8)
          // 横屏下「更多」在底，分隔线也就从左边挪到顶上（原型 `.land .pmore`）。
          .overlay(alignment: .top) { Rectangle().fill(theme.line).frame(height: 1) }
          .contentShape(Rectangle())
      }
      .buttonStyle(.plain)
      .accessibilityLabel("更多周期")
    }
    .frame(width: 52)
    .overlay(alignment: .trailing) { Rectangle().fill(theme.line).frame(width: 1) }
  }

  private func chip(_ iv: Interval) -> some View {
    let on = iv == current
    return Button { onPick(iv) } label: {
      Text(iv.rawValue)
        .font(.system(size: 13, weight: .medium))
        .foregroundStyle(on ? theme.amber : theme.ink2)
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
        .overlay(alignment: .bottom) {
          if on {
            RoundedRectangle(cornerRadius: 2)
              .fill(theme.amber)
              .frame(height: 2)
              .padding(.horizontal, 6)
              .padding(.bottom, 2)
          }
        }
        .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
    .accessibilityLabel(iv.display)
    .accessibilityAddTraits(on ? [.isSelected] : [])
  }
}

/// 右侧竖排工具条：画线 · 回竖屏。
///
/// 横屏不是一个独立的行情界面，它是**画线的工作台**——点「画线」自动横屏，点「完成」
/// 自动转回。这条竖栏上原来还排着 记 / 复盘 / 指标 / 图表 / 设置，那是照着「横竖屏
/// 各用 5 分钟、全部功能可达」一条条补出来的，结果横屏被做成了竖屏的缩小复刻：
/// 手边七格里有五格和画线无关，真正要用的工具列反倒被挤到另一根竖栏上。
/// 这五件事竖屏全都到得了（记 / 复盘在底栏，指标 / 图表 / 设置在底栏与周期条尾巴上），
/// 功能一件没丢。
///
/// 留下的两格各有各的理由：
/// - 「画线」是横屏里唯一的开工入口。用手把机器转过来的时候画线态还没开，没有它
///   就得转回竖屏点一下再转过来。
/// - 「竖屏」是出口。锁了方向的手机转不回去，没有它横屏就是一张单程票。
///
/// 工具列、撤销 / 重做、完成都在画线自己那根 `DrawingRail` 上，不在这儿重复一份。
struct ToolRail: View {
  var theme: PanelTheme
  var drawing: Bool
  var onDraw: () -> Void
  var onPortrait: () -> Void

  var body: some View {
    VStack(spacing: 0) {
      Spacer(minLength: 0)
      item(VectorIcon.draw, "画线", on: drawing, action: onDraw)
      item(VectorIcon.landscape, "竖屏", on: false, action: onPortrait)
        .accessibilityIdentifier("land.exit")
      Spacer(minLength: 0)
    }
    .frame(width: 52)
    .background(theme.app)
    .overlay(alignment: .leading) { Rectangle().fill(theme.line).frame(width: 1) }
  }

  private func item(
    _ icon: VectorIcon, _ title: String, on: Bool, action: @escaping () -> Void
  ) -> some View {
    Button(action: action) {
      VStack(spacing: 3) {
        icon
        Text(title).font(.system(size: 9, weight: .medium))
      }
      .foregroundStyle(on ? theme.amber : theme.ink3)
      .frame(maxWidth: .infinity)
      .padding(.vertical, 9)
      .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
    .accessibilityAddTraits(on ? [.isSelected] : [])
  }
}

/// 横屏下的面板：从右边滑进来的侧栏，不盖图的左 2/3（§10.7）。
///
/// 竖屏用的是系统 sheet，横屏这儿不能用——半屏 sheet 在 compact 高度下会顶到全屏，
/// 图就整个没了。所以横屏自己铺一层。
struct SidePanelLayer<Content: View>: View {
  var theme: PanelTheme
  var shown: Bool
  var onClose: () -> Void
  @ViewBuilder var content: () -> Content

  /// 任务书写 320pt。原型那份 `min(420px, 62%)` 是台面上那个缩放过的机型框里的数，
  /// 搬到真机上会盖掉将近一半的图，和同一句里的「不盖图的左 2/3」自相矛盾——
  /// 取任务书的 320（在 16 Pro 横屏 874pt 上占 36.6%，正好压在 1/3 线上）。
  private let width: CGFloat = 320

  var body: some View {
    ZStack(alignment: .trailing) {
      if shown {
        // 面板外的点击只关闭侧栏，不触发底下控件。
        Color.black.opacity(0.18)
          .ignoresSafeArea()
          .overlay { PanelDismissShield(onDismiss: onClose) }
          .transition(.opacity)
        content()
          .frame(width: width)
          .frame(maxHeight: .infinity)
          .background(theme.raised)
          .overlay(alignment: .leading) { Rectangle().fill(theme.line).frame(width: 1) }
          .transition(.move(edge: .trailing))
      }
    }
    .animation(.spring(duration: 0.28), value: shown)
  }
}
