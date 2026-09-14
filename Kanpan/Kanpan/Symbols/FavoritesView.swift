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
  @Environment(\.colorScheme) private var scheme
  @State private var adding = false
  @State private var editingName = false
  @State private var renamedID: String?
  @State private var name = ""
  @FocusState private var searchFocused: Bool
  @State private var search = false
  @State private var query = ""
  @State private var editing = false
  @State private var editQuotes: [String: Ticker] = [:]
  @State private var selection = Set<String>()
  @State private var expanded = Set<String>()
  @State private var sort = "custom"
  @State private var ascending = false
  @State private var amount = false
  @State private var moving: MoveRequest?
  private struct MoveRequest: Identifiable { let id = UUID(); let symbols: [String] }
  private var theme: PanelTheme { PanelTheme(dark: scheme == .dark, redUp: redUp) }
  private var selected: String? { model.prefs.selectedGroupID ?? model.prefs.groups.first?.id }
  private var groupID: String? { selected }
  private var symbols: [String] {
    let source = model.prefs.favorites(in: groupID)
    let term = SymbolQuery.normalize(query)
    var rows = source.filter { term.isEmpty || $0.contains(term) }
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
        if search {
          HStack(spacing: 10) {
            TextField("搜索自选品种", text: $query).textInputAutocapitalization(.characters)
              .autocorrectionDisabled().focused($searchFocused).accessibilityIdentifier("favorites.query")
              .task {
                // 搜索框插入动画结束后再聚焦，避免尚未加入窗口时丢失焦点请求。
                try? await Task.sleep(for: .milliseconds(220))
                guard !Task.isCancelled else { return }
                searchFocused = true
              }
              .padding(9).background(theme.raised2, in: RoundedRectangle(cornerRadius: 9))
            Button("取消") { searchFocused = false; search = false; query = "" }.accessibilityIdentifier("favorites.search.cancel")
          }.padding(.horizontal, 12).padding(.bottom, 9)
        }
        groupBar
        overview
        sortBar
        if symbols.isEmpty {
          ContentUnavailableView {
            Label(query.isEmpty ? "这个分类还是空的" : "没搜到", systemImage: "star")
          } description: {
            Text("把常看的品种加进来，分组只是组织方式，行情不会重复。")
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
            .moveDisabled(!query.isEmpty)
          }.listStyle(.plain).scrollContentBackground(.hidden)
        }
      }
      .background(theme.app)
      .toolbarBackground(theme.app, for: .navigationBar)
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .topBarLeading) {
          Button("行情", action: onClose).accessibilityIdentifier("favorites.close")
        }
        ToolbarItem(placement: .principal) {
          HStack(alignment: .firstTextBaseline, spacing: 6) {
            Text("自选").font(.system(size: 17, weight: .semibold))
            Text("\(model.prefs.favorites.count)").font(.system(size: 11)).foregroundStyle(theme.ink3)
          }
        }
        ToolbarItemGroup(placement: .topBarTrailing) {
          Button {
            withAnimation(reduceMotion ? nil : .easeOut(duration: 0.2)) { search.toggle() }
            if !search { query = ""; searchFocused = false }
          } label: {
            Image(systemName: "magnifyingglass").frame(width: 36, height: 36)
              .background(theme.app, in: RoundedRectangle(cornerRadius: 8)).contentShape(Rectangle())
          }.buttonStyle(.plain).accessibilityLabel("搜索自选").accessibilityIdentifier("favorites.search")
          Button { adding = true } label: { Image(systemName: "plus") }
            .accessibilityLabel("添加品种").accessibilityIdentifier("favorites.add")
          Button(editing ? "完成" : "编辑") {
            if editing { editing = false; editQuotes.removeAll() }
            else { editQuotes = model.tickers; editing = true }
            selection.removeAll(); query = ""; expanded.removeAll()
          }.accessibilityIdentifier("favorites.edit")
        }
      }
      .safeAreaInset(edge: .bottom, spacing: 0) { if editing { editBar } }
    }
    .tint(theme.amber)
    .task { await model.appear() }
    .onDisappear {
      model.disappear()
      for symbol in expanded { onHistoryVisibility(symbol, false) }
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

  private var groupBar: some View {
    HStack(spacing: 0) {
      ScrollView(.horizontal, showsIndicators: false) {
        HStack(spacing: 2) {
          ForEach(model.prefs.groups) { group in
            chip(group.name, id: group.id, count: model.prefs.favorites(in: group.id).count)
              .contextMenu {
                Button("重命名") { renamedID = group.id; name = group.name; editingName = true }
                Button("删除分类", role: .destructive) {
                  model.deleteGroup(group.id)
                }
              }
          }
        }.padding(.horizontal, 4)
      }.accessibilityIdentifier("favorites.groups")
      Button { renamedID = nil; name = ""; editingName = true } label: {
        Image(systemName: "folder.badge.plus").frame(width: 42, height: 38)
      }.accessibilityLabel("新建分类").accessibilityIdentifier("favorites.newGroup")
    }.overlay(alignment: .bottom) { theme.line.frame(height: 0.5) }
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
      .accessibilityValue(feedDiagnostics ?? "")
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
    let base = model.catalog.first { $0.symbol == symbol }?.base ?? String(symbol.dropLast(4))
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
    let color = value.isFinite ? (value >= 0 ? theme.up : theme.down) : theme.ink3
    let decimals = model.catalog.first { $0.symbol == symbol }?.pricePrecision ?? 2
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
    let decimals = model.catalog.first { $0.symbol == symbol }?.pricePrecision ?? 2
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
    model.catalog.first { $0.symbol == symbol }?.quote ??
      (["USDT", "USDC", "BUSD"].first { symbol.hasSuffix($0) } ?? "USDT")
  }
  private func open(_ symbol: String) {
    let info = model.catalog.first { $0.symbol == symbol } ?? SymbolInfo(symbol: symbol, base: String(symbol.dropLast(4)), quote: quoteAsset(symbol), pricePrecision: 2, tickSize: 0.01)
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
      HStack(spacing: 4) { Text(title).font(.system(size: 13, weight: .medium)); Text("\(count)").font(.system(size: 10, design: .monospaced)).opacity(0.75) }
        .padding(.horizontal, 10).padding(.vertical, 12)
        .foregroundStyle(selected == id ? theme.amber : theme.ink2)
        .overlay(alignment: .bottom) { if selected == id { Capsule().fill(theme.amber).frame(height: 2).padding(.horizontal, 10).padding(.bottom, 4) } }
    }.accessibilityIdentifier("favorites.group." + title)
  }
}
