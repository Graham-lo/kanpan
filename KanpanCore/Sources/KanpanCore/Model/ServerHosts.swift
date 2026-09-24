import Foundation

/// 自家服务器（美国那两台 VPS）的地址，全客户端只有这一份。
///
/// 以前同一对主机名抄了三处：行情网关表（`MarketEndpoints.production`）、账号客户端的
/// 放行名单（`AccountClient.allowedHosts`）、app 的 Info.plist（`KanpanAccountAPIURL`）。
/// 换一台机器要改三处，漏改一处的后果还不一样：网关表漏了是连不上，放行名单漏了是
/// 登录一律被拒（审查 2026-09-24 §2）。现在三处都从这里取。
///
/// 两台的分工：行情网关主在前、备在后，`RouteResolver` 会在两台之间切；
/// kanpan-api 的完整版（账号、订单流的品种表 / 深度快照 / 币安与 OKX 中继、板块历史、元数据、
/// 持仓量）只在主机上——备机跑的是 kanpan-api 的 metrics 模式，只有 `/oi/v1/metrics/*` 与
/// `/v1/market/{raw,stream,funding,ticker,open-interest/history}`，别的 `/v1/*` 一律 404
/// （2026-09-24 实测）。所以这些**没有**故障转移，主机挂了登录 / 同步 / 订单流就暂停，
/// 本地缓存照常能用（`kanpan-cloud-outage-must-not-break-the-app`）。
public enum ServerHosts {
  /// 主机（纽约）：行情网关 + 账号 API，走 443。
  public static let primary = "kanpan.107-174-172-10.sslip.io"
  /// 备机：只做行情网关，走 8443。
  public static let backup = "kanpan.96-44-162-222.sslip.io"
  static let backupPort = 8443

  /// 行情网关，主在前、备在后（`MarketEndpoints.production`）。
  public static let gateways: [String] = [primary, "\(backup):\(backupPort)"]

  /// kanpan-api 完整版所在的主机（`MarketRoute.apiHosts`）。只有主机：备机上这些路径都是 404，
  /// 列进来只会让每次主机失败时再白等一次 404。
  public static let api: [String] = [primary]

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
