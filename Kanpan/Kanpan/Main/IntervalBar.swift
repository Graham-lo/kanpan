import KanpanChart
import KanpanCore
import SwiftUI
import UIKit

/// 周期条：钉住的那几档横排 + 行尾「最新 | 更多 ▾ · 指标 · 图表设置」（§9.1）。
///
/// 档位一律写中文短写（`Interval.shortLabel`：5分 / 1时 / 1周 / 1月，审查 U12）——
/// 以前条上 `1m` 和「更多」网格里的 `1M` 只差一个大小写，一分钟和一个月靠眼力分。
///
/// 条上排哪几档由用户自己钉（`quickIntervals`，A6.5），不按停留时长学习——
/// 会自己动的东西没法形成肌肉记忆。顺序固定按 `Interval.allCases` 走。从「更多」里
/// 选了个不在常用里的周期，条上这一排一个都不动，行尾的「更多」写成那一档的名字
/// （2026-09-23，见 `list`）。
///
/// **条上最多六档**（`Prefs.maxQuick`，2026-09-21 定），**出厂就把六格放满**
/// （`Interval.quick` = `5m 30m 1h 4h 1d 1w`）。这一行要同时放下六档、行尾的
/// 「最新」、「更多」、「指标」和图表设置，还得在最窄的 iPhone 16 Pro（402pt，内容 370pt）上
/// 一个字都不截——六档是实测排得下的上限，所以钉位本身就卡在六个，排版只对「≤6 档」负责。
///
/// **排版预算**（2026-09-24 加「指标」时逐项算过，13pt semibold）：六档 + 每格 2×2 内距、
/// 「最新」8 前缝 + 药丸、分隔线 17、「更多 ▾」53.8、「指标」44、图表设置记号 31
/// （它的 44pt 命中区往右伸进页边距，版面只占记号本身，见 `chartButton`）。
/// 出厂六档满钉加「最新」刚好排下；最宽的六档组合（15分 30分 12时 …）加「最新」
/// 会多出八九个点，这时只把格子里那 2pt 内距按剩下的空当收窄（`chipPad`），不缩字、不截字。
/// 原来那条「排不下就横向滚动 + 右边渐隐」的退路一并删了：能滚就意味着有档位藏在屏幕外，
/// 而钉住的那几档是用户自己挑的、每一档都得看得见。
///
/// **这一行读起来必须是「一行文字 + 一个高亮」，不是一排色块**（2026-09-21 用户看了
/// 出厂第一屏的截图定的：「这排版布局有点丑不协调吧」）。三件事合起来做到这个：
///
/// - 每一档占一个**等宽的格子**（`chips`），文字在格子正中，于是档与档之间的留白均匀；
///   没选中的档是**平文字、没有任何底色**，六档连读是一行字。
/// - 只有**当前那一档**有底：一颗贴着文字的淡底药丸（`mark`），宽度按文字算而不是撑满
///   格子，所以它是「文字底下的一层底」，不是又一个色块。
/// - 「最新」**不预留槽位**：不在场时零宽度，在场时淡入，周期区跟着
///   平滑地重新铺满（0.18s）。原来那颗画不出来的影子药丸把行尾恒定地占掉八十来点，
///   出厂第一屏就是「五颗药丸 + 一段空白 + 更多 图表」，用户一眼看出来的就是那段空白。
///
/// 格子有个 76pt 的封顶（`maxChipWidth`），手机上够不着，iPad 那种两三倍宽的行才会
/// 用上——否则同样几档会被摊成一排横向拉长的色块。
///
/// 右端原来还有「画线」「记一笔」，用户的话是「这个功能不是经常用到啊」「记和画线都
/// 放到图表栏目里」，两个都收进图表设置那一页（见 `ChartPanel`）。
///
/// 2026-09-24 行尾加了「指标」（用户：「现在指标这个大类放到周期条中，我看周期条还可以塞下
/// 一个大分类」），同一天「返回刚才」按用户要求整个删掉（「不需要这个功能」）。
struct IntervalBar: View {
  /// 这一行的字：13（`TypeScale.control` / `controlOn`，`.footnote` 曲线，UI 审查 2026-09-24 §4.3 #24）。
  /// 当前档那层底要按字宽画，得拿到**此刻真的排出来**的字号，所以字号自己在这儿按同一条曲线量一份
  /// （`textWidth` 用的就是它），不走 `.font(TypeScale.control)`。封顶跟头部一起（`MarketChrome.typeCap`）。
  ///
  /// 封顶必须在这儿**自己夹**，不能指望 `body` 末尾那句 `.dynamicTypeSize(...)`：那句只管
  /// `body` 里面的子视图，这个结构体自己的属性（原来是 `@ScaledMetric`）读的是**外面**的环境，
  /// 系统字号开到 AX3 时它照样量出 AX3 的字号——周期条的字比头部大一圈、整排比页宽多出 10pt，
  /// 把头部、图表一起往左右各顶出 5pt（UI 整改 P1c 在 16 Pro 上复现：六格右缘 391 > 386）。
  @Environment(\.dynamicTypeSize) private var systemTypeSize
  private var textSize: CGFloat {
    let capped = min(systemTypeSize, MarketChrome.typeCap)
    let traits = UITraitCollection(preferredContentSizeCategory: UIContentSizeCategory(capped))
    return UIFontMetrics(forTextStyle: .footnote).scaledValue(for: TypeScale.control.size, compatibleWith: traits)
  }
  var theme: PanelTheme
  var quick: [Interval]
  var current: Interval
  /// 图还停在最新那根上没有。翻走了行尾才多出一颗「最新」。
  ///
  /// 这颗以前是浮在画布右下角的一个 44×44 圆钮。用户定过规矩：画布上不许浮任何控件，
  /// 所以它搬到了条上——位置固定、不遮 K 线，也不会跟副图的分隔线打架。
  var atLatest: Bool
  /// 「更多」那张网格开着没有。状态放在外面：点图、开面板都要顺手把它收起来。
  @Binding var gridOpen: Bool
  var onPick: (Interval) -> Void
  /// 钉 / 取消钉一档（`Prefs.toggleQuick`）。越界的那两句话由外面弹 toast。
  var onPin: (Interval) -> Void
  /// 「最新」：把视野拽回末根。
  var onLatest: () -> Void
  /// 行尾「指标」：直接开指标页（`Panel.indicators`），不用先进图表设置再推一层。
  var onIndicators: () -> Void
  /// 行尾图表设置那颗记号：开 K 线那一页（`Panel.chart`）。画线、记一笔也在那一页上。
  var onChart: () -> Void

