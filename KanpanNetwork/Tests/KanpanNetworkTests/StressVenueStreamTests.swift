import Foundation
import Testing
@testable import KanpanNetwork
import KanpanNetworkTestSupport
import KanpanCore

// 压测（2026-10-08）：交易所通用推送 `VenueStream` 与两条连接合流的 `SplitVenueStream`。
//
// 假 socket 把每一发上行连同虚拟时刻记下来（`ManualPacer`，手拨），于是「控制帧数 = 最少必要次数」
// 「两帧间隔 ≥ controlGapMs」「一小时里订退不超 480 次」都是确定的计数，不看墙钟。

// ---------------------------------------------------------------- 假件

/// 记下每一发上行与那一刻虚拟时钟的 socket。`receive()` 只认 `push` 与 `cancel()`。
actor ClockedSocket: WSSocket {
  nonisolated let id: Int
  nonisolated let url: URL
  private let pacer: any Pacer
  private var frames: [WSFrame] = []
  private var waiters: [CheckedContinuation<WSFrame, Error>] = []
  private(set) var sent: [(ms: Double, text: String)] = []
  private(set) var closed = false
  private(set) var cancelCalls = 0

  init(id: Int, url: URL, pacer: any Pacer, kicked: Bool) {
    self.id = id; self.url = url; self.pacer = pacer
    if kicked { frames = [.closed("服务器连上就踢")] }
  }

  func receive() async throws -> WSFrame {
    if closed { throw FeedError.badResponse("#\(id) 已关闭") }
    if !frames.isEmpty { return frames.removeFirst() }
    return try await withCheckedThrowingContinuation { waiters.append($0) }
  }
  func push(_ frame: WSFrame) {
    guard !closed else { return }
    if !waiters.isEmpty { waiters.removeFirst().resume(returning: frame) } else { frames.append(frame) }
  }
  func send(_ text: String) async throws {
    if closed { throw FeedError.badResponse("#\(id) 已关闭") }
    let now = await pacer.nowMs()
    sent.append((now, text))
  }
  func pong() async throws {}
  func cancel() async {
    cancelCalls += 1
    guard !closed else { return }
    closed = true
    let w = waiters; waiters = []
    for c in w { c.resume(throwing: FeedError.badResponse("#\(id) 被掐断")) }
  }
  var texts: [String] { sent.map(\.text) }
  /// 推进来的帧都被收走、收帧那一方又挂回来等下一帧了（上一帧已经解完、记完账）。
  var drained: Bool { frames.isEmpty && !waiters.isEmpty }
}

actor ClockedBench: WSSocketFactory {
  private let pacer: any Pacer
  /// 前多少条连接一连上就被踢（重连风暴）。
  private let kickFirst: Int
  private(set) var made: [ClockedSocket] = []
  init(pacer: any Pacer, kickFirst: Int = 0) { self.pacer = pacer; self.kickFirst = kickFirst }
  func connect(to url: URL) async throws -> any WSSocket {
    let s = ClockedSocket(id: made.count + 1, url: url, pacer: pacer, kicked: made.count < kickFirst)
    made.append(s)
    return s
  }
  var connects: Int { made.count }
  func socket(_ id: Int) -> ClockedSocket? { id >= 1 && id <= made.count ? made[id - 1] : nil }
  func liveSockets() async -> Int {
    var n = 0
    for s in made {
      let closed = await s.closed, cancels = await s.cancelCalls
      if !closed && cancels == 0 { n += 1 }
    }
    return n
  }
}

/// 压测用的协议：`{"op":"subscribe","args":[…]}`，一帧最多 10 个，控制帧间隔 200ms，不发保活。
/// 订阅名：`t:SYM`（行情）、`k:<周期>:SYM`（K 线）、`x:SYM`（逐笔）。
/// 数据帧 `{"arg":"t:SYM","px":"1"}`；回执 `{"event":"subscribe","arg":"t:SYM"}`；
/// 报错 `{"event":"error","arg":"t:SYM"}`（点名）或 `{"event":"error"}`（不点名）。
struct StressWire: VenueWire {
  typealias Sub = String
  var gapMs: Double = 200
  var keepAliveEveryMs: Double?
  var name: String { "Stress" }
  var controlGapMs: Double { gapMs }
  var keepAlive: VenueKeepAlive? { keepAliveEveryMs.map { VenueKeepAlive(text: "ping", everyMs: $0) } }

