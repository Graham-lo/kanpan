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
public actor MergedMarketStream: MarketStream {
  public typealias Factory = @Sendable (_ venue: String) -> (any MarketStream)?

  private let make: Factory
  private var streams: [String: any MarketStream] = [:]
  private var pumps: [String: Task<Void, Never>] = [:]
  private var statuses: [String: FeedStatus] = [:]
  private var reported: FeedStatus?
  private var continuation: AsyncStream<WSEvent>.Continuation?

  /// - Parameter make: 交易所 → 这一家的一条新推送连接（给 nil 就是这家不开）。
  public init(make: @escaping Factory) { self.make = make }

  public func start(topics: [StreamTopic]) async -> AsyncStream<WSEvent> {
    let (stream, sink) = AsyncStream<WSEvent>.makeStream()
    continuation = sink
    await apply(topics)
    return stream
  }

  public func replace(topics: [StreamTopic]) async { await apply(topics) }

  public func stop() async {
    let all = streams
    pumps.values.forEach { $0.cancel() }
    pumps.removeAll(); streams.removeAll(); statuses.removeAll(); reported = nil
    for stream in all.values { await stream.stop() }
    continuation?.finish(); continuation = nil
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

  private func apply(_ topics: [StreamTopic]) async {
    var grouped: [String: [StreamTopic]] = [:]
    for topic in topics {
      grouped[VenueRegistry.descriptor(forSymbol: topic.symbol).id, default: []].append(topic)
    }
    // 不再需要的那几家：整条连接收掉。
    var removed = false
    for venue in Array(streams.keys) where grouped[venue] == nil {
      removed = true
      pumps.removeValue(forKey: venue)?.cancel()
      statuses[venue] = nil
      if let gone = streams.removeValue(forKey: venue) { await gone.stop() }
    }
    for venue in VenueRegistry.all.map(\.id) {
      guard let wanted = grouped[venue] else { continue }
      if let existing = streams[venue] {
        await existing.replace(topics: wanted)
        continue
      }
      guard let stream = make(venue) else { continue }
      streams[venue] = stream
      let events = await stream.start(topics: wanted)
      pumps[venue] = Task { [weak self] in
        for await event in events {
          guard !Task.isCancelled, let self else { return }
          await self.forward(event, from: venue)
        }
      }
    }
    // 摘掉了一家，合并状态可能随之变（比如剩下的那家一直在推）。
    if removed { publishStatus() }
  }

  private func forward(_ event: WSEvent, from venue: String) {
    guard streams[venue] != nil else { return }
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
