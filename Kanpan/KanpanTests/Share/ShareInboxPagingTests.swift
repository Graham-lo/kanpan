import Foundation
import Testing
import KanpanAccount
@testable import Kanpan

/// 按游标翻页的假收件箱：第 n 页带 `more`（nil = 老服务端，不带这个字段）。
private final class PagedShareService: ShareInboxService, @unchecked Sendable {
  private let lock = NSLock()
  private let pages: [[ShareItem]]
  private let more: (Int) -> Bool?
  private var _calls: [String?] = []
  private var _removeError: Error?
  init(pages: [[ShareItem]], more: @escaping (Int) -> Bool?) { self.pages = pages; self.more = more }
  var calls: [String?] { lock.withLock { _calls } }
  var removeError: Error? {
    get { lock.withLock { _removeError } }
    set { lock.withLock { _removeError = newValue } }
  }
  func inbox(after: String?) async throws -> ShareClient.Page {
    let index = lock.withLock { () -> Int in
      _calls.append(after)
      return after.flatMap { Int($0.dropFirst(1)) }.map { $0 + 1 } ?? 0
    }
    let items = index < pages.count ? pages[index] : []
    return ShareClient.Page(items: items, cursor: "p\(index)", more: more(index))
  }
  func friends() async throws -> [ShareFriend] { [ShareFriend(username: "qa_old")] }
  func mark(_ id: String, kept: Bool) async throws {}
  func shot(_ id: String) async throws -> Data { Data() }
  func add(_ username: String) async throws {}
  func remove(_ username: String) async throws { if let error = removeError { throw error } }
}

