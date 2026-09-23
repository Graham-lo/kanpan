import KanpanCore
import Foundation
import Observation

/// 一个外来的「去哪儿」。
///
/// 桌面快捷入口、通知点击、收件箱里朋友发来的画线，最后都化成这个枚举里的一条，
/// 由 `MainScreen` 一处消费（见 `71bd340:docs/提醒与体验细节-实施方案-2026-09-20.md` 第 1 节）。
/// **不要为某一个入口另开一条跳转路径**——那样同一个「打开 BTC 的 1 小时图」
/// 会在通知里和桌面图标里长成两套行为。
///
/// 只认一种壳子 `hkline://`（分享走账号内朋友 + 收件箱，不发链接，所以没有 https 通用链接）：
///
///   hkline://symbol/BTCUSDT?interval=1h
///   hkline://drawing/BTCUSDT/<drawingID>
///   hkline://alerts
///   hkline://review/<recordID>
///   hkline://search
///   hkline://favorites
///   hkline://share/<id>
///
/// scheme 登记在 `Kanpan/Config/Info.plist` 的 `CFBundleURLTypes` 里。
enum DeepLink: Equatable {
  /// 打开某个品种的图。`interval` 给了就顺手换周期（`Interval` 的 rawValue，
  /// 如 `1h`；**大小写有意义**，`1M` 是月线、`1m` 是分钟线，所以这里原样保留）。
  case symbol(String, interval: String?)
  /// 打开某个品种并选中它上面的那条线。线不在了就只开品种。
  case drawing(symbol: String, drawingID: String)
  /// 提醒列表。
  case alerts
  /// 复盘本里的某一条记录。到点提醒那条本地通知点开就来这儿。
  case review(id: String)
  /// 品种搜索页。
  case search
  /// 自选页（桌面小号自选那一格点进来）。
  case favorites
  /// 朋友共享的那张图。
  case share(id: String)

  /// 自定义 scheme。
  static let scheme = "hkline"

  /// 认不出来的一律返回 nil——宁可什么都不做，也不要猜一个「差不多」的地方打开。
  static func parse(_ url: URL) -> DeepLink? {
    guard url.scheme?.lowercased() == Self.scheme else { return nil }
    return app(url)
  }

  // ---------------------------------------------------------------- 私有

  /// `hkline://` 那一族。第一段（URL 的 host）是去处，后面是参数。
  private static func app(_ url: URL) -> DeepLink? {
    let parts = segments(url)
    guard let route = parts.first?.lowercased() else { return nil }
    let rest = Array(parts.dropFirst())
    switch (route, rest.count) {
    case ("symbol", 3):
      guard let symbol = normalized(symbol: rest.joined(separator: "/")) else { return nil }
      return .symbol(symbol, interval: query(url, "interval"))
    case ("drawing", 4):
      guard let symbol = normalized(symbol: rest.prefix(3).joined(separator: "/")), !rest[3].isEmpty else { return nil }
      return .drawing(symbol: symbol, drawingID: rest[3])
    case ("symbol", 1):
      guard let symbol = normalized(symbol: rest[0]) else { return nil }
      return .symbol(symbol, interval: query(url, "interval"))
    case ("drawing", 2):
      guard let symbol = normalized(symbol: rest[0]), !rest[1].isEmpty else { return nil }
      return .drawing(symbol: symbol, drawingID: rest[1])
    case ("alerts", 0):
      return .alerts
    case ("review", 1):
      guard !rest[0].isEmpty else { return nil }
      return .review(id: rest[0])
    case ("search", 0):
      return .search
    case ("favorites", 0):
      return .favorites
    case ("share", 1):
      guard !rest[0].isEmpty else { return nil }
      return .share(id: rest[0])
    default:
      return nil
    }
  }

  /// 把 host 和 path 揉成一串段：`hkline://alerts` 的 host 是 `alerts`、path 是空的，
  /// 所以第一段（去处）从 host 取。
  private static func segments(_ url: URL) -> [String] {
    var parts: [String] = []
    if let host = url.host, !host.isEmpty { parts.append(host) }
    parts += url.path.split(separator: "/").map(String.init)
    // path 里的 `%2F` 之类由 URL 自己解过了；空段（`//`）不算一段。
    return parts.filter { !$0.isEmpty }
  }

