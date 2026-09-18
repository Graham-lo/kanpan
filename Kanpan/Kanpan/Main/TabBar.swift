import SwiftUI

/// 底栏那四格。
///
/// 2026-09-18 它从「几个入口按钮」改成了常驻标签栏。用户的话是「大部分 app 把常用的
/// 大分页都固定在底部，比如 tv 和推特都是，底部是固定的，切换页面下面还是那样」——
/// 以前「自选」是全屏 cover、「设置」是半屏 sheet、「复盘」是另一层 cover，一层盖一层，
/// 人不知道自己在第几层，只能一路退回去。现在四格各是一张整页，底栏永远在，
/// 换页就是换一格。
///
/// 顺序是用户定死的：**画线 · 图表 · 自选 · 设置**。他的话是「本来行情 app 这个
/// 就很重要」——画线值一格；「复盘放到图表里」，所以复盘不在底栏上（它挪到了行情页
/// 顶栏那颗带角标的按钮），「指标」也不在（并进了「图表设置」）。
enum Tab: String, CaseIterable, Sendable {
  case draw, chart, favorites, settings

  var title: String {
    switch self {
    case .draw: "画线"
    case .chart: "图表"
    case .favorites: "自选"
    case .settings: "设置"
    }
  }

  /// 能不能停在这一格。
  ///
  /// 「画线」是个动作不是去处：点它是「把当前这张图横过来画」，画完自动转回行情页
  /// （见 `kanpan-landscape-is-for-drawing`）。所以它永远不是那个「回来之后还停在
  /// 这儿」的格子，选中态只在真的在画的时候亮。
  var isRestingPlace: Bool { self != .draw }
}

/// 常驻标签栏：四格等宽，谁亮着谁是当前页。
///
/// 2026-09-18 重画了一版视觉，底子是用户在四套方案里挑的 **C「釉面卡片」**。前两版都被否了
/// （「这看起来太工程太后台风了」「一点都不精致好看唯美」），否掉的不是尺寸而是整个画法：
/// 灰色细线线框 + 一行小灰字，正是后台管理系统的长相。这一版换了三件事：
///
/// 1. **底栏没有自己的材料，它就是页面的底。** 这一条起初做成了左右内缩、带发丝边和投影的
///    悬浮卡片，用户看过真机之后连否两次：「好像有点突兀能融合起来吗，因为其它都是融合的」
///    「下方那块区域先是纯白显得不搭，然后四个底栏还悬浮在这块白色区域」。现在卡片、发丝边、
///    投影、渐变带全部没有了，底栏身下平铺的就是 `theme.app`，`ignoresSafeArea` 一直到
///    home 条——整屏只有一块材料，四个记号直接长在上面
///    （`kanpan-no-seams-one-continuous-surface`）。
/// 2. **文字标签全部去掉，空间让给记号。** 用户的话是「其实没必要把名字标出来，
///    这图表 icon 一看就懂」「空间全部留给 icon」。省下那一行字之后记号从 20 放到 36，
///    整条栏反而比带字的时候更矮（见 `kanpan-tab-bar-has-no-text-labels`）。
/// 3. **记号全部重画成实心圆润的造型**，见 `TabGlyph`。
///
/// 交互一点没动：四格、顺序、`isRestingPlace` 和四个 `bottom.*` 标识都照旧。
struct TabBar: View {
  var theme: PanelTheme
  /// 停在哪一页。`draw` 不会是它——见 `Tab.isRestingPlace`。
  var current: Tab
  /// 正在画线。这时候亮的是最左边那格，而不是身下那张行情页。
  var drawing: Bool
  var onPick: (Tab) -> Void

  /// 让选中胶囊在四格之间滑动的那份坐标系。
  @Namespace private var pill

