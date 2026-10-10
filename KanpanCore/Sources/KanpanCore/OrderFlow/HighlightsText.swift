import Foundation

/// 一句里的一段：`strong` 的是要加粗的数字（原型里的 `<b>`）。
public struct HighlightRun: Sendable, Equatable {
  public var text: String
  public var strong: Bool
  public init(_ text: String, strong: Bool = false) { self.text = text; self.strong = strong }
}

public extension Array where Element == HighlightRun {
  /// 不分粗细的整句（无障碍朗读、测试比对用）。
  var plain: String { map(\.text).joined() }
}

/// 「盘口要点」与首页「异动」的全部拼字。纯函数、不碰界面，三端口径照原型 §11 / §12。
///
/// 价格全按「每一枚币」进来；行情页上的品种带缩放（1000PEPE）时由调用方先乘好再传。
public enum HighlightsText {
  typealias T = HighlightTerm

  static let minus = "\u{2212}"

  // MARK: 数

  /// 金额短写：`35M`、`19.6M`、`4.1K`、`1.2B`、`406M`；不到一千写整数。不满 100 带一位小数，`.0` 去掉。
  public static func usd(_ value: Double) -> String {
    let a = abs(value)
    guard a.isFinite else { return "—" }
    let units: [(scale: Double, suffix: String)] = [(1e12, "T"), (1e9, "B"), (1e6, "M"), (1e3, "K"), (1, "")]
    for (i, u) in units.enumerated() where a >= u.scale || i == units.count - 1 {
      let s = u.scale == 1 ? toFixed(a, 0) : short(a / u.scale)
      // 999.6K 印出来是「1000K」：进到上一档。
      if s == "1000", i > 0 { return "1" + units[i - 1].suffix }
      return s + u.suffix
    }
    return toFixed(a, 0)
  }

  private static func short(_ v: Double) -> String {
    if v < 99.95 {
      let s = toFixed(v, 1)
      return s.hasSuffix(".0") ? String(s.dropLast(2)) : s
    }
    return toFixed(v, 0)
  }

  /// 带符号的金额：`+46M`、`−8M`；四舍五入成 0 的写 `0`。
  public static func signedUSD(_ value: Double) -> String {
    let s = usd(value)
    if s == "0" { return s }
    return (value < 0 ? minus : "+") + s
  }

  /// 带符号百分数，负号用数学减号；四舍五入成 0 的不带符号。
  public static func signedPct(_ value: Double, decimals: Int) -> String {
    guard value.isFinite else { return "—" }
    let m = toFixed(abs(value), decimals)
    let zero = !m.contains { $0 != "0" && $0 != "." }
    return (zero ? "" : (value < 0 ? minus : "+")) + m + "%"
  }

  /// 流向表的价格 / 持仓两列：不到 1% 两位小数，其余一位（`+0.12%`、`+1.4%`）。
  public static func flowPct(_ value: Double?) -> String {
    guard let value, value.isFinite else { return "—" }
    return signedPct(value, decimals: abs(value) < 1 ? 2 : 1)
  }

  /// 距现价：只写大小（上方 / 下方由所在位置说）。不到 0.1% 两位，其余一位。
  public static func distance(_ pct: Double) -> String {
    let a = abs(pct)
    guard a.isFinite else { return "—" }
    return toFixed(a, a < 0.1 ? 2 : 1) + "%"
  }

  /// 资金费率（小数进来）：百分数最多四位、末尾 0 去到两位，正的不带「+」（和头部六格一个写法）。
  public static func funding(_ rate: Double) -> String {
    guard rate.isFinite else { return "—" }
    var s = toFixed(abs(rate * 100), 4)
    while s.hasSuffix("0"), let dot = s.firstIndex(of: "."), s.distance(from: dot, to: s.endIndex) > 3 { s.removeLast() }
    let zero = !s.contains { $0 != "0" && $0 != "." }
    return (rate < 0 && !zero ? minus : "") + s + "%"
  }

  /// 一口价：整数部分千分位。≥ 1 的最多留到 5 位有效数字（`82,940`、`3,812.4`、`114.92`），
  /// 不超过品种自己的小数位；不到 1 的照品种小数位（`fmtPrice` 会把舍成 0 的补出有效数字）。
  public static func price(_ value: Double, decimals: Int?) -> String {
    guard value.isFinite else { return "—" }
    let symbolDecimals = decimals ?? priceDecimalsFallback(value)
    let intDigits = abs(value) >= 1 ? Int(log10(abs(value))) + 1 : 0
    let d = intDigits > 0 ? min(symbolDecimals, max(0, 5 - intDigits)) : symbolDecimals
    return AlertMessage.groupedPrice(value, decimals: d)
  }

