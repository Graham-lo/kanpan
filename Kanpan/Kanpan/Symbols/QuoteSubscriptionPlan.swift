import Foundation

/// 页面切换不影响前台自选订阅；只订可见品种与收藏，最多64个，避免整市场广播。
enum QuoteSubscriptionPlan {
  /// `alerted` 是**挂着活动提醒**的那些品种，它们不占那 64 个名额、也不会被裁掉。
  ///
  /// 理由：前台的到价判定（`AlertEngine`）只能判盘上有价的品种。一条画在
  /// ETHUSDT 上的提醒，用户正在看 BTCUSDT、而 ETHUSDT 又不在自选里的话，
  /// 没有这一条它就一辈子不会响——而这个项目没有 APNs 密钥，前台这条路是唯一的。
  /// 数量有上限（`AlertArchive.limit`），而且提醒本来就是用户点名要盯的东西。
  static func symbols(favorites: [String], visible: Set<String>,
                      alerted: Set<String> = [], limit: Int = 64) -> [String] {
    var seen = Set<String>()
    var out = Array((visible.sorted() + favorites).filter { seen.insert($0).inserted }.prefix(max(0, limit)))
    for symbol in alerted.sorted() where seen.insert(symbol).inserted { out.append(symbol) }
    return out
  }
  static func needsConnection(foreground: Bool, favorites: [String], visible: Bool,
                              alerted: Set<String> = []) -> Bool {
    foreground && (!favorites.isEmpty || visible || !alerted.isEmpty)
  }
}
