import Foundation
import KanpanCore

/// 品种表（§4.1）。`exchangeInfo` 几十 KB，放 `Caches/` 24 小时；
/// 过期就重拉，拉不到就先用旧的（离线也能开品种页）。
public actor SymbolCatalog {
  public static let ttlMs: Int64 = 24 * 3_600_000

  private let rest: BinanceREST
  private let paths: Paths
  private let log: FeedLog
  private var symbols: [SymbolInfo] = []
  private var loadedAtMs: Int64 = 0
  private static let schema = 5 // USDT普通/TradFi，排除稳定币对；刷新早期目录。
  private var loadedSchema = 0

  public init(rest: BinanceREST, paths: Paths = .caches(), log: FeedLog = .silent) {
    self.rest = rest
    self.paths = paths
    self.log = log
  }

  private var refreshTask: Task<[SymbolInfo], Error>?

  public func all(now: Int64 = Int64(Date().timeIntervalSince1970 * 1000)) async -> [SymbolInfo] {
    if !symbols.isEmpty, loadedSchema == Self.schema, now - loadedAtMs < Self.ttlMs { return symbols }
    if symbols.isEmpty, let disk = readDisk(), disk.schema == Self.schema, now - disk.at < Self.ttlMs {
      symbols = disk.list
      loadedAtMs = disk.at
      loadedSchema = Self.schema
      log("品种表走缓存 \(symbols.count) 个")
      return symbols
    }
    if let refreshTask { return (try? await refreshTask.value) ?? symbols }
    let task = Task { [rest] in try await rest.exchangeInfo() }
    refreshTask = task
    defer { refreshTask = nil }
    do {
      let fresh = try await task.value
      guard !fresh.isEmpty else { throw FeedError.badResponse("品种表为空") }
      symbols = fresh
      loadedSchema = Self.schema
      loadedAtMs = now
      writeDisk(fresh, at: now)
      log("品种表刷新 \(fresh.count) 个")
    } catch {
      log("品种表拉取失败，用旧的：\(error)")
      if symbols.isEmpty, let disk = readDisk() { symbols = disk.list; loadedAtMs = disk.at }
    }
    return symbols
  }

  public func find(_ symbol: String) async -> SymbolInfo? {
    let s = symbol.uppercased()
    return await all().first { $0.symbol == s }
  }

  // ------------------------------------------------------------------ 磁盘

  private struct Disk: Codable { var schema: Int?; var at: Int64; var list: [SymbolInfo] }

  private func readDisk() -> Disk? {
    guard let d = try? Data(contentsOf: paths.exchangeInfo) else { return nil }
    return try? JSONDecoder().decode(Disk.self, from: d)
  }

  private func writeDisk(_ list: [SymbolInfo], at: Int64) {
    try? paths.ensureRoot()
    guard let d = try? JSONEncoder().encode(Disk(schema: Self.schema, at: at, list: list)) else { return }
    try? d.write(to: paths.exchangeInfo, options: .atomic)
  }
}
