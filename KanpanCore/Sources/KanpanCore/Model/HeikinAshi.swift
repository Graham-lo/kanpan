import Foundation

/// 平均 K 线（Heikin-Ashi）。
///
/// 标准公式，逐根递推：
/// ```
/// hc = (o + h + l + c) / 4
/// ho = (前一根 ho + 前一根 hc) / 2        // 第一根用 (o + c) / 2
/// hh = max(h, ho, hc)
/// hl = min(l, ho, hc)
/// ```
///
/// **只给蜡烛自己画成什么样用**。MA / EMA / BOLL / MACD / RSI 这些指标、最新价线、
/// 十字线读数、图例价格一律还是真实价格——平均 K 线是给眼睛看趋势的平滑，拿平滑后的
/// 价去算指标，同一根上图例报的 MA 会和别处（详情、报警、真实成交）全部对不上号，
/// 那是 bug 不是特性。
public enum HeikinAshi {
  /// 只算 `lo...hi` 这一段，前面多跑 `warmup` 根热身。
  ///
  /// `ho` 的递推名义上要从第 0 根起。但初值的影响每根**对折**一次（`ho_n` 里上一根的
  /// 权重恰好是 1/2），热身 200 根之后只剩 2^-200，早就掉到 double 的有效位以下了。
  /// 滚动时这是每帧都要做的事，把几千根从头算一遍是纯浪费，所以只热身不全量。
  ///
  /// - Parameter warmup: 热身根数。给一个 >= `lo` 的数就等价于从第 0 根全量算。
  /// - Returns: 四条列，长度都是 `hi - lo + 1`，下标 `k` 对应原序列的 `lo + k`。
  ///   空序列给四条空列。
  public static func slice(_ s: BarSeries, lo: Int, hi: Int, warmup: Int = 200)
    -> (open: [Double], high: [Double], low: [Double], close: [Double])
  {
    guard s.count > 0 else { return ([], [], [], []) }
    let a = max(0, min(lo, s.count - 1))
    let z = max(a, min(hi, s.count - 1))
    let start = max(0, a - max(0, warmup))
    let n = z - a + 1

    var open = [Double](), high = [Double](), low = [Double](), close = [Double]()
    open.reserveCapacity(n); high.reserveCapacity(n)
    low.reserveCapacity(n); close.reserveCapacity(n)

    // 热身段只推 prev，不落进结果里。
    var prevOpen = Double.nan, prevClose = Double.nan
    for i in start...z {
      let hc = (s.open[i] + s.high[i] + s.low[i] + s.close[i]) / 4
      let ho = prevOpen.isFinite ? (prevOpen + prevClose) / 2 : (s.open[i] + s.close[i]) / 2
      if i >= a {
        open.append(ho)
        high.append(max(s.high[i], max(ho, hc)))
        low.append(min(s.low[i], min(ho, hc)))
        close.append(hc)
      }
      prevOpen = ho
      prevClose = hc
    }
    return (open, high, low, close)
  }
}
