import KanpanChart
import KanpanCore
import SwiftUI
import UIKit

/// 周期条：钉住的那几档横排 + 行尾「最新 / 更多 / 图表」（§9.1）。
///
/// 条上排哪几档由用户自己钉（`quickIntervals`，A6.5），不按停留时长学习——
/// 会自己动的东西没法形成肌肉记忆。顺序固定按 `Interval.allCases` 走：从「更多」里
/// 选了个不在常用里的周期，它插进自己那个位置，不会把后面整排顶偏一格。
///
/// **条上最多六档**（`Prefs.maxQuick`，2026-09-21 定），**出厂就把六格放满**
/// （`Interval.quick` = `5m 30m 1h 4h 1d 1w`）。这一行要同时放下六档、行尾的
/// 「最新 / 返回刚才」、「更多」和「图表」，还得在 iPhone SE（375pt）上一个字都不截——
/// 六档是实测排得下的上限，所以钉位本身就卡在六个，排版只对「≤6 档」这一种情况负责。
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
/// - 「最新 / 返回刚才」**不再预留槽位**：不在场时零宽度，在场时淡入，周期区跟着
///   平滑地重新铺满（0.18s）。原来那颗画不出来的影子药丸把行尾恒定地占掉八十来点，
///   出厂第一屏就是「五颗药丸 + 一段空白 + 更多 图表」，用户一眼看出来的就是那段空白。
///
/// 格子有个 76pt 的封顶（`maxChipWidth`），手机上够不着，iPad 那种两三倍宽的行才会
/// 用上——否则同样几档会被摊成一排横向拉长的色块。
///
/// 右端原来还有「画线」「记一笔」，用户的话是「这个功能不是经常用到啊」「记和画线都
/// 放到图表栏目里」，两个都收进「图表」那一页（见 `ChartPanel`）。
struct IntervalBar: View {
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
  /// 「返回刚才」：刚从历史上被「最新」拽回来，再点它回到刚才看的那一屏（§P3-2）。
  ///
  /// 和「最新」是同一个位置上的两颗——两颗永远不会同时在（一个的前提是不在最新，
  /// 另一个的前提是在最新）。没地方可回去时是 nil，那儿**一点宽度都不占**。
  var onReturn: (() -> Void)? = nil
  /// 行尾「图表」：开 K 线那一页（`Panel.chart`）。画线、记一笔也在那一页上。
  var onChart: () -> Void

  /// 条上排哪几档：钉住的那些，外加「当前这档没被钉住」时的一颗临时 chip。
  ///
  /// 临时 chip 不占钉位，虚线描边，切回常用档就消失——否则从网格里点了个 2h，
  /// 条上会一个高亮都没有，看着像没切成。
  ///
  /// 总数**硬卡在 `Prefs.maxQuick`（六）**，这是排版唯一负责的那个数：
  ///
  /// - 存档里躺着更多档（上限从 10 收到 6 之前钉的、手改的存档）时，按从短到长取前六个，
  ///   和 `PrefsCodec` 落盘那一侧是同一条规矩；
  /// - 已经钉满六档、人又从网格里点了个没钉住的周期时，临时 chip 得有地方站，
  ///   就把最长的那一档先让出来（当前这档永远留着——正看着的那一档消失是最难解释的）。
  ///   切回任意一档常用周期，让出去的那一档立刻回来。
  private var list: [Interval] {
    let order = Interval.allCases
    func rank(_ iv: Interval) -> Int { order.firstIndex(of: iv) ?? order.count }
    var set = Array(quick.sorted { rank($0) < rank($1) }.prefix(Prefs.maxQuick))
    guard !set.contains(current) else { return set }
    set.append(current)
    set.sort { rank($0) < rank($1) }
    while set.count > Prefs.maxQuick, let drop = set.last(where: { $0 != current }) {
      set.removeAll { $0 == drop }
    }
    return set
  }