  /// 条上排哪几档：**只有钉住的那些**，按 `Interval.allCases` 从短到长。
  ///
  /// 从前当前档没钉住时会在这儿追加一颗虚线描边的临时 chip，钉满六档时还得把最长的
  /// 那一档先让出去——从网格里点个没钉住的 2h，
  /// 用户自己钉的 1w 当场从条上消失（2026-09-23 体验审查）。钉住的档是人挑的，
  /// 不该被一个临时去看的周期挤掉；现在当前档没钉住时，由行尾「更多」改写成那一档的
  /// 名字并高亮（见 `body`），这一排一个都不动。
  ///
  /// 存档里躺着多于六档（上限从 10 收到 6 之前钉的、手改的存档）时按从短到长取前六个，
  /// 和 `PrefsCodec` 落盘那一侧是同一条规矩。
  private var list: [Interval] {
    let order = Interval.allCases
    func rank(_ iv: Interval) -> Int { order.firstIndex(of: iv) ?? order.count }
    return Array(quick.sorted { rank($0) < rank($1) }.prefix(Prefs.maxQuick))
  }

  /// 当前档没钉在条上：「更多」替它说出来。
  private var currentOffBar: Bool { !list.contains(current) }

  /// 「更多」此刻写什么：当前档没钉在条上时写成那一档（见 `body`）。
  private var moreTitle: String { currentOffBar ? current.shortLabel : "更多" }

