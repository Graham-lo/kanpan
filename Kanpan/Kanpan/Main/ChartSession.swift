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
/// 自己只有一个会被观察的字段：`nowMs`（倒计时那一秒）。别的都是引用，
/// 读谁就在读的那块视图上记依赖——这正是要的效果。
@MainActor @Observable
final class ChartSession {
  @ObservationIgnored let market: MarketModel
  @ObservationIgnored let quotes: QuoteBook
  @ObservationIgnored let comparison: CompareModel
  /// 十字线读数。只有读数那一小块观察它（见 `CrosshairReadout.swift`）。
  @ObservationIgnored let readout: CrosshairReadout

  /// 倒计时的当前时刻（毫秒）。`nil` = 不画。
  ///
  /// 渲染器**不读系统时钟**（`ChartState` 得是纯值，A3.11 的基线靠这条），时间只能
  /// 从外面喂进去，喂的人是 `heartbeat`。只有 `MainChartView` 读它——一秒一跳只叫醒图。
  private(set) var nowMs: Double?

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

  /// 换周期。十字线同理。
  func show(interval: Interval) {
    readout.clear()
    market.switchTo(interval: interval)
  }

  /// 换线路 / 换涨跌口径。行情那条（`MarketModel`）自己认 `RouteResolver.current`，
  /// 这儿交的是报价簿那条。
  func configure(route: RouteResolver, basis: ChangeBasis) {
    quotes.configure(route: route, basis: basis)
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

  /// 一秒一跳：倒计时、持仓量补取、报价簿的钟，再加宿主自己的那一拍（`onBeat`）。
  ///
  /// `active` 为假（不在前台）就不跳，并把倒计时收掉：回到前台时 `.task(id:)` 重来，
  /// 第一跳立刻把停在后台那一刻的旧时间冲掉，不会先闪一秒错的倒计时。
  func heartbeat(active: Bool, countdown: @escaping @MainActor () -> Bool,
                 onBeat: @escaping @MainActor () -> Void) async {
    guard active else { setNow(nil); return }
    while !Task.isCancelled {
      setNow(countdown() ? Date().timeIntervalSince1970 * 1000 : nil)
      market.refreshOIIfNeeded()
      quotes.tick()
      onBeat()
      do { try await Task.sleep(for: .seconds(1)) } catch { return }
    }
  }

  private func setNow(_ value: Double?) {
    if value != nowMs { nowMs = value }
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
    if let quote = chartQuote { return quote }
    // MarketModel already receives the venue ticker frames as part of the
    // chart feed. Use that value immediately instead of waiting for the
    // separate list QuoteBook to open another socket.
    // 两路都还没到（从板块列表 / 搜索点进一只没看过的品种）：退到全市场 24h 那一份
    // 种子——几秒前的价，也比顶栏一排「—」强，真行情一到就被盖掉。
    return market.ticker ?? quotes.seeded(market.symbol)
  }

  /// 报价簿里图上这只的那一格。先读被观察的镜像（`QuoteBook.chartQuote`）；
  /// 报价簿还没认到这只（换品种的那一拍，`setChartSymbol` 在观察者里才跟上）时
  /// 退回整表现取——镜像一跟上，读过它的视图自然会再求值一次。
  private var chartQuote: Ticker? {
    if let quote = quotes.chartQuote, quote.symbol == market.symbol { return quote }
    return quotes.raw[market.symbol]
  }

  var displayedTicker: Ticker? {
    rollingTicker.map { quotes.presented($0) }
  }

  /// Latest trade quote only; changing candle interval must never change its source.
  var readoutPrice: Double? {
    market.capabilities.isSubstitute ? (market.series?.close.last ?? displayedTicker?.last) : displayedTicker?.last
  }

  /// 给 UI 用例读的那串诊断值。**只在 DEBUG 构建里存在**（审查 C-02）：
  /// 正式包不该因为一个环境变量就把根数、视野、报价时刻挂到可访问树上。
  var quoteDiagnostics: String {
    #if DEBUG
    guard ProcessInfo.processInfo.environment["KANPAN_CHART_DIAGNOSTICS"] == "1" else { return "" }
    return "symbol=\(market.symbol);last=\(displayedTicker?.last ?? .nan);time=\(displayedTicker?.timeMs ?? 0)"
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
      livePrice: { [market] in market.tradeQuote?.price ?? market.ticker?.last })
  }

