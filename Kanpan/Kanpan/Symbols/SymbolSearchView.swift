import SwiftUI
import KanpanCore

// ============================================================ 搜索页
//
// 顶栏右上角放大镜开的那一页，长相照原型 `header-search-2026-09-17.html` 的 `searchPage()`：
//
// UI 审查 2026-09-24 按 HIG 阶梯重排之后：
//   搜索条   共用的 `SymbolSearchField`（44 高胶囊、字 15），左右跟页边距
//   取消     15 medium 强调色，点击区 44，贴在输入框右边（不是页头的返回箭头——这一页是
//            从键盘开始的，手指在下面，出口就该在同一条横线上）
//   分组头   16/8，11 medium、1 字距、ink3；右边可以挂一个垃圾桶（点击区 44）或计数
//   历史词   共用的 `SymbolChip`（看得见 28、点击区 44、字 13），和品种整页的筛选同一种
//   行       直接复用品种整页那一行（`SymbolRowView`），两页的行长得一样才不会像两个 app
//   查看全部 高 44、13 强调色
//
// 这一页只做「我知道要找什么」：打字、历史词、最近看过。分组、板块筛选、全部合约
// 那些浏览的事仍然归品种整页（`SymbolPickerView`），搜到超过 6 个时底下那行
// 「查看全部 N 个品种」就是过去的路，查询词跟着一起过去。
//
// 页面上一个英文标签都没有：栏目名、按钮、空态全是中文（用户 2026-09-18 定的），
// 只有品种代号（BTCUSDT）和金额单位（K / M / B / T）保持原样。

struct SymbolSearchView: View {
  @Bindable var model: SymbolPickerModel
  /// 历史搜索词。宿主持有（换页不丢），这儿只读写它。
  var history: SearchHistory
  /// 涨跌配色（A6.7 对调后这一页也要跟着换）。
  var redUp: Bool = false
  /// 取消 / 选中之后关掉这一页。
  var onClose: () -> Void
  /// 「查看全部 N 个品种」——交给品种整页，查询词已经在 `model.query` 里。
  var onAll: () -> Void
  /// 选中一个品种之后调一下。行情页那边不用管（`picker.onPick` 会把所有层一起收掉），
  /// 自选页把这一页当自己的盖层开着，得先自己收了再让宿主换图——不然是里层还开着、
  /// 外层先被拆，UIKit 会抱怨「dismiss while presenting」。
  var onPicked: (() -> Void)? = nil

  /// 在这一页点亮一颗星之后调一下，参数是那个品种的代号（只在「加上了」时调，
  /// 取消收藏不调）。自选页拿它把分类切到品种刚落进去的那一组——收起搜索页回到的
  /// 要是还是原来那一组，刚加的东西不在眼前，人会以为没加上。以前选品页那个 `+`
  /// 就是加完顺手跳过去的，这条只是把那个行为接回来。行情页那边不用管。
  var onStarred: ((String) -> Void)? = nil
  var onVisible: ((String) -> Void)? = nil
  var onRowVisibility: ((String, Bool) -> Void)? = nil

  @Environment(\.panelTheme) private var theme
  @FocusState private var focused: Bool
  @State private var askClear = false
  /// 剪贴板里像是有个能搜的东西（只在这一页出现的那一刻看一次，见 `ClipboardSymbol`）。
  @State private var offerPaste = false
  /// 「热门」的代号，进页时排一次就定住（审查 U7）：成交额每秒都在变，
  /// 行跟着换位置的话手指底下那一行会跑掉。行情照旧是实时的，只是顺序不动。
  @State private var hot: [String] = []

  private var seed: PaletteSeed { theme.seed }
  /// 行上的涨跌色按这一页的 `redUp` 现造（宿主灌进来的环境主题不一定带着它）。
  private var rowTheme: PanelTheme { PanelTheme(seed: seed, redUp: redUp) }

  /// 搜索结果最多先露几行（原型 `out.slice(0,6)`）：一屏之内看得完，
  /// 再多就该去品种整页慢慢翻。
  private static let previewRows = 6

  private var trimmed: String { model.query.trimmingCharacters(in: .whitespacesAndNewlines) }
  private var searching: Bool { !trimmed.isEmpty }

  /// 搜索态下那唯一一个分区（`SymbolSections.build` 有查询时只回一组）。
  private var hits: SymbolSection? { model.sections.first { $0.kind == .search } }
  private var hitCount: Int { hits.map { $0.rows.count + $0.more } ?? 0 }

