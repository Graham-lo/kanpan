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
  // Keep the manual choice intact; automatic brightness selection is runtime-only.
  var ambientTheme = false
  /// 涨跌对调（A6.7）。国内看盘习惯是红涨绿跌，出厂就给红涨；
  /// 老用户存档里存过什么就还是什么，这儿只改「从没设过」的那一档默认值。
  var redUp: Bool = true

  // ---------------------------------------------------------------- 图
  /// 对比 K 线的品种集合（完整品种 key，最多三只，见 `Kanpan/Kanpan/Compare/`）。
  /// 有值时主图换成百分比坐标；集合跟着人走，换主品种不清。
  var compareSymbols: [String] = []
  /// 价格轴 常规 / 对数 / 百分比（A6.8）。
  var priceMode: PriceMode = .log
  /// 十字线磁吸（§7 长按那一行）：长按出来的十字线吸不吸到最近那根 K 线的价位上。
  /// 设置页里写「十字线磁吸」，出厂**关**。
  ///
  /// 注释以前写的是「原型 `chart.magnet = true`」，和下面这行 `false` 对不上——
  /// 原型那个值早就按实机手感翻掉了，注释没跟着改。
  ///
  /// 另外还有一个 `DrawingPreferences.magnet`（画线栏上的「吸附」，出厂**开**），
  /// 两者**不合并**：一个管看盘时读价，一个管画线时端点对齐，出厂档位本来就该不一样。
  var magnet: Bool = false
  /// 本根倒计时，默认关；前台时钟独立更新。
  var depth: Bool = false
  /// 主图指标「主力订单流」：簿里过门槛的大单画到 K 线上。默认关。
  var orderFlow: Bool = false
  /// 主力订单流：用户改过门槛 / 步长的那几只（键是去掉缩放前缀的 base，`OrderFlowFacts.overrideKey`）。
  /// 没改过的 base 不在表里，一律走默认表——默认表以后调了，没改过的人跟着变。随账号同步（整张表一个字段）。
  var orderFlowOverrides: [String: OrderFlowOverride] = [:]
  /// 主力订单流的六个显示开关（跟人走、全品种共用，只管画不画、不影响跟踪）。
  /// 拆成六个字段而不是一个对象，是为了两台设备各关一项时同步不互相覆盖。合起来读写走 `orderFlowDisplay`。
  var orderFlowSpot = true
  var orderFlowContract = true
  var orderFlowFilledBid = true
  var orderFlowFilledAsk = true
  var orderFlowCancelledBid = true
  var orderFlowCancelledAsk = true
  var countdown: Bool = false
  /// 蜡烛 / 平均K线（Heikin-Ashi）。默认蜡烛。
  var candleKind: CandleKind = .candle
  /// 共用网格，默认关闭；旧存档的跟随风格枚举按共用默认解析。
  var gridChoice: GridChoice = .off
  /// 阳线实体：实心 / 空心。默认实心，也就是 AICoin 的画法。
  var bodyChoice: BodyChoice = .solid
  /// 最新价横线 + 右轴胶囊。默认开。
  var lastLine: Bool = true
  /// 十字线打开时，多报一段「选中那根到最新价」的涨跌幅。默认关。
  var sinceChange: Bool = false
  /// 复位到最新时，最新一根落在横向哪儿。默认靠右（现状）。
  var viewAnchor: ViewAnchor = .right
  /// 蜡烛在主图区里整体偏上 / 居中 / 偏下。总留白量不变，只改上下分配，
  /// 所以蜡烛大小不变，只是位置挪。默认居中（现状）。
  var priceBias: PriceBias = .center
  var dataDisplay: CandleDataDisplay = .inside
  var crossPrice: CrossPriceMode = .selected
  /// 默认关，理由见 `ChartOptions.allowMainInversion`。
  var allowMainInversion = false
  var allowSubInversion = false
  /// 用户缩放到的根间距（pt）。
  ///
  /// 「我要一屏看多少根」是**人的习惯**，不是某个品种的属性：以前它只活在图自己身上，
  /// 换品种一律回到出厂的 4pt，用户捏小了去自选点下一个品种，K 线又变回一屏五十根。
  /// 所以把它挪到设置里，跟皮肤、副图高度同一等级——所有品种、所有周期共用一份，
  /// 跨 app 重启也在。没存过就是出厂的 `initialSpacing`。
  ///
  /// ⚠️ **这一份是「盘上那一份」，写入是节流的**（`PrefsStore.noteBarSpacing`），
  /// 它只管下次冷启动。本程内要「用户此刻捏到多宽」请读 `PrefsStore.liveBarSpacing`，
  /// 那一份手一动就变——用户捏完立刻换周期换品种，靠的是它。
  var barSpacing: Double = AICoinBehavior.initialSpacing
  /// 主图上下翻转（双击价格轴）。和根间距同理：是「我习惯怎么看」，不是这个品种的属性。
  /// 要 `allowMainInversion` 开着才生效——开关关掉时不认这一份，免得翻过去再也翻不回来。
  var mainInverted = false
  /// 哪几个副图被上下翻转（双击副图那一侧）。同上，要 `allowSubInversion` 开着才生效。
  var subInverted: Set<IndicatorID> = []
  var adaptiveIndicators = false
  /// 主图在竖屏里占多少（0…1，越大主图越高）。**只有读端，没有写端。**
  ///
  /// 读端是活的：`ChartRenderer` 拿它算主图权重（`ChartContentLayout.mainWeight`）。
  /// 但全仓库没有任何地方改过它——没有设置项、没有手势、没有迁移，它永远是 0.5，
  /// 落盘和跨设备同步的都是同一个常数。
  ///
  /// **这不是漏了持久化，也不该靠新增一个旋钮来「修」。** 主副图比例该由我们定一个
  /// 好用的值，不是摆出来让人调（`kanpan-sector-page-no-basis-picker`：算法口径、
  /// 比例参数这类东西不交给用户选）。字段和 codec 键留着是因为老存档里带着它，
  /// 删了解码会踩空、版本号又不许动；留这段注释是免得下一个人以为哪儿漏了写入。
  var portraitHeight = 0.5
  var indicatorColors: [IndicatorID: [Int: Hex]] = [:]
  var hiddenOutputs: [IndicatorID: Set<Int>] = [:]
  var rsiUpper = 70.0
  var rsiLower = 30.0
  /// 盯盘时不锁屏（§10.4，默认开）。
  var keepAwake: Bool = true
  // 这儿原来还有 `launchSnapshot`（§4.3 的「启动快照」开关）。2026-09-24 审查 U13 把它从
  // 设置页撤了，字段随后也删掉：界面上改不了的开关，谁要是以前关过，就永远关着、
  // 再也打不开——冷启动一直是空图。启动快照现在无条件开着（`MainScreen.boot`）。
  /// 时区（A6.9）。Core 的 `TZChoice` 是原型的口径：本地 / UTC / 交易所（界面上写「UTC+8」）。
  var timeZone: TZChoice = .local
  var changeBasis: ChangeBasis = .rolling24h
  /// 所有价格提醒共用，随账号同步；复盘到期通知不使用此项。
  var alertSound: AlertSound = .default
  /// 自选五分钟波动提醒（P3.1），出厂关。判定只有一种，见 `WatchMove`。
  var watchMoveAlert: Bool = false
  /// 波动幅度（百分数），出厂 1.5，手动输入，夹在 `WatchMove.thresholdRange` 里。
  var watchMoveThreshold: Double = WatchMove.defaultThreshold

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

  // ---------------------------------------------------------------- 网络
  /// 行情线路：直连（默认）/ 网关。选了哪条就走哪条，代码不做自动切换。
  /// 存在这里而不是单独一个键，是为了跟着设置一起走：登录了随账号同步，
  /// 没登录就落在本机的访客档案里；`PrefsStore` 再把它镜像给 `MarketRoutePolicyStore`。
  var routePolicy: MarketRoutePolicy = .direct

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

  /// 自选表的排序口径：`custom`（自选顺序）/ `name` / `price` / `change` / `volume`。
  var favoritesSort: String = "custom"
  /// 排序方向。`custom` 那一档用不上它，但仍然记着——换回某个口径时接着上次的方向。
  var favoritesAscending: Bool = false
  /// 涨跌那一列看涨跌额还是涨跌幅。
  var favoritesAmount: Bool = false
  /// 行尾那条迷你走势线。默认不画，想看的人在「…」里自己打开。
  var favoritesSparkline: Bool = false
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
  /// 板块里那张品种列表的排序口径（`SectorSymbolSort` 的 rawValue）。
  /// 存字符串不存枚举：那个枚举住在 app target 里，这一层（`KanpanSettings`）看不见它。
  var sectorSort: String = "change"

  /// 最近用过的那把画线工具（`Drawing.Kind` 的 rawValue），用来在工具面板上预选高亮。
  ///
  /// 它**不是**「此刻正举着笔」：换品种要把待画状态清掉（`ChartView+Drawing.setDrawings`
  /// 里那行 `d.tool = nil` 保持不动），冷启动更不许一进来就处于待画状态。
  /// 这儿记的只是「上次用的是哪把」这个习惯。
  var lastDrawTool: String = ""

  /// 回放倍速。**是人的习惯，不是这条记录的属性**——调到 4× 退出去，再进另一条记录
  /// 也该还是 4×。游标位置按记录存（`ReviewReplayPosition.cursor`），那个不跟着人走。
  var replaySpeed: Int = 1
  /// 「找相似」的搜索范围：`history`（市场历史）/ `private`（我的记录）。
  var reviewSearchScope: String = "history"

  init() {}

  /// 全新安装就是这一份（A6.4「首次安装即如此」）。
  static let defaults = Prefs()

  /// 最多同时开三个副图。再多主图就被挤没了——「主图和副图要同时落在一屏里」是
  /// 这张图的底线，所以这里卡死在三个，第四个进来就把最早开的那个换下去。
  static let maxSubs = 3
  /// 常用行最多几档（§10.6）。2026-09-21 从 10 收到 **6**：那条「排不下就横向滚动、
  /// 右边淡出去、滑一下就到」的退路已经删掉了（见 `IntervalBar`）——用户在 16 Pro 上
  /// 看到的是周期条只剩「1m 5m 15m 30」、1h/4h/1d 全藏在屏幕外面，钉住的东西看不见
  /// 等于没钉。现在这一行只保证「≤6 档 + 行尾固定槽位 + 更多 + 图表」在 iPhone SE
  /// 到 Pro Max 上都一行放得下、一个字不截，六档就是实测排得下的上限。
  static let maxQuick = 6

  /// 自选表认得的排序口径。存档里写着别的（降级回旧版本、手改存档）就退回 `custom`。
  ///
  /// **这张表和服务端 `sync_validation.rs` 的 `favoritesSort` 白名单是同一张。**
  /// 这边多一档、那边没加，含这个值的 `settings` 操作会被整条拒掉、把同步队列堵住
  /// （2026-09-19 那次十九个字段的教训）。`alert` 是 2026-09-20 随提醒功能加的
  /// 「离提醒线最近」。
  static let favoriteSorts: Set<String> = ["custom", "name", "price", "change", "volume", "alert"]

  /// 「找相似」认得的两档范围。
  static let searchScopes: Set<String> = ["history", "private"]

  /// 回放倍速只有 1 / 2 / 4 三档（`ReviewReplayControls` 上那颗按钮就是这么转的）。
  static func clampSpeed(_ value: Int) -> Int { [1, 2, 4].contains(value) ? value : 1 }

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
    o.grid = gridChoice
    o.body = bodyChoice
    o.lastLine = lastLine
    // 画线显隐只按品种管（画线页「更多」里的「全部隐藏」）。原来还有一个全局的
    // `showDrawings`，和那颗按品种的开关打架——关了全局那颗，画线栏上怎么点都看不见线；
    // 2026-09-23 撤了入口，2026-09-24 连字段带同步白名单两端一起删了。
    o.drawings = true
    o.countdown = countdown          // 「本根倒计时」早就有了，这里接的是同一个字段
    o.sinceChange = sinceChange
    o.anchor = viewAnchor
    o.bias = priceBias
    o.dataDisplay = dataDisplay
    o.crossPrice = crossPrice
    o.allowMainInversion = allowMainInversion
    o.allowSubInversion = allowSubInversion
    o.adaptiveIndicators = adaptiveIndicators
    o.portraitHeight = portraitHeight
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

  /// 主力订单流的显示开关（六个字段合起来）。
  var orderFlowDisplay: OrderFlowDisplay {
    get {
      OrderFlowDisplay(spot: orderFlowSpot, contract: orderFlowContract, filledBid: orderFlowFilledBid,
                       filledAsk: orderFlowFilledAsk, cancelledBid: orderFlowCancelledBid,
                       cancelledAsk: orderFlowCancelledAsk)
    }
    set {
      orderFlowSpot = newValue.spot; orderFlowContract = newValue.contract
      orderFlowFilledBid = newValue.filledBid; orderFlowFilledAsk = newValue.filledAsk
      orderFlowCancelledBid = newValue.cancelledBid; orderFlowCancelledAsk = newValue.cancelledAsk
    }
  }

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
      while subs.count >= Prefs.maxSubs, !subs.isEmpty { evicted = subs.removeFirst() }
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
