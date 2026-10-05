import Foundation
import KanpanAccount
import KanpanCore
import Testing
@testable import Kanpan

/// 「提醒」表的日志页（2026-10-05）：拆包、分天、写时刻，以及按账号缓存 / 404 当空 / 失败照摆缓存。
@Suite("提醒 · 日志")
@MainActor
struct AlertLogTests {
  private let shanghai = TZOffset.fixed(480)

  private func ms(_ iso: String) -> Int64 {
    let f = ISO8601DateFormatter()
    return Int64(f.date(from: iso)!.timeIntervalSince1970 * 1000)
  }

  private func record(_ id: String, at: Int64, symbol: String = "BTCUSDT", condition: String? = "价格达到 85,000",
                      price: Double? = 85_012.5) -> AlertLogRecord {
    AlertLogRecord(id: id, alertId: "a" + id, kind: "price", symbol: symbol, title: "BTC 涨到 85,000",
                   condition: condition, firedAt: at, firedPrice: price)
  }

  @Test("拆包：裸的与包在 data 里的都认，按响的时间倒序；firedAt 是浮点也认，缺的可选字段当空")
  func decode() throws {
    let bare = #"{"records":[{"id":"1","kind":"price","symbol":"BTCUSDT","title":"t1","firedAt":1000},"#
      + #"{"id":"2","kind":"line","symbol":"ETHUSDT","title":"t2","condition":"触到水平线","firedAt":3000.0,"firedPrice":4000.5,"extra":1}]}"#
    let a = try AlertLogText.decode(Data(bare.utf8))
    #expect(a.map(\.id) == ["2", "1"])
    #expect(a[0].firedAt == 3000 && a[0].firedPrice == 4000.5 && a[0].condition == "触到水平线")
    #expect(a[1].alertId == nil && a[1].condition == nil && a[1].firedPrice == nil)
    let wrapped = #"{"data":{"records":[{"id":"9","kind":"reviewDue","symbol":"","title":"复盘到点","firedAt":5}]}}"#
    let b = try AlertLogText.decode(Data(wrapped.utf8))
    #expect(b.map(\.id) == ["9"])
    #expect(throws: (any Error).self) { try AlertLogText.decode(Data("{}".utf8)) }
  }

  @Test("按上海的天分组：今天、昨天、今年的写月日、往年带年份")
  func days() {
    let now = ms("2026-10-05T04:00:00Z")   // 上海 10-05 12:00
    let records = [
      record("old", at: ms("2025-12-31T08:00:00Z")),
      record("today", at: ms("2026-10-04T17:30:00Z")),   // 上海 10-05 01:30
      record("yday", at: ms("2026-10-04T15:59:00Z")),    // 上海 10-04 23:59
      record("oct1", at: ms("2026-10-01T02:00:00Z")),
    ]
    let days = AlertLogText.days(records, zone: shanghai, now: now)
    #expect(days.map(\.title) == ["今天", "昨天", "10月1日", "2025年12月31日"])
    #expect(days.map { $0.records.map(\.id) } == [["today"], ["yday"], ["oct1"], ["old"]])
  }

  @Test("行尾时刻按上海 24 小时制；第二行是条件 · 触发价，没条件用标题")
  func rowText() {
    #expect(AlertLogText.clock(ms("2026-10-04T17:30:00Z"), zone: shanghai) == "01:30")
    #expect(AlertLogText.clock(ms("2026-10-05T15:05:00Z"), zone: shanghai) == "23:05")
    let r = record("1", at: 0)
    #expect(AlertLogText.detail(r, decimals: 1) == "价格达到 85,000 · 触发价 85,012.5")
    #expect(AlertLogText.detail(record("2", at: 0, condition: nil), decimals: 1) == "BTC 涨到 85,000 · 触发价 85,012.5")
    #expect(AlertLogText.detail(record("3", at: 0, condition: " ", price: nil), decimals: nil) == "BTC 涨到 85,000")
    #expect(AlertLogText.name(r) == "BTC/USDT")
    #expect(AlertLogText.name(AlertLogRecord(id: "x", kind: "reviewDue", symbol: "", title: "", firedAt: 0)) == "提醒")
  }

  // ---------------------------------------------------------------- 状态

