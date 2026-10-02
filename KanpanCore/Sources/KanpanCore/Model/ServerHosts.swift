import Foundation

/// 自家服务器的地址，全客户端只有这一份。
///
/// 2026-10-02 起主机换成新加坡那台（腾讯云，币安 / Bybit / OKX 都不封它；美国那台被币安 451、
/// 到国内的链路又慢）。同日用户定：客户端**只连新加坡，不再有任何兜底**——美国两台都不再对
/// 客户端提供服务（主机只是编译机 + 离机备份，备机只收离机备份），旧主机名也不代理了。
/// 以前备机做行情网关兜底，是因为美国主机一个人撑着；现在那条备用线路本身就比新加坡慢，切过去只会更差。
///
/// 以前同一对主机名抄了三处：行情网关表（`MarketEndpoints.production`）、账号客户端的
/// 放行名单（`AccountClient.allowedHosts`）、app 的 Info.plist（`KanpanAccountAPIURL`）。
/// 换一台机器要改三处，漏改一处的后果还不一样：网关表漏了是连不上，放行名单漏了是
/// 登录一律被拒（审查 2026-09-24 §2）。现在三处都从这里取。
///
/// 只有一台：行情网关与 kanpan-api 完整版（账号、订单流的品种表 / 深度快照 / 币安与 OKX 中继、
/// 板块历史、元数据、持仓量）都在它上面。**没有**故障转移：主机挂了登录 / 同步 / 订单流就暂停，
/// 本地缓存照常能用（`kanpan-cloud-outage-must-not-break-the-app`）。
public enum ServerHosts {
  /// 主机（新加坡）：行情网关 + 账号 API，走 443。
  public static let primary = "kanpan.43-160-232-253.sslip.io"

  /// 行情网关表（`MarketEndpoints.production`）。只有主机一台；表仍是数组，因为线路层按表遍历。
  public static let gateways: [String] = [primary]

  /// kanpan-api 完整版所在的主机（`MarketRoute.apiHosts`）。只有主机一台（2026-10-02 起没有备机）。
  public static let api: [String] = [primary]

  /// 账号客户端认的主机名与端口。地址写错一个字母就是把 refresh 令牌递给别人，
  /// 所以 `AccountClient` 只认这张名单，不认「看起来像 https」。
  public static let names: Set<String> = [primary]
  public static let ports: Set<Int> = [443]

  /// 账号 API 的根地址（也是法律文本、分享等自家页面的根）。
  public static let accountAPI: URL = {
    var parts = URLComponents()
    parts.scheme = "https"
    parts.host = primary
    guard let url = parts.url else { preconditionFailure("ServerHosts.primary 不是合法主机名") }
    return url
  }()
}
