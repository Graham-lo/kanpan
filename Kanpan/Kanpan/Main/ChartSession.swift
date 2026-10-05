import Foundation
import KanpanChart
import KanpanCore
import KanpanData
import KanpanNetwork
import Observation
import SwiftUI

// MARK: - 为什么有这一层（审查 21）
//
// 以前行情页的「行情 → 图」整条线都在 `MainScreen.body` 里：`chartState`、顶栏那口价
// （`rollingTicker` / `readoutPrice`）、十字线读数的序列、对比的接线键、以及一秒一跳的
// 倒计时 `nowMs`，全是那只根视图的计算属性或 `@State`。SwiftUI 的观察依赖记在**求值它的
// 那个 body** 上，于是每来一笔推送（K 线、逐笔成交、24h 统计、每秒心跳），整张根视图——
// 标签栏、面板、覆盖层、三十多个观察者——都跟着重求值一遍。静置看一分钟 BTC 1h，
// `MainScreen` 被求值 316 次（`LiveTickBodyCountUITests`，约 5.3 次/秒）。
//
// 现在这一条线收进 `ChartSession`：它持有行情（`MarketModel`）、报价簿（`QuoteBook`）、
// 对比（`CompareModel`）和十字线读数，**逐笔的读取只发生在真正要画它的那几块小视图里**
// （`MainChartView` 揉 `ChartState`、`MainHeaderView` 取那口价、读数视图取序列）。
// `MainScreen` 只剩布局和接线：它读的都是「换品种 / 换周期 / 改设置」才会变的东西。
//
// 同时它是品种、周期、线路、前后台这四件事落到行情这一侧的唯一入口：宿主里凡是要
// 「换一只」「换一档」「换线路」「进出后台」「停机」，都走这儿的方法，不再各处成对地
// 去戳 `market.xxx` 和 `quotes.xxx`（以前换品种前要不要先收十字线，六个调用点各写各的）。

/// 行情页那张图的会话：行情订阅、逐笔落图、四件事的入口。
///
/// 自己没有会被观察的字段（以前那个 `nowMs` 是收线倒计时的那一秒，2026-10-03 倒计时
/// 不再展示，连字段一起删了）。别的都是引用，读谁就在读的那块视图上记依赖——这正是要的效果。
@MainActor @Observable
final class ChartSession {
  @ObservationIgnored let market: MarketModel
  @ObservationIgnored let quotes: QuoteBook
  @ObservationIgnored let comparison: CompareModel
  /// 十字线读数。只有读数那一小块观察它（见 `CrosshairReadout.swift`）。
  @ObservationIgnored let readout: CrosshairReadout

  init(symbol: String) {
    market = MarketModel(symbol: symbol)
    quotes = QuoteBook()
    comparison = CompareModel()
    readout = CrosshairReadout()
  }

  // ---------------------------------------------------------------- 四件事的入口

  /// 换品种。换走之前先收十字线：它指的是上一只的那根 K 线。
  func show(symbol: String) {
    readout.clear()
    market.switchTo(symbol: symbol)
  }

  /// 换品种并同时换周期（按习惯开图时一步到位，不先按旧周期拉一遍再换）。
  func show(symbol: String, interval: Interval) {
    readout.clear()
    market.switchTo(symbol: symbol, interval: interval)
  }

  /// 换周期。十字线同理。
  func show(interval: Interval) {
    readout.clear()
    market.switchTo(interval: interval)
  }

  /// 换线路 / 换涨跌口径。行情那条（`MarketModel`）自己认 `RouteResolver.current`，
  /// 这儿交的是报价簿那条。
  func configure(route: RouteResolver) {
    quotes.configure(route: route)
  }

  /// 进出前台。顺序照旧：对比 → 行情 → 报价簿。
  func setForeground(_ on: Bool) {
    comparison.setForeground(on)
    if on { market.enterForeground() } else { market.enterBackground() }
    quotes.setForeground(on)
  }

  /// 根真的没了：对比、事件流、列表那条 socket 一起停，不走宽限。
  func stop() {
    comparison.stop()
    market.stop()
    quotes.shutdown()
  }

  // ---------------------------------------------------------------- 逐笔

