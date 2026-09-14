import KanpanChart
import KanpanCore
import KanpanData
import SwiftUI
import UIKit

/// 主界面（§9.1）。
///
/// 从上到下：顶栏 → 价格行 → 周期条 → 图（占满剩下的）→ 底部工具条五个。
/// 这一层只做接线：把 `MarketModel` 的行情和 `PrefsStore` 的设置揉成一份 `ChartState`
/// 交给图，再把图和面板的回调转回去。**任何计算都不该在这儿写**——算法在 `KanpanCore`，
/// 画在 `KanpanChart`，这里只负责让它们见面。
struct MainScreen: View {
  @State private var market = MarketModel()
  @State private var store = PrefsStore()
  @State private var picker = SymbolPickerModel()
  @State private var proxy = ChartProxy()

  @State private var panel: Panel?
  @State private var showSymbols = false
  @State private var atLatest = true
  @StateObject private var draw = DrawingController()
  @State private var toast: String?
  @State private var toastID = 0
  /// 十字线亮着的时候，价格行读的是十字线那根，不是最新价（原型 `readout`）。
  @State private var crosshair: Crosshair?

  @Environment(\.colorScheme) private var scheme
  @Environment(\.scenePhase) private var phase
  @Environment(\.verticalSizeClass) private var vClass

  private var prefs: Prefs { store.prefs }

  private var dark: Bool {
    switch prefs.theme {
    case .system: scheme == .dark
    case .light: false
    case .dark: true
    }
  }

  private var theme: PanelTheme { PanelTheme(dark: dark, redUp: prefs.redUp) }

  /// 设置里那两行域名（A6.10）。REST 和推送分开填，理由见 `APIHost.defaultStream`。
  private var hosts: BinanceHosts { BinanceHosts(fapi: prefs.apiHost, stream: prefs.streamHost) }

  /// 横屏判据用高度的 size class，不用宽高比。
  ///
  /// iPad 横过来仍然是 regular × regular——那是「大屏竖版布局转个向」，不该切成
  /// 手机横屏那套（§10.7 说的是 iPhone 横屏；iPad 走 A8.3 的放大布局）。
  private var landscape: Bool { vClass == .compact }

  var body: some View {
    Group {
      if landscape { landscapeBody } else { portraitBody }
    }
    .background(theme.app)
    .preferredColorScheme(prefs.theme.forced)
    .overlay(alignment: .bottom) { toastLayer }
    // 横屏的面板走自己那层侧栏，不挂系统 sheet：半屏 sheet 在 compact 高度下会被
    // 系统顶成全屏，图就整个没了。
    .prefsPanel(landscape ? .constant(nil) : $panel, store: store,
                onPickInterval: pick(interval:))
    .fullScreenCover(isPresented: $showSymbols) {
      SymbolPickerView(model: picker, redUp: prefs.redUp, onClose: { showSymbols = false })
        .preferredColorScheme(prefs.theme.forced)
    }
    .task { boot() }
    .onChange(of: phase) { _, now in
      switch now {
      case .background: market.enterBackground()
      case .active: market.enterForeground()
      default: break
      }
    }
    .onChange(of: prefs.keepAwake, initial: true) { _, on in
      UIApplication.shared.isIdleTimerDisabled = on
    }
    .onChange(of: prefs.launchSnapshot) { _, on in market.setSnapshotEnabled(on) }
    .onChange(of: hosts) { _, next in market.setHosts(next) }
    .onChange(of: store.notice) { _, note in
      if let note { say(note); store.clearNotice() }
    }
    .onChange(of: draw.full) { _, full in
      // A7.7：一个品种最多 50 条，满了只提示、不悄悄丢。
      if full { say("这个品种的线画满了（50 条）"); draw.full = false }
    }
    .environment(\.panelTheme, theme)
  }

  // ---------------------------------------------------------------- 各段

