import Foundation
import KanpanCore
import KanpanNetwork
import Observation

/// 全市场资金费率簿：每个品种此刻的费率和下一次结算时刻。
///
/// 为什么要有它：顶栏的「费率」「结算」两格原来只认逐品种的 `markPrice@1s` 流，
/// 扫图每换一只都要等新订阅推来第一帧（实测 0.5–0.7 s），这段时间两格都是「—」，
/// 连扫十只就闪十次。这本簿用 `/fapi/v1/premiumIndex`（不带 symbol，权重 10）
/// 一次拿回整张表，换品种时先从簿里取；流到了照旧由流接手（它更新、更准）。
///
/// **整表只向有费率能力、且给得出整表的那家要**（`MarketProvider.fundingAll`）：
/// 直连线路上是币安本家的 `premiumIndex`；网关线路供的是 OKX 替身的行情，整表由
/// 网关按 OKX 自己的费率给（`/v1/market/funding?source=okx`）——拿直连的费率去垫
/// 网关线路那张图就是混源。簿按供数的上游分开记（`ProviderCapabilities.upstream`），
/// 替身查不到直连那一行，直连也查不到替身那一行；没有费率的现货什么也查不到。
///
/// 网关线路没有标记价流，那两格**只**靠这本簿：`refreshIfStale` 的 `then` 在表回来
/// （或本来就新）时叫，行情页据此把当前这只再垫一次，并跟着持仓轮询按表续。
///
/// 长按预览卡的费率也从这里读，不再各记一份（原来 `SymbolPreviewStore` 自己有个字典）。
@MainActor @Observable
final class FundingBook {
  static let shared = FundingBook()

  struct Entry: Equatable {
    var rate: Double
    var nextFundingTimeMs: Int64?
    var at: Date
  }

  /// 整表多久重拉一次。换品种时发现簿比这旧才去拉，不在后台按表跑。
  static let refreshEvery: TimeInterval = 60
  /// 簿里的一行多旧还能拿来垫顶栏。费率几小时才结算一次，十分钟内的那口与
  /// 「现在」差不出肉眼可辨的数；流一到就被真值盖掉。
  static let seedMaxAge: TimeInterval = 10 * 60

  private var rows: [String: Entry] = [:]
  /// 按上游记：各家的整表各自多久拉过一次、正不正在拉。
  @ObservationIgnored private var fetchedAt: [String: Date] = [:]
  @ObservationIgnored private var fetching: [String: Task<Void, Never>] = [:]
  /// 表在路上时要来的回调，表回来（成败都叫）后一起叫。
  @ObservationIgnored private var waiters: [String: [@MainActor () -> Void]] = [:]

  private static func key(_ symbol: String, _ upstream: String) -> String {
    upstream + "|" + InstrumentID.canonical(symbol)
  }

  func entry(for symbol: String, upstream: String,
             maxAge: TimeInterval = seedMaxAge) -> Entry? {
    guard let row = rows[Self.key(symbol, upstream)],
          Date().timeIntervalSince(row.at) <= maxAge else { return nil }
    return row
  }

  /// 流捎回来的、或者单品种接口问到的那一口。比整表新，直接覆盖。
  ///
  /// - Parameter live: 真是刚从交易所来的（流、单品种接口）。假 = 界面转手回来的值
  ///   （顶栏那格变了顺手告诉预览卡）：那可能正是从簿里垫上去的旧值，只在它和簿里
  ///   不一样时才记，免得把一口十分钟前的费率重新盖上「刚拿到」的戳。
  ///   流每秒一帧，同一个数五秒内不重记，别让 `@Observable` 每秒都叫一遍。
  func note(rate: Double?, nextFundingTimeMs: Int64? = nil, for symbol: String,
            upstream: String, live: Bool = true) {
    guard let rate, rate.isFinite else { return }
    let key = Self.key(symbol, upstream)
    let next = nextFundingTimeMs.flatMap { $0 > 0 ? $0 : nil } ?? rows[key]?.nextFundingTimeMs
    if let old = rows[key], old.rate == rate, old.nextFundingTimeMs == next,
       !live || Date().timeIntervalSince(old.at) < 5 { return }
    rows[key] = Entry(rate: rate, nextFundingTimeMs: next, at: Date())
  }

  /// 这家的簿比 `refreshEvery` 旧就拉一次整表。没有费率能力的那家不拉；
  /// 给不出整表的那家（`unsupported`）什么也不记，只是少一份「先垫上」的数。
  /// - Parameters:
  ///   - delay: 先等这么久再发（冷启动时让首屏请求先走）。
  ///   - then: 簿里这家的表可用之后叫一次：本来就新就立刻叫，在路上就排队等它回来，
  ///     这一发回来（成败都算）再叫。没有费率能力的那家不叫。
  func refreshIfStale(provider: any MarketProvider, maxAge: TimeInterval = refreshEvery,
                      delay: Duration = .zero, then: (@MainActor () -> Void)? = nil) {
    let upstream = provider.capabilities.upstream
    guard provider.capabilities.hasFunding else { return }
    if fetching[upstream] != nil {
      if let then { waiters[upstream, default: []].append(then) }
      return
    }
    guard Date().timeIntervalSince(fetchedAt[upstream] ?? .distantPast) >= maxAge else {
      then?()
      return
    }
    if let then { waiters[upstream, default: []].append(then) }
    fetching[upstream] = Task { [weak self] in
      if delay > .zero { try? await Task.sleep(for: delay) }
      let table = try? await provider.fundingAll()
      guard let self else { return }
      self.fetching[upstream] = nil
      if let table, !table.isEmpty {
        let at = Date()
        self.fetchedAt[upstream] = at
        self.merge(table, upstream: upstream, at: at)
      }
      let callbacks = self.waiters.removeValue(forKey: upstream) ?? []
      for callback in callbacks { callback() }
    }
  }

  private func merge(_ table: [String: FundingSnapshot], upstream: String, at: Date) {
    var next = rows
    for (symbol, snapshot) in table {
      let key = Self.key(symbol, upstream)
      // 流在这之后又记过更新的一口，就别拿整表把它盖回去。
      if let mine = next[key], mine.at > at { continue }
      next[key] = Entry(rate: snapshot.rate, nextFundingTimeMs: snapshot.nextFundingTimeMs, at: at)
    }
    rows = next
  }
}