  /// 一秒一跳：持仓量补取、报价簿的钟，再加宿主自己的那一拍（`onBeat`）。
  ///
  /// 图上不再画收线倒计时（2026-10-03，用户用不到；恢复见 tag
  /// `before-remove-candle-countdown-2026-10-03`），这一跳不再给图喂时间、也不再每秒叫醒图。
  /// `active` 为假（不在前台）就不跳。
  func heartbeat(active: Bool, onBeat: @escaping @MainActor () -> Void) async {
    guard active else { return }
    while !Task.isCancelled {
      market.refreshOIIfNeeded()
      quotes.tick()
      onBeat()
      do { try await Task.sleep(for: .seconds(1)) } catch { return }
    }
  }

  /// 图上那只的逐笔成交交给报价簿（替身线路上不交：它推的不是这家的成交）。
  func relay(trade: TradeQuote?) {
    guard !market.capabilities.isSubstitute, let trade, trade.symbol == market.symbol else { return }
    quotes.ingestTrade(trade)
  }

  /// 头部涨跌额与涨跌幅成对使用交易所 24 小时统计；自选口径仍走 presented。
  var rollingTicker: Ticker? {
    // 备用线路上先用它自己的一帧；它还没到（或这个品种它根本没有）就退回
    // 共享报价层里那口最后的价，顶栏灰显而不是退成骨架（§2B #54）。
    if market.capabilities.isSubstitute {
      let shared = chartQuote ?? quotes.seeded(market.symbol)
      guard var own = market.ticker else { return shared }
      // 替身的推送帧不带成交额，REST 那一帧补回来之前（冷启动、扫图的头一两百毫秒），
      // 用共享报价层同一条线路上的那份垫着（它按上游分区存盘、种子按上游收），不跨源借。
      if !own.quoteVolume.isFinite, !market.tickerStale, let shared, shared.symbol == own.symbol,
         shared.quoteVolume.isFinite {
        own.quoteVolume = shared.quoteVolume
      }
      return own
    }
    // MarketModel already receives the venue ticker frames as part of the
    // chart feed. Use that value immediately instead of waiting for the
    // separate list QuoteBook to open another socket.
    // 两路都还没到（从板块列表 / 搜索点进一只没看过的品种）：退到全市场 24h 那一份
    // 种子——几秒前的价，也比顶栏一排「—」强，真行情一到就被盖掉。
    return Self.headerTicker(book: chartQuote, feed: market.ticker, seed: quotes.seeded(market.symbol))
  }

  /// 顶栏用哪一份：报价簿那格优先（它和自选表同一口价）；但那格要是还只是逐笔成交拼出来的价
  /// （还没收到 24h 统计，涨跌额是空的、成交额是 NaN），不能拿它盖掉图那条流自己收到的
  /// 24h 统计帧——那样顶栏涨跌和「额」是一排「—」，统计明明就在手边（深度审查 G 线走查：
  /// 从搜索点进 1000PEPE，`market.ticker` 早有统计，报价簿那格的 REST 补统计被挡了二十来秒）。
  /// 这时用图那份统计，价取两边更新的那口（和 `QuoteBook.overlay` 同一个平移算法）。
  static func headerTicker(book: Ticker?, feed: Ticker?, seed: Ticker?) -> Ticker? {
    guard let book else { return feed ?? seed }
    guard book.priceChange == nil, let feed, feed.priceChange != nil,
          InstrumentID.canonical(feed.symbol) == InstrumentID.canonical(book.symbol) else { return book }
    return LatestQuote.accepts(book, after: feed) ? QuoteBook.overlay(book, on: feed) : feed
  }

  /// 报价簿里图上这只的那一格。先读被观察的镜像（`QuoteBook.chartQuote`）；
  /// 报价簿还没认到这只（换品种的那一拍，`setChartSymbol` 在观察者里才跟上）时
  /// 退回整表现取——镜像一跟上，读过它的视图自然会再求值一次。
  private var chartQuote: Ticker? {
    if let quote = quotes.chartQuote, quote.symbol == market.symbol { return quote }
    return quotes.raw[market.symbol]
  }

