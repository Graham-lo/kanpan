import Testing
import Foundation
import KanpanCore
import KanpanData
@testable import KanpanSettings

/// A6.11：清缓存清的是 `KanpanData.Paths` 指的那几处，不是另拼一套目录。
@Suite("清缓存")
struct MarketCacheTests {

  /// 造一个临时沙盒，塞进快照 / 品种表 / 两天 OI 切片。
  private func seed() throws -> (Paths, URL) {
    let root = URL(fileURLWithPath: NSTemporaryDirectory())
      .appendingPathComponent("kanpan-cache-test-\(UUID().uuidString)", isDirectory: true)
    let paths = Paths(root: root)
    try paths.ensureRoot()
    try Data(repeating: 7, count: 4096).write(to: paths.snapshot)
    try Data(repeating: 8, count: 2048).write(to: paths.exchangeInfo)
    let day = paths.oiDay(symbol: "BTCUSDT", day: "2026-09-14")
    try paths.ensure(day.deletingLastPathComponent())
    try Data(repeating: 9, count: 1024).write(to: day)
    return (paths, root)
  }

  @Test("量出来的是那三处，分三笔报")
  func 量() async throws {
    let (paths, root) = try seed()
    defer { try? FileManager.default.removeItem(at: root) }

    let u = await DiskMarketCache(paths: paths).usage()
    #expect(u.available)
    #expect(u.snapshotBytes >= 4096)
    #expect(u.catalogBytes >= 2048)
    #expect(u.oiBytes >= 1024)
    #expect(u.marketBytes == u.snapshotBytes + u.catalogBytes)
    #expect(u.totalBytes == u.marketBytes + u.oiBytes)
  }

  /// 随人走的那几份的真身：`Application Support/kanpan/accounts/<档案>/…`。
  /// 目录名用的是和 `AccountFiles.profileID` 逐字相同的那套 id（`u-…` / `local/…`）。
  ///
  /// 同时**故意**往缓存根下也扔一份同名的。那几份守的是「逐个点名、别删根」：
  /// 哪天有人图省事把 `clear()` 改成删 `paths.root`，缓存根下这几份先红。
  private func seedPersonal(_ paths: Paths) throws -> (accounts: URL, files: [URL]) {
    let fm = FileManager.default
    let accounts = URL(fileURLWithPath: NSTemporaryDirectory())
      .appendingPathComponent("kanpan-accounts-test-\(UUID().uuidString)", isDirectory: true)
    var files: [URL] = []
    // prefs=偏好与图表布局，symbols=自选与分类，draws=画线，search=搜索历史。
    let 随人走 = ["prefs.json", "symbols.json", "draws.json", "search.json", "sync.json"]
    for owner in ["u-3f2a", "local/9c81"] {
      var dir = accounts
      for part in owner.split(separator: "/") {
        dir = dir.appendingPathComponent(String(part), isDirectory: true)
      }
      try fm.createDirectory(at: dir, withIntermediateDirectories: true)
      for name in 随人走 {
        let url = dir.appendingPathComponent(name)
        try Data(repeating: 1, count: 128).write(to: url)
        files.append(url)
      }
    }
    for name in 随人走 {
      let url = paths.root.appendingPathComponent(name)
      try Data(repeating: 1, count: 128).write(to: url)
      files.append(url)
    }
    return (accounts, files)
  }

  /// 「内容随当前账号派生」的那几份缓存：两个身份各一套报价 / 开盘价，外加板块历史。
  /// 它们都是**没了还能原样取回来**的，所以归清缓存管。
  private func seedDerived(_ paths: Paths) throws -> [URL] {
    let fm = FileManager.default
    var urls: [URL] = []
    for id in ["u-3f2a", "local/9c81"] {
      let p = Paths(root: paths.root, profile: id)
      try fm.createDirectory(at: p.profileRoot, withIntermediateDirectories: true)
      try Data(repeating: 2, count: 2048).write(to: p.quotes)
      try Data(repeating: 3, count: 1024).write(to: p.opens)
      urls += [p.quotes, p.opens]
    }
    try Data(repeating: 4, count: 512).write(to: paths.sectorHistory)
    urls.append(paths.sectorHistory)
    return urls
  }

