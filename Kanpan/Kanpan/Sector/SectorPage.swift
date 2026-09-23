import SwiftUI
import UIKit
import KanpanCore

/// 板块气泡页 ——「釉珠」整页外壳。
///
/// 底栏第四格进来的就是这一张页，它自己不做任何计算：口径在 `KanpanCore`
/// （`SectorAggregator` / `SectorSelector`），球画在 `SectorBubbleField` 里，
/// 记号在 `SectorIcon.swift`，行情由 `SectorFeed` 喂进来。这一层只负责把它们
/// 摆到同一张纸上，再管三段导航。
///
/// 三段，中间不弹任何详情浮层（用户 2026-09-18 定稿）：
///
///   一层气泡（板块）──点一颗─→ 该板块的品种列表 ──点一行─→ 行情页（宿主接手）
///
/// 没上场的板块不在气泡页上另起一块界面，只走右上角「…」→「全部板块」整页清单；
/// 兜底桶只出现在那张清单里，并且和普通板块画得一模一样。
///
/// 两个市场（加密 / 美股）是**硬切换**：各自一套基准、各自的 N/M、各自的尺子、
/// 各自的统计行，永远不共处一屏，也不为美股再开一格底栏。
struct SectorPage: View {
  /// 行情。页面只读它，并在出现 / 消失时开关它的轮询。
  var feed: SectorFeed
  /// 红涨绿跌。球身两头的色相交换只由它决定，别的什么都不改。
  var redUp: Bool
  /// 釉珠的可调参数。默认就是原型定稿那一组。
  var knobs: SectorFieldKnobs = .default
  /// 大写 base → 完整合约代号。板块聚合一路只认 base（分类表里记的就是代号），
  /// 但开行情页要的是 `BTCUSDT` 这样的全名。默认按 USDT 本位拼，宿主手里有品种表，
  /// 传一个照表查的实现能把 USDC 本位那几个也认对。
  var symbolForBase: (String) -> String = { $0 + "USDT" }
  /// 这一页上「他摆出来的样子」存在哪：停在哪个市场、看今日还是 5 日，
  /// 以及下钻那层品种列表按什么排。
  var store: PrefsStore
  /// 点中一行品种：交出完整 symbol（如 `BTCUSDT`），由 `MainScreen` 切过去。
  var onPickSymbol: (String) -> Void
  /// 下钻那层品种列表点进图表时，把那一刻列表的顺序交出去（连续扫图，§10.1）。
  var onScanList: ([String]) -> Void = { _ in }
  /// 下钻那层品种列表摆出来 / 收起来。宿主拿前几行去预取 K 线（见 `SectorSymbolList.onRowsShown`）。
  var onListShown: ([String]) -> Void = { _ in }
  var onListHidden: () -> Void = {}
  /// 下钻那层品种列表长按一行时，预览卡的 K 线与统计从这儿来（§4.1）。
  var previews: SymbolPreviewStore?
  /// 长按菜单里那几项自选动作要它。
  var picker: SymbolPickerModel?

  @Environment(\.panelTheme) private var theme
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @Environment(\.dynamicTypeSize) private var dynamicTypeSize
  /// 压在气泡页上面的那几层。空 = 只有球场。最多两层（全部板块 → 某板块的品种列表）。
  ///
  /// 它由宿主（`MainScreen`）持有：底栏是常驻标签栏，这一页每切走一次就整个重建，
  /// 存在自己身上的 `@State` 会跟着死掉——下钻到品种列表、点进行情页再返回，
  /// 人就被扔回球场了。挪到宿主手里，来回一趟才回得到原来那一层。
  @Binding var route: [SectorRoute]
  /// 「5 日」要的日线收盘。取不到就是空，页面回到只有今日的样子，不提示。
  @State private var historyFeed = SectorHistoryFeed()
  /// 面积分母的迟滞记忆。
  ///
  /// 它必须活过一次次重画，又不能是 `@State` 的值类型——`snapshot()` 是在 `body`
  /// 里算的，在那儿写 `@State` 会把视图再拍一遍。装在一个不被观察的盒子里，
  /// 只当上一次的读数用。换市场时清空：两个市场各有各的尺子。
  @State private var scaleMemo = ScaleMemo()

