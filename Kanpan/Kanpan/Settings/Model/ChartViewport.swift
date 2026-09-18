import Foundation
import KanpanCore

/// 档案里那份根宽到货时，是「同一个人的档案晚到了」还是「换了个人」。
///
/// 这两件事对「手上还没落盘的那一捏」意义完全相反，见 `ChartViewport.adopt(barSpacing:reason:)`。
enum ChartLayoutArrival: Equatable {
  /// 同一个人：冷启动装访客档案、`account.restore()` 把登录态读回来、云端那份落地。
  /// 手上那一捏是**他刚做的动作**，要保住。
  case sameProfile
  /// 真换了属主：换号、退登、恢复出厂。手上那一捏属于上一份档案，作废。
  case ownerSwitched
}

/// 图的视野住哪儿：根宽（缩放）、以及「什么时候把它记下来」。
///
/// # 为什么要有这么一层（M2）
///
/// 用户 2026-09-19 报的现象是：「打开 app 进入选择 BTC 缩小后，立马退出后台冷启动，
/// 回来并不是我缩小后的样子。」查下来根宽这一个值有**三个真身**：
///
/// - `Prefs.barSpacing`：盘上（以及云端）那一份，冷启动读它；
/// - `PrefsStore.liveBarSpacing`：内存那一份，换品种/换周期时拿它开新图；
/// - `ChartState.view`：图自己正画着的那一份。
///
/// 三份之间没有谁说了算，于是有两条独立的杀法：
///
/// **杀法甲 · 图把自己的开张宽度当成用户意图报回来（不需要服务器参与）。**
/// 登录的人冷启动时，档案要等 `account.restore()` 那条异步链才到，图早就按出厂的 4pt
/// 开完张了。档案到货只改了内存那一份（2pt），**图还画在 4pt 上**——`resetSpacing`
/// 只有 `.reset` 那一支会消费，`.switchInterval` / `.resize` 都是从图自己身上取宽度。
/// 接着随便来一次视野变化（新 K 线追加、一次拖动、转屏），图就把自己身上那 4pt
/// 当成「用户现在要这么宽」报了回来，把用户的 2pt **主动覆盖写掉**，还顺手推给云端。
/// 用户那个值不是没读出来，是**被写掉了**。
///
/// **杀法乙 · 云端那份旧值回头把本地盖掉。** 见 `ChartLayoutReconcile`。
///
/// # 这层立的三条规矩
///
/// 1. **只有用户手上的动作才算数。** 程序自己造成的视野变化（`.reset` / `.resize` /
///    `.switchInterval` / `.adopt` / 「回到最新」）一律**不**回灌成用户意图。
///    实现上靠 `ChartView.onUserViewChanged`——它只在手势那条路上响。这一条就是杀法甲的全部。
/// 2. **用户手离开画布的那一刻，就地落盘 + 就地同步。** 不是「过 400ms」，不是
///    「等切后台」，不是「等下一轮同步」。用户的原话是「用户手离开的瞬间就应该做同步
///    做持久保存啊」。手势**进行中**的 400ms 节流降格成纯降采样，只决定「手还按着的时候
///    盘上是第几帧」，不参与任何一次读取，也不再是保存时机；切后台那一刀降格成兜底。
/// 3. **档案晚到要能让图重新起点。** 到货之后不是只改内存，还要让图按新宽度重量一次
///    （`ViewIntent.adopt`），否则图身上那份错的宽度早晚会按规矩 1 之外的路子漏回去。
///
/// # 登录与没登录是同一个功能
///
/// 用户的原话是「本身就算登录或者本地这个布局都是一个功能，所以放到一起全部处理好，
/// 无非是云端还是本地」。所以外面（`ChartHost` / `MainScreen`）看不到也不许看登录状态，
/// 它们调的是同一组语义入口；「还要不要往云上记一笔」是这层内部的一个分支
/// （`sync` 装上了就记，没登录就是 `nil`）。
@MainActor
final class ChartViewport {

  /// 「这个人的状态住哪」那一侧。现在是 `PrefsStore`，下一轮会换成 M1 `PersonalStore`——
  /// 所以这里只认这个协议，不认具体是谁。
  ///
  /// 「向它要起点、把结果交回去」就是这两个方法的全部意思。
  @MainActor protocol Owner: AnyObject {
    /// 档案里记着的根宽（冷启动读的那一份）。
    var storedBarSpacing: Double { get }
    /// 把根宽落进档案。实现方自己挡住「没真改动」的那些。
    func storeBarSpacing(_ value: Double)
  }

