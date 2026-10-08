import Foundation
import KanpanCore

// Hyperliquid 公开行情的报文（官方文档 Info endpoint › Perpetuals / Websocket › Subscriptions，2026-10 版）。
// 数值大多是字符串（`"82640.0"`），时间是毫秒，coin 名是原名（`kPEPE`）——全在这一层翻成看盘的口径
// （品种键大写、Double、升序），出了这个文件夹谁都不认识 Hyperliquid 的格式。
//
// 这是 Hyperliquid **唯一**的报文解码：行情提供者（REST）、行情推送（`HyperliquidWire`）、
// 订单流（`HyperliquidBookAdapter`）都调这里。身份与代号互译在 `HyperliquidVenue`。
//
// 用 `JSONSerialization` 而不是 `Decodable`：同一个字段时而字符串时而数字、`midPx` 可能是 null、
// `metaAndAssetCtxs` 的两个数组靠下标对齐（坏一行也不能挪位），按字典取最省事，推送那边也只解一遍。
enum HyperliquidDTO {
  private static func key(_ coin: String) -> String { HyperliquidVenue.key(coin) }

  static func json(_ data: Data) -> Any? { try? JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed]) }
  static func object(_ text: String) -> [String: Any]? { DepthWire.object(text) }
  private static func number(_ v: Any?) -> Double? { DepthWire.number(v) }
  private static func integer(_ v: Any?) -> Int64? { DepthWire.integer(v) }

  // ---------------------------------------------------------------- 品种表

  /// `meta.universe` 的一行：`{name, szDecimals, maxLeverage, onlyIsolated?, isDelisted?}`。
  struct Asset: Equatable {
    var name: String
    var szDecimals: Int
    var isDelisted: Bool

    init?(_ raw: Any?) {
      guard let o = raw as? [String: Any], let name = o["name"] as? String, !name.isEmpty,
            let sz = HyperliquidDTO.integer(o["szDecimals"]), (0...12).contains(sz) else { return nil }
      self.name = name; self.szDecimals = Int(sz)
      self.isDelisted = (o["isDelisted"] as? Bool) == true
    }

    /// 价格：最多 5 位有效数字、小数位不超过 `6 − szDecimals`（官方 Tick and lot size）。
    /// 有效数字那条随价位变，品种表里给不出，按小数位上限记。
    var priceDecimals: Int { max(0, 6 - szDecimals) }

    var symbolInfo: SymbolInfo {
      SymbolInfo(symbol: HyperliquidVenue.key(name),
                 // 原样：`kPEPE` 是千枚计价，订单流按 base 找五家的簿时 `OrderFlowBase.normalize` 认这个小写 `k`。
                 base: name, quote: HyperliquidVenue.quote,
                 pricePrecision: priceDecimals, quantityPrecision: szDecimals,
                 tickSize: pow(10, -Double(priceDecimals)),
                 // 全是币，按币安 `underlyingType` 的口径标 `COIN`（徽章、分类、涨跌口径都认它）。
                 underlyingType: "COIN", contractType: "PERPETUAL", status: .tradable)
    }
  }

  /// 一份 `meta`（`{"universe":[…]}`）→ 按原顺序的行（解不开的行是 nil，不挪位）。
  static func universe(_ meta: Any?) -> [Asset?]? {
    guard let rows = (meta as? [String: Any])?["universe"] as? [Any] else { return nil }
    return rows.map { Asset($0) }
  }

  /// `{"type":"meta"}` 的回答 → 上线中的品种。
  static func meta(_ data: Data) throws -> [Asset] {
    guard let rows = universe(json(data)) else { throw FeedError.badResponse("解不开 Hyperliquid 品种表") }
    return rows.compactMap { $0 }
  }

  // ---------------------------------------------------------------- 资产上下文（价 / 额 / 标记价 / 持仓量 / 费率）

  /// `metaAndAssetCtxs` 第二个数组的一行，也是 `activeAssetCtx` 推送的 `ctx`。
  struct Ctx: Equatable {
    /// 一小时的资金费率（Hyperliquid 每小时结算）。
    var funding: Double?
    /// 持仓量（币数）。
    var openInterest: Double?
    /// 24 小时前的价格：涨跌幅的分母。
    var prevDayPx: Double?
    /// 24 小时成交额（USDC）。
    var dayNtlVlm: Double?
    var markPx: Double?
    /// 盘口中间价；盘口一侧空着时是 null。
    var midPx: Double?
    var oraclePx: Double?
    /// 24 小时成交量（币数）。
    var dayBaseVlm: Double?

    init?(_ raw: Any?) {
      guard let o = raw as? [String: Any] else { return nil }
      funding = HyperliquidDTO.number(o["funding"])
      openInterest = HyperliquidDTO.number(o["openInterest"])
      prevDayPx = HyperliquidDTO.number(o["prevDayPx"])
      dayNtlVlm = HyperliquidDTO.number(o["dayNtlVlm"])
      markPx = HyperliquidDTO.number(o["markPx"])
      midPx = HyperliquidDTO.number(o["midPx"])
      oraclePx = HyperliquidDTO.number(o["oraclePx"])
      dayBaseVlm = HyperliquidDTO.number(o["dayBaseVlm"])
    }

    /// 最新价：有中间价用中间价，没有用标记价。
    var last: Double? {
      if let m = midPx, m > 0 { return m }
      if let m = markPx, m > 0 { return m }
      return nil
    }
  }

  /// `[meta, [ctx…]]` → 一行一只（两个数组按下标对齐；任一边解不开的那只丢掉，不挪位）。
  static func metaAndCtxs(_ data: Data) throws -> [(asset: Asset, ctx: Ctx)] {
    guard let pair = json(data) as? [Any], pair.count == 2, let assets = universe(pair[0]),
          let ctxs = pair[1] as? [Any] else {
      throw FeedError.badResponse("解不开 Hyperliquid 全市场行情")
    }
    return zip(assets, ctxs).compactMap { asset, raw in
      guard let asset, let ctx = Ctx(raw) else { return nil }
      return (asset, ctx)
    }
  }

  /// 资产上下文 → 看盘的 `Ticker`。
  ///
  /// - 价：中间价（没有就标记价）；涨跌按 `prevDayPx`（24 小时前）算，涨跌额与 24h 开盘价也是它。
  /// - 额：`dayNtlVlm`（USDC 名义成交额）。
  /// - Hyperliquid 不给 24h 最高 / 最低：留 NaN（顶栏那两格写「—」，振幅给不出）。
  static func ticker(coin: String, ctx: Ctx, timeMs: Int64?) -> Ticker? {
    guard let last = ctx.last, last.isFinite else { return nil }
    let prev = ctx.prevDayPx.flatMap { $0 > 0 ? $0 : nil }
    return Ticker(symbol: key(coin), last: last,
                  changePercent: prev.map { (last / $0 - 1) * 100 } ?? .nan,
                  high: .nan, low: .nan,
                  quoteVolume: nonNegativeOrNaN(ctx.dayNtlVlm),
                  // 标记价是价：负的、零的不是「有标记价」（原来照搬进 `Ticker.markPrice`）。
                  markPrice: ctx.markPx.flatMap { $0 > 0 ? $0 : nil }, open24h: prev, timeMs: timeMs,
                  priceChange: prev.map { last - $0 })
  }

  /// 资产上下文 → 资金费率。`FundingSnapshot` 没有结算间隔字段：这里的 `rate` 是**一小时**的费率
  /// （币安、OKX 是八小时），下一次结算是下一个整点。
  static func funding(_ ctx: Ctx, nowMs: Int64) -> FundingSnapshot? {
    guard let rate = ctx.funding else { return nil }
    return FundingSnapshot(rate: rate, nextFundingTimeMs: HyperliquidVenue.nextFundingTimeMs(nowMs: nowMs))
  }

  /// 资产上下文 → 标记价推送（带费率与下一次结算）。
  static func markTick(_ ctx: Ctx, nowMs: Int64) -> MarkPriceTick {
    MarkPriceTick(timeMs: nowMs, fundingRate: ctx.funding,
                  nextFundingTimeMs: HyperliquidVenue.nextFundingTimeMs(nowMs: nowMs),
                  indexPrice: ctx.oraclePx.flatMap { $0 > 0 ? $0 : nil })
  }

  // ---------------------------------------------------------------- K 线

  /// 一根 `candleSnapshot` / `candle` 推送：`{t(开盘 ms), T(收盘 ms), s(coin), i(周期), o, h, l, c, v(币), n}`。
  static func bar(_ raw: Any?) -> (coin: String?, interval: String?, bar: Bar)? {
    guard let o = raw as? [String: Any], let t = integer(o["t"]),
          let open = number(o["o"]), let high = number(o["h"]), let low = number(o["l"]),
          let close = number(o["c"]), let volume = number(o["v"]) else { return nil }
    // Hyperliquid 不给主动买量：留 NaN，不填 0（见 `Bar.takerBuy`）。
    let bar = Bar(openTime: t, open: open, high: high, low: low, close: close, volume: volume)
    guard isPlausibleVenueBar(bar) else { return nil }
    return (o["s"] as? String, o["i"] as? String, bar)
  }

  /// K 线页 → 升序。坏一根只丢那一根。
  static func bars(_ data: Data) throws -> [Bar] {
    let parsed = json(data)
    if parsed is NSNull { return [] }
    guard let rows = parsed as? [Any] else { throw FeedError.badResponse("解不开 Hyperliquid K 线") }
    return rows.compactMap { bar($0)?.bar }.sorted { $0.openTime < $1.openTime }
  }

  // ---------------------------------------------------------------- 推送

  /// 一帧推送：`{"channel":…, "data":…}`。
  struct Frame {
    var channel: String
    var data: Any?
  }

  static func frame(_ text: String) -> Frame? {
    guard let o = object(text), let channel = o["channel"] as? String else { return nil }
    return Frame(channel: channel, data: o["data"])
  }

  /// 订阅描述（`subscriptionResponse` 回执里、`error` 帧里带的那一段）。
  struct Subscription: Equatable {
    var type: String
    var coin: String
    var interval: String?

    init?(_ raw: Any?) {
      guard let o = raw as? [String: Any], let type = o["type"] as? String, let coin = o["coin"] as? String else {
        return nil
      }
      self.type = type; self.coin = coin; self.interval = o["interval"] as? String
    }
  }

  /// `subscriptionResponse`：`{"method":"subscribe","subscription":{…}}` → 订上了的那一个（退订回执不算）。
  static func subscribed(_ data: Any?) -> Subscription? {
    guard let o = data as? [String: Any], o["method"] as? String == "subscribe" else { return nil }
    return Subscription(o["subscription"])
  }

  /// `error` 帧的正文是一句话，常把出错的订阅原样贴在后面（`Invalid subscription {"type":"candle",…}`）。
  /// 能从里面抠出订阅就点名，抠不出就 nil（归到最近一发控制帧）。
  static func errorSubscription(_ message: String) -> Subscription? {
    guard let start = message.firstIndex(of: "{"), let end = message.lastIndex(of: "}"), start < end,
          let o = object(String(message[start...end])) else { return nil }
    return Subscription(o["subscription"] ?? o)
  }

  /// `candle` 推送：官方文档写的是 `Candle[]`，实际是一根一个对象，两种都认。
  /// 一根坏的（价量不是有限正数、开盘时刻不合理、缺币名 / 周期）整帧丢并记一笔，和别家同一口径。
  static func candles(_ data: Any?) -> [(coin: String, interval: String, bar: Bar)] {
    let rows: [Any] = (data as? [Any]) ?? (data.map { [$0] } ?? [])
    var out: [(coin: String, interval: String, bar: Bar)] = []
    for row in rows {
      guard let b = bar(row), let coin = b.coin, let interval = b.interval else {
        WireNumber.noteDropped()
        return []
      }
      out.append((coin, interval, b.bar))
    }
    return out
  }

  /// 一笔成交：`{coin, side:"B"(主动买)|"A"(主动卖), px, sz, time, hash, tid, users}`。
  struct Trade: Equatable {
    var coin: String
    var price: Double
    var size: Double
    /// `B` / `A`；别的值原样留着，由调用方决定丢不丢。
    var side: String?
    var timeMs: Int64
    var tid: Int64?
  }

  /// `trades` 推送 → 成交。价量解得开却不是有限值或越界：整帧作废（返回 nil）并记一笔——
  /// 坏帧里别的成交同样不可信，一笔 NaN 折进成交量整根就废了。缺 coin 的那笔只丢它自己。
  static func trades(_ data: Any?) -> [Trade]? {
    guard let items = data as? [[String: Any]] else { return [] }
    var out: [Trade] = []
    out.reserveCapacity(items.count)
    for t in items {
      guard let coin = t["coin"] as? String else { continue }
      guard let p = number(t["px"]), let q = number(t["sz"]), p > 0, q >= 0 else {
        WireNumber.noteDropped()
        return nil
      }
      out.append(Trade(coin: coin, price: p, size: q, side: t["side"] as? String,
                       timeMs: integer(t["time"]) ?? 0, tid: integer(t["tid"])))
    }
    return out
  }

  /// `activeAssetCtx` 推送：`{"coin":"BTC","ctx":{…}}`。
  static func assetCtx(_ data: Any?) -> (coin: String, ctx: Ctx)? {
    guard let o = data as? [String: Any], let coin = o["coin"] as? String, let ctx = Ctx(o["ctx"]) else { return nil }
    return (coin, ctx)
  }
}