  /// 行情 + 设置 揉成一份 `ChartState`。**只在 `MainChartView` 的 body 里调**——
  /// 在哪儿调，逐笔推送就叫醒哪儿。
  ///
  /// `view` 这里给个占位：视野归图自己管，`ChartHost` 会按「换品种/换周期/换风格」
  /// 三种情形各自算一份真的（见 `ViewIntent`）。
  func liveState(_ input: ChartInput) -> ChartState? {
    guard let s = market.series, s.symbol == market.symbol, s.interval == market.interval, s.count > 0 else { return nil }
    let prefs = input.prefs
    // 上下翻转跟着人走，不跟着品种走：换品种时这份 state 是新造的，翻转要是不从设置里
    // 带出来，图就会自己翻回去。开关关掉时不认存档里那一份——否则翻过去之后把开关一关，
    // 就再也没有把它翻回来的入口了。
    var price = PriceTransform(mode: prefs.priceMode)
    price.inverted = prefs.allowMainInversion && prefs.mainInverted
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
      magnet: prefs.magnet,
      decimals: market.info.priceDecimals,
      options: prefs.chartOptions,
      nowMs: nowMs,
      subScale: input.subScale)
    // 走 OKX 兜底线路时持仓量根本取不到（`OISource` 只连币安）——让副图说实话，
    // 别一直挂「加载中」。
    result.external = market.external
    result.depth = input.drawingCanvasOnly || !prefs.depth ? nil : market.depth
    result.orderFlow = market.orderFlow.chartValue(symbol: market.symbol, drawingCanvasOnly: input.drawingCanvasOnly)
    result.orderFlowDisplay = prefs.orderFlowDisplay
    // 持仓量和衍生统计分开认：网关线路上的替身有持仓量历史（kanpan-api 代问 OKX），
    // 多空比、主动买卖、基差没有。
    result.oiSupported = market.capabilities.hasOpenInterestHistory
    result.externalSupported = market.capabilities.hasDerivativeMetrics
    result.subInverted = prefs.allowSubInversion ? prefs.subInverted : []
    result.paletteSeed = input.seed
    result.hiddenOutputs = prefs.hiddenOutputs
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
    result.rsiUpper = prefs.rsiUpper; result.rsiLower = prefs.rsiLower
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
      changePercent: session.displayedTicker?.changePercent,
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
        Text(MarketNetworkDiagnostics.shared.lines).font(.system(size: 1)).opacity(0.01).accessibilityIdentifier("market.network")
        // 根宽的三份拷贝，排查「捏完杀 app」那个 bug 用：
        // `stored` = `PrefsStore` 手上这份（`update` 是同步落盘的，它等于盘上那份）；
        // `live` = `ChartViewport` 内存里那份；图自己量出来的那份在 `chart.canvas` 的
        // `spacing` 里。三份对不上，就知道是哪一步把用户的值写掉了。
        Text("layout").font(.system(size: 1)).opacity(0.01)
          .accessibilityIdentifier("layout.diagnostics")
          .accessibilityValue("stored=\(store.prefs.barSpacing);live=\(viewport.barSpacing);token=\(viewport.adoptToken)")
        // 主力订单流手上这份大单：条数、最早一条的出现时刻、还挂着的条数。用例拿「最早出现」比启动时刻，
        // 早于启动就只能是从服务端历史并进来的（本机日志只记本机看见过的）。
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
