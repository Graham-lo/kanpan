import Foundation
import Observation
import KanpanCore
import KanpanData

/// 存档落在哪儿。真机上是 `UserDefaults.standard`，单测里换成内存里的一份。
protocol PrefsStorage: AnyObject, Sendable {
  func prefsData(forKey key: String) -> Data?
  func setPrefsData(_ data: Data?, forKey key: String)
}

extension UserDefaults: PrefsStorage {
  func prefsData(forKey key: String) -> Data? { data(forKey: key) }
  func setPrefsData(_ data: Data?, forKey key: String) {
    if let data { set(data, forKey: key) } else { removeObject(forKey: key) }
  }
}

/// 单测与 `#Preview` 用：不碰真沙盒。
final class InMemoryPrefsStorage: PrefsStorage, @unchecked Sendable {
  private let lock = NSLock()
  private var box: [String: Data]

  init(_ seed: [String: Data] = [:]) { box = seed }

  func prefsData(forKey key: String) -> Data? {
    lock.lock(); defer { lock.unlock() }
    return box[key]
  }

  func setPrefsData(_ data: Data?, forKey key: String) {
    lock.lock(); defer { lock.unlock() }
    box[key] = data
  }

  /// 断言用：现在盘上有哪些键。
  var keys: [String] {
    lock.lock(); defer { lock.unlock() }
    return box.keys.sorted()
  }
}

/// 四个面板共用的一份设置。主线程独占，`@Observable`，改一下就落盘。
///
/// 面板里没有「确定」也没有「取消」（§10.6）：任何一改都立刻生效、立刻存。
@MainActor
@Observable
final class PrefsStore {

  /// 当前设置。只能经 `update` 改，保证「改了必存」。
  private(set) var prefs: Prefs

  /// 最近一次要说的那句话（换下了哪个副图、参数越界、域名不对）。
  /// 面板拿它弹 toast，弹完调 `clearNotice()`。
  private(set) var notice: String?

  /// 这句话右边那颗「撤销」。nil 就是一条普通提示，不画按钮。
  ///
  /// 不参与 `@Observable` 追踪（闭包本身没法比较），但它永远和 `notice` 同一拍赋值，
  /// 视图因为读了 `notice` 就会重算，读得到最新的这一份。
  @ObservationIgnored private(set) var noticeUndo: (() -> Void)?

  /// 行情缓存占用（A6.11）。没量过是 nil，设置页进来量一次。
  private(set) var cacheUsage: MarketCacheUsage?

  @ObservationIgnored private var storage: any PrefsStorage
  @ObservationIgnored var onChange: ((Prefs) -> Void)?
  /// 整份设置被换掉了（装档案 / 换号 / 退登 / 云端落地 / 恢复出厂 / 撤销）。
  ///
  /// 和 `onChange` 的分工：`onChange` 是「这个人改了一项，记下来、推上去」；
  /// 这一个是「手上这份档案换人了」，接的人要拿它重新起点。`ChartViewport` 靠它
  /// 决定「手上还没落盘的那一捏」是保还是弃——`reason` 就是为这件事带的。
  @ObservationIgnored var onAdopt: ((Prefs, ChartLayoutArrival) -> Void)?
  @ObservationIgnored private let cache: any MarketCacheStore

  // ---------------------------------------------------------------- 状态标识
  //
  // 「值 + 属主 + 脏字段集 + 修改时间」里除了值以外的那三样，形状见 `SettingsStamp`。
  // 这一层暂时兼着 M1 `PersonalStore` 的活：抽出去的时候整块搬走，形状不用改。

  /// 脏标识跟着**真身**走：它和 `prefs.json` 同一个柜子，换档案就换一份。
  /// 所以「A 的脏标识算不到 B 头上」是天然成立的，`owner` 只是再兜一层。
  @ObservationIgnored private(set) var stamp: SettingsStamp

  /// 哨兵跟着**这台机器**走，和真身**不在同一层**（真身在账号目录里的 prefs.json，
  /// 它在 `UserDefaults`）。同一层就会一起消失，「第一次装」和「被清空」就分不出来了。
  @ObservationIgnored private let sentinelStorage: any PrefsStorage
  @ObservationIgnored private(set) var sentinel: SettingsSentinel

  /// 最近一次装档案时，本地那份的体检结论。
  @ObservationIgnored private(set) var verdict: SettingsCacheVerdict = .intact