  var body: some View {
    VStack(spacing: 0) {
      // 缝全交给格子自己（等宽 + 文字居中），所以这一层 `spacing` 是 0：行尾那几件
      // 各自带着自己的留白——「最新」自带 6pt 的前缝，分隔线两侧各 8pt，
      // 「更多 / 图表」本来就有 44pt 的命中区兜着。
      HStack(spacing: 0) {
        chips
        actionSlot
        divider
        tail("更多", chevron: true, on: gridOpen, flipped: gridOpen) {
          withAnimation(.easeOut(duration: 0.18)) { gridOpen.toggle() }
        }
        .accessibilityIdentifier("interval.more")
        tail("图表", action: onChart)
          .accessibilityIdentifier("interval.chart")
      }
      // 两头 12pt：和头部内容的左缘对齐（2026-09-21 从 8 放回来的——影子药丸删掉之后
      // 这一行不再需要从边距里抠那几个点）。
      .padding(.horizontal, 12)
      .frame(height: 44)
      // 「最新 / 返回刚才」进出时周期区跟着重新铺满。这一句兜住 `MainScreen` 那头
      // 没有包 `withAnimation` 的情况：没有它，六档会「啪」地跳一下位置。
      .animation(.easeOut(duration: 0.18), value: atLatest)
      .animation(.easeOut(duration: 0.18), value: onReturn != nil)

      if gridOpen { grid }
    }
  }

  // ---------------------------------------------------------------- 周期区与动作之间

  /// 一条 1×14 的细线，把「选哪一档周期」和「按哪个动作」分成两摊。
  ///
  /// 行尾那两个动作 2026-09-21 从药丸改成了平文字（和没选中的周期一个画法），
  /// 于是需要一条线来说明它们不是周期——原来那层底色承担的就是这件事，
  /// 但一行里摆七八颗深浅不一的底才是用户说的「不协调」。线用皮肤自己的分割线色
  /// （`theme.line`，经典皮肤下就是 AICoin 周期条上下那条 `#EAEAEA`），不另起颜色。
  private var divider: some View {
    Rectangle()
      .fill(theme.line)
      .frame(width: 1, height: 14)
      .padding(.horizontal, 8)
      .accessibilityHidden(true)
  }

  // ---------------------------------------------------------------- 行尾「最新 / 返回刚才」

  /// 「最新 / 返回刚才」：**要的时候才在，不在就一点宽度都不占**。
  ///
  /// 这儿原来是一个按最宽那句话（「返回刚才」）钉死的固定槽位，底下垫一颗画不出来的
  /// 影子药丸，为的是「药丸进出时周期不跳位」。代价是：绝大多数时候这一行里恒定地
  /// 空着八十来点——2026-09-21 用户看出厂第一屏的截图，第一句话就是这段空白
  /// （「周期条空间足够放，那可以搞点间距隔开啊」）。空槽换成了两件事：
  ///
  /// - 六档**出厂就把行放满**（`Interval.quick`），那点宽度本来就该是周期的；
  /// - 它进出时**周期区平滑地重新铺满**（`body` 上那两句 `animation`），
  ///   不是瞬移一下。跳位之所以讨厌，是因为它在手指落下去之前无声地发生；
  ///   0.18s 的铺开是看得见的，手跟得上。
  ///
  /// 这儿**只可能有一颗**：「最新」的前提是不在最新，「返回刚才」的前提是在最新。
  /// 「看细节」从前也挤在这儿，2026-09-20 搬去了头部那一行十字线动作里——
  /// 它本来就是十字线的动作，和「上一根 / 下一根 / 按此价画线」是一伙的
  /// （见 `CrosshairReadoutRow`）。
  ///
  /// 两颗上原来各有一个小箭头（`‹` / `›`），2026-09-21 去掉了：「最新」「返回刚才」
  /// 四个字本身已经把话说完了，箭头连着间距占 14pt。
  @ViewBuilder private var actionSlot: some View {
    if !atLatest {
      actionPill("最新", action: onLatest)
        .accessibilityIdentifier("chart.latest")
        .accessibilityLabel("回到最新")
        .transition(.opacity)
    } else if let onReturn {
      actionPill("返回刚才", action: onReturn)
        .accessibilityIdentifier("chart.returnBack")
        .accessibilityLabel("回到刚才看的那一屏")
        .transition(.opacity)
    }
  }

