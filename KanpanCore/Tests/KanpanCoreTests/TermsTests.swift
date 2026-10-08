import Foundation
import Testing
@testable import KanpanCore

/// 「大单与爆仓」用词的唯一一份：`KanpanCore/Sources/KanpanCore/Terms/terms.json`。
/// 手机网页与电脑网页读的是同一个文件，这里守住它和 `BigTradeTerm` 一一对上、不混进口语。
@Suite("用词表 terms.json")
struct TermsTests {
  @Test("每个 BigTradeTerm 都有一项、非空，也没有多出来的键")
  func everyCaseHasAnEntry() throws {
    let table = try #require(Terms.table["bigTrade"])
    for k in BigTradeTerm.allCases {
      let v = try #require(table[k.rawValue], "\(k.rawValue) 在 terms.json 里没有")
      #expect(!v.trimmingCharacters(in: .whitespaces).isEmpty, "\(k.rawValue) 是空的")
    }
    #expect(Set(table.keys) == Set(BigTradeTerm.allCases.map(\.rawValue)))
  }

  @Test("模板填空")
  func fill() {
    #expect(BigTradeTerm.buyCount.fill(["n": "12"]) == "买 12 笔")
    #expect(BigTradeTerm.hours.fill(["h": "2"]) == "2 小时")
    #expect(BigTradeTerm.longLiq.text == "多单爆仓")
  }

  @Test("不出现口语化、含糊的说法")
  func noColloquialWords() throws {
    let table = try #require(Terms.table["bigTrade"])
    let banned = ["空爆", "多爆", "被打", "被平", "还在走", "稳着", "该根", "这根", "这只品种", "第一次打开", "一笔"]
    for (k, v) in table {
      for b in banned { #expect(!v.contains(b), "\(k)「\(v)」含「\(b)」") }
    }
  }
}