  /// 图上这只的涨跌幅：顶栏、横屏那行小字、分享成片、「创建提醒」页的品种卡都读这一个，
  /// 和顶栏的涨跌额成对，是交易所 24 小时口径（PROJECT.md「头部涨跌额与涨跌幅均为交易所
  /// 24 小时口径，自选表不变」）。
  ///
  /// 原来这儿还有一个 `displayedTicker`（按自选表的口径 `QuoteBook.presented` 改过百分比），
  /// 顶栏 2026-09-24 换成 24 小时口径时只换了顶栏自己，横屏小字、成片、提醒页还读它：
  /// 美股、贵金属这些按 UTC 0 点算的品种，竖屏写「+4.00%」、一转横屏就变成另一个数，
  /// 当天开盘价没取到时干脆是空的，发出去的图也对不上屏幕上那口。
  var changePercent: Double? {
    guard let value = rollingTicker?.changePercent, value.isFinite else { return nil }
    return value
  }

  /// Latest trade quote only; changing candle interval must never change its source.
  var readoutPrice: Double? {
    market.capabilities.isSubstitute ? (market.series?.close.last ?? rollingTicker?.last) : rollingTicker?.last
  }

  /// 给 UI 用例读的那串诊断值。**只在 DEBUG 构建里存在**（审查 C-02）：
  /// 正式包不该因为一个环境变量就把根数、视野、报价时刻挂到可访问树上。
  var quoteDiagnostics: String {
    #if DEBUG
    guard ProcessInfo.processInfo.environment["KANPAN_CHART_DIAGNOSTICS"] == "1" else { return "" }
    return "symbol=\(market.symbol);last=\(rollingTicker?.last ?? .nan);time=\(rollingTicker?.timeMs ?? 0);fresh=\(market.priceFresh ? 1 : 0)"
    #else
    return ""
    #endif
  }

  /// 读数那一小块要的输入。序列是**现取**的（`CrosshairContext.series`）：
  /// 只有十字线真在场时读数视图才去读它，平时一笔推送都叫不醒那几块。
  func crosshairContext(timeZone: TZOffset, enabled: Bool) -> CrosshairContext {
    CrosshairContext(
      seriesSource: { [market] in market.series }, symbol: market.symbol, interval: market.interval,
      decimals: market.info.priceDecimals, offsetMinutes: timeZone, enabled: enabled,
      hasVolume: market.capabilities.hasVolume)
  }

  /// 行情 + 设置 揉成一份 `ChartState`。**只在 `MainChartView` 的 body 里调**——
  /// 在哪儿调，逐笔推送就叫醒哪儿。
  ///
  /// `view` 这里给个占位：视野归图自己管，`ChartHost` 会按「换品种/换周期/换风格」
  /// 三种情形各自算一份真的（见 `ViewIntent`）。
  func liveState(_ input: ChartInput) -> ChartState? {
    guard let s = market.series, s.symbol == market.symbol, s.interval == market.interval, s.count > 0 else { return nil }
    return compose(input, series: s)
  }

  /// 复盘那几张图（交易回放、笔记重温、取景）只要一份「人当前的样式」当底，序列会整条换掉。
  /// 行情还没到（断网、刚启动、线路冷却）时也给一份空序列的底——否则交易回放会被
  /// 「等待行情加载」挡在门外，而它根本不看这只品种此刻的行情，取不到当时的 K 线自有它的话说。
  func styleState(_ input: ChartInput) -> ChartState {
    liveState(input) ?? compose(input, series: BarSeries(symbol: market.symbol, interval: market.interval, bars: []))
  }

