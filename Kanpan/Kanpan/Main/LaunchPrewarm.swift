import Foundation
import KanpanData

/// 冷启动热身。
///
/// 第一笔行情请求要先付 DNS + TCP + TLS，再等数据；那几百毫秒全落在「点开
/// 到看见数字」中间。这里在界面还没起来的时候就先把连接握好——真正要数据时
/// 直接复用连接池里已经建好的那条。
///
/// 两个域名都要热：REST 拿首屏 K 线和整屏报价，推送拿实时。推送那条是
/// `URLSessionWebSocketTask`，不共用这里的 HTTP 连接，但 DNS 解析是全进程的，
/// 先解出来就少一跳。
///
/// 只热身直连域名。网关是线上服务，热身没必要往那儿打；直连不通时这两笔会
/// 自己超时失败，路由该怎么退还怎么退，不影响后面的选路。
@MainActor
enum LaunchPrewarm {
  private static var started = false

  static func run() {
    guard !started else { return }
    started = true
    guard ProcessInfo.processInfo.environment["KANPAN_TEST_PROFILE"] != "1" else { return }
    let prefs = PrefsStore.load(from: UserDefaults.standard)
    warm(host: prefs.apiHost, path: "/fapi/v1/ping", method: "GET")
    // 推送域名只要把 DNS 和 TLS 走通，回什么状态码都无所谓，所以用 HEAD。
    warm(host: prefs.streamHost, path: "/", method: "HEAD")
  }

  private static func warm(host: String, path: String, method: String) {
    guard host.range(of: "^[A-Za-z0-9.-]+(:[0-9]+)?$", options: .regularExpression) != nil,
          var parts = URLComponents(string: "https://" + host), parts.host != nil else { return }
    parts.path = path
    guard let url = parts.url else { return }
    Task.detached(priority: .utility) {
      var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 3)
      request.httpMethod = method
      request.setValue("kanpan-ios/1.0", forHTTPHeaderField: "User-Agent")
      _ = try? await URLSession.shared.data(for: request)
    }
  }
}