  /// 记号的边长。18 → 20 → 32 → 36：前两次只在原来的画法上往大里推，用户照样说素；
  /// 真正让它撑得住的是「把那行字去掉」——没有字要垫在下面，记号就能占满整格。
  /// 36 是最后一档：用户看过 32 那版之后说「底栏稍微大一点点有辨识性和层次」。
  static let glyph: Double = 36
  /// 记号在卡片里上下各留多少。36 + 11 + 11 = 58，比系统标签栏的 49 高一点点，
  /// 够撑起层次又不至于变成一块面板（用户要的「不能大得特别突兀」）。
  private static let padY: CGFloat = 11
  /// 选中那颗胶囊。比记号宽出一圈，高度只比记号高 14——横着的胶囊才像个「格」。
  private static let pillW: CGFloat = 66
  private static let pillH: CGFloat = 50

  /// 亮着的是哪一格。
  private var active: Tab { drawing ? .draw : current }

  var body: some View {
    HStack(spacing: 0) {
      ForEach(Tab.allCases, id: \.self) { tab in
        item(tab).accessibilityIdentifier("bottom.\(tab.rawValue)")
      }
    }
    .padding(.top, 10)
    .padding(.bottom, 10)
    .background { shelf }
    .animation(.spring(response: 0.34, dampingFraction: 0.82), value: active)
  }

  /// 底栏身下那块底。
  ///
  /// 这儿先后错了两回，都是同一个毛病：给底栏配了一块「自己的」材料。第一版是左右内缩、
  /// 带发丝边和投影的悬浮釉面卡片，第二版把卡片拿掉了但还留着一道沉到 `raised2` 的渐变。
  /// 用户两句话都指着这件事：「好像有点突兀能融合起来吗，因为其它都是融合的」
  /// 「下方那块区域先是纯白显得不搭，然后四个底栏还悬浮在这块白色区域」。
  ///
  /// 所以现在这儿一点花样都没有：就是 `theme.app`，和上面那张页一模一样的底色，平铺到底。
  /// 底栏没有轮廓、没有渐变带、没有明度差，它不是一块托着图标的板子，而是页面自己的底
  /// 在最下面多留出来的一段。屏幕从上到下只有一块材料，图标直接长在上面
  /// （`kanpan-no-seams-one-continuous-surface`）。
  ///
  /// `ignoresSafeArea` 是必须的——home 条那一条也得是同一块底色，否则颜色在安全区边界上
  /// 断一次，那就又是一条拼缝。
  private var shelf: some View {
    theme.app
      .ignoresSafeArea(edges: .bottom)
      .allowsHitTesting(false)
  }

