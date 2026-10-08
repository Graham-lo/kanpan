import Foundation
import KanpanCore

// Coinbase Advanced Trade 公开行情的报文。数值一律是字符串、时间戳是秒（K 线）或
// ISO 8601（推送），K 线按时间**降序**给——全在这一层翻成看盘的口径
// （毫秒、Double、升序），出了这个文件夹谁都不认识 Coinbase 的格式。

//
// 这是 Coinbase **唯一**的报文解码：行情提供者（REST）、行情推送（`CoinbaseWire`）、
// 订单流（`CoinbaseLevel2Adapter`）都调这里。身份与代号互译在 `CoinbaseVenue`。
enum CoinbaseDTO {
  private static func key(_ productID: String) -> String { CoinbaseVenue.key(productID) }

  // ---------------------------------------------------------------- 品种表 / 24h 行情

  /// 坏一行只丢那一行（`LenientList`）：几百个币对里有一行缺了 `product_id`，
  /// 不能让整张品种表和全市场行情一起解不开。
  struct Products: Decodable {
    var products: [Product]
    private enum CodingKeys: String, CodingKey { case products }
    init(from decoder: Decoder) throws {
      let c = try decoder.container(keyedBy: CodingKeys.self)
      products = try c.decode(LenientList<Product>.self, forKey: .products).items
    }
  }

  struct Product: Decodable {
    var product_id: String
    var price: String?
    var price_percentage_change_24h: String?
    var volume_24h: String?
    var high_24h: String?
    var low_24h: String?
    var base_increment: String?
    var price_increment: String?
    var base_display_symbol: String?
    var base_currency_id: String?
    var quote_currency_id: String?
    var status: String?
    var product_type: String?
    var view_only: Bool?
    var trading_disabled: Bool?
    var cancel_only: Bool?
    var is_disabled: Bool?

    /// 准入：美元计价、在线、现货、不是只读展示。
    var isListed: Bool {
      quote_currency_id == CoinbaseVenue.quote && status == "online"
        && product_type == "SPOT" && view_only != true && is_disabled != true
    }

    var symbolInfo: SymbolInfo? {
      guard let tick = price_increment.flatMap(Double.init), tick > 0 else { return nil }
      let base = (base_display_symbol?.isEmpty == false ? base_display_symbol : base_currency_id) ?? product_id
      let step = base_increment.flatMap(Double.init) ?? 0
      return SymbolInfo(symbol: CoinbaseVenue.key(product_id), base: base.uppercased(), quote: CoinbaseVenue.quote,
                        pricePrecision: price_increment.map(CoinbaseDTO.decimals) ?? 0,
                        quantityPrecision: step > 0 ? base_increment.map(CoinbaseDTO.decimals) ?? 8 : 8,
                        tickSize: tick,
                        // Coinbase 现货只有币（美元计价的币对），按币安 `underlyingType` 的口径
                        // 标成 `COIN`：徽章、搜索的「加密」筛选、自选分类判据都认这一个字段。
                        underlyingType: "COIN",
                        // 暂停撮合 / 只许撤单是临时的，按停牌算，不按下架算。
                        status: trading_disabled == true || cancel_only == true ? .halted : .tradable)
    }

    var ticker: Ticker? {
      guard let last = price.flatMap(Double.init), last.isFinite, last > 0 else { return nil }
      return CoinbaseDTO.ticker(product: product_id, last: last,
                                changePercent: price_percentage_change_24h.flatMap(Double.init),
                                high: high_24h.flatMap(Double.init), low: low_24h.flatMap(Double.init),
                                baseVolume: volume_24h.flatMap(Double.init), timeMs: nil)
    }
  }

  /// 步长要几位小数才写得下：**按交易所给的那串字面数**，末尾的 0 不算。
  ///
  /// 原来是 `⌈-log10(步长)⌉`，只对 10 的整数次幂成立：`0.25` 算出来是 1 位，
  /// 价格按一位小数摆，`x.25` / `x.75` 这些合法的价位全被四舍五入成相邻的档，
  /// 图上的价格刻度和最新价都对不上成交。字面数本来就在报文里，数它最准，
  /// 也不经过一次浮点换算。科学计数法（`1e-8`、`2.5E-3`）按指数折算。
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