  /// 这份值往云上走的那一小段。登录时由 `AppAccountBridge` 装进来，没登录就是 `nil`。
  ///
  /// 故意只暴露三个**动作**、不暴露任何状态：这层不该知道「有没有登录」「同步到哪一步了」
  /// 「存档长什么样」。什么时候调它们由这层决定（见 `settle()`）。
  @MainActor protocol Sync: AnyObject {
    /// 把此刻这份设置记成一条待发操作。**不去抖**——调它的时刻就是该记下的时刻。
    /// 没真变过就什么都不记（由实现方自己比）。
    func recordLayout()
    /// 把同步存档队列里欠着的写立刻落到盘上，**等它写完才返回**。
    /// 存档的写排在后台串行队列上，不等一下的话「手一松就杀 app」照样丢。
    func flushLayoutArchive()
    /// 把待发操作推给服务端。不等结果，推不上去也不影响本地那份已经落好的盘。
    func pushLayout()
  }

  private weak var owner: (any Owner)?
  weak var sync: (any Sync)?

  /// 图**该**有多宽，内存里的那一份。
  ///
  /// 谁来读都是最新的：用户捏完**立刻**换周期、换品种、开另一张图，新图按的就是这个。
  /// `Prefs.barSpacing` 是落到盘上的那一份，管的是下次冷启动。
  private(set) var barSpacing: Double

  /// 手势进行中还没落盘的那个根宽。手一抬（或节流到点）就清空。
  private var pending: Double?
  /// 手势进行中的落盘降采样。见类型注释规矩 2：它**不是**保存时机。
  private var throttle: Task<Void, Never>?
  /// 手势中降采样的窗口。
  private static let throttleMilliseconds = 400

  /// 档案到货、要让图按新宽度重量一次时 +1。`ChartHost` 只认这个数变没变。
  ///
  /// 为什么要个计数器而不是直接传值：图可能正好已经画在这个宽度上了（那就什么都不用做），
  /// 而「档案到货」是一个**事件**，不是一个值——用值去比会漏掉「到货的值恰好等于图上那个」
  /// 的情形，也会把普通的 SwiftUI 重算误当成一次到货。
  private(set) var adoptToken = 0

  init(owner: any Owner) {
    self.owner = owner
    self.barSpacing = owner.storedBarSpacing
  }

  // ---------------------------------------------------------------- 外面报告发生了什么

  /// **用户**正在缩放（`ChartHost` 只把手势来源的视野变化喂进来，一帧一次）。
  ///
  /// 内存立刻认；盘上等手抬起来（`settled()`），手一直按着超过 400ms 就先垫一次盘。
  func userIsZooming(to value: Double) {
    let want = Prefs.clampSpacing(value)
    guard abs(want - barSpacing) > 0.001 else { return }
    barSpacing = want
    pending = want
    throttle?.cancel()
    throttle = Task { [weak self] in
      try? await Task.sleep(for: .milliseconds(Self.throttleMilliseconds))
      guard !Task.isCancelled else { return }
      self?.settle()
    }
  }

  /// **手指全部离开画布了。** 落盘与同步就钉在这一刻（规矩 2）。
  ///
  /// 这一下每次抬手都会来（拖、甩、点、捏都算），所以 `settle()` 自己挡住「什么都没改」
  /// 的那些——没有欠账时它是一次纯比较，不写盘也不惊动同步。
  func interactionEnded() { settle() }

  /// app 要离开前台了。**兜底，不是保存时机**——正常情况下它到的时候已经没有欠账了。
  ///
  /// 这是「退到后台」这件事在视野这条线上的**唯一**入口，由 `AppLifecycle` 按固定次序叫；
  /// 以前是 `MainScreen` 的 `scenePhase` 和 `AppAccountBridge` 的
  /// `didEnterBackgroundNotification` 两个钩子各写各的，谁先谁后没人定义，而它们的
  /// 正确顺序是**先产生数据、后排空队列**。
  func willLeaveForeground() { settle() }

  /// 档案里那份根宽到货了（装档案 / 云端落地 / 恢复出厂 / 撤销）。
  ///
  /// - 手上要是还捏着没落盘的那一下：
  ///   - `.sameProfile` —— 那是**用户刚做的动作**，比档案里那份新，保住它，并且当场落盘。
  ///     这修的是「冷启动图一出来立刻捏、300ms 后 `restore()` 回来、那一捏彻底蒸发」。
  ///   - `.ownerSwitched` —— 真换了人，作废。
  /// - 没有欠账时以档案为准，并且**让图重新起点**（`adoptToken` +1）：只改内存不改图的话，
  ///   图身上那份开张时的出厂宽度早晚会漏回去（杀法甲）。
  func adopt(barSpacing value: Double, reason: ChartLayoutArrival) {
    if pending != nil, reason == .sameProfile {
      settle()                                  // 用户刚做的那一下赢，顺手落盘
      return
    }
    throttle?.cancel(); throttle = nil; pending = nil
    let want = Prefs.clampSpacing(value)
    barSpacing = want
    adoptToken &+= 1
  }

  // ---------------------------------------------------------------- 里面决定什么时候落

