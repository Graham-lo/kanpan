import Foundation
import os
import ReviewDomain
import KanpanCore

// 交易复盘（`kind:"trade"`）的线上接口与本地那一份（协议 `docs/交易复盘-协议-2026-09-27.md` §3）。
//
// 回合本身住在 app 那一侧（按设备、按交易所账户拼出来的，见 `ExchangeReviewBridge`），
// 这里只管「服务端那份」：传上去、拉回来（带服务端算好的结果）、写那一句备注。
// 本地这份是按账号分目录的侧文件 `trades-v1.json`，和观点的 `review-v1.json` 同一个目录、
// 互不干扰：只记服务端给回来的记录、哪一版已经传过、哪一版被拒过、正在发的那一批的幂等键。
// **不存交易所的 Key、Key 尾号、水位**——那几样只在设备的钥匙串和交易所模块自己的状态文件里。

public struct TradeListResponse: Codable, Sendable {
  public var records: [TradeRecord]
  public var next: String?
  public init(records: [TradeRecord], next: String?) { self.records = records; self.next = next }
}
struct TradeRecordsEnvelope: Codable, Sendable { var records: [TradeRecord] }
struct TradeRecordEnvelope: Codable, Sendable { var record: TradeRecord }

extension ScorebookClient {
  /// `POST /v1/native-review/trades`：一批最多 100 个回合，整批要么全收要么全拒。
  /// 同一批（同样的回合、同样的版本）重发带同一个 `key`，服务端原样回放。
  public func uploadTrades(_ rounds: [TradeRound], key: UUID) async throws -> [TradeRecord] {
    struct Body: Encodable { var rounds: [TradeRound] }
    let body = try JSONEncoder().encode(Body(rounds: rounds))
    let value: TradeRecordsEnvelope = try await request("v1/native-review/trades", method: "POST", body: body, key: key)
    return value.records
  }
  /// `GET /v1/native-review/records?kind=trade`：一页 50 条，持仓中的在前，其余按平仓时间倒序。
  public func tradeList(after: String? = nil) async throws -> TradeListResponse {
    var parts = URLComponents()
    var items = [URLQueryItem(name: "kind", value: "trade")]
    if let after { items.append(URLQueryItem(name: "after", value: after)) }
    parts.queryItems = items
    return try await request("v1/native-review/records" + (parts.string ?? ""))
  }
  /// 一条的最新样子（服务端的结果随时可能回写，详情页打开时拉这一次）。
  public func tradeDetail(_ id: String) async throws -> TradeRecord {
    let value: TradeRecordEnvelope = try await request("v1/native-review/records/\(id)")
    return value.record
  }
  /// 「当时怎么想」。`expectedRevision` 对不上回 409 `record_revision_changed`；空字串就是清掉。
  public func tradeNote(id: String, expectedRevision: Int, text: String, key: UUID) async throws -> TradeRecord {
    struct Body: Encodable { var expectedRevision: Int; var text: String }
    let body = try JSONEncoder().encode(Body(expectedRevision: expectedRevision, text: text))
    let value: TradeRecordEnvelope = try await request("v1/native-review/trades/\(id)/note", method: "POST", body: body, key: key)
    return value.record
  }
}

/// 本地那一份交易复盘（按账号）。
public struct TradeArchive: Codable, Sendable, Equatable {
  public struct PendingBatch: Codable, Sendable, Equatable {
    public var key: UUID
    public var fingerprint: String
    public init(key: UUID, fingerprint: String) { self.key = key; self.fingerprint = fingerprint }
  }
  public var version = 1
  /// 服务端给回来的记录（带结果、备注），以服务端为准。
  public var records: [TradeRecord] = []
  /// 回合 id → 服务端手上那一版的 `updatedAt`。本地回合的 `updatedAt` 比它新才要再传（审查 R11）。
  public var uploaded: [String: Int64] = [:]
  /// 回合 id → 被服务端拒掉的那一版。同一版不再传；回合一变（新成交）就会再试。
  public var rejected: [String: Int64] = [:]
  /// 正在发的那一批：同一批重发必须带同一个幂等键（发出去了但没收到回应的情形）。
  public var pending: PendingBatch?
  public init() {}

