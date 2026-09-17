import Foundation
import Testing
@testable import KanpanNetwork
import KanpanNetworkTestSupport

@Suite("网关信封：只扫一趟就把载荷切出来")
struct GatewayEnvelopeTests {

  @Test("标量字段读得出来，载荷是原样字节")
  func basics() throws {
    let raw = #"{"source":"binance","symbol":"BTCUSDT","interval":"1m","bars":[[1,"2","3"],[4,"5","6"]]}"#
    let e = try #require(GatewayEnvelope.parse(Data(raw.utf8), field: "bars"))
    #expect(e.source == "binance")
    #expect(e.symbol == "BTCUSDT")
    #expect(e.interval == "1m")
    #expect(String(decoding: try #require(e.payload), as: UTF8.self) == #"[[1,"2","3"],[4,"5","6"]]"#)
  }

  @Test("载荷排在信封中间、后面还有字段，也切得准")
  func payloadInTheMiddle() throws {
    let raw = #"{"source":"okx", "bars" : [{"a":1},{"b":[2,3]}] ,"symbol":"ETHUSDT","interval":"5m"}"#
    let e = try #require(GatewayEnvelope.parse(Data(raw.utf8), field: "bars"))
    #expect(e.source == "okx")
    #expect(e.symbol == "ETHUSDT")
    #expect(e.interval == "5m")
    #expect(String(decoding: try #require(e.payload), as: UTF8.self) == #"[{"a":1},{"b":[2,3]}]"#)
  }

  @Test("字符串里的括号和逗号不会把扫描带偏")
  func bracketsInsideStrings() throws {
    let raw = #"{"source":"binance","instruments":{"symbols":[{"symbol":"A]},{","note":"x"}]},"symbol":"A"}"#
    let e = try #require(GatewayEnvelope.parse(Data(raw.utf8), field: "instruments"))
    #expect(e.source == "binance")
    let payload = try #require(e.payload)
    // 切出来的那段必须还是合法 JSON，而且结构和原文一致。
    let object = try #require(try JSONSerialization.jsonObject(with: payload) as? [String: Any])
    let rows = try #require(object["symbols"] as? [[String: Any]])
    #expect(rows.count == 1)
    #expect(rows[0]["symbol"] as? String == "A]},{")
  }

  @Test("切出来的字节和老路 JSONSerialization 重新序列化后等价")
  func matchesTheOldPath() throws {
    let raw = #"{"source":"binance","symbol":"BTCUSDT","interval":"1h","bars":[[1700000000000,"1.5","2","0.5","1.75","10",1700003599999,"17.5",3,"6","10.5","0"]]}"#
    let body = Data(raw.utf8)
    let sliced = try #require(GatewayEnvelope.parse(body, field: "bars")?.payload)

    let object = try #require(try JSONSerialization.jsonObject(with: body) as? [String: Any])
    let reserialized = try JSONSerialization.data(withJSONObject: try #require(object["bars"]))

    // 字节未必逐字相同（老路会重新格式化），但解出来的东西必须一样。
    let a = try JSONSerialization.jsonObject(with: sliced) as? [[Any]]
    let b = try JSONSerialization.jsonObject(with: reserialized) as? [[Any]]
    #expect(a?.count == b?.count)
    #expect(a?.first?.count == b?.first?.count)
    #expect(a?.first?.first as? Int64 == 1_700_000_000_000)
    // 而且真的能被上层解成 K 线。
    let bars = try JSONDecoder().decode([KlineRow].self, from: sliced).map(\.bar)
    #expect(bars.count == 1)
    #expect(bars[0].openTime == 1_700_000_000_000)
    #expect(bars[0].close == 1.75)
  }

  @Test("形状不对就返回 nil，让调用方退回老路")
  func bailsOutOnOddShapes() {
    // 顶层不是对象。
    #expect(GatewayEnvelope.parse(Data(#"[1,2,3]"#.utf8), field: "bars") == nil)
    // 括号没闭上。
    #expect(GatewayEnvelope.parse(Data(#"{"source":"binance","bars":[1,2"#.utf8), field: "bars") == nil)
    // 键里带转义：少见，直接放弃扫描，让调用方退回 JSONSerialization。
    let escapedKey = "{" + "\"sou\\u0072ce\":\"binance\",\"bars\":[]}"
    #expect(GatewayEnvelope.parse(Data(escapedKey.utf8), field: "bars") == nil)
    // 字段本身不在：能扫完，但没有载荷。
    #expect(GatewayEnvelope.parse(Data(#"{"source":"binance"}"#.utf8), field: "bars")?.payload == nil)
  }
}
