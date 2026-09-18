import SwiftUI
import UIKit
import KanpanCore

/// 底栏那五格。
///
/// 2026-09-18 它从「几个入口按钮」改成了常驻标签栏。用户的话是「大部分 app 把常用的
/// 大分页都固定在底部，比如 tv 和推特都是，底部是固定的，切换页面下面还是那样」——
/// 以前「自选」是全屏 cover、「设置」是半屏 sheet、「复盘」是另一层 cover，一层盖一层，
/// 人不知道自己在第几层，只能一路退回去。现在每一格各是一张整页，底栏永远在，
/// 换页就是换一格。
///
/// 顺序是用户定死的：**画线 · 图表 · 自选 · 板块分类 · 设置**。他的话是「本来行情 app
/// 这个就很重要」——画线值一格；「复盘放到图表里」，所以复盘不在底栏上（它挪到了行情页
/// 顶栏那颗带角标的按钮），「指标」也不在（并进了「图表设置」）。
///
/// 「板块分类」是第四格，2026-09-18 晚随板块气泡页一起落地。它只有这一格——加密和美股
/// 是那一页顶上的硬切换，**不会**再为美股开第六格。
enum Tab: String, CaseIterable, Sendable {
  case draw, chart, favorites, sectors, settings

  var title: String {
    switch self {
    case .draw: "画线"
    case .chart: "图表"
    case .favorites: "自选"
    case .sectors: "板块分类"
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

/// 常驻标签栏：五格等宽，谁亮着谁是当前页。
///
/// 2026-09-18 白天这一版的底子是「釉面卡片」：选中那格坐在一枚 40 的釉面方块上，记号是白的，
/// 没选中的三格身下垫一层极淡的同色釉、记号是灰的。那一版解决的是「底栏不能说自己的视觉语言」，
/// 但它把**颜色**全收进了那一枚方块里——四个记号本身仍旧是一个灰、一个白。
///
/// 晚上用户在板块气泡原型上看到另一种画法，说「我觉得这个好看啊比之前的精致一些」
/// 「颜色搭配也很好看」。那一版的做法正好反过来：
///
/// 1. **一格底座都不画。** 选中的方块、没选中的淡釉全部去掉，底栏只剩四个记号浮在页面的材料上。
///    这不是退回「底栏没设计」——`kanpan-bottom-bar-has-no-surface-of-its-own` 说的是底栏不许有
///    自己的**底**，釉面方块只是当时用来把颜色带进来的载体。颜色现在长在记号上，方块就没有存在的
///    理由了，去掉之后那一段更轻、更透，页面的极光一路淌到 home 条。
/// 2. **记号自己是釉的。** 每个记号都由皮肤的两支颜色填出来——主色（青苔的墨绿 / 陶土的赤陶）配
///    暖金，斜向渐变，浅的一头在左上。和品种徽章、分类药丸是同一支渐变、同一个方向，
///    只是从方块挪到了记号本身（`kanpan-badge-colors-match-the-skin`）。
/// 3. **选中就是「亮着」。** 没选中的整组压到 52%，选中那格是满的。不换颜色、不加底、不加圈——
///    四个记号是同一套材料的四个位置，亮着的那个自己跳出来。
///
/// 2026-09-18 晚板块气泡页定稿，用户的话是「这版可以，直接做，我喜欢这个设计，
/// **底栏也照着改即可**」。所以这一版把五个记号逐个对齐了定稿原型：记号的框从 28 收到 24
/// （原型 SVG 的 viewBox），蜡烛补回影线、齿轮换成六齿加挖空的环、画线换成折线只留一颗金点，
/// 并补上第四格「板块分类」那四颗气泡。三支釉的口径原型里就是照着这个文件写的，没有出入。
///
/// 交互一点没动：顺序、`isRestingPlace` 和 `bottom.*` 标识都照旧，只是多了一格。
struct TabBar: View {
  var theme: PanelTheme
  /// 停在哪一页。`draw` 不会是它——见 `Tab.isRestingPlace`。
  var current: Tab
  /// 正在画线。这时候亮的是最左边那格，而不是身下那张行情页。
  var drawing: Bool
  var onPick: (Tab) -> Void

  /// 记号的边长。18 → 20 → 32 → 36 → 26 → 27。往 36 推那几档是为了治「太素」，可推上去之后
  /// 整条栏在屏幕上占了 112 点，用户看真机的话是「而且显得占比那么大」「不仅浪费空间，
  /// 而且下面会显得空很多」。治「素」的从来不是尺寸是材料：记号自己上了釉之后，27 就够。
  static let glyph: Double = 27
  /// 一格的点区。记号 27 坐在 40 的方框中间，四边各留出指头点得着的余量——
  /// 方框本身不画任何东西了，它只是热区。
  private static let cellH: CGFloat = 40
  /// 一格的宽。
  private static let cellW: CGFloat = 52

  /// 亮着的是哪一格。
  private var active: Tab { drawing ? .draw : current }

  var body: some View {
    HStack(spacing: 0) {
      ForEach(Tab.allCases, id: \.self) { tab in
        item(tab).accessibilityIdentifier("bottom.\(tab.rawValue)")
      }
    }
    // 留白全给上面那一侧：`safeAreaInset` 已经把栏摆在 home 条正上方了，底下再垫一道
    // 就是把整排记号往屏幕中间顶。用户要的是「往下移一点」。
    .padding(.top, 8)
    .padding(.bottom, 0)
    .background { glowBed }
    .animation(.spring(response: 0.34, dampingFraction: 0.82), value: active)
  }

  /// 一格。只有记号，没有字，也没有底——无障碍那一份由 `accessibilityLabel` 顶上。
  private func item(_ tab: Tab) -> some View {
    let on = tab == active
    return Button { onPick(tab) } label: {
      TabGlyph(tab: tab, theme: theme, on: on)
        .frame(width: Self.cellW, height: Self.cellH)
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

  /// 往亮里提一档：色相不动，饱和收一点、明度往上走。和自选页 `LiuliSkin.lift` 同一支算法——
  /// 那支是 `private` 的，跨文件借不到，所以这儿照抄一份；两处必须给出同一枚釉，
  /// 不然底栏这一枚和列表里的徽章会差半档色。
  fileprivate static func lift(_ hex: Hex, _ amount: Double) -> Color {
    let rgba = hex.rgba
    var h: CGFloat = 0, sat: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
    UIColor(red: rgba.r, green: rgba.g, blue: rgba.b, alpha: 1)
      .getHue(&h, saturation: &sat, brightness: &b, alpha: &a)
    return Color(hue: Double(h), saturation: Double(sat) * (1 - amount * 0.6),
                 brightness: Double(b) + (1 - Double(b)) * amount)
  }
}

/// 底栏那五个记号。
///
/// **它们是实心的，不是线框。** 2026-09-18 之前这几个是单色细描边的示意图——两点连一线的
/// 「画线」、方框加引线的「蜡烛」、六角螺母的「设置」。用户连否两版：「太工程太后台风」
/// 「一点都不精致好看唯美」。线框加细描边在这个项目里就是后台管理系统的味道，描边再粗、
/// 记号再大也救不回来（`kanpan-icons-are-not-wireframes`）。
///
/// **它们也是有颜色的。** 白天那一版把记号画成一个白、几个灰，颜色全交给身下那枚釉面方块；
/// 晚上用户在板块气泡原型上挑中了反过来的画法——方块没有了，颜色长在记号上。每个记号用皮肤的
/// 两支颜色填：**主色**（`theme.amber`，青苔的墨绿 / 陶土的赤陶）和**暖金**（`seed.amber`，
/// 图上那支暖色）。同一条栏上五个记号分三支釉，深浅冷暖各就各位，这就是用户说的
/// 「颜色搭配也很好看」：
///
/// - **画线**：一道两折的折线，尾端按一颗金色的锚点。画在图上的线就是这个样子，
///   比钢笔更直说它是干什么的。
/// - **图表**：三根圆角蜡烛，外侧两根主色、中间一根金的；外侧两根各带一截圆头影线。
///   影线是这枚记号唯一的细部，收在 2.8 宽的圆角柱里，不会退回线框那一路。
/// - **自选**：一颗圆角饱满的五角星，整颗是金的。一栏里只有它是纯暖色，所以一眼找得到。
/// - **板块分类**：四颗大小不一的气泡，两颗主色、一颗金、一颗浅主色。这正是板块页上那幅画面
///   ——大小说幅度、位置说强弱——缩到一枚记号里，所以它不用画任何别的东西就已经说清楚了。
/// - **设置**：六枚圆头的齿从身子上鼓出来，中间挖一个孔。孔走 `destinationOut`，露出来的是
///   **身下那块材料**（页面的极光），填一块固定的底色会在深浅两套皮肤上各错一个色。
private struct TabGlyph: View {
  var tab: Tab
  var theme: PanelTheme
  var on: Bool

  /// 记号的框。所有坐标都按 24 排——这是定稿原型那几枚 SVG 的 viewBox，
  /// 「照着改」就得连坐标系一起照着，不然每一枚都要换算一遍、迟早对不齐。
  private static let box: Double = 24

  var body: some View {
    Group {
      switch tab {
      case .draw: trendline
      case .chart: candles
      case .favorites: star
      case .sectors: bubbles
      case .settings: gear
      }
    }
    .frame(width: TabBar.glyph, height: TabBar.glyph)
    // 先合成再压淡：不合成的话 `opacity` 会逐层往下压，两片叠在一起的地方会比别处深一档。
    .compositingGroup()
    // 选中就是「亮着」，没选中整组压到 52%。不换颜色也不加底——记号是同一套材料的几个位置，
    // 亮着的那个自己跳出来。
    .opacity(on ? 1 : 0.52)
    // 一层贴着的软影，让记号离页面的材料一点点。原型是 `drop-shadow(0 2px 5px #0000001f)`。
    .shadow(color: .black.opacity(theme.dark ? 0.26 : 0.12), radius: 2.5, y: 1)
  }

  // MARK: 三支釉

  /// 釉·主色：浅一档的主色 → 主色。和品种徽章、分类药丸同一支渐变、同一个方向
  /// （浅的一头在左上），只是从方块挪到了记号上。原型里这支叫 `gA`。
  private var accentGlaze: LinearGradient { glaze(TabBar.lift(theme.seed.accent, 0.42), theme.amber) }
  /// 釉·浅主色：比上面那支再提亮半档。原型里这支叫 `gL`，只用在板块记号那颗最小的气泡上——
  /// 它紧挨着一颗主色的大球，同色贴在一起会糊成一块。
  private var accentLightGlaze: LinearGradient {
    glaze(TabBar.lift(theme.seed.accent, 0.52), TabBar.lift(theme.seed.accent, 0.16))
  }
  /// 釉·暖金：浅一档的金 → 金。金是 `seed.amber`——画在图上那支暖色，
  /// 不是界面强调色（那支在这儿叫 `theme.amber`，见 `PaletteSeed`）。原型里这支叫 `gG`。
  private var goldGlaze: LinearGradient {
    glaze(TabBar.lift(theme.seed.amber, 0.34), Color(hex: theme.seed.amber))
  }

  private func glaze(_ top: Color, _ bottom: Color) -> LinearGradient {
    LinearGradient(colors: [top, bottom], startPoint: .topLeading, endPoint: UnitPoint(x: 0.35, y: 1))
  }

  // MARK: 五个形

  /// 画线：一道两折的折线，尾端按一颗金色的锚点。
  ///
  /// 之前那版是一道平滑的曲线加两头两颗点。定稿原型收成了折线加一颗点——曲线在 27 点上
  /// 读起来像一道随手划的弧，折线才是「在图上连出来的一条趋势」；两颗点也多了，
  /// 一栏之内的暖色有星和这一颗就够，再多就散了。
  private var trendline: some View {
    ZStack {
      shape([.path("M3.4 17.6 8.5 12.1l3.4 3 6.4-8.2")])
        .stroke(accentGlaze, style: StrokeStyle(lineWidth: 2.6, lineCap: .round, lineJoin: .round))
      shape([.circle(x: 19.1, y: 5.9, r: 2.5)]).fill(goldGlaze)
    }
  }

  /// 图表：三根圆角蜡烛，外侧两根主色、中间一根金的，外侧两根各带一截影线。
  ///
  /// 影线一度被整个砍掉（一像素的细线缩到 27 之后既看不清又把记号拉回线框那一路），
  /// 定稿原型把它加回来了，但换了个写法：影线不是线，是一根 2.8 宽的圆角柱，
  /// 从柱身顶上探出来一截。这样它在 27 点上仍然是个「实心的东西」，不是一根发丝。
  private var candles: some View {
    ZStack {
      shape([.rect(x: 3.7, y: 8.6, w: 2.8, h: 4.6, r: 1.4),
             .rect(x: 3, y: 12.4, w: 4.2, h: 8.4, r: 2.1)]).fill(accentGlaze)
      shape([.rect(x: 9.9, y: 6.2, w: 4.2, h: 14.6, r: 2.1)]).fill(goldGlaze)
      shape([.rect(x: 17.5, y: 6.4, w: 2.8, h: 4.4, r: 1.4),
             .rect(x: 16.8, y: 10.2, w: 4.2, h: 10.6, r: 2.1)]).fill(accentGlaze)
    }
  }

  /// 自选：一颗五角星，十个角全是圆的（路径自己带圆角，不再靠同色描边去磨）。整颗是金的。
  private var star: some View {
    shape([.path(
      "M12 3.3c.42 0 .8.24 1 .62l2.14 4.26 4.78.69c.93.13 1.3 1.28.62 1.93l-3.45 3.28"
      + ".81 4.67c.16.93-.82 1.64-1.66 1.2L12 17.76l-4.24 2.19c-.84.44-1.82-.27-1.66-1.2"
      + "l.81-4.67-3.45-3.28c-.68-.65-.31-1.8.62-1.93l4.78-.69L11 3.92c.2-.38.58-.62 1-.62z")])
      .fill(goldGlaze)
  }

  /// 板块分类：四颗大小不一的气泡。
  ///
  /// 这一格的记号不用另想——板块页上那幅画面本身就是几十颗大小不一的球，大小说幅度、
  /// 位置说强弱。把它缩到 24 的框里就剩四颗：左上一颗主色的大球、右上一颗金的小球、
  /// 右下一颗主色的中球、左下一颗浅主色的小球。四颗错开摆，留白也是构图的一部分，
  /// 所以不要把它们排齐。
  private var bubbles: some View {
    ZStack {
      shape([.circle(x: 8.1, y: 8.6, r: 5), .circle(x: 15.7, y: 16.4, r: 4.4)]).fill(accentGlaze)
      shape([.circle(x: 17.4, y: 6.6, r: 2.9)]).fill(goldGlaze)
      shape([.circle(x: 6.1, y: 18, r: 2.5)]).fill(accentLightGlaze)
    }
  }

  /// 设置：六枚圆头的齿从身子上鼓出来，中间挖一个孔。
  ///
  /// 六枚齿是同一根圆角柱绕着 (12, 12) 转六次——`box` 是 24、框是正方形，所以
  /// `rotationEffect` 的默认锚点正好落在 (12, 12) 上，不用自己算变换。
  /// 孔走 `destinationOut`：底栏不许有自己的底，页面的材料要从这个孔里透上来。
  private var gear: some View {
    ZStack {
      ForEach(0..<6, id: \.self) { i in
        shape([.rect(x: 10.5, y: 1.3, w: 3, h: 5.2, r: 1.5)])
          .fill(accentGlaze)
          .rotationEffect(.degrees(Double(i) * 60))
      }
      shape([.circle(x: 12, y: 12, r: 7.4)]).fill(accentGlaze)
      shape([.circle(x: 12, y: 12, r: 3.1)]).fill(.black).blendMode(.destinationOut)
    }
    .compositingGroup()
  }

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
