import SwiftUI
import KanpanCore
import KanpanNetwork
import UIKit

// ============================================================ 品种整页
//
// §9.3 / §10.5 / A5.7–A5.9。长相逐条对原型 `#pgSymbol`：
//   .sheeth  13/16/10 内边距，标题 600 15，右边一行小字 400 11 ink3
//   .search  8/12/10，输入框 raised2 底、line 描边、圆角 9、字 14
//   .row     11/16，名 500 14、小字 400 11 ink3、数 mono 500 13.5、涨跌 mono 500 11
//   .groupt  14/16/6，500 11，字距 .09em，ink3
//   .note    10/16/2，400 11.5，ink3
//   .star    ink3，选中强调色（`seed.accent`，随皮肤走，不是画在图上那支暖色）
//
// 页面进入自动聚焦搜索框弹键盘（§10.5「这是来搜的」），返回时收键盘。

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

  @ScaledMetric(relativeTo: .body) private var nameSize: CGFloat = 14
  @ScaledMetric(relativeTo: .caption) private var metaSize: CGFloat = 11
  @ScaledMetric(relativeTo: .body) private var priceSize: CGFloat = 13.5
  @ScaledMetric(relativeTo: .caption) private var pctSize: CGFloat = 11
  @ScaledMetric(relativeTo: .body) private var fieldSize: CGFloat = 14

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
    HStack(spacing: 8) {
      Button {
        searchFocused = false
        onClose?()
      } label: {
        Chevron()
          .stroke(Color(hex: seed.ink2), style: StrokeStyle(lineWidth: 1.7, lineCap: .round, lineJoin: .round))
          .frame(width: 18, height: 18)
          .frame(width: 32, height: 32)
          // 描边形状的按钮，点击区默认只有那条 1.7pt 的线本身——32×32 里绝大部分是空的，
          // 手指落在两笔之间就没反应（A8.4 在 5 台机器上实测到）。补一块矩形点击区，
          // 画面一个像素都不动。
          .contentShape(Rectangle())
      }
      .buttonStyle(.plain)
      .accessibilityLabel("返回")
      .accessibilityIdentifier("symbols.back")

      Text("品种").font(.scaled(15, .semibold)).foregroundStyle(Color(hex: seed.ink))
      Text(model.countText).font(.scaled(11)).foregroundStyle(Color(hex: seed.ink3))
      Spacer(minLength: 0)
    }
    .padding(.leading, 16 - 7)   // iconbtn 自带 7pt 视觉留白，对齐到 16
    .padding(.trailing, 16)
    .padding(.top, 13)
    .padding(.bottom, 10)
    .overlay(alignment: .bottom) { Divider().overlay(Color(hex: seed.line)) }
  }

  // ---------------------------------------------------------------- 搜索

  private var searchBar: some View {
    HStack(spacing: 8) {
      TextField("", text: $model.query, prompt:
        Text("搜 BTC、ETH、SOL…").foregroundStyle(Color(hex: seed.ink3)))
        .font(.system(size: fieldSize))
        .foregroundStyle(Color(hex: seed.ink))
        // 品种代号全是 ASCII，锁住输入法语言，别让上次用中文输入法的人在这儿先切一次。
        .keyboardType(.asciiCapable)
        .textInputAutocapitalization(.characters)
        .autocorrectionDisabled()
        .submitLabel(.search)
        .focused($searchFocused)
        .padding(.vertical, 9)
        .padding(.horizontal, 11)
        .background(RoundedRectangle(cornerRadius: 9).fill(Color(hex: seed.raised2)))
        .overlay(RoundedRectangle(cornerRadius: 9).stroke(
          searchFocused ? theme.amberLine : Color(hex: seed.line),
          lineWidth: searchFocused ? 2 : 1))
        .accessibilityIdentifier("symbols.query")

      Button("清空") {
        model.query = ""
      }
      .font(.scaled(14, .medium))
      .foregroundStyle(Color(hex: seed.accent))
      .buttonStyle(.plain)
      .padding(6)
    }
    .padding(.leading, 12)
    .padding(.trailing, 6)
    .padding(.top, 8)
    .padding(.bottom, 10)
    .overlay(alignment: .bottom) { Divider().overlay(Color(hex: seed.line)) }
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
    HStack(spacing: 18) {
      Button { openFilter(.market) } label: { Label(MarketSector.title(model.marketFilter), systemImage: "chevron.down") }
        .accessibilityIdentifier("symbols.market")
      Button { openFilter(.sector) } label: {
        Label(model.sectorFilter.map(MarketSector.title) ?? "全部板块", systemImage: "chevron.down")
      }.disabled(model.sectors.isEmpty).accessibilityIdentifier("symbols.sector")
      Spacer(minLength: 0)
    }.font(.scaled(12, .medium)).foregroundStyle(theme.amber)
      .padding(.horizontal, 16).padding(.bottom, 10)
  }

  // ---------------------------------------------------------------- 列表

  @ViewBuilder
  private var list: some View {
    if model.isEmpty {
      // §10.5：空结果一行小字，不放插画。
      VStack {
        Text(model.emptyText)
          .font(.scaled(12.5))
          .foregroundStyle(Color(hex: seed.ink3))
          .padding(.horizontal, 16)
          .padding(.vertical, 22)
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
                .font(.scaled(11.5))
                .foregroundStyle(Color(hex: seed.ink3))
                .lineSpacing(4)
                .listRowInsets(EdgeInsets(top: 10, leading: 16, bottom: 2, trailing: 16))
                .listRowBackground(Color(hex: seed.app))
                .listRowSeparator(.hidden)
            }
          } header: {
            Text(section.title)
              .font(.scaled(11, .medium))
              .kerning(1)
              .textCase(nil)
              .foregroundStyle(Color(hex: seed.ink3))
              .listRowInsets(EdgeInsets(top: 14, leading: 16, bottom: 6, trailing: 16))
          }
        }
      }
      .listStyle(.plain)
      // 同搜索页：滚动条会吃掉行尾那颗星的点击。
      .scrollIndicators(.hidden)
      .scrollContentBackground(.hidden)
      .scrollDismissesKeyboard(.interactively)
      .environment(\.defaultMinListRowHeight, 0)
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
    // 行的内缩从 `listRowInsets` 挪进内容里：砖画在行的 `.background` 上，
    // 行要是被 `listRowInsets` 往里收 16pt，砖就够不着屏幕右沿了
    // （`DrawingSheet` 那一处同样的处理）。挪完分隔线的两头会跟着跑，
    // 所以按挪之前量到的位置钉死：左 59pt（16 内缩 + 33 徽章 + 10 间距）、
    // 右 16pt，也就是 iPhone 15 上那条 x 177…1131 像素的发丝线。
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
                    seed: seed,
                    colors: colors,
                    nameSize: nameSize, metaSize: metaSize,
                    priceSize: priceSize, pctSize: pctSize,
                    onStar: { Haptics.tap(); model.toggleFavorite(row.id) },
                    onPick: {
                      if swipe.isOpen { swipe.close(); return }
                      searchFocused = false
                      Haptics.press()
                      if let onSelect { onSelect(row.info) } else { model.pick(row.info) }
                    })
      .padding(EdgeInsets(top: 11, leading: 16, bottom: 11, trailing: 16))
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
    .alignmentGuide(.listRowSeparatorLeading) { _ in 59 }
    .alignmentGuide(.listRowSeparatorTrailing) { d in d.width - 16 }
  }

}

