import Foundation
import Testing
@testable import KanpanNetwork
import KanpanCore

/// A-T10 / A-T11 的 Swift 半边：网关把 OKX 折成币安形状之后，客户端读的是哪一列。
///
/// OKX 的一根 5 分钟 K 线同时给三个量：`vol` 是**张数**（100 张）、`volCcy` 是**币数**
/// （1 BTC）、`volCcyQuote` 是**成交额**（100000 USDT）。网关按 `Backend/kanpan-gateway/README.md`
/// 把 `volCcy` 放到币安的第 6 列（`volume`）、`volCcyQuote` 放到第 8 列（`quoteVolume`）。
/// 客户端这一侧的验收就一句话：`Bar.volume` 只能是 1，既不能是 100（张数），
/// 也不能是 100000（成交额）——拿错一列，成交量柱和 OI 的量纲就全错了。
@Suite("A-T10/A-T11 量纲与收盘标志")
struct GatewayDimensionDecodeTests {

  /// 一行「OKX 折成币安形状」的 K 线：第 6 列 1 BTC，第 8 列 100000 USDT。
  private static let row = #"[[1700000000000,"90000","90500","89500","90200","1",1700000299999,"100000",120,"0.5","45000","0"]]"#

  @Test("A-T10 REST K 线只认第 6 列（币数），不拿成交额也不拿张数")
  func restKlineVolumeIsCoinCount() throws {
    let rows = try JSONDecoder().decode([KlineRow].self, from: Data(Self.row.utf8))
    #expect(rows[0].bar.volume == 1)
    #expect(rows[0].bar.openTime == 1700000000000)
    #expect(rows[0].bar.close == 90200)
  }

  @Test("A-T10 WS K 线也只认 k.v，k.q 是成交额不许混进成交量")
  func wsKlineVolumeIsCoinCount() throws {
    let text = #"{"e":"kline","E":1700000123456,"s":"BTCUSDT","k":{"t":1700000000000,"T":1700000299999,"s":"BTCUSDT","i":"5m","o":"90000","c":"90200","h":"90500","l":"89500","v":"1","q":"100000","x":false}}"#
    let payload = try JSONDecoder().decode(StreamPayload.self, from: Data(text.utf8))
    guard case .kline(let event) = payload else { Issue.record("应当解成 kline"); return }
    #expect(event.bar.volume == 1)
    // A-T11 后半句：开盘时间只能来自 `k.t`，不能拿事件时间（`E`）顶上。
    #expect(event.openTime == 1700000000000)
    #expect(event.bar.openTime == 1700000000000)
    #expect(event.eventTime == 1700000123456)
    #expect(event.interval == "5m")
  }

  @Test("A-T11 confirm 0/1 → x false/true：没收的那根不许当收盘")
  func confirmMapsToClosedFlag() throws {
    func closed(_ x: String) throws -> Bool {
      let text = #"{"e":"kline","E":1700000123456,"s":"BTCUSDT","k":{"t":1700000000000,"s":"BTCUSDT","i":"5m","o":"1","c":"1","h":"1","l":"1","v":"1","x":\#(x)}}"#
      let payload = try JSONDecoder().decode(StreamPayload.self, from: Data(text.utf8))
      guard case .kline(let event) = payload else { throw FeedError.badResponse("不是 kline") }
      return event.closed
    }
    #expect(try closed("false") == false)    // OKX confirm=0
    #expect(try closed("true") == true)      // OKX confirm=1
    // 字段缺了也当「没收」——宁可少收一根，也不要把还在动的那根钉死。
    let missing = #"{"e":"kline","E":1,"s":"BTCUSDT","k":{"t":1700000000000,"s":"BTCUSDT","i":"5m","o":"1","c":"1","h":"1","l":"1","v":"1"}}"#
    let payload = try JSONDecoder().decode(StreamPayload.self, from: Data(missing.utf8))
    guard case .kline(let event) = payload else { Issue.record("应当解成 kline"); return }
    #expect(!event.closed)
  }

  @Test("A-T10 OKX 报价没有成交额时给空串：解成 NaN，不许变成 0")
  func emptyQuoteVolumeIsNotZero() throws {
    // 网关对 OKX 的 `quoteVolume` 恒发空串（README 钉住的行为）：0 会在界面上
    // 变成「成交额 0」，NaN 才是「这一项没有」。
    let dto = try JSONDecoder().decode(Ticker24hDTO.self, from: Data(#"{"symbol":"BTCUSDT","lastPrice":"90200","priceChangePercent":"1.5","highPrice":"90500","lowPrice":"89500","quoteVolume":"","closeTime":1700000299999}"#.utf8))
    let ticker = dto.ticker
    #expect(ticker.quoteVolume.isNaN)
    #expect(ticker.last == 90200)            // 其余字段照旧可用
    #expect(ticker.timeMs == 1700000299999)
  }
}
