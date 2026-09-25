import Foundation
import KanpanCore
import KanpanNetwork

/// 跨交易所的一条「列表行情」推送：订阅按品种键里的交易所分组，每家各开一条自己的连接，
/// 吐出来的事件合成一条流。
///
/// 自选 / 搜索列表里同时有几家的品种；上层（`QuoteBook`）只想要「这些品种的 24h 行情」，
/// 不该知道背后开了几条连接、各连哪家。只有一家时它就是那一条连接的直通。
///
/// 状态合并：任何一家在推就算 `.live`（列表那盏灯只说「有实时数据在来」）；
/// 全都不在推时，有一家在重连就报重连，否则离线。
///
/// 订阅是「期望集 + 唯一一个对账任务」：`want` / `replace` 只改期望集，真正去开连接、换订阅的
/// 永远只有一个对账任务，它一轮一轮追到期望集不再变为止。所以上层随手在无序的 `Task {}` 里
/// 调多少次都不会乱序覆盖（旧的那次后到也只是再对一次账，读到的仍是最新的期望），
/// 也不会两次并发 apply 给同一家各开一条连接。
public actor MergedMarketStream: MarketStream {
  public typealias Factory = @Sendable (_ venue: String) -> (any MarketStream)?

  /// 期望集放在锁里，`want` 不用进 actor 就能同步写下（调用方写完立刻就算数）。
  private final class Desired: @unchecked Sendable {
    private let lock = NSLock()
    private var topics: [StreamTopic] = []
    private var version = 0
    func set(_ next: [StreamTopic]) { lock.withLock { topics = next; version &+= 1 } }
    var current: (topics: [StreamTopic], version: Int) { lock.withLock { (topics, version) } }
  }

  private let make: Factory
  private let desired = Desired()
  /// 已经对到连接上的期望版本；-1 表示还什么都没对（新建或 stop 之后）。
  private var applied = -1
  private var reconcileTask: Task<Void, Never>?
  /// 每次 `stop` 加一：还在半路的对账看到它变了就收手，并把自己刚开的连接关掉。
  private var epoch = 0
  private var streams: [String: any MarketStream] = [:]
  /// 每家当前那条连接的编号：旧连接的泵迟到的事件对不上号就扔掉。
  private var serials: [String: Int] = [:]
  private var nextSerial = 0
  private var pumps: [String: Task<Void, Never>] = [:]
  private var statuses: [String: FeedStatus] = [:]
  private var reported: FeedStatus?
  private var continuation: AsyncStream<WSEvent>.Continuation?

  /// - Parameter make: 交易所 → 这一家的一条新推送连接（给 nil 就是这家不开）。
  public init(make: @escaping Factory) { self.make = make }

  /// 同步写下期望的订阅集，对账在后台追上。可以在任何线程、按任何顺序调，最后一次说了算。
  public nonisolated func want(_ topics: [StreamTopic]) {
    desired.set(topics)
    Task { await self.kick() }
  }

  /// 开一条事件流给上层读（期望集由 `want` 给）。再开一次会先结束旧的那条流。
  public func open() -> AsyncStream<WSEvent> {
    continuation?.finish()
    let (stream, sink) = AsyncStream<WSEvent>.makeStream()
    continuation = sink
    // 换了读者：把当前合并状态补给它，别让新读者一直等下一次状态变化。
    if let reported { sink.yield(.status(reported)) }
    kick()
    return stream
  }

  public func start(topics: [StreamTopic]) async -> AsyncStream<WSEvent> {
    desired.set(topics)
    let stream = open()
    await settle()
    return stream
  }

  public func replace(topics: [StreamTopic]) async {
    desired.set(topics)
    kick()
    await settle()
  }

  public func stop() async {
    epoch &+= 1
    reconcileTask?.cancel(); reconcileTask = nil
    applied = -1
    let all = streams
    pumps.values.forEach { $0.cancel() }
    pumps.removeAll(); streams.removeAll(); serials.removeAll(); statuses.removeAll(); reported = nil
    continuation?.finish(); continuation = nil
    for stream in all.values { await stream.stop() }
  }

  public var firstFrameSilenceMs: Double {
    get async {
      var longest = 0.0
      for stream in streams.values { longest = max(longest, await stream.firstFrameSilenceMs) }
      return longest
    }
  }

  /// 各家连接号之和。任何一家重连它都会变，够「有没有重连过」这种判断用。
  public var currentConnectionID: Int {
    get async {
      var sum = 0
      for stream in streams.values { sum += await stream.currentConnectionID }
      return sum
    }
  }

  /// 期望集和已对上的不一样、又有人在读时，起（唯一的）对账任务；已经在跑就交给它。
  private func kick() {
    guard continuation != nil, reconcileTask == nil, desired.current.version != applied else { return }
    let epoch = self.epoch
    reconcileTask = Task { [weak self] in await self?.reconcile(epoch: epoch) }
  }

  /// 等到期望集全部对上（或被 stop 打断）。
  private func settle() async {
    while let task = reconcileTask {
      await task.value
      if reconcileTask == task { reconcileTask = nil }
    }
  }

  private func reconcile(epoch: Int) async {
    while self.epoch == epoch, continuation != nil {
      let want = desired.current
      guard want.version != applied else { break }
      await apply(want.topics, epoch: epoch)
      guard self.epoch == epoch else { return }
      applied = want.version
    }
    if self.epoch == epoch { reconcileTask = nil }
  }

  private func apply(_ topics: [StreamTopic], epoch: Int) async {
    var grouped: [String: [StreamTopic]] = [:]
    for topic in topics {
      grouped[VenueRegistry.descriptor(forSymbol: topic.symbol).id, default: []].append(topic)
    }
    // 不再需要的那几家：整条连接收掉。
    var removed = false
    for venue in Array(streams.keys) where grouped[venue] == nil {
      removed = true
      pumps.removeValue(forKey: venue)?.cancel()
      statuses[venue] = nil; serials[venue] = nil
      if let gone = streams.removeValue(forKey: venue) { await gone.stop() }
      guard self.epoch == epoch else { return }
    }
    for venue in VenueRegistry.all.map(\.id) {
      guard let wanted = grouped[venue] else { continue }
      if let existing = streams[venue] {
        await existing.replace(topics: wanted)
        guard self.epoch == epoch else { return }
        continue
      }
      guard let stream = make(venue) else { continue }
      nextSerial &+= 1
      let serial = nextSerial
      streams[venue] = stream; serials[venue] = serial
      let events = await stream.start(topics: wanted)
      guard self.epoch == epoch else {
        // 半路被 stop 了：stop 那边可能赶在 start 之前关过它，这里再关一次（stop 可重入）。
        await stream.stop()
        return
      }
      pumps[venue] = Task { [weak self] in
        for await event in events {
          guard !Task.isCancelled, let self else { return }
          await self.forward(event, from: venue, serial: serial)
        }
      }
    }
    // 摘掉了一家，合并状态可能随之变（比如剩下的那家一直在推）。
    if removed { publishStatus() }
  }

  private func forward(_ event: WSEvent, from venue: String, serial: Int) {
    guard serials[venue] == serial else { return }
    if case .status(let status) = event {
      statuses[venue] = status
      publishStatus()
      return
    }
    continuation?.yield(event)
  }

  private func publishStatus() {
    guard !statuses.isEmpty else { return }
    let values = Array(statuses.values)
    let merged: FeedStatus = values.contains(.live) ? .live
      : values.contains(.reconnecting) ? .reconnecting : .offline
    // 单家时每一次状态都照转（和直接用那一条连接一模一样）；多家时只在合并后的值变了才报。
    guard streams.count == 1 || merged != reported else { return }
    reported = merged
    continuation?.yield(.status(merged))
  }
}
