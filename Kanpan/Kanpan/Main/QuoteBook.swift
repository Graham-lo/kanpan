import Foundation
import Observation
import KanpanAccount
import KanpanCore
import KanpanData
import KanpanNetwork

/// 前台跨页面共享自选/可见品种WS；后台释放。日开盘只按需取一次。
@MainActor @Observable
final class QuoteBook {
#if DEBUG
  /// 预览只给静态报价，不启动网络、不写缓存。
  static func preview(_ values: [Ticker]) -> QuoteBook {
    let book = QuoteBook()
    book.raw = Dictionary(values.map { ($0.symbol, $0) }, uniquingKeysWith: { _, last in last })
    return book
  }
#endif

  /// 全部品种的最新报价。**不参与观察**（审查 21）：自选表里任何一只跳一下都会改它，
  /// 谁在 body 里读它，谁就跟着整张表一起重算。列表走 `onUpdate` 合批那条路，
  /// 图表头部读下面那份 `chartQuote`——这儿只在动作里现取。
  @ObservationIgnored private(set) var raw: [String: Ticker] = [:] { didSet { syncChartQuote() } }
  /// 图上那只（`setChartSymbol`）的最新报价，`raw` 里那一格的镜像。**只有它参与观察**：
  /// 头部价格行读它，自选表别的行跳动不会把行情页叫起来。
  private(set) var chartQuote: Ticker?
  /// 新建提醒那一页点名的那只（`quoteNow`）的最新报价，同样是 `raw` 里一格的镜像：
  /// 那一页在自己的 body 里读它，价到了就只叫醒那一页。
  private(set) var namedQuote: Ticker?
  private(set) var lastListUpdate: Date?
  private(set) var basis: ChangeBasis = .rolling24h
  private var latestReceived: [String: QuoteState] = [:]
  /// 线路 × 主机。每个品种找它那一家的提供者要数据（`provider(for:)`）。
  /// 一出生就是这台设备当前的线路（`RouteResolver.current`），`configure` 之前也不会偷偷直连。
  private var resolver = RouteResolver.current.logging(to: QuoteBook.log)
  /// 提供者按交易所缓存；线路或主机一变整份换。
  private var providers: [String: any MarketProvider] = [:]
  private var socket: MergedMarketStream?
  private var subscribedStreams: [StreamTopic] = []
  private var pump: Task<Void, Never>?
  private var wanted = Set<String>()
  private var opens: [String: (time: Int64, price: Double)] = [:]
  private var queue = Set<String>()
  private var jobs: [String: Task<Void, Never>] = [:]
  private var failedAt: [String: Date] = [:]
  /// 连续失败次数，用来把重试间隔逐级拉开。
  private var failCount: [String: Int] = [:]
  /// 「先拿现价顶上」的那批开盘价（见 `rollBoundary(to:)`）。它们是真实成交价，
  /// 但不是交易所口径的当日开盘价，所以既要继续去取正式值，也不能落盘。
  private var provisionalOpens = Set<String>()
  /// 已经落盘的那批开盘价（以及它们属于哪一档边界）。只为避免重复写同一份。
  private var persistedOpens = Set<String>()
  private var persistedBoundary: Int64?
  private var generation = 0
  private var boundary: Int64?
  private var visible = false
  private var foreground = true
  private var favorites: [String] = []
  /// 挂着活动提醒的品种（大写）。**只加不减**：一条提醒响过之后把它的品种从订阅里
  /// 摘掉，会让列表那条 socket 走一轮 `replaceStreams`——几十行价格在那一瞬间全停
  /// （`listSymbols()` 的注释里写过这一幕）。多订一条 ticker 的代价比那个小得多，
  /// 而且这一程里用户很可能马上又在同一只上重新上膛。这一程结束就没了。
  private var alerted: Set<String> = []
  private var chartSymbol: String?
  private var online = true
  private let network = MarketNetworkMonitor()
  private var session = QuoteSession()
  private var quoteQueue: [String] = []
  private var quoteJobs: [String: Task<Void, Never>] = [:]
  private var quoteAttempt: [String: Date] = [:]
  private var startedAt = Date()
  private var firstQuoteMs: Int?
  /// 每个品种最后一次真正收到值的本机时间。判「要不要补价」看它，
  /// 不再看「有没有值」——留着上次的价格显示，不等于那个价格还新鲜。
  private var receivedAt: [String: Date] = [:]
  /// 报价与开盘价的落点。**跟着当前档案走**（见 `retargetProfile()`），
  /// 所以它是 `var`：换个人，这两份缓存立刻换一个目录。
  private var paths = Paths.caches()
  private var persistTask: Task<Void, Never>?
  private var baselineTask: Task<Void, Never>?
  /// 下一次定时落盘。`nil` 表示当前没有排队的写。
  private var persistPending: Task<Void, Never>?
  private var lastPersist = Date.distantPast
  /// 上一次真正落盘的那批品种。用来判断「这次有没有新面孔」——有就别等节流。
  private var persistedSymbols = Set<String>()
  private var restored = false
  /// 已经露过面的行。只有第一次露面的行需要合帧——它是「凭空冒出来」的那种；
  /// 已经有值的行只是数字变一下，谁也看不出先后。
  private var everPublished = Set<String>()
  /// 攒着等一起发的首帧行。见 `publish(_:)`。
  private var coalesced: [String: Ticker] = [:]
  private var coalesceFlush: Task<Void, Never>?
  /// `coalesced` 里这批攒于哪一代。见 `batchEpoch`。
  private var coalescedEpoch = 0
  /// 稳态合批的缓冲：按品种覆盖，所以攒多久都只发最新值。见 `emit(_:)`。
  private var steady: [String: Ticker] = [:]
  private var steadyFlush: Task<Void, Never>?
  /// `steady` 里这批攒于哪一代。见 `batchEpoch`。
  private var steadyEpoch = 0
  /// 合批缓冲的「这一代是谁的」。换人（`retargetProfile()`）、换上游
  /// （`configure(...)` 里 `changedSource`）、清空重连（`restartStream(clearing:)`）
  /// 各自把它 +1。
  ///
  /// 两个缓冲原来不随这三件事一起清：换号那一刻攒在 `coalesced` 里的，是**上一个人**
  /// 自选表里的行；换上游那一刻攒在 `steady` 里的，是上一家交易所的价格。
  /// 它们照样会被那个已经排上队的 flush 任务发出去，于是新表上先闪一批不属于这里的行。
  private var batchEpoch = 0
  private var lastEmit = Date.distantPast
  /// 下一次落盘不晚于这个时刻。`distantFuture` 表示当前没有排队的写。
  private var persistDeadline = Date.distantFuture
  /// 宿主把自选表送进来了吗。
  ///
  /// 冷启动的顺序是「`restoreQuotes()` 先把上次的报价摆好 → 宿主接着告诉我们自选是哪些」。
  /// 中间这一小段里 `wanted` 只有图上那一个品种，照着它裁 `raw`，刚摆出来的十几行
  /// 立刻退回骨架——用户看到的「自选一个个慢慢加载」就是从这儿来的。所以在自选表
  /// 到齐之前，只准往 `wanted` 里加，不准拿它去裁。
  private var favoritesKnown = false
  /// 进后台后延迟拆连接的窗口。宿主用 `beginBackgroundTask` 顶住这段时间，
  /// 短暂切走再回来就不必重连。
  private var idleTeardown: Task<Void, Never>?
  private var batchJob: Task<Void, Never>?
  /// 全市场报价只有直连可用，网关只代理单品种。失败后先别反复试。
  private var batchRetry = Date.distantPast
  /// 超过这个秒数的值只是「上次看到的」，要重新取。
  private static let freshSeconds: TimeInterval = 20
  /// 推送帧不带成交额的线路（网关上的 OKX 替身）：成交额多旧就得单独问一次 REST，
  /// 以及两次之间至少隔多久。成交额是 24h 滚动总数，一分钟一更足够。
  private static let turnoverRefreshSeconds: TimeInterval = 60
  /// 攒够这么多行要补，就用一次全市场请求换掉逐行往返。
  ///
  /// 门槛原来是 8，那是按「一次请求换几十次往返」估的，但估错了两件事：
  /// 单品种的 `ticker/24hr` 回包只有 ~375 B，而全市场那一条是 285 KB；
  /// 而且币安是 HTTP/2，几十条单品种请求在同一条连接上多路复用，
  /// 实际只花一个往返。于是「省」出来的是把 8 KB 换成 285 KB——在手机
  /// 网络上，这恰恰就是冷启动时那段「等一下才出来」。
  /// 抬到 48：自选表怎么加都走逐行那条，只有品种搜索页那种几百行滚动时
  /// 才值得用全市场换。
  private static let batchThreshold = 48
  /// 不进板块页的那几家的全市场种子：多久刷一次、失败后多久再试、一次最多等多久、
  /// 回前台后晚多久再取（见 `warmSeeds`）。
  private static let seedRefreshSeconds: TimeInterval = 60
  private static let seedRetrySeconds: TimeInterval = 30
  private static let seedTimeoutSeconds: TimeInterval = 8
  private static let seedWarmDelaySeconds = 3
  /// 逐行补价的并发。
  ///
  /// HTTP/2 下这些请求共用一条连接，并发开大不多开连接，只是多几条流；
  /// 一屏自选（二十几行）因此一个往返就全部补齐，而不是 4 个一批排队。
  private static let quoteConcurrency = 24
  /// 展开详情里 1h / 4h 分钟线的并发。同上，原来是 2，一行行地填。
  private static let historyConcurrency = 8
  /// 取「当日开盘价」（算非 24 小时口径涨跌幅用）的并发。
  ///
  /// 原来是 4：二十几个自选要排六轮往返才填满，价格早就在那儿了，涨跌幅还在
  /// 一格格地冒。这些请求和补价走同一条 HTTP/2 连接，开大只多几条流、不多开连接。
  private static let baselineConcurrency = 16
  /// 首帧合帧的等待上限。
  ///
  /// 二十几行各自一个 REST 响应，虽然共用一条 HTTP/2 连接、只花一个往返，
  /// 但回包落地的时刻仍然差着几十到几百毫秒。一条一条发出去，列表就是
  /// 「一行行往外冒」——明明总共只等了半秒，体感却是慢慢加载。攒起来一次发，
  /// 整屏同时出现。攒的时间不会超过这一轮本来就要等的那个往返，不是把数据压慢。
  ///
  /// 正常情况下走的不是这个上限，而是「这一轮补价排空」——二十几行同时在飞，
  /// 最后一行回来时一起发，只画一帧。这个数只是兜底：真有一两行卡住了，
  /// 别让已经到的那十几行陪着一起等。所以它要明显大于一轮往返（实测半秒上下），
  /// 定 0.45 秒反而会在排空之前先把半屏发出去，变成两拨——那正是要消掉的东西。
  private static let coalesceMaxSeconds: Double = 1.2
  /// 进后台后连接还留多久。和 `MarketFeed.backgroundGraceMs` 对齐，
  /// 都在 iOS 给的约 30 秒后台运行时间之内。
  private static let idleGraceSeconds: Double = 25
  /// 定时落盘的最小间隔。
  private static let persistEverySeconds: Double = 30
  /// 盘上出现没存过的品种时，落盘最多再等这么久（见 `notePersist()`）。
  private static let persistNewFaceSeconds: Double = 2
  /// 稳态下最多多久画一帧列表。
  ///
  /// 取 0.3 秒：比屏幕刷新慢一个量级，用户看到的仍然是「一直在跳」，
  /// 但整表重算从一秒十几次降到三次。再快没有意义——价格本身也没那么快变。
  private static let steadyCoalesceSeconds: Double = 0.3
  /// 列表不可见时的合批窗口。
  ///
  /// 行情照收（`raw` 是跨页共享的，回到列表要立刻有值），只是不再为一张
  /// 看不见的表一帧帧地重算。看图的时候整个自选表的重算就从后台消失了。
  private static let hiddenCoalesceSeconds: Double = 2
  /// 内存里最多留多少个品种的当日开盘价。一个品种一个 Double，留着是为了
  /// 翻来翻去不用重取；到这个数才按当前可见范围收一次。
  private static let maxRememberedOpens = 512
  /// 跨档之后还能拿现价顶开盘价的时间窗。超出这一段就只能老老实实去取。
  private static let provisionalWindowMs: Int64 = 120_000
  /// 给 UI 用例读的诊断串。**只在 DEBUG 构建里存在**（审查 C-02）。
  var diagnostics: String? {
    #if DEBUG
    guard ProcessInfo.processInfo.environment["KANPAN_CHART_DIAGNOSTICS"] == "1" else { return nil }
    return "session=\(session.generation);firstQuoteMs=\(firstQuoteMs ?? -1);rows=\(raw.count);status=\(status.rawValue)"
    #else
    return nil
    #endif
  }
  private(set) var status: FeedStatus = .reconnecting { didSet { if status != oldValue { trackLink() } } }

