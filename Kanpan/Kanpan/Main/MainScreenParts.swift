import KanpanAccount
import KanpanChart
import KanpanCore
import KanpanData
import KanpanNetwork
import ReviewDomain
import ReviewUI
import SwiftUI
import UIKit

// MARK: - 为什么这些东西从 MainScreen 里搬了出来
//
// 2026-09-22 iOS 27 真机上「点开就闪退」（`EXC_BAD_ACCESS` / `Thread stack size exceeded`，
// 栈顶是 `swift_getTypeByMangledName` → `decodeMangledType` 的递归）。根因是
// `MainScreen.body` 那条修饰符链把具体类型套了一百多层，运行时按 mangled name 实例化
// 类型元数据时递归太深，主线程 1MB 栈放不下。细节见 `MainScreen.swift` 顶部那段注释。
//
// 这个文件里的每一个 `View` / `ViewModifier` 都是一个**新的类型根**：非泛型 struct 的
// `body`、以及 `ViewModifier.body(content:)`（它的 `Content` 是 `_ViewModifier_Content<Self>`，
// 不带宿主的类型）都不会把深度累加回 `MainScreen.body` 的类型上。所以往这儿搬是免费的，
// 往 `MainScreen` 那条链上堆才是要命的。

/// 主屏那一串观察者（`onChange` / `onReceive` / `task(id:)`）。
///
/// 它们从前是直接挂在内容链上的三十一个修饰符，每一个都往 `MainScreen.body` 的具体类型
/// 上再套一层 `ModifiedContent<...>`——那正是启动栈溢出的大头。观察者不需要挂在那棵巨大的
/// 内容树上，只要在视图树里活着就会触发，所以整串收进这个 `ViewModifier`，主链上只剩
/// `.modifier(...)` 一层。
///
/// **被观察的值一律由 `MainScreen.body` 算好传进来，这儿不读模型。**
/// `onChange(of:)` 里那个表达式在哪儿求值，依赖就记在谁头上：传值进来等于依赖照旧记在
/// 宿主的 body 上，和搬家之前一模一样；要是图省事在这儿读 `picker.prefs.favorites`，
/// 宿主就不再订阅它，靠它算出来的 `listVisible` 会永远停在旧值上。
/// 动作（下面那一堆闭包）不受这条限制——它们在 body 求值之后才跑，读什么都不建立依赖，
/// 所以正文照旧留在 `MainScreen` 里，读的还是当时最新的值。
struct MainScreenObservers: ViewModifier {
  // 被观察的值。
  let prefs: Prefs
  let phase: ScenePhase
  let deepLink: DeepLink?
  let microstructureVisible: Bool
  let syncGate: Bool
  let reviewScope: String
  let routePolicy: MarketRoutePolicy
  /// 逐笔推送带出来的两条（成交、费率）不在这儿求值，交给 `LiveTickRelay`（审查 21）。
  let session: ChartSession
  let catalogCount: Int
  let listVisible: Bool
  let favorites: [String]
  let symbol: String
  let undoStamp: Int
  let storeNotice: String?
  let drawFull: Bool
  let drawNotice: String?
  let panel: Panel?
  let drawActive: Bool
  let alertsNotice: String?
  let reviewNotice: String?
  let reviewChartNotice: String?
  let reviewBookOpen: Bool
  let reviewRecords: [ReviewRecord]

  // 动作。收到的都是 `onChange` 给的**新值**，和搬家之前那些闭包收到的一模一样。
  let onPhase: (ScenePhase) -> Void
  let onDeepLink: () -> Void
  let onMicrostructure: (Bool) -> Void
  let onSubs: ([IndicatorID]) -> Void
  let onDepth: (Bool) -> Void
  let onComfort: () -> Void
  let onSyncGate: () -> Void
  let onReviewScope: (String) -> Void
  let onPrefsReviewScope: (String) -> Void
  let onTimeZone: (TZChoice) -> Void
  let onChangeBasis: (ChangeBasis) -> Void
  let onInterval: (Interval) -> Void
  let onRoutePolicy: (MarketRoutePolicy) -> Void
  let onFundingRate: (Double?) -> Void
  let onCatalog: () -> Void
  let onListVisible: (Bool) -> Void
  let onFavorites: ([String]) -> Void
  let onSymbol: (String) -> Void
  let onUndoStamp: () -> Void
  let noteDwell: () async -> Void
  let onStoreNotice: (String?) -> Void
  let onDrawFull: () -> Void
  let onDrawNotice: (String?) -> Void
  let onPanel: (Panel?) -> Void
  let onDrawActive: (Bool) -> Void
  let onAlertsNotice: (String?) -> Void
  let onReviewNotice: (String?) -> Void
  let onReviewChartNotice: (String?) -> Void
  let onReviewBookOpen: () -> Void
  let onReviewRecords: ([ReviewRecord]) -> Void