  private func compose(_ input: ChartInput, series s: BarSeries) -> ChartState {
    let prefs = input.prefs
    // 上下翻转跟着人走，不跟着品种走：换品种时这份 state 是新造的，翻转要是不从设置里
    // 带出来，图就会自己翻回去。（「允许翻转」开关 2026-09-28 收掉，手势直接生效、再双击翻回。）
    var price = PriceTransform(mode: prefs.priceMode)
    price.inverted = prefs.mainInverted
    var result = ChartState(
      series: s,
      symbol: market.info,
      view: ViewWindow(to: Double(s.lastTime), span: Double(s.step) * 80),
      dark: input.seed.dark,
      redUp: prefs.redUp,
      price: price,
      overlays: input.overlays,
      subs: input.subs,
      params: prefs.params,
      timezone: prefs.timeZone,
      oi: market.oi,
      // 十字线不吸附（2026-10-03）：吸附时横线只认手指底下那根 K 线的收盘价，手指上下拖它纹丝不动、
      // 横着走一根跳一个收盘价，想把价格线放到某个价位根本放不过去。横线跟着手指的高度走。
      magnet: false,
      decimals: market.info.priceDecimals,
      options: prefs.chartOptions,
      subScale: input.subScale)
    // 走 OKX 兜底线路时持仓量根本取不到（`OISource` 只连币安）——让副图说实话，
    // 别一直挂「加载中」。
    result.external = market.external
    result.depth = input.drawingCanvasOnly || !prefs.depth ? nil : market.depth
    // 没有盘口的品种（美元指数：一个算出来的指数，没有簿）不挂订单流——开关开着也不转圈、不报错。
    result.orderFlow = market.capabilities.hasOrderFlow
      ? market.orderFlow.chartValue(symbol: market.symbol, drawingCanvasOnly: input.drawingCanvasOnly) : nil
    // 横屏画线台：主图指标可以开着（顶行「指标」胶囊管），但价格轴只按 K 线定——
    // 挂一条 MA256 不该把量程拉宽、把蜡烛压扁，画出来的线才落在真实的价格结构上。
    result.overlaysAffectPriceRange = !input.drawingCanvasOnly
    // 持仓量和衍生统计分开认：网关线路上的替身有持仓量历史（kanpan-api 代问 OKX），
    // 多空比、主动买卖、基差没有。
    result.oiSupported = market.capabilities.hasOpenInterestHistory
    result.externalSupported = market.capabilities.hasDerivativeMetrics
    result.subInverted = prefs.subInverted
    result.paletteSeed = input.seed
    result.indicatorColors = prefs.indicatorColors
    result.percentAxis = input.comparing
    if input.comparing { result.options.drawings = false }
    let shown = input.comparing ? input.compareKeys : []
    let names = input.compareNames
    result.compare = comparison.series(main: s, keys: shown,
      colors: shown.map { key in
        let slot = prefs.compareSymbols.firstIndex(of: key) ?? 0
        let palette = result.colors.palette
        return palette[slot % palette.count]
      },
      names: { names[$0] ?? String($0.split(separator: "/").last ?? "") })
    return result
  }
}

/// 揉 `ChartState` 要的、**不随推送变**的那一半：设置、皮肤、此刻开着哪几个指标、
/// 是不是对比态。宿主在自己的 body 里算好（它们变了宿主本来就要重排），
/// 逐笔的那一半由 `ChartSession.liveState` 在图那块视图里现取。
struct ChartInput {
  var prefs: Prefs
  var seed: PaletteSeed
  var overlays: [IndicatorID]
  var subs: [IndicatorID]
  var subScale: [IndicatorID: Double]
  var drawingCanvasOnly: Bool
  var comparing: Bool
  var compareKeys: [String]
  var compareNames: [String: String]
}

/// 逐笔推送带出来的两件副作用：成交交给报价簿、费率存一份给预览卡。
///
/// 从前是 `MainScreenObservers` 里的两条 `onChange`，被观察的值（`market.tradeQuote`、
/// `market.displayedFundingRate`）在 `MainScreen.body` 里求值——于是每一笔成交都把
/// 整张根视图叫起来一次。挪到这只空视图里：跟着推送重求值的只有它自己，它什么都不画。
struct LiveTickRelay: View {
  let session: ChartSession
  let onFunding: (Double?) -> Void

  var body: some View {
    #if DEBUG
      let _ = FrameProbe.shared.countBody("LiveTickRelay")
    #endif
    let market = session.market
    Color.clear
      .frame(width: 0, height: 0)
      .accessibilityHidden(true)
      .onChange(of: market.tradeQuote) { _, trade in session.relay(trade: trade) }
      // 费率只有正在看的那张图才有（`markPrice` 流里捎的），顺手存一份给预览卡。
      .onChange(of: market.displayedFundingRate) { _, rate in onFunding(rate) }
  }
}

/// 横屏那一行小字的实时版：价和涨跌在这一小块里现取，逐笔推送只叫醒它。
struct LiveLandscapeHeadline: View {
  let session: ChartSession
  let theme: PanelTheme
  let onTapSymbol: (() -> Void)?

  var body: some View {
    let market = session.market
    LandscapeHeadline(
      theme: theme, symbol: market.symbol, price: session.readoutPrice,
      changePercent: session.changePercent,
      decimals: market.info.priceDecimals,
      onTapSymbol: onTapSymbol)
  }
}

