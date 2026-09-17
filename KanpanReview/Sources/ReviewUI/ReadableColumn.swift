import SwiftUI

/// 内容列封顶——和 app 里那份 `readableColumn` 同一件事，只是 `ReviewUI` 是独立的包，
/// 看不到那边的扩展，所以在这儿再留一份。
///
/// 复盘本和记录详情都是「左边一个名目、右边一个数」的行（`LabeledContent`、战绩里的
/// 胜率）。iPhone 上两端相距 350pt 左右扫得过来；13" iPad 横屏铺满就是 1300pt，
/// 名目在最左、数在最右，中间一片空白，对不上号。看盘对 iPad 的口径是「不破」
/// （2026-09-18 用户定的）：不做宽屏分栏，但也不许这么拉。
///
/// 上限取 560pt——比最宽的 iPhone 再富余一点，所以 iPhone 上这一层等于不存在；
/// 页面底色仍由调用方铺在封顶外面，两侧不露白边。
extension View {
  func readableColumn(_ max: CGFloat = 560) -> some View {
    frame(maxWidth: max).frame(maxWidth: .infinity)
  }
}