  /// 还没推上去的那些字段。
  var dirtyFields: Set<String> { stamp.dirtyFields }
  /// 交给推送方的那一份快照（字段 → 改动时刻）。推成功之后原样交回 `syncPushed`。
  var dirtyMarks: [String: Double] { stamp.dirty }

  /// 这台机器上这份设置该落在哪。
  ///
  /// 以前这段挑选埋在 `init` 里，而 `storage` 还带一个 `= UserDefaults.standard` 的
  /// 默认值——于是「不写参数」看着像「用默认的」，实际是「悄悄落到 UserDefaults」。
  /// `SymbolPrefsStore()` 就是这么把「上次看的那张图」读到另一个柜子里去的（R3-1）。
  /// 现在存哪儿必须在建store的地方写出来，这个函数只是把那句话写短一点。
  static func deviceStorage() -> any PrefsStorage {
    #if DEBUG
    guard ProcessInfo.processInfo.environment["KANPAN_TEST_PROFILE"] == "1" else { return UserDefaults.standard }
    if let profile = ProcessInfo.processInfo.environment["KANPAN_PERSISTENCE_PROFILE"],
       UUID(uuidString: profile) != nil, let defaults = UserDefaults(suiteName: "kanpan.tests." + profile) {
      return defaults
    }
    return InMemoryPrefsStorage()
    #else
    // Release 包里没有测试模式这回事：柜子只有一个。
    return UserDefaults.standard
    #endif
  }

  /// - Parameter fallback: 这个柜子里还没有存档时，从哪一份 `Prefs` 起步。
  ///   默认是出厂值；`MainScreen` 传的是 `LaunchThemeMirror.prefs()`——设置的真身在
  ///   账号目录里，第一帧之前读不到，皮肤与深浅先按本机镜像铺，见 `LaunchThemeMirror`。
  /// - Parameter sentinel: 哨兵落在哪一层。**不要和 `storage` 传同一个柜子**——
  ///   真身以后会被 `useStorage` 换成账号目录里的那份，哨兵必须留在这台机器上，
  ///   否则「档案被清空」和「第一次装」分不出来。不传就先和 `storage` 同层
  ///   （登录之前本来就只有这一层，没什么可分辨的）。
  init(storage: any PrefsStorage,
       cache: any MarketCacheStore = MarketCacheFactory.make(),
       fallback: Prefs = .defaults,
       sentinel: (any PrefsStorage)? = nil) {
    let selectedStorage = storage
    self.storage = selectedStorage
    self.cache = cache
    let sentinelStorage = sentinel ?? selectedStorage
    self.sentinelStorage = sentinelStorage
    self.sentinel = PrefsStore.storedSentinel(in: sentinelStorage)
      ?? SettingsSentinel(install: UUID().uuidString)
    self.stamp = PrefsStore.storedStamp(in: selectedStorage) ?? SettingsStamp()
    self.prefs = PrefsStore.load(from: selectedStorage, fallback: fallback)
    // UI 测试沙盒里的常用行自己铺一套，不跟着出厂默认走。
    //
    // 出厂默认是 `5m 30m 1h 4h 1d 1w`（2026-09-21 放满六格），里头没有 1m / 15m，
    // 而 `ChartFoundationUITests` 里直接按 `interval.chip.1m` 找 chip 的那几处要点得着
    // ——那个文件是禁改的契约文件。那几条用例要验的是「点哪一档图就换到哪一档」，
    // 不是「出厂钉了哪几档」，所以沙盒里按它们要的那六档铺，
    // 真正的出厂默认交给 `PrefsDefaultsTests` 在单元层面守。
    // 只在测试沙盒、且这轮还没有任何存档时生效，用例自己钉过的照样按存档走。
    // 种子只在 Debug 包里存在：Release 里这几行连编都不编（A.4）。
    #if DEBUG
    if ProcessInfo.processInfo.environment["KANPAN_TEST_PROFILE"] == "1",
       selectedStorage.prefsData(forKey: PrefsCodec.key) == nil {
      self.prefs.quickIntervals = PrefsStore.uiTestQuick
      if let raw = ProcessInfo.processInfo.environment["KANPAN_TEST_COMPARE_SYMBOLS"] {
        self.prefs.compareSymbols = Prefs.cleanCompareSymbols(raw.split(separator: ",").map(String.init))
      }
      // UI 用例要验网关那条线路（OKX 历史）时从这儿起步，不用在用例里去点设置。
      if let raw = ProcessInfo.processInfo.environment["KANPAN_TEST_ROUTE_POLICY"],
         let policy = MarketRoutePolicy(rawValue: raw) {
        self.prefs.routePolicy = policy
      }
      // 不经 XCUITest、直接 `simctl launch` 起的长时取证（M5 的 30 分钟 1 分钟图）从这一档开张：
      // 深链要过系统那句「在 Hkline 中打开？」，没有测试进程就没人去点。
      if let raw = ProcessInfo.processInfo.environment["KANPAN_TEST_INTERVAL"], let interval = Interval(rawValue: raw) {
        self.prefs.interval = interval
      }
    }
    #endif
    mirrorToDevice()
  }