  // ---------------------------------------------------------------- 连接断了多久

  /// 列表这条推送连接断满宽限了（口径同顶栏：`MarketModel.linkGrace`，bfc1c816）。
  /// 自选表拿它把每一行的价和涨跌退成灰——断网 / 弱网 / 电梯里，重连退避一直转，
  /// 列表上那些价却一直全彩摆着，读起来就是实时价（整机压测 2026-09-26）。
  /// 只在翻的那一下写，一次断线最多叫醒自选页两次。
  private(set) var linkDown = false
  @ObservationIgnored private var link = LinkGrace()
  @ObservationIgnored private var linkSweep: Task<Void, Never>?

  /// 前台里这条连接**该连着**（`needsConnection`）却不在 `.live` 就起算；
  /// 连上、进后台、没人要这条连接了都当场停表复原。
  /// 用 `needsConnection` 而不是「有没有 pump」：断网（`online == false`）时根本不起 pump，
  /// 可那正是要灰的情形。
  private func trackLink(now: Date = Date()) {
    let waiting = needsConnection && status != .live
    if link.track(waiting: waiting, now: now) {
      linkSweep?.cancel()
      linkSweep = Task { [weak self] in
        try? await Task.sleep(for: .seconds(LinkGrace.seconds + 0.05))
        guard !Task.isCancelled else { return }
        self?.sweepLink()
      }
    } else if !waiting {
      linkSweep?.cancel(); linkSweep = nil
    }
    sweepLink(now: now)
  }

  /// 到点替「时间流过去」扫一次。测试也从这儿推时钟。
  func sweepLink(now: Date = Date()) {
    let down = link.isDown(now: now)
    if down != linkDown { linkDown = down }
  }

  /// 排查「列表连上了但不跳」：`KANPAN_LOG=1` 时把这条流的连接和收帧量打出来。
  /// 图那条流一直有日志，列表这条一直是哑的——两边都不跳的时候根本分不清是谁的问题。
  ///
  /// **只在 DEBUG 构建里认这个开关**（审查 C-02）：正式包一律静音，省得同一个
  /// 二进制在有／无环境变量两种启动下表现不一样。
  private static let log: FeedLog = {
    #if DEBUG
    return ProcessInfo.processInfo.environment["KANPAN_LOG"] == "1" ? .stdout : .silent
    #else
    return .silent
    #endif
  }()
  private var ingestCount = 0
  private var ingestDropped = 0
  private var ingestReport = Date()
  var onReset: (() -> Void)?
  var onScopeChange: ((Set<String>) -> Void)?
  private var visibleRows = Set<String>()
  /// 全市场 24h 行情的种子（板块页那份，见 `seed(_:upstream:)`）。只拿来给**刚露面、
  /// 手里还没有值**的行垫第一帧，不订阅、不当成实时，也不观察——它变了不需要重画谁。
  @ObservationIgnored private var seeds: [String: Ticker] = [:]
  /// 每一家那份种子是什么时候收下的 / 上一次去取是什么时候（交易所 id → 时刻）。
  @ObservationIgnored private var seededAt: [String: Date] = [:]
  @ObservationIgnored private var seedAttempt: [String: Date] = [:]
  @ObservationIgnored private var seedJobs: [String: Task<Void, Never>] = [:]
  /// 还在等那一拍延时、没真正发出去的种子任务（列表一露面就不再等，当场取）。
  @ObservationIgnored private var seedSleeping: Set<String> = []
  @ObservationIgnored private var seedFlush: Task<Void, Never>?
  @ObservationIgnored private var seededBatch: [Ticker] = []
  /// `quoteNow` 点名要的那一只（新建价格提醒页），列表不可见也给它要价。
  @ObservationIgnored private var named: String? { didSet { syncChartQuote() } }
  private var historyWanted = Set<String>()
  private var historyJobs: [String: Task<Void, Never>] = [:]
  private var historyRequested: [String: Date] = [:]
  var onHistory: ((String, [Bar]) -> Void)?
  var onUpdate: (([Ticker]) -> Void)?
  /// 盘上每一口新价，**不合批**。提醒模块（`AlertEngine`）挂在这儿判到价。
  ///
  /// 为什么不搭 `onUpdate` 的顺风车：那一条是画表用的，稳态下 0.3 秒（列表不可见时
  /// 2 秒）才发一帧，缓冲还按品种覆盖——中间那些价就此消失。到价判定要的恰恰是
  /// 「有没有哪一口碰到过线」，少看一口就可能整条提醒不响。这儿一条也不省。
  var onPrice: (([Ticker]) -> Void)?
  /// 交易所拿这个代号答不出来（400 `-1121 Invalid symbol` / 404）。
  ///
  /// 「下架」这件事只有一个判据，就是品种表里的 `SymbolInfo.status`（审查 B-06）；
  /// 这条回调是把交易所的那句否认**送到目录层**去落成那个判据，不是自己在这儿下结论。
  /// 限流、地域拒绝、超时一概不算——那些拒的是整条线路，照它判会把整张自选表
  /// 一次标成下架（判定写在 `SymbolCatalog.rejectsSymbol`）。
  var onSymbolRejected: ((String) -> Void)?

  /// 换人了：报价和开盘价这两份缓存立刻改指向新档案的目录。
  ///
  /// 它们存的是**当前这个人自选表里的那些品种**——价格是公开数据，但「这台机器上
  /// 刚才关注的是哪几十个品种」随人走。所以档案一换，盘上这批既不能留在屏幕上
  /// 给下一个人看，也绝不能被写进新档案的目录里。
  ///
  /// 身份只从一个地方拿（`AccountFiles.currentProfile`，和账号目录同一套 id），
  /// 这儿不自己拼、不自己记。读写前都过一遍这个口子，就不存在「档案已经换了、
  /// 缓存还写在上一个人名下」那一小段窗口。
  private func retargetProfile() {
    let id = AccountFiles.currentProfile
    guard id != paths.profile else { return }
    // 冷启动第一次认主（`""` → 某个档案）：盘上还什么都没有，直接认下就行。
    let switching = !paths.profile.isEmpty || restored
    paths = Paths.caches(profile: id)
    persistedSymbols.removeAll()
    persistedOpens.removeAll(); persistedBoundary = nil
    guard switching else { return }
    // 攒着的两批是上一个人的行，跟着 `raw` 一起丢——留着就会在新表上闪一下。
    discardBatches()
    // 钉进来的提醒品种是**上一个人**的提醒。新的那份由 `AlertEngine` 换档案之后重新交。
    alerted.removeAll()
    raw.removeAll(keepingCapacity: true); receivedAt.removeAll(keepingCapacity: true)
    everPublished.removeAll(keepingCapacity: true)
    opens.removeAll(); provisionalOpens.removeAll()
    onReset?()
    restored = false
    restoreQuotes()   // 换上新档案自己那份，别让这个人对着一张空表等网络。
  }

