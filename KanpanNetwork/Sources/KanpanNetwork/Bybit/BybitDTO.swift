import Foundation
import KanpanCore

// Bybit v5 公开行情的报文。数值一律是字符串、时间戳是毫秒（有的是字符串）、K 线与持仓量历史按时间**降序**给，
// REST 一律包在 `{"retCode":0,"retMsg":"OK","result":{…},"time":…}` 里（出错时 HTTP 也可能是 200，看 `retCode`）——
// 全在这一层翻成看盘的口径（毫秒、Double、升序），出了这个文件夹谁都不认识 Bybit 的格式。
//
// 这是 Bybit **唯一**的报文解码：行情提供者（REST）、行情推送（`BybitWire`）、订单流（`BybitBooksAdapter`）都调这里。
// 身份与代号互译在 `BybitVenue`。
//
// 夹具来源：容器连不上交易所，REST / 行情推送的字段按 Bybit v5 官方文档（Market › Get Instruments Info /
// Get Tickers / Get Kline / Get Open Interest，WebSocket › Public › Ticker / Kline / Trade）写；
// 订单流那两种帧（`orderbook.1000`、`publicTrade`）是 2026-10-08 经 kanpan-api 中继录的真帧。
enum BybitDTO {
  // ---------------------------------------------------------------- REST 信封

  /// 限流时 Bybit 也可能回 HTTP 200 + `retCode 10006`。
  static let rateLimitedCode = 10006

  struct Header: Decodable { var retCode: Int; var retMsg: String? }

  struct Envelope<R: Decodable>: Decodable {
    var result: R?
    var time: Int64?
  }

  /// 拆信封：`retCode` 不是 0 就是没拿到。10006 按限流报（调用方罚这一家的限速器）。
  static func result<R: Decodable>(_ type: R.Type, _ data: Data, what: String) throws -> (result: R, timeMs: Int64?) {
    // 先只看 `retCode`：出错时 `result` 往往是 `{}`，按 R 去解会把真正的原因（限流、参数错）盖掉。
    let header: Header
    do { header = try JSONDecoder().decode(Header.self, from: data) }
    catch { throw FeedError.badResponse("解不开 Bybit \(what)：\(error)") }
    guard header.retCode == 0 else {
      if header.retCode == rateLimitedCode {
        throw UpstreamError(status: 429, code: header.retCode, msg: header.retMsg, reason: .rateLimited)
      }
      throw FeedError.badResponse("Bybit \(what)：\(header.retMsg ?? "retCode \(header.retCode)")")
    }
    let envelope: Envelope<R>
    do { envelope = try JSONDecoder().decode(Envelope<R>.self, from: data) }
    catch { throw FeedError.badResponse("解不开 Bybit \(what)：\(error)") }
    guard let result = envelope.result else { throw FeedError.badResponse("Bybit \(what)为空") }
    return (result, envelope.time)
  }

  /// 错误体 → 给人看的一句话（`VenueREST.message`）：Bybit 写在 `retMsg`。
  static let errorMessage: @Sendable (Data) -> String? = { body in
    struct E: Decodable { var retMsg: String?; var message: String?; var msg: String? }
    let e = try? JSONDecoder().decode(E.self, from: body)
    return e?.retMsg ?? e?.message ?? e?.msg
  }

  // ---------------------------------------------------------------- 品种表

  struct Instruments: Decodable {
    var list: [Instrument]
    var nextPageCursor: String?
    private enum CodingKeys: String, CodingKey { case list, nextPageCursor }
    init(from decoder: Decoder) throws {
      let c = try decoder.container(keyedBy: CodingKeys.self)
      // 坏一行只丢那一行：几百个合约里有一行缺了字段，不能让整张品种表解不开。
      list = try c.decode(LenientList<Instrument>.self, forKey: .list).items
      nextPageCursor = try c.decodeIfPresent(String.self, forKey: .nextPageCursor)
    }
  }

