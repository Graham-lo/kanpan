import Foundation
import KanpanCore

// 板块页顶上那一行药丸「到底显示哪一档、写哪个名字」。
//
// 这一段本来写在 `SectorPage.swift` 里（`snapshot()` 中的一行三元式 + `windowBar`
// 里两个字面量）。那个文件 import SwiftUI，进不了 `Kanpan/Sector` 那个测试壳包，
// 于是审查 B-T21 的后半——「历史不够时窗口和它的名字要一致」——只能靠肉眼在真机上看
// （复核项 7）。现在决定本身是纯函数，页面只负责摆。

/// 当前窗口这一档的决定。
enum SectorWindowChoice {
  /// 药丸上的两个名字。讲的是这一屏在挑什么样的板块，不是口径名
  /// （底下还是 `SectorWindow.today` / `.d5`，换名字不是换口径）。
  static let todayTitle = "板块明星"
  static let d5Title = "潜力明星"

  /// 某一档窗口在屏上叫什么。`d20` 不是一个模式（它只是 5 日那档头部补的一句），
  /// 所以除了 `d5` 都按今日那个名字写。
  static func title(_ window: SectorWindow) -> String {
    window == .d5 ? d5Title : todayTitle
  }

  /// 决定的结果。三样东西必须一起给出来，不然就会出现「名字写着潜力明星、
  /// 底下的数却是今日」这种屏（那正是原来那行三元式和 `windowBar` 分开算的后果）。
  struct Resolved: Sendable, Equatable {
    /// 这一屏真正在用的窗口。
    let window: SectorWindow
    /// 药丸那一行在不在。5 日那档没东西可看就整行不出现（美股那边服务端还没采日线）。
    let showsBar: Bool
    /// 当前那一档在屏上的名字，和 `window` 永远同源。
    let title: String
  }

  /// - Parameters:
  ///   - preferred: 用户停在哪一档（`Prefs.sectorWindow`，随账号同步）。
  ///   - hasD5: 这个市场的 5 日那档真算得出东西吗（`SectorAggregator.hasEligible`）。
  ///
  /// 停在 5 日的人进了一个没有日线的市场：**就地**退回今日，偏好一个字不动——
  /// 他换个市场回来还是 5 日。回写偏好等于让「数据暂时不够」偷偷改掉用户的选择。
  static func resolve(preferred: SectorWindow, hasD5: Bool) -> Resolved {
    let window: SectorWindow = (preferred == .d5 && hasD5) ? .d5 : .today
    return Resolved(window: window, showsBar: hasD5, title: title(window))
  }
}
