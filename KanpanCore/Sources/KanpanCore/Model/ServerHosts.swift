import Foundation

/// 自家服务器（美国那两台 VPS）的地址，全客户端只有这一份。
///
/// 以前同一对主机名抄了三处：行情网关表（`MarketEndpoints.production`）、账号客户端的
/// 放行名单（`AccountClient.allowedHosts`）、app 的 Info.plist（`KanpanAccountAPIURL`）。
/// 换一台机器要改三处，漏改一处的后果还不一样：网关表漏了是连不上，放行名单漏了是
/// 登录一律被拒（审查 2026-09-24 §2）。现在三处都从这里取。
///
/// 两台的分工：行情网关主在前、备在后，`RouteResolver` 会在两台之间切；
/// 账号 API 只走主机——账号库只在主机上，备机没有账号服务，所以账号**没有**故障转移，
/// 主机挂了登录 / 同步就暂停，本地缓存照常能用（`kanpan-cloud-outage-must-not-break-the-app`）。
public enum ServerHosts {
  /// 主机（纽约）：行情网关 + 账号 API，走 443。
  public static let primary = "kanpan.107-174-172-10.sslip.io"
  /// 备机：只做行情网关，走 8443。
  public static let backup = "kanpan.96-44-162-222.sslip.io"
  static let backupPort = 8443

  /// 行情网关，主在前、备在后（`MarketEndpoints.production`）。
  public static let gateways: [String] = [primary, "\(backup):\(backupPort)"]

  /// 账号客户端认的主机名与端口。地址写错一个字母就是把 refresh 令牌递给别人，
  /// 所以 `AccountClient` 只认这张名单，不认「看起来像 https」。
  public static let names: Set<String> = [primary, backup]
  public static let ports: Set<Int> = [443, backupPort]

  /// 账号 API 的根地址（也是法律文本、分享等自家页面的根）。
  public static let accountAPI: URL = {
    var parts = URLComponents()
    parts.scheme = "https"
    parts.host = primary
    guard let url = parts.url else { preconditionFailure("ServerHosts.primary 不是合法主机名") }
    return url
  }()
}