  /// 最近看过。品种表还没到的时候查不到信息，那就先不显示这一组——
  /// 不占位、不解释，表到了它自己就出来。存几个就摆几个（`SymbolPrefs.recentLimit`，
  /// 10 个）：这里原来另截到 8 个，存下的最后两个永远看不见。
  private var recents: [SymbolRow] {
    model.prefs.recents.compactMap { model.info(for: $0) }.prefix(SymbolPrefs.recentLimit).map {
      SymbolRow(match: SymbolMatch(info: $0), ticker: model.ticker(for: $0.symbol))
    }
  }

  var body: some View {
    VStack(spacing: 0) {
      searchBar
      ScrollView {
        LazyVStack(alignment: .leading, spacing: 0) {
          // 剪贴板里像是有个品种时，最上面摆一个系统的粘贴按钮。
          if !searching, offerPaste { clipboardRow }
          if searching { results } else { resting }
          Color.clear.frame(height: Space.xxl)
        }
      }
      // 同自选页：系统滚动条那条竖带压在每行最右边那颗星上，而这一页加自选全靠点星，
      // 滚动条一闪那一两秒点上去会没反应，所以不露它。
      .scrollIndicators(.hidden)
      .scrollDismissesKeyboard(.interactively)
    }
    // iPad 上这一页是满屏的：不封顶的话品种名钉在最左、价格钉在最右，隔着一米。
    .readableColumn()
    .background(theme.app)
    .foregroundStyle(theme.ink)
    .confirmationDialog("清除搜索记录", isPresented: $askClear, titleVisibility: .visible) {
      Button("清除", role: .destructive) { Haptics.warning(); history.clear() }
      Button("取消", role: .cancel) {}
    }
    .task {
      // 这一页是**整页搜索页**，用户是自己点「搜索」进来的，进来就是为了打字：
      // 键盘自己上来、焦点就落在框里（用户 2026-09-18 的原话是「那儿自动聚焦是对的」）。
      //
      // 记忆 `kanpan-symbol-search-keyboard` 里「进来不自动抢焦点」那一条说的是
      // **画线工作台里点品种名弹的那层换品种浮层**（`DrawingSymbolSwitcher`，
      // 由 `ChartFoundationUITests.testDrawingSymbolSwitcherKeepsKeyboardDown` 守着）：
      // 那层的主体是底下那格「常看」，键盘一上来就把它盖了。两处是两回事，
      // 2026-09-21 曾把那条规矩误套到这一页上，键盘从此不来了。
      //
      // 先聚焦再 `await`：目录还没到的时候 `model.appear()` 要等一个网络往返，
      // 排在它后面的话人已经对着一页不动的界面点了两下了。
      focused = true
      model.setSectionsActive(true)
      refreshHot()
      await model.appear()
      refreshHot()
      await lookAtClipboard()
    }
    // 目录或行情比这一页晚到时，到了再排一次；排出来之后就不再动。
    .onChange(of: model.quoteRevision) { refreshHot() }
    .onDisappear {
      focused = false
      model.setSectionsActive(false)
    }
  }

  // ---------------------------------------------------------------- 搜索条

  private var searchBar: some View {
    HStack(spacing: Space.xs) {
      SymbolSearchField(text: $model.query, focused: $focused, id: "search.query",
                        onSubmit: { history.remember(trimmed) },
                        clearID: "search.clear",
                        onClear: { model.query = ""; focused = true })

      Button {
        focused = false
        close()
      } label: {
        Text("取消")
          .font(TypeScale.bodyEmph)
          .foregroundStyle(theme.amber)
          .padding(.horizontal, Space.s)
          .hitTarget()
      }
      .buttonStyle(.plain)
      // 字右边那截留白伸进页边距里，「取消」两个字的右沿仍在页面右边那条竖线上。
      .padding(.trailing, -Space.s)
      .accessibilityIdentifier("search.cancel")
    }
    .pageHorizontalInset()
    .padding(.vertical, Space.s)
  }

  // ---------------------------------------------------------------- 没打字：历史 + 最近