  /// 把「比档案先到的人要读的那几项」镜像到本机。
  ///
  /// 三个去处，理由是同一个：**要读它们的人比档案先到，或者根本不该认识 `Prefs`。**
  ///
  /// - 线路：真身在 `prefs.routePolicy`（2026-09-19 起是本机字段，不随账号同步），
  ///   而 `KanpanData` 那边的 `RoutedMarketFeed` 只认 `MarketRoutePolicyStore`。
  ///   镜像挂在**落盘**那一步（`init` / `persist` / `useStorage` / `applySynced` 都调它），
  ///   所以用户在设置里点一下就走 `update` → `persist` → 这里，和同步那条路没关系。
  ///   没变的话 `set` 自己会跳过，不会把行情重开。
  /// - 域名：`LaunchPrewarm` 跑在账号桥把档案装进来之前，只能读本机的一份，
  ///   见 `LaunchHostMirror`。
  /// - 皮肤与深浅：第一帧的底色就要用它，而登录过的人那份档案要等
  ///   `account.restore()` 异步回来，见 `LaunchThemeMirror`。
  private func mirrorToDevice() {
    MarketRoutePolicyStore.set(prefs.routePolicy)
    LaunchHostMirror.set(api: prefs.apiHost, stream: prefs.streamHost)
    LaunchThemeMirror.set(skin: prefs.skin, theme: prefs.theme)
  }

  /// 见上：UI 测试沙盒专用的常用行。
  /// 六档——和 `Prefs.maxQuick`、和出厂默认一样满钉，用例要量的就是「钉满时这一行还排得下」。
  /// 2026-09-21 从七档收到六档：上限改成 6 之后，七档的沙盒会让条上少画一档，
  /// 量出来的不是产品行为。档位本身和出厂那六档不同（这儿有 1m / 15m），
  /// 为的是让契约用例按 `interval.chip.1m` 点得着。
  static let uiTestQuick: [Interval] = [.m1, .m5, .m15, .m30, .h1, .h4]

  // ---------------------------------------------------------------- 读

  /// 柜子是空的（全新安装、或这台机器上这个人还没落过盘）时用 `fallback` 起步；
  /// 有存档就以存档为准，`fallback` 一个字也不掺。
  static func load(from storage: any PrefsStorage, key: String = PrefsCodec.key,
                   fallback: Prefs = .defaults) -> Prefs {
    guard let data = storage.prefsData(forKey: key), !data.isEmpty else { return fallback }
    return PrefsCodec.decode(data)
  }

  // ---------------------------------------------------------------- 写
  //
  // 这一层有一条通用规矩，改任何偏好之前先读一遍：
  //
  //   **内存即时，落盘节流。**
  //
  // 「体验类设置」——皮肤、根宽、副图高度、指标选择、翻转、周期……凡是属于
  // 「我习惯怎么用」的那一类，都跟着人走：所有品种、所有周期、所有页面共用一份，
  // 跨 app 重启保留。而且**一旦改动必须实时跟随**：用户改完立刻换品种、换周期、
  // 开另一张图，那一下读到的必须已经是新值。
  //
  // 所以：
  //
  // 1. **内存里那一份当场就改**，读取方一律读内存（`prefs`）。
  //    **任何读取路径都不许回头去读 `UserDefaults`** —— 盘上那份可能还没跟上，
  //    而且那是冷启动才需要的东西。
  // 2. **写盘可以在手势进行中降采样**，但只在「这个值会每帧变一次」时才需要
  //    （双指缩放的根宽是唯一一例，那件事已经整个搬去 `ChartViewport` 了）。
  //    离散动作（点一下、双击一下、手势松手那一下）直接走 `update`，它自己会挡住
  //    没真改动的那些回调。
  //
  // 2026-09-19 补一条，这条比上面两条都硬：
  //
  //   **「落盘节流」的下限是「用户的手离开屏幕」。**
  //
  // 根宽以前是 400ms 定时器写的，于是「捏完立刻杀 app」必丢——用户报的就是这个。
  // 现在保存时机钉在手指抬起那一刻（`ChartViewport.interactionEnded`），
  // 切后台那一刀只是兜底。别再给任何一项偏好加「等一会儿再写」的定时器。
  //
  // 看到某处「手势改完了内存值却要等一会儿才更新」，那是 bug，不是设计。

