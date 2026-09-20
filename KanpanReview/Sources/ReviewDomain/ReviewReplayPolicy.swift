import Foundation

// ============================================================ 重温这件事的两条规矩
//
// 桥（`ReviewChartBridge`）住在 app 里，跑不进这个包的测试；而它身上最容易出错的
// 两件事恰恰是**纯算术**：这段行情该用几位小数（审查 B-04），推进一根之后视野该
// 落在哪（审查 B-05）。所以把这两条搬到这儿，桥只剩「取数、喂给图」这点接线。

/// 这段行情自己的价格小数位。
///
/// 回放的是**另一个品种**，精度不能跟着当前这张实时图走：一位小数的图上打开
/// 0.00001234 的记录，轴、十字线、画线标签会把它写成 `0.0`（审查 B-04）。
/// 品种目录在这个包里看不见，但行情本身就带着答案——交易所给的报价一律落在
/// `tickSize` 的整数倍上，所以「让每一口价都能原样写出来的最少位数」就是它。
public enum ReviewPricePrecision {
  /// 最多认到第几位。币安 USDⓈ-M 的 `pricePrecision` 不超过 8。
  public static let maxDecimals = 8

  /// 这批价格需要几位小数；全是整数时返回 `nil`（该由调用方按一口价兜底）。
  public static func decimals(of prices: [Double]) -> Int? {
    var need = 0
    for price in prices where price.isFinite && price != 0 {
      need = max(need, digits(price))
      if need >= maxDecimals { return maxDecimals }
    }
    return need > 0 ? need : nil
  }

  /// 小数位 → `tickSize`。
  public static func tickSize(decimals: Int) -> Double {
    pow(10, -Double(max(0, min(maxDecimals, decimals))))
  }

  private static func digits(_ price: Double) -> Int {
    let magnitude = abs(price)
    for d in 0...maxDecimals {
      let scaled = magnitude * pow(10, Double(d))
      // 浮点数还原出来的报价会差几个 ulp，容差按量级给，不能写死绝对值：
      // 76800.5 和 0.00001234 差着八个数量级。
      if abs(scaled - scaled.rounded()) <= max(1, scaled) * 1e-9 { return d }
    }
    return maxDecimals
  }
}

/// 重温时的视野（毫秒）。和 `KanpanCore.ViewWindow` 同一口径：存右缘 + 窗宽。
public struct ReviewReplayWindow: Sendable, Equatable {
  public var to: Double
  public var span: Double
  public init(to: Double, span: Double) { self.to = to; self.span = span }
}

/// 推进一根之后，视野该落在哪。
///
/// 原来每一拍都写死 `span = 80 根`、右缘贴着最新一根（审查 B-05）：人在回放里放大
/// 看细节，按一下「下一根」就被缩回 80 根——那颗按钮把人的手一次次拨开。
///
/// 现在 80 根只是**第一次进来**（和明确「跳到判断处」重新取数）时的兜底；之后：
/// * 根宽（`span`）一律保留，人捏成什么样就是什么样；
/// * 右缘只在**人还跟着播放头**时才跟着走——最新那根还在屏幕里就算跟着；
///   人已经拖去看历史了，就一动不动，让新根在视野外长出来。
public enum ReviewReplayViewport {
  /// 没有个人视野时的兜底窗宽（根）。
  public static let defaultBars: Double = 80
  /// 右边留白（根）。
  public static let rightPadBars: Double = 6

  public static func next(current: ReviewReplayWindow?, previousLastTime: Int64?,
                          lastTime: Int64, step: Int64, reset: Bool) -> ReviewReplayWindow {
    let fallback = ReviewReplayWindow(to: Double(lastTime + step * Int64(rightPadBars)),
                                      span: Double(step) * defaultBars)
    guard !reset, let current, current.span > 0, current.to.isFinite, current.span.isFinite else { return fallback }
    guard let previousLastTime else { return ReviewReplayWindow(to: fallback.to, span: current.span) }
    // 最新那根的开盘时刻还在视野里 = 人还跟着播放头。
    guard current.to >= Double(previousLastTime) else { return current }
    return ReviewReplayWindow(to: fallback.to, span: current.span)
  }
}
