import Foundation
import KanpanCore

// ============================================================ 搜索匹配
//
// 原型 `app.js/renderSymbols()` 的过滤只有一行：
//
//   rows = D.catalog.filter(r => !query || r[0].includes(query) || r[1].includes(query))
//
// 即「symbol 或 base 含子串」，大写后比。**命中集合照抄这条**。
// 原型没有做排序（按 catalog 原序出），任务书 §10.5 / A5.7 明确要求
// 「base 前缀匹配排最前（搜 eth 先出 ETHUSDT 再出 ETHFIUSDT）」＋「匹配片段高亮」，
// 所以名次和高亮按任务书补上——这是原型少做的一件事，不是和原型打架。
// 差异已记在 docs/acceptance/M5/品种页.md。
//
// 排序分两层，用户 2026-09-18 定的：**先最匹配、再按 24h 成交额降序**。
// 这里只管第一层（`Tier`，纯字面比较，不需要行情）；第二层要拿到 24h 成交额，
// 落在 `SymbolSections.build` 里。这样打半个词也能第一眼看到最热门的那个，
// 而不是撞上交易所原表里排在前面的冷门合约。

/// 一条命中：品种 + 名次档 + 高亮片段。
///
/// `highlight` 是**字符下标区间**，落在 `info.symbol` 上（永续合约恒有
/// `symbol == base + quote`，所以下标 < base.count 的部分即 base 段，
/// 其余是 quote 段，行视图据此分两段上色）。无查询时为 nil。
struct SymbolMatch: Sendable, Equatable, Identifiable {
  var info: SymbolInfo
  var tier: Tier
  var highlight: Range<Int>?

  var id: String { info.symbol }

  /// 名次档，小的排前。同档之间由调用方按 24h 成交额排（`SymbolSections.build`）。
  ///
  /// 中文/拼音那两档夹在「最匹配」和字面前缀之间，是用户 2026-09-20 定的顺序：
  /// 打「bitebi」的人要的就是比特币，它该排在任何一个恰好以 BITEBI… 开头的
  /// 冷门代号前面；只打首字母「btb」的说法更含糊，再退一档。
  enum Tier: Int, Sendable, Comparable, CaseIterable {
    case exact = 0             // 搜 ETH → ETHUSDT；搜 ETHUSDT → ETHUSDT；搜「比特币」→ BTCUSDT
    case pinyinFull = 1        // 搜 bitebi / 比特 → BTCUSDT
    case pinyinInitials = 2    // 搜 btb / tsl → BTCUSDT / TSLAUSDT
    case basePrefix = 3        // 搜 ET  → ETHUSDT
    case symbolPrefix = 4      // 搜 ETHU → ETHUSDT（base 不前缀，但 symbol 前缀）
    case baseContains = 5      // 搜 TH  → ETHUSDT
    case symbolContains = 6    // 搜 USD → 任何 USDT 对

    static func < (a: Tier, b: Tier) -> Bool { a.rawValue < b.rawValue }
  }

  init(info: SymbolInfo, tier: Tier = .exact, highlight: Range<Int>? = nil) {
    self.info = info
    self.tier = tier
    self.highlight = highlight
  }
}

enum SymbolQuery {
  /// 归一化用户输入：去分隔符、转大写。空串表示「不过滤」。
  ///
  /// 同一个合约人有五种写法：`ETH/USDT`（交易所网页的写法）、`ethusdt`、
  /// `eth usdt`、`$ETH`（推特的写法）、`ETH-USDT`（另一批交易所的写法）。
  /// 它们指的是同一个东西，所以在比之前**把分隔符全去掉**，五种写法落到
  /// 同一个 `ETHUSDT` 上（方案第 3 节「搜索流程打磨」第四条）。
  ///
  /// 去掉的只有分隔符，字母数字一个不动——「相似的名字不合并」：`ETHFI` 和
  /// `ETH` 仍然是两个词，靠名次档分先后，不靠模糊匹配凑到一起。
  static func normalize(_ raw: String) -> String {
    raw.uppercased().filter { !separators.contains($0) }
  }

  /// 写合约时人会顺手打的那些分隔符。中文没有这些字符，所以粘中文不受影响。
  private static let separators: Set<Character> = [
    " ", "\t", "\n", "\r", "/", "\\", "-", "_", "$", ".", "·", ":", ",", "\u{00A0}",
    // 全角的那几个：粘进来的文字常常带着中文输入法打出来的符号。
    "／", "－", "：", "，", "、", "　",
  ]

