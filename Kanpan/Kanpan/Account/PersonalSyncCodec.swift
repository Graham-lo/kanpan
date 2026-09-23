import Foundation
import KanpanCore
import KanpanAccount

/// Explicit allowlist shared by cloud preferences and review chart snapshots.
enum PersonalSyncCodec {
  /// 随账号同步的字段清单。
  ///
  /// 真身 2026-09-19 搬去了 `Prefs.syncedFieldNames`（设置包里）：脏标识要按这张表
  /// 计字段，而脏标识做在 `PrefsStore` 那一层（包里，M1 抽 `PersonalStore` 时整块搬走），
  /// 包看不见 app 靶子里的这个文件。**一份清单，两处用**——别在这儿再抄一份。
  static var fields: Set<String> { Prefs.syncedFieldNames }
  static let nested: Set<String> = ["params", "indicatorColors", "hiddenOutputs", "subHeightOverrides", "styles", "variants"]
  static func flatten(_ value: [String: KanpanAccount.JSONValue]) -> [String: KanpanAccount.JSONValue] {
    var result: [String: KanpanAccount.JSONValue] = [:]
    for (key, value) in value {
      if nested.contains(key), case .object(let children) = value {
        for (child, content) in children {
          if key == "indicatorColors", case .object(let outputs) = content {
            for (output, color) in outputs { result[key + "/" + child + "/" + output] = color }
          } else { result[key + "/" + child] = content }
        }
      } else { result[key] = value }
    }
    return result
  }
  static func expand(_ value: [String: KanpanAccount.JSONValue]) -> [String: KanpanAccount.JSONValue] {
    var result: [String: KanpanAccount.JSONValue] = [:]
    for (path, value) in value {
      let keys = path.split(separator: "/").map(String.init)
      if keys.count == 1 { if value != .null { result[path] = value }; continue }
      var children: [String: KanpanAccount.JSONValue] = [:]
      if case .object(let old) = result[keys[0]] { children = old }
      if keys.count == 2 { if value != .null { children[keys[1]] = value } }
      else if keys.count == 3 {
        var outputs: [String: KanpanAccount.JSONValue] = [:]
        if case .object(let old) = children[keys[1]] { outputs = old }
        if value != .null { outputs[keys[2]] = value }; children[keys[1]] = .object(outputs)
      }
      result[keys[0]] = .object(children)
    }
    return result
  }
  static func settings(_ prefs: Prefs) throws -> SyncObject {
    let all = try JSONDecoder().decode([String: KanpanAccount.JSONValue].self, from: PrefsCodec.encode(prefs))
    var object = SyncObject(collection: "settings", id: "chart")
    object.body = flatten(all.filter { fields.contains($0.key) })
    object.body["rsiRange"] = .array([.number(prefs.rsiLower), .number(prefs.rsiUpper)])
    return object
  }
  static func apply(_ object: SyncObject, to local: Prefs) throws -> Prefs {
    var all = try JSONDecoder().decode([String: KanpanAccount.JSONValue].self, from: PrefsCodec.encode(local))
    let values = expand(object.body)
    for key in fields where values[key] != nil { all[key] = values[key] }
    if case .array(let range) = values["rsiRange"], range.count == 2 { all["rsiLower"] = range[0]; all["rsiUpper"] = range[1] }
    return try JSONDecoder().decode(Prefs.self, from: JSONEncoder().encode(all))
  }
  /// 换档案（登录 / 退登 / 切账号）时，从内存里那份**留在本机**、不被新档案覆盖的字段。
  ///
  /// 判据只有一条：**这是不是「这台机器自己的属性」**。本机缓存 `launchSnapshot`
  /// 只对这台机器有意义，它留在这里是对的。（从前并排的自定义域名 `apiHost` / `streamHost`
  /// 2026-09-24 删了，主机一律由 `RouteResolver` 按线路给。）
  ///
  /// **`routePolicy`（直连 / 网关那两档）2026-09-19 也进了这一堆**：它曾经跟着人走，
  /// 结果是「A 在自己的网络里选了网关同步上去，B 从没碰过线路却跟着换了一头」。
  /// 他点的是**这台手机怎么连得上行情**，不是他想让所有设备都长成什么样——
  /// 同一个账号的两台手机完全可能一台直连通、一台非走网关不可。产品规则一个字没变
  /// （两档、出厂直连、没有自动切换），变的只是这个选择不再跨设备覆盖；理由写在
  /// `PrefsFieldPlan` 的注释里，服务端为老客户端保留这个键的原因在它的 `wireOnlyKeys`。
  ///
  /// `interval`（周期）和 `keepAwake`（屏幕常亮）**2026-09-19 从这张表里拿掉了**：
  /// 早先把它们当成本机设置，结果是「换台设备登同一个账号，周期回到出厂 1h」。
  /// 按「用户用手改过的一切状态都跟着人走，无论怎么切换」这条规矩，看哪个周期、
  /// 要不要常亮都是他的习惯而不是这台手机的属性，所以两项改成随账号同步
  /// （已进 `fields`），不再在换档案时被上一份内存值盖住。
  ///
  /// 实现从「手抄四行赋值」改成了**按 `deviceOnly` 表在 JSON 键上覆盖**：清单只有
  /// `PrefsFieldPlan` 那一张，这儿加不加字段不再取决于下一个人记不记得回来改这里。
  static func keepDeviceFields(_ source: Prefs, in target: inout Prefs) {
    target = Prefs.keeping(Prefs.deviceOnlyFieldNames, of: source, over: target)
  }
  static func snapshot(_ prefs: Prefs) throws -> Data {
    // Format marker distinguishes the allowlisted snapshot from legacy full-Prefs drafts.
    var fields = try settings(prefs).body
    fields.removeValue(forKey: "compareSymbols")
    return try JSONEncoder().encode(ChartSnapshot(version: 1, fields: fields))
  }
  struct ChartSnapshot: Codable { var version: Int; var fields: [String: KanpanAccount.JSONValue] }
  static func snapshotPrefs(_ data: Data, base: Prefs = .defaults) throws -> Prefs {
    let value = try JSONDecoder().decode(ChartSnapshot.self, from: data)
    guard value.version == 1 else { throw AccountError.invalidResponse }
    var object = SyncObject(collection: "settings", id: "chart"); object.body = value.fields
    object.body.removeValue(forKey: "compareSymbols")
    var restored = try apply(object, to: base)
    restored.compareSymbols = []
    return restored
  }
  /// 一条画线发上去长什么样。
  ///
  /// body 直接来自 `Drawing` 的 `encode(to:)`，所以**标注文字那一栏的线协议在那儿定**：
  /// 带文字的工具永远写一个 `text`，清空了就写 `""`。这件事不能想当然——`SyncStore.stage`
  /// 是拿前后两份 body 逐键做差分的，一个先前有、现在没有的键会被翻译成 `text: null`
  /// （「删掉这个字段」），而服务端从前不收 `drawings.text` 的 null：用户把标注文字全删掉，
  /// 整条操作 400 被顶回来、被隔离，云端那份旧文字又写了回来。
  static func drawings(_ archive: DrawArchive) throws -> [SyncObject] {
    var output: [SyncObject] = []
    var preferences = SyncObject(collection: "drawingPreferences", id: "tools")
    preferences.body = flatten(try KanpanAccount.JSONValue.encode(archive.preferences).decode([String: KanpanAccount.JSONValue].self)); output.append(preferences)
    for (symbol, drawings) in archive.bySymbol {
      for drawing in drawings {
        var object = SyncObject(collection: "drawings", id: InstrumentID.canonical(symbol) + "/" + drawing.id)
        var value = try KanpanAccount.JSONValue.encode(drawing).decode([String: KanpanAccount.JSONValue].self)
        value.removeValue(forKey: "id"); value["anchors"] = value.removeValue(forKey: "points")
        value["symbol"] = .string(InstrumentID(symbol).symbol); value["market"] = .string(InstrumentID(symbol).market); value["venue"] = .string(InstrumentID(symbol).venue)
        object.body = value; output.append(object)
      }
    }
    return output
  }
  /// 反过来：线上那份还原成一条画线。
  ///
  /// 老服务端／老客户端留下的 `text: null` 也收：`Drawing` 的 `decodeIfPresent` 把它解成
  /// 空文字，和新写法的 `""` 同一个结果——「清空」是一个值，不是解码失败，更不能退回旧值。
  static func drawing(_ object: SyncObject) throws -> Drawing {
    var value = object.body; value["id"] = .string(String(object.id.split(separator: "/").last ?? "")); value["points"] = value.removeValue(forKey: "anchors")
    return try KanpanAccount.JSONValue.object(value).decode(Drawing.self)
  }
  /// 一条提醒发上去长什么样。
  ///
  /// 和画线同一个形状：对象 id 是 `binance/usd_m/<代号>/<提醒 id>`，身体里不放 `id`
  /// （它已经在对象 id 里了）。区别在于 `market` 这儿是**整串** `binance/usd_m`——
  /// 服务端对 `alerts.market` 就是这么卡的（`sync_validation.rs`），不是画线那种
  /// `venue` + `market` 拆两半。别照着画线想当然。
  ///
  /// 身体的 15 个键由 `Alert.encode(to:)` 一次写全，可空的那五个空就写 null——
  /// 理由见那儿的注释（省略会被 `SyncStore.stage` 读成「删掉这个字段」）。
  static func alerts(_ archive: [Alert]) throws -> [SyncObject] {
    try archive.map { alert in
      var object = SyncObject(collection: "alerts", id: InstrumentID.canonical(alert.symbol) + "/" + alert.id)
      var value = try KanpanAccount.JSONValue.encode(alert).decode([String: KanpanAccount.JSONValue].self)
      value.removeValue(forKey: "id")
      object.body = value
      return object
    }
  }

