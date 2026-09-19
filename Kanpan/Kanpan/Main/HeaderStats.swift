import Foundation
import KanpanCore

/// 顶栏右侧四格（仓 / 额 / 市值 / 费率）的**取值规则**。
///
/// 单独拆一份是因为这四格的规则全是「什么时候该显示 `--`」，而它们出错的样子
/// 用户一眼看不出来（一个上一条线路留下的成交额和一个真的成交额长得一模一样）。
/// 规则留在 SwiftUI 的 `body` 里没法用例守，所以这儿只做纯函数，`PriceRow`
/// 只负责把返回的字串画出来（`nil` → `--`，不解释、不弹提示）。
///
/// 三条共同的约定：
/// * 拿不到可靠数据就 `nil`（界面上是 `--`），绝不拿另一个口径或估算值顶上；
/// * 数值必须是有限数，成交额 / 市值 / 持仓还必须是正数——0 在这几格里只可能是缺数；
/// * 「不新鲜」和「没有」在界面上是同一种结果：都显示 `--`。
enum HeaderStats {
  /// 「仓」= **美元名义**持仓量（`openInterestValue`）。
  ///
  /// 审查 A-02：以前后端给不出名义时会退回币本位数量（`openInterest`）顶上，
  /// 于是同一格在不同品种上一会儿是「多少钱」一会儿是「多少个币」，还没有任何
  /// 标记能区分。名义拿不到就空着。
  static func openInterestText(value: Double?, unit: VolUnit?) -> String? {
    guard let v = value, v.isFinite, v > 0 else { return nil }
    return fmtVol(v, unit: unit ?? volUnit(v))
  }

  /// 「额」= 24h 成交额。价不新鲜时一起 `--`：成交额和价来自同一帧，
  /// 价已经被判定为旧的，那个额同样是旧的（审查 B.8）。
  static func turnoverText(quoteVolume: Double?, unit: VolUnit?, fresh: Bool) -> String? {
    guard fresh, let v = quoteVolume, v.isFinite, v > 0 else { return nil }
    return fmtVol(v, unit: unit ?? volUnit(v))
  }

  /// 「市值」= 总供应量 × 正在显示的那口价（用户点名要总市值，不是流通市值）。
  /// 供应量为空就空着，绝不用流通量或者「排名估算」顶上；价不新鲜时也 `--`——
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

  /// 费率帧的展示寿命。资金费率每小时结算一次，帧比一个结算周期还旧就等于没有。
  static let fundingMaxAge: TimeInterval = 3600

  /// 帧是不是已经过了展示寿命。`frameMs <= 0`（从没收到过帧）不算过期——
  /// 那时候本来就没有值可显示，另一条 `rate == nil` 的门会拦住它。
  static func expired(frameMs: Int64, now: Date, maxAge: TimeInterval) -> Bool {
    guard frameMs > 0 else { return false }
    return now.timeIntervalSince1970 - Double(frameMs) / 1000 > maxAge
  }
}
