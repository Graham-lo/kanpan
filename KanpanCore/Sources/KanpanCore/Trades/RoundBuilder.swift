import Foundation

// 把成交拼成回合（规格：方案第 3.3 节；口径：协议文档 2.3）。
//
// 为什么做成一个带状态、可落盘的值类型，而不是每次把 90 天成交全拉一遍重算：
// 首次接入回溯 90 天之后，拉取就只按水位增量拉（每 5 分钟一次，交易所的权重和手机流量都省着用）。
// 增量拉回来的成交要接在「上次拼到哪儿」后面，所以开着的回合、刚结束的回合、见过的成交键
// 都得留在这里、随水位一起落盘。它很小：只有开着的回合和最近 3 天结束的回合。
//
// 规则摘要：
// - 按「品种 + 持仓方向」各记一本账，有符号变化量买 + 卖 −（双向持仓的空头仓就是负数）；
// - 从 0 离开 = 回合开始，回到 0 = 结束，一笔成交越过 0 = 反手：这笔拆两半，
//   平旧仓那一半带走这笔全部已实现盈亏、手续费按数量比例分，剩下那一半开新回合；
// - 同一笔成交拉到两次只算一次；
// - 回溯窗口之前就开着的旧仓先用窗口开头的成交消化到 0，这段残缺回合不产出（开仓价不在窗口里）。

/// 数值落盘成十进制字符串（`JSONDecoder` 解 `Decimal` 会绕 Double，第八位上可能出零头）。
@propertyWrapper
struct DecimalCoded: Codable, Sendable, Hashable {
  var wrappedValue: Decimal
  init(wrappedValue: Decimal) { self.wrappedValue = wrappedValue }
  init(from decoder: any Decoder) throws {
    let text = try decoder.singleValueContainer().decode(String.self)
    guard let d = TradeDecimal.parse(text) else {
      throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: text))
    }
    wrappedValue = d
  }
  func encode(to encoder: any Encoder) throws {
    var c = encoder.singleValueContainer()
    try c.encode(TradeDecimal.format(wrappedValue))
  }
}

@propertyWrapper
struct DecimalMapCoded: Codable, Sendable, Hashable {
  var wrappedValue: [String: Decimal]
  init(wrappedValue: [String: Decimal]) { self.wrappedValue = wrappedValue }
  init(from decoder: any Decoder) throws {
    let raw = try decoder.singleValueContainer().decode([String: String].self)
    var out: [String: Decimal] = [:]
    for (k, v) in raw {
      guard let d = TradeDecimal.parse(v) else {
        throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: v))
      }
      out[k] = d
    }
    wrappedValue = out
  }
  func encode(to encoder: any Encoder) throws {
    var c = encoder.singleValueContainer()
    try c.encode(wrappedValue.mapValues(TradeDecimal.format))
  }
}

public struct RoundBuilder: Codable, Sendable {
  /// 结束的回合留多久：资金费流水可能下一次增量才拉到，要能归回去并重新产出一版。
  public static let closedRetentionMs: Int64 = 3 * 86_400_000
  /// 见过的成交键留多久。增量拉取的回看重叠必须比它短（`ExchangeAccountSync` 用 1 小时）。
  public static let seenRetentionMs: Int64 = 7 * 86_400_000

  public let venue: String
  public let market: String
  public let accountTag: String

  /// 一次拉取带进来的上下文。
  public struct Context: Sendable {
    /// 品种 → 当前杠杆（交易所持仓风险接口给的）。
    public var leverage: [String: Int]
    /// 合约代号 → 标记价，用来把 BNB 之类的手续费折成保证金资产（找 `<币种><保证金资产>` 那一只）。
    public var markPrices: [String: Decimal]
    /// 当前持仓（有符号）。**只在第一次回溯时给**：用来推出回溯窗口起点有没有旧仓。
    public var currentPositions: [PositionKey: Decimal]?

    public init(leverage: [String: Int] = [:], markPrices: [String: Decimal] = [:],
                currentPositions: [PositionKey: Decimal]? = nil) {
      self.leverage = leverage; self.markPrices = markPrices; self.currentPositions = currentPositions
    }
  }

