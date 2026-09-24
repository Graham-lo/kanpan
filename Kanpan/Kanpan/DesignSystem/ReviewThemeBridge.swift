import SwiftUI
import ReviewUI

extension PanelTheme {
  /// 把当前配色递给复盘那几页。
  ///
  /// `ReviewUI` 是独立的包，看不到 `PanelTheme`，所以复盘原来把橙色钉死在自己那边：
  /// 换成青苔配色之后，全 app 只有「记一笔」「找相似」「战绩」还是橙的，像是另一个 app
  /// 挂在这儿。这儿只做一次翻译，复盘那边一个颜色都不自己定。
  var review: ReviewTheme {
    ReviewTheme(app: app, raised: raised, raised2: raised2, line: line,
                ink: ink, ink2: ink2, ink3: ink3,
                accent: amber, accentSoft: amberSoft, onAccent: badgeInk,
                up: up, down: down, danger: danger)
  }
}