  /// Coinbase 口径的 24h 行情 → 看盘的 `Ticker`。
  ///
  /// - 额：Coinbase 推送里只有 base 成交量，按「base 量 × 现价」近似（已拍板；REST 里
  ///   有 `approximate_quote_24h_volume`，但推送里没有，两边口径必须一致，否则一刷新一跳）。
  /// - 24h 开盘价与涨跌额由现价和涨跌幅反推，振幅才有分母。
  static func ticker(product: String, last: Double, changePercent: Double?, high: Double?, low: Double?,
                     baseVolume: Double?, timeMs: Int64?) -> Ticker {
    let pct = changePercent.flatMap { $0.isFinite ? $0 : nil }
    let open = pct.flatMap { 1 + $0 / 100 > 0 ? last / (1 + $0 / 100) : nil }
    return Ticker(symbol: key(product), last: last, changePercent: pct ?? .nan,
                  high: high ?? .nan, low: low ?? .nan,
                  quoteVolume: (baseVolume ?? .nan) * last,
                  open24h: open, timeMs: timeMs,
                  priceChange: open.map { last - $0 })
  }

  // ---------------------------------------------------------------- K 线

  struct Candles: Decodable {
    var candles: [Candle]
  }

  struct Candle: Decodable {
    var start: String
    var low: String
    var high: String
    var open: String
    var close: String
    var volume: String
    var product_id: String?

    var bar: Bar? {
      guard let t = Int64(start), let o = Double(open), let h = Double(high), let l = Double(low),
            let c = Double(close), let v = Double(volume) else { return nil }
      // Coinbase 不给主动买量：留 NaN，不填 0（见 `Bar.takerBuy`）。
      let bar = Bar(openTime: t * 1000, open: o, high: h, low: l, close: c, volume: v)
      return bar.isValidMarketBar ? bar : nil
    }
  }

  /// K 线页：降序 → 升序、秒 → 毫秒、字符串 → Double。
  static func bars(_ data: Data) throws -> [Bar] {
    let page: Candles
    do { page = try JSONDecoder().decode(Candles.self, from: data) }
    catch { throw FeedError.badResponse("解不开 Coinbase K 线：\(error)") }
    return page.candles.compactMap(\.bar).sorted { $0.openTime < $1.openTime }
  }

  // ---------------------------------------------------------------- 推送

  struct Frame: Decodable {
    var channel: String?
    var type: String?
    var message: String?
    var timestamp: String?
    var events: [Event]?
  }

  struct Event: Decodable {
    var type: String?
    var trades: [Trade]?
    var tickers: [WSTicker]?
    var candles: [Candle]?
    /// 订阅应答（`channel == "subscriptions"`）：频道 → 已订的品种。
    var subscriptions: [String: [String]]?
  }

  /// 一帧推送证明了哪些「频道 × 品种」的订阅已经生效：数据帧（快照、更新都算）里出现的品种，
  /// 以及订阅应答里列着的那些。心跳不算——它只说明连接活着。
  static func confirmedSubs(_ frame: Frame) -> [(channel: String, product: String)] {
    guard let channel = frame.channel, let events = frame.events else { return [] }
    var out: [(channel: String, product: String)] = []
    switch channel {
    case "subscriptions":
      for event in events {
        for (ch, products) in event.subscriptions ?? [:] where ch != "heartbeats" {
          for p in products { out.append((ch, p)) }
        }
      }
    case "market_trades":
      for event in events { for t in event.trades ?? [] { out.append((channel, t.product_id)) } }
    case "ticker", "ticker_batch":
      for event in events { for t in event.tickers ?? [] { out.append(("ticker", t.product_id)) } }
    case "candles":
      for event in events { for c in event.candles ?? [] { if let id = c.product_id { out.append((channel, id)) } } }
    default:
      break
    }
    return out
  }

  struct Trade: Decodable {
    var product_id: String
    var trade_id: String?
    var price: String
    var size: String
    var time: String
  }

  struct WSTicker: Decodable {
    var product_id: String
    var price: String
    var volume_24_h: String?
    var low_24_h: String?
    var high_24_h: String?
    var price_percent_chg_24_h: String?
  }

