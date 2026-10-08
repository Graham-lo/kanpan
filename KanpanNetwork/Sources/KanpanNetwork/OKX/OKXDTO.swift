import Foundation
import KanpanCore

// OKX v5 公开行情的报文。数值一律是字符串、时间戳是毫秒字符串，K 线按时间**降序**给——
// 全在这一层翻成看盘的口径（Double、升序），出了这个文件夹谁都不认识 OKX 的格式。
//
// 这是 OKX **唯一**的报文解码：行情提供者（REST）、行情推送（`OKXWire`）、订单流（`OKXBooksAdapter`）
// 都调这里。身份、代号与周期互译在 `OKXVenue`。
//
// 报文形状按 OKX 官方 API v5 文档（2026-09 现行版：Public Data / Market Data / WebSocket 各节）
// 与服务端 `Backend/kanpan-api/src/venues/okx/` 里的线上实录整理；容器连不上 OKX，没有新录的帧。
enum OKXDTO {
  // ---------------------------------------------------------------- 信封

  /// REST 的外层：`{"code":"0","msg":"","data":[…]}`。`code` 不是 `"0"` 就是出错（HTTP 照样可能是 200）。
  /// 坏一行只丢那一行（`LenientList`）。
  struct Envelope<Row: Decodable>: Decodable {
    var code: String?
    var msg: String?
    var data: [Row]

    private enum CodingKeys: String, CodingKey { case code, msg, data }
    init(from decoder: Decoder) throws {
      let c = try decoder.container(keyedBy: CodingKeys.self)
      // `code` 文档写的是字符串，个别接口回数字：两种都认。
      if let s = try? c.decode(String.self, forKey: .code) { code = s }
      else { code = (try? c.decode(Int.self, forKey: .code)).map(String.init) }
      msg = try c.decodeIfPresent(String.self, forKey: .msg)
      data = try c.decodeIfPresent(LenientList<Row>.self, forKey: .data)?.items ?? []
    }
  }

  /// 解一页 REST 答复，`code != "0"` 当错误报（带上 OKX 的 `msg`）。
  static func rows<Row: Decodable>(_ data: Data, _ what: String) throws -> [Row] {
    let page: Envelope<Row>
    do { page = try JSONDecoder().decode(Envelope<Row>.self, from: data) }
    catch { throw FeedError.badResponse("解不开 OKX \(what)：\(error)") }
    if let code = page.code, code != "0" {
      throw FeedError.badResponse("OKX \(what)出错（\(code)）：\(page.msg ?? "")")
    }
    return page.data
  }

  // ---------------------------------------------------------------- 品种表

  /// `GET /api/v5/public/instruments?instType=SWAP` 的一行。
  struct Instrument: Decodable {
    var instId: String
    var instType: String?
    var ctType: String?
    var settleCcy: String?
    var ctVal: String?
    var ctValCcy: String?
    var tickSz: String?
    var lotSz: String?
    var state: String?
    var listTime: String?

    /// 准入：USDT 结算的线性永续（`BASE-USDT-SWAP`），上线、停牌、待上市都留（状态在 `SymbolInfo.status` 里说）。
    var isListed: Bool {
      settleCcy?.uppercased() == OKXVenue.quote && ctType == "linear"
        && OKXVenue.baseOf(instID: instId) != nil
        && (instType == nil || instType == "SWAP")
    }

    /// 一张合约是多少个币（只认以底名计的面值；`ctValCcy` 缺了按底名算）。
    var contractValue: Double? {
      guard let v = ctVal.flatMap(Double.init), v.isFinite, v > 0 else { return nil }
      if let ccy = ctValCcy, !ccy.isEmpty, ccy.uppercased() != OKXVenue.baseOf(instID: instId) { return nil }
      return v
    }

