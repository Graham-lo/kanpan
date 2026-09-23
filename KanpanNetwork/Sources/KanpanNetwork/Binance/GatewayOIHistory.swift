import Foundation
import KanpanCore

/// 网关线路上替身自己的持仓量历史：kanpan-api 的 `/v1/market/open-interest/history`。
///
/// 参数照币安 `openInterestHist`（`period` 同一套 5m…1d、`limit` ≤ 500、`endTime` 含端点），
/// 服务端去问 OKX 官方的 `rubik/stat/contracts/open-interest-history`，6h/12h/1d 用 UTC
/// 对齐的档，桶头和币安一致。答复 `{"source":"okx","rows":[[毫秒, 币的个数, 美元名义值|null], …]}`，
/// 时间升序。取的是**币的个数**：和币安 `sumOpenInterest` 同一个单位，副图读法不变。
///
/// 不混源：回来的 `source` / `symbol` 对不上就整页不收。
enum GatewayOIHistory {
  static let path = "/v1/market/open-interest/history"
  /// 一页 500 条，服务端要替我们去 OKX 翻五页（每 2 秒 5 次），给足。
  static let timeout: TimeInterval = 15

  static func url(host: String, source: String, symbol: String, period: String,
                  limit: Int, endTime: Int64?) -> URL? {
    guard var c = URLComponents(string: "https://\(host)"), c.host != nil,
          c.user == nil, c.password == nil else { return nil }
    c.path = path
    var items = [URLQueryItem(name: "source", value: source),
                 URLQueryItem(name: "symbol", value: InstrumentID(symbol).symbol),
                 URLQueryItem(name: "period", value: period),
                 URLQueryItem(name: "limit", value: String(max(1, min(limit, 500))))]
    if let endTime { items.append(URLQueryItem(name: "endTime", value: String(endTime))) }
    c.queryItems = items
    return c.url
  }

  private struct Envelope: Decodable {
    struct Page: Decodable {
      var source: String
      var symbol: String
      var rows: [[Double?]]
    }
    var data: Page
  }

  static func decode(_ body: Data, source: String, symbol: String) throws -> [OIPoint] {
    let page: Envelope.Page
    do { page = try JSONDecoder().decode(Envelope.self, from: body).data }
    catch { throw FeedError.badResponse("解不开网关持仓量历史：\(error)") }
    guard page.source == source, page.symbol.uppercased() == InstrumentID(symbol).symbol else {
      throw FeedError.badResponse("网关持仓量历史来源或品种不符")
    }
    var out: [OIPoint] = []
    out.reserveCapacity(page.rows.count)
    for row in page.rows {
      guard row.count >= 2, let t = row[0], let coins = row[1],
            t.isFinite, t > 0, coins.isFinite, coins >= 0 else { continue }
      out.append(OIPoint(time: Int64(t), value: coins))
    }
    return out.sorted { $0.time < $1.time }
  }

  /// 按主、备顺序问。4xx 是这一笔本身的问题（周期不认、品种不认），换主机也一样，直接报。
  static func fetch(hosts: [String], source: String, symbol: String, period: String, limit: Int,
                    endTime: Int64?, transport: any HTTPTransport) async throws -> [OIPoint] {
    var failure: any Error = FeedError.badResponse("持仓量历史暂不可用")
    for host in hosts {
      guard let url = url(host: host, source: source, symbol: symbol, period: period,
                          limit: limit, endTime: endTime) else { continue }
      let reply: HTTPReply
      do { reply = try await transport.get(url, timeout: timeout) }
      catch {
        if error is CancellationError || Task.isCancelled { throw CancellationError() }
        failure = error
        continue
      }
      if reply.status == 200 { return try decode(reply.body, source: source, symbol: symbol) }
      failure = FeedError.badResponse("持仓量历史 HTTP \(reply.status)")
      if (400..<500).contains(reply.status) { throw failure }
    }
    throw failure
  }
}