  /// 反过来：线上那份还原成一条提醒。
  ///
  /// 服务端判出触发之后写回来的就是这条路（它写的是一条 `patch`，`status` / `firedAt` /
  /// `firedPrice` 三个键），所以这里不能挑字段，整条按身体重建。
  static func alert(_ object: SyncObject) throws -> Alert {
    var value = object.body
    value["id"] = .string(String(object.id.split(separator: "/").last ?? ""))
    return try KanpanAccount.JSONValue.object(value).decode(Alert.self)
  }

  static func instrument(_ object: SyncObject) -> String {
    let parts = object.id.split(separator: "/")
    return parts.count >= 3 ? InstrumentID.canonical(parts.prefix(3).joined(separator: "/")) : ""
  }

  /// 访客档案并进账号那一刻，**真正要记进同步队列**的那几条（带导入批次号）。
  ///
  /// 只记「并进来之后盘上真的变成了访客那份」的对象，和 `AppAccountBridge.prepare`
  /// 合并盘上文件的规则一一对应：
  ///
  /// - 画线、自选、分组、提醒：只记**访客有、账号原来没有**的那几条，值取合并后的那份
  ///   （自选接在账号原有的后面，`order` 以合并后为准）。两边都有的，盘上留的是账号的，
  ///   队列里也不该出现访客那份。
  /// - 设置、画线工具偏好这两个单例：只有账号目录里原来没有那份文件、盘上整份换成了
  ///   访客的（`adopted` 里点了名），才记。
  ///
  /// 2026-09-24 以前这里是把访客那几份**原样整份**记进去。坏在冷启动：已登录的人每次
  /// 冷启动都先装一遍访客档案（它会把默认偏好写进访客目录），`account.restore()` 回来
  /// 再 `claimGuest`，于是每次冷启动都「导入」一份默认设置——同步存档的 `local` 被改成
  /// 默认值，而盘上仍是这个人自己的设置；紧接着脏标识 / `ChartLayoutReconcile` 那一步
  /// 看见两份不一样，又把这个人的设置**以当下的时间戳**重新记了一条。结果是：
  /// 哪台设备最后冷启动，它手上所有非默认的设置在云端就算「最新」，别的设备更晚做的
  /// 改动被它盖掉（P4.5 两台模拟器并发改设置的回归里复现过：B 在 T2 改的浅色压过了
  /// A 在 T3 改的深色，因为 B 冷启动时把浅色重记成了当下）。
  static func guestImport(merged: [SyncObject], guest: [SyncObject], accountBefore: [SyncObject],
                          adopted: Set<String>) -> [SyncObject] {
    let guestKeys = Set(guest.map(\.key)), existing = Set(accountBefore.map(\.key))
    return merged.filter { object in
      if object.collection == "settings" || object.collection == "drawingPreferences" { return adopted.contains(object.collection) }
      return guestKeys.contains(object.key) && !existing.contains(object.key)
    }
  }