  @Test("清完三处都没了，数字归零；沙盒里别的东西不动")
  func 清() async throws {
    let (paths, root) = try seed()
    defer { try? FileManager.default.removeItem(at: root) }
    let personal = try seedPersonal(paths)
    defer { try? FileManager.default.removeItem(at: personal.accounts) }

    let cache = DiskMarketCache(paths: paths)
    await cache.clear()

    let fm = FileManager.default
    #expect(!fm.fileExists(atPath: paths.snapshot.path))
    #expect(!fm.fileExists(atPath: paths.exchangeInfo.path))
    #expect(!fm.fileExists(atPath: paths.oi.path))

    // 偏好、图表布局、自选与分类、画线、搜索历史：清缓存一个都不许碰。
    // 它们没了就真没了，唯一合法的消失方式是用户卸载 app。
    for url in personal.files {
      #expect(fm.fileExists(atPath: url.path), "\(url.lastPathComponent) 被清缓存带走了")
    }
    #expect(fm.fileExists(atPath: personal.accounts.path), "整个账号目录被清缓存带走了")

    let after = await cache.usage()
    #expect(after.totalBytes == 0)
  }

  /// 洞一 + 洞二的验收：这两样以前一个躲开了清缓存（自己拼 `Library/Caches` 根），
  /// 一个躲开了「不串号」（两个人共用一份 `quotes.json`）。
  /// 换过行情源的人盘上会多一棵 `sources/<行情源>/`：那个源自己的品种表与启动快照。
  /// 品种表是公开数据、没了重取就有，按判据归清缓存管；它以前躲过了，因为
  /// `clear()` 逐个点名时压根没这个名字（目录是调用方手拼的）。
  private func seedSource(_ paths: Paths) throws -> [URL] {
    let okx = paths.source("okx")
    try okx.ensureRoot()
    try Data(repeating: 6, count: 3072).write(to: okx.exchangeInfo)
    try okx.ensure(okx.series)
    let bar = okx.series.appendingPathComponent("BTCUSDT-1h.kbar")
    try Data(repeating: 6, count: 1024).write(to: bar)
    return [okx.exchangeInfo, bar]
  }

