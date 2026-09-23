import Foundation
import Testing
import UIKit
import KanpanAccount
import KanpanCore
import KanpanNetwork
@testable import KanpanMain

// 这一份盯的是「宿主没了 / 换人了 / 连着转两次屏」之后，后台那几摊有没有真的收掉。
// 它们全是**看不见的**泄漏：界面上一切正常，代价落在电量、后台额度和「新表上闪出
// 上一个人的价格」上，所以只能靠用例守。

// ---------------------------------------------------------------- 小工具

/// 用例里攒东西用。`@MainActor` 类才能被 `@Sendable` 闭包捕获。
@MainActor private final class Box<T> {
  var value: T
  init(_ value: T) { self.value = value }
}

@MainActor private func spin(_ seconds: TimeInterval) async {
  try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
}

private func ticker(_ symbol: String, last: Double, id: Int64) -> Ticker {
  Ticker(symbol: symbol, last: last, changePercent: 1, high: last, low: last,
         quoteVolume: 1_000, open24h: last, timeMs: 1_700_000_000_000 + id, lastTradeID: id)
}

// ---------------------------------------------------------------- BT-17

@MainActor
// `.serialized`：`AppLifecycle.shared` 是全 app 唯一一份，两条用例并行跑会
// 互相把对方登记的钩子跑掉。
@Suite("BT-17 宿主销毁之后没人还在跑", .serialized)
struct RootLifecycleTests {

  @Test("根的 @State 存储一释放，收摊的活就跑一次")
  func teardownFiresWhenStateStorageDies() {
    let fired = Box(0)
    do {
      let teardown = RootTeardown()
      teardown.onTeardown { [fired] in fired.value += 1 }
      #expect(fired.value == 0)   // 还活着的时候一次都不许跑
    }
    #expect(fired.value == 1)
  }

  @Test("迟到的旧宿主注销不掉新宿主那份资源登记")
  func staleResourceTokenCannotUnregisterTheLiveOne() {
    let life = AppLifecycle.shared
    let oldLeft = Box(0), newLeft = Box(0)
    let before = life.resourceCount

    let stale = life.registerResources(id: "bt17.feeds",
                                       leave: { [oldLeft] in oldLeft.value += 1 },
                                       enter: {})
    let live = life.registerResources(id: "bt17.feeds",
                                      leave: { [newLeft] in newLeft.value += 1 },
                                      enter: {})
    // 覆盖不等于停机：被顶掉的那份要有最后一次「离开前台」的机会。
    #expect(oldLeft.value == 1)

    life.unregisterResources(token: stale)      // 旧宿主这才死透，带着老 token 来注销
    #expect(life.resourceCount == before + 1)   // 新的那份必须还在

    life.phaseChanged(to: .background)
    #expect(newLeft.value == 1)
    #expect(oldLeft.value == 1)                 // 旧的不会再被叫到

    life.unregisterResources(token: live)
    #expect(life.resourceCount == before)
    life.phaseChanged(to: .active)
  }

  @Test("迟到的旧宿主注销不掉新宿主那条落盘钩子")
  func staleHookTokenCannotUnregisterTheLiveOne() {
    let life = AppLifecycle.shared
    let oldRan = Box(0), newRan = Box(0)
    let before = life.hookCount

    let stale = life.register(id: "bt17.flush", priority: .data) { [oldRan] in oldRan.value += 1 }
    let live = life.register(id: "bt17.flush", priority: .data) { [newRan] in newRan.value += 1 }
    life.unregister(hook: stale)
    #expect(life.hookCount == before + 1)

    life.leaveForeground(final: true)
    #expect(newRan.value == 1)
    #expect(oldRan.value == 0)

    life.unregister(hook: live)
    #expect(life.hookCount == before)
  }

  @Test("没人要这份行情了，模型就该被放掉")
  func marketModelIsReleasedWhenItsHostGoesAway() async {
    weak var probe: MarketModel?
    do {
      let model = MarketModel(symbol: "BTCUSDT", interval: .h1, endpoints: .default)
      model.start(snapshot: false)
      probe = model
      #expect(probe != nil)
    }
    // 事件流那条 Task 还挂在 `for await` 上。它要是强持有模型，这里就永远非 nil。
    await spin(0.3)
    #expect(probe == nil, "pump 还攥着模型：socket、重连、45 秒一轮的持仓量轮询都在没界面的情况下继续跑")
  }
}

// ---------------------------------------------------------------- BT-18

@MainActor
// `.serialized`：`AccountFiles.currentProfile` 也是全局的一份，并行跑会互相换档案。
@Suite("BT-18 换人之后不许再发上一个人的行", .serialized)
struct QuoteBatchTests {

