import KanpanCore
import SwiftUI

/// 周期条：钉住的那几档横排 + 行尾「最新 / 更多 / 图表」（§9.1）。
///
/// 条上排哪几档由用户自己钉（`quickIntervals`，A6.5），不按停留时长学习——
/// 会自己动的东西没法形成肌肉记忆。顺序固定按 `Interval.allCases` 走：从「更多」里
/// 选了个不在常用里的周期，它插进自己那个位置，不会把后面整排顶偏一格。
///
/// 钉得少的时候各档平分铺满整行，不在右边留一条空白；钉得多到排不下才退回横向滚动
/// 加边缘渐隐（见 `chips`）。药丸有个 76pt 的封顶（`maxChipWidth`），手机上够不着，
/// iPad 那种两三倍宽的行才会用上——否则同样几档会被摊成一排横向拉长的色块。
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
  /// 行尾「图表」：开 K 线那一页（`Panel.chart`）。画线、记一笔也在那一页上。
  var onChart: () -> Void

  /// 条上排哪几档：钉住的那些，外加「当前这档没被钉住」时的一颗临时 chip。
  ///
  /// 临时 chip 不占钉位，虚线描边，切回常用档就消失——否则从网格里点了个 2h，
  /// 条上会一个高亮都没有，看着像没切成。
  private var list: [Interval] {
    var set = quick
    if !set.contains(current) { set.append(current) }
    let order = Interval.allCases
    return set.sorted { (order.firstIndex(of: $0) ?? 0) < (order.firstIndex(of: $1) ?? 0) }
  }

  var body: some View {
    VStack(spacing: 0) {
      HStack(spacing: 6) {
        chips
        if !atLatest {
          tail("最新", icon: VectorIcon.chevronRight(11), action: onLatest)
            .accessibilityIdentifier("chart.latest")
            .accessibilityLabel("回到最新")
            .transition(.opacity)
        }
        tail("更多", chevron: true, on: gridOpen, flipped: gridOpen) {
          withAnimation(.easeOut(duration: 0.18)) { gridOpen.toggle() }
        }
        .accessibilityIdentifier("interval.more")
        tail("图表", action: onChart)
          .accessibilityIdentifier("interval.chart")
      }
      .padding(.horizontal, 10)
      .frame(height: 44)

      if gridOpen { grid }
    }
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

  /// 那一排按自然宽度排出来有多宽。
  ///
  /// 量的是下面那排影子 chip，不是真排——真排要铺满整行，早被撑开了，量回来的永远等于
  /// 行宽，判不出排不排得下。只有「右边那道淡出画不画」用得上它，版面本身不靠它。
  @State private var naturalWidth: CGFloat = 0

  /// 排得下就平分铺满整行，排不下才横向滚动加边缘渐隐。
  ///
  /// 行宽由外面这层 `GeometryReader` 当场给出，不走 `@State`：
  /// 一来 `ScrollView` 在横排里只按内容宽要地方，钉三档时它自己就缩成三颗药丸那么窄，
  /// 里头再怎么写行宽也铺不满；二来铺满必须给内容一个**确定的宽度**——滚动方向上
  /// `ScrollView` 给内容的提案是「随你多宽」，chip 上那句 `maxWidth: .infinity` 在这种
  /// 提案下只会退回自己的自然宽度，试过 `minWidth:` 和先量后铺，三颗 chip 都还是缩在左边。
  ///
  /// 外面这一层始终是同一个 `ScrollView`（`interval.quick`）：试过用 `ViewThatFits`
  /// 在「平铺」和「滚动」两支之间挑，排得下的时候整个 `ScrollView` 就不存在了，
  /// 一来 `ChartFoundationUITests` 里按 `scrollViews["interval.quick"]` 找条的用例
  /// 当场落空，二来那个 identifier 落到容器上会把每颗 chip 自己的
  /// `interval.chip.<iv>` 全盖成 `interval.quick`（实测七颗 chip 的 id 都变成了它）。
  @ViewBuilder private var chips: some View {
    GeometryReader { geo in
      // 排不下才需要那道淡出。留半个点余量，免得两个数差在小数位上来回抖。
      let overflows = naturalWidth > geo.size.width + 0.5
      ScrollView(.horizontal, showsIndicators: false) {
        HStack(spacing: 4) {
          ForEach(list, id: \.self) { chip($0) }
        }
        .padding(.horizontal, 2)
        .frame(width: max(geo.size.width, naturalWidth), alignment: .leading)
      }
      .accessibilityIdentifier("interval.quick")
      // 影子行：跟真那排同样的药丸，只是 `fixedSize` 不跟着铺满、也不画出来，专门用来量
      // 「这几档按自己的自然宽度排出来有多宽」。它挂在背景上，不占位、不影响横条尺寸。
      .background(alignment: .leading) {
        HStack(spacing: 4) {
          ForEach(list, id: \.self) { chipLabel($0) }
        }
        .padding(.horizontal, 2)
        .fixedSize()
        .background(GeometryReader { g in
          Color.clear.preference(key: IntervalRowWidth.self, value: g.size.width)
        })
        .hidden()
        .accessibilityHidden(true)
      }
      .onPreferenceChange(IntervalRowWidth.self) { naturalWidth = $0 }
      // 排不下时右边会切出半颗药丸，硬切看着像画错了。让它在最后那几个点里淡出去，
      // 一眼就知道「右边还有，滑一下」。
      //
      // 排得下就一点都不淡：钉住的那几档铺满整行，右边并没有藏着东西，这时候还淡一道，
      // 最后一颗「1d」看着像被啃掉一口，反而像画错了。
      .mask(LinearGradient(
        stops: overflows
          ? [.init(color: .black, location: 0),
             .init(color: .black, location: 0.93),
             .init(color: .black.opacity(0), location: 1)]
          : [.init(color: .black, location: 0), .init(color: .black, location: 1)],
        startPoint: .leading, endPoint: .trailing))
    }
    // `GeometryReader` 竖着也贪心，会把 44pt 的条整个吃掉、chip 贴到顶上。
    // 按药丸自己的高度钉死，行里照旧居中。
    .frame(height: 28)
  }

  /// 一档周期：没选中是一颗浅底药丸，选中了填 10% 的强调色淡底、字用强调色本身。
  /// 没被钉住的当前档画成虚线描边——它是临时的，切走就没了。
  private func chip(_ iv: Interval) -> some View {
    Button { onPick(iv) } label: { chipLabel(iv) }
      .buttonStyle(.plain)
      // §10.6：长按 = 取消钉。临时 chip 上长按则是把它钉下来，同一个 `toggleQuick`。
      .onLongPressGesture(minimumDuration: 0.45) { onPin(iv) }
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
      // 两头各 6pt：钉到七、八档时在 6.3 吋屏上正好还排得下，多一个点就要退回滚动，
      // 第一眼看到的就是「1d 被渐隐吃掉半颗」。字号和高度都没动，只收了内边距。
      // （出厂只钉五档，这时候是各自摊宽，收内边距不影响它。）
      .padding(.horizontal, 6)
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
      .contentShape(Capsule())
    }
    .buttonStyle(.plain)
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
      Text("至少留 1 档，最多 \(Prefs.maxQuick) 档")
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

  private func cell(_ iv: Interval) -> some View {
    let on = iv == current
    let pinned = quick.contains(iv)
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
          .frame(width: 24, height: 22)
          .contentShape(Rectangle())
      }
      .buttonStyle(.plain)
      .accessibilityIdentifier("period.pin.\(iv.rawValue)")
      .accessibilityLabel(pinned ? "从常用行移除 \(iv.display)" : "加进常用行 \(iv.display)")
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

/// 影子那一排按自然宽度排出来有多宽（含两头 2pt 内边距）。
private struct IntervalRowWidth: PreferenceKey {
  static let defaultValue: CGFloat = 0
  static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = nextValue() }
}

/// 横条自己能露出多宽。和上面那个一比就知道排不排得下。
private struct IntervalViewportWidth: PreferenceKey {
  static let defaultValue: CGFloat = 0
  static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = nextValue() }
}
