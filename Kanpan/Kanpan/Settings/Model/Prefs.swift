import Foundation
import KanpanCore
import KanpanData
import KanpanNetwork

/// 一份完整的设置（任务书 §3.2 的 `AppState` 里可持久化的那一半）。
///
/// 纯值类型、`Sendable`，读的人拿到的是快照，不会被别的线程改到。
/// 默认 AICoin 风格、1h、MA 与 VOL/OI/MACD，具体参数见 AICoinBehavior。
/// 已存设置通过容错解码保留，不在启动时强行重置。
///
/// 品种、自选、最近**不在这里**——那三样归 `SymbolPrefs`（`kanpan.symbols.v1`），
/// 画线归 `DrawStore`。这里只管「设置」四个面板能改的东西。
struct Prefs: Sendable, Equatable {

  // ---------------------------------------------------------------- 周期
  /// 当前周期。原型 `S.interval` 恒从 `'1h'` 起步。
  var interval: Interval = .h1
  /// 周期条第一行的常用档（原型 `QUICK`）。§10.6：长按可增删，最多 `Prefs.maxQuick`（六）个。
  var quickIntervals: [Interval] = Interval.quick

  // ---------------------------------------------------------------- 外观
  /// 跟随系统 / 浅 / 深（A6.3）。
  var theme: ThemeChoice = .system
  /// 配色：青苔（冷）/ 陶土（暖）。出厂青苔。
  var skin: ThemeSkin = .sage
  // 「按屏幕亮度切换深浅」（`ambientTheme`）2026-09-28 收掉：深浅只有跟随系统 / 浅 / 深三档，
  // 系统自己的「自动」外观已经管了昼夜切换，再按屏幕亮度切一层只会两套规则打架。
  /// 涨跌对调（A6.7）。2026-10-03 用户：「现在一律默认绿涨红跌」——出厂绿涨（`false`），
  /// 老用户的档在 `PrefsCodec` 第 4 版一次性迁成绿涨、云端由服务端迁移 0041 翻一次；
  /// 之后用户自己切回红涨就一直是红涨。
  var redUp: Bool = false

