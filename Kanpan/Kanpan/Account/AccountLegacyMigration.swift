import Foundation
import os
import KanpanCore
import KanpanAccount
import ReviewData

/// 账号桥建起来那一下要做的一次性搬家与清理：老版本放在 `UserDefaults` / 老目录里的
/// 设置、自选、画线、复盘搬进访客目录，再把 `UserDefaults` 里那几份冻住的副本清掉。
///
/// 从 `AppAccountBridge.init` 原样搬出来（2026-10-10 拆分），顺序不变：
/// 先 `migrateLegacy()`（它抛错的话 `AppAccountBridge.init` 直接失败，后面三步不跑、原件留着），
/// 再清历史搜索、旧自选、旧设置。
@MainActor enum AccountLegacyMigration {
  /// 设置编不出字节（`PrefsCodec.encoded` 返回 nil）时留一句：那一次写盘整段跳过，绝不写空档。
  private static let log = Logger(subsystem: "com.kanpan.app", category: "account")

  static func run(files: AccountFiles, prefs: PrefsStore, symbols: SymbolPickerModel, drawings: DrawingController) throws {
    try migrateLegacy(files: files, prefs: prefs, symbols: symbols, drawings: drawings)
    dropSharedSearchHistory()
    dropLegacySymbols()
    dropLegacyPrefs()
  }

