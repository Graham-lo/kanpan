import Foundation
import Testing
@testable import KanpanData
import KanpanNetwork
import KanpanNetworkTestSupport
import KanpanCore

// §B.10 回归规格 BT-06 / BT-08（行情流水线那一半）。
//
// 连接数是按 `GateSocketBench.live()` 数的：从来没有任何人叫过 `cancel()` 的 socket。
// 要摆出来的时序是「一次网络切换正卡在关旧连接那一步（`ws.stop()` 要等一次真往返）」，
// 所以 1 号 socket 的 `cancel()` 挂在一道闸上，其余的全部即时关。一条 `sleep` 都不靠：
// 每一步都等到闸前真有人报到再往下走。

private let lastOpen: Int64 = 1_700_000_000_000
private let step: Int64 = 60_000

/// 历史接口：按 `limit` / `startTime` 给等距 1m K 线，其余一律回一份合法 ticker。
private func history() -> FakeTransport {
  FakeTransport(FakeServer { url in
    guard url.path.contains("klines") else {
      return json(#"{"symbol":"X","lastPrice":"1","priceChangePercent":"0","highPrice":"1","lowPrice":"1","quoteVolume":"1","closeTime":3000}"#)
    }
    let q = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
    var count = min(q.first { $0.name == "limit" }?.value.flatMap(Int.init) ?? 300, 1500)
    if let start = q.first(where: { $0.name == "startTime" })?.value.flatMap(Int64.init) {
      guard start <= lastOpen else { return json("[]") }
      count = min(Int((lastOpen - start) / step) + 1, count)
    }
    let rows = (0..<count).map { i -> String in
      let t = lastOpen - Int64(count - 1 - i) * step
      return "[\(t),\"1\",\"1\",\"1\",\"1\",\"1\",\(t + step - 1),\"1\",1,\"1\",\"1\",\"0\"]"
    }
    return json("[" + rows.joined(separator: ",") + "]")
  })
}

/// 状态事件记录（`.status(...)` 按到达顺序）。
private final class StatusLog: @unchecked Sendable {
  private let lock = NSLock()
  private var items: [FeedStatus] = []
  func add(_ s: FeedStatus) { lock.lock(); items.append(s); lock.unlock() }
  var all: [FeedStatus] { lock.lock(); defer { lock.unlock() }; return items }
}

private struct Rig {
  let feed: MarketFeed
  let bench: GateSocketBench
  let pacer: ManualPacer
  let statuses: StatusLog
  let collector: Task<Void, Never>
  /// 1 号 socket 的关门闸（没要求就是 nil）。
  let hold: Gate?

  /// 收尾：停 feed、放掉所有闸和挂着的闹钟，别让聋 socket 把进程挂住。
  func teardown() async {
    await hold?.open()
    await feed.stop()
    collector.cancel()
    await pacer.drain()
    for s in await bench.sockets { await s.cancel() }
  }
}

/// 起一份连着的 feed：1 号连接已经连上、挂在收帧上。
private func rig(holdFirstCancel: Bool) async throws -> Rig {
  let bench = GateSocketBench(answersKeepalive: true)
  let hold = holdFirstCancel ? await bench.holdCancel(on: 1) : nil
  // WS 的看门狗窗口放到十分钟：这几条用例里连接只该因为 owner 的动作而开关。
  let ws = BinanceWS(factory: bench, silenceMs: 600_000, transportSilenceMs: 600_000)
  // feed 自己的时钟用手拨钟：后台 25 秒闹钟永远不会自己响，要响就由用例显式触发。
  let pacer = ManualPacer()
  let feed = MarketFeed(rest: BinanceREST(transport: history()), ws: ws,
                        paths: Paths(root: FileManager.default.temporaryDirectory
                          .appendingPathComponent(UUID().uuidString)),
                        pacer: pacer, reconcileMs: 0)
  await feed.setSnapshotEnabled(false)
  let statuses = StatusLog()
  let events = await feed.events()
  let collector = Task {
    for await update in events { if case .status(let s) = update.event { statuses.add(s) } }
  }
  await feed.start(symbol: "BTCUSDT", interval: .m1)
  try #require(await waitUntil(5) {
    guard let s = await bench.socket(1) else { return false }
    return await s.receiving == 1
  }, "1 号连接应该已经连上并挂在收帧上")
  #expect(await feed.isWSRunningForTests)
  return Rig(feed: feed, bench: bench, pacer: pacer, statuses: statuses,
             collector: collector, hold: hold)
}

/// 发一次「网络恢复」，让它卡在关 1 号连接那一步（闸前报到了才返回）。
private func heldOnline(_ r: Rig) async throws -> Task<Void, Never> {
  let feed = r.feed
  let t = Task { await feed.networkChanged(online: true) }
  let gate = try #require(r.hold)
  try #require(await waitUntil(5) { await gate.arrived >= 1 },
               "网络切换应该正卡在关 1 号连接那一步")
  return t
}

