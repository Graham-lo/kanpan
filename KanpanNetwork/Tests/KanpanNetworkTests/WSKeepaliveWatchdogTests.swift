import Foundation
import Testing
@testable import KanpanNetwork
import KanpanNetworkTestSupport
import KanpanCore

/// 第四轮 A-07：「行情没更新」和「连接死了」是三件不同的事。
///
/// 三层窗口（`BinanceWS` 的注释里也写着同一套）：
/// 1. 传输层还通不通：行情静默时主动 ping，`keepaliveProbeMs` 内要有 pong；
///    只有连续 `transportSilenceMs`（默认 30 秒）既没有帧也探不到 pong 才重连；
/// 2. 订阅生效了没有：**第一帧有效行情之前**，`silenceMs`（网关档 15 秒 / 直连 60 秒）
///    内什么都没推来就是这条路不对，照旧重连换一条；
/// 3. 行情有没有变：第一帧之后的静默都是合法的，不许再拆连接——夜里冷门品种
///    十几分钟不成交是常态，拆了重连换来的还是同样的静默。
@Suite("A-07 三层静默看门狗")
struct WSKeepaliveWatchdogTests {

  /// 一帧真行情（`markPriceUpdate` 解得开，`gotFrame` 会被置上）。
  private static let market = #"{"e":"markPriceUpdate","s":"BTCUSDT","p":"90000","E":1700000000000}"#
  /// SUBSCRIBE 的应答：解出来是 `.other`，**不算**有效行情。
  private static let ack = #"{"result":null,"id":1}"#

  // ---------------------------------------------------------------- A-T13

  @Test("A-T13 收到首帧行情之后长时间没有行情但保活正常：连接保留，不重连")
  func legalMarketSilenceKeepsTheConnection() async throws {
    // 首帧行情 → 然后十分钟（虚拟）一帧都不推。传输层答保活。
    let deck = ReplayDeck([.frame(.text(Self.market)), .silence(600_000), .hang],
                          answersKeepalive: true)
    let pacer = FastPacer()
    let ws = BinanceWS(factory: ReplayFactory(deck: deck, pacer: pacer), pacer: pacer,
                       silenceMs: 15_000, transportSilenceMs: 30_000, keepaliveProbeMs: 10_000)
    let stream = await ws.start(streams: ["btcusdt@kline_1m"])
    let seen = Statuses()
    let reader = Task { for await event in stream { await seen.note(event) } }

    // 静默期里保活探针一拍一拍地发（第一拍 15 秒，之后每 15 秒＝min(15s, 30s/2)）。
    #expect(await waitUntil(5) { await deck.stats().keepalives >= 3 })
    // 关键断言：一次都没有重连，也没有报「重连中」。
    #expect(await deck.stats().connects == 1)
    #expect(await seen.connects() == 1)
    #expect(await seen.sawReconnecting() == false)
    await ws.stop()
    reader.cancel()
  }

  @Test("A-T13 保活答得上就一直留着：探了很多拍也只有一条连接")
  func manyProbesStillOneConnection() async throws {
    let deck = ReplayDeck([.frame(.text(Self.market)), .silence(600_000), .hang],
                          answersKeepalive: true)
    let pacer = FastPacer()
    let ws = BinanceWS(factory: ReplayFactory(deck: deck, pacer: pacer), pacer: pacer,
                       silenceMs: 15_000, transportSilenceMs: 30_000, keepaliveProbeMs: 10_000)
    let stream = await ws.start(streams: ["btcusdt@kline_1m"])
    let reader = Task { for await _ in stream {} }
    #expect(await waitUntil(5) { await deck.stats().keepalives >= 10 })
    #expect(await deck.stats().connects == 1)
    await ws.stop()
    reader.cancel()
  }

  // ---------------------------------------------------------------- 第①层

