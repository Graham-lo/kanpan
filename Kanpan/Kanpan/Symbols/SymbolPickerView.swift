import SwiftUI
import KanpanCore
import KanpanNetwork
import UIKit

// ============================================================ 品种整页
//
// §9.3 / §10.5 / A5.7–A5.9，UI 审查 2026-09-24 按 HIG 阶梯重排：
//   页头     左右跟页边距（`Inset.page`），标题 17 semibold，右边条数 11 ink3，返回键点击区 44
//   搜索     共用的 `SymbolSearchField`（44 高胶囊、字 15），右边「清空」点击区 44
//   筛选     共用的 `SymbolChip`（看得见 28、点击区 44），和搜索页历史词同一种
//   行       共用的 `SymbolRowView`（名 15、价 15 等宽数字带千分位、涨跌 13，行高 ≥ 44）
//   分组标题 11 medium 字距 1，吸顶时垫页面底色，滚上去的行不从它底下透出来
//   小字     12 ink3
//
// 进页不自动聚焦搜索框（见 `.task`），返回时收键盘。

struct SymbolPickerView: View {
  @Bindable var model: SymbolPickerModel
  /// 涨跌配色（A6.7：设置里对调后，品种页的涨跌幅也要跟着换）。
  var redUp: Bool = false
  /// 返回。宿主给，一般就是关掉这一页。
  var onClose: (() -> Void)?
  var onSelect: ((SymbolInfo) -> Void)? = nil
  var onVisible: ((String) -> Void)? = nil
  var onRowVisibility: ((String, Bool) -> Void)? = nil

  @Environment(\.panelTheme) private var theme
  @FocusState private var searchFocused: Bool
  @State private var dragging: String?
  /// 自选段里现在划开着的是哪一行。同一时刻只许一行（见 `SwipeToDelete`）。
  @State private var openSwipe: String?
  @State private var filterSelection: FilterSelection?
  @State private var filterTask: Task<Void, Never>?
  private enum FilterSelection { case market, sector }

  private var seed: PaletteSeed { theme.seed }
  private var colors: ChartColors { Palette.chart(seed, redUp: redUp) }

  /// 行上的涨跌色按这一页的 `redUp` 现造（宿主灌进来的环境主题不一定带着它）。
  private var rowTheme: PanelTheme { PanelTheme(seed: seed, redUp: redUp) }

  var body: some View {
    VStack(spacing: 0) {
      header
      searchBar
      filters
      list
    }
    // 同搜索页：这一页也是满屏的一列行，iPad 上不封顶就两端拉开一米（见 `readableColumn`）。
    .readableColumn()
    .background(Color(hex: seed.app))
    .confirmationDialog(filterSelection == .market ? "市场" : "板块",
      isPresented: Binding(get: { filterSelection != nil }, set: { if !$0 { filterSelection = nil } }),
      titleVisibility: .visible) {
        if filterSelection == .market {
          Button("全部市场") { model.marketFilter = "all" }
          ForEach(model.markets, id: \.self) { key in Button(MarketSector.title(key)) { model.marketFilter = key } }
        } else {
          Button("全部板块") { model.sectorFilter = nil }
          ForEach(model.sectors, id: \.self) { key in Button(MarketSector.title(key)) { model.sectorFilter = key } }
        }
      }
    .task {
      model.setSectionsActive(true)
      await model.appear()
      // 进页不自己把键盘顶起来（记忆 kanpan-symbol-search-keyboard，
      // 方案第 3 节第五件 a）：这一页第一眼是那张品种表，键盘糊上来就盖掉半屏，
      // 而人多半是进来翻的，不是进来打字的。要打字他自己点那个框。
      // 以前这儿有一句 `searchFocused = true`。
    }
    .onDisappear {
      filterTask?.cancel()
      searchFocused = false
      model.setSectionsActive(false)
    }
  }

  // ---------------------------------------------------------------- 页头

