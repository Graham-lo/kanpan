import Foundation
import KanpanCore

// ============================================================ 中文与拼音
//
// 搜品种时人不一定记得代号。他记得的是「比特币」「特斯拉」，打字时可能打
// 「bitebi」，也可能只打首字母「btb」「tsl」。这一层就是把这三种说法接到
// 代号上去（方案 `71bd340:docs/提醒与体验细节-实施方案-2026-09-20.md` 第 3 节第一件）。
//
// 三条原则：
//
// 1. **键盘不改**。搜索框照旧锁 ASCII（记忆 kanpan-symbol-search-keyboard），
//    中文只会从「粘贴」进来——所以中文那一路必须真的能走通，不能只做拼音。
// 2. **拼音是算出来的，不是抄的**。中文名一份（下面这张表 + 美股那份），
//    全拼与首字母由 `CFStringTransform` 在运行时从中文名生成，缓存一次。
//    手抄拼音必然会和中文名走样，也没人去对。
// 3. **名字只收有把握的**。别名进的是搜索命中集合，编错一个就把不相干的币
//    顶到前面去。拿不准的（NEAR、SEI、ARB 这种圈里本来就直接念英文的）
//    宁可不收——搜不到中文名顶多退回打代号，收错了是错的结果。
//
// 名次：全拼命中排在「最匹配」之后一档，首字母再后一档（`SymbolMatch.Tier`），
// 同档之间照旧按 24h 成交额降序（`SymbolSections.build`）。
//
// 美股的中文名不在这儿抄第二份：`KanpanCore` 的 `SectorCatalog.chineseName(base:)`
// 已经有一份（英伟达、特斯拉、台积电…），这里只把它读进索引。

enum SymbolAliases {
  /// 这个代号的中文名与常用叫法。没有就是空数组。
  static func names(base: String) -> [String] { index[key(base)]?.names ?? [] }

  /// 中文 / 拼音这一侧的命中档。`q` 必须是 `SymbolQuery.normalize` 过的。
  ///
  /// 返回 nil 表示这一侧没命中——调用方（`SymbolQuery.match`）再和字面那一侧
  /// 取较前的一档。
  static func tier(base: String, query q: String) -> SymbolMatch.Tier? {
    guard !q.isEmpty, let entry = index[key(base)] else { return nil }
    if q.contains(where: isHan) { return chineseTier(entry, q) }
    // 一个字母的拼音没有意义：「b」会把所有中文名以 b 开头的币一起顶上来，
    // 而那一档本来就该让字面前缀去排。两个字母起才认。
    guard q.count >= 2 else { return nil }
    if entry.pinyin.contains(where: { $0 == q || $0.hasPrefix(q) }) { return .pinyinFull }
    if entry.initials.contains(where: { $0 == q || $0.hasPrefix(q) }) { return .pinyinInitials }
    return nil
  }

  /// 从一段中文算出（全拼, 首字母），都是大写。没有汉字就返回 nil。
  ///
  /// `kCFStringTransformMandarinLatin` 给的是带声调的、按音节空开的拉丁串
  /// （「比特币」→「bǐ tè bì」），所以还要再过一遍 `StripDiacritics` 把声调去掉，
  /// 然后按空格切音节：连起来是全拼，各取首字母是缩写。
  ///
  /// 非汉字部分先摘掉再转：「SK 海力士」只算「海力士」。不摘的话拉丁字母会被
  /// 当成一个音节混进首字母里，「AMD」这种纯英文名还会算出一个 "A" 的首字母，
  /// 搜任何以 A 开头的词都要撞它一下。
  static func pinyin(_ text: String) -> (full: String, initials: String)? {
    let han = String(text.filter(isHan))
    guard !han.isEmpty else { return nil }
    let buffer = NSMutableString(string: han) as CFMutableString
    guard CFStringTransform(buffer, nil, kCFStringTransformMandarinLatin, false),
          CFStringTransform(buffer, nil, kCFStringTransformStripDiacritics, false)
    else { return nil }
    let syllables = (buffer as String)
      .split(whereSeparator: { $0 == " " || $0 == "'" })
      .map { $0.uppercased() }
      .filter { !$0.isEmpty }
    guard !syllables.isEmpty else { return nil }
    return (syllables.joined(), String(syllables.compactMap(\.first)))
  }

  // ---------------------------------------------------------------- 索引

  private struct Entry: Sendable {
    var names: [String] = []
    var pinyin: [String] = []
    var initials: [String] = []
  }

  /// 全表只算一次。`static let` 的惰性初始化本身是线程安全的，不用自己加锁。
  private static let index: [String: Entry] = build()

  private static func build() -> [String: Entry] {
    var table: [String: [String]] = cryptoNames
    // 美股那一份在 `SectorCatalog` 里，按板块成员反查，不在这儿抄第二份。
    for base in SectorCatalog.us.flatMap(\.members) {
      guard let name = SectorCatalog.chineseName(base: base) else { continue }
      table[base.uppercased(), default: []].append(name)
    }

    var out: [String: Entry] = [:]
    out.reserveCapacity(table.count)
    for (base, names) in table {
      var entry = Entry(names: names)
      for name in names {
        guard let p = pinyin(name) else { continue }
        if !entry.pinyin.contains(p.full) { entry.pinyin.append(p.full) }
        // 一个字的名字首字母只有一位，跟上面「一个字母不认」是同一个道理。
        if p.initials.count >= 2, !entry.initials.contains(p.initials) {
          entry.initials.append(p.initials)
        }
      }
      out[base] = entry
    }
    return out
  }