  @Test("清完之后，按行情源分的那份品种表也没了")
  func 清掉行情源子树() async throws {
    let (paths, root) = try seed()
    defer { try? FileManager.default.removeItem(at: root) }
    let personal = try seedPersonal(paths)
    defer { try? FileManager.default.removeItem(at: personal.accounts) }
    let 子树 = try seedSource(paths)
    let fm = FileManager.default
    for url in 子树 { #expect(fm.fileExists(atPath: url.path)) }

    await DiskMarketCache(paths: paths).clear()

    for url in 子树 {
      #expect(!fm.fileExists(atPath: url.path), "\(url.path) 躲过了清缓存")
    }
    // 整棵没了，不是只删了其中一个行情源。
    #expect(!fm.fileExists(atPath: paths.sources.path))
    // 照旧：账号那两棵（`u-…` 与 `local/…`）一个文件都不许少。
    for url in personal.files {
      #expect(fm.fileExists(atPath: url.path), "\(url.lastPathComponent) 被清缓存带走了")
    }
    #expect(fm.fileExists(atPath: personal.accounts.path), "整个账号目录被清缓存带走了")
  }

  @Test("按行情源分的那份品种表算进「行情缓存」那个数")
  func 量行情源子树() async throws {
    let (paths, root) = try seed()
    defer { try? FileManager.default.removeItem(at: root) }
    _ = try seedSource(paths)

    let u = await DiskMarketCache(paths: paths).usage()
    // 根上那份品种表 2048 + 子树里的 3072 + 1024，一笔都不能漏。
    #expect(u.catalogBytes >= 2048 + 3072 + 1024)
    #expect(u.marketBytes == u.snapshotBytes + u.catalogBytes + u.derivedBytes)
  }

  @Test("清完之后，板块历史和分身份的报价都没了")
  func 清掉派生那几份() async throws {
    let (paths, root) = try seed()
    defer { try? FileManager.default.removeItem(at: root) }
    let derived = try seedDerived(paths)
    let fm = FileManager.default
    for url in derived { #expect(fm.fileExists(atPath: url.path)) }

    await DiskMarketCache(paths: paths).clear()

    for url in derived {
      #expect(!fm.fileExists(atPath: url.path), "\(url.path) 躲过了清缓存")
    }
    // 按身份分的那一层整棵没了，不是只删了当前这个人的那一份。
    #expect(!fm.fileExists(atPath: paths.profiles.path))
    #expect(!fm.fileExists(atPath: paths.sectorHistory.path))
  }

  @Test("分身份的报价和板块历史都算进「行情缓存」那个数")
  func 量派生那几份() async throws {
    let (paths, root) = try seed()
    defer { try? FileManager.default.removeItem(at: root) }
    _ = try seedDerived(paths)

    let u = await DiskMarketCache(paths: paths).usage()
    #expect(u.derivedBytes >= 2 * (2048 + 1024) + 512)
    #expect(u.marketBytes == u.snapshotBytes + u.catalogBytes + u.derivedBytes)
  }

  /// 哨兵与脏标识住在 `UserDefaults`，比归档那一层还顽固：它们是用来分辨
  /// 「第一次装」和「缓存被清了」的，清缓存要是把它们抹了，这个分辨就没了。
  @Test("清缓存不碰 UserDefaults 里那几格")
  @MainActor
  func 不碰哨兵() async throws {
    let (paths, root) = try seed()
    defer { try? FileManager.default.removeItem(at: root) }

    // 自选（`SymbolPrefs.defaultsKey`）与搜索历史（`SearchHistory.defaultsKey`）
    // 在 app 那一层，这个测试包看不见它们的符号，键名照抄并注明出处：
    // `Kanpan/Kanpan/Symbols/SymbolPrefs.swift:311`、`.../SearchHistory.swift:40`。
    let keys = [PrefsCodec.key, SettingsStamp.storageKey, SettingsSentinel.storageKey,
                "kanpan.symbols.v1", "kanpan.symbols.v2", "kanpan.searchHistory.v1"]
    let defaults = UserDefaults.standard
    let 原样 = keys.map { defaults.object(forKey: $0) }
    defer {
      for (key, old) in zip(keys, 原样) {
        if let old { defaults.set(old, forKey: key) } else { defaults.removeObject(forKey: key) }
      }
    }
    for key in keys { defaults.set(Data(repeating: 5, count: 16), forKey: key) }

    let store = PrefsStore(storage: InMemoryPrefsStorage(), cache: DiskMarketCache(paths: paths))
    await store.clearCache()          // 走的是设置页那个按钮真正调的那条路

    for key in keys {
      #expect(defaults.object(forKey: key) != nil, "\(key) 被清缓存抹了")
    }
  }

  /// 规矩三：两类东西不共用一棵目录。共用了，「清一个」就成了「清两个」。
  @Test("行情缓存那棵树和账号那棵树互不包含")
  func 两棵树分开() {
    let cache = Paths.caches().root.standardizedFileURL.path
    // 账号目录的根，见 `Kanpan/Kanpan/Account/AppAccountBridge.swift:53`。
    let accounts = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
      .appendingPathComponent("kanpan/accounts").standardizedFileURL.path
    #expect(!cache.hasPrefix(accounts + "/"))
    #expect(!accounts.hasPrefix(cache + "/"))
    #expect(cache != accounts)
    // 分身份那一层是缓存这边的事，不许跑到账号目录底下去。
    let mine = Paths.caches(profile: "u-3f2a").quotes.standardizedFileURL.path
    #expect(mine.hasPrefix(cache + "/"))
    #expect(!mine.hasPrefix(accounts + "/"))
  }

  @Test("目录本来就不存在 → 量出 0，清也不报错")
  func 空沙盒() async {
    let root = URL(fileURLWithPath: NSTemporaryDirectory())
      .appendingPathComponent("kanpan-cache-empty-\(UUID().uuidString)", isDirectory: true)
    let cache = DiskMarketCache(paths: Paths(root: root))
    await cache.clear()
    let u = await cache.usage()
    #expect(u.available)
    #expect(u.totalBytes == 0)
  }

  /// 清完**不**说话：数字当场归零就是回执，再补一句「已清缓存」是只报成功、
  /// 没有下一步可做的提示，2026-09-21 一并删掉了。
  @Test("store 清完会重新量，而且不多说一句")
  @MainActor
  func 走store() async throws {
    let (paths, root) = try seed()
    defer { try? FileManager.default.removeItem(at: root) }

    let store = PrefsStore(storage: InMemoryPrefsStorage(), cache: DiskMarketCache(paths: paths))
    #expect(store.cacheUsage == nil)
    await store.refreshCacheUsage()
    #expect((store.cacheUsage?.totalBytes ?? 0) > 0)
    await store.clearCache()
    #expect(store.cacheUsage?.totalBytes == 0)
    #expect(store.notice == nil)
  }

  /// P2.7：设置页那颗「清除」现在走 `clearCacheLater`——先说「已清理存储空间 · 撤销」，
  /// 窗口过了才真清；窗口里点撤销，一个字节都不动。
  @Test("清缓存五秒内点撤销，缓存原样还在")
  @MainActor
  func 撤销清缓存() async throws {
    let (paths, root) = try seed()
    defer { try? FileManager.default.removeItem(at: root) }

    let store = PrefsStore(storage: InMemoryPrefsStorage(), cache: DiskMarketCache(paths: paths))
    store.undoWindow = .milliseconds(80)
    await store.refreshCacheUsage()
    let before = store.cacheUsage?.totalBytes ?? 0
    #expect(before > 0)

    store.clearCacheLater()
    #expect(store.notice == "已清理存储空间")
    let undo = try #require(store.noticeUndo)
    undo()
    try await Task.sleep(for: .milliseconds(300))
    await store.refreshCacheUsage()
    #expect(store.cacheUsage?.totalBytes == before, "点了撤销缓存还是被清了")
  }

  @Test("清缓存不撤销，窗口一过就真清")
  @MainActor
  func 窗口过了才清() async throws {
    let (paths, root) = try seed()
    defer { try? FileManager.default.removeItem(at: root) }

    let store = PrefsStore(storage: InMemoryPrefsStorage(), cache: DiskMarketCache(paths: paths))
    store.undoWindow = .milliseconds(80)
    await store.refreshCacheUsage()
    #expect((store.cacheUsage?.totalBytes ?? 0) > 0)

    store.clearCacheLater()
    await store.refreshCacheUsage()
    #expect((store.cacheUsage?.totalBytes ?? 0) > 0, "撤销窗口还没过就清了")
    for _ in 0..<100 where store.cacheUsage?.totalBytes != 0 {
      try await Task.sleep(for: .milliseconds(20))
    }
    #expect(store.cacheUsage?.totalBytes == 0)
  }

  @Test("数据层没接上就如实说没接上，不报假的 0")
  func 占位() async {
    let u = await UnavailableMarketCache().usage()
    #expect(!u.available)
    #expect(u.totalBytes == 0)
  }

  @Test("体积文案")
  func 文案() {
    #expect(MarketCacheUsage.display(0) == "0 KB")
    #expect(MarketCacheUsage.display(312 * 1024) == "312 KB")
    #expect(MarketCacheUsage.display(1024 * 1024 + 1024 * 200) == "1.2 MB")
  }
}