  @ViewBuilder
  private var resting: some View {
    if !history.terms.isEmpty {
      groupHead("历史搜索") {
        Button { askClear = true } label: {
          Image(systemName: "trash")
            .font(TypeScale.footnote)
            .foregroundStyle(theme.ink3)
            .hitTarget()
        }
        .buttonStyle(.plain)
        // 44 的点击区不把分组头撑高：竖向多出来的那截叠在上下的留白上。
        .frame(height: Space.l)
        .accessibilityLabel("清除搜索记录")
        .accessibilityIdentifier("search.clearHistory")
      }
      // 小块看得见 28、点击区 44：竖向多出来的 16 就是两行小块之间的间距，
      // 所以这里行距给 0，看起来仍是 16 一行。
      ChipFlow(spacing: Space.s, lineSpacing: 0) {
        ForEach(history.terms, id: \.self) { term in
          SymbolChip(title: term) {
            model.query = term
            history.remember(term)
            focused = true
          }
          .accessibilityIdentifier("search.history." + term)
        }
      }
      .pageHorizontalInset()
      .padding(.top, -Space.s)
    }

    let rows = recents
    if !rows.isEmpty {
      groupHead("最近看过") { EmptyView() }
      rowList(rows)
    }

    // 第一次打开：没搜过、也没看过，这一页原来是一整屏空白（审查 U7）。
    // 给按 24h 成交额排的前 10 个——和搜索结果、「全部合约」同一个排序口径。
    // 有了历史或最近，这一组就让位，不和它们抢位置。
    if history.terms.isEmpty, rows.isEmpty {
      let hotRows = hot.compactMap { key in
        model.info(for: key).map { SymbolRow(match: SymbolMatch(info: $0), ticker: model.ticker(for: $0.symbol)) }
      }
      if !hotRows.isEmpty {
        groupHead("热门") { EmptyView() }
          .accessibilityIdentifier("search.hot")
        rowList(hotRows)
      }
    }
  }

  private func refreshHot() {
    guard hot.isEmpty, history.terms.isEmpty, recents.isEmpty else { return }
    hot = model.hotSymbols()
  }

  // ---------------------------------------------------------------- 打了字：结果

  @ViewBuilder
  private var results: some View {
    let rows = hits?.rows ?? []
    if rows.isEmpty {
      Text(model.emptyText)
        .font(TypeScale.caption)
        .foregroundStyle(theme.ink3)
        .frame(maxWidth: .infinity, alignment: .center)
        .pageHorizontalInset()
        .padding(.vertical, Space.xxl)
        .accessibilityIdentifier("search.empty")
    } else {
      groupHead("品种") {
        Text("\(hitCount)")
          .font(TypeScale.caption2)
          .monospacedDigit()
          .foregroundStyle(theme.ink3)
      }
      rowList(Array(rows.prefix(Self.previewRows)))
      if hitCount > Self.previewRows {
        Button {
          history.remember(trimmed)
          onAll()
        } label: {
          HStack(spacing: Space.xs) {
            Text("查看全部 \(hitCount) 个品种").font(TypeScale.footnote)
            VectorIcon.chevronRight(ControlMetrics.chevron)
          }
          .foregroundStyle(theme.amber)
          .frame(maxWidth: .infinity)
          .frame(height: Hit.min)
          .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("search.all")
      }
    }
  }

  // ---------------------------------------------------------------- 零件

  /// 分组头：11 medium + 1 字距 + ink3，右边挂一个动作（垃圾桶 / 计数）。
  private func groupHead<Trailing: View>(
    _ title: String, @ViewBuilder trailing: () -> Trailing
  ) -> some View {
    HStack(alignment: .center, spacing: Space.s) {
      Text(title)
        .font(TypeScale.caption2Emph)
        .kerning(1)
        .foregroundStyle(theme.ink3)
      trailing()
      Spacer(minLength: 0)
    }
    .pageHorizontalInset()
    .padding(.top, Space.l)
    .padding(.bottom, Space.s)
  }

  @ViewBuilder
  private func rowList(_ rows: [SymbolRow]) -> some View {
    ForEach(Array(rows.enumerated()), id: \.element.id) { index, row in
      if index > 0 { SymbolRowDivider() }
      SymbolRowView(row: row,
                    isFavorite: model.isFavorite(row.id),
                    theme: rowTheme,
                    onStar: {
                      if model.toggleFavorite(row.id, info: row.info) { onStarred?(row.id) }
                    },
                    onPick: { pick(row.info) })
        .onAppear { onVisible?(row.id); onRowVisibility?(row.id, true) }
        .onDisappear { onRowVisibility?(row.id, false) }
    }
  }

  // ---------------------------------------------------------------- 剪贴板那一行

  /// 剪贴板那一行：系统自己的粘贴按钮，一按就走。
  ///
  /// 用系统按钮而不是我们自己画一行「打开 SOL」的原因写在 `ClipboardSymbol`
  /// 文件头：想在按之前就知道剪贴板里是什么，就得先弹一次「允许粘贴？」。
  /// 这颗按钮上的字（「粘贴」）和图标由系统画，我们只给它一个色。
  /// 不写「检测到剪贴板内容」之类的说明——他自己刚复制的，不用我们告诉他。
  private var clipboardRow: some View {
    HStack(spacing: 0) {
      PasteButton(payloadType: String.self) { items in
        guard let text = items.first else { return }
        takePasted(text)
      }
      .labelStyle(.titleAndIcon)
      .buttonBorderShape(.capsule)
      .tint(theme.amber)
      Spacer(minLength: 0)
    }
    .pageHorizontalInset()
    .frame(height: Hit.min)
    .accessibilityIdentifier("search.clipboard")
  }

  /// 他按了粘贴：认得出来就直接开那张图，认不出来就把这段文字填进搜索框
  /// ——他刚亲手交过来的东西，总得有个去处，不能按完什么都没发生。
  private func takePasted(_ text: String) {
    offerPaste = false
    if let info = ClipboardSymbol.resolve(text, catalog: model.catalog) {
      pick(info)
      return
    }
    let one = text.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !one.isEmpty, one.count <= 32, !one.contains("\n") else { return }
    model.query = one
  }

  /// 进页面的那一刻看一眼剪贴板。里面没有能搜的文字就什么都不摆。
  private func lookAtClipboard() async {
    guard await ClipboardSymbol.hasText() else { return }
    guard !searching else { return }
    offerPaste = true
  }

  /// 选中一个品种：把这一次搜的词记下来（真搜到了才算数），再交给宿主换图。
  private func pick(_ info: SymbolInfo) {
    focused = false
    if searching { history.remember(trimmed) }
    model.query = ""
    onPicked?()
    model.pick(info)
  }

  private func close() {
    model.query = ""
    onClose()
  }
}

// ============================================================ 会换行的一排

/// 历史词那一排：放得下就并排，放不下换行（原型 `.hchips` 的 `flex-wrap`）。
/// SwiftUI 没有现成的流式排布，`LazyVGrid` 的等宽列会把「BTC」和「1000PEPE」
/// 撑成一样宽——那一排就不像一串词了，所以自己量。
/// `Layout` 这个名字在本仓库里撞车：`KanpanCore.Layout` 是图表的几何布局。
/// 这儿要的是 SwiftUI 那个协议，写全名。
private struct ChipFlow: SwiftUI.Layout {
  var spacing: CGFloat = Space.s
  /// 行与行之间。小块自带 44 的点击区（比看得见的 28 高 16），所以通常给 0。
  var lineSpacing: CGFloat = Space.s

