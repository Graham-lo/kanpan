import Foundation
import Testing
@testable import KanpanData
import KanpanNetwork
import KanpanNetworkTestSupport
import KanpanCore

/// 第四轮 A.3.4 / A.3.5 / A-T05 / A-T15：撞上封禁之后这一轮就该结束，
/// 以及分钟边界上掉线时那个洞怎么补回来。
///
/// 这两件事都只能在 `MarketFeed` 这一层验：`KanpanNetwork` 里的 A-T01…A-T04 管的是
/// 「限流器与 REST 自己不叠加」，而真正把同一个封禁撞成 3×4＝12 次的是外面这层
/// 首屏重试——它必须在「短时间内不可能成功」的那几种错误上当场收手，
/// 落到既有的「点此重试」入口，本地图表原样留着。
@Suite("封禁后的首屏与分钟边界补洞")
struct FeedBlockedRetryTests {

  private func tempPaths() -> Paths {
    let p = Paths(root: URL(fileURLWithPath: NSTemporaryDirectory())
      .appendingPathComponent("kanpan-blocked-\(UUID().uuidString)"))
    try? p.ensureRoot()
    return p
  }

  /// 收 `FeedUpdate` 的小盒子：留「横幅文案」（此刻的和亮过的每一条）和「有没有报过离线」。
  private actor Seen {
    private(set) var banner: String?
    /// 亮过的每一条横幅，按先后。横幅是「最后一条说了算」，而封禁期间合法地会亮两条：
    /// 首屏那句，和 WS（重）连上之后补缺被封禁挡回来的「行情缺口暂未补齐」。两者谁后到
    /// 取决于 WS 握手和首屏回包谁快，是调度决定的，所以要问「首屏那句亮过没有」得看这里。
    private(set) var banners: [String] = []
    private(set) var offline = false
    func note(_ update: FeedUpdate) {
      switch update.event {
      case .historyError(let text):
        banner = text
        if let text { banners.append(text) }
      case .status(let s): if s == .offline { offline = true }
      default: break
      }
    }
    func clearBanner() { banner = nil; banners = [] }
  }

  /// 封禁期间允许亮的两条横幅（都带「点此重试」）。
  private static let firstFillBanner = "历史行情暂未加载，点此重试"
  private static let gapBanner = "行情缺口暂未补齐，点此重试"

  /// 被上游按住的出口：每一发都回 429 + `Retry-After`，并且数出站次数。
  private actor BannedUpstream: HTTPTransport {
    private let retryAfterSeconds: Int
    private(set) var calls = 0
    private(set) var klineCalls = 0
    init(retryAfterSeconds: Int) { self.retryAfterSeconds = retryAfterSeconds }
    func get(_ url: URL, timeout: TimeInterval) async throws -> HTTPReply {
      calls += 1
      if url.path.contains("klines") { klineCalls += 1 }
      return json(#"{"code":-1003,"msg":"Too many requests"}"#, status: 429,
                  headers: ["Retry-After": "\(retryAfterSeconds)"])
    }
  }

  // ---------------------------------------------------------------- A-T05

