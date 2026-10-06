import SwiftUI
import KanpanCore

/// 面板的出场方式（§9.2 / §10.6）：半屏 sheet，可拉到全屏，下拉关闭。
///
/// 挂到主界面那一步不在这儿——这儿只提供 `.prefsPanel(…)` 这一个入口，
/// 主界面拿一个 `Panel?` 当状态，改它就开关面板。

/// 哪个面板。
///
/// 2026-09-18 底栏改成常驻标签栏（当时是画线 · 图表 · 自选 · 设置）之后，这儿只剩两张：
/// 「设置」升成了标签栏上的一整页，不再是半屏；「指标」整段并进了「图表设置」，
/// 成为它里头的一个子栏目——用户的话是「行情页面的指标放到图表里作为一个子栏目」。
/// 半屏 sheet 从此只留给这种「从某一页里叫出来的子面板」，不承载标签本身。
///
/// 2026-09-24 周期条行尾多了一个「指标」大类入口（用户：「现在指标这个大类放到周期条中」），
/// 它直接开指标页（`indicators`），左上角那颗就是关面板。
///
/// 2026-09-27（方案「我的 · 自动复盘 · 周期分组指标」§1.3）：「图表设置 › 指标」那条推进去的路撤了，
/// 指标页只剩周期条这一个入口，并把「对比」从图表设置接了过来（指标 · 对比 · 主力订单流三节）；
/// 「图表设置」只剩这张图 · K 线 · 显示 · 价格轴。底栏也从五格收成四格（图表 · 自选 · 板块分类 · 我的），
/// 「设置」是「我的」里推进去的一页，「画线」进了周期条行尾。
///
/// 2026-09-28 行尾收回三件：那格「指标」改名「分析」，面板也叫「分析」，分四节
/// 画线 · 指标 · 对比 · 主力订单流——画线与指标并列，「指标」从此只是面板里的一节名。
/// 2026-10-05「对比」那一节搬到顶栏（加号，`top.compare`），面板一度只剩三节；10-06 用户要求两处并存，
/// 分析面板恢复四节，这一节的「添加对比」开的就是顶栏加号那张对比模式搜索页。
/// 枚举值仍叫 `indicators`（面板状态、测试 id 都挂在它上面，改名没有好处）。
///
/// 同一天（顶栏方案 B）多了一张 `share`：「图表设置 › 这张图 › 分享」那条推进去的路撤了，
/// 分享改成顶栏右侧一颗圆片；两种分享（图片 / 画线）都能用时，点它开这张面板，里头就是
/// 原来那层二选一 `ShareChooser`，左上角那颗是关面板。
enum Panel: String, Identifiable, CaseIterable, Sendable {
  case period, chart, indicators, share

  var id: String { rawValue }

  var title: String {
    switch self {
    case .period: "周期"
    // 「图表」这个名字给了标签栏那一格（整张行情页），面板只管图上那些设置，
    // 所以它叫「图表设置」——同名两个东西会让人不知道自己点开的是哪个。
    case .chart: "图表设置"
    case .indicators: "分析"
    case .share: "分享"
    }
  }
}

extension ThemeChoice {
  /// 「跟随系统」时交给环境，浅 / 深两档自己说了算（A6.3）。
  var forced: ColorScheme? {
    switch self {
    case .system: nil
    case .light: .light
    case .dark: .dark
    }
  }
}

/// 给面板灌上主题、深浅与半屏尺寸。四个面板都从这儿出场，省得各写一遍。
struct PanelHost<Content: View>: View {
  var store: PrefsStore
  @ViewBuilder var content: () -> Content

  @Environment(\.colorScheme) private var systemScheme

  private var seed: PaletteSeed { store.prefs.seed(systemDark: systemScheme == .dark) }

  var body: some View {
    content()
      .environment(\.panelTheme, PanelTheme(seed: seed, redUp: store.prefs.redUp))
      .preferredColorScheme(store.prefs.theme.forced)
      .presentationDetents([.medium, .large])
      .presentationDragIndicator(.visible)
      .presentationBackground { Color(hex: seed.raised) }
      // 圆角交给系统（iOS 26 的 sheet 圆角与屏幕同心），不再手写 18。
      // 背后继续更新；外部触摸由宿主页的 `PanelDismissShield` 接住，只关闭面板。
      .presentationBackgroundInteraction(.enabled(upThrough: .medium))
      // 面板里那张长列表**自己滚**，不许它把面板一路顶到满屏。
      //
      // 不写这一句时 `.automatic` 生效：手指在内容上往上一划，系统先把 sheet 从
      // `.medium` 撑到 `.large`，划完才轮到内容滚。于是「往下找一个指标」这么一下
      // 就把图整个盖住了——而这一叠修饰符的用意恰恰相反：`.enabled(upThrough: .medium)`
      // 就是为了让人一边开关指标一边看着图上的变化。撑满之后图看不见，背后也不再收触摸，
      // 点图区收面板这条路（§10.6）跟着一起断（M8 兼容性矩阵 iPhone 15 上的
      // `testOnlyTheThingsTheRulesSayToClearGetCleared`：指标开关被滚到 y=361，
      // 那已经在 `.medium` 的上沿之上了，随后点 (40,346) 落在面板上，面板当然不收）。
      //
      // 要满屏仍旧走得通：拖那根把手 / 面板顶部空白处，那还是改尺寸。
      .presentationContentInteraction(.scrolls)
  }
}

