import KanpanCore
import SwiftUI

/// 「画线」面板：十二把工具，三列四行，一屏摆完。
///
/// 这块原来是照 TradingView 做的——搜索框 + 九格分类标签 + 41 把工具的网格，
/// 还带一颗收藏星。那是 41 把工具逼出来的排布：格子一屏放不下，就得先分类再翻页，
/// 翻着费劲就得给搜索，找到了还得能收藏起来下次少翻一次。
///
/// 2026-09-22 用户把工具砍到 12 把之后，这三样一个都不需要了：一屏就是全部，
/// 分类标签只会在十二个格子上面再压一条横滚的栏；搜索框是给记得住名字的人用的，
/// 而十二个记号本身就看得懂；收藏是给「翻不到」准备的解法，没得翻就没有这个问题。
/// 所以这里只剩标题、关闭和格子——退出去的那几把画法收进了样式表（`Drawing.Kind.swaps`）。
///
/// 横竖屏共用这一个视图：竖屏是一张半屏表单，横屏是贴着左边的一块卡片。所以它自己不带
/// `NavigationStack`，标题和关闭都画在里面——两种呈现方式下长得一模一样。
struct DrawingToolPicker: View {
  var controller: DrawingController
  /// 「上次用的是哪把工具」存在哪。见 `tile(_:)`。
  var store: PrefsStore
  var onClose: () -> Void
  @Environment(\.panelTheme) private var theme

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      header
      grid
    }
    .background(theme.raised)
  }

  private var header: some View {
    HStack {
      // 标题和其它面板同一档（17 semibold）；原来 20 是全 app 唯一一处。
      Text("画线").font(TypeScale.title).foregroundStyle(theme.ink)
      Spacer()
      Button(action: onClose) {
        Image(systemName: "xmark").font(TypeScale.captionEmph)
          .frame(width: ControlMetrics.iconDisc, height: ControlMetrics.iconDisc)
          .background(theme.raised2, in: Circle())
          .hitTarget()
      }
      .buttonStyle(.plain).foregroundStyle(theme.ink2)
      .accessibilityLabel("关闭").accessibilityIdentifier("draw.sheet.done")
    }
    .padding(.leading, Inset.card)
    // 关闭钮的圆托底落在右缘 `hPad` 上：44 的点击区比托底宽，多出来的那半截借进边距。
    .padding(.trailing, Inset.card - (Hit.min - ControlMetrics.iconDisc) / 2)
    .padding(.vertical, Space.xs)
  }

  /// 仍然套一层 `ScrollView`：十二格在最小的机型上也摆得下，但把字号调到 AX 档之后
  /// 每一格会长高，那时候还能往下推一点，而不是把最后一行顶出屏幕。
  private var grid: some View {
    ScrollView {
      LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: Space.m), count: 3), spacing: Space.m) {
        ForEach(Drawing.Kind.palette) { kind in tile(kind) }
      }
      .padding(.horizontal, Inset.card).padding(.top, Space.xs).padding(.bottom, Space.xl)
    }
  }

  /// 一格：图形在上、名字在下。名字就是 `Drawing.Kind.title`，和画线栏、横屏那根条上写的一字不差。
  private func tile(_ kind: Drawing.Kind) -> some View {
    // 手上正举着的那把优先；空着手的时候把「上次用的那把」预选高亮出来。
    //
    // 这两件事必须分清：**待画状态**换品种就该清掉（`ChartView+Drawing.resetDrawingInteraction`
    // 里那行 `d.tool = nil` 保持不动），冷启动更不许一进来就举着笔；而**上次用的是
    // 哪把**是习惯，该记住并跨启动保留，只体现在这一格的高亮上（见 `Prefs.lastDrawTool`）。
    // 存着的要是一把已经不在面板上的（老版本留下的「矩形」，或者换过画法的「射线」），
    // 就没有哪一格亮起来——这正是该有的样子，不必去改那个值。
    let picked = controller.tool == kind
      || (controller.tool == nil && store.prefs.lastDrawTool == kind.rawValue)
    return Button { controller.pick(kind) } label: {
      VStack(spacing: Space.s) {
        DrawKindGlyph(kind: kind, size: 30)
        Text(kind.title).font(TypeScale.caption).multilineTextAlignment(.center)
          .lineLimit(2).fixedSize(horizontal: false, vertical: true)
      }
      .padding(.horizontal, Space.xs).padding(.vertical, Space.m)
      .frame(maxWidth: .infinity, minHeight: Hit.min * 2)
      .contentShape(RoundedRectangle(cornerRadius: Radius.m, style: .continuous))
    }
    .buttonStyle(.plain)
    .foregroundStyle(picked ? theme.amber : theme.ink)
    .background(RoundedRectangle(cornerRadius: Radius.m, style: .continuous)
      .fill(picked ? theme.amberSoft : theme.raised2))
    .accessibilityIdentifier("draw.tool.\(kind.rawValue)")
    .drawRepeatOnLongPress(controller, kind)
  }
}