  static func symbols(_ prefs: SymbolPrefs) -> [SyncObject] {
    var objects: [SyncObject] = []
    for (order, group) in prefs.groups.enumerated() {
      var value = SyncObject(collection: "groups", id: group.id); value.body = ["name": .string(group.name), "order": .number(Double(order))]; objects.append(value)
    }
    for (order, symbol) in prefs.favorites.enumerated() {
      var value = SyncObject(collection: "favorites", id: InstrumentID.canonical(symbol))
      value.body = ["symbol": .string(InstrumentID(symbol).symbol), "market": .string(InstrumentID(symbol).market), "venue": .string(InstrumentID(symbol).venue), "groupId": prefs.groupForSymbol[symbol].map(KanpanAccount.JSONValue.string) ?? .null, "order": .number(Double(order))]
      objects.append(value)
    }
    return objects
  }

  // MARK: - 这个客户端替哪些字段说话

  /// 一个集合里**这个版本的客户端认得、并且说了算**的那些键（拍平之后的路径，逐字相等）。
  ///
  /// 传给 `SyncStore.capture(_:device:owning:)`，那一层拿它回答一个问题：前一份 body 里有、
  /// 这一份里没有的键，到底是「用户把它清掉了」，还是「这个版本根本没听说过它」。
  ///
  /// ## 为什么非要分清这两件事
  ///
  /// `SyncStore.stage` 是拿前后两份 body 逐键做差分的，而「前一份」不一定是这台设备写的——
  /// 整份同步和增量同步都会把**云端那份**原样放进 `archive.local`。于是只要云端那个对象上
  /// 带着一个这一版模型里根本不存在的字段，下一次碰它，差分就会把它读成「这个字段被删了」，
  /// 发一个 `null` 上去。两头都是错的：
  ///
  /// - 服务端的 null 白名单很窄（只有 `color` / `groupId` / `text` 和 `settings` /
  ///   `drawingPreferences` 的嵌套路径），别的键一律 `invalid_operation`——而它是**整条操作**
  ///   拒绝，于是那条操作被隔离，`retryRejected` 重新差分又发一遍同一个 null，再被拒一次。
  ///   一个账号从此每次整份同步都白跑一趟跨洋请求，后面对这个对象的每一次编辑也一起卡死。
  ///   真实案例：云端两条文字标注上带着 `created`（`Drawing` 上压根没有这个属性，
  ///   服务端却认得——和 `PrefsFieldPlan.wireOnlyKeys` 里的 `styleID` 是同一类只活在线上的
  ///   老键），用户只是改了一下标注的样式，整条操作就 400 了。
  /// - 反过来，如果服务端**收**了这些 null，那就更糟：一个老版本客户端会把它仅仅是不认识的
  ///   字段悄悄抹掉，新版本那边的东西就这么没了。今天是服务端的拒绝挡住了这场数据丢失。
  ///
  /// 所以规矩是**一个客户端只替它认识的字段说话**：没听说过的字段既不改也不删，原样留在
  /// 对象上（`stage` 会把它从前一份 body 里带回来）。用户清掉一个**自己的**字段
  /// （比如一条线的 `color`）照旧发 null，那才是真的「删掉这个字段」。
  ///
  /// ## 这张表是算出来的，不是抄的
  ///
  /// 手抄的字段清单在这个仓库里已经咬过两次（见 `PrefsFieldPlan` 的注释、提交 `a161bb0`
  /// 与 `0f09f7e`），所以这儿一个键都不手写：全部**拿这个 codec 自己的编码器跑一遍**得出来——
  /// 给每一样东西做一份「把所有可选项都填满」的样板，编出来的键就是这一版会发的键。
  /// 往 `Drawing` 上加一个存储属性、往 `Prefs` 里加一个同步字段、往 `symbols` 里多发一个键，
  /// 这张表当场跟着变，`PersonalSyncCodecOwnedKeysTests` 那一组穷举守卫也当场对得上。
  static let ownedKeys: [String: Set<String>] = {
    do {
      var table: [String: Set<String>] = ["settings": Set(try settings(maximalPrefs).body.keys)]
      for object in try drawings(maximalDrawArchive) { table[object.collection, default: []].formUnion(object.body.keys) }
      for object in symbols(maximalSymbolPrefs) { table[object.collection, default: []].formUnion(object.body.keys) }
      for object in try alerts([maximalAlert]) { table[object.collection, default: []].formUnion(object.body.keys) }
      return table
    } catch {
      // 编这几份纯值结构不该失败（全是标准类型，没有一条会抛的路）。真失败了就交一张空表：
      // `stage` 拿不到某个集合的清单时退回老行为——照旧发 null，被服务端顶回来，
      // 也就是 2026-09-19 之前的样子。宁可退回那个已知的死法，也不能反过来变成
      // 「什么都不删」——那会让用户清掉的字段永远清不掉，而且一声不响。
      // `ownedKeysCoverEveryCollection` 把这条空表钉死成红的。
      return [:]
    }
  }()