  func sizeThatFits(proposal: ProposedViewSize, subviews: LayoutSubviews, cache: inout ()) -> CGSize {
    let maxWidth = proposal.width ?? .infinity
    var x: CGFloat = 0, y: CGFloat = 0, rowHeight: CGFloat = 0, widest: CGFloat = 0
    for view in subviews {
      let size = view.sizeThatFits(.unspecified)
      if x > 0, x + size.width > maxWidth {
        x = 0
        y += rowHeight + lineSpacing
        rowHeight = 0
      }
      x += size.width + spacing
      widest = max(widest, x - spacing)
      rowHeight = max(rowHeight, size.height)
    }
    return CGSize(width: min(widest, maxWidth), height: y + rowHeight)
  }

  func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize,
                     subviews: LayoutSubviews, cache: inout ()) {
    var x: CGFloat = 0, y: CGFloat = 0, rowHeight: CGFloat = 0
    for view in subviews {
      let size = view.sizeThatFits(.unspecified)
      if x > 0, x + size.width > bounds.width {
        x = 0
        y += rowHeight + lineSpacing
        rowHeight = 0
      }
      view.place(at: CGPoint(x: bounds.minX + x, y: bounds.minY + y),
                 anchor: .topLeading, proposal: ProposedViewSize(size))
      x += size.width + spacing
      rowHeight = max(rowHeight, size.height)
    }
  }
}

#if DEBUG
// ============================================================ 预览

/// 自包含宿主：自己造 model 和历史词，接进主界面之前用它跑预览。
private struct SearchHost: View {
  @State private var model = SymbolPickerModel(
    catalog: SymbolFixtures.catalog,
    tickers: Array(QuoteBook.preview(SymbolFixtures.tickers).raw.values),
    store: SymbolPrefsStore(storage: MemoryPrefsStorage(), key: "preview"))
  @State private var history = SearchHistory(storage: MemorySearchHistoryStorage(), key: "preview")
  private let seeded: [String]
  private let query: String

  init(query: String = "", history seeded: [String] = ["BTC", "ETH", "SOL", "1000PEPE", "DOGE"]) {
    self.query = query
    self.seeded = seeded
  }

  var body: some View {
    SymbolSearchView(model: model, history: history,
                     onClose: {}, onAll: {})
      .onAppear {
        for term in seeded.reversed() { history.remember(term) }
        model.query = query
      }
  }
}

#Preview("搜索页 · 历史与最近") {
  SearchHost()
}

#Preview("搜索页 · 搜到了") {
  SearchHost(query: "ET")
}

#Preview("搜索页 · 没搜到") {
  SearchHost(query: "ZZZZ")
}

#Preview("搜索页 · 深") {
  SearchHost().preferredColorScheme(.dark)
}
#endif
