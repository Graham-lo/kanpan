import Foundation
import Observation

/// 一个外来的「去哪儿」。
///
/// 桌面快捷入口、通知点击、朋友之间的共享链接，最后都化成这个枚举里的一条，
/// 由 `MainScreen` 一处消费（见 `71bd340:docs/提醒与体验细节-实施方案-2026-09-20.md` 第 1 节）。
/// **不要为某一个入口另开一条跳转路径**——那样同一个「打开 BTC 的 1 小时图」
/// 会在通知里和桌面图标里长成两套行为。
///
/// 两种壳子解析到同一个枚举：
///
///   hkline://symbol/BTCUSDT?interval=1h
///   hkline://drawing/BTCUSDT/<drawingID>
///   hkline://alerts
///   hkline://review/<recordID>
///   hkline://search
///   hkline://share/<id>
///   https://kanpan.107-174-172-10.sslip.io/s/<id>        （与上一条等价）
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
  /// 朋友共享的那张图。
  case share(id: String)

  /// 通用链接的主机。共享链接 `https://<host>/s/<id>` 只认这一个。
  static let webHost = "kanpan.107-174-172-10.sslip.io"
  /// 自定义 scheme。
  static let scheme = "hkline"

  /// 认不出来的一律返回 nil——宁可什么都不做，也不要猜一个「差不多」的地方打开。
  static func parse(_ url: URL) -> DeepLink? {
    guard let scheme = url.scheme?.lowercased() else { return nil }
    switch scheme {
    case Self.scheme: return app(url)
    case "https": return web(url)
    default: return nil
    }
  }

  // ---------------------------------------------------------------- 私有

  /// `hkline://` 那一族。第一段（URL 的 host）是去处，后面是参数。
  private static func app(_ url: URL) -> DeepLink? {
    let parts = segments(url)
    guard let route = parts.first?.lowercased() else { return nil }
    let rest = Array(parts.dropFirst())
    switch (route, rest.count) {
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
    case ("share", 1):
      guard !rest[0].isEmpty else { return nil }
      return .share(id: rest[0])
    default:
      return nil
    }
  }

  /// 通用链接。只有共享那一条，形态固定 `https://<webHost>/s/<id>`。
  private static func web(_ url: URL) -> DeepLink? {
    guard url.host?.lowercased() == webHost else { return nil }
    let parts = segments(url)
    guard parts.count == 2, parts[0].lowercased() == "s", !parts[1].isEmpty else { return nil }
    return .share(id: parts[1])
  }

  /// 把 host 和 path 揉成一串段。
  ///
  /// `hkline://alerts` 的 host 是 `alerts`、path 是空的；`https://…/s/x` 反过来，
  /// host 是域名、段全在 path 里——所以两族各自决定第一段从哪儿取：自定义 scheme
  /// 连 host 一起算，通用链接只算 path。
  private static func segments(_ url: URL) -> [String] {
    var parts: [String] = []
    if url.scheme?.lowercased() == Self.scheme, let host = url.host, !host.isEmpty { parts.append(host) }
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
    let upper = symbol.uppercased()
    guard (1...32).contains(upper.count) else { return nil }
    guard upper.allSatisfy({ $0.isASCII && ($0.isLetter || $0.isNumber) }) else { return nil }
    return upper
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
