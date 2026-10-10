import SwiftUI
import UIKit
import KanpanCore
import ReviewUI

/// 底栏那四格。
///
/// 2026-09-18 它从「几个入口按钮」改成了常驻标签栏。用户的话是「大部分 app 把常用的
/// 大分页都固定在底部，比如 tv 和推特都是，底部是固定的，切换页面下面还是那样」——
/// 以前「自选」是全屏 cover、「设置」是半屏 sheet、「复盘」是另一层 cover，一层盖一层，
/// 人不知道自己在第几层，只能一路退回去。现在每一格各是一张整页，底栏永远在，
/// 换页就是换一格。
///
/// 2026-09-27 用户定的四格：**图表 · 自选 · 板块分类 · 我的**（方案
/// `docs/方案-我的-自动复盘-周期分组指标-2026-09-27.md` §1.1，用户：「我的确实是对的，
/// 画线你的建议也是对的」）。原来五格里最左的「画线」不是一张页、只是一个动作（把眼前这张图
/// 横过来画），占一整格却从来不能「停」在那儿；它挪到了行情页周期条行尾，2026-09-28 行尾收回
/// 三件时又和指标并列归进「分析」这个大类（分析面板第一节，`indicator.draw`）。于是 `Tab.draw` 和那个只为它存在的
/// `isRestingPlace` 一起删掉——四格现在每一格都是能停下来的家。
///
/// 最右那格从「设置」换成「我的」：账号、复盘本、全部预警、朋友与收件箱、交易所账户、设置
/// 六块收在一页上（`MePage`）。顶栏那颗复盘按钮撤了，复盘还欠着答案的条数改挂在「我的」
/// 记号右上角（`ReviewCountBadge`）。
///
/// 2026-10-10 定的四格：**首页 · 图表 · 自选 · 我的**。最左加「首页」（异动 · 涨跌 · 持仓 · 板块，
/// PROJECT.md §79），冷启动默认落在它上面；原来的「板块分类」一格并进首页成了第四段（那一页原样搬过去，
/// 删格之前的最后一个提交打了 tag `before-merge-sectors-tab-2026-10-10`）。
enum Tab: String, CaseIterable, Sendable {
  case home, chart, favorites, me

  var title: String {
    switch self {
    case .home: HighlightTerm.home.text
    case .chart: "图表"
    case .favorites: "自选"
    case .me: "我的"
    }
  }
}

/// 常驻标签栏：四格等宽，谁亮着谁是当前页。
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
/// 2026-09-27 收成四格（见 `Tab`）：记号尺寸、釉、明暗、没有自己的底全都不动，
/// 「画线」那格连同它的置灰逻辑搬去了周期条，「设置」的齿轮换成「我的」那枚人形。
struct TabBar: View {
  var theme: PanelTheme
  /// 停在哪一页。
  var current: Tab
  /// 复盘本：「我的」记号右上角那颗待判定角标数的就是它（2026-09-27 从顶栏复盘按钮挪过来）。
  /// 传整只 feature 而不是算好的数，理由同 `ReviewCountBadge`。
  var review: ReviewFeature? = nil
  /// 身后那道「透明 → 页面底色」渐变的终点色：每页传**自己的**底色令牌（自选是 `AuroraBackdrop`
  /// 的底、板块是 `SectorSkin.ground`、我的是 `app`）。自选 / 板块 / 我的三页 2026-10-08 起
  /// 铺的都是同一层琉璃底，所以只要传了（非 nil），这里一律收在 `LiuliMaterial.ground` 上，
  /// 宿主传来的具体颜色只当「要不要铺」的开关——免得某页底换了材质、宿主那份令牌没跟上。nil 就不铺——行情页的图不在栏身后滚，
  /// 那道渐变上沿会压淡 K 线图下沿的时间轴。
  var fade: Color? = nil
  var onPick: (Tab) -> Void

  /// 渐变多高：从栏的下沿（home 条上沿）往上 96pt，比栏自己（58）高出 38pt。
  static let fadeHeight: CGFloat = 96
  /// 挂在这条栏上的滚动页，内容底部要多让出的一截：滚到最底时最后一行完整地停在渐变上沿以上，
  /// 记号周围没有文字。滚到中间时记号下面那一行被渐变压淡，不是硬切（2026-09-28）。
  static let fadeClearance: CGFloat = 50