  var body: some View {
    // 缝全交给格子自己（等宽 + 文字居中），所以这一层 `spacing` 是 0：行尾那几件
    // 各自带着自己的留白——「最新」自带 8pt 的前缝，分隔线两侧各 8pt，
    // 「更多」「指标」本来就有 44pt 的命中区兜着。
    ZStack {
      // 量这一行**能给多少**（不是这一行排出来多宽——挤不下时横排会比给的更宽，
      // 拿它判断就永远「排得下」）。`Color.clear` 在 ZStack 里只吃提议的宽度，量到的就是
      // 页边距以内的那一截；`chipPad` 拿它判断要不要把格子内距收掉。
      Color.clear
        .frame(height: 0)
        .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { barWidth = $0 }
        .accessibilityHidden(true)
      HStack(spacing: 0) {
        chips
        actionSlot
        divider
        // 当前档没钉在条上时，「更多」就写成那一档（「2h ▾」）并高亮：人一眼知道
        // 自己正看着哪一档，钉住的那几档也一个都没被挤走。网格拉开时照旧高亮。
        tail(moreTitle, chevron: true,
             on: gridOpen || currentOffBar, flipped: gridOpen) {
          withAnimation(.easeOut(duration: 0.2)) { gridOpen.toggle() }
        }
        .accessibilityIdentifier("interval.more")
        .accessibilityLabel(currentOffBar ? "更多周期，当前 \(current.display)" : "更多周期")
        .accessibilityAddTraits(currentOffBar ? [.isSelected] : [])
        // 「指标」：平文字、**没有下箭头**——「更多」的箭头说的是「从条上往下拉一张网格」，
        // 这颗开的是一张面板（指标页），不是这根条的延伸。开之前先把网格收起来。
        tail("指标") {
          if gridOpen { withAnimation(.easeOut(duration: 0.2)) { gridOpen = false } }
          onIndicators()
        }
        .accessibilityIdentifier("interval.indicators")
        .accessibilityLabel("指标")
        // 图表设置只画一颗记号（审查 U12）：原来写的「图表」和底栏那一格同名，
        // 点开的却是设置面板；读屏照旧读得出它是什么。版面只占记号本身（见 `chartButton`）。
        chartButton
      }
    }
    // 两头 `Inset.page`（16 Pro 16 / 17 Pro Max 20）：和头部内容的左缘对齐（UI 审查 2026-09-24 §4.3 #23）。
    .pageHorizontalInset()
    .frame(height: 44)
    .dynamicTypeSize(...MarketChrome.typeCap)
    // 「最新」进出时周期区跟着重新铺满。这一句兜住 `MainScreen` 那头
    // 没有包 `withAnimation` 的情况：没有它，六档会「啪」地跳一下位置。
    .animation(.easeOut(duration: 0.18), value: atLatest)
    // 「更多」那张网格不在这儿了：它是图上的一层弹层（`IntervalPopoverLayer`），
    // 这根条永远 44pt，展开收起图的高度一个 pt 都不动。
  }

  // ---------------------------------------------------------------- 周期区与动作之间

  /// 一条 1×14 的细线，把「选哪一档周期」和「按哪个动作」分成两摊。
  ///
  /// 行尾那几个动作 2026-09-21 从药丸改成了平文字（和没选中的周期一个画法），
  /// 于是需要一条线来说明它们不是周期——原来那层底色承担的就是这件事，
  /// 但一行里摆七八颗深浅不一的底才是用户说的「不协调」。线用皮肤自己的分割线色
  /// （`theme.line`，经典皮肤下就是 AICoin 周期条上下那条 `#EAEAEA`），不另起颜色。
  private var divider: some View {
    Rectangle()
      .fill(theme.line)
      .frame(width: 1, height: 14)
      .padding(.horizontal, Space.s)
      .accessibilityHidden(true)
  }

  // ---------------------------------------------------------------- 行尾「最新」

