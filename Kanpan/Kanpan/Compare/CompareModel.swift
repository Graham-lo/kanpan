import Foundation
import Observation
import SwiftUI
import KanpanCore
import KanpanData
import KanpanChart

/// 主屏的对比行情寿命与对齐缓存；不占用主行情首屏的等待链。
@MainActor @Observable final class CompareModel {
  private(set) var snapshots: [CompareFeed.Snapshot] = []
  @ObservationIgnored private var feed: CompareFeed?
  @ObservationIgnored private var pump: Task<Void, Never>?
  @ObservationIgnored private var request: Request?
  @ObservationIgnored private var main: BarSeries?
  @ObservationIgnored private var generation = UUID()
  @ObservationIgnored private var foreground = true
  @ObservationIgnored private var alignment: (times: [Int64], revision: [BarSeries], values: [String: (open: [Double?], close: [Double?])])?

  private struct Request: Equatable {
    var keys: [String]
    var symbol: String
    var interval: Interval
    var hosts: BinanceHosts
    var policy: MarketRoutePolicy
  }

  func configure(keys: [String], main: BarSeries?, symbol: String, interval: Interval,
                 hosts: BinanceHosts, policy: MarketRoutePolicy) {
    let next = Request(keys: keys.filter { $0 != InstrumentID.canonical(symbol) }, symbol: symbol, interval: interval, hosts: hosts, policy: policy)
    self.main = main?.symbol == symbol && main?.interval == interval ? main : nil
    if next != request {
      stopFeed(); snapshots = []; alignment = nil; request = next
    }
    guard foreground, !next.keys.isEmpty, let main = self.main, !main.isEmpty else {
      stopFeed(); snapshots = []; alignment = nil
      return
    }
    if let feed { Task { await feed.updateMain(main) }; return }
    let created = CompareFeed(hosts: hosts, policy: policy)
    feed = created
    let token = generation
    pump = Task { [weak self] in
      let events = await created.events()
      await created.start(keys: next.keys, main: main)
      for await values in events {
        guard !Task.isCancelled, let self, self.generation == token else { return }
        self.snapshots = values
      }
    }
  }

  func series(main: BarSeries, keys: [String], colors: [Hex], names: (String) -> String) -> [CompareSeries] {
    guard !keys.isEmpty else { return [] }
    let data = snapshots
    let times = (0..<main.count).map { main.time(at: $0) }
    let revisions = data.map(\.series)
    if alignment?.times != times || alignment?.revision != revisions {
      alignment = (times, revisions, Dictionary(uniqueKeysWithValues: data.map { ($0.key, $0.aligned(to: main)) }))
    }
    return keys.enumerated().map { index, key in
      let value = alignment?.values[key]
      return CompareSeries(key: key, name: names(key), color: colors[index % colors.count],
        open: value?.open ?? [], close: value?.close ?? [])
    }
  }

  func setForeground(_ value: Bool) {
    guard foreground != value else { return }
    foreground = value
    if !value { stopFeed() }
    else if let request {
      configure(keys: request.keys, main: main, symbol: request.symbol, interval: request.interval,
        hosts: request.hosts, policy: request.policy)
    }
  }

  private func stopFeed() {
    generation = UUID(); pump?.cancel(); pump = nil
    let previous = feed; feed = nil
    if let previous { Task { await previous.stop() } }
  }

  func stop() { request = nil; main = nil; stopFeed(); snapshots = []; alignment = nil }
  deinit {
    pump?.cancel()
    if let feed { Task { await feed.stop() } }
  }
}

/// 对比行情的接线键：这几样任何一样变了，就按当前情形把对比行情重配一遍。
///
/// 只放便宜的值（序列首尾时刻而不是整条序列），免得主屏每次求值都去比一千多根 K 线。
/// `keys` 为空表示「这一刻不对比」——横屏画线、复盘、分享预览都走这条，集合本身仍留在偏好里。
struct CompareDrive: Equatable {
  var keys: [String]
  var symbol: String
  var interval: Interval
  var hosts: BinanceHosts
  var policy: MarketRoutePolicy
  var ready: Bool
  var first: Int64
  var last: Int64
}

/// 对比这一摊唯一的观察者。挂成独立修饰符，不往主屏那条 `body` 链上再接 `onChange`。
struct CompareObservers: ViewModifier {
  let drive: CompareDrive
  let onChange: () -> Void
  func body(content: Content) -> some View {
    content.onChange(of: drive, initial: true) { _, _ in onChange() }
  }
}
