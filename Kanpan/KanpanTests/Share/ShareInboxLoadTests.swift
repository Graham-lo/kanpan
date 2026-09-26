import Foundation
import Testing
import UIKit
@testable import Kanpan

/// 计数的假收件箱服务：每只图被要了几次、收件箱被拉了几次。
private final class CountingShareService: ShareInboxService, @unchecked Sendable {
  private let lock = NSLock()
  private var shots: [String: Int] = [:]
  private var failing: Set<String>
  private let items: [ShareItem]
  private let jpeg: Data
  init(items: [ShareItem], jpeg: Data, failOnce: Set<String> = []) {
    self.items = items; self.jpeg = jpeg; failing = failOnce
  }
  var shotCalls: Int { lock.withLock { shots.values.reduce(0, +) } }
  func shotCalls(_ id: String) -> Int { lock.withLock { shots[id] ?? 0 } }
  private var opened: Set<String> = []
  /// 服务端把回执过「已读」的那几封带着已读时间发回来。
  func inbox(after: String?) async throws -> ShareClient.Page {
    let opened = lock.withLock { self.opened }
    return ShareClient.Page(items: items.map { item in
      var item = item
      if opened.contains(item.id) { item.openedAt = ShareDates.stamp() }
      return item
    }, cursor: "c")
  }
  func friends() async throws -> [ShareFriend] { [] }
  func mark(_ id: String, kept: Bool) async throws { lock.withLock { _ = opened.insert(id) } }
  func shot(_ id: String) async throws -> Data {
    let fail = lock.withLock { () -> Bool in
      shots[id, default: 0] += 1
      return failing.remove(id) != nil
    }
    if fail { throw URLError(.notConnectedToInternet) }
    return jpeg
  }
  func add(_ username: String) async throws {}
  func remove(_ username: String) async throws {}
}

/// 压测 H2 / L3：朋友页收件箱几百封信时，拉一次收件箱不该让所有缩略图重下、重解码。
@Suite(.serialized) @MainActor struct ShareInboxLoadTests {
  private func items(_ count: Int) -> [ShareItem] {
    (0..<count).map { index in
      ShareItem(id: "s\(index)", from: "qa_friend", symbol: "BTCUSDT", market: "binance/usd_m", interval: .h1,
                view: ShareWindow(from: 0, to: 1), drawings: [], alerted: [],
                createdAt: ShareDates.stamp(Date().addingTimeInterval(-Double(index) * 60)))
    }
  }
  private func jpeg() -> Data {
    let format = UIGraphicsImageRendererFormat(); format.scale = 1
    return UIGraphicsImageRenderer(size: CGSize(width: 600, height: 1200), format: format).jpegData(withCompressionQuality: 0.7) { context in
      UIColor.systemTeal.setFill(); context.fill(CGRect(x: 0, y: 0, width: 600, height: 1200))
    }
  }
  private func folder() throws -> URL {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
  }
  private func settle(_ inbox: ShareInbox) async throws {
    let deadline = Date().addingTimeInterval(10)
    while inbox.busy, Date() < deadline { try await Task.sleep(for: .milliseconds(10)) }
    #expect(!inbox.busy)
  }

