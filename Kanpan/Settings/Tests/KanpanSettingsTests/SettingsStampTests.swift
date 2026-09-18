import Testing
import Foundation
import KanpanCore
import KanpanData
@testable import KanpanSettings

/// 「体验类状态标识」这一套。用户 2026-09-19 定的机制级要求：
///
/// > 用户缩小 K 线，改变副图区域大小，指标颜色等等其它体验类操作，那么这是修改，
/// > **需要记录一个标识**，避免**云端没同步，下次进来对不上又覆盖回去，相当于没改**。
///
/// 这一套东西的形状是「值 + 属主 + 脏字段集 + 修改时间」，**粒度按字段，不按整份档案**。
@Suite("体验类状态标识")
@MainActor
struct SettingsStampTests {

  /// 把墙上钟换成手摇的，免得靠 sleep 制造时间差。
  private func withClock(_ body: (@escaping (Double) -> Void) -> Void) {
    let old = SettingsClock.now
    final class Box: @unchecked Sendable { var value: Double = 1_000 }
    let box = Box()
    SettingsClock.now = { box.value }
    body { box.value = $0 }
    SettingsClock.now = old
  }

  private func makeStore() -> (PrefsStore, InMemoryPrefsStorage, InMemoryPrefsStorage) {
    let archive = InMemoryPrefsStorage(), sentinel = InMemoryPrefsStorage()
    let store = PrefsStore(storage: archive, cache: UnavailableMarketCache(), sentinel: sentinel)
    return (store, archive, sentinel)
  }

  // ---------------------------------------------------------------- 记

  @Test("改一项就记一个脏字段，落盘和记脏是同一步")
  func marksOnWrite() {
    let (store, archive, sentinel) = makeStore()
    #expect(store.dirtyFields.isEmpty)

    store.update { $0.barSpacing = 2 }

    // 值、脏标识、哨兵，三样在同一次调用里就已经在盘上了——不是等定时器。
    #expect(store.dirtyFields == ["barSpacing"])
    #expect(archive.keys.contains(SettingsStamp.storageKey))
    #expect(sentinel.keys.contains(SettingsSentinel.storageKey))
    #expect(store.sentinel.wroteAt > store.sentinel.pushedAt)
  }

  @Test("按字段记，不按整份档案：改皮肤不会把根宽也标成脏的")
  func marksPerField() {
    let (store, _, _) = makeStore()
    store.update { $0.skin = .terra }
    #expect(store.dirtyFields == ["skin"])
    store.update { $0.barSpacing = 2 }
    #expect(store.dirtyFields == ["skin", "barSpacing"])
  }

  @Test("副图高度、副图顺序、指标颜色，一样都算一次改动")
  func marksEveryExperienceField() {
    let (store, _, _) = makeStore()
    store.update { $0.subHeightOverrides[.vol] = 120 }
    store.update { $0.subs = [.vol, .macd] }
    store.update { $0.indicatorColors[.macd] = [0: "#FF0000"] }
    #expect(store.dirtyFields == ["subHeightOverrides", "subs", "indicatorColors"])
  }

  // ---------------------------------------------------------------- 清

  @Test("推成功才清脏字段")
  func clearsOnlyAfterPush() {
    let (store, _, _) = makeStore()
    store.update { $0.barSpacing = 2 }
    let marks = store.dirtyMarks
    #expect(!marks.isEmpty)
    store.syncPushed(marks, acked: store.stamp.dirtyWireKeys)
    #expect(store.dirtyFields.isEmpty)
    #expect(store.sentinel.pushedAt >= store.sentinel.wroteAt)
  }

  @Test("推的中途用户又改了同一项：那一改不许跟着被清掉")
  func keepsMarksChangedWhilePushing() {
    withClock { setNow in
      let (store, _, _) = makeStore()
      setNow(1_000)
      store.update { $0.barSpacing = 2 }
      let inFlight = store.dirtyMarks          // 推上去的是这一份
      setNow(2_000)
      store.update { $0.barSpacing = 3 }       // 推的过程中又捏了一下
      store.syncPushed(inFlight, acked: ["barSpacing"])
      #expect(store.dirtyFields == ["barSpacing"], "晚到的这一改还没推上去，标识必须留着")
    }
  }

