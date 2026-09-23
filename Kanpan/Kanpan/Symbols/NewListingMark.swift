import SwiftUI
import KanpanCore

/// 名字后面那枚小「新」（P2.15）：上线不满 30 天的品种才有。
///
/// 皮肤强调色，字号和品种整页上那排分类筛选（市场 / 板块）一样——`.scaled(12, .medium)`，
/// 跟着系统文字大小走（P2.13）。只是一个字，不垫底色、不写上线日期、不给解释。
struct NewListingMark: View {
  let symbol: String
  let accent: Color

  var body: some View {
    Text("新")
      .font(.scaled(12, .medium))
      .foregroundStyle(accent)
      .fixedSize()
      .accessibilityLabel("新上线")
      .accessibilityIdentifier("symbols.new." + symbol)
  }

  /// 这个品种此刻该不该挂记号。时钟取渲染那一刻，够用——跨过 30 天那一秒没人盯着看。
  static func shows(_ info: SymbolInfo?, now: Date = Date()) -> Bool {
    info?.isNewListing(nowMs: Int64(now.timeIntervalSince1970 * 1000)) ?? false
  }
}
