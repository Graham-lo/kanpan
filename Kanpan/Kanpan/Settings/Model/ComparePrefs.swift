import Foundation
import KanpanCore

extension Prefs {
  /// 对比 K 线最多几只（界面、同步、服务端都是 3）。
  static let maxCompareSymbols = 3

  /// 同步与本地档案共用完整品种身份；坏值逐个丢弃，不牵连其它设置。
  ///
  /// 每一项必须是完整身份键 `venue/market/SYMBOL`，而且原样就能被服务端收下——
  /// 规则只有 `InstrumentID.isSyncKey` 那一条（对着服务端 `compare_key` → `identity`，
  /// 和自选同一条）。这里原来自己抄了一条只收 `A-Z 0-9 - _` 的代号规则，于是
  /// `币安人生USDT` 这类中文底名合约加进对比之后，下一次从本地档案或云端解码就被
  /// 静默丢掉，客户端再把「删掉它」推回服务端。
  static func cleanCompareSymbols(_ raw: [String]) -> [String] {
    var seen: Set<String> = []
    return Array(raw.filter { key in
      InstrumentID.isSyncKey(key) && seen.insert(key).inserted
    }.prefix(maxCompareSymbols))
  }

  /// 往对比里加一只：和解码走同一条规则（`cleanCompareSymbols`），加不进去（身份不合规、
  /// 已经在里面、满了、就是当前这只）返回 `false`、集合原样不动。
  @discardableResult
  mutating func addCompareSymbol(_ key: String, current: String? = nil) -> Bool {
    guard key != current, !compareSymbols.contains(key), compareSymbols.count < Self.maxCompareSymbols,
      Self.cleanCompareSymbols([key]) == [key]
    else { return false }
    compareSymbols.append(key)
    return true
  }
}
