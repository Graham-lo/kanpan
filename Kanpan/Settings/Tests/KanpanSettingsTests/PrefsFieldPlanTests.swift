import Testing
import Foundation
import KanpanCore
import KanpanData
@testable import KanpanSettings

/// **把「加了字段忘了归类」变成一条红线。**
///
/// 这一套守卫存在的理由写在 `PrefsFieldPlan` 的注释里，一句话版本：同一件事
/// （哪个字段跟着人走 / 留在本机）以前散在四张手抄的清单里，两天里咬了两次——
/// 提交 `a161bb0`（客户端白名单比服务端多十九个字段，整条同步操作被拒，那个账号
/// 从此同步不上任何东西）和提交 `0f09f7e`（脏标识永远清不掉）。
///
/// 现在清单只有一张（`PrefsFieldPlan.table`），下面这几条负责保证它**不漏不多**。
/// 红的时候不要改测试，改表。
@Suite("体验类状态的归类表")
struct PrefsFieldPlanTests {

  /// `Prefs` 的每一个存储字段都得在表里，表里也不许有 `Prefs` 上没有的字段。
  ///
  /// 用 `Mirror` 而不是 JSON 键：可选字段是 nil 时 `encodeIfPresent` 根本不写那个键，
  /// 只看 JSON 会把它当成「不存在」放过去。`Mirror` 数的是存储属性，一个都躲不掉。
  @Test("每个存储字段都归了类")
  func everyStoredFieldIsClassified() {
    let stored = Set(Mirror(reflecting: Prefs.defaults).children.compactMap(\.label))
    let classified = Set(PrefsFieldPlan.table.keys)
    let missing = stored.subtracting(classified).sorted()
    let extra = classified.subtracting(stored).sorted()
    #expect(missing.isEmpty, """
      \(missing) 是 `Prefs` 上新加的存储字段，还没归类。
      去 Kanpan/Kanpan/Settings/Model/PrefsFieldPlan.swift 的 `table` 里加一行，判据只有一条：
      用手改出来的习惯 → `.synced`（跟着人走）；这台机器的属性 → `.deviceOnly`；
      自动累积的统计 → `.derivedLocal`（不跟人也不同步）。
      归 `.synced` 的还要同时改服务端 `Backend/kanpan-api/src/sync.rs` 的 `SETTINGS_FIELDS`
      和 `src/sync_validation.rs` 的值规则——只进白名单不补值规则，这个字段会变成毒丸，
      整条同步操作 400。两边对不齐上一次的代价见提交 a161bb0。
      """)
    #expect(extra.isEmpty, """
      \(extra) 在 `PrefsFieldPlan.table` 里，但 `Prefs` 上没有这个存储字段。
      字段被删了或者改了名字就把表里这一行一起改掉；名字对不上的话，
      `Prefs.syncedFieldNames` 会把一个谁也不认识的键发给服务端。
      """)
  }

  /// 表里的键必须和 `PrefsCodec` 编码出来的键逐字相同——整条同步链路
  /// （`PersonalSyncCodec.settings` 过滤、`Prefs.keeping` 按键覆盖）都是在 JSON 键上做的。
  @Test("表里的键就是存档里的键")
  func tableKeysMatchTheArchiveKeys() throws {
    let data = PrefsCodec.encode(.defaults)
    let json = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
    let encoded = Set(json.keys).subtracting(PrefsFieldPlan.nonFieldKeys)
    let classified = Set(PrefsFieldPlan.table.keys)
    let missing = encoded.subtracting(classified).sorted()
    let extra = classified.subtracting(encoded).sorted()
    #expect(missing.isEmpty, """
      \(missing) 会被写进存档、也会被发上云，但 `PrefsFieldPlan.table` 里没有它。
      """)
    #expect(extra.isEmpty, """
      \(extra) 在 `PrefsFieldPlan.table` 里，却没被 `PrefsCodec.encode` 写出来。
      要么是 `CodingKeys` / `encode(to:)` 漏了一行（那这个字段根本存不下来，杀掉 app 就没了），
      要么是表里的键名拼错了。
      """)
  }

  /// 三张派生表就是那张母表，不许再出现第二份字面量。
  @Test("派生出来的几张表对得上母表")
  func derivedSetsComeFromTheTable() {
    #expect(Prefs.syncedFieldNames == PrefsFieldPlan.names(.synced))
    #expect(Prefs.deviceOnlyFieldNames == PrefsFieldPlan.names(.deviceOnly))
    #expect(Prefs.stampedFieldNames == Prefs.syncedFieldNames.union(SettingsWire.rsiFields))
    // `.syncedMerged` 的定义就是「打脏标识认它，但不以自己的名字上云」。
    #expect(PrefsFieldPlan.names(.syncedMerged) == SettingsWire.rsiFields)
    #expect(Prefs.syncedFieldNames.isDisjoint(with: Prefs.deviceOnlyFieldNames))
  }

  /// **客户端会发的字段 ≡ 服务端认的字段——两边都读同一个文件，谁也不再手抄。**
  ///
  /// 2026-09-19 之前这条测试里躺着一份从 `Backend/kanpan-api/src/sync.rs` 手抄过来的
  /// 53 个字符串，服务端那边的 `the_allowlist_is_what_ios_sends` 又把同一份期望写了第三遍。
  /// 三份手抄只在「三个地方都记得同时改」时才成立，而它已经咬过一次：提交 `a161bb0`——
  /// 服务端认的字段比客户端会发的少十九个，服务端对含未知字段的操作是**整条拒绝**，
  /// 于是那个账号的同步队列被一条永远推不上去的操作堵死。
  ///
  /// 现在中间放了一个机器可读的产物 `Backend/kanpan-api/contract/settings-fields.json`：
  /// 它由**这个文件里的 `SettingsFieldContract`** 从母表 `PrefsFieldPlan.table` 生成
  /// （`make sync-contract`），Swift 这边跟它对账，Rust 那边 `include_str!` 读同一份对账。
  /// 母表变了而契约没重新生成 → 这条红；契约变了而服务端没跟上 → `cargo test` 那条红。
  ///
  /// 这条红了**不要改契约文件**（它是生成物），改母表再跑 `make sync-contract`。
  @Test("客户端会发的字段和契约文件一个不差")
  func theContractFileIsTheOneListBothSidesRead() throws {
    let rendered = try SettingsFieldContract.rendered()
    if SettingsFieldContract.isWriting {
      try SettingsFieldContract.write(rendered)
      return
    }

    let onDisk = try SettingsFieldContract.readFromDisk()
    let contract = try SettingsFieldContract.decode(onDisk)

    // 先逐项对，失败信息才说得清差在哪个键；最后再整篇比一次兜住说明文字与格式的漂移。
    let contractClasses = contract.fieldClasses
    let tableClasses = PrefsFieldPlan.table.mapValues(\.rawValue)
    #expect(contractClasses == tableClasses, """
      `PrefsFieldPlan.table` 和契约文件对不上：
      表里多出来 \(Set(tableClasses.keys).subtracting(contractClasses.keys).sorted())，
      契约里多出来 \(Set(contractClasses.keys).subtracting(tableClasses.keys).sorted())，
      归类不一样的 \(tableClasses.filter { contractClasses[$0.key] != nil && contractClasses[$0.key] != $0.value }.keys.sorted())。
      契约是生成物：改母表，然后在仓库根跑 `make sync-contract`。
      """)

    let contractWire = Set(contract.wireKeys)
    let sent = Prefs.syncedFieldNames.union(PrefsFieldPlan.wireOnlyKeys.keys)
    #expect(sent == contractWire, """
      客户端会发的顶层键和契约里那份「线上会出现的键」对不上：
      客户端会发、契约里没有 \(sent.subtracting(contractWire).sorted())，
      契约里有、客户端不发 \(contractWire.subtracting(sent).sorted())。
      服务端 `SETTINGS_FIELDS` 是逐字照契约这一份对账的，对不上就等于同步断了（提交 a161bb0）。
      跑 `make sync-contract` 重新生成。
      """)

    #expect(PrefsFieldPlan.wireOnlyKeys == contract.wireOnlyKeys, """
      `PrefsFieldPlan.wireOnlyKeys` 和契约里的 `wireOnlyKeys` 对不上：
      键差在 \(Set(PrefsFieldPlan.wireOnlyKeys.keys).symmetricDifference(contract.wireOnlyKeys.keys).sorted())，
      理由不一样的 \(PrefsFieldPlan.wireOnlyKeys.filter { contract.wireOnlyKeys[$0.key] != nil && contract.wireOnlyKeys[$0.key] != $0.value }.keys.sorted())。
      这一档是「服务端认、客户端不发」的键（老存档遗留 / 合成键），加一个就要在母表里写清楚为什么。
      跑 `make sync-contract` 重新生成。
      """)

    #expect(onDisk == rendered, """
      \(SettingsFieldContract.relativePath) 和母表生成出来的那份逐字不同——
      上面几条都绿说明差的是说明文字或格式，多半是有人手改了这个文件。它是生成物，
      在仓库根跑 `make sync-contract` 重新生成一遍。
      """)
  }

  /// 搬家不能把人停在哪一类弄丢：`favoritesGroup` 得真的存得下来、也真的跟着人走。
  @Test("自选页停在哪一类跟着账号走")
  func favoritesGroupIsSynced() {
    #expect(PrefsFieldPlan.table["favoritesGroup"] == .synced)
    #expect(Prefs.syncedFieldNames.contains("favoritesGroup"))
    var prefs = Prefs.defaults
    #expect(prefs.favoritesGroup.isEmpty)   // 还没挑过。
    prefs.favoritesGroup = "F1E0A6C2-0000-4000-8000-000000000001"
    #expect(PrefsCodec.decode(PrefsCodec.encode(prefs)).favoritesGroup == prefs.favoritesGroup)
    // 长度和服务端那条规则同一个上限，超了就当没存过。
    prefs.favoritesGroup = String(repeating: "x", count: 129)
    #expect(PrefsCodec.decode(PrefsCodec.encode(prefs)).favoritesGroup.isEmpty)
  }

  /// **「线路」这一摊分在两边，是产品决定，不是分类漂移。**
  ///
  /// 这条测试是拿来钉住那个决定的，不是拿来描述现状的。审查报告曾经按「行情域名、
  /// 线路开关一概是本机属性」这句话读出「`routePolicy` 应该改成 `deviceOnly`」——
  /// 那是把两件事混成了一件：
  ///
  /// - `apiHost` / `streamHost` / `smartMarketRoute` 是**具体主机名与探测开关**，
  ///   取决于这台手机现在挂在哪张网上，跟着人走只会把 A 的网络环境带到 B。`deviceOnly`。
  /// - `routePolicy` 是他在设置里**用手点的「直连 / 网关」两档**，和皮肤、周期同一类：
  ///   用手改出来的习惯。`synced`。
  ///
  /// 产品规则的原话在 `AGENTS.md` 的稳定约定里：行情线路两档由用户自己选、出厂默认直连、
  /// 没有任何自动切换，「**选择随账号同步、未登录记在本机**」。
  ///
  /// **这条红了不要改测试，也不要改 `PrefsFieldPlan`——先去改产品规则。** 真要改，
  /// `AGENTS.md`、这条测试、`PrefsFieldPlan` 的注释和服务端 `SETTINGS_FIELDS` 一起改。
  @Test("直连 / 网关跟着人走，域名和探测开关留在本机")
  func routePolicyFollowsThePerson() {
    #expect(PrefsFieldPlan.table["routePolicy"] == .synced, "这是产品决定：选择随账号同步、未登录记在本机")
    #expect(Prefs.syncedFieldNames.contains("routePolicy"), "不在同步白名单里就发不上去，等于没同步")
    for name in ["apiHost", "streamHost", "smartMarketRoute", "launchSnapshot"] {
      #expect(PrefsFieldPlan.table[name] == .deviceOnly, "\(name) 是这台机器 / 这张网的属性，不跟人走")
      #expect(!Prefs.syncedFieldNames.contains(name))
    }

    // 换档案（登录 / 退登 / 切账号）时按 `deviceOnlyFieldNames` 保本机值：
    // 主机名留住，线路那两档让新档案说了算。
    var mine = Prefs.defaults
    mine.apiHost = "mine.example.com"
    mine.streamHost = "mine-stream.example.com"
    mine.smartMarketRoute = false
    mine.routePolicy = .gateway
    var theirs = Prefs.defaults
    theirs.routePolicy = .direct
    let merged = Prefs.keeping(Prefs.deviceOnlyFieldNames, of: mine, over: theirs)
    #expect(merged.apiHost == "mine.example.com" && merged.streamHost == "mine-stream.example.com")
    #expect(merged.smartMarketRoute == false)
    #expect(merged.routePolicy == .direct, "线路那两档跟着账号那份走，不被这台机器的上一份值盖住")
  }
}

// MARK: - 跨语言契约：那份两边都读的文件

/// **`Backend/kanpan-api/contract/settings-fields.json` 的生成器兼定位器。**
///
/// 存在的理由：同一件事（哪些 settings 键会出现在线上）以前在三个地方各手抄了一遍——
/// 这个文件里一份 53 个字符串的数组、Rust 的 `SETTINGS_FIELDS`、Rust 测试里
/// `the_allowlist_is_what_ios_sends` 的期望。三份手抄只在「三个地方都记得同时改」时成立，
/// 提交 `a161bb0` 就是没成立的那一次：服务端少认十九个字段，那个账号从此同步不上任何东西。
///
/// 现在链路是一条直线：
///
///     PrefsFieldPlan.table ──make sync-contract──▶ settings-fields.json
///                                                        ├──▶ Swift 测试对账（本文件）
///                                                        └──▶ Rust 测试 include_str! 对账
///
/// **母表只有 `PrefsFieldPlan.table` 一张**，契约是它的生成物，谁也不许手改契约。
enum SettingsFieldContract {
  /// 契约在仓库里的位置。放在 Rust crate 下面是因为那边只能 `include_str!` 一个
  /// 相对本 crate 的路径；Swift 这边靠 `#filePath` 退到仓库根再拼，两边都够得着。
  static let relativePath = "Backend/kanpan-api/contract/settings-fields.json"

  /// 契约的格式版本。字段含义变了（不是内容变了）才 +1，两边的读法都要跟着改。
  static let version = 1

  /// 环境变量置 1 时这条测试不对账，改为把母表重新导出成契约文件。`make sync-contract` 走的就是这条。
  static var isWriting: Bool { ProcessInfo.processInfo.environment["KANPAN_WRITE_SYNC_CONTRACT"] == "1" }

  // MARK: 文件本身

  /// 契约文件的全部内容。用 `Codable` 而不是 `[String: Any]`：`JSONEncoder` 能关掉
  /// 正斜杠转义（`\/`），导出来的路径在文件里是给人看的样子。
  struct Document: Codable, Equatable {
    var version: Int
    var whatThisIs: String
    var generatedFrom: String
    var generatedBy: String
    var howToRegenerate: String
    var fieldClassesNote: String
    /// 字段名 → `PrefsFieldClass` 的 rawValue。客户端那一半的全部信息。
    var fieldClasses: [String: String]
    var wireKeysNote: String
    /// 线上真正会出现的 settings 顶层键 = `synced` 的字段名 + `wireOnlyKeys`。
    /// 服务端 `SETTINGS_FIELDS` 必须逐字等于它。
    var wireKeys: [String]
    var wireOnlyKeysNote: String
    /// 服务端认、客户端不发的键 → 它为什么只在线上存在。
    var wireOnlyKeys: [String: String]
  }

  // MARK: 定位

  /// 仓库根。从**这个源文件**往上退五层：
  /// `<root>/Kanpan/Settings/Tests/KanpanSettingsTests/PrefsFieldPlanTests.swift`。
  ///
  /// 用 `#filePath` 而不是当前工作目录：`swift test` 的 CWD 取决于谁在哪儿敲的命令
  /// （`make` 从仓库根、手敲从 `Kanpan/Settings`、Xcode 又是另一处），拿 CWD 拼路径
  /// 迟早会在某台机器上找不到文件，然后被当成「测试挂了」。源文件的位置是编译期钉死的。
  static var repositoryRoot: URL {
    var url = URL(fileURLWithPath: #filePath)
    for _ in 0..<5 { url.deleteLastPathComponent() }
    return url
  }

  static var fileURL: URL { repositoryRoot.appendingPathComponent(relativePath) }

  // MARK: 生成

  /// 母表今天该导出成的那份契约。
  static func generated() -> Document {
    Document(
      version: version,
      whatThisIs: "iOS 与 Rust 后端之间那份 settings 字段白名单的唯一权威副本。"
        + "客户端按 fieldClasses 决定一个字段跟不跟人走；服务端 sync::SETTINGS_FIELDS 必须逐字等于 wireKeys。",
      generatedFrom: "Kanpan/Kanpan/Settings/Model/PrefsFieldPlan.swift · PrefsFieldPlan.table",
      generatedBy: "Kanpan/Settings/Tests/KanpanSettingsTests/PrefsFieldPlanTests.swift · SettingsFieldContract",
      howToRegenerate: "这是生成物，不要手改。改 PrefsFieldPlan.table，然后在仓库根跑 `make sync-contract`。"
        + "改完两边的测试自动对账：Kanpan/Settings 的 theContractFileIsTheOneListBothSidesRead，"
        + "Backend/kanpan-api 的 the_allowlist_is_what_ios_sends 与 every_wire_key_has_a_value_rule。",
      fieldClassesNote: "synced=随账号同步、线上用自己的名字；"
        + "syncedMerged=随账号同步但线上并成别的键（见 wireOnlyKeys）；"
        + "deviceOnly=这台机器 / 这张网的属性，不跟人走；"
        + "derivedLocal=自动累积的统计，不跟人也不同步。",
      fieldClasses: PrefsFieldPlan.table.mapValues(\.rawValue),
      wireKeysNote: "线上真正会出现的 settings 顶层键 = synced 的字段名 + wireOnlyKeys。"
        + "Backend/kanpan-api/src/sync.rs 的 SETTINGS_FIELDS 必须逐字等于这一集合。"
        + "少一个：含那个键的操作被服务端整条拒绝，客户端的同步队列被它堵死（提交 a161bb0）。"
        + "多一个而 sync_validation::field 没配值规则：同一种死法，_=>false 让整条操作 400。",
      wireKeys: PrefsFieldPlan.names(.synced).union(PrefsFieldPlan.wireOnlyKeys.keys).sorted(),
      wireOnlyKeysNote: "服务端认、客户端不发的键，以及它们为什么只在线上存在。",
      wireOnlyKeys: PrefsFieldPlan.wireOnlyKeys
    )
  }

  /// 导出的字节。`sortedKeys` 让同一张表每次导出**逐字节相同**——不确定的话 diff 里全是噪声，
  /// 也没法拿「整篇相等」当兜底断言。
  static func rendered() throws -> String {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
    return String(decoding: try encoder.encode(generated()), as: UTF8.self) + "\n"
  }

  static func write(_ text: String) throws {
    try FileManager.default.createDirectory(
      at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
    try text.write(to: fileURL, atomically: true, encoding: .utf8)
    print("sync-contract: 已从 PrefsFieldPlan.table 重新生成 \(relativePath)")
  }

  // MARK: 读回来

  static func readFromDisk() throws -> String {
    guard FileManager.default.fileExists(atPath: fileURL.path) else {
      throw ContractError.missingFile(fileURL.path)
    }
    return try String(contentsOf: fileURL, encoding: .utf8)
  }

  static func decode(_ text: String) throws -> Document {
    let document: Document
    do { document = try JSONDecoder().decode(Document.self, from: Data(text.utf8)) }
    catch { throw ContractError.unreadable("\(error)") }
    guard document.version == version else { throw ContractError.wrongVersion(document.version) }
    return document
  }

  enum ContractError: Error, CustomStringConvertible {
    case missingFile(String)
    case unreadable(String)
    case wrongVersion(Int)

    var description: String {
      switch self {
      case .missingFile(let path):
        return "契约文件不在 \(path)。在仓库根跑 `make sync-contract` 生成它。"
      case .unreadable(let reason):
        return "契约文件读不出来（\(reason)）。它是生成物，跑 `make sync-contract` 重新生成。"
      case .wrongVersion(let found):
        return "契约文件的 version 是 \(found)，这份代码读的是 \(version)。"
          + "格式升过级就把 Swift 与 Rust 两边的读法一起改，再跑 `make sync-contract`。"
      }
    }
  }
}