  // 分成四段挂，是因为三十一个 `onChange` 串成一条表达式会让类型检查器超时
  // （`unable to type-check this expression in reasonable time`）。顺序和从前一样。
  func body(content: Content) -> some View {
    panelSection(marketSection(displaySection(lifecycleSection(content))))
      // 成交交给报价簿、费率存给预览卡：这只空视图自己观察推送，宿主不跟着醒。
      .background(LiveTickRelay(session: session, onFunding: onFundingRate))
  }

  // 原 `lifecycleContent` + `indicatorObservedContent`。
  private func lifecycleSection<V: View>(_ view: V) -> some View {
    view
    // 前后台只走这一条路，落盘顺序由 `AppLifecycle` 排（产数据的先、排空存档的最后）。
    .onChange(of: phase) { _, now in onPhase(now) }
    // 外面进来的链接（通知、桌面快捷入口、共享链接）全在这儿落地。app 已经开着时
    // 走这条；冷启动那一下界面还没搭好，由 `boot()` 末尾补取一次。
    .onChange(of: deepLink) { _, link in if link != nil { onDeepLink() } }
    .onChange(of: microstructureVisible, initial: true) { _, visible in onMicrostructure(visible) }
    .onChange(of: prefs.subs) { _, subs in onSubs(subs) }
    .onChange(of: prefs.depth) { _, on in onDepth(on) }
  }

  // 原 `observedContent`：亮度 / 皮肤 / 常亮 / 云端设置 / 找相似范围 / 时区。
  private func displaySection<V: View>(_ view: V) -> some View {
    view
    .onReceive(NotificationCenter.default.publisher(for: UIScreen.brightnessDidChangeNotification)) { _ in onComfort() }
    .onChange(of: prefs.ambientTheme) { _, _ in onComfort() }
    .onChange(of: prefs.theme) { _, _ in onComfort() }
    // 常亮：退后台 / 低电量模式且电量 ≤20% 时放手，回前台再按设置设回（P2.10）。
    .modifier(KeepAwakeGate(enabled: prefs.keepAwake, phase: phase))
    // 面板 / 画线 / 复盘开着的时候云端设置是被挡下来的（会把人正在做的事掀掉）。
    // 关掉的这一刻补跑一次，别让人等下一轮全量（300 秒）。
    .onChange(of: syncGate) { _, open in if open { onSyncGate() } }
    // 「找相似」的范围两头对接（R3-5）：面板上改了就落进偏好，云端换下来一份
    // （或者换了账号）也照样灌回面板。两条都靠 `PrefsStore.update` 自带的
    // 「没真改动就不写」挡住回环，不会你来我往。
    .onChange(of: reviewScope) { _, value in onReviewScope(value) }
    .onChange(of: prefs.reviewSearchScope) { _, value in onPrefsReviewScope(value) }
    // 时区那一档也要跟着改：设置里从「本地」切到「交易所」，复盘本、找相似列表、
    // 到期轮盘要和 K 线时间轴一起换口径（审查 B-08）。
    .onChange(of: prefs.timeZone) { _, value in onTimeZone(value) }
  }