  @Test("传输层真的死了（既无帧也无 pong）：到 30 秒那一档才重连")
  func deadTransportReconnects() async throws {
    // 首帧行情之后静默，而且保活探不通——这才是真断线（代理黑洞 / NAT 超时）。
    let deck = ReplayDeck([.frame(.text(Self.market)), .silence(600_000), .hang],
                          answersKeepalive: false)
    let pacer = FastPacer()
    let ws = BinanceWS(factory: ReplayFactory(deck: deck, pacer: pacer), pacer: pacer,
                       silenceMs: 1_000, transportSilenceMs: 3_000, keepaliveProbeMs: 100)
    let stream = await ws.start(streams: ["btcusdt@kline_1m"])
    let reader = Task { for await _ in stream {} }
    #expect(await waitUntil(5) { await deck.stats().connects >= 2 })
    #expect(await deck.stats().keepalives >= 1)     // 拆之前一定探过
    await ws.stop()
    reader.cancel()
  }

  /// 探针探不通的那一段**不许空转**。
  ///
  /// 第一版写成「探不通就把下一拍设成 1 毫秒接着探」，虚拟时钟下那就是 1kHz 干转，
  /// 真机上也是每毫秒一次系统调用，一直转到 30 秒那一档。正确的做法是隔一拍再探，
  /// 而那一拍也走注入的时钟。判据就是**探针次数**：干转会探上万次，隔拍只探几次。
  @Test("探针探不通时按拍重探，不空转：拆连接之前只探了几次")
  func failedProbesDoNotBusyLoop() async throws {
    let deck = ReplayDeck([.frame(.text(Self.market)), .silence(600_000), .hang],
                          answersKeepalive: false)
    let pacer = FastPacer()
    let ws = BinanceWS(factory: ReplayFactory(deck: deck, pacer: pacer), pacer: pacer,
                       silenceMs: 15_000, transportSilenceMs: 30_000, keepaliveProbeMs: 10_000)
    let stream = await ws.start(streams: ["btcusdt@kline_1m"])
    let reader = Task { for await _ in stream {} }
    // 30 秒（虚拟）到点就该拆掉重连。
    #expect(await waitUntil(5) { await deck.stats().connects >= 2 })
    await ws.stop()
    reader.cancel()
    let probes = await deck.stats().keepalives
    #expect(probes >= 1)
    // 节拍是 min(15s, 30s/4)＝7.5 秒，两条连接加起来也就十来次；干转的话是上万次。
    #expect(probes <= 16, "探针发了 \(probes) 次，这是在空转")
  }

  /// 整夜静默时这条日志只该出现一次。每 15 秒刷一条一样的话，等于把日志烧掉，
  /// 真出事时翻不到有用的东西。
  ///
  /// **必须跨帧验**：币安每三分钟发一个 ping，那一帧会让 `receiveFrame` 重新进来一次。
  /// 探针状态要是挂在那个方法的局部变量上，每个 ping 就把它清零，整夜下来这句话
  /// 照样刷满日志——所以牌堆里夹了两个 ping，行情却一帧都不再来。
  @Test("行情静默的保活日志只在状态变化时打一次（跨帧也只有一次）")
  func quietKeepaliveLogsOnce() async throws {
    let deck = ReplayDeck([.frame(.text(Self.market)),
                           .silence(120_000), .frame(.ping),
                           .silence(120_000), .frame(.ping),
                           .silence(600_000), .hang],
                          answersKeepalive: true)
    let pacer = FastPacer()
    let lines = Lines()
    let ws = BinanceWS(factory: ReplayFactory(deck: deck, pacer: pacer), pacer: pacer,
                       silenceMs: 15_000, transportSilenceMs: 30_000, keepaliveProbeMs: 10_000,
                       log: FeedLog { lines.note($0) })
    let stream = await ws.start(streams: ["btcusdt@kline_1m"])
    let reader = Task { for await _ in stream {} }
    // 两个 ping 都收到了（证明这一路真的跨了帧），探针也探了十几拍。
    #expect(await waitUntil(5) { lines.all().filter { $0.contains("回 pong") }.count >= 2 })
    #expect(await waitUntil(5) { await deck.stats().keepalives >= 10 })
    await ws.stop()
    reader.cancel()
    #expect(await deck.stats().connects == 1)
    let quiet = lines.all().filter { $0.contains("传输层保活正常") }
    #expect(quiet.count == 1, "这句话被刷了 \(quiet.count) 次，探针状态又跟着帧重置了")
  }

  // ---------------------------------------------------------------- 第②层

