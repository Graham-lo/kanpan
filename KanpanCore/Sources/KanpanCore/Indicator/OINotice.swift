import Foundation

/// 持仓量副图空着的时候，那一行小字说什么。
///
/// 从前这儿有一句「这个周期币安不提供持仓量历史（最细 5 分钟）」，它两头都不成立：
///
/// - **说的不是事实。** 持仓量的历史从 2020-09-01 起在归档站上是全的
///   （`OISource.archiveEpoch`，配套的网关 `/oi/v1/metrics/{symbol}/range` 按图表
///   周期聚合），1w / 1M / 1y 照样画得出来。源真正的边界只有一条：**粒度是五分钟**，
///   所以 1m / 3m 图上的持仓量是一条横着走五根的阶梯——那也是画得出来，不是没有。
/// - **触发它的也不是周期。** 老判据是「指标结果还没算出来」，而指标引擎给 `.oi`
///   永远返回一条（没数据就整列 NaN），于是这句话实际只可能在还没算完的那一瞬间闪出来，
///   却把锅扣在了交易所头上。
///
/// 所以这里只剩三种情形，一句也不多说：线路不报、还没到、这一段真的没有。
public enum OINotice: String, Sendable, Equatable, CaseIterable {
  /// 当前行情线路（OKX 兜底）根本不报持仓量，等多久都不会来。
  case routeMissing = "当前行情线路不提供持仓量"
  /// 请求还在路上。
  case loading = "持仓量加载中"
  /// 问到了，这一段就是没有：品种上市之前、归档站缺的那几天。
  case empty = "这一段没有持仓量数据"

  public var text: String { rawValue }

  /// 这一屏一个有限值都没有时该说哪一句。
  ///
  /// - Parameters:
  ///   - routeSupportsOI: 当前行情线路报不报持仓量（只有币安报）。
  ///   - loaded: 这个品种 + 周期的持仓量已经到手一份（哪怕这一屏正好落在它外面）。
  public static func forEmptyPane(routeSupportsOI: Bool, loaded: Bool) -> OINotice {
    guard routeSupportsOI else { return .routeMissing }
    return loaded ? .empty : .loading
  }
}
