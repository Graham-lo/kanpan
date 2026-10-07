import Foundation

// 主力订单流 · 本机日志（一只品种一个文件，只存大单，簿不存；KanpanData 的 OrderFlowFeed 管读写）。
//
// 第 2 版是逐行 JSON（JSON Lines）：
//
//     {"version":2,"symbol":"BTCUSDT","step":100,"savedAtMs":…,"historyFromMs":…,"historyCursorMs":…,…}
//     {"v":"binance:usdtPerp:BTCUSDT","x":"币安","p":"usdtPerp","s":"bid","b":1123,"px":112300,…}
//     {"v":…}
//
// 第一行是头（步长、存盘时刻、服务端历史取到哪儿），之后一行一条大单（短键同 `BigOrder.CodingKeys`）。
// 原来（第 1 版）整份是一个 JSON 对象：中间坏一个字节、或某一条的状态读不懂，JSONDecoder 整体失败，
// 整份作废——下次打开从服务端重拉 24 小时。现在只有头坏了才整份作废，坏的那几行跳过、其余照读；
// 第 1 版照样读（某一条读不懂也只丢那一条）。
//
// 编码手写（不走 JSONEncoder）：2 万条时 JSONEncoder 要六七十毫秒，手写的是它的几分之一；
// 解码仍用 JSONDecoder（把各行拼成一个数组一次解完，某行语法坏了才退回逐行解）。

/// 服务端历史取到哪儿了（`OrderFlowFeed` 的三个游标）。随日志落盘：读回来时日志还在 24 小时内、步长对得上，
/// 下一次取服务端就只取游标之后的增量，不再整页重取 24 小时。
public struct OrderFlowHistoryCursor: Sendable, Equatable {
  /// 已经并进来的最早时刻（往左补从这里接着往前）。
  public var fromMs: Int64
  /// 增量从哪儿接着取（上一页最晚的出现 / 结束时刻）。
  public var cursorMs: Int64
  /// 服务端从什么时候开始跟这只（往左补到这里为止）。
  public var trackedSinceMs: Int64?
  /// 取这些页时各产品用过的最高门槛。读回时此刻某个产品的门槛比它低，低出来的那一截服务端没给过，
  /// 游标不能接着用（整页重取）；nil 表示不知道，同样不接着用。
  public var thresholds: OrderFlowThresholds?

  public init(fromMs: Int64, cursorMs: Int64, trackedSinceMs: Int64?, thresholds: OrderFlowThresholds?) {
    self.fromMs = fromMs; self.cursorMs = cursorMs; self.trackedSinceMs = trackedSinceMs; self.thresholds = thresholds
  }

  /// 此刻的门槛下还能不能接着用：每个要订的产品，此刻的门槛都不低于取历史时用过的。
  public func stillCovers(_ now: OrderFlowThresholds) -> Bool {
    guard let used = thresholds else { return false }
    for product in now.products {
      guard let current = now[product], let before = used[product], current >= before else { return false }
    }
    return true
  }
}

/// 落盘的那一份。
public struct OrderFlowJournal: Sendable, Equatable {
  public static let currentVersion = 2
  public var version: Int
  public var symbol: String
  /// 存盘时的步长：步长变了桶号就对不上，整份作废。
  public var step: Double
  public var savedAtMs: Int64
  public var orders: [BigOrder]
  /// 服务端历史的游标（第 2 版起有；第 1 版读回来是 nil，下一次取服务端照旧整页取）。
  public var history: OrderFlowHistoryCursor?
  /// 上一次按簿深标定出的非币默认门槛（美元）。下次打开先按它出帧（不再空等 8 秒标定），
  /// 标定完有出入再改。币与固定表里的品种不标定，是 nil；旧日志读回来也是 nil。
  public var calibrated: Double?

  public init(symbol: String, step: Double, savedAtMs: Int64, orders: [BigOrder],
              history: OrderFlowHistoryCursor? = nil, calibrated: Double? = nil) {
    self.version = Self.currentVersion; self.symbol = symbol; self.step = step
    self.savedAtMs = savedAtMs; self.orders = orders; self.history = history; self.calibrated = calibrated
  }

  // MARK: - 写