  /// 指标输出的序号上限。
  ///
  /// `PrefsCodec` 解码 `indicatorColors` / `hiddenOutputs` 时按 `0..<21` 夹，服务端
  /// `sync_validation.rs` 的值规则也是 `n <= 20`。两边本来就是同一个数，这儿跟着它们走。
  private static let maxOutputIndex = 20

  /// 每一个同步字段都填满了的一份设置。
  ///
  /// 嵌套的那几摊（`params` / `indicatorColors` / `hiddenOutputs` /
  /// `subHeightOverrides`）拍平之后是 `<字段>/<指标>` 甚至 `<字段>/<指标>/<输出序号>`，
  /// 一份出厂设置只拍得出其中几条，所以这儿按 `IndicatorID.allCases` × `0...maxOutputIndex`
  /// 全部铺满——铺不满的话，用户把某个指标的自定义颜色清掉时，那一条就成了「外来键」
  /// 被带回来，他清的东西永远同步不上去。
  ///
  /// 铺得比真实情况宽一点是安全的：多出来的那些路径（比如主图指标的 `subHeightOverrides/MA`）
  /// 本来就是这一版自己的词汇表，而 `settings` 的嵌套 null 服务端是收的，不会堵队列。
  private static var maximalPrefs: Prefs {
    var prefs = Prefs.defaults
    let colors = Dictionary(uniqueKeysWithValues: (0...maxOutputIndex).map { ($0, Hex("#ffffff")) })
    for id in IndicatorID.allCases {
      prefs.params[id] = prefs.params[id] ?? []
      prefs.hiddenOutputs[id] = []
      prefs.indicatorColors[id] = colors
      prefs.subHeightOverrides[id] = 1
    }
    return prefs
  }

