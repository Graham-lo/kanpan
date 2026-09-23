import Foundation
import KanpanCore
import KanpanNetwork

/// 长按预览卡要的那两样行情：一段 1 小时 K 线和一口资金费率。
///
/// 从前这段取数写在 `SymbolPreviewCard.swift`（一个 View 文件）里，自己拿提供者拉数，
/// 线路也是自己拼的「直连 + 空网关表」（审查 1.1 / 18a）。现在挪到数据层：提供者一律
/// 从调用方交进来的 `RouteResolver` 要，于是走的是用户选的那条线路，REST 走的是和
/// 行情页同一份共享限流器与冷却（提供者建在 `VenueRegistry` 的工厂里，限流器是进程级
/// 共享的那一份），不再另起炉灶。
///
/// 只管「取」：缓存、淘汰、按住才取这些界面节奏仍归 app 里的 `SymbolPreviewStore`。
public struct SymbolPreviewService: Sendable {
  /// 卡上那段 K 线：1 小时 × 60 根。
  public static let interval = Interval.h1
  public static let barCount = 60

  public let resolver: RouteResolver

  public init(resolver: RouteResolver) { self.resolver = resolver }

  /// 这只在当前线路上由谁供数（费率簿按上游分开记）。
  public func capabilities(for symbol: String) -> ProviderCapabilities {
    resolver.provider(forSymbol: InstrumentID.canonical(symbol)).capabilities
  }

  /// 卡上那段 K 线。取不到或全是坏根就给空表——卡上那一格空着，不报错。
  public func bars(for symbol: String) async -> [Bar] {
    let key = InstrumentID.canonical(symbol)
    let rest = resolver.provider(forSymbol: key)
    do {
      let rows = try await rest.klines(symbol: key, interval: Self.interval, limit: Self.barCount)
      return Array(rows.filter(\.isValidMarketBar).suffix(Self.barCount))
    } catch is CancellationError {
      return []
    } catch {
      resolver.log("预览卡 K 线取不到 \(key)：\(error)")
      return []
    }
  }

  /// 单品种资金费率。没有费率的品种（现货、美股）或取不到时给 nil。
  public func funding(for symbol: String) async -> FundingSnapshot? {
    let key = InstrumentID.canonical(symbol)
    let rest = resolver.provider(forSymbol: key)
    guard rest.capabilities.hasFunding else { return nil }
    do {
      let snapshot = try await rest.funding(symbol: key)
      return snapshot.rate.isFinite ? snapshot : nil
    } catch is CancellationError {
      return nil
    } catch {
      resolver.log("预览卡费率取不到 \(key)：\(error)")
      return nil
    }
  }
}