// ---------------------------------------------------------------- 订单流（l2Book + trades）

extension HyperliquidDTO {
  /// 订单流那条连接上的一帧 → 这几本簿的消息（`HyperliquidBookAdapter.decode` 调它）。`books` 按 coin 原名索引。
  ///
  /// - `l2Book` 每一帧都是整本簿（每侧最多 `levels` 档）、没有序号：出快照，`data.time` 当序号与事件时间，
  ///   标 `slidingWindow`（窗口外的档不知道）。
  /// - `trades` 的 `side` 是主动方：`B` 吃卖盘、`A` 吃买盘。
  /// - pong、`subscriptionResponse`、不在这条连接上的币：空。
  static func orderFlow(_ text: String, books: [String: DepthBook], levels: Int) -> [VenueMessage] {
    guard let frame = frame(text) else { return [] }
    switch frame.channel {
    case "l2Book": return l2Book(frame.data, books: books, levels: levels)
    case "trades": return orderFlowTrades(frame.data, books: books)
    default: return []
    }
  }

  static func l2Book(_ raw: Any?, books: [String: DepthBook], levels limit: Int) -> [VenueMessage] {
    guard let data = raw as? [String: Any], let coin = data["coin"] as? String, let book = books[coin],
          let time = integer(data["time"]),
          let sides = data["levels"] as? [Any], sides.count == 2,
          let bids = levels(sides[0], book), let asks = levels(sides[1], book),
          bids.count <= limit, asks.count <= limit else { return [] }
    return [VenueMessage(book.id, .snapshot(BookSnapshot(lastUpdateID: time, requestedLevels: limit,
                                                         bids: bids, asks: asks, eventTimeMs: time,
                                                         slidingWindow: true)))]
  }

  /// 一侧 `[{"px","sz","n"}]` → `[[px, sz]]` 交给簿统一换算（价格口径、数量口径）。
  private static func levels(_ raw: Any, _ book: DepthBook) -> [BookLevel]? {
    guard let items = raw as? [[String: Any]] else { return nil }
    var pairs: [[Any]] = []
    pairs.reserveCapacity(items.count)
    for item in items {
      guard let px = item["px"], let sz = item["sz"] else { return nil }
      pairs.append([px, sz])
    }
    return book.levels(pairs)
  }

  static func orderFlowTrades(_ raw: Any?, books: [String: DepthBook]) -> [VenueMessage] {
    guard let trades = trades(raw) else { return [] }
    var out: [VenueMessage] = []
    for t in trades {
      guard let book = books[t.coin], t.size > 0, t.side == "B" || t.side == "A" else { continue }
      out.append(VenueMessage(book.id, .trade(book.trade(price: t.price, quantity: t.size,
                                                         hit: t.side == "B" ? .ask : .bid, timeMs: t.timeMs))))
    }
    return out
  }
}
