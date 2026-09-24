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
  /// 只有画线工作台传它，别处一律 `nil`——竖屏行情页的品种名不是按钮，
  /// 横屏看行情时也不是。理由见 `DrawingSymbolSwitcher` 顶上那段。
  var onTapSymbol: (() -> Void)?

  private var up: Bool { (changePercent ?? 0) >= 0 }
  /// 拆法和 `TopBar` 同一把：`SymbolInfo.placeholder` 认得币安裸代号和别家带分隔的代号。
  private var pair: (base: String, quote: String) {
    let info = SymbolInfo.placeholder(symbol: symbol)
    return (info.base, info.quote)
  }

  var body: some View {
    HStack(spacing: Space.s) {
      // 和竖屏顶栏同一个写法「BTC/USDT」：基础币正文色、计价币降一级（审查 U11——
      // 原来写的是裸代号「BTCUSDT」，转个屏品种名就换了个样子）。
      HStack(alignment: .firstTextBaseline, spacing: 1) {
        Text(pair.base)
          .font(TypeScale.controlOn)
          .foregroundStyle(theme.ink)
        if !pair.quote.isEmpty {
          Text("/" + pair.quote)
            .font(TypeScale.caption2Emph)
            .foregroundStyle(theme.ink3)
        }
      }
      if onTapSymbol != nil {
        // 原来 8 号粗体，是全 app 最小的一个记号；和别处的列表箭头统一成一个尺寸。
        VectorIcon.chevron(ControlMetrics.chevron)
          .foregroundStyle(theme.ink3)
          .padding(.leading, -Space.xs)
      }
      if let price {
        // 横屏这颗药丸和竖屏顶栏是同一口价，写法也必须一样（审查 B-07）。
        Text(fmtPrice(price, decimals: decimals))
          .font(TypeScale.controlOn).monospacedDigit()
          .foregroundStyle(up ? theme.up : theme.down)
      }
      if let changePercent, changePercent.isFinite {
        Text(changePercentText(changePercent))
          .font(TypeScale.caption2Emph).monospacedDigit()
          .foregroundStyle(up ? theme.up : theme.down)
      }
    }
    .padding(.horizontal, Space.m)
    .padding(.vertical, Space.xs)
    .background(Capsule().fill(theme.raised2.opacity(0.82)))
    // 画线工作台里它是换品种的按钮：画面还是这颗矮胶囊，点击区上下撑到 44，
    // 多出来的高度用负边距还给布局，图例位不因此变高。
    .frame(minHeight: onTapSymbol == nil ? nil : Hit.min)
    .padding(.vertical, onTapSymbol == nil ? 0 : -(Hit.min - ControlMetrics.pillHeight) / 2)
    .contentShape(Rectangle())
    .dynamicTypeSize(...MarketChrome.typeCap)
    .onTapGesture { onTapSymbol?() }
    .accessibilityElement(children: .combine)
    .accessibilityAddTraits(onTapSymbol == nil ? [] : .isButton)
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
        VStack(spacing: 0) {
          ForEach(list, id: \.self) { chip($0) }
        }
        .padding(.vertical, Space.xs)
      }
      Button(action: onMore) {
        VectorIcon.chevron(ControlMetrics.chevron)
          .foregroundStyle(theme.ink2)
          .frame(maxWidth: .infinity, minHeight: Hit.min)
          // 横屏下「更多」在底，分隔线也就从左边挪到顶上（原型 `.land .pmore`）。
          .overlay(alignment: .top) { Rectangle().fill(theme.line).frame(height: 1) }
          .contentShape(Rectangle())
      }
      .buttonStyle(.plain)
      .accessibilityLabel("更多周期")
    }
    .frame(width: 52)
    .overlay(alignment: .trailing) { Rectangle().fill(theme.line).frame(width: 1) }
    .dynamicTypeSize(...MarketChrome.typeCap)
  }

  private func chip(_ iv: Interval) -> some View {
    let on = iv == current
    return Button { onPick(iv) } label: {
      Text(iv.shortLabel)
        .font(on ? TypeScale.controlOn : TypeScale.control)
        .foregroundStyle(on ? theme.amber : theme.ink2)
        // 每档一格 44 高（原来 13 号字上下各 8，约 32）：竖着排七八档仍然一屏装下。
        .frame(maxWidth: .infinity, minHeight: Hit.min)
        .overlay(alignment: .bottom) {
          if on {
            Capsule()
              .fill(theme.amber)
              .frame(height: Space.xxs)
              .padding(.horizontal, Space.s)
              .padding(.bottom, Space.s)
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
/// 工具列、撤销 / 重做、完成都在画线自己那根 `DrawingDock` 上，不在这儿重复一份。
///
/// **画线进行中这条竖栏整条不出现**（2026-09-23）：那时「画线」等于退出画线、「竖屏」也是
/// 退法之一，两格都和画线栏上的「完成」重复。开工入口和出口都只在不画线的时候需要。
struct ToolRail: View {
  var theme: PanelTheme
  var onDraw: () -> Void
  var onPortrait: () -> Void

  var body: some View {
    VStack(spacing: 0) {
      Spacer(minLength: 0)
      item(VectorIcon.draw, "画线", on: false, action: onDraw)
        .accessibilityIdentifier("land.draw")
      item(VectorIcon.landscape, "竖屏", on: false, action: onPortrait)
        .accessibilityIdentifier("land.exit")
      Spacer(minLength: 0)
    }
    .frame(width: 52)
    .background(theme.app)
    .overlay(alignment: .leading) { Rectangle().fill(theme.line).frame(width: 1) }
    .dynamicTypeSize(...MarketChrome.typeCap)
  }

  private func item(
    _ icon: VectorIcon, _ title: String, on: Bool, action: @escaping () -> Void
  ) -> some View {
    Button(action: action) {
      // 记号 22 的框（和画线栏同一个尺寸，见 `DrawChrome`），字 11（原来 9，低于下限）。
      // 52 宽的竖栏里「画线」「竖屏」两个字 11 号只要 22pt，不用改成只剩图标。
      VStack(spacing: Space.xxs) {
        sized(icon)
        Text(title).font(TypeScale.caption2Emph).lineLimit(1).fixedSize()
      }
      .foregroundStyle(on ? theme.amber : theme.ink2)
      .frame(maxWidth: .infinity, minHeight: Hit.min)
      .padding(.vertical, Space.s)
      .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
    .accessibilityAddTraits(on ? [.isSelected] : [])
  }

  private func sized(_ icon: VectorIcon) -> VectorIcon {
    var icon = icon
    icon.size = DrawChrome.icon
    return icon
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
