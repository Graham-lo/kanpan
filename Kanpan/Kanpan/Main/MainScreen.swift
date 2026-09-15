import KanpanChart
import KanpanCore
import KanpanData
import SwiftUI
import UIKit
import ReviewDomain
import ReviewUI
import KanpanAccount

/// 主界面（§9.1）。
///
/// 从上到下：顶栏 → 价格行 → 周期条 → 图（占满剩下的）→ 底部工具条五个。
/// 这一层只做接线：把 `MarketModel` 的行情和 `PrefsStore` 的设置揉成一份 `ChartState`
/// 交给图，再把图和面板的回调转回去。**任何计算都不该在这儿写**——算法在 `KanpanCore`，
/// 画在 `KanpanChart`，这里只负责让它们见面。
struct MainScreen: View {
  @State private var account = AccountFeature()
  @State private var accountBridge: AppAccountBridge?
  @State private var comfort = DisplayComfort()
  @Environment(\.accessibilityReduceMotion) private var systemReduceMotion
  @State private var market = MarketModel()
  @State private var store = PrefsStore()
  @State private var picker = SymbolPickerModel()
  @State private var quotes = QuoteBook()
  @State private var didBoot = false
  @State private var grace = BackgroundGrace()
  @State private var proxy = ChartProxy()
  @State private var review = ReviewFeature(directory: ReviewChartBridge.storageDirectory())
  @State private var reviewChart = ReviewChartBridge()

  @State private var panel: Panel?
  @State private var showQuickFavorites = false
  @State private var quickSearchPending = false
  /// 半屏弹层里点了「全部自选与分组」：等它关完再开全屏自选页。
  @State private var quickListPending = false
  @State private var showSymbols = false
  @State private var showFavorites = false
  /// 冷启动的自选盖层还在吗。详见 `launchFavorites`。
  @State private var launchCover = MainScreen.startsOnFavorites
  /// 账号那一侧已经「切」过一次了吗。
  ///
  /// 冷启动时 `account.restore()` 把登录态恢复回来，走的是和用户主动换号完全
  /// 同一条 `AppAccountBridge.onSwitch`。第一次不能当换号看——用户刚开 app，
  /// 本来就该停在自选页；盖层里那张表会跟着恢复出来的账号自己换
  /// （`onChange(of: picker.prefs.favorites)`）。
  @State private var didRestoreAccount = false
  /// 自选表的预热跑过了吗。见 `primeFavorites(_:)`。
  @State private var didPrimeFavorites = false
  /// 用户已经从首屏走开了吗（点了品种、关掉了自选页、或者主动换了账号）。
  ///
  /// 首屏盖层只能在「还没走开」的时候升起来。`launchCover` 的初值是拿上次存下的
  /// 自选表猜的，猜得不一定准——登录用户的自选表存在账号那份档案里，默认档案可能
  /// 是空的。账号恢复回来之后要按真表重判一次，这个标记保证那次重判不会把已经在
  /// 看图的用户拽回自选页。
  @State private var didLeaveLaunch = false
  /// 还在等 `account.restore()` 把登录态读回来吗。
  ///
  /// 这一小段里 `picker.prefs` 挂的还是访客那份空档案，不能拿「自选是空的」当真——
  /// 否则首屏盖层会当场让位给行情页，等账号回来再翻回自选，闪一下。
  @State private var awaitingAccount = false
  @State private var expandedChart = false
  /// 这次横屏是「点画线」带进来的吗——是的话画完要自己转回竖屏。
  @State private var landscapeForDrawing = false
  @StateObject private var draw = DrawingController()
  @State private var toast: String?
  @State private var toastID = 0
  /// Historical OHLC belongs only to the crosshair container.
  @State private var crosshair: Crosshair?
  /// 倒计时的当前时刻（毫秒）。`nil` = 不画。
  ///
  /// 渲染器**不读系统时钟**（`ChartState` 得是纯值，A3.11 的基线靠这条），时间只能
  /// 从外面喂进去。喂的人就是下面那个 `heartbeat()`。
  @State private var nowMs: Double?

  @Environment(\.colorScheme) private var scheme
  @Environment(\.scenePhase) private var phase
  @Environment(\.verticalSizeClass) private var vClass

  /// 上次存下来的自选表非空吗。只读一次，值在这一整次启动里不会变——
  /// 自选表本身是 `SymbolPickerModel` 在管，这儿只关心「第一帧该盖谁」。
  private static let startsOnFavorites = !SymbolPrefsStore().load().favorites.isEmpty

  private var prefs: Prefs { store.prefs }

  private var effectiveTheme: ThemeChoice { prefs.ambientTheme ? (comfort.automaticTheme ?? prefs.theme) : prefs.theme }
  private var seed: PaletteSeed { effectiveTheme.seed(systemDark: scheme == .dark) }
  private var dark: Bool { seed.dark }
  private var theme: PanelTheme { PanelTheme(seed: seed, redUp: prefs.redUp) }

  /// 设置里那两行域名（A6.10）。REST 和推送分开填，理由见 `APIHost.defaultStream`。
  private var hosts: BinanceHosts {
    BinanceHosts(fapi: prefs.apiHost, stream: prefs.streamHost,
      streamFallbacks: prefs.smartMarketRoute ? [APIHost.defaultStream, APIHost.gateway, APIHost.gatewayBackup] : [],
      oiProxy: APIHost.gateway, oiProxyFallbacks: [APIHost.gatewayBackup])
  }