  private var header: some View {
    HStack(spacing: Space.xs) {
      Button {
        searchFocused = false
        onClose?()
      } label: {
        Chevron()
          .stroke(Color(hex: seed.ink2), style: StrokeStyle(lineWidth: 1.7, lineCap: .round, lineJoin: .round))
          .frame(width: Self.chevron, height: Self.chevron)
          // 描边形状的按钮，点击区默认只有那条 1.7pt 的线本身（A8.4 在 5 台机器上实测到）。
          // 补一块 44 的矩形点击区（HIG），画面一个像素都不动。
          .hitTarget()
      }
      .buttonStyle(.plain)
      // 点击区左半截伸进页边距里，箭头那个 18 的框仍贴着页面左边那条竖线。
      .padding(.leading, -(Hit.min - Self.chevron) / 2)
      .accessibilityLabel("返回")
      .accessibilityIdentifier("symbols.back")

      HStack(alignment: .firstTextBaseline, spacing: Space.s) {
        Text("品种").font(TypeScale.title).foregroundStyle(Color(hex: seed.ink))
        Text(model.countText).font(TypeScale.caption2).foregroundStyle(Color(hex: seed.ink3))
      }
      Spacer(minLength: 0)
    }
    .pageHorizontalInset()
    .padding(.top, Space.xs)
    .overlay(alignment: .bottom) { Divider().overlay(Color(hex: seed.line)) }
  }

  /// 返回箭头画多大（点击区另算，44）。
  private static let chevron: CGFloat = 18

  // ---------------------------------------------------------------- 搜索

  private var searchBar: some View {
    HStack(spacing: Space.xs) {
      // 品种代号全是 ASCII，框里锁英文键盘（见 `SymbolSearchField`）。
      SymbolSearchField(text: $model.query, focused: $searchFocused, id: "symbols.query")

      Button {
        model.query = ""
      } label: {
        Text("清空")
          .font(TypeScale.bodyEmph)
          .foregroundStyle(Color(hex: seed.accent))
          .padding(.horizontal, Space.s)
          .hitTarget()
      }
      .buttonStyle(.plain)
      .padding(.trailing, -Space.s)
    }
    .pageHorizontalInset()
    .padding(.vertical, Space.s)
  }

  private func openFilter(_ kind: FilterSelection) {
    searchFocused = false
    filterTask?.cancel()
    filterTask = Task { @MainActor in
      do { try await Task.sleep(for: .milliseconds(250)) } catch { return }
      filterSelection = kind
    }
  }

  private var filters: some View {
    // 和搜索页的历史词同一种小块（UI 审查：筛选小块原有四套）。选了具体的市场 / 板块
    // 就按选中画，一眼看得出这张表现在被筛过。
    HStack(spacing: Space.s) {
      SymbolChip(title: MarketSector.title(model.marketFilter),
                 selected: model.marketFilter != "all", menu: true) { openFilter(.market) }
        .accessibilityIdentifier("symbols.market")
      SymbolChip(title: model.sectorFilter.map(MarketSector.title) ?? "全部板块",
                 selected: model.sectorFilter != nil, menu: true) { openFilter(.sector) }
        .disabled(model.sectors.isEmpty)
        .accessibilityIdentifier("symbols.sector")
      Spacer(minLength: 0)
    }
    .pageHorizontalInset()
    .overlay(alignment: .bottom) { Divider().overlay(Color(hex: seed.line)) }
  }

  // ---------------------------------------------------------------- 列表

  @ViewBuilder
  private var list: some View {
    if model.isEmpty {
      // §10.5：空结果一行小字，不放插画。
      VStack {
        Text(model.emptyText)
          .font(TypeScale.caption)
          .foregroundStyle(Color(hex: seed.ink3))
          .pageHorizontalInset()
          .padding(.vertical, Space.xl)
        Spacer(minLength: 0)
      }
      .frame(maxWidth: .infinity, alignment: .leading)
    } else {
      List {
        ForEach(model.sections) { section in
          Section {
            ForEach(section.rows) { row in
              rowView(row, in: section)
            }
            if let note = section.moreNote {
              Text(note)
                .font(TypeScale.caption)
                .foregroundStyle(Color(hex: seed.ink3))
                .lineSpacing(Space.xs)
                .frame(maxWidth: .infinity, alignment: .leading)
                .pageHorizontalInset()
                .padding(.top, Space.s)
                .padding(.bottom, Space.xxs)
                .listRowInsets(EdgeInsets())
                .listRowBackground(Color(hex: seed.app))
                .listRowSeparator(.hidden)
            }
          } header: {
            // 吸顶的分组标题自己垫一层页面底色、铺满整宽：`.plain` 表的吸顶头默认是
            // 系统的半透明材质，滚上去的行从它底下透出来，在青苔 / 陶土底上是一条色带（接缝）。
            Text(section.title)
              .font(TypeScale.caption2Emph)
              .kerning(1)
              .textCase(nil)
              .foregroundStyle(Color(hex: seed.ink3))
              .frame(maxWidth: .infinity, alignment: .leading)
              .pageHorizontalInset()
              .padding(.top, Space.l)
              .padding(.bottom, Space.s)
              .background(Color(hex: seed.app))
              .listRowInsets(EdgeInsets())
          }
        }
      }
      .listStyle(.plain)
      // 同搜索页：滚动条会吃掉行尾那颗星的点击。
      .scrollIndicators(.hidden)
      .scrollContentBackground(.hidden)
      .scrollDismissesKeyboard(.interactively)
      .environment(\.defaultMinListRowHeight, 0)
      // `.plain` 表自带一截顶部留白，叠上分组标题自己的 `Space.l`，筛选条下面空出一大块；
      // 间距只由标题那一个令牌管。
      .contentMargins(.top, 0, for: .scrollContent)
      .listSectionSpacing(0)
    }
  }