  struct Instrument: Decodable {
    struct PriceFilter: Decodable { var tickSize: String? }
    struct LotSizeFilter: Decodable { var qtyStep: String? }
    var symbol: String
    var contractType: String?
    var status: String?
    var baseCoin: String?
    var quoteCoin: String?
    var launchTime: String?
    var priceScale: String?
    var priceFilter: PriceFilter?
    var lotSizeFilter: LotSizeFilter?

    /// 准入：USDT 计价的线性永续，代号是看盘收的形状。
    var isListed: Bool {
      quoteCoin == BybitVenue.quote && contractType == "LinearPerpetual" && BybitVenue.isListedSymbol(symbol)
    }

    var symbolInfo: SymbolInfo? {
      guard let tickText = priceFilter?.tickSize, let tick = Double(tickText), tick.isFinite, tick > 0 else { return nil }
      let step = lotSizeFilter?.qtyStep
      return SymbolInfo(symbol: BybitVenue.key(symbol),
                        // `1000PEPEUSDT` 的 baseCoin 是 `1000PEPE`：原样（订单流按 base 找五家的簿时自己折倍数）。
                        base: (baseCoin?.isEmpty == false ? baseCoin! : String(symbol.dropLast(BybitVenue.quote.count))).uppercased(),
                        quote: BybitVenue.quote,
                        pricePrecision: BybitDTO.decimals(tickText),
                        quantityPrecision: step.map(BybitDTO.decimals) ?? 3,
                        tickSize: tick,
                        // 全是币：按币安 `underlyingType` 的口径标 `COIN`，徽章、筛选、自选分类认它。
                        underlyingType: "COIN",
                        contractType: "PERPETUAL",
                        status: BybitDTO.status(status),
                        onboardDate: launchTime.flatMap { Int64($0) }.flatMap { $0 > 0 ? $0 : nil })
    }
  }

  /// Bybit 的合约状态：`PreLaunch` 还没开盘、`Trading` 正常、`Delivering` / `Closed` / `Settling` 不会再开。
  static func status(_ raw: String?) -> SymbolStatus {
    switch raw {
    case "Trading": .tradable
    case "PreLaunch": .pending
    case "Delivering", "Closed", "Settling": .delisted
    default: SymbolStatus.exchange(raw)
    }
  }

  /// 步长要几位小数才写得下：**按交易所给的那串字面数**，末尾的 0 不算（`0.10` 是 1 位，`0.25` 是 2 位）。
  static func decimals(_ text: String) -> Int {
    let t = text.trimmingCharacters(in: .whitespaces).lowercased()
    if let e = t.firstIndex(of: "e") {
      let exponent = Int(t[t.index(after: e)...]) ?? 0
      return max(0, min(12, decimals(String(t[..<e])) - exponent))
    }
    guard let dot = t.firstIndex(of: ".") else { return 0 }
    let fraction = t[t.index(after: dot)...].reversed().drop { $0 == "0" }
    return max(0, min(12, fraction.count))
  }

  // ---------------------------------------------------------------- 24h 行情 / 资金费率

  struct Tickers: Decodable {
    var list: [TickerRow]
    private enum CodingKeys: String, CodingKey { case list }
    init(from decoder: Decoder) throws {
      let c = try decoder.container(keyedBy: CodingKeys.self)
      list = try c.decode(LenientList<TickerRow>.self, forKey: .list).items
    }
  }

  /// `/v5/market/tickers?category=linear` 的一行：价、额、标记价、持仓量、费率一条全有。
  struct TickerRow: Decodable {
    var symbol: String
    var lastPrice: String?
    var markPrice: String?
    var indexPrice: String?
    var prevPrice24h: String?
    var price24hPcnt: String?
    var highPrice24h: String?
    var lowPrice24h: String?
    var turnover24h: String?
    var volume24h: String?
    var openInterest: String?
    var fundingRate: String?
    var nextFundingTime: String?

    var isListed: Bool { BybitVenue.isListedSymbol(symbol) }

