import Foundation
import Testing

@testable import KanpanSymbols

/// A5.8 自选（加 / 删 / 拖排序 / 杀 app 重开保留）、A5.9 最近（倒序、最多 10）。
@Suite("自选与最近")
struct SymbolPrefsTests {

  // ---------------------------------------------------------------- 自选

  @Test("加自选追加到末尾，再点一次移除")
  func toggle() {
    var p = SymbolPrefs()
    p.toggleFavorite("binance/usd_m/BTCUSDT")
    p.toggleFavorite("binance/usd_m/ETHUSDT")
    #expect(p.favorites == ["binance/usd_m/BTCUSDT", "binance/usd_m/ETHUSDT"])
    #expect(p.isFavorite("binance/usd_m/BTCUSDT"))

    p.toggleFavorite("binance/usd_m/BTCUSDT")
    #expect(p.favorites == ["binance/usd_m/ETHUSDT"])
    #expect(!p.isFavorite("binance/usd_m/BTCUSDT"))

    // 再加回来是排到末尾，不是回原位（原型 push 的口径）
    p.toggleFavorite("binance/usd_m/BTCUSDT")
    #expect(p.favorites == ["binance/usd_m/ETHUSDT", "binance/usd_m/BTCUSDT"])
  }

  @Test("重复加不会多出一条，大小写不敏感")
  func dedupe() {
    var p = SymbolPrefs()
    p.addFavorite("binance/usd_m/BTCUSDT")
    p.addFavorite("btcusdt")
    p.addFavorite(" BTCUSDT ")
    #expect(p.favorites == ["binance/usd_m/BTCUSDT"])
    p.removeFavorite("btcusdt")
    #expect(p.favorites.isEmpty)
    // 空字符串进不去
    p.addFavorite("   ")
    #expect(p.favorites.isEmpty)
  }

  @Test("构造时就把老存档洗干净：大写、去空、去重、保序")
  func cleanOnInit() {
    let p = SymbolPrefs(favorites: ["btcusdt", "binance/usd_m/BTCUSDT", "", "  ", "ethusdt"],
                        recents: ["solusdt", "binance/usd_m/SOLUSDT"])
    #expect(p.favorites == ["binance/usd_m/BTCUSDT", "binance/usd_m/ETHUSDT"])
    #expect(p.recents == ["binance/usd_m/SOLUSDT"])
  }

  @Test("拖排序：onMove 口径")
  func moveByOffsets() {
    var p = SymbolPrefs(favorites: ["binance/usd_m/A", "binance/usd_m/B", "binance/usd_m/C", "binance/usd_m/D"])
    p.moveFavorites(from: IndexSet(integer: 0), to: 3)   // A 挪到 C 后面
    #expect(p.favorites == ["binance/usd_m/B", "binance/usd_m/C", "binance/usd_m/A", "binance/usd_m/D"])
    p.moveFavorites(from: IndexSet(integer: 3), to: 0)   // D 挪到最前
    #expect(p.favorites == ["binance/usd_m/D", "binance/usd_m/B", "binance/usd_m/C", "binance/usd_m/A"])
  }

  @Test("拖排序：落在某一行上")
  func moveOnto() {
    var p = SymbolPrefs(favorites: ["binance/usd_m/A", "binance/usd_m/B", "binance/usd_m/C", "binance/usd_m/D"])
    p.moveFavorite("binance/usd_m/D", onto: "binance/usd_m/B")      // 往上拖，插到 B 的位置
    #expect(p.favorites == ["binance/usd_m/A", "binance/usd_m/D", "binance/usd_m/B", "binance/usd_m/C"])
    p.moveFavorite("binance/usd_m/A", onto: "binance/usd_m/C")      // 往下拖，落到 C 之后
    #expect(p.favorites == ["binance/usd_m/D", "binance/usd_m/B", "binance/usd_m/C", "binance/usd_m/A"])
    // 拖到自己身上、拖不存在的，都不动
    p.moveFavorite("binance/usd_m/A", onto: "binance/usd_m/A")
    p.moveFavorite("ZZZ", onto: "binance/usd_m/A")
    p.moveFavorite("binance/usd_m/A", onto: "ZZZ")
    #expect(p.favorites == ["binance/usd_m/D", "binance/usd_m/B", "binance/usd_m/C", "binance/usd_m/A"])
  }