  /// 每一把工具、每一个可选字段都摆出来的一份画线存档。
  ///
  /// `Drawing.encode(to:)` 有两个条件分支：`color` 是 `encodeIfPresent`，`text` 只有带文字的
  /// 工具（或者老存档里真有文字）才写。样板把这两样都给上值，取的是**并集**——这一版能发出去
  /// 的键一个不少。**往 `Drawing` 上加一个 `encodeIfPresent` 的新属性时，这儿也要给它一个
  /// 非空值**，否则它不会进这张表，用户清空它时那一下就同步不上去。
  private static var maximalDrawArchive: DrawArchive {
    var archive = DrawArchive()
    var items: [Drawing] = []
    for kind in Drawing.Kind.allCases {
      var drawing = Drawing(id: "d", kind: kind, points: Array(repeating: DrawPoint(t: 0, p: 0), count: kind.pointCount))
      drawing.color = Hex("#ffffff")
      drawing.text = "x"
      items.append(drawing)
      archive.preferences.styles[kind.rawValue] = DrawingStyle(drawing)
    }
    // 每一族「换画法」的记忆拍平成 `variants/<面板那一格>`，三族一个不能少。
    for kind in Drawing.Kind.palette where kind.paletteHead == kind {
      archive.preferences.variants[kind.rawValue] = kind.swaps.first?.options.last?.kind ?? kind
    }
    archive.bySymbol["BTCUSDT"] = items
    return archive
  }

  /// 每一个可空字段都填了值的一条提醒。
  ///
  /// 其实 `Alert.encode(to:)` 无论如何都会把 15 个键全写出来（空就写 null），
  /// 所以这份样板填不填值都一样；**照旧把它们填满**，是为了下一个往 `Alert` 上加
  /// `encodeIfPresent` 字段的人——那种字段不给值就进不了这张表，用户清空它时那一下
  /// 就同步不上去（和画线那份样板是同一条规矩）。
  private static var maximalAlert: Alert {
    Alert(id: "a", kind: .drawing, symbol: "BTCUSDT", drawingID: "d",
          lines: [AlertLine(points: [DrawPoint(t: 0, p: 0)], extendLeft: true, extendRight: true)],
          condition: .touch, armedAt: 0, once: true, status: .active,
          firedAt: 0, firedPrice: 0, dueAt: 0, reviewID: "r", title: "x", created: 0)
  }

  /// 分类、自选、归属都齐了的一份自选表：`symbols` 每一种对象都发得出来。
  private static var maximalSymbolPrefs: SymbolPrefs {
    SymbolPrefs(favorites: ["BTCUSDT"], groups: [FavoriteGroup(id: "g", name: "g")],
                groupForSymbol: ["BTCUSDT": "g"])
  }
}