  // ---------------------------------------------------------------- 图
  /// 对比 K 线的品种集合（完整品种 key，最多三只，见 `Kanpan/Kanpan/Compare/`）。
  /// 有值时主图换成百分比坐标；集合跟着人走，换主品种不清。
  var compareSymbols: [String] = []
  /// 价格轴 常规 / 对数 / 百分比（A6.8）。
  var priceMode: PriceMode = .log
  // 「十字线吸附到 K 线」（`magnet`）2026-09-28 收掉了设置项；2026-10-03 起十字线一律不吸附、
  // 横线跟着手指的高度走（`ChartSession` 里写死 `magnet: false`）。画线栏上的「吸附」是另一件事
  // （`DrawingPreferences.magnet`），不受影响。恢复见 tag settings-before-trim-2026-09-28。
  /// 盘口。默认关。
  var depth: Bool = false
  /// 主图指标「主力订单流」：簿里过门槛的大单画到 K 线上。默认关。
  var orderFlow: Bool = false
  /// 分析 › 主力订单流 › 历史大单。默认只看仍挂着的单，随账号同步。
  var orderFlowHistory: Bool = false
  /// 图上大单与爆仓气泡（2026-10-08，键名沿用）：每根向上（大买 + 空单爆仓）/ 向下（大卖 + 多单爆仓）过门槛的在 K 线高 / 低外
  /// 标点或泡，点泡开「大单与爆仓」。出厂开、跟账号走；和挂单墙（`orderFlow`）互不依赖——墙关着泡照出。「指标 › 主力订单流」里一颗开关。
  var bigTradeSigns: Bool = true
  /// 自动分析层，跟人走；目前只有公允价值缺口（`AutoLayer.fvg`）。「分析 › 指标」里单独一颗开关，
  /// 不进 `overlays`、不受「隐藏画线」影响。按打开先后排、不重复，出厂全关。
  var autoLayers: [AutoLayer] = []
  /// 主力订单流：用户改过门槛 / 步长的那几只（键是去掉缩放前缀的 base，`OrderFlowFacts.overrideKey`）。
  /// 没改过的 base 不在表里，一律走默认表——默认表以后调了，没改过的人跟着变。随账号同步（整张表一个字段）。
  ///
  /// 整张表一个字段是**有意接受的取舍**（审查 5.9 / 第 42 项）：两台设备在同一段离线时间里各改一只币，
  /// 后写的会把先写的整张盖掉。要不盖就得让服务端按 base 做字段级合并，那是一套新的合并规则，
  /// 而一个人同时在两台设备上改两只币的门槛极少见（用户规模也就几个人），改错了再改一次即可。
  var orderFlowOverrides: [String: OrderFlowOverride] = [:]
  // 主力订单流的四个显示开关（`orderFlowSpot` / `orderFlowContract` / `orderFlowShowFilled` /
  // `orderFlowShowCancelled`，「指标 › 主力订单流」表底「显示」一节）2026-09-28 收掉（收设置项 D 组）：
  // 现货与合约一律显示；历史是否显示由 `orderFlowHistory` 统一控制（2026-10-09）。
  /// 蜡烛 / 平均K线（Heikin-Ashi）。默认蜡烛。
  var candleKind: CandleKind = .candle
  // 2026-09-28 收设置项 B 组：网格、阳线实心 / 空心、实时价格线、本根倒计时、至今涨幅、
  // 横向 / 纵向位置、K 线数据位置、十字线取价、主 / 副轴允许翻转、指标区域自适应这十二项
  // 不再给人调，一律按 `chartOptions` 里写的定值画（理由写在那儿）。老存档与云端老 body
  // 里的这些键读时忽略，服务端把它们退役了。恢复见 tag settings-before-trim-2026-09-28。
  /// 用户缩放到的根间距（pt）。
  ///
  /// 「我要一屏看多少根」是**人的习惯**，不是某个品种的属性：以前它只活在图自己身上，
  /// 换品种一律回到出厂的 4pt，用户捏小了去自选点下一个品种，K 线又变回一屏五十根。
  /// 所以把它挪到设置里，跟皮肤、副图高度同一等级——所有品种、所有周期共用一份，
  /// 跨 app 重启也在。没存过就是出厂的 `initialSpacing`。
  ///
  /// ⚠️ **这一份是「档案那一份」，手指抬起那一刻才写**（`ChartViewport.interactionEnded`
  /// → `PrefsStore.storeBarSpacing`），捏的过程中它不动。本程内要「用户此刻捏到多宽」
  /// 请读 `ChartViewport.barSpacing`，那一份手一动就变——用户捏完立刻换周期换品种，靠的是它。
  var barSpacing: Double = AICoinBehavior.initialSpacing
  /// 横屏（画线台、横过来的全屏图）自己记的根间距（pt）。竖屏仍用 `barSpacing`。
  ///
  /// 两边共用一份的时候，横屏图宽是竖屏的两倍多，在横屏里捏一下合适了，转回竖屏一屏的根数
  /// 就跟着翻了一倍（反过来也一样）。所以横竖各记各的，转屏时各回各的（`ChartViewport`）。
  ///
  /// **第一次有这个字段时取当时的 `barSpacing`**：老存档、云端老 body 里没有这个键，读的时候
  /// 拿同一份里的 `barSpacing` 补上（`PrefsCodec`），之后两份独立。范围与 `barSpacing` 同一个
  /// （`clampSpacing`，1.6…40）。随账号同步，和 `barSpacing` 同理是「人的习惯」。
  var landscapeBarSpacing: Double = AICoinBehavior.initialSpacing
  /// 主图上下翻转（双击价格轴）。和根间距同理：是「我习惯怎么看」，不是这个品种的属性。
  /// 原来要先在设置里打开「主轴允许翻转」才认，2026-09-28 起开关收掉、手势直接生效，
  /// 再双击一下就翻回来。
  var mainInverted = false
  /// 哪几个副图被上下翻转（双击副图那一侧）。同上，手势直接生效。
  var subInverted: Set<IndicatorID> = []
  // 「主图在竖屏里占多少」（`portraitHeight`）2026-10-10 退役：三端只读不写、永远 0.5，主副图比例由我们定，
  // 不摆出来让人调（`kanpan-sector-page-no-basis-picker`）。图表直接用 `ChartOptions.portraitHeight` 的出厂值；
  // 老存档、云端老 body 里的这个键读时忽略，服务端在 RETIRED_SETTINGS_FIELDS 里退役。
  var indicatorColors: [IndicatorID: [Int: Hex]] = [:]
  // 「指标输出」开关（`hiddenOutputs`，指标编辑页「输出」一节）与 RSI 上下限（`rsiUpper` / `rsiLower`，
  // 线上合成 `rsiRange`）2026-09-28 收掉（收设置项 C 组）：线一律全画（不想要哪条均线就左滑删掉那个周期），
  // RSI 超买超卖线定在 70 / 30（`ChartState` 的出厂值）。老存档、云端老 body 里的这些键读时忽略，服务端退役。
  // 「盯盘时不锁屏」（`keepAwake`）2026-09-28 收掉：图表页在前台就常亮、离开图表页或退后台放手，
  // 不再交给用户开关（`KeepAwakeGate`）。
  // 这儿原来还有 `launchSnapshot`（§4.3 的「启动快照」开关）。2026-09-24 审查 U13 把它从
  // 设置页撤了，字段随后也删掉：界面上改不了的开关，谁要是以前关过，就永远关着、
  // 再也打不开——冷启动一直是空图。启动快照现在无条件开着（`MainScreen.boot`）。
  /// 时区：全 app 一律按上海时间（UTC+8）显示——K 线时间轴、十字线、提醒与复盘的时刻。
  ///
  /// 2026-09-28 起不再是设置项（原来是「本地 / UTC / UTC+8」三档的存储字段，同步白名单两端已退役）。
  /// 留成只读的计算属性，是为了读它的各处（图表、复盘、提醒）不用各自再写一遍口径。
  /// 这只管**显示**：日线及以上的 K 线边界是交易所给的 UTC 0 点（上海 08:00），不跟着它挪。
  var timeZone: TZChoice { .exchange }
  // 「涨跌幅起点」（`changeBasis`）2026-09-28 收掉：口径按品种类型自动定（`ChangeBasis.automatic`）——
  // 加密看滚动 24 小时，美股 / ETF / 贵金属 / 指数这类有交易日的看 UTC 0 点起。
  /// 所有价格提醒共用，随账号同步；复盘到期通知不使用此项。
  var alertSound: AlertSound = .default
  /// 自选五分钟波动提醒（P3.1），出厂关。判定只有一种，见 `WatchMove`。
  var watchMoveAlert: Bool = false
  // 波动幅度（`watchMoveThreshold`）2026-09-28 收掉（收设置项 E 组）：按每只自己最近一天的
  // 1 分钟波动自动定（`WatchMove.autoThreshold`），两端同一个公式。
  /// 设置 › 通知「品种上新与停牌下架」，出厂关，随账号同步。服务端 `listing_watch.rs` 读它推送；
  /// 没有 APNs 密钥时 app 在前台 / 每次同步去拉 `/v1/alerts/listing-notices` 当本地通知出（`ListingNotices`）。
  var notifyListingChanges: Bool = false
  /// 设置 › 通用「按我的习惯自动调整」，出厂开，随账号同步。关掉：学到的全清、不再记。
  /// 规则与日志都在 `Habits/`，这里只是开关。
  var habitLearning: Bool = true
  /// 按习惯学到的结论（`LearnedDefaults`：每只的开图周期、每类的价格轴、板块窗口、波动提醒灵敏度），
  /// 整份一个键随账号同步（≤ 16 KB）；行为日志只在本机，不上传。
  var learnedDefaults: LearnedDefaults = .empty