  private final class Fake: @unchecked Sendable {
    var calls: [(String, String)] = []
    var result: Result<Data, Error> = .success(Data(#"{"records":[]}"#.utf8))
    var fetch: AlertLogModel.Fetch {
      { path, method in
        self.calls.append((path, method))
        return try self.result.get()
      }
    }
  }

  private func defaults() -> UserDefaults {
    UserDefaults(suiteName: "alert-log-\(UUID().uuidString)")!
  }

  private func payload(_ ids: [String]) -> Data {
    let items = ids.enumerated().map { i, id in
      #"{"id":"\#(id)","kind":"price","symbol":"BTCUSDT","title":"t","firedAt":\#(1000 + i)}"#
    }
    return Data(#"{"records":[\#(items.joined(separator: ","))]}"#.utf8)
  }

  @Test("拉一趟：带 limit=200 的 GET；拿到的按账号存下，换号不串，换回来照摆")
  func refreshAndCachePerOwner() async {
    let store = defaults()
    let a = UUID(), b = UUID()
    let fake = Fake()
    fake.result = .success(payload(["1", "2"]))
    let model = AlertLogModel(defaults: store)
    await model.refresh(owner: a, fetch: fake.fetch)
    #expect(fake.calls.map(\.0) == ["v1/alerts/log?limit=200"])
    #expect(fake.calls.map(\.1) == ["GET"])
    #expect(model.records.map(\.id) == ["2", "1"])
    #expect(model.phase == .loaded)
    model.select(owner: b)
    #expect(model.records.isEmpty && model.phase == .idle)
    model.select(owner: a)
    #expect(model.records.map(\.id) == ["2", "1"])
    // 另起一个（app 重启）照样读得到 A 那份。
    let reborn = AlertLogModel(defaults: store)
    reborn.select(owner: a)
    #expect(reborn.records.map(\.id) == ["2", "1"])
  }

  @Test("404（服务端还没这条路）当「暂无记录」；断网照摆上一次那份")
  func notFoundIsEmptyAndFailureKeepsCache() async {
    let owner = UUID()
    let fake = Fake()
    let model = AlertLogModel(defaults: defaults())
    fake.result = .success(payload(["1"]))
    await model.refresh(owner: owner, fetch: fake.fetch)
    fake.result = .failure(URLError(.notConnectedToInternet))
    await model.refresh(owner: owner, fetch: fake.fetch)
    #expect(model.records.map(\.id) == ["1"])
    #expect(model.phase == .failed)
    fake.result = .failure(AccountError.http(404, "not found"))
    await model.refresh(owner: owner, fetch: fake.fetch)
    #expect(model.records.isEmpty && model.phase == .loaded)
  }

  @Test("没登录：不发请求、一条都不摆")
  func signedOut() async {
    let fake = Fake()
    let model = AlertLogModel(defaults: defaults())
    await model.refresh(owner: nil, fetch: fake.fetch)
    #expect(fake.calls.isEmpty && model.records.isEmpty)
    #expect(await model.clear(fetch: fake.fetch) == false)
  }

  @Test("清空：DELETE 成功（或 404）本机那份一起清；失败列表不动")
  func clear() async {
    let store = defaults()
    let owner = UUID()
    let fake = Fake()
    let model = AlertLogModel(defaults: store)
    fake.result = .success(payload(["1", "2"]))
    await model.refresh(owner: owner, fetch: fake.fetch)
    fake.result = .failure(AccountError.http(500, "boom"))
    #expect(await model.clear(fetch: fake.fetch) == false)
    #expect(model.records.count == 2)
    fake.result = .success(Data())
    #expect(await model.clear(fetch: fake.fetch))
    #expect(fake.calls.last.map { $0.0 + " " + $0.1 } == "v1/alerts/log DELETE")
    #expect(model.records.isEmpty)
    let reborn = AlertLogModel(defaults: store)
    reborn.select(owner: owner)
    #expect(reborn.records.isEmpty)
    fake.result = .failure(AccountError.http(404, ""))
    #expect(await model.clear(fetch: fake.fetch))
  }
}

/// 「提醒」表列表页：图上这只置顶成一组，其余照总表；顶栏铃角标的数。
@Suite("提醒 · 置顶与角标")
@MainActor
struct AlertPinnedRowsTests {
  private func fresh() -> AlertStore {
    let url = FileManager.default.temporaryDirectory
      .appendingPathComponent("alerts-pinned-\(UUID().uuidString).json")
    return AlertStore(store: AlertFileStore(url: url))
  }

  private func shape(_ rows: [AlertListItem]) -> [String] {
    rows.map {
      switch $0 {
      case let .pinTitle(symbol): "PIN \(InstrumentID(symbol).symbol)"
      case let .pinKind(kind, count, top): "K \(kind.rawValue) \(count) \(top)"
      case .pinEmpty: "EMPTY"
      case let .title(kind, _, first): "T \(kind.rawValue) \(first)"
      case let .header(_, symbol, count, _): "H \(InstrumentID(symbol).symbol) \(count)"
      case let .record(_, withSymbol, divider, _, bottom): "R \(withSymbol) \(divider) \(bottom)"
      }
    }
  }

  private func seeded() throws -> AlertStore {
    let store = fresh()
    _ = try #require(store.addPrice(symbol: "BTCUSDT", target: 90_000, current: 84_500, label: "a", now: 1))
    _ = try #require(store.addPrice(symbol: "BTCUSDT", target: 80_000, current: 84_500, label: "b", now: 2))
    let line = Drawing(id: "d1", kind: .hline, points: [DrawPoint(t: 1_000, p: 83_000)])
    _ = try #require(store.add(drawing: line, symbol: "BTCUSDT", now: 3))
    _ = try #require(store.addPrice(symbol: "ETHUSDT", target: 5_000, current: 4_000, label: "e", now: 4))
    return store
  }

  @Test("这只置顶：组名 + 价格 / 画线两小节，行里不写品种；其余品种照总表，第一段不再顶格")
  func pinnedFirst() throws {
    let store = try seeded()
    #expect(shape(store.pinnedRows(symbol: "BTCUSDT")) == [
      "PIN BTCUSDT",
      "K price 2 true",
      "R false true false",
      "R false false false",
      "K drawing 1 false",
      "R false false true",
      "T price false",
      "H ETHUSDT 1",
      "R false false true",
    ])
  }

