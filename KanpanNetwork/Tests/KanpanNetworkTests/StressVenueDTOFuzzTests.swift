import Foundation
import Testing
@testable import KanpanNetwork
import KanpanNetworkTestSupport
import KanpanCore

// 压测（2026-10-08）：三家（OKX / Bybit / Hyperliquid）的报文解码喂畸形输入。
//
// 从一份合法的帧出发，按固定种子随机地删字段、换成坏值（`"NaN"`、`"inf"`、带空格的数字、负价、零价、
// 超大数、超长串、unicode、类型错的嵌套）、重复 / 乱序 / 清空数组、截断文本，每份模板几千个样本。
// 判据：不崩；出来的价永远是有限正数（只带费率的标记价帧按约定是 NaN 价）；K 线根根有效；坏的整帧丢。

// ---------------------------------------------------------------- 模糊器

struct FuzzRNG {
  private var state: UInt64
  init(seed: UInt64) { state = seed }
  mutating func next() -> UInt64 {
    state &+= 0x9E37_79B9_7F4A_7C15
    var z = state
    z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
    z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
    return z ^ (z >> 31)
  }
  mutating func below(_ n: Int) -> Int { Int(next() % UInt64(max(1, n))) }
}

enum Fuzz {
  /// 坏值清单：数字字符串的各种歪法、类型错、超大、超长、unicode。
  nonisolated(unsafe) static let evils: [Any] = [
    "NaN", "nan", "inf", "-inf", "Infinity", " 1.5", "1.5 ", "", "-1", "0", "-0", "0.0", "1e400", "1e308", "-1e308",
    "1e-400", "0x10", "１２３", "比特币", "😀", "kAITO", "KAITO", String(repeating: "9", count: 400),
    String(repeating: "A", count: 5000), "9223372036854775807", "-9223372036854775808", "99999999999999999999",
    "1e18", "1e19", "BTC-USDT-SWAP\u{0}", "BTC-USDT-SWAP", "tickers.BTCUSDT", NSNull(), [Any](), [String: Any](),
    true, false, NSNumber(value: 1e308), NSNumber(value: -5), NSNumber(value: 0), NSNumber(value: Int64.max),
    NSNumber(value: Int64.min), NSNumber(value: 1.5), ["nested": ["deep": [1, 2, 3]]], [[["x"]]],
  ]

  static func mutate(_ v: Any, _ r: inout FuzzRNG, depth: Int = 0) -> Any? {
    if var d = v as? [String: Any], !d.isEmpty, depth < 6, r.below(5) != 0 {
      let keys = d.keys.sorted()
      let k = keys[r.below(keys.count)]
      switch r.below(6) {
      case 0: d[k] = nil
      case 1, 2, 3: d[k] = mutate(d[k]!, &r, depth: depth + 1)
      default: d[k] = evils[r.below(evils.count)]
      }
      return d
    }
    if var a = v as? [Any], depth < 6, r.below(5) != 0 {
      if a.isEmpty { return [evils[r.below(evils.count)]] }
      let i = r.below(a.count)
      switch r.below(9) {
      case 0: a.remove(at: i)
      case 1: a.append(a[i])
      case 2: a.reverse()
      case 3: a = []
      case 4: a.swapAt(i, r.below(a.count))
      case 5, 6, 7: if let m = mutate(a[i], &r, depth: depth + 1) { a[i] = m } else { a.remove(at: i) }
      default: a[i] = evils[r.below(evils.count)]
      }
      return a
    }
    if r.below(12) == 0 { return nil }
    return evils[r.below(evils.count)]
  }

  static func text(_ obj: Any) -> String? {
    guard let data = try? JSONSerialization.data(withJSONObject: obj, options: [.fragmentsAllowed, .sortedKeys]) else {
      return nil
    }
    return String(decoding: data, as: UTF8.self)
  }

  /// 从一份模板派生 `count` 个畸形样本（含原样那一份）。
  static func samples(_ template: String, count: Int, seed: UInt64) -> [String] {
    guard let root = try? JSONSerialization.jsonObject(with: Data(template.utf8), options: [.fragmentsAllowed]) else {
      Issue.record("模板不是 JSON：\(template.prefix(80))")
      return []
    }
    var r = FuzzRNG(seed: seed)
    var out = [template]
    for _ in 0..<count {
      switch r.below(10) {
      case 0:
        // 文本层面的坏：截断、尾巴拼垃圾、引号乱掉。
        let cut = template.index(template.startIndex, offsetBy: r.below(template.count))
        out.append([String(template[..<cut]), template + "}}", template.replacingOccurrences(of: "\"", with: "'"),
                    "", "null", "[]", "pong", "{}"][r.below(8)])
      default:
        var obj: Any? = root
        for _ in 0...r.below(3) { obj = obj.flatMap { mutate($0, &r) } }
        if let obj, let t = text(obj) { out.append(t) }
      }
    }
    return out
  }
}

// ---------------------------------------------------------------- 不变式

