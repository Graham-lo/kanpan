import Foundation
import KanpanCore

/// 网关线路上替身自己的 24h 行情：kanpan-api 的 `/v1/market/ticker?source=<替身>&symbol=`。
///
/// 为什么不用网关原有的 `/market/v1/ticker`：那一条把 OKX 的行情翻成币安形状时
/// `quoteVolume` 是空串（OKX 只给币的个数），顶栏「额」在这条线路上就永远是「—」。
/// 服务端这一条按 OKX 自己的数算：24h 成交的币数 × OKX 近 24h 的成交均价
/// （`Σ volCcyQuote ÷ Σ volCcy`，都来自 OKX 的 5 分钟 K 线），换成 USDT 成交额。
/// 价格、开盘、高低、涨跌都是 OKX 滚动 24 小时的原数，和币安 `/fapi/v1/ticker/24hr` 同一个口径。
///
/// 不混源：回来的 `source` 对不上就不收。
enum GatewayTicker {
  static let path = "/v1/market/ticker"

  static func url(host: String, source: String, symbol: String) -> URL? {
    // `host` 可能带端口（备用网关是 `…:8443`），不能直接塞进 `URLComponents.host`。
    guard var c = URLComponents(string: "https://\(host)"), c.host != nil,
          c.user == nil, c.password == nil else { return nil }
    c.path = path
    c.queryItems = [URLQueryItem(name: "source", value: source),
                    URLQueryItem(name: "symbol", value: InstrumentID(symbol).symbol)]
    return c.url
  }

  private struct Envelope: Decodable {
    struct Body: Decodable {
      var source: String
      var ticker: Ticker24hDTO
    }
    var data: Body
  }

  static func decode(_ body: Data, source: String, symbol: String) throws -> Ticker {
    let reply: Envelope.Body
    do { reply = try JSONDecoder().decode(Envelope.self, from: body).data }
    catch { throw FeedError.badResponse("解不开网关 24h 行情：\(error)") }
    guard reply.source == source else { throw FeedError.badResponse("网关 24h 行情来源不符") }
    let ticker = reply.ticker.ticker
    guard ticker.symbol == InstrumentID.canonical(symbol), ticker.last.isFinite, ticker.last > 0 else {
      throw FeedError.badResponse("报价品种或价格无效")
    }
    return ticker
  }

  /// 按主、备顺序问。4xx 是这一笔本身的问题（品种不认、来源不认），换主机也一样，直接报。
  static func fetch(hosts: [String], source: String, symbol: String, timeout: TimeInterval,
                    transport: any HTTPTransport) async throws -> Ticker {
    var failure: any Error = FeedError.badResponse("24h 行情暂不可用")
    for host in hosts {
      guard let url = url(host: host, source: source, symbol: symbol) else { continue }
      let reply: HTTPReply
      do { reply = try await transport.get(url, timeout: timeout) }
      catch {
        if error is CancellationError || Task.isCancelled { throw CancellationError() }
        failure = error
        continue
      }
      if reply.status == 200 { return try decode(reply.body, source: source, symbol: symbol) }
      failure = FeedError.badResponse("24h 行情 HTTP \(reply.status)")
      if (400..<500).contains(reply.status) { throw failure }
    }
    throw failure
  }
}