  // 原 `marketContent`：线路、口径、行情源、品种表、自选、报价、停留。
  private func marketSection<V: View>(_ view: V) -> some View {
    view
    .onChange(of: prefs.changeBasis) { _, next in onChangeBasis(next) }
    // 偏好里的周期不是经周期条改的（云端落地、撤销、恢复默认），图也要跟上。
    // 周期条那条路是先改偏好、再当场 `session.show`，到这儿两边已经一样，什么都不做。
    .onChange(of: prefs.interval) { _, next in onInterval(next) }
    .onChange(of: routePolicy) { _, next in onRoutePolicy(next) }
    // 品种表是板块页认 base 的依据（兜底桶按它的标签凑，点行去看图也靠它拼全名）。
    // 它是异步载进来的，所以不能只在 `boot()` 里交一次。
    .onChange(of: catalogCount) { _, _ in onCatalog() }
    .onChange(of: listVisible) { _, on in onListVisible(on) }
    .onChange(of: favorites) { _, symbols in onFavorites(symbols) }
    .onChange(of: symbol) { _, next in onSymbol(next) }
    // 自选页删掉一只之后那句「已移除 · 撤销」（§P3-4）。全屏只有一层提示条，
    // 所以话由自选页放进来、宿主念出去；盯的是计数不是那句话本身——连删两只
    // 说的是同一句，`onChange(of: String)` 不会响第二次。
    .onChange(of: undoStamp) { _, _ in onUndoStamp() }
    // 「常看」记的是**在这张图上真待住了**，不是「点开过」：搜索里滑过一下、点错一次
    // 立刻退出去的，都不该算一分。`task(id:)` 换品种就取消重来，离屏也取消，
    // 所以停不满 3 秒的那些一分都拿不到。
    .task(id: symbol) { await noteDwell() }
    .onChange(of: storeNotice) { _, note in onStoreNotice(note) }
    .onChange(of: drawFull) { _, full in if full { onDrawFull() } }
  }

  // 原来挂在 `body` 上的那一批：画线、面板、提醒、复盘。
  private func panelSection<V: View>(_ view: V) -> some View {
    view
    .onChange(of: drawNotice, initial: true) { _, note in onDrawNotice(note) }
    .onChange(of: panel) { _, value in onPanel(value) }
    .onChange(of: drawActive) { _, active in onDrawActive(active) }
    .onChange(of: alertsNotice) { _, note in onAlertsNotice(note) }
    .onChange(of: reviewNotice) { _, note in onReviewNotice(note) }
    .onChange(of: reviewChartNotice) { _, note in onReviewChartNotice(note) }
    .onChange(of: reviewBookOpen) { _, open in if open { onReviewBookOpen() } }
    // 复盘的待办本来就有到期时间，这儿把它兑现成一条到点响的本地通知（方案 2.3 末条）。
    // 整批重排，便宜且不会对不上账。
    .onChange(of: reviewRecords, initial: true) { _, list in onReviewRecords(list) }
  }
}

/// 行情页头部：顶栏 + 价格行 / 十字线读数（原 `MainScreen.header`）。
///
/// 独立成 struct 不是为了复用，是为了把它那四十来层嵌套从 `MainScreen.body` 的类型里摘出去。
/// 画的东西一个 pt 都没动。
struct MainHeaderView<Card: View>: View {
  let theme: PanelTheme
  let market: MarketModel
  let review: ReviewFeature
  /// 那口价、涨跌和诊断串都在这块自己的 body 里向会话现取（审查 21）：逐笔推送只叫醒头部，
  /// 不叫醒宿主。
  let session: ChartSession
  let context: CrosshairContext
  /// 「要不要加提醒」/ 分享卡在场没有：价格行和读数行照旧占位，只是透明。
  let cardVisible: Bool
  let onBack: (() -> Void)?
  let onReview: () -> Void
  let onSearch: () -> Void
  let onScan: (ScanDirection) -> Void
  let card: Card

