import Foundation
import Testing
import KanpanCore
@testable import KanpanNetwork

/// B-06 / B-05：品种表的挂牌状态与解析失败。
///
/// 两件事在一起测是因为它们是同一次解析的两半：非 `TRADING` 的行要**留下来带着状态**，
/// 解不开的响应要**抛出来**，而不是双双退化成「这个品种不存在」。
@Suite("品种表状态与解析失败")
struct ExchangeInfoStatusTests {
  static func body(_ rows: [[String: Any]]) throws -> Data {
    try JSONSerialization.data(withJSONObject: ["symbols": rows])
  }

  static func row(_ symbol: String, status: String?, type: String = "PERPETUAL") -> [String: Any] {
    var r: [String: Any] = [
      "symbol": symbol,
      "baseAsset": symbol.replacingOccurrences(of: "USDT", with: ""),
      "quoteAsset": "USDT", "contractType": type,
      "pricePrecision": 2, "quantityPrecision": 3, "filters": [],
    ]
    if let status { r["status"] = status }
    return r
  }

  @Test("交易所的十来种挂牌状态映射成四档，非 TRADING 的行留在表里")
  func statusMapsIntoFourBuckets() throws {
    let data = try Self.body([
      Self.row("AUSDT", status: "TRADING"),
      Self.row("BUSDT", status: "PENDING_TRADING"),
      Self.row("CUSDT", status: "SETTLING"),
      Self.row("DUSDT", status: "CLOSE"),
      Self.row("EUSDT", status: nil),
      Self.row("FUSDT", status: "SOMETHING_NEW"),
      Self.row("GUSDT", status: "BREAK"),
      Self.row("HUSDT", status: "HALT"),
      Self.row("IUSDT", status: "AUCTION_MATCH"),
      Self.row("JUSDT", status: "END_OF_DAY"),
      Self.row("KUSDT", status: "PRE_SETTLE"),
      Self.row("LUSDT", status: "DELIVERED"),
    ])
    let list = try BinanceREST.parseExchangeInfo(data)
    func status(_ symbol: String) throws -> SymbolStatus {
      try #require(list.first { $0.id.symbol == symbol }).status
    }
    #expect(list.count == 12, "非 TRADING 的行不能被扔掉")
    #expect(try status("AUSDT") == .tradable)
    #expect(try status("BUSDT") == .pending)
    #expect(try status("CUSDT") == .delisted)
    #expect(try status("DUSDT") == .delisted)
    #expect(try status("KUSDT") == .delisted)
    #expect(try status("LUSDT") == .delisted)
    // 缺字段、以及交易所以后新加的状态，都按「正常」走：宁可当正常，也别把自选打成灰的。
    #expect(try status("EUSDT") == .tradable)
    #expect(try status("FUSDT") == .tradable)
    // 收盘 / 休市 / 集合竞价 / 交易所维护是**临时停牌**，不是下架（审查复核项 3）：
    // 美股永续和贵金属每天收盘都报这几种，压成下架就等于每晚摘一次牌。
    #expect(try status("GUSDT") == .halted)
    #expect(try status("HUSDT") == .halted)
    #expect(try status("IUSDT") == .halted)
    #expect(try status("JUSDT") == .halted)
    #expect(try status("AUSDT").hasLivePrice)
    #expect(try !status("CUSDT").hasLivePrice)
    #expect(try !status("BUSDT").hasLivePrice)
    // 停牌的行在列表、计数、颜色上和正常合约一模一样；「价格不动」由价格陈旧那条规则说。
    #expect(try status("GUSDT").hasLivePrice)
    #expect(try status("JUSDT").hasLivePrice)
    #expect(try status("GUSDT").isHalted && !status("AUSDT").isHalted)
  }

  @Test("产品范围的过滤条件一条没少")
  func productScopeFiltersStay() throws {
    let data = try Self.body([
      Self.row("BTCUSDT", status: "TRADING"),
      Self.row("SNDKUSDT", status: "TRADING", type: "TRADIFI_PERPETUAL"),
      Self.row("FUTUREUSDT", status: "TRADING", type: "CURRENT_QUARTER"),
      Self.row("USDCUSDT", status: "TRADING"),        // 稳定币对，永续
      ["symbol": "XUSDC", "baseAsset": "X", "quoteAsset": "USDC", "contractType": "PERPETUAL",
       "pricePrecision": 2, "quantityPrecision": 3, "filters": [], "status": "TRADING"],
    ])
    let list = try BinanceREST.parseExchangeInfo(data)
    #expect(list.map(\.symbol) == ["binance/usd_m/BTCUSDT", "binance/usd_m/SNDKUSDT"])
  }

  @Test("解不开就抛，不给空表")
  func brokenPayloadThrows() throws {
    // 交易所的错误体（-1121 之类）不是一张空表。
    let err = Data(#"{"code":-1121,"msg":"Invalid symbol."}"#.utf8)
    #expect(throws: (any Error).self) { try BinanceREST.parseExchangeInfo(err) }
    #expect(throws: (any Error).self) { try BinanceREST.parseExchangeInfo(Data("not json".utf8)) }
    // 结构对但一个品种都没有：这是**成功解析**出来的空表，由目录层去拒绝（B-05）。
    let empty = try Self.body([])
    #expect(try BinanceREST.parseExchangeInfo(empty).isEmpty)
  }

  /// 五百多行里有一行缺了必填字段（新挂的合约、网关替身表里的一行）：只丢那一行，
  /// 不能让整张品种表解不开、刷新失败、搜索和自选一直吃旧表。一行都解不开才算解不开。
  @Test("坏一行只丢那一行；全部坏掉才抛")
  func badRowDropsOnlyItself() throws {
    var broken = Self.row("BADUSDT", status: "TRADING")
    broken["pricePrecision"] = nil
    let mixed = try JSONSerialization.data(withJSONObject: ["symbols": [
      Self.row("AUSDT", status: "TRADING"), broken, "garbage", Self.row("CUSDT", status: "TRADING"),
    ] as [Any]])
    let list = try BinanceREST.parseExchangeInfo(mixed)
    #expect(list.map(\.id.symbol) == ["AUSDT", "CUSDT"])
    let allBad = try JSONSerialization.data(withJSONObject: ["symbols": [broken, "garbage"] as [Any]])
    #expect(throws: (any Error).self) { try BinanceREST.parseExchangeInfo(allBad) }
  }
}
