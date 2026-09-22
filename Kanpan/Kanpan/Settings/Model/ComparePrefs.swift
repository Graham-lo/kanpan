import Foundation

extension Prefs {
  /// 同步与本地档案共用完整品种身份；坏值逐个丢弃，不牵连其它设置。
  static func cleanCompareSymbols(_ raw: [String]) -> [String] {
    var seen: Set<String> = []
    return Array(raw.filter { key in
      let parts = key.split(separator: "/", omittingEmptySubsequences: false)
      guard key.utf8.count <= 128, parts.count == 3, parts.allSatisfy({ !$0.isEmpty }) else { return false }
      let prefixOK = parts.prefix(2).allSatisfy { part in
        part.utf8.allSatisfy { (97...122).contains($0) || (48...57).contains($0) || $0 == 95 }
      }
      let symbolOK = parts[2].utf8.allSatisfy { (65...90).contains($0) || (48...57).contains($0) || $0 == 45 || $0 == 95 }
      return prefixOK && symbolOK && seen.insert(key).inserted
    }.prefix(3))
  }
}