  var body: some View {
    #if DEBUG
      let _ = FrameProbe.shared.countBody("MainHeaderView")
    #endif
    let readout = session.readout
    VStack(spacing: Space.s) {
      // 顶栏没有自选星了（用户 2026-09-18 定的）：加自选统一在搜索页和自选页的
      // 品种行上做，那儿看得见一整列，挑着加；顶栏这一颗紧贴品种名，只会误触。
      // 复盘从底栏挪到了这儿：底栏换成常驻标签栏之后那四格是分页，复盘按用户的话
      // 「放到图表里」——它是看着某张图时才想起来的事。角标是还欠着答案的条数。
      TopBar(
        theme: theme, symbol: market.symbol,
        review: review,
        // 有来路才有返回。复盘态走的是另一副页头（`ReplayHeaderView`），不经过这儿。
        onBack: onBack,
        onReview: onReview,
        onSearch: onSearch)
      ZStack {
        PriceRow(theme: theme, instrument: market.symbol, ticker: session.rollingTicker, lastPrice: session.readoutPrice,
          decimals: market.info.priceDecimals,
          volumeUnit: market.volumeUnit,
          openInterest: market.openInterestDisplay,
          openInterestUnit: market.openInterestUnit,
          totalSupply: market.totalSupply,
          fundingRate: market.displayedFundingRate,
          asset: market.asset,
          forwardEarnings: market.forwardEarnings,
          revenue: market.revenue,
          nextFundingTimeMs: market.displayedNextFundingTime,
          stale: !market.priceFresh)
          .modifier(HiddenWhileCrosshairReads(readout: readout, context: context))
          .accessibilityElement(children: .contain)
          .accessibilityIdentifier("market.quote")
          .accessibilityValue(session.quoteDiagnostics)
          // 「要不要加提醒」在场的那六秒，价格行也照旧占着位置、只是透明——
          // 和十字线那套让位一模一样，行高一个 pt 都不变。
          .opacity(cardVisible ? 0 : 1)
        // 「顶部」那一档的开高低收（其余两档读数在图里，这儿什么都不画）。
        // 十字线那颗「创建提醒」不在头部：它在周期条那一行（`CrosshairActionBar`），
        // 所以按住图找位置的时候，价格、涨跌、六格一直是实时的（2026-09-23）。
        CrosshairOHLCLabel(readout: readout, context: context, color: theme.ink, fillsWidth: true)
          .fixedSize(horizontal: false, vertical: true)
          // 刚画完的那一句优先：让位也是透明让位，这一行的高度不因此变。
          .opacity(cardVisible ? 0 : 1)
          .allowsHitTesting(false)
      }
      // 画完一条线问的那一句，摆在**价格行的位置上**，而且是 `overlay`——
      // overlay 不参与父视图定尺寸，所以它在与不在，头部和图表的高度一个 pt 都不会变
      // （从前它在图外面自成一行，画完线图当场矮一截、六秒后又弹回来）。
      // 它盖着的只有价格与那六格，画布一个点都没碰着（`kanpan-no-floating-controls-over-chart`）。
      .overlay { card }
      // 连续扫图（§10.1）：横滑**只挂在价格这一块**上。
      //
      // 画布上不挂——那儿的横滑是平移 K 线，人一辈子都在那儿横滑；周期条上也不挂——
      // 那一排药丸本来就要横向滚动。价格区是这一屏唯一一块「横着划没有别的意思」的地方，
      // 而且它正是「现在看的是哪一只」那句话所在的位置，滑它换一只读起来是顺的。
      .contentShape(Rectangle())
      .gesture(DragGesture(minimumDistance: 20).onEnded { g in
        let dx = g.translation.width, dy = g.translation.height
        // 要横得明显：斜着划过去的多半是想划别的，宁可不动。
        guard !cardVisible, abs(dx) > 44, abs(dx) > abs(dy) * 1.5 else { return }
        onScan(dx < 0 ? .next : .previous)
      })
    }
    // 左右 `Inset.page`（16 Pro 16 / 17 Pro Max 20），上下 8 / 8（UI 审查 2026-09-24 §4.3 #1–#3）。
    // 周期条、十字线动作条、「更多」弹层用的是同一份边距，四样东西站在同一条竖线上。
    .pageHorizontalInset()
    .padding(.vertical, Space.s)
    .background(theme.app)
    // 头部整块（顶栏品种名、价格 + 六格、十字线读数、「要不要加提醒」那一句）只跟到
    // `MarketChrome.typeCap` 为止，比全局的 .xxxLarge 低得多（P2.13 / P0 D.13）：
    // 价格 + 六格要并排装下，而且头部多高、图表就少多高——
    // 辅助大字下六格照旧在价格右边、头部一个 pt 都不长；调小字号时照常跟着变小。
    .dynamicTypeSize(...MarketChrome.typeCap)
  }
}

/// 行情页顶上那几条常驻 chrome（头部、周期条、十字线动作条、「更多」弹层）共用的口径。
enum MarketChrome {
  /// 字号跟随系统到哪一档为止。
  ///
  /// 仍是 `.large`。09-22 在 390pt 的机器上实测 `.xLarge` 下价格 + 六格超宽 16pt；
  /// 2026-09-24 兼容机型收到 16 Pro（402pt）/ 17 Pro Max（440pt）、字号换成令牌之后在 16 Pro 上
  /// 重量了一次（`MainScreenUITests.testHeaderStatsAtLargestDynamicType` 临时开到 `.xLarge`）：
  /// BTC、SNDK、MU 装得下（BTC 涨跌行到六格只剩 17.7pt），1000SATS 的价格八位小数 139pt 宽，
  /// 整行超出约 30pt——价格左缘顶出屏幕 15pt、六格右缘顶出 15pt。所以不放宽。改档先重量。
  static let typeCap: DynamicTypeSize = .large
}

