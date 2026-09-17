import Foundation

/// `<symbol>@markPrice@1s` 那一帧里除标记价以外的东西。
///
/// 这条流本来就一秒一帧地在推，资金费率（`r`）、下次结算时间（`T`）、指数价（`i`）、
/// 预估结算价（`P`）都在同一帧里，以前解报文时被丢掉了。顶栏的 FR 那一格要的就是
/// `fundingRate`——把它们捎上，等于零新增请求。
///
/// 除 `timeMs` 外全是可选：镜像域名 / 回放文件里这些字段不一定齐，缺了就那一格显示 `--`。
public struct MarkPriceTick: Sendable, Equatable {
  /// 事件时间 `E`，毫秒。用来丢弃乱序的旧帧。
  public var timeMs: Int64
  /// 资金费率 `r`，已经是小数（`0.0001` = 0.01%）。
  public var fundingRate: Double?
  /// 下次结算时间 `T`，毫秒。
  public var nextFundingTimeMs: Int64?
  /// 指数价 `i`。
  public var indexPrice: Double?
  /// 预估结算价 `P`。
  public var estimatedSettlePrice: Double?

  public init(timeMs: Int64, fundingRate: Double? = nil, nextFundingTimeMs: Int64? = nil,
              indexPrice: Double? = nil, estimatedSettlePrice: Double? = nil) {
    self.timeMs = timeMs
    self.fundingRate = fundingRate
    self.nextFundingTimeMs = nextFundingTimeMs
    self.indexPrice = indexPrice
    self.estimatedSettlePrice = estimatedSettlePrice
  }
}

/// 资金费率文案：`0.0001` → `0.0100%`，正数带 `+`。非数给 `--`。
///
/// 四位小数是行业惯例（币安 / AICoin 都按 `0.0100%` 显示），少一位就看不出
/// 万分之一档的差别。
public func fmtFundingRate(_ r: Double?) -> String {
  guard let r, r.isFinite else { return "--" }
  let s = toFixed(r * 100, 4) + "%"
  return r > 0 ? "+" + s : s
}
