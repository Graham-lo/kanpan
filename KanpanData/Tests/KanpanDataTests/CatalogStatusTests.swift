import Foundation
import Testing
@testable import KanpanData
import KanpanNetworkTestSupport
import KanpanCore

/// 品种表这一层的三件事（审查 B-05 / B-06）：
/// 1. 一次刷新只跑一趟，而且**校验和采纳都在那一趟里面**，等在门口的人拿到同一份验过的表；
/// 2. 非 `TRADING` 的行留在表里带 `SymbolStatus`，交易所不认某个代号时把它标成下架、**不删**；
/// 3. 用户点名一个表里没有的代号时允许立刻重拉一次，两趟之间有去抖。
///
/// 全离线：`FakeServer` + 临时目录，没有一次真网络。
@Suite("品种表状态与单飞刷新")
struct CatalogStatusTests {

  // ---------------------------------------------------------------- 夹具

  private func tempPaths() -> Paths {
    let p = Paths(root: URL(fileURLWithPath: NSTemporaryDirectory())
      .appendingPathComponent("kanpan-catalog-\(UUID().uuidString)"))
    try? p.ensureRoot()
    return p
  }

  /// `exchangeInfo` 的最小响应体：`(代号, 交易所 status)`。
  private func infoBody(_ rows: [(String, String)]) throws -> Data {
    let symbols: [[String: Any]] = rows.map { symbol, status in
      ["symbol": symbol, "baseAsset": symbol.replacingOccurrences(of: "USDT", with: ""),
       "quoteAsset": "USDT", "pricePrecision": 2, "quantityPrecision": 3,
       "contractType": "PERPETUAL", "status": status, "filters": []]
    }
    return try JSONSerialization.data(withJSONObject: ["symbols": symbols])
  }

  private func info(_ symbol: String, status: SymbolStatus = .tradable) -> SymbolInfo {
    SymbolInfo(symbol: symbol, base: symbol.replacingOccurrences(of: "USDT", with: ""),
               pricePrecision: 2, tickSize: 0.01, status: status)
  }

  /// 往盘上放一份目录缓存。`schema` 传 `nil` 就是「老版本写的、根本没有这个字段」。
  private func seedDisk(_ list: [SymbolInfo], at ms: Int64, schema: Int?, _ paths: Paths) throws {
    var obj: [String: Any] = ["at": ms,
                              "list": try JSONSerialization.jsonObject(with: JSONEncoder().encode(list))]
    if let schema { obj["schema"] = schema }
    try JSONSerialization.data(withJSONObject: obj).write(to: paths.exchangeInfo)
  }

  private struct DiskShape: Decodable { var schema: Int?; var at: Int64; var list: [SymbolInfo] }

  private func readDisk(_ paths: Paths) throws -> DiskShape {
    try JSONDecoder().decode(DiskShape.self, from: try Data(contentsOf: paths.exchangeInfo))
  }

  private func makeREST(_ body: @escaping @Sendable (URL) -> HTTPReply,
                    gate: Gate? = nil) -> (BinanceREST, FakeServer) {
    let server = FakeServer(handler: body)
    let transport: HTTPTransport = gate.map { GatedTransport(server: server, gate: $0) }
      ?? FakeTransport(server)
    return (BinanceREST(transport: transport, pacer: StepPacer()), server)
  }

  private struct GatedTransport: HTTPTransport {
    let server: FakeServer
    let gate: Gate
    func get(_ url: URL, timeout: TimeInterval) async throws -> HTTPReply {
      await gate.wait()
      return await server.serve(url)
    }
  }

  // ---------------------------------------------------------------- B-T13