  /// 把 `UserDefaults.standard` 里那份旧的历史搜索一次性清掉，不归给任何身份。
  ///
  /// 这份历史是多个身份混在一起的——这台机器上所有登录过的人搜的词都记在同一个键里，
  /// 无法归属到具体的人，所以在搬到按身份存储（`PersonalFileStorage` 的 search.json）时
  /// 一次性清掉。归给「升级那一刻登录着的人」比不迁更糟：A 搜过的词会正式写进 B 的档案，
  /// B 之后怎么清自己的历史都清不掉那几条的来路。搜索历史是最不值钱的状态，
  /// 用几天自己就回来了，不值得为它担这个风险。
  ///
  /// 不挂 `legacy-imported.json` 那个标记：老用户早就越过那道标记了，挂上去等于不清。
  /// 清完之后写入已经改道到档案里，这个键不会再被写第二次，所以每次启动跑一遍是幂等的。
  private static func dropSharedSearchHistory() {
    UserDefaults.standard.removeObject(forKey: SearchHistory.defaultsKey)
  }
  /// 搬完清原件：`UserDefaults` 里那份旧的自选档案（`kanpan.symbols.v1`）搬进
  /// 账号目录之后就抹掉。
  ///
  /// 和历史搜索不同，这份是**归当前这个人**的（自选、分类、最近看过的品种都在
  /// 这台机器上由他一个人攒出来的），所以先搬后清，不是直接丢。
  ///
  /// 为什么非清不可：`migrateLegacy()` 只复制、不清原件，于是同一份档案在机器上留了
  /// 两个真身——写在 `symbols.json`（`PersonalFileStorage`），读却可能读回
  /// `UserDefaults`。这正是 R3-1 那个「新装机每次冷启动都开 BTCUSDT、老用户永远停在
  /// 升级那一刻的品种上」的病根：那份 UserDefaults 副本在搬家那一刻冻住了，之后
  /// 一个字都不会再更新，谁不小心读到它谁就看到一份几个月前的自选表。清掉之后
  /// 这条错路在运行时就不存在了。
  ///
  /// 时机：一定跑在 `migrateLegacy()` **之后**——那一步要么已经把内容写进了访客目录，
  /// 要么因为目录里已经有 `symbols.json` 而跳过（文件那份更新，本来就该赢）；
  /// 它抛错的话 `init` 直接失败，这一行不会跑到，原件留着。
  ///
  /// 不挂 `legacy-imported.json` 那个标记（理由同 `dropSharedSearchHistory()`）：
  /// 早就越过标记的老用户机器上，那份冻住的副本还躺着，挂上标记等于不清。
  /// 写入早已改道到文件，这个键不会再被写第二次，所以每次启动跑一遍是幂等的。
  private static func dropLegacySymbols() {
    UserDefaults.standard.removeObject(forKey: SymbolPrefsStore.defaultsKey)
    UserDefaults.standard.removeObject(forKey: SymbolPrefsStore.legacyDefaultsKey)
  }
  /// 同理清掉 `UserDefaults.standard` 里那份旧的设置（`PrefsCodec.key`）与它的脏标识。
  ///
  /// 设置的真身在账号目录的 `prefs.json`（`PersonalFileStorage`）；`MainScreen` 那个
  /// `PrefsStore` 在档案到货之前先挂在本机柜子上，于是这份副本要么是搬家那一刻冻住的，
  /// 要么是「上一次启动在档案装上之前写下的」某个人的设置——冷启动第一帧读到它，
  /// 就是先按一份不属于任何人的旧设置开张。第一帧真正要的皮肤 / 深浅 / 涨跌色走
  /// `LaunchThemeMirror`，这份副本不再有读者。
  ///
  /// **哨兵（`SettingsSentinel.storageKey`）不清**：它是故意留在本机柜子上的，用来分辨
  /// 「档案被清空」和「第一次装」。时机、幂等性同 `dropLegacySymbols()`。
  private static func dropLegacyPrefs() {
    UserDefaults.standard.removeObject(forKey: PrefsCodec.key)
    UserDefaults.standard.removeObject(forKey: SettingsStamp.storageKey)
  }
  private static func migrateLegacy(files: AccountFiles, prefs: PrefsStore, symbols: SymbolPickerModel, drawings: DrawingController) throws {
    let marker = files.root.appendingPathComponent("legacy-imported.json")
    guard !FileManager.default.fileExists(atPath: marker.path) else { return }
    let guest = try files.directory(user: nil)
    // 设置编不出字节就不搬这一份（`PrefsCodec.encoded` 返回 nil），不能往访客目录写一个空的 prefs.json：
    // 空档读回来是出厂值，再被当成「这个人的设置」推上去。
    let encodedPrefs = PrefsCodec.encoded(prefs.prefs)
    if encodedPrefs == nil { log.error("legacy prefs unencodable, skipped migrating prefs.json") }
    let values: [(String, Data)] = (encodedPrefs.map { [("prefs.json", $0)] } ?? []) + [("symbols.json", try JSONEncoder().encode(symbols.prefs)), ("draws.json", try JSONEncoder().encode(drawings.storedArchive))]
    for (name, data) in values {
      let target = guest.appendingPathComponent(name)
      if !FileManager.default.fileExists(atPath: target.path) { try data.write(to: target, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication]) }
    }
    // Only the unowned local review archive is eligible for automatic migration.
    //
    // 复盘落**三个**文件，不是一个：主档 `review-v1.json`、草稿 `draft-v1.json`、
    // 重温进度 `replay-positions.json`。这儿原来只搬主档，于是老用户升上来那一刻
    // 「写了一半还没提交的那条草稿」和「每条记录重温到哪一根」全留在老目录里再也读不到——
    // 那两份是纯粹的用户产出，不是可以重算的缓存。主档能不能搬得通仍然是前提
    // （`ReviewStore(directory:)` 解不动就抛，整次迁移不做）。
    let source = ReviewPaths.legacy(in: ReviewChartBridge.storageDirectory())
    let target = ReviewPaths(directory: guest)
    if FileManager.default.fileExists(atPath: source.archive.path),
       !FileManager.default.fileExists(atPath: target.archive.path) {
      _ = try ReviewStore(paths: source)
      for name in ReviewPaths.files {
        let from = source.directory.appendingPathComponent(name), to = guest.appendingPathComponent(name)
        guard FileManager.default.fileExists(atPath: from.path),
              !FileManager.default.fileExists(atPath: to.path) else { continue }
        try FileManager.default.copyItem(at: from, to: to)
      }
    }
    try AccountFiles.write(true, to: marker)
  }
}
