import Testing
import ReviewDomain
@testable import ReviewUI

/// 记录详情退出时「要不要替人存一份草稿」：只认人真的改过，不认记录在页开着时被换了。
@MainActor struct ReviewReflectionEditorTests {
  private func reflection(_ note: String, _ next: String = "") -> ReviewReflection {
    var value = ReviewReflection(); value.note = note; value.nextTime = next; return value
  }

  @Test func remoteReflectionArrivingWhilePageIsOpenIsNotOverwritten() {
    // 打开时本机这条还没复盘；页开着时同步拉回了另一台设备写的那版。
    var editor = ReviewReflectionEditor(reflection(""))
    editor.adopt(reflection("突破回踩没站稳", "等收盘确认"))
    // 框里跟着换成新版，退出时什么都不发——原来会拿打开时的空字当草稿把它盖掉。
    #expect(editor.note == "突破回踩没站稳")
    #expect(editor.nextTime == "等收盘确认")
    #expect(!editor.edited)
  }

  @Test func userEditsSurviveARemoteUpdateAndStillGetSaved() {
    var editor = ReviewReflectionEditor(reflection("旧的"))
    editor.note = "我刚改的"
    #expect(editor.edited)
    editor.adopt(reflection("别的设备写的"))
    #expect(editor.note == "我刚改的")
    #expect(editor.edited)
  }

  @Test func savingMakesTheEditorCleanAgain() {
    var editor = ReviewReflectionEditor(reflection(""))
    editor.note = "写完了"
    // 按下「保存草稿」：记录上的复盘变成框里这份，退出时不必再发一次。
    editor.adopt(reflection("写完了"))
    #expect(!editor.edited)
  }
}