  /// **唯一的落盘 + 同步点。** 顺序有讲究，不要调换：
  ///
  /// 1. 把手势里欠着的根宽交给档案那一侧（`Owner` 自己挡住没真改动的）；
  /// 2. 本地那份这时已经在盘上了（`PrefsStore.update` → `persist()` 是同步写）；
  /// 3. 让同步那边把这份设置记成一条**待发操作**——这一步不能省，理由见
  ///    `ChartLayoutReconcile`：有了待发操作，云端拉回来的旧值才盖不住它；
  /// 4. 把存档队列里欠的写**等着**落到盘上；
  /// 5. 最后才谈推给服务端。推得上去最好，推不上去也不影响前四步——本地那份已经稳了。
  ///
  /// 第 3、4、5 步在没登录时不存在（`sync == nil`），其余一模一样。这就是「登录和本地
  /// 是同一个功能」在代码上的样子：分支只有这一处，而且在这层里面。
  private func settle() {
    throttle?.cancel(); throttle = nil
    guard let want = pending else { return }
    pending = nil
    owner?.storeBarSpacing(want)
    guard let sync else { return }
    sync.recordLayout()
    sync.flushLayoutArchive()
    sync.pushLayout()
  }
}

/// 本地那份和云端那份打架时算谁的。
///
/// # 病根（取证抓到的）
///
/// 登录之后同一份设置有三个副本：盘上的 `prefs.json`（用户亲手写下的，本机唯一的真相）、
/// 同步存档 `sync-v1.json` 里的 `local["settings:chart"]`（「上次记给服务端的那份」的影子）、
/// 内存里的 `PrefsStore.prefs`。冷启动装档案时（`AppAccountBridge.prepare`）原来这么写：
///
///     for object in initial where archive.local[object.key] == nil { archive.local[object.key] = object }
///
/// **只在缺的时候播种**。于是存档里那份陈旧的 settings 能一直活着；而装档案走的是
/// `PrefsStore.useStorage(_:prefs:)`，它不触发 `onChange`，所以也不会有任何一条操作
/// 去纠正它。取证时抓到的正是这个状态：`prefs.json` 里 `barSpacing = 1.6`，存档里
/// `local["settings:chart"].barSpacing = 4`，两份并排躺了整整一个会话都没人管，
/// 期间新生出来的操作只有副图高度那一条，**根宽一条都没有**。
/// 而 `SyncStore.receive` 只在**有待发操作**时才护住本地那份
/// （`if !a.operations.contains(where: ...)`）——这儿一条都没有。下一次成功 pull 之后
/// `applyPending()` 就拿那个 4 把用户刚捏出来的 1.6 盖回去了。
///
/// # 规矩
///
/// 装档案那一刻拿盘上那份和影子比一下：
///
/// - **影子根本不存在** → 只播种，**不记操作**。这台机器还没跟服务端对过账，此刻手上
///   多半是一份出厂默认；记成操作就等于抢在 bootstrap 之前把默认值推上去，会把用户
///   在别的设备上的真设置盖掉。让 bootstrap 先说话。
/// - **影子在，但和盘上那份不一样** → **以盘上那份为准**，并且当场记成一条待发操作。
///   影子只是「我上次告诉服务端的话」，盘上那份是「用户后来又做的动作」，后者永远更新。
///   记成操作有两个作用：把这个动作真的推上去，以及让它在 `receive` 里受保护。
/// - **两份一样** → 什么都不用做。
///
/// 配合「手一松就落盘 + 就记操作」（`ChartViewport.settle`），这条规矩只在异常情况下
/// 才用得上：写盘写到一半被杀、崩溃、或者从**旧版本升上来**的机器（它们身上很可能
/// 正躺着一份已经错开的影子）。但正因为如此它必须在。
///
/// # 推拉顺序
///
/// **永远先推后拉。** `AppAccountBridge.run` 里那个 `while !sync.archive.operations.isEmpty`
/// 的推送循环跑在所有 `v1/sync/bootstrap` 之前，就是这条。顺序反过来的话，拉回来的旧值
/// 会先落进 `local`，再被推上去，用户的动作就被自己洗掉了。
enum ChartLayoutReconcile {
  enum Outcome: Equatable {
    /// 存档里还没有基线：播一份进去，不记操作。
    case seed
    /// 盘上那份比基线新：以盘上为准，并且记成待发操作。
    case recapture
    /// 两份一致：什么都不做。
    case agree
  }

  /// - Parameters:
  ///   - onDisk: 刚从 `prefs.json` 读出来的那份。
  ///   - baseline: 存档 `local["settings:chart"]` 还原出来的那份；存档里没有就传 `nil`。
  static func decide(onDisk: Prefs, baseline: Prefs?) -> Outcome {
    guard let baseline else { return .seed }
    return baseline == onDisk ? .agree : .recapture
  }
}
