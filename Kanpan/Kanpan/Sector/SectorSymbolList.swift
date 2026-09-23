import KanpanChart
import SwiftUI
import KanpanCore

/// 第二层：某一个板块里的品种。
///
/// 视觉照抄自选页（`FavoritesView.row(_:first:)`）——同样的 66 高、同样的徽章、
/// 同样的两端渐隐发丝线、同样的价格与涨跌药丸。用户点过名：这儿要的是自选页那张
/// 列表，不是浮在板块页上的胶囊卡片。
///
/// 底还是 `SectorBackdrop`，和板块列表同一块材料；不加玻璃纸（自选页 2026-09-17
/// 起已经改成「融合」）。
struct SectorSymbolList: View {
  var stat: SectorStat
  /// 板块成员（大写 base）。兜底桶也走这条路。
  var members: [String]
  var quotes: [String: SectorQuote]
  /// 看今日还是看 5 日。大数字、每行的涨跌、领涨、以及「涨跌幅」那颗排序都跟着它。
  var window: SectorWindow = .today
  /// 日线收盘。今日那一档用不着。
  var history: SectorHistory = .empty
  /// 这个板块的 20 日中位数。只在 5 日那一档、且真有 20 日数据时才有值。
  var medianD20: Double?
  var symbolForBase: (String) -> String
  /// 这个 base 对应品种的价格小数位。品种表还没到就返回 nil（见 `SectorSymbolRow.priceText`）。
  var decimalsForBase: (String) -> Int? = { _ in nil }
  /// 这张列表按什么排，存在哪。见 `sort`。
  var store: PrefsStore
  var onBack: () -> Void
  /// 点中一行：交出完整 symbol。
  var onPick: (String) -> Void
  /// 点进图表的那一刻把**这张表当时的顺序**交出去，供顶栏横滑连续扫图（§10.1）。
  /// 顺序是 `SectorSymbolRow.build` 按当前排序口径现算的，外面拿不到，只能这儿递。
  var onScanList: ([String]) -> Void = { _ in }
  /// 列表摆出来（以及排在最前面的那几只换了）时交出前几行的完整 symbol，宿主拿去预取
  /// K 线；列表收起时叫 `onRowsHidden` 撤掉。点进去的那一只第一帧就有图。
  var onRowsShown: ([String]) -> Void = { _ in }
  var onRowsHidden: () -> Void = {}
  /// 长按一行时那张预览卡的 K 线与统计（§4.1）。没接线就不做长按预览。
  var previews: SymbolPreviewStore?
  /// 长按菜单里动自选的那几项要它。没接线时菜单里只剩「打开」。
  var picker: SymbolPickerModel?

  @Environment(\.panelTheme) private var theme
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  /// 系统字号超过默认档时头部副文案放开到两行；默认档仍是原来的一行。
  @Environment(\.dynamicTypeSize) private var dynamicTypeSize

  private var skin: SectorSkin { SectorSkin(theme: theme) }
  /// 这张列表按什么排。原来是裸 `@AppStorage("sector.sort")`，跟着这台机器走；
  /// 2026-09-19 按「用手改过的状态跟着人走」搬进 `Prefs.sectorSort`，随账号同步。
  /// 认不出的字面量（降级回旧版本、手改存档）退回出厂的「涨跌幅」。
  private var sort: SectorSymbolSort {
    get { SectorSymbolSort(rawValue: store.prefs.sectorSort) ?? .change }
    nonmutating set { store.update { $0.sectorSort = newValue.rawValue } }
  }