  /// 一格。只有记号，没有字——无障碍那一份由 `accessibilityLabel` 顶上。
  private func item(_ tab: Tab) -> some View {
    let on = tab == active
    return Button { onPick(tab) } label: {
      ZStack {
        if on { selectedPill }
        TabGlyph(tab: tab, theme: theme, on: on)
      }
      .frame(width: Self.pillW, height: Self.pillH)
      .padding(.vertical, Self.padY - (Self.pillH - CGFloat(Self.glyph)) / 2)
      .frame(maxWidth: .infinity)
      .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
    .accessibilityLabel(tab.title)
    .accessibilityAddTraits(on ? [.isSelected] : [])
  }

  /// 选中那格身下的胶囊：一层往下渐淡的强调色玻璃，上沿一条高光，身下一团同色的光。
  ///
  /// 浓度压在 22% 起步：它是**染在页面底色上的一片主色**，不是贴上去的色块。
  ///
  /// 原来它还带一圈白描边和一层投影，那是按「浮在瓷面卡片上的一颗玻璃」画的。卡片没了之后
  /// 这两样也一并去掉——投影意味着它离开了页面，白描边意味着它有自己的边界，两样都和
  /// 「整屏一块材料」相抵。现在只剩渐变本身：上浓下淡，边缘由 `Capsule` 自己收住。
  private var selectedPill: some View {
    Capsule()
      .fill(LinearGradient(
        colors: [theme.amber.opacity(theme.dark ? 0.36 : 0.22),
                 theme.amber.opacity(theme.dark ? 0.14 : 0.08)],
        startPoint: .top, endPoint: .bottom))
      .matchedGeometryEffect(id: "pill", in: pill)
  }
}

/// 底栏那四个记号。
///
/// **它们是实心的，不是线框。** 2026-09-18 之前这四个是单色细描边的示意图——两点连一线的
/// 「画线」、方框加引线的「蜡烛」、六角螺母的「设置」。用户连否两版：「太工程太后台风」
/// 「一点都不精致好看唯美」。线框加细描边在这个项目里就是后台管理系统的味道，描边再粗、
/// 记号再大也救不回来（`kanpan-icons-are-not-wireframes`）。
///
/// 所以现在四个全是实心、圆润、有性格的造型，画在同一个 28 的框里，胖瘦和视觉重心是一套字
/// （`kanpan-badge-colors-match-the-skin` 说的「不能各画各的」）：
///
/// - **画线**：一支斜着的钢笔，笔尖挖一道石墨缺口、笔杆勒一圈箍——不是「节点连线」那种图示。
/// - **图表**：一根涨一根跌，圆角实心的身子加探出去的影线。
/// - **自选**：一颗饱满的五角星，五个角都是圆的。
/// - **设置**：八瓣圆齿中间挖一个孔。不用六角螺母：螺母本身就是这一栏里工程味最重的东西。
///
/// 挖缺口走的是 `destinationOut`：缺口要露出**身下那块材料**（卡片的釉面或者选中胶囊的
/// 主色玻璃），填一块固定的底色在两种背景上都会错一个色。
private struct TabGlyph: View {
  var tab: Tab
  var theme: PanelTheme
  var on: Bool

  /// 记号的框。所有坐标都按 28 排，改形状只要照着这个框改数。
  private static let box: Double = 28

  /// 记号本身的颜色。选中是强调色；没选中是 `ink3`，再由整组统一压淡——四格并排时
  /// 要能看清，但不能和亮着的那格抢。
  ///
  /// 淡是**压在整组上**而不是压在颜色上：星是「填充 + 同色圆角描边」叠出来的，
  /// 颜色本身带了透明度的话，两层交叠的那一圈会比中间深，星就凭空多出一道黑边。
  private var ink: Color { on ? theme.amber : theme.ink3 }

  var body: some View {
    Group {
      switch tab {
      case .draw: pen
      case .chart: candles
      case .favorites: star
      case .settings: rosette
      }
    }
    .frame(width: TabBar.glyph, height: TabBar.glyph)
    // 先合成再压淡。不合成的话 `opacity` 会逐层往下压，星那圈「填充 + 同色描边」
    // 交叠的地方就会比中间深一档，凭空多出一道黑边。
    .compositingGroup()
    .opacity(on ? 1 : (theme.dark ? 0.85 : 0.72))
  }

  /// 画线：一支斜 45° 的钢笔。笔杆是圆角的身子，笔尖是个三角，尖上挖出石墨那一小块，
  /// 笔杆中间勒一道箍——两处缺口让它一眼是「笔」而不是一根圆头棍子。
  private var pen: some View {
    ZStack {
      shape([.rect(x: 9.5, y: 4.0, w: 9.0, h: 12.0, r: 3.0)]).fill(ink)
      shape([.path("M9.5 15.6h9L14 24.2z")]).fill(ink)
      shape([.path("M12.05 20.5h3.9L14 24.2z")]).fill(.black).blendMode(.destinationOut)
      shape([.rect(x: 9.5, y: 10.6, w: 9.0, h: 1.9, r: 0)]).fill(.black).blendMode(.destinationOut)
    }
    .compositingGroup()
    // 斜 45° 摆之后，笔在框里的对角跨度会比正着放短一截；放大一档，它并排时才和
    // 星、齿轮一样重，不会看着小一号。
    .scaleEffect(1.12)
    .rotationEffect(.degrees(45))
  }

