import SwiftUI
import UIKit
import KanpanCore
import KanpanData

/// 自选分类页 ——「琉璃」。
///
/// 底是三团会慢慢漂的光，上面浮着玻璃：按钮是玻璃圆片，分类是玻璃胶囊，整张列表
/// 是一张玻璃纸。颜色一律从当前皮肤的种子推（见 `LiuliSkin`），View 里不写死
/// 十六进制——唯一的例外是浅色那组「天青·薄荷」光斑，那是浅色底下专配的一组冷光，
/// 不属于任何一套皮肤。
///
/// 功能与原来那一版逐条对齐：分类切换/新建/重命名/删除/溢出、添加品种、批量编辑、
/// 排序、展开详情、右滑删除、长按拖动、进图表，`accessibilityIdentifier` 一个没换。
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
  @State private var sorting = false
  @State private var afterMore: (() -> Void)?
  @State private var moreTask: Task<Void, Never>?
  @State private var editingName = false
  @State private var renamedID: String?
  @State private var name = ""
  @State private var editing = false
  @State private var editQuotes: [String: Ticker] = [:]
  @State private var selection = Set<String>()
  @State private var expanded = Set<String>()
  /// 已经替它开了历史订阅的品种。页面整体消失时要逐个关掉——
  /// 行自己的 `onDisappear` 在整页被拆掉时不保证会走到。
  @State private var historyOn = Set<String>()
  @State private var sort = "custom"
  @State private var ascending = false
  @State private var amount = false
  /// 行尾那条迷你走势线。默认不画——它挤在价格旁边会把整行的视觉打散；
  /// 想看的人在「…」里自己打开，开关记在本机。
  @AppStorage("favorites.sparkline") private var sparkline = false
  @State private var moving: MoveRequest?
  private struct MoveRequest: Identifiable { let id = UUID(); let symbols: [String] }
  private var selected: String? { model.prefs.selectedGroupID ?? model.prefs.groups.first?.id }
  private var groupID: String? { selected }
  private var skin: LiuliSkin { LiuliSkin(theme: theme) }
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
      GeometryReader { geometry in
        VStack(spacing: 0) {
          navBar
          titleRow
          subline
          FavoritesHeader(prefs: model.prefs, editing: editing, more: more,
                          theme: theme, width: geometry.size.width,
                          content: groupBar(width: geometry.size.width)).equatable()
          sortBar
          if symbols.isEmpty { emptyState } else { listSheet }
        }
        .frame(width: geometry.size.width, height: geometry.size.height, alignment: .top)
      }
      .background { AuroraBackdrop(skin: skin, reduceMotion: reduceMotion).ignoresSafeArea() }
      .toolbar(.hidden, for: .navigationBar)
      .safeAreaInset(edge: .bottom, spacing: 0) { if editing { editBar } }
    }
    .tint(theme.amber)
    .task { await model.appear() }
    .onDisappear {
      moreTask?.cancel()
      model.disappear()
      for symbol in historyOn { onHistoryVisibility(symbol, false) }
      historyOn.removeAll()
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

  // MARK: - 头部

  /// 返回 / 编辑 / 更多：三颗 32 的玻璃圆片，命中区 44。
  private var navBar: some View {
    HStack(spacing: 0) {
      circleButton("chevron.left", label: "返回行情", id: "favorites.back", action: onClose)
      Spacer(minLength: 0)
      if editing {
        Button { toggleEditing() } label: {
          Text("完成").font(.system(size: 13.5, weight: .semibold)).foregroundStyle(theme.amber)
            .frame(height: 32).padding(.horizontal, 14)
            .background(skin.glassThin, in: Capsule())
            .overlay(Capsule().strokeBorder(skin.edgeSoft, lineWidth: 0.5))
            .frame(height: 44).contentShape(Rectangle())
        }.buttonStyle(.plain)
          .accessibilityLabel("完成编辑").accessibilityIdentifier("favorites.editToggle")
      } else {
        circleButton("square.and.pencil", label: "编辑自选", id: "favorites.editToggle") { toggleEditing() }
      }
      circleButton("ellipsis", label: "更多分类与管理", id: "favorites.more") { more = true }
        .popover(isPresented: $more, arrowEdge: .top) {
          moreList(hidden: hiddenGroups).presentationCompactAdaptation(.popover)
        }
    }
    .padding(.horizontal, 10)
    .frame(height: 44)
  }

  private func circleButton(_ icon: String, label: String, id: String,
                            action: @escaping () -> Void) -> some View {
    Button(action: action) {
      Image(systemName: icon)
        .font(.system(size: 15, weight: .regular))
        .foregroundStyle(theme.ink)
        .frame(width: 32, height: 32)
        .background(skin.glassThin, in: Circle())
        .overlay(Circle().strokeBorder(skin.edgeSoft, lineWidth: 0.5))
        .frame(width: 44, height: 44)
        .contentShape(Rectangle())
    }.buttonStyle(.plain)
      .accessibilityLabel(label).accessibilityIdentifier(id)
  }

  /// 「自选」衬线体 + 数量印章（正放），右边是涨跌比。
  private var titleRow: some View {
    HStack(alignment: .center, spacing: 10) {
      HStack(alignment: .center, spacing: 8) {
        Text("自选").font(skin.serif(22)).foregroundStyle(theme.ink)
          .tracking(1.3)
        seal(symbols.count)
      }
      Spacer(minLength: 8)
      breadth
    }.padding(.horizontal, 20).padding(.top, 2)
  }

  private func seal(_ count: Int) -> some View {
    Text("\(count)")
      .font(.system(size: 10.5, weight: .semibold)).monospacedDigit()
      .foregroundStyle(.white)
      .frame(minWidth: 20).frame(height: 20)
      .padding(.horizontal, 4)
      .background(skin.accent, in: RoundedRectangle(cornerRadius: 5, style: .continuous))
      .overlay(
        RoundedRectangle(cornerRadius: 4, style: .continuous)
          .strokeBorder(Color.white.opacity(0.35), lineWidth: 1).padding(1))
      .shadow(color: skin.accent.opacity(0.5), radius: 5, x: 0, y: 3)
      .offset(y: -3)
      .accessibilityLabel("\(count) 个品种")
  }

  private var breadth: some View {
    let values = changeValues
    let up = values.filter { $0 >= 0 }.count
    let down = values.count - up
    let ratio = values.isEmpty ? 0 : CGFloat(up) / CGFloat(max(1, values.count))
    return HStack(spacing: 7) {
      Text(values.isEmpty ? "—" : "\(up)").foregroundStyle(theme.up)
      ZStack(alignment: .leading) {
        Capsule().fill(values.isEmpty ? skin.rule : theme.down)
          .shadow(color: values.isEmpty ? .clear : theme.down.opacity(0.4), radius: 4)
        if !values.isEmpty {
          Capsule()
            .fill(LinearGradient(colors: [theme.up, skin.lift(theme.chart.up, 0.3)],
                                 startPoint: .leading, endPoint: .trailing))
            .frame(width: 62 * ratio)
            .shadow(color: theme.up.opacity(0.5), radius: 4)
        }
      }.frame(width: 62, height: 4)
      Text(values.isEmpty ? "—" : "\(down)").foregroundStyle(theme.down)
    }.font(.system(size: 10, weight: .medium)).monospacedDigit()
  }

  /// 标题下那一行小字：整页唯一允许出现的状态文案。
  private var subline: some View {
    let values = changeValues
    let up = values.filter { $0 >= 0 }.count
    let amplitudes = symbols.compactMap { displayQuote($0)?.amplitude24h }.filter(\.isFinite)
    let live = feedStatus == .live
    let text: String = {
      guard !values.isEmpty else { return "正在取最新价" }
      var line = "今日 \(up) 涨 \(values.count - up) 跌"
      if !amplitudes.isEmpty {
        line += " · 平均振幅 " + toFixed(amplitudes.reduce(0, +) / Double(amplitudes.count), 1) + "%"
      }
      return line
    }()
    return HStack(spacing: 0) {
      Circle().fill(live ? skin.accent : skin.ink4)
        .frame(width: 5, height: 5)
        .overlay(Circle().stroke((live ? skin.accent : skin.ink4).opacity(0.22), lineWidth: 3))
        .padding(.trailing, 7)
      Text(text).font(.system(size: 10.5)).foregroundStyle(theme.ink3)
      Spacer(minLength: 0)
    }.padding(.horizontal, 20).padding(.top, 5).frame(height: 18)
      .accessibilityElement(children: .contain)
      .accessibilityIdentifier("favorites.feed")
      .accessibilityValue(paletteDiagnostics)
  }

  private var changeValues: [Double] {
    symbols.compactMap { displayQuote($0)?.changePercent }.filter(\.isFinite)
  }

  private var paletteDiagnostics: String {
    guard let feedDiagnostics else { return "" }
    return feedDiagnostics + ";background=" + theme.chart.bg.value
  }

  // MARK: - 分类分段器

  /// 一格分类占多宽：12.5 的名字 + 上标数字 + 左右各 12 的内边。
  private func tabWidth(_ group: FavoriteGroup) -> CGFloat {
    let text = (group.name as NSString)
      .size(withAttributes: [.font: UIFont.systemFont(ofSize: 12.5, weight: .medium)]).width
    let count = model.prefs.favorites(in: group.id).count
    return min(124, max(54, text + CGFloat("\(count)".count) * 6 + 28))
  }

  private func visibleGroups(width: CGFloat) -> [FavoriteGroup] {
    var result: [FavoriteGroup] = []
    // 32 是右边那颗「+」，8 是它和胶囊之间的缝，6 是胶囊自己的内边，32 是左右页边。
    var remaining = max(0, width - 32 - 8 - 6 - 32)
    for group in model.prefs.groups {
      let required = tabWidth(group)
      guard remaining >= required else { break }
      result.append(group); remaining -= required
    }
    if let active = model.prefs.groups.first(where: { $0.id == selected }),
       !result.contains(where: { $0.id == active.id }) {
      while !result.isEmpty && remaining < tabWidth(active) {
        remaining += tabWidth(result.removeLast())
      }
      result.append(active)
    }
    return result
  }

  /// 「更多」里那半截：没能排进分段器的分类。
  private var hiddenGroups: [FavoriteGroup] {
    let visible = visibleGroups(width: barWidth)
    return model.prefs.groups.filter { group in !visible.contains(where: { $0.id == group.id }) }
  }

  /// 分段器可用宽度。页面是整屏盖上来的，宽度就是屏宽——只在这儿记一次，
  /// 免得「更多」弹层还要再问一遍几何。
  @State private var barWidth: CGFloat = 393

  private func groupBar(width: CGFloat) -> some View {
    let visible = visibleGroups(width: width)
    return HStack(spacing: 8) {
      HStack(spacing: 0) {
        ForEach(visible) { group in
          chip(group.name, id: group.id, count: model.prefs.favorites(in: group.id).count)
            .frame(width: tabWidth(group))
        }
      }
      .padding(.horizontal, 3)
      .background {
        RoundedRectangle(cornerRadius: 15, style: .continuous)
          .fill(skin.glassThin)
          .overlay(RoundedRectangle(cornerRadius: 15, style: .continuous)
            .strokeBorder(skin.edgeSoft, lineWidth: 0.5))
          .frame(height: 36)
      }
      .accessibilityElement(children: .contain)
      .accessibilityIdentifier("favorites.groups")
      Spacer(minLength: 0)
      Button { adding = true } label: {
        Image(systemName: "plus").font(.system(size: 14, weight: .medium))
          .foregroundStyle(theme.ink3)
          .frame(width: 32, height: 32)
          .background(skin.glassThin, in: RoundedRectangle(cornerRadius: 11, style: .continuous))
          .overlay(RoundedRectangle(cornerRadius: 11, style: .continuous)
            .strokeBorder(skin.edgeSoft, lineWidth: 0.5))
          .frame(width: 40, height: 44)
          .contentShape(Rectangle())
      }.buttonStyle(.plain)
        .accessibilityLabel("添加品种").accessibilityIdentifier("favorites.add")
    }
    .padding(.horizontal, 16).padding(.top, 12)
    .onAppear { barWidth = width }
    .onChange(of: width) { _, next in barWidth = next }
  }

  private func chip(_ title: String, id: String, count: Int) -> some View {
    let on = selected == id
    return Button { model.selectGroup(id); selection.removeAll(); expanded.removeAll() } label: {
      HStack(alignment: .firstTextBaseline, spacing: 3) {
        Text(title).font(.system(size: 12.5, weight: .medium))
          .lineLimit(1).truncationMode(.middle)
        Text("\(count)").font(.system(size: 9, weight: .medium)).monospacedDigit()
          .baselineOffset(4)
          .foregroundStyle(on ? Color.white.opacity(0.75) : skin.ink4)
      }
      .foregroundStyle(on ? Color.white : theme.ink2)
      .frame(maxWidth: .infinity).frame(height: 30)
      .background {
        if on {
          RoundedRectangle(cornerRadius: 11, style: .continuous)
            .fill(skin.accentGradient)
            .overlay(alignment: .top) { skin.topHighlight(inset: 7) }
            .shadow(color: skin.accent.opacity(skin.dark ? 0.5 : 0.35), radius: 8, x: 0, y: 5)
        }
      }
      .frame(height: 44)
      .contentShape(Rectangle())
    }.buttonStyle(.plain)
      .accessibilityLabel(title + "，\(count)个品种")
      .accessibilityAddTraits(on ? .isSelected : [])
      .accessibilityIdentifier("favorites.group." + title)
  }

  // MARK: - 更多

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
        moreRow(sparkline ? "隐藏迷你走势" : "显示迷你走势", icon: sparkline ? "waveform.slash" : "waveform",
                id: "favorites.sparkline") { sparkline.toggle() }
        if let group = model.prefs.groups.first(where: { $0.id == selected }) {
          moreRow("重命名当前分类", icon: "square.and.pencil", id: "favorites.renameGroup") {
            renamedID = group.id; name = group.name; editingName = true
          }
          moreRow("删除当前分类", icon: "trash", id: "favorites.deleteGroup", destructive: true) { model.deleteGroup(group.id) }
        }
      }.padding(.vertical, 6)
    }.font(.system(size: 14)).frame(width: 260).frame(idealHeight: min(430, CGFloat(5 + hidden.count) * 46 + (hidden.isEmpty ? 18 : 61)), maxHeight: 430)
      .background(theme.app).presentationBackground(theme.app)
  }

  private func toggleEditing() {
    if editing { editing = false; editQuotes.removeAll() }
    else { editQuotes = model.tickers; editing = true }
    selection.removeAll(); expanded.removeAll()
  }

  // MARK: - 排序行

  private var sortBar: some View {
    HStack(spacing: 0) {
      Text("\(symbols.count) 个品种").font(.system(size: 10.5)).foregroundStyle(skin.ink4)
      Spacer(minLength: 0)
      Button { sorting = true } label: {
        HStack(spacing: 4) {
          Text(sortTitle).font(.system(size: 11)).foregroundStyle(theme.ink3)
          Image(systemName: sort == "custom" ? "arrow.up.arrow.down"
                : (ascending ? "arrowtriangle.up.fill" : "arrowtriangle.down.fill"))
            .font(.system(size: 7)).foregroundStyle(theme.amber)
        }.frame(height: 28).contentShape(Rectangle())
      }.buttonStyle(.plain).disabled(editing)
        .accessibilityLabel("排序方式").accessibilityIdentifier("favorites.sort")
        .popover(isPresented: $sorting, arrowEdge: .top) {
          sortList.presentationCompactAdaptation(.popover)
        }
    }.padding(.horizontal, 22).padding(.top, 10).padding(.bottom, 4)
  }

  private var sortTitle: String {
    switch sort {
    case "name": "品种"
    case "volume": "成交额"
    case "price": "价格"
    case "change": amount ? "涨跌额" : basisTitle
    default: "自选顺序"
    }
  }

  private var sortList: some View {
    VStack(spacing: 0) {
      sortItem("自选顺序", key: "custom")
      sortItem("品种", key: "name")
      sortItem("成交额", key: "volume")
      sortItem("价格", key: "price")
      sortItem(basisTitle, key: "change", useAmount: false)
      sortItem("涨跌额", key: "change", useAmount: true)
    }.padding(.vertical, 6).font(.system(size: 14)).frame(width: 190)
      .background(theme.app).presentationBackground(theme.app)
  }

  private func sortItem(_ title: String, key: String, useAmount: Bool? = nil) -> some View {
    let current = sort == key && (useAmount == nil || useAmount == amount)
    return Button {
      if let useAmount { amount = useAmount }
      applySort(key)
      sorting = false
    } label: {
      HStack(spacing: 8) {
        Text(title)
        Spacer(minLength: 0)
        if current {
          Image(systemName: ascending ? "arrowtriangle.up.fill" : "arrowtriangle.down.fill")
            .font(.system(size: 8)).foregroundStyle(theme.amber)
        }
      }.frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
        .padding(.horizontal, 16).contentShape(Rectangle())
    }.buttonStyle(.plain).foregroundStyle(current ? theme.amber : theme.ink)
  }

  /// 排序键与方向：和原来那排小按钮一个逻辑——同一个键点第二次翻方向，
  /// 第三次退回自选顺序。
  private func applySort(_ key: String) {
    guard key != "custom" else { sort = "custom"; return }
    if sort != key { sort = key; ascending = key == "name" }
    else if ascending == (key == "name") { ascending.toggle() } else { sort = "custom" }
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

  // MARK: - 列表玻璃纸

  private var listSheet: some View {
    List {
      ForEach(symbols, id: \.self) { symbol in
        VStack(spacing: 0) {
          row(symbol, first: symbol == symbols.first)
          if expanded.contains(symbol), !editing { details(symbol) }
        }
        .listRowInsets(EdgeInsets())
        .listRowBackground(Color.clear)
        .listRowSeparator(.hidden)
        .onAppear {
          onVisible(symbol); onRowVisibility(symbol, true)
          if historyOn.insert(symbol).inserted { onHistoryVisibility(symbol, true) }
        }
        .onDisappear {
          onRowVisibility(symbol, false)
          if historyOn.remove(symbol) != nil { onHistoryVisibility(symbol, false) }
        }
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
    }
    .listStyle(.plain)
    .scrollContentBackground(.hidden)
    .environment(\.defaultMinListRowHeight, 0)
    // 玻璃纸只铺到内容那么高，品种少的时候不在下半屏拖一大块空白；
    // 但 List 本身仍旧占满——收窄的话，长按把一行拖到最后一行下面就落到列表外面去了。
    .background(alignment: .top) { sheetSkin }
    .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    .padding(.horizontal, 12).padding(.top, 8).padding(.bottom, 8)
  }

  /// 那张玻璃纸。展开了详情行高就量不准，这时让它照旧占满。
  private var sheetSkin: some View {
    let shape = RoundedRectangle(cornerRadius: 22, style: .continuous)
    return shape.fill(skin.glass)
      .overlay(alignment: .top) { skin.topHighlight(inset: 10) }
      .overlay { shape.strokeBorder(skin.edgeSoft, lineWidth: 0.5) }
      .frame(maxHeight: expanded.isEmpty ? CGFloat(symbols.count) * 66 : .infinity, alignment: .top)
  }

  private func row(_ symbol: String, first: Bool) -> some View {
    let ticker = displayQuote(symbol)
    let base = model.info(for: symbol)?.base ?? String(symbol.dropLast(4))
    let amplitude = ticker?.amplitude24h
    let volumeText = ticker.map { $0.quoteVolume.isFinite ? fmtVol($0.quoteVolume) : "—" } ?? "—"
    let amplitudeText = amplitude.map { toFixed($0, 2) + "%" } ?? "—"
    let value = ticker?.changePercent ?? .nan
    let trend = value.isFinite ? (value >= 0 ? theme.up : theme.down) : skin.ink4
    return HStack(spacing: 10) {
      if editing {
        Button { if !selection.insert(symbol).inserted { selection.remove(symbol) } } label: {
          checkbox(selection.contains(symbol))
        }.buttonStyle(.plain).accessibilityLabel(selection.contains(symbol) ? "取消选择" : "选择")
      }
      HStack(spacing: 10) {
        badge(base)
        VStack(alignment: .leading, spacing: 4) {
          HStack(alignment: .firstTextBaseline, spacing: 3) {
            Text(base).font(.system(size: 13.5, weight: .semibold)).foregroundStyle(theme.ink)
            Text(quoteAsset(symbol)).font(.system(size: 9, weight: .regular)).foregroundStyle(skin.ink4)
          }.lineLimit(1).minimumScaleFactor(0.75)
          Text("额 " + volumeText + "  ·  幅 " + amplitudeText)
            .font(.system(size: 10)).monospacedDigit().foregroundStyle(theme.ink3)
            .lineLimit(1).minimumScaleFactor(0.8)
        }.frame(maxWidth: .infinity, alignment: .leading)
        if !editing, sparkline {
          Sparkline(values: sparkValues(symbol), color: trend)
            .frame(width: 44, height: 24)
        }
        quote(symbol)
      }.contentShape(Rectangle())
        .onTapGesture { selectOrOpen(symbol) }
        .accessibilityElement(children: .contain)
        .accessibilityAddTraits(.isButton)
        .accessibilityIdentifier("favorites.open." + symbol)
        .accessibilityAction { selectOrOpen(symbol) }
        .accessibilityAction(named: "展开详情") { toggleDetails(symbol) }
      if editing {
        Button { moving = MoveRequest(symbols: [symbol]) } label: {
          Image(systemName: "folder").font(.system(size: 13)).foregroundStyle(theme.ink3)
            .frame(width: 22, height: 44).contentShape(Rectangle())
        }.buttonStyle(.plain).accessibilityIdentifier("favorites.move." + symbol)
      } else {
        Button { toggleDetails(symbol) } label: {
          Image(systemName: expanded.contains(symbol) ? "chevron.up" : "chevron.down")
            .font(.system(size: 9, weight: .semibold)).foregroundStyle(skin.ink4)
            .frame(width: 14, height: 44).contentShape(Rectangle())
        }.buttonStyle(.plain).accessibilityLabel("展开详情")
          .accessibilityIdentifier("favorites.expand." + symbol)
      }
    }
    .padding(.leading, 15).padding(.trailing, 14)
    .frame(height: 66)
    .overlay(alignment: .top) {
      if !first {
        LinearGradient(colors: [.clear, skin.rule, skin.rule, .clear],
                       startPoint: .leading, endPoint: .trailing)
          .frame(height: 0.5).padding(.horizontal, 14)
      }
    }
  }

  /// 徽章：背后一团品牌色的光晕，外面一圈捕光环。
  private func badge(_ base: String) -> some View {
    let spec = CoinSpec.of(base)
    let brand = BadgeTint.gradient(from: spec.from, to: spec.to, seed: theme.seed).bottom
    return ZStack {
      RadialGradient(colors: [brand.opacity(skin.dark ? 0.34 : 0.2), brand.opacity(0)],
                     center: .center, startRadius: 2, endRadius: 24)
        .frame(width: 48, height: 48)
      CoinBadge(base: base, size: 33)
        .overlay {
          RoundedRectangle(cornerRadius: 13.7, style: .continuous)
            .strokeBorder(AngularGradient(
              gradient: Gradient(stops: [
                .init(color: brand, location: 0),
                .init(color: brand.opacity(0.2), location: 0.3),
                .init(color: brand, location: 0.55),
                .init(color: brand.opacity(0.15), location: 0.83),
                .init(color: brand, location: 1)]),
              center: .center, angle: .degrees(210)), lineWidth: 1)
            .opacity(skin.dark ? 0.6 : 0.55)
            .padding(-3.5)
        }
    }.frame(width: 33, height: 33)
  }

  private func checkbox(_ on: Bool) -> some View {
    ZStack {
      if on {
        Circle().fill(skin.accentGradient)
          .overlay(alignment: .top) { skin.topHighlight(inset: 5) }
        Image(systemName: "checkmark").font(.system(size: 10, weight: .bold)).foregroundStyle(.white)
      } else {
        Circle().strokeBorder(skin.ink4, lineWidth: 1.4)
      }
    }.frame(width: 20, height: 20)
  }

  /// 走势线取的是详情那条历史订阅里的分钟线，不另开请求。
  private func sparkValues(_ symbol: String) -> [Double] {
    guard let bars = model.historyBars[symbol], bars.count > 4 else { return [] }
    let tail = Array(bars.suffix(60))
    let step = max(1, tail.count / 30)
    var picked = stride(from: 0, to: tail.count, by: step).map { tail[$0].close }
    if let last = tail.last?.close, picked.last != last { picked.append(last) }
    return picked
  }

  private func quote(_ symbol: String) -> some View {
    let ticker = displayQuote(symbol)
    let value = ticker?.changePercent ?? .nan
    let decimals = model.info(for: symbol)?.pricePrecision ?? 2
    let price = ticker?.last ?? .nan
    let change = amount && value.isFinite && price.isFinite && value > -100 ? price - price / (1 + value / 100) : value
    let priceText = price.isFinite ? grouped(fmtNum(price, decimals)) : "—"
    let tint = value.isFinite ? (value >= 0 ? theme.up : theme.down) : skin.ink4
    // 还没到的涨跌幅和还没到的价格用同一种骨架：一块底色，不写字。
    // 写「—」会让人以为这个品种没有涨跌幅，而不是还在路上。
    let changeText = change.isFinite ? toFixed(abs(change), amount ? decimals : 2) + (amount ? "" : "%") : "—"
    let signed = change.isFinite ? (change >= 0 ? "+" : "-") + changeText : "—"
    return VStack(alignment: .trailing, spacing: 5) {
      Text(priceText)
        .font(.system(size: 15.5, weight: .medium)).monospacedDigit()
        .lineLimit(1).minimumScaleFactor(0.7)
        .foregroundStyle(price.isFinite ? theme.ink : .clear)
        .overlay(alignment: .trailing) {
          if !price.isFinite {
            RoundedRectangle(cornerRadius: 4).fill(skin.rule).frame(width: 70, height: 13)
              .accessibilityHidden(true)
          }
        }.accessibilityIdentifier("favorites.price." + symbol)
      HStack(spacing: 4) {
        if change.isFinite {
          Triangle(up: change >= 0).fill(tint).frame(width: 6, height: 5)
            .accessibilityHidden(true)
        }
        Text(changeText)
          .font(.system(size: 11, weight: .semibold)).monospacedDigit()
          .foregroundStyle(change.isFinite ? tint : .clear)
          .accessibilityLabel(signed)
          .accessibilityIdentifier("favorites.change." + symbol)
      }
      .padding(.horizontal, 7).frame(height: 19).frame(minWidth: 54)
      .background {
        RoundedRectangle(cornerRadius: 7, style: .continuous)
          .fill(change.isFinite ? tint.opacity(0.14) : skin.rule)
          .overlay(RoundedRectangle(cornerRadius: 7, style: .continuous)
            .strokeBorder(change.isFinite ? tint.opacity(0.3) : .clear, lineWidth: 0.5))
      }
    }.frame(minWidth: 86, alignment: .trailing)
      .animation(reduceMotion ? nil : .easeOut(duration: 0.32), value: ticker != nil)
  }

  /// 价格千分位。`fmtNum` 只管小数位，逗号在这儿补。
  private func grouped(_ text: String) -> String {
    let parts = text.split(separator: ".", maxSplits: 1, omittingEmptySubsequences: false)
    var head = String(parts[0])
    let negative = head.hasPrefix("-")
    if negative { head.removeFirst() }
    guard head.count > 3 else { return text }
    var out = ""
    for (index, character) in head.reversed().enumerated() {
      if index > 0, index % 3 == 0 { out.append(",") }
      out.append(character)
    }
    let body = (negative ? "-" : "") + String(out.reversed())
    return parts.count > 1 ? body + "." + parts[1] : body
  }

  // MARK: - 展开详情

  private func details(_ symbol: String) -> some View {
    let ticker = displayQuote(symbol)
    let decimals = model.info(for: symbol)?.pricePrecision ?? 2
    return VStack(spacing: 12) {
      LazyVGrid(columns: Array(repeating: GridItem(.flexible(), alignment: .leading), count: 3), spacing: 12) {
        cell("1H", percent(historyChange(symbol, hours: 1)))
        cell("4H", percent(historyChange(symbol, hours: 4)))
        cell(basisTitle, percent(ticker?.changePercent))
        cell("24H 高", number(ticker?.high, decimals))
        cell("24H 低", number(ticker?.low, decimals))
        cell("24H 额", ticker.map { fmtVol($0.quoteVolume) + " " + quoteAsset(symbol) } ?? "—")
      }
      if let ticker, ticker.high > ticker.low, ticker.last.isFinite {
        GeometryReader { geometry in
          Capsule().fill(skin.rule).frame(height: 4)
          Capsule().fill(skin.accentGradient).frame(width: 2, height: 10)
            .offset(x: min(max((ticker.last - ticker.low) / (ticker.high - ticker.low), 0), 1) * max(0, geometry.size.width - 2), y: -3)
        }.frame(height: 8)
      }
      HStack(spacing: 10) {
        detailAction("移到分类", id: "favorites.move." + symbol) { moving = MoveRequest(symbols: [symbol]) }
        Spacer(minLength: 0)
        detailAction("打开行情图表", id: "favorites.open.chart." + symbol) { open(symbol) }
      }
    }.padding(.horizontal, 18).padding(.top, 12).padding(.bottom, 16)
      .background(skin.glassThin)
      .overlay(alignment: .top) {
        LinearGradient(colors: [.clear, skin.rule, skin.rule, .clear], startPoint: .leading, endPoint: .trailing)
          .frame(height: 0.5).padding(.horizontal, 14)
      }
      .accessibilityElement(children: .contain).accessibilityIdentifier("favorites.details." + symbol)
  }

  private func detailAction(_ title: String, id: String, action: @escaping () -> Void) -> some View {
    Button(action: action) {
      Text(title).font(.system(size: 12, weight: .medium)).foregroundStyle(theme.amber)
        .frame(height: 30).padding(.horizontal, 14)
        .background(skin.glassThin, in: Capsule())
        .overlay(Capsule().strokeBorder(skin.edgeSoft, lineWidth: 0.5))
        .contentShape(Rectangle())
    }.buttonStyle(.plain).accessibilityIdentifier(id)
  }

  private func historyChange(_ symbol: String, hours: Int) -> Double? {
    let target = Int64(Date().timeIntervalSince1970 * 1000) - Int64(hours) * 3_600_000
    guard let bar = model.historyBars[symbol]?.last(where: { $0.openTime <= target }),
          target - bar.openTime < 60_000, bar.open > 0,
          let price = displayQuote(symbol)?.last else { return nil }
    return (price / bar.open - 1) * 100
  }
  private func percent(_ value: Double?) -> String { guard let value, value.isFinite else { return "—" }; return (value >= 0 ? "+" : "") + toFixed(value, 2) + "%" }
  private func number(_ value: Double?, _ decimals: Int) -> String { guard let value, value.isFinite else { return "—" }; return grouped(fmtNum(value, decimals)) }
  private func cell(_ title: String, _ value: String) -> some View {
    VStack(alignment: .leading, spacing: 5) {
      Text(title).font(.system(size: 9, weight: .medium)).tracking(1.2).foregroundStyle(skin.ink4)
      Text(value).font(.system(size: 12, weight: .medium)).monospacedDigit().foregroundStyle(theme.ink)
    }
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

  // MARK: - 空自选 / 编辑条

  private var emptyState: some View {
    VStack(spacing: 10) {
      Spacer(minLength: 0)
      Image(systemName: "plus")
        .font(.system(size: 17, weight: .medium)).foregroundStyle(skin.accent)
        .frame(width: 44, height: 44)
        .background(skin.glassThin, in: RoundedRectangle(cornerRadius: 13.6, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 13.6, style: .continuous)
          .strokeBorder(skin.accent.opacity(0.35), lineWidth: 1))
      Text("这一栏还空着").font(skin.serif(15.5)).foregroundStyle(theme.ink).padding(.top, 2)
      Text("加几个常看的品种，它们会在这里排好")
        .font(.system(size: 12)).foregroundStyle(theme.ink3)
      Button { adding = true } label: {
        Text("添加品种").font(.system(size: 13, weight: .semibold)).foregroundStyle(.white)
          .frame(height: 36).padding(.horizontal, 20)
          .background(skin.accentGradient, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
          .overlay(alignment: .top) { skin.topHighlight(inset: 8) }
          .shadow(color: skin.accent.opacity(0.4), radius: 10, x: 0, y: 6)
      }.buttonStyle(.plain).padding(.top, 8)
      Spacer(minLength: 0)
    }.frame(maxWidth: .infinity, maxHeight: .infinity)
      .background {
        RoundedRectangle(cornerRadius: 22, style: .continuous).fill(skin.glass)
          .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous)
            .strokeBorder(skin.edgeSoft, lineWidth: 0.5))
      }
      .padding(.horizontal, 12).padding(.top, 8).padding(.bottom, 8)
  }

  private var editBar: some View {
    HStack(spacing: 0) {
      Button(selection.count == symbols.count ? "全不选" : "全选") {
        selection = selection.count == symbols.count ? [] : Set(symbols)
      }.foregroundStyle(theme.amber)
      Spacer(minLength: 0)
      Button("移到分组") { moving = MoveRequest(symbols: Array(selection)) }
        .disabled(selection.isEmpty)
        .foregroundStyle(selection.isEmpty ? skin.ink4 : theme.amber)
      Spacer(minLength: 0)
      Button("删除", role: .destructive) {
        selection.forEach { model.removeFavorite($0) }; selection.removeAll()
      }.disabled(selection.isEmpty)
        .foregroundStyle(selection.isEmpty ? skin.ink4 : theme.down)
    }
    .buttonStyle(.plain)
    .font(.system(size: 13, weight: .semibold))
    .padding(.horizontal, 20).frame(height: 52)
    .background(skin.glass, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(skin.edgeSoft, lineWidth: 0.5))
    .overlay(alignment: .top) { skin.topHighlight(inset: 9) }
    .padding(.horizontal, 12).padding(.bottom, 8)
  }
}

// MARK: - 派生色板

/// 「琉璃」用到的所有材质与光，全部从当前皮肤种子推出来。
///
/// 浅色的底与光斑是唯一的例外：用户定的「天青 · 薄荷」，不是皮肤原色——
/// 皮肤原色在浅底上糊成一片，冷光才托得住玻璃。
private struct LiuliSkin {
  let theme: PanelTheme
  var seed: PaletteSeed { theme.seed }
  var dark: Bool { theme.dark }
  private var warm: Bool { Palette.isWarm(seed) }

  private static let sageGround: Hex = "#E9F3F1"
  private static let terraGround: Hex = "#F4EFEA"
  private static let sageLobes: [Hex] = ["#A9DDF3", "#BFEFD6", "#DCEFF6"]
  private static let terraLobes: [Hex] = ["#B5D9F1", "#F5D8C3", "#D3EDE0"]

  var ground: Color {
    dark ? Color(hex: seed.ground) : Color(hex: warm ? Self.terraGround : Self.sageGround)
  }
  var lobes: [Color] {
    dark ? [accent, accentLift, Color(hex: seed.amber)]
         : (warm ? Self.terraLobes : Self.sageLobes).map { Color(hex: $0) }
  }
  /// 第三团是 amber。深色下它和青苔的墨绿差着一个色系，按 55% 铺出来会在屏幕
  /// 下半截烧出一块橘斑，收到 34% 才只剩「墙角一点暖」。
  func lobeOpacity(_ index: Int) -> Double {
    guard dark else { return 0.9 }
    return index == 2 ? 0.34 : 0.55
  }
  var grainOpacity: Double { dark ? 0.05 : 0.035 }

  var accent: Color { Color(hex: seed.accent) }
  var accentLift: Color { Self.lift(seed.accent, 0.42) }
  /// 液态药丸：acc2 → acc。
  var accentGradient: LinearGradient {
    LinearGradient(colors: [accentLift, accent], startPoint: .topLeading, endPoint: .bottomTrailing)
  }
  /// 玻璃：深色借近白的墨色，浅色借 `raised`（两套浅色种子的 raised 都是白）。
  private var pane: Color { Color(hex: dark ? seed.ink : seed.raised) }
  var glass: Color { pane.opacity(dark ? 0.065 : 0.64) }
  var glassThin: Color { pane.opacity(dark ? 0.045 : 0.46) }
  var edgeSoft: Color { pane.opacity(dark ? 0.12 : 0.62) }
  var rule: Color { Color(hex: seed.ink).opacity(dark ? 0.11 : 0.09) }
  /// 比 ink3 再弱一档，给上标数字、单位、微标签。
  var ink4: Color { Color(hex: seed.ink3).opacity(0.7) }

  /// 玻璃顶上那一线高光。
  func topHighlight(inset: CGFloat) -> some View {
    Capsule().fill(pane.opacity(dark ? 0.3 : 0.9))
      .frame(height: 1).padding(.horizontal, inset)
  }

  /// 标题字体。原型上是宋体，但 iOS 装机量里没有任何一支简体中文衬线体可用——
  /// `UIFont.familyNames` 里既没有 Songti SC 也没有 Kaiti SC，New York 只管拉丁字母，
  /// 唯一在机的明朝体 Hiragino Mincho ProN 缺「选」「这」「栏」这些简体字，混排会崩。
  /// 既然说好了不打包字体文件，这里就老实用 `.serif`：拉丁走 New York，中文走系统字，
  /// 靠字号与字距把标题撑起来。
  func serif(_ size: CGFloat) -> Font { .system(size: size, weight: .medium, design: .serif) }

  func lift(_ hex: Hex, _ amount: Double) -> Color { Self.lift(hex, amount) }

  /// 往亮里提一档：色相不动，饱和收一点、明度往上走——原型里 acc2 和 acc 的关系。
  private static func lift(_ hex: Hex, _ amount: Double) -> Color {
    let rgba = hex.rgba
    var h: CGFloat = 0, s: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
    UIColor(red: rgba.r, green: rgba.g, blue: rgba.b, alpha: 1)
      .getHue(&h, saturation: &s, brightness: &b, alpha: &a)
    return Color(hue: Double(h), saturation: Double(s) * (1 - amount * 0.6),
                 brightness: Double(b) + (1 - Double(b)) * amount)
  }
}

// MARK: - 底：三团会动的光

private struct AuroraBackdrop: View {
  let skin: LiuliSkin
  let reduceMotion: Bool
  @State private var drift = false

  var body: some View {
    GeometryReader { geometry in
      let width = geometry.size.width, height = geometry.size.height
      ZStack(alignment: .topLeading) {
        skin.ground
        lobe(0, size: 300, x: -95, y: -80, seconds: 22)
        lobe(1, size: 250, x: width - 170, y: 240, seconds: 27)
        lobe(2, size: 280, x: -70, y: height - 230, seconds: 31)
        if let grain = Grain.image {
          grain.resizable(resizingMode: .tile).opacity(skin.grainOpacity)
        }
      }
      .frame(width: width, height: height)
    }
    .allowsHitTesting(false)
    .onAppear { if !reduceMotion { drift = true } }
  }

  /// 漂移只动 `offset` / `scale`，交给渲染线程去跑，不会让列表每帧重建。
  private func lobe(_ index: Int, size: CGFloat, x: CGFloat, y: CGFloat, seconds: Double) -> some View {
    let color = skin.lobes[index]
    let peak = skin.lobeOpacity(index)
    return RadialGradient(
      gradient: Gradient(stops: [
        .init(color: color.opacity(peak), location: 0),
        .init(color: color.opacity(peak * 0.55), location: 0.45),
        .init(color: color.opacity(0), location: 1)]),
      center: .center, startRadius: 0, endRadius: size / 2)
      .frame(width: size, height: size)
      .scaleEffect(drift ? 1.08 : 1)
      .offset(x: x + (drift ? 18 : 0), y: y + (drift ? -26 : 0))
      .animation(reduceMotion ? nil
                 : .easeInOut(duration: seconds).repeatForever(autoreverses: true), value: drift)
  }
}

/// 一张 96×96 的灰噪点，平铺当颗粒。只生成一次。
@MainActor private enum Grain {
  static let image: Image? = {
    let side = 96
    var bytes = [UInt8](repeating: 0, count: side * side)
    var state: UInt64 = 0x2545_F491_4F6C_DD1D
    for index in bytes.indices {
      state ^= state << 13; state ^= state >> 7; state ^= state << 17
      bytes[index] = UInt8(truncatingIfNeeded: state >> 33)
    }
    guard let provider = CGDataProvider(data: Data(bytes) as CFData),
          let image = CGImage(width: side, height: side, bitsPerComponent: 8, bitsPerPixel: 8,
                              bytesPerRow: side, space: CGColorSpaceCreateDeviceGray(),
                              bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.none.rawValue),
                              provider: provider, decode: nil, shouldInterpolate: false,
                              intent: .defaultIntent) else { return nil }
    return Image(decorative: image, scale: 1)
  }()
}

