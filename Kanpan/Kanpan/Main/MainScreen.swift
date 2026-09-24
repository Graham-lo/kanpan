import KanpanChart
import KanpanCore
import KanpanData
import KanpanNetwork
import SwiftUI
import UIKit
import ReviewData
import ReviewDomain
import ReviewUI
import KanpanAccount

// ⚠️ 这个文件有一条**嵌套层数上限**，加修饰符之前先读完这段。
//
// 2026-09-22：iPhone 16 Pro / iOS 27.0 上这个 app 点开就闪退，九次崩溃报告一个签名：
// `EXC_BAD_ACCESS (SIGSEGV)` + `Thread stack size exceeded`，主线程栈顶是
// `swift_getTypeByMangledNameInContext2` → `decodeMangledType` → `buildDescriptorPath`
// 的无尽递归，往下依次是 `MainScreen.header.getter` → `chartPage` → `portraitBody`
// → `basePresentation` → `presentation` → `MainScreen.body.getter`。
//
// 根因不是逻辑，是**类型**：SwiftUI 里每加一个修饰符就把整棵具体类型再套一层
// `ModifiedContent<...>`，而 `some View` 的计算属性和泛型包装都**不会**断开这个累加。
// 当时 `body` 那条主链一共一百四十一层，运行时按 mangled name 实例化这个类型的元数据
// 时递归太深，主线程 1MB 的栈直接撞穿。iOS 26 模拟器不崩，只有真机 iOS 27 崩，
// 所以「编译过了 / 模拟器能跑」在这件事上一点都不算数。
//
// 修法是把层数摘出去，现在主链在四十层以内。能断开累加的只有两样：
//   * **非泛型的 `View` struct**——它的 `body` 是一个全新的类型根；
//   * **自定义 `ViewModifier`**——`body(content:)` 的 `Content` 是
//     `_ViewModifier_Content<Self>`，不带宿主的类型。
// 所以 `header` / `chart` / `reviewHeader` / `captureCard` 和那三十一个观察者
// （`onChange` / `onReceive` / `task(id:)`）都搬去了 `MainScreenParts.swift`。
//
// **要加观察者就往 `MainScreenObservers` 里加，不要重新挂回 `body` 这条链上**；
// 要加界面就新开一个 `View` struct，别在 `chartPage` / `portraitBody` 上接修饰符。
// 加之前数一数：`body` → `lifecycleContent` → `presentation` → `basePresentation`
// → `portraitBody` → `chartPage` 这一路的顶层修饰符总数得留在四十以内。

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
  ///
  /// 行情、报价簿、对比、十字线读数都归 `ChartSession`（审查 21）：逐笔推送只该叫醒图和
  /// 顶栏那几块，不该叫醒这张根视图。下面的 `market` / `quotes` 等只是它的简写。
  @State private var session: ChartSession
  private var market: MarketModel { session.market }
  /// 第一帧的底色不能等档案。
  ///
  /// 设置的真身在账号目录里的 `prefs.json`，而这个 `store` 是在第一帧**之前**构造的，
  /// 那一刻只有 `UserDefaults` 可读（里头没有 prefs 这个键）。不给起点的话，
  /// 一个选了「陶土 · 深色」的人每次冷启动都会先看一眼青苔、等档案回来再整屏换一次。
  /// 所以拿本机镜像当起点，见 `LaunchThemeMirror`。
  @State private var store: PrefsStore
  /// 图的视野（根宽）由它一个人说了算：什么时候记、什么时候写、什么时候听档案的，
  /// 规则全在 `ChartViewport` 里。这一层只负责**报事件**——用户在捏、手松了、
  /// 档案到货了——**一个字都不许自己决定要不要写盘**。
  @State private var viewport: ChartViewport
  @State private var picker = SymbolPickerModel(store: SymbolPrefsStore(storage: SymbolPrefsStore.deviceStorage()),
                                                venueCategory: { VenueRegistry.descriptor(forSymbol: $0).favoriteCategory })
  /// 自选页上正在做的那次批量编辑（编辑模式 + 勾中的那几行 + 冻住的报价）。
  ///
  /// 它必须挂在宿主身上：`portraitBody` 里的 `switch tab` 会把自选页整个拆掉，
  /// 放在页面自己的 `@State` 里，人切去设置页看一眼回来，勾好的就全没了。
  /// 但它也只活在这一次使用里，不落盘——理由见 `FavoritesEditSession`。
  @State private var favoritesEdit = FavoritesEditSession()
  /// 画线工作台里那一层换品种开着没有。只在横屏画线时有意义。
  @State private var showDrawSwitcher = false
  private var quotes: QuoteBook { session.quotes }
  /// 板块页那一路的行情。它拉的是**全市场 24h ticker**（一趟就够），和 `QuoteBook`
  /// 那条按可见范围订阅的线完全不搭界，所以单独一份，只在板块页看得见时才跑。
  @State private var sectorFeed = SectorFeed()
  /// 对比 K 线的行情（`Kanpan/Kanpan/Compare/`）：集合在 `prefs.compareSymbols`，这里只管拉数与对齐。
  private var comparison: CompareModel { session.comparison }
  @State private var showComparePicker = false
  /// 长按一行品种弹出来那张预览卡的数据（§4.1）。自选页和板块品种列表共用一份，
  /// 所以它挂在这儿而不是各自页里——两张表长按同一个品种只取一趟。
  @State private var previews = SymbolPreviewStore()
  /// 「这棵根真的没了」的信号。行情、报价簿、后台额度都挂在上面这些 `@State` 上，
  /// 而 SwiftUI 从不说「这个 View 销毁了」——见 `RootTeardown`。
  @State private var teardown = RootTeardown()
  @State private var grace = BackgroundGrace()
  @State private var proxy = ChartProxy()
  @State private var review = ReviewFeature()
  /// 复盘待办到点叫人的唯一一处（本机日历通知；没有通知权限时前台自己补叫）。
  @State private var reviewDue = ReviewDueReminders.live()
  @State private var reviewChart = ReviewChartBridge()

  @State private var panel: Panel?
  /// 顶栏放大镜开的搜索页，以及它「查看全部」通往的品种整页（见 `SymbolSearchFlow`，
  /// 自选页用的是同一个）。换品种只有这一条路了：左上角的品种名以前开一个
  /// 半屏的「最近看过」弹层，搜索页做出来之后它就是重复入口，已经撤掉。
  @State private var symbolSearch = SymbolSearchFlow()
  /// 把人送进这张图的是哪一格。nil = 没有来路（底栏直接点的「图表」），顶栏不画返回。
  ///
  /// 底栏是常驻标签栏，每一格都是家；但板块下钻和自选行是「走进来」的，
  /// 走进来就得走得回去（用户：点进去之后没有返回按钮）。
  @State private var chartOrigin: Tab?
  /// 板块页压着的那几层。页归页，路由归宿主——见 `SectorPage.route`。
  @State private var sectorRoute: [SectorRoute] = []
  /// 连续扫图（§10.1）：走进这张图的那一刻，那张列表的顺序。
  ///
  /// nil = 这一趟没有名单（底栏直接点「图表」、顶栏搜索、深链进来的）——那时候横滑
  /// 什么都不做。名单在离开标签页时作废（见 `switchTo(tab:)`），不跨越一次「出去再进来」。
  @State private var scanList: ScanList?
  /// 「看细节」钻下去之前的那些视野，按周期记（§10.1）。切回大周期时回到原处。
  @State private var detailZoom = DetailZoomStack()
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
  ///
  /// 初值不再写死 `.chart`：上一次档案判定的落点在本机有一份镜像（`LaunchLandingMirror`），
  /// 判的是自选页就从第一帧起画自选——登录用户的档案要等 `account.restore()` 回来，
  /// 写死图表就是「先画 BTC 图、约 0.2s 后跳自选」那一闪。
  @State private var tab: Tab = LaunchLandingMirror.favorites ? .favorites : .chart
  /// 第一帧是按镜像停在自选页的、而真档案还没到货吗。
  ///
  /// 这一段里 `picker.prefs` 挂的还是访客那份（登录用户的自选表在账号档案里），
  /// 自选页只铺底（`FavoritesLandingPlaceholder`），不画「这一栏还空着」。
  /// 档案判定一次（`honorProfile()`）或用户自己换一格就放下。
  @State private var landingHeld = LaunchLandingMirror.favorites
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
  /// 画线壳。`@Observable`：这一页只在读到的那几个字段（`active` / `panel` / `picker` /
  /// `full` / `notice` / `previewing`）真变了的时候才重算，拖线、落点那一串内部状态不再
  /// 把整页叫起来（审查 16.1）。挂在 `@State` 上，和从前的 `@StateObject` 一样跟着这一页活。
  @State private var draw = DrawingController()
  /// 提醒那一摊：存档、画完线问的那一句、以及「响了」怎么走到用户眼前。
  /// 三个都挂在宿主这一层，换页不重建（和行情、复盘那几个模型同一个理由）。
  @StateObject private var alerts = AlertStore()
  @StateObject private var alertPrompt = AlertPromptModel()
  /// 选中一条线时画线栏上那句「跌到 64,000 叫我」。放在 `@State` 里而不是 `@StateObject`：
  /// 它逐笔跟着现价变，主屏不该跟着它重算，只有胶囊自己观察它。
  @State private var lineAlert = LineAlertModel()
  @StateObject private var alertWatcher = AlertWatcher()
  /// 提醒「盯一个」挂在锁屏上的那块实时活动（一台设备一块）。
  @StateObject private var activities = AlertActivityController()
  /// 前台的到价判定。没有 APNs 密钥，它是提醒在这台手机上唯一会响的那条路。
  @StateObject private var alertEngine = AlertEngine()
  /// 自选五分钟波动提醒的前台那一半（P3.1）。
  @State private var watchMove = WatchMoveMonitor()
  /// 桌面小组件的快照写手（P3.2）。
  @State private var widgetFeed = WidgetFeed()
  /// 提醒总表开着没有。设置里那一行和 `hkline://alerts` 都开它。
  @State private var showAlerts = false
  @State private var shareInterval: SharePreviewInterval?
  @State private var inbox = ShareInbox()
  @State private var showFriends = false
  @State private var showFriendPicker = false
  /// 朋友页上点了「登录」：账号页收起、而且真登上了，就把朋友页再打开。
  @State private var friendsAfterLogin = false
  @State private var shareDraft: ShareOutbound?
  @State private var shareShot: Data?
  /// 「回给他」：他那一封的线已经留在图上，等我画完点发送（P3.5）。
  @State private var replying: ShareItem?
  @State private var replySending = false
  /// 「更多」那张周期网格摊开了没有。开着时它把图往下推，所以状态得住在这一层。
  @State private var intervalGrid = false
  /// 图还停在最新那根上没有。周期条行尾那颗「最新」靠它决定露不露面。
  @State private var atLatest = true
  /// 刚被「最新」拽回来之前，人在看哪一屏（§P3-2）。
  ///
  /// 有值 = 周期条行尾那颗「最新」变成「返回刚才」，点它原样回去。它是一条**后路**，
  /// 不是一段记忆：手一碰图、换品种、换周期、或者过了一分钟都作废——再点回去时
  /// 那一屏多半已经不是他刚才看的那件事了。
  @State private var returnView: ViewWindow?
  /// 每记一笔后路自增。六十秒那条计时器用它作废上一笔（`task(id:)`）。
  @State private var returnStamp = 0
  /// Historical OHLC belongs only to the crosshair container.
  ///
  /// 十字线跟手时一秒钟能动几十次，从前它写在主屏自己的 `@State` 上，于是主屏的 body
  /// 一起跟着重求值几十次——而真正变的只有头部那几行开高低收。现在它住在
  /// `CrosshairReadout` 里，只有读数那一小块观察它（见 `CrosshairReadout.swift`）。
  private var crosshairReadout: CrosshairReadout { session.readout }

  /// `store` 要先造出来才能交给 `viewport` 当属主，`@State` 的默认值互相引用不了，
  /// 所以这里显式写一个 init。
  @MainActor init() {
    // 哨兵单开一层：`storage` 这一份等账号桥就位就会被换成账号目录里的那份，
    // 哨兵要留在这台机器上，否则「档案被清空」和「第一次装」分不出来。
    let store = PrefsStore(storage: PrefsStore.deviceStorage(), fallback: LaunchThemeMirror.prefs(),
                           sentinel: PrefsStore.deviceStorage())
    _store = State(initialValue: store)
    _viewport = State(initialValue: ChartViewport(owner: store))
    _session = State(initialValue: ChartSession(symbol: "BTCUSDT"))
  }

  @Environment(\.colorScheme) private var scheme
  /// **全 app 唯一一处读 `scenePhase`**。它只干一件事：把话递给 `AppLifecycle`。
  /// 别在任何别的地方再读一次，也别在这儿顺手做事——落盘顺序是有规定的，见那个文件。
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

  /// 这台设备选的线路。所有取数件（报价簿、板块、预览卡、对比、复盘、小组件）都从它拿
  /// 主机，不再各自拼（审查 14）。
  private var route: RouteResolver { RouteResolver(policy: prefs.routePolicy) }

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
        MainDiagnosticsOverlay(market: market, store: store, viewport: viewport)
      }
      #endif
    }
    .overlay {
      if !landscape, panel != nil || draw.panel != nil { PanelDismissShield(onDismiss: dismissPanel) }
    }
    .preferredColorScheme(effectiveTheme.forced)
    // 横屏的面板走自己那层侧栏，不挂系统 sheet：半屏 sheet 在 compact 高度下会被
    // 系统顶成全屏，图就整个没了。
    .prefsPanel(landscape ? .constant(nil) : $panel, store: store, actions: panelActions)
  }

  private var presentation: some View {
    basePresentation
    .fullScreenCover(isPresented: $symbolSearch.searchShown, onDismiss: { symbolSearch.searchDismissed() }) {
      SymbolSearchView(model: picker, history: searchHistory, redUp: prefs.redUp,
                       onClose: { symbolSearch.searchShown = false },
                       onAll: { symbolSearch.showAllFromSearch() },
                       onVisible: { quotes.watch($0) },
                       onRowVisibility: { quotes.watchRow($0, visible: $1) })
        .preferredColorScheme(effectiveTheme.forced)
    }
    .fullScreenCover(isPresented: $showComparePicker) {
      SymbolPickerView(model: picker, redUp: prefs.redUp,
        onClose: { showComparePicker = false; picker.query = "" },
        onSelect: { info in
          let key = InstrumentID.canonical(info.symbol)
          if key != InstrumentID.canonical(market.symbol), !prefs.compareSymbols.contains(key), prefs.compareSymbols.count < 3 {
            store.update { $0.compareSymbols.append(key) }
          }
          showComparePicker = false; picker.query = ""
        },
        onVisible: { quotes.watch($0) },
        onRowVisibility: { quotes.watchRow($0, visible: $1) })
        .environment(\.panelTheme, theme)
        .preferredColorScheme(effectiveTheme.forced)
    }
    .fullScreenCover(isPresented: $symbolSearch.allShown, onDismiss: { symbolSearch.allDismissed() }) {
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
    if symbolSearch.closeAll() { picker.query = "" }
  }

  /// 自选那一整页。标签栏上的一格，所以没有「返回」——返回就是换一格标签。
  private var favoritesPage: some View {
    FavoritesView(model: picker, session: favoritesEdit, history: searchHistory, store: store, redUp: prefs.redUp, basisTitle: prefs.changeBasis.shortTitle, updatedAt: quotes.lastListUpdate, feedStatus: quotes.status, feedDiagnostics: quotes.diagnostics,
                  onVisible: { quotes.watch($0) },
                  // 露面的自选行顺手把顶栏那几格（仓 / 费率 / 结算 / 市值）的数先取回来。
                  onRowVisibility: { quotes.watchRow($0, visible: $1); if $1 { market.prefetchListStats([$0]) } },
                  onHistoryVisibility: { quotes.watchHistory($0, visible: $1) },
                  previews: previews,
                  // 点一行进图的同一瞬间冻结这张表的顺序，顶栏横滑就照着它一只只看过去。
                  onScanList: { adoptScanList($0) },
                  // 加了提醒的线就是「关注线」：自选页多一档「离提醒线最近」（§10）。
                  alerts: alerts.all)
  }

  /// 板块列表页那一整页。计算全在 `KanpanCore`，画全在 `Kanpan/Sector/`，
  /// 这儿只把行情和「点中一行去看图」两根线接上（涨跌色页面自己从 `theme` 拿）。
  ///
  /// 点一行品种走的是 `picker.onPick` 同一条路——切到行情页、换品种、回到最新那一根，
  /// 而不是另起一套跳转，免得板块页进来的图和自选页进来的图行为不一样。
  private var sectorPage: some View {
    SectorPage(feed: sectorFeed,
               symbolForBase: { sectorFeed.symbol(forBase: $0) }, store: store,
               onPickSymbol: { symbol in
                 if let info = picker.info(for: symbol) { picker.pick(info) }
                 else {
                   if tab != .chart { chartOrigin = tab }
                   tab = .chart; didLeaveLaunch = true
                   // 目录还没载回来时点一行，以前只换图不记「最近」——同一个动作在
                   // 目录加载前后结果不一样，而且这张图下次冷启动也回不来。
                   picker.visit(symbol)
                   session.show(symbol: symbol)
                 }
               },
               onScanList: { adoptScanList($0) },
               // 板块品种列表一出现就把最上面几行的 K 线先拉好（独立槽位，不顶掉自选那轮）。
               onListShown: { market.prefetchList($0) },
               onListHidden: { market.cancelListPrefetch() },
               previews: previews, picker: picker,
               route: $sectorRoute)
  }

  /// 此刻画的是不是自选页。账号还在恢复的那一小段里，`picker.prefs` 挂的是访客那份
  /// 空档案，不能拿「自选是空的」当真——所以 `awaitingAccount` 也算数。
  private var showingFavorites: Bool {
    tab == .favorites && (!picker.prefs.favorites.isEmpty || awaitingAccount)
  }

  /// 报价簿要不要拉列表：看得见一列品种的时候才拉。
  private var listVisible: Bool { showingFavorites || symbolSearch.isActive }

  private var lifecycleContent: some View {
    presentation
    // 接线要排在盖层前面：`QuoteBook` 得先知道自选是哪些，才不会拿「图上那一个品种」
    // 去裁刚从盘上恢复出来的报价。`.onAppear` 和 `.task` 两个入口都接在 `BootOnce`
    // 里的同一道闸上，先到的那个真跑，后到的空转（BT-20 在 KanpanTests 的 Main 组里量这件事）。
    .modifier(BootOnce(boot: boot))
    // 开关一变、或前后台一切，这个 task 就整个重来（旧的先被取消），心跳跟着起停。
    .task(id: beating) { await heartbeat() }
    // 其余三十一个观察者收在这一层里（`MainScreenParts.swift` 的 `MainScreenObservers`）。
    // 它们从前是直接挂在这条链上的三十一个修饰符，每一个都往 `body` 的具体类型上再
    // 套一层 `ModifiedContent<...>`——那正是 iOS 27 真机启动栈溢出的大头。
    // **不要把 `.onChange` / `.onReceive` 重新挂回这条链上，往那只修饰符里加。**
    .modifier(observers)
    // 对比 K 线只有这一个观察者，自带一层修饰符，不往上面那只里塞。
    // 接线键（要读序列首尾时刻）在修饰符自己的 body 里求值，见 `LiveCompareObservers`。
    .modifier(LiveCompareObservers(drive: { compareDrive }, onChange: { updateCompare() }))
    .modifier(OrderFlowObserver(on: prefs.orderFlow, overrides: prefs.orderFlowOverrides, market: market))
  }

  private var microstructureVisible: Bool {
    tab == .chart && !symbolSearch.isActive && !review.bookOpen && !reviewChart.active && !drawingCanvasOnly
  }

  /// 主屏那一串观察者的接线。
  ///
  /// **被观察的值全在这儿求值**——`onChange(of:)` 的依赖记在求值它的那个 body 上，
  /// （例外是逐笔推送带出来的那两条：成交和费率。它们在 `LiveTickRelay` 里自己求值，
  /// 放在这儿每一笔成交都会叫醒整页——审查 21。）
  /// 所以这些读取必须留在 `MainScreen` 里，搬进修饰符会让宿主不再订阅它们
  /// （最要命的是 `listVisible`：它是拿 `picker.prefs.favorites` 算的）。
  /// 动作照旧是这只 `MainScreen` 上的方法，收的是 `onChange` 给的新值。
  private var observers: MainScreenObservers {
    MainScreenObservers(
      prefs: prefs,
      phase: phase,
      deepLink: DeepLinkRouter.shared.pending,
      microstructureVisible: microstructureVisible,
      syncGate: syncGate,
      reviewScope: review.searchScope,
      routePolicy: prefs.routePolicy,
      session: session,
      catalogCount: picker.catalog.count,
      listVisible: listVisible,
      favorites: picker.prefs.favorites,
      symbol: market.symbol,
      undoStamp: favoritesEdit.undoStamp,
      returnStamp: returnStamp,
      storeNotice: store.notice,
      drawFull: draw.full,
      drawNotice: draw.notice,
      panel: panel,
      drawActive: draw.active,
      alertsNotice: alerts.notice,
      reviewNotice: review.notice,
      reviewChartNotice: reviewChart.notice,
      reviewBookOpen: review.bookOpen,
      reviewRecords: review.records,
      onPhase: { now in AppLifecycle.shared.phaseChanged(to: now) },
      onDeepLink: { consumeDeepLink() },
      onMicrostructure: { visible in market.setChartVisible(visible) },
      onSubs: { subs in market.setExternalIndicators(subs, depth: prefs.depth) },
      onDepth: { on in market.setExternalIndicators(prefs.subs, depth: on) },
      onComfort: { refreshComfort() },
      onSyncGate: { accountBridge?.resumeApply() },
      onReviewScope: { value in store.update { $0.reviewSearchScope = value } },
      onPrefsReviewScope: { value in review.searchScope = value },
      onTimeZone: { value in review.timezone = value },
      onChangeBasis: { next in session.configure(route: route, basis: next) },
      onRoutePolicy: { next in
        let route = RouteResolver(policy: next)
        session.configure(route: route, basis: prefs.changeBasis)
        sectorFeed.configure(route: route)
        previews.configure(route: route)
      },
      onFundingRate: { rate in previews.note(funding: rate, for: market.symbol) },
      onCatalog: { sectorFeed.setCatalog(picker.catalog) },
      onListVisible: { on in quotes.setVisible(on) },
      onFavorites: { symbols in settleFavorites(symbols) },
      onSymbol: { symbol in
        if let preview = draw.previewing, preview.key != symbol { endSharePreview() }
        // 回信只回那一只上的线：换走了就算不回了。
        if let reply = replying, reply.key != symbol { replying = nil }
        quotes.setChartSymbol(symbol); accountBridge?.focus(symbol)
        // 扫图名单里的前后邻居先预取：滑过去时顶栏六格和持仓量副图就有数（B1 / B2）。
        if let list = scanList { market.prefetchNeighbors(list.neighbors(of: symbol)) }
        // 换了一只，「刚才那一屏」说的已经不是这张图上的事了（§P3-2）。
        forgetReturn()
      },
      onUndoStamp: {
        guard let undo = favoritesEdit.undoAction else { return }
        say(favoritesEdit.undoText, undo: undo)
      },
      expireReturn: {
        guard returnView != nil else { return }
        try? await Task.sleep(for: .seconds(60))
        guard !Task.isCancelled else { return }
        returnView = nil
      },
      noteDwell: {
        let symbol = market.symbol
        guard !symbol.isEmpty else { return }
        try? await Task.sleep(for: .seconds(3))
        guard !Task.isCancelled else { return }
        picker.noteDwell(symbol)
      },
      onStoreNotice: { note in
        // 设置那一侧说的话（换下了哪个副图、常用行满了、已恢复默认、清缓存）一律从这儿
        // 转给那唯一一条提示（P2.7）。它画在面板之上，面板开没开都一样看得见。
        if let note {
          let undo = store.noticeUndo
          store.clearNotice()
          say(note, undo: undo)
        }
      },
      // A7.7：一个品种最多 50 条，满了只提示、不悄悄丢。
      onDrawFull: { say("这个品种的线画满了（50 条）"); draw.full = false },
      onDrawNotice: { note in if let note { say(note); draw.notice = nil } },
      onPanel: { value in if value == nil { try? accountBridge?.applyPending() } },
      onDrawActive: { active in
        if !active { try? accountBridge?.applyPending() }
        // 画线直接横过来，画完自己转回去（§10.7 的入口就此收在「画线」上）。
        if active {
          endSharePreview()
          if !landscape { landscapeForDrawing = true; enterLandscape() }
        } else if landscapeForDrawing {
          landscapeForDrawing = false
          leaveLandscape()
        }
      },
      onAlertsNotice: { note in if let note { say(note); alerts.notice = nil } },
      onReviewNotice: { note in if let note { say(note); review.notice = nil } },
      onReviewChartNotice: { note in if let note { say(note); reviewChart.notice = nil } },
      onReviewBookOpen: { endSharePreview() },
      onReviewRecords: { list in
        // 叫人的只有 `reviewDue` 这一处；下面那份只进提醒总表、跟着同步，不叫人。
        reviewDue.reschedule(list)
        alerts.settleReviewDue(ReviewDueAlerts.plan(items: list.map(ReviewDueAlerts.Item.init(record:)),
                                                    existing: alerts.all,
                                                    now: Date().timeIntervalSince1970 * 1000))
      })
  }

  var body: some View {
    #if DEBUG
      let _ = FrameProbe.shared.countBody("MainScreen")
    #endif
    lifecycleContent
    #if DEBUG
    .task { [market] in await IdleFrameProbe.run { market.status == .live } }
    #endif
    // 那唯一一条提示画在自己的窗里，拿不到这儿的环境；皮肤一换就递一份过去（P2.7）。
    .onChange(of: theme, initial: true) { _, value in ToastCenter.shared.theme = value }
    .sheet(item: $draw.panel) { panel in
      // 主题显式灌进去：这张表里的「画线列表」和「样式」都要跟着皮肤走
      // （和 `IndicatorPanel` 里那张编辑表一个做法）。
      DrawingSheet(controller: draw, panel: panel, decimals: market.info.priceDecimals)
        .environment(\.panelTheme, theme)
    }
    // 竖屏的「绘图」面板是一张半屏表单；横屏走 `drawToolsLayer` 那块贴边卡片，
    // 所以这儿要把横屏挡掉，不然两份会同时在场。
    .sheet(isPresented: Binding(get: { draw.picker && !landscape }, set: { draw.picker = $0 })) {
      DrawingToolPicker(controller: draw, store: store, onClose: { draw.picker = false })
        .presentationDetents([.large])
        .environment(\.panelTheme, theme)
    }
    .sheet(isPresented: Binding(get: { showFriendPicker && !landscape }, set: { showFriendPicker = $0 })) {
      friendPicker.presentationDetents([.medium, .large])
    }
    .sheet(isPresented: $showFriends) {
      FriendsPage(inbox: inbox, loggedIn: account.user != nil, onLogin: loginFromFriends, onOpen: openShare)
        .environment(\.panelTheme, theme)
        .presentationDetents([.large])
    }
    .environment(\.panelTheme, theme)
    .environment(\.accountFeature, account)
    .sheet(isPresented: Binding(get: { account.presented && !review.bookOpen }, set: { account.presented = $0 })) { AccountView(feature: account).environment(\.panelTheme, theme) }
    // 从朋友页点「登录」进来的：登完回到朋友页，不把人丢在设置页上。
    .onChange(of: account.presented) { _, open in
      guard !open, friendsAfterLogin else { return }
      friendsAfterLogin = false
      guard account.user != nil else { return }
      Task { try? await Task.sleep(for: .milliseconds(350)); showFriends = true }
    }
    .fullScreenCover(isPresented: $review.bookOpen) {
      ReviewBook(feature: review)
        .environment(\.reviewTheme, theme.review)
        .sheet(isPresented: $account.presented) { AccountView(feature: account).environment(\.panelTheme, theme) }
    }
    .onAppear { wireReview() }
    // 提醒总表。半屏叫出来的一张面板：它是「管一管已经有的那些」，不是一张要长住的页。
    .sheet(isPresented: $showAlerts) {
      AlertListPage(store: alerts, preferences: store,
                    onOpen: { alert in
                      showAlerts = false
                      if alert.kind == .reviewDue, let id = alert.reviewID { openReview(id: id); return }
                      guard let drawingID = alert.drawingID else { open(linkedSymbol: alert.symbol); return }
                      open(linkedSymbol: alert.symbol)
                      draw.highlight(drawingID: drawingID, symbol: SymbolPrefs.key(alert.symbol))
                    },
                    zone: prefs.timeZone.offsetMinutes,
                    currentSymbol: InstrumentID(market.symbol).display,
                    quote: { text in alertQuote(text) },
                    prepareQuote: { [weak quotes] symbol in quotes?.quoteNow(symbol) },
                    releaseQuote: { [weak quotes] in quotes?.releaseNamed() },
                    watching: activities.watching,
                    onWatch: { alert in watch(alert) })
        .environment(\.panelTheme, theme)
    }
    // 盯着的那条被删、被暂停、响了：锁屏那块跟着收。
    .onReceive(alerts.$archive) { activities.reconcile($0.alerts) }
    // Handoff（P3.4）：在行情页上就登记「这只、这个周期」，同账号的另一台设备可以接力打开。
    .userActivity(ChartHandoff.activityType, isActive: tab == .chart) { activity in
      // 标题给人看，只放代号；userInfo 里是完整品种 key，接力端按它开对交易所。
      activity.title = InstrumentID(market.symbol).symbol + " · " + market.interval.shortLabel
      activity.addUserInfoEntries(from: ChartHandoff.userInfo(symbol: market.symbol, interval: market.interval.rawValue))
      activity.isEligibleForHandoff = true
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
      case .favorites:
        if landingHeld, picker.prefs.favorites.isEmpty { FavoritesLandingPlaceholder() }
        else { favoritesPage }
      case .sectors: sectorPage
      case .settings: SettingsPanel(store: store, asPage: true,
                                    alertCount: alerts.activeCount,
                                    onAlerts: { showAlerts = true },
                                    onFriends: { showFriends = true })
      }
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    // 记一笔和回放这两种状态下标签栏收起来（§2F1 / §2G4）：这时候屏幕上已经有
    // 一套自己的操作（记下 / 收起、播放 / 退出），底下再摆一排分页，点哪个都像是
    // 要跑题。两种状态各自都有明确的回头路（卡片的「收起」、回放条的「退出」）。
    .safeAreaInset(edge: .bottom, spacing: 0) {
      if !reviewChart.active {
        TabBar(theme: theme, current: tab, drawing: draw.active, drawingEnabled: !comparing, onPick: switchTo(tab:))
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
    landingHeld = false
    guard next != .draw else {
      guard !comparing else { return }
      endSharePreview()
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
    // 来路作废，那张冻结的名单也跟着作废：横滑是「接着刚才那张表往下看」，
    // 人已经离开那张表了，再横滑就该什么都不发生（§10.1）。
    scanList = nil
    detailZoom.clear()
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
      // 十字线活着时这一行换成它的四颗动作（`IntervalRow` / `CrosshairActionBar`）。
      if !reviewChart.active { IntervalRow(
        theme: theme, quick: prefs.quickIntervals, current: market.interval,
        atLatest: atLatest, gridOpen: $intervalGrid,
        onPick: pick(interval:),
        onPin: { iv in store.attempt { $0.toggleQuick(iv) } },
        onLatest: { rememberBeforeLatest(); proxy.scrollToLatest() },
        // 「返回刚才」：刚被「最新」拽回来，这颗把人原样送回去（§P3-2）。
        // 没有后路时传 `nil`，那个槽位照旧空着——槽宽是钉死的，谁在里面都不影响周期药丸。
        onReturn: returnView.map { view in { returnToRemembered(view) } },
        // 配置页，不连着关：开着它一次调好几项（和指标 / 设置一样）。
        onChart: { panel = .chart },
        readout: crosshairReadout, context: crosshairContext,
        // 「看细节」（§10.1）：还有更细的一档可进才给。只看当前周期，不引入对十字线的观察。
        canDetail: DetailZoom.finer(than: market.interval) != nil,
        onStep: { proxy.moveCrosshair(by: $0) },
        // 对比态下图上不画线，「按此价画线」这颗也不给。
        onLine: comparing ? nil : { endSharePreview(); proxy.addHorizontalLine(at: $0) },
        onDetail: zoomIntoDetail
      ) }
      hairline
      // 「更多」那张网格是盖在图上的一层（遮罩 + 从上沿展开的面板），和复盘卡片在同一个
      // overlay 里——不在 `chartPage` 这条链上多接修饰符（文件头那条层数上限）。
      chart.overlay(alignment: .bottom) { ZStack(alignment: .bottom) {
        IntervalPopoverLayer(
          theme: theme, quick: prefs.quickIntervals, current: market.interval,
          open: $intervalGrid, onPick: pick(interval:),
          onPin: { iv in store.attempt { $0.toggleQuick(iv) } },
          onReplace: { old, new in store.update { $0.replaceQuick(old: old, new: new) } })
        captureCard
      } }
      replayControls
      hairline
      if draw.active {
        DrawingBar(controller: draw, lineAlert: lineAlert)
      }
      // 画完线问的那一句**不在这儿**（2026-09-21）：它从前是周期条下面、标签栏上面
      // 额外插的一行，于是线一落下整张图当场矮一行，六秒后又弹回来——用户看见的是
      // 两次跳动。现在它占头部价格行那一行的位置（见 `header` 里挂它的那个 `overlay`），
      // 图表尺寸一个 pt 都不动。
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
    if showFriendPicker {
      friendPicker
        .frame(width: 340)
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(theme.line, lineWidth: 0.5))
        .shadow(color: .black.opacity(0.24), radius: 14, x: 2, y: 2)
        .padding(.vertical, 6).padding(.leading, 6)
        .transition(.move(edge: .leading).combined(with: .opacity))
    } else if draw.active, draw.picker {
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
        // 价和涨跌在 `LiveLandscapeHeadline` 自己的 body 里取：逐笔推送只叫醒那一行。
        LiveLandscapeHeadline(
          session: session, theme: theme,
          // 只有画线工作台里那一行是按钮，见 `DrawingSymbolSwitcher` 顶上那段。
          // 换品种和挑工具都贴在左边，同时开会叠在一起——开一个就把另一个收了。
          onTapSymbol: draw.active ? { draw.picker = false; showDrawSwitcher.toggle() } : nil)
          .padding(.horizontal, 8).padding(.vertical, 4)
        CrosshairOHLCLabel(readout: crosshairReadout, context: crosshairContext,
                           size: 10, color: theme.ink)
        }
        // 选中一条线之后的 样式 / 锁定 / 复制 / 删除 排在**图外**这一条属性栏上（§2E2）。
        // 横屏的图就是画布，浮在上面的东西正好压着刚画的那一笔，也和「画布上不浮任何
        // 控件」相冲。挂在图上方、和标题同一根 `VStack` 里，选中 / 取消选中只在图外
        // 增减一行，K 线不会跟着跳。竖屏那份在画线栏上排里（见 `DrawingBar`）。
        if draw.active, draw.selected != nil {
          DrawingSelectionBar(controller: draw, placement: .landscape, lineAlert: lineAlert)
        }
        chart.overlay(alignment: .bottom) { captureCard }
        replayControls
        // 画线工作台的那根条排在图**下面**、图外面（§2E5）：横屏的高度金贵，但十四五个
        // 控件竖着摆放不下、横着摆绰绰有余，而且两个拇指本来就停在下沿。
        shareAndAlertCard(inHeader: false)
        if draw.active {
          DrawingDock(controller: draw)
        }
      }
      // 画线进行中侧栏整条收起：「画线」此时等于退出画线，和画线栏上的「完成」是同一个动作，
      // 「竖屏」也只是另一种退法——右手边两格和左手边的「完成」重复。出口留在「完成」上：
      // 点「画线」进来的，完成后自动转回竖屏；手动横过来再开画线的，完成后侧栏回来。
      if !draw.active {
        ToolRail(
          theme: theme,
          onDraw: { endSharePreview(); dismissPanel(); if reviewChart.active { endReview() }; draw.toggle() },
          onPortrait: {
            dismissPanel()
            landscapeForDrawing = false
            leaveLandscape()
          })
      }
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
    .ignoresSafeArea(.keyboard, edges: showDrawSwitcher || showFriendPicker ? .bottom : [])
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
  /// 外部指标在不支持的线路上保留对应空态，选择不随线路变化。
  ///
  /// 例外是**整个市场就没有这类数据**（现货：没有持仓量、也没有任何衍生统计）：
  /// 那不是线路暂时给不了，而是永远不会有，挂一格空态只是在报错。这时候这几格
  /// 直接不画，`prefs.subs` 一个字不动——切回永续品种，它们原样回来。
  private var visibleSubs: [IndicatorID] {
    if drawingCanvasOnly { return [] }
    let caps = market.capabilities
    guard !caps.hasOpenInterest, !caps.hasOpenInterestHistory, !caps.hasDerivativeMetrics else { return prefs.subs }
    return prefs.subs.filter { !$0.isExternal }
  }
  private var visibleOverlays: [IndicatorID] { drawingCanvasOnly || comparing ? [] : prefs.overlays }
  /// 图上只调整当前可见副图的顺序，保留没有参与排序的设置。
  /// 横屏画线台不展示副图；网关则保留已选指标并显示空态。
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
        PanelContent(which: which, store: store, actions: panelActions)
      }
    }
  }

  /// 面板里的动作，竖屏 sheet 与横屏侧栏共用这一份（见 `PanelActions`）。
  /// 以前侧栏那份是手抄的，比 sheet 少了「记一笔」「对比」两个动作。
  private var panelActions: PanelActions {
    PanelActions(onPickInterval: pick(interval:), onRecord: chartRecordAction,
                 onShare: chartShareAction, onAddCompare: { showComparePicker = true },
                 compareNames: compareNames, onSend: chartSendAction, sendBlocked: shareSendBlocked,
                 orderFlow: market.orderFlow, symbol: market.symbol)
  }

  /// 行情页头部。画的东西全在 `MainHeaderView`（`MainScreenParts.swift`）——
  /// 它那四十来层嵌套摘出去之后才不会算进 `body` 的类型深度里，这一层只接线。
  private var header: some View {
    MainHeaderView(
      theme: theme, market: market, review: review,
      session: session, context: crosshairContext,
      cardVisible: headerCardVisible,
      // 有来路才有返回。复盘态走的是另一副页头（`reviewHeader`），不经过这儿。
      onBack: chartOrigin.map { origin in { switchTo(tab: origin) } },
      onReview: { dismissPanel(); review.bookOpen = true; review.synchronize() },
      onSearch: { dismissPanel(); symbolSearch.openSearch() },
      onScan: { scan($0) },
      card: shareAndAlertCard(inHeader: true))
  }

  /// 读数那一小块要的、**不跟着手指走**的那几样输入。十字线本身不在这儿——
  /// 它住在 `crosshairReadout` 里，只有读数视图读得到（见 `CrosshairReadout.swift`）。
  ///
  /// 序列不在这儿取（审查 21）：`crosshairContext` 在宿主 body 里求值，这儿读一次
  /// `market.series` 就等于让每根新 K 线都把整页叫起来。它交给读数视图在十字线真在场时现取。
  private var crosshairContext: CrosshairContext {
    session.crosshairContext(timeZone: prefs.timeZone.offsetMinutes, enabled: prefs.dataDisplay == .top)
  }

  /// 「图表设置」里的「记一笔」。复盘回放里没有「记」这回事、预览别人的线时那张图不是
  /// 「我的图」，这两种情形返回 nil，那一条直接不排。
  ///
  /// **不按横竖屏拦**（审查 16.2，2026-09-24 定）：以前这里还多一条 `!landscape`，
  /// 理由是「横屏归 `ToolRail` 管」，可 `ToolRail` 只有「绘图」「竖屏」两格，并没有记一笔。
  /// 仓库里也没有「横屏不许记」的规则，横屏外壳本来就挂着取景卡（`landscapeBody` 的
  /// `captureCard`，高 150pt），所以这件事只由上面两条决定。
  ///
  /// 眼下「图表设置」在横屏其实开不出来：横屏周期栏只有「更多」（周期面板），而竖屏开着的
  /// sheet 一转屏就被系统收掉（SwiftUI 经 `$panel` 写回 nil，模拟器上抓到过这一下）。
  /// 所以这里不拦只是让两份面板内容说同一句话，不是新开了一个横屏入口。
  private var chartRecordAction: (() -> Void)? {
    guard !reviewChart.active, draw.previewing == nil else { return nil }
    return { startReviewCapture() }
  }

  /// 「分享图片」：把眼前这张图（画线、指标、配色全带着）离屏画成一张 PNG，
  /// 交给系统的分享面板（见 `ChartSnapshotRenderer`）。
  ///
  /// 复盘回放里那张图不是「我的图」，不给分享。
  private var chartShareAction: (() -> Void)? {
    guard !reviewChart.active else { return nil }
    return { shareChartImage() }
  }

  private var visibleShareDrawings: [Drawing] {
    // 图上关了「显示画线」就不给发；线本身从画线真值取，不从图的投影里抠（审查 23.2）。
    guard let state = proxy.box?.chart.state, state.options.drawings else { return [] }
    return draw.shareable(state.series.symbol)
  }
  /// 「分享 › 画线」那格此刻为什么发不了；nil 就是能发。
  private var shareSendBlocked: String? {
    account.user == nil ? "登录后可发" : visibleShareDrawings.isEmpty ? "先画几条线" : nil
  }
  private var chartSendAction: (() -> Void)? {
    guard !reviewChart.active, draw.previewing == nil else { return nil }
    return beginShareSend
  }
  /// 朋友页没登录时那颗「登录」。朋友页和账号页都挂在根这一层，同一时刻只能开一张：
  /// 先收朋友页，等它退场再开账号页（和 `beginShareSend` 收面板再开发送表同一个等法）。
  private func loginFromFriends() {
    showFriends = false; friendsAfterLogin = true
    Task { try? await Task.sleep(for: .milliseconds(350)); account.open() }
  }
  private var friendPicker: some View {
    FriendPickerSheet(inbox: inbox, onSend: sendShare)
      .environment(\.panelTheme, theme)
      .environment(\.panelDismiss, PanelDismiss { showFriendPicker = false })
  }
  private func beginShareSend() {
    guard account.user != nil else { say("登录后才能发给朋友"); return }
    let lines = visibleShareDrawings
    guard !lines.isEmpty else { say("先在图上画点什么"); return }
    guard let chart = proxy.box?.chart, let state = chart.state else { say("图还没画出来"); return }
    shareDraft = ShareOutbound(to: "", symbol: market.symbol, interval: market.interval,
                              view: ShareWindow(from: state.view.from.rounded(), to: state.view.to.rounded()),
                              drawings: lines, alerted: lines.filter { line in alerts.alerts(symbol: market.symbol).contains { $0.isActive && $0.drawingID == line.id } }.map(\.id))
    shareShot = ChartSnapshotRenderer.thumbnail(state: state, size: chart.bounds.size)
    let wasPanel = panel != nil
    dismissPanel(); draw.picker = false; showDrawSwitcher = false
    if wasPanel {
      Task { try? await Task.sleep(for: .milliseconds(350)); if shareDraft != nil { showFriendPicker = true } }
    } else { showFriendPicker = true }
  }
  private func sendShare(to username: String) async throws {
    guard let api = account.client, let owner = account.user?.id, var draft = shareDraft else { return }
    let shot = shareShot
    draft.to = username
    let client = ShareClient(api: api)
    let id = try await client.send(draft)
    guard account.user?.id == owner else { throw CancellationError() }
    showFriendPicker = false; shareDraft = nil; shareShot = nil
    say("已发给 \(username)")
    inbox.pull()
    if let shot { try? await client.upload(shot, id: id) }
  }
  private var headerCardVisible: Bool {
    alertPrompt.pending != nil || draw.previewing != nil || replying != nil || !inbox.unseen.isEmpty
  }
  @ViewBuilder private func shareAndAlertCard(inHeader: Bool) -> some View {
    if alertPrompt.pending != nil {
      AlertPromptBar(model: alertPrompt, inHeader: inHeader)
    } else if let item = draw.previewing ?? (replying == nil ? inbox.unseen.first : nil) {
      ShareCard(item: item, inbox: inbox, previewing: draw.previewing != nil,
                extra: max(0, inbox.unseen.count - 1), onOpen: { openShare(item) },
                onKeep: { keepShare(item) }, onExit: endSharePreview, onReply: { replyShare(item) })
        .padding(.horizontal, inHeader ? 0 : 10)
    } else if let item = replying {
      ShareReplyBar(item: item, sending: replySending, onSend: sendReply, onCancel: { replying = nil })
        .padding(.horizontal, inHeader ? 0 : 10)
    }
  }

  /// 「回给他」：先把他的线留到我图上（和「留下」同一条路，不重复复制），
  /// 然后收件卡换成回信条，我接着画，画好点「发送」。
  private func replyShare(_ item: ShareItem) {
    do {
      let kept = try inbox.prepareKeep(item)
      if inbox.items.first(where: { $0.id == item.id })?.keptAt == nil {
        guard draw.append(kept, symbol: item.key) else { return }
        inbox.kept(item)
      }
      draw.endPreview(); shareInterval = nil
      replying = item
    } catch { say("暂时无法回信，请重试") }
  }

  /// 把这只品种上看得见的线原路发回去，带上 `replyTo`。不过朋友名单：收件人就是来信的人。
  private func sendReply() {
    guard let item = replying, let api = account.client, let owner = account.user?.id else { return }
    let lines = visibleShareDrawings
    guard !lines.isEmpty else { say("先在图上画点什么"); return }
    guard let chart = proxy.box?.chart, let state = chart.state else { say("图还没画出来"); return }
    let draft = ShareOutbound(to: item.from, symbol: market.symbol, interval: market.interval,
                              view: ShareWindow(from: state.view.from.rounded(), to: state.view.to.rounded()),
                              drawings: lines,
                              alerted: lines.filter { line in alerts.alerts(symbol: market.symbol).contains { $0.isActive && $0.drawingID == line.id } }.map(\.id),
                              replyTo: item.id)
    let shot = ChartSnapshotRenderer.thumbnail(state: state, size: chart.bounds.size)
    let client = ShareClient(api: api)
    replySending = true
    Task {
      defer { replySending = false }
      do {
        let id = try await client.send(draft)
        guard account.user?.id == owner else { return }
        replying = nil
        say("已回给 \(item.from)")
        inbox.pull()
        if let shot { try? await client.upload(shot, id: id) }
      } catch is CancellationError {} catch {
        say(ShareClient.message(error))
      }
    }
  }

  private func openShare(_ item: ShareItem) {
    endSharePreview()
    dismissPanel(); showFriends = false; showAlerts = false
    if reviewChart.active { endReview() }
    draw.finish(); alertPrompt.dismiss()
    let before = market.interval
    open(linkedSymbol: item.key)
    shareInterval = SharePreviewInterval(before: before, shared: item.interval)
    // 分享切换只活在本次预览，不写 Prefs，也不进入个人同步。
    session.show(interval: item.interval)
    draw.focus(item.key)
    draw.preview(item)
    proxy.show(window: item.view.window, symbol: item.key, interval: item.interval)
    inbox.opened(item)
  }

  private func endSharePreview() {
    guard draw.previewing != nil else { return }
    let restore = shareInterval?.restore(current: market.interval)
    draw.endPreview(); shareInterval = nil
    proxy.cancelWindow()
    if let restore { session.show(interval: restore) }
  }

  private func keepShare(_ item: ShareItem) {
    do {
      let kept = try inbox.prepareKeep(item)
      guard draw.append(kept, symbol: item.key) else { return }
      draw.endPreview(); shareInterval = nil
      inbox.kept(item)
      alertPrompt.offerBatch(kept, symbol: item.key, preferred: item.preferred(in: kept), from: item.from)
    } catch { say("暂时无法保存，请重试") }
  }

  private func shareChartImage() {
    let size = proxy.box?.chart.bounds.size ?? .zero
    guard let state = proxy.box?.chart.state,
          ChartSnapshotRenderer.share(state: state, size: size, head: chartShotHead, theme: theme)
    else { say("图还没画出来"); return }
  }

  /// 成片顶上那一条：徽章 品种 · 周期 · 最新价 涨跌药丸。取的和头部同两个数，
  /// 免得图上写的价和屏幕上那口对不上。
  private var chartShotHead: ChartShotHead {
    let pct = session.displayedTicker?.changePercent
    return ChartShotHead(
      symbol: market.symbol, interval: market.interval,
      price: session.readoutPrice, decimals: market.info.priceDecimals,
      changePercent: (pct?.isFinite == true) ? pct : nil)
  }

  /// K 线画布。同样为了断开类型嵌套整块搬进了 `MainChartView`（`MainScreenParts.swift`）。
  private var chart: some View {
    MainChartView(
      theme: theme, market: market, proxy: proxy, viewport: viewport, store: store,
      review: review, reviewChart: reviewChart, draw: draw, alerts: alerts,
      session: session,
      input: chartInput,
      portrait: !landscape,
      renderingActive: tab == .chart && !symbolSearch.isActive && !showComparePicker,
      panelOpen: panel != nil || draw.panel != nil,
      drawingCanvasOnly: drawingCanvasOnly,
      alertedDrawingIDs: alerts.alertedDrawingIDs(symbol: market.symbol),
      atLatest: $atLatest,
      merged: { merged(subs: $0) },
      say: { say($0) },
      onTapped: { dismissPanel() },
      // 他自己动手翻图了：「返回刚才」那条后路当场作废——再点它就是盖掉他刚做的事。
      onUserView: { forgetReturn() },
      onOpenRecord: { openReview(id: $0.uuidString) })
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

  private func reviewState(_ state: ChartState?) -> ChartState? {
    guard var state else { return nil }
    state.percentAxis = false; state.compare = []
    state.price.mode = prefs.priceMode
    state.overlays = prefs.overlays; state.options = prefs.chartOptions
    return state
  }

  private func wireReview() {
    review.onCapture = startReviewCapture
    // 记一笔的那一刻顺手截一张图附在这条记录上（§4.3），和「分享图片」同一支渲染器。
    // 画不出来就没有图：记录照记，详情里那一格不出现。
    review.captureShot = {
      // 记一笔时图表宿主挂的是复盘那只把手（`MainChartView`：`reviewChart.active ?
      // reviewChart.proxy : proxy`），行情那只此刻没有盒子。以前这儿只问行情那只，
      // 于是每一条记录都「画不出来」、详情里永远没有这张图（第 25 项端到端验收时发现）。
      let box = (reviewChart.active ? reviewChart.proxy : proxy).box
      guard let state = reviewState(box?.chart.state), let size = box?.chart.bounds.size, size.width > 0 else { return nil }
      return ChartSnapshotRenderer.png(state: state, size: size, head: chartShotHead, theme: theme)
    }
    // 回放倍速跟着人走：初值从偏好来，那颗按钮一改就写回去（R3-4）。
    reviewChart.preferredSpeed = { store.prefs.replaySpeed }
    reviewChart.onSpeedChange = { value in store.update { $0.replaySpeed = Prefs.clampSpeed(value) } }
    // 「找相似」的范围同理。`ReviewUI` 那个包看不见 `Prefs`，所以在这儿对接两头：
    // 这一句灌初值，下面 `lifecycleContent` 里那两条 `onChange` 管往返（R3-5）。
    review.searchScope = prefs.reviewSearchScope
    // 复盘本里的时刻与口价（审查 B-07 / B-08，复核项 5）。`ReviewUI` 那个包既看不见
    // `Prefs` 也看不见品种目录，所以两样都在这儿灌：时刻跟着图表那一档时区
    // （`prefs.timeZone`，下面 `lifecycleContent` 里有 `onChange` 跟着改），
    // 小数位问品种表要 `priceDecimals`。占位行的步长与精度都为 0（表示「不知道」），
    // 那就交回 nil，让它按那口价自己猜，别把 0.0000004 写成 `0`。
    review.timezone = prefs.timeZone
    let picker = self.picker
    review.priceDecimals = { symbol in
      picker.info(for: symbol)?.knownPriceDecimals
    }
    // 作废记录之类还能反悔的事，走那唯一一条提示（P2.7）。
    review.onUndoable = { text, undo in ToastCenter.shared.say(text, undo: undo) }
    review.onFeedback = { $0 == .done ? Haptics.success() : Haptics.warning() }
    review.onOpenChart = { record in
      endSharePreview(); dismissPanel(); draw.finish()
      replayOrigin = .record(record.id)
      reviewChart.open(record, feature: review, live: reviewState(proxy.box?.chart.state ?? session.liveState(chartInput)), route: route.route)
    }
    // 卡片上改起止时刻（P3.7）：吸附、重算目标失效、把图挪过去，都在图这一头做。
    review.onEditRange = { start, end in reviewChart.editRange(start: start, end: end, feature: review) }
    review.onOpenMatch = { match, cutoff in
      endSharePreview(); dismissPanel(); draw.finish()
      replayOrigin = review.searchRecord.map { .search($0) }
      reviewChart.openMatch(match, cutoff: cutoff, feature: review, live: reviewState(proxy.box?.chart.state ?? session.liveState(chartInput)), route: route.route)
    }
    review.synchronize()
  }
  private func startReviewCapture() {
    endSharePreview(); dismissPanel(); draw.finish()
    reviewChart.beginCapture(feature: review, live: reviewState(proxy.box?.chart.state ?? session.liveState(chartInput)), prefs: prefs)
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
    ReplayHeaderView(bridge: reviewChart, fallbackZone: prefs.timeZone,
                     fallbackDecimals: market.info.priceDecimals)
  }

  /// 记一笔卡片（§2F1）。**盖在图上**，不再排在图下面。画的东西在 `ReviewCaptureLayer`。
  private var captureCard: some View {
    ReviewCaptureLayer(feature: review, bridge: reviewChart, theme: theme,
                       // 横屏图本来就矮，卡片不能占掉一半；竖屏给 280pt。
                       maxHeight: landscape ? 150 : 280,
                       onSaved: {
                         Haptics.success()
                         // 记下的是一笔有方向的判断，到点要叫人——锁屏也得叫得到，那就要通知权限。
                         // 和画线提醒同一个做法：第一次真用到时问一次，问不到也不挡（前台照样补叫）；
                         // 问完按新权限重排，不然这一笔还挂在「没权限」那一轮上。
                         if let id = review.lastSaved, review.record(id)?.outcome == .waiting {
                           Task {
                             await AlertNotifications.requestAuthorization()
                             reviewDue.refresh()
                           }
                         }
                         // 「已记下 · 查看」：右边那颗直接翻到刚记的那条（§2F2）。
                         // 图上那个新记号同时闪一下，两边指的是同一件事。
                         say("已记下", actionTitle: "查看") {
                           review.selectedRecord = review.lastSaved
                           dismissPanel(); review.bookOpen = true; review.synchronize()
                         }
                       })
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

  // ---------------------------------------------------------------- 图的输入

  /// 揉 `ChartState` 要的、**不随推送变**的那一半（审查 21）。
  ///
  /// 逐笔的那一半（序列、持仓量、深度、倒计时）由 `ChartSession.liveState` 在
  /// `MainChartView` 自己的 body 里现取——宿主这儿一个都不读，推送就叫不醒它。
  private var chartInput: ChartInput {
    ChartInput(prefs: prefs, seed: seed, overlays: visibleOverlays, subs: visibleSubs, subScale: subScale,
               drawingCanvasOnly: drawingCanvasOnly, comparing: comparing,
               compareKeys: compareKeys, compareNames: compareNames)
  }

  /// 此刻图上是不是对比态。横屏画线、复盘、看朋友分享的线时暂退，集合本身不动，回来就恢复。
  private var comparing: Bool {
    !compareKeys.isEmpty && !landscape && !draw.active && !reviewChart.active && draw.previewing == nil
  }

  private var compareKeys: [String] {
    prefs.compareSymbols.filter { $0 != InstrumentID.canonical(market.symbol) }
  }
  private var compareNames: [String: String] {
    Dictionary(uniqueKeysWithValues: prefs.compareSymbols.map { key in
      (key, picker.info(for: key)?.base ?? SymbolInfo.placeholder(symbol: key).base)
    })
  }
  private var compareReady: Bool {
    !market.switching && market.routing != .switching
      && comparison.mainSettled(symbol: market.symbol, upstream: market.capabilities.upstream,
                                route: route.route)
  }
  private var compareDrive: CompareDrive {
    let s = market.series
    return CompareDrive(keys: comparing ? compareKeys : [], symbol: market.symbol, interval: market.interval,
      route: route.route, ready: compareReady,
      first: s?.firstTime ?? 0, last: s?.lastTime ?? 0)
  }
  private func updateCompare() {
    comparison.configure(keys: comparing ? compareKeys : [], main: compareReady ? market.series : nil,
      symbol: market.symbol, interval: market.interval, route: route.route)
  }

  /// 副图高度：`Prefs.scale(for:)` 给每个副图的倍率（拖过的用拖出来的，没拖过的用出厂值）。
  ///
  /// 只报当前开着的那几个：`subHeightOverrides` 里会留着以前开过的指标的倍率，全倒进去
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
  ///
  /// 倒计时那一秒记在 `ChartSession.nowMs` 上，只有图读它（审查 21：以前它是这儿的
  /// `@State`，每一秒整页重求值一次）。
  private func heartbeat() async {
    await session.heartbeat(active: beating, countdown: { prefs.countdown }, onBeat: { refreshComfort() })
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
    // 下次冷启动的落点跟着表走（访客那份空档案顶着的那一段不算）。
    if !awaitingAccount { LaunchLandingMirror.set(favorites: !symbols.isEmpty) }
    quotes.setFavorites(symbols)
    watchMove.setFavorites(symbols)
    // 换号那一拍报价簿会把「挂着提醒的品种」清空（那是上一个人的）。这儿顺手把
    // 这个人的那份再交一次，否则他的提醒品种要等下一次存档变动才回得到订阅里。
    alertEngine.republishWatchlist()
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
    // 跟着账号同步（`Prefs.favoritesGroup`；2026-09-19 从 `SymbolPrefs.selectedGroupID`
    // 搬过来的，搬完才是真的跟着人走而不是跟着这台机器）。
    quotes.setVisible(listVisible)
    // 冷启动第一屏就是自选页。趁用户在这儿看报价，把自选的 K 线、以及当前品种
    // 其他常用周期的 K 线先拉好，点进去、切周期第一帧就有图。
    market.prefetchFavorites(symbols, intervals: prefs.quickIntervals)
  }

  /// 向 `AppLifecycle` 报到：离开前台要落什么、进后台要停什么。
  ///
  /// 这些以前散在两个 `scenePhase` 的 `onChange` 里，还有一份在 `AppAccountBridge`
  /// 自己挂的通知里。谁先谁后没人定义，而「根宽先落到 `PrefsStore` 还是存档先排空写盘
  /// 队列」这个顺序，恰恰就是用户那个 bug 的一半。现在顺序写死在 `AppLifecycle` 的
  /// `Priority` 上：产数据的 `.data` 全跑完，排空存档的 `.sync` 最后一个。
  private func wireLifecycle() {
    // 手指抬起那一刻就该写完了（`ChartViewport.interactionEnded`），这一条纯属保险：
    // 万一有一次捏合还卡在那 400ms 的降采样里，人就把 app 切走了。
    let viewportHook = AppLifecycle.shared.register(id: "viewport", priority: .data) { viewport.willLeaveForeground() }
    let reviewHook = AppLifecycle.shared.register(id: "review", priority: .data) {
      review.saveDraft()
      if reviewChart.playing { reviewChart.togglePlay(feature: review) }
    }
    // 内存告警时放掉 K 线缓存：入口只负责听（`KanpanApp`），这里登记谁来收。
    // 以前这行写在 `wireAccount()` 的 `do` 里，没有账号桥的那条路上一次都不登记。
    MemoryWarningRelay.shared.register(id: "market") { [weak market] in market?.memoryWarning() }
    // 档案到货（访客档案装进来、账号档案读回来、云端推下来、换号、恢复出厂）：
    // 图得按新到货的根宽重新起点。**谁到的货、是不是同一个人**由 `arrival` 说明，
    // `ChartViewport` 据此决定要不要把用户刚捏了一半的那份保下来。
    store.onAdopt = { prefs, arrival in viewport.adopt(barSpacing: prefs.barSpacing, reason: arrival) }
    let feedsToken = AppLifecycle.shared.registerResources(id: "feeds") {
      // 先把后台运行额度要下来，再进后台状态：两处宽限窗口靠它才有 CPU 可跑，
      // 短暂切走再回来就不必重连。
      grace.begin()
      session.setForeground(false); sectorFeed.setForeground(false)
      // 后台里响的那些不去动界面，只留一条本地通知（见 `AlertWatcher`）。
      alertWatcher.setForeground(false)
      reviewDue.setForeground(false)
      // 判定也一起停：桶断了就不算连着，回来那一下不拿断口两侧的价去算穿越。
      alertEngine.setForeground(false)
      watchMove.setForeground(false)
      // 小组件：离开前台写最后一份，之后由系统按 15 分钟刷、扩展自己补价。
      widgetFeed.setForeground(false)
    } enter: {
      grace.end()
      session.setForeground(true); sectorFeed.setForeground(true)
      alertWatcher.setForeground(true)
      reviewDue.setForeground(true)
      alertEngine.setForeground(true)
      watchMove.setForeground(true)
      widgetFeed.setForeground(true)
      // 回到前台先拉一次同步：服务端判到价、写回 `status=fired`，这一趟就是
      // 已触发的提醒走到用户眼前的那条路（没有 APNs 时它是唯一一条）。
      accountBridge?.synchronize(); review.synchronize()
    }
    // 根真的没了才停机（场景断开、根被顶掉）。判据是 `@State` 存储的寿命，
    // 不是 `onDisappear`——后者在盖 cover、切标签、转屏时都会响，那时候停流
    // 等于把用户自己的行情掐掉。
    //
    // 捕获列表是必须的：不写的话闭包捕获的是 `MainScreen` 这个结构体，而它的
    // `@State` 包装器正握着 `teardown` 的存储，成环之后 `deinit` 永远不来。
    // 登记全部按 token 撤，撤不到别人的那一份（同一时刻可能已经有新的根接上了）。
    teardown.onTeardown { [session, sectorFeed, grace] in
      AppLifecycle.shared.unregisterResources(token: feedsToken)
      AppLifecycle.shared.unregister(hook: viewportHook)
      AppLifecycle.shared.unregister(hook: reviewHook)
      // `MemoryWarningRelay` 那条不撤：它登记的是 `[weak market]`，模型一释放就成了
      // 空操作；按 id 撤反而可能把新根刚登记的那份摘掉。
      grace.end()          // 系统那份后台额度必须还回去
      // 对比、事件流 / 重连 / OI 轮询、列表那条 socket（不走 25 秒宽限：没有「回来」了）。
      session.stop()
      sectorFeed.setForeground(false)
    }
  }

  /// 提醒这一摊的接线（方案第 2 节）。
  ///
  /// 画完线 → 问一句；答「加入提醒」→ 建；画线几何一动 → 对账；到价判定
  /// （`AlertEngine`）→ 标 `fired`；存档里冒出已触发 → 震一下 + 说一句。
  ///
  /// **到价判定这一段 2026-09-22 才接上线。** 在那之前客户端一侧
  /// （`AlertEvaluator.hit` / `AlertStore.markFired`）是一份写对了但零调用方的实现，
  /// 判定全靠服务端 + APNs；而这个项目没有 APNs 密钥，于是「提醒」在用户手上
  /// 其实一次都没响过。现在前台自己判，服务端那一份照旧当后台的兜底，
  /// 两边靠 `status == .active` 这道闸去重（细节写在 `AlertEngine` 的头注释里）。
  /// 提醒行上的「盯一个」：拿这一刻手上最新的价开一块锁屏实时活动（再点一次就是不盯了）。
  private func watch(_ alert: KanpanCore.Alert) {
    let symbol = alert.symbol
    let ticker = quotes.raw[symbol] ?? (market.symbol == symbol ? market.ticker : nil)
    let price = market.symbol == symbol ? (market.tradeQuote?.price ?? market.ticker?.last) : ticker?.last
    let decimals = picker.info(for: symbol)?.knownPriceDecimals
    let started = activities.toggle(alert, price: price, change: ticker.map { $0.changePercent / 100 },
                                    decimals: decimals, redUp: prefs.redUp)
    if !started && activities.watching == nil && !activities.available { say("系统设置里关掉了实时活动") }
  }

  private func wireAlerts() {
    alertPrompt.onAcceptBatch = { items, symbol in
      for item in items {
        guard alerts.all.count < AlertArchive.limit else { say("提醒最多 \(AlertArchive.limit) 条"); break }
        _ = alerts.add(drawing: item, symbol: symbol)
      }
      Task {
        await AlertNotifications.requestAuthorization()
        PushRegistration.startIfAuthorized()
      }
    }
    // 选中栏上的提醒胶囊。打开之后不再弹「已加入提醒」：胶囊当场变成实心、线右端
    // 多出一枚铃铛，成没成看得见（§P3-8）。满额那句走 `alerts.notice`。
    // 权限只在第一次真的加提醒时问一次。**问不到也不挡**：提醒照建、照同步，
    // 只是后台响的时候弹不出来。
    lineAlert.attach(alerts)
    lineAlert.decimals = { [picker] symbol in
      picker.info(for: symbol)?.knownPriceDecimals
    }
    lineAlert.onArmed = {
      Task {
        await AlertNotifications.requestAuthorization()
        await MainActor.run { PushRegistration.startIfAuthorized() }
      }
    }
    draw.onDragPreview = { [weak lineAlert] item in
      #if DEBUG
        // 拖线的手指归画线覆盖层，不经过 `ChartView.touchesBegan`，画布那条帧探针的打点
        // 接不到它。拖动每报一帧就续一次采集，抬手 1.2 秒后自己停、存盘（和画布手势同一份报告格式）。
        if item != nil { ChartGestureFrames.began(); ChartGestureFrames.ended() }
      #endif
      lineAlert?.drag(item)
    }
    // 线被挪了就按同一个提醒 id 重算几何、重新上膛；线被删了提醒跟着删。
    draw.onGeometryChanged = { archive in alerts.reconcile(with: archive) }
    // 到价判定：两条流各喂各的。图上那只走 `MarketModel`（逐笔，最细），别的品种走
    // 报价簿那条列表流。捕获列表不能省——不写的话闭包捕获的是整个 `MainScreen`
    // 结构体，而它的 `@State` 盒子正握着 `market` / `quotes` 本身，成环之后就不放了
    // （和 `teardown.onTeardown` 那儿同一个理由）。
    alertEngine.attach(alerts)
    alertEngine.onWatchlist = { [weak quotes] symbols in quotes?.setAlertedSymbols(symbols) }
    market.onPrice = { [weak engine = alertEngine, weak mover = watchMove, weak activities, weak quotes, weak lineAlert] symbol, price, timeMs in
      engine?.observe(symbol: symbol, price: price, timeMs: timeMs)
      mover?.observe(symbol: symbol, price: price, timeMs: timeMs)
      activities?.observe(symbol: symbol, price: price, change: quotes?.raw[symbol].map { $0.changePercent / 100 })
      lineAlert?.observe(symbol: symbol, price: price)
    }
    quotes.onPrice = { [weak engine = alertEngine, weak mover = watchMove, weak activities] tickers in
      engine?.observe(tickers)
      mover?.observe(tickers)
      for t in tickers { activities?.observe(symbol: t.symbol, price: t.last, change: t.changePercent / 100) }
    }
    // app 被杀过、锁屏上那块还挂着：接回来继续跟价。
    activities.adopt(alerts: alerts.all)
    alertWatcher.priceDecimals = { [picker] symbol in
      picker.info(for: symbol)?.knownPriceDecimals
    }
    alertWatcher.sound = { [weak store] in store?.prefs.alertSound ?? .default }
    alertWatcher.attach(alerts)
    // 复盘到点不经 `alertWatcher`：只有没有通知权限时由 `reviewDue` 在前台补叫这一声。
    reviewDue.onInApp = { reminder in
      Haptics.alarm()
      say(reminder.title, actionTitle: "查看") { openReview(id: reminder.id.uuidString) }
    }
    alertWatcher.onFired = { alert in
      guard let drawingID = alert.drawingID else {
        return say(alert.title, actionTitle: "查看") { open(linkedSymbol: alert.symbol) }
      }
      say(alert.title, actionTitle: "查看") {
        open(linkedSymbol: alert.symbol)
        draw.highlight(drawingID: drawingID, symbol: SymbolPrefs.key(alert.symbol))
      }
    }
  }

  /// 自选五分钟波动提醒（P3.1）：开关与幅度跟着设置走，自选在 `settleFavorites` 交进去，
  /// 价在 `wireAlerts` 那两条流上一起喂。响了：通知中心留一条 + 震一下 + 浮条「查看」。
  private func wireWatchMove() {
    watchMove.follow { [weak store] in
      (store?.prefs.watchMoveAlert ?? false, store?.prefs.watchMoveThreshold ?? WatchMove.defaultThreshold)
    }
    watchMove.onEvent = { [weak store] event in
      let decimals = picker.info(for: event.symbol).map(\.priceDecimals)
      AlertNotifications.present(event, decimals: decimals, sound: store?.prefs.alertSound ?? .default)
      UIImpactFeedbackGenerator(style: .rigid).impactOccurred()
      let title = WatchMove.title(for: event)
      // 那唯一一条提示画在面板与表之上（P2.7），开着提醒总表时也看得见。
      say(title, actionTitle: "查看") {
        showAlerts = false
        dismissPanel()
        open(linkedSymbol: event.symbol)
      }
    }
  }

  /// 桌面小组件（P3.2）：自选、报价、皮肤折成一份快照写进 App Group，扩展只读它。
  /// 自选 / 分类 / 皮肤一变立刻写并重载；价只是动了，按 `WidgetFeed` 的节奏写。
  private func wireWidget() {
    widgetFeed.bind(
      collect: { closes in
        let prefs = store.prefs
        return WidgetFeed.snapshot(
          symbols: picker.prefs, quotes: quotes.raw.mapValues { quotes.presented($0) },
          decimals: { symbol in
            picker.info(for: symbol)?.knownPriceDecimals
          },
          closes: closes, skin: prefs.skin, appearance: prefs.theme, redUp: prefs.redUp,
          refresh: RouteResolver(policy: prefs.routePolicy).defaultProvider.widgetRefresh,
          basis: prefs.changeBasis)
      },
      shape: {
        let symbols = picker.prefs, prefs = store.prefs
        return symbols.favorites + ["|"] + symbols.groups.map { $0.id + ":" + $0.name }
          + symbols.groupForSymbol.map { $0.key + "=" + $0.value }.sorted()
          + [prefs.skin.rawValue, prefs.theme.rawValue, String(prefs.redUp), prefs.changeBasis.rawValue,
             prefs.routePolicy.rawValue]
      },
      fetchCloses: { [quotes] symbol in await quotes.closes(symbol: symbol) })
  }

  /// 新建价格提醒那一页问的：用户打的这串是哪只品种、现价多少。
  /// 「ETH」认成 `ETHUSDT`；图上那只取逐笔，别的取报价簿。
  private func alertQuote(_ text: String) -> PriceAlertQuote? {
    let raw = text.trimmingCharacters(in: .whitespaces).uppercased()
    guard !raw.isEmpty else { return nil }
    // 输入框里是给人看的代号（「BTCUSDT」「ETH」「BTC/USD」），报价簿、目录、提醒存的都是完整 key。
    // 别家的代号带「-」、显示成「/」，比的时候两样都抹掉：「BTC/USD」「BTC-USD」「BTCUSD」都认。
    let main = InstrumentID.canonical(market.symbol)
    let flat = { (s: String) in s.uppercased().filter { $0 != "-" && $0 != "/" } }
    let typed = flat(raw)
    let symbol: String? = if typed == flat(InstrumentID(main).symbol) || raw == main.uppercased() {
      main
    } else {
      [raw, raw + "USDT"].map(InstrumentID.canonical).first { picker.info(for: $0) != nil }
        ?? picker.catalog.first { flat($0.id.symbol) == typed }?.id.key
    }
    guard let symbol else { return nil }
    let price: Double?
    if symbol == main {
      price = market.tradeQuote?.price ?? market.ticker?.last ?? quotes.observedQuote(symbol)?.last
    } else {
      // 这个闭包在新建提醒那一页的 body 里求值：点名那只走参与观察的镜像，价到了那一页就重算。
      price = quotes.observedQuote(symbol)?.last
    }
    let decimals = picker.info(for: symbol)?.knownPriceDecimals
    return PriceAlertQuote(symbol: symbol, price: price.flatMap { $0 > 0 ? $0 : nil }, decimals: decimals)
  }

  /// 站到某一条复盘记录上（通知、提醒总表、到点浮条都走这儿）。
  private func openReview(id: String) {
    guard let uuid = UUID(uuidString: id), review.record(uuid) != nil else { return }
    dismissPanel(); showAlerts = false
    review.selectedRecord = uuid
    review.bookOpen = true
  }

  /// 只由 `BootOnce` 调（它保证一辈子只进来一次）。别在别处直接调它。
  private func boot() {
    wireLifecycle()
    wireAlerts()
    wireWatchMove()
    wireWidget()
    // 先把档案装进来，再开行情。
    //
    // 以前是反过来的（注释写着「让网络 I/O 和首帧渲染重叠」）：`market.start` 跑在
    // `wireAccount()` 前面，那一刻 `prefs` 还是出厂值——域名、周期、快照开关、
    // 「上次看的那张图」全是错的，得等档案装进来再逐个 `onChange` 补回去。实测就是
    // 「切到 4h、杀掉重开，回到 1h」。而且补回去意味着白打一趟跨洋请求、还让人先
    // 看一眼不是他上次那张图，比晚开这十几毫秒（几个小 JSON 的同步读盘）贵得多。
    // 连接预热本来就在 `LaunchPrewarm` 里更早跑着，这里挪后不影响握手。
    wireAccount()
    // 第一帧画的是自选页时，不为图表同步读 K 线快照（主线程上的一次读盘 + 解码）；
    // 快照照样由 feed 异步送到，点进图表第一帧仍然有图。
    // 启动快照一律开着：原来那颗「启动快照」开关 2026-09-24 从设置页撤了、字段也删了（审查 U13）。
    market.start(snapshot: true, symbol: picker.prefs.recents.first, interval: prefs.interval,
                 deferSnapshot: tab == .favorites)
    picker.setSectionsActive(false)
    quotes.onReset = { picker.clearQuotes() }
    quotes.onScopeChange = { picker.retainQuotes(for: $0) }
    quotes.onUpdate = { [widgetFeed] rows in
      picker.updateQuotes(rows)
      widgetFeed.quotesChanged()
    }
    quotes.onHistory = { picker.setHistory($0, $1) }
    // 交易所不认这个代号：只把它标成下架，自选一行都不删（审查 B-06）。
    // 两处都标是因为品种页手里握的是目录的一份副本，标了它这一屏才立刻一致。
    quotes.onSymbolRejected = { symbol in
      picker.markDelisted(symbol)
      market.noteSymbolRejected(symbol)
    }
    session.configure(route: route, basis: prefs.changeBasis)
    // 自选表要赶在 `setChartSymbol` 前面：后者会重算订阅范围，那时候如果自选还是空的，
    // `configure` 刚恢复出来的那批报价就会被裁到只剩图上这一个品种。
    //
    // 空表则一个字都别说。登录过的机器上这会儿挂着的是**访客**那份档案（`AppAccountBridge`
    // 初始化时同步装的），里面本来就没有自选；把这份空表交上去，`QuoteBook` 会认定
    // 「自选范围已知且为空」，刚从磁盘恢复出来的十几行报价当场被裁光。等
    // `account.restore()` 把账号那份读回来，走 `settleFavorites(_:)` 再交。
    // 自选波动提醒也要在这一拍认表：没登录（或测试档案）时自选不会再「变」一次，
    // 不交就永远盯着一张空表。
    if !picker.prefs.favorites.isEmpty {
      quotes.setFavorites(picker.prefs.favorites)
      watchMove.setFavorites(picker.prefs.favorites)
    }
    quotes.setChartSymbol(market.symbol)
    quotes.setForeground(phase != .background)
    // 全市场 24h 行情落盘、冷启动先恢复（板块页第一帧就有清单）；每到一批（含恢复出来的
    // 那批）都种进报价簿，从板块列表 / 搜索点进一只没看过的品种，价格第一帧就在。
    sectorFeed.cache = .disk
    sectorFeed.onTickers = { [quotes] tickers, upstream in quotes.seed(tickers, upstream: upstream) }
    picker.seedTickers = { [quotes] in quotes.seedTable }
    sectorFeed.configure(route: route)
    previews.configure(route: route)
    sectorFeed.setCatalog(picker.catalog)
    sectorFeed.setForeground(phase != .background)
    picker.onPick = { info in
      endSharePreview()
      symbolSearch.reset()
      // 挑完品种落到行情页：自选、搜索、品种整页三条路都是「去看哪张图」。
      // 从别的一格走进来的，记下来路，顶栏那颗返回才回得去。
      if tab != .chart { chartOrigin = tab }
      tab = .chart; didLeaveLaunch = true
      if info.symbol == market.symbol { proxy.scrollToLatest(animated: false) }
      session.show(symbol: info.symbol)
    }
    picker.setLoader(market.catalogLoader)
    market.knownInfo = { [picker] in picker.info(for: $0) }
    // 搜了一个表里没有的代号：那是「用户点名」，允许立刻问一次目录（审查 B-06）。
    picker.onMissingSymbol = { [market] symbol in await market.lookupMissingSymbol(symbol) }
    market.setExternalIndicators(prefs.subs, depth: prefs.depth)
    // Configure the catalog and its source before presenting the favorites list.
    // Otherwise FavoritesView can start its first catalog request against the
    // default route while the host/source setup is still in flight.
    // 停在哪一格由 `honorProfile()` 按刚装进来的那份档案定，这儿只补预热。
    if !picker.prefs.favorites.isEmpty { primeFavorites(picker.prefs.favorites) }
    // 上次用的是哪把画线工具。只用来在工具面板上把那一格预选高亮（见 `Prefs.lastDrawTool`），
    // 不是「此刻正举着笔」——待画状态归图自己管，换品种照样清掉，冷启动也不会举着笔进来。
    draw.onPickTool = { tool in store.update { $0.lastDrawTool = tool.rawValue } }
    live = true
    // 点通知 / 桌面快捷入口冷启动进来的那一条，这会儿才有人接得住
    // （行情、品种表、报价簿都接好了）。
    consumeDeepLink()
  }

  private func wireAccount() {
    // 画线那几套 fixture 自己带隔离档案，账号用例会明确指一个 endpoint，所以这条
    // 岔路让它们跳过真账号桥。**只在 DEBUG 构建里存在**（审查 C-02）：正式包必须
    // 走真正的产品初始化，否则「Release 回归」跑的是一条没有账号桥的启动路径。
    #if DEBUG
    if ProcessInfo.processInfo.environment["KANPAN_TEST_PROFILE"] == "1",
       ProcessInfo.processInfo.environment["KANPAN_ACCOUNT_API_URL"] == nil {
      // 没有账号桥，就没有「档案到货」那个事件；但档案本身在建 store 的那一刻就已经
      // 读进来了，落地页照样得按它兑现一次，否则有自选的人也停在行情页。
      // 复盘的档案原来是 `ReviewFeature` 自己在构造时开的，现在只由账号桥注入；
      // 没有桥的这条岔路得自己给它一份（仍落在这棵测试子树里），不然「记下」永远存不进去。
      if let reviewStore = try? ReviewStore(paths: .legacy(in: ReviewChartBridge.storageDirectory())) {
        review.activate(store: reviewStore, client: nil)
      }
      honorProfile(); return
    }
    #endif
    do {
      let bridge = try AppAccountBridge(account: account, prefs: store, symbols: picker, drawings: draw, alerts: alerts, review: review, search: searchHistory, inbox: inbox)
      bridge.canApply = { syncGate }
      bridge.onSwitch = {
        endSharePreview(); showFriends = false; showFriendPicker = false; shareDraft = nil; shareShot = nil
        replying = nil
        if reviewChart.mode == .capture { reviewChart.endCapture(feature: review) }
        else if reviewChart.mode == .replay { reviewChart.exitReplay(feature: review) }
        symbolSearch.reset()
        // 用户自己换号 / 退登，要把人从自选页带走（别让他对着上一个账号的表）。
        // 冷启动那一段不算：装访客档案、以及 `account.restore()` 把登录态读回来，
        // 走的是同一条路，那时候该停哪一格交给 `honorProfile()` 按真档案定。
        if !awaitingAccount { tab = .chart; didLeaveLaunch = true }
        // 正勾着的那次批量编辑跟着走：换了号，表就不是刚才那张表了，
        // 勾中的代号留着只会落到别人的自选上。
        // 落脚点也一起丢（审查 C-08）：换了号，「他停在 APTUSDT 那一行」说的是
        // 上一个人的表，留着只会把新账号的表滚到一个莫名其妙的位置。
        if !awaitingAccount { favoritesEdit.end(); favoritesEdit.forgetScrollAnchor() }
        // 换了号，锁屏上盯着的是上一个人的提醒，收掉。
        if !awaitingAccount { activities.stop() }
        dismissPanel(); crosshairReadout.clear()
      }
      // 档案真的装进来之后才谈「该开哪张图、该停在哪一格、该用哪个周期」。
      bridge.onProfileReady = { honorProfile() }
      // 冷启动这一段（装访客档案 → 等 `account.restore()`）里手上可能还是访客那份
      // 空档案，落地页不能拿它当真，所以先把旗子举起来再装档案。
      awaitingAccount = true
      try bridge.activate()
      accountBridge = bridge; bridge.focus(market.symbol)
      activities.submitToken = { [weak bridge] token, activityID, alertID in
        bridge?.submitActivityToken(token, activityID: activityID, alertID: alertID)
      }
      activities.submitEnd = { [weak bridge] activityID in bridge?.endActivity(activityID) }
      // 视野的「云端那条腿」。没有桥（或没登录）时它是 nil，模块照常工作——
      // 登录与否只差这一个引用，对外行为一模一样，调用方一个字的分支都不许写。
      viewport.sync = bridge
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
  private var syncGate: Bool { !draw.active && panel == nil && !reviewChart.active && draw.previewing == nil }

  /// 档案（prefs / symbols）真的换进来之后，把「该开哪张图、该停在哪一格、
  /// 该用哪个周期」按新档案重新兑现一次。
  ///
  /// 这三件事以前各修各的，而且各漏各的：品种去读 `SymbolPrefsStore()` 那个没注入
  /// 存储的柜子（写在账号文件里、读在 UserDefaults 里）；周期只在 `boot()` 里读一次，
  /// 那一刻档案还没装进来，读到的是出厂 1h，而 `subs` /
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
      if !profile.favorites.isEmpty { if !symbolSearch.isActive { tab = .favorites } }
      else if !awaitingAccount { tab = .chart }
      // 上次看的那张图。`boot()` 中途调到这儿时行情还没开张，那一次交给
      // `market.start(symbol:)` 直接开对，不在这儿切。
      if live, let last = profile.recents.first, last != market.symbol {
        session.show(symbol: last)
      }
    }
    if !awaitingAccount {
      // 真档案判过一次了：落点镜像跟着改，占位放下。冷启动按镜像开在自选、而档案
      // 也判自选时，上面那句 `tab = .favorites` 等于没动。
      landingHeld = false
      LaunchLandingMirror.set(favorites: !profile.favorites.isEmpty)
    }
    // 周期跟着人走（已经从 `PersonalSyncCodec.keepDeviceFields` 里拿出来了）。
    // 复盘在跑的时候图是复盘自己的，别动。
    if live, !reviewChart.active, prefs.interval != market.interval {
      session.show(interval: prefs.interval)
    }
    // 报价簿要等 `boot()` 把线接好才认表；`boot()` 自己会交一次。
    if live { settleFavorites(profile.favorites) }
  }

  // ---------------------------------------------------------------- 深链

  /// 把外面递进来的那一条链接走完（通知点击、桌面快捷入口、共享链接，见 `DeepLink`）。
  ///
  /// 所有外来入口只有这一个落点：换品种走的是自选行、板块行同一条路
  /// （`picker.pick`），不另起一套跳转，免得同一个「打开 BTC」在通知里和在自选里
  /// 行为不一样。界面还没接好线（`live == false`）时按兵不动——`boot()` 末尾会回来取。
  private func consumeDeepLink() {
    guard live, let link = DeepLinkRouter.shared.consume() else { return }
    switch link {
    case let .symbol(symbol, interval):
      open(linkedSymbol: symbol)
      if let raw = interval, let iv = Interval(rawValue: raw) { pick(interval: iv) }
    case let .drawing(symbol, drawingID):
      showAlerts = false
      open(linkedSymbol: symbol)
      // 只高亮，不进画线工作台：从通知 / 提醒列表点进来的人要看的是「那条线在哪儿」，
      // 不是「开始画线」（后者在竖屏会当场把屏幕转过去）。品种的线还没装进图时
      // `highlight` 会先记着，等 `ChartHost` 那边 `draw.focus(symbol)` 完成再兑现。
      draw.highlight(drawingID: drawingID, symbol: SymbolPrefs.key(symbol))
    case .alerts:
      dismissPanel()
      showAlerts = true
    case let .review(id):
      // 复盘那条「到点了」的通知点进来：直接站到那条记录上。
      openReview(id: id)
    case .search:
      openLinkedSearch()
    case .favorites:
      // 桌面小号自选那一格点进来。
      dismissPanel(); showAlerts = false
      switchTo(tab: .favorites)
    case let .share(id):
      if let item = inbox.items.first(where: { $0.id == id }) { openShare(item) }
      else { showFriends = true; inbox.pull() }
    }
  }

  /// 链接点名的那个品种。目录里有就走 `picker.pick`（和点自选行一模一样）；
  /// 目录还没载回来就自己换图，那一笔「他看过这张图」照样记下。
  private func open(linkedSymbol symbol: String) {
    endSharePreview()
    dismissPanel()
    if let info = picker.info(for: symbol) { picker.pick(info); return }
    symbolSearch.reset()
    if tab != .chart { chartOrigin = tab }
    tab = .chart; didLeaveLaunch = true
    picker.visit(symbol)
    session.show(symbol: symbol)
  }

  private func openLinkedSearch() {
    dismissPanel()
    symbolSearch.openSearch()
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
    shareInterval?.userPicked()
    dismissPanel()
    guard iv != market.interval else { return }
    store.update { $0.interval = iv }
    // 换了一档，「刚才那一屏」是上一档的坐标，回不去了（§P3-2）。
    forgetReturn()
    // 「看细节」钻下去之后切回大周期：回到钻之前那个视野，而不是这一档的最新一屏——
    // 人是为了看清刚才那一根才下去的，回来当然还站在原地（§10.1）。
    // 栈里没有这一档就是平常的换周期，顺手把可能还欠着的那笔「铺到某段时间」销掉。
    if let back = detailZoom.pop(symbol: market.symbol, interval: iv) {
      proxy.show(window: back, symbol: market.symbol, interval: iv)
    } else {
      proxy.cancelWindow()
    }
    // 换周期连同收十字线一起走会话那一个入口。
    session.show(interval: iv)
    Haptics.step()
  }

  /// 冻结扫图名单。点的若正是图上这只（不会触发 `onSymbol`），邻居就在这里先预取；
  /// 点了别的那只，`onSymbol` 随后会拿新品种的邻居把这一笔替掉（B1 / B2）。
  private func adoptScanList(_ symbols: [String]) {
    let list = ScanList(symbols)
    scanList = list
    market.prefetchNeighbors(list.neighbors(of: market.symbol))
  }

  /// 顶栏价格区横滑一下：按冻结下来的名单换上一只 / 下一只（§10.1）。
  ///
  /// 换品种走的是**和点自选行一模一样的那条路**（`open(linkedSymbol:)` → `picker.pick`），
  /// 不另起一套加载：周期、根宽、指标、画线该怎么跟过去就怎么跟过去。
  private func scan(_ direction: ScanDirection) {
    // 复盘和画线各有各的横向手势与语义，这时候不扫图。
    guard !reviewChart.active, !draw.active, panel == nil else { return }
    guard let list = scanList else { return }
    switch list.step(from: market.symbol, direction) {
    case .unavailable:
      // 没名单可扫。一声不吭——给了触感人会以为自己滑错了方向。
      return
    case .edge:
      // 到头了。不循环、不弹字，只轻轻顶一下手指（§10.1）。
      Haptics.tap()
    case .move(let symbol):
      // 正在看历史：新的那只也停在同一段时间上，不要每换一只就被拽回最新——
      // 横着扫一排品种，看的就是「同一段时间里它们各自在干什么」。
      let keep = atLatest ? nil : proxy.currentView
      detailZoom.clear()
      // 人已经翻到下一只去了，那句问话问的还是上一只身上那条线——跟着走没有意义，
      // 当场收掉（等于「只画线」，线本身早就落盘了）。横滑本身照常翻：那一句是挂在
      // 价格行上的一层 overlay，除了它自己那两颗按钮，整行的横滑仍旧走这条路。
      alertPrompt.dismiss()
      open(linkedSymbol: symbol)
      if let keep { proxy.show(window: keep, symbol: symbol, interval: market.interval) }
      Haptics.step()
    }
  }

  // ---------------------------------------------------------------- 返回刚才（§P3-2）

  /// 点「最新」之前先记一笔：人现在看的是哪一屏。
  ///
  /// 「最新」是一下不可逆的跳转——从三个月前的那一段被拽回此刻，想回去只能重新拖。
  /// 记下来之后行尾那一格变成「返回刚才」，点一下原样回去。
  private func rememberBeforeLatest() {
    guard !atLatest, let view = proxy.currentView else { return }
    returnView = view
    returnStamp += 1
  }

  /// 「返回刚才」：把视野原样铺回去，这条后路随即作废（回来了就不用再回了）。
  private func returnToRemembered(_ view: ViewWindow) {
    proxy.show(window: view, symbol: market.symbol, interval: market.interval)
    forgetReturn()
  }

  /// 后路作废。手一碰图、换品种、换周期、或者六十秒到了，都走这儿。
  private func forgetReturn() {
    guard returnView != nil else { return }
    returnView = nil
    returnStamp += 1
  }

  /// 「看细节」：把十字线选中的这一根，换到更细的一档铺满一屏（§10.1）。
  private func zoomIntoDetail(_ crosshair: Crosshair) {
    guard let series = market.series, series.symbol == market.symbol,
          series.interval == market.interval,
          crosshair.index >= 0, crosshair.index < series.count,
          let finer = DetailZoom.finer(than: market.interval) else { return }
    let open = Double(series.time(at: crosshair.index))
    // 这一根管到哪儿：下一根的开盘时刻。没有下一根（选的就是末根）才按名义步长加一格——
    // 1M / 1y 那两档每根长短不一，能问真值就别算（`DetailZoom.window` 那段注释）。
    let end = crosshair.index + 1 < series.count
      ? Double(series.time(at: crosshair.index + 1))
      : open + Double(series.step)
    // 先记下此刻的视野：切回这一档时回到这儿。
    if let view = proxy.currentView {
      detailZoom.push(symbol: market.symbol, interval: market.interval, view: view)
    }
    // 换档走的还是那唯一一条换档的路，铺视野的请求跟在它后面提（`pick` 会把旧请求销掉）。
    pick(interval: finer)
    proxy.show(window: DetailZoom.window(barOpen: open, barEnd: end, finer: finer),
               symbol: market.symbol, interval: finer)
  }

  /// 说一句话。全 app 只有一条提示（`ToastCenter`），新的一句直接顶掉旧的。
  ///
  /// 给了 `undo` 就在右边画一颗按钮并停 5 秒：1.6 秒只够读完，来不及看清、
  /// 决定、再抬手点。不给就还是 1.6 秒。按钮上的字默认是「撤销」，
  /// 「已记下 · 查看」这类「去看看」用 `actionTitle` 换掉。
  private func say(_ text: String, actionTitle: String = "撤销", undo: (() -> Void)? = nil) {
    let center = ToastCenter.shared
    center.theme = theme
    center.say(text, actionTitle: actionTitle, undo: undo)
  }
}

#Preview { MainScreen() }