  /// 记号的边长。18 → 20 → 32 → 36 → 26 → 27。往 36 推那几档是为了治「太素」，可推上去之后
  /// 整条栏在屏幕上占了 112 点，用户看真机的话是「而且显得占比那么大」「不仅浪费空间，
  /// 而且下面会显得空很多」。治「素」的从来不是尺寸是材料：记号自己上了釉之后，27 就够。
  static let glyph: Double = 27
  /// 一格的点区。记号 27 坐在 40 的方框中间，四边各留出指头点得着的余量——
  /// 方框本身不画任何东西了，它只是热区。
  private static let cellH: CGFloat = 40
  /// 一格的宽。
  private static let cellW: CGFloat = 52
  /// 栏顶上那道留白（见 `body` 里的注释：留白全给上面那一侧）。
  private static let topPad: CGFloat = 8
  /// 一格上下各垫的那一点。
  private static let cellVPad: CGFloat = 5

  /// 栏自己的高度（不含 home 条那截安全区）：顶上留白 + 一格的点区 + 上下垫。
  /// 浮在栏上方的东西（`ToastStage` 那条提示）按它让位，不再各写一个魔数。
  static let height: CGFloat = topPad + cellH + cellVPad * 2

  /// 亮着的是哪一格。画线进行中也还是「图表」——画线不再占底栏的格子。
  private var active: Tab { current }

  var body: some View {
    HStack(spacing: 0) {
      ForEach(Tab.allCases, id: \.self) { tab in
        item(tab).accessibilityIdentifier("bottom.\(tab.rawValue)")
      }
    }
    // 留白全给上面那一侧：`safeAreaInset` 已经把栏摆在 home 条正上方了，底下再垫一道
    // 就是把整排记号往屏幕中间顶。用户要的是「往下移一点」。
    .padding(.top, Self.topPad)
    .padding(.bottom, 0)
    .background { glowBed }
    // 渐变垫在灯座下面：先把滚进栏身后的那一截内容压回页面底色，灯座再浮在上面。
    .background(alignment: .bottom) { if fade != nil { fadeBed(LiuliMaterial(theme).ground) } }
    .animation(.spring(response: 0.34, dampingFraction: 0.82), value: active)
  }