  /// A-T05：上游给的是 `Retry-After: 3600`。
  ///
  /// 三件事一起验：
  /// ① 没有人替用户睡一个小时——限流器对超过 `waitableBanMs` 的封禁是**拒发**不是等；
  ///    外层首屏重试也当场收手，日志里只有「本轮到此为止」，没有任何一档「退避重试」
  ///    （断言走日志而不是墙上时钟：机器被别的用例占满时，掐秒数只会让用例乱闪）；
  /// ② 本地图表（快照打的底）一根不少，还留在屏幕上；
  /// ③ 封禁没到点时用户再点一次「点此重试」，一个包都不许出站。
  @Test("A-T05 封禁期内首屏立刻收手：图表留着、横幅亮着、重试不再撞上游")
  func blockedFirstFillEndsTheRound() async throws {
    let paths = tempPaths()
    defer { try? FileManager.default.removeItem(at: paths.root) }
    // 「上次退出时」的快照：这就是封禁期间用户屏幕上该留着的那张图。
    let seed = makeSeries("BTCUSDT", .m1, count: 300)
    _ = try SeriesStore.write(seed, in: paths.series)

    // 封禁按报告给的 3600 秒（A-T05）。REST / 限流器 / feed 用阶梯时钟：针只在有人
    // `sleep` 时才走，所以
    // - 「封禁还剩很久」（> 3_000_000 毫秒）不再随墙上时钟流逝——原来用 FastPacer(0.01)，
    //   整包并行跑时这条用例被饿过 6 秒真实时间，封禁就「自己快到点了」；
    // - 「有没有人在等封禁结束」直接看睡眠账本：谁要是去睡那 3600 秒，账上一目了然，
    //   不必再拿墙上时钟掐「横幅 10 秒内亮」（机器忙的时候那个秒数只会乱闪）。
    let pacer = StepPacer()
    let upstream = BannedUpstream(retryAfterSeconds: 3600)
    // 真 `MarketRESTTransport`（直连档）：这样「点此重试」清的是真的线路冷却，
    // 而不是一个空操作。清完线路冷却，限流器上的 IP 封禁仍然在（A-03 第 4 点）。
    let routed = MarketRESTTransport(source: .binance, gateways: ["gw.example.com"],
                                     transport: upstream, policy: .direct)
    let limiter = RateLimiter(pacer: pacer, minGapMs: 0)
    let rest = BinanceREST(transport: routed, limiter: limiter, pacer: pacer)
    // WS 走真时钟：它的看门狗在阶梯时钟上会一睡就「到点」，连着空转重连。原来它跟着
    // FastPacer(0.01)，60 虚拟秒的首帧窗口只有 0.6 秒真实时间，用例一慢就重连一次，
    // 每次重连都去补缺、被封禁挡回来，把横幅换成「行情缺口暂未补齐」。
    let ws = BinanceWS(factory: ReplayFactory(deck: ReplayDeck([.hang]), pacer: SystemPacer()),
                       pacer: SystemPacer())
    let logged = Waits()
    let feed = MarketFeed(rest: rest, ws: ws, paths: paths, pacer: pacer, reconcileMs: 0,
                          log: FeedLog { logged.note($0) })

    let seen = Seen()
    let stream = await feed.events()
    let pump = Task { for await update in stream { await seen.note(update) } }
    defer { pump.cancel() }

    await feed.start(symbol: "BTCUSDT", interval: .m1)
    #expect(await waitUntil(20) { await seen.banners.contains(Self.firstFillBanner) })
    // 没人在等封禁结束：睡眠账本上没有一笔长到能「等过」封禁（能等的上限是 10 秒）。
    let slept = await pacer.sleepLog()
    #expect(slept.allSatisfy { $0 < RateLimiter.waitableBanMs }, "有人在等封禁结束：\(slept)")
    // 横幅亮着，而且只会是封禁期间那两条之一（WS 连上后补缺被挡回来那条是合法的）。
    #expect(await seen.banner != nil)
    let firstRound = await seen.banners
    #expect(firstRound.allSatisfy { $0 == Self.firstFillBanner || $0 == Self.gapBanner }, "\(firstRound)")
    #expect(await seen.offline)

    // 本地图表原样留着：封禁不是「把图清空」的理由。
    let kept = await feed.currentSeries
    #expect(kept.count == seed.count)
    #expect(kept.lastTime == seed.lastTime)

    // 零叠加：首屏那一层当场收手，一档退避都没走。
    let lines = logged.all()
    #expect(lines.contains { $0.contains("本轮到此为止") },
            "没看到「撞上封禁就收手」那一行：\(lines)")
    #expect(!lines.contains { $0.contains("退避重试") },
            "外层还在叠加重试：\(lines.filter { $0.contains("退避重试") })")

    // 封禁记在限流器上，而且是上游说的那个长度（3600 秒，远超我们自己那点秒级退避）。
    #expect(await limiter.banRemainingMs() > 3_000_000)
    // 出站次数：首屏那一发 + 快照缺口那一发最多两笔（它们是同时出发的，
    // 封禁是第一个回包才记上的）。要是外层还在叠加，这里会是十几笔。
    let sentBefore = await upstream.calls
    #expect(sentBefore <= 2, "封禁期内出站 \(sentBefore) 次")
    #expect(await upstream.klineCalls <= 2)

    // 用户点「点此重试」：和 `RoutedMarketFeed.retry()` 同一条路——先清线路冷却，
    // 再重新加载。封禁没到点，所以这一轮一个包都不许出站，横幅照旧。
    await seen.clearBanner()
    await rest.resetRouteCooldowns()
    await feed.switchTo(symbol: "BTCUSDT", interval: .m1)
    #expect(await waitUntil(20) { await seen.banners.contains(Self.firstFillBanner) })
    #expect(await seen.banner != nil)
    let retryRound = await seen.banners
    #expect(retryRound.allSatisfy { $0 == Self.firstFillBanner || $0 == Self.gapBanner }, "\(retryRound)")
    let sleptAfter = await pacer.sleepLog()
    #expect(sleptAfter.allSatisfy { $0 < RateLimiter.waitableBanMs }, "\(sleptAfter)")
    let sentAfter = await upstream.calls
    #expect(sentAfter == sentBefore, "重试又去撞了上游：\(sentAfter) 次")
    #expect(await limiter.banRemainingMs() > 3_000_000)   // 点重试也不能让封禁提前结束
    #expect(await feed.currentSeries.count == seed.count)
    await feed.stop()
  }

  // ---------------------------------------------------------------- A.3.4（451）

  /// 被地区拒绝的出口：每一发都回 451，并且数出站次数。
  private actor GeoRefusedUpstream: HTTPTransport {
    private(set) var calls = 0
    private(set) var klineQueries: [String] = []
    var klineCalls: Int { klineQueries.count }
    func get(_ url: URL, timeout: TimeInterval) async throws -> HTTPReply {
      calls += 1
      if url.path.contains("klines") { klineQueries.append(url.query ?? "") }
      return json(#"{"code":0,"msg":"Service unavailable from a restricted location"}"#,
                  status: 451)
    }
  }

  /// 451 比限流更没救：这条线路的出口被上游按地区拒了，退避几秒再打一遍（网关档
  /// 每一遍还要把两台网关都竞速一次）结果一模一样。所以首屏这一轮也必须当场收手，
  /// 落到既有的「点此重试」，把换线路的决定交回用户。
  @Test("A.3.4 451 地域拒绝也只打一发：落到既有的「点此重试」，不叠加退避")
  func geoBlockedFirstFillEndsTheRound() async throws {
    let paths = tempPaths()
    defer { try? FileManager.default.removeItem(at: paths.root) }
    let seed = makeSeries("BTCUSDT", .m1, count: 300)
    _ = try SeriesStore.write(seed, in: paths.series)

    let pacer = FastPacer(scale: 0.01)
    let upstream = GeoRefusedUpstream()
    let limiter = RateLimiter(pacer: pacer, minGapMs: 0)
    let rest = BinanceREST(transport: upstream, limiter: limiter, pacer: pacer)
    // WS 走真时钟，理由同 A-T05：跟着 FastPacer(0.01) 时 60 虚拟秒的首帧窗口只有
    // 0.6 秒真实时间，机器一忙就重连，重连后的补缺同样吃 451，横幅被换成「行情缺口
    // 暂未补齐」——那是合法行为，不是本条要验的东西。
    let ws = BinanceWS(factory: ReplayFactory(deck: ReplayDeck([.hang]), pacer: SystemPacer()),
                       pacer: SystemPacer())
    let logged = Waits()
    let feed = MarketFeed(rest: rest, ws: ws, paths: paths, pacer: pacer, reconcileMs: 0,
                          log: FeedLog { logged.note($0) })
    let seen = Seen()
    let stream = await feed.events()
    let pump = Task { for await update in stream { await seen.note(update) } }
    defer { pump.cancel() }

    await feed.start(symbol: "BTCUSDT", interval: .m1)
    // 首屏这一轮落到「历史行情暂未加载，点此重试」；之后横幅一直亮着，且只会是
    // 这条或 WS 连上后补缺被 451 挡回的那条。
    #expect(await waitUntil(20) { await seen.banners.contains(Self.firstFillBanner) })
    #expect(await seen.banner != nil)
    let banners = await seen.banners
    #expect(banners.allSatisfy { $0 == Self.firstFillBanner || $0 == Self.gapBanner }, "\(banners)")
    // 本地图表原样留着。
    #expect(await feed.currentSeries.count == seed.count)

    let lines = logged.all()
    #expect(lines.contains { $0.contains("本轮到此为止") },
            "451 也该当场收手：\(lines)")
    #expect(!lines.contains { $0.contains("退避重试") },
            "451 还在叠加退避重试：\(lines.filter { $0.contains("退避重试") })")
    // 零叠加的硬判据：**首屏那一条请求只发了一次**。没有这一项时 `fillOnce` 会按
    // 1/2/3 秒退避把同一条 query 打三遍（网关档每一遍还要竞速两台）。
    // （`startTime=` 那种是补缺，另有自己的节奏，不在这一条的判据里。）
    let firstScreen = await upstream.klineQueries.filter { !$0.contains("startTime") }
    #expect(firstScreen.count == 1, "首屏这一条被重发了：\(firstScreen)")
    #expect(await staysFalse(for: 1) {
      await upstream.klineQueries.filter { !$0.contains("startTime") }.count > 1
    }, "晚一点还是把首屏那条请求重发了")
    // 451 不是限流：不许在本机限流器上记罚停，换一条线路应该立刻能用。
    #expect(await limiter.banRemainingMs() == 0)
    await feed.stop()
  }

  // ---------------------------------------------------------------- A-T15

  /// A-T15：一根 K 线刚好在分钟边界上收线（`x=true`），连接就在那一刻被掐；
  /// 新连接晚了一段才开始出报文，这期间的报文全丢。
  ///
  /// 只验两件事（报告里点名的那两件）：补洞请求真的从断线前的末根往后发了出去，
  /// 以及补回来的那一段和交易所自己的真相逐根一致（时间轴仍然整分钟等距，
  /// 边界那根是收线值，不是半截）。
  @Test("A-T15 分钟边界上掉线、新连接晚到：补洞请求发出去，补回来的与交易所一致")
  func minuteBoundaryGapRefill() async throws {
    let rec = Recording.load()
    // 找一条 x=true 的报文：那一刻上一根刚收线，正是分钟边界。
    let boundary = try #require((200..<rec.lines.count).first { i in
      guard let k = rec.klineIndexOfLine[i] else { return false }
      return rec.klines[k].closed
    })
    let closedBar = rec.klines[rec.klineIndexOfLine[boundary]!].bar
    let lost = 200

    var steps: [ReplayStep] = rec.lines.prefix(boundary + 1).map { .frame(.text($0)) }
    steps.append(.drop("分钟边界上被掐了"))
    // 新连接晚到：重连上去之后先静默 20 秒（虚拟时钟，FastPacer 下是毫秒级），
    // 这期间交易所照常在成交，报文却没人收——那就是要靠 REST 补回来的洞。
    steps.append(.silence(20_000))
    steps += rec.lines.dropFirst(boundary + 1 + lost).map { .frame(.text($0)) }
    steps.append(.hang)
    let stepCount = steps.count

    let deck = ReplayDeck(steps)
    let pacer = FastPacer()
    let truth = Counter()
    let ex = FakeExchange(rec: rec, cursor: truth)
    let server = FakeServer(pacer: pacer) { url in
      // 掉线之后交易所手上比我们多 `lost` 行：断线期间的成交它当然知道。
      let k = deck.cursor.value
      truth.setTo(k <= boundary ? k : min(rec.lines.count, k + lost))
      return ex.reply(for: url)
    }
    let paths = tempPaths()
    defer { try? FileManager.default.removeItem(at: paths.root) }
    let rest = BinanceREST(transport: FakeTransport(server), pacer: pacer)
    let ws = BinanceWS(factory: ReplayFactory(deck: deck, pacer: pacer), pacer: pacer)
    let feed = MarketFeed(rest: rest, ws: ws, paths: paths, pacer: pacer, reconcileMs: 0)
    _ = await feed.events()
    await feed.start(symbol: "BTCUSDT", interval: .m1)
    #expect(await waitUntil(20) { await deck.progress() >= stepCount - 1 })
    #expect(await waitUntil(10) { await deck.stats().connects >= 2 })   // 真的重连了

    // ① 补洞请求启动了：带 `startTime` 的那一发，就是「从断线前的末根往后要」，
    //    不是整屏重拉。
    #expect(await waitUntil(20) {
      await server.urls().contains {
        $0.path.contains("klines") && ($0.query?.contains("startTime=") ?? false)
      }
    })

    // ② 源一致：等序列收敛到交易所的真相，然后逐根比。
    truth.setTo(rec.lines.count)
    let want = ex.bars(now: rec.lines.count)
    let byTime = Dictionary(uniqueKeysWithValues: want.map { ($0.openTime, $0) })
    // 等它真的收敛：末根是活的，报文还在往里灌，`count` 够了不代表每一根都已经是
    // 交易所的最终值（机器忙的时候最后那一两根会停在半截上）。收敛条件就是下面
    // 逐根比的那一条，只是先给它时间走到位，失败时再由逐根断言说清是哪一根。
    #expect(await waitUntil(20) {
      let s = await feed.currentSeries
      guard s.count >= want.count else { return false }
      return (0..<s.count).allSatisfy { i in
        guard let w = byTime[s.time(at: i)] else { return true }
        return s.bar(at: i) == w
      }
    })
    let got = await feed.currentSeries
    #expect(got.symbol == "BTCUSDT")
    #expect(got.interval == .m1)
    for i in 0..<got.count {
      if let w = byTime[got.time(at: i)] {
        #expect(got.bar(at: i) == w, "第 \(i) 根和交易所不一致\n  got  \(got.bar(at: i))\n  want \(w)")
      }
    }
    // 洞补上了：时间轴整分钟等距，而且边界那根（收线的那根）在里面。
    for i in 1..<got.count { #expect(got.time(at: i) == got.time(at: i - 1) + 60_000) }
    let atBoundary = try #require((0..<got.count).first { got.time(at: $0) == closedBar.openTime })
    #expect(got.bar(at: atBoundary) == byTime[closedBar.openTime])
    #expect(got.lastTime > closedBar.openTime)
    await feed.stop()
  }
}
