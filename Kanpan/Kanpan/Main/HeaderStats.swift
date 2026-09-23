import Foundation
import KanpanCore

/// 顶栏右侧六格（仓 / 额 · 市值 / 费率 · 结算 / 振幅）的**取值规则**。
///
/// 单独拆一份是因为这六格的规则全是「什么时候该显示 `—`」，而它们出错的样子
/// 用户一眼看不出来（一个上一条线路留下的成交额和一个真的成交额长得一模一样）。
/// 规则留在 SwiftUI 的 `body` 里没法用例守，所以这儿只做纯函数，`PriceRow`
/// 只负责把返回的字串画出来（`nil` → `—`，不解释、不弹提示）。
///
/// 三条共同的约定：
/// * 拿不到可靠数据就 `nil`（界面上是 `—`），绝不拿另一个口径或估算值顶上；
/// * 数值必须是有限数，成交额 / 市值 / 持仓还必须是正数——0 在这几格里只可能是缺数；
/// * 「不新鲜」和「没有」在界面上是同一种结果：都显示 `—`。
enum HeaderStats {
  static func priceChangeText(change: Double?, percent: Double?, decimals: Int) -> String {
    guard let change, change.isFinite, let percent, percent.isFinite else { return "—" }
    // 符号单独格式化；涨跌额与价格采用同一小数位。
    return (change >= 0 ? "+" : "−") + grouped(toFixed(abs(change), decimals))
      + "  " + (percent >= 0 ? "+" : "−") + toFixed(abs(percent), 2) + "%"
  }

  /// 带方向箭头的涨跌幅药丸（品种预览卡、分享截图）：方向已经由箭头和底色说了，
  /// 数字只写绝对值——「▼ 2.74%」，不是「▼ -2.74%」（2026-09-24 审查 6.4 / U9）。
  /// 和自选列表那一格同一个写法。
  static func arrowPercentText(_ percent: Double?) -> String {
    guard let percent, percent.isFinite else { return "—" }
    return toFixed(abs(percent), 2) + "%"
  }

  /// 「仓」= **美元名义**持仓量（`openInterestValue`）。
  ///
  /// 审查 A-02：以前后端给不出名义时会退回币本位数量（`openInterest`）顶上，
  /// 于是同一格在不同品种上一会儿是「多少钱」一会儿是「多少个币」，还没有任何
  /// 标记能区分。名义拿不到就空着。
  static func openInterestText(value: Double?, unit: VolUnit?) -> String? {
    guard let v = value, v.isFinite, v > 0 else { return nil }
    return fmtVol(v, unit: unit ?? volUnit(v))
  }

  /// 「额」= 24h 成交额。价不新鲜时一起 `—`：成交额和价来自同一帧，
  /// 价已经被判定为旧的，那个额同样是旧的（审查 B.8）。
  static func turnoverText(quoteVolume: Double?, unit: VolUnit?, fresh: Bool) -> String? {
    guard fresh, let v = quoteVolume, v.isFinite, v > 0 else { return nil }
    return fmtVol(v, unit: unit ?? volUnit(v))
  }

  /// 「市值」= 总供应量 × 正在显示的那口价（用户点名要总市值，不是流通市值）。
  /// 供应量为空就空着，绝不用流通量或者「排名估算」顶上；价不新鲜时也 `—`——
  /// 它是拿那口价乘出来的，价旧则市值旧。
  static func marketCapText(totalSupply: Double?, price: Double?, fresh: Bool) -> String? {
    guard fresh, let supply = totalSupply, supply.isFinite, supply > 0,
          let price, price.isFinite, price > 0 else { return nil }
    return fmtVol(supply * price)
  }

  /// 「费率」。除了价的新鲜度，它自己还有一条寿命：`markPrice` 那条流超过
  /// `fundingMaxAge` 没推新帧，屏上这个费率就不再代表现在（审查 B.8）。
  static func fundingText(rate: Double?, fresh: Bool) -> String? {
    guard fresh, let rate, rate.isFinite else { return nil }
    return fmtFundingRate(rate)
  }

  /// 距离下一次资金费率结算的中文倒计时，缺时刻返回 nil。
  /// 结算刚过且下一帧未到时沿用原有八小时滚动规则，不改变取数口径。
  static func fundingCountdownText(nextFundingTimeMs: Int64?, now: Date = Date()) -> String? {
    guard let target = nextFundingTimeMs, target > 0 else { return nil }
    var remaining = Double(target) / 1000 - now.timeIntervalSince1970
    // 已经过了结算时刻：往后滚到下一期。滚太多期说明这一帧早就不算数了，
    // 那由费率本身的展示寿命（`fundingMaxAge`）去判，这儿不再多说一句。
    while remaining <= 0 { remaining += fundingPeriod }
    guard remaining.isFinite, remaining < fundingPeriod * 4 else { return nil }
    if remaining < 60 { return "<1分" }
    let total = Int(remaining)
    let hours = total / 3600, minutes = (total % 3600) / 60
    return hours > 0 ? "\(hours)时\(minutes)分" : "\(minutes)分"
  }

  /// 一期资金费率多长。币安 USD-M 的标准档是 8 小时（少数品种 4 / 1 小时，
  /// 它们的下一次结算时刻同样由流里那一帧给，这个常量只用在「刚结算完、
  /// 下一帧还没到」的那几秒里）。
  static let fundingPeriod: TimeInterval = 8 * 3600

  /// 费率帧的展示寿命。资金费率每小时结算一次，帧比一个结算周期还旧就等于没有。
  static let fundingMaxAge: TimeInterval = 3600

  /// 「振幅」= 24h 最高与最低之间隔了多远，按最低价算：`(高 − 低) / 低`。
  ///
  /// 分母用最低价而不是开盘价：这一格回答的是「今天这根柱子有多长」，
  /// 从谷底看涨到顶要多少，和开在哪儿无关（`Ticker.amplitude24h` 那支是
  /// 以开盘价为分母的另一口径，给别处用，两边不混）。
  /// 高低价和价来自同一帧，价旧了这一格也一起 `—`。
  static func amplitudeText(high: Double?, low: Double?, fresh: Bool) -> String? {
    guard fresh, let high, let low, high.isFinite, low.isFinite,
          low > 0, high >= low else { return nil }
    return toFixed((high - low) / low * 100, 2) + "%"
  }

  /// 帧是不是已经过了展示寿命。`frameMs <= 0`（从没收到过帧）不算过期——
  /// 那时候本来就没有值可显示，另一条 `rate == nil` 的门会拦住它。
  static func expired(frameMs: Int64, now: Date, maxAge: TimeInterval) -> Bool {
    guard frameMs > 0 else { return false }
    return now.timeIntervalSince1970 - Double(frameMs) / 1000 > maxAge
  }
}

/// 给整数部分插千分位。用于头部的价格与涨跌额：
/// 价格轴、十字线读数那些是密排的数据，加了分隔反而更挤。
func grouped(_ text: String) -> String {
  let parts = text.split(separator: ".", maxSplits: 1, omittingEmptySubsequences: false)
  guard let head = parts.first else { return text }
  let neg = head.hasPrefix("-")
  let digits = Array(neg ? head.dropFirst() : head)
  guard digits.count > 3, digits.allSatisfy(\.isNumber) else { return text }
  var out: [Character] = []
  for (i, d) in digits.enumerated() {
    if i > 0, (digits.count - i) % 3 == 0 { out.append(",") }
    out.append(d)
  }
  let intPart = (neg ? "-" : "") + String(out)
  return parts.count > 1 ? intPart + "." + parts[1] : intPart
}