/// 对比的接线键在修饰符自己的 body 里求值：它要读序列首尾时刻，放在宿主 body 里
/// 就等于让每根新 K 线都把宿主叫起来一次。
struct LiveCompareObservers: ViewModifier {
  let drive: () -> CompareDrive
  let onChange: () -> Void
  func body(content: Content) -> some View {
    content.modifier(CompareObservers(drive: drive(), onChange: onChange))
  }
}

#if DEBUG
  /// 给 UI 用例读的那几条诊断（上游、推送状态、网络、根宽三份拷贝）。
  ///
  /// 独立成一只小视图：推送状态和网络诊断是跟着连接变的，写在宿主 body 里就会把整页叫起来。
  struct MainDiagnosticsOverlay: View {
    let market: MarketModel
    let store: PrefsStore
    let viewport: ChartViewport

    var body: some View {
      let _ = FrameProbe.shared.countBody("MainDiagnosticsOverlay")
      VStack {
        Text(market.capabilities.upstream).font(.system(size: 1)).opacity(0.01).accessibilityIdentifier("market.source").accessibilityValue(market.status.rawValue)
        // 网络日志（最多 8000 字、每出一笔请求就追加一行）只挂在无障碍标签上，不当正文排：
        // 原来是 `Text(lines)`——1pt、0.01 透明也照样整段断行、塑形、栅格化，每追加一行重来一遍。
        // 整机压测 2026-09-26 采样：连切品种 / 周期时主线程九成时间耗在这段字上，
        // 量出来的「卡顿」几乎全是这个探针自己的。用例读的是 `.label`，照旧拿得到全文。
        Text("network").font(.system(size: 1)).opacity(0.01).accessibilityIdentifier("market.network")
          .accessibilityLabel(MarketNetworkDiagnostics.shared.lines)
        // 根宽的三份拷贝，排查「捏完杀 app」那个 bug 用：
        // `stored` = `PrefsStore` 手上这份（`update` 是同步落盘的，它等于盘上那份）；
        // `live` = `ChartViewport` 内存里那份；图自己量出来的那份在 `chart.canvas` 的
        // `spacing` 里。三份对不上，就知道是哪一步把用户的值写掉了。
        Text("layout").font(.system(size: 1)).opacity(0.01)
          .accessibilityIdentifier("layout.diagnostics")
          .accessibilityValue("stored=\(store.prefs.barSpacing);live=\(viewport.barSpacing);token=\(viewport.adoptToken);landStored=\(store.prefs.landscapeBarSpacing);landLive=\(viewport.landscapeBarSpacing)")
        // 主力订单流手上这份大单：条数、最早一条的出现时刻、还挂着的条数。用例拿「最早出现」比启动时刻，
        // 早于启动就只能是从服务端历史并进来的（本机日志只记本机看见过的）。
        // 主线程卡顿账（`MainThreadHangLog`）：压测用例前后各读一次，看这一轮卡了几次、最长多久。
        Text("hangs").font(.system(size: 1)).opacity(0.01)
          .accessibilityIdentifier("main.hangs")
          .accessibilityValue(MainThreadHangLog.shared.summary)
        Text("orderflow").font(.system(size: 1)).opacity(0.01)
          .accessibilityIdentifier("orderflow.diagnostics")
          .accessibilityValue(orderFlowSummary)
      }.allowsHitTesting(false)
    }

    private var orderFlowSummary: String {
      let snapshot = market.orderFlow.snapshot
      let orders = snapshot?.orders ?? []
      let earliest = orders.map(\.firstSeenMs).min() ?? 0
      // 各本簿就绪与否（`OKX/spot/BTC-USDT:1`），以及每本簿手上的单数——用来核「某家某产品真的接上了」
      // （2026-09-24 用户点名 OKX 现货 BTC 必须接上）：簿就绪只说明快照到了，单数才说明它在出单。
      var perVenue: [String: Int] = [:]
      for o in orders { perVenue[o.venueID, default: 0] += 1 }
      let books = (snapshot?.venues ?? [])
        .map { "\($0.label)/\($0.product.rawValue)/\($0.instrument):\($0.ready ? 1 : 0)" }
        .joined(separator: "|")
      let counts = perVenue.keys.sorted().map { "\($0):\(perVenue[$0]!)" }.joined(separator: "|")
      return "orders=\(orders.count);earliest=\(earliest);live=\(orders.filter { $0.endMs == nil }.count);books=\(books);counts=\(counts)"
    }
  }
#endif
