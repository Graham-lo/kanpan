import Foundation

/// 一个有歧义的专业词：界面上只写一两个字的短标签，旁边挂一颗小问号（`TermMark`），
/// 点开是屏幕正中的一张解释卡（`GlossaryCard`）。照 AICoin 的做法（2026-09-28 用户定）。
///
/// **条目怎么加**：按所在的页面分文件，写成 `extension GlossaryTerm { static let … }`，
/// 放进 `GlossaryTerms+<页面>.swift`（顶栏六格在 `GlossaryTerms+Header.swift`）。
/// 然后在标签后面挂 `TermMark(.xxx)`。不用登记到任何清单里。
///
/// 写法：
/// - `id` 是英文小写短词，拿来拼无障碍标识 `term.<id>`，UI 用例靠它点。
/// - `title` 是「短标签 · 全称」，如「仓 · 持仓量」；短标签就是界面上那一两个字。
/// - `body` 两三行，说人话，写给不玩合约的人看：它是什么、数大数小意味着什么。
///   不写公式推导、不写英文（英文缩写本身除外）。
struct GlossaryTerm: Identifiable, Hashable, Sendable {
  let id: String
  let title: String
  let body: String
}