  // ---------------------------------------------------------------- 指标
  /// 主图叠加，按打开先后排。默认 `[.ma]`。
  var overlays: [IndicatorID] = IndicatorID.defaultOverlays
  /// 副图从上往下的顺序，默认 VOL/OI/MACD。
  var subs: [IndicatorID] = AICoinBehavior.subpanels
  /// 每个指标的参数。没记的取 `IndicatorID.defaultParams`。
  var params: [IndicatorID: [Int]] = IndicatorID.factoryParams
  /// 拖分隔线拖出来的副图高度倍率，按面板身份记。这是**唯一**的副图高度来源。
  ///
  /// 原来还有一份档位式的 `subHeights`（A6.4，小 / 中 / 大），改成拖分隔线之后就没有
  /// 写端了；2026-09-24 连字段、`SubPaneHeight` 和同步白名单两端一起删了（线上 66 份
  /// 设置里它全是空的）。老存档里那个键解码时认不出来，直接忽略。
  ///
  /// 横竖屏共用这一份，是有意的：这里存的是**权重**（占内容高度的比例），不是绝对
  /// 点数——`Layout` 拿它和主图权重一起分配当前视口，所以同一个值在两种朝向下给出
  /// 的是同一个比例。拆成横竖两份等于「设置跟着页面走」，恰恰是要避免的那一类。
  var subHeightOverrides: [IndicatorID: Double] = [:]
  // `indicatorLayouts`（2026-09-27~10-02 按周期分组记忆留下的那一格）2026-10-10 退役：10-03 之前的老客户端
  // 已经没了，读老档的迁移一起删掉。老存档里的这个键读时忽略（布局就是顶层那六项），服务端退役。