    func ticker(timeMs: Int64?) -> Ticker? {
      BybitDTO.ticker(symbol: symbol, last: num(lastPrice), prev: num(prevPrice24h), pcnt: num(price24hPcnt),
                      high: num(highPrice24h), low: num(lowPrice24h), turnover: num(turnover24h),
                      mark: num(markPrice), timeMs: timeMs)
    }

    var funding: FundingSnapshot? {
      guard let rate = num(fundingRate) else { return nil }
      return FundingSnapshot(rate: rate, nextFundingTimeMs: nextFundingTime.flatMap { Int64($0) }.flatMap { $0 > 0 ? $0 : nil })
    }
  }

  /// 字符串 → 有限的数；空串、解不动、`inf` 都是「没有」。
  static func num(_ text: String?) -> Double? {
    guard let text, !text.isEmpty, let v = Double(text), v.isFinite else { return nil }
    return v
  }

  /// Bybit 口径的 24h 行情 → 看盘的 `Ticker`（REST 一行与推送合并后的快照同一个口径）。
  ///
  /// - 额：`turnover24h` 就是计价额（USDT），不用近似。
  /// - 涨跌幅：`price24hPcnt` 是小数（`0.0123` = 1.23%）；没给就拿 24h 前的价反推。
  /// - 24h 开盘价取 `prevPrice24h`，振幅才有分母；涨跌额 = 现价 − 它。
  static func ticker(symbol: String, last: Double?, prev: Double?, pcnt: Double?, high: Double?, low: Double?,
                     turnover: Double?, mark: Double?, timeMs: Int64?) -> Ticker? {
    guard let last, last > 0 else { return nil }
    let open = prev.flatMap { $0 > 0 ? $0 : nil }
    let pct = pcnt.map { $0 * 100 } ?? open.map { (last / $0 - 1) * 100 }
    return Ticker(symbol: BybitVenue.key(symbol), last: last, changePercent: pct ?? .nan,
                  high: high ?? .nan, low: low ?? .nan, quoteVolume: turnover ?? .nan,
                  markPrice: mark.flatMap { $0 > 0 ? $0 : nil }, open24h: open, timeMs: timeMs,
                  priceChange: open.map { last - $0 })
  }

  // ---------------------------------------------------------------- K 线

  struct Klines: Decodable {
    var list: [[String]]
  }

  /// K 线页：降序 → 升序、字符串 → Double。行是 `[start, open, high, low, close, volume(币), turnover(计价)]`。
  static func bars(_ data: Data) throws -> [Bar] {
    let page = try result(Klines.self, data, what: "K 线").result
    return page.list.compactMap { row -> Bar? in
      guard row.count >= 6, let t = Int64(row[0]), let o = num(row[1]), let h = num(row[2]), let l = num(row[3]),
            let c = num(row[4]), let v = num(row[5]) else { return nil }
      // Bybit 不给主动买量：留 NaN，不填 0（见 `Bar.takerBuy`）。
      let bar = Bar(openTime: t, open: o, high: h, low: l, close: c, volume: v)
      return bar.isValidMarketBar ? bar : nil
    }.sorted { $0.openTime < $1.openTime }
  }

  // ---------------------------------------------------------------- 持仓量历史

  struct OpenInterest: Decodable {
    struct Row: Decodable { var openInterest: String; var timestamp: String }
    var list: [Row]
    var nextPageCursor: String?
  }

  /// 持仓量历史一页：降序 → 升序，`openInterest` 是币的个数（和币安 `sumOpenInterest` 同口径）。
  static func openInterest(_ data: Data) throws -> [OIPoint] {
    let page = try result(OpenInterest.self, data, what: "持仓量").result
    return page.list.compactMap { row -> OIPoint? in
      guard let t = Int64(row.timestamp), t > 0, let v = num(row.openInterest), v >= 0 else { return nil }
      return OIPoint(time: t, value: v)
    }.sorted { $0.time < $1.time }
  }
}

// ---------------------------------------------------------------- 行情推送

