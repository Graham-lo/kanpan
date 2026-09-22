import Foundation
import Testing
import KanpanCore
import KanpanAccount
@testable import KanpanAccountCodec

// MARK: - 「这个客户端替哪些字段说话」这张表的穷举守卫

/// `PersonalSyncCodec.ownedKeys` 是 `SyncStore.stage` 用来分清「用户把这个字段清掉了」
/// 和「这个版本根本不认识这个字段」的唯一依据，所以它必须**和 codec 真正发出去的键
/// 一个不差**：
///
/// - 多一个（表里有、codec 不发）：云端那个键会被当成「我自己的字段没了」，发一个 null
///   上去。服务端的 null 白名单外一律 `invalid_operation`，而且是整条操作拒掉——
///   2026-09-19 那个账号就是这么被 `drawings.created` 堵死的。
/// - 少一个（codec 发、表里没有）：用户清掉这个字段时那一下被当成外来键带回去，
///   他清的东西永远同步不上去，而且一声不响。
///
/// 表本身是**算出来的**（拿 codec 自己的编码器跑一份填满了的样板），所以这一组用例不是
/// 在核对一张手抄的清单，而是在核对「算法用的样板够不够满」——`Drawing` 上加一把新工具、
/// 加一个新属性，`Prefs` 里加一个同步字段，这儿立刻红。
@Suite("客户端替哪些字段说话") struct PersonalSyncCodecOwnedKeysTests {
  /// 仓库根。测试要去读那份生成的字段契约。
  private var repository: URL {
    var url = URL(fileURLWithPath: #filePath)
    for _ in 0..<5 { url.deleteLastPathComponent() }
    return url
  }

  /// 空表 = 退回 2026-09-19 之前的老行为（每个键都当自己的、照旧发 null）。
  /// `ownedKeys` 那个 `catch` 分支真要是走到了，这条第一个红。
  @Test("六摊东西一摊都不能少")
  func ownedKeysCoverEveryCollection() {
    for collection in ["settings", "drawings", "drawingPreferences", "favorites", "groups", "alerts"] {
      let keys = PersonalSyncCodec.ownedKeys[collection]
      #expect(keys?.isEmpty == false, "`\(collection)` 这一摊没算出键来，客户端等于又不认识自己的字段了")
    }
  }

  // MARK: 画线

  /// 三十九把工具、每一把的可选字段两种状态，一条一条编出来，一个键都不许落在表外。
  ///
  /// `Drawing.encode(to:)` 有两条件分支（`color` 是 `encodeIfPresent`，`text` 只有
  /// 带文字的工具或者老存档里真有文字才写），所以两种样板都要跑一遍。
  @Test("每一把工具发出去的键都在表里，并集正好是表本身")
  func everyDrawingKindStaysInsideTheTable() throws {
    var bare = DrawArchive()
    var full = DrawArchive()
    for kind in Drawing.Kind.allCases {
      let points = Array(repeating: DrawPoint(t: 1, p: 1), count: kind.pointCount)
      var plain = Drawing(id: "d" + kind.rawValue, kind: kind, points: points)
      plain.color = nil
      plain.text = ""
      bare.bySymbol["BTCUSDT", default: []].append(plain)

      var decorated = plain
      decorated.color = Hex("#123456")
      decorated.text = "字"
      full.bySymbol["BTCUSDT", default: []].append(decorated)
      full.preferences.styles[kind.rawValue] = DrawingStyle(decorated)
    }

    let owned = try #require(PersonalSyncCodec.ownedKeys["drawings"])
    var union: Set<String> = []
    for archive in [bare, full] {
      for object in try PersonalSyncCodec.drawings(archive) where object.collection == "drawings" {
        let keys = Set(object.body.keys)
        #expect(keys.isSubset(of: owned), "\(object.id) 发出去的键不在表里：\(keys.subtracting(owned).sorted())")
        union.formUnion(keys)
      }
    }
    #expect(union == owned, """
      表和 `drawings(_:)` 真正发出去的键对不上：
      表里多出来 \(owned.subtracting(union).sorted())——这些键会被当成「我自己的字段没了」发 null，
      服务端整条拒绝，那个对象的同步从此卡死；
      表里少了 \(union.subtracting(owned).sorted())——用户清掉这些字段时清不掉，还一声不响。
      表是 `PersonalSyncCodec.maximalDrawArchive` 算出来的，红了去补那份样板，别在这儿抄一行。
      """)
  }

  /// 事故里的那个键：`created` 是只活在线上的老字段（`Drawing` 上根本没有这个属性），
  /// 客户端从不发它，所以它绝不能进表——进了表就等于每次碰这条线都提议删掉它。
  @Test("线上那个 created 不在表里")
  func theLegacyCreatedKeyIsNotOurs() throws {
    let owned = try #require(PersonalSyncCodec.ownedKeys["drawings"])
    #expect(!owned.contains("created"))
  }

  /// 工具默认样式那一摊：`styles` 拍平成 `styles/<工具>`，三十九把工具一把都不能少，
  /// 否则用户把某一把工具的样式恢复默认时那一下同步不上去。
  @Test("每一把工具的默认样式都在表里")
  func everyToolStyleIsOurs() throws {
    let owned = try #require(PersonalSyncCodec.ownedKeys["drawingPreferences"])
    for kind in Drawing.Kind.allCases {
      #expect(owned.contains("styles/" + kind.rawValue), "`styles/\(kind.rawValue)` 不在表里")
    }
    for key in ["favorites", "magnet", "continuous"] { #expect(owned.contains(key)) }
  }

  // MARK: 设置

  /// settings 的顶层键必须和那份**生成的**字段契约逐字对上。
  ///
  /// 契约（`Backend/kanpan-api/contract/settings-fields.json`）是 iOS 和 Rust 之间那份
  /// 白名单的唯一权威副本，由 `PrefsFieldPlan.table` 生成。线上会出现的顶层键 =
  /// 契约里的 `wireKeys`；其中 `styleID` 是**服务端认、客户端不发**的老键
  /// （`wireOnlyKeys`），所以它正是那种「不该由这个客户端说话」的字段——
  /// 它要是进了表，`drawings.created` 那一出会在 settings 上再演一遍。
  @Test("settings 替哪些字段说话，和生成的契约对得上")
  func theSettingsTopLevelKeysMatchTheGeneratedContract() throws {
    let path = repository.appendingPathComponent("Backend/kanpan-api/contract/settings-fields.json")
    let contract = try JSONDecoder().decode(Contract.self, from: try Data(contentsOf: path))
    let owned = try #require(PersonalSyncCodec.ownedKeys["settings"])
    // 契约里的 `wireKeys` 是**服务端认的顶层键**，而客户端发上去的路径是拍平过的：
    // `params` 那几摊在线上长的是 `params/MA`，服务端按第一段去对白名单。所以这儿比的是
    // 「每个键的第一段」，下面这两个单独减掉——它们是**服务端认、客户端不发**的键，
    // 照定义就不该由这个客户端替它们说话：
    //
    // - `styleID`：十二款蜡烛造型那一阵子的遗留，客户端早就不发了。
    // - `routePolicy`：2026-09-19 起是本机字段（直连 / 网关那两档不再跟着人走），
    //   服务端留着它只为不把还在发它的老客户端整条操作拒掉。
    // - `drawToolGroup`：「绘图」面板上次停在哪个分类。2026-09-22 工具砍到十二把、
    //   分类标签整条去掉之后这个键就没东西可存了，客户端既不发也不收；服务端同理留着。
    //
    // 注意 `wireOnlyKeys` 不能整组减掉：`rsiRange` 也在那一组里，但它是客户端把
    // `rsiUpper` / `rsiLower` **合成出来发上去**的键，客户端确实替它说话。
    let serverKnownButUnsent: Set<String> = ["styleID", "routePolicy", "drawToolGroup"]
    for key in serverKnownButUnsent {
      #expect(contract.wireOnlyKeys[key] != nil, "`\(key)` 客户端不发，契约里就得写清楚它为什么只在线上存在")
    }
    let expected = Set(contract.wireKeys).subtracting(serverKnownButUnsent)
    let covered = Set(owned.map { String($0.split(separator: "/")[0]) })

    #expect(covered == expected, """
      settings 替哪些字段说话，和契约对不上：
      表里多出来 \(covered.subtracting(expected).sorted())，表里少了 \(expected.subtracting(covered).sorted())。
      契约是生成物，改 `PrefsFieldPlan.table` 之后在仓库根跑 `make sync-contract`。
      """)
    // 嵌套的那几摊只以 `<字段>/<指标>` 的样子上线，顶层一个都不该出现——出现了说明
    // `flatten` 漏拍了，那个整包的值会原样发上去，服务端的值规则当场顶回来。
    let top = Set(owned.filter { !$0.contains("/") })
    #expect(top == expected.subtracting(PersonalSyncCodec.nested), """
      settings 的顶层键对不上：多出来 \(top.subtracting(expected).sorted())，
      少了 \(expected.subtracting(PersonalSyncCodec.nested).subtracting(top).sorted())。
      """)
    #expect(top.contains("rsiRange"), "`rsiRange` 是客户端合成出来发的，它是自己的字段")
    #expect(!top.contains("styleID"), "`styleID` 客户端早就不发了，替它说话等于提议把它删掉")
    #expect(!top.contains("routePolicy"), "线路那两档 2026-09-19 起是本机字段，新客户端不发它")
    #expect(!top.contains("drawToolGroup"), "「绘图」面板没有分类标签了，新客户端不发它")
    for key in Prefs.deviceOnlyFieldNames { #expect(!top.contains(key), "`\(key)` 压根不上线") }
  }

  /// 一份把每个指标都改过的设置，发出去的键一个不许落在表外。
  ///
  /// `params` / `indicatorColors` / `hiddenOutputs` / `subHeights` / `subHeightOverrides`
  /// 拍平之后是 `<字段>/<指标>` 乃至 `<字段>/<指标>/<输出序号>`：一份出厂设置只拍得出
  /// 其中几条，所以这儿按 `IndicatorID.allCases` 铺满了再比。
  @Test("每个指标的嵌套路径都在表里")
  func everyIndicatorPathIsOurs() throws {
    var prefs = Prefs.defaults
    for (index, id) in IndicatorID.allCases.enumerated() {
      prefs.params[id] = [index + 1]
      prefs.hiddenOutputs[id] = [0]
      prefs.indicatorColors[id] = [0: Hex("#123456"), 20: Hex("#654321")]
      prefs.subHeights[id] = .large
      prefs.subHeightOverrides[id] = 1.5
    }
    let owned = try #require(PersonalSyncCodec.ownedKeys["settings"])
    let sent = Set(try PersonalSyncCodec.settings(prefs).body.keys)
    #expect(sent.isSubset(of: owned), "发出去的键不在表里：\(sent.subtracting(owned).sorted())")
    for id in IndicatorID.allCases {
      #expect(owned.contains("params/" + id.rawValue))
      #expect(owned.contains("indicatorColors/" + id.rawValue + "/0"))
      #expect(owned.contains("indicatorColors/" + id.rawValue + "/20"))
    }
    // 认不出的指标、越界的输出序号都不是这个版本的词汇：`PrefsCodec` 解码时就把它们丢了，
    // 客户端根本产不出这两条路径，所以它们也轮不到客户端来说「删掉」。
    #expect(!owned.contains("params/notAnIndicator"))
    #expect(!owned.contains("indicatorColors/MACD/21"))
  }

  // MARK: 自选与分类

  /// 自选和分类那两摊：`symbols(_:)` 发什么，表里就该是什么。
  /// 服务端认得一个客户端不发的 `favorites.alerts`，同样不许进表。
  @Test("自选与分类发出去的键就是表本身")
  func theFavoriteKeysAreExactlyWhatWeSend() throws {
    let prefs = SymbolPrefs(favorites: ["BTCUSDT", "ETHUSDT"],
                            groups: [FavoriteGroup(id: "g1", name: "主力")],
                            groupForSymbol: ["BTCUSDT": "g1"], pinned: ["ETHUSDT"])
    var sent: [String: Set<String>] = [:]
    for object in PersonalSyncCodec.symbols(prefs) { sent[object.collection, default: []].formUnion(object.body.keys) }
    for (collection, keys) in sent {
      #expect(PersonalSyncCodec.ownedKeys[collection] == keys, """
        `\(collection)` 这一摊对不上：表是 \(PersonalSyncCodec.ownedKeys[collection]?.sorted() ?? [])，
        `symbols(_:)` 发的是 \(keys.sorted())。
        """)
    }
    #expect(PersonalSyncCodec.ownedKeys["favorites"]?.contains("alerts") == false,
            "`alerts` 是服务端认、客户端不发的键，替它说话等于提议删掉它")
  }

  /// 契约文件里这个测试要用到的那几项。
  private struct Contract: Decodable {
    var wireKeys: [String]
    var wireOnlyKeys: [String: String]
  }

  // MARK: 提醒

  /// 提醒那一摊：身体正好是方案表 2.2 的十五个键，一个不多一个不少。
  ///
  /// 服务端 `sync_validation.rs` 的 `ALERT_FIELDS` 是同样十五个，多一个键整条操作
  /// 被拒、队列跟着堵（见 `ownedKeys` 的注释）。所以这条是**跨端契约**，
  /// 改字段名之前先去看服务端那张表。
  @Test("提醒发出去的键就是表 2.2 那十五个")
  func theAlertKeysAreExactlyTheContract() throws {
    let alert = Alert(id: "a1", symbol: "BTCUSDT", drawingID: "d1",
                      lines: [AlertLine(points: [DrawPoint(t: 1, p: 2)], extendRight: true)],
                      armedAt: 3, title: "BTC 触到你画的趋势线", created: 4)
    let objects = try PersonalSyncCodec.alerts([alert])
    #expect(objects.count == 1)
    let object = try #require(objects.first)
    #expect(object.collection == "alerts")
    #expect(object.id == "binance/usd_m/BTCUSDT/a1")
    #expect(Set(object.body.keys) == ["kind", "symbol", "market", "drawingID", "lines", "condition",
                                      "armedAt", "once", "status", "firedAt", "firedPrice",
                                      "dueAt", "reviewID", "title", "created"])
    #expect(PersonalSyncCodec.ownedKeys["alerts"] == Set(object.body.keys))
    // 服务端对 `alerts.market` 卡的是整串，不是画线那种 venue + market 拆两半。
    #expect(object.body["market"] == .string("binance/usd_m"))
    #expect(object.body["venue"] == nil)
  }

  /// 空的那五个要写成 null，不许省略——省略会被 `SyncStore.stage` 读成「删掉这个字段」，
  /// 而它们正好是服务端 null 白名单上的那五个。
  @Test("没值的可空字段写 null，不省略")
  func nullableAlertKeysAreExplicitNulls() throws {
    let alert = Alert(id: "a1", symbol: "BTCUSDT", armedAt: 0, title: "x", created: 0)
    let object = try #require(try PersonalSyncCodec.alerts([alert]).first)
    for key in ["drawingID", "firedAt", "firedPrice", "dueAt", "reviewID"] {
      #expect(object.body[key] == .null, "`\(key)` 没写成 null")
    }
  }

  /// 上去再下来还是同一条：服务端判出触发之后写回来的 `status` / `firedAt` /
  /// `firedPrice` 就走这条路进本机。
  @Test("提醒上去再下来是同一条")
  func alertRoundTrips() throws {
    var alert = Alert(id: "a1", symbol: "ETHUSDT", drawingID: "d9",
                      lines: [AlertLine(points: [DrawPoint(t: 1, p: 2), DrawPoint(t: 3, p: 4)],
                                        extendLeft: true, extendRight: true)],
                      condition: .close, armedAt: 5, title: "ETH 触到你画的通道", created: 6)
    alert.status = .fired; alert.firedAt = 7; alert.firedPrice = 3_210.5
    let object = try #require(try PersonalSyncCodec.alerts([alert]).first)
    #expect(try PersonalSyncCodec.alert(object) == alert)
  }
}
