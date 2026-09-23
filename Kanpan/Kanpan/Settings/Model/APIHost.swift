import Foundation
import KanpanNetwork

/// 默认交易所的出厂行情域名与测试网黑名单，app 这一侧的一份只读视图。
///
/// 从前这里还有一整套「自定义域名」：`Prefs.apiHost` / `streamHost`、形状校验、
/// 冷启动镜像 `LaunchHostMirror`、主屏上 `.onChange(of: endpoints)` 那条换域名的路。
/// 设置里的入口早就撤了，线路只剩直连 / 网关两档，主机一律由 `RouteResolver`
/// 按线路给（审查 18a），那一层 2026-09-24 整条删掉。留下的只有下面三个常量——
/// 真身在默认交易所的提供者里，这里不另起一份。
enum APIHost {
  /// 直连时默认交易所的 REST 域名。
  static let `default` = VenueRegistry.defaultRestHost
  /// 直连时默认交易所的推送域名。怎么选出来的（逐条实测）写在提供者那里。
  static let defaultStream = VenueRegistry.defaultStreamHost
  /// 不许再用的推送域名：不发成交 / K 线的旧主机，以及合约测试网（`*.binancefuture.com`）。
  /// 出厂值绝不能落在这张表里，`PrefsDefaultsTests` 钉着。
  static let legacyStreams = VenueRegistry.legacyStreamHosts
}
