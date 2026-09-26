import Foundation
import KanpanCore
import Testing
@testable import Kanpan

/// 偏好编解码压测：坏档、极端值、老版本号、逐帧改。
///
/// 量的是三件读代码不容易一眼看全的事：
/// 1. **一轮就定**：随便什么样的存档（云端推下来的、手改的、半截的、更高版本写的）解一次、
///    编一次之后，再解再编一个字节都不变。不定的话，同步那一侧每一轮都会觉得「又变了」、
///    再记一条账推上去，永远推不完。
/// 2. **有界**：输入再大（几千档周期、几万个参数、上兆的字符串），落盘那一份都是几 KB。
/// 3. **推得上去**：编出来的每个字段都过得了服务端 `sync_validation.rs` 的那几条字节上限——
///    本地收了、服务端不收的值，会让整条 settings 操作被顶回去。
@Suite("偏好编解码压测：坏档、极端值、逐帧改")
@MainActor
struct PrefsStressTests {
  private struct Seeded: RandomNumberGenerator {
    var state: UInt64
    mutating func next() -> UInt64 {
      state &+= 0x9E37_79B9_7F4A_7C15
      var z = state
      z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
      z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
      return z ^ (z >> 31)
    }
  }

  /// 出厂那份编出来的全部键，加上只读不写的旧键和几个认不出的键。
  private static let keys: [String] = {
    let object = (try? JSONSerialization.jsonObject(with: PrefsCodec.encoded(.defaults)!)) as? [String: Any] ?? [:]
    return object.keys.sorted() + ["orderFlowFilledBid", "orderFlowFilledAsk", "orderFlowCancelledBid",
                                   "orderFlowCancelledAsk", "styleID", "recordButtonX", "apiHost", "未来的键"]
  }()

  /// 认得出的字面量池：周期、指标、各个枚举的取值，混上认不出的。
  private static let words: [String] = {
    var out = Interval.allCases.map(\.rawValue) + IndicatorID.allCases.map(\.rawValue)
    let object = (try? JSONSerialization.jsonObject(with: PrefsCodec.encoded(.defaults)!)) as? [String: Any] ?? [:]
    out += object.values.compactMap { $0 as? String }
    out += ["", "style", "paper", "night", "auto", "gateway", "direct", "binance/usd_m/BTCUSDT",
            "binance/usd_m/btcusdt", "BTC", "hline", "trend", "custom", "alert", "#FFAA00", "#zzzzzz",
            String(repeating: "长", count: 100), String(repeating: "长", count: 128), String(repeating: "a", count: 129),
            String(repeating: "🀄️", count: 60), UUID().uuidString]
    return out
  }()

  private static let numbers: [Double] = [0, -0.0, 1, -1, 0.5, 1.6, 2, 4, 40, 40.1, 100, 399, 400, 401, 1e9,
                                          1e308, -1e308, 5e-324, 0.1, 0.09, 50, 50.5, 3.141_592_653_589_793]

  private func scalar(_ rng: inout Seeded) -> Any {
    switch Int.random(in: 0..<6, using: &rng) {
    case 0: return Self.words.randomElement(using: &rng)!
    case 1: return Self.numbers.randomElement(using: &rng)!
    case 2: return Int.random(in: -1_000...1_000, using: &rng)
    case 3: return Bool.random(using: &rng)
    case 4: return NSNull()
    default: return String(repeating: "长", count: Int.random(in: 0...2_000, using: &rng))
    }
  }

  private func value(_ rng: inout Seeded, depth: Int = 0) -> Any {
    switch Int.random(in: 0..<(depth > 1 ? 1 : 4), using: &rng) {
    case 0: return scalar(&rng)
    case 1:
      // 长数组：几千档周期、几千个参数。
      let n = [0, 1, 3, 25, 400, 3_000].randomElement(using: &rng)!
      return (0..<n).map { _ in Bool.random(using: &rng) ? scalar(&rng) : Self.words.randomElement(using: &rng)! }
    case 2:
      var dict: [String: Any] = [:]
      for _ in 0..<Int.random(in: 0...12, using: &rng) {
        let key = Bool.random(using: &rng) ? Self.words.randomElement(using: &rng)! : String(Int.random(in: -3...30, using: &rng))
        dict[key] = value(&rng, depth: depth + 1)
      }
      return dict
    default:
      // 参数形状：指标 → 一长串整数（含越界）。
      var dict: [String: Any] = [:]
      for id in IndicatorID.allCases.shuffled(using: &rng).prefix(Int.random(in: 0...8, using: &rng)) {
        dict[id.rawValue] = (0..<[1, 5, 30, 5_000].randomElement(using: &rng)!).map { _ in Int.random(in: -10...10_000, using: &rng) }
      }
      return dict
    }
  }