  /// 价带：两头写出来一样就只写一个。
  public static func band(low: Double, high: Double, decimals: Int?) -> String {
    let a = price(low, decimals: decimals), b = price(high, decimals: decimals)
    return a == b ? a : a + "–" + b
  }

  // MARK: 时间

  /// 当地时刻 `14:03`。
  public static func clock(_ ms: Int64, zone: TZOffset) -> String {
    let p = DateParts(ms: Double(ms), offsetMinutes: zone.minutes(at: Double(ms)))
    return String(format: "%02d:%02d", p.hour, p.minute)
  }

  /// 时段 `10:20–10:35`；`compact` 时同一小时里写成 `10:20–35`。
  public static func span(from: Int64, to: Int64, zone: TZOffset, compact: Bool = false) -> String {
    let a = clock(from, zone: zone), b = clock(to, zone: zone)
    if a == b { return a }
    if compact, a.prefix(3) == b.prefix(3) { return a + "–" + b.dropFirst(3) }
    return a + "–" + b
  }

  /// 多久以前：刚才 / N 分前 / N 小时前。
  public static func ago(_ ms: Int64, now: Int64) -> String {
    let minutes = max(0, (now - ms) / 60_000)
    if minutes < 1 { return T.justNow.text }
    if minutes < 60 { return T.minutesAgo.fill(["n": "\(minutes)"]) }
    return T.hoursAgo.fill(["n": "\(minutes / 60)"])
  }

  /// 持续多久：`48 分`、`16 时`、`3 天`（≥ 48 小时按天）。
  public static func duration(_ ms: Int64) -> String {
    let minutes = max(0, ms / 60_000)
    if minutes < 60 { return T.minutes.fill(["n": "\(max(1, minutes))"]) }
    let hours = minutes / 60
    if hours < 48 { return T.hours.fill(["n": "\(hours)"]) }
    return T.days.fill(["n": "\(hours / 24)"])
  }

  // MARK: 流向

  /// 窗口名：`15 分` / `1 时` / `4 时` / `24 时` / `区间 31 时`。
  public static func windowName(_ row: FlowRow, nowMs: Int64) -> String {
    switch row.w {
    case .m15: return T.w15m.text
    case .h1: return T.w1h.text
    case .h4: return T.w4h.text
    case .h24: return T.w24h.text
    case .range:
      let hours = row.sinceMs.map { max(1, (nowMs - $0) / 3_600_000) } ?? 0
      return T.wRange.fill(["h": "\(hours)"])
    }
  }

  /// 净主动一格：`+46M` / `−8M`；没盖住整窗的写「—」。
  public static func flowNet(_ row: FlowRow) -> String {
    guard let v = row.netUsd, v.isFinite else { return "—" }
    return signedUSD(v)
  }

  /// 第四行（区间 / 24 时）要加粗。
  public static func isLongRow(_ row: FlowRow) -> Bool { row.w == .range || row.w == .h24 }

  // MARK: 价位

  /// 墙的状态词：挂单中 / 撤单中 / 已破。
  public static func wallState(_ state: HighlightLevel.WallState?) -> String? {
    switch state {
    case .live: return T.wallLive.text
    case .reducing: return T.wallReducing.text
    case .broken: return T.wallBroken.text
    case nil: return nil
    }
  }

  /// 结构参照位的名字（`dayHigh` → 今日高点）；不认识的键不写。
  public static func refName(_ key: String) -> String? {
    switch key {
    case "dayHigh": return T.refDayHigh.text
    case "dayLow": return T.refDayLow.text
    case "prevDayHigh": return T.refPrevDayHigh.text
    case "prevDayLow": return T.refPrevDayLow.text
    case "vwap": return T.refVwap.text
    case "rangeHigh": return T.refRangeHigh.text
    case "rangeLow": return T.refRangeLow.text
    default: return nil
    }
  }

  /// 价位行左边第二行：`距 0.4%`，叠了结构位时再加 ` · = 今日低点`（只写第一个）。
  /// 价区包住现价时写「现价内」（`price` 按每枚币）。
  public static func levelDistance(_ level: HighlightLevel, price: Double? = nil) -> String {
    var s = level.straddles(price) ? T.atPrice.text : T.dist.fill(["v": distance(level.distPct)])
    if let ref = level.refs.lazy.compactMap(refName).first { s += " · = " + ref }
    return s
  }