  @Test("B-T13 一份畸形响应：发起者和等在门口的人拿到同一张旧表，谁都不会拿到空表")
  func singleFlightSharesTheVerifiedResult() async throws {
    let p = tempPaths()
    defer { try? FileManager.default.removeItem(at: p.root) }
    // 盘上先放一份旧表（TTL 已过），刷新时上游回一份 200 的畸形 JSON。
    try seedDisk([info("BTCUSDT"), info("ETHUSDT")], at: 1_000, schema: 6, p)
    let gate = Gate()
    let (rest, server) = makeREST({ _ in HTTPReply(status: 200, body: Data(#"{"symbols":"nope"}"#.utf8)) },
                              gate: gate)
    let catalog = SymbolCatalog(rest: rest, paths: p)
    let now: Int64 = 1_000 + SymbolCatalog.ttlMs + 1

    async let a = catalog.all(now: now)
    async let b = catalog.all(now: now)
    // 两个人都已经进来了，而且只有一笔出站——单飞成立。
    #expect(await waitUntil(5) { await gate.arrived >= 1 })
    await gate.open()
    let (first, second) = await (a, b)

    #expect(first.map(\.symbol) == ["BTCUSDT", "ETHUSDT"])
    #expect(second.map(\.symbol) == first.map(\.symbol))   // 等待者不许拿到 []
    #expect(await server.urls().count == 1)
  }

  @Test("B-T13 一张全是停牌的表不算好表：不采纳、不落盘，盘上那份可用的还在")
  func validateRejectsUntradableTable() async throws {
    let p = tempPaths()
    defer { try? FileManager.default.removeItem(at: p.root) }
    try seedDisk([info("BTCUSDT")], at: 1_000, schema: 6, p)
    let body = try infoBody([("AAAUSDT", "SETTLING"), ("BBBUSDT", "SETTLING")])
    let (rest, _) = makeREST({ _ in HTTPReply(status: 200, body: body) })
    let catalog = SymbolCatalog(rest: rest, paths: p)

    let out = await catalog.all(now: 1_000 + SymbolCatalog.ttlMs + 1)
    #expect(out.map(\.symbol) == ["BTCUSDT"])              // 退回旧表
    #expect(try readDisk(p).list.map(\.symbol) == ["BTCUSDT"])  // 没被顶掉

    // 空表同样不算好表。
    #expect(throws: (any Error).self) { try SymbolCatalog.validate([]) }
    #expect(throws: (any Error).self) {
      try SymbolCatalog.validate([info("AAAUSDT", status: .delisted),
                                 info("BBBUSDT", status: .pending)])
    }
    #expect(throws: Never.self) {
      try SymbolCatalog.validate([info("AAAUSDT", status: .delisted), info("BTCUSDT")])
    }
  }

  @Test("B-T13 刚失败过就先用手里那份，60 秒内不再往枪口上撞")
  func failureCooldown() async throws {
    let p = tempPaths()
    defer { try? FileManager.default.removeItem(at: p.root) }
    try seedDisk([info("BTCUSDT")], at: 1_000, schema: 6, p)
    let (rest, server) = makeREST({ _ in HTTPReply(status: 500, body: Data()) })
    let catalog = SymbolCatalog(rest: rest, paths: p)
    let t0: Int64 = 1_000 + SymbolCatalog.ttlMs + 1

    #expect(await catalog.all(now: t0).count == 1)
    #expect(await server.urls().count == 1)
    #expect(await catalog.all(now: t0 + 1_000).count == 1)
    #expect(await server.urls().count == 1)                 // 冷却期内没有第二笔
    #expect(await catalog.all(now: t0 + SymbolCatalog.retryAfterFailureMs + 1).count == 1)
    #expect(await server.urls().count == 2)                 // 冷却过了才再试
  }

  // ---------------------------------------------------------------- B-T14

  @Test("B-T14 非 TRADING 的行留在表里带状态；老 schema 的缓存一律重拉")
  func statusSurvivesAndSchemaBumpInvalidates() async throws {
    let p = tempPaths()
    defer { try? FileManager.default.removeItem(at: p.root) }
    // 盘上那份是 schema 5 写的：没有停牌的行，所以就算没过期也不能用。
    try seedDisk([info("BTCUSDT")], at: 1_000, schema: 5, p)
    let body = try infoBody([("BTCUSDT", "TRADING"), ("OLDUSDT", "SETTLING"),
                             ("NEWUSDT", "PENDING_TRADING")])
    let (rest, server) = makeREST({ _ in HTTPReply(status: 200, body: body) })
    let catalog = SymbolCatalog(rest: rest, paths: p)

    let list = await catalog.all(now: 1_100)                // TTL 还没到，但 schema 老了
    #expect(await server.urls().count == 1)
    #expect(list.map(\.symbol) == ["BTCUSDT", "NEWUSDT", "OLDUSDT"])
    #expect(list.first { $0.symbol == "OLDUSDT" }?.status == .delisted)
    #expect(list.first { $0.symbol == "NEWUSDT" }?.status == .pending)
    #expect(list.first { $0.symbol == "OLDUSDT" }?.status.hasLivePrice == false)
    #expect(list.first { $0.symbol == "BTCUSDT" }?.status.hasLivePrice == true)
    // 落盘的那份带上了新代次，下次冷启动直接可用。
    #expect(try readDisk(p).schema == 6)
    #expect(try readDisk(p).list.count == 3)
  }

  @Test("B-T14 交易所不认这个代号：标成下架、不删，冷启动之后还记得")
  func markDelistedPersistsWithoutDeleting() async throws {
    let p = tempPaths()
    defer { try? FileManager.default.removeItem(at: p.root) }
    let body = try infoBody([("BTCUSDT", "TRADING"), ("GONEUSDT", "TRADING")])
    let (rest, _) = makeREST({ _ in HTTPReply(status: 200, body: body) })
    let catalog = SymbolCatalog(rest: rest, paths: p)
    #expect(await catalog.all(now: 10_000).count == 2)

    await catalog.markDelisted("goneusdt")                  // 大小写不敏感
    let after = await catalog.all(now: 10_000)
    #expect(after.count == 2)                               // 一行都没少
    #expect(after.first { $0.symbol == "GONEUSDT" }?.status == .delisted)
    #expect(after.first { $0.symbol == "BTCUSDT" }?.status == .tradable)

    // 盘上也改了：换一个 catalog 实例（等于冷启动）读回来还是下架。
    let disk = try readDisk(p)
    #expect(disk.list.first { $0.symbol == "GONEUSDT" }?.status == .delisted)
    let (rest2, server2) = makeREST({ _ in HTTPReply(status: 500, body: Data()) })
    let cold = SymbolCatalog(rest: rest2, paths: p)
    let back = await cold.all(now: 10_000)
    #expect(await server2.urls().isEmpty)                   // 缓存还没过期，不用出站
    #expect(back.first { $0.symbol == "GONEUSDT" }?.status == .delisted)
  }

  @Test("复核项 4 目录里没有这个代号也能标下架：补一行占位，不再默默丢掉")
  func markDelistedRemembersSymbolsOutsideTheCatalog() async throws {
    let p = tempPaths()
    defer { try? FileManager.default.removeItem(at: p.root) }
    let body = try infoBody([("BTCUSDT", "TRADING")])
    let (rest, _) = makeREST({ _ in HTTPReply(status: 200, body: body) })
    let catalog = SymbolCatalog(rest: rest, paths: p)
    #expect(await catalog.all(now: 10_000).map(\.symbol) == ["BTCUSDT"])

    // 一个已经从 exchangeInfo 上消失的老自选：交易所回「不认这个代号」，
    // 它却本来就不在表里。从前这儿直接 return，于是「明确下架」这件事记不下来，
    // 界面只能看见「目录里没有」——而那按新口径是**未知**（留着、灰着、不划掉）。
    await catalog.markDelisted("oldcoinusdt")
    let after = await catalog.all(now: 10_000)
    #expect(after.count == 2)
    let gone = after.first { $0.symbol == "OLDCOINUSDT" }
    #expect(gone?.status == .delisted)
    #expect(gone?.base == "OLDCOIN")                 // 按后缀拆出来的占位行
    #expect(gone?.pricePrecision == 0)               // 精度未知：摆价时按那口价猜
    #expect(gone?.status.hasLivePrice == false)
    #expect(after.first { $0.symbol == "BTCUSDT" }?.status == .tradable)
    // 落盘了：冷启动之后这一行还是下架，不会退回「未知」。
    #expect(try readDisk(p).list.first { $0.symbol == "OLDCOINUSDT" }?.status == .delisted)

    // 标第二次不重复写，也不叠行。
    await catalog.markDelisted("OLDCOINUSDT")
    #expect(await catalog.all(now: 10_000).count == 2)
  }

  @Test("复核项 4 手里还没有表的时候标下架：什么都不写，不许拿一行顶掉盘上那份")
  func markDelistedDoesNothingBeforeTheCatalogIsLoaded() async throws {
    let p = tempPaths()
    defer { try? FileManager.default.removeItem(at: p.root) }
    // 盘上有一份好表，但这个实例还没 `all()` 过——手里是空的（冷启动那一小段）。
    try seedDisk([info("BTCUSDT"), info("ETHUSDT")], at: 9_000, schema: 6, p)
    let (rest, server) = makeREST({ _ in HTTPReply(status: 500, body: Data()) })
    let catalog = SymbolCatalog(rest: rest, paths: p)

    await catalog.markDelisted("BTCUSDT")
    // 盘上那两行一个没动：要是这会儿写一行占位下去，下一次冷启动整张品种表
    // 就只剩这一行（而且 TTL 没到，不会去重拉）。
    let disk = try readDisk(p)
    #expect(disk.list.map(\.symbol).sorted() == ["BTCUSDT", "ETHUSDT"])
    #expect(disk.list.allSatisfy { $0.status == .tradable })
    #expect(disk.at == 9_000)
    #expect(await server.urls().isEmpty)
    // 表读进来之后再标，照常生效。
    #expect(await catalog.all(now: 9_100).count == 2)
    await catalog.markDelisted("BTCUSDT")
    #expect(await catalog.all(now: 9_100).first { $0.symbol == "BTCUSDT" }?.status == .delisted)
  }

  @Test("B-T14 只有「交易所不认这个代号」才配标下架，限流地域超时都不算")
  func rejectsSymbolRuleTable() {
    #expect(SymbolCatalog.rejectsSymbol(BinanceError(status: 400, code: -1121, msg: "Invalid symbol.")))
    #expect(SymbolCatalog.rejectsSymbol(BinanceError(status: 400, msg: "Invalid symbol status.")))
    #expect(SymbolCatalog.rejectsSymbol(BinanceError(status: 404)))
    // 这些拒的是整条线路，不是某一个品种——照它判会把整张自选表一次标成下架。
    #expect(!SymbolCatalog.rejectsSymbol(BinanceError(status: 429)))
    #expect(!SymbolCatalog.rejectsSymbol(BinanceError(status: 418)))
    #expect(!SymbolCatalog.rejectsSymbol(BinanceError(status: 451)))
    #expect(!SymbolCatalog.rejectsSymbol(BinanceError(status: 408)))
    #expect(!SymbolCatalog.rejectsSymbol(BinanceError.blocked(seconds: 30)))
    #expect(!SymbolCatalog.rejectsSymbol(BinanceError(status: 400, code: -1120, msg: "Invalid interval.")))
    #expect(!SymbolCatalog.rejectsSymbol(BinanceError(status: 500)))
    #expect(!SymbolCatalog.rejectsSymbol(FeedError.cancelled))
  }

  // ---------------------------------------------------------------- B-T15

  @Test("B-T15 用户点名一个表里没有的新合约：立刻重拉一次，但 5 分钟内只拉一次")
  func onDemandLookupDebounce() async throws {
    let p = tempPaths()
    defer { try? FileManager.default.removeItem(at: p.root) }
    let listed = try infoBody([("BTCUSDT", "TRADING")])
    let withNew = try infoBody([("BTCUSDT", "TRADING"), ("FRESHUSDT", "TRADING")])
    let stage = Stage(listed)
    let (rest, server) = makeREST({ _ in HTTPReply(status: 200, body: stage.body) })
    let catalog = SymbolCatalog(rest: rest, paths: p)

    let t0: Int64 = 10_000_000
    #expect(await catalog.lookup("BTCUSDT", now: t0)?.symbol == "BTCUSDT")
    #expect(await server.urls().count == 1)                 // 头一趟是普通的 all()

    // 表里没有 FRESHUSDT：为用户立刻重拉一次（上游此时还是旧表，仍然没有）。
    #expect(await catalog.lookup("FRESHUSDT", now: t0) == nil)
    #expect(await server.urls().count == 2)

    // 上游上架了，但去抖还没过：不打第二趟，老实回 nil。
    stage.body = withNew
    #expect(await catalog.lookup("FRESHUSDT", now: t0 + 60_000) == nil)
    #expect(await server.urls().count == 2)

    // 去抖过了，这一趟拿到它。
    let t1 = t0 + SymbolCatalog.onDemandDebounceMs + 1
    #expect(await catalog.lookup("FRESHUSDT", now: t1)?.symbol == "FRESHUSDT")
    #expect(await server.urls().count == 3)
    // 已经在表里的，之后不再为它出站。
    #expect(await catalog.lookup("FRESHUSDT", now: t1 + 1)?.symbol == "FRESHUSDT")
    #expect(await server.urls().count == 3)
  }

  /// 可换的响应体。`@Sendable` 闭包要读它，所以包一层锁。
  private final class Stage: @unchecked Sendable {
    private let lock = NSLock()
    private var value: Data
    init(_ value: Data) { self.value = value }
    var body: Data {
      get { lock.lock(); defer { lock.unlock() }; return value }
      set { lock.lock(); value = newValue; lock.unlock() }
    }
  }
}
