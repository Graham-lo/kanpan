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
/// 从上到下：顶栏 → 价格行 → 周期条 → 图（占满剩下的）→ 常驻标签栏。
///
/// 2026-09-18 底栏改成了常驻标签栏（`TabBar`）：画线 · 图表 · 自选 · 设置，
/// 四格各是一张整页，底栏永远在，换页就是换一格（用户的话是「大部分 app 把常用的
/// 大分页都固定在底部，比如 tv 和推特都是」）。在这之前自选是全屏 cover、设置是
/// 半屏 sheet、复盘是另一层 cover，一层盖一层。现在这一层只剩一个 `tab`，
/// 品种搜索和品种整页仍然是 cover——它们是「从某一页里叫出来的东西」，不是分页。
/// 这一层只做接线：把 `MarketModel` 的行情和 `PrefsStore` 的设置揉成一份 `ChartState`
/// 交给图，再把图和面板的回调转回去。**任何计算都不该在这儿写**——算法在 `KanpanCore`，
/// 画在 `KanpanChart`，这里只负责让它们见面。
struct MainScreen: View {
  @State private var account = AccountFeature()
  @State private var accountBridge: AppAccountBridge?
  @State private var comfort = DisplayComfort()
  @Environment(\.accessibilityReduceMotion) private var systemReduceMotion
  /// 图上这个品种只是个占位。真正「上次看的那张图」要等档案（访客或账号）装进来
  /// 才知道，见 `honorProfile()`；`boot()` 里 `market.start(symbol:)` 会拿着那份
  /// 档案里的值开张，不会先开一张别的图再切过去。
  @State private var market = MarketModel(symbol: "BTCUSDT")
  @State private var store = PrefsStore(storage: PrefsStore.deviceStorage())
  @State private var picker = SymbolPickerModel(store: SymbolPrefsStore(storage: SymbolPrefsStore.deviceStorage()))
  /// 自选页上正在做的那次批量编辑（编辑模式 + 勾中的那几行 + 冻住的报价）。
  ///
  /// 它必须挂在宿主身上：`portraitBody` 里的 `switch tab` 会把自选页整个拆掉，
  /// 放在页面自己的 `@State` 里，人切去设置页看一眼回来，勾好的就全没了。
  /// 但它也只活在这一次使用里，不落盘——理由见 `FavoritesEditSession`。
  @State private var favoritesEdit = FavoritesEditSession()
  /// 画线工作台里那一层换品种开着没有。只在横屏画线时有意义。
  @State private var showDrawSwitcher = false
  @State private var quotes = QuoteBook()
  /// 板块页那一路的行情。它拉的是**全市场 24h ticker**（一趟就够），和 `QuoteBook`
  /// 那条按可见范围订阅的线完全不搭界，所以单独一份，只在板块页看得见时才跑。
  @State private var sectorFeed = SectorFeed()
  @State private var didBoot = false
  @State private var grace = BackgroundGrace()
  @State private var proxy = ChartProxy()
  @State private var review = ReviewFeature(directory: ReviewChartBridge.storageDirectory())
  @State private var reviewChart = ReviewChartBridge()

  @State private var panel: Panel?
  @State private var showSymbols = false
  /// 顶栏放大镜开的搜索页。换品种只有这一条路了：左上角的品种名以前开一个
  /// 半屏的「最近看过」弹层，搜索页做出来之后它就是重复入口，已经撤掉。
  @State private var showSearch = false
  /// 搜索页里点了「查看全部 N 个品种」：这一层关掉之后接着开品种整页，查询词跟着过去。
  @State private var searchAllPending = false
  /// 品种整页是从搜索页「查看全部」进来的吗。是的话它那颗返回要退回搜索页，
  /// 而不是一路退回主界面——人是从搜索页走过来的，返回就该原路走回去，
  /// 查询词也一并留着。挑中品种就作废（人已经走到图上了）。
  @State private var symbolsFromSearch = false
  /// 把人送进这张图的是哪一格。nil = 没有来路（底栏直接点的「图表」），顶栏不画返回。
  ///
  /// 底栏是常驻标签栏，每一格都是家；但板块下钻和自选行是「走进来」的，
  /// 走进来就得走得回去（用户：点进去之后没有返回按钮）。
  @State private var chartOrigin: Tab?
  /// 板块页压着的那几层。页归页，路由归宿主——见 `SectorPage.route`。
  @State private var sectorRoute: [SectorRoute] = []
  /// 这次复盘是从哪儿开的。退出复盘时按它把人放回原处。
  @State private var replayOrigin: ReplayOrigin?
  /// 历史搜索词。放在宿主身上，来回进出搜索页不丢。
  @State private var searchHistory = SearchHistory(storage: SearchHistory.deviceStorage())
  /// 停在哪一格。冷启动落在自选还是行情，看上次存下的自选表空不空。
  ///
  /// 这就是原来那个「冷启动自选盖层」的去处。以前得专门铺一层 `overlay`（不能用
  /// `fullScreenCover`：UIKit 的 present 一定会先画一帧宿主，实测漏出 0.57 s 的
  /// 行情页）。改成标签栏之后这件事自己就成立了——第一帧画的就是 `tab` 指着的那一页。
  /// 初值只是「还不知道」的占位。档案装进来（`boot()` 里同步装访客那份、
  /// 账号那份随 `account.restore()` 异步到）之后由 `honorProfile()` 定。
  @State private var tab: Tab = .chart
  /// 自选表的预热跑过了吗。见 `primeFavorites(_:)`。
  @State private var didPrimeFavorites = false
  /// `boot()` 已经把行情、报价簿、品种表这套线全接好了吗。
  ///
  /// `honorProfile()` 在 `boot()` **中间**也会被调到（冷启动同步装访客档案那一下），
  /// 那一刻行情还没开张、报价簿还没 configure，不能去动它们——`boot()` 自己接着
  /// 就会拿着刚装好的档案把这两件事做对。
  @State private var live = false
  /// 用户已经从首屏走开了吗（点了品种、自己换了一格标签、或者主动换了账号）。
  ///
  /// 首屏那一格只能在「还没走开」的时候改。`tab` 的初值是拿上次存下的自选表猜的，
  /// 猜得不一定准——登录用户的自选表存在账号那份档案里，默认档案可能是空的。
  /// 账号恢复回来之后要按真表重判一次，这个标记保证那次重判不会把已经在看图的
  /// 用户拽回自选页。
  @State private var didLeaveLaunch = false
  /// 还在等 `account.restore()` 把登录态读回来吗。
  ///
  /// 这一小段里 `picker.prefs` 挂的还是访客那份空档案，不能拿「自选是空的」当真——
  /// 否则首屏那一格会当场翻到行情页，等账号回来再翻回自选，闪一下。
  @State private var awaitingAccount = false
  @State private var expandedChart = false
  /// 这次横屏是「点画线」带进来的吗——是的话画完要自己转回竖屏。
  @State private var landscapeForDrawing = false
  @StateObject private var draw = DrawingController()
  @State private var toast: String?
  /// 这句话右边那颗按钮。和 `toast` 同一拍赋值。
  @State private var toastUndo: (() -> Void)?
  /// 那颗按钮上的字。默认「撤销」，「已记下 · 查看」时是「查看」（§2F2）。
  @State private var toastAction = "撤销"
  @State private var toastID = 0
  /// 「更多」那张周期网格摊开了没有。开着时它把图往下推，所以状态得住在这一层。
  @State private var intervalGrid = false
  /// 图还停在最新那根上没有。周期条行尾那颗「最新」靠它决定露不露面。
  @State private var atLatest = true
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
  // iPad 上一个 app 可能同时开两个窗口，落在不同缩放的屏上；`UIScreen.main`
  // 只认主屏，发丝线会画粗或画糊。环境里的 displayScale 跟着当前窗口走。
  @Environment(\.displayScale) private var displayScale