/// 「此后不会再冒出新连接」：在一个很短的有界窗口里确认连接数没有再涨。
/// 迟到的 `networkChanged` 要是错误地重连，`ws.start` 之后拨号是另一条任务做的，
/// 所以除了同步可见的 `isWSRunningForTests`，还要给拨号一点点时间露头。
private func noNewConnection(_ bench: GateSocketBench, beyond n: Int) async -> Bool {
  !(await waitUntil(0.3) { await bench.connects > n })
}

@Suite("BT-06 网络切换与后台/stop 交错：连接数最终收敛到 1 或 0", .serialized, .timeLimit(.minutes(1)))
struct FeedNetworkConvergenceTests {

  @Test("BT-06a online#1 卡在关旧连接 → owner stop() → 放行：迟到的那次切换不许重新连上（收敛到 0）")
  func heldOnlineThenStopConvergesToZero() async throws {
    let r = try await rig(holdFirstCancel: true)
    let online1 = try await heldOnline(r)

    await r.feed.stop()
    await r.hold?.open()
    await online1.value

    #expect(!(await r.feed.isWSRunningForTests), "stop() 之后 feed 不许再挂着 WS 任务")
    #expect(await noNewConnection(r.bench, beyond: 1), "stop() 之后迟到的网络切换重新拨了连接")
    #expect(await r.bench.live() == 0, "stop() 之后必须一条活连接都不剩")
    await r.teardown()
  }

  @Test("BT-06b online#1 卡住 → online#2 完成 → stop() → 放行 online#1：收敛到 0")
  func twoOnlinesThenStopConvergesToZero() async throws {
    let r = try await rig(holdFirstCancel: true)
    let online1 = try await heldOnline(r)

    await r.feed.networkChanged(online: true)
    try #require(await waitUntil(5) {
      guard let s = await r.bench.socket(2) else { return false }
      return await s.receiving == 1
    }, "online#2 应该已经连上 2 号")
    #expect(await r.bench.live() == 1)

    await r.feed.stop()
    await r.hold?.open()
    await online1.value

    #expect(await noNewConnection(r.bench, beyond: 2))
    #expect(await r.bench.live() == 0)
    await r.teardown()
  }

  @Test("BT-06c online#1 卡住 → online#2 完成 → 放行 online#1：迟到的旧切换不许再重连一次（收敛到 1）")
  func twoOnlinesConvergeToOne() async throws {
    let r = try await rig(holdFirstCancel: true)
    let online1 = try await heldOnline(r)

    await r.feed.networkChanged(online: true)
    try #require(await waitUntil(5) { await r.bench.connects == 2 })

    await r.hold?.open()
    await online1.value

    #expect(await noNewConnection(r.bench, beyond: 2), "被后一次切换顶替掉的旧切换又重连了一次")
    #expect(await r.bench.live() == 1)
    #expect(await r.feed.isWSRunningForTests)
    await r.teardown()
  }

  @Test("BT-06d online#1 卡住 → 进后台、25 秒闹钟响 → 放行：后台里不许被迟到的切换重新连上（收敛到 0）")
  func heldOnlineThenBackgroundSuspendConvergesToZero() async throws {
    let r = try await rig(holdFirstCancel: true)
    let online1 = try await heldOnline(r)

    await r.feed.enterBackground()
    await r.feed.suspendForTests(lifecycle: await r.feed.lifecycleEpochForTests)
    await r.hold?.open()
    await online1.value

    #expect(!(await r.feed.isWSRunningForTests), "后台闹钟已经挂起了 WS，迟到的切换不许把它拉起来")
    #expect(await noNewConnection(r.bench, beyond: 1))
    #expect(await r.bench.live() == 0)

    // 回前台照常恢复，而且只恢复一条。
    await r.feed.enterForeground()
    #expect(await waitUntil(5) { await r.bench.connects == 2 })
    #expect(await r.bench.live() == 1)
    await r.teardown()
  }

  @Test("BT-06e 后台闹钟已挂起 WS 之后再来一次 online：后台不许起连接，回前台恰好一条")
  func onlineWhileSuspendedInBackgroundStaysZero() async throws {
    let r = try await rig(holdFirstCancel: false)
    await r.feed.enterBackground()
    await r.feed.suspendForTests(lifecycle: await r.feed.lifecycleEpochForTests)
    #expect(await waitUntil(5) { await r.bench.live() == 0 })

    await r.feed.networkChanged(online: true)
    #expect(!(await r.feed.isWSRunningForTests), "后台里网络恢复不该把 WS 拉起来")
    #expect(await noNewConnection(r.bench, beyond: 1))
    #expect(await r.bench.live() == 0)

    await r.feed.enterForeground()
    #expect(await waitUntil(5) { await r.bench.connects == 2 })
    #expect(await noNewConnection(r.bench, beyond: 2))
    #expect(await r.bench.live() == 1)
    await r.teardown()
  }

  @Test("BT-06f online#1 卡住 → 后台 → 回前台（重连 2 号）→ 放行：恰好一条活连接，不多拨、不报离线")
  func heldOnlineAcrossBackgroundRoundTripConvergesToOne() async throws {
    let r = try await rig(holdFirstCancel: true)
    let online1 = try await heldOnline(r)

    await r.feed.enterBackground()
    await r.feed.enterForeground()
    try #require(await waitUntil(5) {
      guard let s = await r.bench.socket(2) else { return false }
      return await s.receiving == 1
    }, "回前台应该已经把 2 号连上")
    // 2 号连上的 `.live` 先落地，再放行迟到的那次切换。
    try #require(await waitUntil(5) { r.statuses.all.last == .live })

    await r.hold?.open()
    await online1.value

    #expect(await noNewConnection(r.bench, beyond: 2), "迟到的切换把刚回前台连上的 2 号又换掉了")
    #expect(await r.bench.live() == 1)
    #expect(await r.feed.isWSRunningForTests)
    #expect(r.statuses.all.last == .live,
            "2 号正连着，迟到的切换不许把状态改成离线：\(r.statuses.all)")
    await r.teardown()
  }
}