  /// 每个窗口一把尺子。今日跳 3% 是大事，5 日跳 3% 不是；两档共用一个分母会让
  /// 切过去的第一屏球整体大一圈或小一圈，然后再慢慢缩回来。
  private final class ScaleMemo { var values: [String: Double] = [:] }

  private var skin: SectorSkin { SectorSkin(theme: theme) }
  /// 停在哪个市场。
  ///
  /// 这两项原来是裸 `@AppStorage`，注释写的是「记在本机——这是『上次看到哪儿』，
  /// 不是需要跟账号走的偏好」。**2026-09-19 推翻**：判据是「这是他改出来的习惯，
  /// 还是这个对象自己的属性」，「我看的是加密不是美股」「我看 5 日不看今日」都是
  /// 前者。跟着机器走的后果是两头都反了——换台设备登同一个账号全回出厂值，
  /// 同一台机器上换个人登进来又还停在上一个人看的那一档。现在进 `Prefs`
  /// （`sectorMarket` / `sectorWindow`），随账号同步，未登录记在访客档案。
  private var market: SectorMarket { store.prefs.sectorMarket }
  /// 用户选的那一档。这个市场有没有这一档是另一回事，见 `snapshot()`——
  /// 那一行算出来的是**当前真正在显示的那档**，是取数结果的派生值，不许回写到这儿。
  private var preferredWindow: SectorWindow { store.prefs.sectorWindow }

  // MARK: - 口径

  /// 这一屏的全部算料。一次算齐，三层共用——聚合和兜底桶都不便宜，
  /// 不能让每个子视图各算一遍。
  private struct Snapshot {
    /// 当前市场的板块统计（含兜底桶），按**当前窗口**算。
    var stats: [SectorStat]
    /// 上场的那几颗。`SectorSelector` 自己会把兜底桶摘掉，气泡场吃不到它们。
    var selection: SectorSelection
    /// 当前市场、这段窗口上真算得出收益的品种数（去重）。
    var covered: Int
    /// 上面这些里**报得出成交额**的有几个。只给球场那句读屏文案用，不画到屏上。
    var volumed: Int
    /// 兜底桶，用来在下钻时还原成员名单。
    var buckets: [SectorFallbackBucket]
    /// 这一屏真正在用的窗口。用户停在 5 日、这个市场却没有历史时它是今日。
    var window: SectorWindow
    /// 当前这一档在屏上叫什么。和 `window` 同源（`SectorWindowChoice.resolve`）。
    var windowTitle: String
    /// 「5 日」那一档在这个市场有没有东西可看。没有就连药丸行都不出现。
    var hasD5: Bool
    /// 日线收盘。下钻到品种列表时那一层还要拿它算每一行的 5 日 / 20 日。
    var history: SectorHistory
  }

  private func snapshot() -> Snapshot {
    let market = market
    let buckets = feed.fallbackBuckets(for: market)
    let quotes = feed.quotes
    let history = historyFeed.history
    // 「5 日」有没有东西可看，决定的是药丸行在不在；停在 5 日的人在没有历史的市场里
    // 就地退回今日，偏好不动。这一问不算池基准，比再聚合一遍便宜得多。
    let hasD5 = SectorAggregator.hasEligible(market: market, quotes: quotes,
                                             window: .d5, history: history)
    // 「显示哪一档 + 药丸行在不在 + 那一档叫什么」三样一起定，在
    // `SectorWindowChoice` 里（纯函数，`Kanpan/Sector` 那个壳包有用例盯着，
    // 复核项 7）。原来这儿只算窗口，名字在 `windowBar` 里另写一遍。
    let choice = SectorWindowChoice.resolve(preferred: preferredWindow, hasD5: hasD5)
    let window = choice.window
    let stats = SectorAggregator.stats(market: market, quotes: quotes, fallbackBuckets: buckets,
                                       window: window, history: history)
    // N/M 按市场取各自的默认档（加密 5+3、美股 3+2）。上一次的尺子传进去做迟滞——
    // 每个窗口各记各的，不借别人的分母。
    let selection = SectorSelector.select(stats, market: market,
                                          previousScale: scaleMemo.values[window.rawValue])
    scaleMemo.values[window.rawValue] = selection.scalePct
    // 统计行里那个「品种」数不能拿各板块成员数相加——一个品种可以同时属于好几个
    // 板块（允许交叉归属），加起来会比实际多出一大截。这儿数的是去重之后、
    // 这段窗口上真算得出收益的那些。
    var seen = Set<String>()
    func cover(_ members: [String]) {
      for base in members {
        guard let q = quotes[base],
              SectorAggregator.windowReturn(q, window: window, closes: history.closes[base]) != nil
        else { continue }
        seen.insert(base)
      }
    }
    for def in SectorCatalog.sectors(market) { cover(def.members) }
    for bucket in buckets { cover(bucket.members) }
    let volumed = seen.reduce(into: 0) { n, base in
      if quotes[base]?.quoteVolume.isFinite == true { n += 1 }
    }
    return Snapshot(stats: stats, selection: selection, covered: seen.count, volumed: volumed,
                    buckets: buckets,
                    window: window, windowTitle: choice.title,
                    hasD5: choice.showsBar, history: history)
  }

