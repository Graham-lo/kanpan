import SwiftUI
import KanpanCore

/// 面板的出场方式（§9.2 / §10.6）：半屏 sheet，可拉到全屏，下拉关闭。
///
/// 挂到主界面那一步不在这儿——这儿只提供 `.prefsPanel(…)` 这一个入口，
/// 主界面拿一个 `Panel?` 当状态，改它就开关面板。

/// 哪个面板。
///
/// 2026-09-18 底栏改成常驻标签栏（画线 · 图表 · 自选 · 设置）之后，这儿只剩两张：
/// 「设置」升成了标签栏上的一整页，不再是半屏；「指标」整段并进了「图表设置」，
/// 成为它里头的一个子栏目——用户的话是「行情页面的指标放到图表里作为一个子栏目」。
/// 半屏 sheet 从此只留给这种「从某一页里叫出来的子面板」，不承载标签本身。
enum Panel: String, Identifiable, CaseIterable, Sendable {
  case period, chart

  var id: String { rawValue }

  var title: String {
    switch self {
    case .period: "周期"
    // 「图表」这个名字给了标签栏那一格（整张行情页），面板只管图上那些设置，
    // 所以它叫「图表设置」——同名两个东西会让人不知道自己点开的是哪个。
    case .chart: "图表设置"
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

  @Environment(\.panelTheme) private var inheritedTheme
  private var seed: PaletteSeed { store.prefs.ambientTheme ? inheritedTheme.seed : store.prefs.seed(systemDark: systemScheme == .dark) }

  var body: some View {
    content()
      .environment(\.panelTheme, PanelTheme(seed: seed, redUp: store.prefs.redUp))
      .preferredColorScheme(store.prefs.ambientTheme ? (seed.dark ? .dark : .light) : store.prefs.theme.forced)
      .presentationDetents([.medium, .large])
      .presentationDragIndicator(.visible)
      .presentationBackground { Color(hex: seed.raised) }
      .presentationCornerRadius(18)
      // 背后继续更新；外部触摸由ChartBox遮罩消费，只关闭面板。
      .presentationBackgroundInteraction(.enabled(upThrough: .medium))
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

extension View {
  /// 主界面用这一个：`.prefsPanel($panel, store: store)`。
  func prefsPanel(_ panel: Binding<Panel?>,
                  store: PrefsStore,
                  onPickInterval: ((Interval) -> Void)? = nil,
                  onRecord: (() -> Void)? = nil) -> some View {
    sheet(item: panel) { which in
      PanelHost(store: store) {
        switch which {
        case .period: IntervalGridPanel(store: store, onPick: onPickInterval)
        case .chart: ChartPanel(store: store, onRecord: onRecord)
        }
      }
    }
  }
}

// MARK: - 预览

/// `#Preview` 用的壳：不碰真沙盒、不碰真缓存，深浅两版各看一眼。
struct PanelPreviewHost<Content: View>: View {
  @ViewBuilder var content: (PrefsStore) -> Content

  @State private var store = PrefsStore(storage: InMemoryPrefsStorage(),
                                        cache: UnavailableMarketCache())
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
                                        cache: UnavailableMarketCache())
  @State private var panel: Panel?

  var body: some View {
    VStack(spacing: 12) {
      Text("看盘").font(.system(size: 32, weight: .semibold)).kerning(6)
      HStack(spacing: 10) {
        ForEach(Panel.allCases) { p in
          Button(p.title) { panel = p }.buttonStyle(.bordered)
        }
      }
      Text(verbatim: "\(store.prefs.style.name) · \(store.prefs.interval.rawValue) · "
           + store.prefs.subs.map(\.rawValue).joined(separator: "+"))
        .font(.footnote.monospaced())
        .foregroundStyle(.secondary)
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .prefsPanel($panel, store: store)
    .preferredColorScheme(store.prefs.theme.forced)
  }
}
