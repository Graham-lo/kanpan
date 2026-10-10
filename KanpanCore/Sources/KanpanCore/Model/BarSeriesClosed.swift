import Foundation

extension BarSeries {
  /// 前多少根已经收线。
  ///
  /// 只有末根可能还在走：它前面每一根都已经有下一根接着开了。末根的收盘时刻是它的开盘时间往后推一格
  /// （等距周期加 `stepMs`，月线 / 年线按日历月，同 `Interval.advancing`）；那一刻还没到 `nowMs`
  /// 就算它还在走，返回 `count - 1`，否则整段都已收线（停盘、推送断了一阵、复盘切片）。
  ///
  /// 公允价值缺口这类「只拿已收线的 K 线生成」的自动分析层都从这里取 `closedCount`；
  /// 网页两端是同一条规则：手机网页 `Web/src/m/chart/renderer.fvg.ts` 的 `closedBarCount`、
  /// 电脑网页 `Web/src/chart/fvgLayer.ts` 的 `closedCountOf`。
  public func closedCount(nowMs: Int64) -> Int {
    guard count > 0 else { return 0 }
    return interval.advancing(lastTime, by: 1) <= nowMs ? count : count - 1
  }
}