  @Test func secondPullDoesNotReloadThreeHundredThumbnails() async throws {
    let dir = try folder(); defer { try? FileManager.default.removeItem(at: dir) }
    let service = CountingShareService(items: items(300), jpeg: jpeg())
    let inbox = ShareInbox()
    inbox.activate(directory: dir, owner: UUID(), cache: ShareInbox.Cache(), service: service)
    inbox.pull(); try await settle(inbox)
    #expect(inbox.items.count == 300)
    #expect(inbox.unseen.count == 300)

    // 照视图的写法：每一行要一次图，记下它的任务身份。
    var keys: [String: String] = [:]
    for item in inbox.items {
      let image = await inbox.thumbnail(item.id)
      #expect(image != nil)
      keys[item.id] = ShareThumbnail.loadKey(id: item.id, hasImage: image != nil, revision: inbox.revision)
    }
    #expect(service.shotCalls == 300)

    let before = inbox.revision
    inbox.pull(); try await settle(inbox)
    #expect(inbox.revision == before + 1)
    // 有图的行任务身份不随拉取变 → SwiftUI 不会重跑它们（以前是 id + revision，三百行全重跑）。
    let rerun = inbox.items.filter {
      keys[$0.id] != ShareThumbnail.loadKey(id: $0.id, hasImage: true, revision: inbox.revision)
    }
    #expect(rerun.isEmpty)
    // 懒加载列表里行滚出去又滚回来（视图重建）：内存或盘上有，一张也不再去服务端要。
    for item in inbox.items { #expect(await inbox.thumbnail(item.id) != nil) }
    #expect(service.shotCalls == 300)
    // 三百张下载只排了一次（至多几次）目录裁剪，不是每张一次。
    #expect(inbox.trimsScheduled <= 3)
    // 内存里的是缩到屏上尺寸的图，不是整张解码。
    let sample = try #require(await inbox.thumbnail("s0"))
    #expect(min(sample.size.width, sample.size.height) * sample.scale <= CGFloat(ShareInbox.thumbnailPixels))
    #expect(min(sample.size.width, sample.size.height) * sample.scale >= 132)

    // 已读照常：未读马上少一封，后台落盘后读得回来。
    inbox.opened(inbox.items[0])
    #expect(inbox.unseen.count == 299)
    try await settle(inbox)
    #expect(inbox.unseen.count == 299)
    let stored = try ShareInbox.read(directory: dir)
    #expect(stored.items.count == 300)
    #expect(stored.items.filter { $0.openedAt != nil }.map(\.id) == ["s0"])
  }

  @Test func thumbnailWithoutImageStillRetriesAfterPull() async throws {
    let dir = try folder(); defer { try? FileManager.default.removeItem(at: dir) }
    let service = CountingShareService(items: items(3), jpeg: jpeg(), failOnce: ["s1"])
    let inbox = ShareInbox()
    inbox.activate(directory: dir, owner: UUID(), cache: ShareInbox.Cache(), service: service)
    inbox.pull(); try await settle(inbox)
    #expect(await inbox.thumbnail("s1") == nil)
    let first = ShareThumbnail.loadKey(id: "s1", hasImage: false, revision: inbox.revision)
    inbox.pull(); try await settle(inbox)
    // 发的人截图还没传完时拉不到；下一次拉收件箱这一行换了身份，会再要一次。
    #expect(ShareThumbnail.loadKey(id: "s1", hasImage: false, revision: inbox.revision) != first)
    #expect(await inbox.thumbnail("s1") != nil)
    #expect(service.shotCalls("s1") == 2)
  }

  @Test func concurrentRequestsForOneThumbnailFetchOnce() async throws {
    let dir = try folder(); defer { try? FileManager.default.removeItem(at: dir) }
    let service = CountingShareService(items: items(1), jpeg: jpeg())
    let inbox = ShareInbox()
    inbox.activate(directory: dir, owner: UUID(), cache: ShareInbox.Cache(), service: service)
    // 头部卡片和朋友页那一行同时要同一张。
    async let card = inbox.thumbnail("s0")
    async let row = inbox.thumbnail("s0")
    let (a, b) = await (card, row)
    #expect(a != nil && b != nil)
    #expect(service.shotCalls == 1)
  }

  @Test func burstOfSavesIsCoalescedAndOrdered() throws {
    let dir = try folder(); defer { try? FileManager.default.removeItem(at: dir) }
    let file = dir.appendingPathComponent("shares.json")
    let writer = ShareCacheWriter()
    let start = writer.writes
    var cache = ShareInbox.Cache()
    // 队列正忙（上一份还在写）时连着来 50 份：只该写出最后那一份。
    writer.whileBusy {
      for index in 0..<50 {
        cache.cursor = "c\(index)"
        writer.schedule(cache, to: file) {}
      }
    }
    writer.drain()
    #expect(writer.writes - start == 1)
    #expect(try JSONDecoder().decode(ShareInbox.Cache.self, from: Data(contentsOf: file)).cursor == "c49")
    // 同步写排在后台那份之后落地，不会被旧份盖掉。
    cache.cursor = "old"; writer.schedule(cache, to: file) {}
    cache.cursor = "new"; try writer.writeNow(cache, to: file)
    writer.drain()
    #expect(try JSONDecoder().decode(ShareInbox.Cache.self, from: Data(contentsOf: file)).cursor == "new")
  }

  // ---------------------------------------------------------------- L3：未读名单

  @Test func unseenIsStoredNotRefilteredPerRead() async throws {
    let dir = try folder(); defer { try? FileManager.default.removeItem(at: dir) }
    let service = CountingShareService(items: items(300), jpeg: jpeg())
    let inbox = ShareInbox()
    inbox.activate(directory: dir, owner: UUID(), cache: ShareInbox.Cache(), service: service)
    inbox.pull(); try await settle(inbox)
    // 主页头部那张卡一次 body 里读三遍：三遍拿到的是同一份存储，不是各过滤一遍现造的。
    func storage(_ list: [ShareItem]) -> UnsafeRawPointer? { list.withUnsafeBufferPointer { UnsafeRawPointer($0.baseAddress) } }
    let reads = (0..<3).map { _ in storage(inbox.unseen) }
    #expect(reads.allSatisfy { $0 != nil && $0 == reads[0] })
    #expect(inbox.unseen.count == 300)
    // 拉一次、内容没变：还是那一份，读它的视图不被叫回来重画。
    inbox.pull(); try await settle(inbox)
    #expect(storage(inbox.unseen) == reads[0])
    // 打开一封：马上少一封，换成新的一份。
    inbox.opened(inbox.items[5])
    #expect(inbox.unseen.count == 299)
    #expect(!inbox.unseen.contains { $0.id == inbox.items[5].id })
    #expect(storage(inbox.unseen) != reads[0])
    try await settle(inbox)
    // 换账号：跟着清空。
    inbox.activate(directory: dir, owner: nil, cache: ShareInbox.Cache(), service: nil)
    #expect(inbox.unseen.isEmpty)
  }
}