  /// 过滤 + 排名。`list` 的相对顺序在同档内保持不变。
  static func match(_ list: [SymbolInfo], query raw: String) -> [SymbolMatch] {
    let q = normalize(raw)
    guard !q.isEmpty else { return list.map { SymbolMatch(info: $0) } }

    var out: [(Int, SymbolMatch)] = []
    out.reserveCapacity(list.count)
    for (i, info) in list.enumerated() {
      guard let m = match(info, query: q) else { continue }
      out.append((i, m))
    }
    // 稳定排序：先比档，再比原序。同档内的成交额排序由 `SymbolSections.build`
    // 接着做——这一层看不到行情，也不该为了排序把行情灌进来。
    return out
      .sorted { a, b in a.1.tier == b.1.tier ? a.0 < b.0 : a.1.tier < b.1.tier }
      .map(\.1)
  }

  /// 单个品种的命中判定。`q` 必须已经归一化。
  static func match(_ info: SymbolInfo, query q: String) -> SymbolMatch? {
    guard !q.isEmpty else { return SymbolMatch(info: info) }
    let symbol = Array(info.id.symbol.uppercased())
    let base = Array(info.base.uppercased())
    let needle = Array(q)

    let inBase = firstIndex(of: needle, in: base)
    let inSymbol = firstIndex(of: needle, in: symbol)
    // 中文名 / 全拼 / 首字母那一侧（`SymbolAliases`）。字面没命中也可能是它命中。
    let alias = SymbolAliases.tier(base: info.base, query: q)
    // 原型的口径：symbol 含 或 base 含。base ⊂ symbol，所以 inSymbol 为空即落选。
    guard inBase != nil || inSymbol != nil else {
      guard let alias else { return nil }
      // 别名命中时高亮留空：命中的是「比特币」这三个字，不是 `BTCUSDT` 里的某一段，
      // 在代号上划一条高亮只会指错地方。
      return SymbolMatch(info: info, tier: alias, highlight: nil)
    }

    // 打全了就该排第一：搜 ETH 出 ETHUSDT，不能被 ETHFIUSDT 挤到后面去；
    // 搜 ETHUSDT 也一样（用户 2026-09-18 定的「首先选最匹配的」）。
    var tier: SymbolMatch.Tier
    if needle == base || needle == symbol { tier = .exact }
    else if inBase == 0 { tier = .basePrefix }
    else if inSymbol == 0 { tier = .symbolPrefix }
    else if inBase != nil { tier = .baseContains }
    else { tier = .symbolContains }
    // 两侧都命中就取靠前的那一档。
    if let alias, alias < tier { tier = alias }

    // 高亮永远落在 symbol 上：优先用 base 里的位置（和 symbol 下标一致），
    // 没有就用 symbol 里的位置。
    let at = inBase ?? inSymbol
    let highlight = at.map { $0 ..< ($0 + needle.count) }
    return SymbolMatch(info: info, tier: tier, highlight: highlight)
  }

  /// 把一段字按高亮区间切成「命中 / 未命中」若干段，行视图据此分段上色。
  /// `highlight` 的下标落在 `symbol`（= base + quote）上，`offset` 是本段的起点。
  static func split(_ s: String, highlight: Range<Int>?, offset: Int) -> [(text: String, hit: Bool)] {
    let chars = Array(s)
    guard let h = highlight else { return [(s, false)] }
    let lo = max(0, h.lowerBound - offset)
    let hi = min(chars.count, h.upperBound - offset)
    guard lo < hi else { return [(s, false)] }
    var out: [(String, Bool)] = []
    if lo > 0 { out.append((String(chars[0 ..< lo]), false)) }
    out.append((String(chars[lo ..< hi]), true))
    if hi < chars.count { out.append((String(chars[hi...]), false)) }
    return out
  }

  /// 朴素子串查找，返回首个匹配的起始下标。`needle` 非空。
  private static func firstIndex(of needle: [Character], in hay: [Character]) -> Int? {
    guard !needle.isEmpty, needle.count <= hay.count else { return nil }
    let last = hay.count - needle.count
    var i = 0
    while i <= last {
      var k = 0
      while k < needle.count, hay[i + k] == needle[k] { k += 1 }
      if k == needle.count { return i }
      i += 1
    }
    return nil
  }
}
