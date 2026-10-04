import Foundation
import Testing
@testable import Kanpan

/// 提示条右边那颗按钮：点了先做动作，再只收「被点的那一句」。
@MainActor
@Suite("点提示按钮不抹掉动作里新说的那一句")
struct ToastActionTests {
  @Test("动作里又说了一句：新的一句留着，按钮也还在")
  func actionThatSpeaksKeepsTheNewLine() {
    let center = ToastCenter()
    var restored = false
    center.say("已移除", undo: {
      restored = true
      center.say("已恢复", undo: {})
    })
    center.runAction()
    #expect(restored)
    #expect(center.line?.text == "已恢复")
    #expect(center.line?.hasAction == true)
    center.dismiss()
  }

  @Test("动作不说话：照旧收起")
  func silentActionDismisses() {
    let center = ToastCenter()
    var ran = false
    center.say("已移除", undo: { ran = true })
    center.runAction()
    #expect(ran)
    #expect(center.line == nil)
  }
}