  @Test("首帧行情之前的静默照旧算「订阅没生效」：连保活都不探，直接换一条")
  func silenceBeforeFirstMarketFrameStillReconnects() async throws {
    // 只有订阅应答和 ping，一帧行情都没有。保活明明答得上，也不许留着——
    // 这条连接通是通，但我们要的流没推过来（A-T14 的同一条判据）。
    let deck = ReplayDeck([.frame(.text(Self.ack)), .frame(.ping), .silence(600_000), .hang],
                          answersKeepalive: true)
    let pacer = FastPacer()
    let ws = BinanceWS(factory: ReplayFactory(deck: deck, pacer: pacer), pacer: pacer,
                       silenceMs: 15_000, transportSilenceMs: 30_000, keepaliveProbeMs: 10_000)
    let stream = await ws.start(streams: ["btcusdt@kline_1m"])
    let reader = Task { for await _ in stream {} }
    #expect(await waitUntil(5) { await deck.stats().connects >= 2 })
    #expect(await deck.stats().keepalives == 0)
    await ws.stop()
    reader.cancel()
  }

  /// 第②层的窗口就是传进来的那个数。以前「一条 WS 在几个域名之间竞速」时会被夹到
  /// 15 秒；线路由用户定死、不混源之后，那条竞速链（`streamFallbacks`）2026-09-24 整条删了，
  /// 钳子跟着没了。这里守的是它不会借别的路回来。
  @Test("首帧窗口按传进来的 60 秒等，没有竞速钳子")
  func silenceWindowIsWhatTheCallerPassed() async throws {
    let alone = BinanceWS(factory: ReplayFactory(deck: ReplayDeck([.hang]), pacer: FastPacer()),
                          pacer: FastPacer(), silenceMs: 60_000)
    #expect(await alone.firstFrameSilenceMs == 60_000)
  }

  // ---------------------------------------------------------------- A-T16

  @Test("A-T16 64 条旧流换 64 条新流：两帧控制帧，不是 128 帧")
  func bulkSwitchSendsTwoControlFrames() async throws {
    let deck = ReplayDeck([.frame(.text(Self.market)), .hang], answersKeepalive: true)
    // 这一条要看的是控制帧之间**真的**隔了 250ms，所以时钟不加速。
    let pacer = FastPacer(scale: 1)
    let ws = BinanceWS(factory: ReplayFactory(deck: deck, pacer: pacer), pacer: pacer,
                       silenceMs: 60_000_000)
    let old = (0..<64).map { "sym\($0)usdt@kline_1m" }
    let new = (0..<64).map { "new\($0)usdt@kline_1m" }
    _ = await ws.start(streams: old)
    #expect(await waitUntil(5) { await ws.currentConnectionID == 1 })
    let began = Date()
    await ws.replaceStreams(new)
    #expect(await waitUntil(5) { await ws.streamsInSync })
    let elapsed = -began.timeIntervalSinceNow

    let sent = await deck.stats().sent
    #expect(sent.count == 2)                                  // 不是 64＋64
    #expect(sent.first?.contains("UNSUBSCRIBE") == true)      // 退订先走
    #expect(sent.last?.contains("SUBSCRIBE") == true)
    // 每一帧都把 64 条流打成一包。
    #expect(sent.first?.components(separatedBy: "@kline_1m").count == 65)
    #expect(sent.last?.components(separatedBy: "@kline_1m").count == 65)
    // 两帧之间隔了一个控制帧节拍（250ms，币安对入站控制帧限 10 条/秒）。
    #expect(elapsed >= 0.2)
    await ws.stop()
  }
}

/// 收 `WSEvent` 的小账本：连了几次、有没有报过「重连中」。
private actor Statuses {
  private var connected = 0
  private var reconnecting = false
  func note(_ event: WSEvent) {
    switch event {
    case .connected: connected += 1
    case .status(let s): if s == .reconnecting { reconnecting = true }
    case .payload: break
    }
  }
  func connects() -> Int { connected }
  func sawReconnecting() -> Bool { reconnecting }
}

/// 收日志的小盒子。
final class Lines: @unchecked Sendable {
  private let lock = NSLock()
  private var lines: [String] = []
  func note(_ s: String) { lock.lock(); lines.append(s); lock.unlock() }
  func all() -> [String] { lock.lock(); defer { lock.unlock() }; return lines }
}
