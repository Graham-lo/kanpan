import Foundation
import Testing
@testable import KanpanCore

// 交易复盘 · 拼回合（方案 3.3、协议 2.3）。
// 规格点名要覆盖：加仓、分批平、反手、双向持仓同时开、手续费用 BNB 抵扣、资金费为负、
// 跨 7 天窗分页拼接、同一笔成交拉两次只算一次。

enum TradeFixture {
  static let t0: Int64 = 1_790_000_000_000
  static let minute: Int64 = 60_000
  static let hour: Int64 = 3_600_000
  static let day: Int64 = 86_400_000

  static func d(_ s: String) -> Decimal { TradeDecimal.parse(s)! }

  static func fill(_ id: Int, _ side: TradeSide, _ qty: String, at price: String, t: Int64,
                   symbol: String = "BTCUSDT", ps: PositionSide = .both, pnl: String = "0",
                   fee: String = "0", feeAsset: String = "USDT") -> Fill {
    Fill(id: String(id), orderId: String(id * 10), symbol: symbol, time: t, side: side, positionSide: ps,
         price: d(price), qty: d(qty), commission: d(fee), commissionAsset: feeAsset,
         realizedPnl: d(pnl), maker: false, marginAsset: "USDT")
  }

  static func funding(_ id: Int, _ amount: String, t: Int64, symbol: String = "BTCUSDT") -> FundingEntry {
    FundingEntry(id: String(id), symbol: symbol, time: t, amount: d(amount), asset: "USDT")
  }

  static func builder() -> RoundBuilder { RoundBuilder(venue: "binance", market: "usd_m", accountTag: "primary") }
}

@Suite struct TradeRoundIDTests {
  @Test("回合 id 与协议文档里的测试向量逐字节一致（服务端 Rust 按同一张表核）")
  func vectors() {
    #expect(TradeRound.makeID(venue: "binance", market: "usd_m", accountTag: "primary", symbol: "BTCUSDT",
                              positionSide: .both, firstFillID: "5012345678")
            == "2a54e776-a993-8446-b97e-ed7561670918")
    #expect(TradeRound.makeID(venue: "binance", market: "usd_m", accountTag: "primary", symbol: "ETHUSDT",
                              positionSide: .short, firstFillID: "987654321")
            == "7482f6ac-d858-8f56-9479-152b2fd978e9")
  }

  @Test("id 是合法的 UUIDv8：服务端 uuid 列收得下")
  func isUUIDv8() throws {
    let id = TradeRound.makeID(venue: "binance", market: "usd_m", accountTag: "primary", symbol: "X",
                               positionSide: .long, firstFillID: "1")
    let uuid = try #require(UUID(uuidString: id))
    #expect(uuid.uuidString.lowercased() == id)
    #expect(Array(id)[14] == "8", "版本位是 8")
    #expect("89ab".contains(Array(id)[19]), "变体位是 10xx")
  }
}

@Suite struct TradeRoundBuilderTests {
  typealias F = TradeFixture

