import SwiftUI
import KanpanCore

// ============================================================ 搜索页
//
// 顶栏右上角放大镜开的那一页，长相照原型 `header-search-2026-09-17.html` 的 `searchPage()`：
//
//   .sbar    7/6/8/12 内边距，输入框高 34、圆角 9、raised2 底、line 描边，字 13.5
//   .cancel  14pt 强调色，贴在输入框右边（不是页头的返回箭头——这一页是从键盘开始的，
//            手指在下面，出口就该在同一条横线上）
//   .ghead   14/16/6，11pt medium、1px 字距、ink3；右边可以挂一个垃圾桶或计数
//   .hchip   高 30、圆角 8、raised2 底、12.5pt
//   .row     11/16 的品种行——直接复用品种整页那一行（`SymbolRowView`），
//            两页的行长得一样才不会像两个 app
//   .morerow 高 44、13pt 强调色
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

  private var seed: PaletteSeed { theme.seed }
  private var colors: ChartColors { Palette.chart(seed, redUp: redUp) }

  @ScaledMetric(relativeTo: .body) private var nameSize: CGFloat = 14
  @ScaledMetric(relativeTo: .caption) private var metaSize: CGFloat = 11
  @ScaledMetric(relativeTo: .body) private var priceSize: CGFloat = 13.5
  @ScaledMetric(relativeTo: .caption) private var pctSize: CGFloat = 11

  /// 搜索结果最多先露几行（原型 `out.slice(0,6)`）：一屏之内看得完，
  /// 再多就该去品种整页慢慢翻。
  private static let previewRows = 6

  private var trimmed: String { model.query.trimmingCharacters(in: .whitespacesAndNewlines) }
  private var searching: Bool { !trimmed.isEmpty }

  /// 搜索态下那唯一一个分区（`SymbolSections.build` 有查询时只回一组）。
  private var hits: SymbolSection? { model.sections.first { $0.kind == .search } }
  private var hitCount: Int { hits.map { $0.rows.count + $0.more } ?? 0 }

  /// 最近看过。品种表还没到的时候查不到信息，那就先不显示这一组——
  /// 不占位、不解释，表到了它自己就出来。
  private var recents: [SymbolRow] {
    model.prefs.recents.compactMap { model.info(for: $0) }.prefix(8).map {
      SymbolRow(match: SymbolMatch(info: $0), ticker: model.ticker(for: $0.symbol))
    }
  }

  var body: some View {
    VStack(spacing: 0) {
      searchBar
      ScrollView {
        LazyVStack(alignment: .leading, spacing: 0) {
          if searching { results } else { resting }
          Color.clear.frame(height: 26)
        }
      }
      // 同自选页：系统滚动条那条竖带压在每行最右边那颗星上，而这一页加自选全靠点星，
      // 滚动条一闪那一两秒点上去会没反应，所以不露它。
      .scrollIndicators(.hidden)
      .scrollDismissesKeyboard(.interactively)
    }
    .background(theme.app)
    .foregroundStyle(theme.ink)
    .confirmationDialog("清除搜索记录", isPresented: $askClear, titleVisibility: .visible) {
      Button("清除", role: .destructive) { history.clear() }
      Button("取消", role: .cancel) {}
    }
    .task {
      model.setSectionsActive(true)
      await model.appear()
      focused = true
    }
    .onDisappear {
      focused = false
      model.setSectionsActive(false)
      model.disappear()
    }
  }

  // ---------------------------------------------------------------- 搜索条

  private var searchBar: some View {
    HStack(spacing: 6) {
      HStack(spacing: 7) {
        VectorIcon.search(13).foregroundStyle(theme.ink3)
        TextField("", text: $model.query, prompt:
          Text("搜 BTC、ETH、SOL…").foregroundStyle(theme.ink3))
          .font(.system(size: 13.5))
          .foregroundStyle(theme.ink)
          .textInputAutocapitalization(.characters)
          .autocorrectionDisabled()
          .submitLabel(.search)
          .focused($focused)
          .onSubmit { history.remember(trimmed) }
          .accessibilityIdentifier("search.query")
        if searching {
          Button {
            model.query = ""
            focused = true
          } label: {
            Image(systemName: "xmark.circle.fill")
              .font(.system(size: 14))
              .foregroundStyle(theme.ink3)
              .frame(width: 26, height: 30)
              .contentShape(Rectangle())
          }
          .buttonStyle(.plain)
          .accessibilityLabel("清空搜索框")
          .accessibilityIdentifier("search.clear")
        }
      }
      .padding(.horizontal, 10)
      .frame(height: 34)
      .background(RoundedRectangle(cornerRadius: 9).fill(theme.raised2))
      .overlay(RoundedRectangle(cornerRadius: 9).stroke(
        focused ? theme.amberLine : theme.line, lineWidth: focused ? 2 : 1))

      Button("取消") {
        focused = false
        close()
      }
      .font(.system(size: 14, weight: .medium))
      .foregroundStyle(theme.amber)
      .buttonStyle(.plain)
      .padding(.horizontal, 10)
      .frame(height: 34)
      .contentShape(Rectangle())
      .accessibilityIdentifier("search.cancel")
    }
    .padding(.leading, 12)
    .padding(.trailing, 6)
    .padding(.top, 7)
    .padding(.bottom, 8)
  }

  // ---------------------------------------------------------------- 没打字：历史 + 最近

  @ViewBuilder
  private var resting: some View {
    if !history.terms.isEmpty {
      groupHead("历史搜索") {
        Button { askClear = true } label: {
          Image(systemName: "trash")
            .font(.system(size: 13))
            .foregroundStyle(theme.ink3)
            .frame(width: 30, height: 24)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("清除搜索记录")
        .accessibilityIdentifier("search.clearHistory")
      }
      ChipFlow(spacing: 8) {
        ForEach(history.terms, id: \.self) { term in
          Button {
            model.query = term
            history.remember(term)
            focused = true
          } label: {
            Text(term)
              .font(.system(size: 12.5))
              .foregroundStyle(theme.ink2)
              .lineLimit(1)
              .padding(.horizontal, 13)
              .frame(height: 30)
              .background(RoundedRectangle(cornerRadius: 8).fill(theme.raised2))
          }
          .buttonStyle(.plain)
          .accessibilityIdentifier("search.history." + term)
        }
      }
      .padding(.horizontal, 16)
      .padding(.top, 4)
      .padding(.bottom, 10)
    }

    let rows = recents
    if !rows.isEmpty {
      groupHead("最近看过") { EmptyView() }
      rowList(rows)
    }
  }

  // ---------------------------------------------------------------- 打了字：结果

  @ViewBuilder
  private var results: some View {
    let rows = hits?.rows ?? []
    if rows.isEmpty {
      Text(model.emptyText)
        .font(.system(size: 12.5))
        .foregroundStyle(theme.ink3)
        .frame(maxWidth: .infinity, alignment: .center)
        .padding(.horizontal, 16)
        .padding(.vertical, 26)
        .accessibilityIdentifier("search.empty")
    } else {
      groupHead("品种") {
        Text("\(hitCount)")
          .font(.system(size: 11))
          .monospacedDigit()
          .foregroundStyle(theme.ink3)
      }
      rowList(Array(rows.prefix(Self.previewRows)))
      if hitCount > Self.previewRows {
        Button {
          history.remember(trimmed)
          onAll()
        } label: {
          HStack(spacing: 4) {
            Text("查看全部 \(hitCount) 个品种").font(.system(size: 13))
            VectorIcon.chevronRight(12)
          }
          .foregroundStyle(theme.amber)
          .frame(maxWidth: .infinity)
          .frame(height: 44)
          .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("search.all")
      }
    }
  }

  // ---------------------------------------------------------------- 零件

  /// 分组头：11pt medium + 1px 字距 + ink3，右边挂一个动作（垃圾桶 / 计数）。
  private func groupHead<Trailing: View>(
    _ title: String, @ViewBuilder trailing: () -> Trailing
  ) -> some View {
    HStack(alignment: .firstTextBaseline, spacing: 7) {
      Text(title)
        .font(.system(size: 11, weight: .medium))
        .kerning(1)
        .foregroundStyle(theme.ink3)
      trailing()
      Spacer(minLength: 0)
    }
    .padding(.horizontal, 16)
    .padding(.top, 14)
    .padding(.bottom, 6)
  }

  @ViewBuilder
  private func rowList(_ rows: [SymbolRow]) -> some View {
    ForEach(Array(rows.enumerated()), id: \.element.id) { index, row in
      if index > 0 {
        theme.hair.frame(height: 0.5).padding(.leading, 60)
      }
      SymbolRowView(row: row,
                    isFavorite: model.isFavorite(row.id),
                    seed: seed,
                    colors: colors,
                    nameSize: nameSize, metaSize: metaSize,
                    priceSize: priceSize, pctSize: pctSize,
                    onStar: {
                      if model.toggleFavorite(row.id, info: row.info) { onStarred?(row.id) }
                    },
                    onPick: { pick(row.info) })
        .padding(.horizontal, 16)
        .padding(.vertical, 11)
        .onAppear { onVisible?(row.id); onRowVisibility?(row.id, true) }
        .onDisappear { onRowVisibility?(row.id, false) }
    }
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
  var spacing: CGFloat = 8

  func sizeThatFits(proposal: ProposedViewSize, subviews: LayoutSubviews, cache: inout ()) -> CGSize {
    let maxWidth = proposal.width ?? .infinity
    var x: CGFloat = 0, y: CGFloat = 0, rowHeight: CGFloat = 0, widest: CGFloat = 0
    for view in subviews {
      let size = view.sizeThatFits(.unspecified)
      if x > 0, x + size.width > maxWidth {
        x = 0
        y += rowHeight + spacing
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
        y += rowHeight + spacing
        rowHeight = 0
      }
      view.place(at: CGPoint(x: bounds.minX + x, y: bounds.minY + y),
                 anchor: .topLeading, proposal: ProposedViewSize(size))
      x += size.width + spacing
      rowHeight = max(rowHeight, size.height)
    }
  }
}

// ============================================================ 预览

/// 自包含宿主：自己造 model 和历史词，接进主界面之前用它跑预览。
private struct SearchHost: View {
  @State private var model = SymbolPickerModel(
    catalog: SymbolFixtures.catalog,
    tickers: SymbolFixtures.tickers,
    store: SymbolPrefsStore(storage: MemoryPrefsStorage(), key: "preview"),
    feed: StaticTickerFeed(SymbolFixtures.tickers))
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
