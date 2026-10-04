import Testing
import KanpanCore
@testable import Kanpan

// B-T21 的后半：历史不够的时候，屏上那一档窗口和它的名字必须是同一件事。
//
// 从前这个决定散在 `SectorPage.swift` 里（`snapshot()` 一行三元式定窗口、`windowBar`
// 里两个字面量定名字），那个文件是视图，当年进不了测试壳包，于是这半条规则一直
// 只能靠肉眼看（复核项 7）。现在决定是纯函数，这里钉住它。

@Suite("B-T21 板块窗口这一档")
struct SectorWindowChoiceTests {

  @Test("5 日算不出东西时就地退回今日，名字跟着退")
  func fallsBackToTodayWhenHistoryIsThin() {
    let got = SectorWindowChoice.resolve(preferred: .d5, hasD5: false)
    #expect(got.window == .today)
    #expect(got.title == "今日")
    // 那一行药丸整个不出现——没有可切的第二档就别摆一个切不动的开关。
    #expect(!got.showsBar)
  }

  @Test("5 日算得出就照用户停的那一档")
  func honoursThePreferenceWhenHistoryIsThere() {
    let got = SectorWindowChoice.resolve(preferred: .d5, hasD5: true)
    #expect(got == SectorWindowChoice.Resolved(window: .d5, showsBar: true, title: "5 日"))
  }

  @Test("停在今日的人不会被日线推去 5 日")
  func todayStaysToday() {
    let got = SectorWindowChoice.resolve(preferred: .today, hasD5: true)
    #expect(got.window == .today)
    #expect(got.title == "今日")
    #expect(got.showsBar, "有 5 日可切，药丸那一行要在")
  }

  @Test("四种组合里名字和窗口永远同源")
  func titleNeverDisagreesWithTheWindow() {
    for preferred in [SectorWindow.today, .d5] {
      for hasD5 in [true, false] {
        let got = SectorWindowChoice.resolve(preferred: preferred, hasD5: hasD5)
        #expect(got.title == SectorWindowChoice.title(got.window))
      }
    }
  }

  @Test("d20 不是一个模式，写的还是今日那个名字")
  func d20IsNotAMode() {
    #expect(SectorWindowChoice.title(.d20) == SectorWindowChoice.todayTitle)
  }
}

/// 审查 D-05：药丸上再点一下正显示着的那一档，不记习惯、不写偏好。
@MainActor
@Suite("板块窗口药丸 · 点当前档不算数")
struct SectorWindowPickTests {
  @Test("点正显示的那一档：习惯日志不多一条，偏好不落盘；换一档才记、才写")
  func pickingTheShownWindowIsANoOp() {
    let logBox = InMemoryPrefsStorage()
    let habits = Habits(storage: logBox, now: { 1_790_000_000 }, dwellScale: 1)
    let prefsBox = InMemoryPrefsStorage()
    let store = PrefsStore(storage: prefsBox, cache: UnavailableMarketCache())
    habits.bind(store)
    func windowEvents() -> Int {
      HabitLogStore(storage: logBox).load(owner: store.stamp.owner).events.filter { $0.kind == .sectorWindow }.count
    }

    SectorWindowChoice.pick(.d5, shown: .today, market: .crypto, habits: habits, store: store)
    #expect(store.prefs.sectorWindow == .d5)
    #expect(windowEvents() == 1)

    // 盘上那份先拿掉：再点一下当前档要是又写了一次，它会重新出现。
    prefsBox.setPrefsData(nil, forKey: PrefsCodec.key)
    for _ in 0..<3 {
      SectorWindowChoice.pick(.d5, shown: .d5, market: .crypto, habits: habits, store: store)
    }
    #expect(windowEvents() == 1, "重复点当前档被当成又选了一次")
    #expect(prefsBox.prefsData(forKey: PrefsCodec.key) == nil, "重复点当前档又落了一次盘")

    SectorWindowChoice.pick(.today, shown: .d5, market: .crypto, habits: habits, store: store)
    #expect(store.prefs.sectorWindow == .today)
    #expect(windowEvents() == 2)
  }
}