// MARK: - 走势线与小三角

private struct Sparkline: View {
  let values: [Double]
  let color: Color

  var body: some View {
    GeometryReader { geometry in
      let size = geometry.size
      let points = points(in: size)
      if points.count > 1 {
        ZStack {
          shape(points, closing: size.height).fill(
            LinearGradient(colors: [color.opacity(0.28), color.opacity(0)],
                           startPoint: .top, endPoint: .bottom))
          shape(points, closing: nil).stroke(
            color, style: StrokeStyle(lineWidth: 1.4, lineCap: .round, lineJoin: .round))
          if let last = points.last {
            Circle().fill(color).opacity(0.18).frame(width: 10, height: 10).position(last)
            Circle().fill(color).frame(width: 4.4, height: 4.4).position(last)
          }
        }
      }
    }.accessibilityHidden(true)
  }

  private func points(in size: CGSize) -> [CGPoint] {
    guard values.count > 1 else { return [] }
    let low = values.min() ?? 0, high = values.max() ?? 0
    let span = high - low
    return values.enumerated().map { index, value in
      let ratio = span == 0 ? 0.5 : (value - low) / span
      return CGPoint(x: CGFloat(index) / CGFloat(values.count - 1) * (size.width - 4) + 2,
                     y: size.height - 3 - CGFloat(ratio) * (size.height - 7))
    }
  }