extension BybitDTO {
  /// `tickers.*` 推送的快照簿：`snapshot` 整份替换，`delta` **只带变化的字段**，按品种合并到上一份上再出 `Ticker`。
  /// 一条推送连接一份（`BybitWire` 持有），重连后 Bybit 先补一帧 snapshot，自然对上。
  final class TickerBook: @unchecked Sendable {
    private let lock = NSLock()
    private var rows: [String: [String: Any]] = [:]

    init() {}

    /// 合并一帧，返回合并后的整份。delta 里的空串不覆盖旧值（那是「没有」，不是「变成空」）。
    func merge(symbol: String, snapshot: Bool, data: [String: Any]) -> [String: Any] {
      lock.lock(); defer { lock.unlock() }
      var row = snapshot ? [:] : rows[symbol] ?? [:]
      for (k, v) in data {
        if !snapshot, let s = v as? String, s.isEmpty { continue }
        row[k] = v
      }
      rows[symbol] = row
      return row
    }
  }

  /// 这几样变了才出一条 `Ticker`；这几样变了才出一条标记价。
  private static let tickerFields: Set<String> = ["lastPrice", "prevPrice24h", "price24hPcnt", "highPrice24h",
                                                  "lowPrice24h", "turnover24h", "volume24h"]
  private static let markFields: Set<String> = ["markPrice", "indexPrice", "fundingRate", "nextFundingTime"]

  /// 一帧推送解出来的东西（`BybitWire.decode` 再包成 `VenueWireFrame`）。
  struct WireFrame {
    var payloads: [StreamPayload] = []
    /// 这一帧证明生效了的 topic（数据帧本身的 topic；订阅应答不列 topic）。
    var confirmed: [String] = []
    var error: String?
    /// 报错帧里点了名的 topic。
    var rejected: [String]?
  }

  /// 行情推送的一帧文本。认得三种数据帧（`tickers` / `kline` / `publicTrade`）和控制应答；
  /// pong、订阅成功的应答、别的 topic 都是空帧。
  static func wire(_ text: String, tickers book: TickerBook) -> WireFrame {
    guard let frame = DepthWire.object(text) else { return WireFrame() }
    guard let topic = frame["topic"] as? String else { return control(frame) }
    let ts = DepthWire.integer(frame["ts"])
    var out = WireFrame(confirmed: [topic])
    if topic.hasPrefix("tickers.") {
      guard let data = frame["data"] as? [String: Any] else { return WireFrame() }
      let symbol = (data["symbol"] as? String) ?? String(topic.dropFirst("tickers.".count))
      let snapshot = (frame["type"] as? String) != "delta"
      let row = book.merge(symbol: symbol, snapshot: snapshot, data: data)
      out.payloads = tickerPayloads(symbol: symbol, row: row, changed: Set(data.keys), snapshot: snapshot, ts: ts)
    } else if topic.hasPrefix("kline.") {
      out.payloads = klinePayloads(topic: topic, frame["data"], ts: ts)
    } else if topic.hasPrefix("publicTrade.") {
      out.payloads = tradePayloads(frame["data"])
    } else {
      return WireFrame()
    }
    return out
  }

  /// 订阅 / 退订应答：`success == false` 是被拒；报错文里点了名的 topic 记到它们头上（`Invalid symbol :[tickers.XUSDT]`
  /// 这类），没点名的归最近一发控制帧（`VenueStream` 管）。「已经订过」不算错，那个 topic 是活的。
  private static func control(_ frame: [String: Any]) -> WireFrame {
    guard let op = frame["op"] as? String, op == "subscribe" || op == "unsubscribe",
          (frame["success"] as? Bool) == false else { return WireFrame() }
    let message = (frame["ret_msg"] as? String) ?? "subscribe failed"
    let named = topics(in: message)
    if message.lowercased().contains("already subscribed") { return WireFrame(confirmed: named) }
    return WireFrame(error: message, rejected: named.isEmpty ? nil : named)
  }

