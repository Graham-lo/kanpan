import Foundation
import KanpanCore

/// 「大单与爆仓」用的两张服务端分钟表（kanpan-api `orderflow_history/flow.rs`、`liq.rs`，都只留 3 天）。
/// 和 `history` 一样两条线路都问 `MarketRoute.apiHosts`，哪台回了用哪台；都不通、坏数据、别的币的页一律 nil，
/// 调用方当没有、照常只用本地跟到的成交，不报错不提示。
extension OrderFlowCatalog {
  public static let flowPath = "/v1/market/orderflow/flow"
  public static let liquidationPath = "/v1/market/orderflow/liq"

  /// 每分钟大单主动买 / 卖美元额。`base` 是 `OrderFlowBase.normalize` 之后的币名。
  public func flow(base: String, fromMs: Int64, toMs: Int64) async -> BigTradeFlowPage? {
    await fetch(Self.flowPath, base: base, fromMs: fromMs, toMs: toMs) { Self.parseFlow($0, base: base) }
  }

  /// 每分钟多空被强平的美元额、笔数与最大一笔。只对合约有意义——现货的调用方自己不问。
  public func liquidations(base: String, fromMs: Int64, toMs: Int64) async -> LiquidationPage? {
    await fetch(Self.liquidationPath, base: base, fromMs: fromMs, toMs: toMs) { Self.parseLiquidations($0, base: base) }
  }

  private func fetch<T>(_ path: String, base: String, fromMs: Int64, toMs: Int64,
                        parse: (Data) -> T?) async -> T? {
    guard OrderFlowBase.isValid(base), fromMs >= 0, fromMs <= toMs else { return nil }
    for host in route.apiHosts {
      guard var c = URLComponents(string: "https://\(host)"), c.host != nil, c.user == nil else { continue }
      c.path = path
      c.queryItems = [URLQueryItem(name: "base", value: base),
                      URLQueryItem(name: "from", value: String(fromMs)),
                      URLQueryItem(name: "to", value: String(toMs))]
      guard let url = c.url else { continue }
      do {
        let reply = try await http.get(url, timeout: 15)
        guard (200..<300).contains(reply.status), let value = parse(reply.body) else { continue }
        return value
      } catch is CancellationError {
        return nil
      } catch {
        continue
      }
    }
    return nil
  }

  /// `{"base","bigUsd","smallUsd","tracked","rows":[[minute_ms,大买,大卖,小买,小卖],…]}`。
  /// 整体不是这个形状、币不对就是 nil；单行坏了（不足三个数）只丢那一行，负数当 0。
  static func parseFlow(_ data: Data, base: String) -> BigTradeFlowPage? {
    guard let obj = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
          obj["base"] as? String == base,
          let rows = obj["rows"] as? [[Any]] else { return nil }
    let tracked = obj["tracked"] as? Bool ?? false
    let big = DepthWire.number(obj["bigUsd"]).flatMap { $0 > 0 && $0.isFinite ? $0 : nil }
    let parsed: [BigTradeFlowPage.Row] = rows.compactMap { r in
      guard r.count >= 3, let m = DepthWire.number(r[0]), let b = DepthWire.number(r[1]),
            let s = DepthWire.number(r[2]), m.isFinite, b.isFinite, s.isFinite else { return nil }
      return .init(minuteMs: Int64(m), buyUsd: max(0, b), sellUsd: max(0, s))
    }
    return BigTradeFlowPage(tracked: tracked, bigUsd: big, rows: parsed)
  }

  /// `{"base","tracked","rows":[[minute_ms,多头被平,空头被平,笔数,最大一笔,价格,哪边(0 多/1 空),哪家],…]}`。
  /// 「哪家」是注册表条目的 `liquidationCode`（`LiquidationRow.Exchange` 同一套编号：0 / 1 / 2）。
  /// 单行至少要前四个数；后四个缺了当 0；负数当 0；「哪边」只认 1，「哪家」认不出的编号当 0。
  static func parseLiquidations(_ data: Data, base: String) -> LiquidationPage? {
    guard let obj = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
          obj["base"] as? String == base,
          let rows = obj["rows"] as? [[Any]] else { return nil }
    let tracked = obj["tracked"] as? Bool ?? false
    let parsed: [LiquidationRow] = rows.compactMap { r in
      let n = r.map { DepthWire.number($0).flatMap { $0.isFinite ? $0 : nil } }
      guard n.count >= 4, let m = n[0], let long = n[1], let short = n[2], let count = n[3] else { return nil }
      func at(_ i: Int) -> Double { i < n.count ? max(0, n[i] ?? 0) : 0 }
      return LiquidationRow(minuteMs: Int64(m), longUsd: max(0, long), shortUsd: max(0, short),
                            count: Int(max(0, count)), maxUsd: at(4), maxPrice: at(5),
                            maxIsLong: at(6) != 1, maxExchange: LiquidationRow.Exchange(rawValue: Int(at(7))) ?? .binance)
    }
    return LiquidationPage(tracked: tracked, rows: parsed)
  }
}