/// 横屏的侧栏用它把「关掉我」传进面板。
///
/// 竖屏面板是系统 sheet，关自己走 `@Environment(\.dismiss)`；横屏是主界面自己铺的
/// 一层覆盖，系统的 `dismiss` 在那儿什么也不做。面板本身不该知道自己是以哪种方式
/// 出场的，所以两条路都收在 `PanelCloser` 后面。
/// 关自己那个动作。包一层 struct 而不是裸闭包：环境值要求 `Sendable`，
/// 裸的 `(() -> Void)?` 过不了 Swift 6 的并发检查。
struct PanelDismiss: Sendable {
  private let run: @MainActor @Sendable () -> Void
  init(_ run: @escaping @MainActor @Sendable () -> Void) { self.run = run }
  @MainActor func callAsFunction() { run() }
}

private struct PanelDismissKey: EnvironmentKey {
  static let defaultValue: PanelDismiss? = nil
}

extension EnvironmentValues {
  var panelDismiss: PanelDismiss? {
    get { self[PanelDismissKey.self] }
    set { self[PanelDismissKey.self] = newValue }
  }
}

/// 面板内部统一这一句，不关心自己是 sheet 还是侧栏。
@MainActor
struct PanelCloser {
  var side: PanelDismiss?
  var sheet: DismissAction

  func callAsFunction() {
    if let side { side() } else { sheet() }
  }
}

/// 横屏侧栏的外壳：主题、深浅、背景，外加把关闭动作递进去。
struct PanelSide<Content: View>: View {
  var store: PrefsStore
  var seed: PaletteSeed
  var onClose: PanelDismiss
  @ViewBuilder var content: () -> Content

  var body: some View {
    content()
      .environment(\.panelTheme, PanelTheme(seed: seed, redUp: store.prefs.redUp))
      .environment(\.panelDismiss, onClose)
  }
}

/// 面板里那些「由宿主页决定能不能做」的动作。竖屏 sheet 和横屏侧栏拿的是
/// **同一份**（审查 16.2）。
///
/// 某个动作此刻做不了（复盘回放里没有画线、预览别人的线时不能发线），
/// 宿主页就把那一项传 nil，面板里那一行直接不排——面板自己不判断横竖屏。
/// 「记一笔」2026-09-28 起在顶栏上，不再经过面板。
struct PanelActions {
  var onPickInterval: ((Interval) -> Void)? = nil
  /// 分享成图片（`share` 面板的「图片」格）。
  var onShare: (() -> Void)? = nil
  /// 分析面板「对比」一节的「添加对比」：开顶栏加号那张对比模式搜索页。此刻不能对比时传 nil，那一节不排。
  var onAddCompare: (() -> Void)? = nil
  var compareNames: [String: String] = [:]
  /// 指标页第一节「画线」（2026-09-28 从周期条行尾归进来）。复盘回放、已经在画时传 nil，那一节不排。
  var onDraw: (() -> Void)? = nil
  /// 对比期间画不了线：那一行置灰、点不动。
  var drawEnabled = true
  var onSend: (() -> Void)? = nil
  var sendBlocked: String? = nil
  /// 主力订单流的胶水与当前品种：指标页「主力订单流 › 门槛」那张表拿它显示这只币此刻生效的门槛。
  /// 传的是引用而不是算好的值——大单帧每半秒一次，算好的值挂在这里会让主界面跟着重算。
  var orderFlow: OrderFlowLink? = nil
  var symbol: String = ""
  /// 横屏画线台里开的「分析」：只摆主图指标那几段（见 `IndicatorPage.mainOnly`）。
  var mainOnly = false
}

/// 某张面板里装什么。竖屏 sheet（`prefsPanel`）和横屏侧栏（`PanelSide`）都只认这一个，
/// 面板内容从此只有一处 `switch`。
struct PanelContent: View {
  var which: Panel
  var store: PrefsStore
  var actions: PanelActions