  // ---------------------------------------------------------------- 网络
  /// 行情线路：网关（默认，2026-10-08 起）/ 直连。选了哪条就走哪条，代码不做自动切换。
  /// 出厂从直连改成网关的理由见 `MarketRoutePolicyStore.factoryDefault`；老档的迁移在 `PrefsCodec.migrate`（版本 5）。
  /// 存在这里而不是单独一个键，是为了跟着设置一起走（2026-09-19 起是本机字段，不随账号同步）；
  /// `PrefsStore` 再把它镜像给 `MarketRoutePolicyStore`。
  var routePolicy: MarketRoutePolicy = MarketRoutePolicyStore.factoryDefault

  // ------------------------------------------------ 他在各页上摆出来的样子
  //
  // 这一节全是「用户用手改出来的习惯」，不属于四个设置面板，但和皮肤、副图高度
  // 完全是同一等级的东西。以前它们要么是纯 `@State`（切一次页签就没了），要么是
  // 裸 `@AppStorage`（跟着这台机器走：换个账号还在，换台设备又不在）。
  //
  // 判据只有一条：**这是他改出来的习惯，还是这个对象自己的属性。** 自选表按什么
  // 排、板块看今日还是 5 日、上次拿的哪把画线工具、回放几倍速，全是前者，所以
  // 一律搬进这里跟着人走——每一项都同时进了 `PersonalSyncCodec.fields`，
  // 一个都不在 `keepDeviceFields` 里（它们都不是「这台手机的属性」）。

  // `favoritesSort` / `favoritesAscending` / `favoritesAmount`（自选排序口径、方向、涨跌额）与
  // `favoritesSparkline`（行尾迷你走势）2026-09-28 收掉（收设置项 G）：自选表永远按自选顺序、
  // 涨跌固定写涨跌幅、行尾不画走势线。老存档里的键读时忽略，服务端退役。
  /// 自选页停在哪个分类。空串 = 还没挑过，按第一个分类开。
  ///
  /// 2026-09-19 从 `SymbolPrefs.selectedGroupID` 搬过来的。它本来和自选名单、分组名单
  /// 挤在一个对象里，但那个对象存的是**他收藏了哪些品种**（内容），这一条存的是
  /// **他把自选页摆成什么样**（习惯），和上面几行是同一类东西。搬过来之后它才跟着人走：
  /// 换台设备登同一个账号，自选页还停在同一个分类上。
  ///
  /// 存回来的分类可能已经不在了（那一格被删掉），由 `SymbolPrefs.group(_:)` 接住
  /// 退回第一个分类——和搬家之前 `SymbolPrefs` 自己那条兜底是同一个行为。
  var favoritesGroup: String = ""

  /// 板块页停在哪个市场（加密 / 美股）。
  var sectorMarket: SectorMarket = .crypto
  /// 板块页上**他点的那一档**窗口：今日 / 5 日。
  ///
  /// ⚠️ 只存他点的那一档。真正画出来的那一档是派生值——5 日数据没齐时页面就地退回
  /// 今日，而那一刻「今日 / 5 日」的切换条整条都不画。把那个降级结果回写到这儿，
  /// 等于在一个当时根本没有入口的页面上永久改掉了他的选择，数据齐了也回不来。
  var sectorWindow: SectorWindow = .today
  // `sectorSort`（板块品种列表按涨跌幅 / 成交额排）2026-09-28 收掉（收设置项 G）：
  // 一律按当前窗口的涨跌幅降序，和上一层板块列表同一个口径。

  /// 最近用过的那把画线工具（`Drawing.Kind` 的 rawValue），用来在工具面板上预选高亮。
  ///
  /// 它**不是**「此刻正举着笔」：换品种要把待画状态清掉（`ChartView+Drawing.setDrawings`
  /// 里那行 `d.tool = nil` 保持不动），冷启动更不许一进来就处于待画状态。
  /// 这儿记的只是「上次用的是哪把」这个习惯。
  var lastDrawTool: String = ""