  /// 「最新」：**要的时候才在，不在就一点宽度都不占**。
  ///
  /// 这儿原来是一个钉死宽度的固定槽位，底下垫一颗画不出来的影子药丸，为的是
  /// 「药丸进出时周期不跳位」。代价是：绝大多数时候这一行里恒定地空着八十来点——
  /// 2026-09-21 用户看出厂第一屏的截图，第一句话就是这段空白
  /// （「周期条空间足够放，那可以搞点间距隔开啊」）。空槽换成了两件事：
  ///
  /// - 六档**出厂就把行放满**（`Interval.quick`），那点宽度本来就该是周期的；
  /// - 它进出时**周期区平滑地重新铺满**（`body` 上那句 `animation`），
  ///   不是瞬移一下。跳位之所以讨厌，是因为它在手指落下去之前无声地发生；
  ///   0.18s 的铺开是看得见的，手跟得上。
  ///
  /// 「看细节」从前也挤在这儿，后来搬进十字线动作行，2026-09-25 整套删了；十字线在时
  /// 整行顶替这根条的是那颗「创建提醒」（`CrosshairActionBar`）。
  /// 同一处原来还会在点完「最新」后换成「返回刚才」，2026-09-24 按用户要求删了。
  @ViewBuilder private var actionSlot: some View {
    if !atLatest {
      actionPill("最新", action: onLatest)
        .accessibilityIdentifier("chart.latest")
        .accessibilityLabel("回到最新")
        .transition(.opacity)
    }
  }