  var body: some View {
    switch which {
    case .period: IntervalGridPanel(store: store, onPick: actions.onPickInterval)
    case .chart:
      ChartPanel(store: store)
    case .share:
      SharePanel(onImage: actions.onShare, onLines: actions.onSend, linesBlocked: actions.sendBlocked)
    case .indicators:
      // 「分析」面板（画线 · 指标 · 对比 · 主力订单流）。从周期条直接开：没有上一层，`onBack` 不传，左上角那颗就是关面板（`PanelSheet`）。
      // 选中反馈长在指标页各控件的动作上（`PrefsStore.updateByHand`），两条路一样。
      IndicatorPage(store: store, orderFlow: actions.orderFlow, symbol: actions.symbol,
                    onAddCompare: actions.onAddCompare, compareNames: actions.compareNames,
                    onDraw: actions.onDraw, drawEnabled: actions.drawEnabled, mainOnly: actions.mainOnly)
    }
  }
}

/// 顶栏「分享」开的那张面板：图片 / 画线二选一。选完先收面板再做——出图要看见图，
/// 发线要换成选朋友那一层。两样里缺一样时宿主页不会开这张面板（直接走能走的那一种），
/// 这里仍按缺的那格不排兜底。
struct SharePanel: View {
  var onImage: (() -> Void)?
  var onLines: (() -> Void)?
  var linesBlocked: String?

  @Environment(\.dismiss) private var dismiss
  @Environment(\.panelDismiss) private var sideDismiss

  var body: some View {
    let close = PanelCloser(side: sideDismiss, sheet: dismiss)
    ShareChooser(onImage: { close(); onImage?() },
                 onLines: { close(); onLines?() },
                 linesBlocked: onLines == nil ? "此刻发不了画线" : linesBlocked,
                 onBack: nil)
  }
}

extension View {
  /// 主界面用这一个：`.prefsPanel($panel, store: store, actions: …)`。
  func prefsPanel(_ panel: Binding<Panel?>, store: PrefsStore, actions: PanelActions = PanelActions()) -> some View {
    sheet(item: panel) { which in
      PanelHost(store: store) { PanelContent(which: which, store: store, actions: actions) }
    }
  }
}

#if DEBUG
// MARK: - 预览

/// 预览不碰真缓存：报「没接上」，清也不清。
private struct PreviewMarketCache: MarketCacheStore {
  func usage() async -> MarketCacheUsage { .unavailable }
  func clear() async {}
}

/// `#Preview` 用的壳：不碰真沙盒、不碰真缓存，深浅两版各看一眼。
struct PanelPreviewHost<Content: View>: View {
  @ViewBuilder var content: (PrefsStore) -> Content

  @State private var store = PrefsStore(storage: InMemoryPrefsStorage(),
                                        cache: PreviewMarketCache())
  @Environment(\.colorScheme) private var scheme

  var body: some View {
    let seed = store.prefs.seed(systemDark: scheme == .dark)
    content(store)
      .environment(\.panelTheme, PanelTheme(seed: seed, redUp: store.prefs.redUp))
      .preferredColorScheme(store.prefs.theme.forced)
      .background(Color(hex: seed.raised))
  }
}

#Preview("面板") {
  PanelDemo()
}

/// 把面板挂起来看一眼：这就是主界面接它的全部写法。
private struct PanelDemo: View {
  @State private var store = PrefsStore(storage: InMemoryPrefsStorage(),
                                        cache: PreviewMarketCache())
  @State private var panel: Panel?

  var body: some View {
    VStack(spacing: 12) {
      Text("看盘").font(.system(size: 32, weight: .semibold)).kerning(6)
      HStack(spacing: 10) {
        ForEach(Panel.allCases) { p in
          Button(p.title) { panel = p }.buttonStyle(.bordered)
        }
      }
      Text(verbatim: "AICoin · \(store.prefs.interval.rawValue) · "
           + store.prefs.subs.map(\.rawValue).joined(separator: "+"))
        .font(.footnote.monospaced())
        .foregroundStyle(.secondary)
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .prefsPanel($panel, store: store)
    .preferredColorScheme(store.prefs.theme.forced)
  }
}
#endif

// MARK: - 手指拨的那一下

extension PrefsStore {
  /// 面板上**手指拨到**的那一下：真改到了就给一次 selection 触觉。
  ///
  /// 以前触觉是 `.sensoryFeedback(.selection, trigger: prefs)` 挂在几张面板上：
  /// 值一变就震，不管是谁改的——云端落地、图上双击翻转、另一处改设置，面板开着都会震；
  /// 「图表设置」外层一句、里层一句，拨一下还震两下。触觉该回答的是「我这一下拨到了」，
  /// 所以挂在控件动作上。
  func updateByHand(_ change: (inout Prefs) -> Void) {
    byHand { $0.update(change) }
  }

  /// 同上，给不走 `update` 的那几个动作（`toggleIndicator` 这类）用。
  func byHand(_ action: (PrefsStore) -> Void) {
    let before = prefs
    action(self)
    if prefs != before { Haptics.step() }
  }
}