  /// 冷启动第一帧：先把上次看到的报价摆出来，再去取新的。存的是交易所
  /// 真实返回过的值，`timeMs` 一并留着——列表顶部的实时指示灯只认 5 秒内
  /// 的更新，所以它不会被当成实时价。
  func restoreQuotes() {
    retargetProfile()
    guard !restored else { return }
    restored = true
    guard raw.isEmpty else { return }
    let saved = QuoteSnapshot.read(quotePaths.quotes)
    guard !saved.isEmpty else { return }
    for ticker in saved { raw[ticker.symbol] = ticker }
    // 盘上就是这批，别让下面那次 publish 又原样写回去一遍。
    persistedSymbols = Set(saved.map(\.symbol))
    // 缓存直接上屏，不走 `publish` 的首帧合帧：那道闸是给「网络补价一行行往外冒」
    // 准备的，拿磁盘上现成的一整批去等它，只会让自选行白白空着（冷启动、换号都是
    // 约 0.8 秒骨架）。它们已经在盘上，也不必再记一笔写盘。
    emitNow(saved.map(presented))
  }

  /// 不等任何合批窗口，当场交出去。只给本地已有的整批数据用（磁盘缓存、全市场种子）。
  private func emitNow(_ batch: [Ticker]) {
    guard !batch.isEmpty else { return }
    if steadyEpoch != batchEpoch { steady.removeAll(keepingCapacity: true); steadyEpoch = batchEpoch }
    for ticker in batch {
      everPublished.insert(ticker.symbol)
      steady[ticker.symbol] = ticker
    }
    flushSteady()
  }

  private func persistQuotes() {
    retargetProfile()
    persistPending?.cancel()
    persistPending = nil
    persistDeadline = .distantFuture
    lastPersist = Date()
    let values = Array(raw.values)
    guard !values.isEmpty else { return }
    persistedSymbols = Set(values.map(\.symbol))
    let url = quotePaths.quotes
    let log = Self.log
    // 写盘排成一条链（P2.3）：分离任务之间不保证先后，上一笔慢了就可能被这一笔抢先，
    // 旧报价落在新报价上面。cancel 只拦还没开写的那一笔；已经在写的写完即止，
    // 下一笔等它写完再接着写更新的值。
    let previous = persistTask
    previous?.cancel()
    persistTask = Task.detached(priority: .utility) {
      _ = await previous?.value
      Self.writeSnapshot(values, to: url, log: log)
    }
  }

  /// 后台写盘的那一笔。开写之前先看自己被撤了没有，和同文件其余后台任务一个口径：
  /// 被 `persistQuotes` 撤掉的那一笔拿着的是旧报价，照写就会把旧数据盖在新数据之后（P2.3）。
  nonisolated static func writeSnapshot(_ values: [Ticker], to url: URL, log: FeedLog) {
    guard !Task.isCancelled else { return }
    QuoteSnapshot.write(values, to: url, log: log)
  }

  /// 有新报价就记一笔「该存了」，真正写盘按 `persistEverySeconds` 节流。
  ///
  /// 原来只有退后台和拆连接才写。问题是 app 不一定有机会「退后台」——被 jetsam
  /// 杀掉是没有通知的，那一次的报价就全丢了，下次冷启动照样是空列表。定时写一遍，
  /// 最多丢掉这一个间隔里的变化。写的是后台低优先级的一小段 JSON，代价可以忽略。
  private func notePersist() {
    // 出现了盘上没有的品种（多半是刚加的自选）要尽快写一遍：否则用户加完自选
    // 顺手把 app 划掉，这一行下次冷启动就是空的，只能干等网络——「自选一个个
    // 慢慢加载」看到的正是这个。
    //
    // 但「尽快」不等于「立刻」。原来是新面孔一出现就当场整表编码 + 写盘，而
    // 一屏自选头一次补价就是二十几个新面孔陆续到达，于是一轮冷启动里整表 JSON
    // 被写了二十几遍。现在只是把这次写的截止时间从 30 秒提到 2 秒，够把
    // 这一轮的新面孔攒成一次写，「划掉 app 就丢」那条也仍然堵着。
    let fresh = !persistedSymbols.isSuperset(of: raw.keys)
    let periodic = lastPersist.addingTimeInterval(Self.persistEverySeconds)
    let deadline = fresh ? min(periodic, Date().addingTimeInterval(Self.persistNewFaceSeconds)) : periodic
    let wait = deadline.timeIntervalSinceNow
    guard wait > 0 else { persistQuotes(); return }
    // 已经排着一次更早（或一样早）的写，就跟着那一次走。
    if persistPending != nil, deadline >= persistDeadline { return }
    persistPending?.cancel()
    persistDeadline = deadline
    persistPending = Task { [weak self] in
      try? await Task.sleep(nanoseconds: UInt64(wait * 1_000_000_000))
      guard let self, !Task.isCancelled else { return }
      self.persistPending = nil
      self.persistDeadline = .distantFuture
      self.persistQuotes()
    }
  }

  /// 这一只最后一次真正收到值的本机时刻（磁盘垫的种子价没有）。小组件拿它给不带时刻的行情补时刻。
  func receivedTime(_ symbol: String) -> Date? { receivedAt[symbol] }

  private func isFresh(_ symbol: String) -> Bool {
    guard raw[symbol] != nil, let at = receivedAt[symbol] else { return false }
    return Date().timeIntervalSince(at) < Self.freshSeconds
  }
  /// 这一行要不要去问 REST：值不新鲜，或者值新鲜但成交额补不上（推送帧不带成交额）。
  private func wantsQuote(_ symbol: String) -> Bool {
    if !isFresh(symbol) { return true }
    guard let state = latestReceived[symbol], state.value != nil,
          Date().timeIntervalSince(quoteAttempt[symbol] ?? .distantPast) >= Self.turnoverRefreshSeconds else { return false }
    guard let time = state.turnoverTimeMs else { return true }
    return Date().timeIntervalSince1970 - Double(time) / 1000 >= Self.turnoverRefreshSeconds
  }

  /// 某个品种的报价状态。第一次见到时，把手里那份（盘上恢复的、种子）的成交额先记上：
  /// 替身的推送帧不带成交额，不记的话第一帧推送一到，列表和顶栏的「额」就退成「—」。
  /// `raw` 只装当前上游的数（换上游整份清掉、按上游分区读回；种子按上游收），不跨源。
  private func quoteState(_ symbol: String) -> QuoteState {
    if let state = latestReceived[symbol] { return state }
    var state = QuoteState()
    if let old = raw[symbol], old.quoteVolume.isFinite { state.receiveTurnover(old) }
    return state
  }

  /// 报价与开盘价这两份缓存按上游分区：替身上游（`snapshotNamespace`）的数和真身的
  /// 不能串——换了线路冷启动，第一帧摆出来的得是这条线路自己上次的数。
  /// 真身（直连）照旧放在档案根上，老缓存不作废。
  private var quotePaths: Paths {
    let names = Set(VenueRegistry.all.compactMap { provider(for: $0.defaultSymbol).capabilities.snapshotNamespace })
    guard !names.isEmpty else { return paths }
    return paths.source(names.sorted().joined(separator: "+"))
  }


  /// 某个品种该找谁要行情（按品种键里的交易所）。
  private func provider(for symbol: String) -> any MarketProvider {
    let venue = VenueRegistry.descriptor(forSymbol: symbol).id
    if let cached = providers[venue] { return cached }
    let made = resolver.provider(venue: venue)
    providers[venue] = made
    return made
  }

  /// 各家在这条线路上实际由谁供数。线路变了但没有一家换上游，就只算换主机。
  private static func upstreams(_ resolver: RouteResolver) -> [String] {
    VenueRegistry.all.map { resolver.provider(venue: $0.id).capabilities.upstream }
  }

