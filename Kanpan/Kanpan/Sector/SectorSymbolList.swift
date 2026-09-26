import SwiftUI
import KanpanCore

/// 第二层：某一个板块里的品种。
///
/// 视觉就是自选页那一行——现在是同一个 `LiuliSymbolRow`（UI 审查 2026-09-24 把两份手抄
/// 收成一份）：同样的 66 高、同样的徽章、同样的两端渐隐发丝线、同样的价格与涨跌药丸。
/// 用户点过名：这儿要的是自选页那张列表，不是浮在板块页上的胶囊卡片。
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
  /// 上一层口径重算过几次（`SectorPage` 递 `SectorMemo.computations`）。品种表换了之后
  /// 全名与小数位跟着变，但那两个闭包读的是行情源里按代次缓存的索引、观察不到，
  /// 靠这个戳让这一层也重排。
  var inputs: Int = 0

  @Environment(\.panelTheme) private var theme
  @Environment(\.accessibilityReduceMotion) private var reduceMotion

  private var skin: SectorSkin { SectorSkin(theme: theme) }
  /// 这张列表按什么排。原来是裸 `@AppStorage("sector.sort")`，跟着这台机器走；
  /// 2026-09-19 按「用手改过的状态跟着人走」搬进 `Prefs.sectorSort`，随账号同步。
  /// 认不出的字面量（降级回旧版本、手改存档）退回出厂的「涨跌幅」。
  private var sort: SectorSymbolSort {
    get { SectorSymbolSort(rawValue: store.prefs.sectorSort) ?? .change }
    nonmutating set { store.update { $0.sectorSort = newValue.rawValue } }
  }

  /// 排好的行按输入缓存（压测 L1）。以前 body 每跑一次都把成员逐个取价、算窗口涨跌、
  /// 排序、格式化重做一遍，而滚动预取、长按、偏好里别的字段变动都会让 body 重跑。
  @State private var rowMemo = SectorMemo<RowsKey, [SectorSymbolRow]>()

  /// 决定这张表长什么样的全部输入。行情只取成员自己那几只：别的板块的价跳了，
  /// 这张表不用重排。
  struct RowsKey: Equatable {
    var members: [String]
    var quotes: [SectorQuote?]
    var frontier: [String]
    var sort: SectorSymbolSort
    var window: SectorWindow
    var history: SectorHistory
    var inputs: Int
  }

  static func rowsKey(members: [String], quotes: [String: SectorQuote], frontier: [String],
                      sort: SectorSymbolSort, window: SectorWindow, history: SectorHistory,
                      inputs: Int) -> RowsKey {
    RowsKey(members: members, quotes: members.map { quotes[$0] }, frontier: frontier,
            sort: sort, window: window, history: history, inputs: inputs)
  }

  var body: some View {
    let sort = sort
    let key = Self.rowsKey(members: members, quotes: quotes, frontier: stat.frontier,
                           sort: sort, window: window, history: history, inputs: inputs)
    let rows = rowMemo.value(for: key) {
      SectorSymbolRow.build(members: members, quotes: quotes,
                            symbolForBase: symbolForBase,
                            decimalsForBase: decimalsForBase,
                            frontier: Set(stat.frontier), sort: sort,
                            window: window, history: history)
    }
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
        .padding(.bottom, Space.s)
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
    HStack(spacing: Space.s) {
      SectorBackButton(skin: skin, id: "sector.list.back", action: onBack)
        // 返回键的点击区比圆盘大，左半截伸进页边距里，圆盘仍贴着页面左边那条竖线。
        .padding(.leading, -SectorBackButton.overhang)
      if let art = SectorIcons.art(stat.id) {
        SectorIconView(art: art, size: 38)
      }
      VStack(alignment: .leading, spacing: Space.xxs) {
        // 页标题 17 semibold（UI 审查：页标题原有无 / 15 / 19 三种，统一到 17）。
        Text(stat.name).font(TypeScale.title).foregroundStyle(theme.ink)
          .lineLimit(1).minimumScaleFactor(0.8)
        // 副文案 11 是下限，不再缩到 0.6 倍（6.6pt）挤进一行；放不下就折到第二行。
        Text(subtitle)
          .font(TypeScale.caption2).monospacedDigit()
          .foregroundStyle(skin.ink4)
          .lineLimit(2)
          .fixedSize(horizontal: false, vertical: true)
          .accessibilityIdentifier("sector.list.breadth")
      }
      Spacer(minLength: Space.s)
      Text(sectorPctText(stat.pct))
        .font(Self.headlinePct).monospacedDigit()
        .foregroundStyle(stat.pct >= 0 ? theme.up : theme.down)
    }
    .pageHorizontalInset()
    .padding(.top, Space.s)
  }

  /// 头部右边那个聚合涨跌幅：和页标题同一档（17），medium（原 19，不在阶梯上）。
  private static let headlinePct = ScaledFont(TypeScale.title.size, .medium, relativeTo: .headline)

  private func sortBar(_ count: Int) -> some View {
    // 排序小块和搜索页历史词、品种整页筛选同一种（`SymbolChip`）：看得见 28、点击区 44。
    HStack(spacing: Space.s) {
      ForEach(SectorSymbolSort.allCases, id: \.rawValue) { value in
        SymbolChip(title: value.title, selected: sort == value) { sort = value }
          .accessibilityIdentifier("sector.sort." + value.rawValue)
      }
      Spacer(minLength: 0)
      Text("\(count) 个")
        .font(TypeScale.caption2).monospacedDigit()
        .foregroundStyle(skin.ink4)
    }
    .pageHorizontalInset()
    .padding(.top, Space.xxs)
  }

  // MARK: - 长按预览

  /// 和自选页同一张卡，菜单是它的子集：「打开」加一颗收藏开关。
  /// 这儿的品种多半还不在自选里，所以那一项平时是「加入自选」——看板块就是在挑东西，
  /// 挑中了顺手收走，不用先切回自选页再搜一遍；已经在自选里的写「取消自选」。
  /// 没有「调整顺序」（这张表的顺序归排序口径管），也没有「移到分类」——2026-09-24
  /// 收拢入口（审查 U8）：移到分类只在自选页上做（左滑、长按菜单两处），分类本来就是
  /// 那一页的东西，在板块里改了也看不见改到了哪儿。
  @ViewBuilder private func previewable(_ item: SectorSymbolRow, _ content: some View,
                                        open: @escaping (String) -> Void) -> some View {
    if let previews {
      content.contextMenu {
        Button("打开") { open(item.symbol) }
        if let picker {
          if picker.isFavorite(item.symbol) {
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

  /// 取消自选和自选页一样给五秒反悔（P2.7），说在全 app 那唯一一条提示上。
  private func unfavorite(_ symbol: String, _ picker: SymbolPickerModel) {
    guard let before = picker.favoriteSnapshot(symbol) else { return }
    Haptics.warning()
    picker.removeFavorite(symbol)
    ToastCenter.shared.say("已移除", undo: picker.undoable { picker.restoreFavorites([before]) })
  }

  /// 卡上那几格要一份 `Ticker`。板块页手里是 `SectorQuote`，价和涨跌照这一行写的来
  /// （看 5 日时这一行写的就是 5 日），成交额是 24h 的那份。高低价这趟没取回来，
  /// 卡上也不摆，留 NaN。
  private func previewTicker(_ item: SectorSymbolRow) -> Ticker {
    Ticker(symbol: item.symbol, last: item.price, changePercent: item.pct,
           high: .nan, low: .nan, quoteVolume: item.quoteVolume)
  }

  // MARK: - 行（和自选页同一行）

  private func row(_ item: SectorSymbolRow, first: Bool, open: @escaping (String) -> Void) -> some View {
    // 品种表到了才认得出资产类别和「新」；没到就按代号画徽章、不标新，和自选页同一个退路。
    let info = picker?.info(for: item.symbol)
    return LiuliSymbolRow(
      symbol: item.symbol, base: item.base, quote: item.quoteText,
      asset: info.map { SymbolClassifier.classify($0).asset },
      isNew: NewListingMark.shows(info),
      first: first,
      priceText: item.priceText, priceID: "sector.price." + item.symbol,
      change: item.pct, changeText: item.signedText, changeID: "sector.change." + item.symbol,
      openID: "sector.open." + item.symbol, onOpen: { open(item.symbol) }
    ) {
      // 自选页那行是「成交额 … · 振幅 …」，振幅要 24h 高低价，全市场 ticker 的那一趟
      // 里没带回来，所以这儿只留成交额，写法和字号一模一样（原来这儿写的是「额」）。
      //
      // 前沿成员的「领涨」就接在成交额后面，同一个分隔点、同一个字号，只换涨色：
      // `成交额 3.05M · 领涨`。悬在名字和价格中间的空档里它像掉在那儿的。
      HStack(spacing: 0) {
        Text("成交额 " + item.volumeText).foregroundStyle(theme.ink3)
        if item.isFrontier {
          Text(SymbolRowText.separator + "领涨")
            .foregroundStyle(theme.up)
            .accessibilityIdentifier("sector.frontier." + item.symbol)
        }
      }
    } accessory: {
      EmptyView()
    }
  }
}