  /// 一格。只有记号，没有字，也没有底——无障碍那一份由 `accessibilityLabel` 顶上。
  private func item(_ tab: Tab) -> some View {
    let on = tab == active
    return Button { onPick(tab) } label: {
      TabGlyph(tab: tab, theme: theme, on: on)
        // 角标挂在记号外面：记号自己那层 64% 的压暗不该连角标一起压（要一眼看得见）。
        .overlay(alignment: .topTrailing) {
          if tab == .me, let review {
            ReviewCountBadge(review: review, theme: theme).equatable().offset(x: 7, y: -4)
          }
        }
        .frame(width: Self.cellW, height: Self.cellH)
        .padding(.vertical, Self.cellVPad)
        .frame(maxWidth: .infinity)
        .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
    .accessibilityLabel(tab.title)
    .accessibilityAddTraits(on ? [.isSelected] : [])
  }

  /// 栏身后那道渐变（2026-09-28 用户定：底栏保留融合、但内容不再和记号重叠）。
  ///
  /// 栏自己**仍然没有底**（`kanpan-bottom-bar-has-no-surface-of-its-own`）：这一道用的是页面自己的
  /// 底色，从透明化到实色，读起来是「页面的材料在这儿收住了」，不是另起一块底板。
  /// 0% 全透明，45% 处 86%，70% 处到实色，一直铺到屏幕下沿（home 条那一截）。不吃点按。
  private func fadeBed(_ ground: Color) -> some View {
    LinearGradient(stops: [
      .init(color: ground.opacity(0), location: 0),
      .init(color: ground.opacity(0.86), location: 0.45),
      .init(color: ground, location: 0.70),
      .init(color: ground, location: 1),
    ], startPoint: .top, endPoint: .bottom)
    .frame(height: Self.fadeHeight)
    // home 条那一截：同一个底色贴着栏的下沿一直铺到屏幕最下面。
    //
    // 顺序不能反：`ignoresSafeArea` 必须在 `frame` **里面**。以前写成
    // `ground.frame(height: 1).ignoresSafeArea(...)`，安全区放大的是那只 1pt 框外面的
    // 摆放区域，1pt 的框自己不长，只是被居中挪到 home 条半腰——于是 home 条那 34pt
    // 一直是透明的，滚动页的行在记号下面清清楚楚地露出来（2026-10-04 G 线走查：
    // 板块列表、板块下钻页最下面那一行完整地躺在底栏图标下方）。现在 1pt 的框贴着栏的
    // 下沿，里面那块底色忽略安全区、自己往下长满 home 条。
    .background(alignment: .bottom) { ground.ignoresSafeArea(edges: .bottom).frame(height: 1) }
    .allowsHitTesting(false)
    .accessibilityHidden(true)
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

/// 底栏那四个记号（2026-09-27 之前是五个，画线那枚缩小后成了 `IntervalDrawGlyph`，09-28 起挂在分析面板「开始画线」行尾）。
///
/// **它们是实心的，不是线框。** 2026-09-18 之前这几个是单色细描边的示意图——两点连一线的
/// 「画线」、方框加引线的「蜡烛」、六角螺母的「设置」。用户连否两版：「太工程太后台风」
/// 「一点都不精致好看唯美」。线框加细描边在这个项目里就是后台管理系统的味道，描边再粗、
/// 记号再大也救不回来（`kanpan-icons-are-not-wireframes`）。
///
/// **它们也是有颜色的。** 白天那一版把记号画成一个白、几个灰，颜色全交给身下那枚釉面方块；
/// 晚上用户在板块气泡原型上挑中了反过来的画法——方块没有了，颜色长在记号上。每个记号用皮肤的
/// 两支颜色填：**主色**（`theme.amber`，青苔的墨绿 / 陶土的赤陶）和**暖金**（`seed.amber`，
/// 图上那支暖色）。同一条栏上四个记号分三支釉，深浅冷暖各就各位，这就是用户说的
/// 「颜色搭配也很好看」：
///
/// - **图表**：三根圆角蜡烛，外侧两根主色、中间一根金的；外侧两根各带一截圆头影线。
///   影线是这枚记号唯一的细部，收在 2.8 宽的圆角柱里，不会退回线框那一路。
/// - **自选**：一颗圆角饱满的五角星，整颗是金的。一栏里只有它是纯暖色，所以一眼找得到。
/// - **首页**：一面雷达（见 `radar`）。原来那枚「板块分类」四颗气泡 2026-10-10 随那一格一起删了。
/// - **我的**：一个人形——主色的肩身、金色的头，头和肩之间留一道缝。2026-09-27 替下了
///   「设置」那枚齿轮（设置成了「我的」里的一行）。和其余三枚同一种画法：实心、圆润、两支釉，
///   不是线框（`kanpan-icons-are-not-wireframes`）。
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
      case .home: radar
      case .chart: candles
      case .favorites: star
      case .me: person
      }
    }
    .frame(width: TabBar.glyph, height: TabBar.glyph)
    // 先合成再压淡：不合成的话 `opacity` 会逐层往下压，两片叠在一起的地方会比别处深一档。
    .compositingGroup()
    // 选中就是「亮着」，没选中整组压到 64%。不换颜色也不加底——记号是同一套材料的几个位置，
    // 亮着的那个自己跳出来。52% 时未选中记号对页面底只有 2.0–2.9 : 1（UI 审查 2026-09-24 §3.2），
    // 提到 64% 之后「亮 / 不亮」的差少了一截，由选中那颗放大 6% 补回来。
    .opacity(on ? 1 : 0.64)
    .scaleEffect(on ? 1.06 : 1)
    // 一层贴着的软影，让记号离页面的材料一点点。原型是 `drop-shadow(0 2px 5px #0000001f)`。
    .shadow(color: .black.opacity(theme.dark ? 0.26 : 0.12), radius: 2.5, y: 1)
  }

  // MARK: 三支釉

  /// 釉·主色：浅一档的主色 → 主色。和品种徽章、分类药丸同一支渐变、同一个方向
  /// （浅的一头在左上），只是从方块挪到了记号上。原型里这支叫 `gA`。
  private var accentGlaze: LinearGradient { glaze(TabBar.lift(theme.seed.accent, 0.42), theme.amber) }
  /// 釉·浅主色：比上面那支再提亮半档。原型里这支叫 `gL`，原来只用在板块记号那颗最小的气泡上；
  /// 板块格并进首页之后用在首页雷达中间那颗圆盘上——紧挨着主色的外圈，同色贴在一起会糊成一块。
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

  // MARK: 四个形

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

  /// 我的：一个人形。肩身是一块下沿平、上沿圆的主色，头是一颗金色的圆，两块之间留 1.3 的缝，
  /// 缩到 27 点也读得出「头」和「肩」。金只给头：一栏里暖色有星和这一颗就够（和原来折线那颗
  /// 金色锚点同一个分量），整身金会和旁边的星抢。
  private var person: some View {
    ZStack {
      shape([.path("M3.6 19.4c0-4.5 3.8-7.6 8.4-7.6s8.4 3.1 8.4 7.6v.3c0 .9-.7 1.6-1.6 1.6H5.2"
                   + "c-.9 0-1.6-.7-1.6-1.6v-.3z")])
        .fill(accentGlaze)
      shape([.circle(x: 12, y: 6.6, r: 3.9)]).fill(goldGlaze)
    }
  }

  /// 首页：一面雷达——主色的圆盘中间挖一道环缝，金色的扫描扇从圆心扫向右上，盘上一颗浅主色的光点。
  /// 和其余几枚同一种画法：实心、两支釉，环缝是挖穿的（同「记一笔」的字行）。
  private var radar: some View {
    ZStack {
      shape([.circle(x: 12, y: 12.4, r: 9)]).fill(accentGlaze)
      shape([.circle(x: 12, y: 12.4, r: 5.5)]).fill(.black).blendMode(.destinationOut)
      shape([.circle(x: 12, y: 12.4, r: 4)]).fill(accentLightGlaze)
      shape([.path("M12 12.4V3.4a9 9 0 0 1 8.5 6.1z")]).fill(goldGlaze)
      shape([.circle(x: 16.6, y: 16.6, r: 1.7)]).fill(goldGlaze)
    }
    .compositingGroup()
  }

  private func shape(_ items: [IconItem]) -> IconShape { IconShape(box: Self.box, items: items) }
}