  func configure(route: RouteResolver, basis: ChangeBasis) {
    let next = route.logging(to: Self.log)
    let changedHost = next.route != resolver.route
    let changedSource = Self.upstreams(next) != Self.upstreams(resolver)
    let changedBasis = basis != self.basis
    if changedSource {
      // 手里这批是旧上游的：先落进旧上游自己的分区，再换。
      persistQuotes(); persistBaselines()
    }
    if changedHost { resolver = next; providers.removeAll() }
    if changedSource {
      // 换了上游，手里的报价就是另一家的数（成交额口径都不一样）。整份清掉、
      // 从新上游自己的分区读回来——不在连接的时候 `restartStream(clearing:)` 不会走到，
      // 这儿不清，旧上游的「额」就会一直挂在新线路的列表和顶栏上。
      raw.removeAll(keepingCapacity: true); receivedAt.removeAll(keepingCapacity: true)
      latestReceived.removeAll(keepingCapacity: true); everPublished.removeAll(keepingCapacity: true)
      persistedSymbols.removeAll(); persistedOpens.removeAll(); persistedBoundary = nil
      session.reset(); onReset?()
      restored = false
    }
    if changedHost || changedSource {
      // 换镜像不动开盘价：那是交易所的数据，跟走哪台机器取回来没关系。
      // 以前这儿连着 `opens.removeAll()`，改一下行情源地址、或者
      // 「智能线路」开关一动，整屏涨跌幅就得重新排队取一遍。换上游才要重取。
      if changedSource {
        opens.removeAll(); provisionalOpens.removeAll(); seeds.removeAll()
        seededAt.removeAll(); seedAttempt.removeAll()
        seedJobs.values.forEach { $0.cancel() }; seedJobs.removeAll(); seedSleeping.removeAll()
      }
      for symbol in Array(quoteJobs.keys) where symbol != chartSymbol { quoteJobs.removeValue(forKey: symbol)?.cancel() }
      quoteQueue.removeAll { $0 != chartSymbol }
      // 换镜像只是换台机器取同一家的数据，攒着的照发；换上游则整代作废
      // （`needsConnection` 为假时不会走到 `restartStream(clearing:)`，
      // 这儿不丢就真没人丢了）。
      if changedSource { discardBatches() } else { flushCoalesced() }
      historyJobs.values.forEach { $0.cancel() }; historyJobs.removeAll(); historyRequested.removeAll()
    }
    self.basis = basis
    if changedHost || changedSource || changedBasis { resetBaselineRequests() }
    if (changedHost || changedSource), needsConnection { restartStream(clearing: changedSource) }
    restoreQuotes()
    if changedSource { restoreBaselines() }
    tick()
    publish(Array(raw.values))
    if changedSource { warmSeeds() }
  }

  /// 进后台后的宽限窗口里连接还活着，这时到的帧照收——回来就是现价。
  /// REST 那几条路仍然只在前台走。
  private var accepting: Bool { foreground || idleTeardown != nil }

  private var needsConnection: Bool {
    // The chart has its own MarketModel feed. QuoteBook only needs a socket
    // when it is serving the cross-page favorites/symbol list.
    foreground && QuoteSubscriptionPlan.needsConnection(foreground: foreground, favorites: favorites,
                                                        visible: visible, alerted: alerted)
  }

  /// 哪些品种挂着活动提醒。`AlertEngine` 每次存档变了就交一次。
  ///
  /// 它们要被钉进订阅范围：前台的到价判定只能判盘上有价的品种，而提醒是跨品种的——
  /// 用户给 ETHUSDT 画了线设了提醒，然后一直在看 BTCUSDT，没有这一条那条提醒
  /// 在这台手机上永远不会响（没有 APNs 密钥，前台这条路是唯一的）。
  func setAlertedSymbols(_ symbols: Set<String>) {
    let next = alerted.union(symbols.map { InstrumentID.canonical($0) }.filter { !$0.isEmpty })
    guard next != alerted else { return }
    alerted = next
    reconcileConnection()
    updateStreams()
  }

  func setFavorites(_ symbols: [String]) {
    let symbols = symbols.map(InstrumentID.canonical)
    // 换号之后宿主就是从这儿把新的自选表交下来的，所以这一步之前先认一次主：
    // 晚一拍的话，新表配的还是上一个人那份缓存。
    retargetProfile()
    favoritesKnown = true
    favorites = symbols
    for symbol in symbols { wanted.insert(symbol); watchBaseline(symbol) }
    reconcileConnection()
    updateStreams()
  }

  func setForeground(_ on: Bool) {
    guard on != foreground else { return }
    foreground = on
    reconcileConnection()
    // 让开首屏：图表那一只的 K 线、报价先走，种子晚一拍再取（它只服务搜索 / 自选里的行）。
    if on { warmSeeds(after: .seconds(Self.seedWarmDelaySeconds)) }
  }

  func setVisible(_ on: Bool) {
    guard on != visible else { return }
    visible = on
    reconcileConnection()
    updateStreams()
    if !on {
      for symbol in Array(quoteJobs.keys) where symbol != chartSymbol && symbol != named {
        quoteJobs.removeValue(forKey: symbol)?.cancel()
      }
      quoteQueue.removeAll { $0 != chartSymbol && $0 != named }
      flushCoalesced()
      historyJobs.values.forEach { $0.cancel() }; historyJobs.removeAll()
    }
    // 可见性一变，稳态合批的窗口宽度就换了一档（见 `steadyCoalesceSeconds`）。
    // 把攒着的那一帧当场结掉：离开列表时最后一次变动不留在缓冲里，
    // 回到列表时也不必先等满一个 2 秒的窗口才看见第一帧。
    lastEmit = .distantPast
    flushSteady()
    if on { applySeeds(to: visibleRows); warmSeeds() }
  }

  private func reconcileConnection() {
    // 该不该连着变了（前后台、列表露面、自选有没有）：断线计时跟着对一遍。
    defer { trackLink() }
    if needsConnection {
      idleTeardown?.cancel(); idleTeardown = nil
      guard pump == nil else { return } // 健康前台会话跨页面继续，价格无需重取。
      online = true
      network.start { [weak self] online in
        Task { @MainActor [weak self] in self?.networkChanged(online) }
      }
      restartStream()
    } else if !foreground, pump != nil, idleTeardown == nil {
      // 刚进后台：连接先留着。iOS 还给约 30 秒运行时间（宿主用
      // beginBackgroundTask 要下来），窗口内切回来就不必重连，也就没有
      // DNS + TCP + TLS + 订阅 + 等第一帧那一整轮。REST 立刻停，
      // 只让已经开着的 socket 继续填。
      cancelQuotes(); resetBaselineRequests()
      historyJobs.values.forEach { $0.cancel() }; historyJobs.removeAll()
      persistQuotes()
      idleTeardown = Task { [weak self] in
        try? await Task.sleep(nanoseconds: UInt64(Self.idleGraceSeconds * 1_000_000_000))
        guard let self, !Task.isCancelled else { return }
        self.idleTeardown = nil
        guard !self.needsConnection else { return }
        self.teardown()
      }
    } else {
      teardown()
    }
  }

  /// 真正释放连接。价格留在内存里：回来时列表先显示上次看到的值，
  /// 顶部那颗实时指示灯只认 5 秒内的更新，超时自动转灰，所以旧值不会
  /// 被当成实时价。
  private func teardown() {
    idleTeardown?.cancel(); idleTeardown = nil
    batchJob?.cancel(); batchJob = nil
    // 种子只在前台取；前台时列表暂时不需要连接（没有自选、列表没露面）不拦它。
    if !foreground { seedJobs.values.forEach { $0.cancel() }; seedJobs.removeAll(); seedSleeping.removeAll() }
    network.stop(); stopStream(); cancelQuotes(); resetBaselineRequests()
    historyJobs.values.forEach { $0.cancel() }; historyJobs.removeAll()
    lastListUpdate = nil
    flushSteady()
    persistQuotes()
  }

  /// 列表这条流订哪些品种。
  ///
  /// **不含图上那个品种。** 图表有自己的 `MarketFeed`，头部的价格走的是
  /// `ingestTrade(_:)` 那条，列表从来不靠这条流拿它；真取不到还有
  /// `watch(_:)` 的那次 REST 兜底。原来把它塞进来的代价是：每切一次品种
  /// `streamNames()` 就变一次，于是列表这条 socket 跟着 `replaceStreams`
  /// 退订重订一轮——自选表几十行的价格在那一瞬间全停，切得快一点就一直停着。
  /// 它照样留在 `wanted` 里（见 `updateStreams()`），所以 `raw` 里那一行
  /// 不会被裁掉，跨页回来仍然有值。
  private func listSymbols() -> [String] {
    QuoteSubscriptionPlan.symbols(favorites: favorites, visible: visible ? visibleRows : [], alerted: alerted)
  }

  private func streamNames() -> [StreamTopic] {
    let symbols = listSymbols()
    return (symbols.isEmpty ? [VenueRegistry.default.defaultSymbol] : symbols).map { StreamTopic.ticker(symbol: $0) }
  }

  private func updateStreams() {
    let symbols = listSymbols()
    // 点名的那一只（新建提醒页开着时）也算：页面开着期间别的变动不能把它的价裁掉。
    wanted = Set(symbols + [chartSymbol, named].compactMap { $0 })
    // 自选表还没到，先把上次恢复出来的那批一起算进来，别把它们裁掉（见 `favoritesKnown`）。
    if !favoritesKnown { wanted.formUnion(raw.keys) }
    if raw.keys.contains(where: { !wanted.contains($0) }) { raw = raw.filter { wanted.contains($0.key) } }
    latestReceived = latestReceived.filter { wanted.contains($0.key) }
    onScopeChange?(wanted)
    for symbol in Array(jobs.keys) where !wanted.contains(symbol) { jobs.removeValue(forKey: symbol)?.cancel() }
    queue.formIntersection(wanted)
    // 开盘价不跟着裁。一个品种只占一个 Double，重取却要一次网络往返——
    // 翻去别的分类再翻回来就得整屏重算，正是「涨跌幅每次都最慢出来」。
    // 只有攒得实在多了才收一收。
    if opens.count > Self.maxRememberedOpens {
      opens = opens.filter { wanted.contains($0.key) }
      provisionalOpens.formIntersection(wanted)
      failedAt = failedAt.filter { wanted.contains($0.key) }
      failCount = failCount.filter { wanted.contains($0.key) }
    }
    guard let socket else { return }
    let names = streamNames()
    guard names != subscribedStreams else { return }
    subscribedStreams = names
    // 同步写进期望集：合并推送自己只留一个对账任务追最新的一份，不会被乱序的 Task 覆盖回旧订阅。
    socket.want(names)
  }