  /// 一本账上正在记的那个回合（或者一段孤儿旧仓）。
  struct Book: Codable, Sendable, Hashable {
    var symbol: String
    var positionSide: PositionSide
    var quoteAsset: String
    /// 回溯窗口之前开的旧仓：只消化、不产出。
    var orphan: Bool
    @DecimalCoded var qty: Decimal
    @DecimalCoded var avg: Decimal
    var firstFillID: String
    var direction: TradeDirection
    var openedAt: Int64
    var closedAt: Int64?
    @DecimalCoded var openedQty: Decimal = 0
    @DecimalCoded var openNotional: Decimal = 0
    @DecimalCoded var closedQty: Decimal = 0
    @DecimalCoded var closeNotional: Decimal = 0
    @DecimalCoded var maxQty: Decimal = 0
    @DecimalCoded var peakNotional: Decimal = 0
    /// 最近一次非零持仓时的名义额；回合结束后资金费按它分。
    @DecimalCoded var lastNotional: Decimal = 0
    @DecimalCoded var realizedPnl: Decimal = 0
    @DecimalCoded var commissionQuote: Decimal = 0
    @DecimalMapCoded var commissionByAsset: [String: Decimal] = [:]
    var commissionUnpriced = false
    @DecimalCoded var funding: Decimal = 0
    var leverage: Int?
    var fills: [RoundFill] = []
    var updatedAt: Int64

    var notional: Decimal { qty.magnitudeValue * avg }
  }

  /// 开着的账，键是 `PositionKey.description`。
  var books: [String: Book] = [:]
  /// 最近结束的回合。
  var closed: [Book] = []
  /// 见过的成交 / 资金费键 → 事件时间。
  var seen: [String: Int64] = [:]
  var latestEventAt: Int64 = 0
  /// 做过第一次回溯没有。
  public private(set) var initialized = false

  public init(venue: String, market: String, accountTag: String) {
    self.venue = venue; self.market = market; self.accountTag = accountTag
  }

  /// 当前开着（持仓中）的回合，不含孤儿旧仓。
  public var openRounds: [TradeRound] {
    books.values.filter { !$0.orphan && $0.qty != 0 }.map(snapshot).sorted { $0.openedAt < $1.openedAt }
  }

  // MARK: - 喂数据

  /// 喂一批成交与资金费，返回这一批里有变化的回合（同一个 id 只出最后一版）。
  /// 重复喂同一笔成交、同一条资金费不会有任何效果。
  public mutating func ingest(fills: [Fill], funding: [FundingEntry], context: Context) -> [TradeRound] {
    var batchKeys: Set<String> = []
    let newFills = fills.filter { f in
      guard seen[f.dedupeKey] == nil, batchKeys.insert(f.dedupeKey).inserted else { return false }
      return f.qty > 0
    }.sorted(by: Fill.chronological)
    let newFunding = funding.filter { e in
      seen[e.dedupeKey] == nil && batchKeys.insert(e.dedupeKey).inserted
    }.sorted { $0.time != $1.time ? $0.time < $1.time : $0.id < $1.id }

    if !initialized {
      seedOrphans(from: context.currentPositions, fills: newFills)
      initialized = true
    }

    var touched: Set<String> = []  // 回合 id
    // 资金费与成交按时间合并处理；同一毫秒先算资金费（结算那一刻的仓位是成交之前的）。
    var fi = 0, ei = 0
    while fi < newFills.count || ei < newFunding.count {
      if ei < newFunding.count, fi >= newFills.count || newFunding[ei].time <= newFills[fi].time {
        apply(newFunding[ei], touched: &touched)
        ei += 1
      } else {
        apply(newFills[fi], context: context, touched: &touched)
        fi += 1
      }
    }

    for f in newFills { seen[f.dedupeKey] = f.time; latestEventAt = max(latestEventAt, f.time) }
    for e in newFunding { seen[e.dedupeKey] = e.time; latestEventAt = max(latestEventAt, e.time) }

    // 杠杆：交易所只给「当前」杠杆，碰过的回合拿当前值补上（推不出的留空）。
    for (k, book) in books where touched.contains(roundID(book)) {
      if let lev = context.leverage[book.symbol] { books[k]?.leverage = lev }
    }
    for i in closed.indices where touched.contains(roundID(closed[i])) && closed[i].leverage == nil {
      closed[i].leverage = context.leverage[closed[i].symbol]
    }

    let out = (books.values.filter { !$0.orphan } + closed)
      .filter { touched.contains(roundID($0)) }
      .map(snapshot)
      .sorted { $0.openedAt != $1.openedAt ? $0.openedAt < $1.openedAt : $0.id < $1.id }
    prune()
    return out
  }

  // MARK: - 回溯窗口前的旧仓