  private func archive(_ rng: inout Seeded) -> Data {
    var object: [String: Any] = [:]
    for key in Self.keys where Int.random(in: 0..<3, using: &rng) > 0 { object[key] = value(&rng) }
    object["v"] = [-1, 0, 1, 2, 2, 3, 3, 4, 999, "3", NSNull()].randomElement(using: &rng)!
    return try! JSONSerialization.data(withJSONObject: object)
  }

  /// 服务端字节上限（`sync_validation.rs`：`string(v, 128)` / `string(v, 64)` 数的是 UTF-8 字节）。
  private func withinServerLimits(_ data: Data) -> Bool {
    guard let object = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else { return false }
    for key in ["favoritesGroup", "drawToolGroup"] {
      if let s = object[key] as? String, s.utf8.count > 128 { return false }
    }
    for key in ["theme", "priceMode", "timeZone", "candleKind", "gridChoice", "bodyChoice", "viewAnchor",
                "priceBias", "dataDisplay", "crossPrice", "changeBasis"] {
      if let s = object[key] as? String, s.utf8.count > 64 { return false }
    }
    if let quick = object["quickIntervals"] as? [Any], quick.count > 10 { return false }
    if let params = object["params"] as? [String: [Int]], params.values.contains(where: { $0.count > 20 || $0.contains { !(1...400).contains($0) } }) { return false }
    return true
  }

  /// 两份设置里值不一样的字段（字典按键排好再比，免得把打印顺序当成差异）。
  private func diff(_ a: Prefs, _ b: Prefs) -> String {
    func object(_ p: Prefs) -> [String: Any] {
      (try? JSONSerialization.jsonObject(with: PrefsCodec.encode(p))) as? [String: Any] ?? [:]
    }
    let x = object(a), y = object(b)
    return x.keys.sorted().filter { (x[$0] as? NSObject) != (y[$0] as? NSObject) }
      .map { "\($0): \(x[$0] ?? "-") → \(y[$0] ?? "-")" }.joined(separator: "; ")
  }

  @Test("3000 份随机坏档：解一次编一次之后就不再变、落盘有界、字段都过得了服务端的字节上限")
  func randomArchivesSettleInOneRound() throws {
    var rng = Seeded(state: 0x5EED_2026_0926)
    var largestInput = 0, largestOutput = 0
    for trial in 0..<3_000 {
      let data = archive(&rng)
      largestInput = max(largestInput, data.count)
      let first = PrefsCodec.decode(data)
      let encoded = try #require(PrefsCodec.encoded(first), "第 \(trial) 份编不出来")
      let second = PrefsCodec.decode(encoded)
      #expect(second == first, "第 \(trial) 份解编一轮之后还在变：\(diff(first, second))；原档 \(String(data: data, encoding: .utf8)!.prefix(600))")
      #expect(PrefsCodec.encoded(second) == encoded, "第 \(trial) 份第二轮编出来的字节不一样")
      #expect(encoded.count < 64 * 1024, "第 \(trial) 份落盘 \(encoded.count) 字节")
      #expect(withinServerLimits(encoded), "第 \(trial) 份有字段过不了服务端上限")
      largestOutput = max(largestOutput, encoded.count)
    }
    print("PREFS-FUZZ largestInput=\(largestInput) largestOutput=\(largestOutput)")
  }

