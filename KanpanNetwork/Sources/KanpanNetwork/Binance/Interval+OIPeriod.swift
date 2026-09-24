import KanpanCore

/// 持仓量历史接口认的 `period` 字符串（`/futures/data/openInterestHist` 等四个统计接口）。
///
/// 这是币安接口上的字段，不是「周期」本身的属性，所以不放在 KanpanCore 的 `Interval` 上
/// （审查 2026-09-24 §1.4）：周期只管步长与名字，某家交易所怎么叫它由那家的提供者说。
public extension Interval {
  /// 1m/3m 比 5m 还细，用 5m 对齐；> 1d 的没有原生档，返回 nil，
  /// 由调用方把 5m 源按桶取最后一条聚上去（§4.5）。
  var oiPeriod: String? {
    switch self {
    case .m1, .m3, .m5: "5m"
    case .m15: "15m"
    case .m30: "30m"
    case .h1: "1h"
    case .h2: "2h"
    case .h4: "4h"
    case .h6: "6h"
    case .h12: "12h"
    case .d1: "1d"
    case .w1, .mo1, .y1: nil
    }
  }
}