/// K 线画布那一块（原 `MainScreen.chart`）。竖屏横屏共用一份。
///
/// 同样是为了断开类型嵌套才独立成 struct：`ChartHost` 那二十来个回调原样搬过来，
/// 参数从宿主传进来，一个字的行为都没改。
struct MainChartView: View {
  let theme: PanelTheme
  let market: MarketModel
  let proxy: ChartProxy
  let viewport: ChartViewport
  let store: PrefsStore
  let review: ReviewFeature
  let reviewChart: ReviewChartBridge
  let draw: DrawingController
  let alerts: AlertStore
  /// 行情那一半在这块自己的 body 里现取（`session.liveState`），宿主只交不随推送变的
  /// `input`——逐笔推送、倒计时每一秒，叫醒的是这块而不是整页（审查 21）。
  /// 复盘态下用的是 `reviewChart.state`，那时候不去揉实时那份。
  let session: ChartSession
  let input: ChartInput
  let portrait: Bool
  let renderingActive: Bool
  let panelOpen: Bool
  let drawingCanvasOnly: Bool
  let alertedDrawingIDs: Set<String>
  @Binding var atLatest: Bool
  let merged: ([IndicatorID]) -> [IndicatorID]
  let say: (String) -> Void
  let onTapped: () -> Void
  /// 点图上已画的一条复盘记录（P3.7）：打开它的详情。
  var onOpenRecord: (UUID) -> Void = { _ in }