  private enum CodingKeys: String, CodingKey { case version, records, uploaded, rejected, pending }
  public init(from decoder: any Decoder) throws {
    let c = try decoder.container(keyedBy: CodingKeys.self)
    version = try c.decodeIfPresent(Int.self, forKey: .version) ?? 1
    records = try c.decodeIfPresent([TradeRecord].self, forKey: .records) ?? []
    uploaded = try c.decodeIfPresent([String: Int64].self, forKey: .uploaded) ?? [:]
    rejected = try c.decodeIfPresent([String: Int64].self, forKey: .rejected) ?? [:]
    pending = try c.decodeIfPresent(PendingBatch.self, forKey: .pending)
  }

  /// 把服务端给回来的几条并进来（同 id 以 `revision` 高的为准）。
  public mutating func merge(_ incoming: [TradeRecord]) {
    var index = Dictionary(uniqueKeysWithValues: records.enumerated().map { ($1.id, $0) })
    for record in incoming {
      if let at = index[record.id] {
        if record.revision >= records[at].revision { records[at] = record }
      } else {
        index[record.id] = records.count
        records.append(record)
      }
      uploaded[record.id] = max(uploaded[record.id] ?? .min, record.round.updatedAt)
    }
  }

  /// 这一版传上去了。只往大里记：服务端回来的那份（`merge` 刚记下的）可能比这一版还新
  /// （另一台设备传过更新的），记回这一版就又会被判成待传（审查 R11）。
  public mutating func markUploaded(_ round: TradeRound) {
    uploaded[round.id] = max(uploaded[round.id] ?? .min, round.updatedAt)
    rejected[round.id] = nil
  }
}

@MainActor public final class TradeReviewStore {
  public static let fileName = "trades-v1.json"
  public private(set) var archive: TradeArchive
  public let url: URL
  /// 读写这份侧文件出的岔子只记日志、不打断复盘（审查 R22）：原来全是 `try?`，
  /// 写盘失败一点痕迹都没有，记账丢了（重传、幂等键没落盘）时无从查起。
  nonisolated private static let log = Logger(subsystem: "com.kanpan.app", category: "trade-review")

  /// 解不动就留一份 `.backup` 从空档开始：这里面全是服务端那份的缓存与记账，
  /// 丢了最多是重传一遍、重拉一遍（幂等），不值得让整个复盘打不开。
  public init(directory: URL) {
    url = directory.appendingPathComponent(Self.fileName)
    if let data = try? Data(contentsOf: url) {
      do {
        let value = try JSONDecoder().decode(TradeArchive.self, from: data)
        guard value.version == 1 else { throw CocoaError(.coderInvalidValue) }
        archive = value
      } catch {
        Self.log.error("交易复盘档解不开，另存 .backup 后从空档开始：\(String(describing: error), privacy: .public)")
        let backup = url.appendingPathExtension("backup")
        if !FileManager.default.fileExists(atPath: backup.path) {
          do { try FileManager.default.copyItem(at: url, to: backup) } catch {
            Self.log.error("交易复盘档另存 .backup 失败：\(String(describing: error), privacy: .public)")
          }
        }
        archive = TradeArchive()
      }
    } else { archive = TradeArchive() }
  }
  public convenience init(paths: ReviewPaths) { self.init(directory: paths.directory) }

  public func update(_ edit: (inout TradeArchive) -> Void) {
    var next = archive
    edit(&next)
    guard next != archive else { return }
    archive = next
    // 内存这份照样换成新的：这一趟里的判断（传没传过、幂等键）以它为准；落盘没成，
    // 下一次改动会把整份重写一遍。只是失败要留下痕迹。
    do {
      try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
      try JSONEncoder().encode(next).write(to: url, options: .atomic)
    } catch {
      Self.log.error("交易复盘档写盘失败：\(String(describing: error), privacy: .public)")
    }
  }
}

/// 传、拉、写备注三件事的流程。界面层（`TradeReviewFeature`）只管什么时候调。
public enum TradeSync {
  public enum UploadOutcome: Sendable, Equatable {
    /// 都传上去了（或本来就没有要传的）。数字是这一次新传的回合数。
    case done(Int)
    /// 网络 / 凭证 / 服务端忙：停下，下次原样重发。不弹提示、不自己轮询。
    case deferred
  }