  /// 「最新」那颗药丸。
  ///
  /// 这是整条上**唯一还带底色的动作**（`raised2`）：它是随状态冒出来的一件事，
  /// 得让人一眼看见它来了；「更多」「指标」和图表设置是常驻的入口，平文字就够。
  private func actionPill(_ title: String, action: @escaping () -> Void) -> some View {
    // 命中区横着最窄 44pt；药丸本身（字 + 两边 8）不到 44 时，多出来的那一点
    // 往两边伸进前缝和分隔线的留白里，**不占版面**——这一行排版是按药丸本身算的。
    let bleed = max(0, Hit.min - Self.pillWidth(title, size: textSize)) / 2
    return Button(action: action) {
      Text(title)
        .font(.system(size: textSize, weight: .semibold))
        .foregroundStyle(theme.ink2)
        .padding(.horizontal, Space.s)
        .frame(height: ControlMetrics.pillHeight)
        .background(theme.raised2, in: Capsule())
        // 命中区：竖着撑满整条 44pt，横着最窄也有 44pt。药丸自己还是 28pt 高。
        .frame(minWidth: Hit.min, minHeight: Hit.min)
        .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
    // 版面高度收回 28pt：多出来的那两圈只是手指的范围，不许把条顶高。
    .padding(.vertical, -8)
    .fixedSize(horizontal: true, vertical: false)
    .padding(.horizontal, -bleed)
    // 它和末档之间的缝。不在场时整个视图都不存在，这 8pt 也跟着没有。
    .padding(.leading, Space.s)
  }

  // ---------------------------------------------------------------- 排版预算

  /// 页边距以内这一行能给多少宽（见 `body` 里那颗 `Color.clear`）。0 = 还没量到。
  @State private var barWidth: CGFloat = 0

  /// 每格文字两边的内距：平时 2pt，**挤不下时按剩下的空当收窄**，最少到 0。
  ///
  /// 这 2pt 只决定「这一排按自然宽度最少要多宽」：排得下时每格都摊到均分的那一份，
  /// 画出来多宽跟它无关；排不下时它就是把字顶出去的那几个点。最宽的六档组合
  /// （15分 30分 12时 4时 6时 3分，字宽 158.9）加「最新」在 16 Pro 的 370pt 里
  /// 要 378.5，不缩字号、不截字，只收内距。
  ///
  /// 不一刀收到 0：那样宽的三字档（15分 30分 12时）会一颗贴一颗连成一串，空出来的
  /// 那十几点全被窄档吃掉（2026-09-24 取证图里「15分30分12时」连读）。按剩下的空当
  /// 均摊给每一格（取到 0.25pt 往下），上面那组收到 1.25，字与字之间还留着 2.5pt。
  private var chipPad: CGFloat {
    guard barWidth > 0, !list.isEmpty else { return Space.xxs }
    let text = list.reduce(0) { $0 + Self.rawTextWidth($1.shortLabel, size: textSize) }
    let slack = barWidth - tailWidth - text
    let share = slack / (CGFloat(list.count) * 2)
    return max(0, min(Space.xxs, (share * 4).rounded(.down) / 4))
  }

  /// 行尾那几件按自己的自然宽度一共占多少：「最新」（在场时）+ 分隔线 + 「更多 ▾」+「指标」+ 图表设置。
  /// 和下面各自的画法一一对应，改了画法这儿要跟着改。
  private var tailWidth: CGFloat {
    let latest = atLatest ? 0 : Space.s + Self.pillWidth("最新", size: textSize)
    let divider = 1 + Space.s * 2
    let more = max(Hit.min, Self.rawTextWidth(moreTitle, size: textSize) + 3 + 9 + Space.s * 2)
    let indicators = max(Hit.min, Self.rawTextWidth("指标", size: textSize) + Space.s * 2)
    return latest + divider + more + indicators + Self.chartSlot
  }

  /// 「最新」药丸本身多宽（字 + 两边 8）。
  @MainActor private static func pillWidth(_ title: String, size: CGFloat) -> CGFloat {
    rawTextWidth(title, size: size) + Space.s * 2
  }

  // ---------------------------------------------------------------- 常用那一排

  /// 一个格子铺满时最宽能到多少。
  ///
  /// 「档位平分整行」这条是按 iPhone 的行宽定的：最宽的 17 Pro Max 上六档也就各摊到
  /// 五十来点，离这个上限还远，行为一点没变。iPad 的行宽是它的两三倍，不封顶的话
  /// 同样六档会各摊到 130～210pt——字缩在一格正中央，格与格之间空得读不出是一排。
  /// 封在 76pt：手机上照旧铺满，iPad 上多出来的宽度留成末档与行尾之间的一段空白。
  private static let maxChipWidth: CGFloat = 76

  /// 当前那一档的底，比文字往外撑多少（每边）。
  private static let markPad: CGFloat = 8

  /// 那层底离自己格子左右边沿最少留多少——它可以比文字宽，但不许伸到邻档的字底下。
  private static let markGap: CGFloat = 4

  /// 这一排此刻有多宽。只用来算每个格子多宽（`cellWidth`），进而算那层底最宽能画到多少。
  @State private var rowWidth: CGFloat = 0

  /// 一个格子多宽。等宽是 `chipLabel` 里那句 `maxWidth` 挣来的，这儿只是把同一个数
  /// 算出来给底用——背景不参与布局，只能自己算。
  private var cellWidth: CGFloat {
    guard rowWidth > 0, !list.isEmpty else { return 0 }
    return min(rowWidth / CGFloat(list.count), Self.maxChipWidth)
  }

  /// 钉住的那几档，各占一个等宽的格子，平分行里剩下的宽度。
  ///
  /// 这里没有滚动、没有渐隐：档数封在六个（见 `list`），行尾那几件（「最新」/ 分隔线 /
  /// 更多 / 指标 / 图表设置）各自按自然宽度先占好位子，剩下的全归这一排。挤不下时只收
  /// 格子内距（`chipPad`）。最窄的 iPhone 16 Pro 上六档照样一个字不截——
  /// `IntervalSlotUITests` 量的就是这个。
  ///
  /// **等宽是这一行看起来协调的全部原因**：文字在各自格子的正中，于是档与档之间的留白
  /// 只跟「格子多宽、字多宽」有关，不跟「这一档是不是当前档」有关。均分靠的是每个格子
  /// 身上那句 `maxWidth`（见 `chipLabel`）：横排把「超出各自自然宽度的那部分」摊给能伸的
  /// 孩子，字本身先 `fixedSize` 钉死，所以「15m」「30m」这种长一点的档不会被摊薄成省略号。
  private var chips: some View {
    // 间距 0：格子之间首尾相接，缝在格子里头（文字居中让出来的那两边），
    // 所以缝里没有点不着的死区，也不会互相重叠到「点这颗切了那一档」。
    HStack(spacing: 0) {
      ForEach(list, id: \.self) { chip($0) }
    }
    // 整条的 44pt：底自己仍是 28pt 高、在里头居中，上下多出来的那两圈是命中区
    //（见 `chip`），不是把它画大了。
    .frame(maxWidth: .infinity)
    .frame(height: 44)
    .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { rowWidth = $0 }
    // 容器自己也要认领这个 id：以前它挂在横向 `ScrollView` 上，滚动没了之后
    // 用 `children: .contain` 起一个容器元素，UI 测试还能按 `interval.quick` 量这一排的框，
    // 每颗 chip 自己的 `interval.chip.<iv>` 也照旧各是各的。
    .accessibilityElement(children: .contain)
    .accessibilityIdentifier("interval.quick")
  }

  /// 一档周期：没选中就是一行字里的一个词，选中了在它底下垫一层 10% 的强调色。
  ///
  /// 命中区是**整个格子 × 44pt**，比看得见的那几个字大得多：格子等宽、首尾相接，
  /// 手指落在两档之间也一定归其中一档。外面再用一句负的竖向内边距把**版面**高度
  /// 收回 28pt——条还是 44pt 高，变大的只有手指够得着的范围。
  /// 放大必须写在 `label` 里面：`Button` 认的是标签自己的 `contentShape`，
  /// 套在按钮外面的 `frame` 它一点都不认。
  private func chip(_ iv: Interval) -> some View {
    Button { onPick(iv) } label: {
      chipLabel(iv)
        .frame(height: 44)
        .contentShape(Rectangle())
    }
      .buttonStyle(.plain)
      // §10.6：长按 = 取消钉（条上只剩钉住的档，长按只可能是拔掉它）。
      // 挂在收版面高度之前：长按认的是这一层的框，收完再挂就只剩 28pt 那一条。
      .onLongPressGesture(minimumDuration: 0.45) { onPin(iv) }
      .padding(.vertical, -8)
      .accessibilityIdentifier("interval.chip.\(iv.rawValue)")
      .accessibilityLabel(iv.display)
      .accessibilityAddTraits(iv == current ? [.isSelected] : [])
  }

  @ViewBuilder private func chipLabel(_ iv: Interval) -> some View {
    let on = iv == current
    Text(iv.shortLabel)
      .font(.system(size: textSize, weight: on ? .semibold : .medium))
      .foregroundStyle(on ? theme.amber : theme.ink2)
      // 字先 `fixedSize` 钉死自己的自然宽度，再谈铺满。铺满靠每格 `maxWidth`，
      // 横排是**均分**，「15m」「30m」这种四个字符的档分到的那一份可能比它自己还窄，
      // 当场被截成「1…」「3…」。钉死之后均分只分多出来的那部分，窄的宽的都写得全。
      .fixedSize(horizontal: true, vertical: false)
      // 两头各 2pt。这个数只决定「这一排按自然宽度最少要多宽」，也就是排得下排不下：
      // 有富余的时候每格都摊到均分的那一份（下面 `maxWidth`），画出来多宽跟它无关。
      // 2026-09-20 从 6 收到 4，2026-09-21 又收到 2；2026-09-24 行尾多了「指标」，
      // 挤不下时再收到 0（`chipPad`）。
      .padding(.horizontal, chipPad)
      .frame(maxWidth: Self.maxChipWidth)
      .frame(height: 28)
      .background(alignment: .center) { mark(iv, on: on) }
      .contentShape(Rectangle())
  }

  /// 当前那一档底下的那层底。**只有当前档有**，其余五档是平文字。
  ///
  /// 三件事凑成「贴着文字的一层底」而不是「又一个色块」：
  ///
  /// - 它是 `background`，**不参与布局**——格子等宽这件事不会因为哪一档被选中而变形，
  ///   换一档也不会把整排顶动一下。
  /// - 宽度按文字算（`markWidth`：文字 + 每边 8pt），不是撑满格子。iPad 上格子 76pt 宽，
  ///   撑满就是一颗横躺的大药丸。
  /// - 但最宽只到「格子宽 - 4pt」：六档满钉、行尾又站着「最新」时，一格只有
  ///   二十几点，按文字往外撑 8pt 会压到邻档的字上。挤到那个份上，底就贴着文字画。
  ///
  /// 填 10% 的强调色，不是实心：这一行离蜡烛只有 30pt，实心强调色是整屏饱和度最高的
  /// 一块，比任何一根蜡烛都跳，可它要说的只是「十四档里选中了这一档」。2026-09-17
  /// 逐像素比过 AICoin：它的 chrome 一律 10% 淡底 + 彩色字
  /// （`sh_base_transparent_highlight_color` = `#1a1478fa`，落白底上就是 `#E8F1FF`）。
  @ViewBuilder private func mark(_ iv: Interval, on: Bool) -> some View {
    if on {
      Capsule()
        .fill(theme.amberSoft)
        .frame(width: markWidth(iv), height: 28)
    }
  }

  /// 那层底画多宽：贴着文字（每边 `markPad`），但不许伸到邻档的字底下（格子宽 - `markGap`）。
  private func markWidth(_ iv: Interval) -> CGFloat {
    let text = Self.textWidth(iv.shortLabel, size: textSize)
    let hug = text + Self.markPad * 2
    let cell = cellWidth
    guard cell > 0 else { return hug }              // 还没量到这一排多宽，先按贴着文字画
    return max(text, min(hug, cell - Self.markGap))
  }

  /// 一档的字有多宽。
  ///
  /// 底不参与布局，所以拿不到「这几个字被排成了多宽」，只能按同一支字体自己算一遍。
  /// 一律按 `.semibold` 量（当前档就是这个字重），差的那零点几个点落在 8pt 的留白里。
  /// 字号是 `textSize`：13 按 `UIFontMetrics(.footnote)` 的曲线缩放，先夹到 `MarketChrome.typeCap`
  /// 为止——和排出来的字一模一样。
  @MainActor private static func textWidth(_ text: String, size: CGFloat) -> CGFloat {
    ceil(rawTextWidth(text, size: size))
  }

  /// 同上，不取整。排版预算（`chipPad`）用它：六档加行尾七八件，每件取整多出的
  /// 零点几个点加起来能到三四点，出厂满钉那种只差一两点的工况会被误判成「排不下」。
  @MainActor private static func rawTextWidth(_ text: String, size: CGFloat) -> CGFloat {
    let font = UIFont.systemFont(ofSize: size, weight: .semibold)
    return (text as NSString).size(withAttributes: [.font: font]).width
  }

  /// 条右端那几个动作：**平文字，没有底色**——和没选中的周期一个画法，
  /// 整条读起来才是一行字。它们和周期分得开靠的是中间那条 `divider`，不是各自的底色。
  ///
  /// 「更多」展开时、或者当前档没钉在条上（它替那一档说话）时才亮起来：字变强调色、
  /// 底下垫同一套 10% 的淡底（和当前档一个规矩）。
  ///
  /// 「更多」带下箭头（那是从条上往下拉出一张网格，展开时箭头翻上去）；「指标」没有箭头，
  /// 它开的是一张面板；图表设置那颗只有记号、没有字（审查 U12，见 `VectorIcon.adjust`）。
  private func tail(
    _ title: String, chevron: Bool = false,
    on: Bool = false, flipped: Bool = false, action: @escaping () -> Void
  ) -> some View {
    tailButton(on: on, action: action) {
      HStack(spacing: 3) {
        Text(title).font(.system(size: textSize, weight: .semibold))
        if chevron {
          VectorIcon.chevron(9, w: 1.7).rotationEffect(.degrees(flipped ? 180 : 0))
        }
      }
    }
  }

  private func tailButton<Label: View>(
    on: Bool, bleedsTrailing: Bool = false, action: @escaping () -> Void, @ViewBuilder label: () -> Label
  ) -> some View {
    Button(action: action) {
      label()
      .foregroundStyle(on ? theme.amber : theme.ink2)
      .padding(.horizontal, Space.s)
      .frame(height: ControlMetrics.pillHeight)
      .background { if on { Capsule().fill(theme.amberSoft) } }
      // 命中区：竖着撑满整条 44pt，横着最窄也有 44pt（「指标」两个字 + 两边 8pt 只有
      // 41.8pt，差的从这儿补上）。这 44pt 顺带成了动作之间的留白。
      // 图表设置那颗贴左放：多出来的 13pt 要往右伸进页边距（见 `chartButton`）。
      .frame(minWidth: Hit.min, minHeight: Hit.min, alignment: bleedsTrailing ? .leading : .center)
      .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
    // 版面高度收回 28pt：多出来的那两圈只是手指的范围，不许把条顶高。
    .padding(.vertical, -8)
    // 行尾这几件先按自己的自然宽度占好位置，剩下的才归周期区。
    // 不钉死的话它们会跟「有多少要多少」的周期区抢，「最新」刚插进来那一帧能被挤成零宽
    // ——UI 测试里当场报「Activation point invalid」，点都点不着。
    .fixedSize(horizontal: true, vertical: false)
    .padding(.trailing, bleedsTrailing ? Self.chartSlot - Hit.min : 0)
  }

  /// 图表设置那颗在版面上占多宽：记号 15pt + 两边 8pt。
  private static let chartSlot: CGFloat = 15 + Space.s * 2

  /// 行尾图表设置那颗记号。**版面只占记号本身**（`chartSlot` = 31pt），44pt 的命中区
  /// 往右伸 13pt 进页边距（16 Pro 16 / 17 Pro Max 20，伸得进去）：2026-09-24 行尾多了
  /// 「指标」，这 13pt 是出厂六档满钉加「最新」还排得下的那一截。顺带记号的右缘
  /// 离头部内容的右缘只差它自己那 8pt 留白。
  private var chartButton: some View {
    tailButton(on: false, bleedsTrailing: true, action: onChart) { VectorIcon.adjust() }
      .accessibilityIdentifier("interval.chart")
      .accessibilityLabel("图表设置")
  }
}

/// 横屏侧栏那一版「更多」。
///
/// 横屏没有周期条（右侧是 `IntervalRail`），所以在侧栏里摆同一张网格
/// （`IntervalGridPopover`），换档、钉、钉满换档都和竖屏一模一样。
struct IntervalGridPanel: View {
  var store: PrefsStore
  var onPick: ((Interval) -> Void)?

  @Environment(\.panelTheme) private var t
  @Environment(\.dismiss) private var dismiss
  @Environment(\.panelDismiss) private var sideDismiss

  var body: some View {
    PanelSheet(title: "周期", subtitle: nil) {
      IntervalGridPopover(
        theme: t, quick: store.prefs.quickIntervals, current: store.prefs.interval,
        onPick: { iv in
          store.update { $0.interval = iv }
          onPick?(iv)
          PanelCloser(side: sideDismiss, sheet: dismiss)()
        },
        onPin: { iv in store.attempt { $0.toggleQuick(iv) } },
        onReplace: { old, new in store.update { $0.replaceQuick(old: old, new: new) } })
      .frame(maxWidth: .infinity)
    }
  }
}

/// 竖屏周期条那一行：平时是周期条，十字线活着时整行换成那颗「创建提醒」。
///
/// 独立成非泛型 struct 有两个原因：一是把这几层从 `MainScreen.chartPage` 的类型嵌套里
/// 摘出去（见 `MainScreen.swift` 文件头那条层数上限）；二是只有这一层去观察十字线——
/// 让位靠 `YieldsToCrosshair`，按钮自己观察 `readout`，主屏 body 不因手指移动重算。
struct IntervalRow: View {
  var theme: PanelTheme
  var quick: [Interval]
  var current: Interval
  var atLatest: Bool
  @Binding var gridOpen: Bool
  var onPick: (Interval) -> Void
  var onPin: (Interval) -> Void
  var onLatest: () -> Void
  var onIndicators: () -> Void
  var onChart: () -> Void
  let readout: CrosshairReadout
  let context: CrosshairContext
  /// 十字线那颗「创建提醒」点了。
  var onAlert: (Double) -> Void

  var body: some View {
    ZStack {
      IntervalBar(
        theme: theme, quick: quick, current: current, atLatest: atLatest,
        gridOpen: $gridOpen, onPick: onPick, onPin: onPin,
        onLatest: onLatest, onIndicators: onIndicators, onChart: onChart)
        .modifier(YieldsToCrosshair(readout: readout, context: context, gridOpen: $gridOpen))
      CrosshairActionBar(readout: readout, context: context, theme: theme, onAlert: onAlert)
    }
    .frame(height: 44)
    .background(theme.app)
  }
}