// ============================================================ 一行

struct SymbolRowView: View {
  let row: SymbolRow
  let isFavorite: Bool
  let seed: PaletteSeed
  let colors: ChartColors
  let nameSize: CGFloat
  let metaSize: CGFloat
  let priceSize: CGFloat
  let pctSize: CGFloat
  let onStar: () -> Void
  let onPick: () -> Void

  // 行和星都**不是 `Button`**，是两块 `contentShape` 加 `onTapGesture`，
  // 无障碍身份靠 `.isButton` 补回去（自选分类页那一行就是这么写的，见
  // `FavoritesView.row(_:first:)`）。
  //
  // 这不是风格问题：`.buttonStyle(.plain)` 的 `Button` 在 `List` 的行里
  // 认的是「按下—抬手」，横着拖过去一百二十点它照样当成点了一下，而且它把
  // 这一趟触摸整个占住，外层 `SwipeToDelete` 那道 `simultaneousGesture`
  // 一次 `onChanged` 都收不到。2026-09-22 在 iPhone 15 上六次起手全灭：
  // 起手压在星上的那一下把 BTCUSDT 取消了自选，压在行上的那几下把整页关掉
  // 换了品种，砖一次都没露头。`TapGesture` 则在手指挪过点击容差时自己作废，
  // 横拖就干净地落给左划。
  var body: some View {
    HStack(spacing: 10) {
      HStack(spacing: 10) {
        // 这一页原先一个徽章都没有——搜索结果十几行全靠代号分辨，和自选页对不上。
        // 事实分类直接从 `row.info` 算，比让徽章自己去猜准。
        CoinBadge(base: row.info.base, asset: SymbolClassifier.classify(row.info).asset, size: 33)
        VStack(alignment: .leading, spacing: 2) {
          HStack(alignment: .firstTextBaseline, spacing: 5) {
            name
            if NewListingMark.shows(row.info) {
              NewListingMark(symbol: row.id, accent: Color(hex: seed.accent))
            }
            // 别家交易所的品种在名字右边标一个灰色小字（默认那一家不标）——
            // 两家所都有 BTC，搜出来并排时靠它分。
            if let tag = VenueRegistry.descriptor(forSymbol: row.id).searchTag {
              Text(tag)
                .font(.system(size: metaSize))
                .foregroundStyle(Color(hex: seed.ink3))
                .accessibilityIdentifier("symbols.venue.\(row.id)")
            }
          }
          Text(row.meta)
            .font(.system(size: metaSize))
            .foregroundStyle(Color(hex: seed.ink3))
        }
        Spacer(minLength: 0)
        VStack(alignment: .trailing, spacing: 0) {
          Text(row.priceText)
            .font(.system(size: priceSize, weight: .medium, design: .monospaced))
            .monospacedDigit()
            .foregroundStyle(Color(hex: seed.ink))
          Text(row.changeText)
            .font(.system(size: pctSize, weight: .medium, design: .monospaced))
            .monospacedDigit()
            .foregroundStyle(Color(hex: row.ticker?.changePercent.isFinite == true ? (row.isUp ? colors.up : colors.down) : seed.ink3))
        }
      }
      .contentShape(Rectangle())
      .onTapGesture(perform: onPick)
      .accessibilityElement(children: .contain)
      .accessibilityAddTraits(.isButton)
      .accessibilityIdentifier("symbols.row.\(row.id)")
      .accessibilityAction(.default, onPick)
      StarShape()
        .fill(isFavorite ? Color(hex: seed.accent) : .clear)
        .overlay(StarShape().stroke(
          Color(hex: isFavorite ? seed.accent : seed.ink3),
          style: StrokeStyle(lineWidth: 1.5, lineJoin: .round)))
        .frame(width: 15, height: 15)
        // 星画得小是视觉上的克制，但感应区不能跟着小：`StarShape` 那个带凹口的
        // 12×12 星本来就没多少面积，旁边那块铺满整行的感应区又贴着它，
        // 点在星的正中都会被行接走（iPad Pro 11" 上必现：点星变成开图表）。
        // 所以补一块矩形感应区，并把它撑到 35pt——手指按得着，星本身还是 15pt。
        .padding(10)
        .contentShape(Rectangle())
        .animation(.easeOut(duration: 0.2), value: isFavorite)
        .onTapGesture(perform: onStar)
        .accessibilityElement()
        .accessibilityAddTraits(.isButton)
        .accessibilityLabel(isFavorite ? "取消自选" : "加入自选")
        .accessibilityIdentifier("symbols.star.\(row.id)")
        .accessibilityAction(.default, onStar)
    }
  }

  /// `BTC` + 灰的 ` / USDT`；搜索命中的片段用琥珀标出来（§10.5 匹配片段高亮）。
  private var name: Text {
    let base = row.info.base
    let quote = row.info.quote
    // `Text + Text` iOS 26 起废弃了，改用 `Text` 插值拼，逐段的字体/颜色照样保留。
    var out = Text("")
    for seg in SymbolQuery.split(base, highlight: row.match.highlight, offset: 0) {
      let piece = Text(seg.text)
        .font(.system(size: nameSize, weight: .medium))
        .foregroundStyle(Color(hex: seg.hit ? seed.accent : seed.ink))
      out = Text("\(out)\(piece)")
    }
    let slash = Text(" / ").font(.system(size: nameSize)).foregroundStyle(Color(hex: seed.ink3))
    out = Text("\(out)\(slash)")
    for seg in SymbolQuery.split(quote, highlight: row.match.highlight, offset: base.count) {
      let piece = Text(seg.text)
        .font(.system(size: nameSize))
        .foregroundStyle(Color(hex: seg.hit ? seed.accent : seed.ink3))
      out = Text("\(out)\(piece)")
    }
    return out
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
          Text(InstrumentID(symbol).display).font(.scaled(13, .medium)).padding(6)
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
