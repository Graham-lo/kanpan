import Testing
import Foundation
@testable import KanpanSettings

/// 什么东西放在哪一层，以及**谁可以被清空**。
///
/// 2026-09-19 用户定的判据，一句话：**这份东西没了以后还能原样拿回来吗？**
///
/// > 「体验类一律不能主动清空缓存，除非删除 app，必要的数据不能主动给清空操作，
/// > 只有非必要不影响项目运行的才可以清空。」
///
/// - 能再取回来的（K 线快照、品种表、报价、开盘价、OI、板块历史）→ 可清，
///   放 `Library/Caches/kanpan/`，系统缺空间自己清掉也无所谓。
/// - 拿不回来的（偏好、图表布局、自选与分类、画线、搜索历史，以及这一轮加的
///   脏标识与哨兵）→ **不许有任何清空入口**，唯一合法的消失方式是卸载 app。
///   真身在 `Application Support/kanpan/accounts/…`，哨兵在 `UserDefaults`。
///
/// 这条规矩原先只写在 `AccountFiles.swift:3` 的注释里，没有任何测试守着——
/// 注释拦不住下一个人顺手写一行 `removeItem`。这个套件就是那道闸：
/// 新的清理路径必须来这儿报到，说清自己清的是哪一类。
@Suite("存放分层")
struct StorageLayeringTests {

  /// 仓库根。测试文件在 `<root>/Kanpan/Settings/Tests/KanpanSettingsTests/` 底下。
  static let root: URL = {
    var url = URL(fileURLWithPath: #filePath)
    for _ in 0..<5 { url.deleteLastPathComponent() }
    return url
  }()

  /// 生产代码（不含测试）。
  static let sources: [URL] = {
    let trees = ["Kanpan/Kanpan", "KanpanData/Sources", "KanpanAccount/Sources",
                 "KanpanChart/Sources", "KanpanCore/Sources"]
    var files: [URL] = []
    for tree in trees {
      let base = root.appendingPathComponent(tree)
      guard let walk = FileManager.default.enumerator(at: base, includingPropertiesForKeys: nil) else { continue }
      for case let url as URL in walk where url.pathExtension == "swift" { files.append(url) }
    }
    return files
  }()

  static func text(_ url: URL) -> String { (try? String(contentsOf: url, encoding: .utf8)) ?? "" }
  static func name(_ url: URL) -> String { url.lastPathComponent }

  /// 允许出现 `removeItem` 的地方，以及它清的是什么。
  ///
  /// **只能是「没了还能原样拿回来」的东西。** 想往这张表上加一行之前，先回答那句判据。
  static let mayDelete: [String: String] = [
    "MarketCache.swift": "设置里的「清缓存」：K 线快照 / 品种表 / OI，全都能重新拉",
    "SeriesStore.swift": "K 线快照自己的淘汰与上限",
    "Snapshot.swift": "旧版单份快照，只剩清理",
    "QuoteSnapshot.swift": "自选报价快照，下一帧行情就能补回来",
    "BaselineSnapshot.swift": "当日开盘价快照，重新拉一次就有",
    "OIStore.swift": "OI 归档的按天淘汰与 20 MB 上限",
    "FrameReportStore.swift": "自己的帧率报告，纯诊断",
    "DiagnosticsStore.swift": "自己的诊断日志，纯诊断",
    // M4：板块历史搬进 `Paths` 那棵树之后，顺手把老位置（直接挂在 Caches 根上的
    // 那一份）删掉。丢的只是一次日线收盘，进板块页重新取一趟就回来了。
    "SectorHistoryFeed.swift": "老位置上那份板块历史，进页重新取一趟就有",
    // 这一条不是「清理路径」：它是存储适配器把某个键置空时顺手删掉那个键的文件，
    // 一个键一个文件，调用方是 `PersonalFileStorage.setPrefsData(nil, forKey:)`。
    // 它删不到整个账号目录，也没有任何 UI 入口通向它。
    "PersonalFileStorage.swift": "一个键置空时删掉那个键自己的文件，不是清理入口",
    // 861cf81：信过了留存期从收件箱滤掉之后，它那张按需拉下来的截图没人认领。还在收件箱里的信
    // 的图一张不动；删掉的只是已经没人会再打开的本地截图缓存。
    "ShareInbox.swift": "已经不在收件箱里的信的截图缓存，只删 share-shots/ 下的 id.jpg",
    // 审查 22：同步存档拆成 `sync/head.json` + 分片之后，提交是「先写新分片、再原子换 head」。
    // 删的只有三样，都不是数据本身：head 已经不再引用的旧分片（内容在新分片里）、
    // 提交失败时自己刚写的没人引用的分片、以及内容已经进了新 head 的老 `sync-v1.json`。
    // 清扫只在 `sync/` 这一个目录里、只删 head 没引用的文件，删不到账号目录的其他东西。
    "SyncArchiveShards.swift": "同步存档换版后被取代的旧分片、提交失败的孤儿分片、已迁移的老整份存档",
    // 主力订单流按品种的大单小日志（Caches/kanpan/orderflow/<品种>.json，一只几十 KB）。
    // 只删超过 24 小时的（图上本来就只画 24 小时内的单）和目录里认不出的东西；
    // 丢了也只是图上少画几条已经结束的单，打开指标重新订簿就接着记。
    "OrderFlowFeed.swift": "主力订单流超过 24 小时的大单小日志与目录里认不出的文件，纯行情缓存",
  ]

  @Test("会删文件的地方，删的必须都是能再取回来的东西")
  func onlyRefetchableThingsGetDeleted() {
    for file in Self.sources where Self.text(file).contains("removeItem(") {
      #expect(Self.mayDelete[Self.name(file)] != nil,
              "\(Self.name(file)) 新出现了删除文件的代码：先回答「这份东西没了还能原样拿回来吗」，能就把它记进 mayDelete 说清清的是什么，不能就别删")
    }
  }

