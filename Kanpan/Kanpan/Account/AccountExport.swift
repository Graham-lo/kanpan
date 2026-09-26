import Foundation
import KanpanAccount

/// 「导出我的数据」（P3.6）：向服务端要这个人的全部个人数据，落成一份 JSON，
/// 交给系统分享面板——存到「文件」、AirDrop、发邮件都由用户自己挑。
///
/// 服务端 `GET /v1/auth/me/export` 回的是 `{"data":{…}}` 信封，文件里只放信封里那一层
/// （`format: hkline-export-1`），用户拿到的就是自己的数据，不带我们的传输外壳。
/// 文件名带日期：同一天导两次覆盖成一份，不在临时目录里越堆越多。
extension AccountFeature {
  func exportData() {
    guard let client, !exporting else { return }
    exporting = true; error = nil
    // 导出要几秒。这中间退了登（或换了号），回来的是上一个人的全部数据：
    // 不落盘、不弹分享面板，客户端作废旧请求抛的错也不念。
    let started = generation
    Task {
      defer { exporting = false }
      do {
        let raw = try await client.data("v1/auth/me/export")
        guard started == generation else { return }
        // 解开、排版、落盘挪出主线程：服务端导出上限 20 MB（`export.rs`），整份解成对象树
        // 再排版写回，M4 上就要 0.4–0.5 秒、排出来四十多 MB；这个 Task 继承主线程，
        // 原来就在主线程上做，手机上整屏卡住将近一秒。
        let url = try await Task.detached(priority: .userInitiated) { try Self.writeExport(raw) }.value
        guard started == generation else { return }
        ChartSnapshotRenderer.present(url)
      } catch {
        if started == generation { show(error) }
      }
    }
  }

  nonisolated static func writeExport(_ raw: Data, now: Date = Date()) throws -> URL {
    guard let envelope = try JSONSerialization.jsonObject(with: raw) as? [String: Any],
          let body = envelope["data"] as? [String: Any] else { throw AccountError.invalidResponse }
    let data = try JSONSerialization.data(withJSONObject: body, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes])
    let day = now.formatted(.iso8601.year().month().day().dateSeparator(.omitted))
    let url = FileManager.default.temporaryDirectory.appendingPathComponent("Hkline-我的数据-\(day).json")
    try data.write(to: url, options: .atomic)
    return url
  }
}