    var symbolInfo: SymbolInfo? {
      guard let key = OKXVenue.key(instID: instId), let base = OKXVenue.baseOf(instID: instId),
            let tick = tickSz.flatMap(Double.init), tick.isFinite, tick > 0 else { return nil }
      // 数量精度按「一手合约是多少个币」的字面小数位：ctVal 0.01 × lotSz 0.01 → 0.0001 BTC → 4 位。
      let qty = min(12, (ctVal.map(OKXDTO.decimals) ?? 0) + (lotSz.map(OKXDTO.decimals) ?? 0))
      return SymbolInfo(symbol: key, base: base, quote: OKXVenue.quote,
                        pricePrecision: OKXDTO.decimals(tickSz ?? "0"), quantityPrecision: qty,
                        tickSize: tick, underlyingType: "COIN", contractType: "PERPETUAL",
                        // live → 正常、suspend → 停牌、preopen → 待上市（`SymbolStatus.exchange` 认这几个词）。
                        status: SymbolStatus.exchange(state),
                        onboardDate: listTime.flatMap { Int64($0) }.flatMap { $0 > 0 ? $0 : nil })
    }
  }

  /// 步长要几位小数才写得下：按交易所给的那串字面数，末尾的 0 不算；科学计数法按指数折算
  /// （`0.25` 是两位，不是 `⌈-log10⌉` 算出来的一位）。
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

  // ---------------------------------------------------------------- 24h 行情

  /// `GET /api/v5/market/ticker(s)` 的一行，也是 `tickers` 推送的 data 行。
  struct TickerRow: Decodable {
    var instId: String
    var last: String?
    var open24h: String?
    var high24h: String?
    var low24h: String?
    var volCcy24h: String?
    var ts: String?

    var ticker: Ticker? {
      OKXDTO.ticker(instID: instId, last: last, open: open24h, high: high24h, low: low24h,
                    baseVolume: volCcy24h, ts: ts)
    }
  }

  /// OKX 口径的 24h 行情 → 看盘的 `Ticker`。
  ///
  /// - 额：OKX 的 ticker **没有计价成交额**，只有张数（`vol24h`）与币数（`volCcy24h`）。
  ///   按「币数 × 现价」近似（和 Coinbase 同一条已拍板的口径；REST 与推送两边同一个算法，刷新时不跳）。
  /// - 涨跌：滚动 24 小时，`(last / open24h − 1) × 100`，涨跌额 `last − open24h`（和币安同一个定义）。
  static func ticker(instID: String, last: String?, open: String?, high: String?, low: String?,
                     baseVolume: String?, ts: String?) -> Ticker? {
    guard let key = OKXVenue.key(instID: instID),
          let last = last.flatMap(finiteDouble), last > 0 else { return nil }
    let open24h = open.flatMap(finiteDouble).flatMap { $0 > 0 ? $0 : nil }
    return Ticker(symbol: key, last: last,
                  changePercent: open24h.map { (last / $0 - 1) * 100 } ?? .nan,
                  high: high.flatMap(finiteDouble) ?? .nan, low: low.flatMap(finiteDouble) ?? .nan,
                  quoteVolume: (baseVolume.flatMap(finiteDouble) ?? .nan) * last,
                  open24h: open24h, timeMs: ts.flatMap { Int64($0) },
                  priceChange: open24h.map { last - $0 })
  }

  // ---------------------------------------------------------------- K 线

  /// 一行 K 线：`[ts, o, h, l, c, vol(张), volCcy(币), volCcyQuote(计价), confirm]`（REST 与推送同形）。
  /// 成交量取 `volCcy`（币数，和币安 `volume` 同一单位）；OKX 不给主动买量，留 NaN。
  static func bar(_ row: [String]) -> (bar: Bar, closed: Bool)? {
    guard row.count >= 7, let t = Int64(row[0]), let o = Double(row[1]), let h = Double(row[2]),
          let l = Double(row[3]), let c = Double(row[4]), let v = Double(row[6]) else { return nil }
    let bar = Bar(openTime: t, open: o, high: h, low: l, close: c, volume: v)
    guard bar.isValidMarketBar else { return nil }
    return (bar, row.count > 8 ? row[8] == "1" : false)
  }

  /// K 线页：降序 → 升序、字符串 → Double。坏行只丢那一行。
  static func bars(_ data: Data) throws -> [Bar] {
    let page: [[String]] = try rows(data, "K 线")
    return page.compactMap { bar($0)?.bar }.sorted { $0.openTime < $1.openTime }
  }

  // ---------------------------------------------------------------- 资金费率

