import Foundation
import KanpanCore

/// 网关线路上替身自己的整张资金费率表：kanpan-api 的 `/v1/market/funding?source=<替身>`。
///
/// 为什么要单独一条：网关线路上币安永续由 OKX 替身顶，而网关的 OKX 组合流只转 ticker
/// 和 K 线、没有标记价，手机又够不着币安 `fapi`（美国 VPS 回 451）——顶栏「费率」
/// 「结算」两格在这条线路上原本永远是「—」。服务端按 OKX 官方的
/// `/api/v5/public/funding-rate?instId=ANY` 整表抓、缓存，换成币安写法的代号
/// （`BTC-USDT-SWAP` → `BTCUSDT`）一次给。
///
/// 不混源：表里的每一个数都是替身自己的（OKX 的 `fundingRate` 与它的下一次结算
/// 时刻），回来的 `source` 对不上就整表不收。
enum GatewayFunding {
  static let path = "/v1/market/funding"
  /// 一次整表往返的上限。表小（几百行、压缩后几 KB），慢成这样就换备用那台。
  static let timeout: TimeInterval = 8

  static func url(host: String, source: String) -> URL? {
    // `host` 可能带端口（备用网关是 `…:8443`），不能直接塞进 `URLComponents.host`。
    guard var c = URLComponents(string: "https://\(host)"), c.host != nil,
          c.user == nil, c.password == nil else { return nil }
    c.path = path
    c.queryItems = [URLQueryItem(name: "source", value: source)]
    return c.url
  }

  private struct Envelope: Decodable {
    struct Table: Decodable {
      var source: String
      var rows: [Row]
    }
    struct Row: Decodable {
      var symbol: String
      var rate: Double?
      var nextFundingTime: Int64?
    }
    var data: Table
  }

  /// 解一张表。键是完整品种 key（`binance/usd_m/BTCUSDT`）：替身顶的就是这一家的这个品种。
  static func decode(_ body: Data, source: String, venue: String, market: String) throws -> [String: FundingSnapshot] {
    let table: Envelope.Table
    do { table = try JSONDecoder().decode(Envelope.self, from: body).data }
    catch { throw FeedError.badResponse("解不开网关资金费率表：\(error)") }
    guard table.source == source else { throw FeedError.badResponse("网关资金费率表来源不符") }
    var out: [String: FundingSnapshot] = [:]
    out.reserveCapacity(table.rows.count)
    for row in table.rows {
      guard let rate = row.rate, rate.isFinite, !row.symbol.isEmpty else { continue }
      let key = InstrumentID(venue: venue, market: market, symbol: row.symbol).key
      out[key] = FundingSnapshot(rate: rate, nextFundingTimeMs: row.nextFundingTime.flatMap { $0 > 0 ? $0 : nil })
    }
    return out
  }

  /// 按主、备顺序问。4xx 是这一笔本身的问题（来源不认），换主机也一样，直接报。
  static func fetch(hosts: [String], source: String, venue: String, market: String,
                    transport: any HTTPTransport) async throws -> [String: FundingSnapshot] {
    var failure: any Error = FeedError.badResponse("资金费率暂不可用")
    for host in hosts {
      guard let url = url(host: host, source: source) else { continue }
      let reply: HTTPReply
      do { reply = try await transport.get(url, timeout: timeout) }
      catch {
        if error is CancellationError || Task.isCancelled { throw CancellationError() }
        failure = error
        continue
      }
      if reply.status == 200 {
        let table = try decode(reply.body, source: source, venue: venue, market: market)
        guard !table.isEmpty else { failure = FeedError.badResponse("资金费率表为空"); continue }
        return table
      }
      failure = FeedError.badResponse("资金费率 HTTP \(reply.status)")
      if (400..<500).contains(reply.status) { throw failure }
    }
    throw failure
  }
}