  /// 每把画线工具用了几次（键是面板那一格的 `Drawing.Kind` rawValue，变体记在族首名下）。
  ///
  /// 画线条只露几把常用的（竖屏 4 把、横屏画线台 5 把），就照它排（`DrawingToolRank`）；
  /// 其余的都在「绘图」面板里。每选一次 +1，总数过 256 整体减半，量的是「最近常用」。
  /// 随账号同步。它不是设置：用户看不到、也不用管。
  var drawToolUsage: [String: Int] = [:]

  /// 「分析」面板四节（画线 · 主力订单流 · 指标 · 对比）各用了几次（键是 `AnalysisSection` rawValue）。
  ///
  /// 面板照它排节（`AnalysisSectionRank`）：每在某节里做一次实事 +1，总数过 256 整体减半，量的是「最近常用」；
  /// 没用过时按出厂顺序。和 `drawToolUsage` 一样是自动统计、不是设置——用户看不到、也不用管；
  /// 它定的是面板摆什么，同一个人换台手机还该是那个顺序，所以随账号同步。
  var analysisUsage: [String: Int] = [:]

  /// 横屏画线台里主图指标（均线、布林……）画不画——顶行最右那颗「指标」胶囊管它，出厂开。
  ///
  /// 开着时价格轴仍只按 K 线定（`ChartSession.compose` 关掉 `overlaysAffectPriceRange`），
  /// 所以开不开都不改量程；关掉就是一整屏原始 K 线。只管画线台，竖屏和横屏看行情照常画。
  var drawingOverlaysShown: Bool = true

  /// 竖屏（和横屏看行情）把画线整片藏起来——画线面板「画线」一节的「隐藏画线」开关，出厂关。
  ///
  /// 2026-10-06 用户：「我既想保留警报又不想看画线」。藏起来时画线、选中态、画线上的铃都不画、
  /// 也点不中；提醒照常盯盘，它的信号线（`ChartAlertSignal`）照常画。横屏画线台永远显示画线、
  /// 不改这个字段（`ChartInput.forcesDrawings`）。跟账号同步。全局那颗旧的 `showDrawings`
  /// 已经退役（服务端 `RETIRED_SETTINGS_FIELDS` 里），所以换了个名字。
  var drawingsHidden: Bool = false

  /// 自选行上那条 24 小时迷你走势线（价格与涨跌药丸之间），出厂开。设置 › 通用「自选走势线」。
  ///
  /// 2026-10-08 用户要回来的：只此一颗全局开关，不分分类、不分品种，跟账号同步。
  /// 2026-09-28 收掉的那颗 `favoritesSparkline`（行尾、出厂关）已在服务端退役名单里，
  /// 老客户端写的是另一种语义，所以换了个名字。
  var favoritesTrend: Bool = true

  // `replaySpeed`（回放倍速）2026-09-28 收掉（收设置项）：每一趟回放按根数自己挑
  // （`ReplayPace`，整趟 20–40 秒），回放条上那颗倍速键只改这一趟，不再存。
  /// 「找相似」的搜索范围：`history`（市场历史）/ `private`（我的记录）。
  var reviewSearchScope: String = "history"
  /// 复盘本「观点 / 交易」停在哪一面：`views` / `trades`（2026-10-10，跟账号同步）。
  ///
  /// 只记他**手点**的那一面（`TradeReviewFeature.chosenSegment`）：「观点」空着、「交易」有回合时
  /// 复盘本会自动翻到交易那面（`TradeReviewFeature.preferredSegment`），那一下只改这次显示、不回写。
  var reviewSegment: String = "views"
  /// 复盘本筛选停在哪一档：`all`（全部）/ `todo`（待判定）/ `decided`（已判定）（2026-10-10，跟账号同步）。
  /// 出厂「待判定」：打开复盘本九成是奔着「有什么该我处理的」去的（§2G2）。
  var reviewBookFilter: String = "todo"

  // ↑ new-sync-field:prefs-field 在这一行上面插新字段（Tools/new-sync-field.py 认这一行，别删）

  init() {}

  /// 全新安装就是这一份（A6.4「首次安装即如此」）。
  static let defaults = Prefs()

  /// 最多同时开三个副图。再多主图就被挤没了——「主图和副图要同时落在一屏里」是
  /// 这张图的底线，所以这里卡死在三个，第四个进来就把最早开的那个换下去。
  ///
  /// **成交量不占名额**（2026-09-29，与网页版对齐）：网页把成交量叠在主图底部，
  /// 口径是「成交量 + 最多三个别的副图」，推到云端的 `subs` 可以是四项。手机原来把
  /// 成交量也算进三个，读档 `prefix(3)` 会把网页开的最后一个副图丢掉。所以这里的三个
  /// 只数**非成交量**的副图（`countsTowardSubLimit`），成交量开关永远不挤别人。
  static let maxSubs = 3