  /// 价位行右边两行：`墙 35M · 挂 48 分` 或 `吃单 120M`；第二行 `爆仓 18M · 测 5 次` 或 `测 2 次`。
  public static func levelMeta(_ level: HighlightLevel) -> (top: [HighlightRun], bottom: String) {
    let top: [HighlightRun]
    if level.wallUsd > 0 {
      top = [HighlightRun(T.wall.text + " "), HighlightRun(usd(level.wallUsd), strong: true)]
        + (heldTail(level.wallHeldMs).map { [HighlightRun($0)] } ?? [])
    } else {
      top = [HighlightRun(T.fill.text + " "), HighlightRun(usd(level.fillUsd), strong: true)]
    }
    let bottom = [level.liqUsd > 0 ? T.liqMeta.fill(["v": usd(level.liqUsd)]) : nil, testsText(level.tests)]
      .compactMap { $0 }.joined(separator: " · ")
    return (top, bottom)
  }

  /// 「测 N 次」：0 次不写（给 `nil`）。
  static func testsText(_ n: Int) -> String? { n > 0 ? T.tests.fill(["n": "\(n)"]) : nil }

  /// 「 · 挂 48 分」：没挂过（0）不写。
  static func heldTail(_ ms: Int64) -> String? { ms > 0 ? " · " + T.heldFor.fill(["d": duration(ms)]) : nil }

  /// 价位展开后的证据行（`吃单` / `墙` / `触及` / `叠加`，没有的不出）。
  public static func evidence(_ level: HighlightLevel, zone: TZOffset) -> [(label: String, runs: [HighlightRun])] {
    var out: [(String, [HighlightRun])] = []
    if level.fillUsd > 0 {
      let buyStrong = level.fillBuyUsd >= level.fillSellUsd
      out.append((T.fill.text, [
        HighlightRun("买 "), HighlightRun(usd(level.fillBuyUsd), strong: buyStrong),
        HighlightRun(" · 卖 "), HighlightRun(usd(level.fillSellUsd), strong: !buyStrong),
      ]))
    }
    if level.wallUsd > 0 {
      var tail = heldTail(level.wallHeldMs) ?? ""
      if let w = wallState(level.wallState) { tail += " · " + w }
      out.append((T.wall.text, [HighlightRun(usd(level.wallUsd), strong: true), HighlightRun(tail)]))
    } else if level.wallState == .broken {
      out.append((T.wall.text, [HighlightRun(T.wallBroken.text)]))
    }
    let touches = level.touchMs.compactMap { $0 }
    if level.tests > 0 || !touches.isEmpty {
      var parts: [String] = []
      for t in touches { let c = clock(t, zone: zone); if parts.last != c { parts.append(c) } }
      parts.append(level.wallState == .broken ? T.wallBroken.text : T.unbroken.text)
      out.append((T.touch.text, [HighlightRun(parts.joined(separator: " · "))]))
    }
    let refs = level.refs.compactMap(refName)
    if !refs.isEmpty { out.append((T.overlap.text, [HighlightRun(refs.map { "= " + $0 }.joined(separator: " · "))])) }
    return out
  }

  /// 价区名：下方是买区、上方是卖区。
  public static func zoneName(_ side: HighlightSide) -> String { side == .bid ? T.buyZone.text : T.sellZone.text }

  /// 价位句的头：`下方 86,120`；价区包住现价时 `现价内 63.405–63.659`（`price` 按每枚币，画的数乘 `scale`）。
  static func levelHead(_ l: HighlightLevel, price p: Double?, decimals: Int?, scale: Double) -> [HighlightRun] {
    if l.straddles(p) {
      return [HighlightRun(T.atPrice.text + " "),
              HighlightRun(band(low: l.low * scale, high: l.high * scale, decimals: decimals), strong: true)]
    }
    return [HighlightRun((l.side == .bid ? T.below : T.above).text + " "),
            HighlightRun(price(l.low * scale, decimals: decimals), strong: true)]
  }

  /// 入口条那一句：`下方 86,120 买区 35M · 挂 48 分 · 测 2 次`（包住现价的写 `现价内 a–b 卖区 …`，且优先取它）；
  /// 没价位时写 `1 时净主动 +46M`；都没有给 `nil`。`price` 是每枚币的现价。
  public static func entrySentence(_ page: HighlightsPage, decimals: Int?, scale: Double = 1, price p: Double? = nil) -> [HighlightRun]? {
    if let l = page.nearestLevel(price: p) {
      var runs = levelHead(l, price: p, decimals: decimals, scale: scale) + [HighlightRun(" " + zoneName(l.side) + " ")]
      if l.wallUsd > 0 {
        runs.append(HighlightRun(usd(l.wallUsd)))
        if let held = heldTail(l.wallHeldMs) { runs.append(HighlightRun(held)) }
      } else {
        runs.append(HighlightRun(T.fillMeta.fill(["v": usd(l.fillUsd)])))
      }
      if let tests = testsText(l.tests) { runs.append(HighlightRun(" · " + tests)) }
      return runs
    }
    if let row = page.flow?.rows.first(where: { $0.w == .h1 }), let v = row.netUsd, v.isFinite {
      let parts = T.flowLine.text.components(separatedBy: "{v}")
      return [HighlightRun(parts.first ?? ""), HighlightRun(signedUSD(v), strong: true), HighlightRun(parts.dropFirst().joined())]
    }
    return nil
  }