  /// 唯一的改法。没真改动就不落盘，免得每次滑动都写一遍。
  func update(_ change: (inout Prefs) -> Void) {
    var next = prefs
    change(&next)
    guard next != prefs else { return }
    let changed = Prefs.changedStampedFields(from: prefs, to: next)
    prefs = next
    persist(marking: changed)
  }

  /// 带提示的改法：`change` 返回一句话就说明这次没改成（原型的 toast）。
  func attempt(_ change: (inout Prefs) -> String?) {
    var next = prefs
    let why = change(&next)
    if let why { note(why); return }
    guard next != prefs else { return }
    let changed = Prefs.changedStampedFields(from: prefs, to: next)
    prefs = next
    persist(marking: changed)
  }

  /// 开 / 关一个指标。
  ///
  /// 单独开一个口子而不是走 `attempt`：副图满三个时 `toggle` 是**改成了**并且带一句话
  /// （「已换下 VOL」），`attempt` 把「有话说」一律当成没改成，会把这一改吞掉。
  /// 顺手把改动前的整份 `Prefs` 扣在闭包里，toast 上那颗「撤销」按下就整份还原。
  func toggleIndicator(_ id: IndicatorID) {
    let before = prefs
    var next = prefs
    let why = next.toggle(id)
    guard next != prefs else { return }
    let changed = Prefs.changedStampedFields(from: prefs, to: next)
    prefs = next
    persist(marking: changed)
    if let why { note(why, undo: { [weak self] in self?.restore(before) }) }
  }

  // ---------------------------------------------------------------- 图上量出来的习惯

  /// 记下主图 / 副图的上下翻转。
  ///
  /// 这个不节流：它是一次双击就翻一下的离散动作，一次写一次；`update` 自己会挡住
  /// 没真改动的那些回调（图每改一次状态都会报一遍）。
  func noteInversion(main: Bool, subs: Set<IndicatorID>) {
    update { $0.mainInverted = main; $0.subInverted = subs }
  }

  /// 说一句话。`undo` 给了就在 toast 右边画一颗「撤销」。
  func note(_ text: String, undo: (() -> Void)? = nil) {
    noticeUndo = undo
    notice = text
  }

  func clearNotice() { notice = nil; noticeUndo = nil }

  /// 把整份设置还原成某个时刻的样子（「撤销」走这条路）。
  func restore(_ value: Prefs) {
    clearNotice()
    guard value != prefs else { return }
    let changed = Prefs.changedStampedFields(from: prefs, to: value)
    prefs = value
    persist(marking: changed)
    // 撤销 = 整份换掉，等同换属主：手上还欠着的那一下属于被撤销掉的那份，作废。
    onAdopt?(prefs, .ownerSwitched)
  }

  /// 恢复出厂：把当前键抹掉，回到新默认。
  func resetToDefaults() {
    let changed = Prefs.changedStampedFields(from: prefs, to: .defaults)
    prefs = .defaults
    persist(marking: changed)
    onAdopt?(prefs, .ownerSwitched)
  }

  /// 落盘 + 记脏 + 记时间，**同一步、同步完成**。
  ///
  /// 「推云端」才是异步的那一半，而且**推成功才清脏字段**（`syncPushed`）。
  /// 推失败、断网、app 被杀，脏标识都留着，下次启动本地照样赢——用户要的
  /// 「避免云端没同步，下次进来对不上又覆盖回去」就靠这个顺序。
  private func persist(marking changed: Set<String> = []) {
    if !changed.isEmpty {
      let now = SettingsClock.now()
      stamp.mark(changed, at: now)
      sentinel.owner = stamp.owner
      sentinel.wroteAt = now
    }
    storage.setPrefsData(PrefsCodec.encode(prefs), forKey: PrefsCodec.key)
    if !changed.isEmpty { writeStamp(); writeSentinel() }
    mirrorToDevice()
    onChange?(prefs)
  }