  var body: some View {
    let rows = SectorSymbolRow.build(members: members, quotes: quotes,
                                     symbolForBase: symbolForBase,
                                     decimalsForBase: decimalsForBase,
                                     frontier: Set(stat.frontier), sort: sort,
                                     window: window, history: history)
    return VStack(spacing: 0) {
      header
      sortBar(rows.count)
      ScrollView {
        LazyVStack(spacing: 0) {
          ForEach(Array(rows.enumerated()), id: \.element.id) { index, item in
            // 冻结名单和开图是同一下：先递出这一刻的顺序，再照常交出 symbol。
            previewable(item, row(item, first: index == 0) { symbol in
              onScanList(rows.map(\.symbol)); onPick(symbol)
            }) { onScanList(rows.map(\.symbol)); onPick($0) }
          }
        }
        .padding(.top, 6).padding(.bottom, 8)
      }
      .scrollIndicators(.hidden)
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    // 这一层底下还铺着板块列表。落在头部空处的点要在这儿吃掉，不然会穿下去点着底下那一行。
    .contentShape(Rectangle())
    .onTapGesture { }
    .background { SectorBackdrop(skin: skin, reduceMotion: reduceMotion).ignoresSafeArea() }
    // 先成组再挂 id，否则这个 id 会盖掉底下每一行自己的（见 `SectorPage`）。
    .accessibilityElement(children: .contain)
    .accessibilityIdentifier("sector.list")
    .onChange(of: rows.prefix(Self.prefetchRows).map(\.symbol), initial: true) { _, top in onRowsShown(top) }
    .onDisappear { onRowsHidden() }
  }

  /// 预取前几行。一屏大约能看到八九行，多了是替用户猜，拖慢正在看的那一只。
  static let prefetchRows = 10

  // MARK: - 头

  /// 原型 `enterList()`：返回、记号、板块名、一行副文案，右边是聚合涨跌幅。
  ///
  /// 副文案 `17 个品种 · 14/17 跑赢大盘 · 成交额 4.86B` 和板块列表每行的完全同一格式
  /// （同一个 `SectorSubtitle`）。「跑赢大盘」几家说的是整体在动还是一只在爆——右边那个大字只说动了多少，这两件事
  /// 分不开。涨跌幅不在这行重写一遍（右边已经有了），分母是有行情的成员数，
  /// 页面上不出现算法名，也不出现目录登记数。
  ///
  /// 看 5 日的时候最后一段换成「20 日 +12.1%」：两段窗口摆在一起，才知道这一周的劲
  /// 是刚起来的还是月线上一直就有。20 日只在这儿出现一次，不做成第三颗药丸。
  /// 没有 20 日数据就只剩前两段——不写「暂无」，也不解释；成交额拿不到时那一段
  /// 也是整个不写（`sectorVolumeClause`），不排一句「成交额 —」。
  private var subtitle: String {
    let tail: String = if window == .d5 {
      medianD20.map { " · 20 日 " + sectorPctText($0) } ?? ""
    } else {
      sectorVolumeClause(stat.quoteVolume)
    }
    return SectorSubtitle.text(stat, tail: tail)
  }

  private var header: some View {
    HStack(spacing: 6) {
      SectorBackButton(skin: skin, id: "sector.list.back", action: onBack)
      if let art = SectorIcons.art(stat.id) {
        SectorIconView(art: art, size: 38)
      }
      VStack(alignment: .leading, spacing: 2) {
        Text(stat.name).font(skin.serif(19)).tracking(0.76).foregroundStyle(theme.ink)
          .lineLimit(1).minimumScaleFactor(0.7)
        Text(subtitle)
          .font(.scaled(11)).monospacedDigit().tracking(0.2)
          .foregroundStyle(skin.ink4)
          .lineLimit(dynamicTypeSize > .large ? 2 : 1).minimumScaleFactor(0.6)
          .accessibilityIdentifier("sector.list.breadth")
      }
      .padding(.leading, 5)
      Spacer(minLength: 8)
      Text(sectorPctText(stat.pct))
        .font(.scaled(19, .medium)).monospacedDigit()
        .foregroundStyle(stat.pct >= 0 ? theme.up : theme.down)
    }
    .padding(.leading, 15).padding(.trailing, 20).padding(.top, 6)
  }

  private func sortBar(_ count: Int) -> some View {
    HStack(spacing: 7) {
      ForEach(SectorSymbolSort.allCases, id: \.rawValue) { sortChip($0) }
      Spacer(minLength: 0)
      Text("\(count) 个")
        .font(.scaled(10.5, design: .monospaced)).tracking(0.63)
        .foregroundStyle(skin.ink4)
    }
    .padding(.horizontal, 20).padding(.top, 10)
  }

  private func sortChip(_ value: SectorSymbolSort) -> some View {
    let on = sort == value
    return Button { sort = value } label: {
      Text(value.title).font(.scaled(11.5)).tracking(0.23)
        .foregroundStyle(on ? theme.ink : theme.ink3)
        .padding(.horizontal, 10).frame(height: 25)
        .background {
          Capsule().fill(on ? skin.chipOn : Color.clear)
            .overlay(Capsule().strokeBorder(on ? skin.chipEdge : skin.rule, lineWidth: 0.5))
        }
        .contentShape(Capsule())
    }.buttonStyle(.plain)
      .accessibilityLabel(value.title)
      .accessibilityAddTraits(on ? .isSelected : [])
      .accessibilityIdentifier("sector.sort." + value.rawValue)
  }

  // MARK: - 长按预览

  /// 和自选页同一张卡、同一份菜单（`FavoritesView.previewable`）。差别有两处：
  /// 这儿的品种多半还不在自选里，所以那一项是「加入自选」而不是「取消自选」——
  /// 看板块就是在挑东西，挑中了顺手收走，不用先切回自选页再搜一遍；另一处是
  /// 没有「调整顺序」，这张表的顺序归排序口径管，本来就不是手排的。
  @ViewBuilder private func previewable(_ item: SectorSymbolRow, _ content: some View,
                                        open: @escaping (String) -> Void) -> some View {
    if let previews {
      content.contextMenu {
        Button("打开") { open(item.symbol) }
        if let picker {
          if picker.isFavorite(item.symbol) {
            if !picker.prefs.groups.isEmpty {
              Menu("移到分类") {
                ForEach(picker.prefs.groups) { group in
                  Button(group.name) { move(item.symbol, to: group, picker) }
                }
              }
            }
            Button("取消自选", role: .destructive) { unfavorite(item.symbol, picker) }
          } else {
            Button("加入自选") { picker.addFavorite(item.symbol, info: picker.info(for: item.symbol)) }
          }
        }
      } preview: {
        SymbolPreviewCard(symbol: item.symbol, info: picker?.info(for: item.symbol),
                          ticker: previewTicker(item), store: previews)
          .environment(\.panelTheme, theme)
      }
    } else {
      content
    }
  }

  /// 移到分类、取消自选都和自选页一样给五秒反悔（P2.7），说在全 app 那唯一一条提示上。
  private func move(_ symbol: String, to group: FavoriteGroup, _ picker: SymbolPickerModel) {
    guard let before = picker.favoriteSnapshot(symbol), before.group != group.id else { return }
    picker.assign(symbol, to: group.id)
    ToastCenter.shared.say("已移到「\(group.name)」") { picker.assign(before.symbol, to: before.group) }
  }

  private func unfavorite(_ symbol: String, _ picker: SymbolPickerModel) {
    guard let before = picker.favoriteSnapshot(symbol) else { return }
    Haptics.warning()
    picker.removeFavorite(symbol)
    ToastCenter.shared.say("已移除") { picker.restoreFavorites([before]) }
  }

  /// 卡上那几格要一份 `Ticker`。板块页手里是 `SectorQuote`，价和涨跌照这一行写的来
  /// （看 5 日时这一行写的就是 5 日），成交额是 24h 的那份。高低价这趟没取回来，
  /// 卡上也不摆，留 NaN。
  private func previewTicker(_ item: SectorSymbolRow) -> Ticker {
    Ticker(symbol: item.symbol, last: item.price, changePercent: item.pct,
           high: .nan, low: .nan, quoteVolume: item.quoteVolume)
  }

  // MARK: - 行（照抄自选页）

  private func row(_ item: SectorSymbolRow, first: Bool, open: @escaping (String) -> Void) -> some View {
    HStack(spacing: 10) {
      badge(item.base)
      VStack(alignment: .leading, spacing: 4) {
        HStack(alignment: .firstTextBaseline, spacing: 3) {
          Text(item.base).font(.scaled(13.5, .semibold)).foregroundStyle(theme.ink)
          Text(item.quoteText).font(.scaled(9)).foregroundStyle(skin.ink4)
        }.lineLimit(1).minimumScaleFactor(0.75)
        // 自选页那行是「额 … · 幅 …」，振幅要 24h 高低价，全市场 ticker 的那一趟
        // 里没带回来，所以这儿只留成交额，排版和字号一模一样。
        //
        // 前沿成员的「领涨」就接在成交额后面，同一个分隔点、同一个字号，只换涨色：
        // `额 3.05M · 领涨`。悬在名字和价格中间的空档里它像掉在那儿的。
        HStack(spacing: 0) {
          Text("额 " + item.volumeText)
            .font(.scaled(10)).monospacedDigit().foregroundStyle(theme.ink3)
          if item.isFrontier {
            Text(" · 领涨")
              .font(.scaled(10)).tracking(0.3)
              .foregroundStyle(theme.up)
              .accessibilityIdentifier("sector.frontier." + item.symbol)
          }
        }.lineLimit(1).minimumScaleFactor(0.8)
      }.frame(maxWidth: .infinity, alignment: .leading)
      quote(item)
    }
    .padding(.leading, 19).padding(.trailing, 20)
    .frame(height: 66)
    .contentShape(Rectangle())
    .onTapGesture { open(item.symbol) }
    .overlay(alignment: .top) {
      if !first { SectorHairline(skin: skin) }
    }
    .accessibilityElement(children: .contain)
    .accessibilityAddTraits(.isButton)
    .accessibilityIdentifier("sector.open." + item.symbol)
    .accessibilityAction { open(item.symbol) }
  }

  /// 徽章：品牌色晕 + `CoinBadge` + 一圈角向高光。和自选页同一支。
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

  /// 右边一列：价 + 涨跌药丸。尺寸全部照自选页。
  private func quote(_ item: SectorSymbolRow) -> some View {
    let tint = item.pct.isFinite ? (item.isUp ? theme.up : theme.down) : skin.ink4
    return VStack(alignment: .trailing, spacing: 5) {
      Text(item.priceText)
        .font(.scaled(15.5, .medium)).monospacedDigit()
        .lineLimit(1).minimumScaleFactor(0.7)
        .foregroundStyle(theme.ink)
        .accessibilityIdentifier("sector.price." + item.symbol)
      HStack(spacing: 4) {
        if item.pct.isFinite {
          SectorTriangle(up: item.isUp).fill(tint).frame(width: 6, height: 5)
            .accessibilityHidden(true)
        }
        Text(item.changeText)
          .font(.scaled(11, .semibold)).monospacedDigit()
          .foregroundStyle(tint)
          .accessibilityLabel(item.signedText)
          .accessibilityIdentifier("sector.change." + item.symbol)
      }
      .padding(.horizontal, 7).frame(minHeight: 19).frame(minWidth: 54)
      .background {
        RoundedRectangle(cornerRadius: 7, style: .continuous)
          .fill(tint.opacity(0.14))
          .overlay(RoundedRectangle(cornerRadius: 7, style: .continuous)
            .strokeBorder(tint.opacity(0.3), lineWidth: 0.5))
      }
    }.frame(minWidth: 86, alignment: .trailing)
  }
}