  /// 区间行：`区间 85,400–87,450 · 已走 31 时` 的三段，与两沿那一句。
  public static func rangeLine(_ r: HighlightRange, nowMs: Int64, decimals: Int?, scale: Double = 1) -> (runs: [HighlightRun], edges: String) {
    let hours = max(1, (nowMs - r.sinceMs) / 3_600_000)
    let runs = [HighlightRun(T.range.text + " "),
                HighlightRun(band(low: r.low * scale, high: r.high * scale, decimals: decimals), strong: true),
                HighlightRun(" · " + T.rangeAge.fill(["h": "\(hours)"]))]
    // 两沿各自：累计吃单 + 测几次（0 次不写），和手机网页 rangeEdgesText 同口径。
    func edge(_ term: HighlightTerm, _ v: Double, _ n: Int) -> String {
      ([term.fill(["v": usd(v)])] + [testsText(n)].compactMap { $0 }).joined(separator: " · ")
    }
    let edges = edge(.rangeLowEdge, r.lowFillUsd, r.lowTests) + " ｜ " + edge(.rangeHighEdge, r.highFillUsd, r.highTests)
    return (runs, edges)
  }

  /// 现价在区间里的位置 0…1（出了区间夹到两头）。
  public static func rangePosition(_ r: HighlightRange, price: Double) -> Double {
    guard r.high > r.low, price.isFinite else { return 0.5 }
    return min(1, max(0, (price - r.low) / (r.high - r.low)))
  }

  // MARK: 三格

  public struct Tile: Sendable, Equatable {
    public var label: String
    public var value: String
    public var fact: String
    /// 0…100；没有分位时为 `nil`（轨道上不画点）。
    public var pctile: Int?
  }

  /// 持仓 · 费率 · 现货溢价三格；缺数的那格照样占位写「—」，三格不缺位。
  public static func tiles(_ p: HighlightPosition) -> [Tile] {
    let oi = Tile(label: T.oi1h.text,
                  value: p.oi?.pct1h.map { signedPct($0, decimals: 1) } ?? "—",
                  fact: p.oi?.combo.map(comboWord) ?? (p.oi?.pctile.map(pctileWord) ?? ""),
                  pctile: p.oi?.pctile)
    let fr = Tile(label: T.funding.text,
                  value: p.funding?.rate.map(funding) ?? "—",
                  fact: p.funding?.pctile.map(pctileWord) ?? "",
                  pctile: p.funding?.pctile)
    let sp = Tile(label: T.spotPremium.text,
                  value: p.spotPremium?.pct.map { signedPct($0, decimals: 2) } ?? "—",
                  fact: p.spotPremium?.pctile.map(pctileWord) ?? "",
                  pctile: p.spotPremium?.pctile)
    return [oi, fr, sp]
  }

  public static func comboWord(_ c: HighlightPosition.Combo) -> String {
    switch c {
    case .oiUpPxUp: return T.oiUpPxUp.text
    case .oiDownPxUp: return T.oiDownPxUp.text
    case .oiUpPxDown: return T.oiUpPxDown.text
    case .oiDownPxDown: return T.oiDownPxDown.text
    }
  }

  public static func pctileWord(_ p: Int) -> String { T.pctile.fill(["n": "\(min(100, max(0, p)))"]) }

  // MARK: 事件

  /// 事件的时刻列：单点 `12:33`，时段 `10:20–35`。
  public static func eventTime(_ e: HighlightEvent, zone: TZOffset, compact: Bool = true) -> String {
    if let a = e.fromMs, let b = e.toMs { return span(from: a, to: b, zone: zone, compact: compact) }
    if let a = e.atMs { return clock(a, zone: zone) }
    return ""
  }

