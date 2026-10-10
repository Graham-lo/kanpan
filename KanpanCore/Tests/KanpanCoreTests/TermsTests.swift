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

  @Test("「分析」组：每个 AnalysisTerm 都有一项，没有多出来的键，也没有多出来的组")
  func analysisGroup() throws {
    let table = try #require(Terms.table["analysis"])
    #expect(Set(table.keys) == Set(AnalysisTerm.allCases.map(\.rawValue)))
    #expect(AnalysisTerm.fvg.text == "公允价值缺口")
    #expect(Set(Terms.table.keys) == ["bigTrade", "analysis", "highlights"])
  }

  @Test("「要点」组：每个 HighlightTerm 都有一项、非空，也不混口语")
  func highlightsGroup() throws {
    let table = try #require(Terms.table["highlights"])
    for k in HighlightTerm.allCases {
      let v = try #require(table[k.rawValue], "\(k.rawValue) 在 terms.json 里没有")
      #expect(!v.trimmingCharacters(in: .whitespaces).isEmpty, "\(k.rawValue) 是空的")
    }
    // 这一组手机网页也读，网页独有的键（重试、搜索这类）可以只在 JSON 里有；反过来 iOS 用到的每个键必须在。
    #expect(Set(HighlightTerm.allCases.map(\.rawValue)).isSubset(of: Set(table.keys)))
    #expect(HighlightTerm.title.text == "盘口要点")
    #expect(HighlightTerm.minutes.fill(["n": "2"]) == "2 分")
    #expect(HighlightTerm.wRange.fill(["h": "31"]) == "区间 31 时")
    let banned = ["挂着", "在场", "在减", "这只品种", "偏多", "偏空", "看涨", "看跌"]
    for (k, v) in table {
      for b in banned { #expect(!v.contains(b), "\(k)「\(v)」含「\(b)」") }
    }
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
    let banned = ["空爆", "多爆", "被打", "被平", "还在走", "稳着", "该根", "这根", "这只品种", "第一次打开", "一笔", "挂着", "在场", "已挂", "已撤销", "后撤"]
    for (k, v) in table {
      for b in banned { #expect(!v.contains(b), "\(k)「\(v)」含「\(b)」") }
    }
  }
}