  /// 这个副图占不占 `maxSubs` 的名额。只有成交量不占。
  static func countsTowardSubLimit(_ id: IndicatorID) -> Bool { id != .vol }

  /// 按上面的口径裁一串副图：成交量原位保留，别的按原顺序只留前 `maxSubs` 个。
  /// 读档（`PrefsCodec`）与改（`toggle`）用的是同一把尺子。
  static func cappedSubs(_ subs: [IndicatorID]) -> [IndicatorID] {
    var counted = 0
    return subs.filter { id in
      guard countsTowardSubLimit(id) else { return true }
      counted += 1
      return counted <= maxSubs
    }
  }
  /// 常用行最多几档（§10.6）。2026-09-21 从 10 收到 **6**：那条「排不下就横向滚动、
  /// 右边淡出去、滑一下就到」的退路已经删掉了（见 `IntervalBar`）——用户在 16 Pro 上
  /// 看到的是周期条只剩「1m 5m 15m 30」、1h/4h/1d 全藏在屏幕外面，钉住的东西看不见
  /// 等于没钉。现在这一行只保证「≤6 档 + 行尾固定槽位 + 更多 + 图表」在 iPhone SE
  /// 到 Pro Max 上都一行放得下、一个字不截，六档就是实测排得下的上限。
  static let maxQuick = 6

  /// 「找相似」认得的两档范围。
  static let searchScopes: Set<String> = ["history", "private"]
  /// 复盘本「观点 / 交易」认得的两面。和服务端 `sync_validation.rs` 的 `reviewSegment` 逐字相同。
  static let reviewSegments: Set<String> = ["views", "trades"]
  /// 复盘本筛选认得的三档。和服务端 `sync_validation.rs` 的 `reviewBookFilter` 逐字相同。
  static let reviewBookFilters: Set<String> = ["all", "todo", "decided"]

  /// 根间距存进档案之前夹一道。
  ///
  /// `ViewMath.reset` 里本来就夹了一次，但那是「画的时候不许越界」；这一道管的是
  /// 「不许把离谱的数写进存档」——真写进去了，下次冷启动第一帧就得靠画图那一道兜，
  /// 而存档里躺着一个永远兑现不了的数，看日志的人只会更糊涂。
  static func clampSpacing(_ value: Double) -> Double {
    guard value.isFinite else { return AICoinBehavior.initialSpacing }
    return min(AICoinBehavior.maximumSpacing, max(AICoinBehavior.minimumSpacing, value))
  }

  // ---------------------------------------------------------------- 取用

  // 造型只剩 AICoin 一套（见 `CandleStyle`），这儿不存风格 id；旧存档里的 `styleID` 解码时直接忽略。

  /// 喂给图表的那一包开关。**主界面只调这一句**：各处自己拼容易漏项，
  /// 漏了的那一项会静悄悄退回引擎默认值，而不是报错，很难发现。
  var chartOptions: ChartOptions {
    var o = ChartOptions()
    o.kind = candleKind
    // 网格：「经典」照 AICoin 手机端，默认不画；青苔 / 陶土画一层自己皮肤色的淡网格
    // （`Palette.canvas` 里网格取皮肤的 `line`，在各自的底上对比度约 1.1–1.2）。
    o.grid = skin == .classic ? .off : .on
    o.body = .solid                  // 阳线一律实心（AICoin 画法）
    o.lastLine = true                // 最新价横线 + 右轴胶囊常在
    // 画线显隐：2026-09-24 删掉的全局 `showDrawings` 和按品种的「全部隐藏」打架；
    // 2026-10-06 起「隐藏画线」（`drawingsHidden`）回来，但只管看行情——一进画线台
    // （或正在预览）`ChartSession` 一律强制画出来，所以不会再出现「画线栏上怎么点都看不见线」。
    o.drawings = !drawingsHidden
    // 本根收线倒计时不画（2026-10-03：用户用不到）。图表引擎的这项能力还在，
    // 要恢复只改这一行并让心跳喂 `nowMs`，原样见 tag `before-remove-candle-countdown-2026-10-03`。
    o.countdown = false
    o.sinceChange = true             // 十字线打开时顺带报「选中那根到最新价」的涨跌幅
    o.anchor = .right                // 回到最新时最新一根靠右
    o.bias = .center                 // 蜡烛在主图区里上下居中
    // K 线数据：长按出十字线时开高低收写在头部（「顶部」那档），不在图里再盖一块框。
    o.dataDisplay = .top
    o.crossPrice = .selected         // 十字线读的是手指选中的价位
    // 主 / 副轴翻转：双击手势直接生效，再双击翻回；翻转状态仍跟着人走（`mainInverted` / `subInverted`）。
    o.allowMainInversion = true
    o.allowSubInversion = true
    o.adaptiveIndicators = true      // 主图图例折行时往下让位，不压蜡烛
    // 竖屏主图占比（`portraitHeight`）不存、不同步，用 `ChartOptions` 的出厂值（2026-10-10 退役）。
    // 副图高度（`subHeightOverrides`）**不**走这里：它改的是分区怎么切，归 `Layout`，
    // 由主界面另行接线。放进来会变成两条路各说各话。
    return o
  }