  // 「上次看的那张图」「第一帧停在哪一格」以前是这儿两个 `static` 在管，读的是
  // `SymbolPrefsStore()`——不注入存储时它落 `UserDefaults.standard`，而档案真身早就
  // 搬进了账号目录里的 `symbols.json`（`AppAccountBridge`）。写在文件里、读在
  // UserDefaults 里，两条道：新装机每次冷启动都开 BTCUSDT、第一帧永远是行情页，
  // 老用户则永远停在「升级到文件存储那一刻」的品种上。现在这两件事一律跟着
  // 档案自己的到达走，见 `honorProfile()`。

  private var prefs: Prefs { store.prefs }

  private var effectiveTheme: ThemeChoice { prefs.ambientTheme ? (comfort.automaticTheme ?? prefs.theme) : prefs.theme }
  private var seed: PaletteSeed { effectiveTheme.seed(skin: prefs.skin, systemDark: scheme == .dark) }
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
                onPickInterval: pick(interval:), onRecord: chartRecordAction)
  }

  private var presentation: some View {
    basePresentation
    .fullScreenCover(isPresented: $showSearch, onDismiss: {
      if searchAllPending { searchAllPending = false; symbolsFromSearch = true; showSymbols = true }
    }) {
      SymbolSearchView(model: picker, history: searchHistory, redUp: prefs.redUp,
                       onClose: { showSearch = false },
                       onAll: { searchAllPending = true; showSearch = false },
                       onVisible: { quotes.watch($0) },
                       onRowVisibility: { quotes.watchRow($0, visible: $1) })
        .preferredColorScheme(effectiveTheme.forced)
    }
    .fullScreenCover(isPresented: $showSymbols) {
      // 关掉品种页顺手把查询词清了：搜索页和它共用一个 `SymbolPickerModel`，
      // 词留着的话，下次点放大镜进来看到的是上一轮的结果，而不是「历史搜索 / 最近看过」。
      // 例外是从搜索页「查看全部」走进来的那一趟：那颗返回要原路退回搜索页，
      // 词得留着，不然退回去看到的是一张空搜索页。
      SymbolPickerView(model: picker, redUp: prefs.redUp,
                       onClose: { closeSymbolPicker() },
                       onVisible: { quotes.watch($0) },
                       onRowVisibility: { quotes.watchRow($0, visible: $1) })
        .preferredColorScheme(effectiveTheme.forced)
    }
  }

  /// 品种整页那颗返回。从搜索页「查看全部」走进来的，原路退回搜索页（词留着）；
  /// 别的路进来的就是关掉，顺手把词清了。
  private func closeSymbolPicker() {
    showSymbols = false
    if symbolsFromSearch {
      symbolsFromSearch = false
      showSearch = true
    } else {
      picker.query = ""
    }
  }

  /// 自选那一整页。标签栏上的一格，所以没有「返回」——返回就是换一格标签。
  private var favoritesPage: some View {
    FavoritesView(model: picker, session: favoritesEdit, history: searchHistory, store: store, redUp: prefs.redUp, basisTitle: prefs.changeBasis.shortTitle, updatedAt: quotes.lastListUpdate, feedStatus: quotes.status, feedDiagnostics: quotes.diagnostics,
                  onVisible: { quotes.watch($0) },
                  onRowVisibility: { quotes.watchRow($0, visible: $1) },
                  onHistoryVisibility: { quotes.watchHistory($0, visible: $1) })
  }

  /// 板块气泡页那一整页。计算全在 `KanpanCore`，画全在 `Kanpan/Sector/`，
  /// 这儿只把行情、红涨绿跌和「点中一行去看图」三根线接上。
  ///
  /// 点一行品种走的是 `picker.onPick` 同一条路——切到行情页、换品种、回到最新那一根，
  /// 而不是另起一套跳转，免得板块页进来的图和自选页进来的图行为不一样。
  private var sectorPage: some View {
    SectorPage(feed: sectorFeed, redUp: prefs.redUp,
               symbolForBase: { sectorFeed.symbol(forBase: $0) }, store: store,
               onPickSymbol: { symbol in
                 if let info = picker.info(for: symbol) { picker.pick(info) }
                 else {
                   if tab != .chart { chartOrigin = tab }
                   tab = .chart; didLeaveLaunch = true
                   crosshair = nil
                   // 目录还没载回来时点一行，以前只换图不记「最近」——同一个动作在
                   // 目录加载前后结果不一样，而且这张图下次冷启动也回不来。
                   picker.visit(symbol)
                   market.switchTo(symbol: symbol)
                 }
               },
               route: $sectorRoute)
  }

  /// 此刻画的是不是自选页。账号还在恢复的那一小段里，`picker.prefs` 挂的是访客那份
  /// 空档案，不能拿「自选是空的」当真——所以 `awaitingAccount` 也算数。
  private var showingFavorites: Bool {
    tab == .favorites && (!picker.prefs.favorites.isEmpty || awaitingAccount)
  }

  /// 报价簿要不要拉列表：看得见一列品种的时候才拉。
  private var listVisible: Bool { showingFavorites || showSymbols || showSearch }

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
        market.enterBackground(); quotes.setForeground(false); sectorFeed.setForeground(false)
      case .active:
        grace.end()
        market.enterForeground(); quotes.setForeground(true); sectorFeed.setForeground(true)
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
    // 面板 / 画线 / 复盘开着的时候云端设置是被挡下来的（会把人正在做的事掀掉）。
    // 关掉的这一刻补跑一次，别让人等下一轮全量（300 秒）。
    .onChange(of: syncGate) { _, open in if open { accountBridge?.resumeApply() } }
    // 「找相似」的范围两头对接（R3-5）：面板上改了就落进偏好，云端换下来一份
    // （或者换了账号）也照样灌回面板。两条都靠 `PrefsStore.update` 自带的
    // 「没真改动就不写」挡住回环，不会你来我往。
    .onChange(of: review.searchScope) { _, value in store.update { $0.reviewSearchScope = value } }
    .onChange(of: prefs.reviewSearchScope) { _, value in review.searchScope = value }
  }

  private var marketContent: some View {
    observedContent
    .onChange(of: hosts) { _, next in
      market.setHosts(next); quotes.configure(hosts: next, basis: prefs.changeBasis, source: market.source)
      sectorFeed.configure(hosts: next, source: market.source)
    }
    .onChange(of: prefs.changeBasis) { _, next in quotes.configure(hosts: hosts, basis: next, source: market.source) }
    .onChange(of: market.source) { _, next in
      quotes.configure(hosts: hosts, basis: prefs.changeBasis, source: next)
      sectorFeed.configure(hosts: hosts, source: next)
    }
    // 品种表是板块页认 base 的依据（兜底桶按它的标签凑，点行去看图也靠它拼全名）。
    // 它是异步载进来的，所以不能只在 `boot()` 里交一次。
    .onChange(of: picker.catalog.count) { _, _ in sectorFeed.setCatalog(picker.catalog) }
    .onChange(of: listVisible) { _, on in quotes.setVisible(on) }
    .onChange(of: picker.prefs.favorites) { _, symbols in settleFavorites(symbols) }
    .onChange(of: market.tradeQuote) { _, trade in
      if market.source == .binance, let trade, trade.symbol == market.symbol { quotes.ingestTrade(trade) }
    }
    .onChange(of: market.symbol) { _, symbol in quotes.setChartSymbol(symbol); accountBridge?.focus(symbol) }
    // 「常看」记的是**在这张图上真待住了**，不是「点开过」：搜索里滑过一下、点错一次
    // 立刻退出去的，都不该算一分。`task(id:)` 换品种就取消重来，离屏也取消，
    // 所以停不满 3 秒的那些一分都拿不到。
    .task(id: market.symbol) {
      let symbol = market.symbol
      guard !symbol.isEmpty else { return }
      try? await Task.sleep(for: .seconds(3))
      guard !Task.isCancelled else { return }
      picker.noteDwell(symbol)
    }
    .onChange(of: store.notice) { _, note in
      // 设置那一侧说的话（换下了哪个副图、常用行满了、已恢复默认）分两处落：
      // 面板开着的时候它归面板自己的 `panelToast` 说——主 toast 压在面板底下
      // 根本看不见；面板没开（比如周期网格里点图钉）才接到主 toast 上。
      // 两处加起来永远只有一层。
      if let note, panel == nil {
        let undo = store.noticeUndo
        store.clearNotice()
        say(note, undo: undo)
      }
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
    // 竖屏的「绘图」面板是一张半屏表单；横屏走 `drawToolsLayer` 那块贴边卡片，
    // 所以这儿要把横屏挡掉，不然两份会同时在场。
    .sheet(isPresented: Binding(get: { draw.picker && !landscape }, set: { draw.picker = $0 })) {
      DrawingToolPicker(controller: draw, store: store, onClose: { draw.picker = false })
        .presentationDetents([.large])
        .environment(\.panelTheme, theme)
    }
    .onChange(of: draw.notice, initial: true) { _, note in if let note { say(note); draw.notice = nil } }
    .environment(\.panelTheme, theme)
    .environment(\.accountFeature, account)
    .sheet(isPresented: Binding(get: { account.presented && !review.bookOpen }, set: { account.presented = $0 })) { AccountView(feature: account).environment(\.panelTheme, theme) }
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
      ReviewBook(feature: review)
        .environment(\.reviewTheme, theme.review)
        .sheet(isPresented: $account.presented) { AccountView(feature: account).environment(\.panelTheme, theme) }
    }
    .onAppear { wireReview() }
    .onChange(of: review.notice) { _, note in if let note { say(note); review.notice = nil } }
    .onChange(of: reviewChart.notice) { _, note in if let note { say(note); reviewChart.notice = nil } }
    .onChange(of: phase) { _, phase in
      // 根间距是节流写的（见 `PrefsStore.noteBarSpacing`）：最后一次缩放要是正卡在
      // 那 400ms 里，用户切后台顺手杀掉 app 就丢了。这儿先把欠的那一次落下去。
      if phase != .active { store.flushBarSpacing(); review.saveDraft(); if reviewChart.playing { reviewChart.togglePlay(feature: review) } }
      else { accountBridge?.synchronize(); review.synchronize() }
    }
  }

  // ---------------------------------------------------------------- 各段

  /// 竖屏：当前这一页 + 底下那条常驻标签栏。
  ///
  /// 三张整页共用同一棵视图树，所以行情的连接、报价、复盘那几个模型都挂在这一层
  /// 的宿主身上（`@State`），换页不重建、行情不断线。
  /// 底栏是**挂在页面上的**，不是页面下面再接的一节。
  ///
  /// 原来这儿是个 `VStack`：页占上面一段，底栏占下面一段，各画各的底。可页面的底不是
  /// 一个纯色——自选页身下是 `AuroraBackdrop`（光斑 + 越往下越浓的 wash + 颗粒），
  /// 于是底栏那一段等于把整页味道最足的收尾裁掉，换成一块平的 `theme.app`。用户连着指了
  /// 三回：「好像有点突兀能融合起来吗，因为其它都是融合的」「下方那块区域先是纯白显得不搭」
  /// 「我觉得白色不太好……其它地方全是融合的」。
  ///
  /// 换成 `safeAreaInset` 之后，页面仍然铺满整屏（它的底一直流到 home 条），底栏只是浮在
  /// 它上面的一排记号，同时把页面内容往上顶开一栏的高度——内容不会被压住，底也不再断。
  private var portraitBody: some View {
    Group {
      switch tab {
      // 「画线」不是一张页：点它是把当前这张图横过来画，所以它落在行情页上。
      case .chart, .draw: chartPage
      case .favorites: favoritesPage
      case .sectors: sectorPage
      case .settings: SettingsPanel(store: store, asPage: true)
      }
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    // 记一笔和回放这两种状态下标签栏收起来（§2F1 / §2G4）：这时候屏幕上已经有
    // 一套自己的操作（记下 / 收起、播放 / 退出），底下再摆一排分页，点哪个都像是
    // 要跑题。两种状态各自都有明确的回头路（卡片的「收起」、回放条的「退出」）。
    .safeAreaInset(edge: .bottom, spacing: 0) {
      if !reviewChart.active {
        TabBar(theme: theme, current: tab, drawing: draw.active, onPick: switchTo(tab:))
      }
    }
    // 键盘不许顶这三张常驻页，也不许顶标签栏。
    //
    // 用户报的是「锁屏解锁 / 从后台回来，图整个被挤到上半屏，底下空出一大块，必须划掉
    // 后台才好」。量他那张照片：选中格的中心在 617.6pt，正常是 814.3pt——底部安全区
    // 从 34pt 涨到了约 231pt，页面和标签栏被一起抬高了约 197pt。顶栏、周期条的位置和
    // 高度都没变，只有会伸缩的图区被压掉，这正是「底部安全区被撑大」的形状，不是丢数据。
    //
    // 这 197pt 是键盘留下的。SwiftUI 的键盘避让是加在**窗口**安全区上的一份 inset，
    // 而 `SymbolSearchView` / `SymbolPickerView` / `IndicatorPanel` / `AccountView` 都开着
    // `scrollDismissesKeyboard(.interactively)`——手指往下拖时键盘跟着走，停在任意高度；
    // 这时候把那层 `fullScreenCover` 撤掉（或者正好锁屏），第一响应者的辞职和页面的拆除
    // 撞在一起，窗口就留着一份半高的键盘 inset 不还。`f68b543` 当时记的那个「关搜索页
    // 之后留了一层铺满全屏的 `UITextEffectsWindow`」是同一件事的另一副样子。
    //
    // 根因修在这儿而不是去追那一次辞职的时序：图表 / 自选 / 设置这三张常驻页身上
    // 一个输入框都没有（搜索、选品种、指标参数、登录、重命名分类全在 cover / sheet /
    // alert 里，它们是各自独立的呈现，不吃这一层的安全区），所以键盘本来就没有理由动它们。
    // 只要它们不参与键盘避让，窗口那份 inset 就算真的卡住了也推不动画面。
    //
    // 唯一的例外是画线：iPad 上 `vClass` 恒为 `.regular`，横屏工作台也是走的这条
    // `portraitBody`，而 `DrawingBar` 的价格 / 文字 / 斐波那契那几个输入框是真的贴在
    // 底边、真的需要被键盘顶起来。所以画线开着的时候 `edges` 给空集，避让照旧。
    .ignoresSafeArea(.keyboard, edges: draw.active ? [] : .bottom)
  }

  /// 换一格标签。
  ///
  /// 「画线」那一格是个动作：先回到行情页，再横过去画（`draw.toggle()` 会触发
  /// `onChange(of: draw.active)` 里的转屏）。用户定的是「用户当前看的这张图作为
  /// 画线的目标，直接实现即可」——不问品种，画的就是眼前这张。
  private func switchTo(tab next: Tab) {
    dismissPanel()
    didLeaveLaunch = true
    guard next != .draw else {
      if reviewChart.active { endReview() }
      // 从别的一格点「画线」等于被带到了图上：这一格就是来路，画完退得回去。
      // 本来就在图上的话来路不变（可能是板块或自选带进来的，别把它抹了）。
      if tab != .chart { chartOrigin = tab }
      tab = .chart
      draw.toggle()
      return
    }
    // 底栏是常驻标签栏，自己点一格就是「回家」——上一次的来路作废，
    // 顶栏那颗返回跟着收起来。
    chartOrigin = nil
    // 再点一下已经站着的那一格 = 回到这一页的根。板块页下钻了两层时尤其需要：
    // 底栏那一格是它唯一的出口。
    if next == tab, next == .sectors { sectorRoute = [] }
    guard next != tab else { return }
    if next != .chart { draw.finish() }
    tab = next
    if next == .favorites { quotes.setVisible(true) }
    // 回到图上时**不要**一律跳到最新那根。
    //
    // 这一句是从旧的自选盖层那儿搬过来的：那会儿关掉盖层多半意味着「刚挑完品种」，
    // 跳最新是对的。改成常驻标签栏之后它变成了「每次点『图表』都跳一次」——人把图
    // 推回三月那一段，去设置里改个时区再点回来，位置没了。图那边本来是接得住的
    // （`ChartHost.makeUIView` 会把 `proxy.savedState` 里的视野、缩放、翻转原样接回
    // 来），是这一句把接回来的东西又推走了。
    //
    // 留下的只有一种情形：走的时候本来就停在最新那根上。那时候续上离开期间新到的
    // 那几根才是「他离开时的样子」，不是「回到默认」。真想从历史里回到最新，
    // 周期条行尾那颗「最新」就是干这个的。
    if next == .chart, atLatest { proxy.scrollToLatest(animated: false) }
  }

  /// 行情页那一整页：顶栏 → 价格行 → 周期条 → 图。
  private var chartPage: some View {
    VStack(spacing: 0) {
      if reviewChart.mode == .replay { reviewHeader } else { header }
      hairline
      if !reviewChart.active { IntervalBar(
        theme: theme, quick: prefs.quickIntervals, current: market.interval,
        atLatest: atLatest, gridOpen: $intervalGrid,
        onPick: pick(interval:),
        onPin: { iv in store.attempt { $0.toggleQuick(iv) } },
        onLatest: { proxy.scrollToLatest() },
        // 配置页，不连着关：开着它一次调好几项（和指标 / 设置一样）。
        onChart: { panel = .chart }
      )
      .background(theme.app) }
      hairline
      chart.overlay(alignment: .bottom) { captureCard }
      replayControls
      hairline
      if draw.active {
        DrawingBar(controller: draw)
      }
    }
  }

  /// 横屏（§10.7）：图占满，周期竖排贴左，工具竖排贴右，顶栏缩成一行小字压在图上。
  ///
  /// 安全区只吃左右两边（灵动岛横过来在左或右）——上下交给图自己占满，那正是横屏
  /// 想要的。右轴永远在图的右边，所以右边那条工具栏放在安全区**外面**、自己留白，
  /// 不然右轴文字会被切（A8.2）。
  /// 横屏的「绘图」面板：贴着左边的一块卡片，不是半屏表单（TV 横屏也是从边上推出来的
  /// 一块）。图还露着右边大半——挑工具的时候看得见自己要往哪儿画，这是它比表单强的地方。
  /// 靠左是因为右边那两条竖栏（画线动作、周期）都在右手底下，卡片压过去就挡住了。
  @ViewBuilder private var drawToolsLayer: some View {
    if draw.active, draw.picker {
      DrawingToolPicker(controller: draw, store: store, onClose: { draw.picker = false })
        .frame(width: 340)
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(theme.line, lineWidth: 0.5))
        .shadow(color: .black.opacity(0.24), radius: 14, x: 2, y: 2)
        .padding(.vertical, 6).padding(.leading, 6)
        .transition(.move(edge: .leading).combined(with: .opacity))
        .environment(\.panelTheme, theme)
    }
  }

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
          // 只有画线工作台里那一行是按钮，见 `DrawingSymbolSwitcher` 顶上那段。
          // 换品种和挑工具都贴在左边，同时开会叠在一起——开一个就把另一个收了。
          onTapSymbol: draw.active ? { draw.picker = false; showDrawSwitcher.toggle() } : nil)
          .padding(.horizontal, 8).padding(.vertical, 4)
        if let text = topCandleData {
          Text(text).font(.system(size: 10, design: .monospaced)).foregroundStyle(theme.ink)
            .accessibilityIdentifier("chart.topOHLC")
        }
        }
        // 选中一条线之后的 样式 / 锁定 / 复制 / 删除 排在**图外**这一条属性栏上（§2E2）。
        // 竖屏它是浮在图下沿的一条，横屏不能照搬：横屏的图就是画布，浮在上面的东西
        // 正好压着刚画的那一笔，也和「画布上不浮任何控件」相冲。挂在图上方、和标题
        // 同一根 `VStack` 里，选中 / 取消选中只在图外增减一行，K 线不会跟着跳。
        if draw.active, draw.selected != nil {
          DrawingSelectionBar(controller: draw, flat: true)
        }
        chart.overlay(alignment: .bottom) { captureCard }
        replayControls
        // 画线工作台的那根条排在图**下面**、图外面（§2E5）：横屏的高度金贵，但十四五个
        // 控件竖着摆放不下、横着摆绰绰有余，而且两个拇指本来就停在下沿。
        if draw.active {
          DrawingDock(controller: draw)
        }
      }
      ToolRail(
        theme: theme, drawing: draw.active,
        onDraw: { dismissPanel(); if reviewChart.active { endReview() }; draw.toggle() },
        onPortrait: {
          dismissPanel()
          landscapeForDrawing = false
          leaveLandscape()
        })
    }
    .overlay(alignment: .topLeading) { drawSwitcherLayer }
    // 换品种那一层开着的时候，键盘不许推整块横屏。
    //
    // 横屏的键盘是**半块屏**（iPhone 上约 209pt / 393pt）。默认的键盘避让会把整个
    // `HStack` 连 K 线一起往上顶，图被挤成一条，浮层自己也被顶出屏外——而用户点品种名
    // 的时候还在看图。所以这一层开着时整块不参与避让，改由 `DrawingSymbolSwitcher`
    // 自己把列表压到键盘上沿以内（见那边的 `listHeight`）。
    //
    // 只在这一层开着时关掉：画线的样式面板里还有价格 / 文字 / 斐波那契那几个输入框，
    // 它们仍然要被键盘顶起来。
    .ignoresSafeArea(.keyboard, edges: showDrawSwitcher ? .bottom : [])
    // 动画只裹住这一块。挂到整个 `body` 上会把图一起带进过渡，开合面板时 K 线跟着晃。
    .overlay(alignment: .leading) { drawToolsLayer.animation(.easeOut(duration: 0.18), value: draw.picker) }
    .overlay(alignment: .trailing) {
      SidePanelLayer(theme: theme, shown: panel != nil, onClose: dismissPanel) {
        sidePanelContent
      }
    }
    // 退出画线、或者品种已经换掉了，这一层就没有存在的理由了。
    .onChange(of: draw.active) { _, on in if !on { showDrawSwitcher = false } }
    .onChange(of: draw.picker) { _, on in if on { showDrawSwitcher = false } }
  }

  /// 画线工作台里那一层换品种（§见 `DrawingSymbolSwitcher`）。
  ///
  /// 铺一张透明的挡板接「点别处就收起」，浮层本体压在品种名底下——挡板不铺满就得靠
  /// 焦点丢失来收，那在横屏里根本不可靠（点 K 线并不会让输入框失焦）。
  @ViewBuilder private var drawSwitcherLayer: some View {
    if draw.active, showDrawSwitcher {
      ZStack(alignment: .topLeading) {
        Color.black.opacity(0.001)
          .contentShape(Rectangle())
          .onTapGesture { showDrawSwitcher = false }
          .accessibilityHidden(true)
        DrawingSymbolSwitcher(
          theme: theme,
          frequent: picker.frequentSymbols(),
          matches: { picker.matchingSymbols($0) },
          current: market.symbol,
          onPick: { symbol in switchDrawingSymbol(symbol) },
          onClose: { showDrawSwitcher = false })
          .padding(.leading, 60)
          .padding(.top, 40)
      }
      .ignoresSafeArea(edges: .bottom)
      .transition(.opacity)
    }
  }

  /// 在画线里换品种：走的是和别处一模一样的那条换品种路（`picker.pick(symbol:)`），
  /// 所以「最近」照记、行情照订、账号照同步——画线只需要跟着换目标就行。
  /// 不问「要不要保存」：每一笔画完就已经落盘了（`DrawingController.persist`），
  /// 用户说的「既然自动存那就不用管」。
  private func switchDrawingSymbol(_ symbol: String) {
    guard SymbolPrefs.key(symbol) != market.symbol else { return }
    picker.pick(symbol: symbol)
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
  /// 备用线路上持仓量整格不画（§2B）。
  ///
  /// `OISource` 只连币安，走兜底线路时这一格永远是空的。以前它照样占一格高度、
  /// 中间写一句「当前行情线路不提供持仓量」——那正是用户不想在界面上看到的
  /// 「线路」两个字，而且还白占了主图的地方。现在直接不排这一格，主图拿回高度；
  /// `prefs.subs` 一个字没动，线路回到币安它自己就回来了。
  private var visibleSubs: [IndicatorID] {
    if drawingCanvasOnly { return [] }
    guard market.source != .binance else { return prefs.subs }
    return prefs.subs.filter { $0 != .oi }
  }
  private var visibleOverlays: [IndicatorID] { drawingCanvasOnly ? [] : prefs.overlays }
  /// 长按拖完副图顺序之后，把这份新顺序合回 `prefs.subs`。
  ///
  /// 图上拖的是 `visibleSubs`——**只有看得见的那几格**。备用线路上持仓量整格不排，
  /// 横屏画线台干脆一格都不排。以前这里直接 `$0.subs = order`，等于把没排进来的
  /// 那几格当成用户删掉了：在非币安线路上拖一次副图顺序，持仓量就**永久消失**，
  /// 换回币安线路也回不来。
  ///
  /// 现在按「看得见的格子按新顺序重排，看不见的留在原来的坑里」合并：`prefs.subs`
  /// 从头走一遍，遇到这次参与拖动的位置就依次填 `order`，其余原样不动。
  private func merged(subs order: [IndicatorID]) -> [IndicatorID] {
    var queue = order[...]
    let moving = Set(order)
    return prefs.subs.map { id in
      guard moving.contains(id), let next = queue.popFirst() else { return id }
      return next
    }
  }

  @ViewBuilder private var sidePanelContent: some View {
    if let which = panel {
      PanelSide(store: store, seed: seed, onClose: PanelDismiss { dismissPanel() }) {
        switch which {
        case .period: IntervalGridPanel(store: store, onPick: pick(interval:))
        case .chart: ChartPanel(store: store)
        }
      }
    }
  }

  private var header: some View {
    VStack(spacing: 9) {
      // 顶栏没有自选星了（用户 2026-09-18 定的）：加自选统一在搜索页和自选页的
      // 品种行上做，那儿看得见一整列，挑着加；顶栏这一颗紧贴品种名，只会误触。
      // 复盘从底栏挪到了这儿：底栏换成常驻标签栏之后那四格是分页，复盘按用户的话
      // 「放到图表里」——它是看着某张图时才想起来的事。角标是还欠着答案的条数。
      TopBar(
        theme: theme, symbol: market.symbol,
        reviewCount: review.pendingCount,
        // 有来路才有返回。复盘态走的是另一副页头（`reviewHeader`），不经过这儿。
        onBack: chartOrigin.map { origin in { switchTo(tab: origin) } },
        onReview: { dismissPanel(); review.bookOpen = true; review.synchronize() },
        onSearch: { dismissPanel(); showSearch = true })
      ZStack {
        PriceRow(theme: theme, ticker: displayedTicker, lastPrice: readoutPrice,
          decimals: market.info.pricePrecision,
          volumeUnit: market.volumeUnit,
          openInterest: market.openInterestDisplay,
          openInterestUnit: market.openInterestUnit,
          totalSupply: market.totalSupply,
          fundingRate: market.funding?.fundingRate,
          stale: market.tickerStale)
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
    .padding(.top, 6)
    .padding(.bottom, 9)
    .background(theme.app)
  }

  private var displayedTicker: Ticker? {
    // 备用线路上先用它自己的一帧；它还没到（或这个品种它根本没有）就退回
    // 共享报价层里那口最后的价，顶栏灰显而不是退成骨架（§2B #54）。
    if market.source == .okx { return market.ticker ?? quotes.raw[market.symbol].map { quotes.presented($0) } }
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

  /// Latest trade quote only; changing candle interval must never change its source.
  private var readoutPrice: Double? {
    return market.source == .okx ? (market.series?.close.last ?? displayedTicker?.last) : displayedTicker?.last
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

  /// 「图表」那一页顶上的「记一笔」。复盘回放里没有「记」这回事，横屏归 `ToolRail` 管，
  /// 这两种情形返回 nil，那一条直接不排。
  private var chartRecordAction: (() -> Void)? {
    guard !reviewChart.active, !landscape else { return nil }
    return { startReviewCapture() }
  }

  private var chart: some View {
    ZStack(alignment: .bottomTrailing) {
      theme.chartBG
      ChartHost(
        portrait: !landscape,
        renderingActive: tab == .chart && !showSymbols && !showSearch,
        panelOpen: panel != nil || draw.panel != nil,
        state: reviewChart.active ? reviewChart.state : chartState,
        proxy: reviewChart.active ? reviewChart.proxy : proxy,
        onView: { view in
          if !reviewChart.active { market.loadOI(view: view) }
          // 视野一动就重算一次：周期条行尾那颗「最新」靠它露面 / 收起。
          let now = (reviewChart.active ? reviewChart.proxy : proxy).isAtLatest
          if now != atLatest { atLatest = now }
        },
        // 读的是 store 里**内存那一份**，不是 `prefs.barSpacing`：落盘是节流的，
        // 而用户捏完可能下一秒就换品种，那一下必须按刚刚捏出来的宽度开图。
        resetSpacing: store.liveBarSpacing,
        // 复盘只读这份根宽、不写回去：一进复盘 K 线不该突然变宽变窄，但复盘是在重放
        // 一段历史，它那边怎么拉怎么捏都不该改写用户平时看盘的习惯。
        onBarSpacing: { if !reviewChart.active { store.noteBarSpacing($0) } },
        onInversion: { main, subs in if !reviewChart.active { store.noteInversion(main: main, subs: subs) } },
        onSubResize: { id, scale in store.update { $0.subHeightOverrides[id] = scale } },
        onSubReorder: { order in let next = merged(subs: order); store.update { $0.subs = next } },
        onCrosshair: { crosshair = $0 },
        onNeedsHistory: { if reviewChart.mode == .replay { reviewChart.loadReplayPage(forward: false, feature: review) } else if !reviewChart.active { market.loadMore() } },
        // 面板打开时由原生遮罩消费首个触摸，只收起面板。
        onTapped: { dismissPanel() },
        onNotice: { say($0) },
        drawing: reviewChart.active ? nil : draw
      )
      .id(reviewChart.mode.rawValue)
      // 横屏画线时复盘的区间框、目标线和「等答案」标签一律不画（§2E5）：横屏那一屏
      // 要的是干净的原始 K 线，和「指标一律不画」是同一条理由——画布上多一根线，
      // 画的时候就多一次「这是我画的还是本来就有的」。记录本身没动，转回竖屏原样都在。
      ReviewRangeOverlay(feature: review, bridge: reviewChart, liveProxy: proxy,
                         suppressed: drawingCanvasOnly, flash: review.lastSaved)
        .allowsHitTesting(reviewChart.mode == .capture)
      // 切线路一律静默：用户要看的是 K 线，不是我们从哪台机器取的数。
      // 历史数据真拉不下来才出这一条——那是「图不全」，得让人知道并且能重试。
      if let error = market.historyError, !reviewChart.active {
        Button(error) { market.retryHistory() }.font(.caption).foregroundStyle(theme.ink2)
          .padding(.horizontal, 12).padding(.vertical, 8)
          .background(theme.raised, in: Capsule())
          .overlay(Capsule().strokeBorder(theme.line, lineWidth: 1))
          .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
          .padding(.top, 8)
      }
      if reviewChart.loading {
        ProgressView("加载重温行情")
          .tint(theme.amber)
          .foregroundStyle(theme.ink2)
          .padding(16)
          .background(theme.raised, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
          .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(theme.line, lineWidth: 1))
      }
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

  /// 这次重温是从哪儿开的。复盘本会在开图之前把自己关掉，退出时照这个把它开回来——
  /// 人是从一条记录（或那条记录的「找相似」）走进来的，出来就该站回那条记录上，
  /// 而不是被扔在一张不相干的行情图上。
  private enum ReplayOrigin: Equatable {
    /// 复盘本里的某一条记录。
    case record(UUID)
    /// 某条记录的「找相似」结果。退出时把记录和那张搜索层一并开回来。
    case search(UUID)
  }

  private func wireReview() {
    review.onCapture = startReviewCapture
    // 回放倍速跟着人走：初值从偏好来，那颗按钮一改就写回去（R3-4）。
    reviewChart.preferredSpeed = { store.prefs.replaySpeed }
    reviewChart.onSpeedChange = { value in store.update { $0.replaySpeed = Prefs.clampSpeed(value) } }
    // 「找相似」的范围同理。`ReviewUI` 那个包看不见 `Prefs`，所以在这儿对接两头：
    // 这一句灌初值，下面 `lifecycleContent` 里那两条 `onChange` 管往返（R3-5）。
    review.searchScope = prefs.reviewSearchScope
    review.onOpenChart = { record in
      dismissPanel(); draw.finish()
      replayOrigin = .record(record.id)
      reviewChart.open(record, feature: review, live: proxy.box?.chart.state ?? chartState, hosts: hosts)
    }
    review.onOpenMatch = { match, cutoff in
      dismissPanel(); draw.finish()
      replayOrigin = review.searchRecord.map { .search($0) }
      reviewChart.openMatch(match, cutoff: cutoff, feature: review, live: proxy.box?.chart.state ?? chartState, hosts: hosts)
    }
    review.synchronize()
  }
  private func startReviewCapture() {
    dismissPanel(); draw.finish()
    reviewChart.beginCapture(feature: review, live: proxy.box?.chart.state ?? chartState, prefs: prefs, source: market.source)
  }
  /// 退出复盘。
  ///
  /// `backToOrigin` 只有回放条上那颗「退出」才给 true——它是人主动说「看完了」，
  /// 该被放回复盘本。另外两个调用点（点「画线」、横屏工具栏的「绘图」）是人要去干
  /// 别的事，把复盘本糊在画线上面就成了挡路的。
  private func endReview(backToOrigin: Bool = false) {
    let replaying = reviewChart.mode == .replay
    let origin = replayOrigin
    replayOrigin = nil
    if reviewChart.mode == .capture { reviewChart.endCapture(feature: review) }
    else { reviewChart.exitReplay(feature: review) }
    guard backToOrigin, replaying, let origin else { return }
    switch origin {
    case .record(let id):
      review.bookOpen = true
      review.selectedRecord = id
    case .search(let id):
      review.bookOpen = true
      review.selectedRecord = id
      review.searchOpen = true
    }
    review.synchronize()
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
  /// 记一笔卡片（§2F1）。**盖在图上**，不再排在图下面。
  ///
  /// 原来它和图是同一根 `VStack` 里的两格，卡片一出来图就被压到剩下三分之一——
  /// 而记一笔恰恰是「看着这段行情写点什么」，图被压扁了正好把要看的东西挤没了。
  /// 现在它压在图的下沿，图一根 K 线都不动；用户想看被盖住的那截，点「收起」就是。
  ///
  /// 卡片自带 `t.raised` 的不透明底（见 `ReviewCaptureCard`），所以盖上去不会
  /// 透出 K 线；上沿补一条 `hairline`，让它读起来是「叠上来的一层」而不是图的一部分。
  @ViewBuilder private var captureCard: some View {
    if reviewChart.mode == .capture {
      VStack(spacing: 0) {
        hairline
        ReviewCaptureCard(feature: review, onSave: {
          if review.saveRecord() {
            reviewChart.endCapture(feature: review)
            // 「已记下 · 查看」：右边那颗直接翻到刚记的那条（§2F2）。
            // 图上那个新记号同时闪一下，两边指的是同一件事。
            say("已记下", actionTitle: "查看") {
              review.selectedRecord = review.lastSaved
              dismissPanel(); review.bookOpen = true; review.synchronize()
            }
          }
        }, onClose: { reviewChart.endCapture(feature: review) })
        // 横屏图本来就矮，卡片不能占掉一半；竖屏给 280pt，正好是交接说明里的数。
        .frame(maxHeight: landscape ? 150 : 280)
      }
      .environment(\.reviewTheme, theme.review)
      .transition(.move(edge: .bottom))
    }
  }

  /// 回放条。它是一条细的走带控制，压着图没意义（要看的就是图在往前走），
  /// 所以照旧排在图下面——被它顶掉的是主底栏，见 `portraitBody`（§2G4）。
  @ViewBuilder private var replayControls: some View {
    if reviewChart.mode == .replay {
      ReviewReplayControls(time: reviewChart.replayTime, playing: reviewChart.playing, speed: reviewChart.speed,
        onStep: { reviewChart.step($0, feature: review) }, onPlay: { reviewChart.togglePlay(feature: review) },
        onSpeed: { reviewChart.cycleSpeed() },
        onJudgment: { reviewChart.jumpToJudgment(feature: review) },
        onExit: { endReview(backToOrigin: true) })
      .environment(\.reviewTheme, theme.review)
    }
  }

  private var hairline: some View {
    Rectangle().fill(theme.line).frame(height: 1 / displayScale)
  }

  @ViewBuilder private var toastLayer: some View {
    if let toast {
      Toast(theme: theme, text: toast, actionTitle: toastAction, undo: toastUndo.map { act in
        { act(); withAnimation(.easeOut(duration: 0.22)) { self.toast = nil; toastUndo = nil } }
      })
        .padding(.bottom, 92)
        // 带撤销的那一条要能点；不带的照旧穿透，别挡住底下的图。
        .allowsHitTesting(toastUndo != nil)
    }
  }

  // ---------------------------------------------------------------- 图的输入

  /// 行情 + 设置 揉成一份 `ChartState`。
  ///
  /// `view` 这里给个占位：视野归图自己管，`ChartHost` 会按「换品种/换周期/换风格」
  /// 三种情形各自算一份真的（见 `ViewIntent`）。
  private var chartState: ChartState? {
    guard let s = market.series, s.symbol == market.symbol, s.interval == market.interval, s.count > 0 else { return nil }
    // 上下翻转跟着人走，不跟着品种走：换品种时这份 state 是新造的，翻转要是不从设置里
    // 带出来，图就会自己翻回去。开关关掉时不认存档里那一份——否则翻过去之后把开关一关，
    // 就再也没有把它翻回来的入口了。
    var price = PriceTransform(mode: prefs.priceMode)
    price.inverted = prefs.allowMainInversion && prefs.mainInverted
    var result = ChartState(
      series: s,
      symbol: market.info,
      view: ViewWindow(to: Double(s.lastTime), span: Double(s.step) * 80),
      style: prefs.style,
      dark: dark,
      redUp: prefs.redUp,
      price: price,
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
    result.subInverted = prefs.allowSubInversion ? prefs.subInverted : []
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
    // 这儿原来有一行 `picker.resetSelectedGroup()`，执行的是「冷启动从第一个分类
    // 看起」——理由写的是「存下来的那个选中分组只给『同一次使用里来回切』用，
    // 不该跨启动生效」。
    //
    // **2026-09-19 这条决定被推翻了，连那行代码一起删掉。** 新规矩是「所有交互状态
    // 跟着人走，无论怎么切换」，而「上次停在哪个分类」正是他用手改出来的习惯，不是
    // 分类自己的属性；冷启动也在必须穷举的切换路径里。旧做法恰恰是用户点名的那一类
    // ——「改过的设置在某条路径上悄悄回到默认值」。现在选中的分类跨启动保留，
    // 跟着账号同步（`SymbolPrefs.selectedGroupID`，本来就在存档里）。
    quotes.setVisible(listVisible)
    // 冷启动第一屏就是自选页。趁用户在这儿看报价，把自选的 K 线、以及当前品种
    // 其他常用周期的 K 线先拉好，点进去、切周期第一帧就有图。
    market.prefetchFavorites(symbols, intervals: prefs.quickIntervals)
  }

  private func boot() {
    guard !didBoot else { return }
    didBoot = true
    // 先把档案装进来，再开行情。
    //
    // 以前是反过来的（注释写着「让网络 I/O 和首帧渲染重叠」）：`market.start` 跑在
    // `wireAccount()` 前面，那一刻 `prefs` 还是出厂值——域名、周期、快照开关、
    // 「上次看的那张图」全是错的，得等档案装进来再逐个 `onChange` 补回去。实测就是
    // 「切到 4h、杀掉重开，回到 1h」。而且补回去意味着白打一趟跨洋请求、还让人先
    // 看一眼不是他上次那张图，比晚开这十几毫秒（几个小 JSON 的同步读盘）贵得多。
    // 连接预热本来就在 `LaunchPrewarm` 里更早跑着，这里挪后不影响握手。
    wireAccount()
    market.setHosts(hosts)
    market.start(snapshot: prefs.launchSnapshot, symbol: picker.prefs.recents.first, interval: prefs.interval)
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
    sectorFeed.configure(hosts: hosts, source: market.source)
    sectorFeed.setCatalog(picker.catalog)
    sectorFeed.setForeground(phase != .background)
    picker.onPick = { info in
      showSymbols = false; symbolsFromSearch = false
      showSearch = false; searchAllPending = false
      // 挑完品种落到行情页：自选、搜索、品种整页三条路都是「去看哪张图」。
      // 从别的一格走进来的，记下来路，顶栏那颗返回才回得去。
      if tab != .chart { chartOrigin = tab }
      tab = .chart; didLeaveLaunch = true
      if info.symbol == market.symbol { proxy.scrollToLatest(animated: false) }
      crosshair = nil
      market.switchTo(symbol: info.symbol)
    }
    picker.setLoader(market.catalogLoader)
    market.setOIEnabled(prefs.subs.contains(.oi))
    // Configure the catalog and its source before presenting the favorites list.
    // Otherwise FavoritesView can start its first catalog request against the
    // default Binance route while the host/source setup is still in flight.
    // 停在哪一格由 `honorProfile()` 按刚装进来的那份档案定，这儿只补预热。
    if !picker.prefs.favorites.isEmpty { primeFavorites(picker.prefs.favorites) }
    // 上次用的是哪把画线工具。只用来在工具面板上把那一格预选高亮（见 `Prefs.lastDrawTool`），
    // 不是「此刻正举着笔」——待画状态归图自己管，换品种照样清掉，冷启动也不会举着笔进来。
    draw.onPickTool = { tool in store.update { $0.lastDrawTool = tool.rawValue } }
    live = true
  }

  private func wireAccount() {
    // Existing drawing fixtures keep their own isolated profile; account tests explicitly configure an endpoint.
    if ProcessInfo.processInfo.environment["KANPAN_TEST_PROFILE"] == "1",
       ProcessInfo.processInfo.environment["KANPAN_ACCOUNT_API_URL"] == nil {
      // 没有账号桥，就没有「档案到货」那个事件；但档案本身在建 store 的那一刻就已经
      // 读进来了，落地页照样得按它兑现一次，否则有自选的人也停在行情页。
      honorProfile(); return
    }
    do {
      let bridge = try AppAccountBridge(account: account, prefs: store, symbols: picker, drawings: draw, review: review, search: searchHistory)
      bridge.canApply = { syncGate }
      bridge.onSwitch = {
        if reviewChart.mode == .capture { reviewChart.endCapture(feature: review) }
        else if reviewChart.mode == .replay { reviewChart.exitReplay(feature: review) }
        showSymbols = false; symbolsFromSearch = false
        showSearch = false; searchAllPending = false
        // 用户自己换号 / 退登，要把人从自选页带走（别让他对着上一个账号的表）。
        // 冷启动那一段不算：装访客档案、以及 `account.restore()` 把登录态读回来，
        // 走的是同一条路，那时候该停哪一格交给 `honorProfile()` 按真档案定。
        if !awaitingAccount { tab = .chart; didLeaveLaunch = true }
        // 正勾着的那次批量编辑跟着走：换了号，表就不是刚才那张表了，
        // 勾中的代号留着只会落到别人的自选上。
        if !awaitingAccount { favoritesEdit.end() }
        dismissPanel(); crosshair = nil
      }
      // 档案真的装进来之后才谈「该开哪张图、该停在哪一格、该用哪个周期」。
      bridge.onProfileReady = { honorProfile() }
      // 冷启动这一段（装访客档案 → 等 `account.restore()`）里手上可能还是访客那份
      // 空档案，落地页不能拿它当真，所以先把旗子举起来再装档案。
      awaitingAccount = true
      try bridge.activate()
      accountBridge = bridge; bridge.focus(market.symbol)
      // 内存告警时放掉 K 线缓存：入口只负责听（`KanpanApp`），这里登记谁来收。
      MemoryWarningRelay.shared.register(id: "market") { [weak market] in market?.memoryWarning() }
      Task {
        await account.restore()
        awaitingAccount = false
        // 从没登录过的人在 `restore()` 里 `guard let client` / `savedUser()` 就返回了，
        // `onPrepareAccount` 一次都不调——这一句是他们那条路上唯一的兑现点，
        // 少了它「有自选的访客冷启动一定落在行情页」（R3-2）就修不掉。
        honorProfile()
      }
    } catch {
      // 桥没建起来（存储目录不可写之类）：档案换不进来了，但手上这份仍然是从本机
      // 读出来的真档案，落地页同样要兑现一次——不能因为同步坏了就把人扔回行情页。
      say(error.localizedDescription)
      awaitingAccount = false
      honorProfile()
    }
  }

  /// 面板 / 画线 / 复盘都不开着——云端设置可以往下落了。
  private var syncGate: Bool { !draw.active && panel == nil && !reviewChart.active }

  /// 档案（prefs / symbols）真的换进来之后，把「该开哪张图、该停在哪一格、
  /// 该用哪个周期」按新档案重新兑现一次。
  ///
  /// 这三件事以前各修各的，而且各漏各的：品种去读 `SymbolPrefsStore()` 那个没注入
  /// 存储的柜子（写在账号文件里、读在 UserDefaults 里）；周期只在 `boot()` 里读一次，
  /// 那一刻档案还没装进来，读到的是出厂 1h，而 `launchSnapshot` / `subs` /
  /// `changeBasis` 各自有 `onChange` 兜底、唯独它没有；落地页则挂在 `onSwitch` 上，
  /// 没登录过的人一次都不响。它们是同一个时序病根——**逐个字段补 `onChange` 本身
  /// 就是会漏的结构**，所以统一挂到「档案到货」这一个事件上
  /// （`AppAccountBridge.onProfileReady`，冷启动、登录、退登、云端设置落地都会响）。
  private func honorProfile() {
    let profile = picker.prefs
    if !didLeaveLaunch {
      // 落地页：有自选就停在自选。还在等 `account.restore()` 的那一小段里手上挂的
      // 是访客那份空档案，不能拿「自选是空的」当真，否则会先翻到行情页、账号回来
      // 再翻回自选，闪一下。
      if !profile.favorites.isEmpty { if !showSymbols, !showSearch { tab = .favorites } }
      else if !awaitingAccount { tab = .chart }
      // 上次看的那张图。`boot()` 中途调到这儿时行情还没开张，那一次交给
      // `market.start(symbol:)` 直接开对，不在这儿切。
      if live, let last = profile.recents.first, last != market.symbol {
        crosshair = nil; market.switchTo(symbol: last)
      }
    }
    // 周期跟着人走（已经从 `PersonalSyncCodec.keepDeviceFields` 里拿出来了）。
    // 复盘在跑的时候图是复盘自己的，别动。
    if live, !reviewChart.active, prefs.interval != market.interval {
      crosshair = nil; market.switchTo(interval: prefs.interval)
    }
    // 报价簿要等 `boot()` 把线接好才认表；`boot()` 自己会交一次。
    if live { settleFavorites(profile.favorites) }
  }

  /// 收起面板。选完一项、或者手指落到图和别的控件上，都走这儿。
  private func dismissPanel() {
    // Chart taps also call this after setting the crosshair. Avoid publishing an
    // unchanged sheet binding from that callback while the chart is updating.
    if panel != nil { panel = nil }
    if draw.panel != nil { draw.panel = nil }
    if intervalGrid { withAnimation(.easeOut(duration: 0.18)) { intervalGrid = false } }
  }

  private func pick(interval iv: Interval) {
    dismissPanel()
    guard iv != market.interval else { return }
    store.update { $0.interval = iv }
    crosshair = nil
    market.switchTo(interval: iv)
    UISelectionFeedbackGenerator().selectionChanged()
  }

  /// 说一句话。全屏只有这一层，新的一句直接顶掉旧的（`toastID` 就是用来作废旧计时器的）。
  ///
  /// 给了 `undo` 就在右边画一颗按钮并停 5 秒：1.6 秒只够读完，来不及看清、
  /// 决定、再抬手点。不给就还是 1.6 秒。按钮上的字默认是「撤销」，
  /// 「已记下 · 查看」这类「去看看」用 `actionTitle` 换掉。
  private func say(_ text: String, actionTitle: String = "撤销", undo: (() -> Void)? = nil) {
    toastID += 1
    let mine = toastID
    toastUndo = undo
    toastAction = actionTitle
    withAnimation(.easeOut(duration: 0.18)) { toast = text }
    let stay = undo == nil ? 1600 : 5000
    Task {
      try? await Task.sleep(for: .milliseconds(stay))
      if mine == toastID {
        withAnimation(.easeOut(duration: 0.22)) { toast = nil; toastUndo = nil }
      }
    }
  }
}

#Preview { MainScreen() }