@Suite("BT-08 取消唯一消费者（MarketFeed）：iterator 退出，连接只听 owner 的", .timeLimit(.minutes(1)))
struct FeedConsumerCancelTests {

  @Test("BT-08 取消 feed.events() 的唯一消费者 → 循环退出；WS 照旧连着不抖；owner stop() 才掐 socket")
  func cancellingFeedConsumerLeavesOwnerInCharge() async throws {
    let bench = GateSocketBench(answersKeepalive: true)
    let ws = BinanceWS(factory: bench, silenceMs: 600_000, transportSilenceMs: 600_000)
    let pacer = ManualPacer()
    let feed = MarketFeed(rest: BinanceREST(transport: history()), ws: ws,
                          paths: Paths(root: FileManager.default.temporaryDirectory
                            .appendingPathComponent(UUID().uuidString)),
                          pacer: pacer, reconcileMs: 0)
    await feed.setSnapshotEnabled(false)
    let events = await feed.events()
    let received = Counter()
    let exited = Counter()
    let consumer = Task {
      for await _ in events { received.bump() }
      exited.bump()
    }
    await feed.start(symbol: "BTCUSDT", interval: .m1)
    try #require(await waitUntil(5) {
      guard let s = await bench.socket(1) else { return false }
      return await s.receiving == 1
    })
    try #require(await waitUntil(5) { received.value > 0 }, "消费者应该先收到过东西")
    let first = try #require(await bench.socket(1))

    // ① 消费者：取消它自己的任务，iterator 返回 nil，循环退出。
    consumer.cancel()
    #expect(await waitUntil(5) { exited.value == 1 }, "取消消费者任务后 for-await 必须退出")

    // ② producer：消费者走了，连接的生死仍归 owner。行情照推、连接不掐、不重连。
    await first.push(.text(klineText(close: 101)))
    #expect(await waitUntil(5) { await first.receiving == 1 })
    #expect(await first.cancelCalls == 0)
    #expect(await ws.currentConnectionID == 1)
    #expect(await bench.connects == 1)
    #expect(await feed.isWSRunningForTests)

    // ③ owner 收场：stop() 返回时 socket 已经被 cancel 并关掉，一条活连接都不剩。
    await feed.stop()
    #expect(await first.cancelCalls >= 1)
    #expect(await first.closed)
    #expect(await first.receiving == 0)
    #expect(await bench.live() == 0)
    #expect(!(await feed.isWSRunningForTests))
    #expect(await noNewConnection(bench, beyond: 1))
    await pacer.drain()
  }
}

/// 一帧 BTCUSDT 1m K 线（组合流格式）。
private func klineText(close: Double) -> String {
  """
  {"stream":"btcusdt@kline_1m","data":{"e":"kline","E":\(lastOpen + 1000),"s":"BTCUSDT",\
  "k":{"t":\(lastOpen),"T":\(lastOpen + 59_999),"s":"BTCUSDT","i":"1m","f":1,"L":2,"o":"\(close)",\
  "c":"\(close)","h":"\(close)","l":"\(close)","v":"1","n":2,"x":false,"q":"1","V":"1","Q":"1","B":"0"}}}
  """
}