  /// 这个指标现在用的参数。
  func params(for id: IndicatorID) -> [Int] {
    IndicatorParamRule.sanitize(params[id] ?? id.defaultParams, for: id)
  }

  /// 这个副图实际要多高（倍率，1.0 = 风格表原值）。
  ///
  /// 拖拽只在用户**真的拖过**的时候才算数；没拖过的一律走同一个出厂倍率
  /// `defaultSubScale`，也就是三个副图**等高**。
  ///
  /// 以前这里给成交量满格、其余只给 0.62，理由是「成交量靠柱子的高度差读，压扁了
  /// 就剩一排小墩子」。真机量下来这条理由撑不住：4h 一屏里成交量拿到 105.7pt，
  /// OI 和 MACD 各只有 65.5pt——成交量比它们高出 61%，一排副图看着像没对齐的三段楼梯，
  /// 而矮下去的那两格恰恰是 MACD 这种要看线离零轴多远的图。AICoin 同屏是 89 / 90pt
  /// 的等高两格，读起来齐整得多。
  ///
  /// 等高不是把主图砍掉换来的：三格各 0.75 倍时主图仍是 316.6pt（原来 317.2pt），
  /// 副图各 79.1pt，主图只让出半个点。省高度要省在别处，不是让成交量一家独大。
  func scale(for id: IndicatorID) -> Double {
    if let manual = subHeightOverrides[id] { return manual }
    return Prefs.defaultSubScale
  }

  /// 副图的出厂高度倍率，三个副图共用一个数（等高）。
  ///
  /// 0.75 是照「主图不动」反推的：主图权重 3、三个副图各 w，
  /// 想让每格 ≈79pt 而主图留在 ≈317pt，解出来正好 w = 0.75。
  static let defaultSubScale: Double = 0.75

  /// 主力订单流改过的门槛 / 步长最多记多少只。服务端 `sync_validation.rs` 同一个数。
  static let maxOrderFlowOverrides = 200

  /// 记下一只 base 改过的门槛 / 步长；越界的项丢掉，一项不剩就等于恢复默认（从表里删掉）。
  mutating func setOrderFlowOverride(_ value: OrderFlowOverride?, for base: String) {
    guard OrderFlowBase.isValid(base) else { return }
    if let value = value?.normalized {
      guard orderFlowOverrides[base] != nil || orderFlowOverrides.count < Prefs.maxOrderFlowOverrides else { return }
      orderFlowOverrides[base] = value
    } else {
      orderFlowOverrides[base] = nil
    }
  }

  /// 某个指标是不是开着的。
  func isOn(_ id: IndicatorID) -> Bool {
    if id == .orderFlow { return orderFlow }  // 主力订单流的开关是自己一个字段，不进 overlays
    return id.placement == .main ? overlays.contains(id) : subs.contains(id)
  }

  /// 某个自动分析层是不是开着的。
  func isAutoLayerOn(_ layer: AutoLayer) -> Bool { autoLayers.contains(layer) }

  /// 当前这一套配色 + 深浅下的原始令牌。全 app 只有这一处把两根轴合起来。
  func seed(systemDark: Bool) -> PaletteSeed { theme.seed(skin: skin, systemDark: systemDark) }

  /// 当前深浅下的图表用色，涨跌已按 `redUp` 对调（A6.7 靠这一个入口，不会漏）。
  func chartColors(dark: Bool) -> ChartColors { Palette.chart(seed(systemDark: dark), redUp: redUp) }

  // ---------------------------------------------------------------- 改