  /// 把本地回合里服务端还没有的那几版传上去。
  ///
  /// - 一批 ≤ 100（协议 §3.1），老的先传。
  /// - 幂等键跟着「这一批」走：键和批的指纹一起先落盘再发，同一批重发（上次发出去了
  ///   没收到回应）带同一个键，服务端回放不重算；批一变就换新键。
  /// - 整批被拒（400 这类）时逐条重传找出坏的那一条，只把它记成「这一版被拒」，
  ///   别的照常进去——不能因为一条的数不对就让整页交易都传不上去。
  @MainActor public static func upload(_ rounds: [TradeRound], store: TradeReviewStore,
                                       client: ScorebookClient) async -> UploadOutcome {
    let todo = TradeUploadPlan.pending(rounds, uploaded: store.archive.uploaded, rejected: store.archive.rejected)
    var sent = 0
    for batch in TradeUploadPlan.batches(todo) {
      switch await send(batch, store: store, client: client) {
      case .sent: sent += batch.count
      case .transient: return .deferred
      case .rejected:
        for round in batch {
          switch await send([round], store: store, client: client) {
          case .sent: sent += 1
          case .transient: return .deferred
          case .rejected: store.update { $0.rejected[round.id] = round.updatedAt }
          }
        }
      }
    }
    return .done(sent)
  }

  private enum SendResult { case sent, transient, rejected }

  @MainActor private static func send(_ batch: [TradeRound], store: TradeReviewStore,
                                      client: ScorebookClient) async -> SendResult {
    let fingerprint = TradeUploadPlan.fingerprint(batch)
    let key: UUID
    if let pending = store.archive.pending, pending.fingerprint == fingerprint {
      key = pending.key
    } else {
      key = UUID()
      store.update { $0.pending = .init(key: key, fingerprint: fingerprint) }
    }
    do {
      let records = try await client.uploadTrades(batch, key: key)
      store.update { archive in
        archive.merge(records)
        for round in batch { archive.markUploaded(round) }
        archive.pending = nil
      }
      return .sent
    } catch {
      switch ReviewFailure.verdict(for: error) {
      case .transient: return .transient
      case .conflict:
        // 409 在上传上只会是幂等键撞了别的内容（`idempotency_mismatch`）或 id 撞上了观点记录：
        // 换一个新键再发一次，还不行就当被拒。
        store.update { $0.pending = nil }
        let fresh = UUID()
        store.update { $0.pending = .init(key: fresh, fingerprint: fingerprint) }
        do {
          let records = try await client.uploadTrades(batch, key: fresh)
          store.update { archive in
            archive.merge(records)
            for round in batch { archive.markUploaded(round) }
            archive.pending = nil
          }
          return .sent
        } catch {
          if ReviewFailure.verdict(for: error) == .transient { return .transient }
          store.update { $0.pending = nil }
          return .rejected
        }
      case .rejected:
        store.update { $0.pending = nil }
        return .rejected
      }
    }
  }

  /// 把服务端那份整份拉回来（最多 40 页 = 2000 条，够一个人用很多年）。
  /// 拉到的整份替换本地缓存：服务端才是结果与备注的真值。
  @MainActor @discardableResult
  public static func refresh(store: TradeReviewStore, client: ScorebookClient, maxPages: Int = 40) async throws -> [TradeRecord] {
    var all: [TradeRecord] = []
    var cursor: String?
    for _ in 0..<maxPages {
      let page = try await client.tradeList(after: cursor)
      all += page.records
      guard let next = page.next, !page.records.isEmpty else { cursor = nil; break }
      cursor = next
    }
    let fetched = all
    store.update { archive in
      let local = Dictionary(archive.records.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
      archive.records = fetched.map { record in
        guard let mine = local[record.id], mine.revision > record.revision else { return record }
        return mine
      }
      for record in fetched { archive.uploaded[record.id] = max(archive.uploaded[record.id] ?? .min, record.round.updatedAt) }
    }
    return fetched
  }

  /// 一条的最新样子。
  @MainActor @discardableResult
  public static func detail(_ id: String, store: TradeReviewStore, client: ScorebookClient) async throws -> TradeRecord {
    let record = try await client.tradeDetail(id)
    store.update { $0.merge([record]) }
    return record
  }

  /// 写「当时怎么想」。409 原样抛出，由界面去重拉那一条再告诉人。
  @MainActor @discardableResult
  public static func saveNote(_ text: String, for record: TradeRecord, store: TradeReviewStore,
                              client: ScorebookClient) async throws -> TradeRecord {
    let trimmed = String(text.prefix(2000))
    let saved = try await client.tradeNote(id: record.id, expectedRevision: record.revision, text: trimmed, key: UUID())
    store.update { $0.merge([saved]) }
    return saved
  }
}