  /// 横屏判据用高度的 size class，不用宽高比。
  ///
  /// iPad 横过来仍然是 regular × regular——那是「大屏竖版布局转个向」，不该切成
  /// 手机横屏那套（§10.7 说的是 iPhone 横屏；iPad 走 A8.3 的放大布局）。
  private var landscape: Bool { vClass == .compact || expandedChart }

  private var basePresentation: some View {
    Group {
      if landscape { landscapeBody } else { portraitBody }
    }
    .background(theme.app)
    .overlay(alignment: .topLeading) {
      #if DEBUG
      if ProcessInfo.processInfo.environment["KANPAN_CHART_DIAGNOSTICS"] == "1" {
        VStack {
        Text(market.source.rawValue).font(.system(size: 1)).opacity(0.01).accessibilityIdentifier("market.source").accessibilityValue(market.status.rawValue)
        Text(MarketNetworkDiagnostics.shared.lines).font(.system(size: 1)).opacity(0.01).accessibilityIdentifier("market.network")
        }.allowsHitTesting(false)
      }
      #endif
    }
    .overlay {
      if !landscape, panel != nil || draw.panel != nil { PanelDismissShield(onDismiss: dismissPanel) }
    }
    .preferredColorScheme(effectiveTheme.forced)
    .overlay(alignment: .bottom) { toastLayer }
    // 横屏的面板走自己那层侧栏，不挂系统 sheet：半屏 sheet 在 compact 高度下会被
    // 系统顶成全屏，图就整个没了。
    .prefsPanel(landscape ? .constant(nil) : $panel, store: store,
                onPickInterval: pick(interval:))
  }

  private var presentation: some View {
    basePresentation
    .sheet(isPresented: $showQuickFavorites, onDismiss: {
      if quickSearchPending { quickSearchPending = false; showSymbols = true }
      else if quickListPending { quickListPending = false; showFavorites = true }
    }) {
      FavoritesQuickPicker(model: picker, current: market.symbol,
        onClose: { showQuickFavorites = false },
        onSearch: { quickSearchPending = true; showQuickFavorites = false },
        onAll: { quickListPending = true; showQuickFavorites = false })
        .preferredColorScheme(effectiveTheme.forced)
    }
    .fullScreenCover(isPresented: $showSymbols) {
      SymbolPickerView(model: picker, redUp: prefs.redUp, onClose: { showSymbols = false },
                       onVisible: { quotes.watch($0) },
                       onRowVisibility: { quotes.watchRow($0, visible: $1) })
        .preferredColorScheme(effectiveTheme.forced)
    }
    .fullScreenCover(isPresented: $showFavorites) {
      favoritesPage { showFavorites = false; proxy.scrollToLatest(animated: false) }
        .preferredColorScheme(effectiveTheme.forced)
    }
    .overlay { launchFavorites }
  }

  private func favoritesPage(onClose: @escaping () -> Void) -> some View {
    FavoritesView(model: picker, redUp: prefs.redUp, basisTitle: prefs.changeBasis.shortTitle, updatedAt: quotes.lastListUpdate, feedStatus: quotes.status, feedDiagnostics: quotes.diagnostics,
                  onClose: onClose, onVisible: { quotes.watch($0) },
                  onRowVisibility: { quotes.watchRow($0, visible: $1) },
                  onHistoryVisibility: { quotes.watchHistory($0, visible: $1) })
  }

  /// 盖层此刻是不是真的盖着。`launchCover` 只说「还没离开首屏」，画不画还得看
  /// 自选表当下空不空——账号恢复之后这张表会整体换成那个账号的那一份，空表没什么可盖的。
  /// 图要不要渲染、报价要不要拉，都跟着这个值走，不能只看 `launchCover`。
  private var coveringLaunch: Bool { launchCover && (!picker.prefs.favorites.isEmpty || awaitingAccount) }

  /// 冷启动的自选盖层。
  ///
  /// 上次关掉 app 时自选表非空，这一次就该直接落在自选页上，中间不要漏出行情页。
  /// **不能用 `fullScreenCover` 来做这件事**：那东西的呈现要过一遍 UIKit 的 present
  /// 流程，哪怕把动画关掉（`disablesAnimations`），宿主也一定会先自己画一帧——抓帧
  /// 看到的就是 0.57 s 那张行情页。这里改成叠在同一棵视图树上的 `overlay`，它和宿主
  /// 在同一帧里布局，第一帧就是自选页。
  ///
  /// 只管「第一次」。用户一旦从这儿走开（关掉、或者点了某个品种），`launchCover`
  /// 就永久落下，之后再进自选走的还是原来那个 `showFavorites` 盖层，两条路不会同时在。
  @ViewBuilder private var launchFavorites: some View {
    if coveringLaunch {
      ZStack {
        // 背景要铺满整屏（盖住状态栏和 home indicator 那两条），但页面本身仍然待在
        // 安全区里——和 `fullScreenCover` 里的排版对齐。
        theme.app.ignoresSafeArea()
        favoritesPage { launchCover = false; didLeaveLaunch = true; proxy.scrollToLatest(animated: false) }
      }
    }
  }