  /// 开 / 关一个指标。
  ///
  /// 副图满三个时**不再拒绝**：拒绝等于让用户自己回去找一个关掉，白跑一趟。
  /// 改成把最早打开的那个换下去（`subs` 本来就是按打开先后排的，队首即最早），
  /// 再返回一句「换下了谁」——调用方拿它弹一条带「撤销」的 toast，后悔一下就能还原。
  ///
  /// 成交量不占名额（见 `maxSubs`）：开成交量永远不换下别人，满了换下的也只在
  /// 非成交量的副图里挑最早的那个，成交量本身不会被换下。
  /// 开 / 关一个自动分析层。开的接在末尾，关的从列表里拿掉。
  mutating func toggleAutoLayer(_ layer: AutoLayer) {
    if let at = autoLayers.firstIndex(of: layer) { autoLayers.remove(at: at) } else { autoLayers.append(layer) }
  }

  @discardableResult
  mutating func toggle(_ id: IndicatorID) -> String? {
    if id == .orderFlow { orderFlow.toggle(); return nil }
    switch id.placement {
    case .main:
      if let at = overlays.firstIndex(of: id) { overlays.remove(at: at) } else { overlays.append(id) }
      return nil
    case .sub:
      if let at = subs.firstIndex(of: id) { subs.remove(at: at); return nil }
      var evicted: IndicatorID?
      if Prefs.countsTowardSubLimit(id) {
        while subs.filter(Prefs.countsTowardSubLimit).count >= Prefs.maxSubs,
              let at = subs.firstIndex(where: Prefs.countsTowardSubLimit) {
          evicted = subs.remove(at: at)
        }
      }
      subs.append(id)
      guard let evicted else { return nil }
      return "副图最多三个 · 已换下 \(evicted.name)"
    }
  }

  /// 改一个参数。非法值按 `IndicatorParamRule` 夹回来，不会写进存档。
  mutating func setParam(_ id: IndicatorID, at index: Int, to value: Int) {
    var v = params(for: id)
    guard v.indices.contains(index) else { return }
    v[index] = IndicatorParamRule.clamp(value)
    params[id] = v
  }

  /// 副图上下排序（§10.6 的拖柄）。
  mutating func moveSub(from source: Int, to destination: Int) {
    guard subs.indices.contains(source) else { return }
    let clamped = min(max(0, destination), subs.count - 1)
    guard clamped != source else { return }
    let id = subs.remove(at: source)
    subs.insert(id, at: clamped)
  }

  /// 长按常用行 / 更多面板里的增删（§10.6），最多 `Prefs.maxQuick`（六）个，至少留 1 个。
  ///
  /// 钉满之后「更多」网格里点没钉住的图钉走的是 `replaceQuick`（先挑一档换掉），
  /// 不经过这儿，所以「最多 6 档」那句话正常走不到；它守的是别的入口。
  @discardableResult
  mutating func toggleQuick(_ iv: Interval) -> String? {
    if let at = quickIntervals.firstIndex(of: iv) {
      guard quickIntervals.count > 1 else { return "常用行至少留一档" }
      quickIntervals.remove(at: at)
      return nil
    }
    guard quickIntervals.count < Prefs.maxQuick else { return "常用行最多 \(Prefs.maxQuick) 档" }
    quickIntervals.append(iv)
    quickIntervals.sort { a, b in
      (Interval.allCases.firstIndex(of: a) ?? 0) < (Interval.allCases.firstIndex(of: b) ?? 0)
    }
    return nil
  }

  /// 钉满六档时「换一档」：把钉住的 `old` 换成没钉住的 `new`，一步到位（2026-09-23）。
  ///
  /// 原来钉满之后其余图钉一律灰掉，想换一档得先拔一颗再钉一颗，中间还得记着自己要换哪个。
  /// 现在点没钉住的图钉就进「挑一档换掉」，再点哪一格换哪一格（见 `IntervalGridPopover`）。
  /// 档数不变，顺序照旧按 `Interval.allCases` 排。`old` 不在钉位里或 `new` 已经钉着时不做事。
  mutating func replaceQuick(old: Interval, new: Interval) {
    guard old != new, let at = quickIntervals.firstIndex(of: old),
          !quickIntervals.contains(new) else { return }
    quickIntervals[at] = new
    quickIntervals.sort { a, b in
      (Interval.allCases.firstIndex(of: a) ?? 0) < (Interval.allCases.firstIndex(of: b) ?? 0)
    }
  }
}