  private func shape(_ points: [CGPoint], closing bottom: CGFloat?) -> Path {
    var path = Path()
    path.move(to: points[0])
    for point in points.dropFirst() { path.addLine(to: point) }
    if let bottom, let last = points.last {
      path.addLine(to: CGPoint(x: last.x, y: bottom))
      path.addLine(to: CGPoint(x: points[0].x, y: bottom))
      path.closeSubpath()
    }
    return path
  }
}

private struct Triangle: Shape {
  let up: Bool
  func path(in rect: CGRect) -> Path {
    var path = Path()
    if up {
      path.move(to: CGPoint(x: rect.midX, y: rect.minY))
      path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
      path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
    } else {
      path.move(to: CGPoint(x: rect.midX, y: rect.maxY))
      path.addLine(to: CGPoint(x: rect.minX, y: rect.minY))
      path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
    }
    path.closeSubpath()
    return path
  }
}

/// Keep category controls independent of row-price refreshes.
/// Keep the header's identity tied to folders/editing/theme, not row prices.
private struct FavoritesHeader<Content: View>: View, Equatable {
  let prefs: SymbolPrefs
  let editing: Bool
  let more: Bool
  let theme: PanelTheme
  let width: CGFloat
  let content: Content
  nonisolated static func == (lhs: Self, rhs: Self) -> Bool {
    lhs.prefs == rhs.prefs && lhs.editing == rhs.editing && lhs.more == rhs.more
      && lhs.theme == rhs.theme && lhs.width == rhs.width
  }
  var body: some View { content }
}