  private var portraitBody: some View {
    VStack(spacing: 0) {
      header
      hairline
      IntervalBar(
        theme: theme, quick: prefs.quickIntervals, current: market.interval,
        onPick: pick(interval:), onMore: { panel = .period }
      )
      .background(theme.app)
      hairline
      chart
      hairline
      if draw.active {
        DrawingBar(controller: draw)
      }
      BottomBar(
        theme: theme, active: panel, drawing: draw.active,
        onPanel: { p in panel = (panel == p) ? nil : p },
        onDraw: { dismissPanel(); draw.toggle() },
        onLandscape: { dismissPanel(); Orientation.rotate(to: true) }
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
      ZStack(alignment: .topLeading) {
        chart
        LandscapeHeadline(
          theme: theme, symbol: market.symbol, price: readoutPrice,
          changePercent: market.ticker?.changePercent,
          decimals: market.info.pricePrecision,
          onSymbol: { dismissPanel(); showSymbols = true })
          .padding(.leading, 8)
          .padding(.top, 6)
        if draw.hint != nil {
          DrawingHintStrip(controller: draw)
            .frame(maxWidth: .infinity, alignment: .top)
            .padding(.top, 6)
        }
      }
      if draw.active {
        DrawingRail(controller: draw)
      }
      ToolRail(
        theme: theme, active: panel, drawing: draw.active,
        onPanel: { p in panel = (panel == p) ? nil : p },
        onDraw: { dismissPanel(); draw.toggle() },
        onPortrait: { dismissPanel(); Orientation.rotate(to: false) })
    }
    .ignoresSafeArea(.container, edges: .bottom)
    .overlay(alignment: .trailing) {
      SidePanelLayer(theme: theme, shown: panel != nil, onClose: dismissPanel) {
        sidePanelContent
      }
    }
  }

  @ViewBuilder private var sidePanelContent: some View {
    if let which = panel {
      PanelSide(store: store, dark: dark, onClose: PanelDismiss { dismissPanel() }) {
        switch which {
        case .style: StylePanel(store: store)
        case .indicator: IndicatorPanel(store: store)
        case .period: PeriodPanel(store: store, onPick: pick(interval:))
        case .settings: SettingsPanel(store: store)
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
        onSymbol: { dismissPanel(); showSymbols = true },
        onStatus: { say(statusLine) },
        onSearch: { dismissPanel(); showSymbols = true },
        onStar: {
          dismissPanel()
          let now = picker.toggleFavorite(market.symbol)
          say(now ? "已加入自选" : "已移出自选")
        })
      PriceRow(
        theme: theme, ticker: market.ticker, lastPrice: readoutPrice,
        decimals: market.info.pricePrecision)
    }
    .padding(.horizontal, 12)
    .padding(.vertical, 8)
    .background(theme.app)
  }

  /// 长按状态圆点报的那一行（§10.5）。
  ///
  /// 除了状态本身还报「多久没推了」：WS 能连上但一帧不推的时候 `status` 仍是
  /// `.live`，光看颜色会以为一切正常——这一行是那种情况唯一看得见的线索。
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

  /// 十字线在哪根上就读哪根的收盘，没有十字线就读最新价。
  private var readoutPrice: Double? {
    if let c = crosshair, let s = market.series, c.index >= 0, c.index < s.count {
      return s.close[c.index]
    }
    return market.series?.close.last ?? market.ticker?.last
  }

  private var chart: some View {
    ZStack(alignment: .bottomTrailing) {
      theme.chartBG
      ChartHost(
        state: chartState,
        proxy: proxy,
        onView: { _ in atLatest = proxy.isAtLatest },
        onCrosshair: { crosshair = $0 },
        onNeedsHistory: { market.loadMore() },
        // 点一下图就回到看盘：面板收起（§10.6「点遮罩关闭」在这一层的等价物——
        // sheet 背后仍然可以单指拖图，所以不铺遮罩，而是让图自己把这一下报上来）。
        onTapped: { dismissPanel() },
        drawing: draw
      )
      // 换品种/周期的空档：旧图留着压暗，不闪白（§10.4）。
      .opacity(market.switching ? 0.6 : 1)
      .animation(.easeOut(duration: 0.18), value: market.switching)
      LatestButton(theme: theme, shown: !atLatest, action: goLatest)
      // 提示条压在图区上沿（§10.8），不占版面高度，所以走 overlay 不进 VStack。
      if draw.hint != nil {
        DrawingHintStrip(controller: draw)
          .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
          .padding(.top, 8)
      }
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .clipped()
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
    guard let s = market.series, s.count > 0 else { return nil }
    return ChartState(
      series: s,
      symbol: market.info,
      view: ViewWindow(to: Double(s.lastTime), span: Double(s.step) * 80),
      style: prefs.style,
      dark: dark,
      redUp: prefs.redUp,
      price: PriceTransform(mode: prefs.priceMode),
      overlays: prefs.overlays,
      subs: prefs.subs,
      params: prefs.params,
      timezone: prefs.timeZone,
      magnet: prefs.magnet,
      decimals: market.info.pricePrecision)
  }

  // ---------------------------------------------------------------- 动作

  private func boot() {
    picker.onPick = { info in
      showSymbols = false
      market.switchTo(symbol: info.symbol)
    }
    picker.setLoader(market.catalogLoader)
    // 域名要赶在开流之前给：`MarketModel` 自己的默认是币安官方那两台。
    market.setHosts(hosts)
    market.start(snapshot: prefs.launchSnapshot)
    if market.interval != prefs.interval { market.switchTo(interval: prefs.interval) }
  }

  /// 收起面板。选完一项、或者手指落到图和别的控件上，都走这儿。
  private func dismissPanel() {
    guard panel != nil else { return }
    panel = nil
  }

  private func pick(interval iv: Interval) {
    dismissPanel()
    guard iv != market.interval else { return }
    store.update { $0.interval = iv }
    market.switchTo(interval: iv)
    UISelectionFeedbackGenerator().selectionChanged()
  }

  private func goLatest() {
    proxy.scrollToLatest()
    atLatest = true
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