  @Test("数字写成 1e999、字段类型全错、截断到一半：退回出厂或只丢那一项，不整份作废")
  func malformedTextArchives() throws {
    let good = String(data: PrefsCodec.encoded(.defaults)!, encoding: .utf8)!
    let broken = [
      good.replacingOccurrences(of: "\"barSpacing\":4", with: "\"barSpacing\":1e999"),
      good.replacingOccurrences(of: "\"rsiUpper\":", with: "\"rsiUpper\":-1e999,\"x\":"),
      String(good.prefix(good.count / 2)),
      "{\"v\":2,\"quickIntervals\":[\"5m\",\"30m\",\"1h\",\"4h\",\"1d\"],\"skin\":\"terra\"}",
      "{\"v\":3,\"quickIntervals\":[\"5m\",\"30m\",\"1h\",\"4h\",\"1d\"],\"skin\":\"terra\"}",
      "[]", "null", "\"prefs\"", "{\"v\":{}}",
    ]
    for text in broken {
      let prefs = PrefsCodec.decode(Data(text.utf8))
      let encoded = try #require(PrefsCodec.encoded(prefs))
      #expect(PrefsCodec.decode(encoded) == prefs)
      #expect(prefs.barSpacing.isFinite && prefs.rsiUpper.isFinite && prefs.rsiLower < prefs.rsiUpper)
    }
    // 只有上轨、没有下轨（或者下轨类型不对）：下轨也要夹到上轨以下，一次就定。
    for text in ["{\"v\":3,\"rsiUpper\":1}", "{\"v\":3,\"rsiUpper\":20,\"rsiLower\":\"x\"}"] {
      let prefs = PrefsCodec.decode(Data(text.utf8))
      #expect(prefs.rsiLower < prefs.rsiUpper)
      #expect(PrefsCodec.decode(PrefsCodec.encoded(prefs)!) == prefs)
    }
    // 停在哪一类：服务端按 UTF-8 字节数 128 封顶，本地也按字节收。
    let wide = String(repeating: "长", count: 128)
    #expect(PrefsCodec.decode(Data("{\"favoritesGroup\":\"\(wide)\"}".utf8)).favoritesGroup == "")
    let ascii = String(repeating: "a", count: 128)
    #expect(PrefsCodec.decode(Data("{\"favoritesGroup\":\"\(ascii)\"}".utf8)).favoritesGroup == ascii)
    // 老档（2）里躺着上一版出厂的常用行 → 换新默认；3 起写下的同一串是用户自己钉的，一字不动。
    #expect(PrefsCodec.decode(Data(broken[3].utf8)).quickIntervals == Interval.quick)
    #expect(PrefsCodec.decode(Data(broken[4].utf8)).quickIntervals == [.m5, .m30, .h1, .h4, .d1])
    #expect(PrefsCodec.decode(Data(broken[3].utf8)).skin == .terra)
  }

  @Test("10 秒逐帧改（600 次）：每一次都当场落盘，最后一次一定在盘上，没真改的那几帧不写不记账")
  func sixHundredFramesOfEditsLandTheLastOne() {
    let box = InMemoryPrefsStorage()
    let store = PrefsStore(storage: box, cache: UnavailableMarketCache())
    var changes = 0
    store.onChange = { _ in changes += 1 }
    for frame in 0..<600 {
      // 每四帧里有一帧是同一个值（图每改一次状态都会报一遍），不该写。
      let height = 0.3 + Double(frame / 4 * 4 % 600) / 1_000
      store.update { $0.portraitHeight = height }
      #expect(PrefsStore.load(from: box).portraitHeight == store.prefs.portraitHeight)
    }
    #expect(changes == 150)
    #expect(PrefsStore.load(from: box).portraitHeight == store.prefs.portraitHeight)
    #expect(store.dirtyFields.contains("portraitHeight"))
  }

  /// 只脏了上轨时回拉：上下轨成对留本地的，不拼出一对倒挂的轨。
  @Test func rsiRailsAreKeptAsAPair() {
    var local = Prefs.defaults; local.rsiUpper = 20; local.rsiLower = 10
    var cloud = Prefs.defaults; cloud.rsiUpper = 80; cloud.rsiLower = 30
    for dirty: Set<String> in [["rsiUpper"], ["rsiLower"], ["rsiUpper", "rsiLower"]] {
      let merged = Prefs.keeping(dirty, of: local, over: cloud)
      #expect(merged.rsiUpper == 20 && merged.rsiLower == 10)
    }
    let untouched = Prefs.keeping(["redUp"], of: local, over: cloud)
    #expect(untouched.rsiUpper == 80 && untouched.rsiLower == 30)
  }
}