  /// 一帧推送 → 看盘的统一报文。
  ///
  /// - 成交：订阅时 Coinbase 先回一份最近成交的快照，那些成交早就在 REST 的 K 线里了，
  ///   再折一次成交量就重复了，所以只收 `update`。同一帧里是新的在前，翻成时间升序。
  /// - K 线（只有 5m）：快照里是最近几十根，只取最新那一根；更新按开盘时间升序。
  /// - 24h 行情：快照和更新都收（快照就是订阅那一刻的现状）。
  static func payloads(_ frame: Frame, candleInterval: Interval) -> [StreamPayload] {
    guard let channel = frame.channel, let events = frame.events else { return [] }
    let frameMs = frame.timestamp.flatMap(isoMs)
    var out: [StreamPayload] = []
    switch channel {
    case "market_trades":
      for event in events where event.type == "update" {
        for t in (event.trades ?? []).reversed() {
          guard let px = Double(t.price), let qty = Double(t.size), let ms = isoMs(t.time) else { continue }
          // 解得开却不是有限值（`nan`、`inf`、`1e400`）或越界：整帧丢掉并记一笔。
          // 同一帧里别的成交也不收——坏帧里的其它数字同样不可信，而成交量一旦折进 NaN 整根就废了。
          guard px.isFinite, px > 0, qty.isFinite, qty >= 0 else {
            WireNumber.noteDropped()
            return []
          }
          out.append(.trade(TradeEvent(symbol: key(t.product_id), price: px, qty: qty, timeMs: ms,
                                       tradeID: t.trade_id.flatMap { Int64($0) })))
        }
      }
    case "ticker", "ticker_batch":
      for event in events {
        for t in event.tickers ?? [] {
          guard let px = Double(t.price), px.isFinite, px > 0 else { continue }
          out.append(.ticker(ticker(product: t.product_id, last: px,
                                    changePercent: t.price_percent_chg_24_h.flatMap(Double.init),
                                    high: t.high_24_h.flatMap(Double.init), low: t.low_24_h.flatMap(Double.init),
                                    baseVolume: t.volume_24_h.flatMap(Double.init), timeMs: frameMs)))
        }
      }
    case "candles":
      for event in events {
        var rows = (event.candles ?? []).compactMap { c -> (String, Bar)? in
          guard let id = c.product_id, let bar = c.bar else { return nil }
          return (id, bar)
        }.sorted { $0.1.openTime < $1.1.openTime }
        if event.type == "snapshot" {
          var latest: [String: (String, Bar)] = [:]
          for row in rows { latest[row.0] = row }
          rows = latest.values.sorted { $0.1.openTime < $1.1.openTime }
        }
        for (id, bar) in rows {
          out.append(.kline(KlineEvent(symbol: key(id), interval: candleInterval.rawValue,
                                       openTime: bar.openTime, closed: false, bar: bar,
                                       eventTime: frameMs ?? 0)))
        }
      }
    default:
      break
    }
    return out
  }

  /// `2026-09-22T23:19:46.9835Z` / `…46.408897699Z` / `…46Z` → 毫秒。
  ///
  /// 手写而不用 `ISO8601DateFormatter`：热门品种一秒几十笔成交，格式器又慢又不认
  /// 九位小数。只认 Coinbase 发的这一种 UTC 写法，认不出就丢这一笔。
  static func isoMs(_ s: String) -> Int64? {
    let u = Array(s.utf8)
    guard u.count >= 20, u[4] == 45, u[7] == 45, u[10] == 84, u[13] == 58, u[16] == 58 else { return nil }
    func num(_ from: Int, _ len: Int) -> Int? {
      var v = 0
      for i in from..<(from + len) {
        let d = Int(u[i]) - 48
        guard (0...9).contains(d) else { return nil }
        v = v * 10 + d
      }
      return v
    }
    guard let y = num(0, 4), let mo = num(5, 2), let d = num(8, 2),
          let h = num(11, 2), let mi = num(14, 2), let sec = num(17, 2),
          (1...12).contains(mo), (1...31).contains(d) else { return nil }
    var ms = 0
    var i = 19
    if i < u.count, u[i] == 46 {
      i += 1
      var scale = 100
      while i < u.count, (48...57).contains(u[i]) {
        if scale > 0 { ms += (Int(u[i]) - 48) * scale; scale /= 10 }
        i += 1
      }
    }
    guard i < u.count, u[i] == 90 else { return nil }
    // 公历日期 → 自 1970-01-01 起的天数（Howard Hinnant 的 days_from_civil）。
    let yy = mo <= 2 ? y - 1 : y
    let era = (yy >= 0 ? yy : yy - 399) / 400
    let yoe = yy - era * 400
    let mp = (mo + 9) % 12
    let doy = (153 * mp + 2) / 5 + d - 1
    let doe = yoe * 365 + yoe / 4 - yoe / 100 + doy
    let days = era * 146_097 + doe - 719_468
    let secs = Int64(days) * 86_400 + Int64(h * 3600 + mi * 60 + sec)
    return secs * 1000 + Int64(ms)
  }
}