/// 出来的东西必须守的规矩。`venue` 是这一家的 id：品种键必须落在这一家头上。
func checkPayloads(_ ps: [StreamPayload], venue: String, _ sample: String,
                   sourceLocation: SourceLocation = #_sourceLocation) {
  func ok(_ cond: Bool, _ what: String) {
    if !cond { Issue.record("\(what)：\(sample.prefix(240))", sourceLocation: sourceLocation) }
  }
  for p in ps {
    switch p {
    case .ticker(let t):
      ok(t.last.isFinite && t.last > 0, "最新价不是有限正数 \(t.last)")
      ok(InstrumentID(t.symbol).venue == venue, "品种键串了家 \(t.symbol)")
      ok(!t.high.isInfinite && !(t.high <= 0), "最高价 \(t.high)")
      ok(!t.low.isInfinite && !(t.low <= 0), "最低价 \(t.low)")
      ok(!t.quoteVolume.isInfinite && !(t.quoteVolume < 0), "成交额 \(t.quoteVolume)")
      ok(!t.changePercent.isInfinite, "涨跌幅 \(t.changePercent)")
      ok(t.markPrice.map { $0.isFinite && $0 > 0 } ?? true, "标记价 \(String(describing: t.markPrice))")
      ok(t.open24h.map { $0.isFinite && $0 > 0 } ?? true, "24h 开盘 \(String(describing: t.open24h))")
      ok(t.priceChange.map(\.isFinite) ?? true, "涨跌额")
    case .markPrice(let symbol, let price, let tick):
      ok(InstrumentID(symbol).venue == venue, "标记价品种键串了家 \(symbol)")
      ok((price.isFinite && price > 0) || (price.isNaN && tick.fundingRate != nil), "标记价 \(price)")
      ok(tick.fundingRate.map(\.isFinite) ?? true, "费率")
      ok(tick.indexPrice.map { $0.isFinite && $0 > 0 } ?? true, "指数价 \(String(describing: tick.indexPrice))")
    case .kline(let k):
      ok(InstrumentID(k.symbol).venue == venue, "K 线品种键串了家 \(k.symbol)")
      ok(k.bar.isValidMarketBar && k.bar.low > 0, "K 线无效 \(k.bar)")
      ok(k.openTime > 0 && k.openTime == k.bar.openTime && k.openTime < 100_000_000_000_000, "K 线时间 \(k.openTime)")
      ok(Interval(rawValue: k.interval) != nil, "K 线周期 \(k.interval)")
    case .trade(let t):
      ok(InstrumentID(t.symbol).venue == venue, "成交品种键串了家 \(t.symbol)")
      ok(t.price.isFinite && t.price > 0 && t.qty.isFinite && t.qty >= 0, "成交 \(t.price) × \(t.qty)")
    default:
      ok(false, "这一家不该出这种报文 \(p)")
    }
  }
}

func checkBars(_ bars: [Bar], _ sample: String, sourceLocation: SourceLocation = #_sourceLocation) {
  for b in bars where !(b.isValidMarketBar && b.low > 0 && b.openTime > 0 && b.openTime < 100_000_000_000_000) {
    Issue.record("坏 K 线 \(b)：\(sample.prefix(200))", sourceLocation: sourceLocation)
  }
  // 一页里重复给的同一根照出（提供者那一层 `MarketSeries.dedup` 去重），只要求升序。
  if zip(bars, bars.dropFirst()).contains(where: { $0.openTime > $1.openTime }) {
    Issue.record("K 线没按开盘时间升序：\(sample.prefix(200))", sourceLocation: sourceLocation)
  }
}

func checkInfo(_ info: SymbolInfo, venue: String, _ sample: String, sourceLocation: SourceLocation = #_sourceLocation) {
  let good = InstrumentID(info.symbol).venue == venue && info.tickSize.isFinite && info.tickSize > 0
    && (0...12).contains(info.pricePrecision) && (0...12).contains(info.quantityPrecision) && !info.base.isEmpty
  if !good { Issue.record("坏品种信息 \(info)：\(sample.prefix(200))", sourceLocation: sourceLocation) }
}

// ---------------------------------------------------------------- 模板