  /// 服务端认掉了。**只有这一条路能清脏标识。**
  ///
  /// - Parameters:
  ///   - pushed: 推上去那一刻的脏字段快照。只清「时刻没变的」那几个，推的过程中
  ///     用户又改过的那些留着（见 `SettingsStamp.clear`）。
  ///   - acked: 服务端**真收下了**的那些**线上键名 / 路径**。嵌套字段在线上是拍平的
  ///     （`params/MA`、`indicatorColors/MACD/0`），`rsiRange` 会映回上下轨两个字段，
  ///     映射见 `SettingsWire`。
  ///   - dropped: 同一批里**没落地**的那些线上键名 / 路径：被 `droppedFields` 顶回来的、
  ///     没回执的、被隔离的。一个顶层字段在线上是好几条路径，只要有一条在这儿，
  ///     那个字段的脏标识就得留着——否则等于把没推上去的那一改当成推过了。
  ///
  /// 「发出去了」不算成功——真正的成功是 `SyncPushResponse` 里按 `operationId`
  /// 对上的那几条（`SyncStore.acknowledge`）。断网、服务端拒绝、半路被杀，
  /// 脏标识一个都不许清，下次启动本地照样赢。
  func syncPushed(_ pushed: [String: Double], acked: Set<String>, dropped: Set<String> = []) {
    guard !pushed.isEmpty, !acked.isEmpty else { return }
    let before = stamp
    let now = SettingsClock.now()
    stamp.clear(acked: acked, dropped: dropped, from: pushed, at: now)
    guard stamp != before else { return }
    sentinel.pushedAt = now
    writeStamp(); writeSentinel()
  }

  /// 存档里那份和手上这份**已经一致**、队列里也没有它的操作的脏字段——清掉。
  ///
  /// 清脏标识本来只有 `syncPushed` 一条路：推上去、服务端认下、按字段清。可有一种
  /// 脏字段永远走不到那条路：它被记脏的那一刻**没产生操作**（`SyncStore.stage` 比出来
  /// 手上这份和存档 `local` 一模一样，就不记；或者当时正在应用云端那份、记账被
  /// `ApplyGate` 挡了，事后再比也已经一样）。没有操作就没有 ACK，没有 ACK 就永远脏——
  /// 2026-09-19 在真机取证抓到的正是这个：`interval` 从 13:25:07 起一直脏着，
  /// 盘上、存档、云端三处却都是同一个 `4h`，队列里一条操作都没有。
  ///
  /// 后果不是值错，是**这个字段从此不再跟着人走**：`applySynced` / `applyPending` 拿
  /// 脏字段当「本地更新、别覆盖」的依据，另一台设备改了周期，这台永远不认。
  ///
  /// 判「一致」的活由桥那边做（它才看得见存档和队列），这儿只负责清：这些字段的
  /// 时刻取当前快照，等于「就在此刻推成功了」。
  func syncAgreed(_ fields: Set<String>) {
    let marks = stamp.dirty.filter { fields.contains($0.key) }
    guard !marks.isEmpty else { return }
    stamp.clear(marks, at: SettingsClock.now())
    writeStamp()
  }

  private func writeStamp() { storage.setPrefsData(try? JSONEncoder().encode(stamp), forKey: SettingsStamp.storageKey) }
  private func writeSentinel() { sentinelStorage.setPrefsData(try? JSONEncoder().encode(sentinel), forKey: SettingsSentinel.storageKey) }

  static func storedStamp(in storage: any PrefsStorage) -> SettingsStamp? {
    storage.prefsData(forKey: SettingsStamp.storageKey).flatMap { try? JSONDecoder().decode(SettingsStamp.self, from: $0) }
  }
  static func storedSentinel(in storage: any PrefsStorage) -> SettingsSentinel? {
    storage.prefsData(forKey: SettingsSentinel.storageKey).flatMap { try? JSONDecoder().decode(SettingsSentinel.self, from: $0) }
  }

  /// 这份字节解得开、字段齐不齐。解不开或者连版本号都没有就算「损坏 / 不完整」。
  static func isReadable(_ data: Data?) -> Bool {
    guard let data, !data.isEmpty,
          let object = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else { return false }
    return object["v"] != nil
  }