  private var lifecycleContent: some View {
    presentation
    // 接线要排在盖层前面：`QuoteBook` 得先知道自选是哪些，才不会拿「图上那一个品种」
    // 去裁刚从盘上恢复出来的报价。`boot()` 自己有 `didBoot` 挡着，重复调用是空转。
    .onAppear { boot() }
    .task { boot() }
    // 开关一变、或前后台一切，这个 task 就整个重来（旧的先被取消），心跳跟着起停。
    .task(id: beating) { await heartbeat() }
    .onChange(of: phase) { _, now in
      switch now {
      case .background:
        // 先把后台运行额度要下来，再进后台状态：下面两处的宽限窗口靠它才有
        // CPU 可跑，短暂切走再回来就不必重连。
        grace.begin()
        market.enterBackground(); quotes.setForeground(false)
      case .active:
        grace.end()
        market.enterForeground(); quotes.setForeground(true)
      default: break
      }
    }
  }

  private var observedContent: some View {
    lifecycleContent
    .onReceive(NotificationCenter.default.publisher(for: UIScreen.brightnessDidChangeNotification)) { _ in refreshComfort() }
    .onChange(of: prefs.ambientTheme) { _, _ in refreshComfort() }
    .onChange(of: prefs.theme) { _, _ in refreshComfort() }
    .onChange(of: prefs.keepAwake, initial: true) { _, on in
      UIApplication.shared.isIdleTimerDisabled = on
    }
    .onChange(of: prefs.subs) { _, subs in market.setOIEnabled(subs.contains(.oi)) }
    .onChange(of: prefs.launchSnapshot) { _, on in market.setSnapshotEnabled(on) }
  }

  private var marketContent: some View {
    observedContent
    .onChange(of: hosts) { _, next in market.setHosts(next); quotes.configure(hosts: next, basis: prefs.changeBasis, source: market.source) }
    .onChange(of: prefs.changeBasis) { _, next in quotes.configure(hosts: hosts, basis: next, source: market.source) }
    .onChange(of: market.source) { _, next in quotes.configure(hosts: hosts, basis: prefs.changeBasis, source: next) }
    .onChange(of: showFavorites || showSymbols || coveringLaunch) { _, on in quotes.setVisible(on) }
    .onChange(of: picker.prefs.favorites) { _, symbols in settleFavorites(symbols) }
    .onChange(of: market.routing) { _, state in
      if state == .switched { say("已切换成功") }
    }
    .onChange(of: market.tradeQuote) { _, trade in
      if market.source == .binance, let trade, trade.symbol == market.symbol { quotes.ingestTrade(trade) }
    }
    .onChange(of: market.symbol) { _, symbol in quotes.setChartSymbol(symbol); accountBridge?.focus(symbol) }
    .onChange(of: store.notice) { _, note in
      if let note { say(note); store.clearNotice() }
    }
    .onChange(of: draw.full) { _, full in
      // A7.7：一个品种最多 50 条，满了只提示、不悄悄丢。
      if full { say("这个品种的线画满了（50 条）"); draw.full = false }
    }
  }

  var body: some View {
    marketContent
    .sheet(item: $draw.panel) { panel in
      DrawingSheet(controller: draw, panel: panel, decimals: market.info.pricePrecision)
    }
    .onChange(of: draw.notice, initial: true) { _, note in if let note { say(note); draw.notice = nil } }
    .environment(\.panelTheme, theme)
    .environment(\.accountFeature, account)
    .sheet(isPresented: Binding(get: { account.presented && panel != .settings && !review.bookOpen }, set: { account.presented = $0 })) { AccountView(feature: account).environment(\.panelTheme, theme) }
    .onChange(of: account.notice) { _, note in if let note { say(note); account.notice = nil } }
    .onChange(of: panel) { _, value in if value == nil { try? accountBridge?.applyPending() } }
    .onChange(of: draw.active) { _, active in
      if !active { try? accountBridge?.applyPending() }
      // 画线直接横过来，画完自己转回去（§10.7 的入口就此收在「画线」上）。
      if active {
        if !landscape { landscapeForDrawing = true; enterLandscape() }
      } else if landscapeForDrawing {
        landscapeForDrawing = false
        leaveLandscape()
      }
    }
    .fullScreenCover(isPresented: $review.bookOpen) {
      ReviewBook(feature: review).sheet(isPresented: $account.presented) { AccountView(feature: account).environment(\.panelTheme, theme) }
    }
    .onAppear { wireReview() }
    .onChange(of: review.notice) { _, note in if let note { say(note); review.notice = nil } }
    .onChange(of: reviewChart.notice) { _, note in if let note { say(note); reviewChart.notice = nil } }
    .onChange(of: phase) { _, phase in
      if phase != .active { review.saveDraft(); if reviewChart.playing { reviewChart.togglePlay(feature: review) } }
      else { accountBridge?.synchronize(); review.synchronize() }
    }
  }

  // ---------------------------------------------------------------- 各段