  func subs(_ topics: [StreamTopic]) -> Set<String> {
    var out = Set<String>()
    for topic in topics {
      let s = InstrumentID(topic.symbol).symbol
      switch topic {
      case .ticker: out.insert("t:" + s)
      case .kline(_, let iv): out.insert("k:\(iv.rawValue):" + s)
      case .trade: out.insert("x:" + s)
      default: break
      }
    }
    return out
  }
  func nextBatch(_ pending: Set<String>) -> [String] { Array(pending.sorted().prefix(10)) }
  func control(_ op: VenueControl, _ subs: [String]) throws -> String {
    String(decoding: try JSONSerialization.data(withJSONObject: ["op": op.rawValue, "args": subs], options: [.sortedKeys]),
           as: UTF8.self)
  }
  func decode(_ text: String) -> VenueWireFrame<String> {
    guard text != "pong", let o = try? JSONSerialization.jsonObject(with: Data(text.utf8)) as? [String: Any] else {
      return .ignored
    }
    let arg = o["arg"] as? String
    switch o["event"] as? String {
    case "error"?: return VenueWireFrame(error: "rejected", rejected: arg.map { [$0] })
    case "subscribe"?: return VenueWireFrame(confirmed: arg.map { [$0] } ?? [])
    case .some: return .ignored
    case nil:
      guard let arg, let px = (o["px"] as? String).flatMap(Double.init) else { return .ignored }
      let symbol = InstrumentID(venue: "stress", market: "spot", symbol: String(arg.split(separator: ":").last ?? "")).key
      return VenueWireFrame(payloads: [.ticker(Ticker(symbol: symbol, last: px, changePercent: .nan, high: .nan,
                                                      low: .nan, quoteVolume: .nan))],
                            confirmed: [arg])
    }
  }
  func label(_ sub: String) -> String { sub }
}