  @Test("发出去了不算数，服务端认了才算：没回执的那几项脏标识留着")
  func onlyAnAckClears() {
    let (store, _, _) = makeStore()
    store.update { $0.barSpacing = 2; $0.skin = .terra }
    let marks = store.dirtyMarks
    // 服务端只认下了皮肤那一项（另一项被它的字段白名单顶了回来）。
    store.syncPushed(marks, acked: ["skin"])
    #expect(store.dirtyFields == ["barSpacing"], "没推上去的那一项必须还是脏的，否则下次回拉就把它盖回去了")

    // 一条都没认（断网 / 400）：一个标识都不许清。
    store.syncPushed(store.dirtyMarks, acked: [])
    #expect(store.dirtyFields == ["barSpacing"])
  }

  // ------------------------------------------------ 清：拍平之后的那些线上路径

  @Test("嵌套字段发上去的是拍平后的路径：params/MA 和 params/EMA 都认下了就清 params")
  func clearsNestedWirePaths() {
    let (store, _, _) = makeStore()
    store.update { $0.params[.ma] = [7, 30, 60]; $0.params[.ema] = [9, 21] }
    #expect(store.dirtyFields == ["params"], "脏标识记的是顶层字段名，不是拍平后的路径")

    // 线上收到的是 `PersonalSyncCodec.flatten` 拍出来的路径，不是 `params` 本身。
    store.syncPushed(store.dirtyMarks, acked: ["params/MA", "params/EMA"])
    #expect(store.dirtyFields.isEmpty,
            "服务端都认下了还留着脏标识的话，云端那份 params 永远打不赢本地——另一台设备改的指标参数再也收不到")
  }

  @Test("subHeightOverrides/MACD 被认下就清 subHeightOverrides")
  func clearsNestedSubHeightOverride() {
    let (store, _, _) = makeStore()
    store.update { $0.subHeightOverrides[.macd] = 140 }
    store.syncPushed(store.dirtyMarks, acked: ["subHeightOverrides/MACD"])
    #expect(store.dirtyFields.isEmpty, "拖一次副图分隔线就让这个字段从此永远脏着，每轮同步都白推一份 settings")
  }

  @Test("三段的那条也一样：indicatorColors/MACD/0 映得回 indicatorColors")
  func clearsThreeSegmentWirePath() {
    let (store, _, _) = makeStore()
    store.update { $0.indicatorColors[.macd] = [0: "#FF0000"] }
    store.syncPushed(store.dirtyMarks, acked: ["indicatorColors/MACD/0"])
    #expect(store.dirtyFields.isEmpty)
  }

  @Test("一个字段拍成好几条路径：只要有一条被 droppedFields 丢了，这个字段就还得脏着")
  func keepsFieldWhenOneWirePathIsDropped() {
    let (store, _, _) = makeStore()
    store.update { $0.params[.ma] = [7, 30, 60]; $0.params[.ema] = [9, 21] }
    // 服务端认下了这条操作，但 `params/EMA` 那一项没收下。
    store.syncPushed(store.dirtyMarks, acked: ["params/MA"], dropped: ["params/EMA"])
    #expect(store.dirtyFields == ["params"],
            "兄弟路径被丢掉时还把整个字段清掉，等于把没推上去的那一改当成推过了，下次回拉照样盖回去")

    // 补推一次、这回一条都没丢：到这儿才能清。
    store.syncPushed(store.dirtyMarks, acked: ["params/MA", "params/EMA"])
    #expect(store.dirtyFields.isEmpty)
  }

  @Test("rsiRange 被认下，仍然清掉 rsiLower 和 rsiUpper 两个本地字段")
  func clearsBothRSIBoundsOnRangeAck() {
    let (store, _, _) = makeStore()
    store.update { $0.rsiLower = 25; $0.rsiUpper = 75 }
    #expect(store.dirtyFields == ["rsiLower", "rsiUpper"])
    store.syncPushed(store.dirtyMarks, acked: [SettingsWire.rsiRange])
    #expect(store.dirtyFields.isEmpty)

    // 反过来：rsiRange 被丢掉，上下轨两个都得留着。
    store.update { $0.rsiLower = 30 }
    store.syncPushed(store.dirtyMarks, acked: [], dropped: [SettingsWire.rsiRange])
    #expect(store.dirtyFields == ["rsiLower"])
  }

  @Test("线上键名对得上，RSI 那一对来回都不丢")
  func wireKeysLineUp() {
    // 脏标识认的字段名，映到线上之后必须全都是服务端那张表上的键。
    for field in Prefs.stampedFieldNames {
      let key = SettingsWire.key(for: field)
      #expect(Prefs.syncedFieldNames.contains(key) || key == SettingsWire.rsiRange,
              "\(field) 映出来的 \(key) 不在同步清单上，脏标识和要发上去的字段对不上")
      #expect(SettingsWire.fields(for: key).contains(field), "\(key) 映不回 \(field)")
    }
    // 唯一那处对不齐：上下轨两个本地字段 ↔ 线上一个 rsiRange。
    #expect(SettingsWire.key(for: "rsiLower") == "rsiRange")
    #expect(SettingsWire.key(for: "rsiUpper") == "rsiRange")
    #expect(SettingsWire.fields(for: "rsiRange") == ["rsiLower", "rsiUpper"])

    let (store, _, _) = makeStore()
    store.update { $0.rsiLower = 25 }
    #expect(store.dirtyFields == ["rsiLower"])
    #expect(store.stamp.dirtyWireKeys == ["rsiRange"], "发上去的是 rsiRange，对账就得按这个键")
    // 服务端认下 rsiRange，要清的是**两个**本地字段里那个脏的。
    store.syncPushed(store.dirtyMarks, acked: ["rsiRange"])
    #expect(store.dirtyFields.isEmpty, "rsiRange 的回执映不回上下轨的话，这一项的脏标识永远清不掉")
  }

  // ---------------------------------------------------------------- 合

  @Test("云端回拉：本地脏的字段一律跳过，干净的跟着云端走")
  func cloudNeverClobbersDirtyFields() {
    let (store, _, _) = makeStore()
    store.update { $0.barSpacing = 2 }         // 用户刚捏的，还没推上去

    var cloud = Prefs.defaults
    cloud.barSpacing = 4                       // 服务端那份还是捏之前的
    cloud.skin = .terra                         // 另一台设备改的皮肤，本地没动过
    store.applySynced(cloud)

    #expect(store.prefs.barSpacing == 2, "「相当于没改」就是这一下：脏字段不许被云端盖回去")
    #expect(store.prefs.skin == .terra, "干净字段照常跟着云端走，两台设备各改各的都要合进来")
  }

  @Test("推成功之后，云端那份就说了算了")
  func cloudWinsOnceClean() {
    let (store, _, _) = makeStore()
    store.update { $0.barSpacing = 2 }
    store.syncPushed(store.dirtyMarks, acked: ["barSpacing"])

    var cloud = Prefs.defaults
    cloud.barSpacing = 6                       // 另一台设备后来改的
    store.applySynced(cloud)
    #expect(store.prefs.barSpacing == 6)
  }

  // ---------------------------------------------------------------- 属主

  @Test("换了个人：上一个人的脏标识算不到我头上")
  func stampFollowsTheOwner() {
    let mine = InMemoryPrefsStorage(), sentinel = InMemoryPrefsStorage()
    let store = PrefsStore(storage: mine, cache: UnavailableMarketCache(), sentinel: sentinel)
    store.useStorage(mine, prefs: .defaults, arrival: .ownerSwitched, owner: "A")
    store.update { $0.barSpacing = 2 }
    #expect(store.dirtyFields == ["barSpacing"])

    let other = InMemoryPrefsStorage()
    store.useStorage(other, prefs: .defaults, arrival: .ownerSwitched, owner: "B")
    #expect(store.dirtyFields.isEmpty, "B 的档案里没有 A 的脏标识")

    // A 回来了：他那份脏标识还在自己的档案旁边躺着，一个字没丢。
    store.useStorage(mine, prefs: .defaults, arrival: .ownerSwitched, owner: "A")
    #expect(store.dirtyFields == ["barSpacing"])
  }

  @Test("档案里记的属主不是现在这个人：当它不存在，绝不能用")
  func refusesAnotherPersonsArchive() {
    let (store, archive, _) = makeStore()
    store.useStorage(archive, prefs: .defaults, arrival: .ownerSwitched, owner: "A")
    store.update { $0.barSpacing = 2 }
    // 同一个柜子，换个人来开。
    store.useStorage(archive, prefs: .defaults, arrival: .ownerSwitched, owner: "B")
    #expect(store.verdict == .ownerMismatch(expected: "B", found: "A"))
    #expect(store.dirtyFields.isEmpty)
  }

  // ---------------------------------------------------------------- 哨兵四诊

  @Test("第一次装：哨兵也没有，正常从云端拉")
  func firstRun() {
    #expect(SettingsCacheDoctor.diagnose(archive: nil, readable: false, stamp: nil,
                                         sentinel: nil, owner: "A") == .firstRun)
  }

  @Test("档案没了、哨兵还在：这是「被清空」，而且看得出本地有没有没推上去的改动")
  func wipedIsNotFirstRun() {
    var sentinel = SettingsSentinel(install: "i1", owner: "A", wroteAt: 2_000, pushedAt: 1_000)
    #expect(SettingsCacheDoctor.diagnose(archive: nil, readable: false, stamp: nil,
                                         sentinel: sentinel, owner: "A") == .wiped(unpushed: true))
    sentinel.pushedAt = 3_000
    #expect(SettingsCacheDoctor.diagnose(archive: nil, readable: false, stamp: nil,
                                         sentinel: sentinel, owner: "A") == .wiped(unpushed: false))
  }

  @Test("档案解不开：算「损坏」，回落云端，但脏标识不许顺手抹掉")
  func damagedKeepsTheMarks() {
    let (store, archive, _) = makeStore()
    store.update { $0.barSpacing = 2 }
    let marks = store.dirtyMarks
    // 档案被写坏了（半截 JSON），脏标识那一份还在。
    archive.setPrefsData(Data("{".utf8), forKey: PrefsCodec.key)
    store.useStorage(archive, prefs: .defaults, arrival: .sameProfile, owner: "")
    #expect(store.verdict == .damaged)
    #expect(store.dirtyMarks == marks, "回落云端不等于把没推上去的改动一起抹掉")
  }

  @Test("哨兵和真身不在同一层：真身那层整个没了，哨兵照样认得出这是「被清空」")
  func sentinelOutlivesTheArchive() {
    let archive = InMemoryPrefsStorage(), sentinel = InMemoryPrefsStorage()
    let store = PrefsStore(storage: archive, cache: UnavailableMarketCache(), sentinel: sentinel)
    store.update { $0.barSpacing = 2 }

    // 换一只全新的空柜子当真身（= 那一层被清了），哨兵那一层原样保留。
    let wiped = InMemoryPrefsStorage()
    let next = PrefsStore(storage: wiped, cache: UnavailableMarketCache(), sentinel: sentinel)
    next.useStorage(wiped, prefs: .defaults, arrival: .sameProfile, owner: "")
    #expect(next.verdict == .wiped(unpushed: true))
  }

  // ---------------------------------------------------------------- 字段比对

  @Test("字段比对认的是编码键名，和同步清单是同一张表")
  func fieldNamesMatchTheWire() {
    var next = Prefs.defaults
    next.barSpacing = 7
    #expect(Prefs.changedStampedFields(from: .defaults, to: next) == ["barSpacing"])
    #expect(Prefs.stampedFieldNames.isSuperset(of: Prefs.syncedFieldNames))
    #expect(Prefs.syncedFieldNames.contains("subHeights"))
  }

  @Test("按字段挑回来：只有点名的那几项用本地的，别的原样用对方那份")
  func keepingPicksFields() {
    var local = Prefs.defaults; local.barSpacing = 2; local.skin = .classic
    var cloud = Prefs.defaults; cloud.barSpacing = 9; cloud.skin = .terra
    let merged = Prefs.keeping(["barSpacing"], of: local, over: cloud)
    #expect(merged.barSpacing == 2)
    #expect(merged.skin == .terra)
  }
}
