import XCTest
import KanpanCore
import KanpanAccount
import ReviewDomain
import ReviewData

/// 交易复盘的上传 / 拉取 / 备注对着一台假服务器跑：断言线上看得见的请求（路径、批大小、
/// 幂等键）和本地那份最后的样子。
struct TradeTestEnvelope<V: Encodable>: Encodable { var data: V }

@MainActor final class TradeSyncTests: XCTestCase {
  actor Server {
    struct Call: Sendable { var path: String; var method: String; var key: UUID?; var ids: [String] }
    private(set) var calls: [Call] = []
    /// 按顺序吐出的失败；空了就正常应答。
    var failures: [any Error] = []
    /// 这几个 id 只要在批里，整批 400。
    var poison: Set<String> = []
    var stored: [String: TradeRecord] = [:]
    var pageSize = 50
    var noteConflict = false

    func fail(_ error: any Error) { failures.append(error) }
    func setPoison(_ ids: Set<String>) { poison = ids }
    func setNoteConflict(_ value: Bool) { noteConflict = value }
    func seed(_ records: [TradeRecord]) { for r in records { stored[r.id] = r } }

    func handle(_ path: String, _ method: String, _ body: Data?, _ key: UUID?) throws -> Data {
      var ids: [String] = []
      if path == "v1/native-review/trades", let body,
         let object = try? JSONSerialization.jsonObject(with: body) as? [String: Any],
         let rounds = object["rounds"] as? [[String: Any]] {
        ids = rounds.compactMap { $0["id"] as? String }
      }
      calls.append(Call(path: path, method: method, key: key, ids: ids))
      if !failures.isEmpty { throw failures.removeFirst() }
      if path == "v1/native-review/trades" {
        struct Body: Decodable { var rounds: [TradeRound] }
        let rounds = try JSONDecoder().decode(Body.self, from: body ?? Data()).rounds
        guard rounds.count <= 100 else { throw AccountError.http(400, "too_many_rounds") }
        if rounds.contains(where: { poison.contains($0.id) }) { throw AccountError.http(400, "invalid_round") }
        var out: [TradeRecord] = []
        for round in rounds {
          let revision = (stored[round.id]?.revision ?? 0) + 1
          let record = TradeRecord(id: round.id, revision: revision, submitted: 1, updated: 1, round: round)
          stored[round.id] = record; out.append(record)
        }
        return try wrap(["records": out])
      }
      if path.hasPrefix("v1/native-review/records?") {
        let items = URLComponents(string: "x?" + path.split(separator: "?", maxSplits: 1)[1])?.queryItems ?? []
        precondition(items.contains(URLQueryItem(name: "kind", value: "trade")))
        let after = items.first { $0.name == "after" }?.value.flatMap(Int.init) ?? 0
        let all = stored.values.sorted { $0.id < $1.id }
        let page = Array(all.dropFirst(after).prefix(pageSize))
        let next = after + page.count < all.count ? String(after + page.count) : nil
        return try wrap(TradeListResponse(records: page, next: next))
      }
      if path.hasSuffix("/note") {
        if noteConflict { throw AccountError.http(409, "record_revision_changed") }
        let id = String(path.split(separator: "/")[3])
        struct Body: Decodable { var expectedRevision: Int; var text: String }
        let input = try JSONDecoder().decode(Body.self, from: body ?? Data())
        guard var record = stored[id], record.revision == input.expectedRevision else {
          throw AccountError.http(409, "record_revision_changed")
        }
        record.revision += 1
        record.note = input.text.isEmpty ? nil : TradeNote(text: input.text, updatedAt: 9)
        stored[id] = record
        return try wrap(["record": record])
      }
      if path.hasPrefix("v1/native-review/records/") {
        let id = String(path.dropFirst("v1/native-review/records/".count))
        guard let record = stored[id] else { throw AccountError.http(404, "not_found") }
        return try wrap(["record": record])
      }
      throw AccountError.http(404, "not_found")
    }
    private func wrap<T: Encodable>(_ value: T) throws -> Data {
      try JSONEncoder().encode(TradeTestEnvelope(data: value))
    }
  }

  private var directory: URL!
  override func setUp() async throws {
    directory = FileManager.default.temporaryDirectory.appendingPathComponent("trade-sync-\(UUID().uuidString)")
  }
  override func tearDown() async throws { try? FileManager.default.removeItem(at: directory) }

  private func client(_ server: Server) -> ScorebookClient {
    ScorebookClient(transport: { path, method, body, key in try await server.handle(path, method, body, key) })
  }
  private func round(_ n: Int, updated: Int64 = 1) -> TradeRound {
    TradeRound(id: String(format: "00000000-0000-8000-8000-%012d", n), venue: "binance", market: "usd_m",
               symbol: "BTCUSDT", accountTag: "primary", positionSide: .both, direction: .long, status: .closed,
               quoteAsset: "USDT", openedAt: Int64(n) * 1_000, closedAt: Int64(n) * 1_000 + 500, holdingMs: 500,
               openAvgPrice: 100, closeAvgPrice: 101, openedQty: 1, closedQty: 1, maxQty: 1, peakNotional: 100,
               leverage: 5, realizedPnl: 1, commission: Decimal(string: "0.1")!, commissionByAsset: ["USDT": Decimal(string: "0.1")!],
               commissionUnpriced: false, funding: 0, netPnl: Decimal(string: "0.9")!, fills: [], updatedAt: updated)
  }