  var body: some View {
    let snap = snapshot()
    return ZStack {
      // 上面压了层就把球场整个从可及性树里摘掉：它被盖住了，读屏不该读它，
      // 市场胶囊那套 id 也就不会同时出现两份。
      fieldLayer(snap).accessibilityHidden(!route.isEmpty)
      if route.contains(.all) {
        SectorAllSheet(stats: snap.stats.sorted { $0.pct > $1.pct }, market: market,
                       onBack: pop, onPick: { push(.list($0.id)) },
                       onPickMarket: switchMarket)
          .transition(.opacity)
      }
      if let id = listedSector {
        listLayer(id, snap).transition(.opacity)
      }
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .background { SectorBackdrop(skin: skin, reduceMotion: reduceMotion).ignoresSafeArea() }
    .tint(theme.amber)
    // 只是一层淡入淡出。弹跳、抖动、回弹一概没有。
    .animation(reduceMotion ? nil : .easeOut(duration: 0.24), value: route)
    // 先成组再挂 id：SwiftUI 会把容器上的 identifier 按到底下每一个叶子上，
    // 不成组的话整页的按钮全叫 `sector.page`，自己那颗 id 就被顶掉了。
    .accessibilityElement(children: .contain)
    .accessibilityIdentifier("sector.page")
    .onAppear {
      feed.setVisible(true)
      historyFeed.configure(hosts: feed.backendHosts)
      historyFeed.setVisible(true)
    }
    .onDisappear {
      feed.setVisible(false)
      historyFeed.setVisible(false)
    }
    // 网关名单是宿主在启动时配进 `feed` 的，可能比这一页出现得晚一步；
    // 换线路时也会变。变一次就重新接一次线，免得「5 日」那一档等到下次进页才活。
    .onChange(of: feed.backendHosts) { _, next in historyFeed.configure(hosts: next) }
  }

  /// 最上面那一层如果是品种列表，是哪个板块。
  private var listedSector: String? {
    guard let last = route.last, case .list(let id) = last else { return nil }
    return id
  }

  // MARK: - 第一层：顶栏 + 统计行 + 球场

  private func fieldLayer(_ snap: Snapshot) -> some View {
    VStack(spacing: 0) {
      header(snap)
      if snap.hasD5 { windowBar(snap) }
      if feed.showsEmptyState {
        emptyState
      } else if feed.quotes.isEmpty {
        // 第一趟还在路上：整块留白，不闪那句「暂无行情」，也不写「加载中」
        // （复核项 2 / `kanpan-no-engineering-status-fields`）。
        Color.clear.frame(maxWidth: .infinity, maxHeight: .infinity)
      } else {
        SectorBubbleField(selection: snap.selection, knobs: knobs, redUp: redUp,
                          onPick: { push(.list($0.stat.id)) })
          .frame(maxWidth: .infinity, maxHeight: .infinity)
          // 球场整个是一块 Canvas，底下没有可及的叶子。给它一个 id 和一句
          // 「几颗球 · 多少个品种报得出成交额」，读屏念得出来，UI 用例也拿它当准星
          // （`SectorRouteUITests` 靠它证明网关那条线路上这一页真有全市场行情）。
          .accessibilityElement()
          .accessibilityLabel("板块气泡")
          .accessibilityValue("\(snap.selection.picks.count) 个板块 · \(snap.volumed) 个品种有成交额")
          .accessibilityIdentifier("sector.bubbles")
      }
    }
  }

  /// 一颗球都没有的时候。
  ///
  /// 以前这儿是一张空球场：底还在、统计行写着「0 / 0 板块 · 0 品种」，但中间那块
  /// 什么都没有，用户看不出是在加载、还是这一页坏了、还是他该做点什么。现在给一句
  /// 中文和一个可以点的动作，就这两行——不说「网络异常」、不说「数据截至」、
  /// 不报线路状态（`kanpan-no-engineering-status-fields`），点一下就重取一趟。
  private var emptyState: some View {
    Button { feed.retry() } label: {
      VStack(spacing: 7) {
        Text("暂无行情")
          .font(skin.serif(17)).tracking(0.85)
          .foregroundStyle(theme.ink2)
        Text("点此重试")
          .font(.scaled(11.5)).tracking(0.23)
          .foregroundStyle(theme.ink3)
      }
      .frame(maxWidth: .infinity, maxHeight: .infinity)
      .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
    .accessibilityElement(children: .combine)
    .accessibilityLabel("暂无行情，点此重试")
    .accessibilityIdentifier("sector.empty")
  }

  /// 顶栏一行：标题 + 市场硬切换 +「…」，统计行贴在标题右边。
  ///
  /// 统计行照原型 `paintHeader()`：`N / M 板块 · K 品种`。这不是取数状态，
  /// 是这一屏自己的规模——上场几颗、一共几个板块、盖住了多少品种。
  ///
  /// 聚合口径那行药丸 2026-09-18 整行撤了：板块只有中位数一个口径，
  /// 不再让用户挑（也不退进「…」菜单）。那一行现在站着「板块明星 / 潜力明星」两颗——
  /// 换的是看多长一段，不是换算法。
  ///
  /// 系统字调大、一行放不下时，统计行整句落到标题下面一行，不截成「13 / 28…」（P2.13）。
  /// 默认档及更小照旧一行（统计行靠 `minimumScaleFactor` 在窄屏上收一点）。
  @ViewBuilder private func header(_ snap: Snapshot) -> some View {
    if dynamicTypeSize <= .large {
      oneRowHeader(snap)
        .padding(.horizontal, 20).padding(.top, 10).padding(.bottom, 2)
    } else {
      ViewThatFits(in: .horizontal) {
        oneRowHeader(snap)
        VStack(alignment: .leading, spacing: 2) {
          HStack(spacing: 10) {
            headerTitle
            Spacer(minLength: 0)
            marketSwitch
            moreButton
          }
          headerStats(snap)
        }
      }
      .padding(.horizontal, 20).padding(.top, 10).padding(.bottom, 2)
    }
  }

  private func oneRowHeader(_ snap: Snapshot) -> some View {
    HStack(spacing: 10) {
      HStack(alignment: .firstTextBaseline, spacing: 9) {
        headerTitle
        headerStats(snap)
      }
      Spacer(minLength: 0)
      marketSwitch
      moreButton
    }
  }

  private var headerTitle: some View {
    Text("板块").font(skin.serif(21)).tracking(1.26).foregroundStyle(theme.ink)
  }

  /// 手里还没有行情时整行不出：「0 / 0 板块 · 0 品种」读起来像这一页坏了。
  @ViewBuilder private func headerStats(_ snap: Snapshot) -> some View {
    if !feed.quotes.isEmpty, snap.covered > 0 {
      Text("\(snap.selection.picks.count) / \(snap.stats.count) 板块 · \(snap.covered) 品种")
        .font(.scaled(10.5, design: .monospaced)).tracking(0.63)
        .foregroundStyle(skin.ink4)
        .lineLimit(1).minimumScaleFactor(0.8)
    }
  }

  /// 「板块明星 / 潜力明星」。就这两颗，没有第三颗，也没有任何解释文字。
  ///
  /// 名字讲的是这一屏在挑什么样的板块，底下取的还是今日 24h 与 5 日两段数据
  /// （`SectorWindow.today` / `.d5` 一个字没动）——换名字不是换口径。
  ///
  /// 这一行只在 5 日那档真有东西可看时才出现（`snap.hasD5`）；美股那边服务端还没采
  /// 日线，那一格就整行不在，页面和甲版一模一样。样式照品种列表里「涨跌幅 / 成交额」
  /// 那两颗，整页只有这一种药丸。
  private func windowBar(_ snap: Snapshot) -> some View {
    HStack(spacing: 7) {
      windowChip(.today, on: snap.window == .today)
      windowChip(.d5, on: snap.window == .d5)
      Spacer(minLength: 0)
    }
    .padding(.horizontal, 20).padding(.top, 8)
    .accessibilityElement(children: .contain)
    // 读屏上这一行念的就是当下那一档，名字来自定这一档的那个函数本身，
    // 不在页面上另存一份（复核项 4）。
    .accessibilityValue(snap.windowTitle)
    .accessibilityIdentifier("sector.window")
  }

  /// 药丸上的名字只有 `SectorWindowChoice.title` 一个来源——页面这边一个字面量都不留。
  private func windowChip(_ value: SectorWindow, on: Bool) -> some View {
    Button { store.update { $0.sectorWindow = value } } label: {
      Text(SectorWindowChoice.title(value)).font(.scaled(11.5)).tracking(0.23)
        .foregroundStyle(on ? theme.ink : theme.ink3)
        .padding(.horizontal, 10).frame(height: 25)
        .background {
          Capsule().fill(on ? skin.chipOn : Color.clear)
            .overlay(Capsule().strokeBorder(on ? skin.chipEdge : skin.rule, lineWidth: 0.5))
        }
        .contentShape(Capsule())
    }.buttonStyle(.plain)
      .accessibilityLabel(SectorWindowChoice.title(value))
      .accessibilityAddTraits(on ? .isSelected : [])
      .accessibilityIdentifier("sector.window." + value.rawValue)
  }

  /// 市场硬切换。两个市场永远不共处一屏，换一格就是换一整套尺子。
  private var marketSwitch: some View {
    SectorMarketSwitch(skin: skin, market: market, onPick: switchMarket)
  }

  /// 换市场。球场和「全部板块」那张清单共用这一段。
  private func switchMarket(_ value: SectorMarket) {
    store.update { $0.sectorMarket = value }
    // 换市场就是换一整套尺子，上一档的分母不能带过去。
    scaleMemo.values.removeAll()
    // 人在「全部板块」里换市场，是想看另一个市场的那张清单，不是想被送回球场；
    // 所以清单留着，只把它上面压着的品种列表收掉。
    route = route.first == .all ? [.all] : []
  }

  /// 右上角那颗「…」：没上场的板块只有这一条路。
  private var moreButton: some View {
    Button { push(.all) } label: {
      Image(systemName: "ellipsis")
        .font(.system(size: 14, weight: .medium)).foregroundStyle(theme.ink2)
        .frame(width: 30, height: 30)
        .background(skin.well, in: Circle())
        .overlay(Circle().strokeBorder(skin.rule, lineWidth: 0.5))
        .frame(width: 40, height: 40)
        .contentShape(Rectangle())
    }.buttonStyle(.plain)
      .accessibilityLabel("全部板块")
      .accessibilityIdentifier("sector.more")
  }

  // MARK: - 第三层：某个板块的品种列表

  /// 成员名单从分类表（或兜底桶）取，行情从 `feed` 取。
  ///
  /// 这一帧的 `stats` 里找不到这个板块时**不退栈**（审查 C-01）。「找不到」多数时候
  /// 只是行情还没到——冷启动第一帧、刚换窗口、网络抖一下都会这样；把它当成「人按了
  /// 返回」，用户就会在数据回来之前被悄悄送回球场，而且再也回不去（路由已经被弹掉，
  /// 没人会替他压回来）。退不退由 `SectorDrillDecision` 判：只有分类表确认它不在、
  /// 兜底桶里也没有、而且这一帧确实算出了别的板块（说明行情在跑，只是没有它），
  /// 才算「板块没了」。其余情况留在原地等，摆一张只有名字的空壳——返回键还在，
  /// 人随时能自己走。
  @ViewBuilder private func listLayer(_ id: String, _ snap: Snapshot) -> some View {
    switch SectorDrillDecision.decide(id: id, stats: snap.stats, buckets: snap.buckets) {
    case .show, .wait:
      let stat = snap.stats.first { $0.id == id }
        ?? SectorDrillDecision.placeholder(id: id, market: market, buckets: snap.buckets)
      let members = members(of: id, snap)
      // 20 日不是一个模式，只是 5 日那一档里头部补的一句。没有 20 日数据就不补。
      let d20 = snap.window == .d5
        ? SectorAggregator.windowMedian(members: members, quotes: feed.quotes,
                                        history: snap.history, window: .d20)
        : nil
      SectorSymbolList(stat: stat, members: members, quotes: feed.quotes,
                       window: snap.window, history: snap.history, medianD20: d20,
                       symbolForBase: symbolForBase,
                       decimalsForBase: { feed.priceDecimals(forBase: $0) }, store: store,
                       onBack: pop, onPick: onPickSymbol, onScanList: onScanList,
                       onRowsShown: onListShown, onRowsHidden: onListHidden,
                       previews: previews, picker: picker)
    case .pop:
      Color.clear.onAppear { pop() }
    }
  }

  private func members(of id: String, _ snap: Snapshot) -> [String] {
    if let def = SectorCatalog.sector(id: id) { return def.members }
    return snap.buckets.first { $0.id == id }?.members ?? []
  }

  private func push(_ layer: SectorRoute) {
    guard route.last != layer else { return }
    route.append(layer)
  }

  private func pop() {
    guard !route.isEmpty else { return }
    route.removeLast()
  }
}

// MARK: - 导航

/// 压在球场上面的那几层。宿主持有它（见 `SectorPage.route`），所以它得是 internal。
enum SectorRoute: Equatable {
  case all
  case list(String)
}

// MARK: - 市场硬切换

/// 「加密 / 美股」那颗胶囊。球场的顶栏和「全部板块」的页头共用同一颗——
/// 同一个动作只有一种长相，也只有一套 id。
struct SectorMarketSwitch: View {
  var skin: SectorSkin
  var market: SectorMarket
  var onPick: (SectorMarket) -> Void

  private var theme: PanelTheme { skin.theme }

  var body: some View {
    HStack(spacing: 2) {
      tab(.crypto, "加密")
      tab(.us, "美股")
    }
    .padding(2)
    .background {
      Capsule().fill(skin.well)
        .overlay(Capsule().strokeBorder(skin.rule, lineWidth: 0.5))
    }
    .accessibilityElement(children: .contain)
    .accessibilityIdentifier("sector.market")
  }

  private func tab(_ value: SectorMarket, _ title: String) -> some View {
    let on = market == value
    return Button {
      guard !on else { return }
      onPick(value)
    } label: {
      Text(title).font(.scaled(12)).tracking(0.48)
        // 选中那格的字压在强调色上，走 `badgeInk`（浅色 `#FFFFFF`，观感不变；
        // 深色换成近黑，白字在 `#4FB69C` / `#E2874F` 上只有 2.5:1）。
        .foregroundStyle(on ? theme.badgeInk : theme.ink3)
        .padding(.horizontal, 11).frame(height: 26)
        .background {
          if on {
            Capsule().fill(skin.accentGradient)
              .overlay(alignment: .top) { skin.topHighlight(inset: 7) }
              .shadow(color: skin.accent.opacity(skin.dark ? 0.45 : 0.32), radius: 5, x: 0, y: 2)
          }
        }
        .contentShape(Capsule())
    }.buttonStyle(.plain)
      .accessibilityLabel(title)
      .accessibilityAddTraits(on ? .isSelected : [])
      .accessibilityIdentifier("sector.market." + value.rawValue)
  }
}

// MARK: - 派生色板

/// 板块页用到的材质与光，全部从当前皮肤推出来——这一页不写死任何一支颜色。
///
/// 口径照 `FavoritesView` 的「琉璃」：同一张底、同一根发丝线、同一档墨色，
/// 第二层的品种列表才和自选页读成同一页纸。差别只在光斑取色：自选页浅色下借的是
/// 一组写死的「天青·薄荷」，这一页按契约一律从种子推（原型 `#ground` 用的也正是
/// `--acc` / `--accB` / `--gold` 三支）。
struct SectorSkin {
  let theme: PanelTheme
  var seed: PaletteSeed { theme.seed }
  var dark: Bool { theme.dark }

  /// 深色下画不画那几团光。
  ///
  /// 原型的深色底是有强调色光晕的，但用户看过真机之后点名把自选页深色那两团去掉了
  /// （「深色模式下有两个光晕影响视觉，直接去掉」）。这一页的第二层要和自选页读成
  /// 同一张纸，所以两页一起守这条：深色只留素底加颗粒。
  static let lobesInDark = false

  /// 整页的底。取法和自选页一字不差：深色与经典白用 `ground`，青苔 / 陶土的浅色
  /// 用 `app` 那张暖白 / 冷白（自选页那两支是为「琉璃」单调的字面色，这一页按契约
  /// 只能从种子取，色相同族、明度相近）。
  var ground: Color { Color(hex: dark || Palette.isClassic(seed) ? seed.ground : seed.app) }

  /// 三团光。只在浅色下画，颜色是强调色与暖色**提到很淡**的一档——原型 `#ground`
  /// 用的就是 `--acc` / `--accB` / `--gold` 这三支，自选页浅色下那三支柔和的
  /// 天青、薄荷、淡蓝是同一个意思的手调版。直接拿饱和的强调色铺 63% 会把整页染绿，
  /// 所以先 `lift` 到接近白再铺。
  var lobes: [Color] {
    [Self.lift(seed.accent, 0.78), Self.lift(seed.amber, 0.82), Self.lift(seed.accent, 0.9)]
  }
  /// 列表不再垫玻璃之后光斑直接穿过文字，整体收 30%。和自选页同一个系数。
  func lobeOpacity(_ index: Int) -> Double { 0.9 * 0.7 }
  /// 底部同色收敛：从 22% 高度起往下渐渐回到底色，文字压在光斑上也读得清。
  var washStrength: Double { 0.7 }
  var grainOpacity: Double { dark ? 0.05 : 0.035 }

  var accent: Color { Color(hex: seed.accent) }
  var accentLift: Color { Self.lift(seed.accent, 0.42) }
  /// 液态药丸：提亮的强调 → 强调。
  var accentGradient: LinearGradient {
    LinearGradient(colors: [accentLift, accent], startPoint: .topLeading, endPoint: .bottomTrailing)
  }

  /// 玻璃：深色借近白的墨色，浅色借 `raised`（浅色种子的 raised 都是白）。
  private var pane: Color { Color(hex: dark ? seed.ink : seed.raised) }
  /// 圆按钮与分段器的槽（原型 `.mkt` / `.more` / `.back`）。
  var well: Color { Color(hex: seed.ink).opacity(dark ? 0.055 : 0.06) }
  /// 半像素的边、行与行之间那根发丝线。
  var rule: Color { Color(hex: seed.ink).opacity(dark ? 0.11 : 0.09) }
  /// 选中那颗药丸的底与边（原型 `.chip[aria-selected]`）。
  var chipOn: Color { Color(hex: dark ? seed.ink : seed.raised).opacity(dark ? 0.08 : 0.7) }
  var chipEdge: Color { Color(hex: dark ? seed.ink : seed.line).opacity(dark ? 0.165 : 1) }
  /// 比 ink3 再弱一档，给单位、微标签、统计行。
  var ink4: Color { Color(hex: seed.ink3).opacity(0.7) }

  /// 玻璃顶上那一线高光。
  func topHighlight(inset: CGFloat) -> some View {
    Capsule().fill(pane.opacity(dark ? 0.3 : 0.9))
      .frame(height: 1).padding(.horizontal, inset)
  }

  /// 标题字体。和自选页同一支：iOS 装机里没有可用的简体中文衬线体，
  /// `.serif` 让拉丁走 New York、中文走系统字，靠字号与字距把标题撑起来。
  func serif(_ size: CGFloat) -> ScaledFont { ScaledFont(size, .medium, design: .serif) }

  /// 往亮里提一档：色相不动，饱和收一点、明度往上走。
  private static func lift(_ hex: Hex, _ amount: Double) -> Color {
    let rgba = hex.rgba
    var h: CGFloat = 0, s: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
    UIColor(red: rgba.r, green: rgba.g, blue: rgba.b, alpha: 1)
      .getHue(&h, saturation: &s, brightness: &b, alpha: &a)
    return Color(hue: Double(h), saturation: Double(s) * (1 - amount * 0.6),
                 brightness: Double(b) + (1 - Double(b)) * amount)
  }
}

// MARK: - 底：一块连续的材料

/// 板块页三层共用的底。
///
/// 气泡场、品种列表、全部板块都铺这一张——上层盖下来时换的是内容不是纸，
/// 整屏从头到脚读成同一块材料，上下不出拼缝。
struct SectorBackdrop: View {
  let skin: SectorSkin
  let reduceMotion: Bool
  @State private var drift = false

  var body: some View {
    GeometryReader { geometry in
      let width = geometry.size.width
      let height = geometry.size.height
      ZStack(alignment: .topLeading) {
        skin.ground
        if !skin.dark || SectorSkin.lobesInDark {
          lobe(0, size: 300, x: -95, y: -80, seconds: 22)
          lobe(1, size: 250, x: width - 170, y: 240, seconds: 27)
          lobe(2, size: 280, x: -70, y: height - 230, seconds: 31)
          LinearGradient(stops: [
            .init(color: skin.ground.opacity(0), location: 0.22),
            .init(color: skin.ground.opacity(skin.washStrength), location: 1)],
            startPoint: .top, endPoint: .bottom)
            .frame(width: width, height: height)
        }
        if let grain = SectorGrain.image {
          grain.resizable(resizingMode: .tile).opacity(skin.grainOpacity)
        }
      }
      .frame(width: width, height: height)
      .clipped()
    }
    .allowsHitTesting(false)
    .onAppear { if !reduceMotion { drift = true } }
  }

  /// 漂移只动 `offset` / `scale`，交给渲染层去跑，不会让上面的列表每帧重建。
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
@MainActor enum SectorGrain {
  static let image: Image? = {
    let side = 96
    var bytes = [UInt8](repeating: 0, count: side * side)
    var state: UInt64 = 0x2545_F491_4F6C_DD1D
    for index in bytes.indices {
      state ^= state << 13
      state ^= state >> 7
      state ^= state << 17
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

// MARK: - 三层共用的零件

/// 左上角那颗返回。原型 `.back`：30 的圆片挂在 40 的可点区里。
struct SectorBackButton: View {
  let skin: SectorSkin
  let id: String
  let action: () -> Void

  var body: some View {
    Button(action: action) {
      Image(systemName: "chevron.left")
        .font(.system(size: 15, weight: .semibold))
        .foregroundStyle(skin.theme.ink2)
        .frame(width: 30, height: 30)
        .background(skin.well, in: Circle())
        .overlay(Circle().strokeBorder(skin.rule, lineWidth: 0.5))
        .frame(width: 40, height: 40)
        .contentShape(Rectangle())
    }.buttonStyle(.plain)
      .accessibilityLabel("返回")
      .accessibilityIdentifier(id)
  }
}

/// 行与行之间那根两端渐隐的发丝线。照抄自选页。
struct SectorHairline: View {
  let skin: SectorSkin

  var body: some View {
    LinearGradient(colors: [.clear, skin.rule, skin.rule, .clear],
                   startPoint: .leading, endPoint: .trailing)
      .frame(height: 0.5).padding(.horizontal, 20)
  }
}

/// 涨跌小三角。
struct SectorTriangle: Shape {
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