  @Test("任何清理路径都不许删到账号目录")
  func noCleanupPathTouchesTheAccountDirectory() {
    for file in Self.sources {
      let body = Self.text(file)
      guard body.contains("removeItem(") else { continue }
      #expect(!body.contains("AccountFiles.directory") && !body.contains("accountsRoot"),
              "\(Self.name(file)) 同时碰了账号目录和删除：体验类真身就在那底下，「为了省事把两类放在同一棵目录下再整棵删」正是这条要防的")
    }
  }

  @Test("哨兵那一格不许被整片抹掉")
  func theSentinelSurvivesEveryCleanup() {
    for file in Self.sources {
      #expect(!Self.text(file).contains("removePersistentDomain"),
              "\(Self.name(file)) 整片抹了 UserDefaults：哨兵和首帧镜像都在那一层，抹掉之后「第一次装」和「缓存被清了」就再也分不出来")
    }
    // 两格键名各自属于哪一层，写死在这儿，改了就得来这儿改。
    #expect(SettingsSentinel.storageKey == "kanpan.settings.sentinel.v1")
    #expect(SettingsStamp.storageKey == "kanpan.settings.stamp.v1")
  }

  @Test("Caches 那棵树上只放能再取回来的行情数据")
  func cachesHoldsOnlyMarketData() {
    let paths = Self.root.appendingPathComponent("KanpanData/Sources/KanpanData/Store/Paths.swift")
    let body = Self.text(paths)
    #expect(!body.isEmpty, "找不到 Paths.swift")
    // M4 加进来的两样也都是「没了还能原样取回来」：板块历史重新拉一趟就有；
    // `profiles/<档案>/` 底下那两份（报价、开盘价）分身份只为了不串号，
    // 仍然是缓存，照样归清缓存管。
    // 板块页的全市场 24h 行情（`sector-quotes.json`）同理：它只是给板块页第一帧垫底的
    // 上一份行情，下一次取数就整份覆盖。
    let refetchable: Set<String> = ["kanpan", "tests", "last.kbar", "series", "exchangeInfo.json",
                                    "quotes.json", "opens.json", "oi", "sector-history.json",
                                    "sector-quotes.json"]
    let pattern = try! NSRegularExpression(pattern: #"appendingPathComponent\("([^"]+)""#)
    for match in pattern.matches(in: body, range: NSRange(body.startIndex..., in: body)) {
      guard let range = Range(match.range(at: 1), in: body) else { continue }
      let component = String(body[range])
      // OI 的切片名里带品种 / 日期 / 周期的插值，按后缀认。
      if component.hasSuffix(".oi") { continue }
      #expect(refetchable.contains(component),
              "Caches 下多了 \(component)：这一层系统随时可以清，随人走的东西一个字节都不许放")
    }
  }

  /// 真身和脏标识同在账号目录里，但**不许落在同一个文件上**。
  ///
  /// 2026-09-19 真出过这一刀：`PersonalFileStorage` 的 `prefsData/setPrefsData`
  /// 压根不看 `key`，一律读写 `prefs.json`。于是 `PrefsStore.persist` 里
  /// 「先写值、再写脏标识」这两步落到同一个文件上，**后一步把前一步整份盖掉**，
  /// 冷启动读回来解不出 `Prefs`，整份设置退出厂值。登录态下用户捏小了图、
  /// 立刻杀掉 app，回来看到的就是出厂的 4pt。
  ///
  /// 它在 app target 里（`Kanpan/Kanpan/Account/`），没有跑道能真的 new 一个出来，
  /// 所以这条按源码守：那个适配器必须按键分文件，而且必须点名认得脏标识那个键。
  @Test("账号目录里一个键一个文件，脏标识不许压在偏好上")
  func thePersonalFileStorageKeepsOneFilePerKey() {
    let url = Self.root.appendingPathComponent("Kanpan/Kanpan/Account/PersonalFileStorage.swift")
    let body = Self.text(url)
    #expect(!body.isEmpty, "找不到 PersonalFileStorage.swift")
    #expect(body.contains("SettingsStamp.storageKey"),
            "PersonalFileStorage 不认得脏标识那个键：它会和偏好落到同一个文件上，后写的那份把前一份整份盖掉")
    #expect(!body.contains(#"func setPrefsData(_ data: Data?, forKey key: String) { write(data, name: "prefs.json") }"#),
            "setPrefsData 又写死成 prefs.json 了：键被忽略，脏标识一写就把整份偏好盖掉")
  }

  @Test("体验类的键一个都不许出现在行情缓存那一层")
  func experienceKeysNeverReachTheCacheLayer() {
    let keys = [PrefsCodec.key, SettingsStamp.storageKey, SettingsSentinel.storageKey]
    for file in Self.sources where file.path.contains("KanpanData/Sources") {
      let body = Self.text(file)
      for key in keys {
        #expect(!body.contains(key), "\(Self.name(file)) 提到了 \(key)：体验类不该落在行情缓存那一层")
      }
    }
  }
}