  /// 报错文里出现的 topic（`tickers.X` / `kline.N.X` / `publicTrade.X`）。
  static func topics(in message: String) -> [String] {
    var allowed = CharacterSet.alphanumerics
    allowed.insert(".")
    return message.components(separatedBy: allowed.inverted).filter {
      ($0.hasPrefix("tickers.") || $0.hasPrefix("kline.") || $0.hasPrefix("publicTrade.")) && !$0.hasSuffix(".")
    }
  }

  private static func tickerPayloads(symbol: String, row: [String: Any], changed: Set<String>, snapshot: Bool,
                                     ts: Int64?) -> [StreamPayload] {
    func n(_ k: String) -> Double? { DepthWire.number(row[k]).flatMap { $0.isFinite ? $0 : nil } }
    var out: [StreamPayload] = []
    if snapshot || !changed.isDisjoint(with: tickerFields),
       let t = ticker(symbol: symbol, last: n("lastPrice"), prev: n("prevPrice24h"), pcnt: n("price24hPcnt"),
                      high: n("highPrice24h"), low: n("lowPrice24h"), turnover: n("turnover24h"),
                      mark: n("markPrice"), timeMs: ts) {
      out.append(.ticker(t))
    }
    if snapshot || !changed.isDisjoint(with: markFields), let mark = n("markPrice"), mark > 0 {
      let tick = MarkPriceTick(timeMs: ts ?? 0, fundingRate: n("fundingRate"),
                               nextFundingTimeMs: DepthWire.integer(row["nextFundingTime"]).flatMap { $0 > 0 ? $0 : nil },
                               indexPrice: n("indexPrice"))
      out.append(.markPrice(symbol: BybitVenue.key(symbol), price: mark, tick: tick))
    }
    return out
  }

  /// `kline.<interval>.<代号>` 的 data：一到多根，`confirm == true` 是收了。
  private static func klinePayloads(topic: String, _ raw: Any?, ts: Int64?) -> [StreamPayload] {
    let parts = topic.split(separator: ".", maxSplits: 2).map(String.init)
    guard parts.count == 3, let interval = BybitVenue.interval(wire: parts[1]),
          let rows = raw as? [[String: Any]] else { return [] }
    var out: [(Int64, StreamPayload)] = []
    for k in rows {
      guard let start = DepthWire.integer(k["start"]) else { continue }
      // 解不开、不是有限值（`nan`、`inf`、`1e400`）或越界：整帧丢掉并记一笔（末根的量成了 NaN，整根都画不对）。
      guard let o = DepthWire.number(k["open"]), let h = DepthWire.number(k["high"]), let l = DepthWire.number(k["low"]),
            let c = DepthWire.number(k["close"]), let v = DepthWire.number(k["volume"]) else {
        WireNumber.noteDropped(); return []
      }
      let bar = Bar(openTime: start, open: o, high: h, low: l, close: c, volume: v)
      guard bar.isValidMarketBar else { WireNumber.noteDropped(); return [] }
      out.append((start, .kline(KlineEvent(symbol: BybitVenue.key(parts[2]), interval: interval.rawValue,
                                           openTime: start, closed: (k["confirm"] as? Bool) ?? false, bar: bar,
                                           eventTime: DepthWire.integer(k["timestamp"]) ?? ts ?? 0))))
    }
    return out.sorted { $0.0 < $1.0 }.map(\.1)
  }

  /// `publicTrade.<代号>` 的 data：`T` 成交时刻、`p` 价、`v` 量、`S` 主动方。按成交时刻升序。
  private static func tradePayloads(_ raw: Any?) -> [StreamPayload] {
    guard let rows = raw as? [[String: Any]] else { return [] }
    var out: [TradeEvent] = []
    for t in rows {
      guard let symbol = t["s"] as? String, let ms = DepthWire.integer(t["T"]) else { continue }
      // 坏价量：整帧丢掉并记一笔（坏帧里别的成交同样不可信，成交量一旦折进 NaN 整根就废了）。
      guard let p = DepthWire.number(t["p"]), let q = DepthWire.number(t["v"]),
            p.isFinite, q.isFinite, p > 0, q >= 0 else { WireNumber.noteDropped(); return [] }
      // 成交号 `i` 是 UUID，不是递增整数，不填。
      out.append(TradeEvent(symbol: BybitVenue.key(symbol), price: p, qty: q, timeMs: ms))
    }
    return out.enumerated().sorted { ($0.element.timeMs, $0.offset) < ($1.element.timeMs, $1.offset) }
      .map { .trade($0.element) }
  }
}