// ---------------------------------------------------------------- 订单流（level2 + market_trades）

extension CoinbaseDTO {
  /// 订单流那条连接上的一帧 → 一本簿的消息（`CoinbaseLevel2Adapter.decode` 调它）。
  ///
  /// - `sequence_num` 是**整条连接**的序号，所以心跳、订阅回执、成交帧也各发一条空增量把序号推过去，
  ///   否则本地簿会误判断档。
  /// - l2 的 `side` 是 `bid` / `offer`；snapshot 的请求档数记成两侧较多的一侧 + 1（整本都在）。
  /// - `market_trades` 的 `side` 是主动方（BUY 吃卖盘）；只收 `update`，开头那份 `snapshot` 是旧成交，不计。
  ///
  /// 对应原项目 `bit-orderbook-coinbase/src/lib.rs:709` 与 `:869`。
  static func level2(_ text: String, book: DepthBook) -> [DepthMessage] {
    let symbol = book.venue.instrument
    guard let frame = DepthWire.object(text), let seq = DepthWire.integer(frame["sequence_num"]) else { return [] }
    let advance = DepthMessage.delta(BookDelta(firstUpdateID: seq, finalUpdateID: seq, previousFinalUpdateID: nil))
    let events = frame["events"] as? [[String: Any]] ?? []
    switch frame["channel"] as? String {
    case "l2_data", "level2":
      var bids: [BookLevel] = [], asks: [BookLevel] = []
      var snapshot = false
      var time: Int64?
      for event in events where (event["product_id"] as? String) == symbol {
        if event["type"] as? String == "snapshot" { snapshot = true; bids = []; asks = [] }
        for u in event["updates"] as? [[String: Any]] ?? [] {
          // 坏档（非有限值、越界）整帧丢掉：连序号也不推进，下一帧就会发现断档、整本重来，
          // 不会只漏一档让本地簿悄悄留着一个旧量。
          guard let p = DepthWire.number(u["price_level"]), let q = DepthWire.number(u["new_quantity"]),
                p > 0, q >= 0, p.isFinite, q.isFinite else { WireNumber.noteDropped(); return [] }
          let level = BookLevel(price: p * book.priceFactor, quantity: q * book.quantityFactor)
          switch u["side"] as? String {
          case "bid": bids.append(level)
          case "offer", "ask": asks.append(level)
          default: continue
          }
          if let t = (u["event_time"] as? String).flatMap(isoMs) { time = max(time ?? t, t) }
        }
      }
      if snapshot {
        return [.snapshot(BookSnapshot(lastUpdateID: seq, requestedLevels: max(bids.count, asks.count) + 1,
                                       bids: bids, asks: asks, eventTimeMs: time))]
      }
      return [.delta(BookDelta(firstUpdateID: seq, finalUpdateID: seq, previousFinalUpdateID: nil,
                               bids: bids, asks: asks, eventTimeMs: time ?? 0))]
    case "market_trades":
      var out = [advance]
      for event in events where event["type"] as? String == "update" {
        for t in event["trades"] as? [[String: Any]] ?? [] {
          guard (t["product_id"] as? String) == symbol else { continue }
          guard let p = DepthWire.number(t["price"]), let q = DepthWire.number(t["size"]),
                p.isFinite, q.isFinite, p > 0, q >= 0 else {
            // 坏成交：这一帧的成交全不要（只推进序号），并记一笔。
            WireNumber.noteDropped()
            return [advance]
          }
          guard q > 0 else { continue }
          let hit: BookSide
          switch (t["side"] as? String)?.uppercased() {
          case "BUY": hit = .ask
          case "SELL": hit = .bid
          default: continue
          }
          out.append(.trade(book.trade(price: p, quantity: q, hit: hit,
                                       timeMs: (t["time"] as? String).flatMap(isoMs) ?? 0)))
        }
      }
      return out
    default:
      // 心跳、订阅回执：只推进序号。
      return [advance]
    }
  }
}
