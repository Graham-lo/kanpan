import SwiftUI
import ReviewUI

extension PanelTheme {
  /// 把当前配色递给复盘那几页。
  ///
  /// `ReviewUI` 是独立的包，看不到 `PanelTheme`，所以复盘原来把橙色钉死在自己那边：
  /// 换成青苔配色之后，全 app 只有「记一笔」「找相似」「战绩」还是橙的，像是另一个 app
  /// 挂在这儿。这儿只做一次翻译，复盘那边一个颜色都不自己定。
  ///
  /// 左划也从这儿递过去（UI 整改 P3）：全 app 的划出动作只有 `SwipeToDelete` 一份实现，
  /// 复盘的「找相似 → 保存」「已存案例 → 删除」也走它，砖底和字色跟着皮肤走，
  /// 不再是系统 `.swipeActions` 那颗白字红底。
  var review: ReviewTheme {
    let theme = self
    return ReviewTheme(app: app, raised: raised, raised2: raised2, line: line,
                       ink: ink, ink2: ink2, ink3: ink3,
                       accent: amber, accentSoft: amberSoft, onAccent: badgeInk,
                       up: up, down: down, danger: danger,
                       segOn: segOn,
                       swipe: { row in
                         AnyView(
                           SwipeToDelete(
                             id: row.id, open: row.open, brick: .flush,
                             trailing: row.trailing.map { action in
                               action.destructive
                                 ? SwipeAction.delete(theme, title: action.title, id: action.id, run: action.run)
                                 : SwipeAction(id: action.id, title: action.title, fill: theme.amber, run: action.run)
                             },
                             fullSwipe: row.fullSwipe
                           ) { proxy in
                             row.content(ReviewSwipeState(isOpen: proxy.isOpen, close: proxy.close))
                           }
                           .environment(\.panelTheme, theme))
                       })
  }
}
