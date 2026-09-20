import Foundation
import Testing
@testable import KanpanSymbols

// 这一套整体只在 DEBUG 下编译：它钉的是 `SymbolPrefsStore.testSeed`，而那段种子脚手架
// 按 A-07 只存在于 DEBUG（`Kanpan/Symbols/SymbolPrefs.swift` 里的 `#if DEBUG`）——
// Release 包里连这段代码都不该有。末尾那条走 `read()` 的端到端用例也一并圈进来：
// Release 下种子那条分支根本不存在，它会为了错误的理由变绿，留着反而骗人。
#if DEBUG
/// A-07：UI 测试的自选种子只准落在**隔离仓**上。
///
/// 报告里那条组合路径是这样的：`KANPAN_TEST_PROFILE=1` + `KANPAN_TEST_FAVORITES`
/// 让 `read()` 在碰柜子**之前**就把种子返回去，而它不看手上这个柜子是内存仓还是
/// 账号目录里的 `PersonalFileStorage`——于是账号桥挂在真账号目录上时，用户真实的
/// 自选被一串环境变量顶掉，接着还会被 `AppAccountBridge.prepare` 回写进 `symbols.json`。
/// 「种子生效」和「目录隔离生效」由两组互不相干的开关各自决定，正是这条的病根。
@Suite("自选种子的隔离闸", .serialized)
@MainActor
struct SymbolPrefsSeedIsolationTests {
  private static let environment = ["KANPAN_TEST_PROFILE": "1",
                                    "KANPAN_TEST_FAVORITES": "BTCUSDT,ETHUSDT"]

  /// 隔离仓（内存仓、`accounts/tests/<uuid>` 那棵子树）照常灌种子——UI 用例靠它。
  @Test("隔离仓上照常灌种子")
  func seedsIsolatedStore() {
    let seeded = SymbolPrefsStore.testSeed(environment: Self.environment, isolated: true)
    #expect(seeded?.favorites == ["BTCUSDT", "ETHUSDT"])
  }

  /// 真账号档案上一个字都不许灌。
  @Test("不是隔离仓就不给种子")
  func refusesRealProfile() {
    #expect(SymbolPrefsStore.testSeed(environment: Self.environment, isolated: false) == nil)
  }

  /// 不在测试模式里，连隔离仓也不给。
  @Test("没开测试模式就没有种子这回事")
  func refusesOutsideTestMode() {
    #expect(SymbolPrefsStore.testSeed(environment: ["KANPAN_TEST_FAVORITES": "BTCUSDT"], isolated: true) == nil)
  }

  /// 端到端那一半：真账号档案上 `read()` 读回来的必须是**盘上那份**。
  ///
  /// 柜子用的是一个 `isIsolatedForTests == false` 的仓（`PersonalFileStorage` 挂在
  /// 真账号目录上时就是这个答案），环境变量则真的设进本进程——这正是报告里那条
  /// 组合路径的形状。
  @Test("真账号档案上读回来的是他自己的自选，不是种子")
  func readKeepsRealFavorites() throws {
    setenv("KANPAN_TEST_PROFILE", "1", 1)
    setenv("KANPAN_TEST_FAVORITES", "BTCUSDT,ETHUSDT", 1)
    defer { unsetenv("KANPAN_TEST_PROFILE"); unsetenv("KANPAN_TEST_FAVORITES") }
    let storage = RealProfileStorage()
    let store = SymbolPrefsStore(storage: storage)
    store.save(SymbolPrefs(favorites: ["SOLUSDT"]))
    #expect(try store.read().favorites == ["SOLUSDT"])
  }
}

/// 「不是隔离仓」的那种柜子：真账号目录上的 `PersonalFileStorage` 就是这个答案。
private final class RealProfileStorage: SymbolPrefsStorage {
  private var box: [String: Data] = [:]
  var isIsolatedForTests: Bool { false }
  func symbolPrefsData(forKey key: String) -> Data? { box[key] }
  func setSymbolPrefsData(_ data: Data?, forKey key: String) { box[key] = data }
}
#endif