  /// 每 5 秒报一次列表这条流收了多少行情、其中多少不在订阅集里被丢掉。
  private func noteIngest(_ n: Int) {
    ingestCount += n
    let now = Date()
    guard now.timeIntervalSince(ingestReport) >= 5 else { return }
    Self.log("列表收行情 \(ingestCount) 条/\(Int(now.timeIntervalSince(ingestReport) * 1000))ms 订阅\(subscribedStreams.count) 想要\(wanted.count) 连接\(socket == nil ? "无" : "有")")
    ingestCount = 0; ingestDropped = 0; ingestReport = now
  }

  func ingest(_ batch: [Ticker]) {
    noteIngest(batch.count)
    guard accepting else { return }
    var valid: [Ticker] = []
    for ticker in batch where wanted.contains(ticker.symbol) {
      var state = quoteState(ticker.symbol)
      guard state.receive(ticker), let ticker = state.value else { continue }
      latestReceived[ticker.symbol] = state
      session.receive(ticker.symbol)
      receivedAt[ticker.symbol] = Date()
      if let old = raw[ticker.symbol], LatestQuote.sameDisplay(ticker, old) { continue }
      raw[ticker.symbol] = ticker
      valid.append(ticker)
    }
    if needsConnection, !valid.isEmpty, firstQuoteMs == nil { firstQuoteMs = Int(-startedAt.timeIntervalSinceNow * 1000) }
    if !valid.isEmpty { onPrice?(valid); publish(valid) }
    if visible { loadHistories() }
  }

  /// 只收一帧里的成交额（见 `QuoteState.receiveTurnover`）。价、会话版本、「刚收到」都不动。
  private func ingestTurnover(_ ticker: Ticker) {
    guard accepting, ticker.quoteVolume.isFinite, wanted.contains(ticker.symbol),
          var state = latestReceived[ticker.symbol], state.receiveTurnover(ticker),
          let value = state.value else { return }
    latestReceived[ticker.symbol] = state
    if let old = raw[ticker.symbol], LatestQuote.sameDisplay(value, old) { return }
    raw[ticker.symbol] = value
    publish([value])
  }

  func ingestTrade(_ trade: TradeQuote) {
    noteIngest(1)
    guard accepting, wanted.contains(trade.symbol) else { return }
    var state = quoteState(trade.symbol)
    guard state.receive(trade), var ticker = state.value else { return }
    latestReceived[trade.symbol] = state
    if ticker.quoteVolume.isFinite {
      session.receive(trade.symbol)
      receivedAt[trade.symbol] = Date()
    } else {
      // 这只还没收到过 24h 统计——冷启动时图上那只的逐笔成交常常比统计先到。
      // 从前这一笔照样记成「刚收到」、照样顶掉会话版本：于是补统计的 REST 被判不新鲜
      // 不发，发出去的回来也因为版本对不上被扔掉（逐笔成交几百毫秒一条，REST 回来前
      // 必然又到了一笔），顶栏的涨跌、额、振幅就一直是「—」。成交和统计的先后
      // 由 `QuoteState` 自己按成交号 / 时间判，用不着会话版本来挡。
      requestQuote(trade.symbol)
      // 统计补回来之前，先拿手里那份（盘上恢复的、种子）的统计垫着，只换最新价，
      // 别让顶栏在这一两百毫秒里退成一排「—」。
      if let old = raw[trade.symbol], old.quoteVolume.isFinite { ticker = Self.overlay(ticker, on: old) }
    }
    if let old = raw[trade.symbol], LatestQuote.sameDisplay(ticker, old) { return }
    raw[trade.symbol] = ticker
    if firstQuoteMs == nil { firstQuoteMs = Int(-startedAt.timeIntervalSinceNow * 1000) }
    onPrice?([ticker])
    publish([ticker])
  }

  /// 旧统计 + 新成交价：和 `QuoteState` 拼成交时同一个算法（涨跌额按价差平移，
  /// 有 24h 开盘价就按它重算涨跌幅）。时间、成交号用新的那笔。
  static func overlay(_ trade: Ticker, on old: Ticker) -> Ticker {
    var next = old
    let last = trade.last
    if let change = old.priceChange, old.last.isFinite { next.priceChange = change + (last - old.last) }
    next.last = last
    next.timeMs = trade.timeMs
    next.lastTradeID = trade.lastTradeID
    if let open = old.open24h, open.isFinite, open > 0 { next.changePercent = (last - open) / open * 100 }
    if next.high.isFinite { next.high = max(next.high, last) }
    if next.low.isFinite { next.low = min(next.low, last) }
    return next
  }

  /// `raw` 里图上那一格（和点名那一格）变了才写，同值不写——写了就会叫醒读它的视图。
  private func syncChartQuote() {
    let next = chartSymbol.flatMap { raw[$0] }
    if next != chartQuote { chartQuote = next }
    let named = named.flatMap { raw[$0] }
    if named != namedQuote { namedQuote = named }
  }

  /// 在 body 里要某只的报价走这儿：图上那只、点名那只读的是参与观察的镜像，价一到就重算；
  /// 别的品种只是现取一口（`raw` 不参与观察，见上）。
  func observedQuote(_ symbol: String) -> Ticker? {
    let key = InstrumentID.canonical(symbol)
    if key == chartSymbol { return chartQuote }
    if key == named { return namedQuote }
    return raw[key]
  }

  func presented(_ ticker: Ticker) -> Ticker {
    var value = ticker
    let start = basis.boundary(now: Int64(Date().timeIntervalSince1970 * 1000))
    let opening = opens[ticker.symbol]
    value.changePercent = basis.percent(last: ticker.last, rolling: ticker.changePercent,
      open: opening?.time == start ? opening?.price : nil)
    return value
  }

  /// Keeps the chart symbol available to the shared quote book without
  /// opening a second socket for the chart page. If the list is already
  /// visible, preserve the old behavior and add the symbol to its stream.
  func setChartSymbol(_ symbol: String) {
    let next = InstrumentID.canonical(symbol)
    guard chartSymbol != next else { return }
    chartSymbol = next
    syncChartQuote()
    guard needsConnection else { return }
    watch(next)
    reconcileConnection()
    updateStreams()
  }

  func watch(_ symbol: String) {
    let symbol = InstrumentID.canonical(symbol)
    wanted.insert(symbol)
    requestQuote(symbol)
    watchBaseline(symbol)
  }

  /// 点名要一只的现价：不管列表开没开，都去要一口（新建价格提醒那一页用）。
  ///
  /// 列表不可见时 `requestQuote` 只放行图上那只——平时这是对的，别的页面不该替看不见的
  /// 行去拉价。可新建提醒那一页是从设置里开的，列表本来就不可见：用户在品种框里打了
  /// 「ETH」，要看的就是 ETH 此刻多少；原来这里只调 `watch`，被那道闸挡掉，于是
  /// 不在图上的品种一直是「当前 —」。同一时刻只点名一只，换一只就换掉（前一只照 `releaseNamed` 收掉）。
  func quoteNow(_ symbol: String) {
    let symbol = InstrumentID.canonical(symbol)
    guard !symbol.isEmpty else { return }
    if let old = named, old != symbol { named = nil; unwatchNamed(old) }
    named = symbol
    watch(symbol)
  }

  /// `quoteNow` 的另一半：新建提醒那一页关了，点名的那一只不再特殊照顾。
  ///
  /// 以前点名只进不出：页面关了 `named` 还钉着那只，列表收起时它的报价请求不撤、
  /// 之后每一拍还放它过 `requestQuote` 那道闸，`wanted` / `raw` 里也一直留着它。
  /// 这里只撤「点名」这一条来路——图上那只、列表上露着的行、自选和挂着提醒的品种
  /// 各有各的来路保着，不受影响（刚建好提醒的那只由 `setAlertedSymbols` 接着钉住）。
  func releaseNamed() {
    guard let symbol = named else { return }
    named = nil
    unwatchNamed(symbol)
  }

  private func unwatchNamed(_ symbol: String) {
    if symbol != chartSymbol, !(visible && visibleRows.contains(symbol)) {
      quoteQueue.removeAll { $0 == symbol }
      quoteJobs.removeValue(forKey: symbol)?.cancel()
    }
    updateStreams()
  }

  private func watchBaseline(_ symbol: String) {
    guard let boundary, jobs[symbol] == nil,
          opens[symbol]?.time != boundary || provisionalOpens.contains(symbol),
          Date().timeIntervalSince(failedAt[symbol] ?? .distantPast) > retryDelay(symbol) else { return }
    queue.insert(symbol); drain()
  }

  /// 失败后隔多久再试。
  ///
  /// 原来是一律 30 秒：网络抖一下掉的那一行，要空着三十秒才补得回来；
  /// 而真的被限流时，三十秒又太短，一屏品种轮着撞，谁也好不了。
  /// 改成逐级拉开（2/4/8…最多 60 秒）——抖一下的那种下一秒就回来了，
  /// 一直不成的那种自己退到后台去。
  private func retryDelay(_ symbol: String) -> TimeInterval {
    min(60, pow(2, Double(min(failCount[symbol] ?? 0, 6))))
  }

  func tick() {
    // 兜底的认主点。退登到一张空自选表时宿主不一定会再交一次 `setFavorites`，
    // 而一秒一拍地比一个字符串是免费的。
    retargetProfile()
    let next = basis.boundary(now: Int64(Date().timeIntervalSince1970 * 1000))
    if next != boundary { rollBoundary(to: next) }
    for symbol in wanted { watchBaseline(symbol) }
    for symbol in visibleRows { requestQuote(symbol) }
    if let chartSymbol { requestQuote(chartSymbol) }
    loadHistories()
  }

