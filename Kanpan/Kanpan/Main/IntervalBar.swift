import KanpanChart
import KanpanCore
import SwiftUI

/// 周期条：钉住的那几档横排 + 行尾「最新 / 更多 / 图表」（§9.1）。
///
/// 条上排哪几档由用户自己钉（`quickIntervals`，A6.5），不按停留时长学习——
/// 会自己动的东西没法形成肌肉记忆。顺序固定按 `Interval.allCases` 走：从「更多」里
/// 选了个不在常用里的周期，它插进自己那个位置，不会把后面整排顶偏一格。
///
/// **条上最多六档**（`Prefs.maxQuick`，2026-09-21 定）。这一行要同时放下六颗药丸、
/// 行尾那个固定槽位、「更多」和「图表」，还得在 iPhone SE（375pt）上一个字都不截——
/// 六档是实测排得下的上限，所以钉位本身就卡在六个，排版只对「≤6 档」这一种情况负责。
/// 原来那条「排不下就横向滚动 + 右边渐隐」的退路一并删了：能滚就意味着有档位藏在屏幕外，
/// 而钉住的那几档是用户自己挑的、每一档都得看得见。
///
/// 各档平分铺满整行，不在右边留一条空白。药丸有个 76pt 的封顶（`maxChipWidth`），
/// 手机上够不着，iPad 那种两三倍宽的行才会用上——否则同样几档会被摊成一排横向拉长的色块。
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
  /// 和「最新」共用行尾那个固定槽位——两颗永远不会同时在（一个的前提是不在最新，
  /// 另一个的前提是在最新）。没地方可回去时是 nil，那一格就空着（但仍然占着位子）。
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
      // 缝 4pt、两头 8pt：都是 2026-09-21 从 6 / 10 收下来的。收下来的这 10pt 全给了
      // 常用行——SE（375pt）上六档满钉时，那一排离排不下只差几个点，每一点都算数。
      // 药丸自己的高度、字号、命中区一点没动。
      HStack(spacing: 4) {
        chips
        actionSlot
        tail("更多", chevron: true, on: gridOpen, flipped: gridOpen) {
          withAnimation(.easeOut(duration: 0.18)) { gridOpen.toggle() }
        }
        .accessibilityIdentifier("interval.more")
        tail("图表", action: onChart)
          .accessibilityIdentifier("interval.chart")
      }
      .padding(.horizontal, 8)
      .frame(height: 44)

      if gridOpen { grid }
    }
  }

  // ---------------------------------------------------------------- 行尾那个固定槽位

  /// 行尾「最新 / 返回刚才」那一格，**三种状态下一样宽**（§P3-1）。
  ///
  /// 这一格原来不存在：药丸直接插在 `HStack` 里，来一颗、走一颗，常用行分到的宽度
  /// 就跟着变一次。而常用行的规矩是「排得下就平分铺满整行」——宽度一变，钉住的那几档
  /// 全体重新摊开，人正要点的那一档在手指落下去之前挪了位置。实测（`IntervalSlotUITests`）
  /// 一颗药丸露面，1d 那颗就往左跳 19.3pt，正好是一根手指的宽度。
  ///
  /// 所以这一格按**最宽的那一种文案**钉死：底下垫一颗画不出来的影子药丸（「返回刚才」，
  /// 四个字，比「最新」宽），真正要画的那颗贴着右边叠在它上面。空着的时候这一格仍然
  /// 占着位子，于是常用行拿到的宽度从头到尾是同一个数，一个点都不动。
  ///
  /// 槽位里**只可能有一颗**：「最新」的前提是不在最新，「返回刚才」的前提是在最新。
  /// 「看细节」从前也挤在这儿，2026-09-20 搬去了头部那一行十字线动作里——
  /// 两颗并排要 143pt，16 Pro 上把钉住的周期挤得只剩三档半；而它本来就是十字线的动作，
  /// 和「上一根 / 下一根 / 按此价画线」是一伙的（见 `CrosshairReadoutRow`）。
  ///
  /// 两颗上原来各有一个小箭头（`‹` / `›`），2026-09-21 去掉了：槽位是按最宽的那句话
  /// 钉死的，箭头连着间距占 14pt，而这 14pt 是从六档周期嘴里抠出来的——SE 上恰好是
  /// 「排得下」和「排不下」的分界。「最新」「返回刚才」四个字本身已经把话说完了。
  private var actionSlot: some View {
    ZStack(alignment: .trailing) {
      tail("返回刚才") {}
        .hidden()
        .accessibilityHidden(true)

      if !atLatest {
        tail("最新", action: onLatest)
          .accessibilityIdentifier("chart.latest")
          .accessibilityLabel("回到最新")
          .transition(.opacity)
      } else if let onReturn {
        tail("返回刚才", action: onReturn)
          .accessibilityIdentifier("chart.returnBack")
          .accessibilityLabel("回到刚才看的那一屏")
          .transition(.opacity)
      }
    }
    .fixedSize(horizontal: true, vertical: false)
  }

  // ---------------------------------------------------------------- 常用那一排

  /// 一颗药丸铺满时最宽能到多少。
  ///
  /// 「钉得少就平分铺满整行」这条是按 iPhone 的行宽定的：最宽的 17 Pro Max 上五档也就各
  /// 摊到 57pt 左右，离这个上限还远，行为一点没变。iPad 的行宽是它的两三倍，不封顶的话
  /// 同样五档会各摊到 130～210pt——一排横向拉长的大色块，字还缩在正中央，一眼就是拉伸。
  /// 封在 76pt：手机上照旧铺满，iPad 上药丸保持正常大小，多出来的宽度留成末档与行尾
  /// 「更多／图表」之间的一段空白，读起来是自然的间距而不是被撑开的控件。
  private static let maxChipWidth: CGFloat = 76

  /// 钉住的那几档，平分铺满行里剩下的宽度。
  ///
  /// 这里没有滚动、没有渐隐、也没有「排不排得下」的判断：档数封在六个（见 `list`），
  /// 行尾那三件（固定槽位 / 更多 / 图表）各自按自然宽度先占好位子，剩下的全归这一排。
  /// 最窄的 iPhone SE（375pt）上六档照样一个字不截——`IntervalSlotUITests` 量的就是这个。
  ///
  /// 均分靠的是每颗药丸身上那句 `maxWidth`（见 `chipLabel`）：横排把「超出各自自然宽度
  /// 的那部分」摊给能伸的孩子，字本身先 `fixedSize` 钉死，所以「15m」「30m」这种长一点的
  /// 档不会被摊薄成省略号。这一排必须拿到一个**确定的宽度**才谈得上铺满——
  /// 外面那层 `HStack` 宽度是确定的，行尾几颗又都 `fixedSize`，剩给这里的自然也是确定的。
  private var chips: some View {
    // 间距 0，那点缝挪进每颗药丸自己的命中区里（各让 2pt）：看上去还是 4pt 的缝，
    // 但两颗的命中区正好首尾相接，缝里没有点不着的死区，也不会互相重叠到
    // 「点这颗切了那一档」。
    HStack(spacing: 0) {
      ForEach(list, id: \.self) { chip($0) }
    }
    .padding(.horizontal, 2)
    // 整条的 44pt：药丸自己仍是 28pt 高、在里头居中，上下多出来的那两圈是它的命中区
    //（见 `chip`），不是把药丸画大了。
    .frame(maxWidth: .infinity)
    .frame(height: 44)
    // 容器自己也要认领这个 id：以前它挂在横向 `ScrollView` 上，滚动没了之后
    // 用 `children: .contain` 起一个容器元素，UI 测试还能按 `interval.quick` 量这一排的框，
    // 每颗 chip 自己的 `interval.chip.<iv>` 也照旧各是各的。
    .accessibilityElement(children: .contain)
    .accessibilityIdentifier("interval.quick")
  }

  /// 一档周期：没选中是一颗浅底药丸，选中了填 10% 的强调色淡底、字用强调色本身。
  /// 没被钉住的当前档画成虚线描边——它是临时的，切走就没了。
  ///
  /// 命中区比画出来的那颗大一圈：横着各 2pt（把 `HStack` 让出来的那 4pt 缝吃掉一半），
  /// 竖着撑满整条 44pt。外面再用一句负的竖向内边距把**版面**高度收回 28pt——
  /// 条还是 44pt 高、药丸还是 28pt 高，变大的只有手指够得着的范围。
  /// 放大必须写在 `label` 里面：`Button` 认的是标签自己的 `contentShape`，
  /// 套在按钮外面的 `frame` 它一点都不认。
  private func chip(_ iv: Interval) -> some View {
    Button { onPick(iv) } label: {
      chipLabel(iv)
        .padding(.horizontal, 2)
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
      // 字先 `fixedSize` 钉死自己的自然宽度，再谈铺满。铺满靠每颗 `maxWidth: .infinity`，
      // 横排是**均分**，「15m」「30m」这种四个字符的档分到的那一份比它自己还窄，
      // 当场被截成「1…」「3…」。钉死之后均分只分多出来的那部分，窄的宽的都写得全，
      // 排不下时那一排按自然宽度铺开，每颗也还是写得全。
      .fixedSize(horizontal: true, vertical: false)
      // 两头各 2pt。这个数只决定「这一排按自然宽度最少要多宽」，也就是排得下排不下：
      // 有富余的时候每颗都摊到均分的那一份（下面 `maxWidth`），画出来多宽跟它无关，
      // 所以收紧它并不会让药丸变窄——只有挤到极限时才看得出来。
      // 2026-09-20 从 6 收到 4，2026-09-21 又收到 2：六档满钉是新的上限工况，
      // SE（375pt）上留给常用行的只有一百七十几个点，按 4 算出来的自然宽会顶出去。
      // 字号和高度都没动。
      .padding(.horizontal, 2)
      .frame(maxWidth: Self.maxChipWidth)
      .frame(height: 28)
      // 选中态填 10% 的强调色，不是整颗实心。
      //
      // 这颗药丸离蜡烛只有 30pt，实心强调色是整屏饱和度最高的一块，比任何一根蜡烛都跳——
      // 可它要说的只是「九档里选中了这一档」，跟八个兄弟分得开就够，不需要在全屏抢第一。
      // 2026-09-17 逐像素比 AICoin：它的 chrome 一律 10% 淡底 + 彩色字
      // （`sh_base_transparent_highlight_color` = `#1a1478fa`，落白底上就是 `#E8F1FF`），
      // 高饱和块在周期行只占 0.58%，我们实心时是 4.77%。实心留给「这一屏要看的那个数」——
      // 顶栏那颗涨跌胶囊——chrome 一概降到 10%。
      .background(on ? AnyShapeStyle(theme.amberSoft) : AnyShapeStyle(theme.raised),
                  in: Capsule())
      .overlay {
        if temp {
          Capsule().strokeBorder(theme.amber,
            style: StrokeStyle(lineWidth: 1, dash: [3, 2.5]))
        }
      }
      .contentShape(Capsule())
  }

  /// 条右端那几颗：和周期一样是药丸，只是底色深一档（原型 `.draw` 用的是 `surf2`），
  /// 好让「选哪一档周期」和「按哪个动作」在一条线上仍然分得开。
  ///
  /// 「更多」带下箭头（那是从条上往下拉出一张网格，展开时箭头翻上去），「图表」不带
  /// （它开的是另一页，不是这根条的延伸）。
  private func tail(
    _ title: String, chevron: Bool = false, icon: VectorIcon? = nil,
    on: Bool = false, flipped: Bool = false, action: @escaping () -> Void
  ) -> some View {
    Button(action: action) {
      HStack(spacing: 3) {
        if let icon { icon }
        Text(title).font(.system(size: 12.5, weight: .semibold))
        if chevron {
          VectorIcon.chevron(9, w: 1.7).rotationEffect(.degrees(flipped ? 180 : 0))
        }
      }
      .foregroundStyle(on ? theme.amber : theme.ink2)
      .padding(.horizontal, 9)
      .frame(height: 28)
      // 和周期药丸同一条规矩：选中 / 展开态是 10% 淡底 + 强调色字，不是实心。
      .background(on ? AnyShapeStyle(theme.amberSoft) : AnyShapeStyle(theme.raised2),
                  in: Capsule())
      // 命中区：竖着撑满整条 44pt，横着最窄也有 44pt（「图表」两个字算出来是 43pt，
      // 差的那一点从这儿补上，其余几颗本来就更宽）。药丸自己还是 28pt 高。
      .frame(minWidth: 44, minHeight: 44)
      .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
    // 版面高度收回 28pt：多出来的那两圈只是手指的范围，不许把条顶高。
    .padding(.vertical, -8)
    // 行尾这几颗先按自己的自然宽度占好位置，剩下的才归常用行。
    // 常用行那头是个「有多少要多少」的 `GeometryReader`，不钉死的话它会跟这几颗抢，
    // 「最新」刚插进来那一帧能被挤成零宽——UI 测试里当场报
    // 「Activation point invalid」，点都点不着。
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
    .panelToast(store)
  }
}