  /// 换档案（装访客档案 / 登录 / 换号 / 退登）：线路跟着档案走，登录后用的是账号里记的那条。
  ///
  /// - Parameter arrival: 这是「同一个人的档案晚到了」还是「换了个人」。调用方
  ///   （`AppAccountBridge.prepare`）知道上一次装的是谁，只有它分得清；
  ///   分不清的后果见 `ChartViewport.adopt(barSpacing:reason:)`——冷启动图一出来
  ///   立刻捏、300ms 后档案回来，那一捏会被无条件作废掉。
  /// - Parameter owner: 现在这份档案该是谁的（账号 id / 访客档案 id）。用来体检：
  ///   档案里记着别人的名字就当它不存在，**绝不能用**（防「B 登进来看到 A 的东西」）。
  func useStorage(_ storage: any PrefsStorage, prefs: Prefs, arrival: ChartLayoutArrival, owner: String = "") {
    // 先体检，再换手：诊断要看的是这个柜子里原来躺着什么。
    let archived = storage.prefsData(forKey: PrefsCodec.key)
    let found = PrefsStore.storedStamp(in: storage)
    verdict = SettingsCacheDoctor.diagnose(archive: archived, readable: PrefsStore.isReadable(archived),
                                           stamp: found, sentinel: sentinel, owner: owner)
    self.storage = storage; self.prefs = prefs
    switch verdict {
    case .ownerMismatch:
      // 上一个人留下的那份脏标识跟这个人没关系，从头记。
      stamp = .fresh(owner: owner)
    default:
      stamp = found ?? .fresh(owner: owner)
      stamp.owner = owner
    }
    storage.setPrefsData(PrefsCodec.encode(prefs), forKey: PrefsCodec.key)
    writeStamp()
    mirrorToDevice()
    onAdopt?(prefs, arrival)
  }

  /// 云端那份落地。**这是「合并」，不是「覆盖」。**
  ///
  /// 合并规则（用户 2026-09-19 定的）：
  ///
  /// - **本地脏的字段一律跳过**——它说明「用户刚改的，还没推上去」，盖回去就是
  ///   用户说的「相当于没改」。
  /// - 干净的字段跟着云端走。谁新由服务端那一侧的 `revision` 单调序回答
  ///   （`SyncStore.receive` 只收比本地新的那一版），比拿两边的墙上钟去比可靠；
  ///   `SettingsStamp.updatedAt` 留着给 M1 做本地侧的比较。
  func applySynced(_ value: Prefs) {
    let merged = Prefs.keeping(stamp.dirtyFields, of: prefs, over: value)
    guard merged != prefs else { return }
    prefs = merged
    storage.setPrefsData(PrefsCodec.encode(merged), forKey: PrefsCodec.key)
    mirrorToDevice()
    // 云端落地是同一个人的档案到货，不是换人。
    onAdopt?(prefs, .sameProfile)
  }

  // ---------------------------------------------------------------- 缓存

  func refreshCacheUsage() async {
    cacheUsage = await cache.usage()
  }

  /// 清缓存（A6.11）：清完顺手再量一次，数字当场归零。
  func clearCache() async {
    await cache.clear()
    cacheUsage = await cache.usage()
  }

  /// 「撤销」给多长时间。和提示条带撤销时的停留时间是同一个数（`ToastCenter.undoSeconds`），
  /// 测试里调短。
  @ObservationIgnored var undoWindow: Duration = .seconds(5)
  @ObservationIgnored private var pendingClear: Task<Void, Never>?

  /// 设置页那颗「清除」（P2.7）：先说「已清缓存 · 撤销」，撤销的机会过了才真的清。
  ///
  /// 缓存删了就回不来（要重新下载），所以撤销只能是「还没动手」：在提示条消失之前
  /// 盘上一个字节都不碰。提示期间 app 被杀，这次就当没清——他没等到那一刻。
  func clearCacheLater() {
    pendingClear?.cancel()
    let wait = undoWindow
    pendingClear = Task { [weak self] in
      try? await Task.sleep(for: wait)
      guard !Task.isCancelled, let self else { return }
      self.pendingClear = nil
      await self.clearCache()
    }
    note("已清缓存", undo: { [weak self] in
      self?.pendingClear?.cancel()
      self?.pendingClear = nil
    })
  }
}

// MARK: - 图的视野那一侧要的起点与去处

/// `PrefsStore` 暂时兼着 M1 `PersonalStore` 的活：图的视野向它要起点、把结果交回去。
/// 下一轮抽出 `PersonalStore` 之后，把这个 conformance 整块搬过去即可，
/// `ChartViewport` 一个字都不用改。
extension PrefsStore: ChartViewport.Owner {
  var storedBarSpacing: Double { prefs.barSpacing }
  func storeBarSpacing(_ value: Double) { update { $0.barSpacing = value } }
}