  @Test("开一次平一次：均价、时长、净盈亏 = 已实现 − 手续费 + 资金费")
  func simpleRound() throws {
    var b = F.builder()
    let out = b.ingest(fills: [
      F.fill(1, .buy, "1", at: "100", t: F.t0, fee: "0.04"),
      F.fill(2, .sell, "1", at: "110", t: F.t0 + F.hour, pnl: "10", fee: "0.044"),
    ], funding: [], context: .init(leverage: ["BTCUSDT": 20]))
    let r = try #require(out.first)
    #expect(out.count == 1)
    #expect(r.status == .closed && r.direction == .long && r.positionSide == .both)
    #expect(r.openAvgPrice == 100 && r.closeAvgPrice == 110)
    #expect(r.holdingMs == F.hour && r.closedAt == F.t0 + F.hour)
    #expect(r.realizedPnl == 10 && r.commission == F.d("0.084") && r.netPnl == F.d("9.916"))
    #expect(r.leverage == 20)
    #expect(r.fills.map(\.role) == [.open, .close])
    #expect(r.id == TradeRound.makeID(venue: "binance", market: "usd_m", accountTag: "primary",
                                      symbol: "BTCUSDT", positionSide: .both, firstFillID: "1"))
  }

  @Test("加仓：持仓均价按数量加权，最大持仓量与名义峰值跟着涨")
  func addingToPosition() throws {
    var b = F.builder()
    let out = b.ingest(fills: [
      F.fill(1, .buy, "1", at: "100", t: F.t0),
      F.fill(2, .buy, "1", at: "120", t: F.t0 + F.minute),
      F.fill(3, .sell, "2", at: "130", t: F.t0 + 2 * F.minute, pnl: "40"),
    ], funding: [], context: .init())
    let r = try #require(out.first)
    #expect(r.openAvgPrice == 110 && r.openedQty == 2 && r.closedQty == 2)
    #expect(r.maxQty == 2 && r.peakNotional == 220)
    #expect(r.fills.map(\.role) == [.open, .add, .close])
    #expect(r.netPnl == 40)
  }

  @Test("分批平：减仓不结束回合（持仓中），最后一笔回到 0 才结束；平仓均价按数量加权")
  func partialCloses() throws {
    var b = F.builder()
    let first = b.ingest(fills: [
      F.fill(1, .buy, "3", at: "100", t: F.t0),
      F.fill(2, .sell, "1", at: "110", t: F.t0 + F.hour, pnl: "10"),
    ], funding: [], context: .init())
    let open = try #require(first.first)
    #expect(open.status == .open && open.closedAt == nil && open.holdingMs == nil)
    #expect(open.closeAvgPrice == 110 && open.closedQty == 1)
    #expect(b.openRounds.map(\.id) == [open.id])

    let second = b.ingest(fills: [F.fill(3, .sell, "2", at: "90", t: F.t0 + 2 * F.hour, pnl: "-20")],
                          funding: [], context: .init())
    let done = try #require(second.first)
    #expect(done.id == open.id, "同一个回合，平仓后换一版")
    #expect(done.status == .closed && done.closedQty == 3)
    #expect(done.closeAvgPrice == F.d("96.66666667"))
    #expect(done.fills.map(\.role) == [.open, .reduce, .close])
    #expect(done.realizedPnl == -10)
    #expect(b.openRounds.isEmpty)
  }

  @Test("反手：穿 0 的那一笔拆两半，盈亏全归平仓那一半，手续费按数量分；新回合以这笔为首笔")
  func reversal() throws {
    var b = F.builder()
    let out = b.ingest(fills: [
      F.fill(1, .buy, "2", at: "100", t: F.t0),
      F.fill(2, .sell, "5", at: "90", t: F.t0 + F.hour, pnl: "-20", fee: "0.5"),
    ], funding: [], context: .init())
    #expect(out.count == 2)
    let long = try #require(out.first { $0.direction == .long })
    let short = try #require(out.first { $0.direction == .short })
    #expect(long.status == .closed && long.realizedPnl == -20 && long.commission == F.d("0.2"))
    #expect(long.fills.last?.qty == 2 && long.fills.last?.split == true && long.fills.last?.role == .close)
    #expect(short.status == .open && short.openAvgPrice == 90 && short.maxQty == 3)
    #expect(short.commission == F.d("0.3") && short.realizedPnl == 0)
    #expect(short.fills.map(\.id) == ["2"] && short.fills[0].split && short.fills[0].role == .open)
    #expect(short.id == TradeRound.makeID(venue: "binance", market: "usd_m", accountTag: "primary",
                                          symbol: "BTCUSDT", positionSide: .both, firstFillID: "2"))
    #expect(short.id != long.id)

    let closeShort = b.ingest(fills: [F.fill(3, .buy, "3", at: "80", t: F.t0 + 2 * F.hour, pnl: "30")],
                              funding: [], context: .init())
    #expect(closeShort.map(\.id) == [short.id])
    #expect(closeShort.first?.status == .closed && closeShort.first?.netPnl == F.d("29.7"))
  }

  @Test("双向持仓：多空两本账同时开，各自成回合；资金费按两边名义额分")
  func hedgeModeBothSides() throws {
    var b = F.builder()
    let out = b.ingest(fills: [
      F.fill(1, .buy, "1", at: "100", t: F.t0, ps: .long),
      F.fill(2, .sell, "2", at: "100", t: F.t0 + F.minute, ps: .short),
      F.fill(3, .sell, "1", at: "105", t: F.t0 + 9 * F.hour, ps: .long, pnl: "5"),
      F.fill(4, .buy, "2", at: "105", t: F.t0 + 9 * F.hour, ps: .short, pnl: "-10"),
    ], funding: [F.funding(900, "-3", t: F.t0 + 8 * F.hour)], context: .init())
    #expect(out.count == 2)
    let long = try #require(out.first { $0.positionSide == .long })
    let short = try #require(out.first { $0.positionSide == .short })
    #expect(long.direction == .long && short.direction == .short)
    #expect(long.funding == -1 && short.funding == -2, "名义额 100 : 200")
    #expect(long.netPnl == 4 && short.netPnl == -12)
    #expect(long.id != short.id)
  }

  @Test("BNB 抵扣手续费：按拉取时 BNB 合约的标记价折成 USDT；折不出价的标出来、原值留着")
  func bnbCommission() throws {
    var b = F.builder()
    let out = b.ingest(fills: [
      F.fill(1, .buy, "1", at: "100", t: F.t0, fee: "0.0001", feeAsset: "BNB"),
      F.fill(2, .sell, "1", at: "110", t: F.t0 + F.hour, pnl: "10", fee: "0.02"),
    ], funding: [], context: .init(markPrices: ["BNBUSDT": 600]))
    let r = try #require(out.first)
    #expect(r.commission == F.d("0.08"), "0.0001 BNB × 600 + 0.02 USDT")
    #expect(r.commissionByAsset == ["BNB": F.d("0.0001"), "USDT": F.d("0.02")])
    #expect(!r.commissionUnpriced)

    var bare = F.builder()
    let unpriced = try #require(bare.ingest(fills: [
      F.fill(1, .buy, "1", at: "100", t: F.t0, fee: "0.0001", feeAsset: "BNB"),
    ], funding: [], context: .init()).first)
    #expect(unpriced.commissionUnpriced && unpriced.commission == 0)
    #expect(unpriced.commissionByAsset["BNB"] == F.d("0.0001"))
  }

  @Test("资金费为负：记进回合、拉低净盈亏；平仓之后下一次才拉到的资金费照样归回去并重出一版")
  func negativeFundingAndLateArrival() throws {
    var b = F.builder()
    let out = b.ingest(fills: [
      F.fill(1, .buy, "1", at: "100", t: F.t0),
      F.fill(2, .sell, "1", at: "110", t: F.t0 + 10 * F.hour, pnl: "10"),
    ], funding: [F.funding(1, "-1.5", t: F.t0 + 8 * F.hour)], context: .init())
    let r = try #require(out.first)
    #expect(r.funding == F.d("-1.5") && r.netPnl == F.d("8.5"))

    // 结算点在平仓前，但流水下一次增量才拉到。
    let late = b.ingest(fills: [], funding: [F.funding(2, "-0.5", t: F.t0 + 9 * F.hour)], context: .init())
    let again = try #require(late.first)
    #expect(again.id == r.id && again.funding == -2 && again.netPnl == 8)
    #expect(again.updatedAt == r.updatedAt, "平仓那笔晚于这条资金费，updatedAt 不倒退")

    // 平仓之后才结算的资金费不属于它。
    let after = b.ingest(fills: [], funding: [F.funding(3, "-9", t: F.t0 + 11 * F.hour)], context: .init())
    #expect(after.isEmpty)
  }

  @Test("跨 7 天窗分页拼接：分两页、页界重叠拉到的同一笔只算一次，结果与一次拉完完全一样")
  func stitchingAcrossWindows() throws {
    let fills = [
      F.fill(1, .buy, "1", at: "100", t: F.t0),
      F.fill(2, .buy, "1", at: "110", t: F.t0 + 6 * F.day),
      F.fill(3, .sell, "1", at: "120", t: F.t0 + 7 * F.day - 1, pnl: "15"),
      F.fill(4, .sell, "1", at: "130", t: F.t0 + 7 * F.day + F.hour, pnl: "25"),
      F.fill(5, .sell, "1", at: "125", t: F.t0 + 9 * F.day),
    ]
    let funding = [F.funding(1, "-0.2", t: F.t0 + 2 * F.day), F.funding(2, "0.1", t: F.t0 + 8 * F.day)]
    var whole = F.builder()
    let expected = whole.ingest(fills: fills, funding: funding, context: .init())

    var paged = F.builder()
    let page1 = paged.ingest(fills: Array(fills[0...2]), funding: [funding[0]], context: .init())
    // 第二页往回重叠一小时，fill 3 又被拉到一次。
    let page2 = paged.ingest(fills: Array(fills[2...4]), funding: funding, context: .init())
    #expect(page1.count == 1 && page1[0].status == .open)
    let merged = Dictionary((page1 + page2).map { ($0.id, $0) }, uniquingKeysWith: { _, new in new })
    #expect(merged.count == expected.count)
    for r in expected { #expect(merged[r.id] == r, "\(r.id)") }
    #expect(expected.count == 2, "fill 5 开了一个新的空头回合")
  }

  @Test("同一批成交再喂一次：什么都不产出，回合不变")
  func duplicateIngestIsIdempotent() throws {
    let fills = [F.fill(1, .buy, "1", at: "100", t: F.t0), F.fill(2, .sell, "1", at: "105", t: F.t0 + 1, pnl: "5")]
    var b = F.builder()
    let first = b.ingest(fills: fills + fills, funding: [F.funding(1, "1", t: F.t0)], context: .init())
    #expect(first.count == 1 && first[0].fills.count == 2 && first[0].realizedPnl == 5)
    let again = b.ingest(fills: fills, funding: [F.funding(1, "1", t: F.t0)], context: .init())
    #expect(again.isEmpty)
  }

  @Test("回溯窗口之前就开着的旧仓：先消化到 0，那段残缺回合不产出；穿 0 剩下的部分照常开新回合")
  func orphanBeforeWindow() throws {
    var b = F.builder()
    // 现在空仓；窗口里先卖 1（平掉窗口前的 1 个多头），再开一轮。
    let out = b.ingest(fills: [
      F.fill(1, .sell, "1", at: "100", t: F.t0, pnl: "7"),
      F.fill(2, .buy, "2", at: "101", t: F.t0 + F.hour),
      F.fill(3, .sell, "2", at: "102", t: F.t0 + 2 * F.hour, pnl: "2"),
    ], funding: [], context: .init(currentPositions: [:]))
    #expect(out.count == 1 && out[0].fills.map(\.id) == ["2", "3"])

    var c = F.builder()
    // 现在空头 2；窗口前是多头 1，窗口里卖 3 穿过 0。
    let key = PositionKey(symbol: "BTCUSDT", positionSide: .both)
    let crossed = c.ingest(fills: [F.fill(1, .sell, "3", at: "100", t: F.t0, pnl: "7", fee: "0.3")],
                           funding: [], context: .init(currentPositions: [key: -2]))
    let r = try #require(crossed.first)
    #expect(crossed.count == 1 && r.direction == .short && r.status == .open)
    #expect(r.maxQty == 2 && r.realizedPnl == 0 && r.commission == F.d("0.2"))
  }

  @Test("拼回合的状态落盘再读回来，接着喂和一路喂到底完全一样")
  func stateRoundTrip() throws {
    let a = [F.fill(1, .buy, "1.5", at: "100.12345678", t: F.t0, fee: "0.0001", feeAsset: "BNB")]
    let c = [F.fill(2, .sell, "1.5", at: "101", t: F.t0 + F.hour, pnl: "1.31481483")]
    let ctx = RoundBuilder.Context(markPrices: ["BNBUSDT": F.d("612.3")])
    var straight = F.builder()
    _ = straight.ingest(fills: a, funding: [], context: ctx)
    let expected = straight.ingest(fills: c, funding: [], context: ctx)

    var saved = F.builder()
    _ = saved.ingest(fills: a, funding: [], context: ctx)
    let data = try JSONEncoder().encode(saved)
    var restored = try JSONDecoder().decode(RoundBuilder.self, from: data)
    #expect(restored.initialized)
    #expect(restored.ingest(fills: c, funding: [], context: ctx) == expected)
  }
}