  /// `GET /api/v5/public/funding-rate?instId=` 的一行，也是 `funding-rate` 推送的 data 行。
  /// `fundingRate` 是下一次结算（`fundingTime`）要用的费率；OKX 的 `nextFundingTime` 是再下一期，不用它。
  struct FundingRow: Decodable {
    var instId: String
    var fundingRate: String?
    var fundingTime: String?
    var ts: String?

    var snapshot: FundingSnapshot? {
      guard let rate = fundingRate.flatMap(finiteDouble) else { return nil }
      return FundingSnapshot(rate: rate, nextFundingTimeMs: fundingTime.flatMap { Int64($0) }.flatMap { $0 > 0 ? $0 : nil })
    }
  }

  // ---------------------------------------------------------------- kanpan-api 的两份（持仓量历史、费率整表）

  /// kanpan-api `/v1/market/open-interest/history?source=okx` 的答复：
  /// `{"data":{"source":"okx","symbol":"BTCUSDT","period":"5m","rows":[[毫秒, 币的个数, 美元名义值|null], …]}}`，
  /// 时间升序（`Backend/kanpan-api/src/venues/okx/mod.rs` 的 `oi_history_payload`）。取币的个数。
  /// 不混源：`source` / `symbol` 对不上就整页不收。
  static func openInterestHistory(_ body: Data, symbol: String) throws -> [OIPoint] {
    struct Page: Decodable { var source: String; var symbol: String; var rows: [[Double?]] }
    struct Wrapped: Decodable { var data: Page }
    let page: Page
    do { page = try JSONDecoder().decode(Wrapped.self, from: body).data }
    catch { throw FeedError.badResponse("解不开 OKX 持仓量历史：\(error)") }
    guard page.source == OKXVenue.id, page.symbol.uppercased() == InstrumentID(symbol).symbol else {
      throw FeedError.badResponse("OKX 持仓量历史来源或品种不符")
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

  /// kanpan-api `/v1/market/funding?source=okx` 的答复：
  /// `{"data":{"source":"okx","rows":[{"symbol":"BTCUSDT","rate":0.0001,"nextFundingTime":毫秒}, …]}}`。
  /// 键翻成完整品种键（`okx/usd_m/BTCUSDT`）。
  static func fundingTable(_ body: Data) throws -> [String: FundingSnapshot] {
    struct Row: Decodable { var symbol: String; var rate: Double; var nextFundingTime: Int64? }
    struct Page: Decodable {
      var source: String
      var rows: [Row]
      private enum CodingKeys: String, CodingKey { case source, rows }
      init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        source = try c.decode(String.self, forKey: .source)
        rows = try c.decode(LenientList<Row>.self, forKey: .rows).items
      }
    }
    struct Wrapped: Decodable { var data: Page }
    let page: Page
    do { page = try JSONDecoder().decode(Wrapped.self, from: body).data }
    catch { throw FeedError.badResponse("解不开 OKX 资金费率表：\(error)") }
    guard page.source == OKXVenue.id else { throw FeedError.badResponse("OKX 资金费率表来源不符") }
    var out: [String: FundingSnapshot] = [:]
    for row in page.rows where row.rate.isFinite {
      out[InstrumentID(venue: OKXVenue.id, market: OKXVenue.market, symbol: row.symbol).key] =
        FundingSnapshot(rate: row.rate, nextFundingTimeMs: row.nextFundingTime.flatMap { $0 > 0 ? $0 : nil })
    }
    return out
  }

  // ---------------------------------------------------------------- 推送

  /// 资金费率的最近一笔，按 instId 记（一条推送连接一份）。`mark-price` 帧本身不带费率，
  /// 带上这份，标记价那一格和费率那一格就同一帧到（和币安 `markPrice` 帧同一个形状）。
  final class FundingMemo: @unchecked Sendable {
    private let lock = NSLock()
    private var table: [String: (rate: Double, next: Int64?)] = [:]
    func set(_ instID: String, rate: Double, next: Int64?) { lock.lock(); table[instID] = (rate, next); lock.unlock() }
    func get(_ instID: String) -> (rate: Double, next: Int64?)? { lock.lock(); defer { lock.unlock() }; return table[instID] }
  }

  /// 一帧推送的外层：数据帧 `{"arg":{"channel","instId"},"data":[…]}`；
  /// 事件帧 `{"event":"subscribe"|"unsubscribe"|"error"|"notice"|"channel-conn-count",…}`。
  struct Frame {
    var event: String?
    var code: String?
    var msg: String?
    var channel: String?
    var instID: String?
    var action: String?
    var data: [Any]?

    init?(_ text: String) {
      guard let obj = DepthWire.object(text) else { return nil }
      event = obj["event"] as? String
      code = (obj["code"] as? String) ?? (obj["code"] as? NSNumber)?.stringValue
      msg = obj["msg"] as? String
      let arg = obj["arg"] as? [String: Any]
      channel = arg?["channel"] as? String
      instID = arg?["instId"] as? String
      action = obj["action"] as? String
      data = obj["data"] as? [Any]
    }
  }

  /// 一帧行情推送 → 看盘的统一报文（`OKXWire.decode` 调它）。
  ///
  /// - `tickers`：data 行同 REST ticker。
  /// - `candle<bar>`：data 行同 REST K 线（`confirm == "1"` 是收了）；同一帧可能多行，按开盘时间升序。
  /// - `trades`：`sz` 是**张数**，乘合约面值（`OKXVenue.contractValues`）才是币数；面值还不知道
  ///   （品种表没到）就量记 0、只推动价格，不拿张数冒充币数。同一帧里按成交时间升序。
  /// - `mark-price`：`{markPx, ts}`，捎上这条连接上记着的最近一笔资金费率。
  /// - `funding-rate`：`{fundingRate, fundingTime, ts}`，出一条价格为 NaN 的标记价帧（只带费率，
  ///   上层只认有效价、费率那一格只认有值的帧），并记进 `memo`。
  static func payloads(_ frame: Frame, memo: FundingMemo) -> [StreamPayload] {
    guard let channel = frame.channel, let inst = frame.instID, let rows = frame.data,
          let key = OKXVenue.key(instID: inst) else { return [] }
    let dicts = rows.compactMap { $0 as? [String: Any] }
    func str(_ d: [String: Any], _ k: String) -> String? {
      (d[k] as? String) ?? (d[k] as? NSNumber)?.stringValue
    }
    var out: [StreamPayload] = []
    switch channel {
    case "tickers":
      for d in dicts {
        if let t = ticker(instID: inst, last: str(d, "last"), open: str(d, "open24h"), high: str(d, "high24h"),
                          low: str(d, "low24h"), baseVolume: str(d, "volCcy24h"), ts: str(d, "ts")) {
          out.append(.ticker(t))
        }
      }
    case "trades":
      let ctVal = OKXVenue.contractValues.value(inst)
      var trades: [TradeEvent] = []
      for d in dicts {
        guard let px = str(d, "px").flatMap(Double.init), let sz = str(d, "sz").flatMap(Double.init),
              let ms = str(d, "ts").flatMap({ Int64($0) }) else { continue }
        // 解得开却不是有限值或越界：整帧丢掉并记一笔（坏帧里别的成交同样不可信）。
        guard px.isFinite, px > 0, sz.isFinite, sz >= 0 else { WireNumber.noteDropped(); return [] }
        trades.append(TradeEvent(symbol: key, price: px, qty: ctVal.map { sz * $0 } ?? 0, timeMs: ms,
                                 tradeID: str(d, "tradeId").flatMap { Int64($0) }))
      }
      out = trades.sorted { $0.timeMs < $1.timeMs }.map { .trade($0) }
    case "mark-price":
      let funding = memo.get(inst)
      for d in dicts {
        guard let px = str(d, "markPx").flatMap(finiteDouble), px > 0 else { continue }
        out.append(.markPrice(symbol: key, price: px,
                              tick: MarkPriceTick(timeMs: str(d, "ts").flatMap { Int64($0) } ?? 0,
                                                  fundingRate: funding?.rate, nextFundingTimeMs: funding?.next)))
      }
    case "funding-rate":
      for d in dicts {
        guard let rate = str(d, "fundingRate").flatMap(finiteDouble) else { continue }
        let next = str(d, "fundingTime").flatMap { Int64($0) }.flatMap { $0 > 0 ? $0 : nil }
        memo.set(inst, rate: rate, next: next)
        out.append(.markPrice(symbol: key, price: .nan,
                              tick: MarkPriceTick(timeMs: str(d, "ts").flatMap { Int64($0) } ?? 0,
                                                  fundingRate: rate, nextFundingTimeMs: next)))
      }
    default:
      guard channel.hasPrefix("candle"), let interval = OKXVenue.interval(bar: String(channel.dropFirst("candle".count))) else {
        return []
      }
      let bars = rows.compactMap { row -> (bar: Bar, closed: Bool)? in
        guard let cells = row as? [Any] else { return nil }
        return bar(cells.map { ($0 as? String) ?? ($0 as? NSNumber)?.stringValue ?? "" })
      }.sorted { $0.bar.openTime < $1.bar.openTime }
      for (b, closed) in bars {
        out.append(.kline(KlineEvent(symbol: key, interval: interval.rawValue, openTime: b.openTime,
                                     closed: closed, bar: b)))
      }
    }
    return out
  }
}

// ---------------------------------------------------------------- 订单流（books + trades）

extension OKXDTO {
  /// `books` 频道每侧只维护盘口最近 400 档的滑动窗口：窗口外不推，被挤出窗口的一档推 0
  /// （2026-09-28 实测）。快照因此标 `slidingWindow`，本地簿按「窗口最深一档以内才知道」判。
  static let bookLevels = 400