  private var portraitBody: some View {
    VStack(spacing: 0) {
      if reviewChart.mode == .replay { reviewHeader } else { header }
      hairline
      if !reviewChart.active { IntervalBar(
        theme: theme, quick: prefs.quickIntervals, current: market.interval,
        onPick: pick(interval:), onMore: { panel = .period },
        // 配置页，不连着关：开着它一次调好几项（和指标 / 设置一样）。
        onChart: { panel = .chart }, drawing: draw.active,
        onDraw: { dismissPanel(); draw.toggle() },
        onRecord: chartRecordAction
      )
      .background(theme.app) }
      hairline
      chart
      reviewControls
      hairline
      if draw.active {
        DrawingBar(controller: draw)
      }
      BottomBar(
        theme: theme, active: panel,
        onPanel: { p in panel = (panel == p) ? nil : p },
        onReview: { dismissPanel(); review.bookOpen = true; review.synchronize() }, reviewCount: review.pendingCount,
        onFavorites: { dismissPanel(); showFavorites = true; quotes.setVisible(true) }
      )
      .background(theme.app)
    }
  }

  /// 横屏（§10.7）：图占满，周期竖排贴左，工具竖排贴右，顶栏缩成一行小字压在图上。
  ///
  /// 安全区只吃左右两边（灵动岛横过来在左或右）——上下交给图自己占满，那正是横屏
  /// 想要的。右轴永远在图的右边，所以右边那条工具栏放在安全区**外面**、自己留白，
  /// 不然右轴文字会被切（A8.2）。
  private var landscapeBody: some View {
    HStack(spacing: 0) {
      IntervalRail(
        theme: theme, quick: prefs.quickIntervals, current: market.interval,
        onPick: pick(interval:), onMore: { panel = .period }
      )
      .background(theme.app)
      VStack(spacing: 0) {
        if reviewChart.mode == .replay { reviewHeader } else {
        LandscapeHeadline(
          theme: theme, symbol: market.symbol, price: readoutPrice,
          changePercent: displayedTicker?.changePercent,
          decimals: market.info.pricePrecision,
          onSymbol: { dismissPanel(); showQuickFavorites = true })
          .padding(.horizontal, 8).padding(.vertical, 4)
        if let text = topCandleData {
          Text(text).font(.system(size: 10, design: .monospaced)).foregroundStyle(theme.ink)
            .accessibilityIdentifier("chart.topOHLC")
        }
        }
        chart
        reviewControls
      }
      if draw.active {
        DrawingRail(controller: draw)
      }
      ToolRail(
        theme: theme, active: panel, drawing: draw.active,
        onPanel: { p in panel = (panel == p) ? nil : p },
        onDraw: { dismissPanel(); if reviewChart.active { endReview() }; draw.toggle() },
        onReview: { review.bookOpen = true; review.synchronize() },
        onRecord: startReviewCapture,
        onPortrait: {
          dismissPanel()
          landscapeForDrawing = false
          leaveLandscape()
        })
    }
    .overlay(alignment: .trailing) {
      SidePanelLayer(theme: theme, shown: panel != nil, onClose: dismissPanel) {
        sidePanelContent
      }
    }
  }

  /// 竖屏点「横屏」：先把布局切成横屏，再请系统把屏幕转过去（§10.7）。
  ///
  /// 两件事都要做。`expandedChart` 管的是「这一屏用哪套外壳」——iPad 横过来
  /// 竖直尺寸类仍是 regular，只有它说了算；`Orientation.rotate` 管的是手机上真的
  /// 把屏幕转过去，手机锁了方向照样转得动（锁的是跟重力转，不是 app 指定方向）。
  /// 回来那一格在横屏工具栏上，两边对称。
  ///
  /// 手机上只转屏、**不**置 `expandedChart`：转过去 `vClass` 自己就变 compact 了，
  /// 再多置一个标志，等用户哪天用手把手机转回竖着，标志还挂着，人就卡在一个
  /// 竖着的屏幕配一套横屏外壳里。iPad 反过来——横过来尺寸类不变，只有它说了算。
  private func enterLandscape() {
    if UIDevice.current.userInterfaceIdiom == .pad { expandedChart = true }
    else { Orientation.rotate(to: true) }
  }

  private func leaveLandscape() {
    expandedChart = false
    if UIDevice.current.userInterfaceIdiom != .pad { Orientation.rotate(to: false) }
  }

  /// 画线的时候横屏里**一个指标都不画**：画线要的就是一整屏的原始 K 线。
  ///
  /// 副图（成交量、MACD）好理解——它们只是把主图挤扁。主图上的均线要一起收掉则是
  /// 因为价格轴的上下界是把均线算进去一起取的：MA256 一挂上，量程被拉宽，K 线当场
  /// 被压扁、整体位置也挪了，这时候画的线和真正的价格结构对不上。所以横屏画线给的是
  /// 一张没有任何指标参与定标的图。
  ///
  /// 两个都只影响画出来的这一帧，`prefs.subs` 和 `prefs.overlays` 一个字没动——画完
  /// 退出画线，副图和均线原样回来，用户开着的那几个指标不需要重新打开。
  private var drawingCanvasOnly: Bool { draw.active && landscape }
  private var visibleSubs: [IndicatorID] { drawingCanvasOnly ? [] : prefs.subs }
  private var visibleOverlays: [IndicatorID] { drawingCanvasOnly ? [] : prefs.overlays }