@Suite struct TradeRoundCodingTests {
  typealias F = TradeFixture

  @Test("线上格式：数字是十进制字符串、时间是整数毫秒、可空键写 null；解回来一模一样")
  func wireShape() throws {
    var b = F.builder()
    let r = try #require(b.ingest(fills: [F.fill(7, .buy, "0.001", at: "65000.1", t: F.t0, fee: "0.026")],
                                  funding: [], context: .init()).first)
    let data = try JSONEncoder().encode(r)
    let json = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
    #expect(json["openAvgPrice"] as? String == "65000.1")
    #expect(json["commission"] as? String == "0.026")
    #expect(json["funding"] as? String == "0")
    #expect(json["openedAt"] as? Int64 == F.t0)
    for key in ["closedAt", "holdingMs", "closeAvgPrice", "leverage"] {
      #expect(json[key] is NSNull, "\(key) 要写成 null，不能省略")
    }
    #expect((json["commissionByAsset"] as? [String: String]) == ["USDT": "0.026"])
    let fill = try #require((json["fills"] as? [[String: Any]])?.first)
    #expect(fill["qty"] as? String == "0.001" && fill["role"] as? String == "open" && fill["id"] as? String == "7")
    #expect(try JSONDecoder().decode(TradeRound.self, from: data) == r)
  }

  @Test("十进制格式化不出科学计数法，零写 0")
  func decimalFormat() {
    #expect(TradeDecimal.format(F.d("0.00000001")) == "0.00000001")
    #expect(TradeDecimal.format(F.d("1.50")) == "1.5")
    #expect(TradeDecimal.format(F.d("-0.0")) == "0")
    #expect(TradeDecimal.format(F.d("123456789012.5")) == "123456789012.5")
    #expect(TradeDecimal.parse("abc") == nil && TradeDecimal.parse("") == nil)
  }
}
