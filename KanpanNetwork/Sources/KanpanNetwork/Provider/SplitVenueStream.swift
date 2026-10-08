import Foundation
import KanpanCore

/// 一家交易所的推送分在几个端点上（K 线一个端点、行情另一个端点）时，把几条连接合成一条 `MarketStream`。
/// **不认识任何一家**：每条车道是一条现成的连接（通常是 `VenueStream`）加一句「这条订阅归不归我」，
/// 由那一家的提供者在 `makeStream` 里配好。
///
/// - 订阅按车道分：一条订阅交给第一条认它的车道；谁都不认的丢掉（能力位里本来就没有）。
/// - 车道按需开关：分到订阅才连，分不到就把那条连接收掉——不留一条什么都没订的空连接
///   （有的交易所对连上之后一直不订阅的连接会主动断开）。
/// - 事件合成一条流：报文照转。连接号 `.connected` 只在**这一轮第一次**连上、以及之后任何一条
///   **重连**时报（上层拿它判「重连了 → 补缺」；两条车道刚开时各连一次不是重连）。
/// - 状态取最差的那条（离线 > 重连中 > 在推），只在合并后的值变了才报：K 线那条断了，
///   行情那条还在推也不能报「在推」，否则上层不会记缺口。
///
/// 所有操作排成一队按到达顺序做（`start` / `replace` / `stop` 可能从无序的任务里来）。
public actor SplitVenueStream: MarketStream {
  /// 一条车道：一条连接 + 它收哪些订阅。
  public struct Lane: Sendable {
    public let stream: any MarketStream
    public let accepts: @Sendable (StreamTopic) -> Bool
    public init(_ stream: any MarketStream, accepts: @escaping @Sendable (StreamTopic) -> Bool) {
      self.stream = stream; self.accepts = accepts
    }
  }

  private let lanes: [Lane]
  /// 每条车道此刻开着没有（开着 = `start` 过、没 `stop`）。
  private var running: [Bool]
  /// 每条车道当前这一次 `start` 的编号：旧一轮的泵迟到的事件对不上号就扔掉。
  private var serials: [Int]
  private var nextSerial = 0
  private var pumps: [Task<Void, Never>?]
  /// 每条车道这一轮连上过几次（第一次不算重连）。
  private var connects: [Int]
  private var statuses: [FeedStatus?]
  private var reported: FeedStatus?
  /// 这一轮报过 `.connected` 没有。
  private var announced = false
  private var emitted = 0
  private var continuation: AsyncStream<WSEvent>.Continuation?
  /// 操作队列的队尾。
  private var tail: Task<Void, Never>?

  public init(lanes: [Lane]) {
    self.lanes = lanes
    running = Array(repeating: false, count: lanes.count)
    serials = Array(repeating: 0, count: lanes.count)
    pumps = Array(repeating: nil, count: lanes.count)
    connects = Array(repeating: 0, count: lanes.count)
    statuses = Array(repeating: nil, count: lanes.count)
  }

  // ------------------------------------------------------------------ MarketStream

  public func start(topics: [StreamTopic]) async -> AsyncStream<WSEvent> {
    let (stream, sink) = AsyncStream<WSEvent>.makeStream(bufferingPolicy: .unbounded)
    await enqueue { await $0.restart(topics: topics, sink: sink) }
    return stream
  }

  public func replace(topics: [StreamTopic]) async {
    await enqueue { await $0.apply(topics) }
  }

  public func stop() async {
    await enqueue { await $0.shutdown() }
  }

  public var firstFrameSilenceMs: Double {
    get async {
      var longest = 0.0
      for lane in lanes { longest = max(longest, await lane.stream.firstFrameSilenceMs) }
      return longest
    }
  }

  /// 各条车道连接号之和：任何一条重连它都会变。
  public var currentConnectionID: Int {
    get async {
      var sum = 0
      for lane in lanes { sum += await lane.stream.currentConnectionID }
      return sum
    }
  }

  // ------------------------------------------------------------------ 操作队列

  private func enqueue(_ work: @escaping @Sendable (SplitVenueStream) async -> Void) async {
    let previous = tail
    let task = Task { [weak self] in
      await previous?.value
      guard let self else { return }
      await work(self)
    }
    tail = task
    await task.value
  }

  private func restart(topics: [StreamTopic], sink: AsyncStream<WSEvent>.Continuation) async {
    await closeLanes()
    continuation?.finish()
    continuation = sink
    reported = nil; announced = false
    await apply(topics)
  }

  private func shutdown() async {
    await closeLanes()
    let sink = continuation
    continuation = nil; reported = nil; announced = false
    sink?.yield(.status(.offline))
    sink?.finish()
  }

  private func closeLanes() async {
    for i in lanes.indices where running[i] {
      await close(i)
    }
  }

  private func close(_ i: Int) async {
    running[i] = false
    pumps[i]?.cancel(); pumps[i] = nil
    statuses[i] = nil; connects[i] = 0
    nextSerial &+= 1
    serials[i] = nextSerial
    await lanes[i].stream.stop()
  }

  /// 按车道分订阅：分到的开（已经开着就换订阅），分不到的收掉。
  private func apply(_ topics: [StreamTopic]) async {
    guard continuation != nil else { return }
    var parts = Array(repeating: [StreamTopic](), count: lanes.count)
    for topic in topics {
      if let i = lanes.firstIndex(where: { $0.accepts(topic) }) { parts[i].append(topic) }
    }
    var closed = false
    for i in lanes.indices {
      if parts[i].isEmpty {
        if running[i] { await close(i); closed = true }
        continue
      }
      if running[i] {
        await lanes[i].stream.replace(topics: parts[i])
        continue
      }
      running[i] = true
      nextSerial &+= 1
      let serial = nextSerial
      serials[i] = serial
      connects[i] = 0
      let events = await lanes[i].stream.start(topics: parts[i])
      pumps[i] = Task { [weak self] in
        for await event in events {
          guard !Task.isCancelled, let self else { return }
          await self.forward(event, lane: i, serial: serial)
        }
      }
    }
    if closed { publishStatus() }
  }

  private func forward(_ event: WSEvent, lane i: Int, serial: Int) {
    guard serials[i] == serial, running[i], let sink = continuation else { return }
    switch event {
    case .payload:
      sink.yield(event)
    case .connected:
      connects[i] += 1
      // 这一轮的第一次连上报一次；之后哪条车道再连上（第二次起）就是重连，照报。
      guard !announced || connects[i] > 1 else { return }
      announced = true
      emitted += 1
      sink.yield(.connected(id: emitted))
    case .status(let status):
      statuses[i] = status
      publishStatus()
    }
  }

  private func publishStatus() {
    let live = lanes.indices.filter { running[$0] }.compactMap { statuses[$0] }
    guard !live.isEmpty else { return }
    let merged: FeedStatus = live.contains(.offline) ? .offline
      : live.contains(.reconnecting) ? .reconnecting : .live
    guard merged != reported else { return }
    reported = merged
    continuation?.yield(.status(merged))
  }
}
