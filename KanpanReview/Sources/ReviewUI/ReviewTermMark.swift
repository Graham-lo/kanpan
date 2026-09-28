import SwiftUI

/// 术语问号在复盘包里的口子。
///
/// 问号（`TermMark`）、解释卡（`GlossaryCard`）和词条都住在 app 的 `Glossary/` 模块里，
/// 复盘包看不到它们，也不该抄一份。包里只按 id 要一颗：app 顺着配色把画法递进来
/// （`ReviewTheme.termMark`，由 `ReviewThemeBridge` 灌），认得这个 id 就画那颗 12pt 的问号，
/// 不认得或没递（`#Preview`）就什么都不画——标签照常，只是少一颗问号。
///
/// 词条 id 见 app 的 `GlossaryTerms+Review.swift`。
public typealias ReviewTermMarkProvider = @MainActor @Sendable (String) -> AnyView

/// 标签后面那颗问号。放进 `HStack(spacing: 0)` 紧跟短标签（问号自己带 3pt 左距），颜色跟着所在的字。
struct ReviewTermMark: View {
  var id: String
  @Environment(\.reviewTheme) private var t
  init(_ id: String) { self.id = id }
  var body: some View {
    if let make = t.termMark { make(id) }
  }
}

/// 「短标签 + 问号」：`LabeledContent` 的 label、分组标题都用它。`term` 为 nil 时就是一段字。
struct ReviewTermLabel: View {
  var title: String
  var term: String?
  init(_ title: String, term: String? = nil) { self.title = title; self.term = term }
  var body: some View {
    HStack(spacing: 0) {
      Text(title)
      if let term { ReviewTermMark(term) }
    }
  }
}
