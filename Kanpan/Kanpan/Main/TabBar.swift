import SwiftUI
import UIKit
import KanpanCore

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
/// 1. **底栏根本没有底。** 这一条前后错了三回，一次比一次淡，但错的是同一件事——总想给底栏
///    配一块「自己的」材料：先是左右内缩、带发丝边和投影的悬浮卡片，然后是沉到 `raised2`
///    的渐变带，最后是平铺的 `theme.app`。第三版看着已经和页面同色了，用户还是说
///    「我觉得白色不太好，应该和整体风格融合太突兀了」「其它地方全是融合的」。
///    原因是**页面的底本来就不是一个色**：自选页身下是 `AuroraBackdrop`——底色加几团漂移的光，
///    再往下压一道越走越浓的 wash，最后铺一层颗粒。底栏在那道 wash 最浓的地方盖一块
///    「和 `app` 同色」的平面，等于把整页最有味道的一段裁掉换成一块白板，拼缝就在那儿。
///    所以现在底栏一个 `background` 都不画：它由 `safeAreaInset(edge: .bottom)` 挂在页面上，
///    页面自己的材料（光斑、wash、颗粒）原样从它身后穿过去，一直流到 home 条
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

  /// 记号的边长。18 → 20 → 32 → 36 → 26。往大里推那几档是为了治「太素」，可推到 36 之后
  /// 整条栏在屏幕上占了 112 点（78 的身子 + 34 的 home 条），用户看真机的话是
  /// 「而且显得占比那么大」「不仅浪费空间，而且下面会显得空很多」。
  ///
  /// 治「素」的不是尺寸，是材料：现在选中那格自己是一枚釉面方块（`selectedTile`），
  /// 分量由那块釉承担，记号本身就可以收回到 26——比当初被判「有点小」的 20 仍大出四分之一，
  /// 而整条栏落到 50，和系统标签栏的 49 基本齐平。
  static let glyph: Double = 26
  /// 选中那枚釉面方块的边长。26 / 40 = 0.65，和 `CoinBadge` 里记号占徽章的 0.62 是同一档，
  /// 所以底栏这枚和自选页上每一行的品种徽章看着是同一种东西。
  private static let tile: CGFloat = 40
  /// 一格的宽。方块两边各留 6，指头点得着，四格之间又不会挤。
  private static let cellW: CGFloat = 52

  /// 亮着的是哪一格。
  private var active: Tab { drawing ? .draw : current }

  var body: some View {
    HStack(spacing: 0) {
      ForEach(Tab.allCases, id: \.self) { tab in
        item(tab).accessibilityIdentifier("bottom.\(tab.rawValue)")
      }
    }
    // 上下这两道留白原来各是 10，那是给「悬浮卡片」留的外边距。卡片没了之后它们只是在
    // 把栏撑高；底下这一道尤其多余——`safeAreaInset` 已经把栏摆在 home 条正上方了。
    // 底下不留空：`safeAreaInset` 已经把栏摆在 home 条正上方，再垫一道就是把整排记号
    // 往屏幕中间顶。用户要的是「往下移一点」——所以留白全给上面那一侧。
    .padding(.top, 8)
    .padding(.bottom, 0)
    .background { glowBed }
    .animation(.spring(response: 0.34, dampingFraction: 0.82), value: active)
  }

  /// 一格。只有记号，没有字——无障碍那一份由 `accessibilityLabel` 顶上。
  private func item(_ tab: Tab) -> some View {
    let on = tab == active
    return Button { onPick(tab) } label: {
      ZStack {
        if on { selectedTile } else { restingTile }
        TabGlyph(tab: tab, theme: theme, on: on)
      }
      .frame(width: Self.cellW, height: Self.tile)
      .padding(.vertical, 5)
      .frame(maxWidth: .infinity)
      .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
    .accessibilityLabel(tab.title)
    .accessibilityAddTraits(on ? [.isSelected] : [])
  }

  /// 底栏那一段的「灯座」：一团从屏幕下沿往上化开的强调色光，穿过 home 条一直铺满整条栏。
  ///
  /// 这一团是**设计元素**，不是底色——它没有边、没有轮廓，最浓的地方在屏幕最下沿，往上
  /// 五十来点就化干净了，所以它不会在页面上切出任何一条线。有了它，底栏那一段不再是
  /// 「页面结束之后空出来的一条」：页面的极光往下走的时候被这团光接住，收在屏幕底边上。
  ///
  /// 用户的话是「极致利用下方的空间，不能显得太空，搞点设计视觉元素，让这块不那么突兀」
  /// 「下面会显得空很多」。答案不是把栏做高，是让那一段有东西可看。
  private var glowBed: some View {
    // `endRadius` 必须正好等于这块底的高（含 home 条那一截），光才会在栏顶那一行化到全透明。
    // 写死一个大半径的话，渐变会在框的上沿被切断，那条切口就是一道横着的硬边——第一版
    // 190 的时候真机上看得清清楚楚。高度随机型变，所以得现场量。
    GeometryReader { geo in
      RadialGradient(colors: [theme.amber.opacity(theme.dark ? 0.20 : 0.13), .clear],
                     center: .bottom, startRadius: 0, endRadius: geo.size.height)
        // 横着拉宽：正圆的话光会在左右两格之外就断掉，只托住中间两格。
        .scaleEffect(x: 2.4, y: 1, anchor: .bottom)
    }
    .ignoresSafeArea(edges: .bottom)
    .allowsHitTesting(false)
  }

  /// 没选中那三格身下的座。极淡的一层同色釉——淡到单看几乎看不见，但四格并排时
  /// 它们是同一种东西的四个位置，而不是「一枚徽章加三个飘着的灰记号」。
  private var restingTile: some View {
    RoundedRectangle(cornerRadius: Self.tile * 0.31, style: .continuous)
      .fill(theme.amber.opacity(theme.dark ? 0.10 : 0.06))
      .frame(width: Self.tile, height: Self.tile)
  }

  /// 选中那格：一枚釉面方块，和自选页上每一行的品种徽章、「加密 / 美股」那颗药丸
  /// 是同一种材料——`accentLift → accent` 的斜向渐变，圆角 0.31，身下拖一点同色的影。
  ///
  /// 这儿原来是一片 22% 的强调色玻璃胶囊。它「不难看」，但它不是这个 app 的东西：整页的
  /// 视觉语言是**釉面 + 渐变 + 白记号**（品种徽章、分类药丸、勾选圆点全是这一套），底栏却
  /// 是「浅色底上一个灰记号」，于是那一栏读起来像别的 app 贴过来的。用户的话是
  /// 「针对这块重点设计」「不能因为底栏破坏 ui 的完整性，不然显得格格不入」。
  /// 换成同一枚釉之后，底栏那一格和列表里的徽章是一家人，整屏才是一套东西。
  ///
  /// 影子沿用 `CoinBadge` 的分寸：淡、贴着，只是让这枚方块离纸面一点点，不是让它飞起来。
  private var selectedTile: some View {
    RoundedRectangle(cornerRadius: Self.tile * 0.31, style: .continuous)
      .fill(LinearGradient(colors: [Self.lift(theme.seed.accent, 0.42), theme.amber],
                           startPoint: .topLeading, endPoint: .bottomTrailing))
      .frame(width: Self.tile, height: Self.tile)
      .shadow(color: theme.amber.opacity(theme.dark ? 0.34 : 0.26),
              radius: Self.tile * 0.2, x: 0, y: Self.tile * 0.11)
      .background {
        // 方块身下再化开一团同色的光，铺得比方块宽得多。自选页的底本来就是几团漂移的
        // 极光（`AuroraBackdrop`），这一团等于底栏自己长出来的第四团——有了它，底栏那一段
        // 不再是「页面结束之后空出来的一条」，而是极光收在这儿（「下面会显得空很多」）。
        // 框必须是正方形、且边长正好是 `endRadius` 的两倍：框比直径矮的话，那团光会在
        // 上下沿被切平，凭空多出两条横边——正是这一栏一直在犯的「拼缝」。
        RadialGradient(colors: [theme.amber.opacity(theme.dark ? 0.26 : 0.16), .clear],
                       center: .center, startRadius: 0, endRadius: Self.tile * 1.5)
          .frame(width: Self.tile * 3, height: Self.tile * 3)
          .allowsHitTesting(false)
      }
      .matchedGeometryEffect(id: "pill", in: pill)
  }

  /// 往亮里提一档：色相不动，饱和收一点、明度往上走。和自选页 `LiuliSkin.lift` 同一支算法——
  /// 那支是 `private` 的，跨文件借不到，所以这儿照抄一份；两处必须给出同一枚釉，
  /// 不然底栏这一枚和列表里的徽章会差半档色。
  private static func lift(_ hex: Hex, _ amount: Double) -> Color {
    let rgba = hex.rgba
    var h: CGFloat = 0, sat: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
    UIColor(red: rgba.r, green: rgba.g, blue: rgba.b, alpha: 1)
      .getHue(&h, saturation: &sat, brightness: &b, alpha: &a)
    return Color(hue: Double(h), saturation: Double(sat) * (1 - amount * 0.6),
                 brightness: Double(b) + (1 - Double(b)) * amount)
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

  /// 记号本身的颜色。选中的那格站在釉面方块上，所以它是**白的**——和品种徽章里的记号、
  /// 分类药丸上的字一样，白记号压在渐变釉上是这个 app 通用的那一套。没选中是 `ink3`，
  /// 再由整组统一压淡：四格并排时要能看清，但不能和亮着的那格抢。
  ///
  /// 淡是**压在整组上**而不是压在颜色上：星是「填充 + 同色圆角描边」叠出来的，
  /// 颜色本身带了透明度的话，两层交叠的那一圈会比中间深，星就凭空多出一道黑边。
  private var ink: Color { on ? .white : theme.ink3 }

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
  /// 两根都用 `ink`，不上真的涨跌色：选中时它站在渐变釉上，红绿压在强调色上互相打架；
  /// 没选中时两支高饱和的红绿又会把另外三格压没了。整条栏是一套字，颜色的事交给身下那枚釉。
  private var candles: some View {
    let up = ink
    let down = ink
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