  @ViewBuilder private var sidePanelContent: some View {
    if let which = panel {
      PanelSide(store: store, seed: seed, onClose: PanelDismiss { dismissPanel() }) {
        switch which {
        case .indicator: IndicatorPanel(store: store)
        case .period: PeriodPanel(store: store, onPick: pick(interval:))
        case .settings: SettingsPanel(store: store)
        case .chart: ChartPanel(store: store)
        }
      }
    }
  }

  private var header: some View {
    VStack(spacing: 0) {
      TopBar(
        theme: theme, symbol: market.symbol,
        starred: picker.isFavorite(market.symbol),
        status: market.status,
        onSymbol: { dismissPanel(); showQuickFavorites = true },
        onStatus: { say(statusLine) },
        onStar: {
          dismissPanel()
          let now = picker.toggleFavorite(market.symbol, info: market.info)
          say(now ? "已加入自选" : "已移出自选")
        })
      ZStack {
        PriceRow(theme: theme, ticker: displayedTicker, lastPrice: readoutPrice,
          decimals: market.info.pricePrecision)
          .opacity(topCandleData == nil ? 1 : 0)
          .accessibilityElement(children: .contain)
          .accessibilityIdentifier("market.quote")
          .accessibilityValue(quoteDiagnostics)
        if let text = topCandleData {
          Text(text).font(.system(size: 11, design: .monospaced))
            .foregroundStyle(theme.ink).frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityIdentifier("chart.topOHLC")
        }
      }
    }
    .padding(.horizontal, 12)
    .padding(.vertical, 8)
    .background(theme.app)
  }

  /// 长按状态圆点报的那一行（§10.5）。
  ///
  /// 除了状态本身还报「多久没推了」：WS 能连上但一帧不推的时候 `status` 仍是
  /// `.live`，光看颜色会以为一切正常——这一行是那种情况唯一看得见的线索。
  private var displayedTicker: Ticker? {
    if market.source == .okx { return market.ticker }
    if let quote = quotes.raw[market.symbol] { return quotes.presented(quote) }
    // MarketModel already receives Binance ticker frames as part of the
    // chart feed. Use that value immediately instead of waiting for the
    // separate list QuoteBook to open another socket.
    return market.ticker.map { quotes.presented($0) }
  }

  private var quoteDiagnostics: String {
    guard ProcessInfo.processInfo.environment["KANPAN_CHART_DIAGNOSTICS"] == "1" else { return "" }
    return "symbol=\(market.symbol);last=\(displayedTicker?.last ?? .nan);time=\(displayedTicker?.timeMs ?? 0)"
  }

  private var statusLine: String {
    let head: String
    switch market.status {
    case .live: head = "实时"
    case .reconnecting: head = "重连中"
    case .offline: head = "离线"
    }
    guard let at = market.lastPushAt else { return head + " · 还没收到推送" }
    let age = Int(Date().timeIntervalSince(at))
    return head + (age < 2 ? " · 刚刚更新" : " · \(age) 秒没动了")
  }

  /// Latest trade quote only; changing candle interval must never change its source.
  private var readoutPrice: Double? {
    return market.source == .okx ? market.series?.close.last : displayedTicker?.last
  }

  private var topCandleData: String? {
    guard prefs.dataDisplay == .top, let c = crosshair, let series = market.series, series.symbol == market.symbol, series.interval == market.interval,
          series.close.indices.contains(c.index) else { return nil }
    let i = c.index, p = market.info.pricePrecision
    return fmtFull(ms: Double(series.time(at: i)), offsetMinutes: prefs.timeZone.offsetMinutes)
      + "\n开 " + fmtNum(series.open[i], p) + "  高 " + fmtNum(series.high[i], p)
      + "\n低 " + fmtNum(series.low[i], p) + "  收 " + fmtNum(series.close[i], p)
      + "  量 " + fmtVol(series.volume[i])
  }

  /// 周期条上那颗「记」。复盘回放里没有「记」这回事，横屏归 `ToolRail` 管，
  /// 这两种情形返回 nil，条上那一格直接不排。
  private var chartRecordAction: (() -> Void)? {
    guard !reviewChart.active, !landscape else { return nil }
    return { startReviewCapture() }
  }