  var body: some View {
    #if DEBUG
      let _ = FrameProbe.shared.countBody("MainChartView")
    #endif
    ZStack(alignment: .bottomTrailing) {
      theme.chartBG
      ChartHost(
        portrait: portrait,
        renderingActive: renderingActive,
        state: reviewChart.active ? reviewChart.state : session.liveState(input),
        holdOnEmpty: !reviewChart.active && market.holdsFrame,
        proxy: reviewChart.active ? reviewChart.proxy : proxy,
        onView: { view in
          if !reviewChart.active { market.loadOI(view: view) }
          // 视野一动就重算一次：周期条行尾那颗「最新」靠它露面 / 收起。
          let now = (reviewChart.active ? reviewChart.proxy : proxy).isAtLatest
          if now != atLatest { atLatest = now }
        },
        // 读的是 `ChartViewport` 内存里那一份，不是 `prefs.barSpacing`：落盘虽然钉在
        // 手指抬起那一刻，但用户捏完可能下一帧就换品种，那一下必须按刚捏出来的宽度开图。
        resetSpacing: viewport.barSpacing,
        // 复盘只读这份根宽、不写回去：一进复盘 K 线不该突然变宽变窄，但复盘是在重放
        // 一段历史，它那边怎么拉怎么捏都不该改写用户平时看盘的习惯。
        //
        // **这一路只收用户手上的动作**（`ChartHost.onBarSpacing` ← `ChartView.onUserViewChanged`）。
        // 程序自己摆出来的视野绝不会走到这儿——那正是用户那个 bug 的「杀法甲」。
        onBarSpacing: { if !reviewChart.active { viewport.userIsZooming(to: $0) } },
        onInteractionEnded: { if !reviewChart.active { viewport.interactionEnded() } },
        adoptToken: viewport.adoptToken,
        onInversion: { main, subs in if !reviewChart.active { store.noteInversion(main: main, subs: subs) } },
        onSubResize: { id, scale in store.update { $0.subHeightOverrides[id] = scale } },
        onSubReorder: { order in let next = merged(order); store.update { $0.subs = next } },
        onCrosshair: { [readout = session.readout] in
          readout.set($0)
          // 行情流逐帧发的「精细档」：十字线在主图上，或者正盯着一单的详情卡。
          market.orderFlow.noteCrosshair(onMain: ($0.map { $0.pane == nil } ?? false) || readout.orderFlow != nil)
        },
        // 主力订单流的焦点（轻点选中的那一桶，或十字线停着的那一条合并带）：出详情卡。
        onOrderFlowFocus: { [readout = session.readout] focus in
          readout.set(orderFlow: focus)
          market.orderFlow.noteCrosshair(onMain: focus != nil || readout.crosshair.map { $0.pane == nil } == true)
        },
        onNeedsHistory: { if reviewChart.mode == .replay { reviewChart.loadReplayPage(forward: false, feature: review) } else if !reviewChart.active { market.loadMore() } },
        // 面板打开时由原生遮罩消费首个触摸，只收起面板。
        onTapped: { onTapped() },
        onNotice: { say($0) },
        drawing: reviewChart.active ? nil : draw,
        // 图上哪几条线挂着提醒——右端一枚小铃铛。
        alertedDrawingIDs: alertedDrawingIDs
      )
      .id(reviewChart.mode.rawValue)
      // 横屏画线时复盘的区间框、目标线和「等答案」标签一律不画（§2E5）：横屏那一屏
      // 要的是干净的原始 K 线，和「指标一律不画」是同一条理由——画布上多一根线，
      // 画的时候就多一次「这是我画的还是本来就有的」。记录本身没动，转回竖屏原样都在。
      // 非圈选时这一层只接落图标签那一小块（`RangeOverlayView.point(inside:)`），
      // 其余位置命中测试穿过去，图照常拖、捏、长按。画线时整层让开。
      ReviewRangeOverlay(feature: review, bridge: reviewChart, liveProxy: proxy,
                         suppressed: drawingCanvasOnly, flash: review.lastSaved,
                         tappable: !draw.active && !panelOpen, onOpenRecord: onOpenRecord)
        .allowsHitTesting(reviewChart.mode == .capture || (reviewChart.mode == .live && !draw.active && !drawingCanvasOnly && !panelOpen))
      // 切线路一律静默：用户要看的是 K 线，不是我们从哪台机器取的数。
      // 历史数据真拉不下来才出这一条——那是「图不全」，得让人知道并且能重试。
      // 主力订单流详情卡（照 CoinAnk）：只随焦点重求值，不接触摸，点它等于点下面的图。
      OrderFlowDetailLayer(readout: session.readout, theme: theme, hidden: reviewChart.active,
                           base: QuoteAssets.base(of: market.symbol), decimals: market.info.priceDecimals,
                           timeZone: input.prefs.timeZone.offsetMinutes)
      if let error = market.historyError, !reviewChart.active {
        ChartHistoryRetry(theme: theme, text: error) { market.retryHistory() }
      }
      if reviewChart.loading {
        ChartLoadingBadge(theme: theme)
      }
      // 提示条压在图区上沿（§10.8），不占版面高度，所以走 overlay 不进 VStack。
      if draw.hint != nil {
        DrawingHintStrip(controller: draw)
          .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
          .padding(.top, 8)
      }
      // 选中态的那几个动作**不在图上**（2026-09-21）：竖屏它们顶掉画线栏上排的三个
      // 开关（见 `DrawingBar`），横屏排在标题下面那一行。从前它浮在图区下沿，
      // 正好盖掉半行 MACD 图例。
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .clipped()
  }
}

/// 「历史拉不下来，点一下重试」。样式原样，只是从 `chart` 里抬出来当一层。
struct ChartHistoryRetry: View {
  let theme: PanelTheme
  let text: String
  let action: () -> Void

  var body: some View {
    // 胶囊画出来约 32pt 高，命中区撑到 44（UI 审查 2026-09-24 §4.3 #33）：放大写在 `label` 里，
    // 外面再用负边距把版面收回来，画面一个点不变。
    Button(action: action) {
      Text(text).font(.caption).foregroundStyle(theme.ink2)
        .padding(.horizontal, Space.m).padding(.vertical, Space.s)
        .background(theme.raised, in: Capsule())
        .overlay(Capsule().strokeBorder(theme.line, lineWidth: 1))
        .padding(.vertical, Space.s)
        .hitTarget()
    }
    .buttonStyle(.plain)
    .padding(.vertical, -Space.s)
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    .padding(.top, Space.s)
  }
}

/// 复盘取数时压在图上的那枚「加载重温行情」。
struct ChartLoadingBadge: View {
  let theme: PanelTheme