  @ViewBuilder
  private func rowView(_ row: SymbolRow, in section: SymbolSection) -> some View {
    let favorite = section.kind == .favorites
    // 自选：左滑「取消自选」+ 长按拖动排序（§10.5）。
    //
    // 这一颗原来是系统 `.swipeActions` 里的 destructive 按钮，没给 `.tint`：
    // 底是系统红 `#FF3B30`（整页上唯一不跟皮肤走的颜色）、字被 UIKit 强行画成白，
    // 3.55:1。换成自己画的那一份（`SwipeToDelete`），底走 `theme.danger`、
    // 字走 `theme.badgeInk`。不是自选段的行照旧划不出任何东西——那时候
    // `trailing` 是空数组，手势什么都不做，砖也不建出来。
    //
    // 行的内缩从 `listRowInsets` 挪进内容里（`SymbolRowView` 自己按页边距收）：砖画在行的
    // `.background` 上，行要是被 `listRowInsets` 往里收，砖就够不着屏幕右沿了
    // （`DrawingSheet` 那一处同样的处理）。分隔线两头因此按页边距钉：
    // 左从文字起点（页边距 + 徽章 + 间距），右到页边距。
    SwipeToDelete(
      id: row.id, open: $openSwipe, brick: .flush,
      trailing: favorite
        ? [.delete(theme, title: "取消自选", id: SwipeDeleteIDs.favoritesUnstar) {
            Haptics.warning()
            model.removeFavorite(row.id)
          }]
        : []
    ) { swipe in
      SymbolRowView(row: row,
                    isFavorite: model.isFavorite(row.id),
                    theme: rowTheme,
                    onStar: { Haptics.tap(); model.toggleFavorite(row.id) },
                    onPick: {
                      if swipe.isOpen { swipe.close(); return }
                      searchFocused = false
                      Haptics.press()
                      if let onSelect { onSelect(row.info) } else { model.pick(row.info) }
                    })
      // 拖动排序挂在**砖的里面**，不在外面。`.draggable` 装的是一个 UIKit 的
      // `UIDragInteraction`：它在表里起手很快，压在左划手势的外层时会把那一趟横拖
      // 整个认走，砖一次都划不出来（2026-09-22 在 iPhone 15 上拍到过，三个起手点全灭，
      // 最后那一下还被当成点行、把整页关掉了）。挪到里层之后，横拖先归 `SwipeToDelete`
      // 那道横纵锁，长按不动那一路照旧交给拖拽，两件事各走各的。
      .modifier(FavoriteDragModifier(enabled: favorite, symbol: row.id, dragging: $dragging) { from, onto in
        Haptics.press()
        model.moveFavorite(from, onto: onto)
      })
    }
    .onAppear { onVisible?(row.id); onRowVisibility?(row.id, true) }
    .onDisappear { onRowVisibility?(row.id, false) }
    .listRowInsets(EdgeInsets())
    .listRowBackground(Color(hex: seed.app))
    .listRowSeparatorTint(Color(hex: colors.hair))
    .alignmentGuide(.listRowSeparatorLeading) { d in Inset.page(d.width) + SymbolRowView.textLead }
    .alignmentGuide(.listRowSeparatorTrailing) { d in d.width - Inset.page(d.width) }
  }

}

// ============================================================ 拖动排序
//
// 自选长按拖动排序（§10.5）。不进编辑态——编辑态会冒出一排减号圆圈，
// 和原型的样子对不上——用 `draggable` + `dropDestination`：长按起拖，
// 落在哪一行就插到哪一行。

private struct FavoriteDragModifier: ViewModifier {
  let enabled: Bool
  let symbol: String
  @Binding var dragging: String?
  let onDrop: (String, String) -> Void