  private static func query(_ url: URL, _ name: String) -> String? {
    guard let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems else { return nil }
    guard let value = items.first(where: { $0.name == name })?.value, !value.isEmpty else { return nil }
    return value
  }

  /// 品种代号：一律大写，只收字母数字（`1000PEPEUSDT` 这种带数字的是正常的）。
  /// 收不住的形状（空、带斜杠或点、超长）一律当认不出来。
  private static func normalized(symbol: String) -> String? {
    let id = InstrumentID(symbol)
    guard id.isValid, id.symbol.count <= 32, !id.symbol.contains("_") else { return nil }
    return id.key
  }
}

/// 外面进来的那一条链接停在这儿，等 `MainScreen` 来取。
///
/// 为什么要个中转：`.onOpenURL` 和通知回调都可能发生在界面还没搭起来的时候
/// （冷启动点通知就是），那一刻没有人能去换品种。所以这儿只记一个待办，
/// `MainScreen` 接好线之后（`boot()` 末尾）和之后每次变化时各来取一次。
@MainActor
@Observable
final class DeepLinkRouter {
  static let shared = DeepLinkRouter()

  /// 还没被消费的那一条。只有 `MainScreen` 该读它。
  private(set) var pending: DeepLink?

  init() {
    // 模拟器上 `xcrun simctl openurl` 递进来的链接，系统会先叠一层它自己的确认框
    // （「在 \"Hkline\" 中打开？」），自动化点不到那一下——那是 SpringBoard 的框，
    // 不是 app 的。所以测试档案下多认一条启动环境：`KANPAN_TEST_DEEPLINK`。
    // 它走的是和 `.onOpenURL` 一模一样的那条路（`open(_:)` → `MainScreen` 消费），
    // 不另开跳转路径；Release 包里这几行根本不编（审查 C.10-1）。
    #if DEBUG
    let env = ProcessInfo.processInfo.environment
    guard env["KANPAN_TEST_PROFILE"] == "1", let raw = env["KANPAN_TEST_DEEPLINK"],
          let url = URL(string: raw) else { return }
    open(url)
    #endif
  }

  /// 收一条链接。后来的顶掉先来的——人最后点的那一下才是他想去的地方。
  func open(_ link: DeepLink) { pending = link }

  /// 收一个 URL。认不出来就什么都不做，返回 false。
  @discardableResult
  func open(_ url: URL) -> Bool {
    guard let link = DeepLink.parse(url) else { return false }
    open(link)
    return true
  }

  /// 取走待办（取完就清）。
  func consume() -> DeepLink? {
    let link = pending
    pending = nil
    return link
  }
}

/// Handoff（P3.4）：行情页登记「我在看哪只、哪个周期」，另一台设备接力时化成
/// `hkline://symbol/<S>?interval=<i>` 那条深链，和桌面快捷入口、通知点击走同一个口。
///
/// userInfo 只放两个字符串，不放任何本机状态：接力的那台按自己的布局打开这张图。
enum ChartHandoff {
  /// 登记在 `Kanpan/Config/Info.plist` 的 `NSUserActivityTypes` 里。
  static let activityType = "com.mdd.kanpan.chart"
  static let symbolKey = "symbol"
  static let intervalKey = "interval"

  static func userInfo(symbol: String, interval: String) -> [String: String] {
    [symbolKey: symbol, intervalKey: interval]
  }

  /// 接力过来的那份 userInfo 拼成深链串，再交给 `DeepLink.parse` 按同一套规矩认。
  static func url(from userInfo: [AnyHashable: Any]) -> URL? {
    guard let symbol = userInfo[symbolKey] as? String, !symbol.isEmpty else { return nil }
    var c = URLComponents()
    c.scheme = DeepLink.scheme
    c.host = "symbol"
    c.path = "/" + symbol
    if let interval = userInfo[intervalKey] as? String, !interval.isEmpty {
      c.queryItems = [URLQueryItem(name: "interval", value: interval)]
    }
    return c.url
  }

  static func link(from userInfo: [AnyHashable: Any]) -> DeepLink? {
    url(from: userInfo).flatMap(DeepLink.parse)
  }
}