  private mutating func seedOrphans(from current: [PositionKey: Decimal]?, fills: [Fill]) {
    guard let current else { return }
    var delta: [PositionKey: Decimal] = [:]
    for f in fills { delta[f.key, default: 0] += f.side.sign * f.qty }
    // 当前表里没有的就是空仓（交易所的持仓风险接口列的是全部品种，没列出来 = 0）。
    for key in Set(current.keys).union(delta.keys) {
      let start = (current[key] ?? 0) - (delta[key] ?? 0)
      guard start != 0 else { continue }
      // 孤儿旧仓从「很早以前」就开着：它的开仓时间、均价都不在窗口里，也永远不产出。
      books[key.description] = Book(
        symbol: key.symbol, positionSide: key.positionSide, quoteAsset: "", orphan: true,
        qty: start, avg: 0, firstFillID: "", direction: start > 0 ? .long : .short,
        openedAt: 0, updatedAt: 0)
    }
  }

  // MARK: - 一笔成交

  private mutating func apply(_ fill: Fill, context: Context, touched: inout Set<String>) {
    let k = fill.key.description
    let delta = fill.side.sign * fill.qty
    guard var book = books[k], book.qty != 0 else {
      openBook(k, fill: fill, qty: fill.qty, share: 1, split: false, context: context, touched: &touched)
      return
    }
    let sameWay = (book.qty > 0) == (delta > 0)
    if sameWay {
      record(&book, fill: fill, qty: fill.qty, commissionShare: 1, pnl: fill.realizedPnl,
             role: .add, split: false, context: context)
      let q = book.qty.magnitudeValue
      book.avg = (q * book.avg + fill.qty * fill.price) / (q + fill.qty)
      book.qty += delta
      book.openedQty += fill.qty
      book.openNotional += fill.qty * fill.price
      book.maxQty = max(book.maxQty, book.qty.magnitudeValue)
      book.peakNotional = max(book.peakNotional, book.notional)
      book.lastNotional = book.notional
      books[k] = book
      if !book.orphan { touched.insert(roundID(book)) }
      return
    }

    let held = book.qty.magnitudeValue
    let closing = min(held, fill.qty)
    let crosses = fill.qty > held
    let share = crosses ? closing / fill.qty : 1
    record(&book, fill: fill, qty: closing, commissionShare: share, pnl: fill.realizedPnl,
           role: closing == held ? .close : .reduce, split: crosses, context: context)
    book.lastNotional = book.notional
    book.qty += fill.side.sign * closing
    book.closedQty += closing
    book.closeNotional += closing * fill.price
    if !book.orphan { touched.insert(roundID(book)) }
    if book.qty == 0 {
      book.closedAt = fill.time
      books[k] = nil
      if !book.orphan { closed.append(book) }
    } else {
      books[k] = book
    }
    if crosses {
      openBook(k, fill: fill, qty: fill.qty - closing, share: 1 - share, split: true,
               context: context, touched: &touched)
    }
  }

  private mutating func openBook(_ k: String, fill: Fill, qty: Decimal, share: Decimal, split: Bool,
                                 context: Context, touched: inout Set<String>) {
    let signed = fill.side.sign * qty
    var book = Book(
      symbol: fill.symbol, positionSide: fill.positionSide, quoteAsset: fill.marginAsset, orphan: false,
      qty: signed, avg: fill.price, firstFillID: fill.id, direction: signed > 0 ? .long : .short,
      openedAt: fill.time, updatedAt: fill.time)
    // 反手拆出来的开仓那一半：已实现盈亏全归平仓那一半，这里是 0。
    record(&book, fill: fill, qty: qty, commissionShare: share, pnl: split ? 0 : fill.realizedPnl,
           role: .open, split: split, context: context)
    book.openedQty = qty
    book.openNotional = qty * fill.price
    book.maxQty = qty
    book.peakNotional = book.notional
    book.lastNotional = book.notional
    books[k] = book
    touched.insert(roundID(book))
  }