  /// 第 2 版逐行 JSON。名义、价格不是有限数的那几条不写（JSON 表示不了，写进去整行读不回）。
  public func encoded() -> Data {
    var out = [UInt8]()
    out.reserveCapacity(256 + orders.count * 200)
    Self.writeHeader(self, into: &out)
    for order in orders { Self.write(order, into: &out) }
    return Data(out)
  }

  private static func writeHeader(_ j: OrderFlowJournal, into out: inout [UInt8]) {
    out.append(contentsOf: #"{"version":"#.utf8); out.append(contentsOf: String(currentVersion).utf8)
    out.append(contentsOf: #","symbol":"#.utf8); writeString(j.symbol, into: &out)
    out.append(contentsOf: #","step":"#.utf8); writeNumber(j.step.isFinite ? j.step : 0, into: &out)
    out.append(contentsOf: #","savedAtMs":"#.utf8); out.append(contentsOf: String(j.savedAtMs).utf8)
    out.append(contentsOf: #","count":"#.utf8); out.append(contentsOf: String(j.orders.count).utf8)
    if let c = j.calibrated, c.isFinite, c > 0 {
      out.append(contentsOf: #","calibrated":"#.utf8); writeNumber(c, into: &out)
    }
    if let h = j.history {
      out.append(contentsOf: #","historyFromMs":"#.utf8); out.append(contentsOf: String(h.fromMs).utf8)
      out.append(contentsOf: #","historyCursorMs":"#.utf8); out.append(contentsOf: String(h.cursorMs).utf8)
      if let tracked = h.trackedSinceMs {
        out.append(contentsOf: #","historyTrackedSinceMs":"#.utf8); out.append(contentsOf: String(tracked).utf8)
      }
      if let t = h.thresholds, let data = try? JSONEncoder().encode(t) {
        out.append(contentsOf: #","historyThresholds":"#.utf8); out.append(contentsOf: data)
      }
    }
    out.append(contentsOf: "}\n".utf8)
  }

  private static func write(_ o: BigOrder, into out: inout [UInt8]) {
    guard o.price.isFinite, o.initialNotional.isFinite, o.notional.isFinite, o.filledNotional.isFinite,
          o.threshold.isFinite, o.vanishedNotional?.isFinite ?? true else { return }
    out.append(contentsOf: #"{"v":"#.utf8); writeString(o.venueID, into: &out)
    out.append(contentsOf: #","x":"#.utf8); writeString(o.exchange, into: &out)
    out.append(contentsOf: #","p":""#.utf8); out.append(contentsOf: o.product.rawValue.utf8)
    out.append(contentsOf: #"","s":""#.utf8); out.append(contentsOf: o.side.rawValue.utf8)
    out.append(contentsOf: #"","b":"#.utf8); out.append(contentsOf: String(o.bucket).utf8)
    out.append(contentsOf: #","px":"#.utf8); writeNumber(o.price, into: &out)
    out.append(contentsOf: #","f":"#.utf8); out.append(contentsOf: String(o.firstSeenMs).utf8)
    if let end = o.endMs { out.append(contentsOf: #","e":"#.utf8); out.append(contentsOf: String(end).utf8) }
    out.append(contentsOf: #","st":""#.utf8); out.append(contentsOf: o.status.rawValue.utf8)
    out.append(contentsOf: #"","n0":"#.utf8); writeNumber(o.initialNotional, into: &out)
    out.append(contentsOf: #","n":"#.utf8); writeNumber(o.notional, into: &out)
    out.append(contentsOf: #","fl":"#.utf8); writeNumber(o.filledNotional, into: &out)
    out.append(contentsOf: #","t":"#.utf8); writeNumber(o.threshold, into: &out)
    if let vn = o.vanishedNotional { out.append(contentsOf: #","vn":"#.utf8); writeNumber(vn, into: &out) }
    out.append(contentsOf: "}\n".utf8)
  }

  /// 有限的 Double：`description` 是最短的能原样读回的写法（`1e-05`、`100.0` 都是合法 JSON 数）。
  private static func writeNumber(_ x: Double, into out: inout [UInt8]) {
    out.append(contentsOf: x.description.utf8)
  }

  /// JSON 字符串：引号、反斜杠、控制字符转义（交易所名是中文，原样写 UTF-8）。
  private static func writeString(_ s: String, into out: inout [UInt8]) {
    out.append(0x22)
    for byte in s.utf8 {
      switch byte {
      case 0x22: out.append(contentsOf: [0x5C, 0x22])
      case 0x5C: out.append(contentsOf: [0x5C, 0x5C])
      case 0x0A: out.append(contentsOf: [0x5C, 0x6E])
      case 0x0D: out.append(contentsOf: [0x5C, 0x72])
      case 0x09: out.append(contentsOf: [0x5C, 0x74])
      case 0..<0x20:
        let hex = Array("0123456789abcdef".utf8)
        out.append(contentsOf: [0x5C, 0x75, 0x30, 0x30, hex[Int(byte >> 4)], hex[Int(byte & 0x0F)]])
      default: out.append(byte)
      }
    }
    out.append(0x22)
  }

  // MARK: - 读

  /// 读一份日志。头（第一行）坏了、版本不认识、步长不是正数才是 nil；某几条大单坏了跳过、其余照读。
  public static func decode(_ data: Data) -> OrderFlowJournal? { read(data)?.journal }

  /// 同 `decode`，另外报一声跳过了几条坏的（诊断、压测用）。
  public static func read(_ data: Data) -> (journal: OrderFlowJournal, skipped: Int)? {
    let bytes = [UInt8](data)
    var lines: [Range<Int>] = []
    var start = 0
    for i in bytes.indices where bytes[i] == 0x0A {
      if i > start { lines.append(start..<i) }
      start = i + 1
    }
    if start < bytes.count { lines.append(start..<bytes.count) }
    guard let first = lines.first else { return nil }
    let decoder = JSONDecoder()
    guard let header = try? decoder.decode(Header.self, from: Data(bytes[first])),
          header.step.isFinite, header.step > 0 else { return nil }
    var journal = OrderFlowJournal(symbol: header.symbol, step: header.step, savedAtMs: header.savedAtMs, orders: [])
    if let c = header.calibrated, c.isFinite, c > 0 { journal.calibrated = c }
    switch header.version {
    case 1:
      // 第 1 版整份一个对象，头那一行就是全部；`orders` 按条宽松解（某一条读不懂只丢那一条）。
      let lossy = header.orders ?? []
      journal.orders = lossy.compactMap(\.order)
      return (journal, lossy.count - journal.orders.count + (lines.count - 1))
    case currentVersion:
      journal.history = header.cursor
      let body = lines.dropFirst()
      var skipped = 0
      // 快的一路：各行拼成一个数组一次解完（某一条字段读不懂只丢那一条）；有一行语法坏了（截断、乱码）
      // 整个数组解不开，退回逐行解，坏的那几行跳过。
      var joined = [UInt8]()
      joined.reserveCapacity(bytes.count - first.count + body.count + 2)
      joined.append(0x5B)
      for (k, range) in body.enumerated() {
        if k > 0 { joined.append(0x2C) }
        joined.append(contentsOf: bytes[range])
      }
      joined.append(0x5D)
      if let lossy = try? decoder.decode([LossyOrder].self, from: Data(joined)) {
        journal.orders = lossy.compactMap(\.order)
        skipped = lossy.count - journal.orders.count
      } else {
        journal.orders.reserveCapacity(body.count)
        for range in body {
          if let order = try? decoder.decode(BigOrder.self, from: Data(bytes[range])) {
            journal.orders.append(order)
          } else {
            skipped += 1
          }
        }
      }
      return (journal, skipped)
    default:
      return nil
    }
  }

  /// 头：第 2 版的第一行；第 1 版整份（`orders` 也在里面）。
  private struct Header: Decodable {
    var version: Int
    var symbol: String
    var step: Double
    var savedAtMs: Int64
    var orders: [LossyOrder]?
    var historyFromMs: Int64?
    var historyCursorMs: Int64?
    var historyTrackedSinceMs: Int64?
    var historyThresholds: OrderFlowThresholds?
    var calibrated: Double?

    var cursor: OrderFlowHistoryCursor? {
      guard let from = historyFromMs, let cursor = historyCursorMs, from <= cursor else { return nil }
      return OrderFlowHistoryCursor(fromMs: from, cursorMs: cursor, trackedSinceMs: historyTrackedSinceMs,
                                    thresholds: historyThresholds)
    }
  }

  /// 一条大单，读不懂就是 nil（不让整个数组失败）。
  private struct LossyOrder: Decodable {
    var order: BigOrder?
    init(from decoder: any Decoder) { order = try? BigOrder(from: decoder) }
  }
}