  @Test("这只一条都没有：置顶那组只有一行「暂无提醒」")
  func pinnedEmpty() throws {
    let store = try seeded()
    let rows = shape(store.pinnedRows(symbol: "SOLUSDT"))
    #expect(Array(rows.prefix(2)) == ["PIN SOLUSDT", "EMPTY"])
    #expect(rows.contains("H BTCUSDT 2") && rows.contains("H ETHUSDT 1"))
  }

  @Test("置顶那一列按品种缓存：同一只不重排，存档变了或换了品种才再排")
  func pinnedCache() throws {
    let store = try seeded()
    _ = store.pinnedRows(symbol: "BTCUSDT")
    _ = store.pinnedRows(symbol: "BTCUSDT")
    #expect(store.pinnedRowBuilds == 1)
    _ = store.pinnedRows(symbol: "ETHUSDT")
    #expect(store.pinnedRowBuilds == 2)
    let eth = try #require(store.all.first { InstrumentID($0.symbol).symbol == "ETHUSDT" })
    store.remove(id: eth.id)
    #expect(shape(store.pinnedRows(symbol: "ETHUSDT")).prefix(2) == ["PIN ETHUSDT", "EMPTY"])
    #expect(store.pinnedRowBuilds == 3)
  }

  @Test("铃角标：这只还没触发的价格 / 画线条数，和创建页「当前提醒」同一口径")
  func pendingCount() throws {
    let store = try seeded()
    #expect(store.pendingCount(symbol: "BTCUSDT") == 3)
    #expect(store.pendingCount(symbol: "ETHUSDT") == 1)
    #expect(store.pendingCount(symbol: "SOLUSDT") == 0)
    #expect(store.pendingCount(symbol: "BTCUSDT") == AlertRecordText.records(store.all, symbol: "BTCUSDT").count)
    let first = try #require(store.all.first { InstrumentID($0.symbol).symbol == "BTCUSDT" })
    store.remove(id: first.id)
    #expect(store.pendingCount(symbol: "BTCUSDT") == 2)
  }
}
