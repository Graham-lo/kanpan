import SwiftUI
import KanpanCore
import KanpanData

/// Claude自选原型的原生SwiftUI实现；所有数字来自真实行情，不加载WebView。
struct FavoritesView: View {
  @Bindable var model: SymbolPickerModel
  var redUp: Bool
  var basisTitle: String
  var updatedAt: Date?
  var feedStatus: FeedStatus
  var feedDiagnostics: String? = nil
  var onClose: () -> Void
  var onVisible: (String) -> Void
  var onRowVisibility: (String, Bool) -> Void
  var onHistoryVisibility: (String, Bool) -> Void
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @Environment(\.panelTheme) private var theme
  @State private var adding = false
  @State private var more = false
  @State private var afterMore: (() -> Void)?
  @State private var moreTask: Task<Void, Never>?
  @State private var editingName = false
  @State private var renamedID: String?
  @State private var name = ""
  @State private var editing = false
  @State private var editQuotes: [String: Ticker] = [:]
  @State private var selection = Set<String>()
  @State private var expanded = Set<String>()
  @State private var sort = "custom"
  @State private var ascending = false
  @State private var amount = false
  @State private var moving: MoveRequest?
  private struct MoveRequest: Identifiable { let id = UUID(); let symbols: [String] }
  private var selected: String? { model.prefs.selectedGroupID ?? model.prefs.groups.first?.id }
  private var groupID: String? { selected }
  private var symbols: [String] {
    let source = model.prefs.favorites(in: groupID)
    var rows = source
    if !editing, sort != "custom" {
      rows.sort { a, b in
        if sort == "name" { return ascending ? a < b : a > b }
        let x = sortValue(a)
        let y = sortValue(b)
        guard let x, x.isFinite else { return false }
        guard let y, y.isFinite else { return true }
        if x == y { return a < b }
        return ascending ? x < y : x > y
      }
    }
    return rows
  }

