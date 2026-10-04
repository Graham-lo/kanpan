import Foundation
import KanpanAccount

/// 「导出我的数据」（P3.6）：向服务端要这个人的全部个人数据，落成一份 JSON，
/// 交给系统分享面板——存到「文件」、AirDrop、发邮件都由用户自己挑。
///
/// 服务端 `GET /v1/auth/me/export` 回的是 `{"data":{…}}` 信封，文件里只放信封里那一层
/// （`format: hkline-export-1`），用户拿到的就是自己的数据，不带我们的传输外壳。
/// 文件名带日期。
///
/// 这份文件是这个人**全部**的个人数据，所以它在本机只活到分享面板收起为止（审查 D-08）：
/// 落在临时目录下专用的 `hkline-export/` 里、带 `.completeFileProtection`（锁屏就读不了）；
/// 面板收起当场删，下一次导出、登录 / 退登、冷启动时再把整个目录清一遍兜底。原来它就躺在
/// tmp 根上、只有默认保护，退了登、换了号也一直留着——同一台机器上的下一个人照样翻得到。
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
        ChartSnapshotRenderer.present(url) { Self.purgeExports() }
      } catch {
        if started == generation { show(error) }
      }
    }
  }

  /// 导出文件专用的目录。只放导出，整个删掉不会误伤任何别的东西。
  nonisolated static var exportDirectory: URL {
    FileManager.default.temporaryDirectory.appendingPathComponent("hkline-export", isDirectory: true)
  }
  /// 把本机留着的导出文件全删掉。导出是一次性的东西，删了随时可以再导一份。
  nonisolated static func purgeExports() {
    try? FileManager.default.removeItem(at: exportDirectory)
  }

  nonisolated static func writeExport(_ raw: Data, now: Date = Date()) throws -> URL {
    guard let envelope = try JSONSerialization.jsonObject(with: raw) as? [String: Any],
          let body = envelope["data"] as? [String: Any] else { throw AccountError.invalidResponse }
    let data = try JSONSerialization.data(withJSONObject: body, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes])
    let day = now.formatted(.iso8601.year().month().day().dateSeparator(.omitted))
    // 上一次导出的（可能是上一个人的）先清掉，目录里永远最多只有眼下这一份。
    purgeExports()
    try FileManager.default.createDirectory(at: exportDirectory, withIntermediateDirectories: true)
    let url = exportDirectory.appendingPathComponent("Hkline-我的数据-\(day).json")
    try data.write(to: url, options: [.atomic, .completeFileProtection])
    return url
  }
}