  /// 跨档：过了 0 点 / 8 点，或者第一次算出边界。
  ///
  /// 这儿原来是 `opens.removeAll()` 紧跟一次全量 `publish`——盘上每一行的涨跌幅
  /// 在那一瞬间同时变成空白，要等十几二十个 K 线请求回来才一个个填回去。网络
  /// 不顺的时候就一直空着，也就是「用着用着涨跌幅全都不出来了」。
  ///
  /// 其实新一档的开盘价不用问：这一刻的最新成交价就是新一档的第一笔成交。
  /// 先拿它顶上——那是交易所真实推过来的价，不是编的——再让 REST 回来纠正到
  /// 交易所口径。只有本来就没有新鲜价格的品种（比如冷启动刚恢复出来的那批）
  /// 才留空等取。
  private func rollBoundary(to next: Int64?) {
    let now = Int64(Date().timeIntervalSince1970 * 1000)
    boundary = next
    provisionalOpens.removeAll()
    resetBaselineRequests()
    restoreBaselines()
    // 只有「刚跨过去」才能拿现价当开盘价。要是 app 在后台待到了下午才醒，
    // 这一刻的现价离当档开盘早就差出十万八千里，顶上去就等于编了一个接近
    // 零的涨跌幅摆在那儿——宁可留空等 REST 取回真值。
    if let next, now - next <= Self.provisionalWindowMs {
      for (symbol, ticker) in raw where opens[symbol]?.time != next {
        guard isFresh(symbol), ticker.last.isFinite, ticker.last > 0 else { continue }
        opens[symbol] = (next, ticker.last)
        provisionalOpens.insert(symbol)
      }
    }
    publish(Array(raw.values))
  }

  /// 桌面小组件中号那条折线：最近 24 根 1 小时收盘价（P3.2），和 24 小时涨跌幅看的是同一段。
  /// 按品种所在那一家要（1h 是各家都有的原生周期）。
  func closes(symbol: String) async -> [Double]? {
    let symbol = InstrumentID.canonical(symbol)
    let bars = try? await provider(for: symbol).klines(symbol: symbol, interval: .h1, limit: WidgetSnapshot.sparkBars)
    let closes = (bars ?? []).map(\.close).filter(\.isFinite)
    return closes.count >= 2 ? closes : nil
  }

  func watchRow(_ symbol: String, visible: Bool) {
    let symbol = InstrumentID.canonical(symbol)
    if visible { visibleRows.insert(symbol); requestQuote(symbol) }
    else {
      visibleRows.remove(symbol)
      if symbol != chartSymbol {
        quoteQueue.removeAll { $0 == symbol }; quoteJobs.removeValue(forKey: symbol)?.cancel()
      }
    }
    updateStreams()
    if visible { applySeeds(to: [symbol]) }
  }

  // MARK: 全市场种子

  /// 收下一份全市场 24h 行情（板块页取回的、或它从盘上恢复的）。
  ///
  /// 为什么要它：搜索结果行、从板块列表点进去的那一只，从前都是露面之后才逐个发 REST，
  /// 价格格子先空 300 ms 到一两秒。板块页手里其实已经有全市场的 24h 行情——拿它先垫上，
  /// 第一帧就有价，REST / WS 的真值到了照常盖掉（种子不记 `receivedAt`，所以补价照发）。
  ///
  /// 不是同一家上游供的数一概不收：网关线路上替身顶的数和真身的不混用。
  ///
  /// 种子按交易所分份：`venue` 那一家的这一份整份换掉，别家的不动；键是完整品种 key，
  /// 不是这一家的品种一概不收（板块页那份只垫进板块的那家，别家的由 `warmSeeds` 各取各的）。
  func seed(_ tickers: [Ticker], upstream: String, venue: String = VenueRegistry.sectorVenue.id) {
    let own = (providers[venue] ?? resolver.provider(venue: venue)).capabilities.upstream
    guard upstream == own else { return }
    let prefix = venue + "/"
    var next = seeds.filter { !$0.key.hasPrefix(prefix) }
    next.reserveCapacity(next.count + tickers.count)
    for ticker in tickers where ticker.last.isFinite && ticker.last > 0 && ticker.symbol.hasPrefix(prefix) {
      next[ticker.symbol] = ticker
    }
    seeds = next
    seededAt[venue] = Date()
    applySeeds(to: visibleRows.union([chartSymbol].compactMap { $0 }))
  }

  /// 全市场种子由这儿补取的那部分。
  ///
  /// * 不进板块页的那几家（`joinsSectors == false`）没人替它们取全市场，一律由这儿取，
  ///   一分钟内取过就不再取。
  /// * 进板块页的那一家平时由板块页供（它的轮询与落盘的那份，见 `SectorFeed.onTickers`）；
  ///   只有这一程**一份都还没有**时（新装、从没进过板块页、盘上没有它落的那份）才由这儿
  ///   取一次，之后照旧交给板块页——不跟它抢那 40 的请求权重。
  ///
  /// 为什么：搜索结果、自选里的行从前露面之后才逐个问单品种报价，第一帧是「—」、
  /// 0.5–1 秒后才有价。这些家都有整表接口（`hasBulkTickers`，一次给全部品种的现价与
  /// 24h 涨跌，压缩后几十到两百 KB），先取一份垫上，行一露面就有价；真值（REST / WS）
  /// 到了照常盖掉。失败了半分钟后再试。
  private func warmSeeds(after delay: Duration = .zero) {
    guard foreground else { return }
    for d in VenueRegistry.all {
      if delay == .zero, seedSleeping.remove(d.id) != nil { seedJobs.removeValue(forKey: d.id)?.cancel() }
      guard seedJobs[d.id] == nil, needsSeed(d) else { continue }
      let rest = provider(for: d.defaultSymbol)
      guard rest.capabilities.hasBulkTickers else { continue }
      let venue = d.id, upstream = rest.capabilities.upstream
      if delay > .zero { seedSleeping.insert(venue) }
      seedJobs[venue] = Task { [weak self] in
        if delay > .zero { try? await Task.sleep(for: delay) }
        guard !Task.isCancelled else { return }
        self?.seedSleeping.remove(venue)
        // 等的这一拍里板块页可能已经从盘上摆好了那份：再判一次，用不着就不发。
        guard self?.foreground == true, self?.needsSeed(d) == true else { self?.seedJobs[venue] = nil; return }
        self?.seedAttempt[venue] = Date()
        let all = try? await rest.tickers24h(timeout: Self.seedTimeoutSeconds)
        guard let self, !Task.isCancelled else { return }
        self.seedJobs[venue] = nil
        if let all { self.seed(all, upstream: upstream, venue: venue) }
      }
    }
  }

  private func needsSeed(_ d: VenueDescriptor) -> Bool {
    let now = Date()
    guard now.timeIntervalSince(seedAttempt[d.id] ?? .distantPast) >= Self.seedRetrySeconds else { return false }
    guard let at = seededAt[d.id] else { return true }
    return !d.joinsSectors && now.timeIntervalSince(at) >= Self.seedRefreshSeconds
  }


  /// 这一只的种子。图上那一只还没拿到任何报价时，顶栏先用它（`MainScreen.rollingTicker`）。
  func seeded(_ symbol: String) -> Ticker? { seeds[InstrumentID.canonical(symbol)] }
  /// 整张种子表（品种 key → 行情）。搜索 / 品种页建行时直接拿它垫第一帧。
  var seedTable: [String: Ticker] { seeds }

  /// 在范围里、手里还没有值的行，拿种子垫上，攒到这一轮主线程结束一次交出去。
  private func applySeeds(to symbols: Set<String>) {
    guard !seeds.isEmpty else { return }
    for symbol in symbols where raw[symbol] == nil && wanted.contains(symbol) {
      guard let seed = seeds[symbol] else { continue }
      raw[symbol] = seed
      seededBatch.append(seed)
    }
    guard !seededBatch.isEmpty, seedFlush == nil else { return }
    // 一屏搜索结果是一行行 `onAppear` 进来的，攒成一批只发一次，不必每行各发一帧。
    seedFlush = Task { [weak self] in
      guard let self else { return }
      self.seedFlush = nil
      let batch = self.seededBatch.filter { self.raw[$0.symbol] == $0 }
      self.seededBatch.removeAll()
      self.emitNow(batch.map(self.presented))
    }
  }

  func watchHistory(_ symbol: String, visible: Bool) {
    let symbol = InstrumentID.canonical(symbol)
    if visible { historyWanted.insert(symbol); requestQuote(symbol); loadHistories() }
    else {
      historyWanted.remove(symbol)
      historyJobs.removeValue(forKey: symbol)?.cancel()
    }
  }

  private func loadHistories() {
    guard foreground, visible, online else { return }
    for symbol in historyWanted where historyJobs.count < Self.historyConcurrency && historyJobs[symbol] == nil && raw[symbol] != nil {
      guard Date().timeIntervalSince(historyRequested[symbol] ?? .distantPast) >= 60 else { continue }
      historyRequested[symbol] = Date()
      let rest = provider(for: symbol)
      historyJobs[symbol] = Task { [weak self] in
        let now = Int64(Date().timeIntervalSince1970 * 1000)
        let bars = try? await rest.klines(symbol: symbol, interval: .m1, limit: 245,
          startTime: now - 4 * 3_600_000 - 60_000, endTime: now)
        guard let self, !Task.isCancelled else { return }
        self.historyJobs[symbol] = nil
        if bars == nil { self.historyRequested[symbol] = Date().addingTimeInterval(-30) }
        if let bars, !bars.isEmpty { self.onHistory?(symbol, bars) }
        self.loadHistories()
      }
    }
  }