  /// 「最新 / 返回刚才」那颗药丸。
  ///
  /// 这是整条上**唯一还带底色的动作**（`raised2`）：它是随状态冒出来的一件事，
  /// 得让人一眼看见它来了；「更多 / 图表」是常驻的两个入口，平文字就够。
  private func actionPill(_ title: String, action: @escaping () -> Void) -> some View {
    Button(action: action) {
      Text(title)
        .font(.system(size: 12.5, weight: .semibold))
        .foregroundStyle(theme.ink2)
        .padding(.horizontal, 9)
        .frame(height: 28)
        .background(theme.raised2, in: Capsule())
        // 命中区：竖着撑满整条 44pt，横着最窄也有 44pt。药丸自己还是 28pt 高。
        .frame(minWidth: 44, minHeight: 44)
        .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
    // 版面高度收回 28pt：多出来的那两圈只是手指的范围，不许把条顶高。
    .padding(.vertical, -8)
    // 它和末档之间的缝。不在场时整个视图都不存在，这 6pt 也跟着没有。
    .padding(.leading, 6)
    .fixedSize(horizontal: true, vertical: false)
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
  /// 这里没有滚动、没有渐隐、也没有「排不排得下」的判断：档数封在六个（见 `list`），
  /// 行尾那几件（「最新」/ 分隔线 / 更多 / 图表）各自按自然宽度先占好位子，剩下的全归这一排。
  /// 最窄的 iPhone SE（375pt）上六档照样一个字不截——`IntervalSlotUITests` 量的就是这个。
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
  /// 没被钉住的当前档在那层底上再加一圈虚线——它是临时的，切走就没了。
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
      // §10.6：长按 = 取消钉。临时 chip 上长按则是把它钉下来，同一个 `toggleQuick`。
      // 挂在收版面高度之前：长按认的是这一层的框，收完再挂就只剩 28pt 那一条。
      // 钉满六档时临时 chip 上的长按不做事（和网格里那些灰掉的图钉同一条规矩），
      // 不再走一遍「按了 → 弹一句钉不上」。
      .onLongPressGesture(minimumDuration: 0.45) {
        if quick.contains(iv) || !pinFull { onPin(iv) }
      }
      .padding(.vertical, -8)
      .accessibilityIdentifier("interval.chip.\(iv.rawValue)")
      .accessibilityLabel(iv.display)
      .accessibilityAddTraits(iv == current ? [.isSelected] : [])
  }

  @ViewBuilder private func chipLabel(_ iv: Interval) -> some View {
    let on = iv == current
    let temp = !quick.contains(iv)
    Text(iv.rawValue)
      .font(.system(size: 12.5, weight: on ? .semibold : .medium))
      .foregroundStyle(on ? theme.amber : theme.ink2)
      // 字先 `fixedSize` 钉死自己的自然宽度，再谈铺满。铺满靠每格 `maxWidth`，
      // 横排是**均分**，「15m」「30m」这种四个字符的档分到的那一份可能比它自己还窄，
      // 当场被截成「1…」「3…」。钉死之后均分只分多出来的那部分，窄的宽的都写得全。
      .fixedSize(horizontal: true, vertical: false)
      // 两头各 2pt。这个数只决定「这一排按自然宽度最少要多宽」，也就是排得下排不下：
      // 有富余的时候每格都摊到均分的那一份（下面 `maxWidth`），画出来多宽跟它无关。
      // 2026-09-20 从 6 收到 4，2026-09-21 又收到 2：六档满钉是上限工况，
      // SE（375pt）上留给这一排的只有一百七十几个点，按 4 算出来的自然宽会顶出去。
      .padding(.horizontal, 2)
      .frame(maxWidth: Self.maxChipWidth)
      .frame(height: 28)
      .background(alignment: .center) { mark(iv, on: on, temp: temp) }
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
  /// - 但最宽只到「格子宽 - 4pt」：SE 上六档满钉、行尾又站着「返回刚才」时，一格只有
  ///   二十几点，按文字往外撑 8pt 会压到邻档的字上。挤到那个份上，底就贴着文字画。
  ///
  /// 填 10% 的强调色，不是实心：这一行离蜡烛只有 30pt，实心强调色是整屏饱和度最高的
  /// 一块，比任何一根蜡烛都跳，可它要说的只是「十四档里选中了这一档」。2026-09-17
  /// 逐像素比过 AICoin：它的 chrome 一律 10% 淡底 + 彩色字
  /// （`sh_base_transparent_highlight_color` = `#1a1478fa`，落白底上就是 `#E8F1FF`）。
  ///
  /// `temp`（当前档没被钉住）在那层底上再加一圈虚线。`list` 只在「当前档没钉住」时
  /// 才放它进来，所以 `temp` 必然同时 `on`，虚线不会单独出现。
  @ViewBuilder private func mark(_ iv: Interval, on: Bool, temp: Bool) -> some View {
    if on {
      Capsule()
        .fill(theme.amberSoft)
        .overlay {
          if temp {
            Capsule().strokeBorder(theme.amber,
              style: StrokeStyle(lineWidth: 1, dash: [3, 2.5]))
          }
        }
        .frame(width: markWidth(iv), height: 28)
    }
  }

  /// 那层底画多宽：贴着文字（每边 `markPad`），但不许伸到邻档的字底下（格子宽 - `markGap`）。
  private func markWidth(_ iv: Interval) -> CGFloat {
    let text = Self.textWidth(iv.rawValue)
    let hug = text + Self.markPad * 2
    let cell = cellWidth
    guard cell > 0 else { return hug }              // 还没量到这一排多宽，先按贴着文字画
    return max(text, min(hug, cell - Self.markGap))
  }

  /// 一档的字有多宽。
  ///
  /// 底不参与布局，所以拿不到「这几个字被排成了多宽」，只能按同一支字体自己算一遍。
  /// 一律按 `.semibold` 量（当前档就是这个字重），差的那零点几个点落在 8pt 的留白里。
  @MainActor private static func textWidth(_ text: String) -> CGFloat {
    let font = UIFont.systemFont(ofSize: 12.5, weight: .semibold)
    return ceil((text as NSString).size(withAttributes: [.font: font]).width)
  }

  /// 条右端那两个动作：**平文字，没有底色**——和没选中的周期一个画法，
  /// 整条读起来才是一行字。它们和周期分得开靠的是中间那条 `divider`，不是各自的底色。
  ///
  /// 只有「更多」展开时才亮起来：字变强调色、底下垫同一套 10% 的淡底（和当前档一个规矩），
  /// 说明「这张网格是它拉开的」。
  ///
  /// 「更多」带下箭头（那是从条上往下拉出一张网格，展开时箭头翻上去），「图表」不带
  /// （它开的是另一页，不是这根条的延伸）。
  private func tail(
    _ title: String, chevron: Bool = false,
    on: Bool = false, flipped: Bool = false, action: @escaping () -> Void
  ) -> some View {
    Button(action: action) {
      HStack(spacing: 3) {
        Text(title).font(.system(size: 12.5, weight: .semibold))
        if chevron {
          VectorIcon.chevron(9, w: 1.7).rotationEffect(.degrees(flipped ? 180 : 0))
        }
      }
      .foregroundStyle(on ? theme.amber : theme.ink2)
      .padding(.horizontal, 8)
      .frame(height: 28)
      .background { if on { Capsule().fill(theme.amberSoft) } }
      // 命中区：竖着撑满整条 44pt，横着最窄也有 44pt（「图表」两个字算出来是 43pt，
      // 差的那一点从这儿补上）。这 44pt 顺带成了两个动作之间的留白。
      .frame(minWidth: 44, minHeight: 44)
      .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
    // 版面高度收回 28pt：多出来的那两圈只是手指的范围，不许把条顶高。
    .padding(.vertical, -8)
    // 行尾这几件先按自己的自然宽度占好位置，剩下的才归周期区。
    // 不钉死的话它们会跟「有多少要多少」的周期区抢，「最新」刚插进来那一帧能被挤成零宽
    // ——UI 测试里当场报「Activation point invalid」，点都点不着。
    .fixedSize(horizontal: true, vertical: false)
  }

  // ---------------------------------------------------------------- 「更多」网格

  /// 十四档摊成 4×4，直接把图往下推，不再开一层 sheet。
  ///
  /// 以前这是半屏 `PeriodPanel`：弹一层、选一下、再收一层，换个周期要三次动画。
  /// 摊在条下面之后，点开点选点收都在原地，也顺带解决了「『更多』这个词不说明它是什么」——
  /// 十四档全摆在眼前。
  private var grid: some View {
    VStack(spacing: 8) {
      LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 4),
                spacing: 8) {
        ForEach(Interval.allCases, id: \.self) { cell($0) }
      }
      // 钉满了就换成四个字，直说为什么那些图钉按不动；没满时还是原来那句范围。
      // 两句都是网格底下的一行小字，不弹窗、不挡手——按不动的图钉本身已经灰在那儿了。
      Text(pinFull ? "已满六档" : "至少留 1 档，最多 \(Prefs.maxQuick) 档")
        .font(.system(size: 11))
        .foregroundStyle(theme.ink3)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
    // 四列 `.flexible()` 会把整行宽度平分：iPad 上一格能摊到 250pt 宽、还是 42pt 高，
    // 十四个横躺的长条。封一个和手机相当的上限，网格照旧从左边起排。
    .frame(maxWidth: 460, alignment: .leading)
    .frame(maxWidth: .infinity, alignment: .leading)
    .padding(.horizontal, 10)
    .padding(.bottom, 10)
    .transition(.move(edge: .top).combined(with: .opacity))
    .clipped()
  }

  /// 钉位满了没有。满了之后没钉住的那些图钉一律按不动（§2026-09-21「最多六档」）。
  private var pinFull: Bool { quick.count >= Prefs.maxQuick }

  private func cell(_ iv: Interval) -> some View {
    let on = iv == current
    let pinned = quick.contains(iv)
    // 钉满六档之后，其余那些图钉灰下去、按不动：条上只保证六档排得开，
    // 让人钉第七个再弹一句「钉不上」，是先给希望再收回去。
    let canPin = pinned || !pinFull
    return ZStack(alignment: .topTrailing) {
      Button {
        onPick(iv)
        withAnimation(.easeOut(duration: 0.18)) { gridOpen = false }
      } label: {
        Text(iv.display)
          .font(.system(size: 12.5, weight: on ? .semibold : .medium))
          .foregroundStyle(on ? theme.amber : theme.ink2)
          .frame(maxWidth: .infinity)
          .frame(height: 42)
          // 同上：网格里当前那一格也是 10% 淡底 + 强调色字。
          .background(on ? AnyShapeStyle(theme.amberSoft) : AnyShapeStyle(theme.raised),
                      in: RoundedRectangle(cornerRadius: 10, style: .continuous))
          .contentShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
      }
      .buttonStyle(.plain)
      .accessibilityIdentifier("period.row.\(iv.rawValue)")
      .accessibilityLabel(iv.display)
      .accessibilityAddTraits(on ? [.isSelected] : [])

      // 图钉压在格子右上角：钉住的实心，没钉的是个空壳。点它只钉不切档。
      Button { onPin(iv) } label: {
        Image(systemName: pinned ? "pin.fill" : "pin")
          .font(.system(size: 9.5, weight: .medium))
          .foregroundStyle(pinned ? theme.amber : theme.ink3)
          .opacity(canPin ? 1 : 0.3)
          .frame(width: 24, height: 22)
          .contentShape(Rectangle())
      }
      .buttonStyle(.plain)
      .disabled(!canPin)
      .accessibilityIdentifier("period.pin.\(iv.rawValue)")
      .accessibilityLabel(
        pinned ? "从常用行移除 \(iv.display)"
          : canPin ? "加进常用行 \(iv.display)" : "已满六档，钉不下 \(iv.display)")
    }
  }
}

/// 横屏侧栏那一版「更多」。
///
/// 竖屏的网格是摊在条下面的，横屏没有那根条（右侧是 `IntervalRail`），所以在侧栏里
/// 再挂一份同样的网格。`PeriodPanel` 那张半屏表因此可以整张删掉，功能一个都不少。
struct IntervalGridPanel: View {
  var store: PrefsStore
  var onPick: ((Interval) -> Void)?

  @Environment(\.panelTheme) private var t
  @Environment(\.dismiss) private var dismiss
  @Environment(\.panelDismiss) private var sideDismiss
  @State private var open = true

  var body: some View {
    PanelSheet(title: "周期", subtitle: nil) {
      IntervalBar(
        theme: t, quick: store.prefs.quickIntervals, current: store.prefs.interval,
        atLatest: true, gridOpen: $open,
        onPick: { iv in
          store.update { $0.interval = iv }
          onPick?(iv)
          PanelCloser(side: sideDismiss, sheet: dismiss)()
        },
        onPin: { iv in store.attempt { $0.toggleQuick(iv) } },
        onLatest: {},
        onChart: {})
      .frame(maxWidth: .infinity)
    }
  }
}

