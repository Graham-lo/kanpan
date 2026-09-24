import Foundation

/// 一份复盘档案在盘上的全部位置。
///
/// 以前这几个文件名散在三处各写一遍：`ReviewStore.init` 拼主档 / 草稿 / 进度 / 图，
/// `AppAccountBridge.migrateLegacy` 又手抄了一份 `["review-v1.json", "draft-v1.json",
/// "replay-positions.json"]` 去搬老目录，`ReviewFeature.init` 再自己拼一个 `local/`。
/// 改一处漏一处就是「升级之后草稿没了」那一类 bug。现在只认这一份。
public struct ReviewPaths: Sendable, Equatable {
  /// 这份档案的目录（账号目录或访客目录）。
  public let directory: URL
  public init(directory: URL) { self.directory = directory }

  /// 主档：记录 + 待发队列（只放 id 与小 body，不放图）。
  public var archive: URL { directory.appendingPathComponent(Self.archiveName) }
  /// 写了一半的那条草稿。
  public var draft: URL { directory.appendingPathComponent(Self.draftName) }
  /// 每条记录重温到哪一根。
  public var replay: URL { directory.appendingPathComponent(Self.replayName) }
  /// 「记一笔」那张图，一条记录一张，文件名就是记录 id。
  public var shots: URL { directory.appendingPathComponent("shots", isDirectory: true) }
  public func shot(_ id: UUID) -> URL { shots.appendingPathComponent(id.uuidString + ".png") }

  public static let archiveName = "review-v1.json"
  public static let draftName = "draft-v1.json"
  public static let replayName = "replay-positions.json"
  /// 一份档案的三个 JSON 文件。老目录搬家（`migrateLegacy`）按这张表搬，一个都不许漏：
  /// 草稿和重温进度是纯粹的用户产出，不是能重算的缓存。
  public static let files = [archiveName, draftName, replayName]

  /// 账号化之前那一份「本机复盘」住在哪儿：复盘根目录下的 `local/`。
  /// 现在只有迁移还读它，app 运行时不再在这里开档案。
  public static func legacy(in root: URL) -> ReviewPaths {
    ReviewPaths(directory: root.appendingPathComponent("local", isDirectory: true))
  }
}