  /// 把上次存下的当日开盘价读回来，让冷启动第一帧的涨跌幅就有值。
  ///
  /// `read` 自己对边界，跨了一天就返回空——那时本来也该重新取。
  private func restoreBaselines() {
    retargetProfile()
    guard let boundary else { return }
    let saved = BaselineSnapshot.read(quotePaths.opens, boundary: boundary)
    guard !saved.isEmpty else { return }
    for (symbol, price) in saved { opens[symbol] = (boundary, price); provisionalOpens.remove(symbol) }
    persistedOpens = Set(saved.keys); persistedBoundary = boundary
  }

  private func persistBaselines() {
    retargetProfile()
    guard let boundary else { return }
    // 顶上去的那批不落盘：下次冷启动读回来的必须是交易所口径的开盘价。
    let rows = opens.filter { $0.value.time == boundary && !provisionalOpens.contains($0.key) }.mapValues(\.price)
    guard !rows.isEmpty else { return }
    guard persistedBoundary != boundary || Set(rows.keys) != persistedOpens else { return }
    persistedOpens = Set(rows.keys); persistedBoundary = boundary
    let url = quotePaths.opens
    // 和 `persistQuotes` 同一条理由：链起来，后一笔一定落在前一笔之后；被撤的那一笔不写。
    let previous = baselineTask
    previous?.cancel()
    baselineTask = Task.detached(priority: .utility) {
      _ = await previous?.value
      guard !Task.isCancelled else { return }
      BaselineSnapshot.write(boundary: boundary, opens: rows, to: url)
    }
  }

  private func resetBaselineRequests() {
    generation += 1
    jobs.values.forEach { $0.cancel() }; jobs.removeAll(); queue.removeAll()
    failedAt.removeAll(); failCount.removeAll()
  }

  /// 这一档的开盘价。
  ///
  /// 正常情况就是跨过边界那根 1h K 线的开盘价。但 XAU / XAG 这些 TradFi 永续
  /// 周末休市：边界那个小时根本没有成交，也就没有那根 K 线，于是这一行的涨跌幅
  /// 永远是空的——用户截图里 XAG 空着就是这么来的。休市的时候基准本来就该取
  /// 「停盘前最后成交价」，所以退一步去拿边界之前的最后一根，用它的收盘价。
  private static func dayOpen(symbol: String, boundary: Int64, rest: any MarketProvider) async -> Double? {
    let bars = try? await rest.klines(symbol: symbol, interval: .h1, limit: 1,
      startTime: boundary, endTime: boundary + 3_600_000 - 1)
    if let bar = bars?.first, bar.openTime == boundary, bar.open.isFinite, bar.open > 0 { return bar.open }
    guard bars != nil else { return nil }  // 请求本身失败了，不是「这个小时没成交」。
    let previous = try? await rest.klines(symbol: symbol, interval: .h1, limit: 1, endTime: boundary - 1)
    // 最后一根成交比边界早过一周，就当「这一档没有可用的基准」：休市最长也就是
    // 元旦那种连着几天，一周以前的收盘价拿来当今天的开盘价只会得出一个荒唐的涨跌幅。
    //
    // 注意这**只**决定涨跌幅要不要留空（显示 `--`），价格照常显示，也不代表这个品种
    // 下架了——「下架」只由品种表里的 `SymbolInfo.status` 说（审查 B.5）。老注释写的
    // 「太老的那种是已经下架的品种」把一个显示口径当成了下架判据，那是错的：一个刚
    // 停牌两天的合约在这儿会被判成有基准，一个只是长期不活跃的 TradFi 反而被判成下架。
    guard let bar = previous?.first, boundary - bar.openTime <= 7 * 86_400_000,
          bar.close.isFinite, bar.close > 0 else { return nil }
    return bar.close
  }

  private func drain() {
    guard foreground, online, let boundary else { return }
    while jobs.count < Self.baselineConcurrency, let symbol = queue.first {
      queue.remove(symbol)
      let generation = self.generation, rest = provider(for: symbol)
      jobs[symbol] = Task { [weak self] in
        let price = await Self.dayOpen(symbol: symbol, boundary: boundary, rest: rest)
        guard let self, !Task.isCancelled, generation == self.generation else { return }
        self.jobs[symbol] = nil
        if let price {
          self.opens[symbol] = (boundary, price)
          self.provisionalOpens.remove(symbol)
          self.failedAt[symbol] = nil; self.failCount[symbol] = nil
        } else {
          self.failedAt[symbol] = Date()
          self.failCount[symbol, default: 0] += 1
        }
        if let value = self.raw[symbol] { self.publish([value]) }
        self.drain()
        // 这一批取完了就存一次。开盘价在这一档边界里不会再变，下次冷启动直接读，
        // 涨跌幅和价格同一帧出来。
        if self.jobs.isEmpty, self.queue.isEmpty { self.persistBaselines() }
      }
    }
  }

  private func publish(_ batch: [Ticker]) {
    guard !quoteJobs.isEmpty || !quoteQueue.isEmpty else { emit(batch); return }
    // 首轮补价还在路上。已经露过面的行照常发（它只是数字变一下），头一回露面的
    // 行攒起来——图上那个品种除外，头部的价格不能等。
    var immediate: [Ticker] = [], held: [Ticker] = []
    for ticker in batch {
      if ticker.symbol == chartSymbol || everPublished.contains(ticker.symbol) { immediate.append(ticker) }
      else { held.append(ticker) }
    }
    if !immediate.isEmpty { emit(immediate) }
    guard !held.isEmpty else { return }
    if coalescedEpoch != batchEpoch { coalesced.removeAll(keepingCapacity: true); coalescedEpoch = batchEpoch }
    for ticker in held { coalesced[ticker.symbol] = ticker }
    guard coalesceFlush == nil else { return }
    let epoch = batchEpoch
    coalesceFlush = Task { [weak self] in
      try? await Task.sleep(nanoseconds: UInt64(Self.coalesceMaxSeconds * 1_000_000_000))
      guard let self, !Task.isCancelled, epoch == self.batchEpoch else { return }
      self.flushCoalesced()
    }
  }

  /// 攒一帧，够钟才发。
  ///
  /// 首帧合帧（`coalesced`）解决的是「一行行往外冒」，这里解决的是相反的一头：
  /// 稳定下来之后，二十几行各自按自己的节奏推 ticker，一秒能进来十几次，
  /// 每一次都让整张自选表重算一遍行。合批之后最多每 `steadyCoalesceSeconds`
  /// 画一帧——数字照样是最新的（缓冲按品种覆盖，不排队），只是不再一帧一行地画。
  ///
  /// 前沿先发：第一笔立刻出去，不给「点进列表先愣一下」的机会；之后落在窗口里的
  /// 才攒到窗口末尾一起发。
  private func emit(_ batch: [Ticker]) {
    if steadyEpoch != batchEpoch { steady.removeAll(keepingCapacity: true); steadyEpoch = batchEpoch }
    for ticker in batch {
      everPublished.insert(ticker.symbol)
      steady[ticker.symbol] = ticker
    }
    notePersist()
    deliver()
  }

  private func deliver() {
    guard !steady.isEmpty else { return }
    let window = visible ? Self.steadyCoalesceSeconds : Self.hiddenCoalesceSeconds
    let wait = window - Date().timeIntervalSince(lastEmit)
    guard wait > 0 else { flushSteady(); return }
    guard steadyFlush == nil else { return }
    let epoch = batchEpoch
    steadyFlush = Task { [weak self] in
      try? await Task.sleep(nanoseconds: UInt64(wait * 1_000_000_000))
      guard let self, !Task.isCancelled, epoch == self.batchEpoch else { return }
      self.steadyFlush = nil
      self.flushSteady()
    }
  }

  /// 把攒着的两批整代作废：任务停掉、缓冲清掉、代号 +1。
  ///
  /// 单靠 `cancel()` 不够——真正危险的不是那两个任务，而是**缓冲里的内容**：
  /// 换号 / 换上游之后随便谁再触发一次 flush，上一代的行照样出得去。
  private func discardBatches() {
    coalesceFlush?.cancel(); coalesceFlush = nil
    steadyFlush?.cancel(); steadyFlush = nil
    coalesced.removeAll(keepingCapacity: true)
    steady.removeAll(keepingCapacity: true)
    batchEpoch &+= 1
  }

  /// 两个合批缓冲里还攒着、没发出去的行数。给用例看「换号那一刻它们有没有跟着丢」。
  var pendingBatchRows: Int { coalesced.count + steady.count }

  private func flushSteady() {
    steadyFlush?.cancel(); steadyFlush = nil
    // 攒的时候还是上一代：一行都不发。
    guard steadyEpoch == batchEpoch else { steady.removeAll(keepingCapacity: true); return }
    guard !steady.isEmpty else { return }
    // 盘上已经没有的品种不发：它要么被换号清掉了，要么已经不在当前范围里，
    // 发出去就是一行没人认领的价格。
    let batch = steady.values.filter { raw[$0.symbol] != nil }
    steady.removeAll(keepingCapacity: true)
    guard !batch.isEmpty else { return }
    lastEmit = Date()
    onUpdate?(batch.map(presented))
  }