/// 「画线」那颗记号：底栏原来那枚折线记号的缩小版（2026-09-27 画线从底栏挪进周期条行尾，
/// 方案 §1.2；09-28 行尾收回三件，它跟着画线进了分析面板第一节那一行的行尾，`IndicatorPage.drawSection`）。
/// 形一个点不改——一道两折的主色折线，尾端一颗金色锚点——只是框从 27 缩到 24。
/// 坐标仍按 24 的框排，和底栏几枚同一个坐标系、同一副釉
/// （`TabBar.lift` 是 fileprivate 的，所以它住在这个文件里）。
///
/// 不压暗、不放大：对比期间那一行置灰时由调用方乘 `ControlMetrics.disabledOpacity`。
struct IntervalDrawGlyph: View {
  var theme: PanelTheme
  var size: Double = 24

  private static let box: Double = 24

  var body: some View {
    ZStack {
      shape([.path("M3.4 17.6 8.5 12.1l3.4 3 6.4-8.2")])
        .stroke(accentGlaze, style: StrokeStyle(lineWidth: 2.6, lineCap: .round, lineJoin: .round))
      shape([.circle(x: 19.1, y: 5.9, r: 2.5)]).fill(goldGlaze)
    }
    .compositingGroup()
    .frame(width: size, height: size)
    .shadow(color: .black.opacity(theme.dark ? 0.26 : 0.12), radius: 1.5, y: 0.8)
  }

  private var accentGlaze: LinearGradient { glaze(TabBar.lift(theme.seed.accent, 0.42), theme.amber) }
  private var goldGlaze: LinearGradient { glaze(TabBar.lift(theme.seed.amber, 0.34), Color(hex: theme.seed.amber)) }
  private func glaze(_ top: Color, _ bottom: Color) -> LinearGradient {
    LinearGradient(colors: [top, bottom], startPoint: .topLeading, endPoint: UnitPoint(x: 0.35, y: 1))
  }
  private func shape(_ items: [IconItem]) -> IconShape { IconShape(box: Self.box, items: items) }
}

/// 「记一笔」那颗记号：一本带书签的复盘本（2026-09-24 审查 U6 为顶栏「复盘」画的专属记号，
/// 09-27 顶栏撤掉复盘时一并删了；09-28 乙方案把它请回顶栏，给右上角那颗「记一笔」用，
/// 形一个点没改，从 `656fe59d^` 原样取回）。
/// 本子是主色，两道字行从本子上挖穿、露出托底，书签是金的。坐标按 24 的框排，
/// 和底栏几枚同一个坐标系、同一副釉（`TabBar.lift` 是 fileprivate 的，所以它住在这个文件里）。
struct ReviewGlyph: View {
  var theme: PanelTheme
  var size: Double = 17

