import Foundation
import KanpanCore

/// 小组件快照在磁盘上的那一份：App Group 容器里的一个 JSON 文件。
///
/// app 刷到行情就写（`Kanpan/Kanpan/Widget/WidgetFeed.swift`），小组件扩展只读
/// （`Kanpan/KanpanWidget/SnapshotStore.swift`）。这个文件同时同步进 app 与扩展两个 target，
/// 两边认的是同一个容器、同一个文件名。快照的内容与挑行逻辑是 Core 里的纯值 `WidgetSnapshot`；
/// 从前连这几行读写也放在 Core，审查 24 把文件 IO 与 App Group 请了出来。
extension WidgetSnapshot {
  static let appGroup = "group.com.mdd.kanpan"
  static let fileName = "widget-snapshot.json"

  static func url(in container: URL) -> URL { container.appendingPathComponent(fileName) }

  static func read(from url: URL) -> WidgetSnapshot? {
    guard let data = try? Data(contentsOf: url) else { return nil }
    return try? JSONDecoder().decode(WidgetSnapshot.self, from: data)
  }

  func write(to url: URL) throws {
    let data = try JSONEncoder().encode(self)
    try data.write(to: url, options: .atomic)
  }
}
