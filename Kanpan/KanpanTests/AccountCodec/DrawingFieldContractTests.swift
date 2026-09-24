import Foundation
import Testing
import KanpanCore
import KanpanAccount
@testable import Kanpan

/// **一条画线在线上长什么样，只有一份：客户端 `Drawing` 的编码本身。**
///
/// 这件事过去被手抄了三遍：`Drawing.encode(to:)` 写哪些键（这里）、分享收件时收哪些键 /
/// 哪些必须在（`Backend/kanpan-api/src/share.rs` 的 `validate`）、个人同步收哪些键
/// （`sync.rs` 的 `DRAWING_FIELDS`），外加「每种工具几个锚点」（`Drawing.Kind.pointCount`
/// 与 `sync_validation.rs` 的 `anchor_count`）。四份各自看都「没错」，只有放在一起比才看得出漂移；
/// 而服务端对含未知字段、缺必需字段、点数不对的画线都是**整条拒绝**——新加一个编码键或一把
/// 三点工具而服务端没跟上，那条线就永远发不出去、分享也被 400 顶回来。
///
/// 现在中间放了一个机器可读的产物 `Backend/kanpan-api/contract/drawing-fields.json`：
/// 它由这里的 `DrawingFieldContract` **拿真实的 `Drawing` 与 `PersonalSyncCodec.drawings`
/// 编码出来的键**生成（`make sync-contract`），不是再抄一遍名字。Swift 这边跟它逐项对账，
/// Rust 那边 `include_str!` 读同一份对账（`share.rs` / `sync.rs` / `sync_validation.rs` 的测试）。
///
/// 这条红了**不要改契约文件**（它是生成物），改 `Drawing` 再跑 `make sync-contract`。
@Suite("画线字段契约：Drawing 编码是唯一一份")
struct DrawingFieldContractTests {
  @Test("契约文件就是 Drawing 今天编出来的那一份")
  func theDrawingContractFileIsWhatDrawingEncodes() throws {
    let rendered = try DrawingFieldContract.rendered()
    if DrawingFieldContract.isWriting {
      try DrawingFieldContract.write(rendered)
      return
    }
    let onDisk = try DrawingFieldContract.readFromDisk()
    let contract = try DrawingFieldContract.decode(onDisk)
    let fresh = try DrawingFieldContract.generated()
    let hint = "契约是生成物：改 Drawing，然后在仓库根跑 `make sync-contract`，再让 cargo test 告诉服务端还差什么。"

    #expect(contract.shareFields == fresh.shareFields, """
      分享线上的画线键和契约对不上：编码会写、契约没有 \(Set(fresh.shareFields).subtracting(contract.shareFields).sorted())，
      契约有、编码不写 \(Set(contract.shareFields).subtracting(fresh.shareFields).sorted())。\(hint)
      """)
    #expect(contract.shareRequiredFields == fresh.shareRequiredFields, "每条画线必带的键变了。\(hint)")
    #expect(contract.renamed == fresh.renamed, "分享 → 同步的改名表变了。\(hint)")
    #expect(contract.syncFields == fresh.syncFields, """
      个人同步的画线 body 键和契约对不上：会发、契约没有 \(Set(fresh.syncFields).subtracting(contract.syncFields).sorted())，
      契约有、不发 \(Set(contract.syncFields).subtracting(fresh.syncFields).sorted())。\(hint)
      """)
    #expect(contract.legacySyncFields == fresh.legacySyncFields, "只在线上存在的老键变了。\(hint)")
    #expect(contract.anchorCounts == fresh.anchorCounts, """
      锚点数对不上：\(fresh.anchorCounts.filter { contract.anchorCounts[$0.key] != $0.value }.keys.sorted())。\(hint)
      """)
    // 逐项之后再整篇比一次，兜住说明文字与格式的漂移。
    #expect(onDisk == rendered, "契约文件和生成结果逐字不同（多半是说明文字改了）。\(hint)")
  }

  /// 分享和同步是同一条画线的两种包法：分享原样发 `Drawing` 的编码（带 `id`、叫 `points`），
  /// 同步去掉 `id`、`points` 改名 `anchors`、再补身份三键。服务端 `share.rs` 就是照这个关系把分享
  /// 那份改包成同步那份、交给同一套值规则的——这里证明这个关系在客户端也确实成立。
  @Test("分享那份改个名、补上身份三键，就是同步那份")
  func sharePlusIdentityIsTheSyncBody() throws {
    let contract = try DrawingFieldContract.generated()
    let renamed = contract.shareFields.map { contract.renamed[$0] ?? $0 }
    #expect(Set(renamed).union(DrawingFieldContract.identityKeys) == Set(contract.syncFields))
    #expect(Set(contract.shareRequiredFields).isSubset(of: contract.shareFields))
    #expect(!contract.shareFields.contains("id"), "id 是对象的键，不是 body 的键")
  }
}

enum DrawingFieldContract {
  static let relativePath = "Backend/kanpan-api/contract/drawing-fields.json"
  /// 字段含义变了才 +1，两边的读法都要跟着改。
  static let version = 1
  static var isWriting: Bool { ProcessInfo.processInfo.environment["KANPAN_WRITE_SYNC_CONTRACT"] == "1" }
  /// `PersonalSyncCodec.drawings` 给每条画线补的身份三键（分享那份没有，服务端从信封上的品种补）。
  static let identityKeys: Set<String> = ["symbol", "market", "venue"]

  struct Document: Codable, Equatable {
    var version: Int
    var whatThisIs: String
    var generatedFrom: String
    var generatedBy: String
    var howToRegenerate: String
    var shareFieldsNote: String
    var shareFields: [String]
    var shareRequiredFieldsNote: String
    var shareRequiredFields: [String]
    var renamedNote: String
    var renamed: [String: String]
    var syncFieldsNote: String
    var syncFields: [String]
    var legacySyncFieldsNote: String
    var legacySyncFields: [String: String]
    var anchorCountsNote: String
    var anchorCounts: [String: Int]
  }

  /// 仓库根：`<root>/Kanpan/KanpanTests/AccountCodec/<本文件>` 往上退四层。
  static var repositoryRoot: URL {
    var url = URL(fileURLWithPath: #filePath)
    for _ in 0..<4 { url.deleteLastPathComponent() }
    return url
  }
  static var fileURL: URL { repositoryRoot.appendingPathComponent(relativePath) }

  /// 每种工具各一条、点数正好的样本。`full` 把可选键（颜色、文字）都填上，求并集得「可能出现的键」；
  /// 不填时求交集得「每条都带的键」。
  private static func samples(full: Bool) -> [Drawing] {
    Drawing.Kind.allCases.map { kind in
      var drawing = Drawing(
        id: "c-\(kind.rawValue)", kind: kind,
        points: (0..<kind.pointCount).map { DrawPoint(t: 1_800_000_000_000 + Double($0) * 60_000, p: 100 + Double($0)) })
      if full { drawing.color = Hex("#112233"); drawing.text = "x" }
      return drawing
    }
  }

  private static func keys(_ drawing: Drawing) throws -> Set<String> {
    Set(try KanpanAccount.JSONValue.encode(drawing).decode([String: KanpanAccount.JSONValue].self).keys)
  }

  private static func syncKeys(_ drawings: [Drawing]) throws -> Set<String> {
    let archive = DrawArchive(bySymbol: ["BTCUSDT": drawings])
    return try PersonalSyncCodec.drawings(archive).filter { $0.collection == "drawings" }
      .reduce(into: Set<String>()) { $0.formUnion($1.body.keys) }
  }

  static func generated() throws -> Document {
    let full = try samples(full: true).map(keys)
    let bare = try samples(full: false).map(keys)
    let any = full.reduce(into: Set<String>()) { $0.formUnion($1) }
    let always = bare.dropFirst().reduce(bare.first ?? []) { $0.intersection($1) }
    return Document(
      version: version,
      whatThisIs: "iOS 与 Rust 后端之间「一条画线在线上长什么样」的唯一权威副本："
        + "分享收哪些键、哪些必须在，个人同步收哪些键，每种工具几个锚点。",
      generatedFrom: "KanpanCore/Drawing/Drawing.swift · Drawing.encode(to:) 与 Drawing.Kind.pointCount；"
        + "Kanpan/Kanpan/Account/PersonalSyncCodec.swift · PersonalSyncCodec.drawings",
      generatedBy: "Kanpan/KanpanTests/AccountCodec/DrawingFieldContractTests.swift · DrawingFieldContract",
      howToRegenerate: "这是生成物，不要手改。改 Drawing 的编码或 Kind，然后在仓库根跑 `make sync-contract`。"
        + "两边的测试自动对账：KanpanTests 的 theDrawingContractFileIsWhatDrawingEncodes，"
        + "Backend/kanpan-api 的 share_fields_are_what_drawing_encodes、drawing_fields_are_what_the_codec_sends "
        + "与 anchor_counts_are_the_clients_point_counts。",
      shareFieldsNote: "分享（POST /v1/shares）里每条画线可能出现的键，就是 Drawing 编码会写的键去掉 id"
        + "（id 服务端单独校验）。share.rs 的 SHARE_FIELDS 必须逐字等于它：多一个编码键而服务端不认，整次分享 400。",
      shareFields: any.subtracting(["id"]).sorted(),
      shareRequiredFieldsNote: "每条画线都一定会写的键（去掉 id）。share.rs 的 SHARE_REQUIRED 必须逐字等于它："
        + "服务端多要一个客户端不一定写的键，没带那个键的分享整次 400。",
      shareRequiredFields: always.subtracting(["id"]).sorted(),
      renamedNote: "分享用 Drawing 自己的键名，个人同步把它们改成线上的名字；服务端 share.rs 照这张表改包后交给同一套值规则。",
      renamed: ["points": "anchors"],
      syncFieldsNote: "个人同步 drawings 集合里客户端会发的 body 键：shareFields 按 renamed 改名，再补 symbol / market / venue。"
        + "sync.rs 的 DRAWING_FIELDS 必须等于它加上 legacySyncFields。",
      syncFields: try syncKeys(samples(full: true)).sorted(),
      legacySyncFieldsNote: "服务端还认、今天的客户端不再发的键，以及为什么留着。",
      legacySyncFields: ["created": "老存档随画线带的创建时刻；老客户端推上来的那份不能因为它被整条拒绝"],
      anchorCountsNote: "Drawing.Kind 的 rawValue → 画完的一条线带几个锚点（pointCount）。"
        + "sync_validation.rs 的 anchor_count 必须逐项等于它，KINDS 也必须正好是这些键："
        + "点数不对的画线服务端整条拒绝，那把工具画的线就永远离不开这台手机。",
      anchorCounts: Dictionary(uniqueKeysWithValues: Drawing.Kind.allCases.map { ($0.rawValue, $0.pointCount) })
    )
  }

  static func rendered() throws -> String {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
    return String(decoding: try encoder.encode(generated()), as: UTF8.self) + "\n"
  }

  static func write(_ text: String) throws {
    try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
    try text.write(to: fileURL, atomically: true, encoding: .utf8)
    print("sync-contract: 已从 Drawing 的编码重新生成 \(relativePath)")
  }

  static func readFromDisk() throws -> String {
    guard FileManager.default.fileExists(atPath: fileURL.path) else { throw ContractError.missingFile(fileURL.path) }
    return try String(contentsOf: fileURL, encoding: .utf8)
  }

  static func decode(_ text: String) throws -> Document {
    let document: Document
    do { document = try JSONDecoder().decode(Document.self, from: Data(text.utf8)) }
    catch { throw ContractError.unreadable("\(error)") }
    guard document.version == version else { throw ContractError.wrongVersion(document.version) }
    return document
  }

  enum ContractError: Error, CustomStringConvertible {
    case missingFile(String)
    case unreadable(String)
    case wrongVersion(Int)
    var description: String {
      switch self {
      case .missingFile(let path): "契约文件不在：\(path)。在仓库根跑 `make sync-contract` 生成。"
      case .unreadable(let why): "契约文件读不懂（\(why)）。它是生成物，跑 `make sync-contract` 重新生成。"
      case .wrongVersion(let v): "契约文件是 v\(v)，这边读的是 v\(DrawingFieldContract.version)：两边读法要一起改。"
      }
    }
  }
}