  var body: some View {
    ProgressView("加载重温行情")
      .tint(theme.amber)
      .foregroundStyle(theme.ink2)
      .padding(16)
      .background(theme.raised, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
      .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(theme.line, lineWidth: 1))
  }
}

/// 回放态的页头（原 `MainScreen.reviewHeader`）。
struct ReplayHeaderView: View {
  let bridge: ReviewChartBridge
  /// 图上没给时区时按设置里那一档（`prefs.timeZone`）。
  let fallbackZone: TZChoice
  /// 同理，小数位兜底用当前品种的。
  let fallbackDecimals: Int
  @Environment(\.panelTheme) private var t

  var body: some View {
    // 字和颜色走令牌（UI 整改 P3）：标题 17 semibold `ink`，时刻 12 `ink3`，开高低收 12 等宽 `ink2`。
    // 原来一律系统默认色，深色皮肤下是纯白，和页面上别处的墨色不是一个调子。
    VStack(alignment: .leading, spacing: Space.xs) {
      Text("重温 · " + InstrumentID(bridge.state?.series.symbol ?? "").display)
        .font(TypeScale.title).foregroundStyle(t.ink)
      // 时间跟着**这张图自己的时区档**走，和时间轴、十字线、选区标签同一口径（审查 B-08）。
      // `Text(Date, style:)` 认的是设备时区：图表切到「交易所」之后，这一行和轴上
      // 写着两个时刻。
      HStack {
        Text(fmtFull(ms: Double(bridge.replayTime),
                     offsetMinutes: (bridge.state?.timezone ?? fallbackZone).offsetMinutes))
        Spacer()
      }.font(TypeScale.caption).monospacedDigit().foregroundStyle(t.ink3)
      if let series = bridge.state?.series, let open = series.open.last, let high = series.high.last, let low = series.low.last, let close = series.close.last {
        // 小数位由品种自己说（审查 B-07）：原来按「有效数字 1–7 位」写，
        // 回放头部的开高低收和顶栏的最新价能是两种写法。
        let p = bridge.state?.decimals ?? fallbackDecimals
        // 原来一行排不下就整行缩到 65%（最坏 7.8pt，UI 审查 2026-09-24 §4.3 #34）。
        // 现在不缩字：一行放得下就一行，放不下就折成两行（开高 / 低收）。
        let o = Text("开 " + fmtPrice(open, decimals: p)), h = Text("高 " + fmtPrice(high, decimals: p))
        let l = Text("低 " + fmtPrice(low, decimals: p)), c = Text("收 " + fmtPrice(close, decimals: p))
        ViewThatFits(in: .horizontal) {
          HStack(spacing: Space.s) { o; h; l; c }
          VStack(alignment: .leading, spacing: Space.xxs) {
            HStack(spacing: Space.s) { o; h }
            HStack(spacing: Space.s) { l; c }
          }
        }.font(TypeScale.caption).monospacedDigit().foregroundStyle(t.ink2).lineLimit(1)
      }
    }.pageHorizontalInset().padding(.vertical, Space.s)
  }
}

/// 记一笔卡片（§2F1）。**盖在图上**，不再排在图下面。
///
/// 原来它和图是同一根 `VStack` 里的两格，卡片一出来图就被压到剩下三分之一——
/// 而记一笔恰恰是「看着这段行情写点什么」，图被压扁了正好把要看的东西挤没了。
/// 现在它压在图的下沿，图一根 K 线都不动；用户想看被盖住的那截，点「收起」就是。
///
/// 卡片自带 `t.raised` 的不透明底（见 `ReviewCaptureCard`），所以盖上去不会
/// 透出 K 线；上沿补一条发丝线，让它读起来是「叠上来的一层」而不是图的一部分。
struct ReviewCaptureLayer: View {
  let feature: ReviewFeature
  let bridge: ReviewChartBridge
  let theme: PanelTheme
  /// 横屏图本来就矮，卡片不能占掉一半；竖屏给 280pt，正好是交接说明里的数。
  let maxHeight: CGFloat
  let onSaved: () -> Void
  @Environment(\.displayScale) private var displayScale

  var body: some View {
    if bridge.mode == .capture {
      VStack(spacing: 0) {
        Rectangle().fill(theme.line).frame(height: 1 / displayScale)
        ReviewCaptureCard(feature: feature, onSave: {
          if feature.saveRecord() {
            bridge.endCapture(feature: feature)
            onSaved()
          }
        }, onClose: { bridge.endCapture(feature: feature) })
        .frame(maxHeight: maxHeight)
      }
      .environment(\.reviewTheme, theme.review)
      .transition(.move(edge: .bottom))
    }
  }
}