// ---------------------------------------------------------------- 订单流（orderbook.1000 + publicTrade）

extension BybitDTO {
  /// 订单流那条连接上的一帧 → 这条连接上各本簿的消息（`BybitBooksAdapter.decode` 调它）。
  ///
  /// - `orderbook.<levels>`：`type=snapshot` 整本（`u == 1` 是 Bybit 那边服务重启，整本重来）、`delta` 按 `u` 接，
  ///   数量 `0` 删档；每侧只有盘口最近 `levels` 档，快照标 `slidingWindow`。
  /// - `publicTrade` 的 `S` 是主动方（Buy 吃卖盘）。
  /// - 回执、pong、别的 topic（强平）都不认。`books` 的键是 Bybit 代号。
  static func orderFlow(_ text: String, books: [String: DepthBook], levels: Int) -> [VenueMessage] {
    guard let frame = DepthWire.object(text), let topic = frame["topic"] as? String else { return [] }
    if topic.hasPrefix("orderbook.") { return orderFlowBook(frame, topic: topic, books: books, levels: levels) }
    if topic.hasPrefix("publicTrade.") { return orderFlowTrades(frame, topic: topic, books: books) }
    return []
  }

  private static func orderFlowBook(_ frame: [String: Any], topic: String, books: [String: DepthBook],
                                    levels: Int) -> [VenueMessage] {
    guard let data = frame["data"] as? [String: Any],
          let symbol = data["s"] as? String, let book = books[symbol],
          topic == BybitVenue.bookTopic(levels: levels, symbol),
          let u = DepthWire.integer(data["u"]),
          let bids = book.levels(data["b"]), let asks = book.levels(data["a"]) else { return [] }
    let time = DepthWire.integer(frame["ts"])
    switch frame["type"] as? String {
    case "snapshot":
      guard bids.count <= levels, asks.count <= levels else { return [] }
      return [VenueMessage(book.id, .snapshot(BookSnapshot(lastUpdateID: u, requestedLevels: levels,
                                                           bids: bids, asks: asks, eventTimeMs: time,
                                                           slidingWindow: true, restartsSequence: u == 1)))]
    case "delta":
      return [VenueMessage(book.id, .delta(BookDelta(firstUpdateID: u, finalUpdateID: u, previousFinalUpdateID: nil,
                                                    bids: bids, asks: asks, eventTimeMs: time ?? 0)))]
    default:
      return []
    }
  }

  private static func orderFlowTrades(_ frame: [String: Any], topic: String,
                                      books: [String: DepthBook]) -> [VenueMessage] {
    guard let items = frame["data"] as? [[String: Any]] else { return [] }
    var out: [VenueMessage] = []
    for t in items {
      guard let symbol = t["s"] as? String, let book = books[symbol], topic == BybitVenue.tradeTopic(symbol) else { continue }
      // 价量解得开却不是有限值或越界：整帧丢掉并记一笔（坏帧里别的成交同样不可信）。
      guard let p = DepthWire.number(t["p"]), let q = DepthWire.number(t["v"]),
            p > 0, q >= 0, p.isFinite, q.isFinite else { WireNumber.noteDropped(); return [] }
      guard q > 0, let side = t["S"] as? String, side == "Buy" || side == "Sell" else { continue }
      out.append(VenueMessage(book.id, .trade(book.trade(price: p, quantity: q, hit: side == "Buy" ? .ask : .bid,
                                                         timeMs: DepthWire.integer(t["T"]) ?? 0))))
    }
    return out
  }
}