  /// 事件那句事实。`withPrice` 为假时（首页）墙事件不写「@ 价」。
  public static func eventSentence(_ e: HighlightEvent, decimals: Int?, scale: Double = 1, withPrice: Bool = true) -> [HighlightRun] {
    var runs: [HighlightRun] = []
    func px(_ v: Double) -> String { price(v * scale, decimals: decimals) }
    switch e.t {
    case .wallEaten, .wallCancel:
      let w = e.side == "buy" ? T.buyWall.text : T.sellWall.text
      runs.append(HighlightRun((e.t == .wallEaten ? T.wallEaten : T.wallCancel).fill(["w": w]) + " "))
      runs.append(HighlightRun(usd(e.usd ?? 0), strong: true))
      if withPrice, let p = e.price { runs.append(HighlightRun(" @ " + px(p))) }
      if let d = e.distPct { runs.append(HighlightRun(" · " + T.distPrice.fill(["v": distance(d)]))) }
    case .flowBurst:
      let net = e.netUsd ?? 0
      runs.append(HighlightRun((net >= 0 ? T.takerBuy : T.takerSell).text + " "))
      runs.append(HighlightRun(signedUSD(net), strong: true))
      if let p = e.pxPct { runs.append(HighlightRun(" · " + T.pricePct.fill(["v": signedPct(p, decimals: 1)]))) }
    case .liqWave:
      runs.append(HighlightRun((e.side == "short" ? T.shortLiq : T.longLiq).text + " "))
      runs.append(HighlightRun(usd(e.usd ?? 0), strong: true))
      if let p = e.pxPct { runs.append(HighlightRun(" · " + T.pricePct.fill(["v": signedPct(p, decimals: 1)]))) }
    case .oiJump:
      runs.append(HighlightRun(T.oi5m.text + " "))
      runs.append(HighlightRun(signedPct(e.pct ?? 0, decimals: 1), strong: true))
    case .levelBroken:
      runs.append(HighlightRun(zoneName(e.side == "ask" ? .ask : .bid) + " "))
      if let lo = e.low, let hi = e.high {
        runs.append(HighlightRun(band(low: lo * scale, high: hi * scale, decimals: decimals), strong: true))
        runs.append(HighlightRun(" "))
      }
      runs.append(HighlightRun(T.broken.text))
    }
    return runs
  }

  // MARK: 首页

  /// 首页一行的事实句（价格按每枚币、小数位按价自己猜）。
  public static func homeFact(_ row: HighlightsBoard.Row, zone: TZOffset) -> [HighlightRun] {
    switch row.top {
    case .level(let l):
      let amount = l.wallUsd > 0 ? usd(l.wallUsd) : T.fillMeta.fill(["v": usd(l.fillUsd)])
      return levelHead(l, price: row.price, decimals: nil, scale: 1) + [HighlightRun(" " + zoneName(l.side) + " · " + amount)]
    case .event(let e):
      // 时间在行尾「刚才 / N 分前」里已经有了，这里只写事（和手机网页 boardFact 同口径）。
      return eventSentence(e, decimals: nil, withPrice: false)
    case .position(let p):
      if row.cat == .oi, let v = p.oi?.pct1h {
        var runs = [HighlightRun(T.oi1h.text + " "), HighlightRun(signedPct(v, decimals: 1), strong: true)]
        if let c = p.oi?.combo { runs.append(HighlightRun(" · " + comboWord(c))) }
        return runs
      }
      // 费率一类：费率与现货溢价里离 50 分位更远的那个。
      let fp = p.funding?.pctile.map { abs($0 - 50) } ?? -1
      let sp = p.spotPremium?.pctile.map { abs($0 - 50) } ?? -1
      if sp > fp, let v = p.spotPremium?.pct {
        var runs = [HighlightRun(T.spotPremium.text + " "), HighlightRun(signedPct(v, decimals: 2), strong: true)]
        if let q = p.spotPremium?.pctile { runs.append(HighlightRun(" · " + pctileWord(q))) }
        return runs
      }
      if let r = p.funding?.rate {
        var runs = [HighlightRun(T.funding.text + " "), HighlightRun(funding(r), strong: true)]
        if let q = p.funding?.pctile { runs.append(HighlightRun(" · " + pctileWord(q))) }
        return runs
      }
      if let v = p.oi?.pct1h {
        return [HighlightRun(T.oi1h.text + " "), HighlightRun(signedPct(v, decimals: 1), strong: true)]
      }
      return []
    }
  }

  /// 首页那一行点进行情页时要展开哪一条：价位 id 或事件 id。
  public static func focusID(_ row: HighlightsBoard.Row) -> String? {
    switch row.top {
    case .level(let l): return l.id
    case .event(let e): return e.id
    case .position: return nil
    }
  }
}
