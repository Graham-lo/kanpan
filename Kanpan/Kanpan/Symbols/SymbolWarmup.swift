import SwiftUI
import UIKit

/// 列表行上的「先去拉」：手指一按到行上（还没抬手）、搜索结果一稳定下来，就替那几只
/// 把当前周期的 K 线快照先拉回来，点进图时 `MarketModel.switchTo` 同步读到的就是真图。
///
/// 行视图（`LiuliSymbolRow` / `SymbolRowView`）和搜索页只认这个环境值，不认行情模型；
/// 宿主（`MainScreen` 的几个预取口子）把它接到 `MarketModel.prewarmPress` / `prewarmHits` 上。
/// 默认是空操作：预览、单测、没接线的地方什么都不发。
struct SymbolWarmup {
  var press: @MainActor (String) -> Void = { _ in }
  var hits: @MainActor ([String]) -> Void = { _ in }

  /// 搜索结果停多久算「稳定」：打字中途的结果不拉。
  static let settle: Duration = .milliseconds(350)
  /// 结果里拉前几只。
  static let topHits = 3

  /// 搜索页这一轮该拉哪几只（纯函数，用例守着）。
  static func hitsToWarm(_ ids: [String]) -> [String] {
    var seen = Set<String>()
    return Array(ids.filter { seen.insert($0).inserted }.prefix(topHits))
  }
}

extension EnvironmentValues {
  @Entry var symbolWarmup = SymbolWarmup()
}

extension View {
  /// 手指按下就叫 `action`。不占用这一趟触摸：点、横滑删除、滚动照旧归原来的手势。
  func onTouchDown(_ action: @escaping @MainActor () -> Void) -> some View {
    gesture(TouchDownGesture(action: action))
  }
}

/// 只看「按下」那一下的识别器：`touchesBegan` 里报一声，随即自己作废（`.failed`），
/// 不延迟、不取消视图上的触摸，也不挡别的识别器——所以点按、左划、列表滚动一概不受影响。
private struct TouchDownGesture: UIGestureRecognizerRepresentable {
  let action: @MainActor () -> Void

  func makeUIGestureRecognizer(context: Context) -> TouchDownRecognizer {
    let recognizer = TouchDownRecognizer()
    recognizer.cancelsTouchesInView = false
    recognizer.delaysTouchesBegan = false
    recognizer.delaysTouchesEnded = false
    return recognizer
  }

  func updateUIGestureRecognizer(_ recognizer: TouchDownRecognizer, context: Context) {
    recognizer.onDown = action
  }

  func handleUIGestureRecognizerAction(_ recognizer: TouchDownRecognizer, context: Context) {}
}

final class TouchDownRecognizer: UIGestureRecognizer {
  var onDown: @MainActor () -> Void = {}

  override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent) {
    super.touchesBegan(touches, with: event)
    onDown()
    state = .failed
  }

  override func canPrevent(_ preventedGestureRecognizer: UIGestureRecognizer) -> Bool { false }
  override func canBePrevented(by preventingGestureRecognizer: UIGestureRecognizer) -> Bool { false }
}