  func testUploadsInBatchesOfAHundredAndSkipsWhatTheServerHas() async throws {
    let server = Server()
    let store = TradeReviewStore(directory: directory)
    let rounds = (1...230).map { round($0) }
    let outcome = await TradeSync.upload(rounds, store: store, client: client(server))
    XCTAssertEqual(outcome, .done(230))
    let calls = await server.calls
    XCTAssertEqual(calls.map(\.ids.count), [100, 100, 30])
    XCTAssertEqual(Set(calls.compactMap(\.key)).count, 3, "每一批一个幂等键")
    XCTAssertEqual(store.archive.records.count, 230)
    XCTAssertNil(store.archive.pending)

    // 再跑一遍：服务端都有这一版，一个请求都不发。
    let again = await TradeSync.upload(rounds, store: store, client: client(server))
    XCTAssertEqual(again, .done(0))
    let after = await server.calls
    XCTAssertEqual(after.count, 3)

    // 一个回合有了新成交：只传它。
    var changed = rounds; changed[7] = round(8, updated: 2)
    _ = await TradeSync.upload(changed, store: store, client: client(server))
    let last = await server.calls.last
    XCTAssertEqual(last?.ids, [changed[7].id])
  }

  func testSameBatchRetriesWithTheSameKeyAfterANetworkFailure() async throws {
    let server = Server()
    await server.fail(URLError(.timedOut))
    let store = TradeReviewStore(directory: directory)
    let rounds = [round(1), round(2)]
    let first = await TradeSync.upload(rounds, store: store, client: client(server))
    XCTAssertEqual(first, .deferred, "断网就停下，不自己重试")
    XCTAssertNotNil(store.archive.pending)
    // 进程被杀、重开：从盘上读回来的那份还记着这一批的键。
    let reopened = TradeReviewStore(directory: directory)
    let second = await TradeSync.upload(rounds, store: reopened, client: client(server))
    XCTAssertEqual(second, .done(2))
    let calls = await server.calls
    XCTAssertEqual(calls.count, 2)
    XCTAssertEqual(calls[0].key, calls[1].key, "同一批重发必须带同一个幂等键")
    XCTAssertNil(reopened.archive.pending)
  }

  func testOneBadRoundDoesNotBlockTheBatch() async throws {
    let server = Server()
    let rounds = (1...5).map { round($0) }
    await server.setPoison([rounds[2].id])
    let store = TradeReviewStore(directory: directory)
    let outcome = await TradeSync.upload(rounds, store: store, client: client(server))
    XCTAssertEqual(outcome, .done(4))
    XCTAssertEqual(store.archive.rejected, [rounds[2].id: 1])
    XCTAssertEqual(Set(store.archive.records.map(\.id)), Set(rounds.map(\.id)).subtracting([rounds[2].id]))
    // 被拒的这一版不再传；它变了才再试。
    let before = await server.calls.count
    _ = await TradeSync.upload(rounds, store: store, client: client(server))
    let after = await server.calls.count
    XCTAssertEqual(before, after)
  }

  func testRefreshPagesThroughAndReadsResultsBack() async throws {
    let server = Server()
    await server.seed((1...120).map { n in
      var record = TradeRecord(id: round(n).id, revision: 2, submitted: 1, updated: 1, round: round(n))
      record.result = TradeResult(computedAt: 5, excursion: nil, after: [:], chart: TradeChartSpec(interval: "1m", start: 0, end: 60_000))
      return record
    })
    let store = TradeReviewStore(directory: directory)
    let records = try await TradeSync.refresh(store: store, client: client(server))
    XCTAssertEqual(records.count, 120)
    let lists = await server.calls.filter { $0.path.contains("kind=trade") }
    XCTAssertEqual(lists.count, 3)
    XCTAssertEqual(store.archive.records.first?.result?.chart?.interval, "1m")
    // 拉回来的记账：服务端已有这一版，就不必再传。
    let outcome = await TradeSync.upload((1...120).map { round($0) }, store: store, client: client(server))
    XCTAssertEqual(outcome, .done(0))
  }

  func testNoteConflictSurfacesAndDetailRepullsTheLatest() async throws {
    let server = Server()
    let store = TradeReviewStore(directory: directory)
    _ = await TradeSync.upload([round(1)], store: store, client: client(server))
    let record = try XCTUnwrap(store.archive.records.first)
    let saved = try await TradeSync.saveNote("追多了", for: record, store: store, client: client(server))
    XCTAssertEqual(saved.note?.text, "追多了")
    XCTAssertEqual(store.archive.records.first?.revision, 2)
    // 拿旧版本去写：409 原样抛出。
    do {
      _ = try await TradeSync.saveNote("再改", for: record, store: store, client: client(server))
      XCTFail("旧版本不该写得进去")
    } catch {
      XCTAssertEqual(ReviewFailure.verdict(for: error), .conflict)
    }
    let latest = try await TradeSync.detail(record.id, store: store, client: client(server))
    XCTAssertEqual(latest.revision, 2)
    XCTAssertEqual(latest.note?.text, "追多了")
  }

  /// 「导出我的数据」导的是服务端那份；服务端那份只来自这里传上去的东西。
  /// 所以只要传上去的东西和本地那份里都没有 Key、尾号、水位，导出里就不可能有。
  func testNothingUploadedOrCachedCarriesExchangeSecrets() async throws {
    let server = Server()
    let store = TradeReviewStore(directory: directory)
    _ = await TradeSync.upload([round(1), round(2)], store: store, client: client(server))
    let body = try JSONEncoder().encode(["rounds": [round(1), round(2)]])
    let cached = try Data(contentsOf: store.url)
    for blob in [body, cached] {
      let text = String(decoding: blob, as: UTF8.self).lowercased()
      for word in ["apikey", "secret", "keysuffix", "watermark", "backfill", "signature", "x-mbx"] {
        XCTAssertFalse(text.contains(word), "不该出现 \(word)")
      }
    }
  }
}
