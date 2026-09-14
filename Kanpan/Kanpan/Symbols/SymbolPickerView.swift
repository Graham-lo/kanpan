import SwiftUI
import KanpanCore
#if canImport(UIKit)
import UIKit
#endif

// ============================================================ 品种整页
//
// §9.3 / §10.5 / A5.7–A5.9。长相逐条对原型 `#pgSymbol`：
//   .sheeth  13/16/10 内边距，标题 600 15，右边一行小字 400 11 ink3
//   .search  8/12/10，输入框 raised2 底、line 描边、圆角 9、字 14
//   .row     11/16，名 500 14、小字 400 11 ink3、数 mono 500 13.5、涨跌 mono 500 11
//   .groupt  14/16/6，500 11，字距 .09em，ink3
//   .note    10/16/2，400 11.5，ink3
//   .star    ink3，选中 amber
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

  @Environment(\.colorScheme) private var scheme
  @FocusState private var searchFocused: Bool
  @State private var dragging: String?

  private var seed: PaletteSeed { scheme == .dark ? Palette.darkSeed : Palette.lightSeed }
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
      list
    }
    .background(Color(hex: seed.app))
    .task {
      model.setSectionsActive(true)
      await model.appear()
      searchFocused = true
    }
    .onDisappear {
      searchFocused = false
      model.setSectionsActive(false)
      model.disappear()
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

      Text("品种").font(.system(size: 15, weight: .semibold)).foregroundStyle(Color(hex: seed.ink))
      Text(model.countText).font(.system(size: 11)).foregroundStyle(Color(hex: seed.ink3))
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
        .textInputAutocapitalization(.characters)
        .autocorrectionDisabled()
        .submitLabel(.search)
        .focused($searchFocused)
        .padding(.vertical, 9)
        .padding(.horizontal, 11)
        .background(RoundedRectangle(cornerRadius: 9).fill(Color(hex: seed.raised2)))
        .overlay(RoundedRectangle(cornerRadius: 9).stroke(
          Color(hex: searchFocused ? colors.amberLine : seed.line),
          lineWidth: searchFocused ? 2 : 1))
        .accessibilityIdentifier("symbols.query")

      Button("清空") {
        model.query = ""
      }
      .font(.system(size: 14, weight: .medium))
      .foregroundStyle(Color(hex: seed.amber))
      .buttonStyle(.plain)
      .padding(6)
    }
    .padding(.leading, 12)
    .padding(.trailing, 6)
    .padding(.top, 8)
    .padding(.bottom, 10)
    .overlay(alignment: .bottom) { Divider().overlay(Color(hex: seed.line)) }
  }

  // ---------------------------------------------------------------- 列表

  @ViewBuilder
  private var list: some View {
    if model.isEmpty {
      // §10.5：空结果一行小字，不放插画。
      VStack {
        Text(model.emptyText)
          .font(.system(size: 12.5))
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
                .font(.system(size: 11.5))
                .foregroundStyle(Color(hex: seed.ink3))
                .lineSpacing(4)
                .listRowInsets(EdgeInsets(top: 10, leading: 16, bottom: 2, trailing: 16))
                .listRowBackground(Color(hex: seed.app))
                .listRowSeparator(.hidden)
            }
          } header: {
            Text(section.title)
              .font(.system(size: 11, weight: .medium))
              .kerning(1)
              .textCase(nil)
              .foregroundStyle(Color(hex: seed.ink3))
              .listRowInsets(EdgeInsets(top: 14, leading: 16, bottom: 6, trailing: 16))
          }
        }
      }
      .listStyle(.plain)
      .scrollContentBackground(.hidden)
      .scrollDismissesKeyboard(.interactively)
      .environment(\.defaultMinListRowHeight, 0)
    }
  }

  @ViewBuilder
  private func rowView(_ row: SymbolRow, in section: SymbolSection) -> some View {
    let favorite = section.kind == .favorites
    SymbolRowView(row: row,
                  isFavorite: model.isFavorite(row.id),
                  seed: seed,
                  colors: colors,
                  nameSize: nameSize, metaSize: metaSize,
                  priceSize: priceSize, pctSize: pctSize) {
      haptic(.light)
      model.toggleFavorite(row.id)
    }
    .contentShape(Rectangle())
    .onTapGesture {
      searchFocused = false
      haptic(.medium)
      if let onSelect { onSelect(row.info) } else { model.pick(row.info) }
    }
    .accessibilityIdentifier("symbols.row.\(row.id)")
    .onAppear { onVisible?(row.id); onRowVisibility?(row.id, true) }
    .onDisappear { onRowVisibility?(row.id, false) }
    .listRowInsets(EdgeInsets(top: 11, leading: 16, bottom: 11, trailing: 16))
    .listRowBackground(Color(hex: seed.app))
    .listRowSeparatorTint(Color(hex: colors.hair))
    // 自选：左滑删除 + 长按拖动排序（§10.5）
    .swipeActions(edge: .trailing, allowsFullSwipe: true) {
      if favorite {
        Button(role: .destructive) {
          haptic(.medium)
          model.removeFavorite(row.id)
        } label: { Text("移出自选") }
      }
    }
    .modifier(FavoriteDragModifier(enabled: favorite, symbol: row.id, dragging: $dragging) { from, onto in
      haptic(.medium)
      model.moveFavorite(from, onto: onto)
    })
  }

  private func haptic(_ style: HapticStyle) {
    #if canImport(UIKit) && !targetEnvironment(macCatalyst)
    let generator: UIImpactFeedbackGenerator
    switch style {
    case .light: generator = UIImpactFeedbackGenerator(style: .light)
    case .medium: generator = UIImpactFeedbackGenerator(style: .medium)
    }
    generator.impactOccurred()
    #endif
  }

  private enum HapticStyle { case light, medium }
}