enum Templates {
  static let okxPush: [(OKXVenue.Endpoint, String)] = [
    (.public, #"{"arg":{"channel":"tickers","instId":"BTC-USDT-SWAP"},"data":[{"instId":"BTC-USDT-SWAP","last":"65000.1","open24h":"64000","high24h":"66000","low24h":"63000","volCcy24h":"1234.5","ts":"1700000000000"}]}"#),
    (.public, #"{"arg":{"channel":"trades","instId":"BTC-USDT-SWAP"},"data":[{"instId":"BTC-USDT-SWAP","tradeId":"1","px":"65000","sz":"1","side":"buy","ts":"1700000000000"},{"instId":"BTC-USDT-SWAP","tradeId":"2","px":"65001","sz":"2","side":"sell","ts":"1700000000001"}]}"#),
    (.public, #"{"arg":{"channel":"mark-price","instId":"BTC-USDT-SWAP"},"data":[{"instId":"BTC-USDT-SWAP","markPx":"65000.5","ts":"1700000000000"}]}"#),
    (.public, #"{"arg":{"channel":"funding-rate","instId":"BTC-USDT-SWAP"},"data":[{"instId":"BTC-USDT-SWAP","fundingRate":"0.0001","fundingTime":"1700006400000","ts":"1700000000000"}]}"#),
    (.public, #"{"event":"error","code":"60018","msg":"Wrong URL or channel:tickers,instId:FOO-USDT-SWAP doesn't exist"}"#),
    (.public, #"{"event":"subscribe","arg":{"channel":"tickers","instId":"BTC-USDT-SWAP"},"connId":"a1"}"#),
    (.business, #"{"arg":{"channel":"candle1m","instId":"BTC-USDT-SWAP"},"data":[["1700000060000","2","3","1.5","2.5","10","10","25","0"],["1700000000000","1","2","0.5","1.5","10","10","15","1"]]}"#),
    (.business, #"{"arg":{"channel":"candle1Dutc","instId":"ETH-USDT-SWAP"},"data":[["1700000000000","1","2","0.5","1.5","10","10","15","1"]]}"#),
  ]
  static let okxCandlePage = #"{"code":"0","msg":"","data":[["1700000120000","2","3","1.5","2.5","10","10","25","0"],["1700000060000","2","3","1.5","2.5","10","10","25","1"],["1700000000000","1","2","0.5","1.5","10","10","15","1"]]}"#
  static let okxInstruments = #"{"code":"0","msg":"","data":[{"instId":"BTC-USDT-SWAP","instType":"SWAP","ctType":"linear","settleCcy":"USDT","ctVal":"0.01","ctValCcy":"BTC","tickSz":"0.1","lotSz":"0.01","state":"live","listTime":"1600000000000"},{"instId":"PEPE-USDT-SWAP","instType":"SWAP","ctType":"linear","settleCcy":"USDT","ctVal":"10000000","ctValCcy":"PEPE","tickSz":"1e-9","lotSz":"1","state":"suspend","listTime":"0"}]}"#
  static let okxTickers = #"{"code":"0","msg":"","data":[{"instId":"BTC-USDT-SWAP","last":"65000.1","open24h":"64000","high24h":"66000","low24h":"63000","volCcy24h":"1234.5","ts":"1700000000000"},{"instId":"ETH-USDT-SWAP","last":"3000","open24h":"0","high24h":"","low24h":"-1","volCcy24h":"1e308","ts":"x"}]}"#
  static let okxOIHistory = #"{"data":{"source":"okx","symbol":"BTCUSDT","period":"5m","rows":[[1790162100000,1.5,null],[1790161800000,1,null]]}}"#
  static let okxFundingTable = #"{"data":{"source":"okx","rows":[{"symbol":"BTCUSDT","rate":0.0001,"nextFundingTime":1790121600000},{"symbol":"ETHUSDT","rate":-0.0002}]}}"#

  static let bybitPush = [
    #"{"topic":"tickers.BTCUSDT","type":"snapshot","ts":1700000000000,"data":{"symbol":"BTCUSDT","lastPrice":"65000","prevPrice24h":"64000","price24hPcnt":"0.015625","highPrice24h":"66000","lowPrice24h":"63000","turnover24h":"123456789","volume24h":"1900","markPrice":"65001","indexPrice":"65002","fundingRate":"0.0001","nextFundingTime":"1700006400000","openInterest":"5000"}}"#,
    #"{"topic":"tickers.BTCUSDT","type":"delta","ts":1700000000100,"data":{"symbol":"BTCUSDT","lastPrice":"65010","markPrice":"65011","turnover24h":"123456999"}}"#,
    #"{"topic":"kline.1.BTCUSDT","type":"snapshot","ts":1700000000000,"data":[{"start":1700000000000,"end":1700000059999,"interval":"1","open":"1","close":"1.5","high":"2","low":"0.5","volume":"10","turnover":"15","confirm":false,"timestamp":1700000000000}]}"#,
    #"{"topic":"publicTrade.BTCUSDT","type":"snapshot","ts":1700000000000,"data":[{"T":1700000000000,"s":"BTCUSDT","S":"Buy","v":"0.001","p":"65000","i":"a"},{"T":1700000000001,"s":"BTCUSDT","S":"Sell","v":"0.002","p":"65001","i":"b"}]}"#,
    #"{"success":false,"ret_msg":"Invalid symbol :[tickers.XUSDT]","conn_id":"c","op":"subscribe"}"#,
    #"{"success":true,"ret_msg":"","conn_id":"c","op":"subscribe"}"#,
  ]
  static let bybitKlinePage = #"{"retCode":0,"retMsg":"OK","result":{"category":"linear","symbol":"BTCUSDT","list":[["1700000120000","2","3","1.5","2.5","10","25"],["1700000060000","2","3","1.5","2.5","10","25"],["1700000000000","1","2","0.5","1.5","10","15"]]},"time":1700000130000}"#
  static let bybitInstruments = #"{"retCode":0,"retMsg":"OK","result":{"category":"linear","list":[{"symbol":"BTCUSDT","contractType":"LinearPerpetual","status":"Trading","baseCoin":"BTC","quoteCoin":"USDT","launchTime":"1584230400000","priceScale":"2","priceFilter":{"tickSize":"0.10"},"lotSizeFilter":{"qtyStep":"0.001"}},{"symbol":"1000PEPEUSDT","contractType":"LinearPerpetual","status":"PreLaunch","baseCoin":"1000PEPE","quoteCoin":"USDT","launchTime":"0","priceFilter":{"tickSize":"1e-7"},"lotSizeFilter":{"qtyStep":"100"}}],"nextPageCursor":""},"time":1700000000000}"#
  static let bybitTickers = #"{"retCode":0,"retMsg":"OK","result":{"category":"linear","list":[{"symbol":"BTCUSDT","lastPrice":"65000","prevPrice24h":"64000","price24hPcnt":"0.015625","highPrice24h":"66000","lowPrice24h":"63000","turnover24h":"123456789","volume24h":"1900","markPrice":"65001","indexPrice":"65002","fundingRate":"0.0001","nextFundingTime":"1700006400000","openInterest":"5000"}]},"time":1700000000000}"#
  static let bybitOI = #"{"retCode":0,"retMsg":"OK","result":{"category":"linear","symbol":"BTCUSDT","list":[{"openInterest":"5000.5","timestamp":"1700000300000"},{"openInterest":"4999","timestamp":"1700000000000"}],"nextPageCursor":""},"time":1700000400000}"#

  static let hlPush = [
    #"{"channel":"candle","data":{"t":1700000000000,"T":1700000059999,"s":"BTC","i":"1m","o":"65000","c":"65010","h":"65020","l":"64990","v":"1.5","n":10}}"#,
    #"{"channel":"candle","data":[{"t":1700000000000,"T":1700000059999,"s":"kPEPE","i":"5m","o":"0.01","c":"0.011","h":"0.012","l":"0.009","v":"1000","n":3}]}"#,
    #"{"channel":"trades","data":[{"coin":"BTC","side":"B","px":"65000","sz":"0.1","time":1700000000000,"hash":"0x","tid":1},{"coin":"BTC","side":"A","px":"65001","sz":"0.2","time":1700000000001,"hash":"0x","tid":2}]}"#,
    #"{"channel":"activeAssetCtx","data":{"coin":"BTC","ctx":{"funding":"0.0000125","openInterest":"1000","prevDayPx":"64000","dayNtlVlm":"123456789","markPx":"65001","midPx":"65000.5","oraclePx":"65002","dayBaseVlm":"1900"}}}"#,
    #"{"channel":"subscriptionResponse","data":{"method":"subscribe","subscription":{"type":"candle","coin":"BTC","interval":"1m"}}}"#,
    #"{"channel":"error","data":"Invalid subscription {\"type\":\"candle\",\"coin\":\"NOPE\",\"interval\":\"1m\"}"}"#,
    #"{"channel":"pong"}"#,
  ]
  static let hlCandlePage = #"[{"t":1700000000000,"T":1700000059999,"s":"BTC","i":"1m","o":"65000","c":"65010","h":"65020","l":"64990","v":"1.5","n":10},{"t":1700000060000,"T":1700000119999,"s":"BTC","i":"1m","o":"65010","c":"65000","h":"65030","l":"64980","v":"2","n":11}]"#
  static let hlMetaAndCtxs = #"[{"universe":[{"name":"BTC","szDecimals":5,"maxLeverage":40},{"name":"kPEPE","szDecimals":0,"maxLeverage":10},{"name":"OLD","szDecimals":2,"maxLeverage":3,"isDelisted":true}]},[{"funding":"0.0000125","openInterest":"1000","prevDayPx":"64000","dayNtlVlm":"123456789","markPx":"65001","midPx":"65000.5","oraclePx":"65002","dayBaseVlm":"1900"},{"funding":"0.00001","openInterest":"1","prevDayPx":"0.01","dayNtlVlm":"100","markPx":"0.011","midPx":null,"oraclePx":"0.011","dayBaseVlm":"1"},{"funding":"0","openInterest":"0","prevDayPx":"1","dayNtlVlm":"0","markPx":"1","midPx":"1","oraclePx":"1","dayBaseVlm":"0"}]]"#
}

// ---------------------------------------------------------------- 模糊

extension StressVenueSerial {
  @Suite("压测 · 三家报文模糊", .timeLimit(.minutes(3)))
  struct StressVenueDTOFuzzTests {
    static let perTemplate = 1_500

    @Test("OKX 推送：tickers / trades / mark-price / funding-rate / candle / 事件帧 × 畸形 → 不崩、价有限为正、K 线根根有效")
    func okxPushFuzz() {
      OKXVenue.contractValues.set(["BTC-USDT-SWAP": 0.01])
      for (n, (endpoint, template)) in Templates.okxPush.enumerated() {
        let wire = OKXWire(endpoint: endpoint)
        for sample in Fuzz.samples(template, count: Self.perTemplate, seed: 0x0C5 + UInt64(n)) {
          let frame = wire.decode(sample)
          checkPayloads(frame.payloads, venue: OKXVenue.id, sample)
        }
      }
    }

    @Test("OKX REST：K 线页、品种表、整表行情、持仓量历史、费率整表 × 畸形 → 要么报错要么全是好数")
    func okxRESTFuzz() {
      for sample in Fuzz.samples(Templates.okxCandlePage, count: Self.perTemplate, seed: 11) {
        if let bars = try? OKXDTO.bars(Data(sample.utf8)) { checkBars(bars, sample) }
      }
      for sample in Fuzz.samples(Templates.okxInstruments, count: Self.perTemplate, seed: 12) {
        guard let rows: [OKXDTO.Instrument] = try? OKXDTO.rows(Data(sample.utf8), "品种表") else { continue }
        for row in rows where row.isListed {
          if let info = row.symbolInfo { checkInfo(info, venue: OKXVenue.id, sample) }
          if let v = row.contractValue, !(v.isFinite && v > 0) { Issue.record("面值 \(v)") }
        }
      }
      for sample in Fuzz.samples(Templates.okxTickers, count: Self.perTemplate, seed: 13) {
        guard let rows: [OKXDTO.TickerRow] = try? OKXDTO.rows(Data(sample.utf8), "行情") else { continue }
        checkPayloads(rows.compactMap(\.ticker).map { .ticker($0) }, venue: OKXVenue.id, sample)
      }
      for sample in Fuzz.samples(Templates.okxOIHistory, count: Self.perTemplate, seed: 14) {
        guard let points = try? OKXDTO.openInterestHistory(Data(sample.utf8), symbol: "okx/usd_m/BTCUSDT") else { continue }
        if points.contains(where: { !($0.time > 0 && $0.value.isFinite && $0.value >= 0) }) { Issue.record("持仓量点：\(sample)") }
      }
      for sample in Fuzz.samples(Templates.okxFundingTable, count: Self.perTemplate, seed: 15) {
        guard let table = try? OKXDTO.fundingTable(Data(sample.utf8)) else { continue }
        for (key, f) in table where !(InstrumentID(key).venue == OKXVenue.id && f.rate.isFinite) {
          Issue.record("费率表 \(key)：\(sample)")
        }
      }
    }

    @Test("Bybit 推送：tickers 快照 / 增量、kline、publicTrade、控制应答 × 畸形 → 不崩、价有限为正；合并簿不被坏帧污染")
    func bybitPushFuzz() {
      for (n, template) in Templates.bybitPush.enumerated() {
        let wire = BybitWire()
        // 先喂一份好的快照，增量才有东西可合并。
        _ = wire.decode(Templates.bybitPush[0])
        for sample in Fuzz.samples(template, count: Self.perTemplate, seed: 0xB1B1 + UInt64(n)) {
          let frame = wire.decode(sample)
          checkPayloads(frame.payloads, venue: BybitVenue.id, sample)
        }
        // 坏帧一轮下来，合并簿里 BTCUSDT 的价仍是好数：再来一帧只改成交额的增量，出来的最新价有限为正。
        let after = wire.decode(#"{"topic":"tickers.BTCUSDT","type":"delta","ts":1700000009999,"data":{"symbol":"BTCUSDT","turnover24h":"1"}}"#)
        checkPayloads(after.payloads, venue: BybitVenue.id, "模糊之后的增量")
      }
    }

    @Test("Bybit REST：K 线页、品种表、整表行情、持仓量 × 畸形")
    func bybitRESTFuzz() {
      for sample in Fuzz.samples(Templates.bybitKlinePage, count: Self.perTemplate, seed: 21) {
        if let bars = try? BybitDTO.bars(Data(sample.utf8)) { checkBars(bars, sample) }
      }
      for sample in Fuzz.samples(Templates.bybitInstruments, count: Self.perTemplate, seed: 22) {
        guard let page = try? BybitDTO.result(BybitDTO.Instruments.self, Data(sample.utf8), what: "品种表").result else { continue }
        for row in page.list where row.isListed {
          if let info = row.symbolInfo { checkInfo(info, venue: BybitVenue.id, sample) }
        }
      }
      for sample in Fuzz.samples(Templates.bybitTickers, count: Self.perTemplate, seed: 23) {
        guard let table = try? BybitDTO.result(BybitDTO.Tickers.self, Data(sample.utf8), what: "行情").result else { continue }
        checkPayloads(table.list.filter(\.isListed).compactMap { $0.ticker(timeMs: 1) }.map { .ticker($0) },
                      venue: BybitVenue.id, sample)
        for row in table.list { if let f = row.funding, !f.rate.isFinite { Issue.record("费率：\(sample)") } }
      }
      for sample in Fuzz.samples(Templates.bybitOI, count: Self.perTemplate, seed: 24) {
        guard let points = try? BybitDTO.openInterest(Data(sample.utf8)) else { continue }
        if points.contains(where: { !($0.time > 0 && $0.value.isFinite && $0.value >= 0) }) { Issue.record("持仓量点：\(sample)") }
      }
    }

    @Test("Hyperliquid 推送：candle / trades / activeAssetCtx / 回执 / error × 畸形 → 不崩、价有限为正")
    func hyperliquidPushFuzz() {
      let names = HyperliquidNames()
      names.record(["BTC", "kPEPE"])
      for (n, template) in Templates.hlPush.enumerated() {
        let wire = HyperliquidWire(names: names, clock: { Date(timeIntervalSince1970: 1_700_000_000) })
        for sample in Fuzz.samples(template, count: Self.perTemplate, seed: 0x41 + UInt64(n)) {
          let frame = wire.decode(sample)
          checkPayloads(frame.payloads, venue: HyperliquidVenue.id, sample)
        }
      }
    }

    @Test("Hyperliquid REST：K 线页、metaAndAssetCtxs × 畸形")
    func hyperliquidRESTFuzz() {
      for sample in Fuzz.samples(Templates.hlCandlePage, count: Self.perTemplate, seed: 31) {
        if let bars = try? HyperliquidDTO.bars(Data(sample.utf8)) { checkBars(bars, sample) }
      }
      for sample in Fuzz.samples(Templates.hlMetaAndCtxs, count: Self.perTemplate, seed: 32) {
        guard let rows = try? HyperliquidDTO.metaAndCtxs(Data(sample.utf8)) else { continue }
        for row in rows {
          checkInfo(row.asset.symbolInfo, venue: HyperliquidVenue.id, sample)
          if let t = HyperliquidDTO.ticker(coin: row.asset.name, ctx: row.ctx, timeMs: 1) {
            checkPayloads([.ticker(t)], venue: HyperliquidVenue.id, sample)
          }
          if let f = HyperliquidDTO.funding(row.ctx, nowMs: 1), !f.rate.isFinite { Issue.record("费率：\(sample)") }
        }
      }
    }
  }
}

// ---------------------------------------------------------------- 定点的极端

/// 只认 POST 正文的假传输（Hyperliquid 的 `info` 查询都是 POST）。
struct PostTransport: HTTPTransport {
  let answer: @Sendable (Data) -> HTTPReply
  init(_ answer: @escaping @Sendable (Data) -> HTTPReply) { self.answer = answer }
  func get(_ url: URL, timeout: TimeInterval) async throws -> HTTPReply { json("{}", status: 404) }
  func post(_ url: URL, json body: Data, timeout: TimeInterval) async throws -> HTTPReply { answer(body) }
}

extension StressVenueSerial {
  @Suite("三家报文的极端场景")
  struct VenueDTOEdgeTests {
    // ------------------------------------------------------------ 坏帧整帧丢

    @Test("一帧里有一根坏 K 线 / 一笔坏成交：整帧丢掉并计数（OKX、Bybit、Hyperliquid 同一口径）",
          arguments: ["NaN", "inf", "1e400", "-1", "0", "abc", " 1"])
    func badRowDropsWholeFrame(_ bad: String) {
      OKXVenue.contractValues.set(["BTC-USDT-SWAP": 0.01])
      let okxCandle = OKXWire(endpoint: .business).decode(#"{"arg":{"channel":"candle1m","instId":"BTC-USDT-SWAP"},"data":[["1700000060000","2","3","1.5","2.5","10","10","25","0"],["1700000000000","1","2","\#(bad)","1.5","10","10","15","1"]]}"#)
      #expect(okxCandle.payloads.isEmpty, "OKX K 线 \(bad)")
      let okxTrade = OKXWire(endpoint: .public).decode(#"{"arg":{"channel":"trades","instId":"BTC-USDT-SWAP"},"data":[{"px":"65000","sz":"1","side":"buy","ts":"1700000000000"},{"px":"\#(bad)","sz":"1","side":"buy","ts":"1700000000001"}]}"#)
      #expect(okxTrade.payloads.isEmpty, "OKX 成交 \(bad)")
      let bybitKline = BybitWire().decode(#"{"topic":"kline.1.BTCUSDT","ts":1,"data":[{"start":1700000000000,"open":"1","close":"1.5","high":"2","low":"\#(bad)","volume":"1","confirm":false},{"start":1700000060000,"open":"1","close":"1.5","high":"2","low":"0.5","volume":"1","confirm":false}]}"#)
      #expect(bybitKline.payloads.isEmpty, "Bybit K 线 \(bad)")
      let bybitTrade = BybitWire().decode(#"{"topic":"publicTrade.BTCUSDT","data":[{"T":1700000000000,"s":"BTCUSDT","S":"Buy","v":"1","p":"65000"},{"T":1700000000001,"s":"BTCUSDT","S":"Buy","v":"1","p":"\#(bad)"}]}"#)
      #expect(bybitTrade.payloads.isEmpty, "Bybit 成交 \(bad)")
      let names = HyperliquidNames()
      let hl = HyperliquidWire(names: names, clock: { Date(timeIntervalSince1970: 1_700_000_000) })
      let hlCandle = hl.decode(#"{"channel":"candle","data":[{"t":1700000000000,"s":"BTC","i":"1m","o":"1","c":"1.5","h":"2","l":"0.5","v":"1"},{"t":1700000060000,"s":"BTC","i":"1m","o":"1","c":"1.5","h":"2","l":"\#(bad)","v":"1"}]}"#)
      #expect(hlCandle.payloads.isEmpty, "Hyperliquid K 线 \(bad)")
      let hlTrade = hl.decode(#"{"channel":"trades","data":[{"coin":"BTC","side":"B","px":"65000","sz":"1","time":1700000000000},{"coin":"BTC","side":"B","px":"\#(bad)","sz":"1","time":1700000000001}]}"#)
      #expect(hlTrade.payloads.isEmpty, "Hyperliquid 成交 \(bad)")
    }

    @Test("开盘时间畸形（负数、0、Int64 边界、秒当毫秒乘上去溢出）的 K 线不收、不崩")
    func badOpenTimes() throws {
      for t in ["-9223372036854775808", "-1", "0", "9223372036854775807", "99999999999999999"] {
        let okx = try OKXDTO.bars(Data(#"{"code":"0","data":[["\#(t)","1","2","0.5","1.5","10","10","15","1"]]}"#.utf8))
        #expect(okx.isEmpty, "OKX \(t)")
        let bybit = try BybitDTO.bars(Data(#"{"retCode":0,"result":{"list":[["\#(t)","1","2","0.5","1.5","10","15"]]}}"#.utf8))
        #expect(bybit.isEmpty, "Bybit \(t)")
        let hl = try HyperliquidDTO.bars(Data(#"[{"t":\#(t),"o":"1","c":"1.5","h":"2","l":"0.5","v":"1"}]"#.utf8))
        #expect(hl.isEmpty, "Hyperliquid \(t)")
        // Coinbase 的 `start` 是秒，乘 1000 那一下原来会溢出闪退。
        let cb = try CoinbaseDTO.bars(Data(#"{"candles":[{"start":"\#(t)","low":"0.5","high":"2","open":"1","close":"1.5","volume":"1"}]}"#.utf8))
        #expect(cb.isEmpty, "Coinbase \(t)")
      }
      // kanpan-api 的持仓量历史：时间是数，超过 Int64 的原来在 `Int64(t)` 上闪退。
      let oi = try OKXDTO.openInterestHistory(Data(#"{"data":{"source":"okx","symbol":"BTCUSDT","rows":[[1e19,1,null],[1790161800000,1,null]]}}"#.utf8),
                                              symbol: "okx/usd_m/BTCUSDT")
      #expect(oi == [OIPoint(time: 1_790_161_800_000, value: 1)])
    }

    @Test("步长写成科学计数法、指数巨大：小数位封顶，不溢出")
    func hugeExponents() {
      for text in ["1e-9223372036854775808", "1e9223372036854775807", "1e-99999999999999999999", "0.1e-400"] {
        #expect((0...12).contains(OKXDTO.decimals(text)), "OKX \(text)")
        #expect((0...12).contains(BybitDTO.decimals(text)), "Bybit \(text)")
        #expect((0...12).contains(CoinbaseDTO.decimals(text)), "Coinbase \(text)")
      }
    }

    @Test("零价 / 负价 / 带空格的数：K 线不收、行情不出、24h 高低不带负数，成交额乘爆了记「不知道」")
    func zeroNegativeAndPadded() throws {
      #expect(try OKXDTO.bars(Data(#"{"code":"0","data":[["1700000000000","0","0","0","0","0","0","0","1"]]}"#.utf8)).isEmpty)
      #expect(try BybitDTO.bars(Data(#"{"retCode":0,"result":{"list":[["1700000000000","0","0","0","0","0","0"]]}}"#.utf8)).isEmpty)
      #expect(try HyperliquidDTO.bars(Data(#"[{"t":1700000000000,"o":"0","c":"0","h":"0","l":"0","v":"0"}]"#.utf8)).isEmpty)
      #expect(OKXDTO.ticker(instID: "BTC-USDT-SWAP", last: " 1", open: nil, high: nil, low: nil, baseVolume: nil, ts: nil) == nil)
      let t = try #require(OKXDTO.ticker(instID: "BTC-USDT-SWAP", last: "2", open: "1", high: "-5", low: "0",
                                          baseVolume: "1e308", ts: "1"))
      #expect(t.high.isNaN && t.low.isNaN)
      #expect(t.quoteVolume.isNaN)
      let b = try #require(BybitDTO.ticker(symbol: "BTCUSDT", last: 2, prev: 1, pcnt: nil, high: -1, low: 0,
                                            turnover: -3, mark: -1, timeMs: 1))
      #expect(b.high.isNaN && b.low.isNaN && b.quoteVolume.isNaN && b.markPrice == nil)
      let ctx = try #require(HyperliquidDTO.Ctx(["markPx": "-5", "midPx": "2", "prevDayPx": "1", "dayNtlVlm": "-1", "oraclePx": "-2"]))
      let h = try #require(HyperliquidDTO.ticker(coin: "BTC", ctx: ctx, timeMs: 1))
      #expect(h.markPrice == nil && h.quoteVolume.isNaN && h.last == 2)
      #expect(HyperliquidDTO.markTick(ctx, nowMs: 1).indexPrice == nil)
    }

    // ------------------------------------------------------------ Bybit tickers 合并

    private func tick(_ wire: BybitWire, _ text: String) -> (ticker: Ticker?, mark: Double?) {
      var t: Ticker?, m: Double?
      for p in wire.decode(text).payloads {
        if case .ticker(let x) = p { t = x }
        if case .markPrice(_, let price, _) = p { m = price }
      }
      return (t, m)
    }

    @Test("Bybit tickers：快照没到先来增量 → 只用增量里有的；增量把字段改成空串 → 留旧值；坏数的增量整帧丢、不污染合并簿")
    func bybitTickerMerge() throws {
      let wire = BybitWire()
      // 没有快照先来增量：最新价照出，别的不知道的留 NaN（上层按「没有」处理），不拿别家 / 别的品种的值凑。
      let first = tick(wire, #"{"topic":"tickers.BTCUSDT","type":"delta","ts":1,"data":{"symbol":"BTCUSDT","lastPrice":"100"}}"#)
      let t0 = try #require(first.ticker)
      #expect(t0.last == 100 && t0.quoteVolume.isNaN && t0.changePercent.isNaN && t0.high.isNaN)
      // 快照整份替换。
      let snap = tick(wire, Templates.bybitPush[0])
      #expect(snap.ticker?.last == 65000 && snap.ticker?.quoteVolume == 123_456_789 && snap.mark == 65001)
      // 增量里的空串是「没有」：不覆盖旧值。
      let blank = tick(wire, #"{"topic":"tickers.BTCUSDT","type":"delta","ts":2,"data":{"symbol":"BTCUSDT","lastPrice":"65100","highPrice24h":"","markPrice":""}}"#)
      #expect(blank.ticker?.last == 65100 && blank.ticker?.high == 66000)
      #expect(blank.mark == 65001)
      // 坏数的增量：整帧丢，合并簿里还是上一份好的。
      for bad in ["NaN", "inf", "-1", "0", "1e400", "abc"] {
        let dropped = wire.decode(#"{"topic":"tickers.BTCUSDT","type":"delta","ts":3,"data":{"symbol":"BTCUSDT","lastPrice":"\#(bad)","turnover24h":"5"}}"#)
        #expect(dropped.payloads.isEmpty, "lastPrice=\(bad) 的增量没丢")
        let markBad = wire.decode(#"{"topic":"tickers.BTCUSDT","type":"delta","ts":3,"data":{"symbol":"BTCUSDT","markPrice":"\#(bad)"}}"#)
        #expect(markBad.payloads.isEmpty, "markPrice=\(bad) 的增量没丢")
      }
      let next = tick(wire, #"{"topic":"tickers.BTCUSDT","type":"delta","ts":4,"data":{"symbol":"BTCUSDT","turnover24h":"7"}}"#)
      #expect(next.ticker?.last == 65100 && next.ticker?.quoteVolume == 7)
    }

    @Test("Bybit tickers：两只交叉到达，各合各的；topic 与 data.symbol 对不上的整帧丢")
    func bybitTwoSymbolsInterleaved() throws {
      let wire = BybitWire()
      _ = wire.decode(Templates.bybitPush[0])
      _ = wire.decode(#"{"topic":"tickers.ETHUSDT","type":"snapshot","ts":1,"data":{"symbol":"ETHUSDT","lastPrice":"3000","turnover24h":"10","highPrice24h":"3100","lowPrice24h":"2900","markPrice":"3001"}}"#)
      for i in 0..<200 {
        let btc = tick(wire, #"{"topic":"tickers.BTCUSDT","type":"delta","ts":\#(i),"data":{"symbol":"BTCUSDT","lastPrice":"\#(65000 + i)"}}"#)
        let eth = tick(wire, #"{"topic":"tickers.ETHUSDT","type":"delta","ts":\#(i),"data":{"symbol":"ETHUSDT","turnover24h":"\#(10 + i)"}}"#)
        #expect(btc.ticker?.symbol == "bybit/usd_m/BTCUSDT" && btc.ticker?.last == Double(65000 + i) && btc.ticker?.quoteVolume == 123_456_789)
        #expect(eth.ticker?.symbol == "bybit/usd_m/ETHUSDT" && eth.ticker?.last == 3000 && eth.ticker?.quoteVolume == Double(10 + i))
      }
      // topic 说 BTC、data 说 ETH：不知道该信哪个，整帧丢（原来按 data 把 ETH 的价改了）。
      let mismatched = wire.decode(#"{"topic":"tickers.BTCUSDT","type":"delta","ts":999,"data":{"symbol":"ETHUSDT","lastPrice":"1"}}"#)
      #expect(mismatched.payloads.isEmpty)
      #expect(tick(wire, #"{"topic":"tickers.ETHUSDT","type":"delta","ts":1000,"data":{"symbol":"ETHUSDT","turnover24h":"1"}}"#).ticker?.last == 3000)
    }

    // ------------------------------------------------------------ OKX candle

    @Test("OKX candle：一帧多根新的在前 → 出来按开盘升序；confirm 1 收了、0 / 缺省没收")
    func okxCandleOrderAndConfirm() throws {
      let wire = OKXWire(endpoint: .business)
      let frame = wire.decode(#"{"arg":{"channel":"candle1H","instId":"BTC-USDT-SWAP"},"data":[["1700006400000","2","3","1.5","2.5","10","10","25","0"],["1700002800000","1","2","0.5","1.5","10","10","15","1"],["1699999200000","1","2","0.5","1.5","10","10","15"]]}"#)
      let klines = frame.payloads.compactMap { p -> KlineEvent? in if case .kline(let k) = p { return k } else { return nil } }
      #expect(klines.map(\.openTime) == [1_699_999_200_000, 1_700_002_800_000, 1_700_006_400_000])
      #expect(klines.map(\.closed) == [false, true, false])
      #expect(klines.allSatisfy { $0.interval == "1h" && $0.symbol == "okx/usd_m/BTCUSDT" })
      #expect(frame.confirmed.count == 1)
      // 同一根重复给两次：两条都照出（上层按开盘时刻覆盖），不崩。
      let dup = wire.decode(#"{"arg":{"channel":"candle1m","instId":"BTC-USDT-SWAP"},"data":[["1700000000000","1","2","0.5","1.5","10","10","15","0"],["1700000000000","1","2","0.5","1.6","10","10","15","1"]]}"#)
      #expect(dup.payloads.count == 2)
      // 认不出的周期频道（OKX 有、看盘没有的 3Dutc）：不出报文。
      #expect(wire.decode(#"{"arg":{"channel":"candle3Dutc","instId":"BTC-USDT-SWAP"},"data":[["1700000000000","1","2","0.5","1.5","10","10","15","0"]]}"#).payloads.isEmpty)
    }

    // ------------------------------------------------------------ Hyperliquid 大写键译回原名

    @Test("Hyperliquid 原名表：没拉到 → 用大写原样；表里没有 → 大写原样；KAITO 与 kAITO 撞名 → 大写那只就是 KAITO，千枚那只不抢它的键")
    func hyperliquidNames() {
      let empty = HyperliquidNames()
      #expect(HyperliquidVenue.coin("hyperliquid/usd_m/KPEPE", names: empty) == "KPEPE")
      #expect(HyperliquidVenue.needsNames("hyperliquid/usd_m/KPEPE", names: empty))
      #expect(!HyperliquidVenue.needsNames("hyperliquid/usd_m/BTC", names: empty))
      let names = HyperliquidNames()
      names.record(["BTC", "kPEPE"])
      #expect(HyperliquidVenue.coin("hyperliquid/usd_m/KPEPE", names: names) == "kPEPE")
      #expect(HyperliquidVenue.coin("hyperliquid/usd_m/NOPE", names: names) == "NOPE")
      #expect(!HyperliquidVenue.needsNames("hyperliquid/usd_m/KNOPE", names: names))
      // 撞名：两种到达顺序结果一样，大写那只赢。
      for order in [["KAITO", "kAITO"], ["kAITO", "KAITO"]] {
        let t = HyperliquidNames()
        t.record(order)
        #expect(HyperliquidVenue.coin("hyperliquid/usd_m/KAITO", names: t) == "KAITO", "\(order)")
        let wire = HyperliquidWire(names: t, clock: { Date(timeIntervalSince1970: 1_700_000_000) })
        #expect(wire.subs([.ticker(symbol: "hyperliquid/usd_m/KAITO")]).map(\.coin) == ["KAITO"])
      }
    }

    @Test("Hyperliquid 品种表 / 整表行情撞名：KAITO 与 kAITO 只留大写那只（千枚那只的价差一千倍，不许顶掉它）")
    func hyperliquidCollisionInProvider() async throws {
      let body = #"[{"universe":[{"name":"kAITO","szDecimals":0},{"name":"KAITO","szDecimals":1}]},[{"markPx":"0.001","midPx":"0.001","prevDayPx":"0.001","funding":"0.00002"},{"markPx":"1.5","midPx":"1.5","prevDayPx":"1.4","funding":"0.00001"}]]"#
      let meta = #"{"universe":[{"name":"kAITO","szDecimals":0},{"name":"KAITO","szDecimals":1}]}"#
      let transport = PostTransport { req in
        json(String(decoding: req, as: UTF8.self).contains("metaAndAssetCtxs") ? body : meta)
      }
      let p = HyperliquidProvider(policy: .direct, gateways: ["gw.example"], transport: transport,
                                  limiter: VenueRateLimiter(weightPerMinute: 1_000_000, pacer: FastPacer()),
                                  clock: { Date(timeIntervalSince1970: 1_700_000_000) })
      let infos = try await p.instruments()
      #expect(infos.map(\.symbol) == ["hyperliquid/usd_m/KAITO"])
      #expect(infos.first?.base == "KAITO")
      let tickers = try await p.tickers24h(timeout: 5)
      #expect(tickers.count == 1 && tickers.first?.last == 1.5)
      #expect(try await p.ticker24h(symbol: "hyperliquid/usd_m/KAITO", timeout: 5).last == 1.5)
      #expect(try await p.funding(symbol: "hyperliquid/usd_m/KAITO").rate == 0.00001)
      #expect(try await p.fundingAll().count == 1)
    }
  }
}