  /// 订单流那条连接上的一帧 → 各本簿的消息（`OKXBooksAdapter.decode` 调它）。
  ///
  /// - `books`（400 档）首帧 `action=snapshot`（prevSeqId = -1），之后 `update` 按各自 instId 的
  ///   seqId / prevSeqId 首尾相接；序号倒退（OKX 那边重置过）就整本重来。checksum 不校验，只靠序号。
  /// - 数量原样给（现货是币数，永续 / 交割是张数），名义美元由 `OrderFlowNotional` 按面值换。
  /// - `trades` 的 `side` 是主动方（buy 吃卖盘）。
  /// - 回执、错误、`pong`（不是 JSON）一律回空。
  ///
  /// 对应原项目 `bit-orderbook-okx/src/lib.rs:878 decode_depth_message`。
  static func books(_ text: String, byInstrument: [String: DepthBook]) -> [VenueMessage] {
    guard let message = DepthWire.object(text), message["event"] == nil,
          let arg = message["arg"] as? [String: Any],
          let instID = arg["instId"] as? String, let book = byInstrument[instID],
          let items = message["data"] as? [[String: Any]] else { return [] }
    switch arg["channel"] as? String {
    case "trades":
      var out: [VenueMessage] = []
      for t in items {
        // 价量解得开却不是有限值或越界：整帧丢掉并记一笔（坏帧里别的成交同样不可信）。
        guard let p = DepthWire.number(t["px"]), let q = DepthWire.number(t["sz"]),
              p > 0, q >= 0, p.isFinite, q.isFinite else { WireNumber.noteDropped(); return [] }
        guard q > 0, let side = t["side"] as? String, side == "buy" || side == "sell" else { continue }
        out.append(VenueMessage(book.id, .trade(book.trade(price: p, quantity: q, hit: side == "buy" ? .ask : .bid,
                                                           timeMs: DepthWire.integer(t["ts"]) ?? 0))))
      }
      return out
    case "books":
      guard let action = message["action"] as? String, items.count == 1 else { return [] }
      let item = items[0]
      guard let seq = DepthWire.integer(item["seqId"]),
            let bids = book.levels(item["bids"]), let asks = book.levels(item["asks"]) else { return [] }
      let time = DepthWire.integer(item["ts"])
      switch action {
      case "snapshot":
        return [VenueMessage(book.id, .snapshot(BookSnapshot(lastUpdateID: seq, requestedLevels: bookLevels,
                                                             bids: bids, asks: asks, eventTimeMs: time,
                                                             slidingWindow: true)))]
      case "update":
        guard let previous = DepthWire.integer(item["prevSeqId"]) else { return [] }
        // 序号倒退：OKX 那边重置过，整本重来。
        if seq < previous { return [VenueMessage(book.id, .reset)] }
        return [VenueMessage(book.id, .delta(BookDelta(firstUpdateID: seq, finalUpdateID: seq,
                                                      previousFinalUpdateID: previous,
                                                      bids: bids, asks: asks, eventTimeMs: time ?? 0)))]
      default:
        return []
      }
    default:
      return []
    }
  }
}