  var body: some View {
    NavigationStack {
      VStack(spacing: 0) {
        FavoritesHeader(prefs: model.prefs, editing: editing, more: more, theme: theme, content: groupBar).equatable()
        overview
        sortBar
        if symbols.isEmpty {
          ContentUnavailableView {
            Label("暂无自选", systemImage: "star")
          } description: {
            Text("添加常看的品种")
          } actions: { Button("添加品种") { adding = true } }
        } else {
          List {
            ForEach(symbols, id: \.self) { symbol in
              VStack(spacing: 0) {
                row(symbol)
                if expanded.contains(symbol), !editing { details(symbol) }
              }
              .listRowInsets(EdgeInsets(top: 0, leading: 0, bottom: 0, trailing: 0))
              .listRowBackground(theme.app).listRowSeparatorTint(theme.hair)
              .onAppear { onVisible(symbol); onRowVisibility(symbol, true) }
              .onDisappear { onRowVisibility(symbol, false); onHistoryVisibility(symbol, false) }
              .swipeActions(edge: .leading, allowsFullSwipe: false) {
                Button("删除自选", role: .destructive) { model.removeFavorite(symbol) }
              }
              .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                Button("移到分类") { moving = MoveRequest(symbols: [symbol]) }.tint(theme.amber)
                Button("删除", role: .destructive) { model.removeFavorite(symbol) }
              }

            }
            .onMove { source, target in
              // 编辑时恢复自定义顺序，筛选时不允许把可见索引套到完整列表。
              model.moveVisible(symbols, from: source, to: target)
              sort = "custom"
            }
          }.listStyle(.plain).scrollContentBackground(.hidden)
        }
      }
      .background(theme.app)
      .toolbar(.hidden, for: .navigationBar)
      .safeAreaInset(edge: .bottom, spacing: 0) { if editing { editBar } }
    }
    .tint(theme.amber)
    .task { await model.appear() }
    .onDisappear {
      moreTask?.cancel()
      model.disappear()
      for symbol in expanded { onHistoryVisibility(symbol, false) }
    }
    .onChange(of: more) { _, shown in
      guard !shown, let action = afterMore else { return }
      afterMore = nil
      moreTask?.cancel()
      moreTask = Task { @MainActor in
        do { try await Task.sleep(for: .milliseconds(250)) } catch { return }
        action()
      }
    }
    .onChange(of: expanded) { old, next in
      for symbol in next.subtracting(old) { onHistoryVisibility(symbol, true) }
      for symbol in old.subtracting(next) { onHistoryVisibility(symbol, false) }
    }
    .onChange(of: model.tickers.isEmpty) { _, empty in
      if empty { editQuotes.removeAll(); editing = false; selection.removeAll() }
    }
    .alert(renamedID == nil ? "新建分类" : "重命名分类", isPresented: $editingName) {
      TextField("分类名称", text: $name)
      Button("取消", role: .cancel) { }
      Button("保存") {
        if let renamedID { model.renameGroup(renamedID, name: name) }
        else if let id = model.createGroup(name) { model.selectGroup(id) }
      }.disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
    }
    .sheet(isPresented: $adding) {
      SymbolPickerView(model: model, redUp: redUp, onClose: { adding = false }, onSelect: { info in
        model.addFavorite(info.symbol, info: info)
        if let group = model.prefs.groupForSymbol[info.symbol] { model.selectGroup(group) }
        adding = false
      }, onVisible: onVisible, onRowVisibility: onRowVisibility)
    }
    .sheet(item: $moving) { request in
      NavigationStack {
        List {
          ForEach(model.prefs.groups) { group in Button(group.name) { assign(request.symbols, to: group.id) } }
        }.scrollContentBackground(.hidden).background(theme.app)
          .navigationTitle("移到分类").navigationBarTitleDisplayMode(.inline)
          .toolbar { ToolbarItem(placement: .cancellationAction) { Button("取消") { moving = nil } } }
      }.presentationDetents([.medium, .large]).tint(theme.amber)
    }
  }

  /// Width follows native container/font metrics; extra folders live in the menu.
  private func tabWidth(_ group: FavoriteGroup) -> CGFloat {
    min(132, max(66, (group.name as NSString).size(withAttributes:
      [.font: UIFont.systemFont(ofSize: 17, weight: .semibold)]).width + 24))
  }

  private func visibleGroups(width: CGFloat) -> [FavoriteGroup] {
    var result: [FavoriteGroup] = []
    // 104 是右边「+」和「…」两个按钮，44 是左边新加的返回按钮。
    var remaining = max(0, width - 104 - 44)
    for group in model.prefs.groups {
      let required = tabWidth(group) + (result.isEmpty ? 0 : 4)
      guard remaining >= required else { break }
      result.append(group); remaining -= required
    }
    if let active = model.prefs.groups.first(where: { $0.id == selected }),
       !result.contains(where: { $0.id == active.id }) {
      while !result.isEmpty && remaining < tabWidth(active) + 4 {
        remaining += tabWidth(result.removeLast()) + 4
      }
      result.append(active)
    }
    return result
  }

  private func toggleEditing() {
    if editing { editing = false; editQuotes.removeAll() }
    else { editQuotes = model.tickers; editing = true }
    selection.removeAll(); expanded.removeAll()
  }

  private var groupBar: some View {
    GeometryReader { geometry in
      let visible = visibleGroups(width: geometry.size.width)
      HStack(spacing: 4) {
        // 自选是整屏盖上来的（`fullScreenCover`），没有导航栏也没有 tab 栏。
        // 原来唯一的出口埋在「…」弹层最后一行、红色的「删除当前分类」下面——
        // 实测新用户在这一页出不去。常驻一个返回按钮，放在所有人第一眼找出口的地方。
        Button(action: onClose) {
          HStack(spacing: 2) {
            Image(systemName: "chevron.left")
            Text("行情").font(.system(size: 15, weight: .medium))
          }
          .frame(height: 48).padding(.trailing, 4).contentShape(Rectangle())
        }
        .foregroundStyle(theme.amber)
        .accessibilityLabel("返回行情").accessibilityIdentifier("favorites.back")
        HStack(spacing: 4) {
          ForEach(visible) { group in
            chip(group.name, id: group.id, count: model.prefs.favorites(in: group.id).count)
              .frame(width: tabWidth(group))

          }
        }.accessibilityElement(children: .contain).accessibilityIdentifier("favorites.groups")
        Spacer(minLength: 0)
        Button { adding = true } label: { Image(systemName: "plus").frame(width: 44, height: 48) }
          .accessibilityLabel("添加品种").accessibilityIdentifier("favorites.add")
        Button { more = true } label: {
          Image(systemName: "ellipsis").frame(width: 44, height: 48).contentShape(Rectangle())
        }.accessibilityLabel("更多分类与管理").accessibilityIdentifier("favorites.more")
          .popover(isPresented: $more, arrowEdge: .top) {
            moreList(hidden: model.prefs.groups.filter { group in !visible.contains(where: { $0.id == group.id }) })
              .presentationCompactAdaptation(.popover)
          }
      }.font(.system(size: 19, weight: .medium)).padding(.horizontal, 8)
    }.frame(height: 58)
      .overlay(alignment: .bottom) { theme.line.frame(height: 0.5) }
  }

  private func runMore(_ action: @escaping () -> Void) {
    afterMore = action; more = false
  }

  private func moreRow(_ title: String, icon: String, id: String, destructive: Bool = false,
                       action: @escaping () -> Void) -> some View {
    Button { runMore(action) } label: {
      Label(title, systemImage: icon).frame(maxWidth: .infinity, minHeight: 46, alignment: .leading)
        .padding(.horizontal, 16).contentShape(Rectangle())
    }.buttonStyle(.plain).foregroundStyle(destructive ? Color(hex: Palette.chart(theme.seed, redUp: false).down) : theme.ink)
      .accessibilityIdentifier(id)
  }

  private func moreList(hidden: [FavoriteGroup]) -> some View {
    ScrollView {
      VStack(spacing: 0) {
        if !hidden.isEmpty {
          Text("更多分类").font(.system(size: 11)).foregroundStyle(theme.ink3)
            .frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, 16).padding(.vertical, 10)
          ForEach(hidden) { group in
            moreRow(group.name, icon: "folder", id: "favorites.group." + group.name) {
              model.selectGroup(group.id); selection.removeAll(); expanded.removeAll()
            }
          }
          theme.line.frame(height: 0.5).padding(.vertical, 6)
        }
        moreRow("新建分类", icon: "folder.badge.plus", id: "favorites.newGroup") {
          renamedID = nil; name = ""; editingName = true
        }
        moreRow(editing ? "完成编辑" : "编辑自选", icon: "pencil", id: "favorites.edit") { toggleEditing() }
        if let group = model.prefs.groups.first(where: { $0.id == selected }) {
          moreRow("重命名当前分类", icon: "square.and.pencil", id: "favorites.renameGroup") {
            renamedID = group.id; name = group.name; editingName = true
          }
          moreRow("删除当前分类", icon: "trash", id: "favorites.deleteGroup", destructive: true) { model.deleteGroup(group.id) }
        }
      }.padding(.vertical, 6)
    }.font(.system(size: 14)).frame(width: 260).frame(idealHeight: min(430, CGFloat(4 + hidden.count) * 46 + (hidden.isEmpty ? 18 : 61)), maxHeight: 430)
      .background(theme.app).presentationBackground(theme.app)
  }

  private var overview: some View {
    let values = symbols.compactMap { displayQuote($0)?.changePercent }.filter(\.isFinite)
    let up = values.filter { $0 >= 0 }.count, down = values.filter { $0 < 0 }.count
    return HStack(spacing: 8) {
      HStack(spacing: 1) {
        theme.up.frame(width: 54 * CGFloat(up) / CGFloat(max(1, up + down)))
        (values.isEmpty ? theme.ink3 : theme.down)
      }.frame(width: 54, height: 5).clipShape(Capsule())
      Text(values.isEmpty ? "涨 —" : "涨 \(up)").foregroundStyle(theme.up)
      Text(values.isEmpty ? "跌 —" : "跌 \(down)").foregroundStyle(theme.down)
      Spacer()
      TimelineView(.periodic(from: .now, by: 1)) { context in
        let live = feedStatus == .live && (updatedAt.map { context.date.timeIntervalSince($0) < 5 } ?? false)
        HStack(spacing: 5) {
          Circle().fill(live ? theme.up : theme.ink3).frame(width: 5, height: 5)
          Text((live ? "实时 · " : "") + basisTitle.replacingOccurrences(of: "涨跌幅", with: ""))
        }.foregroundStyle(theme.ink3)
      }
    }.font(.system(size: 11)).padding(.horizontal, 16).padding(.vertical, 8)
      .accessibilityElement(children: .contain)
      .accessibilityIdentifier("favorites.feed")
      .accessibilityValue(paletteDiagnostics)
  }

  private var paletteDiagnostics: String {
    guard let feedDiagnostics else { return "" }
    return feedDiagnostics + ";background=" + theme.chart.bg.value
  }

  private var sortBar: some View {
    HStack(spacing: 6) {
      sortButton("品种", key: "name")
      sortButton("成交额", key: "volume")
      Spacer()
      sortButton("价格", key: "price")
      Button { amount.toggle() } label: { Image(systemName: "arrow.left.arrow.right").font(.system(size: 10)) }
        .accessibilityLabel("切换涨跌额与涨跌幅")
      sortButton(amount ? "涨跌额" : basisTitle, key: "change")
    }.font(.system(size: 11)).foregroundStyle(theme.ink3)
      .padding(.horizontal, 16).padding(.vertical, 7)
      .overlay(alignment: .bottom) { theme.line.frame(height: 0.5) }
  }

  /// 编辑行布局不随每批WS报价重建；退出编辑立刻读取最新行情。
  private func displayQuote(_ symbol: String) -> Ticker? {
    editing ? editQuotes[symbol] : model.ticker(for: symbol)
  }

  private func sortValue(_ symbol: String) -> Double? {
    guard let ticker = displayQuote(symbol) else { return nil }
    if sort == "price" { return ticker.last }
    if sort == "volume" { return ticker.quoteVolume }
    if amount, ticker.changePercent > -100 {
      return ticker.last - ticker.last / (1 + ticker.changePercent / 100)
    }
    return ticker.changePercent
  }

  private func sortButton(_ title: String, key: String) -> some View {
    Button {
      if sort != key { sort = key; ascending = key == "name" }
      else if ascending == (key == "name") { ascending.toggle() } else { sort = "custom" }
    } label: {
      HStack(spacing: 3) { Text(title); Image(systemName: sort == key ? (ascending ? "arrowtriangle.up.fill" : "arrowtriangle.down.fill") : "arrow.up.arrow.down").font(.system(size: 7)) }
    }.foregroundStyle(sort == key ? theme.amber : theme.ink3).disabled(editing)
  }

  private func row(_ symbol: String) -> some View {
    let ticker = displayQuote(symbol)
    let base = model.info(for: symbol)?.base ?? String(symbol.dropLast(4))
    let index = symbol.utf8.reduce(0) { ($0 + Int($1)) % 6 }
    let tint = Color(hex: theme.chart.palette[index % theme.chart.palette.count])
    let amplitude = ticker?.amplitude24h
    let volumeText = ticker.map { $0.quoteVolume.isFinite ? fmtVol($0.quoteVolume) : "—" } ?? "—"
    let amplitudeText = amplitude.map { toFixed($0, 2) + "%" } ?? "—"
    let metadata = "额 " + volumeText + " · 振幅 " + amplitudeText
    return HStack(spacing: 10) {
      if editing {
        Button { if !selection.insert(symbol).inserted { selection.remove(symbol) } } label: {
          Image(systemName: selection.contains(symbol) ? "checkmark.circle.fill" : "circle").foregroundStyle(theme.amber)
        }.buttonStyle(.plain)
      }
      HStack(spacing: 10) {
          if !editing {
            Text(base == "BTC" ? "₿" : String(base.prefix(2)))
              .font(.system(size: 12, weight: .bold)).foregroundStyle(tint).frame(width: 30, height: 30)
              .background(tint.opacity(0.13), in: RoundedRectangle(cornerRadius: 9))
              .overlay(RoundedRectangle(cornerRadius: 9).stroke(tint.opacity(0.24), lineWidth: 0.5))
          }
          VStack(alignment: .leading, spacing: 3) {
            HStack(alignment: .firstTextBaseline, spacing: 1) {
              Text(base).font(.system(size: 15, weight: .semibold))
              Text("/" + quoteAsset(symbol)).font(.system(size: 11)).foregroundStyle(theme.ink3)
              Text("永续").font(.system(size: 9)).foregroundStyle(theme.ink3).padding(2)
                .overlay(RoundedRectangle(cornerRadius: 3).stroke(theme.line, lineWidth: 0.5)).padding(.leading, 3)
            }.lineLimit(1).minimumScaleFactor(0.7)
            Text(metadata)
              .font(.system(size: 10)).foregroundStyle(theme.ink3).lineLimit(1).minimumScaleFactor(0.75)
          }.frame(maxWidth: .infinity, alignment: .leading)
          quote(symbol)
      }.contentShape(Rectangle())
        .onTapGesture { selectOrOpen(symbol) }
        .accessibilityElement(children: .contain)
        .accessibilityAddTraits(.isButton)
        .accessibilityIdentifier("favorites.open." + symbol)
        .accessibilityAction { selectOrOpen(symbol) }
        .accessibilityAction(named: "展开详情") { toggleDetails(symbol) }
      if editing {
        Button { moving = MoveRequest(symbols: [symbol]) } label: { Image(systemName: "folder") }
          .buttonStyle(.plain).accessibilityIdentifier("favorites.move." + symbol)
      } else {
        Button { toggleDetails(symbol) } label: {
          Image(systemName: expanded.contains(symbol) ? "chevron.up" : "chevron.down")
            .font(.system(size: 10, weight: .semibold)).frame(width: 18, height: 44)
        }.buttonStyle(.plain).accessibilityLabel("展开详情")
          .accessibilityIdentifier("favorites.expand." + symbol)
      }
    }.foregroundStyle(theme.ink).padding(.horizontal, 16).padding(.vertical, 10)
  }

  private func quote(_ symbol: String) -> some View {
    let ticker = displayQuote(symbol)
    let value = ticker?.changePercent ?? .nan
    let color = value.isFinite ? theme.badgeFill(up: value >= 0) : theme.ink3
    let decimals = model.info(for: symbol)?.pricePrecision ?? 2
    let price = ticker?.last ?? .nan
    let change = amount && value.isFinite && price.isFinite && value > -100 ? price - price / (1 + value / 100) : value
    let priceText = price.isFinite ? fmtNum(price, decimals) : "—"
    let sign = change >= 0 ? "+" : ""
    let suffix = amount ? "" : "%"
    let changeText = change.isFinite ? sign + toFixed(change, amount ? decimals : 2) + suffix : "—"
    return VStack(alignment: .trailing, spacing: 4) {
      Text(priceText)
        .font(.system(size: 14.5, weight: .medium, design: .monospaced))
        .lineLimit(1).minimumScaleFactor(0.7)
        .foregroundStyle(price.isFinite ? theme.ink : .clear)
        .overlay(alignment: .trailing) {
          if !price.isFinite { RoundedRectangle(cornerRadius: 3).fill(theme.raised2).frame(width: 68, height: 12).accessibilityHidden(true) }
        }.accessibilityIdentifier("favorites.price." + symbol)
      Text(changeText)
        .font(.system(size: 12, weight: .semibold, design: .monospaced))
        .foregroundStyle(theme.badgeInk)
        .padding(.horizontal, 6).padding(.vertical, 4).frame(minWidth: 62)
        .background(color, in: RoundedRectangle(cornerRadius: 5))
        .accessibilityIdentifier("favorites.change." + symbol)
    }.frame(width: 98, alignment: .trailing)
      .animation(reduceMotion ? nil : .easeOut(duration: 0.32), value: ticker != nil)
  }

  private func details(_ symbol: String) -> some View {
    let ticker = displayQuote(symbol)
    let decimals = model.info(for: symbol)?.pricePrecision ?? 2
    return VStack(spacing: 10) {
      LazyVGrid(columns: Array(repeating: GridItem(.flexible(), alignment: .leading), count: 3), spacing: 10) {
        cell("1h", percent(historyChange(symbol, hours: 1)))
        cell("4h", percent(historyChange(symbol, hours: 4)))
        cell(basisTitle, percent(ticker?.changePercent))
        cell("24h 高", number(ticker?.high, decimals))
        cell("24h 低", number(ticker?.low, decimals))
        cell("24h 额", ticker.map { fmtVol($0.quoteVolume) + " " + quoteAsset(symbol) } ?? "—")
      }
      if let ticker, ticker.high > ticker.low, ticker.last.isFinite {
        GeometryReader { geometry in
          Capsule().fill(theme.raised2).frame(height: 4)
          Capsule().fill(theme.ink2).frame(width: 2, height: 10)
            .offset(x: min(max((ticker.last - ticker.low) / (ticker.high - ticker.low), 0), 1) * max(0, geometry.size.width - 2), y: -3)
        }.frame(height: 8)
      }
      HStack {
        Button("移到分类") { moving = MoveRequest(symbols: [symbol]) }
          .accessibilityIdentifier("favorites.move." + symbol)
        Spacer()
        Button("打开行情图表") { open(symbol) }
      }.font(.system(size: 12)).padding(.top, 2)
    }.buttonStyle(.plain).padding(14).background(theme.chartBG).accessibilityElement(children: .contain).accessibilityIdentifier("favorites.details." + symbol)
  }

  private func historyChange(_ symbol: String, hours: Int) -> Double? {
    let target = Int64(Date().timeIntervalSince1970 * 1000) - Int64(hours) * 3_600_000
    guard let bar = model.historyBars[symbol]?.last(where: { $0.openTime <= target }),
          target - bar.openTime < 60_000, bar.open > 0,
          let price = displayQuote(symbol)?.last else { return nil }
    return (price / bar.open - 1) * 100
  }
  private func percent(_ value: Double?) -> String { guard let value, value.isFinite else { return "—" }; return (value >= 0 ? "+" : "") + toFixed(value, 2) + "%" }
  private func number(_ value: Double?, _ decimals: Int) -> String { guard let value, value.isFinite else { return "—" }; return fmtNum(value, decimals) }
  private func cell(_ title: String, _ value: String) -> some View {
    VStack(alignment: .leading, spacing: 3) { Text(title).font(.system(size: 10)).foregroundStyle(theme.ink3); Text(value).font(.system(size: 12, weight: .medium, design: .monospaced)) }.foregroundStyle(theme.ink)
  }
  private func toggleDetails(_ symbol: String) { if !expanded.insert(symbol).inserted { expanded.remove(symbol) } }
  private func selectOrOpen(_ symbol: String) {
    if editing { if !selection.insert(symbol).inserted { selection.remove(symbol) } }
    else { open(symbol) }
  }
  private func quoteAsset(_ symbol: String) -> String {
    model.info(for: symbol)?.quote ??
      (["USDT", "USDC", "BUSD"].first { symbol.hasSuffix($0) } ?? "USDT")
  }
  private func open(_ symbol: String) {
    let info = model.info(for: symbol) ?? SymbolInfo(symbol: symbol, base: String(symbol.dropLast(4)), quote: quoteAsset(symbol), pricePrecision: 2, tickSize: 0.01)
    model.pick(info)
  }
  private func assign(_ symbols: [String], to group: String?) {
    symbols.forEach { model.assign($0, to: group) }; moving = nil; selection.removeAll()
  }
  private var editBar: some View {
    HStack {
      Button(selection.count == symbols.count ? "全不选" : "全选") { selection = selection.count == symbols.count ? [] : Set(symbols) }
      Spacer()
      Button("移到分组") { moving = MoveRequest(symbols: Array(selection)) }.disabled(selection.isEmpty)
      Spacer()
      Button("删除", role: .destructive) { selection.forEach { model.removeFavorite($0) }; selection.removeAll() }.disabled(selection.isEmpty)
    }.font(.system(size: 12)).padding(16).background(theme.raised)
  }
  private func chip(_ title: String, id: String, count: Int) -> some View {
    Button { model.selectGroup(id); selection.removeAll(); expanded.removeAll() } label: {
      Text(title).font(.system(size: 17, weight: selected == id ? .semibold : .medium))
        .lineLimit(1).truncationMode(.middle).frame(maxWidth: .infinity, minHeight: 48)
        .contentShape(Rectangle())
        .foregroundStyle(selected == id ? theme.amber : theme.ink2)
        .overlay(alignment: .bottom) { if selected == id { Capsule().fill(theme.amber).frame(height: 2).padding(.horizontal, 10).padding(.bottom, 4) } }
    }.buttonStyle(.plain).accessibilityLabel(title + "，\(count)个品种")
      .accessibilityAddTraits(selected == id ? .isSelected : [])
      .accessibilityIdentifier("favorites.group." + title)
  }
}

/// Keep category controls independent of row-price refreshes.
/// Keep the header's identity tied to folders/editing/theme, not row prices.
private struct FavoritesHeader<Content: View>: View, Equatable {
  let prefs: SymbolPrefs
  let editing: Bool
  let more: Bool
  let theme: PanelTheme
  let content: Content
  nonisolated static func == (lhs: Self, rhs: Self) -> Bool {
    lhs.prefs == rhs.prefs && lhs.editing == rhs.editing && lhs.more == rhs.more && lhs.theme == rhs.theme
  }
  var body: some View { content }
}