  // ---------------------------------------------------------------- 最近

  @Test("最近按时间倒序，最新的在最前")
  func recentOrder() {
    var p = SymbolPrefs()
    p.visit("binance/usd_m/BTCUSDT")
    p.visit("binance/usd_m/ETHUSDT")
    p.visit("binance/usd_m/SOLUSDT")
    #expect(p.recents == ["binance/usd_m/SOLUSDT", "binance/usd_m/ETHUSDT", "binance/usd_m/BTCUSDT"])
  }

  @Test("再打开一次已在列表里的，提到队首而不是多一条")
  func recentDedupe() {
    var p = SymbolPrefs()
    for s in ["binance/usd_m/A", "binance/usd_m/B", "binance/usd_m/C"] { p.visit(s) }
    p.visit("binance/usd_m/A")
    #expect(p.recents == ["binance/usd_m/A", "binance/usd_m/C", "binance/usd_m/B"])
    #expect(p.recents.count == 3)
    p.visit("a")
    #expect(p.recents == ["binance/usd_m/A", "binance/usd_m/C", "binance/usd_m/B"])
  }

  @Test("容量 10，第 11 个把最旧的挤掉")
  func recentLimit() {
    #expect(SymbolPrefs.recentLimit == 10)
    var p = SymbolPrefs()
    for i in 1 ... 12 { p.visit("S\(i)USDT") }
    #expect(p.recents.count == 10)
    #expect(p.recents.first == "binance/usd_m/S12USDT")
    #expect(p.recents.last == "binance/usd_m/S3USDT")          // S1 / S2 被淘汰
    #expect(!p.recents.contains("binance/usd_m/S1USDT"))
    #expect(!p.recents.contains("binance/usd_m/S2USDT"))
  }

  @Test("老存档里塞了 20 条，读进来只留 10 条")
  func recentTruncatedOnInit() {
    let p = SymbolPrefs(recents: (1 ... 20).map { "S\($0)USDT" })
    #expect(p.recents.count == 10)
    #expect(p.recents.first == "binance/usd_m/S1USDT")
  }

  // ---------------------------------------------------------------- 落盘

  @Test("写进去再读出来，一模一样（杀 app 重开保留）")
  @MainActor
  func roundTrip() {
    let storage = MemoryPrefsStorage()
    let store = SymbolPrefsStore(storage: storage, key: "test.key")
    #expect(store.load() == SymbolPrefs())      // 空存档给空值，不抛

    var p = SymbolPrefs()
    p.addFavorite("binance/usd_m/BTCUSDT")
    p.addFavorite("binance/usd_m/ETHUSDT")
    p.moveFavorite("binance/usd_m/ETHUSDT", onto: "binance/usd_m/BTCUSDT")
    p.visit("binance/usd_m/SOLUSDT")
    p.visit("binance/usd_m/DOGEUSDT")
    store.save(p)

    // 新开一个 store（模拟重开 app），拿到同一份
    let reopened = SymbolPrefsStore(storage: storage, key: "test.key").load()
    #expect(reopened == p)
    #expect(reopened.favorites == ["binance/usd_m/ETHUSDT", "binance/usd_m/BTCUSDT"])
    #expect(reopened.recents == ["binance/usd_m/DOGEUSDT", "binance/usd_m/SOLUSDT"])
  }

  @Test("存档键就是 kanpan.symbols.v2，落的是 JSON")
  @MainActor
  func defaultsKey() throws {
    #expect(SymbolPrefsStore.defaultsKey == "kanpan.symbols.v2")
    let storage = MemoryPrefsStorage()
    let store = SymbolPrefsStore(storage: storage)
    store.save(SymbolPrefs(favorites: ["binance/usd_m/BTCUSDT"]))
    let blob = try #require(storage.raw["kanpan.symbols.v2"])
    let text = try #require(String(data: blob, encoding: .utf8))
    #expect(text.contains("BTCUSDT"))
    #expect(text.contains("favorites"))
  }