private struct Control: Decodable { var op: String; var args: [String] }
private func controls(_ sent: [(ms: Double, text: String)]) -> [(ms: Double, c: Control)] {
  sent.compactMap { e in (try? JSONDecoder().decode(Control.self, from: Data(e.text.utf8))).map { (e.ms, $0) } }
}
/// OKX 的控制帧（`args` 是对象，不是字符串）：只数 `op`。
private func okxControls(_ sent: [(ms: Double, text: String)]) -> [(ms: Double, op: String)] {
  sent.compactMap { e in
    guard let o = try? JSONSerialization.jsonObject(with: Data(e.text.utf8)) as? [String: Any],
          let op = o["op"] as? String else { return nil }
    return (e.ms, op)
  }
}
private func minGap(_ times: [Double]) -> Double {
  zip(times.dropFirst(), times).map { $0 - $1 }.min() ?? .infinity
}
private func data(_ arg: String, px: Double = 1) -> WSFrame { .text(#"{"arg":"\#(arg)","px":"\#(px)"}"#) }
private func tickers(_ symbols: [String]) -> [StreamTopic] { symbols.map { .ticker(symbol: "stress/spot/\($0)") } }
private let streamURLs = [URL(string: "wss://a.stress.test/ws")!, URL(string: "wss://b.stress.test/ws")!]

/// 拨钟直到条件成立：每次拨 `step` 毫秒，再让出一会儿给醒来的任务跑。
private func spin(_ pacer: ManualPacer, step: Double, maxSteps: Int = 10_000,
                  until cond: @Sendable () async -> Bool) async -> Bool {
  for _ in 0..<maxSteps {
    if await cond() { return true }
    await pacer.advance(step)
    try? await Task.sleep(nanoseconds: 200_000)
  }
  return await cond()
}

// ---------------------------------------------------------------- VenueStream

extension StressVenueSerial {
  @Suite("压测 · 交易所推送", .timeLimit(.minutes(3)))
  struct StressVenueStreamTests {

    @Test("200 个订阅一次订上：恰好 ⌈200/10⌉ 帧、每个订阅只出现一次、两帧间隔 ≥ 200ms；100 次同刻连切只落地一帧退订批 + 一帧订阅")
    func twoHundredSubsAndRapidSwitches() async throws {
      let pacer = ManualPacer()
      let bench = ClockedBench(pacer: pacer)
      let ws = VenueStream(wire: StressWire(), urls: streamURLs, factory: bench, pacer: pacer,
                           silenceMs: 1e12, transportSilenceMs: 1e12)
      let initial = (0..<100).flatMap { i -> [StreamTopic] in
        [.ticker(symbol: "stress/spot/S\(i)"), .trade(symbol: "stress/spot/S\(i)")]
      }
      _ = await ws.start(topics: initial)
      #expect(await waitUntil(5) { await bench.socket(1) != nil })
      let socket = try #require(await bench.socket(1))
      #expect(await spin(pacer, step: 200) { controls(await socket.sent).count >= 20 })
      #expect(await staysFalse(for: 0.2) { controls(await socket.sent).count > 20 })
      var frames = controls(await socket.sent)
      #expect(frames.count == 20)
      #expect(frames.allSatisfy { $0.c.op == "subscribe" && $0.c.args.count == 10 })
      #expect(Set(frames.flatMap(\.c.args)).count == 200)
      #expect(minGap(frames.map(\.ms)) >= 200)

      // 100 次同一刻连切（钟不动）：中间态不该落地。最少必要 = 退订原来的 200 个（20 帧）+ 订最后那一只（1 帧）。
      for i in 0..<100 { await ws.replace(topics: tickers(["N\(i)"])) }
      #expect(await spin(pacer, step: 200) {
        controls(await socket.sent).contains { $0.c.op == "subscribe" && $0.c.args == ["t:N99"] }
      })
      #expect(await staysFalse(for: 0.2) { controls(await socket.sent).count > 41 })
      frames = Array(controls(await socket.sent).dropFirst(20))
      #expect(frames.count == 21, "连切 100 次发了 \(frames.count) 帧")
      #expect(frames.filter { $0.c.op == "unsubscribe" }.flatMap(\.c.args).count == 200)
      #expect(!frames.contains { $0.c.args.contains { $0.hasPrefix("t:N") && $0 != "t:N99" } }, "中间态落地了")
      #expect(minGap(controls(await socket.sent).map(\.ms)) >= 200)
      #expect(await bench.connects == 1)
      await ws.stop()
      await pacer.drain()
    }

    @Test("逐次切周期 100 次（每次都落地）：每次恰好一帧退订 + 一帧订阅，不重连")
    func hundredIntervalSwitches() async throws {
      let pacer = ManualPacer()
      let bench = ClockedBench(pacer: pacer)
      let ws = VenueStream(wire: StressWire(), urls: streamURLs, factory: bench, pacer: pacer,
                           silenceMs: 1e12, transportSilenceMs: 1e12)
      let intervals: [Interval] = [.m1, .m5, .m15, .h1, .h4]
      _ = await ws.start(topics: [.kline(symbol: "stress/spot/BTC", interval: .m1), .ticker(symbol: "stress/spot/BTC")])
      #expect(await waitUntil(5) { await bench.socket(1) != nil })
      let socket = try #require(await bench.socket(1))
      #expect(await spin(pacer, step: 200) { controls(await socket.sent).count >= 1 })
      for n in 1...100 {
        await ws.replace(topics: [.kline(symbol: "stress/spot/BTC", interval: intervals[n % intervals.count]),
                                  .ticker(symbol: "stress/spot/BTC")])
        #expect(await spin(pacer, step: 200) { controls(await socket.sent).count >= 1 + 2 * n })
      }
      #expect(await staysFalse(for: 0.2) { controls(await socket.sent).count > 201 })
      let frames = controls(await socket.sent)
      #expect(frames.count == 201)
      #expect(frames.dropFirst().allSatisfy { $0.c.args.count == 1 && $0.c.args[0].hasPrefix("k:") })
      #expect(minGap(frames.map(\.ms)) >= 200)
      #expect(await bench.connects == 1)
      await ws.stop()
      await pacer.drain()
    }

    /// OKX：每条连接 subscribe + unsubscribe **合计 480 次 / 小时**（按请求帧计）。一小时里每分钟切一次品种，
    /// 两条端点各自只花 1 + 2 × 60 = 121 帧，离红线很远；顺带保活照发、首帧到了不重发。
    @Test("OKX 红线：一小时 60 次切品种，business / public 两条连接各 121 帧控制帧（≤ 480），间隔 ≥ 350ms，不重连")
    func okxHourlyControlBudget() async throws {
      for endpoint in OKXVenue.Endpoint.allCases {
        let pacer = ManualPacer()
        let bench = ClockedBench(pacer: pacer)
        let ws = VenueStream(wire: OKXWire(endpoint: endpoint), urls: [OKXVenue.businessStreamURL], factory: bench,
                             pacer: pacer, silenceMs: 60_000, transportSilenceMs: 1e12)
        func topics(_ i: Int) -> [StreamTopic] {
          let key = "okx/usd_m/C\(i)USDT"
          return endpoint == .business ? [.kline(symbol: key, interval: .m1)]
            : [.ticker(symbol: key), .trade(symbol: key), .markPrice(symbol: key)]
        }
        func confirm(_ socket: ClockedSocket, _ i: Int) async {
          let inst = "C\(i)-USDT-SWAP"
          if endpoint == .business {
            await socket.push(.text(#"{"arg":{"channel":"candle1m","instId":"\#(inst)"},"data":[["1700000000000","1","2","0.5","1.5","10","10","15","0"]]}"#))
          } else {
            for channel in ["tickers", "trades", "mark-price", "funding-rate"] {
              await socket.push(.text(#"{"event":"subscribe","arg":{"channel":"\#(channel)","instId":"\#(inst)"}}"#))
              #expect(await waitUntil(5) { await socket.drained })
            }
            await socket.push(.text(#"{"arg":{"channel":"tickers","instId":"\#(inst)"},"data":[{"instId":"\#(inst)","last":"1.5","open24h":"1","ts":"1700000000000"}]}"#))
          }
        }
        _ = await ws.start(topics: topics(0))
        #expect(await waitUntil(5) { await bench.socket(1) != nil })
        let socket = try #require(await bench.socket(1))
        #expect(await spin(pacer, step: 350, maxSteps: 50) { okxControls(await socket.sent).count >= 1 })
        await confirm(socket, 0)
        for minute in 1...60 {
          await ws.replace(topics: topics(minute))
          #expect(await spin(pacer, step: 350, maxSteps: 50) { okxControls(await socket.sent).count >= 1 + 2 * minute })
          await confirm(socket, minute)
          // 这一分钟剩下的时间：保活照发。
          let elapsed = 2 * 350.0
          _ = await spin(pacer, step: 5_000, maxSteps: Int((60_000 - elapsed) / 5_000)) { false }
        }
        let frames = okxControls(await socket.sent)
        #expect(frames.count == 121, "\(endpoint) 一小时发了 \(frames.count) 帧控制帧")
        #expect(frames.count <= 480)
        #expect(minGap(frames.map(\.ms)) >= OKXVenue.controlGapMs)
        let span = (frames.last?.ms ?? 0) - (frames.first?.ms ?? 0)
        #expect(span <= 3_600_000 + 60_000)
        #expect(await socket.texts.filter { $0 == "ping" }.count >= 150)
        #expect(await bench.connects == 1, "\(endpoint) 这一小时里重连了")
        await ws.stop()
        await pacer.drain()
      }
    }

    @Test("重连风暴：连上就被踢 × 50 → 退避档位单调涨、每次等待在 ±20% 抖动内且不超 30 秒、主备地址轮换、任何时刻至多一条活连接")
    func reconnectStorm() async throws {
      let pacer = ManualPacer()
      let bench = ClockedBench(pacer: pacer, kickFirst: 50)
      let ws = VenueStream(wire: StressWire(), urls: streamURLs, factory: bench, pacer: pacer,
                           silenceMs: 1e12, transportSilenceMs: 1e12)
      _ = await ws.start(topics: tickers(["BTC"]))
      var attempts: [Int] = []
      for n in 1...50 {
        #expect(await waitUntil(10) { await bench.connects >= n })
        #expect(await waitUntil(10) { await ws.backoffAttempt >= n })
        attempts.append(await ws.backoffAttempt)
        #expect(await bench.liveSockets() <= 1)
        // 拨到退避醒点（只拨退避那一觉：控制帧间隔、看门狗都比它短或长得多）。
        #expect(await waitUntil(10) {
          let next = await pacer.nextWakeIn ?? .infinity
          return next >= 500 && next < 1e9
        })
        var spins = 0
        while await bench.connects < n + 1, spins < 100 {
          await pacer.advance(max(1, await pacer.nextWakeIn ?? 1))
          spins += 1
        }
      }
      #expect(await waitUntil(10) { await bench.connects >= 51 })
      #expect(attempts == Array(1...50), "退避档位：\(attempts)")
      let waits = await pacer.sleepLog().filter { $0 >= 500 && $0 < 1e9 }
      #expect(waits.count >= 50)
      for (k, w) in waits.prefix(50).enumerated() {
        let nominal = min(30_000, 1000 * pow(2, Double(k)))
        #expect(w >= nominal * 0.8 - 1e-6 && w <= min(30_000, nominal * 1.2) + 1e-6, "第 \(k + 1) 次退避 \(w)ms，名义 \(nominal)")
      }
      #expect(waits.max() ?? 0 <= 30_000)
      let urls = await bench.made.map(\.url)
      #expect(zip(urls.dropFirst(), urls).prefix(50).allSatisfy { $0 != $1 }, "连不上的地址没轮换")
      // 第 51 条不再被踢：订阅照发、只剩它一条活连接。
      let last = try #require(await bench.socket(51))
      #expect(await spin(pacer, step: 200) { controls(await last.sent).count >= 1 })
      #expect(await bench.liveSockets() == 1)
      await ws.stop()
      await pacer.drain()
    }

    /// 原来：看门狗那一圈里每个过期的订阅各发一帧 subscribe、彼此之间不隔——推着行情时一口气加 30 只
    /// 而上游一只都没回，到点就是 30 帧连发（Bybit 每条连接每秒 10 条入站，当场被踢；OKX 一次烧掉 480 的十六分之一）。
    @Test("首帧看门狗：新加的 30 个订阅都没首帧 → 只重发一次，按批（3 帧）、按间隔发；再没有才重连")
    func firstFrameResendIsBatchedAndOnce() async throws {
      let pacer = ManualPacer()
      let bench = ClockedBench(pacer: pacer)
      let ws = VenueStream(wire: StressWire(), urls: streamURLs, factory: bench, pacer: pacer,
                           silenceMs: 10_000, transportSilenceMs: 1e12)
      _ = await ws.start(topics: tickers(["BTC"]))
      #expect(await waitUntil(5) { await bench.socket(1) != nil })
      let socket = try #require(await bench.socket(1))
      #expect(await spin(pacer, step: 200) { controls(await socket.sent).count >= 1 })
      await socket.push(data("t:BTC"))
      #expect(await waitUntil(5) { await socket.drained })
      let added = (0..<30).map { "A\($0)" }
      await ws.replace(topics: tickers(["BTC"] + added))
      #expect(await spin(pacer, step: 200) { controls(await socket.sent).count >= 4 })
      // 第一个窗口过去：重发。
      #expect(await spin(pacer, step: 500) { controls(await socket.sent).count >= 7 })
      #expect(await staysFalse(for: 0.2) { controls(await socket.sent).count > 7 })
      let frames = controls(await socket.sent)
      let resent = Array(frames.dropFirst(4))
      #expect(resent.count == 3, "重发了 \(resent.count) 帧")
      #expect(Set(resent.flatMap(\.c.args)) == Set(added.map { "t:" + $0 }))
      #expect(minGap(frames.map(\.ms)) >= 200, "控制帧间隔 \(minGap(frames.map(\.ms)))ms")
      #expect(await bench.connects == 1)
      // 重发之后再一个窗口还没有：重连，旧连接上不再有第三次。
      #expect(await spin(pacer, step: 500) { await bench.connects >= 2 })
      #expect(controls(await socket.sent).count == 7)
      await ws.stop()
      await pacer.drain()
    }

    /// 看门狗判了「该重发」、重发还没轮到（订阅同步正在控制帧间隔里睡着）时用户切走了：它仍算已发，照样退订。
    /// 不能为了重发把它从「已发」里拿掉——那样切走时没人退它，上游一直推一只没人要的品种。
    @Test("待重发的订阅在重发之前被切走：照样退订，不重发")
    func resendThenSwitchAwayStillUnsubscribes() async throws {
      let pacer = ManualPacer()
      let bench = ClockedBench(pacer: pacer)
      let ws = VenueStream(wire: StressWire(gapMs: 3_000), urls: streamURLs, factory: bench, pacer: pacer,
                           silenceMs: 10_000, transportSilenceMs: 1e12)
      let t0 = await pacer.nowMs()
      func step(to ms: Double) async {
        while await pacer.nowMs() < t0 + ms {
          await pacer.advance(500)
          try? await Task.sleep(nanoseconds: 2_000_000)
        }
      }
      _ = await ws.start(topics: tickers(["BTC"]))
      #expect(await waitUntil(5) { await bench.socket(1) != nil })
      let socket = try #require(await bench.socket(1))
      #expect(await waitUntil(5) { controls(await socket.sent).count == 1 })
      await socket.push(data("t:BTC"))
      #expect(await waitUntil(5) { await socket.drained })
      await step(to: 3_000)
      await ws.replace(topics: tickers(["BTC", "A"]))
      #expect(await waitUntil(5) { controls(await socket.sent).count == 2 })
      // A 在 t0+3000 发出；t0+13000 过期，看门狗 t0+15000 那一拍发现。先在 t0+14000 加一只 B，让同步睡到 t0+17000。
      await step(to: 14_000)
      await ws.replace(topics: tickers(["BTC", "A", "B"]))
      #expect(await waitUntil(5) { controls(await socket.sent).count == 3 })
      await step(to: 15_000)
      #expect(await waitUntil(5) { await ws.resendCount == 1 })
      // 重发还没轮到：用户把 A 切走了。
      await ws.replace(topics: tickers(["BTC", "B"]))
      await step(to: 21_000)
      #expect(await waitUntil(5) { controls(await socket.sent).count >= 4 })
      _ = await staysFalse(for: 0.2) { false }
      let tail = controls(await socket.sent).dropFirst(3)
      #expect(tail.contains { $0.c.op == "unsubscribe" && $0.c.args == ["t:A"] }, "A 没退订：\(tail.map(\.c.args))")
      #expect(!tail.contains { $0.c.op == "subscribe" && $0.c.args.contains("t:A") })
      #expect(await ws.resendCount == 0)
      await ws.stop()
      await pacer.drain()
    }

    @Test("首帧看门狗：重发之后有一部分回了首帧，只为没回的那几个重连；回了的不再重发")
    func partialConfirmationAfterResend() async throws {
      let pacer = ManualPacer()
      let bench = ClockedBench(pacer: pacer)
      let ws = VenueStream(wire: StressWire(), urls: streamURLs, factory: bench, pacer: pacer,
                           silenceMs: 10_000, transportSilenceMs: 1e12)
      _ = await ws.start(topics: tickers(["BTC"]))
      #expect(await waitUntil(5) { await bench.socket(1) != nil })
      let socket = try #require(await bench.socket(1))
      #expect(await spin(pacer, step: 200) { controls(await socket.sent).count >= 1 })
      await socket.push(data("t:BTC"))
      #expect(await waitUntil(5) { await socket.drained })
      await ws.replace(topics: tickers(["BTC", "A", "B"]))
      #expect(await spin(pacer, step: 200) { controls(await socket.sent).count >= 2 })
      await socket.push(data("t:A"))
      #expect(await waitUntil(5) { await socket.drained })
      #expect(await spin(pacer, step: 500) { controls(await socket.sent).count >= 3 })
      #expect(controls(await socket.sent).dropFirst(2).first?.c.args == ["t:B"])
      await socket.push(data("t:B"))
      #expect(await waitUntil(5) { await socket.drained })
      // 都回了：再过三个窗口也不重连、不再发。
      _ = await spin(pacer, step: 1000, maxSteps: 30) { false }
      #expect(await bench.connects == 1)
      #expect(controls(await socket.sent).count == 3)
      await ws.stop()
      await pacer.drain()
    }

    @Test("被点名拒掉的订阅：不重发、不重连，首帧窗口也不再等它")
    func rejectedIsNotResent() async throws {
      let pacer = ManualPacer()
      let bench = ClockedBench(pacer: pacer)
      let ws = VenueStream(wire: StressWire(), urls: streamURLs, factory: bench, pacer: pacer,
                           silenceMs: 10_000, transportSilenceMs: 1e12)
      _ = await ws.start(topics: tickers(["BTC"]))
      #expect(await waitUntil(5) { await bench.socket(1) != nil })
      let socket = try #require(await bench.socket(1))
      #expect(await spin(pacer, step: 200) { controls(await socket.sent).count >= 1 })
      await socket.push(data("t:BTC"))
      #expect(await waitUntil(5) { await socket.drained })
      await ws.replace(topics: tickers(["BTC", "NOPE"]))
      #expect(await spin(pacer, step: 200) { controls(await socket.sent).count >= 2 })
      await socket.push(.text(#"{"event":"error","arg":"t:NOPE"}"#))
      #expect(await waitUntil(5) { await socket.drained })
      #expect(await waitUntil(5) { await ws.topicErrors["t:NOPE"] != nil })
      _ = await spin(pacer, step: 1000, maxSteps: 60) { false }
      #expect(controls(await socket.sent).count == 2)
      #expect(await bench.connects == 1)

      // 一开始就全被拒的那一轮：60 秒窗口一个接一个过去，也不为它重连。
      let pacer2 = ManualPacer()
      let bench2 = ClockedBench(pacer: pacer2)
      let ws2 = VenueStream(wire: StressWire(), urls: streamURLs, factory: bench2, pacer: pacer2,
                            silenceMs: 10_000, transportSilenceMs: 1e12)
      _ = await ws2.start(topics: tickers(["NOPE"]))
      #expect(await waitUntil(5) { await bench2.socket(1) != nil })
      let s2 = try #require(await bench2.socket(1))
      #expect(await spin(pacer2, step: 200) { controls(await s2.sent).count >= 1 })
      await s2.push(.text(#"{"event":"error","arg":"t:NOPE"}"#))
      #expect(await waitUntil(5) { await s2.drained })
      #expect(await waitUntil(5) { await ws2.topicErrors["t:NOPE"] != nil })
      _ = await spin(pacer2, step: 2_500, maxSteps: 40) { false }
      #expect(await bench2.connects == 1)
      await ws.stop(); await ws2.stop()
      await pacer.drain(); await pacer2.drain()
    }

    /// 原来：不点名的报错一律算到「最近一发控制帧」头上——哪怕那一帧是退订。退订失败（上游说「没订过」）
    /// 就把刚退掉的订阅记成「被拒」，之后用户切回这只，它的首帧窗口不再等它、诊断里还挂着一条假报错。
    /// 一批里一个被拒、别的照样来数据的，也一直挂在 `topicErrors` 里。
    @Test("不点名的报错：退订招来的不记成拒订；一批被连坐的订阅，来了数据就从报错里摘掉")
    func unnamedErrorsAttribution() async throws {
      let pacer = ManualPacer()
      let bench = ClockedBench(pacer: pacer)
      let ws = VenueStream(wire: StressWire(), urls: streamURLs, factory: bench, pacer: pacer,
                           silenceMs: 1e12, transportSilenceMs: 1e12)
      _ = await ws.start(topics: tickers(["A", "B"]))
      #expect(await waitUntil(5) { await bench.socket(1) != nil })
      let socket = try #require(await bench.socket(1))
      #expect(await spin(pacer, step: 200) { controls(await socket.sent).count >= 1 })
      // 不点名的报错落在 [A, B] 那一帧上：两个都被连坐。
      await socket.push(.text(#"{"event":"error"}"#))
      #expect(await waitUntil(5) { await socket.drained })
      #expect(await waitUntil(5) { await ws.topicErrors.count == 2 })
      // A 来了数据：它不是被拒的那个。
      await socket.push(data("t:A"))
      #expect(await waitUntil(5) { await socket.drained })
      #expect(await waitUntil(5) { await ws.topicErrors.keys.sorted() == ["t:B"] })
      // 退掉 A，上游回一句不点名的报错：A 已经不要了，不记。
      await ws.replace(topics: tickers(["B"]))
      #expect(await spin(pacer, step: 200) { controls(await socket.sent).contains { $0.c.op == "unsubscribe" } })
      await socket.push(.text(#"{"event":"error"}"#))
      #expect(await waitUntil(5) { await socket.drained })
      #expect(await staysFalse(for: 0.3) { await ws.topicErrors["t:A"] != nil })
      await ws.stop()
      await pacer.drain()
    }

    @Test("stop() 之后：出口流收尾、socket 被掐、再推的帧不外泄、保活与控制帧都不再发")
    func nothingLeaksAfterStop() async throws {
      let pacer = ManualPacer()
      let bench = ClockedBench(pacer: pacer)
      let ws = VenueStream(wire: StressWire(keepAliveEveryMs: 1_000), urls: streamURLs, factory: bench, pacer: pacer,
                           silenceMs: 10_000, transportSilenceMs: 1e12)
      let stream = await ws.start(topics: tickers(["BTC"]))
      let tally = EventTally()
      let reader = Task { for await e in stream { tally.note(e) } }
      #expect(await waitUntil(5) { await bench.socket(1) != nil })
      let socket = try #require(await bench.socket(1))
      #expect(await spin(pacer, step: 200) { controls(await socket.sent).count >= 1 })
      for i in 0..<50 { await socket.push(data("t:BTC", px: Double(i + 1))) }
      #expect(await waitUntil(5) { tally.count("payload") == 50 })
      // 起一笔切换，正在控制帧间隔里睡着时 stop。
      await ws.replace(topics: tickers(["BTC", "ETH", "SOL"]))
      #expect(await spin(pacer, step: 200) { controls(await socket.sent).count >= 2 })
      await ws.stop()
      await reader.value
      let sentAtStop = await socket.sent.count
      #expect(await socket.closed)
      for i in 0..<20 { await socket.push(data("t:BTC", px: Double(i + 100))) }
      _ = await spin(pacer, step: 1_000, maxSteps: 30) { false }
      #expect(await socket.sent.count == sentAtStop)
      #expect(tally.count("payload") == 50)
      #expect(tally.status == .offline)
      #expect(await bench.connects == 1)
      await pacer.drain()
    }

    @Test("换轮（start 两次）：旧一轮的 socket 被掐，旧轮迟到的帧不进新流，新一轮从头订")
    func restartIsolatesRounds() async throws {
      let bench = GateSocketBench()
      let ws = VenueStream(wire: StressWire(gapMs: 1), urls: streamURLs, factory: bench, pacer: FastPacer(scale: 0.001),
                           silenceMs: 1e12, transportSilenceMs: 1e12)
      let hold = await bench.holdCancel(on: 1)
      let first = await ws.start(topics: tickers(["OLD"]))
      let firstTally = EventTally()
      let r1 = Task { for await e in first { firstTally.note(e) } }
      #expect(await waitUntil(5) { await bench.socket(1) != nil })
      let old = try #require(await bench.socket(1))
      #expect(await waitUntil(5) { await old.sent.count >= 1 })

      let second = await ws.start(topics: tickers(["NEW"]))
      let secondTally = EventTally()
      let r2 = Task { for await e in second { secondTally.note(e) } }
      #expect(await waitUntil(5) { await bench.socket(2) != nil })
      let fresh = try #require(await bench.socket(2))
      #expect(await waitUntil(5) { await fresh.sent.contains { $0.contains("t:NEW") } })
      let freshSent = await fresh.sent
      #expect(!freshSent.contains { $0.contains("t:OLD") })
      // 旧 socket 的 cancel 还卡在闸上：这时它带着帧醒来，新流里不许出现。
      for i in 0..<30 { await old.push(.text(#"{"arg":"t:OLD","px":"\#(i + 1)"}"#)) }
      for i in 0..<30 { await fresh.push(.text(#"{"arg":"t:NEW","px":"\#(i + 1)"}"#)) }
      #expect(await waitUntil(5) { secondTally.count("payload") == 30 })
      #expect(await staysFalse(for: 0.3) { secondTally.count("payload") > 30 })
      #expect(secondTally.klineSymbols.isEmpty)
      await r1.value
      #expect(firstTally.count("payload") == 0)
      await hold.open()
      #expect(await waitUntil(5) { await old.closed })
      await ws.stop()
      await r2.value
    }
  }
}

// ---------------------------------------------------------------- SplitVenueStream

/// 记下每条报文来自哪条车道（`px` 编码：车道 × 100000 + 序号）。
private final class LaneTally: @unchecked Sendable {
  private let lock = NSLock()
  private var pxs: [Double] = []
  private var statuses: [FeedStatus] = []
  private var connected: [Int] = []
  private(set) var finished = false
  func note(_ e: WSEvent) {
    lock.withLock {
      switch e {
      case .payload(.ticker(let t)): pxs.append(t.last)
      case .payload: break
      case .status(let s): statuses.append(s)
      case .connected(let id): connected.append(id)
      }
    }
  }
  func finish() { lock.withLock { finished = true } }
  var prices: [Double] { lock.withLock { pxs } }
  var statusLog: [FeedStatus] { lock.withLock { statuses } }
  var connects: [Int] { lock.withLock { connected } }
}

extension StressVenueSerial {
  @Suite("压测 · 两条连接合流", .timeLimit(.minutes(2)))
  struct StressSplitVenueStreamTests {
    /// 车道 0 收行情、车道 1 收 K 线，各自一套假 socket。
    private func make() -> (SplitVenueStream, GateSocketBench, GateSocketBench) {
      let a = GateSocketBench(), b = GateSocketBench()
      let pacer = FastPacer(scale: 0.0005)
      let lane0 = VenueStream(wire: StressWire(gapMs: 1), urls: [URL(string: "wss://pub.stress.test")!], factory: a,
                              pacer: pacer, silenceMs: 1e12, transportSilenceMs: 1e12)
      let lane1 = VenueStream(wire: StressWire(gapMs: 1), urls: [URL(string: "wss://biz.stress.test")!], factory: b,
                              pacer: pacer, silenceMs: 1e12, transportSilenceMs: 1e12)
      let split = SplitVenueStream(lanes: [
        .init(lane0, accepts: { if case .ticker = $0 { return true } else { return false } }),
        .init(lane1, accepts: { if case .kline = $0 { return true } else { return false } }),
      ])
      return (split, a, b)
    }

    @Test("订阅只落在该去的那条；一条断了另一条照常推、合流状态先「重连中」再「在推」、只为重连报一次 connected；顺序按车道稳定；stop 两条都收")
    func laneIsolation() async throws {
      let (split, a, b) = make()
      let topics: [StreamTopic] = (0..<50).flatMap { i -> [StreamTopic] in
        [.ticker(symbol: "stress/spot/S\(i)"), .kline(symbol: "stress/spot/S\(i)", interval: .m1)]
      }
      let stream = await split.start(topics: topics)
      let tally = LaneTally()
      let reader = Task { for await e in stream { tally.note(e) }; tally.finish() }
      #expect(await waitUntil(5) {
        let x = await a.socket(1), y = await b.socket(1)
        return x != nil && y != nil
      })
      let pub = try #require(await a.socket(1)), biz = try #require(await b.socket(1))
      #expect(await waitUntil(5) {
        let x = await pub.sent.count, y = await biz.sent.count
        return x >= 5 && y >= 5
      })
      let pubArgs = await pub.sent.joined(), bizArgs = await biz.sent.joined()
      #expect(!pubArgs.contains("k:") && pubArgs.contains("t:S49"))
      #expect(!bizArgs.contains("t:") && bizArgs.contains("k:1m:S49"))
      #expect(await waitUntil(5) { tally.connects.count == 1 && tally.statusLog.last == .live })

      // 两条交替推 400 帧：每条车道自己的顺序不乱。
      for i in 0..<200 {
        await pub.push(.text(#"{"arg":"t:S1","px":"\#(100_000 + i)"}"#))
        await biz.push(.text(#"{"arg":"k:1m:S1","px":"\#(200_000 + i)"}"#))
      }
      #expect(await waitUntil(5) { tally.prices.count == 400 })
      let lane0 = tally.prices.filter { $0 < 200_000 }, lane1 = tally.prices.filter { $0 >= 200_000 }
      #expect(lane0 == (0..<200).map { Double(100_000 + $0) })
      #expect(lane1 == (0..<200).map { Double(200_000 + $0) })

      // K 线那条断了：行情那条照推；合流状态报重连，重连上后报一次 connected、回到在推。
      await biz.push(.closed("上游踢线"))
      #expect(await waitUntil(5) { tally.statusLog.contains(.reconnecting) })
      for i in 0..<20 { await pub.push(.text(#"{"arg":"t:S1","px":"\#(300_000 + i)"}"#)) }
      #expect(await waitUntil(5) { tally.prices.filter { $0 >= 300_000 }.count == 20 })
      #expect(await waitUntil(5) { await b.socket(2) != nil })
      #expect(await waitUntil(5) { tally.connects.count == 2 && tally.statusLog.last == .live })
      #expect(await a.connects == 1)
      let biz2 = try #require(await b.socket(2))
      #expect(await waitUntil(5) { await biz2.sent.joined().contains("k:1m:S49") })

      // 去掉全部 K 线：K 线那条收掉，不留空连接；行情那条不动。
      await split.replace(topics: tickers(["S1"]))
      #expect(await waitUntil(5) { await biz2.closed })
      #expect(await a.connects == 1)
      #expect(!(await pub.closed))

      await split.stop()
      await reader.value
      #expect(tally.finished)
      #expect(await pub.closed)
      #expect(tally.statusLog.last == .offline)
    }

    @Test("200 次快速切换（行情 ↔ K 线来回挪）：最后落定的订阅与最后一次 replace 一致，空车道全收")
    func rapidLaneChurn() async throws {
      let (split, a, b) = make()
      let stream = await split.start(topics: tickers(["BTC"]))
      let reader = Task { for await _ in stream {} }
      for i in 0..<200 {
        let symbol = "S\(i % 7)"
        let topics: [StreamTopic] = i % 3 == 0 ? [.kline(symbol: "stress/spot/\(symbol)", interval: .m5)]
          : i % 3 == 1 ? tickers([symbol]) : [.ticker(symbol: "stress/spot/\(symbol)"), .kline(symbol: "stress/spot/\(symbol)", interval: .m1)]
        await split.replace(topics: topics)
      }
      // 第 199 次：i % 3 == 1 → 只剩行情 S3。
      #expect(await waitUntil(5) {
        guard let s = await a.sockets.last else { return false }
        if await s.closed { return false }
        return await s.sent.last?.contains("t:S3") == true
      })
      #expect(await waitUntil(5) {
        for s in await b.sockets { if !(await s.closed) { return false } }
        return true
      })
      #expect(await a.live() <= 1)
      await split.stop()
      await reader.value
      let everything = await a.sockets + (await b.sockets)
      for s in everything { #expect(await s.closed) }
    }
  }
}

private extension Array where Element == String {
  func joined() -> String { joined(separator: "\n") }
}
