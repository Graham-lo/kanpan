import Testing
import Foundation
import KanpanCore
import KanpanData
import KanpanNetwork
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
  /// 同一份契约还捎带两份**词表**：`IndicatorID` 与 `Drawing.Kind` 的 rawValue。它们不在母表里
  /// （不是「字段」，是字段的**取值**），但服务端的值规则手抄了它们——`sync_validation.rs` 的
  /// `OVERLAY_INDICATORS` / `SUB_INDICATORS` / `KINDS`。手抄就会漂，漂了就是同一种死法：
  /// 新加一把画线工具而服务端不认，用它画出来的线被整条拒绝，永远离不开这台手机。
  /// 指标那份连**顺序**都算数——服务端是按「前 N 个是主图、其余是副图」切的。
  ///
  /// 这条红了**不要改契约文件**（它是生成物），改母表 / 枚举再跑 `make sync-contract`。
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

    // 指标与画线工具那两份词表：服务端是拿它们做值校验的，客户端这边是枚举。
    // 这几条在**生成模式之外**也跑，所以「改了枚举没重新生成契约」当场红，
    // 不用等到 Rust 那边才发现。
    let indicators = IndicatorID.allCases.map(\.rawValue)
    #expect(contract.indicatorIDs == indicators, """
      契约里的 `indicatorIDs` 和 `IndicatorID` 对不上（顺序也算）：
      契约 \(contract.indicatorIDs)
      枚举 \(indicators)
      跑 `make sync-contract` 重新生成。
      """)

    let overlays = IndicatorID.allCases.filter { $0.placement == .main }.map(\.rawValue)
    let subs = IndicatorID.allCases.filter { $0.placement == .sub }.map(\.rawValue)
    #expect(contract.overlayIndicatorIDs == overlays && contract.subIndicatorIDs == subs, """
      契约里的主副划分和 `IndicatorID.placement` 对不上：
      主图 契约 \(contract.overlayIndicatorIDs) / 枚举 \(overlays)
      副图 契约 \(contract.subIndicatorIDs) / 枚举 \(subs)
      跑 `make sync-contract` 重新生成。
      """)

    #expect(contract.overlayIndicatorIDs + contract.subIndicatorIDs == contract.indicatorIDs, """
      主图那几种必须排在副图前面：服务端是按「前 N 个是主图、其余是副图」切这份词表的
      （`sync_validation.rs` 的 OVERLAY_INDICATORS / SUB_INDICATORS）。
      `IndicatorID` 的 case 顺序被打乱成主副交错了，把它排回去——
      新指标落错一边，`overlays` / `subs` / `subInverted` 就会拒掉它，整条同步操作 400。
      """)

    let kinds = Drawing.Kind.allCases.map(\.rawValue)
    #expect(contract.drawingKinds == kinds, """
      契约里的 `drawingKinds` 和 `Drawing.Kind` 对不上：
      枚举有、契约没有 \(Set(kinds).subtracting(contract.drawingKinds).sorted())，
      契约有、枚举没有 \(Set(contract.drawingKinds).subtracting(kinds).sorted())。
      新加一把工具就跑一次 `make sync-contract`，否则服务端不认它，
      用它画出来的线被整条拒绝，永远离不开这台手机。
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

  /// **「线路」这一摊整个留在这台设备上——直连 / 网关那两档也不再跟着人走。**
  ///
  /// 这条钉的是 2026-09-19 按 GPT Pro 第二轮审查 B7 定下的决定。在那之前 `routePolicy`
  /// 是 `.synced`，于是有过这么一出：A 在自己的网络里选了网关并同步上去，B 本来是直连、
  /// 这个字段还干净，B 同步一轮之后存档里就成了网关——B 从头到尾没碰过线路那两档。
  ///
  /// 现在它是 `deviceOnly`，判据是「这是不是这台机器 / 这张网的属性」：直连还是走 VPS
  /// 网关，取决于这台手机这张网连得通哪一头，不是他摆出来的样子。（原来并排的
  /// `apiHost` / `streamHost` 两个自定义域名字段 2026-09-24 删了，审查 18a。）
  ///
  /// **产品规则本身一个字没变**：出厂默认直连、只有两档、手动选、没有任何自动切换。
  /// 变的只有一件事——这个选择不再跨设备覆盖。
  ///
  /// 服务端那一侧仍然认 `routePolicy`（进了 `PrefsFieldPlan.wireOnlyKeys`）：口袋里还有
  /// 老版本客户端在发它，而服务端对含未知字段的操作是**整条拒绝**，把它从白名单上删掉
  /// 等于把那台手机的同步队列堵死。新客户端既不发也不收。
  @Test("直连 / 网关留在这台设备上")
  func routePolicyStaysOnThisDevice() {
    for name in ["apiHost", "streamHost"] {
      #expect(PrefsFieldPlan.table[name] == nil, "\(name) 已删：主机一律由 RouteResolver 按线路给")
    }
    for name in ["routePolicy", "launchSnapshot"] {
      #expect(PrefsFieldPlan.table[name] == .deviceOnly, "\(name) 是这台机器 / 这张网的属性，不跟人走")
      #expect(!Prefs.syncedFieldNames.contains(name), "\(name) 进了同步白名单就会被发上去")
    }
    #expect(Prefs.deviceOnlyFieldNames.contains("routePolicy"), "不在这张表里，换档案时就保不住这台设备的选择")

    // 记脏 = 会生成一条同步操作。本机字段一条都不该生成。
    #expect(!Prefs.stampedFieldNames.contains("routePolicy"))
    var gateway = Prefs.defaults
    gateway.routePolicy = .gateway
    #expect(Prefs.changedStampedFields(from: .defaults, to: gateway).isEmpty,
            "改线路不该记脏，更不该推一条操作上去")

    // 但服务端还得继续认这个键：老客户端还在发。
    #expect(PrefsFieldPlan.wireOnlyKeys["routePolicy"] != nil,
            "服务端不认它，老客户端那条操作会被整条拒绝，队列从此堵死（提交 a161bb0）")

    // 换档案（登录 / 退登 / 切账号）时按 `deviceOnlyFieldNames` 保本机值：
    // 线路那两档留住。
    var mine = Prefs.defaults
    mine.routePolicy = .gateway
    var theirs = Prefs.defaults
    theirs.routePolicy = .direct
    theirs.skin = .terra
    let merged = Prefs.keeping(Prefs.deviceOnlyFieldNames, of: mine, over: theirs)
    #expect(merged.routePolicy == .gateway, "这台设备选的那一档不被新档案盖掉")
    #expect(merged.skin == .terra, "真正跟着人走的那些照旧由新档案说了算")
  }

  /// 「智能行情线路」（`smartMarketRoute`）2026-09-24 整条删了：它是一个没有界面入口的布尔，
  /// 却决定了网关主机表给不给——和「两档、没有任何自动切换」正相反。删了之后：
  /// 母表里没有它、编码出来没有它，老存档里带着这个键也照常读回，线路那一档原样保住。
  @Test("smartMarketRoute 不再是字段；老存档带着它也照常读回")
  func smartMarketRouteIsGone() throws {
    #expect(PrefsFieldPlan.table["smartMarketRoute"] == nil)
    var prefs = Prefs.defaults
    prefs.routePolicy = .gateway
    let encoded = PrefsCodec.encode(prefs)
    var object = try #require(try JSONSerialization.jsonObject(with: encoded) as? [String: Any])
    #expect(object["smartMarketRoute"] == nil, "新存档不该再写这个键")
    object["smartMarketRoute"] = false
    let legacy = try JSONSerialization.data(withJSONObject: object)
    let restored = PrefsCodec.decode(legacy)
    #expect(restored == prefs, "老存档里的 smartMarketRoute 只是被忽略，别的字段一个不丢")
    #expect(restored.routePolicy == .gateway)
  }

  /// **升级不许把这台设备上已经选好的线路弄丢。**
  ///
  /// 「改归类」这件事最容易出的事故是拿出厂值把存量档案洗一遍：用户本来在网关上，
  /// 升完级回到直连，行情那一头当场连不上。`routePolicy` 照旧写在 `prefs.json` 里
  /// （`deviceOnly` 说的是「不跟人走」，不是「不落盘」），所以存档怎么写的，起来就该是什么。
  @Test("老存档里选的是网关，升级之后这台机器还是网关")
  @MainActor
  func routePolicyMigrationKeepsThisDevicesChoice() {
    var archived = Prefs.defaults
    archived.routePolicy = .gateway
    let box = InMemoryPrefsStorage([PrefsCodec.key: PrefsCodec.encode(archived)])

    let store = PrefsStore(storage: box, cache: UnavailableMarketCache())
    #expect(store.prefs.routePolicy == .gateway, "存档里是网关，起来还得是网关，不许重置成出厂直连")

    // 改别的设置照旧落盘，线路那一档跟着留在档案里。
    store.update { $0.skin = .terra }
    #expect(PrefsStore(storage: box, cache: UnavailableMarketCache()).prefs.routePolicy == .gateway)
    #expect(store.dirtyFields.contains("skin"), "皮肤是跟着人走的那一类，改了要记脏")

    // 用手点回直连：当场生效、落盘，但不记脏（不生成同步操作，也就不会被推上去）。
    store.update { $0.routePolicy = .direct }
    #expect(store.prefs.routePolicy == .direct)
    #expect(!store.dirtyFields.contains("routePolicy"), "本机字段不该记脏")
    #expect(PrefsStore(storage: box, cache: UnavailableMarketCache()).prefs.routePolicy == .direct,
            "本机字段照样落盘，杀掉 app 再起来还是这一档")
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
  ///
  /// 2026-09-19 往里加了 `indicatorIDs` / `overlayIndicatorIDs` / `subIndicatorIDs` /
  /// `drawingKinds` 四个键，**没有** +1：老键一个没动、含义一个没变，加的是新的一摊，
  /// 已经在读 v1 的那几条 Rust 测试照旧读得懂。+1 只会让它们全红一遍，换不来任何保护。
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
    var indicatorIDsNote: String
    /// `IndicatorID.allCases` 的全部 rawValue，**顺序照抄枚举**：主图那几种在前，副图那几种在后。
    var indicatorIDs: [String]
    var overlayIndicatorIDsNote: String
    /// 画在主图上的那几种（`IndicatorID.placement == .main`）。
    var overlayIndicatorIDs: [String]
    var subIndicatorIDsNote: String
    /// 画在副图上的那几种（`placement == .sub`）。
    var subIndicatorIDs: [String]
    var drawingKindsNote: String
    /// `Drawing.Kind` 的全部 rawValue。
    var drawingKinds: [String]
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
      whatThisIs: "iOS 与 Rust 后端之间那份 settings 字段白名单的唯一权威副本，"
        + "外加两份服务端做值校验时要照抄的词表（indicatorIDs 与 drawingKinds）。"
        + "客户端按 fieldClasses 决定一个字段跟不跟人走；服务端 sync::SETTINGS_FIELDS 必须逐字等于 wireKeys，"
        + "sync_validation 的指标与画线词表必须逐项等于这里的两份。",
      generatedFrom: "Kanpan/Kanpan/Settings/Model/PrefsFieldPlan.swift · PrefsFieldPlan.table；"
        + "KanpanCore/Indicator/IndicatorID.swift · IndicatorID；KanpanCore/Drawing/Drawing.swift · Drawing.Kind",
      generatedBy: "Kanpan/Settings/Tests/KanpanSettingsTests/PrefsFieldPlanTests.swift · SettingsFieldContract",
      howToRegenerate: "这是生成物，不要手改。改 PrefsFieldPlan.table（或 IndicatorID / Drawing.Kind），"
        + "然后在仓库根跑 `make sync-contract`。"
        + "改完两边的测试自动对账：Kanpan/Settings 的 theContractFileIsTheOneListBothSidesRead，"
        + "Backend/kanpan-api 的 the_allowlist_is_what_ios_sends、every_wire_key_has_a_value_rule、"
        + "the_indicator_vocabulary_is_the_contract_one 与 every_drawing_tool_is_in_the_contract。",
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
      wireOnlyKeys: PrefsFieldPlan.wireOnlyKeys,
      indicatorIDsNote: "`IndicatorID` 的全部 rawValue，顺序就是枚举的顺序：主图那几种在前、副图那几种在后。"
        + "服务端 sync_validation 的 OVERLAY_INDICATORS ++ SUB_INDICATORS 必须逐项等于它——"
        + "`params` / `hiddenOutputs` / `indicatorColors` / `subHeightOverrides` 这些带指标名的路径，"
        + "第二段只认这份词表，不在表里的整条操作 400。",
      indicatorIDs: IndicatorID.allCases.map(\.rawValue),
      overlayIndicatorIDsNote: "画在主图上的那几种（`IndicatorID.placement == .main`）。"
        + "settings.overlays 只认这一档，条数上限也是它的长度。",
      overlayIndicatorIDs: IndicatorID.allCases.filter { $0.placement == .main }.map(\.rawValue),
      subIndicatorIDsNote: "画在副图上的那几种（`placement == .sub`）。"
        + "settings.subs 与 settings.subInverted 只认这一档。"
        + "主副分界也是契约的一部分：服务端是按「前 N 个是主图、其余是副图」切的，"
        + "新指标落错一边 = 那条设置永远同步不上去。",
      subIndicatorIDs: IndicatorID.allCases.filter { $0.placement == .sub }.map(\.rawValue),
      drawingKindsNote: "`Drawing.Kind` 的全部 rawValue。服务端 sync_validation 的 KINDS 必须和它一样——"
        + "drawings.kind、drawingPreferences.favorites 与 styles/<kind>、settings.lastDrawTool "
        + "四条值规则都拿它当词表。少一个：用那把工具画出来的线被服务端整条拒绝，永远离不开这台手机。",
      drawingKinds: Drawing.Kind.allCases.map(\.rawValue)
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