  /// 把攒着的首帧行一次发出去。首轮补价排空、或者等满 `coalesceMaxSeconds` 就走这儿——
  /// 哪个先到算哪个，慢的那几行不会把整屏一起拖住。
  private func flushCoalesced() {
    coalesceFlush?.cancel(); coalesceFlush = nil
    guard coalescedEpoch == batchEpoch else { coalesced.removeAll(keepingCapacity: true); return }
    guard !coalesced.isEmpty else { return }
    let batch = coalesced.values.filter { raw[$0.symbol] != nil }
    coalesced.removeAll(keepingCapacity: true)
    guard !batch.isEmpty else { return }
    emit(batch)
  }

  private func startStream() {
    guard pump == nil else { return }
    // 每家一条连接，由各家提供者自己建（线路与退路也归它管）。首帧前的窗口用提供者
    // 的默认值：线路是用户定死的，冷门品种 15 秒内真可能一帧都没有，收窄就变成
    // 「订阅没生效」的重连循环（A-07）。
    var byVenue: [String: any MarketProvider] = [:]
    for venue in VenueRegistry.all { byVenue[venue.id] = provider(for: venue.defaultSymbol) }
    let makers = byVenue
    let log = QuoteBook.log
    let socket = MergedMarketStream { venue in makers[venue]?.makeStream(silenceMs: nil, log: log) }
    let generation = session.generation
    self.socket = socket
    let names = streamNames()
    subscribedStreams = names
    socket.want(names)
    pump = Task { [weak self] in
      let events = await socket.open()
      for await event in events {
        guard let self, !Task.isCancelled, generation == self.session.generation else { break }
        switch event {
        case .payload(.tickerBatch(let batch)):
          guard !batch.isEmpty else { continue }
          self.noteLive(); self.ingest(batch)
        case .payload(.ticker(let ticker)):
          self.noteLive(); self.ingest([ticker])
        case .status(let status):
          // 握手成功还不等于行情到达。
          if status != .live {
            // 断了就把指示灯熄掉，但别把数字抹了——空列表比一个标注为
            // 「非实时」的旧价格更没用，用户也更容易以为是卡死。
            self.status = status; self.lastListUpdate = nil
            self.cancelQuotes(); self.latestReceived.removeAll(keepingCapacity: true)
          }
        default: break
        }
      }
    }
  }

  private func noteLive() {
    let now = Date()
    if lastListUpdate == nil || now.timeIntervalSince(lastListUpdate!) >= 1 { lastListUpdate = now }
    if status != .live { status = .live }
  }

  private func networkChanged(_ online: Bool) {
    guard needsConnection else { return }
    self.online = online
    restartStream()
  }

  /// `clearing` 只在换交易所时为真。断线重连不清价：`latestReceived` 这类
  /// 跨连接不能延用的顺序状态照清，显示值留着，第一帧到了自然覆盖。
  private func restartStream(clearing: Bool = false) {
    // 清空重连（换交易所）：先把合批缓冲整代作废，再往下走。
    // 顺序要紧——下面的 `cancelQuotes()` 会 `flushCoalesced()`，那一步正是把
    // 上一家交易所攒着的行发出去的地方。
    if clearing { discardBatches() }
    stopStream(); cancelQuotes(); resetBaselineRequests()
    historyJobs.values.forEach { $0.cancel() }; historyJobs.removeAll()
    batchJob?.cancel(); batchJob = nil
    session.reset(); latestReceived.removeAll(keepingCapacity: true); lastListUpdate = nil
    if clearing {
      raw.removeAll(keepingCapacity: true); receivedAt.removeAll(keepingCapacity: true)
      everPublished.removeAll(keepingCapacity: true); onReset?()
    }
    startedAt = Date(); firstQuoteMs = nil
    status = online ? .reconnecting : .offline
    guard online else { return }
    startStream()
    for symbol in visibleRows { requestQuote(symbol) }
    if let chartSymbol { requestQuote(chartSymbol) }
  }

  private func cancelQuotes() {
    quoteJobs.values.forEach { $0.cancel() }; quoteJobs.removeAll()
    quoteQueue.removeAll(); quoteAttempt.removeAll()
    // 这一轮不跑了，攒着的行现在就发——否则它们要等到下一轮才有机会露面。
    flushCoalesced()
  }

  /// 可见行先请求当前报价；WS 已经在喂的行不再请求。判据是「值够不够新」，
  /// 不是「有没有值」——从后台或磁盘带回来的旧值也要补一次。
  /// REST 与 WS 并行，不依赖 REST 成功。
  private func requestQuote(_ symbol: String) {
    guard foreground, (visible || symbol == chartSymbol || symbol == named), online, wantsQuote(symbol), quoteJobs[symbol] == nil,
          !quoteQueue.contains(symbol), quoteQueue.count < 128,
          Date().timeIntervalSince(quoteAttempt[symbol] ?? .distantPast) >= Self.freshSeconds else { return }
    quoteQueue.append(symbol); drainQuotes()
  }

  /// 攒够一屏要补的行时，用一次全市场请求换掉几十个逐行往返。
  /// 网关只代理单品种，这条只有直连可用；失败就退回下面的逐个请求。
  private func drainBatch() -> Bool {
    guard batchJob == nil, online, Date() >= batchRetry,
          quoteQueue.count >= Self.batchThreshold else { return false }
    // 按交易所分：只有能一次拿全市场的那家（`hasBulkTickers`）才值得走这条，
    // 而且那一家自己攒的行也得够门槛。其余的留在队列里逐个请求。
    let venues = Dictionary(grouping: quoteQueue) { VenueRegistry.descriptor(forSymbol: $0).id }
    guard let (venue, pending) = VenueRegistry.all.lazy.compactMap({ d -> (String, [String])? in
      guard let rows = venues[d.id], rows.count >= Self.batchThreshold,
            self.provider(for: d.defaultSymbol).capabilities.hasBulkTickers else { return nil }
      return (d.id, rows)
    }).first else { return false }
    quoteQueue.removeAll { VenueRegistry.descriptor(forSymbol: $0).id == venue }
    let now = Date()
    var requests: [String: QuoteSession.Request] = [:]
    for symbol in pending { quoteAttempt[symbol] = now; requests[symbol] = session.request(symbol) }
    let rest = provider(for: pending[0])
    batchJob = Task { [weak self] in
      let all = try? await rest.tickers24h(timeout: 6)
      guard let self, !Task.isCancelled else { return }
      self.batchJob = nil
      guard let all else {
        // 换回逐个请求，并且别马上再试一次全市场。
        self.batchRetry = Date().addingTimeInterval(120)
        for symbol in pending { self.quoteAttempt[symbol] = .distantPast }
        for symbol in pending { self.requestQuote(symbol) }
        return
      }
      // 手里已经是那一家的全市场了，顺手当种子收下（板块页那家由板块页供，不重复收）。
      if !VenueRegistry.descriptor(forSymbol: pending[0]).joinsSectors {
        self.seed(all, upstream: rest.capabilities.upstream, venue: venue)
      }
      let accepted = all.filter { ticker in
        guard self.wanted.contains(ticker.symbol), let request = requests[ticker.symbol] else { return false }
        return self.session.accepts(request, symbol: ticker.symbol)
      }
      if !accepted.isEmpty { self.ingest(accepted) }
      self.drainQuotes()
      if self.quoteJobs.isEmpty, self.quoteQueue.isEmpty { self.flushCoalesced() }
    }
    return true
  }

  private func drainQuotes() {
    guard foreground, online else { return }
    if drainBatch() { return }
    while quoteJobs.count < Self.quoteConcurrency, !quoteQueue.isEmpty {
      let symbol = quoteQueue.removeFirst()
      guard wantsQuote(symbol) else { continue }
      quoteAttempt[symbol] = Date()
      let request = session.request(symbol), rest = provider(for: symbol)
      quoteJobs[symbol] = Task { [weak self] in
        // 原来这儿是 `try?`：交易所回「我不认识这个代号」和「网络不通」被压成同一个
        // `nil`，于是一个已经下架的自选就永远停在最后看到的那口价上（审查 B-06）。
        var ticker: Ticker?
        var rejected = false
        do { ticker = try await rest.ticker24h(symbol: symbol, timeout: 5) }
        catch { rejected = SymbolCatalog.rejectsSymbol(error) }
        guard let self, !Task.isCancelled, request.generation == self.session.generation else { return }
        self.quoteJobs[symbol] = nil
        if rejected { self.onSymbolRejected?(symbol) }
        if let ticker {
          if self.session.accepts(request, symbol: symbol) { self.ingest([ticker]) }
          // 推送在这期间到过，整帧作废；但它带的成交额推送帧里没有，照收这一格。
          else { self.ingestTurnover(ticker) }
        }
        self.drainQuotes()
        if self.quoteJobs.isEmpty, self.quoteQueue.isEmpty { self.flushCoalesced() }
      }
    }
  }

  private func stopStream() {
    pump?.cancel(); pump = nil
    let old = socket; socket = nil; subscribedStreams = []
    Task { await old?.stop() }
  }

  /// 宿主销毁：立刻放连接，不走那 25 秒宽限。
  ///
  /// 宽限是给「切出去一下就回来」留的；根都没了就没有「回来」这回事，
  /// 再留着 socket 只是在没有界面的情况下继续收帧。
  func shutdown() {
    foreground = false
    visible = false
    favorites = []
    alerted.removeAll()
    teardown()   // 它自己会落一次盘
    trackLink()  // 不该再有连接了：停表、复原
    discardBatches()
    onUpdate = nil; onReset = nil; onScopeChange = nil; onHistory = nil
    onPrice = nil
    onSymbolRejected = nil
  }
}