  /// `load()` 是「没有档案也得开得起来」那条路（`SymbolPickerModel.init` 的占位档案）。
  /// 要回写磁盘的调用方走 `read()`，它对同一份坏档是**抛**的——见
  /// `SymbolPrefsDurabilityTests`，那才是不让空档盖掉自选的那道闸。
  @Test("存档坏了：load() 当空处理不崩，read() 照实抛")
  @MainActor
  func brokenArchive() {
    let storage = MemoryPrefsStorage(["k": Data("这不是 JSON".utf8)])
    #expect(SymbolPrefsStore(storage: storage, key: "k").load() == SymbolPrefs())
    #expect(throws: SymbolPrefsStore.StoreError.unreadable) {
      try SymbolPrefsStore(storage: storage, key: "k").read()
    }
  }

  @Test("清空存档")
  @MainActor
  func clear() {
    let storage = MemoryPrefsStorage()
    let store = SymbolPrefsStore(storage: storage, key: "k")
    store.save(SymbolPrefs(favorites: ["binance/usd_m/BTCUSDT"]))
    store.clear()
    #expect(store.load() == SymbolPrefs())
  }
}

// ============================================================ 常看（画线工作台换品种用）

@Suite("常看")
struct FrequentTests {
  private let day: Double = 86_400
  private let t0: Double = 1_700_000_000

  /// 「常看」问的是**次数**，不是最后一次什么时候——这正是它不能用 `recents` 顶替的原因。
  @Test func countsBeatRecency() {
    var p = SymbolPrefs()
    for i in 0 ..< 5 { p.noteDwell("binance/usd_m/BTCUSDT", now: t0 + Double(i) * day) }
    p.noteDwell("binance/usd_m/DOGEUSDT", now: t0 + 5 * day)
    p.visit("binance/usd_m/DOGEUSDT")
    #expect(p.recents.first == "binance/usd_m/DOGEUSDT")
    #expect(p.frequent(now: t0 + 5 * day).first == "binance/usd_m/BTCUSDT")
  }

  /// 半衰期：同样看过 4 次，两个月没碰的那个要让位给这周天天看的。
  @Test func staleScoresDecay() {
    var p = SymbolPrefs()
    for i in 0 ..< 4 { p.noteDwell("binance/usd_m/OLDUSDT", now: t0 + Double(i) * 3_600) }
    let later = t0 + 60 * day
    for i in 0 ..< 3 { p.noteDwell("binance/usd_m/NEWUSDT", now: later + Double(i) * 3_600) }
    #expect(p.frequent(now: later).first == "binance/usd_m/NEWUSDT")
  }

  /// 分数表有上限，超了丢最低的；也不许把空串记进去。
  @Test func capacityAndJunk() {
    var p = SymbolPrefs()
    p.noteDwell("  ", now: t0)
    p.noteDwell("", now: t0)
    #expect(p.viewScores.isEmpty)
    for i in 0 ..< (SymbolPrefs.scoreCapacity + 20) { p.noteDwell("S\(i)USDT", now: t0) }
    #expect(p.viewScores.count <= SymbolPrefs.scoreCapacity)
  }

  /// 时钟倒退（改过系统时间、跨设备同步）时宁可不衰减，也不能把分数**放大**回去。
  @Test func clockGoingBackwardsDoesNotInflate() {
    var p = SymbolPrefs()
    p.noteDwell("binance/usd_m/BTCUSDT", now: t0 + 30 * day)
    let before = p.frequent(now: t0)
    p.noteDwell("binance/usd_m/BTCUSDT", now: t0)
    #expect(before == ["binance/usd_m/BTCUSDT"])
    #expect(p.viewScores["binance/usd_m/BTCUSDT"] == 2)
  }

  /// 存档来回一趟，常看这张表要跟着活下来。
  @Test func roundTrip() {
    var p = SymbolPrefs(favorites: ["binance/usd_m/BTCUSDT"])
    p.noteDwell("binance/usd_m/ETHUSDT", now: t0)
    p.noteDwell("binance/usd_m/ETHUSDT", now: t0 + 60)
    let data = try! JSONEncoder().encode(p)
    let back = try! JSONDecoder().decode(SymbolPrefs.self, from: data)
    #expect((back.viewScores["binance/usd_m/ETHUSDT"] ?? 0) > 1.9)  // 第二次打分前先衰减了 60 秒，所以是 1.99…
    #expect(back.frequent(now: t0 + 120) == ["binance/usd_m/ETHUSDT"])
  }
}