  /// 把一笔（或拆开后的一部分）成交记进账：手续费、盈亏、明细行。
  private func record(_ book: inout Book, fill: Fill, qty: Decimal, commissionShare: Decimal, pnl: Decimal,
                      role: FillRole, split: Bool, context: Context) {
    let commission = commissionShare == 1 ? fill.commission : (fill.commission * commissionShare).amountRounded
    if book.quoteAsset.isEmpty { book.quoteAsset = fill.marginAsset }
    book.commissionByAsset[fill.commissionAsset, default: 0] += commission
    if fill.commissionAsset == book.quoteAsset {
      book.commissionQuote += commission
    } else if let price = context.markPrices[fill.commissionAsset + book.quoteAsset] {
      // BNB 抵扣：按拉取时的标记价折算，近似（协议 2.4）。
      book.commissionQuote += commission * price
    } else if commission != 0 {
      book.commissionUnpriced = true
    }
    book.realizedPnl += pnl
    book.updatedAt = max(book.updatedAt, fill.time)
    book.fills.append(RoundFill(
      id: fill.id, orderId: fill.orderId, time: fill.time, side: fill.side, positionSide: fill.positionSide,
      price: fill.price, qty: qty, quoteQty: (fill.price * qty).amountRounded, commission: commission,
      commissionAsset: fill.commissionAsset, realizedPnl: pnl, maker: fill.maker, role: role, split: split))
  }

  // MARK: - 一条资金费

  /// 分给结算时刻开着的同品种回合；多个同时开着（双向持仓两边都有仓）按名义额比例分。
  private mutating func apply(_ entry: FundingEntry, touched: inout Set<String>) {
    enum Slot { case open(String), closed(Int) }
    var slots: [(Slot, Decimal, Bool)] = []  // (位置, 权重, 是不是孤儿)
    for (k, b) in books.sorted(by: { $0.key < $1.key })
    where b.symbol == entry.symbol && b.qty != 0 && b.openedAt <= entry.time {
      slots.append((.open(k), b.notional, b.orphan))
    }
    for (i, b) in closed.enumerated()
    where b.symbol == entry.symbol && b.openedAt <= entry.time && (b.closedAt ?? .max) >= entry.time {
      slots.append((.closed(i), b.lastNotional, false))
    }
    let total = slots.reduce(Decimal(0)) { $0 + $1.1 }
    guard total > 0 else { return }  // 只有孤儿旧仓（或什么都没开）：这条归不到任何产出的回合
    var remaining = entry.amount
    for (n, (slot, weight, orphan)) in slots.enumerated() {
      let part = n == slots.count - 1 ? remaining : (entry.amount * weight / total).amountRounded
      remaining -= part
      guard !orphan else { continue }
      switch slot {
      case .open(let k):
        guard var b = books[k] else { continue }
        b.funding += part
        b.updatedAt = max(b.updatedAt, entry.time)
        books[k] = b
        touched.insert(roundID(b))
      case .closed(let i):
        closed[i].funding += part
        closed[i].updatedAt = max(closed[i].updatedAt, entry.time)
        touched.insert(roundID(closed[i]))
      }
    }
  }

  // MARK: - 产出

  private func roundID(_ b: Book) -> String {
    TradeRound.makeID(venue: venue, market: market, accountTag: accountTag, symbol: b.symbol,
                      positionSide: b.positionSide, firstFillID: b.firstFillID)
  }

  private func snapshot(_ b: Book) -> TradeRound {
    let commission = b.commissionQuote.amountRounded
    let funding = b.funding.amountRounded
    let realized = b.realizedPnl.amountRounded
    return TradeRound(
      id: roundID(b), venue: venue, market: market, symbol: b.symbol, accountTag: accountTag,
      positionSide: b.positionSide, direction: b.direction, status: b.closedAt == nil ? .open : .closed,
      quoteAsset: b.quoteAsset, openedAt: b.openedAt, closedAt: b.closedAt,
      holdingMs: b.closedAt.map { $0 - b.openedAt },
      openAvgPrice: b.openedQty > 0 ? (b.openNotional / b.openedQty).amountRounded : 0,
      closeAvgPrice: b.closedQty > 0 ? (b.closeNotional / b.closedQty).amountRounded : nil,
      openedQty: b.openedQty.amountRounded, closedQty: b.closedQty.amountRounded,
      maxQty: b.maxQty.amountRounded, peakNotional: b.peakNotional.amountRounded, leverage: b.leverage,
      realizedPnl: realized, commission: commission,
      commissionByAsset: b.commissionByAsset.mapValues(\.amountRounded),
      commissionUnpriced: b.commissionUnpriced, funding: funding,
      netPnl: realized - commission + funding, fills: b.fills, updatedAt: b.updatedAt)
  }

  private mutating func prune() {
    let closedCutoff = latestEventAt - Self.closedRetentionMs
    closed.removeAll { ($0.closedAt ?? .max) < closedCutoff }
    let seenCutoff = latestEventAt - Self.seenRetentionMs
    seen = seen.filter { $0.value >= seenCutoff }
  }
}