  private var chart: some View {
    ZStack(alignment: .bottomTrailing) {
      theme.chartBG
      ChartHost(
        portrait: !landscape,
        renderingActive: !showFavorites && !showSymbols && !coveringLaunch,
        panelOpen: panel != nil || draw.panel != nil,
        state: reviewChart.active ? reviewChart.state : chartState,
        proxy: reviewChart.active ? reviewChart.proxy : proxy,
        onView: { view in if !reviewChart.active { market.loadOI(view: view) } },
        onSubResize: { id, scale in store.update { $0.subHeightOverrides[id] = scale } },
        onSubReorder: { order in store.update { $0.subs = order } },
        onCrosshair: { crosshair = $0 },
        onNeedsHistory: { if reviewChart.mode == .replay { reviewChart.loadReplayPage(forward: false, feature: review) } else if !reviewChart.active { market.loadMore() } },
        // 面板打开时由原生遮罩消费首个触摸，只收起面板。
        onTapped: { dismissPanel() },
        onNotice: { say($0) },
        drawing: reviewChart.active ? nil : draw
      )
      .id(reviewChart.mode.rawValue)
      ReviewRangeOverlay(feature: review, bridge: reviewChart, liveProxy: proxy)
        .allowsHitTesting(reviewChart.mode == .capture)
      if market.routing == .switching, !reviewChart.active {
        Text("检测到当前链路不可用，正在切换智能链路")
          .font(.caption).padding(10).background(.regularMaterial, in: Capsule())
          .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top).padding(.top, 8)
          .allowsHitTesting(false).accessibilityIdentifier("market.routeSwitching")
      } else if let error = market.historyError, !reviewChart.active {
        Button(error) { market.retryHistory() }.font(.caption).padding(10)
          .background(.regularMaterial, in: Capsule()).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
          .padding(.top, 8)
      }
      if reviewChart.loading { ProgressView("加载重温行情").padding().background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12)) }
      // 提示条压在图区上沿（§10.8），不占版面高度，所以走 overlay 不进 VStack。
      if draw.hint != nil {
        DrawingHintStrip(controller: draw)
          .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
          .padding(.top, 8)
      }
      // 选中态的动作条同样浮在图上（贴下沿），理由见 `DrawingSelectionBar`。
      if draw.active, !landscape {
        DrawingSelectionBar(controller: draw)
          .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
          .padding(.bottom, 6)
      }
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .clipped()
  }

  private func wireReview() {
    review.onCapture = startReviewCapture
    review.onOpenChart = { record in
      dismissPanel(); draw.finish()
      reviewChart.open(record, feature: review, live: proxy.box?.chart.state ?? chartState, hosts: hosts)
    }
    review.onOpenMatch = { match, cutoff in
      dismissPanel(); draw.finish()
      reviewChart.openMatch(match, cutoff: cutoff, feature: review, live: proxy.box?.chart.state ?? chartState, hosts: hosts)
    }
    review.synchronize()
  }
  private func startReviewCapture() {
    dismissPanel(); draw.finish()
    reviewChart.beginCapture(feature: review, live: proxy.box?.chart.state ?? chartState, prefs: prefs, source: market.source)
  }
  private func endReview() {
    if reviewChart.mode == .capture { reviewChart.endCapture(feature: review) }
    else { reviewChart.exitReplay(feature: review) }
  }
  private var reviewHeader: some View {
    VStack(alignment: .leading, spacing: 5) {
      Text("重温 · " + (reviewChart.state?.series.symbol ?? "")).font(.headline)
      HStack {
        Text(Date(timeIntervalSince1970: Double(reviewChart.replayTime) / 1000), style: .date)
        Text(Date(timeIntervalSince1970: Double(reviewChart.replayTime) / 1000), style: .time)
        Spacer()
      }.font(.caption.monospacedDigit())
      if let series = reviewChart.state?.series, let open = series.open.last, let high = series.high.last, let low = series.low.last, let close = series.close.last {
        HStack(spacing: 10) {
          Text("开 " + open.formatted(.number.precision(.significantDigits(1...7))))
          Text("高 " + high.formatted(.number.precision(.significantDigits(1...7))))
          Text("低 " + low.formatted(.number.precision(.significantDigits(1...7))))
          Text("收 " + close.formatted(.number.precision(.significantDigits(1...7))))
        }.font(.caption.monospacedDigit()).lineLimit(1).minimumScaleFactor(0.65)
      }
    }.padding(.horizontal).padding(.vertical, 8)
  }
  @ViewBuilder private var reviewControls: some View {
    if reviewChart.mode == .capture {
      ReviewCaptureCard(feature: review, onSave: {
        if review.saveRecord() { reviewChart.endCapture(feature: review) }
      }, onClose: { reviewChart.endCapture(feature: review) })
      .frame(maxHeight: landscape ? 150 : 290)
    } else if reviewChart.mode == .replay {
      ReviewReplayControls(time: reviewChart.replayTime, playing: reviewChart.playing, speed: reviewChart.speed,
        onStep: { reviewChart.step($0, feature: review) }, onPlay: { reviewChart.togglePlay(feature: review) },
        onSpeed: { reviewChart.speed = reviewChart.speed == 4 ? 1 : reviewChart.speed * 2 },
        onJudgment: { reviewChart.jumpToJudgment(feature: review) }, onExit: endReview)
    }
  }

  private var hairline: some View {
    Rectangle().fill(theme.line).frame(height: 1 / UIScreen.main.scale)
  }

  @ViewBuilder private var toastLayer: some View {
    if let toast {
      Toast(theme: theme, text: toast)
        .padding(.bottom, 92)
        .allowsHitTesting(false)
    }
  }

  // ---------------------------------------------------------------- 图的输入

  /// 行情 + 设置 揉成一份 `ChartState`。
  ///
  /// `view` 这里给个占位：视野归图自己管，`ChartHost` 会按「换品种/换周期/换风格」
  /// 三种情形各自算一份真的（见 `ViewIntent`）。
  private var chartState: ChartState? {
    guard let s = market.series, s.symbol == market.symbol, s.interval == market.interval, s.count > 0 else { return nil }
    var result = ChartState(
      series: s,
      symbol: market.info,
      view: ViewWindow(to: Double(s.lastTime), span: Double(s.step) * 80),
      style: prefs.style,
      dark: dark,
      redUp: prefs.redUp,
      price: PriceTransform(mode: prefs.priceMode),
      overlays: visibleOverlays,
      subs: visibleSubs,
      params: prefs.params,
      timezone: prefs.timeZone,
      oi: market.oi,
      magnet: prefs.magnet,
      decimals: market.info.pricePrecision,
      options: prefs.chartOptions,
      nowMs: nowMs,
      subScale: subScale)
    // 走 OKX 兜底线路时持仓量根本取不到（`OISource` 只连币安）——让副图说实话，
    // 别一直挂「加载中」。
    result.oiSupported = market.source == .binance
    result.paletteSeed = seed
    result.hiddenOutputs = prefs.hiddenOutputs
    result.indicatorColors = prefs.indicatorColors
    result.rsiUpper = prefs.rsiUpper; result.rsiLower = prefs.rsiLower
    return result
  }

  /// 副图高度（A6.4）：`Prefs.subHeights` 是档位，图要的是倍率。
  ///
  /// 只报当前开着的那几个：`subHeights` 里会留着以前开过的指标的档位，全倒进去
  /// 没坏处但也没用，而且每帧都要比一次字典，不如只带用得上的。
  private var subScale: [IndicatorID: Double] {
    var out: [IndicatorID: Double] = [:]
    for id in visibleSubs { out[id] = prefs.scale(for: id) }
    return out
  }

  /// 心跳该不该跳：开关开着、且 app 在前台。
  ///
  /// 后台不跳有两层意思：省电，以及回到前台时 `.task(id:)` 会重来一遍，第一跳立刻把
  /// 停在后台那一刻的旧时间冲掉，不会先闪一秒错的倒计时。
  private var beating: Bool { phase == .active }

  /// 一秒一跳。倒计时读到秒就够，再快只是白耗。
  private func heartbeat() async {
    guard beating else { nowMs = nil; return }
    while !Task.isCancelled {
      nowMs = prefs.countdown ? Date().timeIntervalSince1970 * 1000 : nil
      market.refreshOIIfNeeded()
      quotes.tick()
      refreshComfort()
      do { try await Task.sleep(for: .seconds(1)) } catch { return }
    }
  }

  private func refreshComfort() {
    let screen = proxy.box?.window?.screen ?? UIApplication.shared.connectedScenes
      .compactMap { $0 as? UIWindowScene }.first(where: { $0.activationState == .foregroundActive })?.screen
    comfort.tick(prefs: prefs, active: phase == .active,
      brightness: Double(screen?.brightness ?? 0.5), systemDark: scheme == .dark,
      animated: !systemReduceMotion)
  }

  // ---------------------------------------------------------------- 动作

  /// 自选表这次算是定下来了：交给报价簿，顺手把第一次的预热跑了。
  ///
  /// 登录过的机器上，冷启动时 `boot()` 看到的自选表是**空的**——`AppAccountBridge`
  /// 初始化时先同步装上访客那份档案，账号自己那份要等 `account.restore()` 异步读回来。
  /// 所以「订阅自选、预热 K 线」这两件事不能只在 `boot()` 里做一次，得跟着表本身走。
  private func settleFavorites(_ symbols: [String]) {
    quotes.setFavorites(symbols)
    primeFavorites(symbols)
  }

  /// 自选表第一次有内容时的一次性预热：让报价订阅它、把 K 线提前拉好。
  private func primeFavorites(_ symbols: [String]) {
    guard !didPrimeFavorites, !symbols.isEmpty else { return }
    didPrimeFavorites = true
    // 冷启动从第一个分类看起。存下来的那个选中分组是给「同一次使用里来回切」用的，
    // 不该跨启动生效——这一份表是刚刚才定下来的（登录用户还等过一次账号恢复），
    // 所以这里才是重置的时机。
    picker.resetSelectedGroup()
    quotes.setVisible(showFavorites || showSymbols || coveringLaunch)
    // 冷启动第一屏就是自选页。趁用户在这儿看报价，把自选的 K 线、以及当前品种
    // 其他常用周期的 K 线先拉好，点进去、切周期第一帧就有图。
    market.prefetchFavorites(symbols, intervals: prefs.quickIntervals)
  }

  private func boot() {
    guard !didBoot else { return }
    didBoot = true
    // Start the chart feed before the account/catalog wiring so network I/O
    // overlaps the synchronous view setup and first frame rendering.
    market.setHosts(hosts)
    market.start(snapshot: prefs.launchSnapshot, interval: prefs.interval)
    wireAccount()
    picker.setSectionsActive(false)
    quotes.onReset = { picker.clearQuotes() }
    quotes.onScopeChange = { picker.retainQuotes(for: $0) }
    quotes.onUpdate = { picker.updateQuotes($0) }
    quotes.onHistory = { picker.setHistory($0, $1) }
    quotes.configure(hosts: hosts, basis: prefs.changeBasis, source: market.source)
    // 自选表要赶在 `setChartSymbol` 前面：后者会重算订阅范围，那时候如果自选还是空的，
    // `configure` 刚恢复出来的那批报价就会被裁到只剩图上这一个品种。
    //
    // 空表则一个字都别说。登录过的机器上这会儿挂着的是**访客**那份档案（`AppAccountBridge`
    // 初始化时同步装的），里面本来就没有自选；把这份空表交上去，`QuoteBook` 会认定
    // 「自选范围已知且为空」，刚从磁盘恢复出来的十几行报价当场被裁光。等
    // `account.restore()` 把账号那份读回来，走 `settleFavorites(_:)` 再交。
    if !picker.prefs.favorites.isEmpty { quotes.setFavorites(picker.prefs.favorites) }
    quotes.setChartSymbol(market.symbol)
    quotes.setForeground(phase != .background)
    picker.onPick = { info in
      showSymbols = false; showFavorites = false; showQuickFavorites = false
      launchCover = false; didLeaveLaunch = true
      if info.symbol == market.symbol { proxy.scrollToLatest(animated: false) }
      crosshair = nil
      market.switchTo(symbol: info.symbol)
    }
    picker.setLoader(market.catalogLoader)
    market.setOIEnabled(prefs.subs.contains(.oi))
    // Configure the catalog and its source before presenting the favorites list.
    // Otherwise FavoritesView can start its first catalog request against the
    // default Binance route while the host/source setup is still in flight.
    if !picker.prefs.favorites.isEmpty {
      // 盖层已经在了（`launchFavorites`）就别再叠一层 `fullScreenCover`。
      if !launchCover { showFavorites = true }
      primeFavorites(picker.prefs.favorites)
    }
  }

  private func wireAccount() {
    // Existing drawing fixtures keep their own isolated profile; account tests explicitly configure an endpoint.
    if ProcessInfo.processInfo.environment["KANPAN_TEST_PROFILE"] == "1",
       ProcessInfo.processInfo.environment["KANPAN_ACCOUNT_API_URL"] == nil { return }
    do {
      let bridge = try AppAccountBridge(account: account, prefs: store, symbols: picker, drawings: draw, review: review)
      bridge.canApply = { !draw.active && panel == nil && !reviewChart.active }
      bridge.onSwitch = {
        if reviewChart.mode == .capture { reviewChart.endCapture(feature: review) }
        else if reviewChart.mode == .replay { reviewChart.exitReplay(feature: review) }
        showFavorites = false; showSymbols = false; showQuickFavorites = false
        // 换号要把首屏盖层也掀掉（别让人对着上一个账号的自选表）；但冷启动恢复
        // 登录态是同一条路走过来的第一次，那一次盖层必须留着，否则第一眼看到的
        // 就是行情页——这正是真机上「冷启动没进自选」的成因，模拟器没登录才看不出来。
        if didRestoreAccount { launchCover = false; didLeaveLaunch = true }
        else {
          didRestoreAccount = true
          // `onSwitch()` 在 `symbols.useStorage` **之前**调用，这会儿 `picker.prefs`
          // 还是旧的。等这一趟同步的切换做完再看：恢复出来的账号要是根本没有自选，
          // 就没有盖层可留，照旧落在行情页。
          //
          // 顺带把这份表正式交给报价簿。`onChange(of: picker.prefs.favorites)` 只在
          // 表真的变了时才响；恢复出来还是空表的话它不响，而 `boot()` 那会儿也故意
          // 没交——不在这儿补一句，`QuoteBook` 就永远等着一份不会来的自选表。
          Task { @MainActor in
            // 恢复出来的这份表才是准的，首屏该不该盖按它重判一次：有自选就盖上
            // （默认档案是空的、`launchCover` 初值猜成 false 的机器也能进自选页），
            // 没有就照旧落在行情页。前提是用户还没自己走开。
            if picker.prefs.favorites.isEmpty { launchCover = false }
            else if !didLeaveLaunch, !showFavorites, !showSymbols { launchCover = true }
            settleFavorites(picker.prefs.favorites)
          }
        }
        dismissPanel(); crosshair = nil
      }
      accountBridge = bridge; bridge.focus(market.symbol)
      awaitingAccount = true
      Task { await account.restore(); awaitingAccount = false }
    } catch { say(error.localizedDescription) }
  }

  /// 收起面板。选完一项、或者手指落到图和别的控件上，都走这儿。
  private func dismissPanel() {
    // Chart taps also call this after setting the crosshair. Avoid publishing an
    // unchanged sheet binding from that callback while the chart is updating.
    if panel != nil { panel = nil }
    if draw.panel != nil { draw.panel = nil }
  }

  private func pick(interval iv: Interval) {
    dismissPanel()
    guard iv != market.interval else { return }
    store.update { $0.interval = iv }
    crosshair = nil
    market.switchTo(interval: iv)
    UISelectionFeedbackGenerator().selectionChanged()
  }

  private func say(_ text: String) {
    toastID += 1
    let mine = toastID
    withAnimation(.easeOut(duration: 0.18)) { toast = text }
    Task {
      try? await Task.sleep(for: .milliseconds(1600))
      if mine == toastID { withAnimation(.easeOut(duration: 0.22)) { toast = nil } }
    }
  }
}

#Preview { MainScreen() }
