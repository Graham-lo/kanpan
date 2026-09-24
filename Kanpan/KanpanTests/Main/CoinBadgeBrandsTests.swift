import Foundation
import Testing
@testable import Kanpan

/// 临时对账（审查第 18 项）：品牌标从 Swift 静态表搬进资源文件之前，先证明两边逐条一样。
@Suite("品种徽章表 · 搬家对账")
struct CoinBadgeBrandsTests {
  @Test func jsonMatchesSwiftTablesFieldByField() throws {
    let file = CoinSpec.brandFile
    // 按原 `brand(_:)` 的查表顺序合并：同一个键先出现的表说了算。
    var merged: [String: CoinSpec] = [:]
    var total = 0
    for table in CoinSpec.legacyBrandTables {
      total += table.count
      for (key, spec) in table where merged[key] == nil { merged[key] = spec }
    }
    #expect(total == merged.count, "八张表之间有重复的键")
    #expect(file.count == merged.count)
    #expect(Set(file.keys) == Set(merged.keys))
    for (key, expected) in merged {
      let got = try #require(file[key], "JSON 缺 \(key)")
      #expect(got.from == expected.from, "\(key) from")
      #expect(got.to == expected.to, "\(key) to")
      #expect(got.inset == expected.inset, "\(key) inset")
      #expect(got.mark == expected.mark, "\(key) mark")
      #expect(got == expected, "\(key)")
      // 旧入口与新表查出来也得一样。
      #expect(CoinSpec.brand(key) == got, "\(key) brand()")
    }
  }
}
