import Foundation
import KanpanCore

/// App Group 里那份快照的读口。扩展只读不写：写的是 app（`WidgetFeed`），
/// 两边都写会让小组件拿一口旧价盖掉 app 刚写的新快照。
enum SnapshotStore {
  static func load() -> WidgetSnapshot? {
    guard let container = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: WidgetSnapshot.appGroup)
    else { return nil }
    return WidgetSnapshot.read(from: WidgetSnapshot.url(in: container))
  }
}
