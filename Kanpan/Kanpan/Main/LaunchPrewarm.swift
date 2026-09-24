import Foundation
import KanpanNetwork

/// 冷启动热身。
///
/// 第一笔行情请求要先付 DNS + TCP + TLS，再等数据；那几百毫秒全落在「点开
/// 到看见数字」中间。这里在界面还没起来的时候就先把连接握好——真正要数据时
/// 直接复用连接池里已经建好的那条。
///
/// 热哪几台由当前线路定（`MarketProvider.prewarmTargets`，审查 14）：直连热交易所的
/// REST 与推送域名；网关线路热那两台网关——之前网关用户热的是直连域名，白握一次手，
/// 真正要连的那台反倒是冷的。推送是 `URLSessionWebSocketTask`，不共用这里的 HTTP
/// 连接，但 DNS 解析是全进程的，先解出来就少一跳。
///
/// 线路只记在本机（`MarketRoutePolicyStore`），这一刻不用等账号档案就读得到。
@MainActor
enum LaunchPrewarm {
  private static var started = false

  static func run() {
    guard !started else { return }
    started = true
    // 品牌标表从资源文件解（`CoinSpec.brandFile`，模拟器上冷读约 3 ms）。第一屏的徽章
    // 马上就要查它，先在后台解好，主线程第一次查表时就是现成的。纯本地，不碍测试。
    Task.detached(priority: .userInitiated) { _ = CoinSpec.brandFile }
    // 测试模式下不热身（UI 用例不该为两笔无认证预热等网络）。Release 包里没有这回事。
    #if DEBUG
    guard ProcessInfo.processInfo.environment["KANPAN_TEST_PROFILE"] != "1" else { return }
    #endif
    for target in RouteResolver.current.defaultProvider.prewarmTargets {
      warm(target)
    }
  }

  private static func warm(_ target: PrewarmTarget) {
    let url = target.url, method = target.method
    Task.detached(priority: .utility) {
      var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 3)
      request.httpMethod = method
      request.setValue("kanpan-ios/1.0", forHTTPHeaderField: "User-Agent")
      _ = try? await URLSession.shared.data(for: request)
    }
  }
}