  func body(content: Content) -> some View {
    if enabled {
      content
        .opacity(dragging == symbol ? 0.4 : 1)
        .draggable(symbol) {
          Text(InstrumentID(symbol).display).font(TypeScale.footnoteEmph).padding(Space.s)
        }
        .dropDestination(for: String.self) { items, _ in
          guard let from = items.first, from != symbol else { return false }
          onDrop(from, symbol)
          dragging = nil
          return true
        } isTargeted: { over in
          if over { dragging = symbol } else if dragging == symbol { dragging = nil }
        }
    } else {
      content
    }
  }
}

// ============================================================ 两个图形
//
// 逐点照抄原型的 SVG path，免得再引一套图标。

/// 返回箭头：`M11 3.5 5.5 9l5.5 5.5`（18×18）。
private struct Chevron: Shape {
  func path(in r: CGRect) -> Path {
    let k = min(r.width, r.height) / 18
    func p(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: r.minX + x * k, y: r.minY + y * k) }
    var path = Path()
    path.move(to: p(11, 3.5))
    path.addLine(to: p(5.5, 9))
    path.addLine(to: p(11, 14.5))
    return path
  }
}

/// 五角星：`M9 2.2l2 4.2 4.6.6-3.4 3.2.9 4.6L9 12.6 4.9 14.8l.9-4.6L2.4 7l4.6-.6z`（18×18）。
struct StarShape: Shape {
  private static let pts: [(CGFloat, CGFloat)] = [
    (9, 2.2), (11, 6.4), (15.6, 7), (12.2, 10.2), (13.1, 14.8),
    (9, 12.6), (4.9, 14.8), (5.8, 10.2), (2.4, 7), (7, 6.4),
  ]

  func path(in r: CGRect) -> Path {
    let k = min(r.width, r.height) / 18
    let dx = r.minX + (r.width - 18 * k) / 2
    let dy = r.minY + (r.height - 18 * k) / 2
    var path = Path()
    for (i, pt) in Self.pts.enumerated() {
      let p = CGPoint(x: dx + pt.0 * k, y: dy + pt.1 * k)
      if i == 0 { path.move(to: p) } else { path.addLine(to: p) }
    }
    path.closeSubpath()
    return path
  }
}

#if DEBUG
// ============================================================ 最小宿主 + 预览

/// 自包含的宿主：自己造 model、自己接返回。接进主界面之前用它跑预览 / 单页调试。
struct SymbolPickerHost: View {
  @State private var model: SymbolPickerModel
  @State private var picked: String?
  private let redUp: Bool

  init(catalog: [SymbolInfo] = SymbolFixtures.catalog,
       tickers: [Ticker] = SymbolFixtures.tickers,
       prefs: SymbolPrefs = SymbolPrefs(favorites: ["ETHUSDT", "SOLUSDT", "BTCUSDT"],
                                        recents: ["DOGEUSDT", "AVAXUSDT", "BTCUSDT"]),
       redUp: Bool = false) {
    // 预览不碰真的 UserDefaults，落在一个内存假货上。
    let storage = MemoryPrefsStorage()
    let store = SymbolPrefsStore(storage: storage, key: "preview")
    store.save(prefs)
    let quotes = QuoteBook.preview(tickers)
    let m = SymbolPickerModel(catalog: catalog, tickers: Array(quotes.raw.values), store: store)
    _model = State(initialValue: m)
    self.redUp = redUp
  }

  var body: some View {
    SymbolPickerView(model: model, redUp: redUp) { picked = nil }
      .onAppear { model.onPick = { picked = $0.symbol } }
      .overlay(alignment: .bottom) {
        if let picked {
          Text("选了 \(picked)")
            .font(.scaled(12))
            .padding(.horizontal, 12).padding(.vertical, 7)
            .background(Capsule().fill(Color(hex: Palette.lightSeed.ink).opacity(0.8)))
            .foregroundStyle(.white)
            .padding(.bottom, 24)
        }
      }
  }
}

#Preview("品种页 · 浅") {
  SymbolPickerHost()
}

#Preview("品种页 · 深") {
  SymbolPickerHost().preferredColorScheme(.dark)
}

#Preview("品种页 · 红涨绿跌") {
  SymbolPickerHost(redUp: true)
}

#Preview("品种页 · 空自选") {
  SymbolPickerHost(prefs: SymbolPrefs())
}
#endif
