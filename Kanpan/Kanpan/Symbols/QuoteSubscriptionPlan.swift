import Foundation

/// 页面切换不影响前台自选订阅；只订可见品种与收藏，最多64个，避免整市场广播。
enum QuoteSubscriptionPlan {
  static func symbols(favorites: [String], visible: Set<String>, limit: Int = 64) -> [String] {
    var seen = Set<String>()
    return Array((visible.sorted() + favorites).filter { seen.insert($0).inserted }.prefix(max(0, limit)))
  }
  static func needsConnection(foreground: Bool, favorites: [String], visible: Bool) -> Bool {
    foreground && (!favorites.isEmpty || visible)
  }
}