// ============================================================ 一行

private struct SymbolRowView: View {
  let row: SymbolRow
  let isFavorite: Bool
  let seed: PaletteSeed
  let colors: ChartColors
  let nameSize: CGFloat
  let metaSize: CGFloat
  let priceSize: CGFloat
  let pctSize: CGFloat
  let onStar: () -> Void

  var body: some View {
    HStack(spacing: 10) {
      VStack(alignment: .leading, spacing: 2) {
        name
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
      Button(action: onStar) {
        StarShape()
          .fill(isFavorite ? Color(hex: seed.amber) : .clear)
          .overlay(StarShape().stroke(
            Color(hex: isFavorite ? seed.amber : seed.ink3),
            style: StrokeStyle(lineWidth: 1.5, lineJoin: .round)))
          .frame(width: 15, height: 15)
          .padding(4)
          .animation(.easeOut(duration: 0.2), value: isFavorite)
      }
      .buttonStyle(.plain)
      .accessibilityLabel(isFavorite ? "移出自选" : "加入自选")
    }
  }

  /// `BTC` + 灰的 ` / USDT`；搜索命中的片段用琥珀标出来（§10.5 匹配片段高亮）。
  private var name: Text {
    let base = row.info.base
    let quote = row.info.quote
    var out = Text("")
    for seg in SymbolQuery.split(base, highlight: row.match.highlight, offset: 0) {
      out = out + Text(seg.text)
        .font(.system(size: nameSize, weight: .medium))
        .foregroundStyle(Color(hex: seg.hit ? seed.amber : seed.ink))
    }
    out = out + Text(" / ").font(.system(size: nameSize)).foregroundStyle(Color(hex: seed.ink3))
    for seg in SymbolQuery.split(quote, highlight: row.match.highlight, offset: base.count) {
      out = out + Text(seg.text)
        .font(.system(size: nameSize))
        .foregroundStyle(Color(hex: seg.hit ? seed.amber : seed.ink3))
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
          Text(symbol).font(.system(size: 13, weight: .medium)).padding(6)
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
    let m = SymbolPickerModel(catalog: catalog, tickers: tickers, store: store,
                              feed: StaticTickerFeed(tickers))
    _model = State(initialValue: m)
    self.redUp = redUp
  }

  var body: some View {
    SymbolPickerView(model: model, redUp: redUp) { picked = nil }
      .onAppear { model.onPick = { picked = $0.symbol } }
      .overlay(alignment: .bottom) {
        if let picked {
          Text("选了 \(picked)")
            .font(.system(size: 12))
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