  /// 图表：一根涨、一根跌。
  ///
  /// 只有选中时才上真的涨跌色——卡片上同时亮着两支高饱和的红绿，会把另外三格压没了。
  /// 没选中时和别的记号同一个灰，整条栏才是一套字。
  private var candles: some View {
    let up = on ? theme.up : ink
    let down = on ? theme.down : ink
    return ZStack {
      shape([.rect(x: 4.2, y: 8, w: 8, h: 12.6, r: 2)]).fill(up)
      shape([.path("M8.2 4.6v3.4M8.2 20.6v2.8")]).stroke(up, style: stroke)
      shape([.rect(x: 15.8, y: 5.4, w: 8, h: 9.8, r: 2)]).fill(down)
      shape([.path("M19.8 3v2.4M19.8 15.2v5.2")]).stroke(down, style: stroke)
    }
  }

  /// 自选：一颗实心五角星。描边和填充同色、`lineJoin` 走圆角——等于把十个尖都磨圆，
  /// 比自己去算圆角路径省事，形也更饱满。
  private var star: some View {
    let d: [IconItem] = [.path(
      "M14 5.2L16.59 10.64L22.56 11.42L18.19 15.56L19.29 21.48L14 18.6L8.71 21.48L9.81 15.56L5.44 11.42L11.41 10.64Z")]
    return shape(d)
      .fill(ink)
      .overlay(shape(d).stroke(ink, style: StrokeStyle(lineWidth: 2.5, lineJoin: .round)))
  }

  /// 设置：八瓣圆齿，中间挖一个孔。
  ///
  /// 八个小圆压在一个大圆上，`fill` 的 nonzero 会把它们并成一个轮廓；中间那个孔用
  /// `destinationOut` 挖穿，好让身下的釉面透出来。齿是圆的，所以它是「齿轮的形」
  /// 而不是一枚机械零件——这一栏里不需要第二件工程制品。
  private var rosette: some View {
    var lobes: [IconItem] = [.circle(x: 14, y: 14, r: 6.4)]
    for k in 0..<8 {
      let t = Double(k) * .pi / 4
      lobes.append(.circle(x: 14 + 6.5 * cos(t), y: 14 + 6.5 * sin(t), r: 2.5))
    }
    return ZStack {
      shape(lobes).fill(ink)
      shape([.circle(x: 14, y: 14, r: 3.05)]).fill(.black).blendMode(.destinationOut)
    }
    .compositingGroup()
  }

  private var stroke: StrokeStyle { StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round) }
  private func shape(_ items: [IconItem]) -> IconShape { IconShape(box: Self.box, items: items) }
}

/// 一句话提示（原型 `.toast`）。
///
/// 没有「撤销」时 1.6 秒自己消失；带「撤销」时停 5 秒——按钮得给人反应过来的时间，
/// 1.6 秒够不上「看清楚 + 决定 + 抬手点」。停多久由外面的 `say(_:undo:)` 定，
/// 这儿只管画。
///
/// 全屏同一时刻只有这一层：新的一句直接顶掉旧的，不叠不排队。
struct Toast: View {
  var theme: PanelTheme
  var text: String
  /// 右边那颗按钮上的字。绝大多数带动作的提示都是「撤销」，所以它是默认值；
  /// 「已记下 · 查看」那种「去看看刚才那条」也走同一条通道（§2F2），
  /// 免得为一颗按钮再养一套 toast。
  var actionTitle = "撤销"
  /// 右边那颗按钮。nil 就是一条普通提示，不画按钮。
  var undo: (() -> Void)?

  var body: some View {
    HStack(spacing: 10) {
      Text(text)
      if let undo {
        // 中间点一个间隔点，别让文案和按钮糊成一句话。
        Text("·").foregroundStyle(theme.ink3)
        Button(actionTitle, action: undo)
          .buttonStyle(.plain)
          .foregroundStyle(theme.amber)
          .accessibilityIdentifier(actionTitle == "撤销" ? "toast.undo" : "toast.action")
      }
    }
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