  /// 查表用的键。
  ///
  /// 币安把小面值的币按 1000 倍打包成合约（`1000PEPEUSDT` 的 base 就是 `1000PEPE`，
  /// 还有 `1MBABYDOGE` 这种百万倍的），倍数不是名字的一部分——人搜「佩佩」
  /// 要的就是那一个合约。所以查表前先把前面的倍数剥掉。
  private static func key(_ base: String) -> String {
    var s = Substring(base.uppercased())
    while let c = s.first, c.isNumber { s = s.dropFirst() }
    if s.first == "M", s.count >= 3 { s = s.dropFirst() }   // 1M / 1MB 那一族
    return s.isEmpty ? base.uppercased() : String(s)
  }

  private static func isHan(_ c: Character) -> Bool {
    guard let v = c.unicodeScalars.first?.value, c.unicodeScalars.count == 1 else { return false }
    return (0x4E00...0x9FFF).contains(v) || (0x3400...0x4DBF).contains(v)
  }

  /// 粘进来的是中文时。名字里可能混着拉丁（「SK 海力士」），所以比之前先大写。
  private static func chineseTier(_ entry: Entry, _ q: String) -> SymbolMatch.Tier? {
    var best: SymbolMatch.Tier?
    for name in entry.names {
      let n = name.uppercased()
      let tier: SymbolMatch.Tier?
      if n == q { tier = .exact }
      else if n.hasPrefix(q) { tier = .pinyinFull }
      else if n.contains(q) { tier = .pinyinInitials }
      else { tier = nil }
      if let tier, best.map({ tier < $0 }) ?? true { best = tier }
    }
    return best
  }

  // ---------------------------------------------------------------- 中文名表
  //
  // 按 24h 成交额排在前面的那六十来个币，中文名 + 圈里真在用的叫法。
  // 加一行之前先想清楚：这个名字有没有可能是**另一个币**的名字。

  private static let cryptoNames: [String: [String]] = [
    "BTC": ["比特币", "大饼"],
    "ETH": ["以太坊", "以太", "二饼"],
    "BNB": ["币安币", "币安"],
    "SOL": ["索拉纳"],
    "XRP": ["瑞波币", "瑞波"],
    "DOGE": ["狗狗币", "狗币"],
    "ADA": ["艾达币", "卡尔达诺"],
    "TRX": ["波场币", "波场"],
    "AVAX": ["雪崩币", "雪崩"],
    "LINK": ["预言机"],
    "DOT": ["波卡币", "波卡"],
    "POL": ["马蹄链", "马蹄"],
    "MATIC": ["马蹄链", "马蹄"],
    "LTC": ["莱特币", "莱特"],
    "BCH": ["比特现金"],
    "ETC": ["以太经典"],
    "XLM": ["恒星币", "恒星"],
    "SHIB": ["柴犬币", "屎币"],
    "UNI": ["独角兽"],
    "AAVE": ["阿威"],
    "ATOM": ["阿童木", "宇宙"],
    "FIL": ["文件币", "菲尔币"],
    "APT": ["阿普托斯"],
    "SUI": ["苏伊"],
    "TON": ["电报币"],
    "ICP": ["互联网计算机"],
    "HBAR": ["海博"],
    "VET": ["唯链"],
    "RUNE": ["雷神"],
    "ALGO": ["阿尔戈"],
    "SAND": ["沙盒"],
    "AXS": ["阿蟹"],
    "CRV": ["曲线"],
    "EOS": ["柚子币", "柚子"],
    "XMR": ["门罗币", "门罗"],
    "ZEC": ["大零币", "零币"],
    "DASH": ["达世币"],
    "NEO": ["小蚁币", "小蚁"],
    "QTUM": ["量子链"],
    "IOTA": ["埃欧塔"],
    "THETA": ["希塔"],
    "FTM": ["范特姆"],
    "S": ["索尼克"],
    "KAS": ["卡斯帕"],
    "TIA": ["天体"],
    "ORDI": ["铭文"],
    "PEPE": ["佩佩", "佩佩蛙", "青蛙"],
    "WIF": ["帽子狗", "狗帽"],
    "BONK": ["邦克"],
    "FLOKI": ["弗洛基"],
    "JUP": ["木星"],
    "CAKE": ["薄饼"],
    "APE": ["猿币", "无聊猿"],
    "WLD": ["世界币"],
    "TRUMP": ["特朗普币", "川普币"],
    "CFX": ["树图"],
    "ONT": ["本体"],
    "RENDER": ["渲染币"],
    "HMSTR": ["仓鼠"],
    "PENGU": ["企鹅"],
    // 贵金属这几个合约在币安那张表里是真有的，中文名也是人真会打的。
    "XAU": ["黄金"],
    "PAXG": ["黄金"],
    "XAUT": ["黄金"],
    "XAG": ["白银"],
    "XPT": ["铂金"],
    "XPD": ["钯金"],
  ]
}