  @Test("换档案时攒在合批缓冲里的行跟着丢")
  func switchingProfileDiscardsBatchedRows() async throws {
    let root = URL(fileURLWithPath: NSTemporaryDirectory())
      .appendingPathComponent("bt18-\(UUID().uuidString)", isDirectory: true)
    defer { try? FileManager.default.removeItem(at: root) }
    let files = try AccountFiles(root: root)
    files.activate(user: UUID())          // 甲登录

    let book = QuoteBook()
    let sent = Box<[[Ticker]]>([])
    book.onUpdate = { [sent] rows in sent.value.append(rows) }
    book.restoreQuotes()                  // 认主：这份缓存现在归甲
    book.watch("AAAUSDT"); book.watch("BBBUSDT")

    book.ingest([ticker("AAAUSDT", last: 100, id: 1)])
    #expect(sent.value.count == 1)        // 前沿先发，第一笔立刻出去
    book.ingest([ticker("BBBUSDT", last: 200, id: 2)])
    #expect(book.pendingBatchRows == 1)   // 第二笔落在合批窗口里，攒着

    files.activate(user: UUID())          // 乙登录
    book.restoreQuotes()                  // 宿主认主的那一下
    #expect(book.pendingBatchRows == 0, "甲那批行还攒着，窗口一到就会发到乙的表上")

    // 窗口（隐藏时 2 秒）走完，确认一行都没漏出去。
    await spin(2.4)
    #expect(sent.value.count == 1, "换人之后又发了一批：\(sent.value)")

    book.shutdown()
  }

  @Test("宿主销毁就放连接，回调也一并摘掉")
  func shutdownReleasesEverything() throws {
    let root = URL(fileURLWithPath: NSTemporaryDirectory())
      .appendingPathComponent("bt18b-\(UUID().uuidString)", isDirectory: true)
    defer { try? FileManager.default.removeItem(at: root) }
    let files = try AccountFiles(root: root)
    files.activate(user: UUID())

    let book = QuoteBook()
    let sent = Box<[[Ticker]]>([])
    book.onUpdate = { [sent] rows in sent.value.append(rows) }
    book.restoreQuotes()
    book.watch("AAAUSDT")
    book.ingest([ticker("AAAUSDT", last: 100, id: 1)])
    sent.value.removeAll()

    book.ingest([ticker("AAAUSDT", last: 101, id: 2)])
    #expect(book.pendingBatchRows == 1)
    book.shutdown()
    #expect(book.pendingBatchRows == 0)
    // 收摊时那一次 flush 是应该的（同一个人、还在盘上），但之后回调就该是哑的。
    book.ingest([ticker("AAAUSDT", last: 102, id: 3)])
    let after = sent.value.count
    book.ingest([ticker("AAAUSDT", last: 103, id: 4)])
    #expect(sent.value.count == after)
  }
}

// ---------------------------------------------------------------- BT-23

@MainActor
@Suite("BT-23 连着转两次屏，只有最后一次说了算")
struct OrientationReleaseTests {

  @Test("后一次复位把前一次顶掉")
  func onlyTheLastReleaseTakesEffect() async {
    Orientation.cancelPendingRelease()
    defer { Orientation.cancelPendingRelease(); OrientationBridge.mask = .allButUpsideDown }

    OrientationBridge.mask = .landscape
    Orientation.scheduleRelease(after: 60)     // 「点画线」那一次
    OrientationBridge.mask = .portrait
    Orientation.scheduleRelease(after: 400)    // 紧接着「画完转回去」那一次

    await spin(0.2)
    // 第一次的 60ms 早就到点了。它要是还活着，这儿的 mask 已经被抹成 allButUpsideDown，
    // 手一斜系统就按自动方向把人又转回横屏。
    #expect(OrientationBridge.mask == .portrait,
            "上一次转屏的复位任务没被取消，把这一次刚设的方向抹掉了")
    #expect(Orientation.hasPendingRelease)

    await spin(0.4)
    #expect(OrientationBridge.mask == .allButUpsideDown)   // 最后一次到点，正常放开
    #expect(!Orientation.hasPendingRelease)
  }
}

// ---------------------------------------------------------------- B.7 附加

@MainActor
@Suite("后台运行额度：欠的必须还")
struct BackgroundGraceTests {

  @Test("宿主先没了，额度也得还回去")
  func deinitEndsTheBackgroundTask() {
    let ended = Box<[Int]>([])
    let handle = UIBackgroundTaskIdentifier(rawValue: 4242)
    do {
      let grace = BackgroundGrace(seconds: 9_999,
                                  begin: { _ in handle },
                                  end: { [ended] id in
                                    MainActor.assumeIsolated { ended.value.append(id.rawValue) }
                                  })
      grace.begin()
      #expect(ended.value.isEmpty)
    }
    #expect(ended.value == [4242], "只 cancel 了自己的定时器，系统那边的后台任务还开着")
  }

  @Test("正常收尾只还一次")
  func endIsIdempotent() {
    let ended = Box<[Int]>([])
    do {
      let grace = BackgroundGrace(seconds: 9_999,
                                  begin: { _ in UIBackgroundTaskIdentifier(rawValue: 7) },
                                  end: { [ended] id in
                                    MainActor.assumeIsolated { ended.value.append(id.rawValue) }
                                  })
      grace.begin()
      grace.end()
      grace.end()
    }
    #expect(ended.value == [7])
  }
}
