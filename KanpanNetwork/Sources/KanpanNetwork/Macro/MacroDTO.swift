import Foundation
import KanpanCore

/// 美元指数（`macro/index/DXY`）的报文。
///
/// 服务端 `kanpan-api` 的 `venues::macro_index` 把它说成**币安形状**：K 线是币安那种混型数组
/// （`KlineRow` 直接能解）、24h 行情是 `ticker/24hr` 对象、推送是 `{"stream","data"}` 组合流。
/// 多出来的只有 `marketState`（`open` / `closed`）与 `prevClosePrice`、`priceSource`。
/// 协议全文见 `docs/美元指数-协议-2026-10-05.md`。
enum MacroDTO {
  static let venue = "macro"
  static let market = "index"
  /// 服务端只采这一只。
  static let symbol = "DXY"
  static let key = InstrumentID(venue: venue, market: market, symbol: symbol).key
  /// 价格步长与小数位（服务端品种表给的也是这两个数）。
  static let tickSize = 0.001
  static let pricePrecision = 3

  /// 服务端不通、品种表还没拿到时也要能搜到、能加自选：内置的这一行和服务端品种表一字不差。
  static let builtin = SymbolInfo(symbol: key, base: symbol, quote: "", pricePrecision: pricePrecision,
                                  quantityPrecision: 0, tickSize: tickSize, underlyingType: "INDEX",
                                  status: .tradable)

  /// 品种键 / 裸代号 → 服务端认的代号（`DXY`）。
  static func wireSymbol(_ key: String) -> String { InstrumentID(key).symbol }

  // ---------------------------------------------------------------- 品种表

  struct Instruments: Decodable { var symbols: [Instrument] }

  struct Instrument: Decodable {
    var symbol: String
    var baseAsset: String?
    var pricePrecision: Int?
    var tickSize: String?
    var status: String?
    var underlyingType: String?

    var symbolInfo: SymbolInfo? {
      let id = InstrumentID(venue: MacroDTO.venue, market: MacroDTO.market, symbol: symbol)
      guard id.isValid else { return nil }
      let tick = tickSize.flatMap(Double.init).flatMap { $0 > 0 ? $0 : nil } ?? MacroDTO.tickSize
      // 休市时服务端照样报 `TRADING`（休市走 `marketState`，不走品种状态）。
      return SymbolInfo(symbol: id.key, base: baseAsset ?? symbol, quote: "",
                        pricePrecision: pricePrecision ?? MacroDTO.pricePrecision, quantityPrecision: 0,
                        tickSize: tick, underlyingType: underlyingType ?? "INDEX",
                        status: SymbolStatus.exchange(status))
    }
  }

  static func instruments(_ data: Data) throws -> [SymbolInfo] {
    do { return try JSONDecoder().decode(Instruments.self, from: data).symbols.compactMap(\.symbolInfo) }
    catch { throw FeedError.badResponse("解不开美元指数品种表：\(error)") }
  }

  // ---------------------------------------------------------------- 24h 行情（REST）

  /// `GET /v1/market/raw/ticker/24hr?source=macro[&symbol=DXY]`：带 symbol 回对象，不带回数组。
  ///
  /// 涨跌是**相对上一交易日收盘**（`prevClosePrice`），不是滚动 24 小时；`priceChange` 可能是 null。
  /// 成交额恒为 0（指数没有成交），按「没有」摆（NaN → 界面写「—」），不能写成 0。
  struct RestTicker: Decodable {
    var symbol: String
    var lastPrice: String
    var priceChange: String?
    var priceChangePercent: String?
    var highPrice: String?
    var lowPrice: String?
    var openPrice: String?
    var closeTime: Int64?
    var marketState: String?

    var ticker: Ticker? {
      guard let last = Double(lastPrice), last.isFinite, last > 0 else { return nil }
      return MacroDTO.ticker(symbol: symbol, last: last, change: priceChange, percent: priceChangePercent,
                             high: highPrice, low: lowPrice, open: openPrice, timeMs: closeTime,
                             state: marketState)
    }
  }

  static func ticker(symbol: String, last: Double, change: String?, percent: String?,
                     high: String?, low: String?, open: String?, timeMs: Int64?, state: String?) -> Ticker {
    func num(_ s: String?) -> Double? { s.flatMap(Double.init).flatMap { $0.isFinite ? $0 : nil } }
    let key = InstrumentID(venue: venue, market: market, symbol: symbol).key
    return Ticker(symbol: key, last: last, changePercent: num(percent) ?? .nan,
                  high: num(high) ?? .nan, low: num(low) ?? .nan, quoteVolume: .nan,
                  open24h: num(open), timeMs: timeMs, priceChange: num(change),
                  marketClosed: isClosed(state))
  }

  /// 只有明确说了 `closed` 才算休市；字段缺失（旧服务端）按开市。
  static func isClosed(_ state: String?) -> Bool { state?.lowercased() == "closed" }