  private static let box: Double = 24

  var body: some View {
    ZStack {
      shape([.rect(x: 4.2, y: 2.6, w: 15.6, h: 18.8, r: 3.4)]).fill(accentGlaze)
      // 两道字行：一长一短，挖穿本身，露出托底。
      shape([.rect(x: 7.6, y: 12.2, w: 8.8, h: 2.3, r: 1.15),
             .rect(x: 7.6, y: 16.1, w: 5.6, h: 2.3, r: 1.15)])
        .fill(.black).blendMode(.destinationOut)
      // 书签：从本子上沿垂下来，尾巴剪一个燕尾口，四个角都是圆的。
      shape([.path("M12.6 1.9h4.2c.5 0 .9.4.9.9v7.5c0 .45-.52.7-.87.42L14.7 9.1l-2.13 1.62"
                   + "c-.35.28-.87.03-.87-.42V2.8c0-.5.4-.9.9-.9z")])
        .fill(goldGlaze)
    }
    .compositingGroup()
    .frame(width: size, height: size)
    .shadow(color: .black.opacity(theme.dark ? 0.26 : 0.12), radius: 1.5, y: 0.8)
  }

  private var accentGlaze: LinearGradient { glaze(TabBar.lift(theme.seed.accent, 0.42), theme.amber) }
  private var goldGlaze: LinearGradient { glaze(TabBar.lift(theme.seed.amber, 0.34), Color(hex: theme.seed.amber)) }
  private func glaze(_ top: Color, _ bottom: Color) -> LinearGradient {
    LinearGradient(colors: [top, bottom], startPoint: .topLeading, endPoint: UnitPoint(x: 0.35, y: 1))
  }
  private func shape(_ items: [IconItem]) -> IconShape { IconShape(box: Self.box, items: items) }
}

/// 复盘还欠着答案的条数：底栏「我的」记号右上角那颗主题色小圆点（2026-09-27 从顶栏复盘按钮上
/// 挪过来，方案 §1.4）。0 就不画。
///
/// 单独成一个视图，是为了让「数欠着几条」这件事只跟着复盘记录走：宿主（底栏、再往上是
/// `MainScreen`）跟着行情一秒重画好几次，只要递下来的 feature 引用没变，SwiftUI 就不重跑
/// 这里的 body；`pendingCount` 本身也已在 feature 里缓存，记录真变了才重数。
///
/// 「引用没变就不重跑」不能交给 SwiftUI 默认的逐字段比对：`PanelTheme` 里的种子和图色带着
/// `[Hex]` 数组，宿主每趟 body 都现做一份主题，数组是新开的堆内存，逐字段比对一律判「变了」，
/// 角标就跟着宿主一趟不落地重算（单元用例 `ReviewBadgeIsolationTests` 量到 20 趟重算 20 次）。
/// 所以这儿自己说清楚什么叫「没变」——同一只 feature、主题按值相等——挂的时候套 `.equatable()`。
/// 复盘记录真变了不走这条比对：body 里读 `pendingCount` 登记的观察会直接叫醒这一块。
struct ReviewCountBadge: View, Equatable {
  let review: ReviewFeature
  let theme: PanelTheme

  nonisolated static func == (a: Self, b: Self) -> Bool {
    a.review === b.review && a.theme == b.theme
  }
  #if DEBUG
    /// 测试用：这块 body 一共求值了几次。
    static var bodies = 0
    /// 测试用：按复盘本那只对象分开数。单测跑在 app 宿主里，宿主自己那条底栏也挂着一颗角标
    /// （首页 2026-10-10 成了冷启动落点之后，宿主首屏还在落定时会多画几趟），只看总数会把宿主那几趟算进来。
    static var bodiesByReview: [ObjectIdentifier: Int] = [:]
  #endif

