import Testing
import KanpanCore
@testable import KanpanSector

// B-T21 的后半：历史不够的时候，屏上那一档窗口和它的名字必须是同一件事。
//
// 从前这个决定散在 `SectorPage.swift` 里（`snapshot()` 一行三元式定窗口、`windowBar`
// 里两个字面量定名字），那个文件 import SwiftUI 进不了这个壳包，于是这半条规则一直
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