/// 审查 D 线：收件箱翻页、预留 id 跟着旧信清、朋友名单的保存与报错、坏缓存挪开、
/// 「发给朋友」名单不顶掉打了一半的名字。
@Suite(.serialized) @MainActor struct ShareInboxPagingTests {
  private func item(_ id: String, minutesAgo: Double = 1) -> ShareItem {
    ShareItem(id: id, from: "qa_friend", symbol: "BTCUSDT", market: "binance/usd_m", interval: .h1,
              view: ShareWindow(from: 0, to: 1), drawings: [], alerted: [],
              createdAt: ShareDates.stamp(Date().addingTimeInterval(-minutesAgo * 60)))
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
  private func onDisk(_ dir: URL) throws -> ShareInbox.Cache {
    ShareInbox.writer.drain()
    return try JSONDecoder().decode(ShareInbox.Cache.self,
                                    from: Data(contentsOf: dir.appendingPathComponent("shares.json")))
  }

  @Test("服务端说后面还有，就一趟接着拉完；游标落在最后一页")
  func pullFollowsMoreUntilTheLastPage() async throws {
    let dir = try folder(); defer { try? FileManager.default.removeItem(at: dir) }
    let pages = (0..<3).map { page in (0..<4).map { item("s\(page)-\($0)", minutesAgo: Double(page * 4 + $0)) } }
    let service = PagedShareService(pages: pages) { $0 < 2 }
    let inbox = ShareInbox()
    inbox.activate(directory: dir, owner: UUID(), cache: .init(), service: service)
    inbox.pull(); try await settle(inbox)
    #expect(service.calls == [nil, "p0", "p1"])
    #expect(inbox.items.count == 12)
    #expect(try onDisk(dir).cursor == "p2")
    #expect(inbox.friends.map(\.username) == ["qa_old"])
  }

  @Test("老服务端不带 more：只拉一页，和以前一样")
  func oldServerStopsAfterOnePage() async throws {
    let dir = try folder(); defer { try? FileManager.default.removeItem(at: dir) }
    let service = PagedShareService(pages: [[item("a")], [item("b")]]) { _ in nil }
    let inbox = ShareInbox()
    inbox.activate(directory: dir, owner: UUID(), cache: .init(), service: service)
    inbox.pull(); try await settle(inbox)
    #expect(service.calls == [nil])
    #expect(inbox.items.map(\.id) == ["a"])
  }

  @Test("服务端一直说还有：一趟最多拉 pagesPerPull 页，不打死循环")
  func endlessMoreIsCapped() async throws {
    let dir = try folder(); defer { try? FileManager.default.removeItem(at: dir) }
    let service = PagedShareService(pages: []) { _ in true }
    let inbox = ShareInbox()
    inbox.activate(directory: dir, owner: UUID(), cache: .init(), service: service)
    inbox.pull(); try await settle(inbox)
    #expect(service.calls.count == ShareInbox.pagesPerPull)
    #expect(inbox.notice == nil)
  }

  @Test("「留下」预留的新 id 跟着过了留存期的信一起清掉")
  func copiesFollowExpiredItems() async throws {
    #expect(ShareInbox.prunedCopies(["a": ["x"], "gone": ["y"]], keeping: ["a"]) == ["a": ["x"]])
    let dir = try folder(); defer { try? FileManager.default.removeItem(at: dir) }
    var cache = ShareInbox.Cache()
    cache.items = [item("live"), item("old", minutesAgo: 91 * 24 * 60)]
    cache.copies = ["live": ["c1"], "old": ["c2"]]
    let service = PagedShareService(pages: [[]]) { _ in false }
    let inbox = ShareInbox()
    inbox.activate(directory: dir, owner: UUID(), cache: cache, service: service)
    inbox.pull(); try await settle(inbox)
    #expect(inbox.items.map(\.id) == ["live"])
    #expect(try onDisk(dir).copies == ["live": ["c1"]])
  }

  @Test("服务端加上了朋友、本机名单这会儿写不进盘：不报「没加成」，名单照样多一位")
  func addedFriendSticksEvenIfLocalSaveFails() async throws {
    let missing = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    let inbox = ShareInbox()
    inbox.activate(directory: missing, owner: UUID(), cache: .init(),
                   service: PagedShareService(pages: []) { _ in false })
    try await inbox.addFriend("qa_new")
    #expect(inbox.friends.map(\.username) == ["qa_new"])
  }

  @Test("删朋友失败：错抛给朋友页，不写进收件箱那行「· 重试」，朋友还在")
  func removeFailureGoesToTheCaller() async throws {
    let dir = try folder(); defer { try? FileManager.default.removeItem(at: dir) }
    var cache = ShareInbox.Cache(); cache.friends = [ShareFriend(username: "qa_old")]
    let service = PagedShareService(pages: []) { _ in false }
    service.removeError = AccountError.http(503, "down")
    let inbox = ShareInbox()
    inbox.activate(directory: dir, owner: UUID(), cache: cache, service: service)
    await #expect(throws: AccountError.self) { try await inbox.removeFriend("qa_old") }
    #expect(inbox.notice == nil)
    #expect(inbox.friends.map(\.username) == ["qa_old"])
    service.removeError = nil
    try await inbox.removeFriend("qa_old")
    #expect(inbox.friends.isEmpty)
    #expect(try onDisk(dir).friends.isEmpty)
  }

  @Test("shares.json 解不开：挪到旁边原样留着，当空缓存往下走，不挡住整个档案")
  func unreadableCacheIsSetAside() throws {
    let dir = try folder(); defer { try? FileManager.default.removeItem(at: dir) }
    let file = dir.appendingPathComponent("shares.json")
    let junk = Data("{\"items\":[{\"id\":".utf8)
    try junk.write(to: file)
    let cache = try ShareInbox.read(directory: dir, now: Date(timeIntervalSince1970: 1_700_000_000))
    #expect(cache.items.isEmpty && cache.cursor == nil)
    #expect(!FileManager.default.fileExists(atPath: file.path))
    let aside = dir.appendingPathComponent("shares.json.unreadable-1700000000000")
    #expect(try Data(contentsOf: aside) == junk)
    // 好的那份照常读。
    var good = ShareInbox.Cache(); good.cursor = "p3"
    try JSONEncoder().encode(good).write(to: file)
    #expect(try ShareInbox.read(directory: dir).cursor == "p3")
  }

  @Test("发给朋友：输入框里有字时名单到了也不换掉它；空着才换成名单")
  func pickerKeepsTheHalfTypedName() {
    #expect(FriendPickerSheet.showsList(adding: false, typed: "", friends: 2))
    #expect(!FriendPickerSheet.showsList(adding: false, typed: "qa_", friends: 2))
    #expect(!FriendPickerSheet.showsList(adding: true, typed: "", friends: 2))
    #expect(!FriendPickerSheet.showsList(adding: false, typed: "", friends: 0))
  }
}