  static func restTicker(_ data: Data) throws -> Ticker {
    guard let t = try? JSONDecoder().decode(RestTicker.self, from: data).ticker else {
      throw FeedError.badResponse("美元指数报价无效")
    }
    return t
  }

  static func restTickers(_ data: Data) throws -> [Ticker] {
    do { return try JSONDecoder().decode([RestTicker].self, from: data).compactMap(\.ticker) }
    catch { throw FeedError.badResponse("解不开美元指数报价：\(error)") }
  }

  // ---------------------------------------------------------------- K 线

  /// 币安形状的数组（`[openTime, o, h, l, c, v, closeTime, …]`），升序；到历史头回 `[]`。
  /// 休市那几段服务端不补，图上就是空着（那不是坏数据）。
  static func bars(_ data: Data) throws -> [Bar] {
    do { return try JSONDecoder().decode([KlineRow].self, from: data).map(\.bar) }
    catch { throw FeedError.badResponse("解不开美元指数 K 线：\(error)") }
  }

  /// 服务端的错误体：`{"error":"invalid_symbol"}`。
  static func errorCode(_ body: Data) -> String? {
    struct E: Decodable { var error: String? }
    return (try? JSONDecoder().decode(E.self, from: body))?.error
  }

  // ---------------------------------------------------------------- 推送

  /// 组合流的一帧：`{"stream":"dxy@ticker","data":{…}}`；控制应答是 `{"result":null,"id":n}`，
  /// 出错是 `{"error":{…},"id":n}`（连接数超限时 `id` 是 null，紧接着服务端断开）。
  struct Envelope: Decodable {
    var stream: String?
    var id: Int?
    var error: ControlError?
  }

  struct ControlError: Decodable {
    var code: Int?
    var msg: String?
  }

  /// `data` 里先只看事件类型与心跳要的两格。
  struct Head: Decodable {
    var e: String?
    var E: Int64?
    var marketState: String?
  }

  /// `24hrTicker` 推送帧（`s c p P h l o C marketState`）。
  struct StreamTicker: Decodable {
    var s: String
    var c: String
    var p: String?
    var P: String?
    var h: String?
    var l: String?
    var o: String?
    var C: Int64?
    var E: Int64?
    var marketState: String?

    var ticker: Ticker? {
      guard let last = Double(c), last.isFinite, last > 0 else { return nil }
      return MacroDTO.ticker(symbol: s, last: last, change: p, percent: P, high: h, low: l, open: o,
                             timeMs: C ?? E, state: marketState)
    }
  }

  private struct Wrapped<T: Decodable>: Decodable { var data: T }

  enum Frame {
    /// 控制帧应答（订阅、退订）。
    case ack(id: Int)
    /// 控制帧被拒（或者连接数超限，`id` 为 nil）。
    case error(id: Int?, message: String)
    /// 每 15 秒一帧，带当前开休市。
    case heartbeat(timeMs: Int64?, closed: Bool)
    case ticker(Ticker, stream: String)
    case kline(KlineEvent, stream: String)
    case other
  }

  static func frame(_ data: Data) -> Frame {
    let decoder = JSONDecoder()
    guard let env = try? decoder.decode(Envelope.self, from: data) else { return .other }
    if let error = env.error {
      return .error(id: env.id, message: error.msg ?? "code \(error.code ?? -1)")
    }
    guard let stream = env.stream else { return env.id.map { .ack(id: $0) } ?? .other }
    guard let head = try? decoder.decode(Wrapped<Head>.self, from: data).data else { return .other }
    switch head.e {
    case "heartbeat":
      return .heartbeat(timeMs: head.E, closed: isClosed(head.marketState))
    case "24hrTicker":
      guard let t = try? decoder.decode(Wrapped<StreamTicker>.self, from: data).data.ticker else { return .other }
      return .ticker(t, stream: stream)
    case "kline":
      guard var k = try? decoder.decode(Wrapped<KlineEvent>.self, from: data).data else { return .other }
      k.symbol = InstrumentID(venue: venue, market: market, symbol: k.symbol).key
      // 指数没有成交，`L` 恒为 -1：不能拿来比新旧（会把每一帧都判成「同一笔」）。
      k.lastTradeID = nil
      return .kline(k, stream: stream)
    default:
      return .other
    }
  }

  /// 订阅 → 服务端流名（`dxy@ticker`、`dxy@kline_15m`）。没有的（标记价、逐笔、盘口）不订。
  static func streamName(_ topic: StreamTopic) -> String? {
    let s = wireSymbol(topic.symbol).lowercased()
    switch topic {
    case .ticker: return "\(s)@ticker"
    case .kline(_, let iv): return "\(s)@kline_\(iv.rawValue)"
    case .markPrice, .trade, .aggTrade, .depth: return nil
    }
  }
}