  var body: some View {
    #if DEBUG
      let _ = Self.bodies += 1
      let _ = Self.bodiesByReview[ObjectIdentifier(review), default: 0] += 1
    #endif
    let count = review.pendingCount
    if count > 0 {
      Text("\(min(count, 99))")
        // 角标里也是字，一样守 11pt 这个下限。
        .font(TypeScale.caption2Emph)
        .monospacedDigit()
        .foregroundStyle(theme.badgeInk)
        .padding(.horizontal, Space.xs).padding(.vertical, Space.xxs)
        .frame(minWidth: 16)
        .background(theme.amber, in: Capsule())
        .allowsHitTesting(false)
        .accessibilityIdentifier("bottom.me.badge")
    }
  }
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

  /// 上下内边距 10（审查定案 16 / 10）：阶梯上没有 10，拿 8 + 2 拼。
  static let vPad = Space.s + Space.xxs
  /// 「撤销」点区比字多出来的那一圈：13pt 的字约 16 高，四边各 14 撑到 44。
  static let undoReach = (Hit.min - 16) / 2

  var body: some View {
    HStack(spacing: Space.s) {
      Text(text)
      if let undo {
        // 中间点一个间隔点，别让文案和按钮糊成一句话。
        Text("·").foregroundStyle(Color(hex: Self.secondaryInk(theme)))
        Button(action: undo) {
          // 命中区 44（UI 审查 2026-09-24 §4.3 #31）：字本身只有十五六点高，点区四边各往外撑
          // `Self.undoReach`，版面一个点不变。竖着撑出条外的那几点由 `ToastStage` 把命中矩形
          // 同步放大（`ToastCenter.hitReach`），不然透传窗口会把它们放给底下的图。
          Text(actionTitle)
            .contentShape(Rectangle().inset(by: -Self.undoReach))
        }
          .buttonStyle(.plain)
          .foregroundStyle(Color(hex: Self.actionInk(theme)))
          .accessibilityIdentifier(actionTitle == "撤销" ? "toast.undo" : "toast.action")
      }
    }
      .font(TypeScale.footnote)
      .foregroundStyle(theme.ink)
      .padding(.horizontal, Space.l)
      .padding(.vertical, Self.vPad)
      // 高约 36，圆角大过半高，本来就是胶囊。底是琉璃玻璃：一层系统模糊垫着，
      // 上面压 `fillOpacity` 的玻璃料（浅色白 / 陶土暖白，深色 `raised`），再描一圈 1/3pt 细线。
      // 料压得够厚，底下是白图还是黑图，墨色字都在 4.5:1 以上（`ToastContrastTests`）。
      .background {
        Capsule().fill(.ultraThinMaterial)
          .overlay(Capsule().fill(Color(hex: Self.base(theme)).opacity(Self.fillOpacity)))
          .overlay(Capsule().strokeBorder(Color(hex: theme.seed.ink).opacity(theme.dark ? 0.16 : 0.12),
                                          lineWidth: LiuliMaterial.hairline))
      }
      .shadow(color: .black.opacity(theme.dark ? 0.45 : 0.10), radius: 12, y: 4)
      .transition(.opacity)
  }

  /// 玻璃料压多厚。0.9：透出一点底下的颜色，读起来是玻璃；再薄，白图上的深色皮肤字就不够 4.5:1。
  static let fillOpacity = 0.9

  /// 玻璃料的颜色：浅色借琉璃的白（陶土是暖白），深色借 `raised`（深色琉璃那层太薄，托不住字）。
  static func base(_ theme: PanelTheme) -> Hex {
    if theme.dark { return theme.seed.raised }
    return Palette.isWarm(theme.seed) ? "#FFFAF4" : theme.seed.raised
  }

  /// 最坏情况下这条胶囊落成什么颜色：玻璃料 90% 盖在纯白或纯黑上（模糊层不算，按没有算）。
  static func worstSurfaces(_ theme: PanelTheme) -> [Hex] {
    let b = base(theme)
    return [Palette.mix(b, "#FFFFFF", amount: fillOpacity), Palette.mix(b, "#000000", amount: fillOpacity)]
  }

  /// 右边那颗按钮的字色：皮肤强调色，压不到 4.5:1 就往墨色挪到够为止。
  static func actionInk(_ theme: PanelTheme) -> Hex {
    Palette.readable(theme.seed.accent, on: worstSurfaces(theme), toward: theme.seed.ink)
  }

  /// 间隔点的字色：`ink3` 往墨色挪到够 4.5:1。
  static func secondaryInk(_ theme: PanelTheme) -> Hex {
    Palette.readable(theme.seed.ink3, on: worstSurfaces(theme), toward: theme.seed.ink)
  }
}
